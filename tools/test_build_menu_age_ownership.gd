extends Node
## Regression: AI progression must never unlock the human Build palette.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(844, 390)
	add_child(viewport)
	var host := Control.new()
	host.size = Vector2(844, 390)
	viewport.add_child(host)
	var build_menu: PanelContainer = load("res://scenes/ui/build_menu.tscn").instantiate() as PanelContainer
	host.add_child(build_menu)
	await get_tree().process_frame
	build_menu.call("update_resources", {"food": 5000, "wood": 5000, "gold": 5000})
	build_menu.call("open_menu")
	await get_tree().process_frame

	_assert_card_lock(build_menu, BuildingData.BuildingType.ARCHERY_RANGE, true, "initial human Dark Age")
	_expect_eq(int(build_menu.get("_current_age")), 1, "palette did not initialize from human age")

	_expect(GameManager.advance_age(1), "AI failed to advance to Feudal Age")
	await get_tree().process_frame
	_expect_eq(GameManager.get_player_age(1), 2, "AI age did not advance")
	_expect_eq(GameManager.get_player_age(0), 1, "human age changed with AI age-up")
	_expect_eq(int(build_menu.get("_current_age")), 1, "AI age-up changed the human palette age")
	_assert_card_lock(build_menu, BuildingData.BuildingType.ARCHERY_RANGE, true, "after AI age-up")

	# Reopening also synchronizes from the palette owner rather than whichever
	# player most recently emitted the global progression signal.
	build_menu.call("close_menu")
	build_menu.call("open_menu")
	await get_tree().process_frame
	_expect_eq(int(build_menu.get("_current_age")), 1, "reopen synchronized the palette from AI age")
	_assert_card_lock(build_menu, BuildingData.BuildingType.ARCHERY_RANGE, true, "after reopen")

	_expect(GameManager.advance_age(0), "human failed to advance to Feudal Age")
	await get_tree().process_frame
	_expect_eq(int(build_menu.get("_current_age")), 2, "human age-up did not refresh the palette")
	_assert_card_lock(build_menu, BuildingData.BuildingType.ARCHERY_RANGE, false, "after human age-up")

	build_menu.free()
	viewport.free()
	if _failures.is_empty():
		print("[PASS] build_menu_age_ownership: AI age-up stays isolated; human age-up unlocks palette")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] build_menu_age_ownership: %s" % failure)
	get_tree().quit(1)


func _assert_card_lock(build_menu: PanelContainer, building_type: int, expected_locked: bool, context: String) -> void:
	var button_map: Dictionary = build_menu.get("_button_map")
	_expect(button_map.has(building_type), "%s: target building card is missing" % context)
	if not button_map.has(building_type):
		return
	var button: Button = button_map[building_type] as Button
	var actual_locked: bool = bool(button.get_meta("age_locked", false))
	_expect_eq(actual_locked, expected_locked, "%s: age lock is wrong" % context)
	_expect_eq(button.disabled, expected_locked, "%s: enabled state is wrong with ample resources" % context)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
