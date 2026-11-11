extends Node
## Loaded by tools/probe_online_match.gd once autoloads exist.
## Scripted online 1v1 client for tools/run_online_tests.py --probe-match.
## Two of these play a ~5.5 minute match against the real authority
## (tools/probe_online_authority.gd) using only the commands a player's taps
## send: gather, train, build House/Farm/Barracks, Loom, the timed age, town
## bell, hunting, reseeding a fallow Farm, an army that fights, and (with
## AOEM_PROBE_RECONNECT=1) a dropped connection that resumes mid-match.
##
## Every tenth snapshot it prints the replica's digest:
##   REPLICA {"tick", "time", "slot", ...}
## in the same shape as the authority's AUDIT lines, for the runner to compare.
const END_AT := 330.0
const RECONNECT_AT := 150.0
const FIGHT_AT := 185.0
const PUSH_AT := 245.0
const WALL_LIMIT := 560.0

var session: Node
var main: Node
var map: Node
var slot: int = -1
var elapsed: float = 0.0
var reconnect_client: bool = OS.get_environment("AOEM_PROBE_RECONNECT") == "1"
var checks: Dictionary = {}
var done: Dictionary = {}
var notes: Array[String] = []
var pending_places: Dictionary = {}  # building type -> {"at": game time, "attempt": n}
var farm_builder: int = 0
var farm_seen_total: Dictionary = {}  # farm id -> highest food seen
var hunted: Dictionary = {}  # wildlife id -> remaining when ordered
var reconnect_dropped_at: float = -1.0
var reconnect_resumed_at: float = -1.0
var statuses: Array[String] = []
var max_inside: int = 0
var bell_on_at: float = -1.0
var replica_lines: int = 0
var initial_villagers: int = -1
var resumed_train_baseline: int = -1
var finished: bool = false
var rejections: Dictionary = {}
var next_train: Dictionary = {}  # building id -> game time of the next top-up

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_node("/root/AudioManager").set_all_enabled(false)
	session = get_node("/root/NetworkSession")
	session.snapshot_received.connect(_snapshot)
	session.match_ended.connect(_ended)
	session.status_changed.connect(_status)
	session.command_rejected.connect(func(reason: String) -> void:
		rejections[reason] = int(rejections.get(reason, 0)) + 1
		if int(rejections[reason]) <= 3:
			print("PROBE_REJECTED slot=%d at=%.1f %s" % [slot, GameManager.game_time, reason]))
	for name: String in ["map", "villagers_trained", "house", "barracks", "farm_built", "farm_gathered", "loom", "age_research_seen", "age_2", "bell_garrison", "bell_release", "wildlife_hunted", "farm_fallow", "farm_reseeded", "army", "fight", "replica_digests", "result"]:
		checks[name] = false
	if reconnect_client:
		checks["reconnect"] = false
		checks["command_after_resume"] = false
	session.find_match()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > WALL_LIMIT and not finished:
		finished = true
		push_error("PROBE_TIMEOUT slot=%d state=%s checks=%s notes=%s" % [slot, session.state, checks, notes])
		get_tree().quit(1)

func _status(state: String, message: String) -> void:
	statuses.append(state)
	print("PROBE_STATUS slot=%d state=%s message=%s game_time=%.1f" % [slot, state, message, GameManager.game_time])
	if state == "reconnecting":
		reconnect_dropped_at = GameManager.game_time
	elif state == "playing" and reconnect_dropped_at >= 0.0 and reconnect_resumed_at < 0.0:
		reconnect_resumed_at = GameManager.game_time
		checks["reconnect"] = true
	elif state == "error" and not finished:
		finished = true
		push_error("PROBE_SESSION_ERROR slot=%d %s" % [slot, message])
		get_tree().quit(1)

# --- Replica helpers --------------------------------------------------------

func _own_units(type: int = -1) -> Array:
	var result: Array = []
	for node: Variant in session.adapter.entities.values():
		if is_instance_valid(node) and node is UnitBase and not node.is_queued_for_deletion() and node.player_owner == 0 and (type < 0 or node.unit_type == type):
			result.append(node)
	result.sort_custom(func(a: Node, b: Node) -> bool: return _id(a) < _id(b))
	return result

func _own_buildings(type: int = -1, active_only: bool = false) -> Array:
	var result: Array = []
	for node: Variant in session.adapter.entities.values():
		if is_instance_valid(node) and node is BuildingBase and not node.is_queued_for_deletion() and node.player_owner == 0 and (type < 0 or node.building_type == type):
			if not active_only or node.state == BuildingBase.State.ACTIVE:
				result.append(node)
	result.sort_custom(func(a: Node, b: Node) -> bool: return _id(a) < _id(b))
	return result

func _id(node: Variant) -> int:
	return session.entity_id(node)

func _ids(nodes: Array) -> Array:
	return nodes.map(func(node: Node) -> int: return _id(node))

func _send(operation: String, payload: Dictionary = {}) -> void:
	if not session.send_command(operation, payload):
		notes.append("%s not sent at %.1f (state %s)" % [operation, GameManager.game_time, session.state])

func _top_up(building: BuildingBase, unit_type: int, now: float) -> void:
	## At most one paid order every 3 s while fewer than two are queued: what a
	## player tapping Train does, within housing.
	var id: int = _id(building)
	var queue: ProductionQueue = building.get_production_queue()
	if queue == null or now < float(next_train.get(id, 0.0)) or queue.queue.size() >= 2:
		return
	var player: Dictionary = GameManager.players[0]
	if int(player.population) + int(player.get("population_reserved", 0)) >= int(player.population_cap):
		return
	next_train[id] = now + 3.0
	_send("train", {"target": id, "type": unit_type})

func _place(type: int, builders: Array, near: Vector2i, now: float, want: int = 1) -> void:
	## Requests until `want` of this type stand; retried at another spot if the
	## authority did not create it within 8 s (the replica can lag a foundation).
	if _own_buildings(type).size() >= want:
		pending_places.erase(type)
		return
	if _own_buildings(type).size() > int(pending_places.get(type, {}).get("count", 0)):
		pending_places.erase(type)
	var pending: Dictionary = pending_places.get(type, {})
	if not pending.is_empty() and now - float(pending.at) < 8.0:
		return
	var attempt: int = int(pending.get("attempt", -1)) + 1
	var skip: int = attempt * 3
	for radius: int in range(4, 14):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var position: Vector2 = map.tile_to_world(near + Vector2i(dx, dy))
				if main._building_placement.revalidate_confirmation(type, position, 0):
					if skip > 0:
						skip -= 1
						continue
					_send("place", {"type": type, "ids": _ids(builders), "position": [position.x, position.y]})
					pending_places[type] = {"at": now, "attempt": attempt, "count": _own_buildings(type).size()}
					return
	notes.append("no site for building %d" % type)
	pending_places[type] = {"at": now, "attempt": attempt, "count": _own_buildings(type).size()}

# --- Digest -----------------------------------------------------------------

func _server_owner(local_owner: int) -> int:
	if local_owner < 0:
		return local_owner
	return slot if local_owner == 0 else 1 - slot

func replica_digest() -> Dictionary:
	var player: Dictionary = GameManager.players[0]
	var research: Array = []
	var farms: Array = []
	var garrison: Array = []
	for building: BuildingBase in _own_buildings():
		var id: int = _id(building)
		if not building.research_id.is_empty():
			research.append([id, building.research_id, snappedf(building.research_progress, 0.01)])
		if building.building_type == BuildingData.BuildingType.FARM and building.state == BuildingBase.State.ACTIVE:
			farms.append([id, 1 if building.farm_fallow else 0, int(building.farm_food_remaining)])
		if building.state == BuildingBase.State.ACTIVE:
			var inside: int = int(building.get_meta("network_garrison", 0))
			if inside > 0 or building.bell_active:
				garrison.append([id, inside, 1 if building.bell_active else 0])
	research.sort()
	farms.sort()
	garrison.sort()
	var wildlife: Array = []
	var director: WildlifeDirector = WildlifeDirector.of(map)
	if director != null:
		for node: Variant in director.by_id.values():
			if is_instance_valid(node) and not node.is_queued_for_deletion() and node.remaining > 0:
				wildlife.append([node.wildlife_id, node.remaining, _server_owner(node.owner_id)])
	wildlife.sort()
	var site: Node = map.sacred_site
	var researched: Array = (GameManager.researched_upgrades.get(0, []) as Array).duplicate()
	researched.sort()
	return {
		"time": snappedf(GameManager.game_time, 0.01), "slot": slot,
		"bank": [ResourceManager.get_resource(0, "food"), ResourceManager.get_resource(0, "wood"), ResourceManager.get_resource(0, "gold")],
		"pop": [int(player.population), int(player.population_cap), int(player.age)],
		"units": _own_units().size(), "buildings": _own_buildings().size(), "research": research, "researched": researched,
		"farms": farms, "garrison": garrison, "wildlife": wildlife,
		"sacred": [int(site.state), _server_owner(int(site.owning_player)), snappedf(site.victory_timer, 0.01), snappedf(site.victory_hold_time, 0.01), site.clock_ticking],
	}

# --- Script -----------------------------------------------------------------

func _snapshot(data: Dictionary) -> void:
	if session.state != "playing" or not is_instance_valid(session.adapter) or finished:
		return
	if main == null:
		main = session.adapter.main
		map = main.game_map
		slot = int(session.player_slot)
		var expected := MapGenerator.new(session.match_seed, session.match_map_archetype)
		checks["map"] = map.map_archetype == session.match_map_archetype and map.map_generator.grid == expected.generate()
		print("PROBE_START slot=%d seed=%d archetype=%d reconnect_client=%s" % [slot, session.match_seed, session.match_map_archetype, reconnect_client])
	var tick: int = int(data.get("tick", -1))
	if tick % 10 == 0:
		var digest: Dictionary = replica_digest()
		digest["tick"] = tick
		digest["match"] = int(session.match_id)
		print("REPLICA " + JSON.stringify(digest))
		replica_lines += 1
		checks["replica_digests"] = replica_lines >= 20
	_drive(float(data.get("time", 0.0)), data)

func _drive(now: float, data: Dictionary) -> void:
	var tc: BuildingBase = main._player_town_center
	if not is_instance_valid(tc):
		return
	var home: Vector2i = map.world_to_tile(tc.global_position)
	var villagers: Array = _own_units(UnitData.UnitType.VILLAGER)
	if initial_villagers < 0:
		initial_villagers = villagers.size()
	checks["villagers_trained"] = checks["villagers_trained"] or villagers.size() > initial_villagers
	# Economy: keep two paid Villagers queued (housing allowing) up to twelve.
	if now >= 1.0 and villagers.size() < 12:
		_top_up(tc, UnitData.UnitType.VILLAGER, now)
	if villagers.size() < 5:
		return
	# Buildings, each with its own builder(s).
	if now >= 3.0:
		# The opening cap is 8; two Houses (+10 each) house the whole script.
		var houses: int = _own_buildings(BuildingData.BuildingType.HOUSE, true).size()
		checks["house"] = houses > 0
		if houses < 2:
			_place(BuildingData.BuildingType.HOUSE, [villagers[0]], home, now, 1 if houses == 0 else 2)
	if now >= 5.0 and not checks["barracks"]:
		_place(BuildingData.BuildingType.BARRACKS, [villagers[1], villagers[2]], home + Vector2i(2, 2), now)
		checks["barracks"] = not _own_buildings(BuildingData.BuildingType.BARRACKS, true).is_empty()
	if now >= 8.0 and _own_buildings(BuildingData.BuildingType.FARM).is_empty():
		farm_builder = _id(villagers[3])
		_place(BuildingData.BuildingType.FARM, [villagers[3]], home + Vector2i(-2, 3), now)
	var farms: Array = _own_buildings(BuildingData.BuildingType.FARM, true)
	checks["farm_built"] = checks["farm_built"] or not farms.is_empty()
	for farm: BuildingBase in farms:
		var id: int = _id(farm)
		var last: int = int(farm_seen_total.get(id, -1))
		if last >= 0 and farm.farm_food_remaining < last:
			checks["farm_gathered"] = true
		if last >= 0 and farm.farm_food_remaining > last and not farm.farm_fallow and done.has("reseed_sent"):
			checks["farm_reseeded"] = true
		farm_seen_total[id] = farm.farm_food_remaining
		if farm.farm_fallow:
			checks["farm_fallow"] = true
			if not done.has("reseed_sent"):
				done["reseed_sent"] = now
				print("PROBE_FALLOW slot=%d farm=%d at=%.1f" % [slot, id, now])
				_send("building_action", {"target": id, "action": FarmPlots.ACTION_RESEED})
			elif now - float(done["reseed_sent"]) > 10.0 and not done.has("reseed_retry"):
				done["reseed_retry"] = true
				_send("gather", {"ids": [farm_builder], "target": id, "position": [farm.global_position.x, farm.global_position.y]})
		if not done.has("farm_gather") and farm_builder > 0:
			done["farm_gather"] = true
			_send("gather", {"ids": [farm_builder], "target": id, "position": [farm.global_position.x, farm.global_position.y]})
	# Loom, then the timed age at the same Town Center.
	if now >= 8.0 and not done.has("loom"):
		done["loom"] = true
		_send("research", {"target": _id(tc), "research": "loom"})
	checks["loom"] = "loom" in GameManager.researched_upgrades.get(0, [])
	if tc.research_id == TechData.age_research_id(2):
		checks["age_research_seen"] = true
	if checks["loom"] and checks["barracks"] and not done.has("age") and tc.research_id.is_empty():
		done["age"] = now
		_send("age")
	elif done.has("age") and not checks["age_research_seen"] and now - float(done["age"]) > 6.0 and not done.has("age_retry"):
		done["age_retry"] = true
		_send("age")
	checks["age_2"] = GameManager.get_player_age(0) >= 2
	# Hunt the nearest visible animal with the fifth villager.
	var director: WildlifeDirector = WildlifeDirector.of(map)
	if now >= 15.0 and not done.has("hunt") and director != null:
		var best: Node2D = null
		for node: Variant in director.by_id.values():
			if is_instance_valid(node) and node.remaining > 0 and node.kind != WildlifeData.BOAR and (best == null or node.global_position.distance_to(tc.global_position) < best.global_position.distance_to(tc.global_position)):
				best = node
		if best != null:
			done["hunt"] = now
			hunted[best.wildlife_id] = best.remaining
			print("PROBE_HUNT slot=%d wid=%d kind=%s remaining=%d" % [slot, best.wildlife_id, best.kind, best.remaining])
			_send("hunt", {"wid": best.wildlife_id, "ids": [_id(villagers[4])], "position": [best.global_position.x, best.global_position.y]})
	if director != null:
		for wid: int in hunted:
			var node: Variant = director.by_id.get(wid)
			if (is_instance_valid(node) and node.remaining < int(hunted[wid])) or (not is_instance_valid(node) and done.has("hunt") and now - float(done["hunt"]) > 20.0):
				checks["wildlife_hunted"] = true
	# Town bell at the Town Center: everyone in, then all clear.
	var inside: int = int(tc.get_meta("network_garrison", 0))
	max_inside = maxi(max_inside, inside)
	if now >= 100.0 and not done.has("bell_on"):
		done["bell_on"] = true
		bell_on_at = now
		_send("bell", {"target": _id(tc)})
	if max_inside > 0:
		checks["bell_garrison"] = true
	if done.has("bell_on") and not done.has("bell_off") and (max_inside > 0 and now - bell_on_at > 12.0 or now - bell_on_at > 25.0):
		done["bell_off"] = now
		_send("bell", {"target": _id(tc)})
	if done.has("bell_off") and checks["bell_garrison"] and inside == 0 and not tc.bell_active:
		checks["bell_release"] = true
	# Army: Infantry from the Barracks, then into the middle and on to their base.
	var barracks: Array = _own_buildings(BuildingData.BuildingType.BARRACKS, true)
	if not barracks.is_empty() and _own_units(UnitData.UnitType.INFANTRY).size() < 8 and now < PUSH_AT:
		_top_up(barracks[0], UnitData.UnitType.INFANTRY, now)
	var soldiers: Array = _own_units().filter(func(unit: UnitBase) -> bool: return unit.unit_type != UnitData.UnitType.VILLAGER and unit.unit_type != UnitData.UnitType.TRADER)
	checks["army"] = checks["army"] or _own_units(UnitData.UnitType.INFANTRY).size() >= 3
	if now >= FIGHT_AT and not done.has("march") and not soldiers.is_empty():
		done["march"] = true
		var centre: Vector2 = map.sacred_site.global_position
		_send("attack_move", {"ids": _ids(soldiers), "position": [centre.x, centre.y]})
	if now >= PUSH_AT and not done.has("push") and not soldiers.is_empty():
		done["push"] = true
		var enemy_home: Vector2 = map.tile_to_world(map.map_generator.spawn_positions[1 - slot])
		_send("attack_move", {"ids": _ids(soldiers), "position": [enemy_home.x, enemy_home.y]})
	var stats: Dictionary = data.get("stats", {})
	checks["fight"] = checks["fight"] or int(stats.get("units_killed", 0)) > 0 or int(stats.get("units_lost", 0)) > 0
	# A dropped connection mid-match, without Leave.
	if reconnect_client and now >= RECONNECT_AT and not done.has("drop"):
		done["drop"] = true
		print("PROBE_DROP slot=%d at=%.1f" % [slot, now])
		session.simulate_connection_loss()
		return
	if reconnect_client and checks["reconnect"] and not done.has("after_resume"):
		done["after_resume"] = true
		resumed_train_baseline = int(stats.get("units_trained", 0))
		_send("train", {"target": _id(tc), "type": UnitData.UnitType.VILLAGER})
	if resumed_train_baseline >= 0 and int(stats.get("units_trained", 0)) > resumed_train_baseline:
		checks["command_after_resume"] = true
	if slot == 1 and now >= END_AT and not done.has("surrender"):
		done["surrender"] = true
		_send("surrender")

func _ended(winner: int, reason: String) -> void:
	finished = true
	checks["result"] = winner == 0 and reason == "Surrender"
	var failed: Array = []
	for name: String in checks:
		if not checks[name]:
			failed.append(name)
	print("PROBE_RESULT slot=%d winner=%d reason=%s game_time=%.1f reconnect=[%.1f, %.1f] statuses=%s" % [slot, winner, reason, GameManager.game_time, reconnect_dropped_at, reconnect_resumed_at, statuses])
	print("PROBE_CHECKS slot=%d %s" % [slot, JSON.stringify(checks)])
	if not notes.is_empty():
		print("PROBE_NOTES slot=%d %s" % [slot, notes])
	print("PROBE_REJECTIONS slot=%d %s" % [slot, JSON.stringify(rejections)])
	session.leave_match()
	if not failed.is_empty():
		push_error("PROBE_FAILED slot=%d %s" % [slot, failed])
	get_tree().quit(0 if failed.is_empty() else 1)
