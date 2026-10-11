extends Node
## Real Main selected workers naturally travel to an edge. Runtime camera limits
## remain intact. Phone/safe-area presentation and camera inputs are controlled.
const OUTPUT := "res://output/evolution/camera-edge-20261010"
var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _pan_records: Array[Dictionary] = []
var _resize_records: Array[Dictionary] = []
var _render: bool = false
var _phase: String = "after"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	_render = "--render" in OS.get_cmdline_user_args()
	_phase = "before" if "--baseline" in OS.get_cmdline_user_args() else "after"
	DirAccess.make_dir_recursive_absolute(OUTPUT + "/" + _phase)
	GameManager.guided_opening_enabled = false
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		get_window().size = phone
		GameManager.ui_scale = 1.0
		GameManager.apply_preferences()
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
		var camera: Camera2D = game_map.get("camera")
		var selection: SelectionManager = game_map.get("selection_mgr")
		main.set_process(false)
		game_map.set_process(false)
		game_map.set("_touch_input_detected", true)
		(main.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
		var workers: Array[Node2D] = []
		for unit: Node in get_tree().get_nodes_in_group("units"):
			unit.set_process(false)
			if unit is Villager and (unit as Villager).player_owner == 0:
				(unit as Villager).command_stop()
				workers.append(unit as Node2D)
		selection.select_many(workers)
		# Direct real Main intent avoids the very HUD occlusion under test making
		# a corner tap impossible. Ordinary formation/nav/movement runs unchanged.
		var goal := Vector2i(MapData.MAP_WIDTH - 1, MapData.MAP_HEIGHT - 1)
		main.call("_on_move_command", goal)
		for worker: Node2D in workers:
			worker.set_process(true)
		Engine.time_scale = 4.0
		var deadline: float = GameManager.game_time + 120.0
		while GameManager.game_time < deadline:
			var all_arrived: bool = true
			for worker: Node2D in workers:
				all_arrived = all_arrived and (worker as UnitBase).current_state == UnitBase.State.IDLE and worker.global_position.distance_to((worker as UnitBase).move_target) < 5.0
			if all_arrived:
				break
			await get_tree().process_frame
		for worker: Node2D in workers:
			worker.set_process(false)
			_expect((worker as UnitBase).current_state == UnitBase.State.IDLE and worker.global_position.distance_to((worker as UnitBase).move_target) < 5.0, "normal worker must naturally arrive at accepted edge endpoint")
		main.call("_update_fog_of_war")
		main.call("_update_fog_entity_visibility")
		main.call("_update_minimap")
		for interface_scale: float in [1.0, 1.15]:
			GameManager.ui_scale = interface_scale
			GameManager.apply_preferences()
			for frame: int in range(3):
				await get_tree().process_frame
			var logical: Vector2 = get_viewport().get_visible_rect().size
			var pixel_scale: float = get_viewport().get_final_transform().x.length()
			var inset: float = 44.0 / pixel_scale if interface_scale > 1.0 else 0.0
			var bottom: float = 18.0 / pixel_scale if interface_scale > 1.0 else 0.0
			var safe := Rect2(Vector2(inset, 0.0), logical - Vector2(inset * 2.0, bottom))
			var hud: CanvasLayer = main.get("hud")
			main.call("_on_selection_changed", selection.selected)
			for zoom: float in [0.65, 1.0, 1.6]:
				game_map.call("_set_zoom_anchored", zoom, Vector2(-1.0, -1.0), Vector2(-1.0, -1.0), true)
				var revision: int = game_map.call("get_camera_interaction_revision")
				var center_event := InputEventAction.new()
				center_event.action = "center_selection"
				center_event.pressed = true
				get_viewport().push_input(center_event, true)
				camera.reset_smoothing()
				camera.force_update_scroll()
				for frame: int in range(3):
					await get_tree().process_frame
				# Selection can defer its own desktop-safe relayout. Apply the
				# synthetic notch only after that settles, then verify actual HUD.
				hud.call("apply_mobile_layout", logical, safe)
				await get_tree().process_frame
				var metrics: Dictionary = hud.get("mobile_layout_diagnostics")
				_expect(absf(float(metrics["safe_left"]) - safe.position.x) < 0.1 and absf(float(metrics["safe_right"]) - (logical.x - safe.end.x)) < 0.1, "capture must retain the supplied synthetic safe-area layout")
				var build_button: Control = hud.get("build_menu_button")
				_expect(safe.grow(0.5).encloses(build_button.get_global_rect()), "rendered Build control must remain within actual supplied safe-area rectangle")
				_expect(int(game_map.call("get_camera_interaction_revision")) == revision + 1, "real Center input increments interaction revision exactly once")
				var top: float = (hud.get_node("Root/TopBar") as Control).get_global_rect().end.y + 8.0
				var selection_panel: Control = hud.get("selection_panel")
				var field_bottom: float = minf(safe.end.y - 80.0, selection_panel.get_global_rect().position.y - 8.0)
				var field := Rect2(Vector2(safe.position.x + 8.0, top), Vector2(safe.size.x - 16.0, field_bottom - top))
				var visible: int = 0
				var bounds: Array[String] = []
				for worker: Node2D in workers:
					var projected: Rect2 = _visual_bounds(worker)
					bounds.append(str(projected))
					if field.grow(0.5).encloses(projected):
						visible += 1
				_expect(visible == workers.size(), "Center must fit all selected worker sprites/rings in playable field at %s scale%.2f zoom%.2f: %s in %s" % [phone, interface_scale, zoom, bounds, field])
				_records.append({"phone": str(phone), "ui_scale": interface_scale, "synthetic_notch": interface_scale > 1.0, "safe_area": str(safe), "hud_safe_left": metrics["safe_left"], "hud_safe_right": metrics["safe_right"], "build_control": str(build_button.get_global_rect()), "zoom": zoom, "field": str(field), "worker_bounds": bounds, "workers_fully_inside": visible, "workers": workers.size(), "desired_center": str(_worker_center(workers)), "target_focus": str(camera.position), "rendered_focus": str(camera.get_screen_center_position()), "physical_limits": [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]})
				if _render:
					await RenderingServer.frame_post_draw
					var bitmap: Image = get_viewport().get_texture().get_image()
					_expect(bitmap.get_size() == phone, "native capture must match phone pixels")
					bitmap.save_png(OUTPUT + "/" + _phase + "/%dx%d-scale%.2f-zoom%.2f-centered.png" % [phone.x, phone.y, interface_scale, zoom])
				_test_pan_edges(game_map, camera, phone, interface_scale, zoom)
		await _test_resize_limits(game_map, camera, phone)
		main.free()
		GameManager.set_state(GameManager.GameState.MENU)
		await get_tree().process_frame
	Engine.time_scale = 1.0
	var hashes: Dictionary = {}
	for path: String in ["scripts/map/game_map.gd", "scripts/map/map_generator.gd", "scripts/main/main.gd", "scripts/main/group_order_planner.gd", "scripts/ui/hud.gd", "scripts/units/unit_base.gd", "scripts/units/villager.gd", "tools/test_camera_map_edges.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	var mode: String = "native" if _render else "headless"
	var file := FileAccess.open(OUTPUT + "/" + _phase + "-" + mode + "-camera-edges.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "Real Main natural 4-worker corner arrival; actual Center input, keyboard pan via runtime handler; live window resize; all runtime limits intact. Synthetic phone/notch/layout; no physical-device or human result.", "source_sha256": hashes, "rendered": _render, "records": _records, "pan_records": _pan_records, "resize_records": _resize_records, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] camera_map_edges: " + failure)
	if _failures.is_empty():
		print("[PASS] camera_map_edges: 12 phone/scale/zoom Center profiles, all 4 map edges pannable, runtime limits intact")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _test_resize_limits(game_map: Node2D, camera: Camera2D, phone: Vector2i) -> void:
	var zoom: float = camera.zoom.x
	var revision: int = game_map.call("get_camera_interaction_revision")
	var original_focus: Vector2 = camera.position
	# An aspect change must produce different limits, rather than two nearly
	# identical phone aspect ratios coincidentally rounding to the same ints.
	var next_phone: Vector2i = Vector2i(932, 390) if phone.x == 844 else Vector2i(844, 430)
	var old_limits: Array[int] = [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]
	get_window().size = next_phone
	for frame: int in range(5):
		await get_tree().process_frame
	# Test actual resize notification without manually clamping/updating limits.
	var bounds: Rect2 = game_map.get("_camera_world_bounds")
	var half_view: Vector2 = game_map.call("_get_camera_half_view_world")
	var expected_limits: Array[int] = [floori(bounds.position.x - half_view.x), floori(bounds.position.y - half_view.y), ceili(bounds.end.x + half_view.x), ceili(bounds.end.y + half_view.y)]
	var actual_limits: Array[int] = [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]
	_expect(old_limits != expected_limits, "resize fixture must actually change the logical view extents")
	_expect(actual_limits == expected_limits, "live phone resize must refresh all physical limits without subsequent pan")
	_expect(absf(camera.zoom.x - zoom) < 0.001, "live resize preserves deliberate zoom")
	_expect(int(game_map.call("get_camera_interaction_revision")) == revision, "automatic resize does not impersonate user interaction")
	_expect(camera.position.distance_to(original_focus) < 1.1, "live resize preserves existing focus")
	_resize_records.append({"from_phone": str(phone), "to_phone": str(next_phone), "zoom": camera.zoom.x, "expected_limits": expected_limits, "actual_limits": actual_limits, "focus_drift": camera.position.distance_to(original_focus)})
	get_window().size = phone
	for frame: int in range(5):
		await get_tree().process_frame
	# Preferences change logical viewport size without resizing the window.
	GameManager.ui_scale = 1.0
	GameManager.apply_preferences()
	for frame: int in range(5):
		await get_tree().process_frame
	half_view = game_map.call("_get_camera_half_view_world")
	expected_limits = [floori(bounds.position.x - half_view.x), floori(bounds.position.y - half_view.y), ceili(bounds.end.x + half_view.x), ceili(bounds.end.y + half_view.y)]
	actual_limits = [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]
	_expect(actual_limits == expected_limits, "live interface-scale change must refresh all physical limits without subsequent pan/zoom")
	_resize_records.append({"phone": str(phone), "ui_scale_change": "1.15 to 1.0", "expected_limits": expected_limits, "actual_limits": actual_limits})

func _test_pan_edges(game_map: Node2D, camera: Camera2D, phone: Vector2i, interface_scale: float, zoom: float) -> void:
	var bounds: Rect2 = game_map.get("_camera_world_bounds")
	var edge_cases: Array[Dictionary] = [{"action": "camera_up", "focus": Vector2(0.0, bounds.position.y)}, {"action": "camera_down", "focus": Vector2(0.0, bounds.end.y)}, {"action": "camera_left", "focus": Vector2(bounds.position.x, bounds.get_center().y)}, {"action": "camera_right", "focus": Vector2(bounds.end.x, bounds.get_center().y)}]
	for edge: Dictionary in edge_cases:
		camera.position = bounds.get_center()
		Input.action_press(edge["action"])
		game_map.call("_update_camera_pan", 100.0)
		Input.action_release(edge["action"])
		camera.reset_smoothing()
		camera.force_update_scroll()
		var error: float = camera.get_screen_center_position().distance_to(edge["focus"])
		_expect(error < 1.1, "runtime pan must reach legal %s focus (error%.2f)" % [edge["action"], error])
		_pan_records.append({"phone": str(phone), "ui_scale": interface_scale, "zoom": zoom, "action": edge["action"], "focus_error": error})

func _worker_center(workers: Array[Node2D]) -> Vector2:
	var center := Vector2.ZERO
	for worker: Node2D in workers:
		center += worker.global_position
	return center / float(workers.size())

func _visual_bounds(subject: Node2D) -> Rect2:
	var projected: Rect2 = subject.get_global_transform_with_canvas() * Rect2(-14.0, -14.0, 28.0, 28.0)
	for child: Node in subject.get_children():
		if child is Sprite2D:
			var sprite := child as Sprite2D
			if sprite.texture != null:
				var used: Rect2i = sprite.texture.get_image().get_used_rect()
				projected = projected.merge(sprite.get_global_transform_with_canvas() * Rect2(sprite.get_rect().position + Vector2(used.position), Vector2(used.size)))
	return projected

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
