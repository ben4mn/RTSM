extends Node
## Resource rallies use paid production and real harvesting/drop-off in Main.
## Hidden targets are represented by their last observed identity/position only.

var _failures: Array[String] = []
var _match: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	GameManager.selected_population_limit = 30
	_match = load("res://scenes/main/main.tscn").instantiate()
	add_child(_match)
	for frame: int in range(900):
		if GameManager.current_state == GameManager.GameState.PLAYING and _match.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_match.set_process(false)
	_match.get("ai_controller").get("_decision_timer").stop()
	for owner_units: Array in _match.get("_player_units"):
		for existing: UnitBase in owner_units:
			existing.set_process(false)
	var map: Node2D = _match.get("game_map") as Node2D
	var selection: SelectionManager = map.get("selection_mgr") as SelectionManager
	var tc: BuildingBase = (_match.get("_player_buildings") as Array)[0][0] as BuildingBase
	var source: ResourceNode = null
	for candidate: Node in get_tree().get_nodes_in_group("resources"):
		if candidate is ResourceNode and candidate.resource_type == "wood" and map.is_resource_target_valid(candidate, "wood", 0) and map.is_resource_target_visible_to_player(candidate, 0) and selection.call("_get_node_at", candidate.global_position, true) == null:
			source = candidate as ResourceNode
			break
	_expect(source != null, "seeded opening has a visible wood resource for a deliberate rally tap")
	if source == null:
		_finish()
		return
	selection.select_single(tc)
	_expect(selection.arm_building_rally(tc), "the selected Town Center can arm its rally flag")
	_expect(not selection.arm_building_rally(tc) and not selection.is_building_rally_armed(), "tapping the flag again cancels without issuing an order")
	_expect(selection.arm_building_rally(tc), "rally can be rearmed")
	selection.cancel_touch_gesture()
	_expect(selection.is_building_rally_armed(), "panning or ending a pointer gesture preserves the deliberate rally mode")
	var overlapping_worker: Villager = (_match.get("_player_units") as Array)[0][0] as Villager
	var original_worker_position: Vector2 = overlapping_worker.global_position
	overlapping_worker.global_position = source.global_position
	selection.call("_handle_tap", selection.call("_world_to_screen", source.global_position), true)
	_expect(tc.rally_resource_instance_id == source.get_instance_id(), "armed touch targets the observed resource even behind a friendly worker")
	_expect(not selection.is_building_rally_armed(), "one destination consumes the armed flag")
	overlapping_worker.global_position = original_worker_position
	_expect(tc.rally_resource_type == "wood" and tc.rally_point == source.global_position, "rally retains type and observed position")
	_expect(selection.selected == [tc], "resource rally keeps the producer selected")
	var q: ProductionQueue = tc.get_production_queue() as ProductionQueue
	var food_before: int = ResourceManager.get_resource(0, "food")
	var units: Array = (_match.get("_player_units") as Array)[0] as Array
	var units_before: int = units.size()
	_expect(q.enqueue_unit(UnitData.UnitType.VILLAGER), "ordinary starting budget pays for the resource-rallied Villager")
	q.advance(q.current_train_time + 0.01)
	_expect(units.size() == units_before + 1, "paid completion produces exactly one Villager")
	_expect(ResourceManager.get_resource(0, "food") == food_before - int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).food), "Villager costs exactly its listed Food")
	if units.size() != units_before + 1:
		_finish()
		return
	var worker: Villager = units.back() as Villager
	worker.set_process(false)
	_expect(worker.current_state == UnitBase.State.GATHERING and worker.gather_target == source, "resource rally starts the accepted gather job, not an idle destination")
	var stock_before: int = source.remaining
	var wood_before: int = ResourceManager.get_resource(0, "wood")
	var deposited: Array[int] = []
	worker.resource_deposited.connect(func(resource_type: String, amount: int) -> void:
		if resource_type == "wood": deposited.append(amount)
	)
	for frame: int in range(7200):
		_match.call("_update_fog_of_war")
		worker._process(1.0 / 60.0)
		if not deposited.is_empty(): break
	_expect(not deposited.is_empty(), "the paid worker naturally reaches the tree, harvests and deposits")
	_expect(ResourceManager.get_resource(0, "wood") - wood_before == stock_before - source.remaining - worker.carried_amount, "real resource stock equals deposited plus carried wood")
	worker.command_stop()

	# Ground orders reset resource intent and retain precise forced movement.
	var ground: Vector2i = map.world_to_tile(source.global_position) + Vector2i(0, 1)
	while not map.is_tile_walkable(ground) or selection.call("_get_resource_at", map.tile_to_world(ground), false) != null:
		ground += Vector2i(0, 1)
	selection.select_single(tc)
	_expect(selection.arm_building_rally(tc), "ground destination arms the same flag")
	selection.call("_handle_tap", selection.call("_world_to_screen", map.tile_to_world(ground)), false)
	_expect(tc.rally_resource_instance_id == 0 and tc.rally_resource_type.is_empty(), "ordinary ground rally clears resource intent")
	units_before = units.size()
	_expect(q.enqueue_unit(UnitData.UnitType.VILLAGER), "a second ordinary paid Villager queues")
	q.advance(q.current_train_time + 0.01)
	_expect(units.size() == units_before + 1, "ground rally paid birth completes")
	if units.size() == units_before + 1:
		var ground_worker: Villager = units.back() as Villager
		ground_worker.set_process(false)
		_expect(ground_worker.current_state == UnitBase.State.MOVING and bool(ground_worker.get("_force_move_active")), "ordinary ground rally remains Move")
		_expect(ground_worker.gather_target == null, "ordinary ground rally does not inherit old gather intent")

	# Right-click parity, then simulate loss of current vision after the order.
	selection.select_single(tc)
	selection.call("_handle_right_click", selection.call("_world_to_screen", source.global_position))
	_expect(tc.rally_resource_instance_id == source.get_instance_id(), "mouse resource rally uses the same observed intent")
	var source_tile: Vector2i = map.world_to_tile(source.global_position)
	var fog: FogManager = map.get("fog_of_war") as FogManager
	fog.fog_grid[source_tile.y][source_tile.x] = MapData.FogState.EXPLORED
	_expect(_match.call("_issue_production_rally", worker, tc.rally_point, tc), "resource rally accepts only stored observation while source is hidden")
	_expect(worker.current_state == UnitBase.State.GATHERING and worker.gather_target == null, "hidden rally keeps a position-only gather approach")
	var hidden_stock: int = source.remaining
	worker._process_gathering(0.01)
	_expect(source.remaining == hidden_stock and worker.gather_target == null, "hidden resource cannot be harvested or resolved before current vision")
	fog.fog_grid[source_tile.y][source_tile.x] = MapData.FogState.VISIBLE
	worker._process_gathering(0.01)
	_expect(worker.gather_target == source, "revealing the accepted rally position resolves its exact target")
	worker.command_move(worker.global_position + Vector2(64.0, 0.0))
	_expect(worker.current_state == UnitBase.State.MOVING and not worker.has_active_gather_order(), "manual Move supersedes the inherited economic order")

	# A depleted observed identity never creates food/wood from an absent node.
	fog.fog_grid[source_tile.y][source_tile.x] = MapData.FogState.EXPLORED
	_match.call("_issue_production_rally", worker, tc.rally_point, tc)
	source.remaining = 0
	fog.fog_grid[source_tile.y][source_tile.x] = MapData.FogState.VISIBLE
	worker._process_gathering(0.01)
	_expect(worker.current_state == UnitBase.State.IDLE and worker.gather_target == null, "missing/depleted observation safely idles instead of gathering a phantom")
	# Training continues long after the rallied tree is gone. A newborn whose
	# rally resource is visibly exhausted works the nearest wood instead of idling.
	worker.command_stop()
	_match.call("_issue_production_rally", worker, tc.rally_point, tc)
	_expect(worker.current_state != UnitBase.State.IDLE and worker.has_active_gather_order() and worker.carried_resource_type == "wood", "an exhausted rally resource sends the newborn to other wood")
	selection.select_single(tc)
	selection.arm_building_rally(tc)
	selection.select_single(worker)
	_expect(not selection.is_building_rally_armed(), "changing selection cancels the previous building's rally")
	_expect(not selection.arm_building_rally(tc), "a producer must be selected to arm its flag")
	selection.select_single(tc)
	GameManager.current_state = GameManager.GameState.PAUSED
	_expect(not selection.arm_building_rally(tc), "paused games cannot arm a map command")
	GameManager.current_state = GameManager.GameState.PLAYING
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)


func _finish() -> void:
	if is_instance_valid(_match): _match.free()
	if _failures.is_empty():
		print("[PASS] resource_production_rally: armed touch/mouse, overlap, cancel, paid births, natural deposit, ground reset, fog and manual override")
		get_tree().quit(0)
	else:
		for failure: String in _failures: push_error("[FAIL] resource_production_rally: " + failure)
		get_tree().quit(1)
