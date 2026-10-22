extends Node
## Web insets are normalized CSS fractions, not Retina pixels or native display coordinates.

const BRIDGE: Script = preload("res://scripts/ui/web_shell_bridge.gd")
var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	var viewport := Vector2(844.0, 390.0)
	var full := Rect2(Vector2.ZERO, viewport)
	_check(viewport, [0.0, 0.0, 0.0, 0.0], full, "unnotched full viewport")
	_check(viewport, [48.0 / 844.0, 0.0, 24.0 / 844.0, 21.0 / 390.0], Rect2(48, 0, 772, 369), "asymmetric landscape")
	_check(viewport, [24.0 / 844.0, 0.0, 48.0 / 844.0, 21.0 / 390.0], Rect2(24, 0, 772, 369), "reversed landscape same backing dimensions")
	_check(viewport, [0.0, 28.0 / 390.0, 0.0, 16.0 / 390.0], Rect2(0, 28, 844, 346), "top and bottom insets")
	# A 3x backing buffer has the same normalized fractions; UI scale changes
	# logical coordinates once, while the physically safe edges stay identical.
	var scaled := viewport / 1.15
	_check(scaled, [48.0 / 844.0, 0.0, 24.0 / 844.0, 21.0 / 390.0], Rect2(Vector2(48, 0) / 1.15, Vector2(772, 369) / 1.15), "115 percent UI scale")
	_check(Vector2(1280, 590), [81.0 / 1280.0, 0.0, 81.0 / 1280.0, 25.0 / 590.0], Rect2(81, 0, 1118, 565), "reported phone screenshot")
	_check(Vector2(390, 844), [0.0, 47.0 / 844.0, 0.0, 34.0 / 844.0], Rect2(0, 47, 390, 763), "portrait safe content")
	var malformed: Array[Array] = [
		[], [0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0],
		["0.1", 0, 0, 0], [true, 0, 0, 0], [null, 0, 0, 0],
		[{}, 0, 0, 0], [[], 0, 0, 0],
		[NAN, 0, 0, 0], [0, INF, 0, 0], [0, 0, -INF, 0],
		[-0.1, 0, 0, 0], [0, 0, 1.1, 0],
		[1, 0, 0, 0], [0.6, 0, 0.4, 0], [0, 0.6, 0, 0.5],
	]
	for index: int in malformed.size():
		_check(viewport, malformed[index], full, "malformed safe area %d" % index)
	if _failures.is_empty():
		print("[PASS] web_safe_area: %d normalized CSS mapping, orientation, UI-scale and malformed-payload checks" % _checks)
	else:
		for failure: String in _failures:
			push_error("[FAIL] web_safe_area: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(viewport: Vector2, insets: Array, expected: Rect2, label: String) -> void:
	_checks += 1
	var actual: Rect2 = BRIDGE.map_safe_area_insets(viewport, insets)
	if actual.position.distance_to(expected.position) > 0.01 or actual.size.distance_to(expected.size) > 0.01:
		_failures.append("%s expected %s, got %s" % [label, expected, actual])
