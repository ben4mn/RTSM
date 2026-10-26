extends "res://tools/test_occlusion_touch_orders.gd"
## Staged real workers, authoritative command adapters and actual HUD touch.
## No simulation rewind: cargo/progress/banks are measured across restoration.

var _adapter: Node
var _workers: Array[Node2D] = []
var _food: Node2D
var _wood: Node2D
var _output: String = ""

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): _output = argument.trim_prefix("--output=")
	if not _output.is_empty(): DirAccess.make_dir_recursive_absolute(_output)
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	Input.emulate_mouse_from_touch = true
	for civ: int in CivilizationData.ORDERED_IDS:
		_profile = "civ%d" % civ
		GameManager.selected_civilization = civ
		GameManager.selected_opponent_civilization = civ
		GameManager.set_state(GameManager.GameState.MENU)
		_main = load("res://scenes/main/main.tscn").instantiate()
		add_child(_main)
		for frame: int in 900:
			if _main.get("_building_placement") != null: break
			await get_tree().process_frame
		_main.set_process(false)
		_main.ai_controller.set_process(false)
		_main.ai_controller.get("_decision_timer").stop()
		_main.get_node("StrategyController").set_process(false)
		_map = _main.game_map
		_selection = _map.selection_mgr
		_map.fog_of_war.set_process(false)
		_map.fog_of_war.reveal_all()
		_map.note_camera_interaction()
		_map.set("_touch_input_detected", true)
		_workers.assign((_main.get("_player_units")[0] as Array).filter(func(unit: UnitBase) -> bool: return unit is Villager))
		for unit: Node in get_tree().get_nodes_in_group("units"): unit.set_process(false)
		_food = _resource("food", 0)
		_wood = _resource("wood", 0)
		_expect(_food != null and _wood != null, "visible starting jobs")
		_adapter = load("res://scripts/network/network_match.gd").new()
		_main.add_child(_adapter)
		_adapter.setup(_main)
		_adapter._register_server_entities()
		await _solo_touch_journey()
		_authority_checks()
		await _freed_build_continuation()
		_main.free()
		await _frames(2)
	for failure: String in _failures: push_error("[FAIL] worker_order_undo: " + failure)
	print("[WORKER ORDER UNDO] checks=%d failures=%d" % [_checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _solo_touch_journey() -> void:
	var original_jobs: Array = []
	for i: int in _workers.size():
		var job: Node2D = _food if i % 2 == 0 else _wood
		_expect(_workers[i].command_gather(job), "initial gather accepted")
		original_jobs.append(job)
	# Inject a small already-carried manifest; Undo must keep its current value.
	_workers[0].set("_cargo", {"food": 3})
	_workers[0].carried_amount = 3
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate(true)
	_selection.select_many(_workers)
	_main._on_move_command(_map.world_to_tile(_workers[0].global_position) + Vector2i(3, 0))
	var status: Dictionary = _main._worker_order_undo.status(0)
	_expect(int(status.get("count", 0)) == UnitData.STARTING_VILLAGERS, "group Move exposes initial-worker Undo")
	_expect(int(status.get("remaining_ms", 0)) > 9000, "ten-second monotonic lifetime")
	_workers[0].set("_cargo", {"food": 5})
	_workers[0].carried_amount = 5
	for physical: Vector2i in [Vector2i(844, 390), Vector2i(951, 669), Vector2i(1280, 720)]:
		get_window().size = physical
		get_window().content_scale_size = physical
		get_window().content_scale_factor = 1.15 if physical.x == 844 else 1.0
		_main._refresh_worker_undo_hud()
		await _frames(4)
		var button: Button = _main.hud.get("_worker_undo_button")
		_expect(button.is_visible_in_tree(), "Undo visible " + str(physical))
		_expect(button.size.x >= 48 and button.size.y >= 48, "comfortable Undo target")
		_expect(get_viewport().get_visible_rect().encloses(button.get_global_rect()), "Undo inside viewport")
		_expect(not button.get_global_rect().intersects(_main.hud.get("top_bar").get_global_rect()), "Undo below top rail")
		_expect(not button.get_global_rect().intersects(_main.hud.get("_navigation_controls").get_global_rect()), "Undo separate from navigation")
		if DisplayServer.get_name() != "headless" and not _output.is_empty():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_output.path_join("undo_%s_%dx%d.png" % [_profile, physical.x, physical.y]))
	await _tap(_main.hud.get("_worker_undo_button").get_global_rect().get_center())
	_expect(_main._worker_order_undo.status(0).is_empty(), "actual Undo touch consumes record")
	for i: int in _workers.size():
		_expect(_workers[i].has_active_gather_order() and _workers[i].gather_target == original_jobs[i], "restores each worker's previous job")
	_expect(_workers[0].get_carried_resources() == {"food": 5}, "keeps current cargo, no rewind")
	_expect(ResourceManager.get_all_resources(0) == bank, "Undo never changes bank")
	_expect(not _main.hud.get("_worker_undo_button").visible, "one-shot button retires")

func _authority_checks() -> void:
	var ids: Array = _workers.map(func(unit: UnitBase) -> int: return NetworkSession.entity_id(unit))
	var destination: Vector2 = _map.tile_to_world(_map.world_to_tile(_workers[0].global_position) + Vector2i(4, 0))
	var move: Dictionary = {"command": "move", "ids": ids, "position": [destination.x, destination.y]}
	_expect(_adapter.execute_command(0, move).is_empty(), "authority group Move accepted")
	var status: Dictionary = _main._worker_order_undo.status(0)
	var id: int = int(status.get("id", 0))
	_expect(id > 0, "authority creates its own record")
	for invalid: Variant in [-1, 0, 1.9, INF, NAN, true, false, "1", [], {}]:
		_expect(not _adapter.execute_command(0, {"command": "undo_workers", "undo_id": invalid}).is_empty(), "malformed Undo ID rejected " + str(invalid))
	_expect(int(_main._worker_order_undo.status(0).get("id", 0)) == id, "invalid IDs leave valid record intact")
	_expect(not _adapter.execute_command(1, {"command": "undo_workers", "undo_id": id}).is_empty(), "other owner cannot use record")
	_expect(_adapter._snapshot_for(1).worker_undo.is_empty(), "other owner's snapshot omits record")
	_expect(_adapter._snapshot_for(0).worker_undo.count == UnitData.STARTING_VILLAGERS, "own snapshot contains availability only")
	_expect(_adapter.execute_command(0, {"command": "undo_workers", "undo_id": float(id)}).is_empty(), "integral JSON ID accepted")
	_expect(not _adapter.execute_command(0, {"command": "undo_workers", "undo_id": id}).is_empty(), "replay rejected")
	_expect(_adapter._snapshot_for(0).worker_undo_result.restored == UnitData.STARTING_VILLAGERS, "authority supplies recipient's result counts")
	# A newer single-worker order invalidates the previous group action.
	_adapter.execute_command(0, move)
	_adapter.execute_command(0, {"command": "stop", "ids": [ids[0]]})
	_expect(_main._worker_order_undo.status(0).is_empty(), "later one-worker Stop supersedes group Undo")
	_adapter.execute_command(0, move)
	id = int(_main._worker_order_undo.status(0).id)
	_main._worker_order_undo.get("_records")[0]["until"] = Time.get_ticks_msec() - 1
	_expect(not _adapter.execute_command(0, {"command": "undo_workers", "undo_id": id}).is_empty(), "expired record rejected")
	# Gather uses accepted workers, and ordinary continuation doesn't invalidate.
	for worker: Villager in _workers: worker.command_stop()
	var gather: Dictionary = NetworkSession.target_payload(_wood)
	gather.merge({"command": "gather", "ids": ids})
	_expect(_adapter.execute_command(0, gather).is_empty(), "group Gather accepted")
	id = int(_main._worker_order_undo.status(0).id)
	_workers[0].command_gather(_food) # Simulate autonomous next-deposit continuation.
	_expect(int(_main._worker_order_undo.status(0).id) == id, "autonomous work continuation preserves history")
	_adapter.execute_command(0, {"command": "undo_workers", "undo_id": id})
	for worker: Villager in _workers: _expect(worker.current_state == UnitBase.State.IDLE, "restores previous idle intent")
	# An unavailable old resource safely stops workers, with no hidden lookup.
	for worker: Villager in _workers: worker.command_gather(_wood)
	_adapter.execute_command(0, move)
	id = int(_main._worker_order_undo.status(0).id)
	var tile: Vector2i = _map.world_to_tile(_wood.global_position)
	_map.fog_of_war.fog_grid[tile.y][tile.x] = MapData.FogState.EXPLORED
	_adapter.execute_command(0, {"command": "undo_workers", "undo_id": id})
	_expect(_main._worker_order_undo.result(0).stopped == UnitData.STARTING_VILLAGERS, "hidden old job stops safely with result feedback")
	for worker: Villager in _workers: _expect(worker.current_state == UnitBase.State.IDLE, "hidden resource is not reactivated")
	_map.fog_of_war.reveal_all()
	# Build intent restores via ordinary commands without changing progress.
	var foundation: BuildingBase = _main._spawn_building(BuildingData.BuildingType.HOUSE, 0, Vector2i(34, 30))
	foundation.start_construction()
	foundation.build_progress = 0.25
	for worker: Villager in _workers: worker.command_build(foundation)
	_adapter._register_server_entities()
	_adapter.execute_command(0, move)
	id = int(_main._worker_order_undo.status(0).id)
	_adapter.execute_command(0, {"command": "undo_workers", "undo_id": id})
	for worker: Villager in _workers: _expect(worker.build_target == foundation and worker.has_active_build_order(), "restores construction intent")
	_expect(is_equal_approx(foundation.build_progress, 0.25), "construction progress never rewinds")
	# Dead workers are omitted; deleting a retained target is weak-reference safe.
	_adapter.execute_command(0, move)
	id = int(_main._worker_order_undo.status(0).id)
	_workers[0].current_state = UnitBase.State.DEAD
	foundation.free()
	_adapter.execute_command(0, {"command": "undo_workers", "undo_id": id})
	_expect(_main._worker_order_undo.result(0).stopped == UnitData.STARTING_VILLAGERS - 1, "dead worker skipped; removed foundation stops survivors")
	_expect(_workers[0].current_state == UnitBase.State.DEAD, "Undo never revives workers")
	var guests: Array = (_main.get("_player_units")[1] as Array).filter(func(unit: UnitBase) -> bool: return unit is Villager)
	var guest_job: Node2D = _resource("food", 1)
	_expect(guest_job != null, "guest has visible original work")
	for worker: Villager in guests: worker.command_gather(guest_job)
	var guest_ids: Array = guests.map(func(unit: UnitBase) -> int: return NetworkSession.entity_id(unit))
	var guest_destination: Vector2 = _map.tile_to_world(_map.world_to_tile(guests[0].global_position) + Vector2i(-3, 0))
	_expect(_adapter.execute_command(1, {"command": "move", "ids": guest_ids, "position": [guest_destination.x, guest_destination.y]}).is_empty(), "guest authority group Move accepted")
	var guest_status: Dictionary = _main._worker_order_undo.status(1)
	_expect(int(guest_status.get("count", 0)) == UnitData.STARTING_VILLAGERS, "guest authority owns its own record")
	_expect(_adapter._snapshot_for(0).worker_undo.is_empty(), "host never receives guest availability")
	_expect(_adapter.execute_command(1, {"command": "undo_workers", "undo_id": guest_status.id}).is_empty(), "guest record restores successfully")
	for worker: Villager in guests: _expect(worker.has_active_gather_order() and worker.gather_target == guest_job, "guest restores original work")

func _freed_build_continuation() -> void:
	var survivors: Array = _workers.filter(func(worker: Villager) -> bool: return worker.current_state != UnitBase.State.DEAD)
	var foundation: BuildingBase = _main._spawn_building(BuildingData.BuildingType.HOUSE, 0, Vector2i(36, 30))
	foundation.start_construction()
	for worker: Villager in survivors:
		_expect(worker.command_gather(_wood), "accept work before saved-resource deletion")
		worker.command_build(foundation)
		_expect(worker.get("_saved_gather_target") == _wood, "builder retains prior resource reference")
	var lost_id: int = _wood.get_instance_id()
	_wood.harvest(_wood.remaining) # Real depletion clears registry and frees after its fade.
	await get_tree().create_timer(0.65).timeout
	await _frames(2)
	_expect(not is_instance_valid(_wood), "saved resource is actually freed before Undo capture")
	var selected_workers: Array[Node2D] = []
	selected_workers.assign(survivors)
	_selection.select_many(selected_workers)
	_main._on_move_command(_map.world_to_tile(survivors[0].global_position) + Vector2i(3, 0))
	var status: Dictionary = _main._worker_order_undo.status(0)
	_expect(int(status.get("count", 0)) == survivors.size(), "freed saved reference does not abort capture")
	if status.is_empty(): return
	_main._on_worker_order_undo(int(status.id))
	for worker: Villager in survivors:
		_expect(worker.has_active_build_order() and worker.build_target == foundation, "builder restores with removed prior resource")
		_expect(worker.get("_saved_gather_target") == null, "removed continuation is safely represented as null")
	foundation._complete_construction() # Another builder finishes; ordinary worker completion handles the old job.
	for worker: Villager in survivors:
		worker._process_building(0.05)
		_expect(worker.current_state != UnitBase.State.BUILDING, "completion leaves finished building safely")
		if worker.current_state == UnitBase.State.GATHERING:
			_expect(is_instance_valid(worker.gather_target) and worker.gather_target.get_instance_id() != lost_id, "completion reacquires a live visible resource")

func _resource(kind: String, owner: int) -> Node2D:
	for node: ResourceNode in _map.resource_nodes.values():
		if node.resource_type == kind and _map.is_resource_target_visible_to_player(node, owner): return node
	return null
