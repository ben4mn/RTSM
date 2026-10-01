extends PanelContainer
## Build palette with Economy, Army and Defence groups and readable cards.
##
## Reads building data from BuildingData and checks costs via ResourceManager.
## Emits building_selected when the player taps a building to place.

signal building_selected(building_type: int)
signal cancel_placement()
signal close_requested()

@export var player_owner: int = 0

@onready var grid: GridContainer = %BuildingGrid
@onready var cancel_button: Button = %CancelButton
@onready var title_label: Label = %BuildMenuTitle
@onready var header: HBoxContainer = $Margin/VBox/Header
@onready var scroll_container: ScrollContainer = %ScrollContainer

var _current_age: int = 1
var _current_resources: Dictionary = {"food": 0, "wood": 0, "gold": 0}
var _button_map: Dictionary = {}  # building_type -> Button
var _placement_mode_active: bool = false
var _last_selected_building_type: int = -1
var _resource_legend_row: HBoxContainer = null
var _repeat_button: Button = null
var _recommended_building_type: int = -1
var _card_width: float = 206.0
var _sheet_height: float = 174.0
var _layout_refresh_queued: bool = false
var _safe_area_rect: Rect2 = Rect2()
var _has_safe_area_override: bool = false
var _category_buttons: Dictionary = {}
var _active_category: String = "Economy"
@export var touch_target_diagnostics: Dictionary = {}

const SHEET_MAX_WIDTH := 700.0
const SHEET_HEIGHT := 174.0
const SHEET_MIN_HEIGHT := 174.0
const SHEET_VIEWPORT_MARGIN := 38.0
const SHEET_BOTTOM_MARGIN := 8.0
const CARD_COLUMNS_VISIBLE := 3
const CARD_HEIGHT := 96.0
const CARD_GAP := 8.0
const BUILDING_CATEGORIES: Dictionary = {
	"Economy": [BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.FARM, BuildingData.BuildingType.MILL, BuildingData.BuildingType.LUMBER_CAMP, BuildingData.BuildingType.MINING_CAMP, BuildingData.BuildingType.TOWN_CENTER],
	"Army": [BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE, BuildingData.BuildingType.BLACKSMITH, BuildingData.BuildingType.SIEGE_WORKSHOP],
	"Defence": [BuildingData.BuildingType.WATCH_TOWER],
}
const BUILDING_PURPOSES: Dictionary = {
	BuildingData.BuildingType.HOUSE: "+10 population",
	BuildingData.BuildingType.FARM: "Steady food supply",
	BuildingData.BuildingType.MILL: "Food drop-off",
	BuildingData.BuildingType.LUMBER_CAMP: "Wood drop-off",
	BuildingData.BuildingType.MINING_CAMP: "Gold drop-off",
	BuildingData.BuildingType.TOWN_CENTER: "Train workers",
	BuildingData.BuildingType.BARRACKS: "Train Warriors",
	BuildingData.BuildingType.ARCHERY_RANGE: "Train archers",
	BuildingData.BuildingType.STABLE: "Train Horsemen",
	BuildingData.BuildingType.BLACKSMITH: "Army upgrades",
	BuildingData.BuildingType.SIEGE_WORKSHOP: "Siege production",
	BuildingData.BuildingType.WATCH_TOWER: "Base defence",
}



func _ready() -> void:
	visible = false
	_apply_visual_theme()
	_apply_compact_layout()
	cancel_button.pressed.connect(_on_cancel_pressed)
	cancel_button.visible = false
	_create_category_buttons()
	_create_repeat_button()

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		_current_age = gm.get_player_age(player_owner)
		gm.age_advanced.connect(_on_age_advanced)

	var rm: Node = get_node_or_null("/root/ResourceManager")
	if rm and rm.has_signal("resources_changed"):
		rm.resources_changed.connect(_on_resources_changed)
	var viewport: Viewport = get_viewport()
	if not viewport.size_changed.is_connected(_queue_layout_refresh):
		viewport.size_changed.connect(_queue_layout_refresh)

	_rebuild_grid()
	_refresh_touch_target_diagnostics()


func _queue_layout_refresh() -> void:
	if _layout_refresh_queued or not is_node_ready():
		return
	_layout_refresh_queued = true
	call_deferred("_apply_compact_layout")


func _apply_compact_layout() -> void:
	_layout_refresh_queued = false
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	var safe_area: Rect2 = _safe_area_rect.intersection(viewport_rect) if _has_safe_area_override else viewport_rect
	if not safe_area.has_area():
		safe_area = viewport_rect
	var safe_end: Vector2 = safe_area.position + safe_area.size
	var bottom_inset: float = maxf(0.0, viewport_size.y - safe_end.y)
	var sheet_width: float = minf(SHEET_MAX_WIDTH, maxf(320.0, safe_area.size.x - SHEET_VIEWPORT_MARGIN * 2.0))
	_sheet_height = clampf(viewport_size.y * 0.45, SHEET_MIN_HEIGHT, SHEET_HEIGHT)
	var sheet_center_x: float = safe_area.position.x + safe_area.size.x * 0.5
	anchor_left = 0.5
	anchor_top = 1.0
	anchor_right = 0.5
	anchor_bottom = 1.0
	offset_left = sheet_center_x - viewport_size.x * 0.5 - sheet_width * 0.5
	offset_right = sheet_center_x - viewport_size.x * 0.5 + sheet_width * 0.5
	offset_bottom = -bottom_inset - SHEET_BOTTOM_MARGIN
	offset_top = offset_bottom - _sheet_height
	custom_minimum_size = Vector2(sheet_width, _sheet_height)

	var content_width: float = sheet_width - 20.0
	_card_width = floorf((content_width - CARD_GAP * float(CARD_COLUMNS_VISIBLE - 1)) / 3.2)
	_card_width = clampf(_card_width, 174.0, 206.0)
	title_label.visible = sheet_width >= 590.0
	for button: Button in _button_map.values():
		button.custom_minimum_size = Vector2(_card_width, CARD_HEIGHT)
	_refresh_touch_target_diagnostics()


func set_safe_area_rect(safe_area: Rect2) -> void:
	_safe_area_rect = safe_area
	_has_safe_area_override = safe_area.has_area()
	if is_node_ready():
		_apply_compact_layout()


func _apply_visual_theme() -> void:
	theme = KingdomTheme.create_theme()
	var sheet_style: StyleBoxFlat = KingdomTheme.panel_style()
	sheet_style.bg_color.a = 0.96
	sheet_style.set_content_margin_all(2)
	sheet_style.set_border_width(SIDE_TOP, 2)
	sheet_style.shadow_size = 8
	sheet_style.shadow_offset = Vector2(0, -2)
	add_theme_stylebox_override("panel", sheet_style)
	title_label.text = "Build"
	title_label.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
	title_label.add_theme_font_size_override("font_size", 18)
	KingdomTheme.apply_secondary(cancel_button)


func _apply_header_button_style(button: Button) -> void:
	KingdomTheme.apply_secondary(button)


func _apply_card_style(button: Button) -> void:
	var normal: StyleBoxFlat = KingdomTheme.panel_style(KingdomTheme.INK_LIGHT)
	normal.set_content_margin_all(10)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.border_color = KingdomTheme.AMBER
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(0.20, 0.17, 0.10)
	pressed.border_color = KingdomTheme.AMBER
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = KingdomTheme.INK
	disabled.border_color = Color(0.18, 0.22, 0.27)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
	button.add_theme_color_override("font_disabled_color", KingdomTheme.MUTED)
	button.add_theme_color_override("icon_normal_color", KingdomTheme.PARCHMENT)


func _create_category_buttons() -> void:
	for category: String in BUILDING_CATEGORIES:
		var button := Button.new()
		button.name = "%sCategoryButton" % category
		button.text = category
		button.custom_minimum_size = Vector2(96.0 if category == "Economy" else 88.0, 48.0)
		button.add_theme_font_size_override("font_size", 14)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_category_pressed.bind(category))
		header.add_child(button)
		header.move_child(button, header.get_child_count() - 2)
		_category_buttons[category] = button
	_refresh_categories()


func _on_category_pressed(category: String) -> void:
	_active_category = category
	_refresh_categories()
	scroll_container.scroll_horizontal = 0
	_refresh_touch_target_diagnostics()


func _refresh_categories() -> void:
	for category: String in _category_buttons:
		var button: Button = _category_buttons[category]
		button.set_pressed_no_signal(category == _active_category)
		if category == _active_category:
			KingdomTheme.apply_primary(button)
		else:
			KingdomTheme.apply_secondary(button)
	var visible_count: int = 0
	for building_type: int in _button_map:
		var button: Button = _button_map[building_type]
		button.visible = building_type in BUILDING_CATEGORIES.get(_active_category, [])
		if button.visible:
			visible_count += 1
	grid.columns = maxi(1, visible_count)


func _create_repeat_button() -> void:
	if _repeat_button != null:
		return
	_repeat_button = Button.new()
	_repeat_button.name = "RepeatLastBuildButton"
	_repeat_button.text = "Again"
	_repeat_button.custom_minimum_size = Vector2(64, 48)
	_repeat_button.visible = false
	_repeat_button.tooltip_text = "Repeat the last selected building"
	_repeat_button.pressed.connect(_on_repeat_pressed)
	_apply_header_button_style(_repeat_button)
	header.add_child(_repeat_button)
	header.move_child(_repeat_button, header.get_child_count() - 2)


func open_menu() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		_current_age = gm.get_player_age(player_owner)
	for category: String in BUILDING_CATEGORIES:
		if _recommended_building_type in BUILDING_CATEGORIES[category]:
			_active_category = category
			break
	visible = true
	_apply_compact_layout()
	_rebuild_grid()
	_refresh_affordability()
	_update_aux_button()
	scroll_container.scroll_horizontal = 0
	_refresh_touch_target_diagnostics()


func close_menu() -> void:
	visible = false
	_refresh_touch_target_diagnostics()


func close_for_world_placement() -> void:
	# Placement is represented by the world ghost and HUD Cancel button.  Leave
	# this panel reset so a later Build-button tap opens a normal, usable menu.
	set_placement_mode(false)
	close_menu()


func set_placement_mode(active: bool) -> void:
	_placement_mode_active = active
	_refresh_affordability()
	_update_aux_button()


# --- Grid population ---

func _rebuild_grid() -> void:
	# Clear existing buttons
	for child in grid.get_children():
		# This menu is rebuilt and diagnosed in the same frame. Immediate removal
		# prevents stale buttons from overlapping the new controls until idle time.
		child.free()
	_button_map.clear()

	var all_types: Array = BuildingData.BUILDINGS.keys()
	all_types.sort_custom(func(a: int, b: int) -> bool:
		var a_locked: bool = int(BuildingData.BUILDINGS[a].get("age_required", 0)) > _current_age
		var b_locked: bool = int(BuildingData.BUILDINGS[b].get("age_required", 0)) > _current_age
		if a_locked != b_locked:
			return not a_locked
		return a < b
	)

	for building_type in all_types:
		var gm: Node = get_node_or_null("/root/GameManager")
		if building_type == BuildingData.BuildingType.SIEGE_WORKSHOP and gm and int(gm.call("get_match_population_limit")) <= 40:
			continue
		var stats: Dictionary = BuildingData.get_building_stats(building_type)
		if stats.is_empty():
			continue
		var age_req: int = int(stats.get("age_required", 0))
		var age_locked: bool = age_req > _current_age

		var btn := Button.new()
		btn.name = "BuildButton_%s" % str(building_type)
		btn.custom_minimum_size = Vector2(_card_width, CARD_HEIGHT)
		btn.text = _format_button_text(stats, age_locked, building_type)
		btn.add_theme_font_size_override("font_size", 14)
		btn.tooltip_text = _format_tooltip(stats, building_type)
		btn.set_meta("age_locked", age_locked)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_apply_card_style(btn)

		# Add building icon to button
		var tex_path: String = BuildingBase.BUILDING_SPRITES.get(building_type, "")
		if tex_path != "" and ResourceLoader.exists(tex_path):
			btn.icon = load(tex_path)
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.expand_icon = true
			# Scale icon down within button
			btn.add_theme_constant_override("icon_max_width", 36)

		btn.pressed.connect(_on_building_button_pressed.bind(building_type))
		grid.add_child(btn)
		_button_map[building_type] = btn

	_refresh_categories()
	_refresh_affordability()
	_refresh_touch_target_diagnostics()


func _format_button_text(stats: Dictionary, age_locked: bool, building_type: int = -1) -> String:
	var cost: Dictionary = stats.get("cost", {})
	var parts: PackedStringArray = PackedStringArray()
	for resource: String in ["food", "wood", "gold"]:
		if int(cost.get(resource, 0)) > 0:
			parts.append("%d %s" % [int(cost[resource]), resource])
	var cost_text: String = " · ".join(parts)
	if cost_text == "":
		cost_text = "No cost"
	var purpose: String = BUILDING_PURPOSES.get(building_type, "Expand your settlement")
	if age_locked:
		purpose = "Unlocks in Age %d" % int(stats.get("age_required", 0))
	return "%s\n%s\n%s" % [String(stats.get("name", "Build")), purpose, cost_text]


func _compact_building_name(building_name: String) -> String:
	return building_name


func _format_tooltip(stats: Dictionary, building_type: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(stats["name"])
	lines.append("HP: %d" % stats.get("hp", 0))
	lines.append("Build time: %ds" % int(stats.get("build_time", 30.0)))
	if stats.get("pop_provided", 0) > 0:
		lines.append("Provides: +%d population" % stats["pop_provided"])
	var drop_off: Array = stats.get("drop_off", [])
	if drop_off.size() > 0:
		lines.append("Drop-off: %s" % ", ".join(PackedStringArray(drop_off)))
	var can_train: Array = stats.get("can_train", [])
	if can_train.size() > 0:
		var unit_names: PackedStringArray = PackedStringArray()
		for ut in can_train:
			unit_names.append(UnitData.get_unit_name(ut))
		lines.append("Trains: %s" % ", ".join(unit_names))
	if stats.get("has_research", false):
		lines.append("Research: Weapon & Armor upgrades")
	if stats.get("attack_damage", 0) > 0:
		lines.append("Attack: %d (Range: %d)" % [stats["attack_damage"], stats.get("attack_range", 0)])
	var age_req: int = stats.get("age_required", 0)
	if age_req > 0:
		var gm: Node = get_node_or_null("/root/GameManager")
		if gm:
			lines.append("Requires: %s" % gm.get_age_name(age_req))
	return "\n".join(lines)


# --- Affordability ---

func _refresh_affordability() -> void:
	for building_type in _button_map:
		var cost: Dictionary = BuildingData.get_building_cost(building_type)
		var can_afford: bool = _can_afford(cost)
		var btn: Button = _button_map[building_type]
		var age_locked: bool = bool(btn.get_meta("age_locked", false))
		_apply_card_style(btn)
		btn.disabled = _placement_mode_active or age_locked or not can_afford
		if age_locked:
			btn.modulate = Color(0.82, 0.85, 0.9, 1.0)
		elif can_afford:
			btn.modulate = Color.WHITE
		else:
			btn.modulate = Color(0.85, 0.85, 0.85, 1.0)
		if building_type == _recommended_building_type and not btn.disabled:
			KingdomTheme.apply_primary(btn)
	_update_aux_button()
	_refresh_touch_target_diagnostics()


func _can_afford(cost: Dictionary) -> bool:
	for resource_key in cost:
		if cost[resource_key] > _current_resources.get(resource_key, 0):
			return false
	return true


# --- Signal handlers ---

func _on_building_button_pressed(building_type: int) -> void:
	_last_selected_building_type = building_type
	_update_repeat_button()
	set_placement_mode(true)
	building_selected.emit(building_type)


func _on_cancel_pressed() -> void:
	if _placement_mode_active:
		cancel_placement.emit()
		set_placement_mode(false)
		return
	close_requested.emit()


func _on_repeat_pressed() -> void:
	if _last_selected_building_type < 0:
		return
	var cost: Dictionary = BuildingData.get_building_cost(_last_selected_building_type)
	if not _can_afford(cost):
		return
	set_placement_mode(true)
	building_selected.emit(_last_selected_building_type)


func _on_age_advanced(player_id: int, new_age: int) -> void:
	if player_id != player_owner:
		return
	_current_age = new_age
	_rebuild_grid()


func _on_resources_changed(player_id: int, _resource_type: String, _new_amount: int) -> void:
	if player_id != player_owner:
		return
	var rm: Node = get_node_or_null("/root/ResourceManager")
	if rm:
		_current_resources = rm.get_all_resources(player_owner)
		_refresh_affordability()


func update_resources(resources: Dictionary) -> void:
	_current_resources = resources
	_refresh_affordability()


func update_age(age: int) -> void:
	_current_age = age
	_rebuild_grid()


func set_recommended_building(building_type: int) -> void:
	_recommended_building_type = building_type
	_refresh_affordability()


func _update_aux_button() -> void:
	if _placement_mode_active:
		cancel_button.visible = true
		cancel_button.disabled = false
		cancel_button.text = "Cancel"
		cancel_button.tooltip_text = "Cancel current placement"
		_refresh_touch_target_diagnostics()
		return

	cancel_button.visible = true
	cancel_button.text = "Close"
	cancel_button.tooltip_text = "Close build menu"
	cancel_button.disabled = false
	_update_repeat_button()
	_refresh_touch_target_diagnostics()


func _update_repeat_button() -> void:
	if _repeat_button == null:
		return
	if _last_selected_building_type < 0:
		_repeat_button.visible = false
		_repeat_button.disabled = true
		return
	var building_name: String = BuildingData.get_building_name(_last_selected_building_type)
	var cost: Dictionary = BuildingData.get_building_cost(_last_selected_building_type)
	_repeat_button.visible = not _placement_mode_active
	_repeat_button.disabled = _placement_mode_active or not _can_afford(cost)
	_repeat_button.text = "Again"
	_repeat_button.tooltip_text = "Repeat %s" % building_name


func _get_age_requirement_text(age_required: int) -> String:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		return "Requires %s" % gm.get_age_name(age_required)
	match age_required:
		1:
			return "Requires Dark Age"
		2:
			return "Requires Feudal Age"
		3:
			return "Requires Castle Age"
		4:
			return "Requires Imperial Age"
		_:
			return "Requires later age"


func _control_touch_diag(control: Control, role: String = "") -> Dictionary:
	if control == null:
		return {}
	var disabled: bool = false
	if control is BaseButton:
		disabled = (control as BaseButton).disabled
	var rect: Rect2 = control.get_global_rect()
	var size: Vector2 = control.size
	var aspect_ratio: float = 0.0
	if size.y > 0.0:
		aspect_ratio = size.x / size.y
	return {
		"role": role,
		"path": String(control.get_path()),
		"name": control.name,
		"text": control.text if control is Button else "",
		"visible": control.is_visible_in_tree(),
		"disabled": disabled,
		"width": size.x,
		"height": size.y,
		"aspect_ratio": aspect_ratio,
		"x": rect.position.x,
		"y": rect.position.y,
		"min_width": control.custom_minimum_size.x,
		"min_height": control.custom_minimum_size.y,
	}


func _refresh_touch_target_diagnostics() -> void:
	if OS.has_feature("production"):
		return
	var buttons: Array[Dictionary] = []
	var index: int = 0
	for child in grid.get_children():
		if child is Button:
			var button_entry: Dictionary = _control_touch_diag(child as Control, "build_option_%d" % index)
			button_entry["index"] = index
			buttons.append(button_entry)
			index += 1
	touch_target_diagnostics = {
		"timestamp_ms": Time.get_ticks_msec(),
		"panel": _control_touch_diag(self, "build_menu_panel"),
		"cancel_button": _control_touch_diag(cancel_button, "build_menu_cancel"),
		"repeat_button": _control_touch_diag(_repeat_button, "build_menu_repeat"),
		"grid_buttons": buttons,
		"category_buttons": _category_diagnostics(),
		"active_category": _active_category,
		"visible_card_columns": CARD_COLUMNS_VISIBLE,
		"grid_columns": grid.columns,
		"card_width": _card_width,
		"card_height": CARD_HEIGHT,
		"sheet_height": _sheet_height,
		"safe_area": _safe_area_rect if _has_safe_area_override else get_viewport().get_visible_rect(),
		"scroll_viewport_width": scroll_container.size.x,
		"content_width": grid.size.x,
	}


func _category_diagnostics() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for button: Button in _category_buttons.values():
		entries.append(_control_touch_diag(button, "build_category"))
	return entries
