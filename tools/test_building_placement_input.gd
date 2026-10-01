extends Node
## Regression for UI-first touch routing while building placement is active.

const CANCEL_POSITION := Vector2(650.0, 318.0)
const CANCEL_SIZE := Vector2(178.0, 56.0)
const WORLD_TAP_POSITION := Vector2(240.0, 180.0)

var _failures: Array[String] = []
var _confirmed_count: int = 0
var _cancelled_count: int = 0
var _cancel_button_pressed_count: int = 0


class FakeGameMap extends Node2D:
	var unhandled_event_count: int = 0

	func is_tile_walkable(_tile_pos: Vector2i) -> bool:
		return true

	func is_tile_visible_to_player(_tile_pos: Vector2i, _viewer_player_id: int = 0) -> bool:
		return true

	func _unhandled_input(_event: InputEvent) -> void:
		unhandled_event_count += 1


class FakeSelectionManager extends Node2D:
	var unhandled_event_count: int = 0

	func _unhandled_input(_event: InputEvent) -> void:
		unhandled_event_count += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var world := FakeGameMap.new()
	world.name = "FakeGameMap"
	add_child(world)
	var selection := FakeSelectionManager.new()
	selection.name = "SelectionManager"
	world.add_child(selection)
	var placement := BuildingPlacement.new()
	placement.name = "BuildingPlacement"
	world.add_child(placement)
	placement.placement_confirmed.connect(_on_placement_confirmed)
	placement.placement_cancelled.connect(_on_placement_cancelled)

	var cancel_button := Button.new()
	cancel_button.name = "CancelPlacement"
	cancel_button.position = CANCEL_POSITION
	cancel_button.size = CANCEL_SIZE
	cancel_button.text = "Cancel Build"
	cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
	cancel_button.pressed.connect(_on_cancel_button_pressed.bind(placement))
	add_child(cancel_button)

	await get_tree().process_frame
	world.set_process_unhandled_input(true)
	selection.set_process_unhandled_input(true)
	placement.start_placement(BuildingData.BuildingType.HOUSE, 0)
	_expect(placement.is_processing_unhandled_input(), "placement did not enable UI-first unhandled input")
	_expect(placement.is_processing_input(), "placement did not enable non-consuming early release cleanup")
	_expect(world.is_processing_unhandled_input(), "placement blocked camera/map navigation")
	_expect(not selection.is_processing_unhandled_input(), "placement did not suspend selection input")
	# Early input owns bookkeeping only. The later unhandled callback can
	# reposition a world tap, but a GUI-consumed release cannot move the ghost.
	var ghost_before_cleanup: Vector2 = placement.ghost_position
	var owned_press := InputEventScreenTouch.new()
	owned_press.index = 47
	owned_press.pressed = true
	owned_press.position = WORLD_TAP_POSITION
	placement.call("_unhandled_input", owned_press)
	var early_release := InputEventScreenTouch.new()
	early_release.index = 47
	early_release.position = CANCEL_POSITION
	placement.call("_input", early_release)
	_expect(placement.ghost_position == ghost_before_cleanup, "early cleanup moved the ghost before GUI routing")
	_expect(_confirmed_count == 0 and _cancelled_count == 0, "early cleanup confirmed or canceled placement")
	_expect((placement.get("_touch_points") as Dictionary).is_empty(), "early cleanup retained a world contact")

	var cancel_center: Vector2 = CANCEL_POSITION + CANCEL_SIZE * 0.5
	_push_gui_pointer(cancel_center, true)
	await get_tree().process_frame
	_push_gui_pointer(cancel_center, false)
	await get_tree().process_frame
	_expect(_cancel_button_pressed_count == 1, "Cancel touch did not activate the GUI button exactly once")
	_expect(_confirmed_count == 0, "Cancel touch emitted placement_confirmed")
	_expect(_cancelled_count == 1, "Cancel touch did not emit placement_cancelled exactly once")
	_expect(not placement.active, "placement remained active after GUI Cancel")
	_expect(not placement.is_processing_unhandled_input(), "placement input remained enabled after GUI Cancel")
	_expect(world.is_processing_unhandled_input(), "camera/map input was not restored after cancel")
	_expect(selection.is_processing_unhandled_input(), "selection input was not restored after cancel")

	placement.start_placement(BuildingData.BuildingType.HOUSE, 0)
	_expect(world.is_processing_unhandled_input(), "second placement blocked camera/map navigation")
	_expect(not selection.is_processing_unhandled_input(), "second placement did not suspend selection input")
	_push_touch(WORLD_TAP_POSITION, true)
	await get_tree().process_frame
	_push_touch(WORLD_TAP_POSITION, false)
	await get_tree().process_frame
	_expect(_confirmed_count == 0, "world touch spent before the explicit Place action")
	_expect(_cancelled_count == 1, "world touch unexpectedly emitted placement_cancelled")
	_expect(placement.active and placement.is_valid_placement, "world touch did not leave a valid preview for inspection")
	_expect(not selection.is_processing_unhandled_input(), "preview touch restored unit orders before confirmation")

	# Use a real Control for the explicit Place action too: it must consume its
	# pointer event before the world sees a desktop click at the button's tile.
	cancel_button.pressed.disconnect(_on_cancel_button_pressed.bind(placement))
	cancel_button.text = "Place"
	cancel_button.pressed.connect(func() -> void: placement.confirm_preview())
	_push_gui_pointer(cancel_center, true)
	await get_tree().process_frame
	_push_gui_pointer(cancel_center, false)
	await get_tree().process_frame
	_expect(_confirmed_count == 1, "GUI Place did not confirm the inspected foundation exactly once")
	_expect(not placement.active, "placement remained active after explicit Place")
	_expect(not placement.is_processing_unhandled_input(), "placement input remained enabled after confirmation")
	_expect(world.is_processing_unhandled_input(), "camera/map input was not restored after confirmation")
	_expect(selection.is_processing_unhandled_input(), "selection input was not restored after confirmation")

	placement.free()
	cancel_button.free()
	world.free()
	if _failures.is_empty():
		print("[PASS] building_placement_input: GUI Cancel/Place isolated; touch previews; camera and selection restore")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] building_placement_input: %s" % failure)
	get_tree().quit(1)


func _push_touch(position: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = position
	touch.pressed = pressed
	get_viewport().push_input(touch, true)


func _push_gui_pointer(position: Vector2, pressed: bool) -> void:
	# Touchscreen taps are emulated as primary-pointer button events for Godot
	# Controls. Push the local event directly so this remains deterministic with
	# the headless display driver's tiny backing surface.
	var pointer := InputEventMouseButton.new()
	pointer.button_index = MOUSE_BUTTON_LEFT
	pointer.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	pointer.position = position
	pointer.global_position = position
	pointer.pressed = pressed
	get_viewport().push_input(pointer, true)


func _on_placement_confirmed(_building_type: int, _position: Vector2) -> void:
	_confirmed_count += 1


func _on_placement_cancelled() -> void:
	_cancelled_count += 1


func _on_cancel_button_pressed(placement: BuildingPlacement) -> void:
	_cancel_button_pressed_count += 1
	placement.cancel_placement()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
