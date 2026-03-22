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
signal placement_cancel_requested()
signal pause_requested()
signal resume_requested()
signal quit_to_menu_requested()

const RESOURCE_COLORS: Dictionary = {
	"food": Color(0.9, 0.35, 0.25),
	"wood": Color(0.45, 0.7, 0.3),
	"gold": Color(0.95, 0.85, 0.2),
}

const GAME_SPEEDS: Array[float] = [0.5, 1.0, 2.0, 3.0]
const SPEED_LABELS: Array[String] = ["0.5x", "1x", "2x", "3x"]
const MOBILE_ACTION_BUTTON_HEIGHT := 56.0
const MOBILE_ACTION_MIN_BUTTON_WIDTH := 96.0
const MOBILE_ACTION_MAX_BUTTON_WIDTH := 180.0
const MOBILE_ACTION_GAP := 8.0
const MOBILE_ACTION_MARGIN := 8.0
const MOBILE_ACTION_INNER_PADDING := 10.0
const MOBILE_ACTION_DOUBLE_ROW_BREAKPOINT := 520.0
const MOBILE_MINIMAP_MIN_SIZE := 170.0
const MOBILE_MINIMAP_MAX_SIZE := 220.0
const MOBILE_MINIMAP_SHORT_SIDE_RATIO := 0.46
const MOBILE_TOP_BAR_COMPACT_SHORT_SIDE := 430.0
const MOBILE_TOP_BAR_COMPACT_WIDTH := 780.0
const PHONE_LAYOUT_KEYS: PackedStringArray = ["844x390", "932x430"]

enum UIModalState {
	NONE,
	BUILD_MENU,
	PAUSE_MENU,
	AGE_UP,
}

@onready var food_label: Label = %FoodLabel
@onready var wood_label: Label = %WoodLabel
@onready var gold_label: Label = %GoldLabel
@onready var pop_label: Label = %PopLabel
@onready var age_label: Label = %AgeLabel
@onready var game_time_label: Label = %GameTimeLabel
@onready var top_bar_hbox: HBoxContainer = $Root/TopBar/TopBarMargin/HBox
@onready var top_bar: PanelContainer = $Root/TopBar
@onready var minimap_bg: ColorRect = $Root/MinimapBG

@onready var selection_panel: PanelContainer = %SelectionPanel
@onready var selection_name: Label = %SelectionName
@onready var selection_hp_bar: ProgressBar = %SelectionHPBar
@onready var selection_details: Label = %SelectionDetails
@onready var queue_container: HBoxContainer = %QueueContainer

@onready var build_menu_button: Button = %BuildMenuButton
@onready var age_up_button: Button = %AgeUpButton

@onready var minimap_rect: TextureRect = %MinimapRect

var _build_menu_open: bool = false
var _ui_modal_state: UIModalState = UIModalState.NONE
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
var _villager_task_hbox: HBoxContainer = null

# Mobile action strip
var _mobile_action_panel: PanelContainer = null
var _mobile_action_strip: GridContainer = null
var _placement_cancel_button: Button = null
var _mobile_compact_labels: bool = false
var _last_idle_villager_count: int = 0
var _last_military_count: int = 0
var _top_bar_compact: bool = false

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

# Pause menu overlay
var _pause_overlay: ColorRect = null
var _resource_node_legend: HBoxContainer = null
var _progression_hint_panel: PanelContainer = null
var _progression_hint_label: Label = null
var _minimap_hint_label: Label = null
var _minimap_touch_index: int = -1
var _resource_values: Dictionary = {"food": 0, "wood": 0, "gold": 0}
var _population_current: int = 0
var _population_cap: int = 5
var _last_queue_items: Array = []
var _queue_counts_by_unit: Dictionary = {}
var _primary_action_focus: String = ""
var _primary_action_unit_type: int = -1
var _primary_action_building_type: int = -1
var _early_game_ui_active: bool = false
var _guided_military_shortcuts_visible: bool = false
var _pending_military_shortcut: bool = false
var _focus_pulse_time: float = 0.0

# MCP-readable diagnostics for phone layout checks.
@export var mobile_layout_diagnostics: Dictionary = {}
@export var mobile_layout_profiles: Dictionary = {}
@export var touch_target_diagnostics: Dictionary = {}


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
	_create_resource_node_legend()

	# Create new UI elements
	_create_game_control_buttons()
	_ensure_mobile_action_strip()
	_create_idle_villager_button()
	_create_military_buttons()
	_create_notification_feed()
	_create_hotkey_panel()
	_create_sacred_site_label()
	_create_score_label()
	_create_progression_hint()
	_create_minimap_hint()

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
	minimap_bg.gui_input.connect(_on_minimap_input)
	minimap_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap_bg.color = Color(0.05, 0.07, 0.1, 0.9)

	_update_age_display()
	_update_resource_display({"food": 200, "wood": 200, "gold": 100})
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))
	_refresh_touch_target_diagnostics()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))


func _get_safe_area_rect(viewport_size: Vector2) -> Rect2:
	var safe_rect_i: Rect2i = DisplayServer.get_display_safe_area()
	if safe_rect_i.size.x <= 0 or safe_rect_i.size.y <= 0:
		return Rect2(Vector2.ZERO, viewport_size)
	return Rect2(Vector2(safe_rect_i.position), Vector2(safe_rect_i.size))


func _create_resource_node_legend() -> void:
	if _resource_node_legend != null:
		return
	_resource_node_legend = HBoxContainer.new()
	_resource_node_legend.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Nodes:"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.88, 0.85, 0.78))
	_resource_node_legend.add_child(title)

	for item in [
		{"label": "F", "name": "Food", "color": RESOURCE_COLORS["food"]},
		{"label": "W", "name": "Wood", "color": RESOURCE_COLORS["wood"]},
		{"label": "G", "name": "Gold", "color": RESOURCE_COLORS["gold"]},
	]:
		var chip := Label.new()
		chip.text = item["label"]
		chip.tooltip_text = "%s node marker" % item["name"]
		chip.add_theme_font_size_override("font_size", 12)
		chip.add_theme_color_override("font_color", item["color"])
		_resource_node_legend.add_child(chip)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(8, 1)
	_resource_node_legend.add_child(spacer)
	top_bar_hbox.add_child(_resource_node_legend)
	var top_spacer: Node = top_bar_hbox.get_node_or_null("Spacer")
	if top_spacer != null:
		var spacer_index: int = top_spacer.get_index()
		top_bar_hbox.move_child(_resource_node_legend, spacer_index)


func _process(_delta: float) -> void:
	var gm: Node = _get_game_manager()
	if gm and gm.current_state == gm.GameState.PLAYING:
		game_time_label.text = gm.get_formatted_time()
	_focus_pulse_time += _delta
	_refresh_primary_action_visuals()


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
	hbox.name = "GameControlButtons"
	hbox.add_theme_constant_override("separation", 4)
	hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hbox.offset_left = -192
	hbox.offset_right = -8
	hbox.offset_top = 8
	hbox.offset_bottom = 64
	hbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	_pause_button = Button.new()
	_pause_button.name = "PauseButton"
	_pause_button.text = "||"
	_pause_button.custom_minimum_size = Vector2(56, 56)
	_pause_button.pressed.connect(_on_pause_pressed)
	_pause_button.tooltip_text = "Pause/Resume [P]"
	hbox.add_child(_pause_button)

	_speed_button = Button.new()
	_speed_button.name = "SpeedButton"
	_speed_button.text = "1x"
	_speed_button.custom_minimum_size = Vector2(72, 56)
	_speed_button.pressed.connect(_on_speed_pressed)
	_speed_button.tooltip_text = "Cycle game speed"
	hbox.add_child(_speed_button)

	root_ctrl.add_child(hbox)


func _on_pause_pressed() -> void:
	var gm: Node = _get_game_manager()
	if gm and gm.current_state == gm.GameState.PAUSED:
		resume_requested.emit()
	else:
		pause_requested.emit()


func _on_speed_pressed() -> void:
	_game_speed_index = (_game_speed_index + 1) % GAME_SPEEDS.size()
	var new_speed: float = GAME_SPEEDS[_game_speed_index]
	Engine.time_scale = new_speed
	_speed_button.text = SPEED_LABELS[_game_speed_index]


func sync_speed_display(speed: float) -> void:
	for i in GAME_SPEEDS.size():
		if absf(GAME_SPEEDS[i] - speed) < 0.01:
			_game_speed_index = i
			if _speed_button:
				_speed_button.text = SPEED_LABELS[i]
			return


func set_pause_display(is_paused: bool) -> void:
	set_ui_modal_state(UIModalState.PAUSE_MENU if is_paused else UIModalState.NONE)


func _toggle_pause_overlay(show: bool) -> void:
	if show:
		if _pause_overlay == null:
			_create_pause_overlay()
	if _pause_overlay != null:
		_pause_overlay.visible = show
		_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if show else Control.MOUSE_FILTER_IGNORE
	_refresh_touch_target_diagnostics()
	if show:
		call_deferred("_refresh_touch_target_diagnostics")


func _create_pause_overlay() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.color = Color(0, 0, 0, 0.6)
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_overlay.z_index = 100

	var vbox := VBoxContainer.new()
	vbox.name = "PauseMenu"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(250, 220)
	vbox.position = Vector2(-125, -110)
	vbox.add_theme_constant_override("separation", 12)
	vbox.process_mode = Node.PROCESS_MODE_ALWAYS

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var resume_btn := Button.new()
	resume_btn.name = "ResumeButton"
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(200, 56)
	resume_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resume_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	resume_btn.pressed.connect(func() -> void:
		resume_requested.emit()
	)
	vbox.add_child(resume_btn)

	var pause_help := Label.new()
	pause_help.name = "PauseHelpLabel"
	pause_help.text = "Touch Resume to continue the match."
	pause_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_help.add_theme_font_size_override("font_size", 13)
	pause_help.add_theme_color_override("font_color", Color(0.92, 0.88, 0.74))
	vbox.add_child(pause_help)

	var quit_btn := Button.new()
	quit_btn.name = "QuitButton"
	quit_btn.text = "Quit to Main Menu"
	quit_btn.custom_minimum_size = Vector2(200, 56)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	quit_btn.pressed.connect(func() -> void:
		quit_to_menu_requested.emit()
	)
	vbox.add_child(quit_btn)

	_pause_overlay.add_child(vbox)
	get_node("Root").add_child(_pause_overlay)
	_refresh_touch_target_diagnostics()
	call_deferred("_refresh_touch_target_diagnostics")


func _set_gameplay_ui_interactable(interactable: bool) -> void:
	var allow_mouse: int = Control.MOUSE_FILTER_STOP if interactable else Control.MOUSE_FILTER_IGNORE
	selection_panel.mouse_filter = allow_mouse
	minimap_bg.mouse_filter = allow_mouse
	minimap_rect.mouse_filter = allow_mouse
	if _speed_button:
		_speed_button.disabled = not interactable
	age_up_button.disabled = not interactable
	build_menu_button.disabled = not interactable
	if _idle_villager_button:
		_idle_villager_button.disabled = not interactable or _last_idle_villager_count <= 0
	if _select_military_button:
		_select_military_button.disabled = not interactable or _last_military_count <= 0
	if _find_army_button:
		_find_army_button.disabled = not interactable or _last_military_count <= 0
	if _placement_cancel_button:
		_placement_cancel_button.disabled = not interactable
	if _train_buttons_container:
		_train_buttons_container.mouse_filter = allow_mouse
		for child in _train_buttons_container.get_children():
			if child is BaseButton:
				(child as BaseButton).disabled = not interactable
	if _research_container:
		_research_container.mouse_filter = allow_mouse
		for child in _research_container.get_children():
			if child is BaseButton:
				(child as BaseButton).disabled = not interactable
	for child in queue_container.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = not interactable


func set_ui_modal_state(state: int) -> void:
	var clamped_state: UIModalState = UIModalState.NONE
	if state >= UIModalState.NONE and state <= UIModalState.AGE_UP:
		clamped_state = state
	if clamped_state == _ui_modal_state:
		return
	_ui_modal_state = clamped_state
	var paused: bool = _ui_modal_state == UIModalState.PAUSE_MENU
	if paused and _build_menu_open:
		_build_menu_open = false
		build_menu_button.text = "Build"
		build_menu_toggled.emit(false)
	if _pause_button:
		_pause_button.text = ">" if paused else "||"
	_toggle_pause_overlay(paused)
	_set_gameplay_ui_interactable(not paused)
	if not paused:
		_update_age_display()
		update_idle_villager_count(_last_idle_villager_count)
		update_military_count(_last_military_count)

	if _ui_modal_state == UIModalState.BUILD_MENU:
		queue_container.visible = false
		if _train_buttons_container:
			_train_buttons_container.visible = false
		if _research_container:
			_research_container.visible = false
	elif _selected_building_ref and is_instance_valid(_selected_building_ref):
		_update_queue_display(_last_queue_items)
		var trainable: Array = []
		if _selected_building_ref.has_method("get_trainable_units"):
			trainable = _selected_building_ref.get_trainable_units()
		elif _selected_building_ref is BuildingBase:
			var building_ref: BuildingBase = _selected_building_ref as BuildingBase
			var stats: Dictionary = BuildingData.BUILDINGS.get(building_ref.building_type, {})
			if building_ref.state == BuildingBase.State.ACTIVE:
				trainable = stats.get("can_train", [])
		_update_train_buttons(trainable)
		_update_research_buttons(_selected_building_ref)
	_refresh_touch_target_diagnostics()


# --- Idle villager button ---

func _ensure_mobile_action_strip() -> void:
	if _mobile_action_strip != null:
		return

	var root_ctrl: Control = $Root
	_mobile_action_panel = PanelContainer.new()
	_mobile_action_panel.name = "MobileActionPanel"
	_mobile_action_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_mobile_action_panel.offset_left = -300
	_mobile_action_panel.offset_right = 300
	_mobile_action_panel.offset_top = -74
	_mobile_action_panel.offset_bottom = -8
	_mobile_action_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mobile_action_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_action_panel.add_child(margin)

	_mobile_action_strip = GridContainer.new()
	_mobile_action_strip.name = "MobileActionStrip"
	_mobile_action_strip.columns = 4
	_mobile_action_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_action_strip.add_theme_constant_override("h_separation", int(MOBILE_ACTION_GAP))
	_mobile_action_strip.add_theme_constant_override("v_separation", int(MOBILE_ACTION_GAP))
	_mobile_action_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_mobile_action_strip)

	_placement_cancel_button = Button.new()
	_placement_cancel_button.name = "PlacementCancelButton"
	_placement_cancel_button.text = "Cancel Build"
	_placement_cancel_button.custom_minimum_size = Vector2(170, MOBILE_ACTION_BUTTON_HEIGHT)
	_placement_cancel_button.tooltip_text = "Cancel current building placement [Esc]"
	_placement_cancel_button.pressed.connect(func(): placement_cancel_requested.emit())
	_placement_cancel_button.visible = false
	_mobile_action_strip.add_child(_placement_cancel_button)

	root_ctrl.add_child(_mobile_action_panel)


func _create_idle_villager_button() -> void:
	_ensure_mobile_action_strip()

	_idle_villager_button = Button.new()
	_idle_villager_button.name = "IdleVillagerButton"
	_idle_villager_button.text = "Idle: 0 [.]"
	_idle_villager_button.custom_minimum_size = Vector2(170, MOBILE_ACTION_BUTTON_HEIGHT)
	_idle_villager_button.pressed.connect(_on_idle_villager_pressed)
	_idle_villager_button.tooltip_text = "Cycle idle villagers [.]"
	_idle_villager_button.disabled = true
	_mobile_action_strip.add_child(_idle_villager_button)

	# Villager task breakdown — use HBox with colored labels per resource
	var bottom_right: VBoxContainer = %BottomRight
	_villager_task_hbox = HBoxContainer.new()
	_villager_task_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_villager_task_hbox.add_theme_constant_override("separation", 6)
	bottom_right.add_child(_villager_task_hbox)
	bottom_right.move_child(_villager_task_hbox, 0)


func _on_idle_villager_pressed() -> void:
	idle_villager_pressed.emit()


func _emit_select_all_military_pressed() -> void:
	select_all_military_pressed.emit()


func _emit_find_army_pressed() -> void:
	find_army_pressed.emit()


func _create_military_buttons() -> void:
	_ensure_mobile_action_strip()

	_select_military_button = Button.new()
	_select_military_button.name = "SelectMilitaryButton"
	_select_military_button.text = "Military: 0 [M]"
	_select_military_button.custom_minimum_size = Vector2(170, MOBILE_ACTION_BUTTON_HEIGHT)
	_select_military_button.pressed.connect(_emit_select_all_military_pressed)
	_select_military_button.tooltip_text = "Select all military units [M]"
	_select_military_button.disabled = true
	_mobile_action_strip.add_child(_select_military_button)

	_find_army_button = Button.new()
	_find_army_button.name = "FindArmyButton"
	_find_army_button.text = "Find Army: 0 [F]"
	_find_army_button.custom_minimum_size = Vector2(170, MOBILE_ACTION_BUTTON_HEIGHT)
	_find_army_button.pressed.connect(_emit_find_army_pressed)
	_find_army_button.tooltip_text = "Center camera on your army [F]"
	_find_army_button.disabled = true
	_mobile_action_strip.add_child(_find_army_button)


func update_idle_villager_count(count: int) -> void:
	_last_idle_villager_count = count
	var layout_changed: bool = false
	if _idle_villager_button:
		var was_visible: bool = _idle_villager_button.visible
		_idle_villager_button.visible = count > 0
		layout_changed = was_visible != _idle_villager_button.visible
		if _mobile_compact_labels:
			_idle_villager_button.text = "Idle %d" % count
		else:
			_idle_villager_button.text = "Idle: %d [.]" % count
		_idle_villager_button.disabled = count <= 0
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
	if layout_changed:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))
	_refresh_touch_target_diagnostics()


func set_placement_mode(active: bool, building_name: String = "") -> void:
	if _placement_cancel_button == null:
		return
	_placement_cancel_button.visible = active
	if active and building_name != "":
		_placement_cancel_button.text = "Cancel %s" % building_name
	else:
		_placement_cancel_button.text = "Cancel Build"
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))


func apply_mobile_layout(viewport_size: Vector2, safe_area: Rect2) -> void:
	if _mobile_action_panel == null:
		return

	var action_count: int = _count_visible_mobile_action_buttons()
	var metrics: Dictionary = _calculate_mobile_layout_metrics(viewport_size, safe_area, action_count)

	_mobile_action_panel.anchor_left = 0.0
	_mobile_action_panel.anchor_right = 1.0
	_mobile_action_panel.anchor_top = 1.0
	_mobile_action_panel.anchor_bottom = 1.0
	_mobile_action_panel.offset_left = metrics["action_left"]
	_mobile_action_panel.offset_right = metrics["action_right"]
	_mobile_action_panel.offset_bottom = metrics["action_bottom"]
	_mobile_action_panel.offset_top = metrics["action_top"]

	_mobile_action_strip.columns = metrics["action_columns"]
	var button_width: float = metrics["button_width"]
	for button in [_placement_cancel_button, _idle_villager_button, _select_military_button, _find_army_button]:
		if button:
			button.custom_minimum_size = Vector2(button_width, MOBILE_ACTION_BUTTON_HEIGHT)

	var compact_labels: bool = metrics["compact_labels"]
	if compact_labels != _mobile_compact_labels:
		_mobile_compact_labels = compact_labels
		update_idle_villager_count(_last_idle_villager_count)
		update_military_count(_last_military_count)

	_apply_top_bar_compact(metrics["top_bar_compact"])

	if minimap_bg:
		minimap_bg.offset_left = metrics["minimap_left"]
		minimap_bg.offset_bottom = metrics["minimap_bottom"]
		minimap_bg.offset_top = metrics["minimap_top"]
		minimap_bg.offset_right = metrics["minimap_right"]

	var bottom_right: Control = get_node_or_null("Root/BottomRight")
	if bottom_right:
		bottom_right.offset_left = metrics["bottom_right_left"]
		bottom_right.offset_right = metrics["bottom_right_right"]
		bottom_right.offset_bottom = metrics["bottom_right_bottom"]
		bottom_right.offset_top = metrics["bottom_right_top"]

	selection_panel.offset_left = -metrics["selection_width"] * 0.5
	selection_panel.offset_right = metrics["selection_width"] * 0.5
	selection_panel.offset_bottom = metrics["selection_bottom"]
	selection_panel.offset_top = metrics["selection_top"]
	selection_panel.custom_minimum_size = Vector2(metrics["selection_width"], metrics["selection_height"])
	var side_button_size := Vector2(metrics["side_button_width"], metrics["side_button_height"])
	age_up_button.custom_minimum_size = side_button_size
	build_menu_button.custom_minimum_size = side_button_size

	if _progression_hint_panel:
		_progression_hint_panel.offset_top = metrics["safe_top"] + 54.0
		_progression_hint_panel.offset_bottom = _progression_hint_panel.offset_top + 50.0

	mobile_layout_diagnostics = metrics
	_refresh_mobile_layout_profiles()
	_refresh_touch_target_diagnostics()


func _count_visible_mobile_action_buttons() -> int:
	var count: int = 0
	for button in [_placement_cancel_button, _idle_villager_button, _select_military_button, _find_army_button]:
		if button and button.visible:
			count += 1
	return maxi(count, 1)


func _calculate_mobile_layout_metrics(viewport_size: Vector2, safe_area: Rect2, action_button_count: int) -> Dictionary:
	var safe_pos: Vector2 = safe_area.position
	var safe_end: Vector2 = safe_area.position + safe_area.size
	var left_inset: float = maxf(0.0, safe_pos.x)
	var right_inset: float = maxf(0.0, viewport_size.x - safe_end.x)
	var bottom_inset: float = maxf(0.0, viewport_size.y - safe_end.y)
	var content_width: float = maxf(220.0, safe_area.size.x - MOBILE_ACTION_MARGIN * 2.0)

	var action_columns: int = 4
	if content_width < MOBILE_ACTION_DOUBLE_ROW_BREAKPOINT:
		action_columns = 2
	var action_rows: int = int(ceili(float(action_button_count) / float(action_columns)))
	var gap_total: float = MOBILE_ACTION_GAP * float(action_columns - 1)
	var raw_button_width: float = (content_width - MOBILE_ACTION_INNER_PADDING * 2.0 - gap_total) / float(action_columns)
	var button_width: float = clampf(raw_button_width, MOBILE_ACTION_MIN_BUTTON_WIDTH, MOBILE_ACTION_MAX_BUTTON_WIDTH)
	var action_height: float = 12.0 + MOBILE_ACTION_BUTTON_HEIGHT * float(action_rows) + MOBILE_ACTION_GAP * float(maxi(0, action_rows - 1))

	var action_left: float = left_inset + MOBILE_ACTION_MARGIN
	var action_right: float = -right_inset - MOBILE_ACTION_MARGIN
	var action_bottom: float = -bottom_inset - MOBILE_ACTION_MARGIN
	var action_top: float = action_bottom - action_height

	var short_side: float = minf(safe_area.size.x, safe_area.size.y)
	var minimap_size: float = clampf(
		minf(safe_area.size.y * MOBILE_MINIMAP_SHORT_SIDE_RATIO, safe_area.size.x * 0.28),
		MOBILE_MINIMAP_MIN_SIZE,
		MOBILE_MINIMAP_MAX_SIZE
	)
	var minimap_left: float = left_inset + MOBILE_ACTION_MARGIN
	var minimap_bottom: float = action_top - 10.0
	var minimap_top: float = minimap_bottom - minimap_size
	var minimap_right: float = minimap_left + minimap_size

	var bottom_right_bottom: float = action_top - 8.0
	var bottom_right_right: float = -MOBILE_ACTION_MARGIN - right_inset
	var bottom_right_top: float = bottom_right_bottom - 124.0
	var bottom_right_left: float = bottom_right_right - 164.0

	var selection_width: float = clampf(safe_area.size.x * 0.48, 320.0, 460.0)
	var selection_height: float = _selection_panel_target_height()
	var selection_bottom: float = action_top - 8.0
	var selection_top: float = selection_bottom - selection_height
	var selection_left: float = viewport_size.x * 0.5 - selection_width * 0.5
	var selection_right: float = selection_left + selection_width

	var top_bar_compact: bool = short_side <= MOBILE_TOP_BAR_COMPACT_SHORT_SIDE or safe_area.size.x <= MOBILE_TOP_BAR_COMPACT_WIDTH
	var compact_labels: bool = content_width < 640.0 or top_bar_compact
	var side_button_width: float = clampf(safe_area.size.x * 0.18, 132.0, 168.0)
	var side_button_height: float = 56.0

	var action_rect := Rect2(
		Vector2(action_left, viewport_size.y + action_top),
		Vector2(viewport_size.x + action_right - action_left, action_height)
	)
	var minimap_rect_calc := Rect2(
		Vector2(minimap_left, viewport_size.y + minimap_top),
		Vector2(minimap_right - minimap_left, minimap_bottom - minimap_top)
	)
	var selection_rect := Rect2(
		Vector2(selection_left, viewport_size.y + selection_top),
		Vector2(selection_right - selection_left, selection_height)
	)
	var bottom_right_rect := Rect2(
		Vector2(viewport_size.x + bottom_right_left, viewport_size.y + bottom_right_top),
		Vector2((viewport_size.x + bottom_right_right) - (viewport_size.x + bottom_right_left), bottom_right_bottom - bottom_right_top)
	)

	var minimap_action_overlap: bool = minimap_rect_calc.intersects(action_rect, true)
	var selection_action_overlap: bool = selection_rect.intersects(action_rect, true)
	var bottom_right_action_overlap: bool = bottom_right_rect.intersects(action_rect, true)

	return {
		"viewport_width": viewport_size.x,
		"viewport_height": viewport_size.y,
		"safe_top": safe_pos.y,
		"safe_left": safe_pos.x,
		"safe_width": safe_area.size.x,
		"safe_height": safe_area.size.y,
		"action_columns": action_columns,
		"action_rows": action_rows,
		"button_width": button_width,
		"button_height": MOBILE_ACTION_BUTTON_HEIGHT,
		"action_left": action_left,
		"action_right": action_right,
		"action_top": action_top,
		"action_bottom": action_bottom,
		"minimap_left": minimap_left,
		"minimap_top": minimap_top,
		"minimap_right": minimap_right,
		"minimap_bottom": minimap_bottom,
		"selection_width": selection_width,
		"selection_height": selection_height,
		"selection_top": selection_top,
		"selection_bottom": selection_bottom,
		"side_button_width": side_button_width,
		"side_button_height": side_button_height,
		"bottom_right_top": bottom_right_top,
		"bottom_right_bottom": bottom_right_bottom,
		"bottom_right_left": bottom_right_left,
		"bottom_right_right": bottom_right_right,
		"compact_labels": compact_labels,
		"top_bar_compact": top_bar_compact,
		"minimap_action_overlap": minimap_action_overlap,
		"selection_action_overlap": selection_action_overlap,
		"bottom_right_action_overlap": bottom_right_action_overlap,
		"layout_pass": _layout_metrics_pass(button_width, minimap_action_overlap, selection_action_overlap, bottom_right_action_overlap),
	}


func _selection_panel_target_height() -> float:
	if _train_buttons_container != null and _train_buttons_container.visible:
		return 156.0
	return 112.0


func _layout_metrics_pass(button_width: float, minimap_action_overlap: bool, selection_action_overlap: bool, bottom_right_action_overlap: bool) -> bool:
	if button_width < MOBILE_ACTION_MIN_BUTTON_WIDTH:
		return false
	if MOBILE_ACTION_BUTTON_HEIGHT < 56.0:
		return false
	return not minimap_action_overlap and not selection_action_overlap and not bottom_right_action_overlap


func _refresh_mobile_layout_profiles() -> void:
	mobile_layout_profiles.clear()
	for key in PHONE_LAYOUT_KEYS:
		var parts: PackedStringArray = key.split("x")
		if parts.size() != 2:
			continue
		var width: float = float(parts[0].to_int())
		var height: float = float(parts[1].to_int())
		var profile_metrics: Dictionary = _calculate_mobile_layout_metrics(
			Vector2(width, height),
			Rect2(Vector2.ZERO, Vector2(width, height)),
			4
		)
		mobile_layout_profiles[key] = profile_metrics


func _control_screen_position(control: Control) -> Vector2:
	var screen_pos := Vector2.ZERO
	var current: Node = control
	while current != null and current != self:
		if current is Control:
			screen_pos += (current as Control).position
		current = current.get_parent()
	return screen_pos


func _control_touch_diag(control: Control, role: String = "") -> Dictionary:
	if control == null:
		return {}
	if control.is_queued_for_deletion():
		return {}
	var disabled: bool = false
	if control is BaseButton:
		disabled = (control as BaseButton).disabled
	var size: Vector2 = control.size
	var screen_pos: Vector2 = _control_screen_position(control)
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
		"x": screen_pos.x,
		"y": screen_pos.y,
		"min_width": control.custom_minimum_size.x,
		"min_height": control.custom_minimum_size.y,
	}


func _collect_button_diags(container: Control, role_prefix: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if container == null:
		return entries
	var index: int = 0
	for child in container.get_children():
		if child is Node and (child as Node).is_queued_for_deletion():
			continue
		if child is BaseButton:
			var entry: Dictionary = _control_touch_diag(child as Control, "%s_%d" % [role_prefix, index])
			if not entry.is_empty():
				entry["index"] = index
				entries.append(entry)
				index += 1
	return entries


func _refresh_touch_target_diagnostics() -> void:
	var diag: Dictionary = {}
	diag["timestamp_ms"] = Time.get_ticks_msec()
	diag["build_menu_open"] = _build_menu_open
	diag["ui_modal_state"] = _ui_modal_state
	diag["build_button"] = _control_touch_diag(build_menu_button, "build_button")
	diag["age_up_button"] = _control_touch_diag(age_up_button, "age_up_button")
	diag["pause_button"] = _control_touch_diag(_pause_button, "pause_button")
	diag["speed_button"] = _control_touch_diag(_speed_button, "speed_button")
	diag["mobile_action_panel"] = _control_touch_diag(_mobile_action_panel, "mobile_action_panel")
	diag["placement_cancel_button"] = _control_touch_diag(_placement_cancel_button, "placement_cancel_button")
	diag["mobile_action_buttons"] = _collect_button_diags(_mobile_action_strip, "mobile_action")
	diag["queue_cancel_buttons"] = _collect_button_diags(queue_container, "queue_cancel")
	diag["train_buttons"] = _collect_button_diags(_train_buttons_container, "train")
	diag["research_buttons"] = _collect_button_diags(_research_container, "research")
	diag["minimap_bg"] = _control_touch_diag(minimap_bg, "minimap_bg")
	diag["minimap_rect"] = _control_touch_diag(minimap_rect, "minimap_rect")
	if _pause_overlay != null:
		var pause_menu: Control = _pause_overlay.get_node_or_null("PauseMenu")
		diag["pause_menu"] = _control_touch_diag(pause_menu, "pause_menu")
		var resume_btn: Control = _pause_overlay.get_node_or_null("PauseMenu/ResumeButton")
		var quit_btn: Control = _pause_overlay.get_node_or_null("PauseMenu/QuitButton")
		diag["pause_menu_resume"] = _control_touch_diag(resume_btn, "pause_menu_resume")
		diag["pause_menu_quit"] = _control_touch_diag(quit_btn, "pause_menu_quit")
	touch_target_diagnostics = diag


func _apply_top_bar_compact(compact: bool) -> void:
	if compact == _top_bar_compact:
		return
	_top_bar_compact = compact
	top_bar.custom_minimum_size = Vector2(0, 44) if compact else Vector2(0, 50)
	top_bar_hbox.add_theme_constant_override("separation", 12 if compact else 20)
	if _resource_node_legend:
		_resource_node_legend.visible = not compact
	var font_size: int = 16 if compact else 17
	for label in [food_label, wood_label, gold_label, pop_label, age_label, game_time_label]:
		label.add_theme_font_size_override("font_size", font_size)
	pop_label.add_theme_color_override("font_color", Color(0.97, 0.95, 0.9))
	age_label.add_theme_color_override("font_color", Color(0.97, 0.95, 0.9))
	game_time_label.add_theme_color_override("font_color", Color(0.97, 0.95, 0.9))
	_update_resource_display(_resource_values)
	update_population(_population_current, _population_cap)


func set_primary_action(text: String, focus_target: String = "", unit_type: int = -1, building_type: int = -1, emphasis: bool = true) -> void:
	_primary_action_focus = focus_target
	_primary_action_unit_type = unit_type
	_primary_action_building_type = building_type
	set_progression_hint(text, emphasis)
	_refresh_primary_action_visuals()


func clear_primary_action() -> void:
	_primary_action_focus = ""
	_primary_action_unit_type = -1
	_primary_action_building_type = -1
	_refresh_primary_action_visuals()


func set_early_game_ui_state(active: bool) -> void:
	_early_game_ui_active = active
	age_up_button.visible = not active
	if _score_label:
		_score_label.visible = not active
	if _speed_button:
		_speed_button.modulate = Color(0.72, 0.72, 0.72, 0.8) if active else Color.WHITE
	update_idle_villager_count(_last_idle_villager_count)
	update_military_count(_last_military_count)
	_refresh_primary_action_visuals()
	_refresh_touch_target_diagnostics()


func set_guided_military_shortcuts_visible(visible: bool) -> void:
	_guided_military_shortcuts_visible = visible
	update_military_count(_last_military_count)
	_refresh_primary_action_visuals()
	_refresh_touch_target_diagnostics()


func set_pending_military_shortcut(pending: bool) -> void:
	_pending_military_shortcut = pending
	update_military_count(_last_military_count)
	_refresh_primary_action_visuals()
	_refresh_touch_target_diagnostics()


func set_progression_hint(text: String, emphasis: bool = false) -> void:
	if _progression_hint_label == null or _progression_hint_panel == null:
		return
	var trimmed: String = text.strip_edges()
	_progression_hint_panel.visible = trimmed != ""
	if trimmed == "":
		return
	_progression_hint_label.text = trimmed
	var color: Color = Color(0.95, 0.92, 0.82)
	if emphasis:
		color = Color(1.0, 0.9, 0.45)
	_progression_hint_label.add_theme_color_override("font_color", color)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.04, 0.88) if emphasis else Color(0.08, 0.06, 0.04, 0.78)
	style.border_color = Color(0.95, 0.78, 0.34, 0.98) if emphasis else Color(0.64, 0.52, 0.28, 0.85)
	style.set_border_width_all(2 if emphasis else 1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_progression_hint_panel.add_theme_stylebox_override("panel", style)


func set_minimap_hint(text: String) -> void:
	if _minimap_hint_label == null:
		return
	_minimap_hint_label.text = text
	_minimap_hint_label.visible = text.strip_edges() != ""


func _refresh_primary_action_visuals() -> void:
	var pulse: float = 0.88 + 0.12 * (0.5 + 0.5 * sin(_focus_pulse_time * 4.0))
	build_menu_button.modulate = Color.WHITE
	age_up_button.modulate = Color.WHITE
	if _pause_button:
		_pause_button.modulate = Color.WHITE
	if _idle_villager_button:
		_idle_villager_button.modulate = Color.WHITE
	if _select_military_button:
		_select_military_button.modulate = Color.WHITE
	if _find_army_button:
		_find_army_button.modulate = Color.WHITE
	if _placement_cancel_button:
		_placement_cancel_button.modulate = Color.WHITE
	if _minimap_hint_label:
		_minimap_hint_label.modulate = Color(1.0, 1.0, 1.0, 0.82 + 0.18 * sin(_focus_pulse_time * 4.0))
	minimap_bg.color = Color(0.05, 0.07, 0.1, 0.92)

	if _primary_action_focus == "build_button":
		build_menu_button.modulate = Color(1.0, pulse, 0.62, 1.0)
	elif _primary_action_focus == "age_button":
		age_up_button.modulate = Color(1.0, pulse, 0.62, 1.0)
	elif _primary_action_focus == "pause_button" and _pause_button:
		_pause_button.modulate = Color(1.0, pulse, 0.62, 1.0)
	elif _primary_action_focus == "idle_button" and _idle_villager_button:
		_idle_villager_button.modulate = Color(1.0, pulse, 0.62, 1.0)
	elif _primary_action_focus == "military_button":
		if _select_military_button:
			_select_military_button.modulate = Color(1.0, pulse, 0.62, 1.0)
		if _find_army_button:
			_find_army_button.modulate = Color(1.0, pulse, 0.62, 1.0)
	elif _primary_action_focus == "placement_cancel" and _placement_cancel_button:
		_placement_cancel_button.modulate = Color(1.0, pulse, 0.62, 1.0)
	elif _primary_action_focus == "minimap":
		minimap_bg.color = Color(0.18, 0.15, 0.08, 0.96)

	if _train_buttons_container:
		for child in _train_buttons_container.get_children():
			if child is BaseButton:
				var btn: BaseButton = child as BaseButton
				btn.modulate = Color.WHITE
				if _primary_action_focus == "train_unit" and int(btn.get_meta("unit_type", -1)) == _primary_action_unit_type:
					btn.modulate = Color(1.0, pulse, 0.62, 1.0)


# --- Build menu ---

func is_build_menu_open() -> bool:
	return _build_menu_open


func is_placement_cancel_visible() -> bool:
	return _placement_cancel_button != null and _placement_cancel_button.is_visible_in_tree()


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
	_resource_values = resources.duplicate(true)
	var food: int = int(resources.get("food", 0))
	var wood: int = int(resources.get("wood", 0))
	var gold: int = int(resources.get("gold", 0))
	if _top_bar_compact:
		food_label.text = "F:%d" % food
		wood_label.text = "W:%d" % wood
		gold_label.text = "G:%d" % gold
	else:
		food_label.text = "Food: %d" % food
		wood_label.text = "Wood: %d" % wood
		gold_label.text = "Gold: %d" % gold


func update_population(current: int, cap: int) -> void:
	_population_current = current
	_population_cap = cap
	if _top_bar_compact:
		pop_label.text = "P:%d/%d" % [current, cap]
	else:
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
		if _early_game_ui_active:
			age_up_button.visible = false
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


func _on_game_state_changed(new_state: int) -> void:
	var gm: Node = _get_game_manager()
	if gm and new_state == gm.GameState.PAUSED:
		set_ui_modal_state(UIModalState.PAUSE_MENU)
	elif _ui_modal_state == UIModalState.PAUSE_MENU:
		set_ui_modal_state(UIModalState.NONE)


# --- Selection panel ---

func show_unit_selection(unit_name: String, current_hp: int, max_hp: int, action_text: String, count: int = 1, unit_stats: Dictionary = {}) -> void:
	if _ui_modal_state == UIModalState.PAUSE_MENU:
		return
	selection_panel.visible = true
	if count > 1:
		selection_name.text = "%dx %s" % [count, unit_name]
	else:
		selection_name.text = unit_name
	selection_hp_bar.max_value = max_hp
	selection_hp_bar.value = current_hp
	_update_hp_bar_color(current_hp, max_hp)
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
		if unit_stats.has("stance"):
			parts.append("[%s]" % unit_stats["stance"])
		if parts.size() > 0:
			stats_line = " | ".join(parts) + "\n"
	selection_details.text = stats_line + action_text
	queue_container.visible = false
	_last_queue_items = []
	_queue_counts_by_unit.clear()
	_selected_building_ref = null
	if _train_buttons_container:
		_train_buttons_container.visible = false
	if _research_container:
		_research_container.visible = false


func show_building_selection(building_name: String, current_hp: int, max_hp: int, queue_items: Array, trainable_units: Array = [], building_ref: Node2D = null) -> void:
	if _ui_modal_state == UIModalState.PAUSE_MENU:
		return
	selection_panel.visible = true
	selection_name.text = building_name
	selection_hp_bar.max_value = max_hp
	selection_hp_bar.value = current_hp
	_update_hp_bar_color(current_hp, max_hp)
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
	_last_queue_items = queue_items.duplicate(true)
	_update_queue_display(queue_items)
	_update_train_buttons(trainable_units)
	_update_research_buttons(building_ref)


func show_resource_info(type_name: String, remaining: int, total: int, pct: int) -> void:
	if _ui_modal_state == UIModalState.PAUSE_MENU:
		return
	selection_panel.visible = true
	selection_name.text = "%s Resource" % type_name
	selection_hp_bar.max_value = total
	selection_hp_bar.value = remaining
	_update_hp_bar_color(remaining, total)
	selection_details.text = "%d / %d remaining (%d%%)" % [remaining, total, pct]
	queue_container.visible = false
	_last_queue_items = []
	_queue_counts_by_unit.clear()
	_selected_building_ref = null
	if _train_buttons_container:
		_train_buttons_container.visible = false
	if _research_container:
		_research_container.visible = false


func _update_hp_bar_color(current: int, maximum: int) -> void:
	if maximum <= 0:
		return
	var pct: float = float(current) / float(maximum)
	var fill_style: StyleBoxFlat = selection_hp_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	if pct > 0.6:
		fill_style.bg_color = Color(0.35, 0.70, 0.25, 0.9)  # Green
	elif pct > 0.3:
		fill_style.bg_color = Color(0.85, 0.70, 0.15, 0.9)  # Yellow
	else:
		fill_style.bg_color = Color(0.85, 0.20, 0.15, 0.9)  # Red
	selection_hp_bar.add_theme_stylebox_override("fill", fill_style)


func clear_selection() -> void:
	selection_panel.visible = false
	_selected_building_ref = null
	_last_queue_items = []
	_queue_counts_by_unit.clear()
	if _train_buttons_container:
		_train_buttons_container.visible = false
	if _research_container:
		_research_container.visible = false


func _update_queue_display(queue_items: Array) -> void:
	_last_queue_items = queue_items.duplicate(true)
	_queue_counts_by_unit.clear()
	# Clear existing queue chips/buttons.
	for child in queue_container.get_children():
		child.queue_free()

	if queue_items.is_empty():
		queue_container.visible = false
		_refresh_touch_target_diagnostics()
		return

	queue_container.visible = true
	var unit_to_first_index: Dictionary = {}
	var training_label: String = ""
	for i in range(queue_items.size()):
		var item = queue_items[i]
		if not (item is Dictionary):
			continue
		var unit_type: int = int(item.get("unit_type", -1))
		var name_str: String = String(item.get("name", UnitData.get_unit_name(unit_type)))
		if bool(item.get("is_training", false)):
			var progress: float = float(item.get("progress", 0.0))
			var pct: int = int(progress * 100.0)
			var train_time: float = UnitData.UNITS.get(unit_type, {}).get("build_time", 15.0)
			var remaining: float = maxf(0.0, train_time * (1.0 - progress))
			training_label = "%s %d%%  %ds" % [name_str, pct, int(remaining)]
		else:
			var prev_count: int = int(_queue_counts_by_unit.get(unit_type, 0))
			_queue_counts_by_unit[unit_type] = prev_count + 1
			if not unit_to_first_index.has(unit_type):
				unit_to_first_index[unit_type] = i

	if training_label != "":
		var training_chip := Label.new()
		training_chip.text = "Training: %s" % training_label
		training_chip.add_theme_font_size_override("font_size", 14)
		training_chip.add_theme_color_override("font_color", Color(0.95, 0.88, 0.66))
		training_chip.custom_minimum_size = Vector2(180, 0)
		queue_container.add_child(training_chip)

	var queue_units: Array = _queue_counts_by_unit.keys()
	queue_units.sort()
	for unit_type in queue_units:
		var queue_count: int = int(_queue_counts_by_unit.get(unit_type, 0))
		if queue_count <= 0:
			continue
		var btn := Button.new()
		btn.name = "QueueUnit_%s" % str(unit_type)
		btn.text = "%s x%d" % [UnitData.get_unit_name(unit_type), queue_count]
		btn.tooltip_text = "Cancel first queued %s" % UnitData.get_unit_name(unit_type)
		btn.custom_minimum_size = Vector2(120, 38)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_cancel_queue_pressed.bind(int(unit_to_first_index.get(unit_type, 0))))
		queue_container.add_child(btn)

	var clear_last := Button.new()
	clear_last.name = "QueueClearLastButton"
	clear_last.text = "Undo"
	clear_last.tooltip_text = "Cancel last queued unit"
	clear_last.custom_minimum_size = Vector2(76, 38)
	clear_last.pressed.connect(_on_clear_last_queue_pressed)
	queue_container.add_child(clear_last)

	var clear_all := Button.new()
	clear_all.name = "QueueClearAllButton"
	clear_all.text = "Clear"
	clear_all.tooltip_text = "Cancel all queued units"
	clear_all.custom_minimum_size = Vector2(76, 38)
	clear_all.pressed.connect(_on_clear_all_queue_pressed)
	queue_container.add_child(clear_all)

	if _ui_modal_state == UIModalState.BUILD_MENU:
		queue_container.visible = false
	_refresh_touch_target_diagnostics()


func _on_cancel_queue_pressed(index: int) -> void:
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		cancel_queue_requested.emit(_selected_building_ref, index)


func _on_clear_last_queue_pressed() -> void:
	if _last_queue_items.is_empty():
		return
	_on_cancel_queue_pressed(_last_queue_items.size() - 1)


func _on_clear_all_queue_pressed() -> void:
	if _last_queue_items.is_empty():
		return
	for i in range(_last_queue_items.size() - 1, -1, -1):
		_on_cancel_queue_pressed(i)


func _update_train_buttons(trainable_units: Array) -> void:
	# Create container on first use
	if _train_buttons_container == null:
		_train_buttons_container = HBoxContainer.new()
		_train_buttons_container.name = "TrainButtons"
		_train_buttons_container.add_theme_constant_override("separation", 8)
		# Add it after queue_container in the selection panel's VBox
		var parent_vbox: Control = queue_container.get_parent()
		if parent_vbox:
			parent_vbox.add_child(_train_buttons_container)

	# Clear old buttons
	for child in _train_buttons_container.get_children():
		child.free()

	if trainable_units.is_empty():
		_train_buttons_container.visible = false
		var viewport_size_empty: Vector2 = get_viewport().get_visible_rect().size
		apply_mobile_layout(viewport_size_empty, _get_safe_area_rect(viewport_size_empty))
		_refresh_touch_target_diagnostics()
		return

	_train_buttons_container.visible = true
	for ut in trainable_units:
		var unit_name: String = UnitData.get_unit_name(ut)
		var cost: Dictionary = UnitData.get_unit_cost(ut)
		var stats: Dictionary = UnitData.UNITS.get(ut, {})
		var train_time: float = stats.get("build_time", 15.0)
		var cost_str := ""
		if cost.get("food", 0) > 0:
			cost_str += "F%d " % cost["food"]
		if cost.get("wood", 0) > 0:
			cost_str += "W%d " % cost["wood"]
		if cost.get("gold", 0) > 0:
			cost_str += "G%d " % cost["gold"]
		var queue_badge: String = ""
		var queue_count: int = int(_queue_counts_by_unit.get(ut, 0))
		if queue_count > 0:
			queue_badge = " x%d" % queue_count
		var btn := Button.new()
		btn.name = "TrainButton_%s" % str(ut)
		btn.set_meta("unit_type", int(ut))
		btn.text = "%s%s\n%s  %ds" % [unit_name, queue_badge, cost_str.strip_edges(), int(train_time)]
		btn.custom_minimum_size = Vector2(132, 62)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 13)
		var icon_path: String = UnitData.get_unit_icon_path(ut)
		if icon_path != "" and ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
			btn.expand_icon = false
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_constant_override("icon_max_width", 26)
		# Build detailed tooltip with unit stats
		var tip_lines: PackedStringArray = PackedStringArray()
		tip_lines.append("%s (tap to train)" % unit_name)
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
			_auto_queue_button.name = "AutoQueueButton"
			_auto_queue_button.text = "Auto Queue"
			_auto_queue_button.custom_minimum_size = Vector2(108, 50)
			_auto_queue_button.button_pressed = pq.auto_queue_enabled
			_auto_queue_button.toggled.connect(_on_auto_queue_toggled)
			_train_buttons_container.add_child(_auto_queue_button)
	if _ui_modal_state == UIModalState.BUILD_MENU:
		_train_buttons_container.visible = false
	_refresh_primary_action_visuals()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))
	call_deferred("_refresh_touch_target_diagnostics")


func _on_train_button_pressed(unit_type: int) -> void:
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		train_unit_requested.emit(_selected_building_ref, unit_type)


func _on_auto_queue_toggled(pressed: bool) -> void:
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		var pq: Node = _selected_building_ref.get_production_queue() if _selected_building_ref.has_method("get_production_queue") else null
		if pq:
			pq.auto_queue_enabled = pressed
			var building_name: String = "Production"
			if _selected_building_ref is BuildingBase:
				building_name = (_selected_building_ref as BuildingBase).building_name
			show_notification(
				"%s auto-queue %s" % [building_name, "enabled" if pressed else "disabled"],
				Color(0.55, 0.82, 1.0)
			)


# --- Research buttons (Blacksmith) ---

const RESEARCH_DEFS: Array = [
	{"id": "forging", "name": "Forge Weapons", "desc": "+2 Attack", "cost": {"food": 100, "gold": 50}},
	{"id": "scale_mail", "name": "Scale Mail", "desc": "+1 Armor", "cost": {"food": 100, "gold": 50}},
	{"id": "wheelbarrow", "name": "Wheelbarrow", "desc": "+25% Gather", "cost": {"food": 175, "wood": 50}},
	{"id": "loom", "name": "Loom", "desc": "+15 Villager HP", "cost": {"gold": 50}},
]


func _update_research_buttons(building_ref: Node2D) -> void:
	# Create container on first use
	if _research_container == null:
		_research_container = VBoxContainer.new()
		_research_container.name = "ResearchButtons"
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
		_refresh_touch_target_diagnostics()
		return
	if not (building_ref is BuildingBase):
		_research_container.visible = false
		_refresh_touch_target_diagnostics()
		return
	var b: BuildingBase = building_ref as BuildingBase
	if b.building_type != BuildingData.BuildingType.BLACKSMITH or b.state != BuildingBase.State.ACTIVE:
		_research_container.visible = false
		_refresh_touch_target_diagnostics()
		return

	_research_container.visible = true
	var gm: Node = _get_game_manager()

	for rd in RESEARCH_DEFS:
		var btn := Button.new()
		btn.name = "ResearchButton_%s" % str(rd["id"])
		var cost_str := ""
		if rd["cost"].get("food", 0) > 0:
			cost_str += "F:%d " % rd["cost"]["food"]
		if rd["cost"].get("wood", 0) > 0:
			cost_str += "W:%d " % rd["cost"]["wood"]
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
	_refresh_touch_target_diagnostics()


func _on_research_pressed(research_id: String) -> void:
	if _selected_building_ref and is_instance_valid(_selected_building_ref):
		research_requested.emit(_selected_building_ref, research_id)


# --- Build menu toggle ---

func _on_build_menu_pressed() -> void:
	if _ui_modal_state == UIModalState.PAUSE_MENU:
		return
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
					color = Color(0.09, 0.09, 0.1)
				elif fog_state == MapData.FogState.EXPLORED:
					color = color.darkened(0.35)
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
		var cam_color := Color(1.0, 0.95, 0.35, 1.0)
		var cam_shadow := Color(0.08, 0.08, 0.08, 0.85)
		# Draw top and bottom edges
		for tx in range(maxi(0, tl.x), mini(map_w, br.x + 1)):
			if tl.y >= 0 and tl.y < map_h:
				_minimap_image.set_pixel(tx, tl.y, cam_color)
				if tl.y + 1 < map_h:
					_minimap_image.set_pixel(tx, tl.y + 1, cam_shadow)
			if br.y >= 0 and br.y < map_h:
				_minimap_image.set_pixel(tx, br.y, cam_color)
				if br.y - 1 >= 0:
					_minimap_image.set_pixel(tx, br.y - 1, cam_shadow)
		# Draw left and right edges
		for ty in range(maxi(0, tl.y), mini(map_h, br.y + 1)):
			if tl.x >= 0 and tl.x < map_w:
				_minimap_image.set_pixel(tl.x, ty, cam_color)
				if tl.x + 1 < map_w:
					_minimap_image.set_pixel(tl.x + 1, ty, cam_shadow)
			if br.x >= 0 and br.x < map_w:
				_minimap_image.set_pixel(br.x, ty, cam_color)
				if br.x - 1 >= 0:
					_minimap_image.set_pixel(br.x - 1, ty, cam_shadow)

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
	var handled: bool = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_minimap_click(event.position)
		handled = true
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_handle_minimap_click(event.position)
		handled = true
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_minimap_touch_index = touch.index
			_handle_minimap_click(_screen_to_minimap_local(touch.position))
			handled = true
		elif touch.index == _minimap_touch_index:
			_minimap_touch_index = -1
			handled = true
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _minimap_touch_index:
			_handle_minimap_click(_screen_to_minimap_local(drag.position))
			handled = true
	if handled:
		get_viewport().set_input_as_handled()


func _screen_to_minimap_local(screen_pos: Vector2) -> Vector2:
	var xform: Transform2D = minimap_rect.get_global_transform_with_canvas().affine_inverse()
	var local_from_global: Vector2 = xform * screen_pos
	if local_from_global.x >= 0.0 and local_from_global.y >= 0.0 and local_from_global.x <= minimap_rect.size.x and local_from_global.y <= minimap_rect.size.y:
		return local_from_global
	if screen_pos.x >= 0.0 and screen_pos.y >= 0.0 and screen_pos.x <= minimap_rect.size.x and screen_pos.y <= minimap_rect.size.y:
		return screen_pos
	return local_from_global


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
		["R", "Arm patrol command"],
		["G", "Toggle stance (Aggr/Stand)"],
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
	_score_label.offset_left = -280
	_score_label.offset_right = -170
	_score_label.offset_top = 8
	_score_label.offset_bottom = 28
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.add_theme_font_size_override("font_size", 13)
	_score_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	_score_label.text = "Score: 0"
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_score_label)


func _create_minimap_hint() -> void:
	if _minimap_hint_label != null:
		return
	_minimap_hint_label = Label.new()
	_minimap_hint_label.name = "MinimapHintLabel"
	_minimap_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_minimap_hint_label.offset_left = 8
	_minimap_hint_label.offset_right = -8
	_minimap_hint_label.offset_top = -28
	_minimap_hint_label.offset_bottom = -8
	_minimap_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_minimap_hint_label.add_theme_font_size_override("font_size", 12)
	_minimap_hint_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.8))
	_minimap_hint_label.text = ""
	_minimap_hint_label.visible = false
	_minimap_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_bg.add_child(_minimap_hint_label)


func _create_progression_hint() -> void:
	if _progression_hint_panel != null:
		return
	var root_ctrl: Control = $Root
	_progression_hint_panel = PanelContainer.new()
	_progression_hint_panel.name = "ProgressionHintPanel"
	_progression_hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_progression_hint_panel.offset_left = -270
	_progression_hint_panel.offset_right = 270
	_progression_hint_panel.offset_top = 54
	_progression_hint_panel.offset_bottom = 104
	_progression_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progression_hint_panel.visible = false

	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0.08, 0.06, 0.04, 0.78)
	hint_style.border_color = Color(0.64, 0.52, 0.28, 0.85)
	hint_style.set_border_width_all(1)
	hint_style.set_corner_radius_all(4)
	hint_style.set_content_margin_all(8)
	_progression_hint_panel.add_theme_stylebox_override("panel", hint_style)

	_progression_hint_label = Label.new()
	_progression_hint_label.name = "ProgressionHintLabel"
	_progression_hint_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_progression_hint_label.offset_left = 6
	_progression_hint_label.offset_top = 4
	_progression_hint_label.offset_right = -6
	_progression_hint_label.offset_bottom = -4
	_progression_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progression_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progression_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progression_hint_label.add_theme_font_size_override("font_size", 16)
	_progression_hint_label.add_theme_color_override("font_color", Color(0.93, 0.89, 0.75))
	_progression_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progression_hint_panel.add_child(_progression_hint_label)

	root_ctrl.add_child(_progression_hint_panel)


func update_score(score: int, enemy_score: int = 0) -> void:
	if _score_label:
		_score_label.text = "Score: %d / %d" % [score, enemy_score]


# --- Military Count ---

func update_military_count(count: int) -> void:
	_last_military_count = count
	var can_show_guided_shortcuts: bool = not _early_game_ui_active or _guided_military_shortcuts_visible
	var show_shortcuts: bool = can_show_guided_shortcuts and (count > 0 or _pending_military_shortcut)
	var layout_changed: bool = false
	if _select_military_button:
		var was_visible: bool = _select_military_button.visible
		_select_military_button.visible = show_shortcuts
		layout_changed = layout_changed or was_visible != _select_military_button.visible
		if _mobile_compact_labels:
			_select_military_button.text = "Army %d" % count if count > 0 else "Army"
		else:
			_select_military_button.text = "Military: %d [M]" % count if count > 0 else "Military [M]"
		_select_military_button.disabled = not (count > 0 or _pending_military_shortcut)
	if _find_army_button:
		var was_find_visible: bool = _find_army_button.visible
		_find_army_button.visible = show_shortcuts and count > 0
		layout_changed = layout_changed or was_find_visible != _find_army_button.visible
		if _mobile_compact_labels:
			_find_army_button.text = "Find %d" % count
		else:
			_find_army_button.text = "Find Army: %d [F]" % count
		_find_army_button.disabled = count <= 0
	if layout_changed:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))
	_refresh_touch_target_diagnostics()


func update_villager_tasks(food: int, wood: int, gold: int, building: int) -> void:
	if _villager_task_hbox == null:
		return
	# Clear existing labels
	for child in _villager_task_hbox.get_children():
		child.queue_free()
	# Create colored label for each task type
	var entries: Array = [
		["F:%d" % food, Color(0.95, 0.40, 0.30), food],
		["W:%d" % wood, Color(0.50, 0.78, 0.35), wood],
		["G:%d" % gold, Color(0.98, 0.88, 0.25), gold],
		["B:%d" % building, Color(0.70, 0.70, 0.85), building],
	]
	for entry in entries:
		if entry[2] > 0:
			var lbl := Label.new()
			lbl.text = entry[0]
			lbl.add_theme_font_size_override("font_size", 13)
			lbl.add_theme_color_override("font_color", entry[1])
			_villager_task_hbox.add_child(lbl)


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
