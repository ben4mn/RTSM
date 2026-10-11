extends SceneTree
## Paid siege must use its weapon reach with live allied vision.
## Funded/relocated fixture; real buildings, worker labor, queues and fog.

var _failures: Array[String] = []
var _main: Node
var _map: Node2D
var _gm: Node
var _rm: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_gm = root.get_node("GameManager")
	_rm = root.get_node("ResourceManager")
	root.get_node("AudioManager").call("set_all_enabled", false)
	_gm.set("guided_opening_enabled", false)
	_gm.set("selected_map_seed", 42)
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	var initialized := false
	for _frame in range(900):
		await process_frame
		var units: Array = _main.get("_player_units")
		if units.size() == 2 and units[1].size() >= 4:
			initialized = true
			break
	_expect(initialized, "real match initializes")
	if not initialized:
		_finish()
		return
	_main.set_process(false)
	var ai: Node = _main.get("ai_controller")
	(ai.get("_decision_timer") as Timer).stop()
	ai.set_process(false)
	_map = _main.get("game_map") as Node2D
	var fog: Node = _map.get("fog_of_war")
	fog.set_process(false)
	for unit: Node in get_nodes_in_group("units"):
		unit.set_process(false)
		unit.call("command_stop")
	for building: Node in get_nodes_in_group("buildings"):
		building.set_process(false)
	for player_id: int in [0, 1]:
		_rm.call("initialize_player", player_id, {"food": 10000, "wood": 10000, "gold": 10000})
	_expect(_gm.call("try_advance_age", 0) and _gm.call("try_advance_age", 0), "paid Castle unlock is real")
	var buildings: Array = _main.get("_player_buildings")
	var home: Node2D = buildings[0][0] as Node2D
	var target: Node2D = buildings[1][0] as Node2D
	var origin_tile: Vector2i = _map.call("world_to_tile", home.global_position)
	var workshop_tile: Vector2i = _find_workshop_tile(origin_tile)
	_expect(workshop_tile != Vector2i(-1, -1), "home pocket supports legal Workshop footprint")
	if workshop_tile == Vector2i(-1, -1):
		_finish()
		return
	_expect(_rm.call("try_spend", 0, BuildingData.get_building_cost(BuildingData.BuildingType.SIEGE_WORKSHOP)), "Workshop is paid")
	var workshop: Node2D = _main.call("_spawn_building", BuildingData.BuildingType.SIEGE_WORKSHOP, 0, workshop_tile) as Node2D
	workshop.call("start_construction")
	var units: Array = _main.get("_player_units")
	var worker: Node2D = units[0][0] as Node2D
	worker.global_position = workshop.global_position + Vector2(28.0, 0.0)
	worker.call("command_build", workshop)
	worker.call("_process_building", float(workshop.get("build_time")))
	_expect(int(workshop.get("state")) == 2, "real worker completes Workshop")
	workshop.set_process(false)
	var siege: Node2D = _produce(workshop, UnitData.UnitType.SIEGE)
	var spotter: Node2D = _produce(home, UnitData.UnitType.SCOUT)
	_expect(siege != null and spotter != null, "paid Siege and Scout actually spawn")
	if siege == null or spotter == null:
		_finish()
		return
	var home_position: Vector2 = spotter.global_position
	# Find a walkable firing tile within weapon reach that cannot reveal even
	# an edge of the Town Center footprint with the siege's own short sight.
	var firing_position: Vector2 = Vector2.INF
	for degrees: float in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		var candidate: Vector2 = target.global_position + Vector2.RIGHT.rotated(deg_to_rad(degrees)) * 108.0
		if not bool(_map.call("is_tile_walkable", _map.call("world_to_tile", candidate))):
			continue
		siege.global_position = candidate
		_main.call("_update_fog_of_war")
		if not bool(_map.call("is_entity_visible_to_player", target, 0)):
			firing_position = candidate
			break
	_expect(firing_position != Vector2.INF, "fixture distinguishes weapon reach from current sight")
	if firing_position == Vector2.INF:
		_finish()
		return
	spotter.global_position = target.global_position + Vector2(0.0, -96.0)
	_main.call("_update_fog_of_war")
	_expect(bool(_map.call("is_entity_visible_to_player", target, 0)), "allied paid Scout reveals target through real fog")
	siege.set("_auto_attack_timer", 0.0)
	siege.call("_try_auto_attack")
	print("Siege acquisition: reach=%s sight=%s distance=%.1f state=%s building=%s" % [siege.get("attack_range"), siege.get("vision_radius"), siege.global_position.distance_to(target.global_position), siege.get("current_state"), siege.get("attack_building_target") == target])
	_expect(siege.get("attack_building_target") == target, "idle siege acquires a scouted building within weapon range")
	var hp_before: float = float(target.get("hp"))
	for _tick in range(30):
		siege.call("_process", 1.0 / 60.0)
	_expect(float(target.get("hp")) < hp_before, "acquired target takes actual siege damage at firing range")
	_expect(siege.global_position.distance_to(firing_position) < 0.1, "siege fires without walking into point-blank range")
	# A nearby worker cannot divert automatic siege from its structural role.
	var guard: Node2D = units[1][0] as Node2D
	guard.global_position = firing_position + Vector2(0.0, 30.0)
	siege.call("command_stop")
	siege.set("_auto_attack_timer", 0.0)
	_main.call("_update_fog_of_war")
	siege.call("_try_auto_attack")
	_expect(siege.get("attack_building_target") == target, "siege automatic targeting prefers visible buildings over a nearby unit")
	# A player explicitly focusing that worker still has full authority.
	siege.call("command_attack", guard)
	siege.set("_auto_attack_timer", 0.0)
	siege.call("_process_attacking", 0.01)
	_expect(siege.get("attack_target") == guard, "explicit unit focus remains authoritative")
	guard.global_position = target.global_position + Vector2(700.0, 700.0)
	spotter.global_position = home_position
	_main.call("_update_fog_of_war")
	_expect(not bool(_map.call("is_entity_visible_to_player", target, 0)), "removing live spotter hides target")
	siege.call("command_stop")
	siege.set("_auto_attack_timer", 0.0)
	siege.call("_try_auto_attack")
	_expect(siege.get("attack_building_target") == null, "weapon reach never grants hidden building targeting")
	spotter.global_position = target.global_position + Vector2(0.0, -96.0)
	_main.call("_update_fog_of_war")
	var destination: Vector2 = target.global_position + Vector2(400.0, 0.0)
	siege.call("command_attack_move", destination)
	siege.set("_auto_attack_timer", 0.0)
	siege.call("_try_auto_attack")
	_expect(siege.get("attack_building_target") == target and bool(siege.get("attack_move")), "attack-move acquires building and preserves travel intent")
	_expect(siege.get("move_target") == destination, "automatic acquisition preserves attack-move destination")
	spotter.global_position = home_position
	_main.call("_update_fog_of_war")
	siege.call("_process", 0.05)
	_expect(siege.get("attack_building_target") == null, "existing siege target is dropped immediately after losing live sight")
	_expect(bool(siege.get("attack_move")) and siege.get("move_target") == destination, "sight loss resumes the original attack-move order")
	print("Paid siege: Workshop labor40s; production35s/150W100G/3pop; live Scout40F10G; target HP %s -> %s" % [hp_before, target.get("hp")])
	_finish()


func _produce(building: Node2D, unit_type: int) -> Node2D:
	var queue: Node = building.call("get_production_queue")
	queue.set("auto_queue_enabled", false)
	queue.call("cancel_all")
	var units: Array = _main.get("_player_units")
	var before_count: int = units[0].size()
	var before_bank: Dictionary = _rm.call("get_all_resources", 0)
	var before_reservations: int = int(_gm.call("get_reserved_population", 0))
	if not bool(queue.call("enqueue_unit", unit_type)):
		return null
	var expected_bank: Dictionary = before_bank.duplicate()
	var cost: Dictionary = UnitData.get_unit_cost(unit_type)
	for resource: String in cost:
		expected_bank[resource] -= int(cost[resource])
	_expect(_rm.call("get_all_resources", 0) == expected_bank, "paid %s spends its full advertised price" % UnitData.get_unit_name(unit_type))
	_expect(int(_gm.call("get_reserved_population", 0)) == before_reservations + int(UnitData.get_unit_stats(unit_type)["pop_cost"]), "paid %s reserves full population" % UnitData.get_unit_name(unit_type))
	queue.call("advance", float(queue.get("current_train_time")) + 0.1)
	units = _main.get("_player_units")
	if units[0].size() != before_count + 1:
		return null
	var produced: Node2D = units[0][-1] as Node2D
	produced.set_process(false)
	produced.call("command_stop")
	return produced


func _find_workshop_tile(home: Vector2i) -> Vector2i:
	for dy: int in range(-10, 11):
		for dx: int in range(-10, 11):
			var candidate: Vector2i = home + Vector2i(dx, dy)
			var legal := true
			for fy: int in range(3):
				for fx: int in range(3):
					legal = legal and bool(_map.call("is_tile_buildable", candidate + Vector2i(fx, fy)))
			if legal and bool(_map.call("is_tile_visible_to_player", candidate, 0)):
				return candidate
	return Vector2i(-1, -1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[FAIL] paid_siege_acquisition: " + message)


func _finish() -> void:
	paused = false
	if is_instance_valid(_main):
		_main.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] paid_siege_acquisition: paid Workshop/queue, full weapon reach, live spotter, role priority, explicit focus and attack-move intent")
		quit(0)
	else:
		quit(1)
