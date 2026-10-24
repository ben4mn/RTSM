extends "res://tools/test_attack_march_cohesion.gd"
## Private synthetic partition checks plus real Main/network/fresh-AI seams.
## No paid-match, rendered benefit, pacing or performance claim.


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.selected_civilization = CivilizationData.Civilization.SUNSTRIDE_CLANS
	GameManager.selected_opponent_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	container = NavigationMap.new()
	add_child(container)
	_test_core_and_singleton()
	_test_permutation_and_bridge()
	_test_global_validation()
	_test_no_route_rescue()
	_test_independent_lifecycle()
	_test_pending_groups()
	container.free()
	await _test_partition_authority()
	for failure: String in failures:
		push_error("[FAIL] attack_march_partition: " + failure)
	print("ATTACK_MARCH_PARTITION checks=%d failures=%s scope=private-synthetic-plus-authority" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _core(owner: int = 0) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for index: int in 8:
		result.append(_spawn(UnitData.UnitType.INFANTRY if index < 4 else UnitData.UnitType.CAVALRY, Vector2((index % 2) * 32, (index / 2) * 24), owner))
	return result


func _test_core_and_singleton() -> void:
	for owner: int in 2:
		var core := _core(owner)
		var newcomer := _spawn(UnitData.UnitType.CAVALRY, Vector2(-320, 48), owner)
		var roster: Array[UnitBase] = core.duplicate()
		roster.append(newcomer)
		var orders := _orders(roster)
		var paths: Array[PackedVector2Array] = []
		for unit: UnitBase in roster:
			paths.append(unit.path.duplicate())
		var requests: int = container.requests
		_expect(MARCH.attach_orders(orders) == null, "unchanged whole-nine admission rejects the dispersed batch")
		var tokens: Array[RefCounted] = MARCH.attach_compact_orders(orders)
		_expect(tokens.size() == 1 and core.all(func(unit: UnitBase) -> bool: return unit.is_attack_marching()), "compact mixed eight survives a distant ninth for owner%d" % owner)
		_expect(not newcomer.is_attack_marching() and newcomer.get_movement_speed() == newcomer.speed, "newborn retains its native accepted attack move")
		for index: int in roster.size():
			_expect(roster[index].path == paths[index] and roster[index].move_target == orders[index].destination, "partition preserves every accepted path and endpoint")
		_expect(container.requests == requests, "partition makes zero planner requests")
		# Test-only position change models catching up; the runtime has no join hook.
		newcomer.position = Vector2(40, 40)
		newcomer.get_movement_speed()
		_expect(not newcomer.is_attack_marching() and core[0].get_attack_march() == tokens[0], "catching up never auto-joins a native singleton")
		_clear()


func _membership(groups: Array) -> Array[String]:
	var result: Array[String] = []
	for group: Array in groups:
		var ids: Array[int] = []
		for unit: UnitBase in group:
			ids.append(unit.get_instance_id())
		ids.sort()
		result.append(str(ids))
	result.sort()
	return result


func _test_permutation_and_bridge() -> void:
	var a := _spawn(UnitData.UnitType.INFANTRY, Vector2(0, 0))
	var b := _spawn(UnitData.UnitType.CAVALRY, Vector2(100, 0))
	var c := _spawn(UnitData.UnitType.INFANTRY, Vector2(200, 0))
	var reference := _membership(MARCH.spatial_candidates([a, b, c]))
	for order: Array in [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]]:
		var groups: Array = MARCH.spatial_candidates(order)
		_expect(_membership(groups) == reference, "bridge membership is invariant under all six input permutations")
		_expect(groups.size() == 2, "transitive proximity chain never becomes one over-wide cohort")
		for group: Array in groups:
			for first: UnitBase in group:
				for second: UnitBase in group:
					_expect(first.position.distance_to(second.position) <= MARCH.START_DIAMETER, "every candidate remains pairwise compact")
	_clear()
	var core := _core()
	var fringe := _spawn(UnitData.UnitType.CAVALRY, Vector2(-120, 0))
	var roster: Array = [fringe]
	roster.append_array(core)
	var expected := _membership(MARCH.spatial_candidates(roster))
	roster.reverse()
	_expect(_membership(MARCH.spatial_candidates(roster)) == expected, "dense-core/fringe partition is deterministic under reverse order")
	_expect(MARCH.spatial_candidates(roster).any(func(group: Array) -> bool: return group.size() == 8), "dense core is not fragmented by a low-degree fringe")
	_clear()


func _test_global_validation() -> void:
	var a := _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
	var b := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48))
	var enemy_a := _spawn(UnitData.UnitType.INFANTRY, Vector2(600, 0), 1)
	var enemy_b := _spawn(UnitData.UnitType.CAVALRY, Vector2(600, 48), 1)
	for roster: Array[UnitBase] in [[a, b, a] as Array[UnitBase], [a, b, enemy_a, enemy_b] as Array[UnitBase]]:
		_expect(MARCH.attach_compact_orders(_orders(roster)).is_empty(), "duplicate/mixed-owner total batch cannot be split into valid cohorts")
		_expect(roster.all(func(unit: UnitBase) -> bool: return not unit.is_attack_marching()), "rejected total batch attaches nobody")
		for unit: UnitBase in roster:
			unit.command_attack_move(Vector2(900, 0))
		_expect(PENDING.watch_compact_waves(roster, Vector2(900, 0), 0).is_empty(), "pending wrapper retains global duplicate/owner rejection")
	_expect(MARCH.spatial_candidates([a, null, b]).is_empty(), "invalid entry cannot be filtered to rescue a candidate")
	b.position = Vector2(NAN, 0)
	_expect(MARCH.spatial_candidates([a, b]).is_empty(), "nonfinite positions reject before geometry sorting")
	b.position = Vector2(0, 48)
	_clear()
	var crowd: Array[UnitBase] = []
	for index: int in 65:
		crowd.append(_spawn(UnitData.UnitType.INFANTRY if index % 2 == 0 else UnitData.UnitType.CAVALRY, Vector2((index / 2) * 400, (index % 2) * 48)))
	var first64: Array[UnitBase] = crowd.slice(0, 64)
	_expect(MARCH.spatial_candidates(first64).size() == 32, "valid64 total recipients remain bounded across32 compact pairs")
	_expect(MARCH.attach_compact_orders(_orders(crowd)).is_empty(), "65 distinct recipients reject before any per-cohort admission")
	for unit: UnitBase in crowd:
		unit.command_attack_move(Vector2(15000, 0))
	_expect(PENDING.watch_compact_waves(crowd, Vector2(15000, 0), 0).is_empty(), "pending wrapper cannot bypass64 with separate pairs")
	crowd[64].unit_type = UnitData.UnitType.SCOUT
	_expect(MARCH.spatial_candidates(crowd).is_empty(), "raw65 budget includes unarmed exclusions")
	_clear()


func _test_no_route_rescue() -> void:
	for defect: String in ["idle", "empty_route", "detour"]:
		var a := _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
		var b := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48))
		var bad := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 96))
		var orders := _orders([a, b, bad])
		match defect:
			"idle": bad.command_stop()
			"empty_route": orders[2].path = PackedVector2Array()
			"detour":
				var route := PackedVector2Array([bad.position, Vector2(-200, 96), Vector2(600, 96)])
				orders[2].path = route
				bad.command_attack_move_path(route)
		_expect(MARCH.spatial_candidates([a, b, bad])[0].size() == 3, "armed bad member is retained during geometry-only partition: " + defect)
		_expect(MARCH.attach_compact_orders(orders).is_empty() and not a.is_attack_marching() and not b.is_attack_marching(), "unchanged route gate rejects whole compact candidate without rescue: " + defect)
		var other_a := _spawn(UnitData.UnitType.INFANTRY, Vector2(0, 400))
		var other_b := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 448))
		orders.append_array(_orders([other_a, other_b]))
		_expect(MARCH.attach_compact_orders(orders).size() == 1 and other_a.is_attack_marching() and other_b.is_attack_marching() and not a.is_attack_marching() and not b.is_attack_marching(), "a separate valid cohort survives without rescuing the bad-route cohort: " + defect)
		_clear()
	var only_riders: Array[UnitBase] = [_spawn(UnitData.UnitType.CAVALRY, Vector2.ZERO), _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48))]
	var only_warriors: Array[UnitBase] = [_spawn(UnitData.UnitType.INFANTRY, Vector2(0, 400)), _spawn(UnitData.UnitType.INFANTRY, Vector2(0, 448))]
	var roster: Array[UnitBase] = only_riders + only_warriors
	_expect(MARCH.attach_compact_orders(_orders(roster)).is_empty(), "separate homogeneous groups remain uncapped despite mixed total selection")
	_clear()


func _two_groups() -> Array[UnitBase]:
	return [_spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO), _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48)), _spawn(UnitData.UnitType.INFANTRY, Vector2(0, 400)), _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 448))]


func _test_independent_lifecycle() -> void:
	for action: String in ["damage", "combat", "move", "retask", "death"]:
		var roster := _two_groups()
		var tokens: Array[RefCounted] = MARCH.attach_compact_orders(_orders(roster))
		_expect(tokens.size() == 2 and roster[0].get_attack_march() != roster[2].get_attack_march(), "separate compact mixed groups receive independent tokens")
		var other: RefCounted = roster[2].get_attack_march()
		match action:
			"damage": roster[0].take_damage(1.0)
			"combat":
				var enemy := _spawn(UnitData.UnitType.INFANTRY, Vector2(40, 0), 1)
				container.visible_enemy = true
				roster[0].command_attack(enemy, false)
			"move": roster[0].command_move(Vector2(-200, 0))
			"retask": roster[0].command_attack_move(Vector2(800, 0))
			"death": roster[0].die()
		_expect(not roster[1].is_attack_marching() and roster[1].get_movement_speed() == roster[1].speed, "first cohort releases/detaches after " + action)
		_expect(roster[2].is_attack_marching() and roster[3].is_attack_marching() and roster[2].get_attack_march() == other, "other cohort remains independent after " + action)
		roster[1].position = Vector2(0, 410)
		roster[1].get_movement_speed()
		_expect(not roster[1].is_attack_marching(), "released member cannot join another cohort while catching up")
		_clear()
	container.visible_enemy = false


func _test_pending_groups() -> void:
	for interruption: String in ["none", "same_target_retask", "damage", "expired"]:
		var roster := _two_groups()
		var singleton := _spawn(UnitData.UnitType.CAVALRY, Vector2(-400, 200))
		roster.append(singleton)
		var target := Vector2(900, 200)
		for unit: UnitBase in roster:
			unit.command_attack_move(target)
		var tokens: Array[RefCounted] = PENDING.watch_compact_waves(roster, target, 0)
		_expect(tokens.size() == 2 and singleton.get_pending_attack_march() == null, "fresh wave gets only two compact pending tokens")
		var requests: int = container.requests
		roster[0].call("_request_navigation_path", container, target, 4.0, false)
		roster[2].call("_request_navigation_path", container, target, 4.0, false)
		match interruption:
			"same_target_retask": roster[0].command_attack_move(target)
			"damage": roster[0].take_damage(1.0)
			"expired": GameManager.game_time += 1.1
		roster[1].call("_request_navigation_path", container, target, 4.0, false)
		roster[3].call("_request_navigation_path", container, target, 4.0, false)
		_expect(container.requests == requests + 4, "pending partition adds no planner requests")
		_expect(roster[0].is_attack_marching() == (interruption == "none") and roster[1].is_attack_marching() == (interruption == "none"), "first pending token preserves generation/contact/expiry cancellation")
		_expect(roster[2].is_attack_marching() == (interruption != "expired") and roster[3].is_attack_marching() == (interruption != "expired"), "other pending token is independent but retains its own1s expiry")
		_expect(singleton.get_attack_march() == null and singleton.get_pending_attack_march() == null, "far pending singleton never auto-attaches")
		_clear()


func _test_partition_authority() -> void:
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	main.set_process(false)
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("StrategyController").set_process(false)
	var map: Node2D = main.get("game_map")
	map.set_process(false)
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var generator := MapGenerator.new(101)
	generator.call("_init_grid")
	map.set("pathfinding", Pathfinding.new(generator))
	container = map.get_node("UnitsContainer")
	var groups: Array = []
	for owner: int in 2:
		var units: Array[UnitBase] = []
		for index: int in 3:
			var tile := Vector2i(20 + index, 20 + owner * 2) if index < 2 else Vector2i(15, 15 + owner * 2)
			var unit: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY if index == 0 else UnitData.UnitType.CAVALRY, owner, map.tile_to_world(tile))
			unit.set_process(false)
			units.append(unit)
		groups.append(units)
	var own: Array[UnitBase] = groups[0]
	map.selection_mgr.select_many([own[0], own[1], own[2]] as Array[Node2D])
	main.call("_arm_attack_move_command")
	main.call("_on_move_command", Vector2i(30, 20))
	_expect(own[0].is_attack_marching() and own[1].is_attack_marching() and not own[2].is_attack_marching(), "actual Main planner creates partial2/3 march")
	main.call("_on_selection_changed", [own[0], own[1], own[2]] as Array[Node2D])
	_expect(str(main.get_node("HUD").get("selection_details").text) == "Group march\n2/3 fighters", "existing HUD honestly shows partial membership")
	main.call("_arm_move_command")
	main.call("_on_move_command", Vector2i(31, 20))
	_expect(own.all(func(unit: UnitBase) -> bool: return not unit.is_attack_marching()), "Main forced Move releases all selected march members")
	var server: Node = NETWORK.new()
	main.add_child(server)
	server.main = main
	server.game_map = map
	server.set_process(false)
	server.call("_register_server_entities")
	for owner: int in 2:
		var units: Array[UnitBase] = groups[owner]
		var ids: Array = units.map(func(unit: UnitBase) -> int: return NetworkSession.entity_id(unit))
		var goal: Vector2 = map.tile_to_world(Vector2i(30, 20 + owner * 2))
		var response: String = server.execute_command(owner, {"command": "attack_move", "ids": ids, "position": [goal.x, goal.y]})
		_expect(response.is_empty() and units[0].is_attack_marching() and units[1].is_attack_marching() and not units[2].is_attack_marching(), "authority slot%d uses same partial rule" % owner)
	main.call("_update_fog_of_war")
	for slot: int in 2:
		var packet: Dictionary = server.call("_snapshot_for", slot)
		var own_ids: Array = groups[slot].map(func(unit: UnitBase) -> int: return NetworkSession.entity_id(unit))
		var active := 0
		var own_seen := 0
		var enemy_seen := 0
		for actor: Dictionary in packet.actors:
			if int(actor.id) in own_ids:
				own_seen += 1
				active += int(actor.get("marching") == true)
			elif int(actor.owner) != slot:
				enemy_seen += 1
				_expect(not actor.has("marching"), "partial status remains absent from visible foreign actors")
		_expect(own_seen == 3 and active == 2 and enemy_seen > 0, "slot%d receives own2/3 with nonvacuous enemy privacy" % slot)
	var ai: Node = main.get_node("AIController")
	var enemy_units: Array[UnitBase] = groups[1]
	var target: Vector2 = map.tile_to_world(Vector2i(30, 22))
	ai.call("_send_attack", enemy_units, target)
	_expect(enemy_units[0].get_pending_attack_march() != null and enemy_units[1].get_pending_attack_march() == enemy_units[0].get_pending_attack_march() and enemy_units[2].get_pending_attack_march() == null, "actual fresh AI partitions before lazy path acceptance")
	for unit: UnitBase in enemy_units:
		unit.call("_request_navigation_path", map, target, 4.0, false)
	_expect(enemy_units[0].is_attack_marching() and enemy_units[1].is_attack_marching() and not enemy_units[2].is_attack_marching(), "AI accepted routes admit only its compact pair")
	ai.call("_retarget_attack_wave", enemy_units)
	_expect(enemy_units.all(func(unit: UnitBase) -> bool: return unit.get_pending_attack_march() == null and not unit.is_attack_marching()), "actual AI retarget refresh never repartitions or reforms")
	main.free()
