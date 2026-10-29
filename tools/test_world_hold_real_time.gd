extends Node
## Real viewport dispatch for the 350ms world hold and contact cancellation.
## Timing observations use the monotonic clock, without injecting hold timestamps.

const GROUND := Vector2(440.0, 240.0)
const HOLD_MSEC := 350

class FakeGameMap extends Node2D:
	func world_to_tile(world_pos: Vector2) -> Vector2i:
		return Vector2i(roundi(world_pos.x / 16.0), roundi(world_pos.y / 16.0))

var _selection: SelectionManager
var _unit: Villager
var _resource: ResourceNode
var _blocker: ColorRect
var _orders: Array[Dictionary] = []
var _admissions: Array[int] = []
var _failures: Array[String] = []
var _timing: Array[Dictionary] = []
var _popup_open_count := 0
var _popup_close_count := 0
var _consume_release_index := -1
var _consumed_releases := 0


func _ready() -> void:
	call_deferred("_run")


func _input(event: InputEvent) -> void:
	# Model a UI layer consuming a world-origin release through actual viewport
	# routing, after child SelectionManager's early ownership bookkeeping.
	if event is InputEventScreenTouch and not event.pressed and event.index == _consume_release_index:
		_consumed_releases += 1
		get_viewport().set_input_as_handled()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var original_speed: float = Engine.time_scale
	var original_mouse_emulation: bool = Input.emulate_mouse_from_touch
	var original_touch_emulation: bool = Input.emulate_touch_from_mouse
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	Input.emulate_touch_from_mouse = false
	var game_map := FakeGameMap.new()
	add_child(game_map)
	_selection = SelectionManager.new()
	_selection.game_map = game_map
	game_map.add_child(_selection)
	_unit = load("res://scenes/units/villager.tscn").instantiate() as Villager
	_unit.position = Vector2(80.0, 240.0)
	game_map.add_child(_unit)
	_unit.set_process(false)
	_resource = ResourceNode.new()
	_resource.position = Vector2(620.0, 240.0)
	game_map.add_child(_resource)
	_blocker = ColorRect.new()
	_blocker.position = Vector2(30.0, 30.0)
	_blocker.size = Vector2(160.0, 70.0)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.gui_input.connect(func(_event: InputEvent) -> void: _blocker.accept_event())
	add_child(_blocker)
	_selection.move_command.connect(func(tile: Vector2i) -> void:
		_orders.append({"action": "move", "time_msec": Time.get_ticks_msec(), "tile": str(tile)}))
	_selection.queue_order_command.connect(func(position: Vector2, _target: Node2D) -> void:
		_orders.append({"action": "queue", "time_msec": Time.get_ticks_msec(), "tile": str(position)}))
	_selection.gather_command.connect(func(_target: Node2D) -> void:
		_orders.append({"action": "gather", "time_msec": Time.get_ticks_msec()}))
	_selection.world_gesture_started.connect(func(index: int, _position: Vector2) -> void: _admissions.append(index))
	_selection.touch_context_opened.connect(func() -> void: _popup_open_count += 1)
	_selection.touch_context_closed.connect(func() -> void: _popup_close_count += 1)
	await _frames(3)
	for emulate_mouse: bool in [false, true]:
		Input.emulate_mouse_from_touch = emulate_mouse
		for speed: float in [0.5, 1.0, 2.0, 3.0]:
			Engine.time_scale = speed
			_reset_case()
			var start: int = Time.get_ticks_msec()
			_contact(41, GROUND, true)
			await _wait_until(start + 300)
			_expect(_orders.is_empty() and not _selection.is_hold_gesture_active(), "speed %.1f / emulation %s activated before 350 real ms" % [speed, emulate_mouse])
			while not _selection.is_hold_gesture_active() and Time.get_ticks_msec() < start + 550:
				await get_tree().process_frame
			var elapsed: int = Time.get_ticks_msec() - start if _selection.is_hold_gesture_active() else -1
			_expect(_selection.is_hold_gesture_active() and _orders.is_empty(), "speed %.1f / emulation %s did not arm one real-time hold (orders wait for the lift)" % [speed, emulate_mouse])
			_expect(elapsed >= HOLD_MSEC and elapsed <= 500, "speed %.1f / emulation %s hold elapsed %dms" % [speed, emulate_mouse, elapsed])
			_contact(41, GROUND, false)
			await _frames(2)
			_expect(_orders.size() == 1 and _orders[0]["action"] == "queue", "hold release must issue exactly one queued destination")
			_expect(_admissions == [41], "touch gesture was admitted more than once or acquired synthetic mouse ownership")
			_expect_clean("timed hold")
			_timing.append({"speed": speed, "mouse_emulation": emulate_mouse, "elapsed_msec": elapsed, "orders": _orders.size()})
			_reset_case()
			start = Time.get_ticks_msec()
			_contact(58, GROUND, true)
			# Keep scheduling slack under browser-play load. The timed hold above
			# independently verifies the real 350ms threshold at every speed.
			await _wait_until(start + 250)
			_expect(_orders.is_empty(), "below-threshold short tap activated during hold")
			_contact(58, GROUND, false)
			await _frames(2)
			_expect(_orders.size() == 1 and _orders[0]["action"] == "move" and _selection.touch_context_diagnostics.get("execution_count", 0) == _context_count_before, "short tap changed its passive Move meaning")
			_expect_clean("short tap")
	Engine.time_scale = 1.0
	Input.emulate_mouse_from_touch = true
	await _test_movement_cancel()
	await _test_contact_ownership()
	await _test_sparse_release()
	await _test_popup_contract()
	await _test_lifecycle_cancel()
	game_map.queue_free()
	_blocker.hide()
	await _frames(3)
	await _test_main_selection_change()
	Engine.time_scale = original_speed
	Input.emulate_mouse_from_touch = original_mouse_emulation
	Input.emulate_touch_from_mouse = original_touch_emulation
	var output_path := "res://output/evolution/mobile-rts-pass-20261012-input/world-hold-real-input.json"
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var record := FileAccess.open(output_path, FileAccess.WRITE)
	record.store_string(JSON.stringify({"scope": "Real Input.parse_input_event; monotonic time; no injected hold timestamps", "timing": _timing, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] world_hold_real_time: " + failure)
	if _failures.is_empty():
		print("[PASS] world_hold_real_time: all speeds/emulation, short taps, movement latch/boundary, sparse release, arbitrary/reused/GUI/OS contacts, popup lifecycle, armed destination, resize/focus, actual Main selection replacement")
	get_tree().quit(0 if _failures.is_empty() else 1)


var _context_count_before := 0


func _reset_case() -> void:
	_selection.set_process(true)
	_selection.cancel_touch_gesture()
	_selection.set_unit_command_armed(false)
	_selection.select_single(_unit)
	_orders.clear()
	_admissions.clear()
	_context_count_before = int(_selection.touch_context_diagnostics.get("execution_count", 0))
	_blocker.position = Vector2(30.0, 30.0)
	_blocker.show()
	_consume_release_index = -1


func _test_movement_cancel() -> void:
	for wait_msec: int in [40, 420]:
		_reset_case()
		var start: int = Time.get_ticks_msec()
		_contact(93, GROUND, true)
		_drag(93, GROUND + Vector2(13.0, 0.0), Vector2(13.0, 0.0))
		_drag(93, GROUND, Vector2(-13.0, 0.0))
		_expect(bool(_selection.get("_touch_hold_canceled")) and float(_selection.get("_touch_max_displacement_px")) >= 13.0, "real drag did not latch maximum displacement before returning")
		await _wait_until(start + wait_msec)
		_expect(_orders.is_empty(), "out-and-back movement activated a pending hold")
		_contact(93, GROUND, false)
		await _frames(2)
		_expect(_orders.is_empty(), "out-and-back movement became a hold or normal tap on release")
		_expect_clean("out-and-back")
	_reset_case()
	_contact(105, GROUND, true)
	_drag(105, GROUND + Vector2(12.0, 0.0), Vector2(12.0, 0.0))
	await _wait_until(Time.get_ticks_msec() + 390)
	_expect(_orders.is_empty(), "exact 12px pan boundary activated a world hold")
	_contact(105, GROUND + Vector2(12.0, 0.0), false)
	await _frames(2)
	_expect(_orders.is_empty(), "12px pan boundary release issued a world order")
	_reset_case()
	_contact(117, GROUND, true)
	_drag(117, GROUND + Vector2(20.0, 0.0), Vector2(20.0, 0.0))
	_drag(117, GROUND, Vector2(-20.0, 0.0))
	_contact(117, GROUND, false)
	await _frames(2)
	_expect(_orders.is_empty(), "camera pan return became a command")


func _test_contact_ownership() -> void:
	_reset_case()
	_contact(164, GROUND, true)
	_contact(221, GROUND + Vector2(50.0, 0.0), true)
	_contact(311, GROUND + Vector2(100.0, 0.0), true)
	_contact(221, GROUND + Vector2(50.0, 0.0), false)
	_contact(164, GROUND, false)
	await _wait_until(Time.get_ticks_msec() + 390)
	_contact(311, GROUND + Vector2(100.0, 0.0), false)
	await _frames(2)
	_expect(_orders.is_empty() and _admissions == [164], "multi-contact release produced a command or new admission")
	_expect_clean("three contacts")
	_reset_case()
	_contact(400, _blocker.get_global_rect().get_center(), true)
	_expect(_admissions.is_empty(), "GUI press was admitted before its Control disappeared")
	_blocker.hide()
	_drag(400, GROUND, GROUND - Vector2(100.0, 65.0))
	await _wait_until(Time.get_ticks_msec() + 390)
	_contact(400, GROUND, false)
	await _frames(2)
	_expect(_orders.is_empty() and _admissions.is_empty(), "GUI-origin contact acquired world ownership after the Control disappeared")
	_expect_clean("GUI origin")
	_reset_case()
	_contact(443, GROUND, true)
	var consumed_before: int = _consumed_releases
	_consume_release_index = 443
	_contact(443, GROUND, false)
	await _frames(2)
	_expect(_consumed_releases == consumed_before + 1, "diagnostic UI did not consume the real release dispatch")
	_expect(_orders.is_empty(), "GUI-consumed release issued a world command")
	_expect_clean("GUI release")
	_reset_case()
	_contact(487, GROUND, true)
	_contact(487, GROUND, false, true)
	await _frames(2)
	_expect(_orders.is_empty(), "OS-canceled contact issued a command")
	_expect_clean("OS cancel")
	_reset_case()
	_contact(501, GROUND, false)
	_drag(501, GROUND, Vector2(5.0, 0.0))
	await _frames(2)
	_expect(_orders.is_empty() and _admissions.is_empty(), "orphan release or drag acquired ownership")
	_reset_case()
	_contact(612, GROUND, true)
	_contact(612, GROUND, false)
	_contact(612, GROUND + Vector2(100.0, 0.0), true)
	await _frames(2)
	_expect(_selection.get("_active_touch_indices").has(612), "old deferred release erased a reused ID")
	_contact(612, GROUND + Vector2(100.0, 0.0), false)
	await _frames(2)
	_expect(_orders.size() == 2 and _admissions == [612, 612], "reused ID lost a normal short tap")
	_expect_clean("reused ID")
	_reset_case()
	_selection.set_touch_area_selection_armed(true)
	_contact(734, GROUND, true)
	await _wait_until(Time.get_ticks_msec() + 390)
	_contact(734, GROUND, false)
	await _frames(2)
	_expect(_orders.is_empty() and not _selection.touch_area_selection_armed, "Area hold became a world context command")
	_expect_clean("Area")


func _test_sparse_release() -> void:
	_reset_case()
	_selection.set_process(false)
	_contact(809, GROUND, true)
	_drag(809, GROUND + Vector2(11.0, 0.0), Vector2(11.0, 0.0))
	await _wait_until(Time.get_ticks_msec() + 370)
	_contact(809, GROUND + Vector2(11.0, 0.0), false)
	await _frames(2)
	_expect(_orders.size() == 1 and int(_selection.touch_context_diagnostics.get("execution_count", 0)) == _context_count_before + 1, "sparse-frame release missed the real-time hold below the 12px pan boundary")
	_expect_clean("sparse release")
	_reset_case()
	_selection.set_process(false)
	_contact(821, GROUND, true)
	await _wait_until(Time.get_ticks_msec() + 370)
	_contact(821, GROUND + Vector2(13.0, 0.0), false)
	await _frames(2)
	_expect(_orders.is_empty(), "release-only displacement exceeded tolerance but issued a hold")
	_expect_clean("release displacement")


func _test_popup_contract() -> void:
	_reset_case()
	var opened_before: int = _popup_open_count
	var closed_before: int = _popup_close_count
	_contact(911, _resource.position, true)
	var popup_deadline: int = Time.get_ticks_msec() + 550
	while not _selection.is_hold_gesture_active() and Time.get_ticks_msec() < popup_deadline:
		await get_tree().process_frame
	_expect(not _selection.is_touch_context_open() and _orders.is_empty(), "a multi-action hold opened or acted before the finger lifted")
	_contact(911, _resource.position, false)
	await _frames(2)
	_expect(_selection.is_touch_context_open() and _popup_open_count == opened_before + 1, "multi-action world hold did not publish one popup opening")
	_expect(_selection.get_touch_context_rect().has_area(), "visible popup exposed no actual obstacle rectangle")
	_expect(_orders.is_empty(), "opening multi-action popup executed a command")
	_selection.close_touch_context()
	_selection.close_touch_context()
	_expect(not _selection.is_touch_context_open() and _selection.get_touch_context_rect() == Rect2() and _popup_close_count == closed_before + 1, "idempotent popup close emitted duplicate lifecycle events or retained bounds")
	await _frames(2)
	_expect(_orders.is_empty(), "closing the popup leaked a tap")
	_reset_case()
	_selection.set_unit_command_armed(true)
	_contact(923, _resource.position, true)
	await _wait_until(Time.get_ticks_msec() + 390)
	_contact(923, _resource.position, false)
	await _frames(2)
	_expect(_orders.size() == 1 and _orders[0]["action"] == "move" and not _selection.is_touch_context_open(), "armed destination hold offered or executed a conflicting Gather meaning")


func _test_lifecycle_cancel() -> void:
	_reset_case()
	_contact(1017, GROUND, true)
	_selection.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _wait_until(Time.get_ticks_msec() + 390)
	_contact(1017, GROUND, false)
	await _frames(2)
	_expect(_orders.is_empty(), "focus loss retained a pending hold")
	_expect_clean("focus loss")
	_reset_case()
	_contact(1029, GROUND, true)
	get_window().size = Vector2i(932, 430)
	await _wait_until(Time.get_ticks_msec() + 390)
	_contact(1029, GROUND, false)
	await _frames(2)
	_expect(_orders.is_empty(), "resize retained a pending hold")
	_expect_clean("resize")


func _test_main_selection_change() -> void:
	get_window().size = Vector2i(844, 390)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.set_state(GameManager.GameState.MENU)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	main.get("ai_controller").set_process(false)
	main.get("ai_controller").get("_decision_timer").stop()
	_selection = main.get("game_map").get("selection_mgr") as SelectionManager
	_unit = main.get("_player_units")[0][0] as Villager
	_selection.select_single(_unit)
	_orders.clear()
	_selection.move_command.connect(func(tile: Vector2i) -> void:
		_orders.append({"action": "move", "time_msec": Time.get_ticks_msec(), "tile": str(tile)}))
	_selection.queue_order_command.connect(func(position: Vector2, _target: Node2D) -> void:
		_orders.append({"action": "queue", "time_msec": Time.get_ticks_msec(), "tile": str(position)}))
	await _frames(3)
	_contact(1227, Vector2(350.0, 150.0), true)
	_expect(_selection.get("_active_touch_indices").has(1227) and bool(_selection.get("_touch_hold_active")), "actual Main did not admit the pending world hold")
	# The normal Home action replaces the worker selection while its finger is
	# still held. A routine status refresh must preserve a valid held context.
	main.call("_on_selection_changed", _selection.selected)
	_expect(_selection.get("_active_touch_indices").has(1227), "routine Main status refresh canceled an unchanged selection")
	var home := InputEventAction.new()
	home.action = "select_tc"
	home.pressed = true
	Input.parse_input_event(home)
	Input.flush_buffered_events()
	_expect(_selection.selected == [main.get("_player_town_center")], "actual Home action did not change selection")
	_expect_clean("Main selection changed before threshold")
	await _wait_until(Time.get_ticks_msec() + 390)
	_contact(1227, Vector2(350.0, 150.0), false)
	home.pressed = false
	Input.parse_input_event(home)
	Input.flush_buffered_events()
	await _frames(2)
	_expect(_orders.is_empty(), "old world hold issued a Move/rally for the replacement selection")
	_expect_clean("Main selection replacement release")
	await _test_main_move_intents(main)
	main.queue_free()
	await _frames(3)


func _test_main_move_intents(main: Node) -> void:
	# Real Main command dispatch on both phone canvases. One injected military
	# fixture isolates intent; this is not a paid training or movement test.
	var scout: UnitBase = null
	for unit: UnitBase in main.get("_player_units")[0]:
		unit.set_process(false)
		if unit.unit_type == UnitData.UnitType.SCOUT:
			scout = unit
	if scout == null:
		scout = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, _unit.position + Vector2(24, 0)) as UnitBase
	_expect(scout != null, "Main phone intent fixture has an owned military unit")
	if scout == null:
		return
	scout.set_process(false)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		get_window().size = phone
		get_window().content_scale_size = phone
		await _frames(3)
		for kind: String in ["tap", "hold", "pan", "pinch", "cancel"]:
			scout.command_stop()
			_selection.select_single(scout)
			_orders.clear()
			await _frames(3)
			var ground: Vector2 = _main_empty_ground(main)
			_expect(ground != Vector2.ZERO, "actual phone battlefield exposes an empty ground target")
			_contact(1501, ground, true)
			if kind == "tap":
				_contact(1501, ground, false)
			elif kind == "hold":
				await _wait_until(Time.get_ticks_msec() + 390)
				_expect(_orders.is_empty() and _selection.is_hold_gesture_active(), "real Main hold arms at threshold and waits for the lift")
				_contact(1501, ground, false)
			else:
				if kind == "pan":
					_drag(1501, ground + Vector2(20, 0), Vector2(20, 0))
					_drag(1501, ground, Vector2(-20, 0))
				elif kind == "pinch":
					_contact(1502, ground + Vector2(40, 0), true)
					_drag(1502, ground + Vector2(60, 0), Vector2(20, 0))
				else:
					_contact(1501, ground, false, true)
				await _wait_until(Time.get_ticks_msec() + 390)
				if kind == "pinch":
					_contact(1502, ground + Vector2(60, 0), false)
				if kind != "cancel":
					_contact(1501, ground, false)
			await _frames(2)
			if kind == "tap":
				_expect(_orders.size() == 1 and _orders[0]["action"] == "move" and not scout.attack_move and bool(scout.get("_force_move_active")), "actual phone ground tap delivers passive Move through Main")
			elif kind == "hold":
				_expect(_orders.size() == 1 and not scout.attack_move and bool(scout.get("_force_move_active")), "actual phone hold/release delivers one queued move through Main")
			else:
				_expect(_orders.is_empty() and scout.current_state == UnitBase.State.IDLE, "actual phone %s cannot leak Move or attack-move" % kind)
			_expect_clean("Main %s %s" % [phone, kind])
			_timing.append({"phone": str(phone), "gesture": kind, "orders": _orders.duplicate(true), "attack_move": scout.attack_move, "passive_move": scout.get("_force_move_active")})


func _main_empty_ground(main: Node) -> Vector2:
	var hud: CanvasLayer = main.get("hud")
	var bottom: float = (hud.get("selection_panel") as Control).get_global_rect().position.y - 24.0
	for y: int in range(100, int(bottom), 24):
		for x: int in range(210, int(get_viewport().get_visible_rect().size.x) - 210, 32):
			var point := Vector2(x, y)
			var world: Vector2 = _selection.call("_screen_to_world", point)
			if _selection.call("_get_node_at", world, true) == null and _selection.call("_get_resource_at", world, true) == null:
				return point
	return Vector2.ZERO


func _contact(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * point
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _drag(index: int, point: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * point
	event.relative = get_viewport().get_final_transform().basis_xform(relative)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func _wait_until(deadline: int) -> void:
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _expect_clean(context: String) -> void:
	_expect(_selection.get("_active_touch_indices").is_empty() and _selection.get("_released_world_touch_indices").is_empty() and int(_selection.get("_primary_touch_index")) == -1 and not bool(_selection.get("_touch_hold_active")), context + " left contact ownership or a pending hold")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
