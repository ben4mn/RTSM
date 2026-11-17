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
	if failures.is_empty(): print("[PASS] navigation_collapse: %d checks; four desktop/phone viewports, no View tray, actual GUI portrait tap Info / double-tap Center, resize and modal" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)

## Loop 2: the View tray (zoom +/-, Reset, Center, Select area, Clear) is
## gone. Pinch / wheel zoom, hold-drag box-selects, the dock's Clear or a
## two-finger tap deselects, and a double-tap on the selection portrait is the
## touch Center (Space on desktop). This checks the replacement surface.
func _profile(size: Vector2i) -> void:
	var view := SubViewport.new()
	view.size = size
	add_child(view)
	var hud: CanvasLayer = HUD_SCENE.instantiate()
	view.add_child(hud)
	await _settle(hud, size)
	var label := str(size)
	for removed: String in ["_navigation_controls", "_camera_view_button", "_select_area_button", "_camera_controls", "_selection_back_button", "_camera_center_button"]:
		_expect(hud.get(removed) == null, label + " removed navigation control is back: " + removed)
	_expect(hud.find_child("MapNavigation", true, false) == null and hud.find_child("CameraViewButton", true, false) == null, label + " View tray nodes still exist")
	var centers: Array[int] = [0]
	hud.center_selection_requested.connect(func() -> void: centers[0] += 1)
	var building := BuildingBase.new()
	building.player_owner = 0
	building.building_type = BuildingData.BuildingType.TOWN_CENTER
	building.state = BuildingBase.State.ACTIVE
	view.add_child(building)
	hud.call("show_building_selection", "Town Center", 100, 100, [], [], building)
	await _settle(hud, size)
	var portrait: Button = hud.get("_selection_info_button")
	_expect(portrait.is_visible_in_tree(), label + " selection portrait is hidden")
	_check_geometry(hud, portrait, size, label)
	# One tap: Info; the portrait stays reachable through the Info shield.
	await _tap(view, hud, portrait, size)
	_expect(hud.call("get_secondary_surface_name") == "info" and centers[0] == 0, label + " portrait tap did not open Info")
	# A quick second tap: Info closes and the camera centers once.
	await _tap(view, hud, portrait, size)
	_expect(centers[0] == 1 and hud.call("get_secondary_surface_name") == "none", label + " portrait double-tap did not center once and close Info")
	# A slow second tap is never a Center: Info just opens again.
	await _tap(view, hud, portrait, size)
	hud.set("_portrait_last_tap_msec", Time.get_ticks_msec() - 2000)
	await _tap(view, hud, portrait, size)
	_expect(centers[0] == 1, label + " a slow portrait tap centered the camera")
	hud.call("close_secondary_surface")
	var resized := Vector2i(932, 430) if size.x < size.y else Vector2i(390, 844)
	view.size = resized
	await _settle(hud, resized)
	_check_geometry(hud, portrait, resized, label + " resized")
	hud.call("set_ui_modal_state", 2)
	await _settle(hud, resized)
	_expect(not portrait.is_visible_in_tree() or portrait.disabled or hud.call("get_secondary_surface_name") == "none", label + " modal left a portrait surface open")
	hud.call("set_ui_modal_state", 0)
	await _settle(hud, resized)
	view.free()
	await get_tree().process_frame

func _check_geometry(hud: CanvasLayer, button: Button, size: Vector2i, label: String) -> void:
	var safe := Rect2(Vector2.ZERO, Vector2(size))
	_expect(button.size.x >= 47.5 and button.size.y >= 47.5, label + " portrait target below48")
	_expect(safe.encloses(button.get_global_rect()), label + " portrait leaves viewport")

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
