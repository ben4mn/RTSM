extends Node
## Actual input dispatch: extra fingers and modal interruption cannot strand camera contacts.

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = false
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 202
	var main: Node2D = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	var game_map: Node2D = main.get_node("GameMap")
	var camera: Camera2D = game_map.get("camera")
	var hud: CanvasLayer = main.get_node("HUD")
	var selection: SelectionManager = game_map.get("selection_mgr")
	selection.touch_context_enabled = false
	camera.position = (game_map.get("_camera_world_bounds") as Rect2).get_center()
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _settle()
	var p0 := Vector2(300, 180)
	var p1 := Vector2(490, 180)
	var p2 := Vector2(580, 180)
	await _touch(7, p0, true)
	await _touch(41, p1, true)
	await _touch(99, p2, true)
	_expect((game_map.get("_touch_points") as Dictionary).size() == 3, "camera does not admit all three world contacts")
	var before_extra: Vector2 = camera.position
	var before_zoom: float = camera.zoom.x
	await _drag(99, p2 + Vector2(30, 0), Vector2(30, 0))
	_expect(camera.position.is_equal_approx(before_extra) and is_equal_approx(camera.zoom.x, before_zoom), "third finger moves the existing camera pair")
	await _drag(41, p1 + Vector2(50, 0), Vector2(50, 0))
	_expect(camera.zoom.x > before_zoom, "third contact freezes the first two fingers' pinch")
	var before_release: Vector2 = camera.position
	await _touch(7, p0, false)
	_expect(camera.position.is_equal_approx(before_release), "lifting a primary pinch finger jumps the view")
	await _touch(41, p1 + Vector2(50, 0), false)
	await _touch(99, p2 + Vector2(30, 0), false)
	await _settle()
	_expect((game_map.get("_touch_points") as Dictionary).is_empty(), "three-finger release leaves camera contacts")

	await _touch(101, p0, true)
	await _touch(205, p1, true)
	_expect((game_map.get("_touch_points") as Dictionary).size() == 2, "camera does not admit arbitrary world identifiers")
	_key(KEY_P, true)
	_key(KEY_P, false)
	await _settle()
	_expect(GameManager.current_state == GameManager.GameState.PAUSED, "routed pause key did not open pause")
	_expect((game_map.get("_touch_points") as Dictionary).is_empty(), "pause retains camera fingers")
	_expect((selection.get("_active_touch_indices") as Dictionary).is_empty(), "pause retains a world selection gesture")
	var resume: Button = hud.get("_pause_overlay").get_node("PauseMenu/ResumeButton")
	_pointer(resume.get_global_rect().get_center(), true)
	_pointer(resume.get_global_rect().get_center(), false)
	await _settle()
	_expect(GameManager.current_state == GameManager.GameState.PLAYING, "real GUI Resume did not resume")
	var resumed_position: Vector2 = camera.position
	await _drag(101, p0 + Vector2(80, 0), Vector2(80, 0))
	_expect(camera.position.is_equal_approx(resumed_position), "old contact moves camera after resume without a fresh press")
	await _touch(101, p0 + Vector2(80, 0), false)
	await _touch(205, p1, false)
	await _settle()

	selection.deselect_all()
	await _settle()
	await _touch(301, p0, true)
	_expect((game_map.get("_touch_points") as Dictionary).has(301), "Build cleanup fixture did not start a world contact")
	_expect((selection.get("_active_touch_indices") as Dictionary).has(301), "Build cleanup fixture did not start a selection contact")
	var build: Button = hud.get("build_menu_button")
	_expect(build.is_visible_in_tree(), "Build fixture is not visible")
	_pointer(build.get_global_rect().get_center(), true)
	_pointer(build.get_global_rect().get_center(), false)
	await _settle()
	_expect(hud.is_build_menu_open(), "real GUI Build did not open the menu")
	_expect((game_map.get("_touch_points") as Dictionary).is_empty(), "opening Build retains camera contact")
	_expect((selection.get("_active_touch_indices") as Dictionary).is_empty(), "opening Build retains selection contact")
	await _touch(301, p0, false)
	main.call("_on_build_menu_close_requested")
	await _settle()
	# A state-level pause can bypass the HUD handler's placement cancellation.
	# Preserve its preview, but never resume ownership of the old held finger.
	var placement: BuildingPlacement = main.get("_building_placement")
	main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	await _settle()
	await _touch(601, p0, true)
	_expect((placement.get("_touch_points") as Dictionary).has(601), "direct pause fixture did not start a placement contact")
	var paused_ghost: Vector2 = placement.ghost_position
	GameManager.set_paused(true)
	await _settle()
	_expect(placement.active, "direct pause canceled its pending preview")
	_expect((placement.get("_touch_points") as Dictionary).is_empty(), "direct pause retained a placement contact")
	GameManager.set_paused(false)
	await _settle()
	await _drag(601, p0 + Vector2(60, 0), Vector2(60, 0))
	_expect(placement.ghost_position == paused_ghost, "old placement finger moves the preview after direct resume")
	await _touch(601, p0 + Vector2(60, 0), false)
	await _touch(602, p1, true)
	await _drag(602, p1 + Vector2(60, 0), Vector2(60, 0))
	_expect(placement.ghost_position != paused_ghost, "fresh placement finger cannot reposition after direct resume")
	await _touch(602, p1 + Vector2(60, 0), false)
	main.call("_cancel_placement")
	await _settle()
	await _touch(401, p0, true)
	_expect((game_map.get("_touch_points") as Dictionary).has(401), "game-over cleanup fixture did not start a world contact")
	_expect((selection.get("_active_touch_indices") as Dictionary).has(401), "game-over cleanup fixture did not start a selection contact")
	GameManager.set_state(GameManager.GameState.GAME_OVER)
	_expect((game_map.get("_touch_points") as Dictionary).is_empty(), "game over retains camera contact")
	_expect((selection.get("_active_touch_indices") as Dictionary).is_empty(), "game over retains selection contact")
	await _touch(401, p0, false)
	# Exercise the ordinary match-conclusion path with a pending foundation.
	GameManager.set_state(GameManager.GameState.PLAYING)
	main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	await _settle()
	await _touch(701, p0, true)
	_expect((placement.get("_touch_points") as Dictionary).has(701), "match conclusion fixture did not start a placement contact")
	main.call("_conclude_match", 1, "Elimination")
	await _settle()
	_expect(GameManager.current_state == GameManager.GameState.GAME_OVER, "ordinary conclusion did not end the match")
	_expect((placement.get("_touch_points") as Dictionary).is_empty(), "ordinary game over retains a placement contact")
	_expect((game_map.get("_touch_points") as Dictionary).is_empty(), "ordinary game over retains a camera contact")
	await _touch(701, p0, false)
	main.free()
	GameManager.set_state(GameManager.GameState.MENU)
	for failure: String in _failures:
		push_error("[FAIL] camera_modal_touch_lifecycle: " + failure)
	if _failures.is_empty():
		print("[PASS] camera_modal_touch_lifecycle: arbitrary IDs; extra finger continuity; routed Pause/GUI Resume/Build, direct placement pause/resume and ordinary game-over cleanup")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * position
	event.pressed = pressed
	Input.parse_input_event(event)
	await _settle()


func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	var transform: Transform2D = get_viewport().get_final_transform()
	event.position = transform * position
	event.relative = transform.basis_xform(relative)
	Input.parse_input_event(event)
	await _settle()


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _pointer(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = get_viewport().get_final_transform() * position
	event.global_position = event.position
	event.pressed = pressed
	Input.parse_input_event(event)


func _settle() -> void:
	for frame: int in 4:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
