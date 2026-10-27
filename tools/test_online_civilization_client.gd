extends SceneTree
## Two independent clients use ordinary paid age/build/train commands. No
## resource, actor, time or outcome injection. The intentional final surrender
## checks result agreement after both replicas have been exercised.

var session: Node
var civilization: int = 0
var opponent_civilization: int = 0
var elapsed: float = 0.0
var placed: bool = false
var age_sent: bool = false
var trained: bool = false
var verified: bool = false
var verified_at: float = 0.0
var enemy_verified: bool = false
var saw_combat: bool = false
var surrendered: bool = false
var checks: int = 0
var failures: Array[String] = []
var signature_type: int = 2
var production_type: int = 3

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	civilization = int(OS.get_environment("AOEM_TEST_CIVILIZATION"))
	opponent_civilization = int(OS.get_environment("AOEM_TEST_OPPONENT_CIVILIZATION"))
	var manager: Node = root.get_node("GameManager")
	manager.selected_civilization = civilization
	manager.selected_opponent_civilization = (civilization + 1) % 3
	signature_type = 3 if civilization == 2 else 2
	production_type = 4 if civilization == 2 else 3
	session = root.get_node("NetworkSession")
	session.snapshot_received.connect(_snapshot)
	session.match_ended.connect(_ended)
	session.status_changed.connect(_status)
	session.find_match()

func _process(delta: float) -> bool:
	elapsed += delta
	# The100-population opening pays the full320F/160G Feudal price. Allow
	# ordinary configured-worker gathering plus construction, travel and combat.
	if elapsed > 420.0:
		push_error("ONLINE_CIV_TIMEOUT civ=%d slot=%d age=%s placed=%s trained=%s verified=%s enemy=%s combat=%s" % [civilization, session.player_slot, age_sent, placed, trained, verified, enemy_verified, saw_combat])
		quit(1)
	return false

func _snapshot(data: Dictionary) -> void:
	if session.state != "playing" or elapsed < 2.0:
		return
	var manager: Node = root.get_node("GameManager")
	var map: Node = current_scene.get_node("GameMap")
	var slot: int = session.player_slot
	var workers: Array[int] = []
	var bank: Dictionary = data.bank
	var age: int = int(data.player.age)
	var age_cost: Dictionary = manager.get_age_up_cost(0, 2)
	var age_affordable: bool = true
	for resource: String in age_cost:
		age_affordable = age_affordable and int(bank.get(resource, 0)) >= int(age_cost[resource])
	if not age_sent and age == 1 and age_affordable:
		session.send_command("age")
		age_sent = true
	for actor: Dictionary in data.actors:
		if int(actor.owner) != slot:
			var opponent_type: int = 3 if opponent_civilization == 2 else 2
			if str(actor.kind) == "unit" and int(actor.type) == opponent_type:
				saw_combat = saw_combat or float(actor.hp) < float(actor.max_hp)
				if not enemy_verified:
					var enemy: Node = session.adapter.entities.get(int(actor.id))
					var enemy_stats: Dictionary = CivilizationData.get_unit_stats(UnitData.UNITS[opponent_type], opponent_type, opponent_civilization)
					_expect(is_instance_valid(enemy), "visible enemy has a replica")
					if is_instance_valid(enemy):
						_expect(enemy.player_owner == 1 and not enemy.can_process(), "enemy replica remains inert and maps to local opponent")
						_expect(float(actor.max_hp) == float(enemy_stats.hp) and enemy.max_hp == float(enemy_stats.hp), "enemy authority and replica HP agree")
						_expect(enemy.speed == float(enemy_stats.speed) and enemy.attack_range == MapData.range_tiles_to_world(float(enemy_stats.attack_range)), "enemy signature range and speed survive slot remapping")
						_expect(enemy.get_unit_type() == str(enemy_stats.name), "enemy signature name is truthful")
						var expected_icon: String = UnitData.get_unit_icon_path(opponent_type, 1)
						_expect(enemy.get("_sprite").texture.resource_path == expected_icon, "enemy signature uses its actual civilization artwork")
					enemy_verified = true
					print("ONLINE_CIV_ENEMY_VERIFIED civ=%d opponent=%d slot=%d time=%.2f signature=%s failures=%s" % [civilization, opponent_civilization, slot, data.time, enemy_stats.name, failures])
			continue
		if str(actor.kind) == "unit" and int(actor.type) == signature_type:
			saw_combat = saw_combat or float(actor.hp) < float(actor.max_hp)
		if str(actor.kind) == "unit" and int(actor.type) == 0:
			workers.append(int(actor.id))
		elif str(actor.kind) == "building" and int(actor.type) == production_type and int(actor.state) == 2 and not trained:
			var cost: Dictionary = UnitData.get_unit_cost(signature_type)
			if int(bank.food) >= int(cost.food) and int(bank.wood) >= int(cost.wood) and int(bank.gold) >= int(cost.gold):
				session.send_command("train", {"target": int(actor.id), "type": signature_type})
				trained = true
		elif str(actor.kind) == "unit" and int(actor.type) == signature_type and not verified:
			# A SceneTree --script fixture is compiled before autoload symbols.
			# Resolve the already-created actor dynamically instead of preloading
			# UnitBase and its GameManager dependency at script parse time.
			var replica: Node = session.adapter.entities.get(int(actor.id))
			var expected: Dictionary = CivilizationData.get_unit_stats(UnitData.UNITS[signature_type], signature_type, civilization)
			_expect(manager.get_player_civilization(0) == civilization and manager.get_player_civilization(1) == opponent_civilization, "both identities map into local owners")
			_expect(int(data.civilizations[slot]) == civilization and int(data.civilizations[1 - slot]) == opponent_civilization, "authoritative snapshot preserves both selected civilizations")
			_expect(int(data.player.civilization) == civilization, "authoritative player identity agrees")
			_expect(is_instance_valid(replica), "paid unit has a client replica")
			if is_instance_valid(replica):
				_expect(replica.player_owner == 0 and not replica.can_process(), "own replica stays inert and owner mapped")
				_expect(replica.max_hp == float(expected.hp) and float(actor.max_hp) == float(expected.hp), "authoritative and replica signature HP agree")
				_expect(replica.speed == float(expected.speed) and replica.attack_range == MapData.range_tiles_to_world(float(expected.attack_range)), "replica speed/range agree with civilization rules")
				_expect(replica.get_unit_type() == str(expected.name), "replica signature identity is truthful")
				_expect(replica.get("_sprite").texture.resource_path == KingdomArt.unit_path(civilization, signature_type), "replica signature artwork follows selected kingdom")
			for owned_actor: Dictionary in data.actors:
				if int(owned_actor.owner) == slot and str(owned_actor.kind) == "building":
					var expected_hp: float = float(BuildingData.BUILDINGS[int(owned_actor.type)].hp) * CivilizationData.get_building_hp_multiplier(civilization)
					_expect(float(owned_actor.max_hp) == expected_hp, "authoritative building HP includes real civilization weakness")
			_expect(int(data.stats.resources_gathered) > 0 and age >= 2, "ordinary delivered resources paid for age progression")
			verified = true
			verified_at = float(data.time)
			var center: Vector2 = map.sacred_site.global_position
			session.send_command("attack_move", {"ids": [int(actor.id)], "position": [center.x, center.y]})
			print("ONLINE_CIV_VERIFIED civ=%d opponent=%d slot=%d time=%.2f checks=%d signature=%s paid_age=true paid_building=true paid_unit=true failures=%s" % [civilization, opponent_civilization, slot, verified_at, checks, expected.name, failures])
	if age >= 2 and not placed and not workers.is_empty() and int(bank.wood) >= 120:
		var spawn: Vector2i = map.map_generator.spawn_positions[slot]
		for radius: int in range(4, 11):
			for dx: int in range(-radius, radius + 1):
				for dy: int in [-radius, radius]:
					var world: Vector2 = map.tile_to_world(spawn + Vector2i(dx, dy))
					if not placed and current_scene._building_placement.revalidate_confirmation(production_type, world, 0):
						session.send_command("place", {"type": production_type, "ids": [workers[0]], "position": [world.x, world.y]})
						placed = true
	if verified and enemy_verified and saw_combat and slot == 1 and float(data.time) >= maxf(120.0, verified_at + 30.0) and not surrendered:
		surrendered = true
		session.send_command("surrender")

func _ended(winner: int, reason: String) -> void:
	var manager: Node = root.get_node("GameManager")
	_expect(verified, "paid civilization checks completed before result")
	_expect(enemy_verified and saw_combat, "ordinary attack-move reveals enemy signature and real replicated damage")
	_expect(winner == 0 and reason == "Surrender", "both clients agree on deliberate result")
	session.leave_match()
	_expect(manager.selected_civilization == civilization and manager.selected_opponent_civilization == (civilization + 1) % 3, "online match preserves next solo preferences")
	print("ONLINE_CIV_RESULT civ=%d winner=%d reason=%s verified=%s enemy=%s combat=%s checks=%d failures=%s" % [civilization, winner, reason, verified, enemy_verified, saw_combat, checks, failures])
	call_deferred("_finish_fixture")

func _finish_fixture() -> void:
	# Results start an alert sound. Immediate process exit can leave the audio
	# mixer's WAV/playback references alive even after the scene is freed.
	# Stop and drain the fixture explicitly; this changes no match outcome.
	root.get_node("AudioManager").stop_all()
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	await create_timer(0.15, true, false, true).timeout
	quit(0 if failures.is_empty() else 1)

func _status(value: String, message: String) -> void:
	print("ONLINE_CIV_STATUS civ=%d state=%s message=%s" % [civilization, value, message])
	if value == "error":
		push_error("ONLINE_CIV_TRANSPORT_FAILURE " + message)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
