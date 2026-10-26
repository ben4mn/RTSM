extends Node
## Real phone dispatch for one-shot area selection, camera ownership, and clear.

var _failures: Array[String] = []
var _main: Node
var _map: Node2D
var _selection: SelectionManager
var _hud: CanvasLayer
var _orders: int = 0
var _consume_release_index: int = -1


func _ready() -> void:
	call_deferred("_run")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index == _consume_release_index:
		get_viewport().set_input_as_handled()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	Input.emulate_mouse_from_touch = true
	Input.emulate_touch_from_mouse = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_map = _main.get("game_map")
	_selection = _map.get("selection_mgr")
	_hud = _main.get("hud")
	_main.get("ai_controller").set_process(false)
	_main.get("ai_controller").get("_decision_timer").stop()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
		unit.command_stop()
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	_selection.queue_order_command.connect(func(_position: Vector2, _target: Node2D) -> void: _orders += 1)
	await _frames(4)
	var worker: Villager = _main.get("_player_units")[0][0] as Villager
	# Area includes the starting Scout; same-type double tap includes workers only.
	var worker_count: int = (_main.get("_player_units")[0] as Array).filter(func(unit: UnitBase) -> bool: return unit is Villager).size()
	var camera: Camera2D = _map.get("camera")
	var army_center := Vector2.ZERO
	for unit: Node2D in _main.get("_player_units")[0]:
		army_center += unit.global_position
	camera.position = army_center / float((_main.get("_player_units")[0] as Array).size())
	camera.force_update_scroll()
	await _frames(2)
	var points: Array[Vector2] = []
	for unit: Node2D in _main.get("_player_units")[0]:
		points.append(get_viewport().get_canvas_transform() * unit.global_position)
	var box := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		box = box.expand(point)
	box = box.grow(30.0)
	_expect(Rect2(Vector2(145, 60), Vector2(540, 235)).encloses(box), "starting workers do not fit the world gesture fixture: %s" % box)
	var initial_camera: Vector2 = camera.position
	await _arm_area()
	await _touch(17, box.position, true)
	await _drag(17, box.end, box.size)
	await _hold_duration()
	_expect(bool(_selection.get("_is_dragging")), "area gesture does not show a rectangle")
	_expect(_orders == 0, "area drag emitted a movement or long-press order")
	_expect(camera.position.is_equal_approx(initial_camera), "area drag panned the camera")
	await _touch(17, box.end, false)
	_expect(_selection.selected.size() == points.size(), "area did not select the enclosed workers")
	_expect(not _selection.touch_area_selection_armed, "area mode remained armed after selection")
	_expect(not bool((_hud.get("_select_area_button") as Button).button_pressed), "area button remained armed after selection")
	_expect_clean("completed area")
	await _tap(21, points[0])
	_expect(_selection.selected == [worker] and _orders == 0, "first unit tap did not switch area selection to one worker")
	await _tap(23, points[0])
	_expect(_selection.selected.size() == worker_count and _orders == 0, "same-type double-tap selection was broken by ground-clear gesture")
	_expect_clean("same-type double tap after area")
	# A first unit tap also changes identity from no selection; its synchronous
	# HUD revision must leave the completed tap available for the second tap.
	_selection.deselect_all()
	await _tap(25, points[0])
	_expect(_selection.selected == [worker] and _orders == 0, "first unit tap from empty selection did not select one worker")
	await _tap(27, points[0])
	_expect(_selection.selected.size() == worker_count and _orders == 0, "same-type double tap from empty selection lost its first tap")
	_expect_clean("same-type double tap from empty selection")

	# A second contact aborts the box; neither finger may command on release.
	var selected_before: Array[Node2D] = _selection.selected.duplicate()
	await _arm_area()
	await _touch(31, box.position, true)
	await _drag(31, box.end, box.size)
	await _touch(44, box.end - Vector2(20, 0), true)
	_expect(not _selection.touch_area_selection_armed, "second finger did not cancel area mode")
	await _drag(31, box.position + Vector2(60, 0), Vector2(60, 0))
	await _touch(31, box.position, false)
	await _touch(44, box.end, false)
	_expect(_selection.selected == selected_before and _orders == 0, "canceled multi-contact box changed selection or issued an order")
	_expect(camera.position.is_equal_approx(initial_camera), "canceled box adopted a surviving camera finger")
	_expect_clean("second-finger cancellation")

	await _arm_area()
	await _touch(61, box.position, true)
	await _drag(61, box.end, box.size)
	await _touch(61, box.end, false, true)
	_expect(not _selection.touch_area_selection_armed and _selection.selected == selected_before, "OS cancellation selected units or retained area mode")
	_expect_clean("OS cancellation")

	await _arm_area()
	await _touch(72, box.position, true)
	await _drag(72, box.end, box.size)
	_consume_release_index = 72
	await _touch(72, box.end, false)
	_consume_release_index = -1
	_expect(not _selection.touch_area_selection_armed and _selection.selected == selected_before, "GUI-consumed release selected units or retained area mode")
	_expect_clean("GUI-consumed release")

	await _arm_area()
	await _tap(80, (_hud.get("_camera_view_button") as Button).get_global_rect().get_center())
	await _tap(81, (_hud.get("_select_area_button") as Button).get_global_rect().get_center())
	_expect(not _selection.touch_area_selection_armed, "Cancel area button did not cancel the mode")
	await _arm_area()
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	await _frames(3)
	_expect(not _selection.touch_area_selection_armed, "placement retained area-selection ownership")
	_main.call("_cancel_placement")
	await _frames(3)

	var ground: Vector2 = _find_empty_ground(worker)
	_expect(ground != Vector2.ZERO, "no visible reachable empty ground fixture")
	_selection.select_single(_main.get("_player_town_center"))
	await _frames(3)
	await _tap(91, ground)
	_expect(_selection.selected.is_empty() and _orders == 0, "tapping away from a building did not clear inspection")
	for resource: Node2D in get_tree().get_nodes_in_group("resources"):
		if _map.is_entity_visible_to_player(resource, 0):
			_selection.select_single(resource)
			break
	await _frames(3)
	await _tap(93, ground)
	_expect(_selection.selected.is_empty() and _orders == 0, "tapping away from a resource did not clear inspection")
	var producer: BuildingBase = _main.get("_player_town_center")
	_selection.select_single(producer)
	await _frames(3)
	await _touch(97, ground, true)
	await _hold_duration()
	await _touch(97, ground, false)
	_expect(producer.has_custom_rally_point() and _selection.selected == [producer] and _orders == 1, "holding ground did not retain mobile producer rally access")
	_selection.select_single(worker)
	await _frames(3)
	await _tap(101, ground)
	_expect(_orders == 2 and worker.current_state == UnitBase.State.MOVING, "first ground tap did not move the selected worker")
	await _tap(103, ground)
	_expect(_selection.selected == [worker] and _orders == 3, "repeated ground tap must remain an order and retain selection")
	_expect(worker.current_state == UnitBase.State.MOVING, "repeated destination stopped movement")
	worker.command_stop()
	_selection.select_single(worker)
	await _frames(3)
	var attack: Button = (_hud.get("_unit_command_container") as HBoxContainer).get_node("UnitAttackMoveButton")
	await _tap(111, attack.get_global_rect().get_center())
	_expect(_selection.unit_command_armed and bool(_main.get("_attack_move_command_armed")), "primary Attack did not arm attack-move")
	_expect(attack.button_pressed and (_hud.get("selection_details") as Label).text.contains("Tap attack-move"), "armed Attack lacks persistent visible destination feedback")
	await _tap(113, attack.get_global_rect().get_center())
	_expect(not _selection.unit_command_armed, "tapping armed Attack did not cancel the mode")
	await _tap(115, attack.get_global_rect().get_center())
	await _tap(117, ground)
	_expect(_orders == 4 and worker.attack_move and not _selection.unit_command_armed, "Attack destination did not execute one-shot attack-move")
	_expect(_selection.selected.size() == 1, "attack-move destination unexpectedly cleared selection")
	_expect(not attack.button_pressed and not (_hud.get("selection_details") as Label).text.contains("Tap attack-move"), "completed Attack retains stale destination instructions")

	_main.free()
	for failure: String in _failures:
		push_error("[FAIL] mobile_area_selection: " + failure)
	if _failures.is_empty():
		print("[PASS] mobile_area_selection: real phone box/one-shot/camera isolation; arbitrary IDs; pinch/OS/GUI/mode cancellation; same-type double tap; tap-away inspection and hold-ground rally; repeated ground orders retain selection; primary Attack toggle and destination")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _arm_area() -> void:
	await _tap(6, (_hud.get("_camera_view_button") as Button).get_global_rect().get_center())
	await _tap(7, (_hud.get("_select_area_button") as Button).get_global_rect().get_center())
	_expect(_selection.touch_area_selection_armed, "real GUI Select area did not arm")
	_expect((_hud.get("_progression_hint_label") as Label).text.contains("Drag to select") and (_hud.get("_progression_hint_panel") as Control).visible, "armed area lacks a persistent instruction")


func _tap(index: int, position: Vector2) -> void:
	await _touch(index, position, true)
	await _touch(index, position, false)


func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * position
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	await _frames(2)


func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	var transform: Transform2D = get_viewport().get_final_transform()
	event.position = transform * position
	event.relative = transform.basis_xform(relative)
	Input.parse_input_event(event)
	await _frames(2)


func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func _hold_duration() -> void:
	var deadline: int = Time.get_ticks_msec() + 450
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _find_empty_ground(worker: Villager) -> Vector2:
	var origin: Vector2i = _map.world_to_tile(worker.global_position)
	for dy: int in range(-8, 9):
		for dx: int in range(-8, 9):
			var tile: Vector2i = origin + Vector2i(dx, dy)
			if not _map.is_tile_walkable(tile) or not _map.is_tile_visible_to_player(tile, 0):
				continue
			var world: Vector2 = _map.tile_to_world(tile)
			var screen: Vector2 = get_viewport().get_canvas_transform() * world
			if not Rect2(Vector2(155, 105), Vector2(480, 135)).has_point(screen) or world.distance_to(worker.global_position) < 64:
				continue
			if _selection.call("_get_node_at", world, true) != null or _selection.call("_get_resource_at", world, true) != null:
				continue
			if not _map.get_navigation_world_path(worker.global_position, world).is_empty():
				return screen
	return Vector2.ZERO


func _expect_clean(context: String) -> void:
	_expect(_selection.get("_active_touch_indices").is_empty() and _selection.get("_released_world_touch_indices").is_empty() and int(_selection.get("_primary_touch_index")) == -1 and not bool(_selection.get("_is_dragging")), context + " retained contact/box state")
	_expect(_map.get("_touch_points").is_empty(), context + " retained a camera contact")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
