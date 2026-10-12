extends Node
## Real Main and natural four-worker movement, with actual phone touch dispatch.
## AI decisions pause to isolate the order. No unit positions or map edits here.

const OUTPUT := "res://output/evolution/group-movement-20261010"
var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _captures: Array[Dictionary] = []
var _render: bool = false
var _loaded_source_hashes: Dictionary = {}

const CAPTURE_SOURCES: Array[String] = ["scripts/main/main.gd", "scripts/main/group_order_planner.gd", "scripts/map/game_map.gd", "scripts/map/pathfinding.gd", "scripts/managers/selection_manager.gd", "scripts/managers/game_manager.gd", "scripts/units/unit_base.gd", "scripts/units/villager.gd", "scripts/ui/hud.gd", "scripts/ui/command_path_overlay.gd", "tools/test_group_order_endpoints.gd"]

func _ready() -> void:
	for path: String in CAPTURE_SOURCES:
		_loaded_source_hashes[path] = FileAccess.get_sha256("res://" + path)
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_render = "--render" in OS.get_cmdline_user_args()
	if _render and DisplayServer.get_name() == "headless":
		push_error("Native group captures require a renderer; omit --headless")
		get_tree().quit(1)
		return
	if _render:
		DirAccess.make_dir_recursive_absolute(OUTPUT + "/native")
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	GameManager.ui_scale = 1.0
	GameManager.apply_preferences()
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		get_window().size = phone
		GameManager.set_state(GameManager.GameState.MENU)
		GameManager.selected_map_seed = 202
		GameManager.selected_population_limit = 30
		var main: Node = load("res://scenes/main/main.tscn").instantiate()
		add_child(main)
		for frame: int in range(900):
			if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
				break
			await get_tree().process_frame
		var game_map: Node2D = main.get("game_map")
		var selection: SelectionManager = game_map.get("selection_mgr")
		main.set_process(false)
		game_map.set_process(false)
		(main.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
		var workers: Array[Node2D] = []
		for unit: Node in get_tree().get_nodes_in_group("units"):
			unit.set_process(false)
			if unit is Villager and (unit as Villager).player_owner == 0:
				(unit as Villager).command_stop()
				workers.append(unit as Node2D)
		selection.select_many(workers)
		var received_orders: Array[Vector2i] = []
		selection.move_command.connect(func(tile: Vector2i) -> void: received_orders.append(tile))
		var goal := Vector2i(MapData.MAP_WIDTH - 1, MapData.MAP_HEIGHT - 1)
		var camera: Camera2D = game_map.get("camera")
		camera.position = game_map.tile_to_world(goal)
		camera.reset_smoothing()
		camera.force_update_scroll()
		await get_tree().process_frame
		await get_tree().process_frame
		main.call("_arm_move_command")
		var screen: Vector2 = get_viewport().get_final_transform() * get_viewport().get_canvas_transform() * game_map.tile_to_world(goal)
		for pressed: bool in [true, false]:
			var tap := InputEventScreenTouch.new()
			tap.index = 7
			tap.position = screen
			tap.pressed = pressed
			Input.parse_input_event(tap)
			await get_tree().process_frame
		_expect(received_orders.size() == 1 and received_orders[0] == goal, "phone touch must dispatch exactly the requested corner tile")
		var destinations: Array[String] = []
		var unique: Dictionary = {}
		for worker: Node2D in workers:
			var unit := worker as UnitBase
			destinations.append(str(game_map.world_to_tile(unit.move_target)))
			unique[unit.move_target] = true
			_expect(bool(unit.get("_force_move_active")), "actual group Move must retain no-engagement intent")
			unit.set_process(true)
		_expect(unique.size() == workers.size(), "corner group order must allocate distinct destinations rather than clamp everyone onto one tile")
		Engine.time_scale = 4.0
		var deadline: float = GameManager.game_time + 100.0
		var approach_captured: bool = false
		while GameManager.game_time < deadline:
			var all_arrived: bool = true
			var all_near: bool = true
			for worker: Node2D in workers:
				all_arrived = all_arrived and (worker as UnitBase).current_state == UnitBase.State.IDLE
				all_near = all_near and worker.global_position.distance_to(game_map.tile_to_world(goal)) <= 96.0
			if _render and all_near and not all_arrived and not approach_captured:
				await _capture_native(main, game_map, workers, phone, "approach")
				approach_captured = true
			if all_arrived:
				break
			await get_tree().process_frame
		var arrived: int = 0
		var min_separation: float = INF
		for i: int in workers.size():
			var unit := workers[i] as UnitBase
			if unit.current_state == UnitBase.State.IDLE and unit.global_position.distance_to(unit.move_target) <= 5.0:
				arrived += 1
			for j: int in range(i + 1, workers.size()):
				min_separation = minf(min_separation, unit.global_position.distance_to(workers[j].global_position))
		_expect(arrived == workers.size(), "every starting worker must naturally arrive at its accepted group endpoint")
		_expect(min_separation >= 24.0, "arriving group must remain individually readable instead of stacking sprites")
		if _render:
			_expect(approach_captured, "native fixture must capture an actual moving approach")
			await _capture_native(main, game_map, workers, phone, "arrived")
		var goals_before_repeat: Array[Vector2] = []
		for worker: Node2D in workers:
			goals_before_repeat.append((worker as UnitBase).move_target)
		main.call("_arm_move_command")
		screen = get_viewport().get_final_transform() * get_viewport().get_canvas_transform() * game_map.tile_to_world(goal)
		for pressed: bool in [true, false]:
			var tap := InputEventScreenTouch.new()
			tap.index = 19
			tap.position = screen
			tap.pressed = pressed
			Input.parse_input_event(tap)
			await get_tree().process_frame
		_expect(received_orders.size() == 2 and received_orders[1] == goal, "repeated corner touch must dispatch the same destination exactly once")
		var repeated_goal_changes: int = 0
		for i: int in workers.size():
			if (workers[i] as UnitBase).move_target != goals_before_repeat[i]:
				repeated_goal_changes += 1
		_expect(repeated_goal_changes == 0, "repeating an arrived formation order must retain each legal occupied slot")
		_records.append({"phone": str(phone), "input": "Input.parse_input_event contacts7/19", "dispatched_tiles": str(received_orders), "workers": workers.size(), "target": str(goal), "destinations": destinations, "unique_destinations": unique.size(), "natural_arrivals": arrived, "minimum_arrival_separation": min_separation, "repeated_goal_changes": repeated_goal_changes})
		main.free()
		GameManager.set_state(GameManager.GameState.MENU)
		await get_tree().process_frame
	Engine.time_scale = 1.0
	var phase: String = "before" if "--baseline" in OS.get_cmdline_user_args() else "after"
	if "--repeat-baseline" in OS.get_cmdline_user_args():
		phase = "repeat-first-candidate"
	if _render:
		phase = "native"
	var file := FileAccess.open(OUTPUT + "/" + phase + "-phone-worker-orders.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "Normal starting workers; actual phone touch; seeded natural navigation and arrival; no synthetic unit/map positions.", "records": _records, "failures": _failures}, "  "))
	if _render:
		for path: String in CAPTURE_SOURCES:
			_expect(_loaded_source_hashes[path] == FileAccess.get_sha256("res://" + path), "loaded native sources must remain unchanged throughout capture: " + path)
		var manifest := FileAccess.open(OUTPUT + "/native/manifest.json", FileAccess.WRITE)
		manifest.store_string(JSON.stringify({"scope": "Native exact phone captures after actual touch and natural navigation of normal starting workers. Actual Center input and canonical runtime zoom frame the selection; all runtime Camera2D limits remain intact. Synthetic safe-area presentation is controlled. UI scales1/1.15, zoom0.62/1.25/2.0; no injected units or movement positions, no physical-device claim.", "source_sha256": _loaded_source_hashes, "captures": _captures, "orders": _records, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] group_order_endpoints: " + failure)
	if _failures.is_empty():
		print("[PASS] group_order_endpoints: actual phone group Move assigns distinct reachable endpoints and every starting worker arrives with readable spacing")
	AudioManager.stop_all()
	# Let the mixer release stopped playback before process teardown.
	await get_tree().create_timer(0.15, true, false, true).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _capture_native(main: Node, game_map: Node2D, workers: Array[Node2D], phone: Vector2i, state: String) -> void:
	for worker: Node2D in workers:
		worker.set_process(false)
	var camera: Camera2D = game_map.get("camera")
	var old_position: Vector2 = camera.position
	var old_zoom: Vector2 = camera.zoom
	var hud: CanvasLayer = main.get("hud")
	var overlay: Node2D = game_map.get_node("CommandPaths")
	main.call("_update_fog_of_war")
	main.call("_update_fog_entity_visibility")
	main.call("_update_minimap")
	for interface_scale: float in [1.0, 1.15]:
		GameManager.ui_scale = interface_scale
		GameManager.apply_preferences()
		for frame: int in range(3):
			await get_tree().process_frame
		var logical: Vector2 = get_viewport().get_visible_rect().size
		var physical_scale: float = get_viewport().get_final_transform().x.length()
		var inset: float = 44.0 / physical_scale if interface_scale > 1.0 else 0.0
		var bottom: float = 18.0 / physical_scale if interface_scale > 1.0 else 0.0
		var safe := Rect2(Vector2(inset, 0.0), logical - Vector2(inset * 2.0, bottom))
		for zoom: float in [0.62, 1.25, 2.0]:
			main.call("_on_selection_changed", game_map.selection_mgr.selected)
			hud.call("apply_mobile_layout", logical, safe)
			game_map.call("_set_zoom_anchored", zoom, Vector2(-1.0, -1.0), Vector2(-1.0, -1.0), true)
			var revision: int = game_map.call("get_camera_interaction_revision")
			var center_event := InputEventAction.new()
			center_event.action = "center_selection"
			center_event.pressed = true
			get_viewport().push_input(center_event, true)
			_expect(int(game_map.call("get_camera_interaction_revision")) == revision + 1, "native actual Center input must dispatch exactly once")
			camera.reset_smoothing()
			camera.force_update_scroll()
			overlay.queue_redraw()
			for frame: int in range(3):
				await get_tree().process_frame
			# Selection refresh schedules normal device layout. Set the synthetic
			# presentation only after those deferred refreshes have settled.
			hud.call("apply_mobile_layout", logical, safe)
			await RenderingServer.frame_post_draw
			var metrics: Dictionary = hud.get("mobile_layout_diagnostics")
			_expect(is_equal_approx(float(metrics.get("safe_left", -1.0)), inset) and is_equal_approx(float(metrics.get("safe_bottom", -1.0)), bottom), "rendered synthetic safe-area layout must persist through capture")
			var field_top: float = (hud.get_node("Root/TopBar") as Control).get_global_rect().end.y + 8.0
			var field_bottom: float = (hud.get("selection_panel") as Control).get_global_rect().position.y - 8.0
			var field := Rect2(Vector2(safe.position.x + 8.0, field_top), Vector2(safe.size.x - 16.0, field_bottom - field_top))
			var worker_bounds: Array[String] = []
			for worker: Node2D in workers:
				var visual_bounds: Rect2 = _visual_bounds(worker)
				worker_bounds.append(str(visual_bounds))
				_expect(field.grow(0.5).encloses(visual_bounds), "actual centered worker sprite/ring must fit above phone selection HUD")
			var bitmap: Image = get_viewport().get_texture().get_image()
			_expect(bitmap.get_size() == phone, "native image must match actual phone pixel size")
			var filename: String = "%dx%d-scale%.2f-zoom%.2f-%s.png" % [phone.x, phone.y, interface_scale, zoom, state]
			bitmap.save_png(OUTPUT + "/native/" + filename)
			var routes: Array[Dictionary] = overlay.call("get_display_routes")
			if state == "approach":
				_expect(not routes.is_empty(), "approaching natural group must display its accepted navigation route")
			_captures.append({"image": filename, "phone": str(phone), "pixels": str(bitmap.get_size()), "ui_scale": interface_scale, "synthetic_notch": interface_scale > 1.0, "safe_area": str(safe), "safe_area_preserved": is_equal_approx(float(metrics.get("safe_left", -1.0)), inset), "worker_visual_bounds": worker_bounds, "playable_field": str(field), "zoom": zoom, "state": state, "display_routes": routes.size(), "physical_camera_limits": [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom], "selection_details": (hud.get("selection_details") as Label).text})
			print("GROUP_NATIVE_CAPTURE ", filename)
	GameManager.ui_scale = 1.0
	GameManager.apply_preferences()
	game_map.call("_set_zoom_anchored", old_zoom.x, Vector2(-1.0, -1.0), Vector2(-1.0, -1.0), false)
	camera.position = old_position
	game_map.call("_clamp_camera")
	camera.reset_smoothing()
	camera.force_update_scroll()
	for frame: int in range(3):
		await get_tree().process_frame
	hud.call("apply_mobile_layout", get_viewport().get_visible_rect().size, Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size))
	for worker: Node2D in workers:
		worker.set_process(true)


func _visual_bounds(subject: Node2D) -> Rect2:
	var unit := subject as UnitBase
	var size: float = float(UnitBase.UNIT_SIZES.get(unit.unit_type, 10.0))
	# Measure UnitBase._draw's ground ellipse and stroke, not a full ground
	# circle that would add invisible padding below this isometric worker.
	var stroke: float = 1.5 if unit.is_selected else 0.8
	var ring := Rect2(Vector2(-size - 1.0 - stroke, 3.0 - size * 0.48 - stroke), Vector2((size + 1.0 + stroke) * 2.0, (size * 0.48 + stroke) * 2.0))
	var projected: Rect2 = subject.get_global_transform_with_canvas() * ring
	if unit.is_selected or unit.hp < unit.max_hp:
		var bar_y: float = -(size + 12.0) if unit.unit_type == UnitData.UnitType.VILLAGER else -43.0
		projected = projected.merge(subject.get_global_transform_with_canvas() * Rect2(-size * 1.25, bar_y, size * 2.5, 3.0))
	if unit.hp > 0.0 and unit.hp / unit.max_hp < 0.25:
		var critical_radius: float = size + 4.0
		projected = projected.merge(subject.get_global_transform_with_canvas() * Rect2(Vector2.ONE * -critical_radius, Vector2.ONE * critical_radius * 2.0))
	for child: Node in subject.get_children():
		if child is Sprite2D:
			var sprite := child as Sprite2D
			if sprite.texture != null and sprite.is_visible_in_tree():
				var used: Rect2i = sprite.texture.get_image().get_used_rect()
				projected = projected.merge(sprite.get_global_transform_with_canvas() * Rect2(sprite.get_rect().position + Vector2(used.position), Vector2(used.size)))
	return projected
