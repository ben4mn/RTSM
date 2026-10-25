extends PanelContainer
## Build palette with Economy, Army and Defence groups and readable cards.
##
## Reads building data from BuildingData and checks costs via ResourceManager.
## Emits building_selected when the player taps a building to place.

signal building_selected(building_type: int)
signal cancel_placement()
signal close_requested()
signal hold_component_created(component: Node)
signal information_requested(info: Dictionary)

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
var _info_button: Button = null
var _info_mode: bool = false
var _recommended_building_type: int = -1
var _card_width: float = 150.0
var _sheet_height: float = 174.0
var _layout_refresh_queued: bool = false
var _safe_area_rect: Rect2 = Rect2()
var _has_safe_area_override: bool = false
var _category_buttons: Dictionary = {}
var _header_action_spacer: Control = null
var _active_category: String = "Economy"
var _dismiss_shield: Control = null
var _hold_components: Array[Node] = []
@export var touch_target_diagnostics: Dictionary = {}

const SHEET_MAX_WIDTH := 700.0
const SHEET_VIEWPORT_MARGIN := 16.0
const SHEET_BOTTOM_MARGIN := 8.0
const HEADER_HEIGHT := 48.0
const CARD_WIDTH := 150.0
const CARD_HEIGHT := 94.0
const CARD_GAP := 8.0
const BUILDING_CATEGORIES: Dictionary = {
	"Economy": [BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.FARM, BuildingData.BuildingType.RESOURCE_CAMP, BuildingData.BuildingType.TOWN_CENTER],
	"Army": [BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE, BuildingData.BuildingType.SIEGE_WORKSHOP, BuildingData.BuildingType.BLACKSMITH],
	"Defence": [BuildingData.BuildingType.WATCH_TOWER],
}
const BUILDING_PURPOSES: Dictionary = {
	BuildingData.BuildingType.HOUSE: "Housing for your growing town",
	BuildingData.BuildingType.FARM: "Unlimited food · 1 worker",
	BuildingData.BuildingType.RESOURCE_CAMP: "All resource drop-off",
	BuildingData.BuildingType.TOWN_CENTER: "Train workers",
	BuildingData.BuildingType.BARRACKS: "Train Warriors",
	BuildingData.BuildingType.BLACKSMITH: "Unit and worker upgrades",
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
	_create_info_button()

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

	_create_dismiss_shield()
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
	var maximum_width: float = minf(SHEET_MAX_WIDTH, maxf(320.0, safe_area.size.x - SHEET_VIEWPORT_MARGIN * 2.0))
	var visible_count: int = _visible_card_count()
	title_label.visible = viewport_size.y > 520.0 and maximum_width >= 590.0 and visible_count > 1
	title_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var panel_padding: Vector2 = get_theme_stylebox("panel").get_minimum_size()
	var margin: MarginContainer = $Margin
	var horizontal_padding: float = panel_padding.x + float(margin.get_theme_constant("margin_left") + margin.get_theme_constant("margin_right"))
	var vertical_padding: float = panel_padding.y + float(margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom"))
	var sheet_width: float = maximum_width
	if visible_count == 1:
		# The header sets the compact sheet width; its single building keeps the
		# same card proportions as every other category.
		sheet_width = minf(maximum_width, _header_minimum_width() + horizontal_padding)
	# Keep every Castle unlock reachable without squeezing its card text.
	# Narrow Army rows can scroll inside the sheet; other rows still fit.
	var content_width: float = sheet_width - horizontal_padding
	_card_width = maxf(120.0, minf(CARD_WIDTH, (content_width - CARD_GAP * float(visible_count - 1)) / float(visible_count)))
	var needs_scroll: bool = _card_width * visible_count + CARD_GAP * (visible_count - 1) > content_width + 0.5
	# Keep a five-card row scroll-capable even while it fits. Otherwise its old
	# wider child minimum can expand the panel during a category/scale change.
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if visible_count > 4 or needs_scroll else ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.accessibility_name = "%s buildings; swipe horizontally for more" % _active_category if needs_scroll else "%s buildings" % _active_category
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet_height = vertical_padding + HEADER_HEIGHT + float(($Margin/VBox as VBoxContainer).get_theme_constant("separation")) + CARD_HEIGHT
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

	grid.columns = visible_count
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for button: Button in _button_map.values():
		button.custom_minimum_size = Vector2(_card_width, CARD_HEIGHT)
	if _dismiss_shield != null:
		var hud_layer: Node = get_parent()
		var top: Control = hud_layer.get("top_bar") as Control
		_dismiss_shield.set("protected_rects", [top.get_global_rect()] as Array[Rect2] if top != null else [] as Array[Rect2])
	_refresh_touch_target_diagnostics()


func _visible_card_count() -> int:
	var visible_count: int = 0
	for building_type: int in _button_map:
		if building_type in BUILDING_CATEGORIES.get(_active_category, []):
			visible_count += 1
	return maxi(1, visible_count)


func _header_minimum_width() -> float:
	var width: float = 0.0
	var control_count: int = 0
	for child: Node in header.get_children():
		if child is Control and (child as Control).visible:
			width += (child as Control).get_combined_minimum_size().x
			control_count += 1
	return width + float(header.get_theme_constant("separation") * maxi(0, control_count - 1))


func set_safe_area_rect(safe_area: Rect2) -> void:
	_safe_area_rect = safe_area
	_has_safe_area_override = safe_area.has_area()
	if is_node_ready():
		_apply_compact_layout()


func _apply_visual_theme() -> void:
	theme = KingdomTheme.create_theme()
	var sheet_style: StyleBoxFlat = FieldStyle.surface(16)
	sheet_style.bg_color.a = 0.98
	sheet_style.border_width_top = 1
	sheet_style.set_content_margin_all(2)
	add_theme_stylebox_override("panel", sheet_style)
	title_label.text = "Construction"
	KingdomTheme.apply_heading(title_label, 18)
	title_label.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
	title_label.add_theme_font_size_override("font_size", 18)
	KingdomTheme.apply_secondary(cancel_button)


func _apply_header_button_style(button: Button) -> void:
	KingdomTheme.apply_secondary(button)


func _apply_card_style(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style: StyleBox = KingdomTheme.button_style("secondary", state)
		style.set_content_margin_all(6)
		style.set_content_margin(SIDE_TOP, 4)
		style.set_content_margin(SIDE_BOTTOM, 4)
		button.add_theme_stylebox_override(state, style)
	FieldStyle.soften(button, 12, true)
	button.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
	button.add_theme_color_override("font_disabled_color", KingdomTheme.MUTED)
	# Painted buildings keep their original palette on cloth and honey states.
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_color_override("icon_%s_color" % state, Color.WHITE)


func _create_category_buttons() -> void:
	for category: String in BUILDING_CATEGORIES:
		var button := Button.new()
		button.name = "%sCategoryButton" % category
		button.custom_minimum_size = Vector2(CommandIcons.TARGET_SIZE, HEADER_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.add_theme_font_size_override("font_size", 13)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_category_pressed.bind(category))
		header.add_child(button)
		header.move_child(button, header.get_child_count() - 2)
		_category_buttons[category] = button
	_header_action_spacer = Control.new()
	_header_action_spacer.name = "BuildHeaderActionSpacer"
	_header_action_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_header_action_spacer)
	header.move_child(_header_action_spacer, header.get_child_count() - 2)
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
		CommandIcons.apply(button, {"Economy": "economy", "Army": "army", "Defence": "stance"}[category], "%s buildings" % category, category)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width", 20)
		FieldStyle.soften(button, 24, category != _active_category)
	var visible_count: int = 0
	for building_type: int in _button_map:
		var button: Button = _button_map[building_type]
		button.visible = building_type in BUILDING_CATEGORIES.get(_active_category, [])
		if button.visible:
			visible_count += 1
	grid.columns = maxi(1, visible_count)
	_queue_layout_refresh()


func _create_repeat_button() -> void:
	if _repeat_button != null:
		return
	_repeat_button = Button.new()
	_repeat_button.name = "RepeatLastBuildButton"
	_repeat_button.custom_minimum_size = Vector2(48, 48)
	_repeat_button.visible = false
	_repeat_button.tooltip_text = "Repeat the last selected building"
	_repeat_button.pressed.connect(_on_repeat_pressed)
	_apply_header_button_style(_repeat_button)
	header.add_child(_repeat_button)
	CommandIcons.apply(_repeat_button, "repeat", "Repeat the last selected building")
	header.move_child(_repeat_button, header.get_child_count() - 2)


func _create_dismiss_shield() -> void:
	_dismiss_shield = preload("res://scripts/ui/modal_dismiss_shield.gd").new()
	_dismiss_shield.name = "BuildOutsideDismissShield"
	get_parent().add_child.call_deferred(_dismiss_shield)
	call_deferred("_position_dismiss_shield")
	_dismiss_shield.dismiss_requested.connect(func() -> void: close_requested.emit())


func _create_info_button() -> void:
	_info_button = Button.new()
	_info_button.name = "BuildInfoButton"
	_info_button.custom_minimum_size = Vector2(48, 48)
	_info_button.toggle_mode = true
	_info_button.focus_mode = Control.FOCUS_NONE
	_info_button.tooltip_text = "Inspect building costs and requirements; tap Info again to build"
	_info_button.toggled.connect(_on_info_toggled)
	header.add_child(_info_button)
	header.move_child(_info_button, header.get_child_count() - 2)
	KingdomTheme.apply_secondary(_info_button)
	CommandIcons.apply(_info_button, "info", "Inspect building costs and requirements; tap Info again to build")


func _on_info_toggled(enabled: bool) -> void:
	_info_mode = enabled
	for component: Node in _hold_components:
		if is_instance_valid(component):
			component.cancel_gesture("build_info_mode_changed")
	if enabled:
		KingdomTheme.apply_primary(_info_button)
	else:
		KingdomTheme.apply_secondary(_info_button)
	CommandIcons.apply(_info_button, "info", "Return to building" if enabled else "Inspect building costs and requirements")
	CommandIcons.set_badge(_info_button, "ON" if enabled else "")
	_info_button.accessibility_name = "Inspect mode on. Tap cards for details; tap Info again to build." if enabled else "Inspect mode off. Tap Info to learn about any building."
	_refresh_affordability()


func _position_dismiss_shield() -> void:
	if is_instance_valid(_dismiss_shield) and _dismiss_shield.is_inside_tree():
		get_parent().move_child(_dismiss_shield, get_index())


func _build_info(building_type: int) -> Dictionary:
	var stats: Dictionary = BuildingData.get_building_stats(building_type, player_owner)
	var lines: PackedStringArray = _format_tooltip(stats, building_type).split("\n")
	lines.remove_at(0)
	if int(stats.get("age_required", 0)) <= _current_age and _can_afford(stats.get("cost", {})):
		lines.append("Close this panel and turn off Info to choose a placement." if _info_mode else "Tap the card to preview a placement.")
	lines.append("Place spends the cost; Cancel spends nothing.")
	lines.append("Card cost key: F = Food · W = Wood · G = Gold.")
	return {"title": BuildingData.get_building_name(building_type), "body": "\n".join(lines)}


func _hold_safe_area() -> Rect2:
	if get_parent().has_method("get_hold_safe_rect"):
		return get_parent().get_hold_safe_rect()
	return _safe_area_rect if _has_safe_area_override else get_viewport().get_visible_rect()


func get_hold_occlusion_rects() -> Array[Rect2]:
	var bounds: Array[Rect2] = []
	for component: Node in _hold_components:
		if is_instance_valid(component):
			bounds.append_array(component.get_visible_bounds())
	return bounds


func open_menu() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		_current_age = gm.get_player_age(player_owner)
	for category: String in BUILDING_CATEGORIES:
		if _recommended_building_type in BUILDING_CATEGORIES[category]:
			_active_category = category
			break
	visible = true
	if _dismiss_shield != null:
		_dismiss_shield.set_active(true)
	_rebuild_grid()
	_refresh_affordability()
	_update_aux_button()
	_apply_compact_layout()
	scroll_container.scroll_horizontal = 0
	_refresh_touch_target_diagnostics()


func close_menu() -> void:
	visible = false
	_info_mode = false
	if _info_button != null:
		_info_button.set_pressed_no_signal(false)
		KingdomTheme.apply_secondary(_info_button)
		CommandIcons.apply(_info_button, "info", "Inspect building costs and requirements")
		CommandIcons.set_badge(_info_button, "")
	if _dismiss_shield != null:
		_dismiss_shield.set_active(false)
	for component: Node in _hold_components:
		if is_instance_valid(component):
			component.cancel_gesture("build_closed")
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
	for component: Node in _hold_components:
		if is_instance_valid(component):
			component.cancel_gesture("cards_rebuilt")
			component.detach()
	_hold_components.clear()
	# Clear existing buttons
	for child in grid.get_children():
		# This menu is rebuilt and diagnosed in the same frame. Immediate removal
		# prevents stale buttons from overlapping the new controls until idle time.
		child.free()
	_button_map.clear()

	# Keep familiar targets in place as ages unlock additional buildings.
	# Category order is also display order; locks change the card, not its slot.
	var all_types: Array = []
	for category_types: Array in BUILDING_CATEGORIES.values():
		all_types.append_array(category_types)

	for building_type in all_types:
		var stats: Dictionary = BuildingData.get_building_stats(building_type, player_owner)
		if stats.is_empty():
			continue
		var age_req: int = int(stats.get("age_required", 0))
		var age_locked: bool = age_req > _current_age

		var btn := Button.new()
		btn.name = "BuildButton_%s" % str(building_type)
		btn.custom_minimum_size = Vector2(_card_width, CARD_HEIGHT)
		btn.text = _format_button_text(stats, age_locked, building_type)
		btn.add_theme_font_size_override("font_size", 13)
		btn.tooltip_text = _format_tooltip(stats, building_type)
		btn.accessibility_name = btn.tooltip_text
		btn.set_meta("age_locked", age_locked)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("h_separation", 4)
		btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_apply_card_style(btn)

		# Add building icon to button
		var tex_path: String = BuildingBase.get_sprite_texture_path(building_type, 0)
		if tex_path != "" and ResourceLoader.exists(tex_path):
			btn.icon = load(tex_path)
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			btn.expand_icon = true
			# Scale icon down within button
			btn.add_theme_constant_override("icon_max_width", 40)

		btn.pressed.connect(_on_building_button_pressed.bind(building_type))
		grid.add_child(btn)
		_button_map[building_type] = btn
		var hold: Node = preload("res://scripts/ui/hud_hold_control.gd").attach_to(btn, get_parent(), _build_info.bind(building_type), func() -> Variant: return building_type, _hold_safe_area)
		hold.set("admission_provider", func() -> bool:
			var hud_layer: Node = get_parent()
			return visible and not _placement_mode_active and (not hud_layer.has_method("get_secondary_surface_name") or hud_layer.get_secondary_surface_name() not in ["info", "help", "world_context"]))
		_hold_components.append(hold)
		hold_component_created.emit(hold)

	_refresh_categories()
	_refresh_affordability()
	_refresh_touch_target_diagnostics()


func _format_button_text(stats: Dictionary, age_locked: bool, building_type: int = -1) -> String:
	var cost: Dictionary = stats.get("cost", {})
	var parts: PackedStringArray = []
	for resource: String in ["food", "wood", "gold"]:
		if int(cost.get(resource, 0)) > 0:
			parts.append("%d%s" % [int(cost[resource]), resource.left(1).to_upper()])
	var lines: PackedStringArray = [_compact_building_name(String(stats.get("name", "Build")))]
	lines.append(" · ".join(parts) if not parts.is_empty() else "No cost")
	# Only decision-changing context stays on the compact card. Full purpose,
	# cost names and effects remain available through Info, hold and accessibility.
	if age_locked:
		lines.append(_get_age_requirement_text(int(stats.get("age_required", 0))).trim_prefix("Requires "))
	elif building_type == BuildingData.BuildingType.FARM:
		lines.append("Unlimited food")
	elif building_type == BuildingData.BuildingType.HOUSE:
		var housing: Dictionary = _housing_gain(stats)
		lines.append("Limit %d reached" % housing.limit if housing.gain == 0 else "+%d housing" % housing.gain)
	return "\n".join(lines)


func _compact_building_name(building_name: String) -> String:
	return {"Resource Camp": "Camp", "Archery Range": "Archery", "Siege Workshop": "Siege", "Town Center": "Town Center"}.get(building_name, building_name)


func _format_tooltip(stats: Dictionary, building_type: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(stats["name"])
	if building_type == BuildingData.BuildingType.ARCHERY_RANGE:
		lines.append("Train %ss" % UnitData.get_unit_name(UnitData.UnitType.ARCHER, player_owner))
	elif building_type == BuildingData.BuildingType.STABLE:
		var unit_name: String = UnitData.get_unit_name(UnitData.UnitType.CAVALRY, player_owner)
		lines.append("Train %s" % ("Horsemen" if unit_name == "Horseman" else unit_name + "s"))
	else:
		lines.append(BUILDING_PURPOSES.get(building_type, "Expand your settlement"))
	var costs: PackedStringArray = []
	for resource: String in ["food", "wood", "gold"]:
		var amount: int = int(stats.get("cost", {}).get(resource, 0))
		if amount > 0:
			costs.append("%d %s" % [amount, resource])
	lines.append("Cost: " + (" · ".join(costs) if not costs.is_empty() else "No cost"))
	var age_req: int = stats.get("age_required", 0)
	if age_req > _current_age:
		lines.append("Locked · " + _get_age_requirement_text(age_req))
	elif not _can_afford(stats.get("cost", {})):
		var missing: PackedStringArray = []
		for resource: String in ["food", "wood", "gold"]:
			var shortage: int = maxi(0, int(stats.get("cost", {}).get(resource, 0)) - int(_current_resources.get(resource, 0)))
			if shortage > 0:
				missing.append("%d %s" % [shortage, resource])
		lines.append("Need " + " · ".join(missing) + " more")
	else:
		lines.append("Ready to place")
	if age_req > 1 and age_req <= _current_age:
		lines.append(_get_age_requirement_text(age_req))
	lines.append("HP %d · Build %ds" % [stats.get("hp", 0), int(stats.get("build_time", 30.0))])
	if building_type == BuildingData.BuildingType.FARM:
		lines.append("One worker per Farm. Food must be carried to a Town Center or Resource Camp.")
	if stats.get("pop_provided", 0) > 0:
		var housing: Dictionary = _housing_gain(stats)
		lines.append("Housing: %d / %d match limit" % [housing.cap, housing.limit])
		if housing.gain > 0:
			lines.append("Adds up to %d housing when complete." % housing.gain)
		else:
			lines.append("Match limit reached. More Houses cannot raise it during this match.")
			lines.append("Extra housing is a reserve if another House is destroyed.")
		if housing.limit < SkirmishData.POPULATION_OPTIONS.max():
			lines.append("Choose a higher population limit in the next match's More options.")
	var drop_off: Array = stats.get("drop_off", [])
	if drop_off.size() > 0:
		lines.append("Drop-off: %s" % ", ".join(PackedStringArray(drop_off)))
	var can_train: Array = stats.get("can_train", [])
	if can_train.size() > 0:
		var unit_names: PackedStringArray = PackedStringArray()
		for ut in can_train:
			unit_names.append(UnitData.get_unit_name(ut, player_owner))
		lines.append("Trains: %s" % ", ".join(unit_names))
	if stats.get("has_research", false):
		lines.append("Research: weapons, armor, gathering and Villager health")
	if stats.get("attack_damage", 0) > 0:
		lines.append("Attack: %d (Range: %d)" % [stats["attack_damage"], stats.get("attack_range", 0)])
	return "\n".join(lines)


func _housing_gain(stats: Dictionary) -> Dictionary:
	var gm: Node = get_node_or_null("/root/GameManager")
	var limit: int = gm.get_player_population_limit(player_owner) if gm else SkirmishData.DEFAULT_POPULATION_LIMIT
	var cap: int = int(gm.players.get(player_owner, {}).get("population_cap", 0)) if gm else 0
	return {"cap": cap, "limit": limit, "gain": mini(int(stats.get("pop_provided", 0)), maxi(0, limit - cap))}


func refresh_housing_capacity() -> void:
	# House completion/destruction can change capacity without changing stock.
	# Refresh the open sheet immediately instead of waiting for resource income.
	if visible and is_node_ready():
		_refresh_affordability()


# --- Affordability ---

func _refresh_affordability() -> void:
	for building_type in _button_map:
		var cost: Dictionary = BuildingData.get_building_cost(building_type)
		var can_afford: bool = _can_afford(cost)
		var btn: Button = _button_map[building_type]
		var age_locked: bool = bool(btn.get_meta("age_locked", false))
		var stats: Dictionary = BuildingData.get_building_stats(building_type, player_owner)
		btn.text = _format_button_text(stats, age_locked, building_type)
		if not age_locked and not can_afford:
			# Farm stock remains visible even when its purchase is unaffordable.
			btn.text += "\n" + _missing_resource_text(cost)
		btn.tooltip_text = _format_tooltip(stats, building_type)
		btn.accessibility_name = btn.tooltip_text
		_apply_card_style(btn)
		btn.disabled = _placement_mode_active or (not _info_mode and (age_locked or not can_afford))
		if age_locked:
			btn.modulate = Color(0.82, 0.85, 0.9, 1.0)
		elif can_afford:
			btn.modulate = Color.WHITE
		else:
			btn.modulate = Color(0.85, 0.85, 0.85, 1.0)
		if building_type == _recommended_building_type and not btn.disabled:
			KingdomTheme.apply_primary(btn)
			# Recommendation colour must not change the common card shape.
			for state: String in ["normal", "hover", "pressed"]:
				var style: StyleBox = btn.get_theme_stylebox(state).duplicate()
				style.set_content_margin(SIDE_LEFT, 6)
				style.set_content_margin(SIDE_RIGHT, 6)
				btn.add_theme_stylebox_override(state, style)
			FieldStyle.soften(btn, 12)
	_update_aux_button()
	_refresh_touch_target_diagnostics()


func _missing_resource_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for resource: String in ["food", "wood", "gold"]:
		var shortage: int = maxi(0, int(cost.get(resource, 0)) - int(_current_resources.get(resource, 0)))
		if shortage > 0:
			parts.append("%d%s" % [shortage, resource.left(1).to_upper()])

	# Multi-resource buildings need a fourth line to keep every shortage legible
	# beside the portrait without widening this card or reducing its font.
	return "Need " + "\n".join(parts)


func _can_afford(cost: Dictionary) -> bool:
	for resource_key in cost:
		if cost[resource_key] > _current_resources.get(resource_key, 0):
			return false
	return true


# --- Signal handlers ---

func _on_building_button_pressed(building_type: int) -> void:
	if _info_mode:
		information_requested.emit(_build_info(building_type))
		return
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
	# Selection/status refreshes repeat the same guidance, including while this
	# sheet is hidden. Resources, age, housing and opening refresh independently.
	if _recommended_building_type == building_type:
		return
	_recommended_building_type = building_type
	_refresh_affordability()


func _update_aux_button() -> void:
	if _info_button != null:
		_info_button.disabled = _placement_mode_active
	if _placement_mode_active:
		cancel_button.visible = true
		cancel_button.disabled = false
		CommandIcons.apply(cancel_button, "close", "Cancel current placement")
		_queue_layout_refresh()
		_refresh_touch_target_diagnostics()
		return

	cancel_button.visible = true
	cancel_button.custom_minimum_size = Vector2(48, 48)
	CommandIcons.apply(cancel_button, "close", "Close build menu")
	cancel_button.disabled = false
	_update_repeat_button()
	_queue_layout_refresh()
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
	CommandIcons.apply(_repeat_button, "repeat", "Repeat %s" % building_name)


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
		"info_button": _control_touch_diag(_info_button, "build_menu_info"),
		"info_mode": _info_mode,
		"grid_buttons": buttons,
		"category_buttons": _category_diagnostics(),
		"active_category": _active_category,
		"visible_card_columns": mini(_visible_card_count(), floori((scroll_container.size.x + CARD_GAP) / (_card_width + CARD_GAP))),
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
