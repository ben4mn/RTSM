extends Node
## Real Main wiring, paid recruits, drop-off completion and authoritative packets.
## Cargo/positions are staged to isolate ordering from harvesting and map RNG.

var failures: Array[String] = []
var checks: int = 0
var main: Node
var map: Node2D

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
	map.fog_of_war.set_process(false)
	map.fog_of_war.reveal_all()
	for unit: UnitBase in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
		unit.command_stop()
	var worker: Villager = main._player_units[0][0]
	var tc: BuildingBase = main._player_town_center
	var route: PackedVector2Array = map.get_navigation_world_path(worker.global_position, worker.global_position + Vector2(256, 0))
	_check(not route.is_empty(), "opening has reachable test destination")
	if route.is_empty():
		_finish()
		return
	var first: Vector2 = route[-1]
	var second_route: PackedVector2Array = map.get_navigation_world_path(first, first + Vector2(160, 64))
	_check(not second_route.is_empty(), "second destination has a reachable path")
	var second: Vector2 = second_route[-1] if not second_route.is_empty() else first
	_check(map.is_tile_walkable(map.world_to_tile(first)) and map.is_tile_walkable(map.world_to_tile(second)), "queue fixture destinations are actually walkable")
	map.selection_mgr.select_single(worker)
	main._on_move_command(map.world_to_tile(first))
	main._on_queue_order_command(second, null)
	_check(worker.queued_orders.size() == 1, "Main hold queue appends without replacing active move")
	var overlay: Node = map.get_node("CommandPaths")
	_check(overlay.get_queued_destination_markers().size() == 1, "selected queue has numbered waypoint feedback")
	var companion: UnitBase = main._player_units[0][1]
	companion.queued_orders.assign([{"kind": "move", "position": second + Vector2(24, 0)}])
	map.selection_mgr.selected.append(companion)
	_check(overlay.get_queued_destination_markers().size() == 1, "nearby formation waypoints share one numbered route")
	companion.queued_orders[0]["position"] = second + Vector2(240, 0)
	_check(overlay.get_queued_destination_markers().size() == 2, "separate destinations retain distinct numbered routes")
	companion.queued_orders.clear()
	map.selection_mgr.select_single(worker)
	main._on_cancel_queue_command()
	_check(worker.queued_orders.is_empty() and worker.current_state == UnitBase.State.MOVING, "clear queue retains active leg")

	worker.command_stop()
	worker.carried_resource_type = "wood"
	worker.carried_amount = 5
	var bank: int = ResourceManager.get_resource(0, "wood")
	_check(worker.command_dropoff(tc), "manual drop-off accepts owned active compatible depot")
	worker.enqueue_order({"kind": "move", "position": first})
	for step: int in 1800:
		worker._process(1.0 / 30.0)
		if worker.carried_amount == 0: break
	_check(worker.carried_amount == 0 and ResourceManager.get_resource(0, "wood") == bank + 5, "manual drop-off deposits cargo exactly once")
	_check(worker.move_target == first and worker.current_state == UnitBase.State.MOVING, "manual deposit continues queued movement")
	worker.command_stop()
	worker.enqueue_order({"kind": "dropoff", "target_id": 1})
	_check(worker.current_state == UnitBase.State.IDLE and worker.queued_orders.is_empty(), "stale drop-off identity is skipped")
	worker.carried_resource_type = "wood"
	worker.carried_amount = 3
	worker.set_state(UnitBase.State.GATHERING)
	worker.enqueue_order({"kind": "dropoff", "target_id": tc.get_instance_id(), "position": tc.global_position})
	worker._find_and_go_to_dropoff()
	_check(worker.dropoff_target == tc and bool(worker.get("_manual_dropoff")), "harvest completion honors queued depot before choosing an automatic drop-off")
	worker.command_stop()

	_test_gather_depot_resume(worker, tc, first)

	map.selection_mgr.select_single(tc)
	tc.set_rally_point(first)
	main._on_queue_order_command(second, null)
	_check(tc.rally_orders.size() == 2, "existing rally precedes appended destination")
	var queue: ProductionQueue = tc.get_production_queue()
	var count: int = main._player_units[0].size()
	_check(queue.enqueue_unit(UnitData.UnitType.VILLAGER), "normal production pays for queued-rally recruit")
	queue.advance(queue.current_train_time + 0.1)
	_check(main._player_units[0].size() == count + 1, "one paid recruit spawns")
	var recruit: UnitBase = main._player_units[0].back()
	recruit.set_process(false)
	_check(recruit.current_state == UnitBase.State.MOVING and recruit.move_target == first and recruit.queued_orders.size() == 1, "recruit inherits ordered rally sequence")
	tc.set_rally_point(second)
	_check(tc.rally_orders.is_empty() and recruit.queued_orders.size() == 1, "new rally replaces future births without mutating recruited queue")

	var enemy: UnitBase = main._player_units[1][0]
	enemy.global_position = first + Vector2(128, 0)
	enemy.visible = true
	var ink: Vector2 = enemy.get_node("UnitSprite").to_global(map.selection_mgr._unit_touch_body_rect(enemy.get_node("UnitSprite")).get_center())
	recruit.global_position = ink
	map.selection_mgr.select_single(worker)
	var attacks: Array[Node2D] = []
	map.selection_mgr.attack_command.connect(func(target: Node2D) -> void: attacks.append(target))
	map.selection_mgr._handle_tap(map.selection_mgr._world_to_screen(ink), true)
	map.selection_mgr._handle_tap(map.selection_mgr._world_to_screen(ink), true)
	_check(attacks == [enemy, enemy] and map.selection_mgr.selected == [worker], "repeated enemy ink taps attack through overlapping friendly hitbox without clearing selection")

	var adapter: Node = load("res://scripts/network/network_match.gd").new()
	add_child(adapter)
	adapter.main = main
	adapter.game_map = map
	adapter._register_server_entities()
	worker.command_move(first)
	var worker_id: int = NetworkSession.entity_id(worker)
	var tc_id: int = NetworkSession.entity_id(tc)
	_check(adapter.execute_command(0, {"command": "queue_move", "ids": [worker_id], "position": [second.x, second.y]}) == "", "authority accepts own queued move")
	_check(worker.queued_orders.size() == 1, "authority appends exactly once")
	_check(adapter.execute_command(1, {"command": "queue_move", "ids": [worker_id], "position": [second.x, second.y]}) != "", "authority rejects another owner's unit")
	_check(adapter.execute_command(0, {"command": "queue_rally", "target": tc_id, "position": [first.x, first.y]}) == "", "authority accepts own rally queue")
	_check(adapter.execute_command(1, {"command": "queue_rally", "target": tc_id, "position": [first.x, first.y]}) != "", "authority rejects another owner's producer")
	var own_snapshot: Dictionary = adapter._snapshot_for(0)
	var opponent_snapshot: Dictionary = adapter._snapshot_for(1)
	var own_queue: bool = false
	for actor: Dictionary in own_snapshot.actors:
		if int(actor.id) == worker_id:
			own_queue = actor.get("queued_orders", []).size() == 1
	_check(own_queue, "owner snapshot includes pending waypoint")
	for actor: Dictionary in opponent_snapshot.actors:
		if int(actor.owner) == 0:
			_check(not actor.has("queued_orders") and not actor.has("rally_orders"), "opponent snapshot omits private queue")
	_check(adapter.execute_command(0, {"command": "queue_dropoff", "ids": [worker_id], "target": tc_id}) == "", "authority accepts owned drop-off intent")
	adapter.execute_command(0, {"command": "cancel_orders", "ids": [worker_id]})
	_check(worker.queued_orders.is_empty(), "authority clears pending destinations")
	adapter.free()
	_finish()

func _test_gather_depot_resume(worker: Villager, depot: BuildingBase, waypoint: Vector2) -> void:
	var source: Node2D = map.get_nearest_reachable_resource_node("wood", worker.global_position, 0)
	_check(source != null, "resume fixture has reachable real wood")
	if source == null: return
	for mode: String in ["resume", "queued_move", "move", "stop", "deposit_move"]:
		worker.command_stop()
		worker.set("_cargo", {})
		worker.carried_amount = 0
		_check(worker.command_gather(source), mode + ": accepted original gather job")
		worker.enqueue_order({"kind": "dropoff", "target_id": depot.get_instance_id(), "position": depot.global_position})
		for step: int in 3600:
			worker._process(1.0 / 30.0)
			if bool(worker.get("_manual_dropoff")): break
		_check(bool(worker.get("_manual_dropoff")) and worker.carried_amount > 0, mode + ": real harvest begins queued delivery")
		var cargo: int = worker.carried_amount
		var bank: int = ResourceManager.get_resource(0, "wood")
		if mode == "queued_move":
			worker.enqueue_order({"kind": "move", "position": waypoint})
		elif mode == "deposit_move":
			worker.resource_deposited.connect(func(_resource: String, _amount: int) -> void: worker.command_move(waypoint), CONNECT_ONE_SHOT)
		elif mode in ["move", "stop"]:
			if mode == "move": worker.command_move(waypoint)
			else: worker.command_stop()
			worker._on_arrived_for_dropoff(worker)
			_check(not bool(worker.get("_manual_dropoff")) and not worker.has_active_gather_order(), mode + ": fresh order cancels gather resumption and stale arrival")
			_check(worker.carried_amount == cargo and ResourceManager.get_resource(0, "wood") == bank, mode + ": canceled delivery preserves cargo without bank credit")
			continue
		for step: int in 3600:
			worker._process(1.0 / 30.0)
			if worker.carried_amount == 0: break
		_check(worker.carried_amount == 0 and ResourceManager.get_resource(0, "wood") == bank + cargo, mode + ": natural queued delivery credits exactly its load")
		if mode == "resume":
			_check(worker.current_state == UnitBase.State.GATHERING and worker.gather_target == source, "terminal queued depot resumes original valid gather job")
		else:
			_check(worker.current_state == UnitBase.State.MOVING and worker.move_target == waypoint and not worker.has_active_gather_order(), "later queued waypoint takes precedence over original gather job")
	worker.command_stop()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _finish() -> void:
	for failure: String in failures: push_error("[FAIL] queued_destinations: " + failure)
	print("[QUEUED DESTINATIONS] checks=%d failures=%d" % [checks, failures.size()])
	main.free()
	get_tree().quit(0 if failures.is_empty() else 1)
