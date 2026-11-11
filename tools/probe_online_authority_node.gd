extends Node
## Loaded by tools/probe_online_authority.gd (match-server wrapper for
## tools/run_online_tests.py --probe-match) once autoloads exist.
## Runs the real authoritative server (pass `-- --aoem-server`) and, once a
## second, prints what the authority itself holds for each seat, taken right
## after that snapshot round was built:
##   AUDIT {"tick", "time", "slot", ...}
## The paired clients (tools/probe_online_match.gd) print the same digest from
## their replicas for the same tick; the runner compares the two.
##
## Two fixture nudges keep a ~6 minute scripted match covering every system.
## They touch only authority state, so replication of their effects is still
## what is being tested:
##   * each seat gets PROBE_BANK extra of every resource once, so a timed age,
##     a technology, a Barracks and an army all fit in the script;
##   * each seat's first sown Farm is cut to PROBE_FARM_FOOD food, so it runs
##     fallow (and is reseeded) inside the match.
const PROBE_BANK := 1500
const PROBE_FARM_FOOD := 30
const AUDIT_EVERY_TICKS := 10

var session: Node
var _granted: Dictionary = {}
var _shrunk_farms: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	session = get_node("/root/NetworkSession")
	session.snapshots_broadcast.connect(_on_snapshots)

func _on_snapshots(tick: int) -> void:
	var adapter: Node = session.adapter
	if not is_instance_valid(adapter) or not is_instance_valid(adapter.main):
		return
	var main: Node = adapter.main
	var match_id: int = int(session.match_id)
	for slot: int in 2:
		var key: String = "%d:%d" % [match_id, slot]
		if not _granted.has(key):
			_granted[key] = true
			for resource: String in ["food", "wood", "gold"]:
				ResourceManager.add_resource(slot, resource, PROBE_BANK)
			print("PROBE_AUTHORITY_GRANT match=%d slot=%d bank=%d" % [match_id, slot, PROBE_BANK])
		if not _shrunk_farms.has(key):
			for building: Variant in main._player_buildings[slot]:
				if is_instance_valid(building) and building.building_type == BuildingData.BuildingType.FARM and building.state == BuildingBase.State.ACTIVE \
						and not building.farm_fallow and int(building.farm_food_total) > 0 and int(building.farm_food_remaining) > PROBE_FARM_FOOD:
					building.farm_food_remaining = PROBE_FARM_FOOD
					_shrunk_farms[key] = NetworkSession.entity_id(building)
					print("PROBE_AUTHORITY_FARM match=%d slot=%d farm=%d food=%d" % [match_id, slot, _shrunk_farms[key], PROBE_FARM_FOOD])
					break
	if tick % AUDIT_EVERY_TICKS != 0:
		return
	for slot: int in 2:
		var digest: Dictionary = authority_digest(main, slot)
		digest["tick"] = tick
		digest["match"] = match_id
		print("AUDIT " + JSON.stringify(digest))

static func authority_digest(main: Node, slot: int) -> Dictionary:
	var map: Node = main.game_map
	var player: Dictionary = GameManager.players[slot]
	var units: int = 0
	for unit: Variant in main._player_units[slot]:
		if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit.current_state != UnitBase.State.DEAD:
			units += 1
	var buildings: int = 0
	var research: Array = []
	var farms: Array = []
	var garrison: Array = []
	for building: Variant in main._player_buildings[slot]:
		if not is_instance_valid(building) or building.is_queued_for_deletion() or building.state == BuildingBase.State.DESTROYED:
			continue
		buildings += 1
		var id: int = NetworkSession.entity_id(building)
		if not building.research_id.is_empty():
			research.append([id, building.research_id, snappedf(building.research_progress, 0.01)])
		if building.building_type == BuildingData.BuildingType.FARM and building.state == BuildingBase.State.ACTIVE:
			farms.append([id, 1 if building.farm_fallow else 0, int(building.farm_food_remaining)])
		if building.state == BuildingBase.State.ACTIVE:
			var inside: int = Garrison.garrisoned_units(building).size()
			if inside > 0 or building.bell_active:
				garrison.append([id, inside, 1 if building.bell_active else 0])
	research.sort()
	farms.sort()
	garrison.sort()
	var wildlife: Array = []
	var director: WildlifeDirector = WildlifeDirector.of(map)
	if director != null:
		for node: WildlifeNode in director.nodes:
			if is_instance_valid(node) and node.remaining > 0 and map.is_entity_visible_to_player(node, slot):
				wildlife.append([node.wildlife_id, node.remaining, node.owner_id])
	wildlife.sort()
	var site: Node = map.sacred_site
	var researched: Array = (GameManager.researched_upgrades.get(slot, []) as Array).duplicate()
	researched.sort()
	return {
		"time": snappedf(GameManager.game_time, 0.01), "slot": slot,
		"bank": [ResourceManager.get_resource(slot, "food"), ResourceManager.get_resource(slot, "wood"), ResourceManager.get_resource(slot, "gold")],
		"pop": [int(player.population), int(player.population_cap), int(player.age)],
		"units": units, "buildings": buildings, "research": research, "researched": researched,
		"farms": farms, "garrison": garrison, "wildlife": wildlife,
		"sacred": [int(site.state), int(site.owning_player), snappedf(site.victory_timer, 0.01), snappedf(site.victory_hold_time, 0.01), site.clock_ticking],
	}
