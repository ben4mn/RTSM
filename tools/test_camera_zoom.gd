extends Node
## Anchored wheel/pinch zoom, HUD controls, overview limits and map-edge safety.

var _failures: Array[String] = []
var _zoom_notifications: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var game_map: Node2D = load("res://scenes/map/game_map.tscn").instantiate() as Node2D
	add_child(game_map)
	await get_tree().process_frame
	game_map.set_process(false)
	var selection: SelectionManager = game_map.get("selection_mgr") as SelectionManager
	selection.touch_context_enabled = false
	selection.set_process_unhandled_input(false)
	var camera: Camera2D = game_map.get("camera") as Camera2D
	game_map.zoom_changed.connect(func(_current: float, _minimum: float, _maximum: float) -> void: _zoom_notifications += 1)
	_center_camera(game_map, camera)

	# Public +/- actions use a center pivot and exact reciprocal steps.
	var state: Dictionary = game_map.call("get_zoom_state")
	var initial_zoom: float = float(state["zoom"])
	var initial_center: Vector2 = _world_at(_screen_center())
	game_map.call("zoom_in")
	_expect(camera.zoom.x > initial_zoom, "HUD plus does not zoom into detail")
	_expect_vector(_world_at(_screen_center()), initial_center, "HUD plus shifted the centered terrain")
	game_map.call("zoom_out")
	_expect_float(camera.zoom.x, initial_zoom, "one plus/minus pair should restore zoom exactly")
	_expect_vector(_world_at(_screen_center()), initial_center, "plus/minus pair drifted the centered terrain")

	# Wheel input preserves a noncentral cursor anchor even while the camera's
	# smoothing target is elsewhere, rather than jumping toward that target.
	var cursor: Vector2 = _screen_center() + Vector2(130.0, -55.0)
	var cursor_world: Vector2 = _world_at(cursor)
	camera.position += Vector2(100.0, 35.0)
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_UP)
	_expect_vector(_world_at(cursor), cursor_world, "wheel zoom moved terrain away from the pointer")
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_DOWN)
	_expect_float(camera.zoom.x, initial_zoom, "wheel in/out is not reciprocal")
	_expect_vector(_world_at(cursor), cursor_world, "wheel in/out drifted the pointer anchor")
	var magnify := InputEventMagnifyGesture.new()
	magnify.position = cursor
	magnify.factor = 1.1
	get_viewport().push_input(magnify, true)
	_expect_vector(_world_at(cursor), cursor_world, "trackpad magnification drifted the pointer anchor")

	_center_camera(game_map, camera)
	var p0: Vector2 = _screen_center() + Vector2(-120.0, -25.0)
	var p1: Vector2 = _screen_center() + Vector2(80.0, -25.0)
	var old_midpoint: Vector2 = (p0 + p1) * 0.5
	var midpoint_world: Vector2 = _world_at(old_midpoint)
	_push_touch(0, p0, true)
	_push_touch(1, p1, true)
	var widened_p1: Vector2 = p1 + Vector2(60.0, 0.0)
	_push_drag(1, widened_p1, Vector2(60.0, 0.0))
	var new_midpoint: Vector2 = (p0 + widened_p1) * 0.5
	_expect(camera.zoom.x > initial_zoom, "spreading fingers did not zoom in")
	_expect_vector(_world_at(new_midpoint), midpoint_world, "pinch did not carry terrain with its moving midpoint")
	_push_touch(1, widened_p1, false)
	var after_pinch: Vector2 = camera.position
	_push_drag(0, p0 + Vector2(5.0, 0.0), Vector2(5.0, 0.0))
	_expect_vector(camera.position, after_pinch, "lifting one pinch finger caused a camera jump")
	_push_touch(0, p0 + Vector2(5.0, 0.0), false)
	_expect((game_map.get("_touch_points") as Dictionary).is_empty(), "pinch release retained a finger")

	# Simulate the early release callback followed by a HUD consuming the event:
	# unhandled input never runs, but no stale pinch finger may remain.
	_push_touch(0, p0, true)
	_push_touch(1, p1, true)
	var early_release := InputEventScreenTouch.new()
	early_release.index = 1
	early_release.position = p1
	early_release.pressed = false
	game_map.call("_input", early_release)
	_expect(not (game_map.get("_touch_points") as Dictionary).has(1), "HUD-consumed release left a stale pinch finger")
	_push_touch(0, p0, false)

	# The visible world extent is inverse to zoom. Overview and detail remain
	# bounded, including when the viewport is larger than the map's height.
	game_map.call("show_overview")
	state = game_map.call("get_zoom_state")
	_expect_float(camera.zoom.x, float(state["min"]), "overview did not reach the overview limit")
	var overview_half: Vector2 = game_map.call("_get_camera_half_view_world")
	var overview_bounds: Rect2 = game_map.get("_camera_world_bounds")
	if overview_half.y * 2.0 > overview_bounds.size.y:
		_expect_float(_world_at(_screen_center()).y, overview_bounds.get_center().y, "whole-map overview rendered away from the map center")
	for _step in range(24):
		game_map.call("zoom_out")
	_expect_float(camera.zoom.x, float(state["min"]), "zoom out escaped the overview limit")
	for _step in range(32):
		game_map.call("zoom_in")
	state = game_map.call("get_zoom_state")
	_expect_float(camera.zoom.x, float(state["max"]), "zoom in escaped the detail limit")
	game_map.call("reset_zoom")
	state = game_map.call("get_zoom_state")
	_expect_float(camera.zoom.x, float(state["default"]), "Reset did not restore gameplay zoom")
	_expect_float(float(state["ratio"]), 1.0, "default zoom ratio is not 100 percent")

	var bounds: Rect2 = game_map.get("_camera_world_bounds")
	camera.position = bounds.position
	game_map.call("_clamp_camera")
	camera.reset_smoothing()
	camera.force_update_scroll()
	game_map.call("zoom_out", Vector2(0.0, 0.0))
	var half_view: Vector2 = game_map.call("_get_camera_half_view_world")
	_expect(camera.position.x >= bounds.position.x + half_view.x - 0.01, "edge zoom moved beyond the map's horizontal bound")
	if half_view.y * 2.0 <= bounds.size.y:
		_expect(camera.position.y >= bounds.position.y + half_view.y - 0.01, "edge zoom moved beyond the map's vertical bound")
	else:
		_expect_float(camera.position.y, bounds.get_center().y, "overview did not center a viewport taller than the map")
	_expect(_zoom_notifications > 10, "HUD did not receive zoom/limit updates")

	game_map.free()
	if _failures.is_empty():
		print("[PASS] camera_zoom: reciprocal +/- and wheel, rendered cursor pivot, moving pinch midpoint, release continuity, overview/reset and bounded map edges")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] camera_zoom: %s" % failure)
		get_tree().quit(1)


func _center_camera(game_map: Node2D, camera: Camera2D) -> void:
	var bounds: Rect2 = game_map.get("_camera_world_bounds")
	camera.position = bounds.get_center()
	camera.reset_smoothing()
	camera.force_update_scroll()
	game_map.call("reset_zoom")


func _screen_center() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


func _world_at(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


func _push_wheel(position: Vector2, button: int) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = true
	get_viewport().push_input(event, true)


func _push_touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _push_drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	get_viewport().push_input(event, true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_float(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) <= 0.01, "%s (expected %.3f, got %.3f)" % [message, expected, actual])


func _expect_vector(actual: Vector2, expected: Vector2, message: String) -> void:
	_expect(actual.distance_to(expected) <= 0.08, "%s (expected %s, got %s)" % [message, expected, actual])
