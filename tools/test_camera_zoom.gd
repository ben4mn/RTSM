extends Node
## Anchored wheel/pinch zoom, HUD controls, overview limits and map-edge safety.

var _failures: Array[String] = []
var _zoom_notifications: int = 0
var _zoom_samples: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.reduced_motion = false
	GameManager.zoom_sensitivity_scale = 1.0
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
	_expect_float(camera.zoom.x, initial_zoom, "button step should begin from the rendered scale")
	game_map.call("_update_camera_zoom", 0.03)
	_expect(camera.zoom.x > initial_zoom, "HUD plus does not zoom into detail")
	_expect(camera.zoom.x < initial_zoom * 1.12, "button step jumps straight to its final scale")
	_expect_vector(_world_at(_screen_center()), initial_center, "HUD plus shifted the centered terrain")
	game_map.call("zoom_out")
	_finish_zoom(game_map)
	_expect_float(camera.zoom.x, initial_zoom, "one plus/minus pair should restore zoom exactly")
	_expect_vector(_world_at(_screen_center()), initial_center, "plus/minus pair drifted the centered terrain")

	# Wheel input preserves a noncentral cursor anchor even while the camera's
	# smoothing target is elsewhere, rather than jumping toward that target.
	var cursor: Vector2 = _screen_center() + Vector2(130.0, -55.0)
	var cursor_world: Vector2 = _world_at(cursor)
	camera.position += Vector2(100.0, 35.0)
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_UP)
	_finish_zoom(game_map, cursor, cursor_world)
	_expect_vector(_world_at(cursor), cursor_world, "wheel zoom moved terrain away from the pointer")
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_DOWN)
	_finish_zoom(game_map, cursor, cursor_world)
	_expect_float(camera.zoom.x, initial_zoom, "wheel in/out is not reciprocal")
	_expect_vector(_world_at(cursor), cursor_world, "wheel in/out drifted the pointer anchor")
	# Precision scroll events should preserve their fractional distance, and
	# rapid reversal must accumulate against the requested target.
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_UP, 0.25)
	_finish_zoom(game_map, cursor, cursor_world)
	_expect_float(camera.zoom.x, initial_zoom * pow(1.12, 0.25), "fractional trackpad wheel became a full notch")
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_DOWN, 0.25)
	game_map.call("_update_camera_zoom", 0.03)
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_DOWN, 1.0)
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_UP, 1.0)
	_finish_zoom(game_map, cursor, cursor_world)
	_expect_float(camera.zoom.x, initial_zoom, "reversing a pending wheel step lost accumulated intent")
	GameManager.reduced_motion = true
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_UP)
	_expect_float(camera.zoom.x, initial_zoom * 1.12, "reduced motion does not apply zoom immediately")
	_expect(not bool(game_map.get("_zoom_transition_active")), "reduced motion leaves a zoom animation")
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_DOWN)
	GameManager.reduced_motion = false
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_UP, 3.0)
	_finish_zoom(game_map, cursor, cursor_world)
	_expect_float(camera.zoom.x, initial_zoom * 1.12, "large browser pixel-wheel event exceeds one comfortable step")
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_DOWN, 0.0)
	_finish_zoom(game_map, cursor, cursor_world)
	_expect_float(camera.zoom.x, initial_zoom, "unsupported zero wheel factor does not retain a normal step")
	# A modal or a fresh focus must cancel animation at its current scale so
	# resuming/centering cannot snap back toward a stale cursor anchor.
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_UP)
	game_map.call("_update_camera_zoom", 0.03)
	game_map.call("cancel_camera_touch_gesture")
	var canceled_zoom: float = camera.zoom.x
	var canceled_position: Vector2 = camera.position
	_finish_zoom(game_map)
	_expect_float(camera.zoom.x, canceled_zoom, "modal cancellation leaves a pending zoom")
	_expect_vector(camera.position, canceled_position, "canceled zoom moves the camera")
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_UP)
	game_map.call("note_camera_interaction")
	camera.position += Vector2(40.0, 20.0)
	camera.reset_smoothing()
	camera.force_update_scroll()
	canceled_position = camera.position
	_finish_zoom(game_map)
	_expect_vector(camera.position, canceled_position, "focus change resumes an old zoom anchor")
	_center_camera(game_map, camera)
	cursor_world = _world_at(cursor)
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
	_push_wheel(cursor, MOUSE_BUTTON_WHEEL_UP)
	_push_touch(0, p0, true)
	_push_touch(1, p1, true)
	_expect(not bool(game_map.get("_zoom_transition_active")), "new fingers retain an eased wheel step")
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
	_finish_zoom(game_map)
	_expect_float(camera.zoom.x, float(state["min"]), "zoom out escaped the overview limit")
	for _step in range(32):
		game_map.call("zoom_in")
	_finish_zoom(game_map)
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
	_finish_zoom(game_map)
	_expect(bounds.grow(0.01).has_point(camera.position), "edge zoom moved focus beyond the legal map rectangle")
	var half_view: Vector2 = game_map.call("_get_camera_half_view_world")
	_expect(camera.limit_left <= floori(bounds.position.x - half_view.x), "physical horizontal limit must let a map-edge focus center")
	_expect(camera.limit_top <= floori(bounds.position.y - half_view.y), "physical vertical limit must let a map-edge focus center")
	for corner: Vector2 in [bounds.position, bounds.end, Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.end.x, bounds.position.y)]:
		game_map.call("show_overview")
		camera.position = corner
		camera.reset_smoothing()
		camera.force_update_scroll()
		game_map.call("zoom_in", Vector2.ZERO)
		for frame: int in 20:
			game_map.call("_update_camera_zoom", 0.01)
			_expect(camera.position.is_finite() and bounds.grow(0.01).has_point(camera.position), "eased overview zoom escaped a clamped map corner")
		game_map.call("zoom_out", Vector2.ZERO)
		_finish_zoom(game_map)
		_expect_float(camera.zoom.x, float(state["min"]), "overview corner +/- does not return to minimum")
	_expect(_zoom_notifications > 10, "HUD did not receive zoom/limit updates")
	# A map-edge subject cannot move past a central HUD card at minimum zoom
	# because the legal camera focus stops at the map edge. There is a visible
	# right-side slot at an intermediate zoom, despite both min and detail
	# being infeasible. Center must find it instead of hiding the subject.
	game_map.set("_camera_world_bounds", Rect2(0, 0, 1000, 1000))
	var subjects: Array[Rect2] = [Rect2(220, 300, 100, 50)]
	var field := Rect2(_screen_center() + Vector2(-300, -80), Vector2(600, 160))
	var blockers: Array[Rect2] = [Rect2(field.position, Vector2(450, 160))]
	var expanded_blockers: Array[Rect2] = [blockers[0].grow(6.0)]
	var minimum_focus: Vector2 = game_map.call("_find_unoccluded_focus", subjects, field.grow(-8), expanded_blockers, float(state["min"]))
	_expect(not minimum_focus.is_finite(), "edge/card fixture must make minimum zoom infeasible")
	var intermediate_focus: Vector2 = game_map.call("_find_unoccluded_focus", subjects, field.grow(-8), expanded_blockers, 1.0)
	_expect(intermediate_focus.is_finite(), "edge/card fixture must retain an intermediate clear view")
	game_map.call("_set_zoom_anchored", 2.0, Vector2(-1, -1), Vector2(-1, -1), true)
	var framed: Dictionary = game_map.call("frame_world_bounds", subjects, field, blockers)
	var projected: Rect2 = get_viewport().get_canvas_transform() * subjects[0]
	_expect(bool(framed["fit"]) and camera.zoom.x > float(state["min"]) and camera.zoom.x < 2.0, "Center missed a feasible intermediate zoom beside a map-edge HUD card")
	_expect(field.grow(-7.5).encloses(projected) and not projected.intersects(blockers[0].grow(5.5)), "Center's intermediate view fails independent subject clearance")
	game_map.set("_camera_world_bounds", bounds)

	var output: String = OS.get_environment("AOEM_CAMERA_TEST_OUTPUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("zoom.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"evidence": "Dispatched wheel, magnify and multi-contact touch input, with deterministic animation-frame progression; no physical phone claim.", "viewport": str(get_viewport().get_visible_rect().size), "limits": state, "source_sha256": FileAccess.get_sha256("res://scripts/map/game_map.gd"), "samples": _zoom_samples, "failures": _failures}, "  "))
	game_map.free()
	if _failures.is_empty():
		print("[PASS] camera_zoom: eased reciprocal steps, fractional wheel and rapid reversal, every-frame cursor anchor, reduced motion/cancellation, direct magnify/pinch, overview/reset and map edges")
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


func _finish_zoom(game_map: Node2D, anchor: Vector2 = Vector2(-1, -1), world: Vector2 = Vector2.ZERO) -> void:
	for frame: int in 20:
		game_map.call("_update_camera_zoom", 0.01)
		if anchor != Vector2(-1, -1):
			_expect_vector(_world_at(anchor), world, "intermediate zoom frame drifted terrain under the pointer")
			_zoom_samples.append({"zoom": (game_map.get("camera") as Camera2D).zoom.x, "anchor_error": _world_at(anchor).distance_to(world)})


func _push_wheel(position: Vector2, button: int, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = true
	event.factor = factor
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
