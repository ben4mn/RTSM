extends CanvasLayer
## Main HUD overlay. Shows resources, selection info, minimap, and build toggle.
##
## Connects to GameManager and ResourceManager autoloads for live data.

signal build_menu_toggled(is_open: bool)
signal age_up_requested()
signal idle_villager_pressed()
signal train_unit_requested(building: Node2D, unit_type: int)

const RESOURCE_COLORS: Dictionary = {
	"food": Color(0.9, 0.35, 0.25),
	"wood": Color(0.45, 0.7, 0.3),
	"gold": Color(0.95, 0.85, 0.2),
}

const GAME_SPEEDS: Array[float] = [0.5, 1.0, 2.0]
const SPEED_LABELS: Array[String] = ["0.5x", "1x", "2x"]

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

@onready var minimap_rect: TextureRect = %MinimapRect

var _build_menu_open: bool = false
var _minimap_image: Image = null
var _minimap_texture: ImageTexture = null
var _minimap_timer: float = 0.0
const MINIMAP_UPDATE_INTERVAL: float = 1.0

# Pause / speed controls
var _pause_button: Button = null
var _speed_button: Button = null
var _game_speed_index: int = 1  # 0=0.5x, 1=1x, 2=2x

# Idle villager button
var _idle_villager_button: Button = null

# Train buttons
var _train_buttons_container: HBoxContainer = null
var _selected_building_ref: Node2D = null

# Debug panel reference (set from main.gd)
var _debug_panel: Node = null


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	selection_panel.visible = false

	build_menu_button.pressed.connect(_on_build_menu_pressed)
	age_up_button.pressed.connect(_on_age_up_pressed)
	age_up_button.visible = true

	# Apply custom theme
	_apply_game_theme()

	# Create new UI elements
	_create_game_control_buttons()
	_create_idle_villager_button()

	# Connect to autoloads if available
	if Engine.has_singleton("GameManager") or has_node("/root/GameManager"):
		var gm: Node = _get_game_manager()
		if gm:
			gm.age_advanced.connect(_on_age_advanced)
			gm.game_state_changed.connect(_on_game_state_changed)

	if has_node("/root/ResourceManager"):
		var rm: Node = _get_resource_manager()
		if rm and rm.has_signal("resources_changed"):
			rm.resources_changed.connect(_on_resources_changed)

	_update_age_display()
	_update_resource_display({"food": 200, "wood": 200, "gold": 100})


func _process(_delta: float) -> void:
	var gm: Node = _get_game_manager()
	if gm and gm.current_state == gm.GameState.PLAYING:
		game_time_label.text = gm.get_formatted_time()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("pause"):
		_on_pause_pressed()
	elif event is InputEventKey and (event.keycode == KEY_F1 or event.keycode == KEY_QUOTELEFT):
		if _debug_panel and _debug_panel.has_method("toggle"):
			_debug_panel.toggle()


# --- Pause / Speed controls ---

func _create_game_control_buttons() -> void:
	var root_ctrl: Control = $Root
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hbox.offset_left = -160
	hbox.offset_right = -8
	hbox.offset_top = 8
	hbox.offset_bottom = 40
	hbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	_pause_button = Button.new()
	_pause_button.text = "||"
	_pause_button.custom_minimum_size = Vector2(40, 30)
	_pause_button.pressed.connect(_on_pause_pressed)
	hbox.add_child(_pause_button)

	_speed_button = Button.new()
	_speed_button.text = "1x"
	_speed_button.custom_minimum_size = Vector2(50, 30)
	_speed_button.pressed.connect(_on_speed_pressed)
	hbox.add_child(_speed_button)

	root_ctrl.add_child(hbox)


func _on_pause_pressed() -> void:
	var gm: Node = _get_game_manager()
	if gm:
		gm.toggle_pause()
		var is_paused: bool = gm.current_state == gm.GameState.PAUSED
		_pause_button.text = ">" if is_paused else "||"


func _on_speed_pressed() -> void:
	_game_speed_index = (_game_speed_index + 1) % GAME_SPEEDS.size()
	var new_speed: float = GAME_SPEEDS[_game_speed_index]
	Engine.time_scale = new_speed
	_speed_button.text = SPEED_LABELS[_game_speed_index]


func set_pause_display(is_paused: bool) -> void:
	if _pause_button:
		_pause_button.text = ">" if is_paused else "||"


# --- Idle villager button ---

func _create_idle_villager_button() -> void:
	var root_ctrl: Control = $Root
	_idle_villager_button = Button.new()
	_idle_villager_button.text = "Idle: 0"
	_idle_villager_button.custom_minimum_size = Vector2(90, 30)
	_idle_villager_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_idle_villager_button.offset_left = -100
	_idle_villager_button.offset_right = -8
	_idle_villager_button.offset_top = -180
	_idle_villager_button.offset_bottom = -148
	_idle_villager_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_idle_villager_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_idle_villager_button.pressed.connect(_on_idle_villager_pressed)
	root_ctrl.add_child(_idle_villager_button)


func _on_idle_villager_pressed() -> void:
	idle_villager_pressed.emit()


func update_idle_villager_count(count: int) -> void:
	if _idle_villager_button:
		_idle_villager_button.text = "Idle: %d" % count


# --- Build menu ---

func is_build_menu_open() -> bool:
	return _build_menu_open


func close_build_menu() -> void:
	if _build_menu_open:
		_on_build_menu_pressed()


func set_debug_panel(panel: Node) -> void:
	_debug_panel = panel


# --- Resource display ---

func _on_resources_changed(player_id: int, _resource_type: String, _new_amount: int) -> void:
	if player_id != 0:
		return
	var rm: Node = _get_resource_manager()
	if rm:
		_update_resource_display(rm.get_all_resources(player_id))


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
	var gm: Node = _get_game_manager()
	if gm:
		var age: int = gm.get_player_age(0)
		age_label.text = gm.get_age_name(age)
		# Update age-up button text with cost
		if age == 1:
			age_up_button.text = "Age Up (400F 200G)"
		elif age == 2:
			age_up_button.text = "Age Up (1200F 600G)"
		else:
			age_up_button.text = "Max Age"
			age_up_button.disabled = true
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
	_selected_building_ref = null
	if _train_buttons_container:
		_train_buttons_container.visible = false


func show_building_selection(building_name: String, current_hp: int, max_hp: int, queue_items: Array, trainable_units: Array = [], building_ref: Node2D = null) -> void:
	selection_panel.visible = true
	selection_name.text = building_name
	selection_hp_bar.max_value = max_hp
	selection_hp_bar.value = current_hp
	selection_details.text = ""
	_selected_building_ref = building_ref
	_update_queue_display(queue_items)
	_update_train_buttons(trainable_units)


func clear_selection() -> void:
	selection_panel.visible = false
	_selected_building_ref = null
	if _train_buttons_container:
		_train_buttons_container.visible = false


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
		if item is Dictionary:
			var name_str: String = item.get("name", "?")
			if item.get("is_training", false):
				var pct: int = int(item.get("progress", 0.0) * 100)
				lbl.text = "%s (%d%%)" % [name_str, pct]
			else:
				lbl.text = name_str
		else:
			lbl.text = str(item)
		lbl.add_theme_font_size_override("font_size", 14)
		queue_container.add_child(lbl)


func _update_train_buttons(trainable_units: Array) -> void:
	# Create container on first use
	if _train_buttons_container == null:
		_train_buttons_container = HBoxContainer.new()
		_train_buttons_container.add_theme_constant_override("separation", 4)
		# Add it after queue_container in the selection panel's VBox
		var parent_vbox: Control = queue_container.get_parent()
		if parent_vbox:
			parent_vbox.add_child(_train_buttons_container)

	# Clear old buttons
	for child in _train_buttons_container.get_children():
		child.queue_free()

	if trainable_units.is_empty():
		_train_buttons_container.visible = false
		return

	_train_buttons_container.visible = true
	for ut in trainable_units:
		var unit_name: String = UnitData.get_unit_name(ut)
		var cost: Dictionary = UnitData.get_unit_cost(ut)
		var cost_str := ""
		if cost.get("food", 0) > 0:
			cost_str += "F:%d " % cost["food"]
		if cost.get("wood", 0) > 0:
			cost_str += "W:%d " % cost["wood"]
		if cost.get("gold", 0) > 0:
			cost_str += "G:%d " % cost["gold"]
		var btn := Button.new()
		btn.text = "Train %s (%s)" % [unit_name, cost_str.strip_edges()]
		btn.custom_minimum_size = Vector2(120, 30)
		btn.pressed.connect(_on_train_button_pressed.bind(ut))
		_train_buttons_container.add_child(btn)


func _on_train_button_pressed(unit_type: int) -> void:
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		train_unit_requested.emit(_selected_building_ref, unit_type)


# --- Build menu toggle ---

func _on_build_menu_pressed() -> void:
	_build_menu_open = !_build_menu_open
	build_menu_toggled.emit(_build_menu_open)
	build_menu_button.text = "X" if _build_menu_open else "Build"


# --- Age up ---

func _on_age_up_pressed() -> void:
	age_up_requested.emit()


func show_age_up_button(is_shown: bool) -> void:
	age_up_button.visible = is_shown


# --- Minimap ---

func update_minimap(grid: Array, player_units: Array, enemy_units: Array, player_buildings: Array = [], enemy_buildings: Array = []) -> void:
	if grid.is_empty():
		return

	var map_h: int = grid.size()
	var map_w: int = grid[0].size() if map_h > 0 else 0
	if map_w == 0:
		return

	# Create image on first call
	if _minimap_image == null or _minimap_image.get_width() != map_w:
		_minimap_image = Image.create(map_w, map_h, false, Image.FORMAT_RGB8)
		_minimap_texture = ImageTexture.create_from_image(_minimap_image)

	# Draw terrain
	for y in range(map_h):
		for x in range(map_w):
			var tile_type: int = grid[y][x]
			var color: Color = MapData.TILE_COLORS.get(tile_type, Color(0.35, 0.65, 0.25))
			_minimap_image.set_pixel(x, y, color)

	# Draw player units (blue dots)
	for unit in player_units:
		if not is_instance_valid(unit):
			continue
		var tile_pos: Vector2i = _world_to_tile_minimap(unit.global_position)
		if tile_pos.x >= 0 and tile_pos.x < map_w and tile_pos.y >= 0 and tile_pos.y < map_h:
			_minimap_image.set_pixel(tile_pos.x, tile_pos.y, Color(0.2, 0.5, 1.0))

	# Draw player buildings (bright blue squares)
	for building in player_buildings:
		if not is_instance_valid(building):
			continue
		var tile_pos: Vector2i = _world_to_tile_minimap(building.global_position)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var px: int = tile_pos.x + dx
				var py: int = tile_pos.y + dy
				if px >= 0 and px < map_w and py >= 0 and py < map_h:
					_minimap_image.set_pixel(px, py, Color(0.3, 0.6, 1.0))

	# Draw enemy buildings (bright red squares)
	for building in enemy_buildings:
		if not is_instance_valid(building):
			continue
		var tile_pos: Vector2i = _world_to_tile_minimap(building.global_position)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var px: int = tile_pos.x + dx
				var py: int = tile_pos.y + dy
				if px >= 0 and px < map_w and py >= 0 and py < map_h:
					_minimap_image.set_pixel(px, py, Color(1.0, 0.3, 0.3))

	# Draw enemy units (red dots)
	for unit in enemy_units:
		if not is_instance_valid(unit):
			continue
		var tile_pos: Vector2i = _world_to_tile_minimap(unit.global_position)
		if tile_pos.x >= 0 and tile_pos.x < map_w and tile_pos.y >= 0 and tile_pos.y < map_h:
			_minimap_image.set_pixel(tile_pos.x, tile_pos.y, Color(1.0, 0.25, 0.2))

	_minimap_texture.update(_minimap_image)
	minimap_rect.texture = _minimap_texture


func _world_to_tile_minimap(world_pos: Vector2) -> Vector2i:
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	var tile_x := int((world_pos.x / half_w + world_pos.y / half_h) / 2.0)
	var tile_y := int((world_pos.y / half_h - world_pos.x / half_w) / 2.0)
	return Vector2i(tile_x, tile_y)


# --- Helpers ---

func _get_game_manager() -> Node:
	return get_node_or_null("/root/GameManager")


func _get_resource_manager() -> Node:
	return get_node_or_null("/root/ResourceManager")


func _apply_game_theme() -> void:
	var root_ctrl: Control = $Root
	if root_ctrl == null:
		return

	# Load Kenney Pixel font
	var game_font: Font = null
	if ResourceLoader.exists("res://assets/ui/kenney_pixel.ttf"):
		game_font = load("res://assets/ui/kenney_pixel.ttf")

	# Create custom theme
	var theme := Theme.new()

	# Panel styles — dark semi-transparent with warm border
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.06, 0.04, 0.85)
	panel_style.border_color = Color(0.55, 0.42, 0.22, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(6)
	theme.set_stylebox("panel", "PanelContainer", panel_style)

	# Button styles
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.18, 0.14, 0.10, 0.9)
	btn_normal.border_color = Color(0.55, 0.42, 0.22, 0.7)
	btn_normal.set_border_width_all(2)
	btn_normal.set_corner_radius_all(3)
	btn_normal.set_content_margin_all(8)
	theme.set_stylebox("normal", "Button", btn_normal)

	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = Color(0.25, 0.20, 0.14, 0.95)
	btn_hover.border_color = Color(0.75, 0.60, 0.30, 0.9)
	theme.set_stylebox("hover", "Button", btn_hover)

	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.12, 0.09, 0.06, 0.95)
	btn_pressed.border_color = Color(0.45, 0.35, 0.18, 0.9)
	theme.set_stylebox("pressed", "Button", btn_pressed)

	var btn_disabled := btn_normal.duplicate()
	btn_disabled.bg_color = Color(0.10, 0.08, 0.06, 0.6)
	btn_disabled.border_color = Color(0.30, 0.25, 0.15, 0.4)
	theme.set_stylebox("disabled", "Button", btn_disabled)

	# ProgressBar styles
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.08, 0.05, 0.9)
	bar_bg.set_border_width_all(1)
	bar_bg.border_color = Color(0.3, 0.25, 0.15, 0.6)
	bar_bg.set_corner_radius_all(2)
	theme.set_stylebox("background", "ProgressBar", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.35, 0.70, 0.25, 0.9)
	bar_fill.set_corner_radius_all(2)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)

	# Font settings
	if game_font:
		theme.set_default_font(game_font)
	theme.set_default_font_size(16)

	# Label colors — warm parchment tone
	theme.set_color("font_color", "Label", Color(0.92, 0.88, 0.75))
	theme.set_color("font_color", "Button", Color(0.92, 0.88, 0.75))
	theme.set_color("font_disabled_color", "Button", Color(0.50, 0.45, 0.35))

	# Apply theme to root control
	root_ctrl.theme = theme

	# Keep explicit resource label colors
	food_label.add_theme_color_override("font_color", Color(0.95, 0.40, 0.30))
	wood_label.add_theme_color_override("font_color", Color(0.50, 0.78, 0.35))
	gold_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.25))
