extends Node
## A touch gesture can inspect and reposition a foundation without spending;
## only explicit confirmation commits, with authoritative revalidation.

var _failures: Array[String] = []
var _confirmations: int = 0
var _preview_events: int = 0


class PreviewMap extends Node2D:
	var blocked: bool = false

	func world_to_tile(world_pos: Vector2) -> Vector2i:
		var half_w: float = MapData.TILE_WIDTH * 0.5
		var half_h: float = MapData.TILE_HEIGHT * 0.5
		return Vector2i(roundi((world_pos.x / half_w + world_pos.y / half_h) * 0.5), roundi((world_pos.y / half_h - world_pos.x / half_w) * 0.5))

	func tile_to_world(tile_pos: Vector2i) -> Vector2:
		return Vector2((tile_pos.x - tile_pos.y) * MapData.TILE_WIDTH * 0.5, (tile_pos.x + tile_pos.y) * MapData.TILE_HEIGHT * 0.5)

	func is_tile_visible_to_player(_tile: Vector2i, _owner: int = 0) -> bool:
		return true

	func is_tile_buildable(_tile: Vector2i) -> bool:
		return not blocked

	func _unhandled_input(_event: InputEvent) -> void:
		pass


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var world := PreviewMap.new()
	add_child(world)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = world.tile_to_world(Vector2i(10, 10))
	world.add_child(camera)
	var selection := SelectionManager.new()
	selection.name = "SelectionManager"
	selection.touch_context_enabled = false
	world.add_child(selection)
	var placement := BuildingPlacement.new()
	world.add_child(placement)
	placement.placement_confirmed.connect(func(_kind: int, _pos: Vector2) -> void: _confirmations += 1)
	placement.preview_changed.connect(func(_valid: bool, _reason: String) -> void: _preview_events += 1)
	await get_tree().process_frame

	selection.set("_touch_hold_active", true)
	selection.set("_active_touch_indices", {0: true})
	placement.start_placement(BuildingData.BuildingType.HOUSE)
	_expect(placement.visible and placement.is_valid_placement, "placement opens with a visible, validated preview")
	_expect(world.world_to_tile(placement.ghost_position) == Vector2i(10, 10), "initial preview is centered in the camera view")
	_expect(not selection.is_processing_unhandled_input(), "placement suspends unit orders")
	_expect(not bool(selection.get("_touch_hold_active")), "placement cancels a pending long-press order")
	_expect((selection.get("_active_touch_indices") as Dictionary).is_empty(), "placement clears the previous finger gesture")
	_expect(world.is_processing_unhandled_input(), "camera input remains available during placement")

	# L2: a tap away from the ghost moves it there (footprint centred under the
	# finger) and never builds.
	var first_pos: Vector2 = _footprint_center_screen(placement, world, Vector2i(15, 15))
	_expect(not placement.is_screen_point_on_ghost(first_pos), "fixture: the tap lands off the ghost")
	placement.call("_unhandled_input", _touch(0, first_pos, true))
	_expect_eq(_confirmations, 0, "touch-down never places a building")
	placement.call("_unhandled_input", _touch(0, first_pos, false))
	_expect(world.world_to_tile(placement.ghost_position) == Vector2i(15, 15), "a world tap repositions the preview")
	_expect_eq(_confirmations, 0, "a tap off the ghost never builds")

	# A drag that starts on the ghost carries it.
	var dragged_pos: Vector2 = _footprint_center_screen(placement, world, Vector2i(16, 16))
	placement.call("_unhandled_input", _touch(0, first_pos, true))
	placement.call("_unhandled_input", _drag(0, dragged_pos, dragged_pos - first_pos))
	_expect(world.world_to_tile(placement.ghost_position) == Vector2i(16, 16), "drag repositions the ghost")
	_expect_eq(_confirmations, 0, "drag cannot spend resources")
	placement.call("_unhandled_input", _touch(0, dragged_pos, false))
	_expect_eq(_confirmations, 0, "releasing a ghost drag does not build")
	first_pos = _footprint_center_screen(placement, world, Vector2i(12, 20))

	var ghost_before: Vector2 = placement.ghost_position
	placement.call("_unhandled_input", _touch(0, first_pos, true))
	placement.call("_unhandled_input", _touch(1, first_pos + Vector2(100.0, 0.0), true))
	placement.call("_unhandled_input", _drag(1, first_pos + Vector2(130.0, 0.0), Vector2(30.0, 0.0)))
	_expect(placement.ghost_position == ghost_before, "two-finger navigation leaves the chosen foundation in place")
	placement.call("_unhandled_input", _touch(1, first_pos + Vector2(130.0, 0.0), false))
	placement.call("_unhandled_input", _touch(0, first_pos, false))
	_expect(placement.ghost_position == ghost_before, "releasing a camera gesture cannot relocate the foundation")

	world.blocked = true
	_expect(not placement.confirm_preview(), "Place revalidates newly blocked terrain")
	_expect_eq(_confirmations, 0, "invalid explicit Place cannot commit")
	_expect(placement.active, "rejected Place keeps the preview available for correction")
	world.blocked = false
	_expect(placement.confirm_preview(), "valid explicit Place confirms")
	_expect_eq(_confirmations, 1, "explicit Place commits exactly once")
	_expect(not placement.confirm_preview(), "a second Place cannot commit again")
	_expect(selection.is_processing_unhandled_input(), "successful placement restores unit orders")
	_expect(_preview_events >= 3, "preview state is reported to the HUD")

	# A tap on the ghost itself builds it where it is drawn.
	placement.start_placement(BuildingData.BuildingType.HOUSE)
	placement.update_preview_at_world(world.tile_to_world(Vector2i(18, 18)))
	var on_ghost: Vector2 = _footprint_center_screen(placement, world, Vector2i(18, 18))
	await _real_wait(400)
	placement.call("_unhandled_input", _touch(3, on_ghost, true))
	placement.call("_unhandled_input", _touch(3, on_ghost, false))
	_expect_eq(_confirmations, 2, "a tap on the ghost builds it (on ghost %s, valid %s, active %s, since %d, pts %s)" % [placement.is_screen_point_on_ghost(on_ghost), placement.is_valid_placement, placement.active, Time.get_ticks_msec() - int(placement.get("_last_confirm_msec")), placement.get("_touch_points")])
	_confirmations = 1

	# Real desktop clicks keep the existing immediate placement workflow.
	placement.start_placement(BuildingData.BuildingType.HOUSE)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = placement.get_canvas_transform() * world.tile_to_world(Vector2i(15, 15))
	placement.call("_unhandled_input", click)
	_expect_eq(_confirmations, 2, "desktop left click still places immediately")

	world.free()
	if _failures.is_empty():
		print("[PASS] touch_placement_preview: inspect/drag, camera gesture, explicit Place, revalidation, desktop parity")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] touch_placement_preview: %s" % failure)
		get_tree().quit(1)


func _footprint_center_screen(placement: BuildingPlacement, world: Node2D, origin: Vector2i) -> Vector2:
	var center: Vector2 = world.call("tile_to_world", origin)
	var axis_x: Vector2 = (world.call("tile_to_world", origin + Vector2i(1, 0)) as Vector2) - center
	var axis_y: Vector2 = (world.call("tile_to_world", origin + Vector2i(0, 1)) as Vector2) - center
	return placement.get_canvas_transform() * (center + (axis_x + axis_y) * 0.5)


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	return event


func _drag(index: int, pos: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


## Real (wall-clock) time: the 0.35 s double-confirm guard is measured in it.
func _real_wait(msec: int) -> void:
	var until: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
