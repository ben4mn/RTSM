extends CanvasLayer
## Main HUD overlay. Shows resources, selection info, minimap, and build toggle.
##
## Connects to GameManager and ResourceManager autoloads for live data.

signal build_menu_toggled(is_open: bool)
signal age_up_requested()

const RESOURCE_COLORS: Dictionary = {
	"food": Color(0.9, 0.35, 0.25),
	"wood": Color(0.45, 0.7, 0.3),
	"gold": Color(0.95, 0.85, 0.2),
}

@onready var food_label: Label = %FoodLabel
@onready var wood_label: Label = %WoodLabel
@onready var gold_label: Label = %GoldLabel
@onready var pop_label: Label = %PopLabel
@onready var age_label: Label = %AgeLabel
@onready var game_time_label: Label = %GameTimeLabel

@onready var selection_panel: PanelContainer = %SelectionPanel
@onready var selection_name: Label = %SelectionName
@onready var selection_hp_bar: ProgressBar = %SelectionHPBar
@onready var selection_details: Label = %SelectionDetails
@onready var queue_container: HBoxContainer = %QueueContainer

@onready var build_menu_button: Button = %BuildMenuButton
@onready var age_up_button: Button = %AgeUpButton

@onready var minimap_rect: ColorRect = %MinimapRect

var _build_menu_open: bool = false


func _ready() -> void:
	layer = 10
	selection_panel.visible = false

	build_menu_button.pressed.connect(_on_build_menu_pressed)
	age_up_button.pressed.connect(_on_age_up_pressed)
	age_up_button.visible = false

	# Connect to autoloads if available
	if Engine.has_singleton("GameManager") or has_node("/root/GameManager"):
		var gm := _get_game_manager()
		if gm:
			gm.age_advanced.connect(_on_age_advanced)
			gm.game_state_changed.connect(_on_game_state_changed)

	if has_node("/root/ResourceManager"):
		var rm := _get_resource_manager()
		if rm and rm.has_signal("resources_changed"):
			rm.resources_changed.connect(_on_resources_changed)

	_update_age_display()
	_update_resource_display({"food": 200, "wood": 200, "gold": 100})


func _process(_delta: float) -> void:
	var gm := _get_game_manager()
	if gm and gm.current_state == gm.GameState.PLAYING:
		game_time_label.text = gm.get_formatted_time()


# --- Resource display ---

func _on_resources_changed(resources: Dictionary) -> void:
	_update_resource_display(resources)


func _update_resource_display(resources: Dictionary) -> void:
	food_label.text = "Food: %d" % resources.get("food", 0)
	wood_label.text = "Wood: %d" % resources.get("wood", 0)
	gold_label.text = "Gold: %d" % resources.get("gold", 0)


func update_population(current: int, cap: int) -> void:
	pop_label.text = "Pop: %d/%d" % [current, cap]


# --- Age display ---

func _on_age_advanced(_player_id: int, _new_age: int) -> void:
	_update_age_display()


func _update_age_display() -> void:
	var gm := _get_game_manager()
	if gm:
		var age: int = gm.get_player_age(0)
		age_label.text = gm.get_age_name(age)
	else:
		age_label.text = "Dark Age"


func _on_game_state_changed(_new_state: int) -> void:
	pass  # Subclass or connect externally if needed


# --- Selection panel ---

func show_unit_selection(unit_name: String, current_hp: int, max_hp: int, action_text: String) -> void:
	selection_panel.visible = true
	selection_name.text = unit_name
	selection_hp_bar.max_value = max_hp
	selection_hp_bar.value = current_hp
	selection_details.text = action_text
	queue_container.visible = false


func show_building_selection(building_name: String, current_hp: int, max_hp: int, queue_items: Array) -> void:
	selection_panel.visible = true
	selection_name.text = building_name
	selection_hp_bar.max_value = max_hp
	selection_hp_bar.value = current_hp
	selection_details.text = ""
	_update_queue_display(queue_items)


func clear_selection() -> void:
	selection_panel.visible = false


func _update_queue_display(queue_items: Array) -> void:
	# Clear existing queue icons
	for child in queue_container.get_children():
		child.queue_free()

	if queue_items.is_empty():
		queue_container.visible = false
		return

	queue_container.visible = true
	for item in queue_items:
		var lbl := Label.new()
		lbl.text = str(item)
		lbl.add_theme_font_size_override("font_size", 14)
		queue_container.add_child(lbl)


# --- Build menu toggle ---

func _on_build_menu_pressed() -> void:
	_build_menu_open = !_build_menu_open
	build_menu_toggled.emit(_build_menu_open)
	build_menu_button.text = "X" if _build_menu_open else "Build"


# --- Age up ---

func _on_age_up_pressed() -> void:
	age_up_requested.emit()


func show_age_up_button(show: bool) -> void:
	age_up_button.visible = show


# --- Minimap ---

func update_minimap_data(_map_colors: PackedColorArray) -> void:
	# Simplified minimap: the main game scene will write pixel data here
	pass


# --- Helpers ---

func _get_game_manager() -> Node:
	return get_node_or_null("/root/GameManager")


func _get_resource_manager() -> Node:
	return get_node_or_null("/root/ResourceManager")
