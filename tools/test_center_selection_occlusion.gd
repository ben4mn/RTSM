extends Node
## Actual Center dispatch in real Main/HUD, with controlled real worker movement.
## AOEM_CAPTURE_CENTER_DIR optionally records native images; headless is default.
const OUTPUT := "res://output/evolution/ux-redesign-20261011/center"
var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _capture_dir: String = ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	_capture_dir = OS.get_environment("AOEM_CAPTURE_CENTER_DIR")
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		await _test_phone(phone)
	GameManager.ui_scale = 1.0
	GameManager.apply_preferences()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var hashes: Dictionary = {}
	for path: String in ["scripts/map/game_map.gd", "scripts/main/main.gd", "scripts/ui/hud.gd", "scripts/units/unit_base.gd", "scripts/units/villager.gd", "tools/test_center_selection_occlusion.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	var receipt := FileAccess.open(OUTPUT + "/" + ("native" if not _capture_dir.is_empty() else "headless") + "-receipt.json", FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"scope": "Real Main/HUD and actual Center InputEventAction; four normal starting workers marched to legal map edge, then pose-controlled movement/arrival across phone/UI/synthetic-notch profiles. Buildings, spread group, live resize and legal camera bounds. No physical phone or human feel claim.", "source_sha256": hashes, "records": _records, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] center_selection_occlusion: " + failure)
	if _failures.is_empty():
		print("[PASS] center_selection_occlusion: %d actual Center cases, complete moving/arrival rings, visible HUD obstacles, zoom preservation/fallback and live resize" % _records.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_phone(phone: Vector2i) -> void:
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
	var hud: CanvasLayer = main.get("hud")
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
	main.call("_on_move_command", Vector2i(MapData.MAP_WIDTH - 1, MapData.MAP_HEIGHT - 1))
	for tick: int in range(60 * 150):
		var arrived: bool = true
		for worker: Node2D in workers:
			worker.call("_process", 1.0 / 60.0)
			arrived = arrived and (worker as UnitBase).current_state == UnitBase.State.IDLE
		if arrived:
			break
	var arrival_positions: Array[Vector2] = []
	for worker: Node2D in workers:
		arrival_positions.append(worker.global_position)
		_expect((worker as UnitBase).current_state == UnitBase.State.IDLE, "normal movement must reach the map-edge fixture")
	main.call("_on_move_command", Vector2i(MapData.MAP_WIDTH - 6, MapData.MAP_HEIGHT - 6))
	for tick: int in range(15):
		for worker: Node2D in workers:
			worker.call("_process", 1.0 / 60.0)
	var moving_positions: Array[Vector2] = []
	for worker: Node2D in workers:
		moving_positions.append(worker.global_position)
		_expect((worker as UnitBase).current_state == UnitBase.State.MOVING, "approach fixture contains actual moving workers")
	for scale_value: float in [1.0, 1.075, 1.15]:
		GameManager.ui_scale = scale_value
		GameManager.apply_preferences()
		for frame: int in range(3):
			await get_tree().process_frame
		for notched: bool in [false, true]:
			var logical: Vector2 = get_viewport().get_visible_rect().size
			var pixel_scale: float = get_viewport().get_final_transform().x.length()
			var inset: float = 44.0 / pixel_scale if notched else 0.0
			var bottom: float = 18.0 / pixel_scale if notched else 0.0
			var safe := Rect2(Vector2(inset, 0.0), logical - Vector2(inset * 2.0, bottom))
			for pose: String in ["moving", "arrival"]:
				var positions: Array[Vector2] = moving_positions if pose == "moving" else arrival_positions
				for index: int in workers.size():
					workers[index].global_position = positions[index]
					(workers[index] as UnitBase).current_state = UnitBase.State.MOVING if pose == "moving" else UnitBase.State.IDLE
				main.call("_update_fog_of_war")
				main.call("_update_fog_entity_visibility")
				main.call("_update_minimap")
				selection.select_many(workers)
				main.call("_on_selection_changed", selection.selected)
				for frame: int in range(3):
					await get_tree().process_frame
				for zoom_name: String in ["overview", "default", "2x", "detail"]:
					var zoom_state: Dictionary = game_map.call("get_zoom_state")
					var zoom: float = float(zoom_state["min"]) if zoom_name == "overview" else float(zoom_state["default"])
					if zoom_name == "2x":
						zoom = 2.0
					elif zoom_name == "detail":
						zoom = float(zoom_state["max"])
					hud.call("apply_mobile_layout", logical, safe)
					await get_tree().process_frame
					game_map.call("_set_zoom_anchored", zoom, Vector2(-1.0, -1.0), Vector2(-1.0, -1.0), true)
					camera.position = Vector2.ZERO
					game_map.call("_clamp_camera")
					var prefix: String = "%dx%d-scale%.3f-%s-%s-%s" % [phone.x, phone.y, scale_value, "notch" if notched else "full", pose, zoom_name]
					var preserve_zoom: bool = _has_preservation_witness(main, workers, zoom)
					await _center_and_check(main, workers, prefix, true)
					if preserve_zoom:
						_expect(absf(camera.zoom.x - zoom) < 0.001, prefix + " fitting group preserves manual zoom")
					else:
						_expect(camera.zoom.x <= zoom + 0.001, prefix + " Center only reduces detail when framing needs it")
			# A single moving worker fits the Large/notched 2x corridor. This
			# explicitly protects the manual zoom case beside the group fallback.
			selection.select_single(workers[0])
			main.call("_on_selection_changed", selection.selected)
			for frame: int in range(3):
				await get_tree().process_frame
			hud.call("apply_mobile_layout", logical, safe)
			await get_tree().process_frame
			game_map.call("_set_zoom_anchored", 2.0, Vector2(-1.0, -1.0), Vector2(-1.0, -1.0), true)
			await _center_and_check(main, [workers[0]], "%dx%d-scale%.3f-%s-single-2x" % [phone.x, phone.y, scale_value, "notch" if notched else "full"], true)
			_expect(absf(camera.zoom.x - 2.0) < 0.001, "fitting single worker preserves deliberate 2x zoom")
			if notched and is_equal_approx(scale_value, 1.15):
				var view_button: Control = hud.get("_camera_view_button")
				await _tap_control(view_button)
				for frame: int in range(3):
					await get_tree().process_frame
				hud.call("apply_mobile_layout", logical, safe)
				await get_tree().process_frame
				var center_button: Control = hud.get("_camera_center_button")
				_expect(center_button.is_visible_in_tree() and not (center_button as Button).disabled, "Center is reachable through View on Large/notched phone")
				var old_target: Vector2 = (workers[0] as UnitBase).move_target
				var old_selection: Array[Node2D] = selection.selected.duplicate()
				await _center_and_check(main, [workers[0]], "%dx%d-large-notch-touch-center" % [phone.x, phone.y], true, center_button)
				_expect(selection.selected == old_selection and (workers[0] as UnitBase).move_target == old_target, "Center/View touch emits no world order and preserves selection")
				_expect(absf(camera.zoom.x - 2.0) < 0.001, "touch Center preserves fitting manual 2x zoom")
				await _tap_control(view_button)
				for frame: int in range(3):
					await get_tree().process_frame
				for overlay_case: String in ["build-overlay", "help-overlay"]:
					var shortcut: int = KEY_B if overlay_case == "build-overlay" else KEY_F2
					get_viewport().gui_release_focus()
					_dispatch_key(shortcut)
					for frame: int in range(3):
						await get_tree().process_frame
					hud.call("apply_mobile_layout", logical, safe)
					await get_tree().process_frame
					var overlay: Control = hud.get_node("BuildMenu") as Control if overlay_case == "build-overlay" else hud.get("_hotkey_panel") as Control
					_expect(overlay.is_visible_in_tree(), overlay_case + " opens through its real keyboard shortcut")
					var obstacle_present: bool = false
					for obstacle: Rect2 in hud.call("get_world_occlusion_rects"):
						if obstacle.position.distance_to(overlay.get_global_rect().position) < 0.1 and obstacle.size.distance_to(overlay.get_global_rect().size) < 0.1:
							obstacle_present = true
					_expect(obstacle_present, overlay_case + " exposes the actual visible panel rectangle to Center")
					game_map.call("_set_zoom_anchored", 2.0, Vector2(-1.0, -1.0), Vector2(-1.0, -1.0), true)
					var preserve_zoom: bool = _has_preservation_witness(main, [workers[0]], 2.0)
					get_viewport().gui_release_focus()
					await _center_and_check(main, [workers[0]], "%dx%d-large-notch-%s" % [phone.x, phone.y, overlay_case], true, null, true)
					var selected_pixels: Rect2 = get_viewport().get_canvas_transform() * _rendered_world_bounds(workers[0])
					_expect(not selected_pixels.intersects(overlay.get_global_rect().grow(5.5)), overlay_case + " independently measured selected artwork clears the visible panel")
					_expect(overlay.is_visible_in_tree(), overlay_case + " Center preserves the open overlay")
					if preserve_zoom:
						_expect(absf(camera.zoom.x - 2.0) < 0.001, overlay_case + " preserves feasible deliberate 2x zoom")
					_expect(selection.selected == old_selection and (workers[0] as UnitBase).move_target == old_target, overlay_case + " keyboard Center preserves selection and world order")
					_dispatch_key(shortcut)
					for frame: int in range(3):
						await get_tree().process_frame
					_expect(not overlay.is_visible_in_tree(), overlay_case + " closes through its real keyboard shortcut")
			# Center of a selected Town Center includes its roof, flag and complete
			# diamond. Large detail may require fitting, unlike the worker group.
			var tc: BuildingBase = main.get("_player_town_center")
			selection.select_single(tc)
			main.call("_on_selection_changed", selection.selected)
			for frame: int in range(3):
				await get_tree().process_frame
			hud.call("apply_mobile_layout", logical, safe)
			await get_tree().process_frame
			game_map.call("_set_zoom_anchored", 2.0, Vector2(-1.0, -1.0), Vector2(-1.0, -1.0), true)
			await _center_and_check(main, [tc], "%dx%d-scale%.3f-%s-building" % [phone.x, phone.y, scale_value, "notch" if notched else "full"], true)
	# Spread members are a controlled visibility fixture, not an economy grant.
	selection.select_many(workers)
	var map_bounds: Rect2 = game_map.get("_camera_world_bounds")
	for index: int in workers.size():
		workers[index].global_position = map_bounds.get_center() + Vector2(-280.0 + index * 185.0, float(index % 2) * 25.0)
	main.call("_update_fog_of_war")
	main.call("_update_fog_entity_visibility")
	main.call("_update_minimap")
	main.call("_on_selection_changed", selection.selected)
	for frame: int in range(3):
		await get_tree().process_frame
	var logical: Vector2 = get_viewport().get_visible_rect().size
	hud.call("apply_mobile_layout", logical, Rect2(Vector2.ZERO, logical))
	await get_tree().process_frame
	game_map.call("_set_zoom_anchored", 2.0, Vector2(-1.0, -1.0), Vector2(-1.0, -1.0), true)
	await _center_and_check(main, workers, "%dx%d-spread" % [phone.x, phone.y], true)
	_expect(camera.zoom.x < 1.5 and camera.zoom.x >= float(game_map.call("get_zoom_state")["min"]), "spread selection uses a legal useful overview fallback")
	var chosen_zoom: float = camera.zoom.x
	get_window().size = Vector2i(932, 390) if phone.x == 844 else Vector2i(844, 430)
	for frame: int in range(5):
		await get_tree().process_frame
	_expect(absf(camera.zoom.x - chosen_zoom) < 0.001, "live resize preserves the chosen fit zoom")
	await _center_and_check(main, workers, "%dx%d-live-resize" % [phone.x, phone.y], true)
	selection.deselect_all()
	var empty_revision: int = game_map.call("get_camera_interaction_revision")
	_dispatch_center()
	_expect(int(game_map.call("get_camera_interaction_revision")) == empty_revision, "empty Center does not move or create an interaction")
	main.free()
	GameManager.set_state(GameManager.GameState.MENU)
	await get_tree().process_frame


func _center_and_check(main: Node, subjects: Array[Node2D], prefix: String, capture: bool, button: Control = null, keyboard: bool = false) -> void:
	var game_map: Node2D = main.get("game_map")
	var hud: CanvasLayer = main.get("hud")
	var camera: Camera2D = game_map.get("camera")
	var revision: int = game_map.call("get_camera_interaction_revision")
	var old_zoom: float = camera.zoom.x
	if keyboard:
		_dispatch_key(KEY_SPACE)
	elif button == null:
		_dispatch_center()
	else:
		await _tap_control(button)
	_expect(int(game_map.call("get_camera_interaction_revision")) == revision + 1, prefix + " actual Center is dispatched once")
	await get_tree().process_frame
	var safe: Rect2 = hud.call("get_world_safe_rect")
	var obstacles: Array[Rect2] = hud.call("get_world_occlusion_rects")
	var bounds: Array[String] = []
	var framing_bounds: Array[String] = []
	for subject: Node2D in subjects:
		_expect(subject.is_visible_in_tree(), prefix + " selected subject is actually visible")
		var tile: Vector2i = game_map.call("world_to_tile", subject.global_position)
		_expect((game_map.get("fog_of_war") as FogManager).is_tile_visible(tile), prefix + " current fog reveals the rendered subject")
		var world: Rect2 = main.call("_get_camera_subject_bounds", subject)
		var rendered: Rect2 = _rendered_world_bounds(subject)
		_expect(world.grow(0.1).encloses(rendered), prefix + " framing includes independently measured art, ring, flag and HP")
		var projected: Rect2 = get_viewport().get_canvas_transform() * rendered
		bounds.append(str(projected))
		framing_bounds.append(str(get_viewport().get_canvas_transform() * world))
		_expect(safe.grow(-7.5).encloses(projected), prefix + " complete sprite/ring stays in safe terrain: " + str(projected))
		for obstacle: Rect2 in obstacles:
			_expect(not projected.intersects(obstacle.grow(5.5)), prefix + " complete sprite/ring clears visible HUD: " + str(obstacle))
	var legal: Rect2 = game_map.get("_camera_world_bounds")
	_expect(legal.grow(0.01).has_point(camera.position), prefix + " retains legal map focus")
	_records.append({"case": prefix, "old_zoom": old_zoom, "zoom": camera.zoom.x, "safe": str(safe), "bounds": bounds, "framing_bounds": framing_bounds, "obstacles": obstacles.map(func(rect: Rect2) -> String: return str(rect)), "focus": str(camera.position), "rendered_focus": str(camera.get_screen_center_position())})
	if capture and not _capture_dir.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(prefix + ".png"))


func _dispatch_center() -> void:
	var event := InputEventAction.new()
	event.action = "center_selection"
	event.pressed = true
	get_viewport().push_input(event, true)
	event = InputEventAction.new()
	event.action = "center_selection"
	event.pressed = false
	get_viewport().push_input(event, true)


func _dispatch_key(keycode: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event, true)


func _tap_control(control: Control) -> void:
	_expect(control.size.x >= 47.5 and control.size.y >= 47.5, control.name + " has a generous touch target")
	var position: Vector2 = get_viewport().get_final_transform() * control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 9
		touch.position = position
		touch.pressed = pressed
		Input.parse_input_event(touch)
		await get_tree().process_frame
		await get_tree().process_frame


func _has_preservation_witness(main: Node, subjects: Array[Node2D], zoom: float) -> bool:
	# Independent coarse screen sampling supplies a constructive witness. A
	# sampled clear placement at this exact zoom makes shrinking unacceptable.
	# It does not require the runtime boundary sweep or its preferred focus.
	var hud: CanvasLayer = main.get("hud")
	var game_map: Node2D = main.get("game_map")
	var safe: Rect2 = (hud.call("get_world_safe_rect") as Rect2).grow(-8.0)
	var obstacles: Array[Rect2] = hud.call("get_world_occlusion_rects")
	var envelope: Rect2 = main.call("_get_camera_subject_bounds", subjects[0])
	for subject: Node2D in subjects:
		envelope = envelope.merge(main.call("_get_camera_subject_bounds", subject))
	var size: Vector2 = envelope.size * zoom
	if size.x > safe.size.x or size.y > safe.size.y:
		return false
	var legal: Rect2 = game_map.get("_camera_world_bounds")
	var viewport_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	for screen_x: int in range(ceili(safe.position.x + size.x * 0.5), floori(safe.end.x - size.x * 0.5) + 1, 8):
		for screen_y: int in range(ceili(safe.position.y + size.y * 0.5), floori(safe.end.y - size.y * 0.5) + 1, 8):
			var screen_center := Vector2(screen_x, screen_y)
			var focus: Vector2 = envelope.get_center() + (viewport_center - screen_center) / zoom
			if not legal.has_point(focus):
				continue
			var projection := Transform2D(0.0, Vector2(zoom, zoom), 0.0, viewport_center - focus * zoom)
			var clear: bool = true
			for subject: Node2D in subjects:
				var projected: Rect2 = projection * (main.call("_get_camera_subject_bounds", subject) as Rect2)
				for obstacle: Rect2 in obstacles:
					if projected.intersects(obstacle.grow(6.0)):
						clear = false
						break
				if not clear:
					break
			if clear:
				return true
	return false


func _rendered_world_bounds(subject: Node2D) -> Rect2:
	# Read opaque pixels and reproduce the visible marker extents independently
	# of the new camera/visual-bounds helper so missing rings cannot self-pass.
	var bounds := Rect2(subject.global_position - Vector2(1.0, 1.0), Vector2(2.0, 2.0))
	if subject is UnitBase:
		var unit := subject as UnitBase
		var radius: float = float(UnitBase.UNIT_SIZES.get(unit.unit_type, 10.0))
		bounds = subject.get_global_transform() * Rect2(-radius - 2.5, 1.5 - radius * 0.48, radius * 2.0 + 5.0, radius * 0.96 + 3.0)
		if unit.is_selected or unit.hp < unit.max_hp:
			var health_y: float = float(unit.get("_health_bar_y"))
			bounds = bounds.merge(subject.get_global_transform() * Rect2(-radius * 1.25, health_y, radius * 2.5, 3.0))
		if unit.stance == UnitBase.Stance.STAND_GROUND:
			bounds = bounds.merge(subject.get_global_transform() * Rect2(radius + 0.5, -6.5, 7.0, 9.0))
		if unit is Villager and (unit.current_state == UnitBase.State.GATHERING or (unit as Villager).carried_amount > 0):
			bounds = bounds.merge(subject.get_global_transform() * Rect2(radius - 2.0, -6.0, 12.0, 12.0))
	elif subject is BuildingBase:
		var building := subject as BuildingBase
		var footprint := Vector2(building.footprint.x * MapData.TILE_WIDTH, building.footprint.y * MapData.TILE_HEIGHT)
		if building.is_selected:
			bounds = bounds.merge(subject.get_global_transform() * Rect2(-footprint * 0.5, footprint).grow(1.8))
		if building.building_type == BuildingData.BuildingType.TOWN_CENTER:
			bounds = bounds.merge(subject.get_global_transform() * Rect2(47.0, -79.0, 26.0, 45.0))
		if building.state == BuildingBase.State.CONSTRUCTING or building.hp < building.max_hp:
			bounds = bounds.merge(subject.get_global_transform() * Rect2(-footprint.x * 0.3, -footprint.y * 0.5 - 8.0, footprint.x * 0.6, 6.0))
	for child: Node in subject.get_children():
		if child is Sprite2D:
			var sprite := child as Sprite2D
			if sprite.texture == null or not sprite.is_visible_in_tree():
				continue
			var opaque: Rect2i = sprite.texture.get_image().get_used_rect()
			var sprite_rect := Rect2(sprite.get_rect().position + Vector2(opaque.position), Vector2(opaque.size))
			if sprite.flip_h:
				sprite_rect.position.x = -sprite_rect.end.x
			bounds = bounds.merge(sprite.get_global_transform() * sprite_rect)
	return bounds


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
