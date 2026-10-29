extends Node
## Real viewport dispatch for world holds that wait for the finger to lift:
## lift in place = the hold action, pull down = attack-move at the hold point,
## drag from a producer = rally at the release point, any other drag = a box.

const HOLD_MSEC := 420

class FakeGameMap extends Node2D:
	var selection_mgr: SelectionManager = null
	func world_to_tile(world_pos: Vector2) -> Vector2i:
		return Vector2i(roundi(world_pos.x / 16.0), roundi(world_pos.y / 16.0))

var _selection: SelectionManager
var _unit: Villager
var _barracks: BuildingBase
var _orders: Array[Dictionary] = []
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	Input.emulate_touch_from_mouse = false
	Input.emulate_mouse_from_touch = false
	var game_map := FakeGameMap.new()
	add_child(game_map)
	_selection = SelectionManager.new()
	_selection.game_map = game_map
	game_map.selection_mgr = _selection
	game_map.add_child(_selection)
	_unit = load("res://scenes/units/villager.tscn").instantiate() as Villager
	_unit.position = Vector2(300.0, 200.0)
	game_map.add_child(_unit)
	_unit.set_process(false)
	_barracks = (load("res://scenes/buildings/barracks.tscn") as PackedScene).instantiate() as BuildingBase
	_barracks.player_owner = 0
	_barracks.position = Vector2(700.0, 120.0)
	game_map.add_child(_barracks)
	_barracks.complete_instantly()
	_barracks.set_process(false)
	_selection.move_command.connect(func(tile: Vector2i) -> void: _orders.append({"action": "move", "tile": tile}))
	_selection.attack_move_command.connect(func(tile: Vector2i) -> void: _orders.append({"action": "attack_move", "tile": tile}))
	_selection.queue_order_command.connect(func(position: Vector2, _target: Node2D) -> void: _orders.append({"action": "queue", "position": position}))
	await _frames(3)

	# Lift in place: nothing happens until the finger lifts, then the hold action.
	_reset(true)
	_contact(1, Vector2(440, 200), true)
	await _wait(HOLD_MSEC)
	_expect(_orders.is_empty(), "a hold acted before the finger lifted")
	_expect(_selection.is_hold_gesture_active(), "a 420 ms still hold should arm the gesture")
	_contact(1, Vector2(442, 201), false)
	await _frames(2)
	_expect(_orders.size() == 1 and _orders[0]["action"] == "queue", "lifting a hold in place should queue a move: %s" % str(_orders))

	# Pull down: attack-move to where the finger was held.
	_reset(true)
	_contact(2, Vector2(440, 160), true)
	await _wait(HOLD_MSEC)
	_drag(2, Vector2(442, 200))
	_drag(2, Vector2(444, 250))
	await _frames(1)
	_expect(_selection.hold_gesture_kind(Vector2(444, 250)) == "attack_move", "a pull down should read as attack-move")
	_contact(2, Vector2(444, 250), false)
	await _frames(2)
	_expect(_orders.size() == 1 and _orders[0]["action"] == "attack_move" and _orders[0]["tile"] == Vector2i(roundi(440.0 / 16.0), roundi(160.0 / 16.0)), "pull down should attack-move to the held spot: %s" % str(_orders))

	# Sideways drag: a box that selects the villager inside it.
	_reset(false)
	_contact(3, Vector2(250, 150), true)
	await _wait(HOLD_MSEC)
	_drag(3, Vector2(300, 190))
	_drag(3, Vector2(360, 250))
	_contact(3, Vector2(360, 250), false)
	await _frames(2)
	_expect(_orders.is_empty(), "a box should not order anyone: %s" % str(_orders))
	_expect(_selection.selected == [_unit], "the box should select the villager inside it")

	# With nothing selected even a downward drag is a box, never an order.
	_reset(false)
	_contact(4, Vector2(300, 140), true)
	await _wait(HOLD_MSEC)
	_drag(4, Vector2(305, 260))
	_contact(4, Vector2(305, 260), false)
	await _frames(2)
	_expect(_orders.is_empty(), "a downward box with nothing selected should not order")

	# Hold a producer and drag to the ground: its rally point.
	_reset(true)
	var on_barracks: Vector2 = _barracks.global_position + Vector2(0, -20)
	_contact(5, on_barracks, true)
	await _wait(HOLD_MSEC)
	_drag(5, Vector2(560, 300))
	_contact(5, Vector2(560, 300), false)
	await _frames(2)
	_expect(_selection.selected == [_barracks], "a rally drag should select its building")
	_expect(_orders.size() == 1 and _orders[0]["action"] == "move" and _orders[0]["tile"] == Vector2i(35, 19), "a rally drag should set the rally at the release point: %s" % str(_orders))

	# A quick drag before the hold time is still a pan: no gesture, no order.
	_reset(true)
	_contact(6, Vector2(440, 200), true)
	await _wait(80)
	_drag(6, Vector2(480, 220))
	await _wait(HOLD_MSEC)
	_expect(not _selection.is_hold_gesture_active(), "a pan should never arm a hold gesture")
	_contact(6, Vector2(480, 220), false)
	await _frames(2)
	_expect(_orders.is_empty(), "a pan should not order")

	# A second finger cancels an armed hold.
	_reset(true)
	_contact(7, Vector2(440, 200), true)
	await _wait(HOLD_MSEC)
	_contact(8, Vector2(600, 200), true)
	await _frames(1)
	_expect(not _selection.is_hold_gesture_active(), "a pinch should cancel an armed hold")
	_contact(8, Vector2(600, 200), false)
	_contact(7, Vector2(440, 200), false)
	await _frames(2)
	_expect(_orders.is_empty(), "a canceled hold should not order")

	if _failures.is_empty():
		print("[PASS] hold_gestures: lift in place queues, pull down attack-moves, drag boxes, producer drag rallies, pans and pinches never arm")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] hold_gestures: %s" % failure)
		get_tree().quit(1)


func _reset(select_unit: bool) -> void:
	_selection.cancel_touch_gesture()
	_selection.call("_clear_selection")
	if select_unit:
		_selection.select_single(_unit)
	_orders.clear()


func _contact(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * point
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func _wait(msec: int) -> void:
	var deadline: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
