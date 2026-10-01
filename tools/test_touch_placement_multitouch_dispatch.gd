extends Node
## Real phone-style Input dispatch: world/HUD finger ownership, pinch + pan,
## sticky navigation releases and a normal paid explicit placement afterward.

var _failures: Array[String] = []
var _confirmed: int = 0
var _main: Node = null
var _placement: BuildingPlacement = null
var _map: Node2D = null
var _camera: Camera2D = null
var _hide_gui_after_press: bool = false
var _consume_release_index: int = -1
var _consumed_release_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _input(event: InputEvent) -> void:
	# A diagnostic UI owner swallows this one release before unhandled input.
	# Reverse tree input order runs the descendant placement/map bookkeeping
	# first. This models a modal/overlay interception independently of Godot's
	# normal GUI capture, which may keep a world-started contact world-owned.
	if event is InputEventScreenTouch:
		var contact := event as InputEventScreenTouch
		if contact.index == _consume_release_index and not contact.pressed:
			_consumed_release_count += 1
			_consume_release_index = -1
			get_viewport().set_input_as_handled()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_population_limit = 30
	GameManager.selected_map_seed = 101
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for _frame: int in 900:
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_placement = _main.get("_building_placement") as BuildingPlacement
	_map = _main.get_node("GameMap") as Node2D
	_camera = _map.get("camera") as Camera2D
	var hud: CanvasLayer = _main.get_node("HUD") as CanvasLayer
	if _placement == null or _camera == null:
		_failures.append("normal Main did not initialize placement/camera")
		_finish()
		return
	_main.get_node("AIController").set_process(false)
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_physics_process(false)
	_map.set_process(false)
	_camera.position_smoothing_enabled = false
	# This diagnostic Control models a HUD surface that disappears after its
	# press (a panel/mode switch). The normal GUI routing still owns that finger.
	var gui_guard := Control.new()
	gui_guard.position = Vector2(620.0, 120.0)
	gui_guard.size = Vector2(140.0, 90.0)
	gui_guard.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(gui_guard)
	gui_guard.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var contact := event as InputEventScreenTouch
			if contact.pressed and _hide_gui_after_press:
				gui_guard.call_deferred("hide")
		gui_guard.accept_event()
	)
	_placement.placement_confirmed.connect(func(_kind: int, _pos: Vector2) -> void: _confirmed += 1)
	var wood_before: int = int(ResourceManager.get_all_resources(0).get("wood", 0))
	var buildings_before: int = (_main.get("_player_buildings")[0] as Array).size()
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	var valid_world: Vector2 = _placement.ghost_position
	var bounds: Rect2 = _map.get("_camera_world_bounds")
	_camera.position = bounds.get_center()
	_map.call("reset_zoom")
	_camera.force_update_scroll()
	await _frames()
	var p0 := Vector2(275.0, 160.0)
	var p1 := Vector2(480.0, 160.0)
	var ghost_before: Vector2 = _placement.ghost_position
	var camera_before: Vector2 = _camera.position
	var zoom_before: float = _camera.zoom.x

	# Browser touch IDs may increase after menu/HUD contacts; no index0 exists.
	await _touch(41, p0, true)
	await _touch(78, p1, true)
	await _drag(78, p1 + Vector2(64.0, 0.0), Vector2(64.0, 0.0))
	_expect(_camera.zoom.x > zoom_before, "arbitrary-ID pinch did not actually zoom the camera")
	_expect(_camera.position.distance_to(camera_before) > 1.0, "moving pinch midpoint did not actually pan the camera")
	_expect(_placement.ghost_position == ghost_before, "pinch moved the pending foundation")
	_expect_pending(wood_before, buildings_before, "pinch")

	# Drop one finger, then keep navigating with the other. Neither that drag
	# nor either release may hand the ghost back to placement mid-gesture.
	await _touch(78, p1 + Vector2(64.0, 0.0), false)
	camera_before = _camera.position
	await _drag(41, p0 + Vector2(44.0, 24.0), Vector2(44.0, 24.0))
	_expect(_camera.position.distance_to(camera_before) > 1.0, "remaining pinch finger could not continue camera navigation")
	_expect(_placement.ghost_position == ghost_before, "remaining pinch finger repositioned the foundation")
	await _touch(41, p0 + Vector2(44.0, 24.0), false)
	_expect(_placement.ghost_position == ghost_before, "pinch release repositioned the foundation")
	_expect((_placement.get("_touch_points") as Dictionary).is_empty(), "pinch retained placement fingers")
	_expect_pending(wood_before, buildings_before, "pinch releases")

	# A fresh one-finger contact now owns preview movement again.
	await _touch(93, p0, true)
	await _drag(93, p0 + Vector2(48.0, 16.0), Vector2(48.0, 16.0))
	_expect(_placement.ghost_position != ghost_before, "fresh arbitrary-ID finger could not reposition the preview")
	await _touch(93, p0 + Vector2(48.0, 16.0), false)
	_expect_pending(wood_before, buildings_before, "fresh preview gesture")

	# A HUD-owned press that drags into the world remains HUD-owned. A live
	# world finger alongside it must still be a single preview finger.
	var hud_button: Button = hud.get("_placement_confirm_button") as Button
	var hud_position: Vector2 = gui_guard.get_global_rect().get_center()
	_hide_gui_after_press = true
	await _touch(105, hud_position, true)
	_expect(not (_placement.get("_touch_points") as Dictionary).has(105), "HUD press became a placement finger")
	_expect(not gui_guard.visible, "diagnostic HUD press did not hide its Control")
	ghost_before = _placement.ghost_position
	camera_before = _camera.position
	await _drag(105, p1, p1 - hud_position)
	_expect(not (_placement.get("_touch_points") as Dictionary).has(105), "HUD drag was admitted without a world press")
	_expect(_placement.ghost_position == ghost_before, "HUD drag moved the pending foundation")
	_expect(_camera.position == camera_before, "HUD drag navigated the camera")
	await _touch(105, p1, false)
	_expect_pending(wood_before, buildings_before, "HUD drag release")
	_hide_gui_after_press = false
	gui_guard.show()
	ghost_before = _placement.ghost_position
	camera_before = _camera.position
	await _drag(311, p1 + Vector2(32.0, 0.0), Vector2(32.0, 0.0))
	_expect(not (_placement.get("_touch_points") as Dictionary).has(311), "orphan drag became a placement finger without an admitted press")
	_expect(_placement.ghost_position == ghost_before, "orphan drag repositioned the pending foundation")
	_expect(_camera.position == camera_before, "orphan drag navigated the camera")

	# Start two world fingers and let a diagnostic UI owner consume a release.
	# Early bookkeeping still removes it from placement and camera.
	await _touch(122, p0, true)
	await _touch(164, p1, true)
	_consume_release_index = 164
	await _touch(164, hud_position, false)
	_expect(_consumed_release_count == 1, "diagnostic UI owner did not actually consume the routed release")
	_expect(not (_placement.get("_touch_points") as Dictionary).has(164), "HUD-consumed release retained placement ownership")
	_expect(not (_map.get("_touch_points") as Dictionary).has(164), "HUD-consumed release retained camera ownership")
	await _touch(122, p0, false)
	_expect((_placement.get("_touch_points") as Dictionary).is_empty(), "GUI release retained a phantom placement pinch")
	_expect_pending(wood_before, buildings_before, "HUD-consumed pinch release")
	await _touch(180, p0, true)
	ghost_before = _placement.ghost_position
	await _drag(180, p0 + Vector2(40.0, 0.0), Vector2(40.0, 0.0))
	_expect(_placement.ghost_position != ghost_before, "phantom pinch prevented the next preview gesture")
	await _touch(180, p0 + Vector2(40.0, 0.0), false, true)
	_expect_pending(wood_before, buildings_before, "OS-canceled contact")

	# Reverse the release order: the original preview finger lifts first and
	# the secondary navigates, then its final release is consumed by UI.
	await _touch(400, p0, true)
	await _touch(443, p1, true)
	ghost_before = _placement.ghost_position
	await _touch(400, p0, false)
	camera_before = _camera.position
	await _drag(443, p1 + Vector2(-40.0, -16.0), Vector2(-40.0, -16.0))
	_expect(_camera.position.distance_to(camera_before) > 1.0, "secondary finger could not navigate after the first lifted")
	_expect(_placement.ghost_position == ghost_before, "reverse pinch release handed the preview to the secondary finger")
	_consume_release_index = 443
	await _touch(443, hud_position, false)
	_expect(_consumed_release_count == 2, "diagnostic UI did not consume the final pinch release")
	_expect((_placement.get("_touch_points") as Dictionary).is_empty(), "consumed final release retained placement ownership")
	_expect(not bool(_placement.get("_touch_camera_gesture")), "consumed final release retained the navigation latch")
	var released_inputs: Variant = _placement.get("_released_touch_inputs")
	_expect(released_inputs is Dictionary and (released_inputs as Dictionary).is_empty(), "consumed release snapshots accumulated after dispatch")
	_expect(_placement.ghost_position == ghost_before, "consumed final release moved the preview")
	await _touch(487, p0 + Vector2(80.0, 40.0), true)
	await _touch(487, p0 + Vector2(80.0, 40.0), false)
	_expect(_placement.ghost_position != ghost_before, "fresh tap failed after a consumed final release")
	_expect_pending(wood_before, buildings_before, "reverse/consumed final release")

	# Navigation never purchases. Return to the legal opening preview and use
	# the real explicit HUD action for exactly one ordinary paid House.
	_placement.update_preview_at_world(valid_world)
	await _frames()
	_expect(not hud_button.disabled, "original legal preview no longer enables explicit Place")
	hud_position = hud_button.get_global_rect().get_center()
	await _touch(221, hud_position, true)
	await _touch(221, hud_position, false)
	_expect(_confirmed == 1, "explicit Place did not confirm exactly once")
	_expect(not _placement.active, "explicit Place left placement active")
	var house_cost: int = int(BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE).get("wood", 0))
	_expect(int(ResourceManager.get_all_resources(0).get("wood", 0)) == wood_before - house_cost, "explicit Place did not charge exactly the normal House cost")
	_expect((_main.get("_player_buildings")[0] as Array).size() == buildings_before + 1, "explicit Place did not create exactly one foundation")
	_finish()


func _expect_pending(wood_before: int, buildings_before: int, phase: String) -> void:
	_expect(_placement.active, phase + " canceled placement")
	_expect(_confirmed == 0, phase + " confirmed a foundation")
	_expect(int(ResourceManager.get_all_resources(0).get("wood", 0)) == wood_before, phase + " spent Wood")
	_expect((_main.get("_player_buildings")[0] as Array).size() == buildings_before, phase + " created a foundation")


func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	await _frames()


func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	Input.parse_input_event(event)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_main):
		_main.free()
	for failure: String in _failures:
		push_error("[FAIL] touch_placement_multitouch_dispatch: " + failure)
	if _failures.is_empty():
		print("[PASS] touch_placement_multitouch_dispatch: arbitrary-ID routed pinch/pan, sticky navigation, HUD press/drag/release ownership, canceled contact, and one paid explicit House")
	get_tree().quit(0 if _failures.is_empty() else 1)
