extends Node
## Dense phone armies retain exact head/body selection at overview and detail.

var _failures: Array[String] = []
var _move_count: int = 0


class FakeGameMap extends Node2D:
	func world_to_tile(world_pos: Vector2) -> Vector2i:
		return Vector2i(roundi(world_pos.x), roundi(world_pos.y))


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var world := FakeGameMap.new()
	add_child(world)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	world.add_child(camera)
	var selection := SelectionManager.new()
	selection.touch_context_enabled = false
	selection.game_map = world
	world.add_child(selection)
	selection.move_command.connect(func(_tile: Vector2i) -> void: _move_count += 1)
	var scene: PackedScene = load("res://scenes/units/infantry.tscn")
	var units: Array[UnitBase] = []
	for row in range(5):
		for column in range(8):
			var unit: UnitBase = scene.instantiate() as UnitBase
			unit.player_owner = 0
			unit.position = Vector2(float(column) * 34.0 - 119.0, float(row) * 34.0 - 68.0)
			world.add_child(unit)
			unit.set_process(false)
			units.append(unit)
	await get_tree().process_frame

	for zoom: float in [0.62, 0.952, 2.2]:
		camera.zoom = Vector2(zoom, zoom)
		camera.reset_smoothing()
		camera.force_update_scroll()
		for unit: UnitBase in units:
			# Infantry's visible head sits about 20 world units above its feet.
			# A neighbor above is therefore closer by feet distance alone.
			for offset: Vector2 in [Vector2(0.0, -20.0), Vector2(0.0, -10.0), Vector2.ZERO]:
				var tap_world: Vector2 = unit.global_position + offset
				var picked: Node2D = selection.call("_get_node_at", tap_world, true) as Node2D
				_expect(picked == unit, "zoom %.3f picked a neighboring soldier at %s on %s" % [zoom, offset, unit.name])
				selection.select_single(units[0])
				selection.set("_last_tap_time", 0.0)
				_push_tap(selection.call("_world_to_screen", tap_world))
				_expect(selection.selected.size() == 1 and selection.selected[0] == unit, "zoom %.3f head/body tap failed to switch selection" % zoom)
	_expect(_move_count == 0, "visible soldier taps issued ground moves")

	# A stationary two-finger camera gesture must never become a unit tap,
	# regardless of which finger is placed or lifted first.
	var camera_touch_target: Vector2 = selection.call("_world_to_screen", units[20].global_position + Vector2(0.0, -20.0))
	for press_order: Vector2i in [Vector2i(0, 1), Vector2i(1, 0)]:
		for release_order: Vector2i in [Vector2i(0, 1), Vector2i(1, 0)]:
			selection.select_single(units[0])
			selection.set("_last_tap_time", 0.0)
			var positions: Array[Vector2] = [camera_touch_target, camera_touch_target + Vector2(70.0, 0.0)]
			_push_touch(press_order.x, positions[press_order.x], true)
			_push_touch(press_order.y, positions[press_order.y], true)
			_push_touch(release_order.x, positions[release_order.x], false)
			_push_touch(release_order.y, positions[release_order.y], false)
			_expect(selection.selected.size() == 1 and selection.selected[0] == units[0], "camera touch order %s/%s selected a soldier" % [press_order, release_order])
	_expect(_move_count == 0, "stationary camera gestures issued ground moves")

	# Simulate a HUD accepting the release after the early input callback. A
	# subsequent real viewport tap must recover even if either finger ended
	# over the interface and never reached unhandled input.
	for consumed_index: int in [0, 1]:
		selection.select_single(units[0])
		selection.set("_last_tap_time", 0.0)
		var positions: Array[Vector2] = [camera_touch_target, camera_touch_target + Vector2(70.0, 0.0)]
		_push_touch(0, positions[0], true)
		_push_touch(1, positions[1], true)
		var consumed_release := InputEventScreenTouch.new()
		consumed_release.index = consumed_index
		consumed_release.position = positions[consumed_index]
		consumed_release.pressed = false
		selection.call("_input", consumed_release)
		_push_touch(1 - consumed_index, positions[1 - consumed_index], false)
		_expect((selection.get("_active_touch_indices") as Dictionary).is_empty(), "HUD release left a stale selection finger")
		_expect(selection.selected.size() == 1 and selection.selected[0] == units[0], "HUD release selected a soldier")
		_push_tap(camera_touch_target)
		_expect(selection.selected.size() == 1 and selection.selected[0] == units[20], "tap did not recover after a HUD-consumed release")
	selection.touch_context_enabled = true
	_push_touch(0, camera_touch_target, true)
	var consumed_hold_release := InputEventScreenTouch.new()
	consumed_hold_release.index = 0
	consumed_hold_release.position = camera_touch_target
	consumed_hold_release.pressed = false
	selection.call("_input", consumed_hold_release)
	_expect(not bool(selection.get("_touch_hold_active")), "HUD-consumed release left a delayed long press active")
	selection.touch_context_enabled = false
	_expect(_move_count == 0, "HUD-consumed camera releases issued ground moves")

	# Armed Move remains a destination even when touching a dense army body.
	selection.select_single(units[0])
	selection.set_unit_command_armed(true)
	var armed_target: Vector2 = selection.call("_world_to_screen", units[20].global_position + Vector2(0.0, -20.0))
	_push_tap(armed_target)
	_expect(selection.selected.size() == 1 and selection.selected[0] == units[0], "body priority replaced an explicitly armed selection")
	_expect(_move_count == 1, "armed body tap did not issue its destination exactly once")

	world.free()
	if _failures.is_empty():
		print("[PASS] overview_unit_discrimination: 40 soldiers, 360 viewport body taps; finger order, HUD release recovery and armed Move retained")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] overview_unit_discrimination: %s" % failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _push_tap(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		_push_touch(0, position, pressed)


func _push_touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	get_viewport().push_input(event, true)
