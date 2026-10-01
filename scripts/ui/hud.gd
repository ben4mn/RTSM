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
signal town_center_pressed()
signal camera_zoom_requested(direction: int)
signal camera_zoom_reset_requested()
signal unit_move_requested()
signal unit_attack_move_requested()
signal unit_patrol_requested()
signal unit_stop_requested()
signal unit_stance_requested()
signal deselect_requested()
signal research_requested(building: Node2D, research_id: String)
signal placement_cancel_requested()
signal placement_confirm_requested()
signal pause_requested()
signal resume_requested()
signal quit_to_menu_requested()
signal guidance_dismissed()

const RESOURCE_COLORS: Dictionary = {
	"food": Color(0.9, 0.35, 0.25),
	"wood": Color(0.45, 0.7, 0.3),
	"gold": Color(0.95, 0.85, 0.2),
}

const GAME_SPEEDS: Array[float] = [0.5, 1.0, 2.0, 3.0]
const SPEED_LABELS: Array[String] = ["0.5x", "1x", "2x", "3x"]
const MOBILE_ACTION_BUTTON_HEIGHT := 48.0
const MOBILE_ACTION_MIN_BUTTON_WIDTH := 104.0
const MOBILE_ACTION_MAX_BUTTON_WIDTH := 116.0
const MOBILE_ACTION_GAP := 6.0
const MOBILE_ACTION_MARGIN := 8.0
const MOBILE_ACTION_INNER_PADDING := 4.0
const MOBILE_ACTION_VERTICAL_PADDING := 0.0
const MOBILE_MINIMAP_MIN_SIZE := 100.0
const MOBILE_MINIMAP_MAX_SIZE := 120.0
const MOBILE_MINIMAP_SHORT_SIDE_RATIO := 0.27
const MOBILE_TOP_BAR_COMPACT_SHORT_SIDE := 520.0
const MOBILE_TOP_BAR_COMPACT_WIDTH := 780.0
const MOBILE_SELECTION_COMMAND_WIDTH := 520.0
const MOBILE_SELECTION_HEIGHT := 72.0
const MOBILE_UNIT_COMMAND_WIDTH := 64.0
const MOBILE_GUIDANCE_WIDTH := 360.0
const MOBILE_GUIDANCE_HEIGHT := 54.0
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
@onready var selection_info_column: VBoxContainer = $Root/SelectionPanel/SelectionMargin/VBox/InfoColumn
@onready var queue_container: HBoxContainer = %QueueContainer
@onready var selection_separator: VSeparator = $Root/SelectionPanel/SelectionMargin/VBox/SelectionSeparator
@onready var command_scroll: ScrollContainer = $Root/SelectionPanel/SelectionMargin/VBox/CommandScroll

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
var _camera_controls: HBoxContainer = null
var _camera_view_button: Button = null
var _camera_controls_expanded: bool = false
var _selection_back_button: Button = null
var _selection_kind: String = "none"
var _selection_is_worker: bool = false
var _age_action_primary: bool = false
var _camera_zoom_in_button: Button = null
var _camera_zoom_out_button: Button = null
var _camera_zoom_reset_button: Button = null
var _camera_zoom_current: float = 1.0
var _camera_zoom_min: float = 0.5
var _camera_zoom_max: float = 2.5
var _match_population_label: Label = null
var _match_population_limit: int = 30
var _mobile_notification_limit: int = MAX_NOTIFICATIONS
var _game_speed_index: int = 1  # 0=0.5x, 1=1x, 2=2x

# Idle villager button
var _idle_villager_button: Button = null
var _villager_task_hbox: HBoxContainer = null

# Mobile action strip
var _mobile_action_panel: PanelContainer = null
var _mobile_action_strip: GridContainer = null
var _placement_cancel_button: Button = null
var _placement_confirm_button: Button = null
var _placement_status_panel: PanelContainer = null
var _placement_status_label: Label = null
var _placement_preview_valid: bool = false
var _placement_building_name: String = ""
var _mobile_compact_labels: bool = false
var _last_idle_villager_count: int = 0
var _last_military_count: int = 0
var _top_bar_compact: bool = false
var _resource_labels_abbreviated: bool = false
var _top_bar_safe_width: float = 844.0
var _selection_full_name: String = ""
var _selection_action_text: String = ""
var _selection_cargo_text: String = ""
var _selection_role_text: String = ""

# Train buttons
var _train_buttons_container: HBoxContainer = null
var _selected_building_ref: Node2D = null
var _auto_queue_button: Button = null
var _queue_page_spacer: Control = null
var _queue_hint_label: Label = null

# Notification feed
var _notification_container: VBoxContainer = null
const MAX_NOTIFICATIONS: int = 3
const NOTIFICATION_DURATION: float = 3.5
const MOBILE_NOTIFICATION_MAX_WIDTH := 224.0

# Military buttons
var _select_military_button: Button = null
var _find_army_button: Button = null
var _town_center_button: Button = null

# The everyday commands stay in the selection shelf. More opens advanced
# orders above it without turning every selection into a command dashboard.
var _unit_command_container: HBoxContainer = null
var _unit_move_button: Button = null
var _unit_attack_move_button: Button = null
var _unit_patrol_button: Button = null
var _unit_stop_button: Button = null
var _unit_stance_button: Button = null
var _unit_clear_button: Button = null
var _unit_more_button: Button = null
var _advanced_command_panel: PanelContainer = null
var _advanced_command_container: HBoxContainer = null
var _advanced_commands_open: bool = false
var _unit_commands_authorized: bool = false
var _unit_commands_have_military: bool = false
var _unit_command_mode: String = "smart"

# Idle villager flash tween
var _idle_flash_tween: Tween = null

# Research buttons
var _research_container: HBoxContainer = null

# Hotkey reference panel
var _hotkey_panel: PanelContainer = null

# Sacred site timer label
var _sacred_site_label: Label = null
var _sacred_site_panel: PanelContainer = null

# Score label
var _score_label: Label = null

# Pause menu overlay
var _pause_overlay: ColorRect = null
var _resource_node_legend: HBoxContainer = null
var _progression_hint_panel: PanelContainer = null
var _progression_hint_label: Label = null
var _guidance_dismiss_button: Button = null
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
var _next_touch_diagnostics_refresh_msec: int = 0
var _safe_area_diagnostics: Dictionary = {}
var _mobile_layout_refresh_queued: bool = false
var _placement_mode_active: bool = false
var _selection_context_active: bool = false
var _minimap_frame: Panel = null

# MCP-readable diagnostics for phone layout checks.
@export var mobile_layout_diagnostics: Dictionary = {}
@export var mobile_layout_profiles: Dictionary = {}
@export var touch_target_diagnostics: Dictionary = {}
@export var train_action_diagnostics: Dictionary = {}


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
	_create_camera_controls()
	_create_match_population_label()
	_ensure_mobile_action_strip()
	_create_idle_villager_button()
	_create_military_buttons()
	_create_unit_command_buttons()
	_create_notification_feed()
	_create_hotkey_panel()
	_create_sacred_site_label()
	_create_score_label()
	_create_progression_hint()
	_create_minimap_hint()
	_configure_mobile_visuals()

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
	minimap_bg.color = KingdomTheme.INK_PANEL
	var viewport: Viewport = get_viewport()
	if not viewport.size_changed.is_connected(_queue_mobile_layout_refresh):
		viewport.size_changed.connect(_queue_mobile_layout_refresh)

	_update_age_display()
	_update_resource_display({"food": 200, "wood": 200, "gold": 100})
	_apply_mobile_layout_for_current_viewport()
	_refresh_touch_target_diagnostics()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and is_node_ready():
		_queue_mobile_layout_refresh()


func _queue_mobile_layout_refresh() -> void:
	if not is_node_ready() or _mobile_layout_refresh_queued:
		return
	_mobile_layout_refresh_queued = true
	call_deferred("_apply_mobile_layout_for_current_viewport")


func _apply_mobile_layout_for_current_viewport() -> void:
	_mobile_layout_refresh_queued = false
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))


func _get_safe_area_rect(viewport_size: Vector2) -> Rect2:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		_safe_area_diagnostics = {"source": "invalid_viewport"}
		return viewport_rect
	# Web reports the canvas as its safe area but the monitor as its screen.
	# Mapping one through the other shrinks the HUD to a fraction of the canvas.
	if OS.has_feature("web"):
		_safe_area_diagnostics = {"source": "web_viewport", "normalized": viewport_rect}
		return viewport_rect

	# DisplayServer reports safe areas in physical display coordinates, while
	# Control layout uses root-viewport coordinates.  These only happened to
	# match at the old 1280x720 desktop test size.  In a resized Web canvas (and
	# on HiDPI phones), mixing the two spaces creates phantom right/bottom
	# insets and pushes the HUD toward the middle of the screen.
	#
	# Desktop safe-area fallbacks describe the whole monitor/taskbar, not this
	# window, so only consume them on the platforms where the game owns the
	# display surface.
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		_safe_area_diagnostics = {"source": "desktop_viewport", "normalized": viewport_rect}
		return viewport_rect

	var safe_rect_i: Rect2i = DisplayServer.get_display_safe_area()
	if safe_rect_i.size.x <= 0 or safe_rect_i.size.y <= 0:
		_safe_area_diagnostics = {"source": "missing_display_safe_area", "normalized": viewport_rect}
		return viewport_rect

	var screen_id: int = DisplayServer.SCREEN_OF_MAIN_WINDOW
	var display_rect := Rect2(
		Vector2(DisplayServer.screen_get_position(screen_id)),
		Vector2(DisplayServer.screen_get_size(screen_id))
	)
	var raw_safe_area := Rect2(Vector2(safe_rect_i.position), Vector2(safe_rect_i.size))
	var normalized := map_display_safe_area_to_viewport(raw_safe_area, display_rect, viewport_size)
	_safe_area_diagnostics = {
		"source": "display_mapped",
		"raw": raw_safe_area,
		"display": display_rect,
		"normalized": normalized,
		"scale_x": viewport_size.x / display_rect.size.x if display_rect.size.x > 0.0 else 1.0,
		"scale_y": viewport_size.y / display_rect.size.y if display_rect.size.y > 0.0 else 1.0,
	}
	return normalized


static func map_display_safe_area_to_viewport(raw_safe_area: Rect2, display_rect: Rect2, viewport_size: Vector2) -> Rect2:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return viewport_rect
	if display_rect.size.x <= 0.0 or display_rect.size.y <= 0.0:
		return viewport_rect
	if raw_safe_area.size.x <= 0.0 or raw_safe_area.size.y <= 0.0:
		return viewport_rect

	var clipped_safe_area: Rect2 = raw_safe_area.intersection(display_rect)
	if not clipped_safe_area.has_area():
		return viewport_rect
	var display_to_viewport := Vector2(
		viewport_size.x / display_rect.size.x,
		viewport_size.y / display_rect.size.y
	)
	var mapped := Rect2(
		(clipped_safe_area.position - display_rect.position) * display_to_viewport,
		clipped_safe_area.size * display_to_viewport
	).intersection(viewport_rect)
	if not mapped.has_area():
		return viewport_rect
	return mapped


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
	var now_msec: int = Time.get_ticks_msec()
	if not OS.has_feature("production") and now_msec >= _next_touch_diagnostics_refresh_msec:
		_next_touch_diagnostics_refresh_msec = now_msec + 250
		_refresh_touch_target_diagnostics()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("pause"):
		_on_pause_pressed()
	elif event is InputEventKey and event.keycode == KEY_F2:
		_toggle_hotkey_panel()


# --- Pause / Speed controls ---

func _create_game_control_buttons() -> void:
	var root_ctrl: Control = $Root
	var hbox := HBoxContainer.new()
	hbox.name = "GameControlButtons"
	hbox.add_theme_constant_override("separation", 4)
	hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hbox.offset_left = -112
	hbox.offset_right = -8
	hbox.offset_top = 2
	hbox.offset_bottom = 50
	hbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	_pause_button = Button.new()
	_pause_button.name = "PauseButton"
	_pause_button.text = "II"
	_pause_button.custom_minimum_size = Vector2(48, 48)
	_pause_button.pressed.connect(_on_pause_pressed)
	_pause_button.tooltip_text = "Pause/Resume [P]"
	hbox.add_child(_pause_button)

	_speed_button = Button.new()
	_speed_button.name = "SpeedButton"
	_speed_button.text = "1x"
	_speed_button.custom_minimum_size = Vector2(52, 48)
	_speed_button.pressed.connect(_on_speed_pressed)
	_speed_button.tooltip_text = "Cycle game speed"
	hbox.add_child(_speed_button)

	root_ctrl.add_child(hbox)


func _create_camera_controls() -> void:
	_camera_controls = HBoxContainer.new()
	_camera_controls.name = "CameraZoomControls"
	_camera_controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_camera_controls.add_theme_constant_override("separation", 4)
	_camera_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera_view_button = Button.new()
	_camera_view_button.name = "CameraViewButton"
	_camera_view_button.text = "View"
	_camera_view_button.custom_minimum_size = Vector2(48, 48)
	_camera_view_button.add_theme_font_size_override("font_size", 12)
	KingdomTheme.apply_secondary(_camera_view_button)
	_camera_view_button.toggle_mode = true
	_camera_view_button.tooltip_text = "Show camera zoom controls"
	for style_name: String in ["normal", "hover", "pressed", "disabled"]:
		var view_style: StyleBox = _camera_view_button.get_theme_stylebox(style_name).duplicate()
		view_style.set_content_margin(SIDE_LEFT, 4.0)
		view_style.set_content_margin(SIDE_RIGHT, 4.0)
		_camera_view_button.add_theme_stylebox_override(style_name, view_style)
	_camera_view_button.pressed.connect(func() -> void:
		_camera_controls_expanded = not _camera_controls_expanded
		_queue_mobile_layout_refresh()
	)
	_camera_controls.add_child(_camera_view_button)
	_camera_zoom_out_button = Button.new()
	_camera_zoom_out_button.name = "ZoomOutButton"
	_camera_zoom_out_button.text = "−"
	_camera_zoom_out_button.custom_minimum_size = Vector2(48, 48)
	_camera_zoom_out_button.add_theme_font_size_override("font_size", 25)
	_camera_zoom_out_button.tooltip_text = "Zoom out to see more of the map"
	_camera_zoom_out_button.pressed.connect(func(): camera_zoom_requested.emit(-1))
	_camera_controls.add_child(_camera_zoom_out_button)
	_camera_zoom_in_button = Button.new()
	_camera_zoom_in_button.name = "ZoomInButton"
	_camera_zoom_in_button.text = "+"
	_camera_zoom_in_button.custom_minimum_size = Vector2(48, 48)
	_camera_zoom_in_button.add_theme_font_size_override("font_size", 25)
	_camera_zoom_in_button.tooltip_text = "Zoom in for a closer view"
	_camera_zoom_in_button.pressed.connect(func(): camera_zoom_requested.emit(1))
	_camera_controls.add_child(_camera_zoom_in_button)
	_camera_zoom_reset_button = Button.new()
	_camera_zoom_reset_button.name = "ZoomResetButton"
	_camera_zoom_reset_button.text = "Reset"
	_camera_zoom_reset_button.custom_minimum_size = Vector2(64, 48)
	_camera_zoom_reset_button.add_theme_font_size_override("font_size", 14)
	_camera_zoom_reset_button.tooltip_text = "Return to the starting view scale"
	_camera_zoom_reset_button.pressed.connect(func(): camera_zoom_reset_requested.emit())
	_camera_controls.add_child(_camera_zoom_reset_button)
	$Root.add_child(_camera_controls)
	_selection_back_button = Button.new()
	_selection_back_button.name = "SelectionBackButton"
	_selection_back_button.text = "Back"
	_selection_back_button.custom_minimum_size = Vector2(64, 48)
	_selection_back_button.add_theme_font_size_override("font_size", 14)
	_selection_back_button.tooltip_text = "Clear selection and return to kingdom controls"
	_selection_back_button.pressed.connect(func() -> void: deselect_requested.emit())
	$Root/BottomRight.add_child(_selection_back_button)
	_selection_back_button.visible = false


func update_camera_zoom(current: float, minimum: float, maximum: float) -> void:
	_camera_zoom_current = current
	_camera_zoom_min = minimum
	_camera_zoom_max = maximum
	var interactable: bool = _ui_modal_state == UIModalState.NONE
	if _camera_zoom_in_button:
		_camera_zoom_in_button.disabled = not interactable or current >= maximum - 0.001
	if _camera_zoom_out_button:
		_camera_zoom_out_button.disabled = not interactable or current <= minimum + 0.001
	if _camera_zoom_reset_button:
		_camera_zoom_reset_button.disabled = not interactable
	if _camera_view_button:
		_camera_view_button.disabled = not interactable
	_refresh_touch_target_diagnostics()


func _create_match_population_label() -> void:
	_match_population_label = Label.new()
	_match_population_label.name = "MatchPopulationLimitLabel"
	_match_population_label.add_theme_font_size_override("font_size", 13)
	_match_population_label.add_theme_color_override("font_color", KingdomTheme.MUTED)
	_match_population_label.tooltip_text = "Match population limit per player, including workers"
	top_bar_hbox.add_child(_match_population_label)
	top_bar_hbox.move_child(_match_population_label, pop_label.get_index() + 1)
	pop_label.tooltip_text = "Current population / housing capacity. Build Houses for more room, up to the match limit."
	var gm: Node = _get_game_manager()
	set_match_population_limit(int(gm.call("get_match_population_limit")) if gm and gm.has_method("get_match_population_limit") else 30)


func set_match_population_limit(limit: int) -> void:
	_match_population_limit = limit
	if _match_population_label:
		_match_population_label.text = "Max %d" % limit


func _configure_mobile_visuals() -> void:
	# Reuse the game's own readable silhouettes so the primary controls scan as
	# game actions rather than anonymous text slabs.
	_set_button_icon(build_menu_button, "res://assets/buildings/house.png", 26)
	_set_button_icon(age_up_button, "res://assets/buildings/town_center_alt.png", 24)
	_set_button_icon(_idle_villager_button, UnitData.get_unit_icon_path(UnitData.UnitType.VILLAGER), 24)
	_set_button_icon(_select_military_button, UnitData.get_unit_icon_path(UnitData.UnitType.SCOUT), 24)
	_set_button_icon(_find_army_button, UnitData.get_unit_icon_path(UnitData.UnitType.SCOUT), 22)
	_set_button_icon(_town_center_button, "res://assets/buildings/town_center_alt.png", 24)
	for button in [build_menu_button, age_up_button, _idle_villager_button, _select_military_button, _find_army_button]:
		if button:
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ColorRect cannot draw a border. A mouse-transparent frame gives the small
	# minimap a crisp edge without stealing drag/tap input from its TextureRect.
	if _minimap_frame == null:
		_minimap_frame = Panel.new()
		_minimap_frame.name = "MinimapFrame"
		_minimap_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		_minimap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_minimap_frame.z_index = 2
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		frame_style.border_color = Color(0.82, 0.67, 0.34, 0.82)
		frame_style.set_border_width_all(2)
		frame_style.set_corner_radius_all(6)
		_minimap_frame.add_theme_stylebox_override("panel", frame_style)
		minimap_bg.add_child(_minimap_frame)


func _set_button_icon(button: Button, texture_path: String, max_width: int) -> void:
	if button == null or texture_path == "" or not ResourceLoader.exists(texture_path):
		return
	button.icon = load(texture_path)
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", max_width)


func _on_pause_pressed() -> void:
	AudioManager.play_ui("button_click")
	var gm: Node = _get_game_manager()
	if gm and gm.current_state == gm.GameState.PAUSED:
		resume_requested.emit()
	else:
		pause_requested.emit()


func _on_speed_pressed() -> void:
	AudioManager.play_ui("button_click")
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
	vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vbox.custom_minimum_size = Vector2(250, 0)
	vbox.add_theme_constant_override("separation", 6)
	vbox.process_mode = Node.PROCESS_MODE_ALWAYS

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var resume_btn := Button.new()
	resume_btn.name = "ResumeButton"
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(192, 48)
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
	pause_help.custom_minimum_size = Vector2(250, 18)
	pause_help.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pause_help.clip_text = true
	pause_help.add_theme_font_size_override("font_size", 12)
	pause_help.add_theme_color_override("font_color", Color(0.92, 0.88, 0.74))
	vbox.add_child(pause_help)

	var sound_btn := Button.new()
	sound_btn.name = "SoundToggleButton"
	sound_btn.text = "Sound: ON" if AudioManager.sfx_enabled else "Sound: OFF"
	sound_btn.custom_minimum_size = Vector2(192, 48)
	sound_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sound_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	sound_btn.pressed.connect(func() -> void:
		var enabled: bool = not AudioManager.sfx_enabled
		AudioManager.set_all_enabled(enabled)
		sound_btn.text = "Sound: ON" if enabled else "Sound: OFF"
		AudioManager.play_ui("button_click")
	)
	vbox.add_child(sound_btn)

	var quit_btn := Button.new()
	quit_btn.name = "QuitButton"
	quit_btn.text = "Quit to Main Menu"
	quit_btn.custom_minimum_size = Vector2(192, 48)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	quit_btn.pressed.connect(func() -> void:
		if quit_btn.disabled:
			return
		quit_btn.disabled = true
		quit_to_menu_requested.emit()
	)
	vbox.add_child(quit_btn)

	_pause_overlay.add_child(vbox)
	get_node("Root").add_child(_pause_overlay)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_layout_pause_menu(viewport_size, _get_safe_area_rect(viewport_size))
	_refresh_touch_target_diagnostics()
	call_deferred("_refresh_touch_target_diagnostics")


func _layout_pause_menu(viewport_size: Vector2, safe_area: Rect2) -> void:
	if _pause_overlay == null:
		return
	var pause_menu: Control = _pause_overlay.get_node_or_null("PauseMenu")
	if pause_menu == null:
		return
	var safe_bounds: Rect2 = safe_area.intersection(Rect2(Vector2.ZERO, viewport_size))
	if not safe_bounds.has_area():
		safe_bounds = Rect2(Vector2.ZERO, viewport_size)
	var available_size := Vector2(maxf(200.0, safe_bounds.size.x - 16.0), maxf(200.0, safe_bounds.size.y - 16.0))
	var desired_size: Vector2 = pause_menu.get_combined_minimum_size()
	desired_size.x = minf(maxf(250.0, desired_size.x), available_size.x)
	desired_size.y = minf(desired_size.y, available_size.y)
	pause_menu.size = desired_size
	pause_menu.position = safe_bounds.position + (safe_bounds.size - desired_size) * 0.5


func _set_gameplay_ui_interactable(interactable: bool) -> void:
	var allow_mouse: int = Control.MOUSE_FILTER_STOP if interactable else Control.MOUSE_FILTER_IGNORE
	selection_panel.mouse_filter = allow_mouse
	minimap_bg.mouse_filter = allow_mouse
	minimap_rect.mouse_filter = allow_mouse
	if _speed_button:
		_speed_button.disabled = not interactable
	update_camera_zoom(_camera_zoom_current, _camera_zoom_min, _camera_zoom_max)
	age_up_button.disabled = not interactable
	build_menu_button.disabled = not interactable
	if _idle_villager_button:
		_idle_villager_button.disabled = not interactable or _last_idle_villager_count <= 0
	if _select_military_button:
		_select_military_button.disabled = not interactable or _last_military_count <= 0
	if _find_army_button:
		_find_army_button.disabled = not interactable or _last_military_count <= 0
	if _town_center_button:
		_town_center_button.disabled = not interactable
	if _selection_back_button:
		_selection_back_button.disabled = not interactable
	if _placement_cancel_button:
		_placement_cancel_button.disabled = not interactable
	if _placement_confirm_button:
		_placement_confirm_button.disabled = not interactable or not _placement_preview_valid
	if _advanced_command_panel:
		_advanced_command_panel.visible = interactable and _advanced_commands_open and _unit_commands_authorized
	if _unit_command_container:
		for child in _unit_command_container.get_children():
			if child is BaseButton:
				var command_button := child as BaseButton
				command_button.disabled = not interactable or not _unit_commands_authorized
		for button in [_unit_attack_move_button, _unit_patrol_button, _unit_stance_button]:
			button.disabled = not interactable or not _unit_commands_authorized
		if _unit_patrol_button:
			_unit_patrol_button.disabled = not interactable or not _unit_commands_authorized or not _unit_commands_have_military
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
	if _ui_modal_state != UIModalState.NONE:
		_close_advanced_commands()
		_camera_controls_expanded = false
	var paused: bool = _ui_modal_state == UIModalState.PAUSE_MENU
	if paused and _build_menu_open:
		_build_menu_open = false
		build_menu_button.text = "Build"
		build_menu_toggled.emit(false)
	if _pause_button:
		_pause_button.text = ">" if paused else "II"
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
		if _is_human_owned_building(_selected_building_ref):
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
		else:
			_last_queue_items = []
			_update_queue_display([])
			_update_train_buttons([])
			_update_research_buttons(null)
	# The Build palette is the only bottom sheet on the phone. Hide the HUD
	# controls beneath it so the palette never collides with the minimap, context
	# shelf, or thumb rail, then restore them when the sheet closes.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))
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
	_mobile_action_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(MOBILE_ACTION_INNER_PADDING))
	margin.add_theme_constant_override("margin_right", int(MOBILE_ACTION_INNER_PADDING))
	margin.add_theme_constant_override("margin_top", int(MOBILE_ACTION_VERTICAL_PADDING))
	margin.add_theme_constant_override("margin_bottom", int(MOBILE_ACTION_VERTICAL_PADDING))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_action_panel.add_child(margin)

	_mobile_action_strip = GridContainer.new()
	_mobile_action_strip.name = "MobileActionStrip"
	_mobile_action_strip.columns = 1
	_mobile_action_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_action_strip.add_theme_constant_override("h_separation", int(MOBILE_ACTION_GAP))
	_mobile_action_strip.add_theme_constant_override("v_separation", int(MOBILE_ACTION_GAP))
	_mobile_action_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_mobile_action_strip)

	_placement_confirm_button = Button.new()
	_placement_confirm_button.name = "PlacementConfirmButton"
	_placement_confirm_button.text = "Place building"
	_placement_confirm_button.custom_minimum_size = Vector2(132, MOBILE_ACTION_BUTTON_HEIGHT)
	_placement_confirm_button.disabled = true
	_placement_confirm_button.visible = false
	_placement_confirm_button.pressed.connect(func(): placement_confirm_requested.emit())
	KingdomTheme.apply_primary(_placement_confirm_button)
	_mobile_action_strip.add_child(_placement_confirm_button)

	_placement_status_panel = PanelContainer.new()
	_placement_status_panel.name = "PlacementStatusPanel"
	_placement_status_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_placement_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placement_status_panel.visible = false
	_placement_status_panel.add_theme_stylebox_override("panel", KingdomTheme.panel_style())
	_placement_status_label = Label.new()
	_placement_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_status_label.add_theme_font_size_override("font_size", 14)
	_placement_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_placement_status_panel.add_child(_placement_status_label)
	root_ctrl.add_child(_placement_status_panel)

	_placement_cancel_button = Button.new()
	_placement_cancel_button.name = "PlacementCancelButton"
	_placement_cancel_button.text = "Cancel"
	_placement_cancel_button.custom_minimum_size = Vector2(MOBILE_ACTION_MIN_BUTTON_WIDTH, MOBILE_ACTION_BUTTON_HEIGHT)
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
	_idle_villager_button.custom_minimum_size = Vector2(MOBILE_ACTION_MIN_BUTTON_WIDTH, MOBILE_ACTION_BUTTON_HEIGHT)
	_idle_villager_button.pressed.connect(_on_idle_villager_pressed)
	_idle_villager_button.tooltip_text = "Cycle idle villagers [.]"
	_idle_villager_button.disabled = true
	_mobile_action_strip.add_child(_idle_villager_button)

	# Villager task breakdown — use HBox with colored labels per resource
	var bottom_right: VBoxContainer = %BottomRight
	_villager_task_hbox = HBoxContainer.new()
	_villager_task_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_villager_task_hbox.add_theme_constant_override("separation", 6)
	# Keep contextual worker counts readable over grass without adding layout or input area.
	var task_backplate := KingdomTheme.panel_style(KingdomTheme.INK, KingdomTheme.INK, 4)
	task_backplate.set_content_margin_all(0.0)
	task_backplate.set_border_width_all(0)
	_villager_task_hbox.draw.connect(func():
		_villager_task_hbox.draw_style_box(task_backplate, Rect2(Vector2.ZERO, _villager_task_hbox.size)))
	_villager_task_hbox.resized.connect(_villager_task_hbox.queue_redraw)
	bottom_right.add_child(_villager_task_hbox)
	bottom_right.move_child(_villager_task_hbox, 0)


func _on_idle_villager_pressed() -> void:
	AudioManager.play_ui("button_click")
	idle_villager_pressed.emit()


func _emit_select_all_military_pressed() -> void:
	select_all_military_pressed.emit()


func _emit_find_army_pressed() -> void:
	find_army_pressed.emit()


func _create_military_buttons() -> void:
	_ensure_mobile_action_strip()
	_town_center_button = Button.new()
	_town_center_button.name = "HomeButton"
	_town_center_button.text = "Home"
	_town_center_button.custom_minimum_size = Vector2(MOBILE_ACTION_MIN_BUTTON_WIDTH, MOBILE_ACTION_BUTTON_HEIGHT)
	_town_center_button.tooltip_text = "Return to your Town Center and recruit villagers [H]"
	_town_center_button.pressed.connect(func(): town_center_pressed.emit())
	_mobile_action_strip.add_child(_town_center_button)

	_select_military_button = Button.new()
	_select_military_button.name = "SelectMilitaryButton"
	_select_military_button.text = "Military: 0 [M]"
	_select_military_button.custom_minimum_size = Vector2(MOBILE_ACTION_MIN_BUTTON_WIDTH, MOBILE_ACTION_BUTTON_HEIGHT)
	_select_military_button.pressed.connect(_emit_select_all_military_pressed)
	_select_military_button.tooltip_text = "Select all military units [M]"
	_select_military_button.disabled = true
	_mobile_action_strip.add_child(_select_military_button)

	_find_army_button = Button.new()
	_find_army_button.name = "FindArmyButton"
	_find_army_button.text = "Find Army: 0 [F]"
	_find_army_button.custom_minimum_size = Vector2(MOBILE_ACTION_MIN_BUTTON_WIDTH, MOBILE_ACTION_BUTTON_HEIGHT)
	_find_army_button.pressed.connect(_emit_find_army_pressed)
	_find_army_button.tooltip_text = "Center camera on your army [F]"
	_find_army_button.disabled = true
	_mobile_action_strip.add_child(_find_army_button)


func _create_unit_command_buttons() -> void:
	if _unit_command_container != null:
		return
	var commands_row: HBoxContainer = $Root/SelectionPanel/SelectionMargin/VBox/CommandScroll/CommandsRow
	commands_row.add_theme_constant_override("separation", 6)
	_unit_command_container = HBoxContainer.new()
	_unit_command_container.name = "UnitCommandContainer"
	_unit_command_container.add_theme_constant_override("separation", 6)
	_unit_command_container.visible = false
	commands_row.add_child(_unit_command_container)
	commands_row.move_child(_unit_command_container, 0)

	_unit_move_button = _make_unit_command_button("UnitMoveButton", "Move", "Move; then tap a destination")
	_unit_move_button.toggle_mode = true
	_unit_move_button.pressed.connect(_on_unit_move_pressed)
	_unit_command_container.add_child(_unit_move_button)
	_unit_stop_button = _make_unit_command_button("UnitStopButton", "Stop", "Stop the selected units")
	_unit_stop_button.pressed.connect(_on_unit_stop_pressed)
	_unit_command_container.add_child(_unit_stop_button)
	_unit_more_button = _make_unit_command_button("UnitMoreButton", "More", "Attack-move, Patrol and Stance")
	_unit_more_button.toggle_mode = true
	_unit_more_button.pressed.connect(_on_unit_more_pressed)
	_unit_command_container.add_child(_unit_more_button)
	_unit_clear_button = _make_unit_command_button("UnitClearButton", "Clear", "Clear the current selection")
	_unit_clear_button.pressed.connect(_on_unit_clear_pressed)
	_unit_command_container.add_child(_unit_clear_button)

	_advanced_command_panel = PanelContainer.new()
	_advanced_command_panel.name = "AdvancedCommandsPanel"
	_advanced_command_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_advanced_command_panel.visible = false
	_advanced_command_panel.add_theme_stylebox_override("panel", KingdomTheme.panel_style())
	$Root.add_child(_advanced_command_panel)
	_advanced_command_container = HBoxContainer.new()
	_advanced_command_container.add_theme_constant_override("separation", 6)
	_advanced_command_panel.add_child(_advanced_command_container)
	_unit_attack_move_button = _make_unit_command_button("UnitAttackMoveButton", "Attack-move", "Engage enemies on the way to a destination")
	_unit_attack_move_button.toggle_mode = true
	_unit_attack_move_button.pressed.connect(_on_unit_attack_move_pressed)
	_advanced_command_container.add_child(_unit_attack_move_button)
	_unit_patrol_button = _make_unit_command_button("UnitPatrolButton", "Patrol", "Patrol between here and a destination")
	_unit_patrol_button.toggle_mode = true
	_unit_patrol_button.pressed.connect(_on_unit_patrol_pressed)
	_advanced_command_container.add_child(_unit_patrol_button)
	_unit_stance_button = _make_unit_command_button("UnitStanceButton", "Stance", "Toggle Aggressive / Stand Ground")
	_unit_stance_button.toggle_mode = true
	_unit_stance_button.pressed.connect(_on_unit_stance_pressed)
	_advanced_command_container.add_child(_unit_stance_button)


func _on_unit_more_pressed() -> void:
	_advanced_commands_open = not _advanced_commands_open
	_unit_more_button.set_pressed_no_signal(_advanced_commands_open)
	_advanced_command_panel.visible = _advanced_commands_open and _unit_commands_authorized
	_queue_mobile_layout_refresh()


func _close_advanced_commands() -> void:
	_advanced_commands_open = false
	if _unit_more_button:
		_unit_more_button.set_pressed_no_signal(false)
	if _advanced_command_panel:
		_advanced_command_panel.visible = false


func _make_unit_command_button(button_name: String, label: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label
	button.custom_minimum_size = Vector2(MOBILE_UNIT_COMMAND_WIDTH, MOBILE_ACTION_BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", 14)
	var compact_style: StyleBoxFlat = button.get_theme_stylebox("normal").duplicate()
	compact_style.set_content_margin(SIDE_LEFT, 8.0)
	compact_style.set_content_margin(SIDE_RIGHT, 8.0)
	button.add_theme_stylebox_override("normal", compact_style)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	return button


func _on_unit_move_pressed() -> void:
	_close_advanced_commands()
	AudioManager.play_ui("button_click")
	unit_move_requested.emit()


func _on_unit_attack_move_pressed() -> void:
	_close_advanced_commands()
	AudioManager.play_ui("button_click")
	unit_attack_move_requested.emit()


func _on_unit_patrol_pressed() -> void:
	_close_advanced_commands()
	AudioManager.play_ui("button_click")
	unit_patrol_requested.emit()


func _on_unit_stop_pressed() -> void:
	_close_advanced_commands()
	AudioManager.play_ui("button_click")
	unit_stop_requested.emit()


func _on_unit_stance_pressed() -> void:
	_close_advanced_commands()
	AudioManager.play_ui("button_click")
	unit_stance_requested.emit()


func _on_unit_clear_pressed() -> void:
	_close_advanced_commands()
	AudioManager.play_ui("button_click")
	deselect_requested.emit()


func configure_unit_commands(
	authorized: bool,
	has_military: bool = false,
	stance_name: String = "Aggressive",
	armed_mode: String = "smart"
) -> void:
	if _unit_command_container == null:
		return
	_unit_commands_authorized = authorized
	_unit_commands_have_military = has_military
	_unit_command_mode = armed_mode
	_refresh_unit_selection_details()
	_unit_command_container.visible = (
		authorized
		and not _placement_mode_active
		and _ui_modal_state == UIModalState.NONE
	)
	for button in [_unit_move_button, _unit_attack_move_button, _unit_stop_button, _unit_stance_button, _unit_clear_button, _unit_more_button]:
		if button:
			button.disabled = not authorized
	if _unit_patrol_button:
		_unit_patrol_button.disabled = not authorized or not has_military
	if _unit_move_button:
		_unit_move_button.set_pressed_no_signal(armed_mode == "move")
	if _unit_attack_move_button:
		_unit_attack_move_button.set_pressed_no_signal(armed_mode == "attack_move")
	if _unit_patrol_button:
		_unit_patrol_button.set_pressed_no_signal(armed_mode == "patrol")
	if _unit_stance_button:
		_unit_stance_button.text = "Stance"
		_unit_stance_button.set_pressed_no_signal(stance_name == "Stand Ground")
		_unit_stance_button.tooltip_text = "Current stance: %s. Tap to toggle." % stance_name
	if _unit_more_button:
		_unit_more_button.text = "More •" if armed_mode in ["attack_move", "patrol"] else "More"
	if _advanced_command_panel:
		_advanced_command_panel.visible = _advanced_commands_open and _unit_command_container.visible
	_queue_mobile_layout_refresh()
	_refresh_touch_target_diagnostics()


func _hide_unit_commands() -> void:
	_unit_commands_authorized = false
	_unit_commands_have_military = false
	_unit_command_mode = "smart"
	if _unit_command_container:
		_unit_command_container.visible = false
	if _advanced_command_panel:
		_advanced_command_panel.visible = false


func update_idle_villager_count(count: int) -> void:
	_last_idle_villager_count = count
	var layout_changed: bool = false
	if _idle_villager_button:
		var was_visible: bool = _idle_villager_button.visible
		_idle_villager_button.visible = count > 0 and not _placement_mode_active and (not _is_phone_context() or not _selection_context_active or (_selection_kind == "unit" and _selection_is_worker and not _unit_commands_have_military))
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
	var was_active: bool = _placement_mode_active
	_placement_mode_active = active
	_placement_cancel_button.visible = active
	_placement_confirm_button.visible = active
	_placement_status_panel.visible = active
	if _town_center_button:
		_town_center_button.visible = not active
	_placement_building_name = building_name
	if active and not was_active:
		_placement_preview_valid = false
		update_placement_preview(false, "Drag onto clear ground")
	_close_advanced_commands()
	var bottom_right: Control = get_node_or_null("Root/BottomRight")
	if bottom_right:
		bottom_right.visible = not active
	minimap_bg.visible = not active
	if active:
		# Placement is a direct-manipulation mode: leave the world, ghost, top
		# resources, and explicit Place / Cancel actions while hiding the prior
		# selection/building chrome over the placement surface.
		selection_panel.visible = false
	elif was_active:
		# Placement temporarily hides the context shelf; completing or cancelling
		# must restore the still-current selection without requiring another tap.
		selection_panel.visible = _selection_context_active
	if _unit_command_container:
		_unit_command_container.visible = (
			_unit_commands_authorized
			and not active
			and _ui_modal_state == UIModalState.NONE
		)
	if active and building_name != "":
		_placement_cancel_button.text = "Cancel"
		_placement_cancel_button.tooltip_text = "Cancel %s placement" % building_name
	else:
		_placement_cancel_button.text = "Cancel"
		_placement_cancel_button.tooltip_text = "Cancel current building placement [Esc]"
	update_idle_villager_count(_last_idle_villager_count)
	update_military_count(_last_military_count)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))


func update_placement_preview(valid: bool, reason: String = "") -> void:
	_placement_preview_valid = valid
	if _placement_confirm_button:
		_placement_confirm_button.disabled = not valid or _ui_modal_state == UIModalState.PAUSE_MENU
		_placement_confirm_button.text = "Place %s" % _placement_building_name if _placement_building_name != "" else "Place building"
		# The complete building name lives in the status. The CTA stays readable.
		if _placement_confirm_button.text.length() > 20:
			_placement_confirm_button.text = "Place building"
	if _placement_status_label:
		var status: String = "Ready to build" if valid else (reason if reason != "" else "Choose clear ground")
		_placement_status_label.text = "%s · %s" % [_placement_building_name, status] if _placement_building_name != "" else status
		_placement_status_label.add_theme_color_override("font_color", KingdomTheme.PARCHMENT if valid else Color(1.0, 0.75, 0.55))
	_refresh_touch_target_diagnostics()


func apply_mobile_layout(viewport_size: Vector2, safe_area: Rect2) -> void:
	if _mobile_action_panel == null:
		return

	var safe_pos: Vector2 = safe_area.position
	_apply_context_actions(viewport_size)
	var action_count: int = _count_visible_mobile_action_buttons()
	var metrics: Dictionary = _calculate_mobile_layout_metrics(viewport_size, safe_area, action_count)
	var build_sheet_open: bool = _ui_modal_state == UIModalState.BUILD_MENU
	var standard_field_chrome_visible: bool = not _placement_mode_active and not build_sheet_open
	var build_menu: Node = get_node_or_null("BuildMenu")
	if build_menu and build_menu.has_method("set_safe_area_rect"):
		build_menu.call("set_safe_area_rect", safe_area)
	_layout_pause_menu(viewport_size, safe_area)
	_mobile_action_panel.visible = action_count > 0 and not build_sheet_open

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
	for button in [_placement_confirm_button, _placement_cancel_button, _town_center_button, _idle_villager_button, _select_military_button, _find_army_button]:
		if button:
			button.custom_minimum_size = Vector2(maxf(button_width, 148.0) if _placement_mode_active else button_width, MOBILE_ACTION_BUTTON_HEIGHT)
	if _unit_command_container:
		for child in _unit_command_container.get_children():
			if child is Button:
				(child as Button).custom_minimum_size = Vector2(MOBILE_UNIT_COMMAND_WIDTH, MOBILE_ACTION_BUTTON_HEIGHT)

	var compact_labels: bool = metrics["compact_labels"]
	if compact_labels != _mobile_compact_labels:
		_mobile_compact_labels = compact_labels
		update_idle_villager_count(_last_idle_villager_count)
		update_military_count(_last_military_count)

	_top_bar_safe_width = safe_area.size.x
	var abbreviated_resources: bool = safe_area.size.x < 620.0
	if _resource_labels_abbreviated != abbreviated_resources:
		_resource_labels_abbreviated = abbreviated_resources
		_update_resource_display(_resource_values)
		update_population(_population_current, _population_cap)
	_apply_top_bar_compact(metrics["top_bar_compact"])
	_update_resource_display(_resource_values)
	if _villager_task_hbox:
		var phone_tasks: bool = bool(metrics["top_bar_compact"])
		var task_parent: Node = $Root if phone_tasks else $Root/BottomRight
		if _villager_task_hbox.get_parent() != task_parent:
			_villager_task_hbox.reparent(task_parent)
		_villager_task_hbox.visible = not phone_tasks or (_selection_kind == "unit" and _selection_is_worker and _unit_commands_authorized and not _unit_commands_have_military and not _advanced_commands_open and not _placement_mode_active and _ui_modal_state == UIModalState.NONE)
	var safe_top: float = metrics["safe_top"]
	var safe_left: float = metrics["safe_left"]
	var safe_right: float = metrics["safe_right"]
	top_bar.offset_top = safe_top
	top_bar.offset_bottom = safe_top + top_bar.custom_minimum_size.y
	var top_bar_margin: MarginContainer = top_bar.get_node_or_null("TopBarMargin")
	if top_bar_margin:
		top_bar_margin.add_theme_constant_override("margin_left", int(round(safe_left + 10.0)))
		# Reserve the top-right utility buttons instead of rendering the timer
		# underneath them at narrow phone widths.
		top_bar_margin.add_theme_constant_override("margin_right", int(round(safe_right + 116.0)))

	var game_controls: Control = get_node_or_null("Root/GameControlButtons")
	if game_controls:
		game_controls.offset_right = -safe_right - 8.0
		game_controls.offset_left = game_controls.offset_right - 104.0
		game_controls.offset_top = safe_top + 2.0
		game_controls.offset_bottom = safe_top + 50.0
	if _score_label:
		_refresh_score_visibility(viewport_size)
		_score_label.offset_left = -safe_right - 290.0
		_score_label.offset_right = -safe_right - 122.0
		_score_label.offset_top = safe_top + 8.0
		_score_label.offset_bottom = safe_top + 28.0

	if minimap_bg:
		minimap_bg.visible = standard_field_chrome_visible
		minimap_bg.offset_left = metrics["minimap_left"]
		minimap_bg.offset_bottom = metrics["minimap_bottom"]
		minimap_bg.offset_top = metrics["minimap_top"]
		minimap_bg.offset_right = metrics["minimap_right"]

	if _camera_controls:
		_camera_controls.visible = _ui_modal_state == UIModalState.NONE
		var phone_camera: bool = minf(viewport_size.x, viewport_size.y) <= 520.0
		_camera_view_button.visible = phone_camera
		_camera_view_button.set_pressed_no_signal(_camera_controls_expanded)
		for zoom_button: Button in [_camera_zoom_out_button, _camera_zoom_in_button, _camera_zoom_reset_button]:
			zoom_button.visible = not phone_camera or _camera_controls_expanded
		_camera_controls.offset_left = metrics["minimap_left"]
		var camera_width: float = 220.0 if phone_camera and _camera_controls_expanded else (48.0 if phone_camera else 168.0)
		_camera_controls.offset_right = metrics["minimap_left"] + camera_width
		_camera_controls.offset_bottom = metrics["minimap_top"] - 24.0
		_camera_controls.offset_top = _camera_controls.offset_bottom - 48.0
		metrics["camera_zoom_left"] = metrics["minimap_left"]
		metrics["camera_zoom_right"] = metrics["minimap_left"] + camera_width
		metrics["camera_zoom_top"] = viewport_size.y + _camera_controls.offset_top
		metrics["camera_zoom_bottom"] = viewport_size.y + _camera_controls.offset_bottom
		_mobile_notification_limit = clampi(int((metrics["camera_zoom_top"] - metrics["safe_top"] - 56.0) / 40.0), 1, MAX_NOTIFICATIONS)
	var bottom_right: Control = get_node_or_null("Root/BottomRight")
	if bottom_right:
		bottom_right.visible = standard_field_chrome_visible and (age_up_button.visible or build_menu_button.visible or _selection_back_button.visible)
		bottom_right.offset_left = metrics["bottom_right_left"]
		bottom_right.offset_right = metrics["bottom_right_right"]
		bottom_right.offset_bottom = metrics["bottom_right_bottom"]
		bottom_right.offset_top = metrics["bottom_right_top"]

	selection_panel.offset_left = metrics["selection_left"] - viewport_size.x * 0.5
	selection_panel.offset_right = metrics["selection_right"] - viewport_size.x * 0.5
	selection_panel.offset_bottom = metrics["selection_bottom"]
	selection_panel.offset_top = metrics["selection_top"]
	selection_panel.custom_minimum_size = Vector2(metrics["selection_width"], metrics["selection_height"])
	selection_info_column.custom_minimum_size.x = metrics["selection_info_width"]
	selection_name.add_theme_font_size_override("font_size", 12 if bool(metrics["top_bar_compact"]) and _is_town_center_production_context() else 14)
	selection_info_column.add_theme_constant_override("separation", 0)
	_update_selection_name_layout(float(metrics["selection_info_width"]))
	selection_panel.visible = _selection_context_active and standard_field_chrome_visible
	if _villager_task_hbox and _villager_task_hbox.get_parent() == $Root:
		_villager_task_hbox.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_villager_task_hbox.offset_left = metrics["selection_left"] - viewport_size.x * 0.5
		_villager_task_hbox.offset_right = _villager_task_hbox.offset_left + 300.0
		_villager_task_hbox.offset_bottom = metrics["selection_top"] - 2.0
		_villager_task_hbox.offset_top = _villager_task_hbox.offset_bottom - 18.0
	var selection_has_commands: bool = _selection_has_commands()
	selection_separator.visible = selection_has_commands and not (bool(metrics["top_bar_compact"]) and _is_town_center_production_context())
	command_scroll.visible = selection_has_commands
	_layout_queue_page()
	if _queue_hint_label:
		_queue_hint_label.offset_left = metrics["selection_left"] + metrics["selection_info_width"] + 12.0 - viewport_size.x * 0.5
		_queue_hint_label.offset_right = _queue_hint_label.offset_left + 150.0
		_queue_hint_label.offset_bottom = metrics["selection_top"] - 2.0
		_queue_hint_label.offset_top = _queue_hint_label.offset_bottom - 16.0
	if _advanced_command_panel:
		var advanced_width: float = minf(344.0, metrics["selection_width"])
		_advanced_command_panel.offset_left = metrics["selection_right"] - advanced_width - viewport_size.x * 0.5
		_advanced_command_panel.offset_right = _advanced_command_panel.offset_left + advanced_width
		_advanced_command_panel.offset_bottom = metrics["selection_top"] - 8.0
		_advanced_command_panel.offset_top = _advanced_command_panel.offset_bottom - 60.0
		_advanced_command_panel.visible = _advanced_commands_open and _unit_command_container.visible and standard_field_chrome_visible
		for child in _advanced_command_container.get_children():
			if child is Button:
				(child as Button).custom_minimum_size = Vector2(104.0, MOBILE_ACTION_BUTTON_HEIGHT)
	if _placement_status_panel:
		var status_width: float = minf(420.0, safe_area.size.x - 16.0)
		_placement_status_panel.offset_left = safe_pos.x + (safe_area.size.x - status_width) * 0.5 - viewport_size.x * 0.5
		_placement_status_panel.offset_right = _placement_status_panel.offset_left + status_width
		_placement_status_panel.offset_bottom = metrics["action_top"] - 8.0
		_placement_status_panel.offset_top = _placement_status_panel.offset_bottom - 32.0
	var side_button_size := Vector2(metrics["side_button_width"], metrics["side_button_height"])
	age_up_button.custom_minimum_size = side_button_size
	build_menu_button.custom_minimum_size = side_button_size

	if _progression_hint_panel:
		var hint_width: float = minf(MOBILE_GUIDANCE_WIDTH, safe_area.size.x - 140.0)
		var hint_left: float = safe_pos.x + (safe_area.size.x - hint_width) * 0.5
		var hint_right: float = hint_left + hint_width
		_progression_hint_panel.offset_left = hint_left - viewport_size.x * 0.5
		_progression_hint_panel.offset_right = hint_right - viewport_size.x * 0.5
		_progression_hint_panel.offset_top = metrics["safe_top"] + 48.0
		_progression_hint_panel.offset_bottom = _progression_hint_panel.offset_top + MOBILE_GUIDANCE_HEIGHT
		metrics["guidance_left"] = hint_left
		metrics["guidance_right"] = hint_right
		metrics["guidance_top"] = _progression_hint_panel.offset_top
		metrics["guidance_bottom"] = _progression_hint_panel.offset_bottom
		if _notification_container:
			var notification_left: float = safe_pos.x + 8.0
			# Prefer the full toast lane, but never force a minimum width through
			# the centered guidance card on a notched phone with Large UI enabled.
			var notification_right: float = notification_left + MOBILE_NOTIFICATION_MAX_WIDTH
			if _progression_hint_panel.visible:
				notification_right = minf(notification_right, hint_left - 8.0)
			_notification_container.offset_left = notification_left
			_notification_container.offset_right = maxf(notification_left, notification_right)
			_notification_container.offset_top = metrics["safe_top"] + 48.0
			_notification_container.offset_bottom = minf(viewport_size.y - 96.0, metrics["safe_top"] + 188.0)
			if _camera_controls and _camera_controls.visible:
				_notification_container.offset_bottom = minf(_notification_container.offset_bottom, metrics["camera_zoom_top"] - 8.0)
			metrics["notification_left"] = _notification_container.offset_left
			metrics["notification_right"] = _notification_container.offset_right
			metrics["notification_top"] = _notification_container.offset_top
			metrics["notification_bottom"] = _notification_container.offset_bottom
			metrics["notification_guidance_gap"] = hint_left - _notification_container.offset_right
			metrics["notification_guidance_overlap"] = Rect2(
				Vector2(_notification_container.offset_left, _notification_container.offset_top),
				Vector2(
					_notification_container.offset_right - _notification_container.offset_left,
					_notification_container.offset_bottom - _notification_container.offset_top
				)
			).intersects(
				Rect2(Vector2(hint_left, _progression_hint_panel.offset_top), Vector2(hint_width, MOBILE_GUIDANCE_HEIGHT)),
				true
			)
			_fit_notification_feed()

	if _sacred_site_panel:
		_sacred_site_panel.offset_top = metrics["safe_top"] + (110.0 if _progression_hint_panel and _progression_hint_panel.visible else 58.0)
		_sacred_site_panel.offset_bottom = _sacred_site_panel.offset_top + 28.0
		metrics["sacred_top"] = _sacred_site_panel.offset_top
		metrics["sacred_bottom"] = _sacred_site_panel.offset_bottom

	if not OS.has_feature("production"):
		metrics["safe_area_source"] = _safe_area_diagnostics.duplicate(true)
		mobile_layout_diagnostics = metrics
		_refresh_mobile_layout_profiles()
	_refresh_touch_target_diagnostics()


func _count_visible_mobile_action_buttons() -> int:
	var count: int = 0
	for button in [_placement_confirm_button, _placement_cancel_button, _town_center_button, _idle_villager_button, _select_military_button, _find_army_button]:
		if button and button.visible:
			count += 1
	return count


func _is_phone_context() -> bool:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return minf(viewport_size.x, viewport_size.y) <= 520.0


func _apply_context_actions(viewport_size: Vector2) -> void:
	var phone: bool = minf(viewport_size.x, viewport_size.y) <= 520.0
	var field_mode: bool = not _placement_mode_active and _ui_modal_state != UIModalState.BUILD_MENU
	var unselected: bool = not _selection_context_active
	var human_building: bool = is_instance_valid(_selected_building_ref) and _is_human_owned_building(_selected_building_ref)
	var town_center: bool = human_building and (_selected_building_ref as BuildingBase).building_type == BuildingData.BuildingType.TOWN_CENTER
	var worker: bool = _selection_kind == "unit" and _selection_is_worker and _unit_commands_authorized and not _unit_commands_have_military
	build_menu_button.visible = field_mode and (not phone or unselected or worker)
	var gm: Node = _get_game_manager()
	var can_advance: bool = gm == null or not gm.get_age_up_cost(0, gm.get_player_age(0) + 1).is_empty()
	age_up_button.visible = field_mode and not _early_game_ui_active and can_advance and (not phone or town_center)
	_selection_back_button.visible = phone and field_mode and _selection_context_active and not _unit_commands_authorized
	_town_center_button.visible = field_mode and (not phone or unselected)
	_idle_villager_button.visible = field_mode and _last_idle_villager_count > 0 and (not phone or unselected or worker)
	var military_allowed: bool = not _early_game_ui_active or _guided_military_shortcuts_visible
	_select_military_button.visible = field_mode and military_allowed and (_last_military_count > 0 or _pending_military_shortcut) and (not phone or unselected)
	_find_army_button.visible = field_mode and not phone and military_allowed and _last_military_count > 0
	var primary_age: bool = phone and town_center
	if primary_age != _age_action_primary:
		_age_action_primary = primary_age
		if primary_age:
			KingdomTheme.apply_primary(age_up_button)
		else:
			KingdomTheme.apply_secondary(age_up_button)


func _calculate_mobile_layout_metrics(viewport_size: Vector2, safe_area: Rect2, action_button_count: int) -> Dictionary:
	var safe_pos: Vector2 = safe_area.position
	var safe_end: Vector2 = safe_area.position + safe_area.size
	var left_inset: float = maxf(0.0, safe_pos.x)
	var right_inset: float = maxf(0.0, viewport_size.x - safe_end.x)
	var bottom_inset: float = maxf(0.0, viewport_size.y - safe_end.y)
	var content_width: float = maxf(220.0, safe_area.size.x - MOBILE_ACTION_MARGIN * 2.0)
	var short_side: float = minf(safe_area.size.x, safe_area.size.y)
	var side_button_width: float = clampf(safe_area.size.x * 0.13, 104.0, 116.0)
	var side_button_height: float = 48.0

	# Build and Age form the permanent bottom-right thumb rail. Two or more
	# utility actions use a compact single row (up to three buttons) so Large UI
	# on a short, notched phone cannot grow into top controls or status chips.
	var bottom_right_right: float = -MOBILE_ACTION_MARGIN - right_inset
	var side_count: int = int(age_up_button.visible) + int(build_menu_button.visible) + int(_selection_back_button != null and _selection_back_button.visible)
	var bottom_right_left: float = bottom_right_right - (side_button_width if side_count > 0 else 0.0)
	var bottom_right_bottom: float = -bottom_inset - MOBILE_ACTION_MARGIN
	var bottom_right_height: float = side_button_height * float(side_count) + 6.0 * float(maxi(0, side_count - 1))
	var bottom_right_top: float = bottom_right_bottom - bottom_right_height

	var action_columns: int = clampi(action_button_count, 1, 3)
	var action_rows: int = ceili(float(action_button_count) / float(action_columns))
	var button_width: float = side_button_width
	var action_height: float = 0.0
	if action_rows > 0:
		action_height = MOBILE_ACTION_VERTICAL_PADDING * 2.0 + MOBILE_ACTION_BUTTON_HEIGHT * float(action_rows) + MOBILE_ACTION_GAP * float(maxi(0, action_rows - 1))
	var action_right: float = bottom_right_right
	var action_width: float = (
		MOBILE_ACTION_INNER_PADDING * 2.0
		+ side_button_width * float(action_columns)
		+ MOBILE_ACTION_GAP * float(maxi(0, action_columns - 1))
	)
	var action_left: float = viewport_size.x + action_right - action_width
	var action_bottom: float = bottom_right_top - 8.0
	var action_top: float = action_bottom - action_height
	if _placement_mode_active:
		action_columns = 2
		action_rows = 1
		action_height = MOBILE_ACTION_BUTTON_HEIGHT
		action_width = 148.0 * 2.0 + MOBILE_ACTION_GAP + MOBILE_ACTION_INNER_PADDING * 2.0
		action_left = safe_pos.x + (safe_area.size.x - action_width) * 0.5
		action_right = action_left + action_width - viewport_size.x
		action_bottom = -bottom_inset - MOBILE_ACTION_MARGIN
		action_top = action_bottom - action_height

	var minimap_size: float = clampf(
		minf(safe_area.size.y * MOBILE_MINIMAP_SHORT_SIDE_RATIO, safe_area.size.x * 0.15),
		MOBILE_MINIMAP_MIN_SIZE,
		MOBILE_MINIMAP_MAX_SIZE
	)
	var minimap_left: float = left_inset + MOBILE_ACTION_MARGIN
	var minimap_bottom: float = -bottom_inset - MOBILE_ACTION_MARGIN
	var minimap_top: float = minimap_bottom - minimap_size
	var minimap_right: float = minimap_left + minimap_size

	var selection_has_commands: bool = _selection_has_commands()
	var unit_commands_visible: bool = _unit_command_container != null and _unit_command_container.visible
	# Center the context shelf inside the actual corridor between the minimap
	# and thumb rail. This remains collision-free when Large UI scale reduces
	# the logical viewport or when a phone has asymmetric safe-area insets.
	var selection_zone_left: float = minimap_right + 8.0
	var selection_zone_right: float = viewport_size.x + bottom_right_left - 8.0
	var selection_zone_width: float = maxf(220.0, selection_zone_right - selection_zone_left)
	var selection_max_width: float = minf(
		MOBILE_SELECTION_COMMAND_WIDTH if selection_has_commands else 320.0,
		selection_zone_width
	)
	var selection_min_width: float = minf(
		360.0 if selection_has_commands else 240.0,
		selection_max_width
	)
	var selection_width: float = selection_max_width if unit_commands_visible else clampf(
		safe_area.size.x * (0.62 if selection_has_commands else 0.34),
		selection_min_width,
		selection_max_width
	)
	var selection_height: float = MOBILE_SELECTION_HEIGHT
	var selection_bottom: float = -bottom_inset - MOBILE_ACTION_MARGIN
	var selection_top: float = selection_bottom - selection_height
	var selection_center_x: float = (selection_zone_left + selection_zone_right) * 0.5
	var selection_left: float = selection_center_x - selection_width * 0.5
	var selection_right: float = selection_left + selection_width

	var top_bar_compact: bool = short_side <= MOBILE_TOP_BAR_COMPACT_SHORT_SIDE or safe_area.size.x <= MOBILE_TOP_BAR_COMPACT_WIDTH
	var compact_labels: bool = content_width < 640.0 or top_bar_compact

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
	var game_controls_rect := Rect2(
		Vector2(viewport_size.x - right_inset - 112.0, safe_pos.y + 2.0),
		Vector2(104.0, 48.0)
	)

	var minimap_action_overlap: bool = minimap_rect_calc.intersects(action_rect, true)
	var selection_action_overlap: bool = selection_rect.intersects(action_rect, true)
	var bottom_right_action_overlap: bool = bottom_right_rect.intersects(action_rect, true)
	var selection_minimap_overlap: bool = selection_rect.intersects(minimap_rect_calc, true)
	var selection_bottom_right_overlap: bool = selection_rect.intersects(bottom_right_rect, true)
	var action_game_controls_overlap: bool = action_rect.intersects(game_controls_rect, true)
	var central_world_left: float = minimap_right + 12.0
	var central_world_right: float = viewport_size.x + bottom_right_left - 12.0
	var central_world_top: float = safe_pos.y + 48.0
	var central_world_bottom: float = viewport_size.y + selection_top - 8.0
	var central_world_width: float = maxf(0.0, central_world_right - central_world_left)
	var central_world_height: float = maxf(0.0, central_world_bottom - central_world_top)

	return {
		"viewport_width": viewport_size.x,
		"viewport_height": viewport_size.y,
		"safe_top": safe_pos.y,
		"safe_left": safe_pos.x,
		"safe_right": right_inset,
		"safe_bottom": bottom_inset,
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
		"selection_info_width": 88.0 if top_bar_compact and _is_town_center_production_context() else (120.0 if unit_commands_visible else (108.0 if selection_has_commands else 148.0)),
		"selection_left": selection_left,
		"selection_right": selection_right,
		"selection_top": selection_top,
		"selection_bottom": selection_bottom,
		"side_button_width": side_button_width,
		"side_button_height": side_button_height,
		"bottom_right_top": bottom_right_top,
		"bottom_right_bottom": bottom_right_bottom,
		"bottom_right_left": bottom_right_left,
		"bottom_right_right": bottom_right_right,
		"central_world_left": central_world_left,
		"central_world_right": central_world_right,
		"central_world_top": central_world_top,
		"central_world_bottom": central_world_bottom,
		"central_world_width": central_world_width,
		"central_world_height": central_world_height,
		"compact_labels": compact_labels,
		"top_bar_compact": top_bar_compact,
		"minimap_action_overlap": minimap_action_overlap,
		"selection_action_overlap": selection_action_overlap,
		"selection_minimap_overlap": selection_minimap_overlap,
		"selection_bottom_right_overlap": selection_bottom_right_overlap,
		"bottom_right_action_overlap": bottom_right_action_overlap,
		"action_game_controls_overlap": action_game_controls_overlap,
		"layout_pass": _layout_metrics_pass(
			button_width,
			minimap_action_overlap,
			selection_action_overlap,
			bottom_right_action_overlap,
			selection_minimap_overlap,
			selection_bottom_right_overlap,
			action_game_controls_overlap
		),
	}


func _selection_has_commands() -> bool:
	if _unit_command_container != null and _unit_command_container.visible and _unit_command_container.get_child_count() > 0:
		return true
	if queue_container != null and queue_container.visible and queue_container.get_child_count() > 0:
		return true
	if _train_buttons_container != null and _train_buttons_container.visible and _train_buttons_container.get_child_count() > 0:
		return true
	return _research_container != null and _research_container.visible and _research_container.get_child_count() > 0


func _layout_metrics_pass(
	button_width: float,
	minimap_action_overlap: bool,
	selection_action_overlap: bool,
	bottom_right_action_overlap: bool,
	selection_minimap_overlap: bool,
	selection_bottom_right_overlap: bool,
	action_game_controls_overlap: bool
) -> bool:
	if button_width < MOBILE_ACTION_MIN_BUTTON_WIDTH:
		return false
	if MOBILE_ACTION_BUTTON_HEIGHT < 48.0:
		return false
	return (
		not minimap_action_overlap
		and not selection_action_overlap
		and not bottom_right_action_overlap
		and not selection_minimap_overlap
		and not selection_bottom_right_overlap
		and not action_game_controls_overlap
	)


func _refresh_mobile_layout_profiles() -> void:
	if OS.has_feature("production"):
		return
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
	if control == null or not control.is_inside_tree():
		return {}
	if control.is_queued_for_deletion():
		return {}
	var disabled: bool = false
	if control is BaseButton:
		disabled = (control as BaseButton).disabled
	var size: Vector2 = control.size
	var screen_pos: Vector2 = _control_screen_position(control)
	var render_transform: Transform2D = control.get_viewport().get_final_transform() * control.get_global_transform_with_canvas()
	var rendered_size: Vector2 = Vector2(render_transform.x.length() * size.x, render_transform.y.length() * size.y)
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
		"render_surface_width": rendered_size.x,
		"render_surface_height": rendered_size.y,
		"render_surface_position": render_transform.origin,
		"coordinate_space": "width/height are logical; render_surface fields include the viewport's actual final transform and still require native density or browser CSS mapping",
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
	if OS.has_feature("production"):
		return
	# Layout refreshes are commonly deferred. A scene transition can win that
	# race, so do not inspect controls after this CanvasLayer leaves the tree.
	if not is_inside_tree():
		return
	var diag: Dictionary = {}
	diag["timestamp_ms"] = Time.get_ticks_msec()
	diag["build_menu_open"] = _build_menu_open
	diag["ui_modal_state"] = _ui_modal_state
	diag["build_button"] = _control_touch_diag(build_menu_button, "build_button")
	diag["age_up_button"] = _control_touch_diag(age_up_button, "age_up_button")
	diag["pause_button"] = _control_touch_diag(_pause_button, "pause_button")
	diag["speed_button"] = _control_touch_diag(_speed_button, "speed_button")
	diag["guidance_dismiss_button"] = _control_touch_diag(_guidance_dismiss_button, "guidance_dismiss")
	diag["mobile_action_panel"] = _control_touch_diag(_mobile_action_panel, "mobile_action_panel")
	diag["placement_confirm_button"] = _control_touch_diag(_placement_confirm_button, "placement_confirm_button")
	diag["placement_preview_valid"] = _placement_preview_valid
	diag["home_button"] = _control_touch_diag(_town_center_button, "home_button")
	diag["camera_zoom_buttons"] = _collect_button_diags(_camera_controls, "camera_zoom")
	diag["camera_zoom_controls"] = _control_touch_diag(_camera_controls, "camera_zoom_controls")
	diag["camera_view_button"] = _control_touch_diag(_camera_view_button, "camera_view")
	diag["camera_controls_expanded"] = _camera_controls_expanded
	diag["selection_back_button"] = _control_touch_diag(_selection_back_button, "selection_back")
	diag["selection_context"] = _selection_kind
	diag["camera_zoom"] = _camera_zoom_current
	diag["match_population_limit"] = _match_population_limit
	diag["match_population_label"] = _match_population_label.text if _match_population_label else ""
	diag["advanced_command_buttons"] = _collect_button_diags(_advanced_command_container, "advanced_command")
	diag["placement_cancel_button"] = _control_touch_diag(_placement_cancel_button, "placement_cancel_button")
	diag["mobile_action_buttons"] = _collect_button_diags(_mobile_action_strip, "mobile_action")
	diag["unit_command_buttons"] = _collect_button_diags(_unit_command_container, "unit_command")
	diag["queue_cancel_buttons"] = _collect_button_diags(queue_container, "queue_cancel")
	diag["train_buttons"] = _collect_button_diags(_train_buttons_container, "train")
	diag["repeat_training_button"] = _control_touch_diag(_auto_queue_button, "repeat_training")
	diag["repeat_training_enabled"] = _auto_queue_button.button_pressed if _auto_queue_button else false
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
	if _match_population_label:
		_match_population_label.visible = not compact
	if compact == _top_bar_compact:
		return
	_top_bar_compact = compact
	top_bar.custom_minimum_size = Vector2(0, 40) if compact else Vector2(0, 48)
	top_bar_hbox.add_theme_constant_override("separation", 8 if compact else 14)
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
	_update_age_display()


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
	_refresh_score_visibility(get_viewport().get_visible_rect().size)
	if _speed_button:
		_speed_button.modulate = Color(0.72, 0.72, 0.72, 0.8) if active else Color.WHITE
	if _guidance_dismiss_button:
		_guidance_dismiss_button.visible = active
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
	var visibility_changed: bool = _progression_hint_panel.visible != (trimmed != "")
	_progression_hint_panel.visible = trimmed != ""
	if visibility_changed:
		_queue_mobile_layout_refresh()
	if trimmed == "":
		return
	_progression_hint_label.text = trimmed
	var color: Color = Color(0.95, 0.92, 0.82)
	if emphasis:
		color = Color(1.0, 0.9, 0.45)
	_progression_hint_label.add_theme_color_override("font_color", color)
	var style: StyleBoxFlat = KingdomTheme.panel_style()
	style.border_color = KingdomTheme.AMBER if emphasis else KingdomTheme.BORDER
	style.set_border_width_all(2 if emphasis else 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(3)
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
	minimap_bg.color = KingdomTheme.INK_PANEL

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
		minimap_bg.color = Color(0.16, 0.13, 0.055, 0.92)

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


func dismiss_build_menu_for_placement() -> void:
	# Choosing a building changes from a modal menu to world placement.  This
	# must not emit build_menu_toggled(false), because the normal close path also
	# cancels placement in Main.  Keep the Build button ready to reopen the menu
	# while the dedicated bottom-bar Cancel button represents placement state.
	_build_menu_open = false
	build_menu_button.text = "Build"
	if _ui_modal_state == UIModalState.BUILD_MENU:
		set_ui_modal_state(UIModalState.NONE)
	_refresh_touch_target_diagnostics()


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
	var names: PackedStringArray = ["Food", "Wood", "Gold"]
	var values: Array[int] = [food, wood, gold]
	var labels: Array[Label] = [food_label, wood_label, gold_label]
	for index: int in 3:
		labels[index].text = "%s: %s" % [names[index], _compact_resource_amount(values[index])]
		labels[index].tooltip_text = "%s: %d" % [names[index], values[index]]
	# Measure the rendered font widths, including population, age and clock.
	# Full resource names stay visible whenever the actual safe corridor fits.
	var required_width: float = 0.0
	var visible_labels: Array[Label] = [food_label, wood_label, gold_label, pop_label, age_label, game_time_label]
	if _match_population_label and _match_population_label.visible:
		visible_labels.append(_match_population_label)
	for label: Label in visible_labels:
		required_width += label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	required_width += float(visible_labels.size() - 1) * float(top_bar_hbox.get_theme_constant("separation"))
	_resource_labels_abbreviated = required_width > _top_bar_safe_width - 136.0
	if _resource_labels_abbreviated:
		for index: int in 3:
			labels[index].text = "%s %s" % [names[index].left(1), _compact_resource_amount(values[index])]
	update_population(_population_current, _population_cap)


func _compact_resource_amount(value: int) -> String:
	if not _top_bar_compact or value < 10000:
		return str(value)
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 100000:
		return "%dk" % (value / 1000)
	return "%.1fk" % (float(value) / 1000.0)


func update_population(current: int, cap: int) -> void:
	_population_current = current
	_population_cap = cap
	if _resource_labels_abbreviated:
		pop_label.text = "P %d/%d" % [current, cap]
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
			var cost: Dictionary = gm.get_age_up_cost(0, age + 1)
			age_up_button.text = "Age Up" if _top_bar_compact else "Age Up (%dF %dG)" % [int(cost.get("food", 0)), int(cost.get("gold", 0))]
			age_up_button.tooltip_text = _get_age_up_preview(age + 1)
			age_up_button.disabled = false
		elif age == 2:
			var cost: Dictionary = gm.get_age_up_cost(0, age + 1)
			age_up_button.text = "Age Up" if _top_bar_compact else "Age Up (%dF %dG)" % [int(cost.get("food", 0)), int(cost.get("gold", 0))]
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
	if gm:
		var cost: Dictionary = gm.get_age_up_cost(0, next_age)
		lines.append("%d food · %d gold" % [int(cost.get("food", 0)), int(cost.get("gold", 0))])
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
	# Main refreshes selected units every 0.5 seconds. Keep the existing
	# command row alive during a unit refresh so a held GUI tap can release.
	# configure_unit_commands() applies the current selection's authority.
	if _selection_kind != "unit":
		_hide_unit_commands()
	_selection_context_active = true
	_selection_kind = "unit"
	selection_panel.visible = not _placement_mode_active and _ui_modal_state != UIModalState.BUILD_MENU
	if count > 1 and unit_name in ["Army", "Units"]:
		selection_name.text = "%s · %d" % [unit_name, count]
	elif count > 1:
		selection_name.text = "%dx %s" % [count, unit_name]
	else:
		selection_name.text = unit_name
	_selection_full_name = selection_name.text
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
			stats_line = " | ".join(parts)
	selection_name.tooltip_text = "%s\n%s\n%s" % [_selection_full_name, stats_line, action_text]
	_selection_action_text = action_text.capitalize()
	_selection_cargo_text = ""
	if int(unit_stats.get("cargo_amount", 0)) > 0:
		_selection_cargo_text = "%s %d/%d" % [str(unit_stats.get("cargo_resource", "mixed")).capitalize(), int(unit_stats["cargo_amount"]), int(unit_stats.get("cargo_capacity", 0))]
	_selection_role_text = ""
	var selected_type: int = int(unit_stats.get("unit_type", -1))
	if selected_type < 0:
		for candidate_type: int in UnitData.UNITS:
			if UnitData.get_unit_name(candidate_type) == unit_name:
				selected_type = candidate_type
				break
	if unit_stats.has("role_counts"):
		selected_type = -1
	_selection_is_worker = selected_type == UnitData.UnitType.VILLAGER
	if selected_type >= 0:
		_selection_role_text = UnitData.get_unit_counter_description(selected_type)
	if unit_stats.has("role_counts") and selected_type < 0:
		var role_parts: PackedStringArray = []
		for role_type: int in unit_stats["role_counts"]:
			var short_name: String = UnitData.get_unit_name(role_type).left(3)
			role_parts.append("%s %d" % [short_name, int(unit_stats["role_counts"][role_type])])
		_selection_role_text = " · ".join(role_parts)
	_refresh_unit_selection_details()
	queue_container.visible = false
	_last_queue_items = []
	_queue_counts_by_unit.clear()
	_selected_building_ref = null
	if _train_buttons_container:
		_train_buttons_container.visible = false
	if _research_container:
		_research_container.visible = false
	_queue_mobile_layout_refresh()


func show_building_selection(building_name: String, current_hp: int, max_hp: int, queue_items: Array, trainable_units: Array = [], building_ref: Node2D = null) -> void:
	_close_advanced_commands()
	if _ui_modal_state == UIModalState.PAUSE_MENU:
		return
	_hide_unit_commands()
	_selection_context_active = true
	_selection_kind = "building"
	_selection_is_worker = false
	selection_panel.visible = not _placement_mode_active and _ui_modal_state != UIModalState.BUILD_MENU
	selection_name.text = building_name
	_selection_full_name = building_name
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
	selection_name.tooltip_text = "%s\n%s" % [building_name, " | ".join(detail_parts)]
	selection_details.tooltip_text = " | ".join(detail_parts)
	selection_details.text = _building_purpose(building_ref)
	_selected_building_ref = building_ref
	var has_command_authority: bool = _is_human_owned_building(building_ref)
	var visible_queue: Array = queue_items if has_command_authority else []
	var visible_trainable: Array = trainable_units if has_command_authority else []
	_last_queue_items = visible_queue.duplicate(true)
	if building_ref is BuildingBase and (building_ref as BuildingBase).building_type == BuildingData.BuildingType.TOWN_CENTER:
		for item: Dictionary in visible_queue:
			if bool(item.get("is_training", false)):
				selection_details.text += "\n%s %d%%" % [str(item.get("name", "Training")), int(float(item.get("progress", 0.0)) * 100.0)]
				break
	_update_queue_display(visible_queue)
	_update_train_buttons(visible_trainable)
	_update_research_buttons(building_ref if has_command_authority else null)
	_queue_mobile_layout_refresh()


func _is_human_owned_building(building_ref: Node2D) -> bool:
	return (
		building_ref != null
		and is_instance_valid(building_ref)
		and building_ref is BuildingBase
		and (building_ref as BuildingBase).player_owner == 0
	)


func show_resource_info(type_name: String, remaining: int, total: int, pct: int) -> void:
	_close_advanced_commands()
	if _ui_modal_state == UIModalState.PAUSE_MENU:
		return
	_hide_unit_commands()
	_selection_context_active = true
	_selection_kind = "resource"
	_selection_is_worker = false
	selection_panel.visible = not _placement_mode_active and _ui_modal_state != UIModalState.BUILD_MENU
	selection_name.text = "%s Resource" % type_name
	_selection_full_name = selection_name.text
	selection_hp_bar.max_value = total
	selection_hp_bar.value = remaining
	_update_hp_bar_color(remaining, total)
	selection_details.text = "%d / %d\n%d%% remaining" % [remaining, total, pct]
	queue_container.visible = false
	_last_queue_items = []
	_queue_counts_by_unit.clear()
	_selected_building_ref = null
	if _train_buttons_container:
		_train_buttons_container.visible = false
	if _research_container:
		_research_container.visible = false
	_queue_mobile_layout_refresh()


func _update_selection_name_layout(available_width: float) -> void:
	if _selection_full_name.is_empty():
		return
	selection_name.text = _selection_full_name
	var font: Font = selection_name.get_theme_font("font")
	var font_size: int = selection_name.get_theme_font_size("font_size")
	if font.get_string_size(selection_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available_width:
		var split_index: int = _selection_full_name.rfind(" ")
		if split_index > 0:
			selection_name.text = _selection_full_name.left(split_index) + "\n" + _selection_full_name.substr(split_index + 1)


func _refresh_unit_selection_details() -> void:
	if _selection_kind != "unit":
		return
	var action: String = _selection_action_text
	if _unit_command_mode == "move":
		action = "Tap to move"
	elif _unit_command_mode == "attack_move":
		action = "Tap attack-move"
	elif _unit_command_mode == "patrol":
		action = "Tap to patrol"
	# Cargo is useful worker information, but fits its own complete line.
	var cargo_start: int = action.find(" (")
	if not _selection_cargo_text.is_empty() and _selection_is_worker:
		selection_details.text = action + "\nCargo " + _selection_cargo_text
	elif cargo_start >= 0 and _selection_role_text.is_empty():
		selection_details.text = action.left(cargo_start) + "\nCargo " + action.substr(cargo_start + 2).trim_suffix(")")
	else:
		selection_details.text = action + ("\n" + _selection_role_text if not _selection_role_text.is_empty() else "")


func _building_purpose(building_ref: Node2D) -> String:
	if not building_ref is BuildingBase:
		return ""
	var building: BuildingBase = building_ref as BuildingBase
	if building.state == BuildingBase.State.CONSTRUCTING:
		# A stopped foundation cannot make progress without an accepted Build
		# order. Keep travel and protective recovery assigned; never infer enemy
		# labor behind fog from this human construction hint.
		if building.player_owner == 0 and not _has_foundation_builder(building):
			return "Needs builder"
		return "Building %d%%" % int(building.build_progress * 100.0)
	match building.building_type:
		BuildingData.BuildingType.TOWN_CENTER: return "Arrows + depot" if building.tower_attack_damage > 0 else "All drop-off"
		BuildingData.BuildingType.HOUSE: return "+%d housing" % int(BuildingData.BUILDINGS[building.building_type].get("pop_provided", 0))
		BuildingData.BuildingType.MILL: return "Food drop-off"
		BuildingData.BuildingType.LUMBER_CAMP: return "Wood drop-off"
		BuildingData.BuildingType.MINING_CAMP: return "Gold drop-off"
		BuildingData.BuildingType.FARM: return "Produces food"
		BuildingData.BuildingType.BARRACKS: return "Trains Warriors"
		BuildingData.BuildingType.ARCHERY_RANGE: return "Trains Archers"
		BuildingData.BuildingType.STABLE: return "Trains Horsemen"
		BuildingData.BuildingType.BLACKSMITH: return "Army upgrades"
		BuildingData.BuildingType.WATCH_TOWER: return "Base defence"
	return ""


func _has_foundation_builder(building: BuildingBase) -> bool:
	for candidate: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion() or not candidate is Villager:
			continue
		var worker: Villager = candidate as Villager
		if worker.player_owner != building.player_owner or worker.current_state == UnitBase.State.DEAD:
			continue
		if worker.build_target != building:
			continue
		# Build travel itself stays BUILDING. Manual Move keeps stale target
		# memory but cancels that work; only recovery's MOVING preserves it.
		if worker.has_active_build_order():
			return true
	return false


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
	_close_advanced_commands()
	_selection_context_active = false
	_selection_kind = "none"
	_selection_is_worker = false
	_hide_unit_commands()
	selection_panel.visible = false
	_selected_building_ref = null
	_last_queue_items = []
	_queue_counts_by_unit.clear()
	if _train_buttons_container:
		_train_buttons_container.visible = false
	if _research_container:
		_research_container.visible = false
	_queue_mobile_layout_refresh()


func _update_queue_display(queue_items: Array) -> void:
	_last_queue_items = queue_items.duplicate(true)
	_queue_counts_by_unit.clear()
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

	var queue_units: Array[int] = []
	for raw_unit_type: Variant in _queue_counts_by_unit.keys():
		queue_units.append(int(raw_unit_type))
	queue_units.sort()
	var desired_names: Dictionary = {}
	var compact_training: bool = _selected_building_ref is BuildingBase and (_selected_building_ref as BuildingBase).building_type == BuildingData.BuildingType.TOWN_CENTER and minf(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y) <= 520.0
	queue_container.add_theme_constant_override("separation", 4 if compact_training else 6)
	if training_label != "" and not compact_training:
		desired_names["QueueTrainingChip"] = true
	for unit_type: int in queue_units:
		desired_names["QueueUnit_%s" % str(unit_type)] = true
	if not queue_items.is_empty():
		desired_names["QueueClearLastButton"] = true
		desired_names["QueueClearAllButton"] = true
	# Keep matching controls alive across Main's 0.5-second selection refresh.
	# Besides preserving an in-progress tap, stable grouped-unit handlers resolve
	# their current queue index at release instead of retaining a stale index.
	for child: Node in queue_container.get_children():
		if child.is_queued_for_deletion():
			continue
		if not desired_names.has(String(child.name)):
			_retire_dynamic_control(child)

	if queue_items.is_empty():
		queue_container.visible = false
		_refresh_touch_target_diagnostics()
		return

	queue_container.visible = true
	var child_index := 0

	if training_label != "" and not compact_training:
		var training_chip: Label = queue_container.get_node_or_null("QueueTrainingChip") as Label
		if training_chip == null:
			training_chip = Label.new()
			training_chip.name = "QueueTrainingChip"
			queue_container.add_child(training_chip)
		training_chip.visible = true
		training_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		training_chip.text = "TRAIN\n%s" % training_label
		training_chip.add_theme_font_size_override("font_size", 12)
		training_chip.add_theme_color_override("font_color", Color(0.95, 0.88, 0.66))
		training_chip.custom_minimum_size = Vector2(132, 48)
		training_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		queue_container.move_child(training_chip, child_index)
		child_index += 1

	for unit_type: int in queue_units:
		var queue_count: int = int(_queue_counts_by_unit.get(unit_type, 0))
		if queue_count <= 0:
			continue
		var button_name := "QueueUnit_%s" % str(unit_type)
		var btn: Button = queue_container.get_node_or_null(NodePath(button_name)) as Button
		if btn == null:
			btn = Button.new()
			btn.name = button_name
			btn.set_meta("unit_type", unit_type)
			btn.pressed.connect(_on_cancel_queued_unit_pressed.bind(unit_type))
			queue_container.add_child(btn)
		btn.visible = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.text = "%s x%d" % [UnitData.get_unit_name(unit_type), queue_count]
		btn.tooltip_text = "Cancel first queued %s" % UnitData.get_unit_name(unit_type)
		btn.custom_minimum_size = Vector2(80 if compact_training else 104, 48)
		btn.add_theme_font_size_override("font_size", 12)
		for style_name: String in ["normal", "hover", "pressed", "disabled"]:
			var queue_style: StyleBox = btn.get_theme_stylebox(style_name).duplicate()
			queue_style.set_content_margin(SIDE_LEFT, 6.0 if compact_training else 12.0)
			queue_style.set_content_margin(SIDE_RIGHT, 6.0 if compact_training else 12.0)
			btn.add_theme_stylebox_override(style_name, queue_style)
		queue_container.move_child(btn, child_index)
		child_index += 1

	var clear_last: Button = queue_container.get_node_or_null("QueueClearLastButton") as Button
	if clear_last == null:
		clear_last = Button.new()
		clear_last.name = "QueueClearLastButton"
		clear_last.pressed.connect(_on_clear_last_queue_pressed)
		queue_container.add_child(clear_last)
	clear_last.visible = true
	clear_last.mouse_filter = Control.MOUSE_FILTER_STOP
	clear_last.text = "Undo"
	clear_last.tooltip_text = "Cancel last queued unit"
	clear_last.custom_minimum_size = Vector2(60 if compact_training else 64, 48)
	clear_last.add_theme_font_size_override("font_size", 14 if compact_training else 16)
	queue_container.move_child(clear_last, child_index)
	child_index += 1

	var clear_all: Button = queue_container.get_node_or_null("QueueClearAllButton") as Button
	if clear_all == null:
		clear_all = Button.new()
		clear_all.name = "QueueClearAllButton"
		clear_all.pressed.connect(_on_clear_all_queue_pressed)
		queue_container.add_child(clear_all)
	clear_all.visible = true
	clear_all.mouse_filter = Control.MOUSE_FILTER_STOP
	clear_all.text = "Clear"
	clear_all.tooltip_text = "Cancel all queued units"
	clear_all.custom_minimum_size = Vector2(60 if compact_training else 64, 48)
	clear_all.add_theme_font_size_override("font_size", 14 if compact_training else 16)
	queue_container.move_child(clear_all, child_index)

	if _ui_modal_state == UIModalState.BUILD_MENU:
		queue_container.visible = false
	_refresh_touch_target_diagnostics()


func _on_cancel_queue_pressed(index: int) -> void:
	if _is_human_owned_building(_selected_building_ref):
		cancel_queue_requested.emit(_selected_building_ref, index)


func _on_cancel_queued_unit_pressed(unit_type: int) -> void:
	# The queue may advance or reorder while the user is holding the button.
	# Resolve the first currently queued (non-training) unit of this type now.
	for index in range(_last_queue_items.size()):
		var item: Variant = _last_queue_items[index]
		if not (item is Dictionary) or bool((item as Dictionary).get("is_training", false)):
			continue
		if int((item as Dictionary).get("unit_type", -1)) == unit_type:
			_on_cancel_queue_pressed(index)
			return


func _on_clear_last_queue_pressed() -> void:
	if _last_queue_items.is_empty():
		return
	_on_cancel_queue_pressed(_last_queue_items.size() - 1)


func _on_clear_all_queue_pressed() -> void:
	if _last_queue_items.is_empty():
		return
	for i in range(_last_queue_items.size() - 1, -1, -1):
		_on_cancel_queue_pressed(i)


func _is_town_center_production_context() -> bool:
	return (
		is_instance_valid(_selected_building_ref)
		and _is_human_owned_building(_selected_building_ref)
		and _selected_building_ref is BuildingBase
		and (_selected_building_ref as BuildingBase).building_type == BuildingData.BuildingType.TOWN_CENTER
		and _train_buttons_container != null
		and _train_buttons_container.visible
	)


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
			# Recruiting stays at the start of the shelf as the queue grows.
			parent_vbox.move_child(_train_buttons_container, 0)
			_queue_page_spacer = Control.new()
			_queue_page_spacer.name = "QueuePageSpacer"
			_queue_page_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent_vbox.add_child(_queue_page_spacer)
			parent_vbox.move_child(_queue_page_spacer, 1)
			_queue_hint_label = Label.new()
			_queue_hint_label.name = "QueueSwipeHint"
			_queue_hint_label.text = "Swipe for queue"
			_queue_hint_label.add_theme_font_size_override("font_size", 11)
			_queue_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			get_node("Root").add_child(_queue_hint_label)
			_queue_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)

	# Reconcile by stable names instead of rebuilding the row on every selection
	# refresh. Main refreshes a selected production building every 0.5 seconds;
	# replacing a Button between touch-down and touch-up cancels that tap.
	var desired_unit_types: Array[int] = []
	for raw_unit_type: Variant in trainable_units:
		var unit_type := int(raw_unit_type)
		if unit_type not in desired_unit_types:
			desired_unit_types.append(unit_type)
	var production_queue: Node = null
	if _is_human_owned_building(_selected_building_ref) and _selected_building_ref.has_method("get_production_queue"):
		production_queue = _selected_building_ref.get_production_queue()
	var desired_names: Dictionary = {}
	for unit_type: int in desired_unit_types:
		desired_names["TrainButton_%s" % str(unit_type)] = true
	if production_queue != null:
		desired_names["AutoQueueButton"] = true
	for child: Node in _train_buttons_container.get_children():
		if child.is_queued_for_deletion():
			continue
		if not desired_names.has(String(child.name)):
			if child == _auto_queue_button:
				_auto_queue_button = null
			_retire_dynamic_control(child)

	if desired_unit_types.is_empty():
		_train_buttons_container.visible = false
		var viewport_size_empty: Vector2 = get_viewport().get_visible_rect().size
		apply_mobile_layout(viewport_size_empty, _get_safe_area_rect(viewport_size_empty))
		_refresh_touch_target_diagnostics()
		return

	_train_buttons_container.visible = true
	var viewport_size_for_cards: Vector2 = get_viewport().get_visible_rect().size
	var compact_town_center: bool = _is_town_center_production_context() and minf(viewport_size_for_cards.x, viewport_size_for_cards.y) <= 520.0
	_train_buttons_container.add_theme_constant_override("separation", 3 if compact_town_center else 8)
	var child_index := 0
	for ut: int in desired_unit_types:
		var unit_name: String = UnitData.get_unit_name(ut)
		var cost: Dictionary = UnitData.get_unit_cost(ut)
		var stats: Dictionary = UnitData.UNITS.get(ut, {})
		var train_time: float = stats.get("build_time", 15.0)
		var cost_parts: PackedStringArray = []
		for resource: String in ["food", "wood", "gold"]:
			if int(cost.get(resource, 0)) > 0:
				cost_parts.append("%d %s" % [int(cost[resource]), resource])
		var cost_str: String = " · ".join(cost_parts)
		var queue_badge: String = ""
		var queue_count: int = int(_queue_counts_by_unit.get(ut, 0))
		if queue_count > 0:
			queue_badge = " x%d" % queue_count
		var button_name := "TrainButton_%s" % str(ut)
		var btn: Button = _train_buttons_container.get_node_or_null(NodePath(button_name)) as Button
		if btn == null:
			btn = Button.new()
			btn.name = button_name
			btn.set_meta("unit_type", ut)
			btn.pressed.connect(_on_train_button_pressed.bind(ut))
			_train_buttons_container.add_child(btn)
		btn.visible = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var role_text: String = UnitData.get_unit_counter_description(ut) if ut != UnitData.UnitType.VILLAGER else ""
		btn.text = "%s%s\n%s%s" % [unit_name, queue_badge, cost_str, "\n" + role_text if not role_text.is_empty() else ""]
		btn.custom_minimum_size = Vector2(80 if ut == UnitData.UnitType.VILLAGER else 108, 48) if compact_town_center else Vector2(130, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER if compact_town_center else HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11 if not role_text.is_empty() else 13)
		for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.remove_theme_stylebox_override(style_name)
			if compact_town_center or not role_text.is_empty():
				var style: StyleBoxFlat = btn.get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
				style.set_content_margin(SIDE_LEFT, 4.0)
				style.set_content_margin(SIDE_RIGHT, 4.0)
				style.set_content_margin(SIDE_TOP, 4.0)
				style.set_content_margin(SIDE_BOTTOM, 4.0)
				btn.add_theme_stylebox_override(style_name, style)
		var icon_path: String = UnitData.get_unit_icon_path(ut)
		if compact_town_center:
			btn.icon = null
		elif icon_path != "" and ResourceLoader.exists(icon_path):
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
		_train_buttons_container.move_child(btn, child_index)
		child_index += 1

	# Repeat training is a normal, fully bounded toggle. A CheckButton's
	# separate indicator can fall outside this horizontally scrolling shelf.
	if production_queue != null:
		if _auto_queue_button == null or not is_instance_valid(_auto_queue_button) or _auto_queue_button.get_parent() != _train_buttons_container:
			_auto_queue_button = _train_buttons_container.get_node_or_null("AutoQueueButton") as Button
		if _auto_queue_button == null:
			_auto_queue_button = Button.new()
			_auto_queue_button.name = "AutoQueueButton"
			_auto_queue_button.toggle_mode = true
			_auto_queue_button.toggled.connect(_on_auto_queue_toggled)
			_train_buttons_container.add_child(_auto_queue_button)
		_auto_queue_button.visible = true
		_auto_queue_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_auto_queue_button.custom_minimum_size = Vector2(96 if compact_town_center else 104, 48)
		_auto_queue_button.add_theme_font_size_override("font_size", 13 if compact_town_center else 14)
		for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var repeat_style: StyleBoxFlat = _auto_queue_button.get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
			repeat_style.set_content_margin(SIDE_LEFT, 4.0)
			repeat_style.set_content_margin(SIDE_RIGHT, 4.0)
			_auto_queue_button.add_theme_stylebox_override(style_name, repeat_style)
		_refresh_auto_queue_button(production_queue)
		_train_buttons_container.move_child(_auto_queue_button, child_index)
	else:
		_auto_queue_button = null
	if _ui_modal_state == UIModalState.BUILD_MENU:
		_train_buttons_container.visible = false
	_refresh_primary_action_visuals()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))
	call_deferred("_refresh_touch_target_diagnostics")


func _layout_queue_page() -> void:
	if _queue_page_spacer == null:
		return
	var has_queue_page: bool = _train_buttons_container.visible and queue_container.visible and selection_panel.visible
	_queue_page_spacer.visible = has_queue_page
	_queue_hint_label.visible = has_queue_page
	if has_queue_page:
		# The queue begins on the next scroll page, so the initial shelf never
		# displays half a TRAIN label or half a cancellation button.
		var gap_width: float = maxf(0.0, command_scroll.size.x - _train_buttons_container.get_combined_minimum_size().x - 12.0)
		_queue_page_spacer.custom_minimum_size.x = gap_width


func _on_train_button_pressed(unit_type: int) -> void:
	AudioManager.play_ui("button_click")
	if not OS.has_feature("production"):
		train_action_diagnostics = {
			"timestamp_ms": Time.get_ticks_msec(),
			"unit_type": unit_type,
			"building_path": str(_selected_building_ref.get_path()) if _selected_building_ref and is_instance_valid(_selected_building_ref) else "",
			"request_emitted": false,
		}
	if _is_human_owned_building(_selected_building_ref):
		if not OS.has_feature("production"):
			train_action_diagnostics["request_emitted"] = true
		train_unit_requested.emit(_selected_building_ref, unit_type)


func _refresh_auto_queue_button(production_queue: Node) -> void:
	if _auto_queue_button == null or production_queue == null:
		return
	var unit_type: int = int(production_queue.get("auto_queue_unit_type"))
	var enabled: bool = bool(production_queue.get("auto_queue_enabled"))
	_auto_queue_button.set_pressed_no_signal(enabled)
	_auto_queue_button.set_meta("repeat_unit_type", unit_type)
	_auto_queue_button.disabled = unit_type < 0 or _ui_modal_state == UIModalState.PAUSE_MENU
	if unit_type < 0:
		_auto_queue_button.text = "Train first\nRepeat · OFF"
		_auto_queue_button.tooltip_text = "Queue a unit first, then turn on repeat training for that unit."
		_auto_queue_button.icon = null
	else:
		var unit_name: String = UnitData.get_unit_name(unit_type)
		_auto_queue_button.text = "%s\nRepeat · %s" % [unit_name, "ON" if enabled else "OFF"]
		_auto_queue_button.tooltip_text = "Keep training %s after each completion while resources and population room allow. The last unit you queue is the one repeated." % unit_name
		_auto_queue_button.icon = null
	if enabled:
		KingdomTheme.apply_primary(_auto_queue_button)
	else:
		KingdomTheme.apply_secondary(_auto_queue_button)
		_auto_queue_button.add_theme_color_override("font_hover_color", KingdomTheme.PARCHMENT)
		_auto_queue_button.add_theme_color_override("font_focus_color", KingdomTheme.PARCHMENT)
	_refresh_touch_target_diagnostics()


func _on_auto_queue_toggled(pressed: bool) -> void:
	if _is_human_owned_building(_selected_building_ref):
		var pq: Node = _selected_building_ref.get_production_queue() if _selected_building_ref.has_method("get_production_queue") else null
		if pq:
			pq.auto_queue_enabled = pressed
			_refresh_auto_queue_button(pq)
			var unit_type: int = int(pq.get("auto_queue_unit_type"))
			var unit_name: String = UnitData.get_unit_name(unit_type) if unit_type >= 0 else "unit"
			show_notification(
				"Repeat %s %s" % [unit_name, "ON" if pressed else "OFF"],
				KingdomTheme.AMBER if pressed else KingdomTheme.MUTED
			)


func _retire_dynamic_control(child: Node) -> void:
	# A Button can synchronously trigger a HUD refresh from its pressed signal.
	# Keep it inside the SceneTree until the input dispatch has unwound; removing
	# it immediately makes BaseButton call can_process() on an orphaned node.
	if child == null or child.is_queued_for_deletion():
		return
	if child is Control:
		(child as Control).visible = false
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Move the old name out of the reconciliation namespace so a second refresh
	# in this frame can safely create a replacement before queue_free runs.
	child.name = "RetiredControl_%d" % child.get_instance_id()
	child.queue_free()


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
		_research_container = HBoxContainer.new()
		_research_container.name = "ResearchButtons"
		_research_container.add_theme_constant_override("separation", 6)
		var parent_vbox: Control = queue_container.get_parent()
		if parent_vbox:
			parent_vbox.add_child(_research_container)

	# Only show for Blacksmith
	var b: BuildingBase = building_ref as BuildingBase if building_ref is BuildingBase else null
	var valid_blacksmith: bool = (
		b != null
		and is_instance_valid(b)
		and b.player_owner == 0
		and b.building_type == BuildingData.BuildingType.BLACKSMITH
		and b.state == BuildingBase.State.ACTIVE
	)
	var desired_names: Dictionary = {}
	if valid_blacksmith:
		for research_def: Dictionary in RESEARCH_DEFS:
			desired_names["ResearchButton_%s" % str(research_def["id"])] = true
	for child: Node in _research_container.get_children():
		if child.is_queued_for_deletion():
			continue
		if not desired_names.has(String(child.name)):
			_retire_dynamic_control(child)

	if not valid_blacksmith:
		_research_container.visible = false
		_refresh_touch_target_diagnostics()
		return

	_research_container.visible = true
	var gm: Node = _get_game_manager()
	var child_index := 0
	for rd: Dictionary in RESEARCH_DEFS:
		var research_id := String(rd["id"])
		var button_name := "ResearchButton_%s" % research_id
		var btn: Button = _research_container.get_node_or_null(NodePath(button_name)) as Button
		if btn == null:
			btn = Button.new()
			btn.name = button_name
			btn.set_meta("research_id", research_id)
			btn.pressed.connect(_on_research_pressed.bind(research_id))
			_research_container.add_child(btn)
		btn.visible = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var cost_str := ""
		if rd["cost"].get("food", 0) > 0:
			cost_str += "F:%d " % rd["cost"]["food"]
		if rd["cost"].get("wood", 0) > 0:
			cost_str += "W:%d " % rd["cost"]["wood"]
		if rd["cost"].get("gold", 0) > 0:
			cost_str += "G:%d" % rd["cost"]["gold"]
		btn.text = "%s\n%s  %s" % [rd["name"], rd["desc"], cost_str.strip_edges()]
		btn.custom_minimum_size = Vector2(154, 48)
		btn.add_theme_font_size_override("font_size", 12)
		var already_done: bool = false
		if gm and gm.has_method("has_research"):
			already_done = gm.has_research(b.player_owner, research_id)
		if already_done:
			btn.text += " [DONE]"
		btn.disabled = already_done
		_research_container.move_child(btn, child_index)
		child_index += 1
	_queue_mobile_layout_refresh()
	_refresh_touch_target_diagnostics()


func _on_research_pressed(research_id: String) -> void:
	if _is_human_owned_building(_selected_building_ref):
		research_requested.emit(_selected_building_ref, research_id)


# --- Build menu toggle ---

func _on_build_menu_pressed() -> void:
	if _ui_modal_state == UIModalState.PAUSE_MENU:
		return
	AudioManager.play_ui("button_click")
	_build_menu_open = !_build_menu_open
	build_menu_toggled.emit(_build_menu_open)
	build_menu_button.text = "X" if _build_menu_open else "Build"


# --- Age up ---

func _on_age_up_pressed() -> void:
	AudioManager.play_ui("age_up")
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
					color = Color(0.025, 0.045, 0.04)
				elif fog_state == MapData.FogState.EXPLORED:
					color = color.darkened(0.28)
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

	# Project all four world corners. A world rectangle is a quadrilateral in
	# the tile grid; projecting only its diagonal collapses it into a stripe.
	if camera_rect.size.x > 0 and camera_rect.size.y > 0:
		var corners: Array[Vector2] = [camera_rect.position, Vector2(camera_rect.end.x, camera_rect.position.y), camera_rect.end, Vector2(camera_rect.position.x, camera_rect.end.y)]
		for index: int in 4:
			_draw_minimap_camera_edge(_world_to_minimap_point(corners[index]), _world_to_minimap_point(corners[(index + 1) % 4]), map_w, map_h)

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


func _world_to_minimap_point(world_pos: Vector2) -> Vector2:
	var game_map: Node = get_node_or_null("../GameMap")
	if game_map and game_map.has_method("world_to_tile"):
		return Vector2(game_map.call("world_to_tile", world_pos))
	return Vector2(_world_to_tile_minimap(world_pos))


func _draw_minimap_camera_edge(start: Vector2, end: Vector2, map_width: int, map_height: int) -> void:
	var steps: int = maxi(1, ceili(maxf(absf(end.x - start.x), absf(end.y - start.y))))
	for step: int in range(steps + 1):
		var point: Vector2i = Vector2i(start.lerp(end, float(step) / float(steps)).round())
		if point.x >= 0 and point.x < map_width and point.y >= 0 and point.y < map_height:
			_minimap_image.set_pixel(point.x, point.y, Color(0.92, 0.96, 1.0))


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
	var tile_x: int = clampi(int(nx * MapData.MAP_WIDTH), 0, MapData.MAP_WIDTH - 1)
	var tile_y: int = clampi(int(ny * MapData.MAP_HEIGHT), 0, MapData.MAP_HEIGHT - 1)
	var game_map: Node = get_node_or_null("../GameMap")
	if game_map and game_map.has_method("tile_to_world"):
		minimap_clicked.emit(game_map.call("tile_to_world", Vector2i(tile_x, tile_y)))
		return
	# Convert tile to world using isometric formula
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	var wx: float = (tile_x - tile_y) * half_w
	var wy: float = (tile_x + tile_y) * half_h
	minimap_clicked.emit(Vector2(wx, wy))


func _world_to_tile_minimap(world_pos: Vector2) -> Vector2i:
	var game_map: Node = get_node_or_null("../GameMap")
	if game_map and game_map.has_method("world_to_tile"):
		return game_map.call("world_to_tile", world_pos)
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
	_notification_container.offset_right = 232
	_notification_container.offset_bottom = 188
	_notification_container.add_theme_constant_override("separation", 2)
	_notification_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_notification_container)


func show_notification(text: String, color: Color = Color.WHITE) -> void:
	if _notification_container == null:
		return
	# Cap at max visible
	var overflow_count: int = maxi(0, _notification_container.get_child_count() - _mobile_notification_limit + 1)
	for child_index: int in range(overflow_count):
		_retire_dynamic_control(_notification_container.get_child(child_index))

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.04, 0.82)
	style.border_color = color
	style.border_width_left = 3
	style.set_content_margin_all(3)
	style.content_margin_left = 7
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	lbl.clip_text = false
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_constant_override("line_spacing", 0)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	_notification_container.add_child(panel)
	_fit_notification_feed()

	# Auto-fade and remove after duration
	var tween := create_tween()
	tween.tween_interval(NOTIFICATION_DURATION)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


func _fit_notification_feed() -> void:
	if _notification_container == null:
		return
	var width: float = maxf(1.0, _notification_container.offset_right - _notification_container.offset_left - 10.0)
	var lane_height: float = maxf(32.0, _notification_container.offset_bottom - _notification_container.offset_top)
	var active_panels: Array[Control] = []
	var total_height: float = 0.0
	for child: Node in _notification_container.get_children():
		if child.is_queued_for_deletion() or not (child as Control).visible:
			continue
		var panel := child as Control
		var label := panel.get_child(0) as Label
		var font: Font = label.get_theme_font("font")
		var font_size: int = 12 if width < 150.0 else 13
		label.add_theme_font_size_override("font_size", font_size)
		# clip_text makes a wrapping Label report a 1px minimum height. Measure
		# the actual message at its lane width so VBox never collapses the text.
		label.custom_minimum_size.y = ceilf(font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y)
		active_panels.append(panel)
		total_height += label.custom_minimum_size.y + 6.0 + 2.0
	while active_panels.size() > 1 and total_height - 2.0 > lane_height:
		var oldest: Control = active_panels.pop_front()
		total_height -= (oldest.get_child(0) as Label).custom_minimum_size.y + 8.0
		_retire_dynamic_control(oldest)


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
	_sacred_site_panel = PanelContainer.new()
	_sacred_site_panel.name = "SacredSiteChip"
	_sacred_site_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sacred_site_panel.offset_top = 110
	_sacred_site_panel.offset_bottom = 138
	_sacred_site_panel.offset_left = -110
	_sacred_site_panel.offset_right = 110
	_sacred_site_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sacred_site_panel.visible = false
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.025, 0.045, 0.04, 0.88)
	chip_style.border_color = Color(0.72, 0.58, 0.28, 0.82)
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(7)
	chip_style.set_content_margin_all(4)
	_sacred_site_panel.add_theme_stylebox_override("panel", chip_style)
	_sacred_site_label = Label.new()
	_sacred_site_label.name = "SacredSiteLabel"
	_sacred_site_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sacred_site_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sacred_site_label.add_theme_font_size_override("font_size", 13)
	_sacred_site_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sacred_site_panel.add_child(_sacred_site_label)
	root_ctrl.add_child(_sacred_site_panel)


func update_sacred_site_timer(player_id: int, remaining: float, total: float) -> void:
	if _sacred_site_label == null:
		return
	if player_id < 0 or remaining <= 0.0:
		_sacred_site_panel.visible = false
		return
	_sacred_site_panel.visible = true
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


func _refresh_score_visibility(viewport_size: Vector2) -> void:
	if _score_label == null:
		return
	# The compact phone rail already owns the remaining top-right width with its
	# match clock and pause/speed controls. Scores remain available at game over.
	var phone_layout: bool = minf(viewport_size.x, viewport_size.y) <= 520.0
	_score_label.visible = not phone_layout and not _early_game_ui_active


func _create_minimap_hint() -> void:
	if _minimap_hint_label != null:
		return
	_minimap_hint_label = Label.new()
	_minimap_hint_label.name = "MinimapHintLabel"
	_minimap_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_minimap_hint_label.offset_left = 0
	_minimap_hint_label.offset_right = 40
	_minimap_hint_label.offset_top = -16
	_minimap_hint_label.offset_bottom = 0
	_minimap_hint_label.anchor_top = 0.0
	_minimap_hint_label.anchor_bottom = 0.0
	_minimap_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_minimap_hint_label.add_theme_font_size_override("font_size", 11)
	_minimap_hint_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.8))
	_minimap_hint_label.text = "Map · tap to view"
	_minimap_hint_label.visible = true
	_minimap_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_bg.add_child(_minimap_hint_label)


func _create_progression_hint() -> void:
	if _progression_hint_panel != null:
		return
	_progression_hint_panel = PanelContainer.new()
	_progression_hint_panel.name = "ProgressionHintPanel"
	_progression_hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_progression_hint_panel.offset_left = -180
	_progression_hint_panel.offset_right = 180
	_progression_hint_panel.offset_top = 48
	_progression_hint_panel.offset_bottom = 102
	_progression_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progression_hint_panel.visible = false
	var hint_style: StyleBoxFlat = KingdomTheme.panel_style()
	hint_style.set_content_margin_all(3)
	_progression_hint_panel.add_theme_stylebox_override("panel", hint_style)
	var row := HBoxContainer.new()
	row.name = "GuidanceRow"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progression_hint_panel.add_child(row)
	_progression_hint_label = Label.new()
	_progression_hint_label.name = "ProgressionHintLabel"
	_progression_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progression_hint_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_progression_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progression_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progression_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progression_hint_label.max_lines_visible = 2
	_progression_hint_label.clip_text = true
	_progression_hint_label.add_theme_font_size_override("font_size", 14)
	_progression_hint_label.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
	_progression_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_progression_hint_label)
	_guidance_dismiss_button = Button.new()
	_guidance_dismiss_button.name = "DismissGuidanceButton"
	_guidance_dismiss_button.text = "Skip"
	_guidance_dismiss_button.custom_minimum_size = Vector2(52, 48)
	_guidance_dismiss_button.tooltip_text = "End guided opener"
	_guidance_dismiss_button.visible = false
	_guidance_dismiss_button.pressed.connect(_on_guidance_dismiss_pressed)
	row.add_child(_guidance_dismiss_button)
	$Root.add_child(_progression_hint_panel)


func _on_guidance_dismiss_pressed() -> void:
	AudioManager.play_ui("button_click")
	guidance_dismissed.emit()


func update_score(score: int, enemy_score: int = 0) -> void:
	if _score_label:
		_score_label.text = "Score: %d / %d" % [score, enemy_score]


# --- Military Count ---

func update_military_count(count: int) -> void:
	_last_military_count = count
	var can_show_guided_shortcuts: bool = not _early_game_ui_active or _guided_military_shortcuts_visible
	var show_shortcuts: bool = (
		can_show_guided_shortcuts
		and not _placement_mode_active
		and (count > 0 or _pending_military_shortcut)
		and (not _is_phone_context() or not _selection_context_active)
	)
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
		_find_army_button.visible = show_shortcuts and count > 0 and not _mobile_compact_labels
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
	var phone: bool = _is_phone_context()
	var entries: Array = [
		["Workers", "Workers", KingdomTheme.MUTED, 1 if phone else 0],
		["Food", "Food %d" % food if phone else "F:%d" % food, Color(0.95, 0.40, 0.30), 1 if phone else food],
		["Wood", "Wood %d" % wood if phone else "W:%d" % wood, Color(0.50, 0.78, 0.35), 1 if phone else wood],
		["Gold", "Gold %d" % gold if phone else "G:%d" % gold, Color(0.98, 0.88, 0.25), 1 if phone else gold],
		["Build", "Build %d" % building if phone else "B:%d" % building, Color(0.70, 0.70, 0.85), building],
	]
	for entry in entries:
		var lbl: Label = _villager_task_hbox.get_node_or_null(str(entry[0])) as Label
		if lbl == null:
			lbl = Label.new()
			lbl.name = str(entry[0])
			lbl.add_theme_font_size_override("font_size", 13)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_villager_task_hbox.add_child(lbl)
		lbl.text = str(entry[1])
		lbl.visible = int(entry[3]) > 0
		lbl.add_theme_color_override("font_color", entry[2])
	_queue_mobile_layout_refresh()


# --- Helpers ---

func _get_game_manager() -> Node:
	return get_node_or_null("/root/GameManager")


func _get_resource_manager() -> Node:
	return get_node_or_null("/root/ResourceManager")


func _apply_game_theme() -> void:
	var root_ctrl: Control = $Root
	root_ctrl.theme = KingdomTheme.create_theme()
	var selection_style: StyleBoxFlat = KingdomTheme.panel_style()
	selection_style.set_content_margin_all(0.0)
	selection_panel.add_theme_stylebox_override("panel", selection_style)
	KingdomTheme.apply_primary(build_menu_button)
	food_label.add_theme_color_override("font_color", Color(0.95, 0.54, 0.39))
	wood_label.add_theme_color_override("font_color", Color(0.62, 0.78, 0.55))
	gold_label.add_theme_color_override("font_color", KingdomTheme.AMBER)
