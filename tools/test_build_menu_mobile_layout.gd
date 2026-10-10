extends Node
## Real-layout regression for the compact 844x390 Build bottom sheet.

const PHONE_SIZE := Vector2i(844, 390)
const MAX_SHEET_WIDTH := 700.0
const MAX_SHEET_HEIGHT := 176.0
const MIN_TOUCH_TARGET := 48.0
const EXPECTED_VISIBLE_COLUMNS := 3

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	await _check_large_scale_geometry(Vector2i(844, 390), 1.15, true)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for ui_scale: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _check_category_density(phone, ui_scale, notched)
	var phone_viewport := SubViewport.new()
	phone_viewport.size = PHONE_SIZE
	add_child(phone_viewport)
	var host := Control.new()
	host.position = Vector2.ZERO
	host.size = Vector2(PHONE_SIZE)
	phone_viewport.add_child(host)

	var build_menu_scene: PackedScene = load("res://scenes/ui/build_menu.tscn")
	var build_menu: PanelContainer = build_menu_scene.instantiate() as PanelContainer
	host.add_child(build_menu)
	await get_tree().process_frame
	build_menu.call("update_age", 4)
	build_menu.call("update_resources", {"food": 5000, "wood": 5000, "gold": 5000})
	build_menu.call("open_menu")
	await get_tree().process_frame
	await get_tree().process_frame
	build_menu.call("_apply_compact_layout")
	await get_tree().process_frame
	build_menu.call("_refresh_touch_target_diagnostics")

	var panel_rect: Rect2 = build_menu.get_global_rect()
	_expect(panel_rect.size.x <= MAX_SHEET_WIDTH + 0.5, "sheet width exceeds 700px: %.1f" % panel_rect.size.x)
	_expect(panel_rect.size.y <= MAX_SHEET_HEIGHT + 0.5, "sheet height exceeds176px: %.1f" % panel_rect.size.y)
	_expect(panel_rect.position.x >= -0.5, "sheet extends beyond the left edge")
	_expect(panel_rect.end.x <= PHONE_SIZE.x + 0.5, "sheet extends beyond the right edge")
	_expect(panel_rect.position.y >= -0.5, "sheet extends above the phone viewport")
	_expect(panel_rect.end.y <= PHONE_SIZE.y + 0.5, "sheet extends below the phone viewport")
	_expect(panel_rect.size.y <= PHONE_SIZE.y * 0.54, "sheet leaves less than46% of the battlefield visible")

	var diagnostics: Dictionary = build_menu.get("touch_target_diagnostics")
	_expect_eq(int(diagnostics.get("visible_card_columns", 0)), EXPECTED_VISIBLE_COLUMNS, "diagnostics preserve three readable columns")
	var grid: GridContainer = build_menu.get_node("Margin/VBox/ScrollContainer/BuildingGrid") as GridContainer
	var scroll: ScrollContainer = build_menu.get_node("Margin/VBox/ScrollContainer") as ScrollContainer
	var cards: Array[Node] = []
	for child: Control in grid.get_children():
		if child.visible:
			cards.append(child)
	_expect_eq(grid.columns, cards.size(), "cards remain in one horizontally scannable row")
	_expect(scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED, "horizontal card scrolling is disabled")
	_expect_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "vertical scrolling should stay disabled")
	_expect(grid.size.x > scroll.size.x + 1.0, "card row does not overflow horizontally")

	var first_card_width: float = 0.0
	for card_node: Node in cards:
		if not card_node is Button:
			continue
		var card := card_node as Button
		if first_card_width <= 0.0:
			first_card_width = card.size.x
		_expect(card.size.x >= MIN_TOUCH_TARGET, "%s is narrower than 48px" % card.name)
		_expect(card.size.y >= MIN_TOUCH_TARGET, "%s is shorter than 48px" % card.name)
		_expect(card.text.split("\n").size() == 3, "%s must show name, purpose and cost" % card.name)
	var gap: float = float(grid.get_theme_constant("h_separation"))
	var visible_card_count: float = (scroll.size.x + gap) / maxf(1.0, first_card_width + gap)
	_expect(
		visible_card_count >= 3.0 and visible_card_count <= 3.4,
		"phone viewport shows %.2f card columns instead of approximately three" % visible_card_count
	)

	var close_diag: Dictionary = diagnostics.get("cancel_button", {})
	_expect(float(close_diag.get("height", 0.0)) >= MIN_TOUCH_TARGET, "Close is shorter than 48px")
	_expect(bool(close_diag.get("visible", false)), "Close is not visible while the sheet is open")

	# Groups are real touch targets; unlocked choices precede future buildings.
	var categories: Dictionary = build_menu.get("_category_buttons")
	_expect_eq(categories.size(), 3, "three build categories are accessible")
	for category_button: Button in categories.values():
		_expect(category_button.size.y >= MIN_TOUCH_TARGET, "build category is under48px")
	build_menu.call("_on_category_pressed", "Army")
	await get_tree().process_frame
	_expect_eq(String(build_menu.get("_active_category")), "Army", "Army category did not activate")
	var button_map: Dictionary = build_menu.get("_button_map")
	_expect((button_map[BuildingData.BuildingType.BARRACKS] as Button).visible, "Army hides Barracks")
	_expect(not (button_map[BuildingData.BuildingType.HOUSE] as Button).visible, "Army still shows economic cards")
	build_menu.call("_on_category_pressed", "Economy")
	await get_tree().process_frame

	# Once a building has been chosen, Repeat must remain a full touch target in
	# the same compact header when the palette is opened again.
	build_menu.set("_last_selected_building_type", 1)
	build_menu.call("set_placement_mode", false)
	build_menu.call("_update_aux_button")
	await get_tree().process_frame
	build_menu.call("_refresh_touch_target_diagnostics")
	diagnostics = build_menu.get("touch_target_diagnostics")
	var repeat_diag: Dictionary = diagnostics.get("repeat_button", {})
	_expect(bool(repeat_diag.get("visible", false)), "Repeat is not visible after choosing a building")
	_expect(float(repeat_diag.get("height", 0.0)) >= MIN_TOUCH_TARGET, "Repeat is shorter than 48px")

	var sheet_style: StyleBox = build_menu.get_theme_stylebox("panel")
	_expect(sheet_style is StyleBoxFlat, "sheet is missing its polished flat-panel style")
	if sheet_style is StyleBoxFlat:
		_expect((sheet_style as StyleBoxFlat).bg_color.a < 1.0, "sheet background is not translucent")

	build_menu.free()
	phone_viewport.free()
	if _failures.is_empty():
		print("[PASS] build_menu_mobile_layout: 12 phone profiles, content-sized Defence, full touch targets and multi-card scrolling")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] build_menu_mobile_layout: %s" % failure)
	get_tree().quit(1)


func _check_large_scale_geometry(physical_size: Vector2i, ui_scale: float, notched: bool) -> void:
	var logical_size := Vector2i(
		floori(float(physical_size.x) / ui_scale),
		floori(float(physical_size.y) / ui_scale)
	)
	var phone_viewport := SubViewport.new()
	phone_viewport.size = logical_size
	add_child(phone_viewport)
	var host := Control.new()
	host.position = Vector2.ZERO
	host.size = Vector2(logical_size)
	phone_viewport.add_child(host)
	var build_menu: PanelContainer = load("res://scenes/ui/build_menu.tscn").instantiate() as PanelContainer
	host.add_child(build_menu)
	await get_tree().process_frame
	var side_inset: float = 44.0 / ui_scale if notched else 0.0
	var bottom_inset: float = 18.0 / ui_scale if notched else 0.0
	var safe_area := Rect2(
		Vector2(side_inset, 0.0),
		Vector2(logical_size.x - side_inset * 2.0, logical_size.y - bottom_inset)
	)
	build_menu.call("set_safe_area_rect", safe_area)
	build_menu.call("update_age", 4)
	build_menu.call("update_resources", {"food": 5000, "wood": 5000, "gold": 5000})
	build_menu.call("open_menu")
	await get_tree().process_frame
	await get_tree().process_frame
	var logical_rect: Rect2 = build_menu.get_global_rect()
	var physical_rect := Rect2(logical_rect.position * ui_scale, logical_rect.size * ui_scale)
	_expect(physical_rect.position.x >= 44.0 - 0.5, "Large UI sheet enters the 44px left landscape safe inset")
	_expect(physical_rect.end.x <= physical_size.x - 44.0 + 0.5, "Large UI sheet enters the 44px right landscape safe inset")
	_expect(physical_rect.end.y <= physical_size.y - 18.0 - 8.0 * ui_scale + 0.5, "Large UI sheet enters the 18px bottom safe inset")
	_expect(
		physical_rect.size.y <= physical_size.y * 0.54 + 0.5,
		"Large UI sheet leaves less than46%% battlefield (%.1fpx high)" % physical_rect.size.y
	)
	var close_button: Button = build_menu.get("cancel_button") as Button
	_expect(close_button.size.y * ui_scale >= MIN_TOUCH_TARGET, "Large UI Close target is under 48 physical px")
	var grid: GridContainer = build_menu.get("grid") as GridContainer
	for card_node: Node in grid.get_children():
		if card_node is Button:
			_expect((card_node as Button).size.y * ui_scale >= MIN_TOUCH_TARGET, "Large UI build card is under 48 physical px")
	build_menu.free()
	phone_viewport.free()
	await get_tree().process_frame


func _check_category_density(phone_size: Vector2i, ui_scale: float, notched: bool) -> void:
	var logical_size := Vector2i(floori(float(phone_size.x) / ui_scale), floori(float(phone_size.y) / ui_scale))
	var viewport := SubViewport.new()
	viewport.size = logical_size
	add_child(viewport)
	var host := Control.new()
	host.size = Vector2(logical_size)
	viewport.add_child(host)
	var menu: PanelContainer = load("res://scenes/ui/build_menu.tscn").instantiate() as PanelContainer
	host.add_child(menu)
	await get_tree().process_frame
	var side_inset: float = 44.0 / ui_scale if notched else 0.0
	var bottom_inset: float = 18.0 / ui_scale if notched else 0.0
	var safe_area := Rect2(Vector2(side_inset, 0.0), Vector2(logical_size) - Vector2(side_inset * 2.0, bottom_inset))
	menu.call("set_safe_area_rect", safe_area)
	menu.call("open_menu")
	var profile: String = "%s scale %.3f notch %s" % [phone_size, ui_scale, notched]
	for repeat_available: bool in [false, true]:
		menu.set("_last_selected_building_type", BuildingData.BuildingType.HOUSE if repeat_available else -1)
		menu.call("set_placement_mode", false)
		for category: String in ["Economy", "Army", "Defence"]:
			menu.call("_on_category_pressed", category)
			for frame: int in 3:
				await get_tree().process_frame
			var panel: Rect2 = menu.get_global_rect()
			var scroll: ScrollContainer = menu.get("scroll_container")
			var grid: GridContainer = menu.get("grid")
			_expect(safe_area.encloses(panel), "%s %s sheet outside safe area" % [profile, category])
			_expect(panel.size.y <= 166.5, "%s %s sheet keeps excess height %.1f" % [profile, category, panel.size.y])
			_expect(not (menu.get("title_label") as Label).visible, "%s retains redundant Build title" % profile)
			var header: HBoxContainer = menu.get("header")
			for control: Control in header.get_children():
				if control.visible and control is Button:
					_expect(control.size.x >= MIN_TOUCH_TARGET and control.size.y >= MIN_TOUCH_TARGET, "%s header target too small" % profile)
					_expect(header.get_global_rect().encloses(control.get_global_rect()), "%s header action overflows" % profile)
					_expect_button_text_fits(control as Button, profile)
			if category == "Defence":
				_expect(panel.size.x <= (410.0 if repeat_available else 340.0), "%s one-card Defence leaves blank width %.1f" % [profile, panel.size.x])
				_expect(panel.size.y <= 150.5, "%s one-card Defence leaves blank height %.1f" % [profile, panel.size.y])
				_expect(not scroll.get_h_scroll_bar().visible, "%s Defence shows an unnecessary scrollbar" % profile)
				var tower: Button = (menu.get("_button_map") as Dictionary)[BuildingData.BuildingType.WATCH_TOWER]
				_expect(absf(tower.size.x - scroll.size.x) <= 0.5, "%s Defence card does not fill its compact row" % profile)
				_expect_button_text_fits(tower, profile)
				# Locked and unaffordable cards explain their requirement on screen.
				_expect(tower.text.contains("Unlocks in Age 2"), "%s locked tower loses age explanation" % profile)
				menu.call("update_age", 2)
				menu.call("update_resources", {"food": 0, "wood": 15, "gold": 0})
				for frame: int in 3:
					await get_tree().process_frame
				var available_tower: Button = (menu.get("_button_map") as Dictionary)[BuildingData.BuildingType.WATCH_TOWER]
				_expect(available_tower.disabled and available_tower.text.contains("Need +85W · +25G"), "%s tower loses visible shortage" % profile)
				_expect_button_text_fits(available_tower, profile)
				menu.call("update_age", 1)
			else:
				_expect(grid.size.x > scroll.size.x + 1.0, "%s %s loses horizontal navigation" % [profile, category])
				var first: Button = null
				for card: Button in grid.get_children():
					if card.visible:
						first = card
						break
				var card_gap: float = float(grid.get_theme_constant("h_separation"))
				var visible_columns: float = (scroll.size.x + card_gap) / (first.size.x + card_gap)
				_expect(visible_columns > 3.0 and visible_columns < 3.4, "%s %s loses next-card discovery %.2f" % [profile, category, visible_columns])
	menu.free()
	viewport.free()
	await get_tree().process_frame


func _expect_button_text_fits(button: Button, profile: String) -> void:
	var available_width: float = button.size.x - button.get_theme_stylebox("normal").get_minimum_size().x
	if button.icon != null:
		available_width -= float(button.get_theme_constant("icon_max_width") + button.get_theme_constant("h_separation"))
	for line: String in button.text.split("\n"):
		var line_width: float = button.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
		_expect(line_width <= available_width + 0.5, "%s '%s' clips words %.1f/%.1f" % [profile, line, line_width, available_width])
	_expect(button.get_minimum_size().y <= button.size.y + 0.5, "%s card clips text vertically" % profile)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
