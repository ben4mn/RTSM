extends Node

const HUD_SCRIPT := preload("res://scripts/ui/hud.gd")
const TARGET_VIEWPORT := Vector2(844.0, 390.0)
const EPSILON := 0.01


func _ready() -> void:
	var failures: Array[String] = []
	_expect_equal(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		TARGET_VIEWPORT.x,
		"project viewport width",
		failures
	)
	_expect_equal(
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 0)),
		TARGET_VIEWPORT.y,
		"project viewport height",
		failures
	)
	var root_window: Window = get_tree().root
	_expect_vector(root_window.content_scale_size, TARGET_VIEWPORT, "runtime content scale size", failures)

	_expect_rect(
		HUD_SCRIPT.map_display_safe_area_to_viewport(
			Rect2(Vector2.ZERO, TARGET_VIEWPORT),
			Rect2(Vector2.ZERO, TARGET_VIEWPORT),
			TARGET_VIEWPORT
		),
		Rect2(Vector2.ZERO, TARGET_VIEWPORT),
		"1x full display",
		failures
	)
	_expect_rect(
		HUD_SCRIPT.map_display_safe_area_to_viewport(
			Rect2(Vector2.ZERO, Vector2(2532.0, 1170.0)),
			Rect2(Vector2.ZERO, Vector2(2532.0, 1170.0)),
			TARGET_VIEWPORT
		),
		Rect2(Vector2.ZERO, TARGET_VIEWPORT),
		"3x full display",
		failures
	)
	_expect_rect(
		HUD_SCRIPT.map_display_safe_area_to_viewport(
			Rect2(Vector2(232.0, 50.0), Vector2(2268.0, 1116.0)),
			Rect2(Vector2(100.0, 50.0), Vector2(2532.0, 1170.0)),
			TARGET_VIEWPORT
		),
		Rect2(Vector2(44.0, 0.0), Vector2(756.0, 372.0)),
		"3x asymmetric inset with non-zero display origin",
		failures
	)
	_expect_rect(
		HUD_SCRIPT.map_display_safe_area_to_viewport(
			Rect2(),
			Rect2(Vector2.ZERO, Vector2(2532.0, 1170.0)),
			TARGET_VIEWPORT
		),
		Rect2(Vector2.ZERO, TARGET_VIEWPORT),
		"invalid safe area fallback",
		failures
	)

	if failures.is_empty():
		print("PASS: mobile viewport and safe-area coordinate mapping")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _expect_rect(actual: Rect2, expected: Rect2, label: String, failures: Array[String]) -> void:
	if actual.position.distance_to(expected.position) > EPSILON or actual.size.distance_to(expected.size) > EPSILON:
		failures.append("%s: expected %s, got %s" % [label, expected, actual])


func _expect_equal(actual: float, expected: float, label: String, failures: Array[String]) -> void:
	if absf(actual - expected) > EPSILON:
		failures.append("%s: expected %.2f, got %.2f" % [label, expected, actual])


func _expect_vector(actual: Vector2, expected: Vector2, label: String, failures: Array[String]) -> void:
	if actual.distance_to(expected) > EPSILON:
		failures.append("%s: expected %s, got %s" % [label, expected, actual])
