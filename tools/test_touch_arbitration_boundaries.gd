extends Node
## Routed engine contacts verify the shared selection/camera boundary and the
## retained ownership of canceled, GUI, extra-contact and desktop gestures.

var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _main: Node2D
var _map: Node2D
var _selection: SelectionManager
var _camera: Camera2D
var _worker: Villager
var _orders: int = 0
var _profile: String
var _next_contact: int = 100
var _consume_release: int = -1


func _ready() -> void:
	call_deferred("_run")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index == _consume_release:
		get_viewport().set_input_as_handled()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	Input.emulate_touch_from_mouse = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale_factor: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _scenario(phone, scale_factor, notched)
	var output_dir := "res://output/evolution/large-maps-20261012-camera/contacts"
	if not OS.get_environment("AOEM_CAMERA_TEST_OUTPUT").is_empty():
		output_dir = OS.get_environment("AOEM_CAMERA_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file := FileAccess.open(output_dir.path_join("contact-boundaries.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "Actual Input.parse_input_event with real Main/HUD and camera; synthetic isolated input fixture, not physical phone or balance evidence.", "profiles": _records, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] touch_arbitration_boundaries: " + failure)
	if _failures.is_empty():
		print("[PASS] touch_arbitration_boundaries: 12 phone/scale/safe-area profiles; shared 12px pan boundary, retained drag, GUI, consumed/canceled/second contacts, mouse ownership and sensitivity")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _scenario(phone: Vector2i, scale_factor: float, notched: bool) -> void:
	_profile = "%dx%d/%.3f/%s" % [phone.x, phone.y, scale_factor, "notch" if notched else "ordinary"]
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = scale_factor
	GameManager.ui_scale = scale_factor
	GameManager.camera_speed_scale = 1.0
	GameManager.zoom_sensitivity_scale = 1.0
	GameManager.hold_shortcuts_enabled = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.set_state(GameManager.GameState.MENU)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_map = _main.get("game_map")
	_selection = _map.get("selection_mgr")
	_camera = _map.get("camera")
	_worker = _main.get("_player_units")[0][0]
	_main.get("ai_controller").set_process(false)
	_main.get("ai_controller").get("_decision_timer").stop()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	_selection.touch_context_enabled = false
	await _settle()
	var hud: CanvasLayer = _main.get("hud")
	var view: Vector2 = get_viewport().get_visible_rect().size
	if notched:
		hud.call("apply_mobile_layout", view, Rect2(Vector2(44.0 / scale_factor, 0), view - Vector2(88.0 / scale_factor, 18.0 / scale_factor)))
	var ground := Vector2(view.x * 0.48, view.y * 0.48)
	var contacts: Array[Dictionary] = []
	for distance: float in [0.0, 11.0, 12.0, 13.0, 14.0, 15.9, 16.0, 24.0]:
		_prepare_world()
		var before: int = _orders
		var before_camera: Vector2 = _camera.position
		var index: int = _new_contact()
		await _touch(index, ground, true)
		if distance > 0.0:
			await _drag(index, ground + Vector2(distance, 0), Vector2(distance, 0))
		await _touch(index, ground + Vector2(distance, 0), false)
		var moved: float = before_camera.distance_to(_camera.position)
		var expected_pan: bool = distance >= 12.0
		_expect((_orders == before) if expected_pan else (_orders == before + 1), "%.1fpx contact issued unexpected world order count %d" % [distance, _orders - before])
		_expect(moved > 0.1 if expected_pan else moved < 0.01, "%.1fpx contact camera delta %.3f disagrees with shared boundary" % [distance, moved])
		_expect_clean("boundary")
		contacts.append({"distance_px": distance, "world_orders": _orders - before, "camera_distance": moved})
	# Going beyond the boundary and returning to the original point remains a
	# pan even though its final displacement is zero.
	_prepare_world()
	var before: int = _orders
	var index: int = _new_contact()
	await _touch(index, ground, true)
	await _drag(index, ground + Vector2(20, 0), Vector2(20, 0))
	await _drag(index, ground, Vector2(-20, 0))
	await _touch(index, ground, false)
	_expect(_orders == before, "return-to-origin drag issued a tap")
	# Neither a canceled contact nor a release consumed before unhandled input
	# can later become a move or delayed hold.
	for consumed: bool in [false, true]:
		_prepare_world()
		before = _orders
		index = _new_contact()
		await _touch(index, ground, true)
		_consume_release = index if consumed else -1
		await _touch(index, ground, false, not consumed)
		_consume_release = -1
		_expect(_orders == before, "canceled/consumed release issued a world order")
		_expect_clean("canceled/consumed")
	# Both world contacts remain non-commanding in either release order.
	for primary_first: bool in [true, false]:
		_prepare_world()
		before = _orders
		index = _new_contact()
		var second: int = _new_contact()
		await _touch(index, ground, true)
		await _touch(second, ground + Vector2(50, 0), true)
		await _touch(index if primary_first else second, ground, false)
		await _touch(second if primary_first else index, ground, false)
		_expect(_orders == before, "two-contact release ordered the world")
		_expect_clean("two contacts")
	# An ordinary hold-capable HUD control must cancel an earlier world finger
	# before that finger can reach its hold threshold or release into a command.
	_prepare_world()
	_selection.touch_context_enabled = true
	_selection.long_press_threshold = 0.08
	var more: Button = hud.get("_unit_more_button")
	before = _orders
	index = _new_contact()
	var gui_index: int = _new_contact()
	await _touch(index, ground, true)
	await _touch(gui_index, more.get_global_rect().get_center(), true)
	await get_tree().create_timer(0.11).timeout
	await _touch(index, ground, false)
	await _touch(gui_index, ground, false)
	_expect(_orders == before, "second GUI contact left a world hold/release actionable")
	_expect_clean("world then GUI")
	hud.call("close_secondary_surface")
	_prepare_world()
	GameManager.hold_shortcuts_enabled = false
	before = _orders
	var hold_executions: int = int(_selection.get("_touch_context_execution_count"))
	index = _new_contact()
	await _touch(index, ground, true)
	await get_tree().create_timer(0.11).timeout
	_expect(_orders == before, "disabled hold preference still activated a world hold")
	await _touch(index, ground, false)
	_expect(_orders == before + 1 and int(_selection.get("_touch_context_execution_count")) == hold_executions, "disabled hold did not preserve ordinary tap semantics")
	GameManager.hold_shortcuts_enabled = true
	_selection.touch_context_enabled = false
	# GUI-origin contact dragged off its button and unknown releases stay owned
	# by GUI even when their endpoint is a valid world destination.
	_prepare_world()
	before = _orders
	index = _new_contact()
	await _touch(index, more.get_global_rect().get_center(), true)
	await _drag(index, ground, Vector2(-80, -80))
	await _touch(index, ground, false)
	await _touch(_new_contact(), ground, false)
	_expect(_orders == before, "GUI-origin/unknown release ordered the world")
	_expect_clean("GUI origin")
	# Sensitivity changes apply to real pan motion without changing arbitration.
	var pan_distances: Array[float] = []
	for sensitivity: float in [0.75, 1.25]:
		_prepare_world()
		GameManager.camera_speed_scale = sensitivity
		var original: Vector2 = _camera.position
		index = _new_contact()
		await _touch(index, ground, true)
		await _drag(index, ground + Vector2(30, 0), Vector2(30, 0))
		await _touch(index, ground + Vector2(30, 0), false)
		pan_distances.append(original.distance_to(_camera.position))
	_expect(pan_distances[1] > pan_distances[0] * 1.5, "pan sensitivity does not change contact motion")
	GameManager.camera_speed_scale = 1.0
	var zoom_ratios: Array[float] = []
	for sensitivity: float in [0.75, 1.25]:
		_map.call("reset_zoom")
		GameManager.zoom_sensitivity_scale = sensitivity
		var original_zoom: float = _camera.zoom.x
		await _mouse(ground, MOUSE_BUTTON_WHEEL_UP, true)
		await get_tree().create_timer(0.2).timeout
		zoom_ratios.append(_camera.zoom.x / original_zoom)
	_expect(zoom_ratios[1] > zoom_ratios[0], "zoom sensitivity does not change wheel motion")
	GameManager.zoom_sensitivity_scale = 1.0
	_map.call("reset_zoom")
	await _stable_target_radii(ground)
	await _desktop_ownership(ground)
	_records.append({"profile": _profile, "logical_viewport": str(view), "boundaries": contacts, "pan_distances": pan_distances})
	_main.free()
	await _settle()


func _stable_target_radii(ground: Vector2) -> void:
	var original_zoom: Vector2 = _camera.zoom
	for zoom: float in [0.42, 0.62, 2.2]:
		_prepare_world()
		_camera.zoom = Vector2(zoom, zoom)
		_camera.position += Vector2(600, 0)
		_camera.force_update_scroll()
		var target: UnitBase = load("res://scenes/units/scout.tscn").instantiate()
		target.player_owner = 0
		_map.add_child(target)
		target.global_position = get_viewport().get_canvas_transform().affine_inverse() * ground
		target.set_process(false)
		var before: int = _orders
		_selection.deselect_all()
		_selection.set_unit_command_armed(false)
		await _tap(_new_contact(), ground + Vector2(21, 0))
		_expect(_selection.selected.size() == 1 and _selection.selected[0] == target, "unit discovery missed 21px target at zoom %.2f" % zoom)
		_selection.select_single(_worker)
		await _tap(_new_contact(), ground + Vector2(21, 0))
		_expect(_selection.selected.size() == 1 and _selection.selected[0] == target and _orders == before, "unit reselection radius changed at zoom %.2f" % zoom)
		_selection.select_single(_worker)
		_selection.set_unit_command_armed(true)
		await _tap(_new_contact(), ground + Vector2(21, 0))
		_expect(_orders == before + 1 and _selection.selected[0] == _worker, "explicit Move failed beside friendly unit at zoom %.2f" % zoom)
		target.free()
		var building := BuildingBase.new()
		building.player_owner = 0
		building.building_type = BuildingData.BuildingType.TOWN_CENTER
		_map.add_child(building)
		building.state = BuildingBase.State.ACTIVE
		building.global_position = get_viewport().get_canvas_transform().affine_inverse() * ground
		building.set_process(false)
		before = _orders
		_selection.deselect_all()
		_selection.set_unit_command_armed(false)
		await _tap(_new_contact(), ground + Vector2(31, 0))
		_expect(_selection.selected.size() == 1 and _selection.selected[0] == building, "building discovery missed 31px target at zoom %.2f" % zoom)
		_selection.select_single(_worker)
		await _tap(_new_contact(), ground + Vector2(31, 0))
		_expect(_selection.selected.size() == 1 and _selection.selected[0] == building and _orders == before, "building reselection radius changed at zoom %.2f" % zoom)
		building.free()
	_camera.zoom = original_zoom
	_camera.force_update_scroll()


func _tap(index: int, position: Vector2) -> void:
	await _touch(index, position, true)
	await _touch(index, position, false)


func _desktop_ownership(ground: Vector2) -> void:
	Input.emulate_touch_from_mouse = false
	Input.emulate_mouse_from_touch = false
	_selection.set("_last_touch_input_msec", 0)
	_prepare_world()
	var before: int = _orders
	await _mouse(ground, MOUSE_BUTTON_RIGHT, false)
	_expect(_orders == before, "unowned native right release issued an order")
	await _mouse(ground, MOUSE_BUTTON_RIGHT, true)
	await _mouse(ground, MOUSE_BUTTON_RIGHT, false, true)
	_expect(_orders == before, "canceled native right release issued an order")
	await _mouse(ground, MOUSE_BUTTON_RIGHT, true)
	_selection.cancel_touch_gesture()
	await _mouse(ground, MOUSE_BUTTON_RIGHT, false)
	_expect(_orders == before, "modal-canceled native right release issued an order")
	await _mouse(ground, MOUSE_BUTTON_RIGHT, true)
	_selection.set("_last_touch_input_msec", Time.get_ticks_msec())
	await _mouse_motion(ground + Vector2(20, 0))
	await _mouse_motion(ground)
	await _mouse(ground, MOUSE_BUTTON_RIGHT, false)
	_expect(_orders == before, "out-and-back native right drag issued a command during recent-touch suppression")
	_selection.set("_last_touch_input_msec", 0)
	await _mouse(ground, MOUSE_BUTTON_RIGHT, true)
	await _mouse(ground, MOUSE_BUTTON_RIGHT, false)
	_expect(_orders == before + 1, "owned native right click no longer commands")
	var retained: Node2D = _selection.selected[0]
	await _mouse(ground, MOUSE_BUTTON_LEFT, false)
	_expect(_selection.selected.size() == 1 and _selection.selected[0] == retained, "unowned native left release changed selection")
	await _mouse(ground, MOUSE_BUTTON_LEFT, true)
	_selection.cancel_touch_gesture()
	await _mouse(ground, MOUSE_BUTTON_LEFT, false)
	_expect(_selection.selected.size() == 1 and _selection.selected[0] == retained, "modal-canceled native left release changed selection")
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true


func _prepare_world() -> void:
	_selection.cancel_touch_gesture()
	_map.call("cancel_camera_touch_gesture")
	_selection.select_single(_worker)
	_selection.set_unit_command_armed(true)
	_camera.position = (_map.get("_camera_world_bounds") as Rect2).get_center()
	_camera.reset_smoothing()
	_camera.force_update_scroll()


func _new_contact() -> int:
	_next_contact += 1
	return _next_contact


func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * position
	event.pressed = pressed
	event.canceled = canceled
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


func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_viewport().get_final_transform() * position
	event.global_position = event.position
	Input.parse_input_event(event)
	await _settle()


func _mouse(position: Vector2, button: int, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = get_viewport().get_final_transform() * position
	event.global_position = event.position
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	await _settle()


func _settle() -> void:
	for frame: int in 2:
		await get_tree().process_frame


func _expect_clean(context: String) -> void:
	_expect(_selection.get("_active_touch_indices").is_empty() and _selection.get("_released_world_touch_indices").is_empty() and int(_selection.get("_primary_touch_index")) == -1 and not bool(_selection.get("_touch_hold_active")), context + " retained world ownership")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(_profile + ": " + message)
