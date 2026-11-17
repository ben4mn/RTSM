extends Node
## Touch-controls pass on real Main wiring: tapping the sole selected unit puts
## it away, a quick two-finger tap clears any selection (a pinch does not),
## selected troops tapped onto their producer recruit one more of their kind
## (workers onto the Town Center recruit a worker), and three held lifts on
## empty ground queue three waypoints without opening a menu. Loop 2: tapping
## an already-selected unit in a worker or mixed group drops just that unit
## (soldier crowds keep the G1 move), and holding a visible enemy while troops
## walk a route queues an attack after the waypoints (idle troops attack now).

var failures: Array[String] = []
var checks: int = 0
var main: Node
var map: Node2D
var sm: SelectionManager

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	main.set_process(false)
	main.ai_controller.set_process(false)
	main.ai_controller.get("_decision_timer").stop()
	main.get_node("StrategyController").set_process(false)
	map = main.game_map
	sm = map.selection_mgr
	map.fog_of_war.set_process(false)
	map.fog_of_war.reveal_all()
	for unit: UnitBase in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
		unit.command_stop()
	GameManager.hold_shortcuts_enabled = true
	sm.touch_context_enabled = true

	var worker: Villager = main._player_units[0][0]
	_test_tap_to_deselect(worker)
	await _test_two_finger_clear(worker)
	_test_unit_to_producer_trains(worker)
	await _test_long_press_queues(worker)
	_test_group_tap_drops_one(worker)
	await _test_long_press_queues_attack(worker)
	_finish()


## Reachable, walkable ground with no unit, building or resource under a touch.
func _empty_ground(origin: Vector2, avoid: Array[Vector2] = []) -> Vector2:
	for radius: int in range(3, 12):
		for step: int in 16:
			var probe: Vector2 = origin + Vector2.RIGHT.rotated(TAU * step / 16.0) * radius * 32.0
			var tile: Vector2i = map.world_to_tile(probe)
			if not map.is_tile_walkable(tile):
				continue
			var spot: Vector2 = map.tile_to_world(tile)
			var near_used: bool = false
			for used: Vector2 in avoid:
				near_used = near_used or used.distance_to(spot) < 96.0
			if near_used or sm._get_node_at(spot, true) != null or sm._get_resource_at(spot, true) != null:
				continue
			if map.get_navigation_world_path(origin, spot).is_empty():
				continue
			return spot
	return Vector2.INF


func _body_screen(unit: UnitBase) -> Vector2:
	var sprite: Sprite2D = unit.get_node("UnitSprite")
	return sm._world_to_screen(sprite.to_global(sm._unit_touch_body_rect(sprite).get_center()))


func _test_tap_to_deselect(worker: Villager) -> void:
	sm.select_single(worker)
	sm._last_tap_time = 0.0
	sm._handle_tap(_body_screen(worker), true, worker)
	_check(sm.selected.is_empty(), "tapping the sole selected unit clears the selection")
	# A later tap selects it again; a quick second tap is the type double-tap.
	sm._last_tap_time = 0.0
	sm._handle_tap(_body_screen(worker), true, worker)
	_check(sm.selected == [worker], "tapping it again later selects it again")
	sm._last_tap_time = 0.0
	sm._handle_tap(_body_screen(worker), true, worker)
	sm._handle_tap(_body_screen(worker), true, worker)
	_check(sm.selected.size() > 1 and sm.selected.has(worker), "a quick double-tap on the selected unit still selects its whole type")


func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	sm._input(event)
	sm._unhandled_input(event)


func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	sm._input(event)
	sm._unhandled_input(event)


func _test_two_finger_clear(worker: Villager) -> void:
	var center: Vector2 = sm._world_to_screen(_empty_ground(worker.global_position))
	var a: Vector2 = center + Vector2(-60, 0)
	var b: Vector2 = center + Vector2(60, 0)
	# A pinch (one finger travels) keeps the selection.
	sm.select_single(worker)
	_touch(0, a, true)
	_touch(1, b, true)
	_drag(1, b + Vector2(70, 0))
	_touch(1, b + Vector2(70, 0), false)
	_touch(0, a, false)
	await get_tree().process_frame
	_check(sm.selected == [worker], "a two-finger pinch keeps the selection")
	# A quick still two-finger tap clears it, whichever finger lifts last.
	_touch(3, a, true)
	_touch(4, b, true)
	_touch(3, a, false)
	_touch(4, b, false)
	await get_tree().process_frame
	_check(sm.selected.is_empty(), "a quick two-finger tap clears the selection")
	var tc: BuildingBase = main._player_town_center
	sm.select_single(tc)
	_touch(5, a, true)
	_touch(6, b, true)
	_touch(6, b, false)
	_touch(5, a, false)
	await get_tree().process_frame
	_check(sm.selected.is_empty(), "a two-finger tap also clears a selected building")
	# A single tap on empty ground with the worker selected still moves it.
	sm.select_single(worker)
	var moves: Array[Vector2i] = []
	var record := func(tile: Vector2i) -> void: moves.append(tile)
	sm.move_command.connect(record)
	_touch(7, a, true)
	_touch(7, a, false)
	sm.move_command.disconnect(record)
	_check(moves.size() == 1 and sm.selected == [worker], "a one-finger ground tap still orders the selected worker")
	worker.command_stop()


func _test_unit_to_producer_trains(worker: Villager) -> void:
	var tc: BuildingBase = main._player_town_center
	var tc_tile: Vector2i = map.world_to_tile(tc.global_position)
	var barracks: BuildingBase = main._spawn_building(BuildingData.BuildingType.BARRACKS, 0, tc_tile + Vector2i(9, 0))
	barracks.complete_instantly()
	_check(barracks.state == BuildingBase.State.ACTIVE, "fixture barracks is active")
	var spearman: UnitBase = main._spawn_unit(UnitData.UnitType.INFANTRY, 0, tc.global_position + Vector2(-220, 140))
	spearman.set_process(false)
	for resource: String in ["food", "wood", "gold"]:
		ResourceManager.add_resource(0, resource, 2000)
	GameManager.players[0]["population_cap"] = 200
	var queue: ProductionQueue = barracks.get_production_queue()
	var before: int = queue.get_queue_size()
	sm.select_single(spearman)
	var barracks_screen: Vector2 = sm._world_to_screen(barracks.global_position)
	sm._handle_tap(barracks_screen, true)
	_check(queue.get_queue_size() == before + 1, "troop tap on its producer queues one more (%d -> %d)" % [before, queue.get_queue_size()])
	_check(sm.selected == [spearman], "the troop selection stays after recruiting")
	_check(int(queue.queue.back()) == UnitData.UnitType.INFANTRY, "the recruit is the selected troop's kind")
	sm._handle_tap(barracks_screen, true)
	_check(queue.get_queue_size() == before + 2, "repeated taps queue more")
	# Unaffordable: nothing queued, selection kept, existing feedback reused.
	for resource: String in ["food", "wood", "gold"]:
		ResourceManager.add_resource(0, resource, -ResourceManager.get_resource(0, resource))
	sm._handle_tap(barracks_screen, true)
	_check(queue.get_queue_size() == before + 2 and sm.selected == [spearman], "an unaffordable tap queues nothing and keeps the troops")
	_check(str(main.get("_last_train_request_result")) == "resources_missing", "unaffordable result reuses the train feedback path")
	for resource: String in ["food", "wood", "gold"]:
		ResourceManager.add_resource(0, resource, 2000)
	# A building that cannot train the kind keeps the old tap: select it.
	var house: BuildingBase = main._spawn_building(BuildingData.BuildingType.HOUSE, 0, tc_tile + Vector2i(0, 9))
	house.complete_instantly()
	sm.select_single(spearman)
	sm._handle_tap(sm._world_to_screen(house.global_position), true)
	_check(sm.selected == [house], "a non-producer is still selected by a troop tap")
	# Workers with no home order onto the Town Center recruit a worker.
	worker.carried_amount = 0
	var tc_queue: ProductionQueue = tc.get_production_queue()
	var tc_before: int = tc_queue.get_queue_size()
	sm.select_single(worker)
	sm._handle_tap(sm._world_to_screen(tc.global_position), true)
	_check(tc_queue.get_queue_size() == tc_before + 1 and int(tc_queue.queue.back()) == UnitData.UnitType.VILLAGER, "worker tap on the Town Center queues a villager")
	_check(sm.selected == [worker], "the worker selection stays")
	tc_queue.queue.clear()
	queue.queue.clear()
	spearman.queue_free()


func _test_long_press_queues(worker: Villager) -> void:
	worker.command_stop()
	worker.queued_orders.clear()
	sm.select_single(worker)
	var origin: Vector2 = worker.global_position
	var targets: Array[Vector2] = []
	for attempt: int in 3:
		var spot: Vector2 = _empty_ground(origin, targets)
		if spot.is_finite():
			targets.append(spot)
	_check(targets.size() == 3, "fixture has three reachable destinations")
	if targets.size() != 3:
		return
	var contexts: Array[int] = [0]
	var on_open := func() -> void: contexts[0] += 1
	sm.touch_context_opened.connect(on_open)
	var index: int = 20
	for target: Vector2 in targets:
		_check(sm._get_node_at(target, true) == null and sm._get_resource_at(target, true) == null, "hold target is empty ground")
		var screen: Vector2 = sm._world_to_screen(target)
		_touch(index, screen, true)
		# Past the real-time threshold the hold arms; lifting in place acts.
		sm._touch_hold_started_at_msec = Time.get_ticks_msec() - int(sm.long_press_threshold * 1000.0) - 10
		sm._process(0.0)
		_check(sm.is_hold_gesture_active(), "a held still finger arms the hold")
		_touch(index, screen, false)
		index += 1
		await get_tree().process_frame
	sm.touch_context_opened.disconnect(on_open)
	_check(contexts[0] == 0, "no context menu opens for held empty ground")
	_check(worker.current_state == UnitBase.State.MOVING and worker.move_target.distance_to(targets[0]) < 24.0, "the first hold on an idle worker starts moving there")
	_check(worker.queued_orders.size() == 2, "the next two holds append waypoints (%d queued)" % worker.queued_orders.size())
	var overlay: Node = map.get_node("CommandPaths")
	var markers: Array = overlay.get_queued_destination_markers()
	_check(markers.size() == 1 and (markers[0].points as PackedVector2Array).size() == 2, "the path overlay numbers the queued chain")
	# A normal tap replaces the chain.
	var tap_screen: Vector2 = sm._world_to_screen(targets[2])
	await get_tree().create_timer(0.5).timeout
	_touch(40, tap_screen, true)
	_touch(40, tap_screen, false)
	_check(worker.queued_orders.is_empty(), "a normal tap replaces the queued chain")
	# Holding a resource while the worker walks a route queues the gather.
	worker.command_move(targets[0])
	var source: Node2D = map.get_nearest_reachable_resource_node("wood", worker.global_position, 0)
	_check(source != null, "fixture has reachable wood")
	if source == null:
		return
	sm._context_world_pos = source.global_position
	sm._context_target = null
	sm._context_resource = source
	sm._execute_touch_context_action(SelectionManager.TouchContextAction.GATHER)
	_check(worker.queued_orders.size() == 1 and str(worker.queued_orders[0].get("kind", "")) == "gather", "held resource appends a gather after the walking leg")
	worker.queued_orders.clear()
	worker.command_stop()
	worker.enqueue_order({"kind": "gather", "target_id": source.get_instance_id(), "position": source.global_position})
	_check(worker.current_state == UnitBase.State.GATHERING and worker.gather_target == source, "an idle worker starts a queued gather at once")
	worker.command_stop()


func _select(units: Array) -> void:
	sm._begin_selection_batch()
	sm._clear_selection()
	for unit: Variant in units:
		sm._add_to_selection(unit)
	sm._end_selection_batch()


func _place_apart(units: Array, origin: Vector2) -> bool:
	var used: Array[Vector2] = []
	for unit: UnitBase in units:
		var spot: Vector2 = _empty_ground(origin, used)
		if not spot.is_finite():
			return false
		used.append(spot)
		unit.global_position = spot
		unit.command_stop()
		unit.queued_orders.clear()
	return true


func _test_group_tap_drops_one(worker: Villager) -> void:
	var workers: Array = []
	for unit: Variant in main._player_units[0]:
		if is_instance_valid(unit) and unit is Villager and workers.size() < 3:
			workers.append(unit)
	_check(workers.size() == 3, "fixture has three workers")
	if workers.size() != 3 or not _place_apart(workers, worker.global_position):
		_check(false, "fixture spreads the workers onto empty ground")
		return
	# Worker group: a tap on a selected worker drops just that worker.
	_select(workers)
	sm._last_tap_time = 0.0
	sm._handle_tap(_body_screen(workers[1]), true, workers[1])
	_check(sm.selected.size() == 2 and workers[0] in sm.selected and workers[2] in sm.selected and not workers[1] in sm.selected, "tapping a selected worker in a group drops only that worker")
	# A later tap on the dropped worker selects it alone; a quick one is the
	# usual double-tap type select.
	sm._last_tap_time = 0.0
	sm._handle_tap(_body_screen(workers[1]), true, workers[1])
	_check(sm.selected == [workers[1]], "a later tap on the dropped worker selects it alone")
	_select(workers)
	sm._last_tap_time = 0.0
	sm._handle_tap(_body_screen(workers[1]), true, workers[1])
	sm._handle_tap(_body_screen(workers[1]), true, workers[1])
	_check(sm.selected.size() >= 3 and sm.selected.has(workers[1]), "a quick double-tap on a selected worker selects every worker in view")
	# Mixed group (one soldier): tapping the soldier drops just the soldier.
	var soldier: UnitBase = main._spawn_unit(UnitData.UnitType.INFANTRY, 0, worker.global_position)
	soldier.set_process(false)
	var guard: UnitBase = main._spawn_unit(UnitData.UnitType.INFANTRY, 0, worker.global_position)
	guard.set_process(false)
	if not _place_apart([workers[0], workers[1], soldier, guard], worker.global_position):
		_check(false, "fixture spreads the mixed group")
		return
	_select([workers[0], workers[1], soldier])
	sm._last_tap_time = 0.0
	var moves: Array[Vector2i] = []
	var record := func(tile: Vector2i) -> void: moves.append(tile)
	sm.move_command.connect(record)
	sm._handle_tap(_body_screen(soldier), true, soldier)
	_check(sm.selected.size() == 2 and not soldier in sm.selected and moves.is_empty(), "tapping the selected soldier in a mixed group drops only it")
	sm._last_tap_time = 0.0
	sm._handle_tap(_body_screen(workers[0]), true, workers[0])
	_check(sm.selected == [workers[1]] and moves.is_empty(), "tapping a selected worker in a mixed group drops only it")
	# Soldier crowd (G1): a tap on a member is still a move order to that spot.
	_select([soldier, guard, workers[0]])
	sm._last_tap_time = 0.0
	sm._handle_tap(_body_screen(guard), true, guard)
	sm.move_command.disconnect(record)
	_check(moves.size() == 1 and sm.selected.size() == 3, "a tap on a soldier-crowd member stays a move order (G1)")
	for unit: UnitBase in [soldier, guard, workers[0], workers[1], workers[2]]:
		unit.command_stop()
		unit.queued_orders.clear()
	guard.queue_free()
	soldier.queue_free()
	sm._clear_selection()


func _hold(index: int, screen: Vector2) -> void:
	_touch(index, screen, true)
	sm._touch_hold_started_at_msec = Time.get_ticks_msec() - int(sm.long_press_threshold * 1000.0) - 10
	sm._process(0.0)
	_check(sm.is_hold_gesture_active(), "a held still finger on the enemy arms the hold")
	_touch(index, screen, false)


func _test_long_press_queues_attack(worker: Villager) -> void:
	var soldier: UnitBase = main._spawn_unit(UnitData.UnitType.INFANTRY, 0, worker.global_position)
	soldier.set_process(false)
	var enemy: UnitBase = main._spawn_unit(UnitData.UnitType.INFANTRY, 1, worker.global_position)
	enemy.set_process(false)
	if not _place_apart([soldier, enemy], worker.global_position):
		_check(false, "fixture places the soldier and the enemy")
		return
	var route: Vector2 = _empty_ground(soldier.global_position, [enemy.global_position, soldier.global_position])
	_check(route.is_finite(), "fixture has a waypoint for the soldier")
	if not route.is_finite():
		return
	_check(map.is_entity_visible_to_player(enemy, 0), "the enemy is visible")
	var enemy_screen: Vector2 = _body_screen(enemy)
	_check(sm._get_node_at(sm._screen_to_world(enemy_screen), true) == enemy, "the hold lands on the enemy")
	var attacks: Array[Node2D] = []
	var record := func(target: Node2D) -> void: attacks.append(target)
	sm.attack_command.connect(record)
	# Walking a route: the held enemy becomes the next leg, the walk continues.
	sm.select_single(soldier)
	soldier.command_move(route)
	await get_tree().create_timer(0.5).timeout
	_hold(60, enemy_screen)
	await get_tree().process_frame
	_check(attacks.is_empty(), "a hold on an enemy while walking does not replace the route")
	_check(soldier.current_state == UnitBase.State.MOVING and soldier.move_target.distance_to(route) < 24.0, "the soldier keeps walking its current leg")
	_check(soldier.queued_orders.size() == 1 and str(soldier.queued_orders[0].get("kind", "")) == "attack" and int(soldier.queued_orders[0].get("target_id", 0)) == enemy.get_instance_id(), "the held enemy is queued as an attack after the waypoint")
	# When the leg ends, the queued attack starts on that enemy.
	soldier.set_state(UnitBase.State.IDLE)
	soldier._advance_queued_order()
	_check(soldier.current_state == UnitBase.State.ATTACKING and soldier.attack_target == enemy and soldier.queued_orders.is_empty(), "the queued attack engages the enemy after the leg")
	# Idle troops with no queue attack at once, as before.
	soldier.command_stop()
	soldier.queued_orders.clear()
	sm.select_single(soldier)
	await get_tree().create_timer(0.5).timeout
	_hold(61, enemy_screen)
	await get_tree().process_frame
	sm.attack_command.disconnect(record)
	_check(attacks == [enemy] and soldier.queued_orders.is_empty() and soldier.current_state == UnitBase.State.ATTACKING, "a hold on an enemy with idle troops attacks now")
	# Authority helper (online "queue_attack"): append for walkers, attack now otherwise.
	soldier.command_move(route)
	_check(main.queue_attack_for_units([soldier], enemy, 0) == 1 and soldier.queued_orders.size() == 1, "queue_attack_for_units appends for a walking unit")
	_check(main.queue_attack_for_units([soldier], soldier, 0) == 0, "queue_attack_for_units refuses an own target")
	# A dead target is skipped and the route goes on.
	soldier.enqueue_order({"kind": "move", "position": route})
	enemy.hp = 0.0
	enemy.set_state(UnitBase.State.DEAD)
	soldier.set_state(UnitBase.State.IDLE)
	soldier._advance_queued_order()
	_check(soldier.current_state == UnitBase.State.MOVING and soldier.queued_orders.is_empty(), "a dead queued target is skipped and the next waypoint runs")
	soldier.command_stop()
	sm._clear_selection()
	soldier.queue_free()
	enemy.queue_free()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _finish() -> void:
	for failure: String in failures: push_error("[FAIL] touch_controls_pass: " + failure)
	print("[TOUCH CONTROLS PASS] checks=%d failures=%d" % [checks, failures.size()])
	main.free()
	get_tree().quit(0 if failures.is_empty() else 1)
