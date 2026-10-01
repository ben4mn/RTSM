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
		print("[PASS] build_menu_mobile_layout: grouped readable-card sheet preserves battlefield at Standard/Large scale")
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
