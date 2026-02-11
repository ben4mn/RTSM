extends CanvasLayer
## Main HUD overlay. Shows resources, selection info, minimap, and build toggle.
##
## Connects to GameManager and ResourceManager autoloads for live data.

signal build_menu_toggled(is_open: bool)
signal age_up_requested()
signal idle_villager_pressed()
signal train_unit_requested(building: Node2D, unit_type: int)
signal minimap_clicked(world_pos: Vector2)
signal cancel_queue_requested(building: Node2D, index: int)
signal select_all_military_pressed()
signal find_army_pressed()
signal research_requested(building: Node2D, research_id: String)

const RESOURCE_COLORS: Dictionary = {
	"food": Color(0.9, 0.35, 0.25),
	"wood": Color(0.45, 0.7, 0.3),
	"gold": Color(0.95, 0.85, 0.2),
}

const GAME_SPEEDS: Array[float] = [0.5, 1.0, 2.0, 3.0]
const SPEED_LABELS: Array[String] = ["0.5x", "1x", "2x", "3x"]

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
var _auto_queue_button: CheckButton = null

# Debug panel reference (set from main.gd)
var _debug_panel: Node = null

# Notification feed
var _notification_container: VBoxContainer = null
const MAX_NOTIFICATIONS: int = 6
const NOTIFICATION_DURATION: float = 5.0

# Military buttons
var _select_military_button: Button = null
var _find_army_button: Button = null

# Idle villager flash tween
var _idle_flash_tween: Tween = null

# Research buttons
var _research_container: VBoxContainer = null

# Hotkey reference panel
var _hotkey_panel: PanelContainer = null

# Sacred site timer label
var _sacred_site_label: Label = null

# Score label
var _score_label: Label = null


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	selection_panel.visible = false

	build_menu_button.pressed.connect(_on_build_menu_pressed)
	build_menu_button.tooltip_text = "Toggle Build Menu [B]"
	age_up_button.pressed.connect(_on_age_up_pressed)
	age_up_button.visible = true
	age_up_button.tooltip_text = "Advance to next age"

	# Apply custom theme
	_apply_game_theme()

	# Create new UI elements
	_create_game_control_buttons()
	_create_idle_villager_button()
	_create_military_buttons()
	_create_notification_feed()
	_create_hotkey_panel()
	_create_sacred_site_label()
	_create_score_label()

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

	# Connect minimap click
	minimap_rect.gui_input.connect(_on_minimap_input)
	minimap_rect.mouse_filter = Control.MOUSE_FILTER_STOP

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
	elif event is InputEventKey and event.keycode == KEY_F2:
		_toggle_hotkey_panel()


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
	_pause_button.tooltip_text = "Pause/Resume [P]"
	hbox.add_child(_pause_button)

	_speed_button = Button.new()
	_speed_button.text = "1x"
	_speed_button.custom_minimum_size = Vector2(50, 30)
	_speed_button.pressed.connect(_on_speed_pressed)
	_speed_button.tooltip_text = "Cycle game speed"
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
	var bottom_right: VBoxContainer = %BottomRight
	_idle_villager_button = Button.new()
	_idle_villager_button.text = "Idle: 0"
	_idle_villager_button.custom_minimum_size = Vector2(140, 36)
	_idle_villager_button.pressed.connect(_on_idle_villager_pressed)
	_idle_villager_button.tooltip_text = "Cycle idle villagers [.]"
	bottom_right.add_child(_idle_villager_button)
	bottom_right.move_child(_idle_villager_button, 0)


func _on_idle_villager_pressed() -> void:
	idle_villager_pressed.emit()


func _create_military_buttons() -> void:
	var bottom_right: VBoxContainer = %BottomRight

	_select_military_button = Button.new()
	_select_military_button.text = "Military [M]"
	_select_military_button.custom_minimum_size = Vector2(140, 36)
	_select_military_button.pressed.connect(func(): select_all_military_pressed.emit())
	_select_military_button.tooltip_text = "Select all military units [M]"
	bottom_right.add_child(_select_military_button)
	bottom_right.move_child(_select_military_button, 1)

	_find_army_button = Button.new()
	_find_army_button.text = "Find Army [F]"
	_find_army_button.custom_minimum_size = Vector2(140, 36)
	_find_army_button.pressed.connect(func(): find_army_pressed.emit())
	_find_army_button.tooltip_text = "Center camera on your army [F]"
	bottom_right.add_child(_find_army_button)
	bottom_right.move_child(_find_army_button, 2)


func update_idle_villager_count(count: int) -> void:
	if _idle_villager_button:
		_idle_villager_button.text = "Idle: %d" % count
		if count > 0:
			if _idle_flash_tween == null or not _idle_flash_tween.is_valid():
				_idle_flash_tween = create_tween().set_loops()
				_idle_flash_tween.tween_property(_idle_villager_button, "modulate", Color(1.0, 0.85, 0.2), 0.5)
				_idle_flash_tween.tween_property(_idle_villager_button, "modulate", Color.WHITE, 0.5)
		else:
			if _idle_flash_tween and _idle_flash_tween.is_valid():
				_idle_flash_tween.kill()
				_idle_flash_tween = null
			_idle_villager_button.modulate = Color.WHITE


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
		# Update age-up button text with cost and preview
		if age == 1:
			age_up_button.text = "Age Up (400F 200G)"
			age_up_button.tooltip_text = _get_age_up_preview(age + 1)
			age_up_button.disabled = false
		elif age == 2:
			age_up_button.text = "Age Up (1200F 600G)"
			age_up_button.tooltip_text = _get_age_up_preview(age + 1)
			age_up_button.disabled = false
		else:
			age_up_button.text = "Max Age"
			age_up_button.tooltip_text = "You have reached the highest age"
			age_up_button.disabled = true
	else:
		age_label.text = "Dark Age"


func _get_age_up_preview(next_age: int) -> String:
	var gm: Node = _get_game_manager()
	var age_name: String = gm.get_age_name(next_age) if gm else "Age %d" % next_age
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Advance to %s" % age_name)
	lines.append("")
	# Find buildings that unlock at this age
	var new_buildings: PackedStringArray = PackedStringArray()
	for key in BuildingData.BUILDINGS:
		var data: Dictionary = BuildingData.BUILDINGS[key]
		if data["age_required"] == next_age:
			new_buildings.append(data["name"])
	if new_buildings.size() > 0:
		lines.append("Unlocks buildings:")
		for b_name in new_buildings:
			lines.append("  + %s" % b_name)
	# Find units that become available via new buildings
	var new_units: PackedStringArray = PackedStringArray()
	for key in BuildingData.BUILDINGS:
		var data: Dictionary = BuildingData.BUILDINGS[key]
		if data["age_required"] == next_age:
			for ut in data["can_train"]:
				var u_name: String = UnitData.get_unit_name(ut)
				if u_name not in new_units:
					new_units.append(u_name)
	if new_units.size() > 0:
		lines.append("Unlocks units:")
		for u_name in new_units:
			lines.append("  + %s" % u_name)
	return "\n".join(lines)


func _on_game_state_changed(_new_state: int) -> void:
	pass  # Subclass or connect externally if needed


# --- Selection panel ---

func show_unit_selection(unit_name: String, current_hp: int, max_hp: int, action_text: String, count: int = 1, unit_stats: Dictionary = {}) -> void:
	selection_panel.visible = true
	if count > 1:
		selection_name.text = "%dx %s" % [count, unit_name]
	else:
		selection_name.text = unit_name
	selection_hp_bar.max_value = max_hp
	selection_hp_bar.value = current_hp
	# Show stats line + action text
	var stats_line := ""
	if not unit_stats.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		if unit_stats.has("damage"):
			parts.append("Atk:%d" % unit_stats["damage"])
		if unit_stats.has("armor"):
			parts.append("Arm:%d" % unit_stats["armor"])
		if unit_stats.has("range") and unit_stats["range"] > 1:
			parts.append("Rng:%d" % unit_stats["range"])
		if parts.size() > 0:
			stats_line = " | ".join(parts) + "\n"
	selection_details.text = stats_line + action_text
	queue_container.visible = false
	_selected_building_ref = null
	if _train_buttons_container:
		_train_buttons_container.visible = false
	if _research_container:
		_research_container.visible = false


func show_building_selection(building_name: String, current_hp: int, max_hp: int, queue_items: Array, trainable_units: Array = [], building_ref: Node2D = null) -> void:
	selection_panel.visible = true
	selection_name.text = building_name
	selection_hp_bar.max_value = max_hp
	selection_hp_bar.value = current_hp
	# Show building details
	var detail_parts: PackedStringArray = PackedStringArray()
	if building_ref and is_instance_valid(building_ref) and building_ref is BuildingBase:
		var b: BuildingBase = building_ref as BuildingBase
		var stats: Dictionary = BuildingData.BUILDINGS.get(b.building_type, {})
		if stats.get("pop_provided", 0) > 0:
			detail_parts.append("+%d pop" % stats["pop_provided"])
		var drop_off: Array = stats.get("drop_off", [])
		if drop_off.size() > 0:
			detail_parts.append("Drop-off: %s" % ", ".join(PackedStringArray(drop_off)))
		if stats.get("attack_damage", 0) > 0:
			detail_parts.append("Atk:%d Rng:%d" % [stats["attack_damage"], stats.get("attack_range", 0)])
		if b.state == BuildingBase.State.CONSTRUCTING:
			detail_parts.append("Under construction...")
	selection_details.text = " | ".join(detail_parts) if detail_parts.size() > 0 else ""
	_selected_building_ref = building_ref
	_update_queue_display(queue_items)
	_update_train_buttons(trainable_units)
	_update_research_buttons(building_ref)


func show_resource_info(type_name: String, remaining: int, total: int, pct: int) -> void:
	selection_panel.visible = true
	selection_name.text = "%s Resource" % type_name
	selection_hp_bar.max_value = total
	selection_hp_bar.value = remaining
	selection_details.text = "%d / %d remaining (%d%%)" % [remaining, total, pct]
	queue_container.visible = false
	_selected_building_ref = null
	if _train_buttons_container:
		_train_buttons_container.visible = false
	if _research_container:
		_research_container.visible = false


func clear_selection() -> void:
	selection_panel.visible = false
	_selected_building_ref = null
	if _train_buttons_container:
		_train_buttons_container.visible = false
	if _research_container:
		_research_container.visible = false


func _update_queue_display(queue_items: Array) -> void:
	# Clear existing queue icons
	for child in queue_container.get_children():
		child.queue_free()

	if queue_items.is_empty():
		queue_container.visible = false
		return

	queue_container.visible = true
	for i in queue_items.size():
		var item = queue_items[i]
		var btn := Button.new()
		if item is Dictionary:
			var name_str: String = item.get("name", "?")
			if item.get("is_training", false):
				var progress: float = item.get("progress", 0.0)
				var pct: int = int(progress * 100)
				# Show remaining time estimate
				var unit_type: int = item.get("unit_type", -1)
				var train_time: float = UnitData.UNITS.get(unit_type, {}).get("build_time", 15.0)
				var remaining: float = maxf(0.0, train_time * (1.0 - progress))
				btn.text = "%s %d%% (%ds)" % [name_str, pct, int(remaining)]
			else:
				btn.text = name_str
		else:
			btn.text = str(item)
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(100, 24)
		btn.tooltip_text = "Click to cancel"
		btn.pressed.connect(_on_cancel_queue_pressed.bind(i))
		queue_container.add_child(btn)


func _on_cancel_queue_pressed(index: int) -> void:
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		cancel_queue_requested.emit(_selected_building_ref, index)


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
		var stats: Dictionary = UnitData.UNITS.get(ut, {})
		var train_time: float = stats.get("build_time", 15.0)
		var cost_str := ""
		if cost.get("food", 0) > 0:
			cost_str += "F:%d " % cost["food"]
		if cost.get("wood", 0) > 0:
			cost_str += "W:%d " % cost["wood"]
		if cost.get("gold", 0) > 0:
			cost_str += "G:%d " % cost["gold"]
		var btn := Button.new()
		btn.text = "Train %s (%s) %ds" % [unit_name, cost_str.strip_edges(), int(train_time)]
		btn.custom_minimum_size = Vector2(140, 30)
		# Build detailed tooltip with unit stats
		var tip_lines: PackedStringArray = PackedStringArray()
		tip_lines.append("%s [Q]" % unit_name)
		tip_lines.append("HP: %d  Atk: %d  Arm: %d" % [stats.get("hp", 0), stats.get("damage", 0), stats.get("armor", 0)])
		if stats.get("attack_range", 1) > 1:
			tip_lines.append("Range: %d" % stats["attack_range"])
		tip_lines.append("Speed: %d  Pop: %d" % [int(stats.get("speed", 50)), stats.get("pop_cost", 1)])
		tip_lines.append("Train time: %ds" % int(train_time))
		btn.tooltip_text = "\n".join(tip_lines)
		btn.pressed.connect(_on_train_button_pressed.bind(ut))
		_train_buttons_container.add_child(btn)

	# Auto-queue checkbox
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		var pq: Node = _selected_building_ref.get_production_queue() if _selected_building_ref.has_method("get_production_queue") else null
		if pq:
			_auto_queue_button = CheckButton.new()
			_auto_queue_button.text = "Auto"
			_auto_queue_button.button_pressed = pq.auto_queue_enabled
			_auto_queue_button.toggled.connect(_on_auto_queue_toggled)
			_train_buttons_container.add_child(_auto_queue_button)


func _on_train_button_pressed(unit_type: int) -> void:
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		train_unit_requested.emit(_selected_building_ref, unit_type)


func _on_auto_queue_toggled(pressed: bool) -> void:
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		var pq: Node = _selected_building_ref.get_production_queue() if _selected_building_ref.has_method("get_production_queue") else null
		if pq:
			pq.auto_queue_enabled = pressed


# --- Research buttons (Blacksmith) ---

const RESEARCH_DEFS: Array = [
	{"id": "forging", "name": "Forge Weapons", "desc": "+2 Attack", "cost": {"food": 100, "gold": 50}},
	{"id": "scale_mail", "name": "Scale Mail", "desc": "+1 Armor", "cost": {"food": 100, "gold": 50}},
]


func _update_research_buttons(building_ref: Node2D) -> void:
	# Create container on first use
	if _research_container == null:
		_research_container = VBoxContainer.new()
		_research_container.add_theme_constant_override("separation", 4)
		var parent_vbox: Control = queue_container.get_parent()
		if parent_vbox:
			parent_vbox.add_child(_research_container)

	# Clear old buttons
	for child in _research_container.get_children():
		child.queue_free()

	# Only show for Blacksmith
	if building_ref == null or not is_instance_valid(building_ref):
		_research_container.visible = false
		return
	if not (building_ref is BuildingBase):
		_research_container.visible = false
		return
	var b: BuildingBase = building_ref as BuildingBase
	if b.building_type != BuildingData.BuildingType.BLACKSMITH or b.state != BuildingBase.State.ACTIVE:
		_research_container.visible = false
		return

	_research_container.visible = true
	var gm: Node = _get_game_manager()

	for rd in RESEARCH_DEFS:
		var btn := Button.new()
		var cost_str := ""
		if rd["cost"].get("food", 0) > 0:
			cost_str += "F:%d " % rd["cost"]["food"]
		if rd["cost"].get("gold", 0) > 0:
			cost_str += "G:%d" % rd["cost"]["gold"]
		btn.text = "%s: %s (%s)" % [rd["name"], rd["desc"], cost_str.strip_edges()]
		btn.custom_minimum_size = Vector2(200, 32)
		var already_done: bool = false
		if gm and gm.has_method("has_research"):
			already_done = gm.has_research(b.player_owner, rd["id"])
		if already_done:
			btn.text += " [DONE]"
			btn.disabled = true
		else:
			btn.pressed.connect(_on_research_pressed.bind(rd["id"]))
		_research_container.add_child(btn)


func _on_research_pressed(research_id: String) -> void:
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		research_requested.emit(_selected_building_ref, research_id)


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

func update_minimap(grid: Array, player_units: Array, enemy_units: Array, player_buildings: Array = [], enemy_buildings: Array = [], camera_rect: Rect2 = Rect2(), fog: Node = null) -> void:
	if grid.is_empty():
		return

	var map_h: int = grid.size()
	var map_w: int = grid[0].size() if map_h > 0 else 0
	if map_w == 0:
		return

	# Get fog grid if available
	var fog_grid: Array = []
	if fog and fog.has_method("is_tile_visible"):
		fog_grid = fog.fog_grid

	# Create image on first call
	if _minimap_image == null or _minimap_image.get_width() != map_w:
		_minimap_image = Image.create(map_w, map_h, false, Image.FORMAT_RGB8)
		_minimap_texture = ImageTexture.create_from_image(_minimap_image)

	# Draw terrain with fog awareness
	for y in range(map_h):
		for x in range(map_w):
			var tile_type: int = grid[y][x]
			var color: Color = MapData.TILE_COLORS.get(tile_type, Color(0.35, 0.65, 0.25))
			# Apply fog darkening
			if fog_grid.size() > 0:
				var fog_state: int = fog_grid[y][x]
				if fog_state == MapData.FogState.UNEXPLORED:
					color = Color(0.05, 0.05, 0.05)
				elif fog_state == MapData.FogState.EXPLORED:
					color = color.darkened(0.5)
			_minimap_image.set_pixel(x, y, color)

	# Draw player units (blue dots) — always visible (own units)
	for unit in player_units:
		if not is_instance_valid(unit):
			continue
		var tile_pos: Vector2i = _world_to_tile_minimap(unit.global_position)
		if tile_pos.x >= 0 and tile_pos.x < map_w and tile_pos.y >= 0 and tile_pos.y < map_h:
			_minimap_image.set_pixel(tile_pos.x, tile_pos.y, Color(0.2, 0.5, 1.0))

	# Draw player buildings (bright blue squares) — always visible (own buildings)
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

	# Draw enemy buildings (bright red squares) — only if tile is visible
	for building in enemy_buildings:
		if not is_instance_valid(building):
			continue
		var tile_pos: Vector2i = _world_to_tile_minimap(building.global_position)
		var show: bool = fog_grid.is_empty()  # Show all if no fog
		if not show and tile_pos.y >= 0 and tile_pos.y < map_h and tile_pos.x >= 0 and tile_pos.x < map_w:
			show = fog_grid[tile_pos.y][tile_pos.x] == MapData.FogState.VISIBLE
		if show:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var px: int = tile_pos.x + dx
					var py: int = tile_pos.y + dy
					if px >= 0 and px < map_w and py >= 0 and py < map_h:
						_minimap_image.set_pixel(px, py, Color(1.0, 0.3, 0.3))

	# Draw enemy units (red dots) — only if tile is visible
	for unit in enemy_units:
		if not is_instance_valid(unit):
			continue
		var tile_pos: Vector2i = _world_to_tile_minimap(unit.global_position)
		if tile_pos.x >= 0 and tile_pos.x < map_w and tile_pos.y >= 0 and tile_pos.y < map_h:
			var show: bool = fog_grid.is_empty()
			if not show:
				show = fog_grid[tile_pos.y][tile_pos.x] == MapData.FogState.VISIBLE
			if show:
				_minimap_image.set_pixel(tile_pos.x, tile_pos.y, Color(1.0, 0.25, 0.2))

	# Draw camera rectangle (white outline)
	if camera_rect.size.x > 0 and camera_rect.size.y > 0:
		var tl: Vector2i = _world_to_tile_minimap(camera_rect.position)
		var br: Vector2i = _world_to_tile_minimap(camera_rect.position + camera_rect.size)
		var cam_color := Color(1.0, 1.0, 1.0, 0.9)
		# Draw top and bottom edges
		for tx in range(maxi(0, tl.x), mini(map_w, br.x + 1)):
			if tl.y >= 0 and tl.y < map_h:
				_minimap_image.set_pixel(tx, tl.y, cam_color)
			if br.y >= 0 and br.y < map_h:
				_minimap_image.set_pixel(tx, br.y, cam_color)
		# Draw left and right edges
		for ty in range(maxi(0, tl.y), mini(map_h, br.y + 1)):
			if tl.x >= 0 and tl.x < map_w:
				_minimap_image.set_pixel(tl.x, ty, cam_color)
			if br.x >= 0 and br.x < map_w:
				_minimap_image.set_pixel(br.x, ty, cam_color)

	# Draw sacred site (bright purple dot at map center, always visible)
	@warning_ignore("integer_division")
	var sacred_x: int = map_w / 2
	@warning_ignore("integer_division")
	var sacred_y: int = map_h / 2
	var sacred_color := Color(0.85, 0.55, 1.0)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var px: int = sacred_x + dx
			var py: int = sacred_y + dy
			if px >= 0 and px < map_w and py >= 0 and py < map_h:
				# Only show if explored
				if fog_grid.is_empty() or fog_grid[py][px] != MapData.FogState.UNEXPLORED:
					_minimap_image.set_pixel(px, py, sacred_color)

	_minimap_texture.update(_minimap_image)
	minimap_rect.texture = _minimap_texture


func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_minimap_click(event.position)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_handle_minimap_click(event.position)


func _handle_minimap_click(local_pos: Vector2) -> void:
	var rect_size: Vector2 = minimap_rect.size
	if rect_size.x <= 0 or rect_size.y <= 0:
		return
	# Normalize click position to 0-1 range
	var nx: float = clampf(local_pos.x / rect_size.x, 0.0, 1.0)
	var ny: float = clampf(local_pos.y / rect_size.y, 0.0, 1.0)
	# Convert to tile coordinates
	var tile_x: int = int(nx * MapData.MAP_WIDTH)
	var tile_y: int = int(ny * MapData.MAP_HEIGHT)
	# Convert tile to world using isometric formula
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	var wx: float = (tile_x - tile_y) * half_w
	var wy: float = (tile_x + tile_y) * half_h
	minimap_clicked.emit(Vector2(wx, wy))


func _world_to_tile_minimap(world_pos: Vector2) -> Vector2i:
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	var tile_x := int((world_pos.x / half_w + world_pos.y / half_h) / 2.0)
	var tile_y := int((world_pos.y / half_h - world_pos.x / half_w) / 2.0)
	return Vector2i(tile_x, tile_y)


# --- Notification feed ---

func _create_notification_feed() -> void:
	var root_ctrl: Control = $Root
	_notification_container = VBoxContainer.new()
	_notification_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_notification_container.offset_left = 8
	_notification_container.offset_top = 48
	_notification_container.offset_right = 260
	_notification_container.offset_bottom = 280
	_notification_container.add_theme_constant_override("separation", 2)
	_notification_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_notification_container)


func show_notification(text: String, color: Color = Color.WHITE) -> void:
	if _notification_container == null:
		return
	# Cap at max visible
	while _notification_container.get_child_count() >= MAX_NOTIFICATIONS:
		var oldest: Node = _notification_container.get_child(0)
		oldest.queue_free()
		_notification_container.remove_child(oldest)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.75)
	style.border_color = color
	style.border_width_left = 3
	style.set_content_margin_all(4)
	style.content_margin_left = 8
	style.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	_notification_container.add_child(panel)

	# Auto-fade and remove after duration
	var tween := create_tween()
	tween.tween_interval(NOTIFICATION_DURATION)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


# --- Hotkey Reference Panel ---

func _create_hotkey_panel() -> void:
	var root_ctrl: Control = $Root
	_hotkey_panel = PanelContainer.new()
	_hotkey_panel.set_anchors_preset(Control.PRESET_CENTER)
	_hotkey_panel.offset_left = -180
	_hotkey_panel.offset_right = 180
	_hotkey_panel.offset_top = -200
	_hotkey_panel.offset_bottom = 200
	_hotkey_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = "Hotkeys [F2]"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hotkeys: Array = [
		["Q", "Train unit (from selected building)"],
		["B", "Toggle build menu"],
		["H", "Select Town Center"],
		["M", "Select all military"],
		["F", "Find/center on army"],
		[".", "Cycle idle villagers"],
		["S", "Toggle stance (Aggr/Stand)"],
		["T", "Stop selected units"],
		["Del", "Demolish selected building"],
		["Ctrl+A", "Select all own units"],
		["Ctrl+1-9", "Save control group"],
		["1-9", "Recall control group"],
		["+/-", "Game speed (0.5x-3x)"],
		["P", "Pause / Resume"],
		["Esc", "Cancel / Deselect"],
		["F1/`", "Debug panel"],
	]

	for pair in hotkeys:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		var key_lbl := Label.new()
		key_lbl.text = pair[0]
		key_lbl.custom_minimum_size = Vector2(80, 0)
		key_lbl.add_theme_font_size_override("font_size", 13)
		key_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		hbox.add_child(key_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = pair[1]
		desc_lbl.add_theme_font_size_override("font_size", 13)
		hbox.add_child(desc_lbl)
		vbox.add_child(hbox)

	_hotkey_panel.add_child(vbox)
	root_ctrl.add_child(_hotkey_panel)


func _toggle_hotkey_panel() -> void:
	if _hotkey_panel:
		_hotkey_panel.visible = not _hotkey_panel.visible


# --- Sacred Site Timer ---

func _create_sacred_site_label() -> void:
	var root_ctrl: Control = $Root
	_sacred_site_label = Label.new()
	_sacred_site_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sacred_site_label.offset_top = 32
	_sacred_site_label.offset_left = -120
	_sacred_site_label.offset_right = 120
	_sacred_site_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sacred_site_label.add_theme_font_size_override("font_size", 15)
	_sacred_site_label.visible = false
	_sacred_site_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_sacred_site_label)


func update_sacred_site_timer(player_id: int, remaining: float, total: float) -> void:
	if _sacred_site_label == null:
		return
	if player_id < 0 or remaining <= 0.0:
		_sacred_site_label.visible = false
		return
	_sacred_site_label.visible = true
	@warning_ignore("integer_division")
	var mins: int = int(remaining) / 60
	@warning_ignore("integer_division")
	var secs: int = int(remaining) % 60
	var owner_name: String = "You" if player_id == 0 else "Enemy"
	_sacred_site_label.text = "Sacred Site: %s (%d:%02d)" % [owner_name, mins, secs]
	if player_id == 0:
		_sacred_site_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	else:
		_sacred_site_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	# Flash warning when under 60s
	if remaining < 60.0 and player_id != 0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
		_sacred_site_label.add_theme_color_override("font_color", Color(1.0, lerpf(0.2, 0.5, pulse), 0.2))


# --- Score Display ---

func _create_score_label() -> void:
	var root_ctrl: Control = $Root
	_score_label = Label.new()
	_score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score_label.offset_left = -260
	_score_label.offset_right = -170
	_score_label.offset_top = 8
	_score_label.offset_bottom = 28
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.add_theme_font_size_override("font_size", 13)
	_score_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	_score_label.text = "Score: 0"
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_score_label)


func update_score(score: int) -> void:
	if _score_label:
		_score_label.text = "Score: %d" % score


# --- Military Count ---

func update_military_count(count: int) -> void:
	if _select_military_button:
		_select_military_button.text = "Military: %d [M]" % count
	if _find_army_button:
		_find_army_button.text = "Find Army: %d [F]" % count


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
