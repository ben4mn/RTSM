extends Node
## Deterministic regression for screen-pixel touch hit radii across camera zoom.

const TOUCH_RADIUS_PX := 24.0
const MIN_TOUCH_RADIUS_WORLD := 8.0
const EPSILON := 0.001

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)

	var game_map := Node2D.new()
	game_map.name = "FakeGameMap"
	add_child(game_map)

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	game_map.add_child(camera)

	var selection_manager := SelectionManager.new()
	selection_manager.name = "SelectionManager"
	selection_manager.touch_context_enabled = false
	selection_manager.touch_unit_hit_radius_px = TOUCH_RADIUS_PX
	selection_manager.game_map = game_map
	game_map.add_child(selection_manager)

	var unit := Node2D.new()
	unit.name = "TouchTarget"
	game_map.add_child(unit)
	unit.add_to_group("units")

	await get_tree().process_frame
	_test_zoom(selection_manager, camera, unit, 0.5, 48.0, "zoom-out")
	_test_zoom(selection_manager, camera, unit, 1.0, 24.0, "1x")
	_test_zoom(selection_manager, camera, unit, 2.0, 12.0, "zoom-in")
	_test_zoom(selection_manager, camera, unit, 4.0, MIN_TOUCH_RADIUS_WORLD, "minimum world-radius clamp")

	game_map.free()
	if _failures.is_empty():
		print("[PASS] touch_hit_radius_zoom: screen pixels divide by zoom and retain the world-radius floor")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] touch_hit_radius_zoom: %s" % failure)
	get_tree().quit(1)


func _test_zoom(
	selection_manager: SelectionManager,
	camera: Camera2D,
	unit: Node2D,
	zoom: float,
	expected_world_radius: float,
	label: String,
) -> void:
	camera.zoom = Vector2(zoom, zoom)
	var actual_world_radius: float = float(selection_manager.call("_screen_px_to_world_radius", TOUCH_RADIUS_PX))
	_expect_near(actual_world_radius, expected_world_radius, "%s radius conversion" % label)

	unit.global_position = Vector2(actual_world_radius - EPSILON, 0.0)
	_expect(
		selection_manager.call("_get_node_at", Vector2.ZERO, true) == unit,
		"%s rejects a unit just inside the touch radius" % label,
	)
	unit.global_position = Vector2(actual_world_radius + EPSILON, 0.0)
	_expect(
		selection_manager.call("_get_node_at", Vector2.ZERO, true) == null,
		"%s accepts a unit just outside the touch radius" % label,
	)


func _expect_near(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s: expected %.3f, got %.3f" % [message, expected, actual])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
