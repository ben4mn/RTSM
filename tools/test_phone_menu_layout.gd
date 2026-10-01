extends Node
## Real-layout regression for the phone-sized first-session menu and settings surfaces.

const PHYSICAL_PHONE_SIZE := Vector2i(844, 390)
const MAX_UI_SCALE := 1.15
const LANDSCAPE_SIDE_INSET := 44.0
const LANDSCAPE_BOTTOM_INSET := 18.0
const MIN_PHYSICAL_TOUCH_TARGET := 48.0
const MAX_TOUCH_TARGET_ASPECT_RATIO := 8.0  # Full-width thumb actions are intentional.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	await _exercise_layout(1.0, false)
	await _exercise_layout(MAX_UI_SCALE, true)

	if _failures.is_empty():
		print("[PASS] phone_menu_layout: menu/settings fit 844x390 at 1.0/1.15 scale with safe areas and 48px targets")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] phone_menu_layout: %s" % failure)
	get_tree().quit(1)


func _exercise_layout(ui_scale: float, notched: bool) -> void:
	# Window.content_scale_factor reduces the logical layout surface as UI grows.
	# Build that effective canvas directly and convert target sizes back to
	# physical pixels for the acceptance checks.
	var logical_size := Vector2(
		floorf(float(PHYSICAL_PHONE_SIZE.x) / ui_scale),
		floorf(float(PHYSICAL_PHONE_SIZE.y) / ui_scale)
	)
	var safe_area := Rect2(Vector2.ZERO, logical_size)
	if notched:
		var side_inset: float = LANDSCAPE_SIDE_INSET / ui_scale
		var bottom_inset: float = LANDSCAPE_BOTTOM_INSET / ui_scale
		safe_area = Rect2(
			Vector2(side_inset, 0.0),
			Vector2(logical_size.x - side_inset * 2.0, logical_size.y - bottom_inset)
		)

	var phone_viewport := SubViewport.new()
	phone_viewport.size = Vector2i(logical_size)
	add_child(phone_viewport)
	var menu_scene: PackedScene = load("res://scenes/ui/main_menu.tscn")
	var menu: Control = menu_scene.instantiate() as Control
	# A full-rect Control only resolves its anchors after it enters a parent
	# Control. Give the isolated root the same logical rect it receives in-game.
	menu.anchor_left = 0.0
	menu.anchor_top = 0.0
	menu.anchor_right = 0.0
	menu.anchor_bottom = 0.0
	menu.position = Vector2.ZERO
	menu.size = logical_size
	phone_viewport.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	menu.call("apply_mobile_layout", logical_size, safe_area)
	await get_tree().process_frame
	await get_tree().process_frame
	menu.call("_refresh_main_menu_diagnostics")

	var suffix := "844x390 scale %.2f%s" % [ui_scale, " notched" if notched else ""]
	var diagnostics: Dictionary = menu.get("main_menu_diagnostics")
	if not bool(diagnostics.get("compact_layout", false)):
		_failures.append("%s menu did not select compact layout" % suffix)
	_expect_near(float(diagnostics.get("viewport_width", 0.0)), logical_size.x, "%s menu viewport width" % suffix)
	_expect_near(float(diagnostics.get("viewport_height", 0.0)), logical_size.y, "%s menu viewport height" % suffix)
	_check_safe_area(diagnostics, safe_area, suffix)
	_check_surface_bounds(diagnostics, "main_menu_bounds", "%s main menu" % suffix)
	_check_action_controls(
		diagnostics,
		[
			"guided_opening_toggle",
			"start_button",
			"settings_button",
		],
		"%s main menu" % suffix,
		ui_scale
	)
	_check_surface_bounds(diagnostics, "kingdom_preview", "%s kingdom preview" % suffix)
	_check_difficulty_choices(menu, diagnostics, suffix, ui_scale)
	for key: String in ["seed_input", "random_seed_button", "difficulty_option"]:
		if bool((diagnostics.get(key, {}) as Dictionary).get("visible", true)):
			_failures.append("%s advanced setup %s leaked into quick start" % [suffix, key])

	menu.call("_on_settings_pressed")
	await get_tree().process_frame
	# Opening the overlay schedules its runtime safe-area refresh. Reapply this
	# test's synthetic notch after that refresh has settled.
	menu.call("apply_mobile_layout", logical_size, safe_area)
	await get_tree().process_frame
	await get_tree().process_frame
	menu.call("_refresh_main_menu_diagnostics")
	_check_settings_choices(menu, suffix)
	_check_population_choices(menu, suffix, ui_scale)
	diagnostics = menu.get("main_menu_diagnostics")
	if not bool(diagnostics.get("settings_open", false)):
		_failures.append("%s settings overlay did not open" % suffix)
	_check_surface_bounds(diagnostics, "settings_bounds", "%s settings overlay" % suffix)
	for key in ["settings_title", "settings_controls", "camera_speed_label", "ui_scale_label"]:
		_check_surface_bounds(diagnostics, key, "%s settings overlay" % suffix)
	_check_action_controls(
		diagnostics,
		["audio_toggle", "camera_speed_option", "ui_scale_option", "seed_input", "random_seed_button", "settings_close_button"],
		"%s settings overlay" % suffix,
		ui_scale
	)

	menu.free()
	phone_viewport.free()
	await get_tree().process_frame


func _check_difficulty_choices(menu: Control, diagnostics: Dictionary, suffix: String, ui_scale: float) -> void:
	var choices: Array = diagnostics.get("difficulty_choices", [])
	if choices.size() != 3:
		_failures.append("%s quick start must expose three difficulty choices" % suffix)
		return
	for choice: Dictionary in choices:
		if not bool(choice.get("visible", false)) or not bool(choice.get("within_safe_area", false)):
			_failures.append("%s difficulty %s is hidden or outside safe area" % [suffix, choice.get("name", "?")])
		if float(choice.get("height", 0.0)) * ui_scale < MIN_PHYSICAL_TOUCH_TARGET - 0.5:
			_failures.append("%s difficulty choice is shorter than 48 physical px" % suffix)
	var hard_button: Button = menu.get_node("CenterContainer/VBox/SetupPanel/SetupMargin/SetupVBox/DifficultyChoices/HardDifficulty")
	var option: OptionButton = menu.get("difficulty_option")
	var original_difficulty: int = option.selected
	hard_button.pressed.emit()
	if option.selected != 2 or int(menu.get("_selected_difficulty")) != 2:
		_failures.append("%s Hard choice did not update match difficulty" % suffix)
	menu.call("_on_difficulty_changed", original_difficulty)


func _check_settings_choices(menu: Control, suffix: String) -> void:
	var ui_scale_option: OptionButton = menu.get("ui_scale_option") as OptionButton
	if ui_scale_option.item_count != 3:
		_failures.append("%s settings overlay does not expose three supported UI scales" % suffix)
		return
	if ui_scale_option.get_item_text(0) != "Standard":
		_failures.append("%s settings still offers a sub-100%% Compact scale" % suffix)
	if ui_scale_option.get_item_text(ui_scale_option.item_count - 1) != "Extra Large":
		_failures.append("%s maximum UI scale is not labeled Extra Large" % suffix)


func _check_population_choices(menu: Control, suffix: String, ui_scale: float) -> void:
	var diagnostics: Dictionary = menu.get("main_menu_diagnostics")
	var choices: Array = diagnostics.get("population_choices", [])
	if choices.size() != 3:
		_failures.append("%s population must offer 20/30/40" % suffix)
		return
	for choice: Dictionary in choices:
		if not bool(choice.get("visible", false)) or not bool(choice.get("within_safe_area", false)):
			_failures.append("%s population choice leaves the settings safe area" % suffix)
		if float(choice.get("height", 0.0)) * ui_scale < MIN_PHYSICAL_TOUCH_TARGET - 0.5 or float(choice.get("width", 0.0)) * ui_scale < MIN_PHYSICAL_TOUCH_TARGET - 0.5:
			_failures.append("%s population choice is under48px" % suffix)
	var previous_limit: int = GameManager.selected_population_limit
	var population_buttons: Array = menu.get("_population_buttons")
	(population_buttons[0] as Button).pressed.emit()
	if GameManager.selected_population_limit != 20 or int(menu.get("_selected_population_limit")) != 20:
		_failures.append("%s population choice did not apply to the match" % suffix)
	menu.call("_on_population_selected", previous_limit)


func _check_safe_area(diagnostics: Dictionary, expected: Rect2, surface: String) -> void:
	var safe: Dictionary = diagnostics.get("safe_area", {})
	if safe.is_empty():
		_failures.append("%s is missing safe-area diagnostics" % surface)
		return
	_expect_near(float(safe.get("x", -1.0)), expected.position.x, "%s safe-area x" % surface)
	_expect_near(float(safe.get("y", -1.0)), expected.position.y, "%s safe-area y" % surface)
	_expect_near(float(safe.get("width", -1.0)), expected.size.x, "%s safe-area width" % surface)
	_expect_near(float(safe.get("height", -1.0)), expected.size.y, "%s safe-area height" % surface)


func _check_surface_bounds(diagnostics: Dictionary, key: String, surface: String) -> void:
	var control: Dictionary = diagnostics.get(key, {})
	if control.is_empty():
		_failures.append("%s missing %s diagnostics" % [surface, key])
		return
	if not bool(control.get("visible", false)):
		_failures.append("%s %s is not visible" % [surface, key])
	if not bool(control.get("within_viewport", false)):
		_failures.append("%s %s extends outside the logical viewport" % [surface, key])
	if not bool(control.get("within_safe_area", false)):
		_failures.append(
			"%s %s violates the safe area (x=%.1f y=%.1f w=%.1f h=%.1f)"
			% [
				surface,
				key,
				float(control.get("x", 0.0)),
				float(control.get("y", 0.0)),
				float(control.get("width", 0.0)),
				float(control.get("height", 0.0)),
			]
		)


func _check_action_controls(
	diagnostics: Dictionary,
	keys: Array[String],
	surface: String,
	ui_scale: float
) -> void:
	for key in keys:
		_check_surface_bounds(diagnostics, key, surface)
		var control: Dictionary = diagnostics.get(key, {})
		if control.is_empty():
			continue
		var physical_height: float = float(control.get("height", 0.0)) * ui_scale
		if physical_height < MIN_PHYSICAL_TOUCH_TARGET - 0.5:
			_failures.append(
				"%s %s is shorter than %.0f physical px: %.1f"
				% [surface, key, MIN_PHYSICAL_TOUCH_TARGET, physical_height]
			)
		var control_height: float = float(control.get("height", 0.0))
		var aspect_ratio: float = float(control.get("width", 0.0)) / maxf(1.0, control_height)
		var compact_button: bool = key in ["random_seed_button", "start_button", "settings_button", "settings_close_button"]
		if compact_button and aspect_ratio > MAX_TOUCH_TARGET_ASPECT_RATIO + 0.01:
			_failures.append(
				"%s %s is too wide for reliable touch targeting: %.2f"
				% [surface, key, aspect_ratio]
			)


func _expect_near(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.5:
		_failures.append("%s expected %.1f, got %.1f" % [label, expected, actual])
