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

var _current_age: int = 1
var _current_resources: Dictionary = {"food": 0, "wood": 0, "gold": 0}
var _button_map: Dictionary = {}  # building_type -> Button


func _ready() -> void:
	visible = false
	cancel_button.pressed.connect(_on_cancel_pressed)
	cancel_button.visible = false

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		gm.age_advanced.connect(_on_age_advanced)

	var rm: Node = get_node_or_null("/root/ResourceManager")
	if rm and rm.has_signal("resources_changed"):
		rm.resources_changed.connect(_on_resources_changed)

	_rebuild_grid()


func open_menu() -> void:
	visible = true
	cancel_button.visible = false
	_refresh_affordability()


func close_menu() -> void:
	visible = false


func set_placement_mode(active: bool) -> void:
	cancel_button.visible = active
	# Disable building buttons while placing
	for btn_type in _button_map:
		_button_map[btn_type].disabled = active


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
		btn.add_theme_font_size_override("font_size", 14)
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
	return "%s\n%s" % [stats["name"], " ".join(parts)]


# --- Affordability ---

func _refresh_affordability() -> void:
	for building_type in _button_map:
		var cost: Dictionary = BuildingData.get_building_cost(building_type)
		var can_afford: bool = _can_afford(cost)
		var btn: Button = _button_map[building_type]
		btn.disabled = !can_afford
		if can_afford:
			btn.modulate = Color.WHITE
		else:
			btn.modulate = Color(0.5, 0.5, 0.5, 0.8)


func _can_afford(cost: Dictionary) -> bool:
	for resource_key in cost:
		if cost[resource_key] > _current_resources.get(resource_key, 0):
			return false
	return true


# --- Signal handlers ---

func _on_building_button_pressed(building_type: int) -> void:
	building_selected.emit(building_type)
	set_placement_mode(true)


func _on_cancel_pressed() -> void:
	cancel_placement.emit()
	set_placement_mode(false)


func _on_age_advanced(_player_id: int, new_age: int) -> void:
	_current_age = new_age
	_rebuild_grid()


func _on_resources_changed(resources: Dictionary) -> void:
	_current_resources = resources
	_refresh_affordability()


func update_resources(resources: Dictionary) -> void:
	_current_resources = resources
	_refresh_affordability()


func update_age(age: int) -> void:
	_current_age = age
	_rebuild_grid()
