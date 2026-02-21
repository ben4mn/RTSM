extends PanelContainer
## Build menu panel. Shows available buildings in a grid.
##
## Reads building data from BuildingData and checks costs via ResourceManager.
## Emits building_selected when the player taps a building to place.

signal building_selected(building_type: int)
signal cancel_placement()

@onready var grid: GridContainer = %BuildingGrid
@onready var cancel_button: Button = %CancelButton
@onready var title_label: Label = %BuildMenuTitle
@onready var header: HBoxContainer = $Margin/VBox/Header

var _current_age: int = 1
var _current_resources: Dictionary = {"food": 0, "wood": 0, "gold": 0}
var _button_map: Dictionary = {}  # building_type -> Button
var _placement_mode_active: bool = false
var _last_selected_building_type: int = -1
var _resource_legend_row: HBoxContainer = null


func _ready() -> void:
	visible = false
	cancel_button.pressed.connect(_on_cancel_pressed)
	cancel_button.visible = false
	_create_resource_legend()

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		gm.age_advanced.connect(_on_age_advanced)

	var rm: Node = get_node_or_null("/root/ResourceManager")
	if rm and rm.has_signal("resources_changed"):
		rm.resources_changed.connect(_on_resources_changed)

	_rebuild_grid()


func _create_resource_legend() -> void:
	if _resource_legend_row != null:
		return
	_resource_legend_row = HBoxContainer.new()
	_resource_legend_row.add_theme_constant_override("separation", 6)
	_resource_legend_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(_resource_legend_row)
	header.move_child(_resource_legend_row, 1)

	for item in [
		{"label": "F", "name": "Food", "color": Color(0.95, 0.40, 0.30)},
		{"label": "W", "name": "Wood", "color": Color(0.50, 0.78, 0.35)},
		{"label": "G", "name": "Gold", "color": Color(0.98, 0.88, 0.25)},
	]:
		var chip := Label.new()
		chip.text = item["label"]
		chip.tooltip_text = "%s resource" % item["name"]
		chip.add_theme_font_size_override("font_size", 13)
		chip.add_theme_color_override("font_color", item["color"])
		_resource_legend_row.add_child(chip)


func open_menu() -> void:
	visible = true
	_refresh_affordability()
	_update_aux_button()


func close_menu() -> void:
	visible = false


func set_placement_mode(active: bool) -> void:
	_placement_mode_active = active
	_refresh_affordability()
	_update_aux_button()


# --- Grid population ---

func _rebuild_grid() -> void:
	# Clear existing buttons
	for child in grid.get_children():
		child.queue_free()
	_button_map.clear()

	var available: Array = BuildingData.get_buildings_for_age(_current_age)

	for building_type in available:
		var stats: Dictionary = BuildingData.get_building_stats(building_type)
		if stats.is_empty():
			continue

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(140, 80)
		btn.text = _format_button_text(stats)
		btn.add_theme_font_size_override("font_size", 13)
		btn.tooltip_text = _format_tooltip(stats, building_type)

		# Add building icon to button
		var tex_path: String = BuildingBase.BUILDING_SPRITES.get(building_type, "")
		if tex_path != "" and ResourceLoader.exists(tex_path):
			btn.icon = load(tex_path)
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.expand_icon = true
			# Scale icon down within button
			btn.add_theme_constant_override("icon_max_width", 40)

		btn.pressed.connect(_on_building_button_pressed.bind(building_type))
		grid.add_child(btn)
		_button_map[building_type] = btn

	_refresh_affordability()


func _format_button_text(stats: Dictionary) -> String:
	var cost: Dictionary = stats.get("cost", {})
	var parts: PackedStringArray = PackedStringArray()
	if cost.get("food", 0) > 0:
		parts.append("F:%d" % cost["food"])
	if cost.get("wood", 0) > 0:
		parts.append("W:%d" % cost["wood"])
	if cost.get("gold", 0) > 0:
		parts.append("G:%d" % cost["gold"])
	# Add pop info if provides housing
	var extra := ""
	if stats.get("pop_provided", 0) > 0:
		extra = " +%d pop" % stats["pop_provided"]
	return "%s%s\n%s" % [stats["name"], extra, " ".join(parts)]


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
		btn.disabled = _placement_mode_active or not can_afford
		if can_afford:
			btn.modulate = Color.WHITE
		else:
			btn.modulate = Color(0.5, 0.5, 0.5, 0.8)
	_update_aux_button()


func _can_afford(cost: Dictionary) -> bool:
	for resource_key in cost:
		if cost[resource_key] > _current_resources.get(resource_key, 0):
			return false
	return true


# --- Signal handlers ---

func _on_building_button_pressed(building_type: int) -> void:
	_last_selected_building_type = building_type
	building_selected.emit(building_type)
	set_placement_mode(true)


func _on_cancel_pressed() -> void:
	if _placement_mode_active:
		cancel_placement.emit()
		set_placement_mode(false)
		return
	if _last_selected_building_type >= 0:
		building_selected.emit(_last_selected_building_type)
		set_placement_mode(true)


func _on_age_advanced(_player_id: int, new_age: int) -> void:
	_current_age = new_age
	_rebuild_grid()


func _on_resources_changed(player_id: int, _resource_type: String, _new_amount: int) -> void:
	if player_id != 0:
		return
	var rm: Node = get_node_or_null("/root/ResourceManager")
	if rm:
		_current_resources = rm.get_all_resources(player_id)
		_refresh_affordability()


func update_resources(resources: Dictionary) -> void:
	_current_resources = resources
	_refresh_affordability()


func update_age(age: int) -> void:
	_current_age = age
	_rebuild_grid()


func _update_aux_button() -> void:
	if _placement_mode_active:
		cancel_button.visible = true
		cancel_button.disabled = false
		cancel_button.text = "Cancel"
		cancel_button.tooltip_text = "Cancel current placement"
		return

	if _last_selected_building_type < 0:
		cancel_button.visible = false
		return

	cancel_button.visible = true
	var building_name: String = BuildingData.get_building_name(_last_selected_building_type)
	cancel_button.text = "Repeat: %s" % building_name
	cancel_button.tooltip_text = "One-tap reselect of last building type"
	var cost: Dictionary = BuildingData.get_building_cost(_last_selected_building_type)
	cancel_button.disabled = not _can_afford(cost)
