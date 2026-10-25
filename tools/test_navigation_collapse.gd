extends Node
## Real GUI taps and rendered control rectangles in browser-sized viewports.
## Headless viewport geometry, not physical-device testing.
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
var failures: Array[String] = []
var checks: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	ResourceManager.initialize_player(0, {"food": 500, "wood": 500, "gold": 500})
	for size: Vector2i in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(632, 356), Vector2i(1280, 720)]:
		await _profile(size)
	for failure: String in failures: push_error("[FAIL] navigation_collapse: " + failure)
	if failures.is_empty(): print("[PASS] navigation_collapse: %d checks; four desktop/phone viewports, one collapsed icon, actual GUI open/zoom/area/reset/clear taps, resize and modal collapse" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _profile(size: Vector2i) -> void:
	var view := SubViewport.new()
	view.size = size
	add_child(view)
	var hud: CanvasLayer = HUD_SCENE.instantiate()
	view.add_child(hud)
	await _settle(hud, size)
	var nav: Control = hud.get("_navigation_controls")
	var toggle: Button = hud.get("_camera_view_button")
	var area: Button = hud.get("_select_area_button")
	var label := str(size)
	_expect(_visible_buttons(nav).size() == 1 and toggle.is_visible_in_tree(), label + " default is not one navigation icon")
	_expect(nav.size.x <= 64.0 and nav.size.y <= 48.5, label + " collapsed cluster retains empty space")
	var signals: Array[int] = [0, 0, 0, 0]
	hud.camera_zoom_requested.connect(func(_direction: int) -> void: signals[0] += 1)
	hud.select_area_requested.connect(func() -> void: signals[1] += 1)
	hud.camera_zoom_reset_requested.connect(func() -> void: signals[2] += 1)
	hud.deselect_requested.connect(func() -> void: signals[3] += 1)
	await _tap(view, hud, toggle, size)
	_expect(bool(hud.get("_camera_controls_expanded")) and area.is_visible_in_tree(), label + " navigation tap did not expose controls")
	_check_geometry(hud, size, label)
	await _tap(view, hud, hud.get("_camera_zoom_out_button"), size)
	_expect(signals[0] == 1 and bool(hud.get("_camera_controls_expanded")), label + " zoom failed or collapsed the tray")
	await _tap(view, hud, area, size)
	_expect(signals[1] == 1 and not bool(hud.get("_camera_controls_expanded")), label + " area tap must arm once and close tray")
	await _tap(view, hud, toggle, size)
	await _tap(view, hud, hud.get("_camera_zoom_reset_button"), size)
	_expect(signals[2] == 1 and _visible_buttons(nav).size() == 1, label + " reset did not collapse")
	var building := BuildingBase.new()
	building.player_owner = 0
	building.building_type = BuildingData.BuildingType.TOWN_CENTER
	building.state = BuildingBase.State.ACTIVE
	view.add_child(building)
	hud.call("show_building_selection", "Town Center", 100, 100, [], [], building)
	await _settle(hud, size)
	_expect(not (hud.get("_selection_back_button") as Button).is_visible_in_tree(), label + " selection exposes a second collapsed button")
	await _tap(view, hud, toggle, size)
	var clear: Button = hud.get("_selection_back_button")
	_expect(clear.is_visible_in_tree(), label + " expanded tray lost Clear")
	_check_geometry(hud, size, label + " selected")
	await _tap(view, hud, clear, size)
	_expect(signals[3] == 1 and _visible_buttons(nav).size() == 1, label + " Clear did not emit once and collapse")
	await _tap(view, hud, toggle, size)
	var resized := Vector2i(932, 430) if size.x < size.y else Vector2i(390, 844)
	view.size = resized
	await _settle(hud, resized)
	_check_geometry(hud, resized, label + " resized")
	hud.call("notify_world_gesture_started")
	await _settle(hud, resized)
	_expect(_visible_buttons(nav).size() == 1, label + " world gesture did not collapse")
	hud.call("set_ui_modal_state", 2)
	await _settle(hud, resized)
	_expect(not nav.is_visible_in_tree(), label + " modal retained navigation")
	hud.call("set_ui_modal_state", 0)
	await _settle(hud, resized)
	_expect(_visible_buttons(nav).size() == 1, label + " modal close reopened navigation")
	view.free()
	await get_tree().process_frame

func _check_geometry(hud: CanvasLayer, size: Vector2i, label: String) -> void:
	var safe := Rect2(Vector2.ZERO, Vector2(size))
	var buttons: Array[Button] = _visible_buttons(hud.get("_navigation_controls"))
	for button: Button in buttons:
		_expect(button.size.x >= 47.5 and button.size.y >= 47.5, label + " target below48: " + button.name)
		_expect(safe.encloses(button.get_global_rect()), label + " target leaves viewport: " + button.name)
		_expect(not button.get_global_rect().intersects((hud.get("minimap_bg") as Control).get_global_rect()), label + " target overlaps minimap")
		for other: Button in buttons:
			if other != button: _expect(not button.get_global_rect().intersects(other.get_global_rect()), label + " navigation targets overlap")

func _visible_buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child: Node in node.get_children():
		if child is Button and child.is_visible_in_tree(): result.append(child)
		result.append_array(_visible_buttons(child))
	return result

func _tap(view: SubViewport, hud: CanvasLayer, button: Button, size: Vector2i) -> void:
	_expect(button.is_visible_in_tree(), "tap target is hidden: " + button.name)
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		view.push_input(event, true)
		await _settle(hud, size)

func _settle(hud: CanvasLayer, size: Vector2i) -> void:
	for frame: int in 3:
		hud.call("apply_mobile_layout", Vector2(size), Rect2(Vector2.ZERO, Vector2(size)))
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
