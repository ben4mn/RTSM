extends Node
## Screen-space touch floor, independent of Web canvas backing-pixel density.

var _failures: Array[String] = []


func _ready() -> void:
	var base := Vector2(844, 390)
	for screen: Vector2 in [Vector2(667, 375), Vector2(579, 357), Vector2(844, 390), Vector2(756, 372), Vector2(932, 430), Vector2(844, 412)]:
		for preference: float in [1.0, 1.075, 1.15]:
			var factor: float = GameManager.display_scale_for_screen(screen, base, preference)
			var stretch: float = minf(screen.x / base.x, screen.y / base.y)
			var target: float = 48.0 * stretch * factor
			_expect(target >= 44.0 * preference - 0.01, "screen target below floor: %s at %.3f" % [screen, preference])
			_expect(factor >= preference, "preference reduced")
			if stretch >= 44.0 / 48.0:
				_expect(is_equal_approx(factor, preference), "roomy screen enlarged unnecessarily")
	_expect(GameManager.display_scale_for_screen(Vector2.ZERO, base, 1.075) == 1.075, "zero size must preserve preference")
	GameManager.ui_scale = 1.075
	get_window().size = Vector2i(666, 374)
	GameManager.apply_preferences()
	var expected: float = GameManager.display_scale_for_screen(Vector2(get_window().size), Vector2(get_window().content_scale_size), 1.075)
	if DisplayServer.get_name() == "headless":
		expected = 1.075
	_expect(is_equal_approx(get_window().content_scale_factor, expected), "runtime did not apply floor")
	_expect(is_equal_approx(GameManager.ui_scale, 1.075), "screen adaptation overwrote saved preference")
	for failure: String in _failures:
		push_error("[FAIL] phone_display_scale: " + failure)
	if _failures.is_empty():
		print("[PASS] phone_display_scale: 18 screen/preference profiles, minimum44 screen units, unchanged roomy screens and preserved user preference")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
