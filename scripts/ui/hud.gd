extends CanvasLayer
## Main HUD overlay. Shows resources, selection info, minimap, and build toggle.
##
## Connects to GameManager and ResourceManager autoloads for live data.

signal build_menu_toggled(is_open: bool)
signal age_up_requested()
signal idle_villager_pressed()
signal train_unit_requested(building: Node2D, unit_type: int)
signal minimap_clicked(world_pos: Vector2)
signal sacred_site_pressed()
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
signal select_area_requested()
signal center_selection_requested()
signal research_requested(building: Node2D, research_id: String)
signal placement_cancel_requested()
signal placement_confirm_requested()
signal pause_requested()
signal resume_requested()
signal quit_to_menu_requested()
signal guidance_dismissed()
signal match_learning_requested()
signal problem_report_requested()
signal world_context_close_requested()
signal secondary_surface_changed(surface: String)
signal world_gesture_cancel_requested()

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
const MOBILE_DOCK_CAPTION_HEIGHT := 24.0
const MOBILE_TOP_RAIL_HEIGHT := 56.0
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

enum SecondarySurface { NONE, VIEW, MORE, QUEUE, INFO, HELP, WORLD_CONTEXT, ECONOMY, ARMY }
var _strategy_overview: StrategyOverview = null
const HUD_HOLD_SCRIPT := preload("res://scripts/ui/hud_hold_control.gd")
const DISMISS_SHIELD_SCRIPT := preload("res://scripts/ui/modal_dismiss_shield.gd")

var _secondary_surface: SecondarySurface = SecondarySurface.NONE
var _selection_context_revision: int = 0
var _world_context_rect := Rect2()
var _hold_components: Array[Node] = []
var _active_hold_component: Node = null
var _hold_hints_shown: Dictionary = {}
var _hold_chooser_active: bool = false
var _selection_info_button: Button = null
var _selection_name_header: HBoxContainer = null
var _info_panel: PanelContainer = null
var _info_title: Label = null
var _info_body: Label = null
var _info_from_build_menu: bool = false
var _secondary_dismissal_shield: Control = null

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
var _select_area_button: Button = null
var _area_selection_armed: bool = false
var _selection_kind: String = "none"
var _selection_is_worker: bool = false
var _age_action_primary: bool = false
var _camera_zoom_in_button: Button = null
var _camera_zoom_out_button: Button = null
var _camera_zoom_reset_button: Button = null
var _camera_center_button: Button = null
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
var _placement_uses_touch: bool = false
var _placement_preview_reason: String = ""
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
var _queue_navigation_button: Button = null
var _queue_view_requested: bool = false
var _queue_navigation_intent: int = -1  # -1: no native press; -2: canceled native press.
var _queue_view_offset: int = 0
var _queue_navigation_revision: int = 0

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
var _sacred_site_button: Button = null
var _sacred_site_status: Dictionary = {}

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
var _match_learning_active: bool = false
var _match_learning_button: Button = null
var _pending_military_shortcut: bool = false
var _focus_pulse_time: float = 0.0
var _next_touch_diagnostics_refresh_msec: int = 0
var _safe_area_diagnostics: Dictionary = {}
var _mobile_layout_refresh_queued: bool = false
var _placement_mode_active: bool = false
var _selection_context_active: bool = false
var _minimap_frame: Panel = null
var _command_dock: Panel = null
var _navigation_controls: HBoxContainer = null
var _worker_idle_button: Button = null
var _world_safe_rect := Rect2()

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
	_create_command_dock()
	_create_idle_villager_button()
	_create_military_buttons()
	_create_unit_command_buttons()
	_create_notification_feed()
	_create_hotkey_panel()
	_create_secondary_surface_controls()
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

	refresh_match_state()
	_apply_mobile_layout_for_current_viewport()
	_refresh_touch_target_diagnostics()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and is_node_ready():
		close_secondary_surface()
		_cancel_hud_holds("resize")
		_queue_mobile_layout_refresh()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		close_secondary_surface()
		_cancel_hud_holds("focus loss")
		_refresh_dismissal_shield()


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
		if is_instance_valid(_pause_overlay) and _pause_overlay.has_node("SettingsPanel"):
			get_viewport().set_input_as_handled()
			return
		_on_pause_pressed()
	elif event is InputEventKey and event.keycode == KEY_F2:
		_toggle_hotkey_panel()


# --- Pause / Speed controls ---

func _create_game_control_buttons() -> void:
	var root_ctrl: Control = $Root
	var hbox := HBoxContainer.new()
	hbox.name = "GameControlButtons"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 4)
	hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hbox.offset_left = -112
	hbox.offset_right = -8
	hbox.offset_top = 2
	hbox.offset_bottom = 50
	hbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	_pause_button = Button.new()
	_pause_button.name = "PauseButton"
	_pause_button.text = "Pause"
	_pause_button.add_theme_font_size_override("font_size", 11)
	_pause_button.custom_minimum_size = Vector2(48, 48)
	_pause_button.pressed.connect(_on_pause_pressed)
	_pause_button.tooltip_text = "Pause/Resume [P]"
	game_time_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	game_time_label.reparent(hbox)
	game_time_label.add_theme_font_size_override("font_size", 13)
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
		_set_secondary_surface(SecondarySurface.NONE if _secondary_surface == SecondarySurface.VIEW else SecondarySurface.VIEW)
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
	_camera_zoom_reset_button.pressed.connect(func() -> void:
		close_secondary_surface()
		camera_zoom_reset_requested.emit()
	)
	_camera_controls.add_child(_camera_zoom_reset_button)
	_camera_center_button = Button.new()
	_camera_center_button.name = "CenterSelectionButton"
	_camera_center_button.text = "Center"
	_camera_center_button.custom_minimum_size = Vector2(64, 48)
	_camera_center_button.add_theme_font_size_override("font_size", 12)
	_camera_center_button.tooltip_text = "Center the selected units in the visible battlefield [Space]"
	_camera_center_button.pressed.connect(func() -> void:
		close_secondary_surface()
		center_selection_requested.emit()
	)
	_camera_controls.add_child(_camera_center_button)
	$Root.add_child(_camera_controls)
	_selection_back_button = Button.new()
	_selection_back_button.name = "SelectionBackButton"
	_selection_back_button.text = "Back"
	_selection_back_button.custom_minimum_size = Vector2(48, 48)
	_selection_back_button.add_theme_font_size_override("font_size", 14)
	_selection_back_button.tooltip_text = "Clear selection and return to kingdom controls"
	_selection_back_button.pressed.connect(func() -> void: deselect_requested.emit())
	$Root/BottomRight.add_child(_selection_back_button)
	_selection_back_button.visible = false
	_select_area_button = Button.new()
	_select_area_button.name = "SelectAreaButton"
	_select_area_button.text = "Select area"
	_select_area_button.custom_minimum_size = Vector2(104, 48)
	_select_area_button.add_theme_font_size_override("font_size", 12)
	_select_area_button.toggle_mode = true
	_select_area_button.focus_mode = Control.FOCUS_NONE
	_select_area_button.tooltip_text = "Select area, then drag around your units. Tap again to cancel."
	_select_area_button.pressed.connect(func() -> void: select_area_requested.emit())
	_navigation_controls = HBoxContainer.new()
	_navigation_controls.name = "MapNavigation"
	_navigation_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_navigation_controls.add_theme_constant_override("separation", 6)
	_navigation_controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	$Root.add_child(_navigation_controls)
	_navigation_controls.add_child(_select_area_button)
	_selection_back_button.reparent(_navigation_controls)
	_selection_back_button.text = "Clear"
	_selection_back_button.add_theme_font_size_override("font_size", 12)
	_camera_controls.reparent(_navigation_controls)
	_camera_controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_select_area_button.text = "Select area"
	KingdomTheme.apply_secondary(_select_area_button)


func set_area_selection_armed(armed: bool) -> void:
	_area_selection_armed = armed
	if _select_area_button:
		_select_area_button.set_pressed_no_signal(armed)
		_select_area_button.text = "Cancel area\nDrag to select" if armed else "Select area"
	_queue_mobile_layout_refresh()


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
		frame_style.border_color = KingdomTheme.BORDER
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

	# Keep reporting reachable without adding another vertical phone menu row.
	var utility_row := HBoxContainer.new()
	utility_row.name = "UtilityRow"
	utility_row.alignment = BoxContainer.ALIGNMENT_CENTER
	utility_row.add_theme_constant_override("separation", 8)
	vbox.add_child(utility_row)
	var sound_btn := Button.new()
	sound_btn.name = "SettingsButton"
	sound_btn.text = "Settings"
	sound_btn.custom_minimum_size = Vector2(128, 48)
	sound_btn.add_theme_font_size_override("font_size", 15)
	sound_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sound_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	sound_btn.pressed.connect(func() -> void:
		load("res://scripts/ui/settings_panel.gd").open(_pause_overlay, true)
	)
	utility_row.add_child(sound_btn)
	var report_btn := Button.new()
	report_btn.name = "ReportProblemButton"
	report_btn.text = "Report problem"
	report_btn.custom_minimum_size = Vector2(160, 48)
	report_btn.add_theme_font_size_override("font_size", 15)
	report_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	report_btn.pressed.connect(func() -> void: problem_report_requested.emit())
	utility_row.add_child(report_btn)
	_match_learning_button = Button.new()
	_match_learning_button.name = "MatchLearningButton"
	_match_learning_button.text = "Battle lessons: ON" if _match_learning_active else "Learn full match"
	_match_learning_button.custom_minimum_size = Vector2(192, 48)
	_match_learning_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_match_learning_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_match_learning_button.pressed.connect(func() -> void: match_learning_requested.emit())
	vbox.add_child(_match_learning_button)

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
	if _select_area_button:
		_select_area_button.disabled = not interactable
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
		for button in [_unit_stop_button, _unit_patrol_button, _unit_stance_button]:
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
	close_secondary_surface()
	_cancel_hud_holds("modal transition")
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

func _create_command_dock() -> void:
	_command_dock = Panel.new()
	_command_dock.name = "CommandDock"
	_command_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_command_dock.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_command_dock.add_theme_stylebox_override("panel", KingdomTheme.panel_style(KingdomTheme.INK_PANEL, KingdomTheme.BORDER, 12))
	$Root.add_child(_command_dock)
	$Root.move_child(_command_dock, 0)
	selection_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	build_menu_button.icon = null
	KingdomTheme.apply_primary(build_menu_button)


func get_world_safe_rect() -> Rect2:
	return _world_safe_rect if _world_safe_rect.has_area() else get_viewport().get_visible_rect()


func get_hold_safe_rect() -> Rect2:
	var safe: Rect2 = get_world_safe_rect()
	var card_top: float = safe.position.y
	if is_instance_valid(top_bar) and top_bar.is_visible_in_tree():
		card_top = maxf(card_top, top_bar.get_global_rect().end.y + 8.0)
	card_top = minf(card_top, safe.end.y)
	return Rect2(Vector2(safe.position.x, card_top), Vector2(safe.size.x, safe.end.y - card_top))


func get_world_occlusion_rects() -> Array[Rect2]:
	# Camera framing consumes actual rendered cards, never transparent containers.
	var obstacles: Array[Rect2] = []
	_prune_hold_components()
	var build_menu_panel: Control = get_node_or_null("BuildMenu") as Control
	for control: Control in [top_bar, minimap_bg, _command_dock, _navigation_controls,
		_progression_hint_panel, _sacred_site_panel, _advanced_command_panel, _placement_status_panel,
		_hotkey_panel, _info_panel, build_menu_panel]:
		if control != null and control.is_visible_in_tree() and control.size.x > 0.0 and control.size.y > 0.0:
			obstacles.append(control.get_global_rect())
	if _placement_mode_active and _mobile_action_panel.is_visible_in_tree():
		obstacles.append(_mobile_action_panel.get_global_rect())
	if _notification_container != null:
		for child: Control in _notification_container.get_children():
			if child.is_visible_in_tree() and not child.is_queued_for_deletion():
				obstacles.append(child.get_global_rect())
	for component: Node in _hold_components:
		if is_instance_valid(component):
			for bounds: Rect2 in component.call("get_visible_bounds"):
				if bounds.has_area() and not obstacles.has(bounds):
					obstacles.append(bounds)
	if _secondary_surface == SecondarySurface.WORLD_CONTEXT and _world_context_rect.has_area():
		obstacles.append(_world_context_rect)
	if build_menu_panel != null and build_menu_panel.has_method("get_hold_occlusion_rects"):
		for bounds: Rect2 in build_menu_panel.call("get_hold_occlusion_rects"):
			if bounds.has_area() and not obstacles.has(bounds):
				obstacles.append(bounds)
	if _strategy_overview:
		obstacles.append_array(_strategy_overview.get_visible_bounds())
	var battlefield: Node = get_node_or_null("Root/BattlefieldFeedback")
	if battlefield and battlefield.has_method("get_visible_bounds"):
		obstacles.append_array(battlefield.call("get_visible_bounds"))
	return obstacles


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
	var bottom_right: BoxContainer = %BottomRight
	_villager_task_hbox = HBoxContainer.new()
	_villager_task_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_villager_task_hbox.add_theme_constant_override("separation", 6)
	# Keep contextual worker counts readable over grass without adding layout or input area.
	var task_backplate := KingdomTheme.panel_style(Color.TRANSPARENT, Color.TRANSPARENT, 4)
	task_backplate.set_content_margin_all(0.0)
	task_backplate.set_border_width_all(0)
	_villager_task_hbox.draw.connect(func():
		_villager_task_hbox.draw_style_box(task_backplate, Rect2(Vector2.ZERO, _villager_task_hbox.size)))
	_villager_task_hbox.resized.connect(_villager_task_hbox.queue_redraw)
	bottom_right.add_child(_villager_task_hbox)
	bottom_right.move_child(_villager_task_hbox, 0)


func _on_idle_villager_pressed() -> void:
	close_secondary_surface()
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
	_unit_attack_move_button = _make_unit_command_button("UnitAttackMoveButton", "Attack", "Attack-move: tap a destination and fight enemies on the way")
	_unit_attack_move_button.toggle_mode = true
	_unit_attack_move_button.pressed.connect(_on_unit_attack_move_pressed)
	_unit_command_container.add_child(_unit_attack_move_button)
	_unit_more_button = _make_unit_command_button("UnitMoreButton", "More", "Stop, Patrol and Stance")
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
	_unit_stop_button = _make_unit_command_button("UnitStopButton", "Stop", "Stop the selected units")
	_unit_stop_button.pressed.connect(_on_unit_stop_pressed)
	_advanced_command_container.add_child(_unit_stop_button)
	_unit_patrol_button = _make_unit_command_button("UnitPatrolButton", "Patrol", "Patrol between here and a destination")
	_unit_patrol_button.toggle_mode = true
	_unit_patrol_button.pressed.connect(_on_unit_patrol_pressed)
	_advanced_command_container.add_child(_unit_patrol_button)
	_unit_stance_button = _make_unit_command_button("UnitStanceButton", "Stance", "Toggle Aggressive / Stand Ground")
	_unit_stance_button.toggle_mode = true
	_unit_stance_button.pressed.connect(_on_unit_stance_pressed)
	_advanced_command_container.add_child(_unit_stance_button)
	_worker_idle_button = _make_unit_command_button("WorkerIdleButton", "Idle workers", "Cycle idle workers")
	_worker_idle_button.pressed.connect(_on_idle_villager_pressed)
	_advanced_command_container.add_child(_worker_idle_button)
	_worker_idle_button.visible = false


func _on_unit_more_pressed() -> void:
	_set_secondary_surface(SecondarySurface.NONE if _secondary_surface == SecondarySurface.MORE else SecondarySurface.MORE)


func _close_advanced_commands() -> void:
	if _secondary_surface == SecondarySurface.MORE:
		_set_secondary_surface(SecondarySurface.NONE)
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
	var compact_style: StyleBoxFlat = KingdomTheme.panel_style(KingdomTheme.INK_LIGHT, KingdomTheme.BORDER, 9)
	compact_style.set_content_margin(SIDE_LEFT, 8.0)
	compact_style.set_content_margin(SIDE_RIGHT, 8.0)
	button.add_theme_stylebox_override("normal", compact_style)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	return button


func _on_unit_move_pressed() -> void:
	close_secondary_surface()
	AudioManager.play_ui("button_click")
	unit_move_requested.emit()


func _on_unit_attack_move_pressed() -> void:
	close_secondary_surface()
	AudioManager.play_ui("button_click")
	unit_attack_move_requested.emit()


func _on_unit_patrol_pressed() -> void:
	close_secondary_surface()
	AudioManager.play_ui("button_click")
	unit_patrol_requested.emit()


func _on_unit_stop_pressed() -> void:
	close_secondary_surface()
	AudioManager.play_ui("button_click")
	unit_stop_requested.emit()


func _on_unit_stance_pressed() -> void:
	close_secondary_surface()
	AudioManager.play_ui("button_click")
	unit_stance_requested.emit()


func _on_unit_clear_pressed() -> void:
	close_secondary_surface()
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
		_unit_move_button.text = "Move\nArmed" if armed_mode == "move" else "Move"
	if _unit_attack_move_button:
		_unit_attack_move_button.set_pressed_no_signal(armed_mode == "attack_move")
		_unit_attack_move_button.text = "Attack\nArmed" if armed_mode == "attack_move" else "Attack"
	if _unit_patrol_button:
		_unit_patrol_button.set_pressed_no_signal(armed_mode == "patrol")
		_unit_patrol_button.text = "Patrol\nArmed" if armed_mode == "patrol" else "Patrol"
	if _unit_stance_button:
		_unit_stance_button.text = "Stance"
		_unit_stance_button.set_pressed_no_signal(stance_name == "Stand Ground")
		_unit_stance_button.tooltip_text = "Current stance: %s. Tap to toggle." % stance_name
	if _worker_idle_button:
		_worker_idle_button.visible = not has_military and _selection_is_worker
		_worker_idle_button.disabled = _last_idle_villager_count <= 0
		_worker_idle_button.text = "Idle %d" % _last_idle_villager_count
	_unit_patrol_button.visible = has_military
	_unit_stance_button.visible = authorized
	if _unit_more_button:
		_unit_more_button.text = "More •" if armed_mode == "patrol" else "More"
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
		_idle_villager_button.visible = _strategy_overview == null and count > 0 and not _placement_mode_active and (not _is_phone_context() or not _selection_context_active or (_selection_kind == "unit" and _selection_is_worker and not _unit_commands_have_military))
		layout_changed = was_visible != _idle_villager_button.visible
		if _mobile_compact_labels:
			_idle_villager_button.text = "Idle %d" % count
		else:
			_idle_villager_button.text = "Idle: %d [.]" % count
		_idle_villager_button.disabled = count <= 0
		if count > 0 and not bool(GameManager.get("reduced_motion")) and not bool(GameManager.get("reduced_flashes")):
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
	if active and not was_active:
		close_secondary_surface()
		_cancel_hud_holds("placement")
	_placement_mode_active = active
	_placement_cancel_button.visible = active
	_placement_confirm_button.visible = active and _placement_uses_touch
	_placement_status_panel.visible = active
	if _town_center_button:
		_town_center_button.visible = not active
	_placement_building_name = building_name
	if active and not was_active:
		_placement_preview_valid = false
		update_placement_preview(false, "Choose clear ground")
	_close_advanced_commands()
	var bottom_right: Control = get_node_or_null("Root/BottomRight")
	if bottom_right:
		bottom_right.visible = not active
	minimap_bg.visible = not active
	if active:
		# Placement is a direct-manipulation mode: leave the world, ghost, top
		# resources, and input-appropriate placement actions while hiding the prior
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
	_placement_preview_reason = reason
	if _placement_confirm_button:
		_placement_confirm_button.disabled = not valid or _ui_modal_state == UIModalState.PAUSE_MENU
		_placement_confirm_button.text = "Place %s" % _placement_building_name if _placement_building_name != "" else "Place building"
		# The complete building name lives in the status. The CTA stays readable.
		if _placement_confirm_button.text.length() > 20:
			_placement_confirm_button.text = "Place building"
	if _placement_status_label:
		var status: String = ("Tap Place to build" if _placement_uses_touch else "Click ground to build") if valid else (reason if reason != "" else "Choose clear ground")
		_placement_status_label.text = "%s · %s" % [_placement_building_name, status] if _placement_building_name != "" else status
		_placement_status_label.add_theme_color_override("font_color", KingdomTheme.PARCHMENT if valid else Color(1.0, 0.75, 0.55))
	_refresh_touch_target_diagnostics()


func set_placement_input_mode(uses_touch: bool) -> void:
	_placement_uses_touch = uses_touch
	if _placement_confirm_button:
		_placement_confirm_button.visible = _placement_mode_active and uses_touch
	update_placement_preview(_placement_preview_valid, _placement_preview_reason)
	if _placement_mode_active:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))


func apply_mobile_layout(viewport_size: Vector2, safe_area: Rect2) -> void:
	if _mobile_action_panel == null:
		return

	var safe_pos: Vector2 = safe_area.position
	_world_safe_rect = safe_area
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
		var task_parent: Node = _command_dock
		if _villager_task_hbox.get_parent() != task_parent:
			_villager_task_hbox.reparent(task_parent)
		_villager_task_hbox.visible = (_selection_kind == "unit" and _selection_is_worker and _unit_commands_authorized and not _unit_commands_have_military and not _advanced_commands_open and not _placement_mode_active and _ui_modal_state == UIModalState.NONE)
	var safe_top: float = metrics["safe_top"]
	var safe_left: float = metrics["safe_left"]
	var safe_right: float = metrics["safe_right"]
	top_bar.offset_top = safe_top
	top_bar.offset_bottom = safe_top + top_bar.custom_minimum_size.y
	_layout_secondary_cards()
	if _strategy_overview:
		_strategy_overview.apply_layout(safe_area, standard_field_chrome_visible and _ui_modal_state == UIModalState.NONE, get_hold_safe_rect())
	var top_bar_margin: MarginContainer = top_bar.get_node_or_null("TopBarMargin")
	if top_bar_margin:
		top_bar_margin.add_theme_constant_override("margin_left", int(round(safe_left + 10.0)))
		# Reserve the top-right utility buttons instead of rendering the timer
		# underneath them at narrow phone widths.
		top_bar_margin.add_theme_constant_override("margin_right", int(round(safe_right + 368.0)))

	var game_controls: Control = get_node_or_null("Root/GameControlButtons")
	if game_controls:
		game_controls.offset_right = -safe_right - 8.0
		game_controls.offset_left = game_controls.offset_right - 158.0
		game_controls.offset_top = safe_top + 4.0
		game_controls.offset_bottom = safe_top + 52.0
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
		_navigation_controls.visible = standard_field_chrome_visible and _ui_modal_state == UIModalState.NONE
		_camera_controls.visible = _navigation_controls.visible
		var phone_camera: bool = minf(viewport_size.x, viewport_size.y) <= 520.0
		_camera_view_button.visible = phone_camera
		_camera_view_button.set_pressed_no_signal(_camera_controls_expanded)
		for zoom_button: Button in [_camera_zoom_out_button, _camera_zoom_in_button, _camera_zoom_reset_button, _camera_center_button]:
			zoom_button.visible = not phone_camera or _camera_controls_expanded
		_navigation_controls.offset_left = metrics["minimap_left"]
		var camera_width: float = 290.0 if phone_camera and _camera_controls_expanded else (48.0 if phone_camera else 238.0)
		_camera_center_button.disabled = not _selection_context_active or _ui_modal_state != UIModalState.NONE
		var nav_width: float = camera_width + (110.0 if _select_area_button.visible else 0.0) + (54.0 if _selection_back_button.visible else 0.0)
		_navigation_controls.offset_right = metrics["minimap_left"] + nav_width
		_navigation_controls.offset_bottom = metrics["minimap_top"] - 8.0
		_navigation_controls.offset_top = _navigation_controls.offset_bottom - 48.0
		metrics["camera_zoom_left"] = metrics["minimap_left"]
		metrics["camera_zoom_right"] = metrics["minimap_left"] + nav_width
		metrics["camera_zoom_top"] = viewport_size.y + _navigation_controls.offset_top
		metrics["camera_zoom_bottom"] = viewport_size.y + _navigation_controls.offset_bottom
		_mobile_notification_limit = 1 if phone_camera else MAX_NOTIFICATIONS
	var bottom_right: Control = get_node_or_null("Root/BottomRight")
	if bottom_right:
		bottom_right.visible = standard_field_chrome_visible and (age_up_button.visible or build_menu_button.visible)
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
	var compact_tc_info: bool = bool(metrics["top_bar_compact"]) and _is_town_center_production_context()
	selection_name.add_theme_font_size_override("font_size", 12 if compact_tc_info else 14)
	selection_details.add_theme_font_size_override("font_size", 10 if compact_tc_info else 11)
	if compact_tc_info:
		selection_details.add_theme_constant_override("line_spacing", 0)
	else:
		selection_details.remove_theme_constant_override("line_spacing")
	selection_hp_bar.custom_minimum_size.y = 8.0 if compact_tc_info else 10.0
	selection_info_column.add_theme_constant_override("separation", 0)
	_update_selection_name_layout(float(metrics["selection_info_width"]) - 26.0)
	if _selection_info_button:
		_selection_info_button.visible = _selection_context_active and standard_field_chrome_visible
		_selection_info_button.position = selection_info_column.get_global_rect().position
		_selection_info_button.size = Vector2(float(metrics["selection_info_width"]), maxf(48.0, selection_info_column.size.y))
		call_deferred("_layout_summary_info_target")
	selection_panel.visible = _selection_context_active and standard_field_chrome_visible
	if _command_dock:
		var caption_height: float = MOBILE_DOCK_CAPTION_HEIGHT if _villager_task_hbox and _villager_task_hbox.visible else 0.0
		var dock_left: float = metrics["selection_left"] if _selection_context_active else metrics["action_left"]
		if not _selection_context_active and action_count == 0:
			dock_left = viewport_size.x + metrics["bottom_right_left"]
		var dock_right: float = maxf(metrics["selection_right"] if _selection_context_active else viewport_size.x + metrics["action_right"], viewport_size.x + metrics["bottom_right_right"] if bottom_right.visible else 0.0)
		_command_dock.position = Vector2(dock_left - 4.0, viewport_size.y + metrics["selection_top"] - caption_height)
		_command_dock.size = Vector2(dock_right - dock_left + 8.0, MOBILE_SELECTION_HEIGHT + caption_height)
		_command_dock.visible = standard_field_chrome_visible and (_selection_context_active or action_count > 0 or bottom_right.visible)
	if _villager_task_hbox and _villager_task_hbox.get_parent() == _command_dock:
		_villager_task_hbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_villager_task_hbox.offset_left = 12.0
		_villager_task_hbox.offset_right = minf(_command_dock.size.x - 12.0, 320.0)
		_villager_task_hbox.offset_top = 3.0
		_villager_task_hbox.offset_bottom = 21.0
	var selection_has_commands: bool = _selection_has_commands()
	selection_separator.visible = selection_has_commands and not (bool(metrics["top_bar_compact"]) and _is_town_center_production_context())
	command_scroll.visible = selection_has_commands
	_layout_queue_page()
	if _advanced_command_panel:
		var advanced_width: float = minf(344.0, metrics["selection_width"])
		_advanced_command_panel.offset_left = metrics["selection_right"] - advanced_width - viewport_size.x * 0.5
		_advanced_command_panel.offset_right = _advanced_command_panel.offset_left + advanced_width
		_advanced_command_panel.offset_bottom = metrics["selection_top"] - (64.0 if _strategy_overview else 8.0)
		_advanced_command_panel.offset_top = _advanced_command_panel.offset_bottom - 60.0
		_advanced_command_panel.visible = _advanced_commands_open and not _hold_chooser_active and _unit_command_container.visible and standard_field_chrome_visible
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
		var hint_width: float = minf(444.0 if _match_learning_active else MOBILE_GUIDANCE_WIDTH, safe_area.size.x - 140.0)
		var hint_left: float = safe_area.end.x - 8.0 - hint_width
		var hint_right: float = hint_left + hint_width
		_progression_hint_panel.offset_left = hint_left - viewport_size.x * 0.5
		_progression_hint_panel.offset_right = hint_right - viewport_size.x * 0.5
		_progression_hint_panel.offset_top = metrics["safe_top"] + MOBILE_TOP_RAIL_HEIGHT + 8.0
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
			_notification_container.offset_top = metrics["safe_top"] + MOBILE_TOP_RAIL_HEIGHT + 8.0
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
		_sacred_site_panel.visible = not _sacred_site_status.is_empty() and standard_field_chrome_visible
		var sacred_width: float = 188.0
		var sacred_left: float = safe_area.end.x - 360.0
		_sacred_site_panel.offset_left = sacred_left - viewport_size.x * 0.5
		_sacred_site_panel.offset_right = _sacred_site_panel.offset_left + sacred_width
		_sacred_site_panel.offset_top = metrics["safe_top"] + 4.0
		_sacred_site_panel.offset_bottom = _sacred_site_panel.offset_top + MOBILE_ACTION_BUTTON_HEIGHT
		_sacred_site_button.disabled = _ui_modal_state == UIModalState.PAUSE_MENU
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
	build_menu_button.visible = field_mode and (unselected or worker)
	var gm: Node = _get_game_manager()
	var can_advance: bool = gm == null or not gm.get_age_up_cost(0, gm.get_player_age(0) + 1).is_empty()
	age_up_button.visible = field_mode and not _early_game_ui_active and can_advance and town_center
	_selection_back_button.visible = field_mode and _selection_context_active and _selection_kind != "unit" and (not _camera_controls_expanded or _strategy_overview == null)
	_selection_back_button.text = "Back"
	_select_area_button.visible = field_mode
	_select_area_button.disabled = _ui_modal_state != UIModalState.NONE
	_town_center_button.visible = _strategy_overview == null and field_mode and unselected
	_idle_villager_button.visible = _strategy_overview == null and field_mode and _last_idle_villager_count > 0 and unselected
	var military_allowed: bool = not _early_game_ui_active or _guided_military_shortcuts_visible
	_select_military_button.visible = _strategy_overview == null and field_mode and military_allowed and (_last_military_count > 0 or _pending_military_shortcut) and unselected
	_find_army_button.visible = _strategy_overview == null and field_mode and not phone and military_allowed and _last_military_count > 0 and unselected
	var primary_age: bool = town_center
	if primary_age != _age_action_primary:
		_age_action_primary = primary_age
		if primary_age:
			KingdomTheme.apply_primary(age_up_button)
		else:
			KingdomTheme.apply_secondary(age_up_button)


func _calculate_mobile_layout_metrics(viewport_size: Vector2, safe_area: Rect2, action_button_count: int) -> Dictionary:
	var safe_pos: Vector2 = safe_area.position
	var safe_end: Vector2 = safe_area.end
	var right_inset: float = maxf(0.0, viewport_size.x - safe_end.x)
	var bottom_inset: float = maxf(0.0, viewport_size.y - safe_end.y)
	var short_side: float = minf(safe_area.size.x, safe_area.size.y)
	var phone: bool = short_side <= MOBILE_TOP_BAR_COMPACT_SHORT_SIDE
	var side_button_width: float = 104.0
	var side_count: int = int(age_up_button.visible) + int(build_menu_button.visible)
	var side_width: float = side_button_width * float(side_count) + 6.0 * float(maxi(0, side_count - 1))
	var bottom_right_right: float = -right_inset - MOBILE_ACTION_MARGIN
	var bottom_right_left: float = bottom_right_right - side_width
	var bottom_right_bottom: float = -bottom_inset - MOBILE_ACTION_MARGIN - 12.0
	var bottom_right_top: float = bottom_right_bottom - MOBILE_ACTION_BUTTON_HEIGHT
	var action_columns: int = maxi(1, action_button_count)
	var button_width: float = 104.0
	var action_width: float = MOBILE_ACTION_INNER_PADDING * 2.0 + button_width * float(action_button_count) + MOBILE_ACTION_GAP * float(maxi(0, action_button_count - 1))
	var action_right: float = bottom_right_left - (8.0 if side_count > 0 else 0.0)
	var action_left: float = viewport_size.x + action_right - action_width
	var action_bottom: float = bottom_right_bottom
	var action_top: float = action_bottom - MOBILE_ACTION_BUTTON_HEIGHT
	if _placement_mode_active:
		action_width = 148.0 * float(action_button_count) + MOBILE_ACTION_GAP * float(maxi(0, action_button_count - 1)) + MOBILE_ACTION_INNER_PADDING * 2.0
		action_left = safe_pos.x + (safe_area.size.x - action_width) * 0.5
		action_right = action_left + action_width - viewport_size.x
		action_bottom = -bottom_inset - MOBILE_ACTION_MARGIN
		action_top = action_bottom - MOBILE_ACTION_BUTTON_HEIGHT
	var minimap_size: float = clampf(minf(safe_area.size.y * 0.26, safe_area.size.x * 0.15), MOBILE_MINIMAP_MIN_SIZE, MOBILE_MINIMAP_MAX_SIZE)
	var minimap_left: float = safe_pos.x + MOBILE_ACTION_MARGIN
	var minimap_bottom: float = -bottom_inset - MOBILE_ACTION_MARGIN
	var minimap_top: float = minimap_bottom - minimap_size
	var minimap_right: float = minimap_left + minimap_size
	var selection_has_commands: bool = _selection_has_commands()
	var unit_commands_visible: bool = _unit_command_container != null and _unit_command_container.visible
	var selection_zone_left: float = minimap_right + 12.0
	var selection_zone_right: float = viewport_size.x + bottom_right_left - (8.0 if side_count > 0 else 0.0)
	var selection_zone_width: float = maxf(220.0, selection_zone_right - selection_zone_left)
	var info_width: float = 120.0 if unit_commands_visible else (108.0 if selection_has_commands else 148.0)
	var selection_width: float = 166.0
	if selection_has_commands:
		selection_width = minf(selection_zone_width, MOBILE_SELECTION_COMMAND_WIDTH)
	if phone and _auto_queue_button != null and _train_buttons_container != null and _train_buttons_container.visible:
		var showing_queue: bool = _queue_view_requested or (queue_container.visible and command_scroll.scroll_horizontal > maxi(1, int(queue_container.position.x * 0.5)))
		var page_width: float = _production_row_width(queue_container) if showing_queue else _production_row_width(_train_buttons_container)
		info_width = 88.0 if _is_town_center_production_context() else 108.0
		selection_width = minf(selection_zone_width, ceilf(info_width + page_width + 48.0 + (16.0 if _is_town_center_production_context() else 28.0) + 16.0) + 2.0)
	elif phone and unit_commands_visible:
		var command_width: float = _production_row_width(_unit_command_container)
		# Keep every frequent action fully visible at scroll0, including Clear.
		# The identity column gives up spare width before any touch target does.
		info_width = clampf(floorf(selection_zone_width - command_width - 38.0), 96.0, 120.0)
		selection_width = minf(selection_zone_width, ceilf(info_width + command_width + 38.0))
	var selection_right: float = selection_zone_right
	var selection_left: float = selection_right - selection_width
	var selection_bottom: float = -bottom_inset - MOBILE_ACTION_MARGIN
	var selection_top: float = selection_bottom - MOBILE_SELECTION_HEIGHT
	var selection_rect := Rect2(Vector2(selection_left, viewport_size.y + selection_top), Vector2(selection_width, MOBILE_SELECTION_HEIGHT))
	var minimap_calc := Rect2(Vector2(minimap_left, viewport_size.y + minimap_top), Vector2(minimap_size, minimap_size))
	var action_rect := Rect2(Vector2(action_left, viewport_size.y + action_top), Vector2(action_width, MOBILE_ACTION_BUTTON_HEIGHT))
	var side_rect := Rect2(Vector2(viewport_size.x + bottom_right_left, viewport_size.y + bottom_right_top), Vector2(side_width, MOBILE_ACTION_BUTTON_HEIGHT))
	var action_visible: bool = action_button_count > 0
	var selection_visible: bool = _selection_context_active and not _placement_mode_active
	var minimap_action_overlap: bool = action_visible and not _placement_mode_active and minimap_calc.intersects(action_rect, true)
	var selection_action_overlap: bool = selection_visible and action_visible and selection_rect.intersects(action_rect, true)
	var selection_minimap_overlap: bool = selection_visible and minimap_calc.intersects(selection_rect, true)
	var selection_side_overlap: bool = selection_visible and side_count > 0 and side_rect.intersects(selection_rect, true)
	var side_action_overlap: bool = action_visible and side_count > 0 and not _placement_mode_active and side_rect.intersects(action_rect, true)
	return {
		"viewport_width": viewport_size.x, "viewport_height": viewport_size.y,
		"safe_top": safe_pos.y, "safe_left": safe_pos.x, "safe_right": right_inset, "safe_bottom": bottom_inset,
		"safe_width": safe_area.size.x, "safe_height": safe_area.size.y,
		"action_columns": action_columns, "action_rows": 1 if action_visible else 0,
		"button_width": button_width, "button_height": MOBILE_ACTION_BUTTON_HEIGHT,
		"action_left": action_left, "action_right": action_right, "action_top": action_top, "action_bottom": action_bottom,
		"minimap_left": minimap_left, "minimap_right": minimap_right, "minimap_top": minimap_top, "minimap_bottom": minimap_bottom,
		"selection_width": selection_width, "selection_height": MOBILE_SELECTION_HEIGHT, "selection_info_width": info_width,
		"selection_left": selection_left, "selection_right": selection_right, "selection_top": selection_top, "selection_bottom": selection_bottom,
		"side_button_width": side_button_width, "side_button_height": MOBILE_ACTION_BUTTON_HEIGHT,
		"bottom_right_top": bottom_right_top, "bottom_right_bottom": bottom_right_bottom, "bottom_right_left": bottom_right_left, "bottom_right_right": bottom_right_right,
		"central_world_left": selection_zone_left, "central_world_right": safe_end.x - 8.0,
		"central_world_top": safe_pos.y + MOBILE_TOP_RAIL_HEIGHT,
		"central_world_bottom": viewport_size.y + selection_top - 8.0,
		"central_world_width": safe_end.x - selection_zone_left - 8.0,
		"central_world_height": viewport_size.y + selection_top - 8.0 - safe_pos.y - MOBILE_TOP_RAIL_HEIGHT,
		"compact_labels": phone, "top_bar_compact": phone,
		"minimap_action_overlap": minimap_action_overlap, "selection_action_overlap": selection_action_overlap,
		"selection_minimap_overlap": selection_minimap_overlap, "selection_bottom_right_overlap": selection_side_overlap,
		"bottom_right_action_overlap": side_action_overlap, "action_game_controls_overlap": false,
		"layout_pass": _layout_metrics_pass(button_width, minimap_action_overlap, selection_action_overlap, side_action_overlap, selection_minimap_overlap, selection_side_overlap, false),
	}


func _selection_has_commands() -> bool:
	if _unit_command_container != null and _unit_command_container.visible and _unit_command_container.get_child_count() > 0:
		return true
	if queue_container != null and queue_container.visible and queue_container.get_child_count() > 0:
		return true
	if _train_buttons_container != null and _train_buttons_container.visible and _train_buttons_container.get_child_count() > 0:
		return true
	return _research_container != null and _research_container.visible and _research_container.get_child_count() > 0


func _production_row_width(row: HBoxContainer) -> float:
	if row == null:
		return 0.0
	var width: float = 0.0
	var count: int = 0
	for child: Control in row.get_children():
		if child.visible and not child.is_queued_for_deletion():
			width += child.get_combined_minimum_size().x
			count += 1
	return width + float(maxi(0, count - 1)) * float(row.get_theme_constant("separation"))


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
	diag["placement_input_mode"] = "touch" if _placement_uses_touch else "mouse"
	diag["home_button"] = _control_touch_diag(get_base_navigation_button(), "home_button")
	if _strategy_overview:
		diag["strategy_rail"] = _collect_button_diags(_strategy_overview.rail, "strategy_rail")
		diag["strategy_surface"] = get_secondary_surface_name()
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
	diag["queue_navigation"] = _control_touch_diag(_queue_navigation_button, "queue_navigation")
	diag["train_buttons"] = _collect_button_diags(_train_buttons_container, "train")
	diag["repeat_training_button"] = _control_touch_diag(_auto_queue_button, "repeat_training")
	diag["repeat_training_enabled"] = _auto_queue_button.button_pressed if _auto_queue_button else false
	diag["sacred_site_button"] = _control_touch_diag(_sacred_site_button, "sacred_site")
	diag["sacred_site_status"] = _sacred_site_label.text if _sacred_site_label else ""
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
		diag["pause_menu_learning"] = _control_touch_diag(_match_learning_button, "pause_menu_learning")
	touch_target_diagnostics = diag


func _apply_top_bar_compact(compact: bool) -> void:
	if _match_population_label:
		_match_population_label.visible = not compact
	top_bar.custom_minimum_size = Vector2(0, MOBILE_TOP_RAIL_HEIGHT)
	if compact == _top_bar_compact:
		return
	_top_bar_compact = compact
	top_bar_hbox.add_theme_constant_override("separation", 8 if compact else 14)
	if _resource_node_legend:
		_resource_node_legend.visible = not compact
	age_label.visible = not compact
	var font_size: int = 14 if compact else 16
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
		_guidance_dismiss_button.visible = active or _match_learning_active
	update_idle_villager_count(_last_idle_villager_count)
	update_military_count(_last_military_count)
	_refresh_primary_action_visuals()
	_refresh_touch_target_diagnostics()


func set_match_learning_active(active: bool) -> void:
	_match_learning_active = active
	if _guidance_dismiss_button:
		_guidance_dismiss_button.visible = active or _early_game_ui_active
		_guidance_dismiss_button.tooltip_text = "Stop battle lessons" if active else "End guided opener"
	if _match_learning_button:
		_match_learning_button.text = "Battle lessons: ON" if active else "Learn full match"
	_queue_mobile_layout_refresh()


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
	var pulse: float = 1.0 if bool(GameManager.get("reduced_motion")) or bool(GameManager.get("reduced_flashes")) else 0.88 + 0.12 * (0.5 + 0.5 * sin(_focus_pulse_time * 4.0))
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
		_minimap_hint_label.modulate = Color(1.0, 1.0, 1.0, 1.0 if bool(GameManager.get("reduced_motion")) or bool(GameManager.get("reduced_flashes")) else 0.82 + 0.18 * sin(_focus_pulse_time * 4.0))
	minimap_bg.color = KingdomTheme.INK_PANEL
	if _strategy_overview:
		_strategy_overview.set_attention(_primary_action_focus, pulse)

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
		if label.visible and label.get_parent() == top_bar_hbox:
			required_width += label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	required_width += float(visible_labels.size() - 1) * float(top_bar_hbox.get_theme_constant("separation"))
	_resource_labels_abbreviated = required_width > _top_bar_safe_width - 378.0
	if _resource_labels_abbreviated:
		for index: int in 3:
			labels[index].text = "%s %s" % [names[index].left(1), _compact_resource_amount(values[index])]
	update_population(_population_current, _population_cap)
	_update_age_display()


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
	if _top_bar_compact:
		var gm: Node = _get_game_manager()
		var current_age: String = gm.get_age_name(gm.get_player_age(0)) if gm else "Dark Age"
		pop_label.text += "\n" + current_age


# --- Age display ---

func refresh_match_state() -> void:
	# Children become ready before Main resets the previous match's players.
	# Main calls this again after initialization and starting population setup.
	_update_age_display()
	var gm: Node = _get_game_manager()
	if gm:
		set_match_population_limit(gm.get_player_population_limit(0))
		var player: Dictionary = gm.players.get(0, {})
		update_population(gm.get_committed_population(0), int(player.get("population_cap", 0)))
		game_time_label.text = gm.get_formatted_time()
	var rm: Node = _get_resource_manager()
	if rm:
		_update_resource_display(rm.get_all_resources(0))
	_queue_mobile_layout_refresh()


func _on_age_advanced(_player_id: int, _new_age: int) -> void:
	_update_age_display()
	update_population(_population_current, _population_cap)


func _update_age_display() -> void:
	var gm: Node = _get_game_manager()
	if gm:
		var age: int = gm.get_player_age(0)
		age_label.text = gm.get_age_name(age)
		var cost: Dictionary = gm.get_age_up_cost(0, age + 1)
		# Keep costs visible on phones, where hover tooltips are unavailable.
		age_up_button.icon = null
		age_up_button.add_theme_font_size_override("font_size", 13)
		age_up_button.add_theme_color_override("font_disabled_color", KingdomTheme.MUTED)
		if not cost.is_empty():
			var rm: Node = _get_resource_manager()
			var affordable: bool = rm != null and rm.can_afford(0, cost)
			age_up_button.text = "Age Up\n%dF · %dG" % [int(cost.get("food", 0)), int(cost.get("gold", 0))]
			age_up_button.tooltip_text = _get_age_up_preview(age + 1)
			age_up_button.disabled = not affordable or _ui_modal_state != UIModalState.NONE
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
		var rm: Node = _get_resource_manager()
		if rm:
			var missing: Dictionary = rm.get_missing_resources(0, cost)
			if missing.is_empty():
				lines.append("Ready to advance")
			else:
				lines.append("Need +%d food · +%d gold" % [int(missing.get("food", 0)), int(missing.get("gold", 0))])
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
	if gm and new_state in [gm.GameState.GAME_OVER, gm.GameState.MENU]:
		close_secondary_surface()
		_cancel_hud_holds("match ended")
		return
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
	var restore_queue_view: bool = _selected_building_ref == building_ref and command_scroll.scroll_horizontal > maxi(1, int(queue_container.position.x * 0.5))
	var queue_view_offset: int = maxi(0, command_scroll.scroll_horizontal - int(queue_container.position.x))
	_queue_view_requested = restore_queue_view
	_queue_view_offset = queue_view_offset if restore_queue_view else 0
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
		if b.provides_food:
			detail_parts.append("%d food remaining" % b.farm_remaining)
		if b.rally_resource_instance_id > 0:
			detail_parts.append("Villager rally: gather %s" % b.rally_resource_type)
	selection_name.tooltip_text = "%s\n%s" % [building_name, " | ".join(detail_parts)]
	selection_details.tooltip_text = " | ".join(detail_parts)
	selection_details.text = _building_purpose(building_ref)
	# A new producer always starts at recruitment. Live updates of the same
	# producer preserve the player's queue inspection position.
	if _selected_building_ref != building_ref:
		if _is_phone_context() and _is_human_owned_building(building_ref) and (building_ref as BuildingBase).can_train():
			show_notification("Hold ground to set a rally. Tap ground to close.", Color(0.65, 0.82, 1.0))
		_queue_view_requested = false
		_queue_view_offset = 0
		_queue_navigation_revision += 1
		command_scroll.scroll_horizontal = 0
	_selected_building_ref = building_ref
	var has_command_authority: bool = _is_human_owned_building(building_ref)
	var visible_queue: Array = queue_items if has_command_authority else []
	var visible_trainable: Array = trainable_units if has_command_authority else []
	_last_queue_items = visible_queue.duplicate(true)
	if _is_human_owned_building(building_ref):
		for item: Dictionary in visible_queue:
			if bool(item.get("is_training", false)):
				# Compact mobile info keeps the full rally cue and live training visible.
				selection_details.text += "\n%s %d%%" % [str(item.get("name", "Training")), int(float(item.get("progress", 0.0)) * 100.0)]
				break
	_update_queue_display(visible_queue)
	_update_train_buttons(visible_trainable)
	_update_research_buttons(building_ref if has_command_authority else null)
	_queue_mobile_layout_refresh()
	if restore_queue_view:
		call_deferred("_restore_producer_queue_view", building_ref, queue_view_offset, _queue_navigation_revision)


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
	if _selection_info_button != null:
		# Full names remain available through the labeled summary Info target.
		return
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
		BuildingData.BuildingType.TOWN_CENTER:
			if building.player_owner != 0:
				return "Arrows + depot" if building.tower_attack_damage > 0 else "All drop-off"
			if building.rally_resource_instance_id > 0:
				return "Rally: %s" % building.rally_resource_type.capitalize()
			if building.has_custom_rally_point():
				return "Ground rally"
			return "Tap resource\nfor rally"
		BuildingData.BuildingType.HOUSE: return "+%d housing" % int(BuildingData.BUILDINGS[building.building_type].get("pop_provided", 0))
		BuildingData.BuildingType.MILL: return "Food drop-off"
		BuildingData.BuildingType.LUMBER_CAMP: return "Wood drop-off"
		BuildingData.BuildingType.MINING_CAMP: return "Gold drop-off"
		BuildingData.BuildingType.FARM: return "Food: %d remaining" % building.farm_remaining
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
	var compact_training: bool = minf(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y) <= 520.0
	queue_container.add_theme_constant_override("separation", 4 if compact_training else 6)
	if training_label != "" and not compact_training:
		desired_names["QueueTrainingChip"] = true
	for unit_type: int in queue_units:
		desired_names["QueueUnit_%s" % str(unit_type)] = true
	var repeat_waiting: bool = false
	if _is_human_owned_building(_selected_building_ref):
		var producer_queue: Node = _selected_building_ref.get_production_queue()
		repeat_waiting = producer_queue != null and bool(producer_queue.get("auto_queue_enabled")) and queue_items.is_empty()
	if repeat_waiting:
		desired_names["QueueWaitingLabel"] = true
	if not queue_items.is_empty() or repeat_waiting:
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

	if queue_items.is_empty() and not repeat_waiting:
		if _secondary_surface == SecondarySurface.QUEUE:
			_set_secondary_surface(SecondarySurface.NONE)
		queue_container.visible = false
		_queue_view_requested = false
		command_scroll.scroll_horizontal = 0
		_refresh_touch_target_diagnostics()
		return

	queue_container.visible = true
	var child_index := 0
	if repeat_waiting:
		var waiting_label: Label = queue_container.get_node_or_null("QueueWaitingLabel") as Label
		if waiting_label == null:
			waiting_label = Label.new()
			waiting_label.name = "QueueWaitingLabel"
			waiting_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			waiting_label.custom_minimum_size = Vector2(148, 48)
			waiting_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			waiting_label.add_theme_font_size_override("font_size", 12)
			queue_container.add_child(waiting_label)
		waiting_label.text = "Repeat waiting\n%s" % _get_repeat_wait_reason()
		queue_container.move_child(waiting_label, child_index)
		child_index += 1

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
		_attach_hud_hold(btn, _refund_information.bind(unit_type))
		btn.visible = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.text = ("%s\nx%d" if compact_training else "%s x%d") % [UnitData.get_unit_name(unit_type), queue_count]
		btn.tooltip_text = "Cancel first queued %s; keep the Repeat setting" % UnitData.get_unit_name(unit_type)
		btn.custom_minimum_size = Vector2(64 if compact_training else 104, 48)
		btn.add_theme_font_size_override("font_size", 11 if compact_training else 12)
		for style_name: String in ["normal", "hover", "pressed", "disabled"]:
			var queue_style: StyleBox = btn.get_theme_stylebox(style_name).duplicate()
			queue_style.set_content_margin(SIDE_LEFT, 4.0 if compact_training else 12.0)
			queue_style.set_content_margin(SIDE_RIGHT, 4.0 if compact_training else 12.0)
			btn.add_theme_stylebox_override(style_name, queue_style)
		queue_container.move_child(btn, child_index)
		child_index += 1

	var clear_last: Button = queue_container.get_node_or_null("QueueClearLastButton") as Button
	if clear_last == null:
		clear_last = Button.new()
		clear_last.name = "QueueClearLastButton"
		clear_last.pressed.connect(_on_clear_last_queue_pressed)
		queue_container.add_child(clear_last)
	clear_last.visible = not queue_items.is_empty()
	_attach_hud_hold(clear_last, _refund_information.bind(-1))
	clear_last.mouse_filter = Control.MOUSE_FILTER_STOP
	clear_last.text = "Undo"
	clear_last.tooltip_text = "Cancel last queued unit; keep the Repeat setting"
	clear_last.custom_minimum_size = Vector2(48 if compact_training else 64, 48)
	clear_last.add_theme_font_size_override("font_size", 13 if compact_training else 16)
	_apply_queue_cancel_padding(clear_last, compact_training)
	queue_container.move_child(clear_last, child_index)
	child_index += 1

	var clear_all: Button = queue_container.get_node_or_null("QueueClearAllButton") as Button
	if clear_all == null:
		clear_all = Button.new()
		clear_all.name = "QueueClearAllButton"
		clear_all.pressed.connect(_on_clear_all_queue_pressed)
		queue_container.add_child(clear_all)
	clear_all.visible = true
	_attach_hud_hold(clear_all, _refund_information.bind(-2))
	clear_all.mouse_filter = Control.MOUSE_FILTER_STOP
	clear_all.text = "Clear"
	clear_all.tooltip_text = "Stop repeat training and cancel all queued units"
	clear_all.custom_minimum_size = Vector2(48 if compact_training else 64, 48)
	clear_all.add_theme_font_size_override("font_size", 13 if compact_training else 16)
	_apply_queue_cancel_padding(clear_all, compact_training)
	queue_container.move_child(clear_all, child_index)

	if _ui_modal_state == UIModalState.BUILD_MENU:
		queue_container.visible = false
	_refresh_touch_target_diagnostics()


func _apply_queue_cancel_padding(button: Button, compact: bool) -> void:
	for style_name: String in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBox = button.get_theme_stylebox(style_name).duplicate()
		style.set_content_margin(SIDE_LEFT, 4.0 if compact else 12.0)
		style.set_content_margin(SIDE_RIGHT, 4.0 if compact else 12.0)
		button.add_theme_stylebox_override(style_name, style)


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
	# One request lets the producer stop Repeat before any cancellation refunds.
	# Do not depend on the HUD snapshot: repeat may now be waiting on an empty queue.
	_on_cancel_queue_pressed(ProductionQueue.CANCEL_ALL_INDEX)


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
			_queue_navigation_button = Button.new()
			_queue_navigation_button.name = "QueueNavigationButton"
			_queue_navigation_button.custom_minimum_size = Vector2(48, 48)
			_queue_navigation_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_queue_navigation_button.focus_mode = Control.FOCUS_NONE
			_queue_navigation_button.add_theme_font_size_override("font_size", 11)
			KingdomTheme.apply_secondary(_queue_navigation_button)
			_queue_navigation_button.button_down.connect(_on_queue_navigation_button_down)
			_queue_navigation_button.pressed.connect(_on_queue_navigation_pressed)
			selection_info_column.get_parent().add_child(_queue_navigation_button)
			command_scroll.get_h_scroll_bar().value_changed.connect(_refresh_queue_navigation)

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
	var compact_producer: bool = minf(viewport_size_for_cards.x, viewport_size_for_cards.y) <= 520.0
	var compact_town_center: bool = _is_town_center_production_context() and compact_producer
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
				cost_parts.append("%d%s" % [int(cost[resource]), resource.left(1).to_upper()] if compact_producer else "%d %s" % [int(cost[resource]), resource])
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
		_attach_hud_hold(btn, _train_information.bind(ut))
		btn.visible = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var role_text: String = UnitData.get_unit_counter_description(ut) if ut != UnitData.UnitType.VILLAGER else ""
		if compact_town_center and ut == UnitData.UnitType.SCOUT:
			role_text = "Recon"
		btn.text = "%s%s\n%s%s" % [unit_name, queue_badge, cost_str, "\n" + role_text if not role_text.is_empty() else ""]
		btn.custom_minimum_size = Vector2(74 if compact_town_center else 104, 48) if compact_producer else Vector2(130, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER if compact_town_center else HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11 if compact_producer or not role_text.is_empty() else 13)
		for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.remove_theme_stylebox_override(style_name)
			if compact_producer or not role_text.is_empty():
				var style: StyleBoxFlat = btn.get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
				style.set_content_margin(SIDE_LEFT, 4.0)
				style.set_content_margin(SIDE_RIGHT, 4.0)
				style.set_content_margin(SIDE_TOP, 4.0)
				style.set_content_margin(SIDE_BOTTOM, 4.0)
				btn.add_theme_stylebox_override(style_name, style)
		var icon_path: String = UnitData.get_unit_icon_path(ut)
		if compact_producer:
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
		_attach_hud_hold(_auto_queue_button, _repeat_information)
		_auto_queue_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_auto_queue_button.custom_minimum_size = Vector2(74 if compact_town_center else 88, 48) if compact_producer else Vector2(104, 48)
		_auto_queue_button.add_theme_font_size_override("font_size", 11 if compact_producer else 14)
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
	_queue_navigation_button.visible = _train_buttons_container.visible and selection_panel.visible and _auto_queue_button != null
	_queue_navigation_button.disabled = not has_queue_page or _ui_modal_state != UIModalState.NONE
	queue_container.custom_minimum_size.x = command_scroll.size.x if has_queue_page else 0.0
	if has_queue_page:
		# The queue begins on the next scroll page, so the initial shelf never
		# displays half a TRAIN label or half a cancellation button.
		var gap_width: float = maxf(0.0, command_scroll.size.x - _train_buttons_container.get_combined_minimum_size().x - 12.0)
		_queue_page_spacer.custom_minimum_size.x = gap_width
		if _queue_view_requested:
			call_deferred("_restore_producer_queue_view", _selected_building_ref, _queue_view_offset, _queue_navigation_revision)
	_refresh_queue_navigation()


func _refresh_queue_navigation(_value: float = 0.0) -> void:
	if _queue_navigation_button == null:
		return
	var queue_in_view: bool = queue_container.visible and command_scroll.scroll_horizontal > maxi(1, int(queue_container.position.x * 0.5))
	if queue_in_view and _secondary_surface != SecondarySurface.QUEUE and _ui_modal_state == UIModalState.NONE:
		_set_secondary_surface(SecondarySurface.QUEUE, true)
	elif not queue_in_view and _secondary_surface == SecondarySurface.QUEUE and not _queue_view_requested:
		# A deliberate return to recruitment must retire Queue ownership too.
		# A pending reconciliation can briefly clamp its scrollbar; keep that
		# requested page alive until its deferred restoration has completed.
		_set_secondary_surface(SecondarySurface.NONE)
	_queue_navigation_button.text = "Train\n‹" if queue_in_view else "Queue\n(%d)" % _last_queue_items.size()
	_queue_navigation_button.tooltip_text = "Return to recruitment" if queue_in_view else "Inspect production and cancel queued units"


func _restore_producer_queue_view(building_ref: Node2D, offset: int, revision: int) -> void:
	# Control reconciliation briefly changes content minima; restore after the
	# containers have sorted so their transient scrollbar clamp cannot hide work.
	await get_tree().process_frame
	await get_tree().process_frame
	if revision == _queue_navigation_revision and _queue_view_requested and _selected_building_ref == building_ref and queue_container.visible and selection_panel.visible:
		command_scroll.scroll_horizontal = int(queue_container.position.x) + offset
		_queue_view_requested = false


func _on_queue_navigation_button_down() -> void:
	var queue_in_view: bool = queue_container.visible and command_scroll.scroll_horizontal > maxi(1, int(queue_container.position.x * 0.5))
	_queue_navigation_intent = SecondarySurface.NONE if queue_in_view else SecondarySurface.QUEUE
	# A delayed reconciliation must not change the page chosen by this press.
	_queue_navigation_revision += 1
	_queue_view_requested = false


func _cancel_queue_navigation_press() -> void:
	if _queue_navigation_intent >= 0:
		_queue_navigation_intent = -2


func _on_queue_navigation_pressed() -> void:
	var intended_surface: int = _queue_navigation_intent
	_queue_navigation_intent = -1
	if intended_surface == -2 or not queue_container.visible:
		return
	var queue_in_view: bool = command_scroll.scroll_horizontal > maxi(1, int(queue_container.position.x * 0.5))
	if intended_surface < 0:
		intended_surface = SecondarySurface.NONE if queue_in_view else SecondarySurface.QUEUE
	_set_secondary_surface(intended_surface as SecondarySurface)


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
	_auto_queue_button.add_theme_font_size_override("font_size", 11 if _is_phone_context() else 14)
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
		if enabled and int(production_queue.call("get_queue_size")) == 0:
			_auto_queue_button.text += "\n" + _get_repeat_wait_reason()
			_auto_queue_button.add_theme_font_size_override("font_size", 11)
	if enabled:
		KingdomTheme.apply_primary(_auto_queue_button)
	else:
		KingdomTheme.apply_secondary(_auto_queue_button)
		_auto_queue_button.add_theme_color_override("font_hover_color", KingdomTheme.PARCHMENT)
		_auto_queue_button.add_theme_color_override("font_focus_color", KingdomTheme.PARCHMENT)
	_refresh_touch_target_diagnostics()


func _get_repeat_wait_reason() -> String:
	if not _is_human_owned_building(_selected_building_ref):
		return "Unavailable"
	var building := _selected_building_ref as BuildingBase
	if building.state != BuildingBase.State.ACTIVE:
		return "Building…" if building.state == BuildingBase.State.CONSTRUCTING else "Unavailable"
	var producer: Node = building.get_production_queue()
	var unit_type: int = int(producer.get("auto_queue_unit_type")) if producer != null else -1
	if unit_type < 0 or unit_type not in building.trainable_units:
		return "Train first"
	var gm: Node = _get_game_manager()
	if gm:
		var committed: int = gm.get_committed_population(building.player_owner)
		var cap: int = int(gm.players.get(building.player_owner, {}).get("population_cap", 0))
		var unit_pop: int = int(UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1))
		if committed + unit_pop > cap:
			return "Pop %d/%d" % [committed, cap]
	var rm: Node = _get_resource_manager()
	if rm:
		var missing: Dictionary = rm.get_missing_resources(building.player_owner, UnitData.get_unit_cost(unit_type))
		var shortages: PackedStringArray = []
		for resource: String in ["food", "wood", "gold"]:
			if int(missing.get(resource, 0)) > 0:
				shortages.append("%d%s" % [int(missing[resource]), resource.left(1).to_upper()])
		if not shortages.is_empty():
			return "Need " + " · ".join(shortages)
	return "Resuming…"


func _on_auto_queue_toggled(pressed: bool) -> void:
	if _is_human_owned_building(_selected_building_ref):
		var pq: Node = _selected_building_ref.get_production_queue() if _selected_building_ref.has_method("get_production_queue") else null
		if pq:
			pq.auto_queue_enabled = pressed
			_refresh_auto_queue_button(pq)
			_update_queue_display(pq.get_queue_info())
			_layout_queue_page()
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
	if child.has_meta("hud_hold_control"):
		var hold_component: Node = child.get_meta("hud_hold_control") as Node
		if is_instance_valid(hold_component):
			hold_component.call("detach")
	if child is Control:
		(child as Control).visible = false
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Move the old name out of the reconciliation namespace so a second refresh
	# in this frame can safely create a replacement before queue_free runs.
	child.name = "RetiredControl_%d" % child.get_instance_id()
	child.queue_free()


# --- Research buttons (Blacksmith) ---

const RESEARCH_DEFS: Array = TechData.RESEARCH_DEFS


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
		_attach_hud_hold(btn, _research_information.bind(research_id))
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
		btn.disabled = already_done or gm == null or not gm.can_research(b.player_owner, b, research_id)
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
	var sacred_phase: String = str(_sacred_site_status.get("phase", "neutral"))
	if sacred_phase in ["contested", "neutralizing"]:
		sacred_color = Color(1.0, 0.85, 0.2)
	elif int(_sacred_site_status.get("owner", -1)) == 0:
		sacred_color = Color(0.3, 0.6, 1.0)
	elif int(_sacred_site_status.get("owner", -1)) == 1:
		sacred_color = Color(1.0, 0.3, 0.3)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var px: int = sacred_x + dx
			var py: int = sacred_y + dy
			if px >= 0 and px < map_w and py >= 0 and py < map_h:
				# Objective location is public; terrain and enemies remain fogged.
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


func show_notification(text: String, color: Color = Color.WHITE, duration: float = NOTIFICATION_DURATION, action: Callable = Callable()) -> void:
	if _notification_container == null:
		return
	# Cap at max visible
	var overflow_count: int = maxi(0, _notification_container.get_child_count() - _mobile_notification_limit + 1)
	for child_index: int in range(overflow_count):
		_retire_dynamic_control(_notification_container.get_child(child_index))

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if action.is_valid():
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.custom_minimum_size.y = MOBILE_ACTION_BUTTON_HEIGHT
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if (event is InputEventScreenTouch and event.pressed) or (
				event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
			):
				action.call()
				panel.accept_event()
		)
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
	tween.tween_interval(duration)
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
		total_height += maxf(panel.custom_minimum_size.y, label.custom_minimum_size.y + 6.0) + 2.0
	while active_panels.size() > 1 and total_height - 2.0 > lane_height:
		var oldest: Control = active_panels.pop_front()
		total_height -= maxf(oldest.custom_minimum_size.y, (oldest.get_child(0) as Label).custom_minimum_size.y + 6.0) + 2.0
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

	var outer := VBoxContainer.new()
	var close_button := Button.new()
	close_button.text = "Close Help"
	close_button.custom_minimum_size = Vector2(104, 48)
	close_button.pressed.connect(close_secondary_surface)
	outer.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var hold_help := Label.new()
	hold_help.text = "Hold action buttons to inspect.\nHold More, slide to preview, release to choose.\nReturn to the center or outside to cancel.\nInfo opens these explanations by tapping.\nDisable hold shortcuts in Settings."
	hold_help.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hold_help)
	scroll.add_child(vbox)
	_hotkey_panel.add_child(outer)
	root_ctrl.add_child(_hotkey_panel)


func _toggle_hotkey_panel() -> void:
	if _hotkey_panel:
		_set_secondary_surface(SecondarySurface.NONE if _secondary_surface == SecondarySurface.HELP else SecondarySurface.HELP)


# --- Sacred Site Timer ---

func _create_sacred_site_label() -> void:
	var root_ctrl: Control = $Root
	_sacred_site_panel = PanelContainer.new()
	_sacred_site_panel.name = "SacredSiteChip"
	_sacred_site_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sacred_site_panel.offset_top = 110
	_sacred_site_panel.offset_bottom = 158
	_sacred_site_panel.offset_left = -118
	_sacred_site_panel.offset_right = 118
	_sacred_site_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_sacred_site_panel.visible = false
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = KingdomTheme.INK_LIGHT
	chip_style.border_color = KingdomTheme.BORDER
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(7)
	chip_style.set_content_margin_all(0)
	_sacred_site_panel.add_theme_stylebox_override("panel", chip_style)
	_sacred_site_button = Button.new()
	_sacred_site_button.name = "SacredSiteButton"
	_sacred_site_button.flat = true
	_sacred_site_button.focus_mode = Control.FOCUS_NONE
	_sacred_site_button.custom_minimum_size = Vector2(0.0, MOBILE_ACTION_BUTTON_HEIGHT)
	_sacred_site_button.pressed.connect(func() -> void: sacred_site_pressed.emit())
	_sacred_site_panel.add_child(_sacred_site_button)
	_sacred_site_label = Label.new()
	_sacred_site_label.name = "SacredSiteLabel"
	_sacred_site_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sacred_site_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sacred_site_label.add_theme_font_size_override("font_size", 12)
	_sacred_site_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sacred_site_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sacred_site_button.add_child(_sacred_site_label)
	root_ctrl.add_child(_sacred_site_panel)


func update_sacred_site_timer(player_id: int, remaining: float, total: float) -> void:
	# Keep this API for HUD-only previews. Runtime feedback uses the site's
	# authoritative phase, including holds paused by a contest or takeover.
	update_sacred_site_status({
		"phase": "holding" if player_id >= 0 else "neutral",
		"owner": player_id,
		"remaining": remaining,
		"total": total,
		"capture_progress": 1.0 if player_id >= 0 else 0.0,
	})


func update_sacred_site_status(status: Dictionary) -> void:
	if _sacred_site_label == null:
		return
	var first_status: bool = _sacred_site_status.is_empty()
	_sacred_site_status = status.duplicate()
	var phase: String = str(status.get("phase", "neutral"))
	var objective_title: String = "Sacred Site · tap to view"
	if phase == "contested":
		objective_title = "Sacred Site · Contested"
	elif phase == "neutralizing":
		objective_title = "Sacred Site · Disrupted"
	if int(status.get("match_mode", SkirmishData.MatchMode.STANDARD)) != SkirmishData.MatchMode.STANDARD:
		var scoring_state: String = "bank control"
		if phase == "holding":
			scoring_state = "You scoring" if int(status.get("owner", -1)) == 0 else "Enemy scoring"
		elif phase == "capturing":
			scoring_state = "capturing"
		if phase in ["contested", "neutralizing"]:
			scoring_state = "paused"
		objective_title = "Sacred %s · %s" % [_sacred_clock(float(status.get("total", 240.0))), scoring_state]
	_sacred_site_label.text = objective_title + "\n" + _sacred_site_status_line(status)
	_sacred_site_button.tooltip_text = _sacred_site_instructions(status)
	var owner: int = int(status.get("owner", -1))
	var color := Color(0.85, 0.7, 1.0)
	if phase in ["contested", "neutralizing"]:
		color = Color(1.0, 0.85, 0.3)
	elif owner == 0:
		color = Color(0.3, 0.7, 1.0)
	elif owner == 1:
		color = Color(1.0, 0.4, 0.3)
	_sacred_site_label.add_theme_color_override("font_color", color)
	if _selection_kind == "sacred":
		show_sacred_site_selection(status)
	if first_status:
		_queue_mobile_layout_refresh()


func _sacred_site_status_line(status: Dictionary) -> String:
	if int(status.get("match_mode", SkirmishData.MatchMode.STANDARD)) != SkirmishData.MatchMode.STANDARD:
		var banks: Array = status.get("control_banks", [0.0, 0.0])
		return "You %s · Enemy %s" % [_sacred_clock(float(banks[0])), _sacred_clock(float(banks[1]))]
	var owner_name: String = "You" if int(status.get("owner", -1)) == 0 else "Enemy"
	var remaining: int = maxi(0, ceili(float(status.get("remaining", 0.0))))
	var remaining_text: String = "%d:%02d" % [int(remaining / 60.0), remaining % 60]
	match str(status.get("phase", "neutral")):
		"capturing": return "%s capturing · %d%%" % [owner_name, floori(float(status.get("capture_progress", 0.0)) * 100.0)]
		"holding": return "%s win in %s" % [owner_name, remaining_text]
		"contested": return "%s %s paused" % [owner_name, remaining_text]
		"neutralizing": return "%s %s paused" % [owner_name, remaining_text]
	return "Neutral · enter the ring"


func _sacred_clock(seconds: float) -> String:
	var whole_seconds: int = maxi(0, floori(seconds))
	return "%d:%02d" % [int(whole_seconds / 60.0), whole_seconds % 60]


func _sacred_site_instructions(status: Dictionary) -> String:
	var total_seconds: int = maxi(0, ceili(float(status.get("total", 0.0))))
	var total_text: String = "%d:%02d" % [int(total_seconds / 60.0), total_seconds % 60]
	var mode: int = int(status.get("match_mode", SkirmishData.MatchMode.STANDARD))
	if mode != SkirmishData.MatchMode.STANDARD:
		var scoring_rule: String = "Contests pause scoring. Clear the ring to resume."
		return "Any living unit can capture. Bank %s of Sacred control to win; each side keeps its earned time across captures. %s Barracks, Range and Stable cost 100 wood; Feudal costs 250 food / 125 gold." % [total_text, scoring_rule]
	return "Any living unit, including Scouts and villagers, can capture. Keep units inside the ring with no enemies. Send units into an enemy-held ring to pause its clock; clear the defenders to neutralize it. An uncontested hold of %s wins, or destroy the enemy Town Center." % total_text


func show_sacred_site_selection(status: Dictionary) -> void:
	if _ui_modal_state == UIModalState.PAUSE_MENU:
		return
	var first_selection: bool = _selection_kind != "sacred"
	if first_selection:
		clear_selection()
		_selection_context_active = true
		_selection_kind = "sacred"
		_selection_full_name = "Sacred Site"
		selection_name.text = _selection_full_name
	selection_name.tooltip_text = _sacred_site_instructions(status)
	selection_hp_bar.max_value = 100.0
	selection_hp_bar.value = float(status.get("capture_progress", 0.0)) * 100.0
	var phase: String = str(status.get("phase", "neutral"))
	var owner_name: String = "You" if int(status.get("owner", -1)) == 0 else "Enemy"
	var remaining: int = maxi(0, ceili(float(status.get("remaining", 0.0))))
	var clock: String = "%d:%02d" % [int(remaining / 60.0), remaining % 60]
	match phase:
		"capturing": selection_details.text = "%s %d%%\n%s" % [owner_name, floori(float(status.get("capture_progress", 0.0)) * 100.0), "Stay in ring" if int(status.get("owner", -1)) == 0 else "Enter to contest"]
		"holding": selection_details.text = "%s · %s\n%s" % [owner_name, clock, "Hold to win" if int(status.get("owner", -1)) == 0 else "Enter to pause"]
		"contested": selection_details.text = "Contested\nClear enemies"
		"neutralizing": selection_details.text = "Disrupted\nStay in ring"
		_: selection_details.text = "Neutral\nEnter ring"
	if int(status.get("match_mode", SkirmishData.MatchMode.STANDARD)) != SkirmishData.MatchMode.STANDARD:
		selection_details.text = "%s\nBank %s · %s" % [_sacred_site_status_line(status), _sacred_clock(float(status.get("total", 240.0))), phase.capitalize()]
	selection_details.tooltip_text = _sacred_site_instructions(status)
	if first_selection:
		_queue_mobile_layout_refresh()


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
	_minimap_hint_label.offset_right = 0
	_minimap_hint_label.offset_top = 2
	_minimap_hint_label.offset_bottom = 18
	_minimap_hint_label.anchor_top = 0.0
	_minimap_hint_label.anchor_bottom = 0.0
	_minimap_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_minimap_hint_label.add_theme_font_size_override("font_size", 11)
	_minimap_hint_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.8))
	_minimap_hint_label.text = "MAP · tap to view"
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
		and _strategy_overview == null
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


# --- Secondary disclosure and HUD hold coordination ---

func get_secondary_surface_name() -> String:
	return SecondarySurface.keys()[_secondary_surface].to_lower()


func close_secondary_surface() -> bool:
	_prune_hold_components()
	var had_surface: bool = _secondary_surface != SecondarySurface.NONE or _queue_navigation_intent >= 0
	_cancel_queue_navigation_press()
	for component: Node in _hold_components:
		if is_instance_valid(component) and bool(component.call("is_gesture_active")):
			had_surface = true
	_set_secondary_surface(SecondarySurface.NONE)
	_cancel_hud_holds("surface dismissed")
	return had_surface


func set_selection_context_revision(revision: int, automatic_cleanup: bool = false) -> void:
	if revision == _selection_context_revision:
		return
	_selection_context_revision = revision
	# Economy and Army manage the whole player, so casualties must not remove
	# the sheet from beneath the next contact or reset its production scroll.
	if automatic_cleanup and _secondary_surface in [SecondarySurface.ECONOMY, SecondarySurface.ARMY]:
		_cancel_queue_navigation_press()
	else:
		close_secondary_surface()
	_cancel_hud_holds("selection changed")


func notify_world_gesture_started() -> bool:
	_cancel_queue_navigation_press()
	# Called only after actual world admission; GUI contacts cannot collapse a
	# reading surface. Blocking outside contacts belong to the dismissal shield.
	if _secondary_surface in [SecondarySurface.VIEW, SecondarySurface.MORE, SecondarySurface.QUEUE]:
		close_secondary_surface()
	return false


func begin_world_context() -> bool:
	if _ui_modal_state != UIModalState.NONE or _placement_mode_active:
		world_context_close_requested.emit()
		return false
	_set_secondary_surface(SecondarySurface.WORLD_CONTEXT)
	return true


func end_world_context() -> void:
	_world_context_rect = Rect2()
	if _secondary_surface == SecondarySurface.WORLD_CONTEXT:
		_set_secondary_surface(SecondarySurface.NONE)


func set_world_context_rect(bounds: Rect2) -> void:
	_world_context_rect = bounds


func _set_secondary_surface(surface: SecondarySurface, preserve_queue_scroll: bool = false, keep_hold: bool = false) -> void:
	var modal_inspection: bool = surface == SecondarySurface.INFO and (_active_hold_component != null or _info_from_build_menu) and _ui_modal_state == UIModalState.BUILD_MENU
	if surface != SecondarySurface.NONE and (_placement_mode_active or (_ui_modal_state != UIModalState.NONE and not modal_inspection)):
		return
	if surface == SecondarySurface.MORE and not _unit_commands_authorized:
		return
	if surface == SecondarySurface.QUEUE and (not queue_container.visible or not is_instance_valid(_selected_building_ref)):
		return
	var previous: SecondarySurface = _secondary_surface
	if surface in [SecondarySurface.VIEW, SecondarySurface.MORE, SecondarySurface.INFO, SecondarySurface.HELP, SecondarySurface.WORLD_CONTEXT]:
		_cancel_queue_navigation_press()
	_secondary_surface = surface
	if surface != SecondarySurface.INFO:
		_info_from_build_menu = false
	if not keep_hold:
		_cancel_hud_holds("replacement surface")
	# Assign first: synchronous popup-close callbacks must not replace the next
	# requested surface with NONE while the old presentation is being retired.
	if previous == SecondarySurface.WORLD_CONTEXT and surface != previous:
		_world_context_rect = Rect2()
		world_context_close_requested.emit()
	if surface != SecondarySurface.QUEUE:
		_queue_navigation_revision += 1
		_queue_view_requested = false
		_queue_view_offset = 0
		if previous == SecondarySurface.QUEUE:
			command_scroll.scroll_horizontal = 0
	elif previous != SecondarySurface.QUEUE or not preserve_queue_scroll:
		_queue_navigation_revision += 1
		_queue_view_requested = true
		_queue_view_offset = maxi(0, command_scroll.scroll_horizontal - int(queue_container.position.x)) if preserve_queue_scroll else 0
		if not preserve_queue_scroll:
			command_scroll.scroll_horizontal = int(queue_container.position.x)
	_camera_controls_expanded = surface == SecondarySurface.VIEW
	_advanced_commands_open = surface == SecondarySurface.MORE
	if _unit_more_button:
		_unit_more_button.set_pressed_no_signal(_advanced_commands_open)
	if _advanced_command_panel:
		_advanced_command_panel.visible = _advanced_commands_open and not _hold_chooser_active and _unit_commands_authorized
	if _hotkey_panel:
		_hotkey_panel.visible = surface == SecondarySurface.HELP
	if _info_panel:
		_info_panel.visible = surface == SecondarySurface.INFO and _active_hold_component == null
	if _strategy_overview:
		_strategy_overview.set_surface(get_secondary_surface_name())
	if surface != SecondarySurface.MORE:
		_hold_chooser_active = false
	_refresh_dismissal_shield()
	_queue_mobile_layout_refresh()
	if previous != surface:
		secondary_surface_changed.emit(get_secondary_surface_name())


func _create_secondary_surface_controls() -> void:
	_secondary_dismissal_shield = DISMISS_SHIELD_SCRIPT.new()
	_secondary_dismissal_shield.name = "SecondaryDismissalShield"
	_secondary_dismissal_shield.z_index = 50
	add_child(_secondary_dismissal_shield)
	_secondary_dismissal_shield.connect("dismiss_requested", close_secondary_surface)
	_info_panel = PanelContainer.new()
	_info_panel.name = "SelectionInfoPanel"
	_info_panel.z_index = 60
	_info_panel.visible = false
	_info_panel.add_theme_stylebox_override("panel", KingdomTheme.panel_style())
	add_child(_info_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_info_panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_info_title = Label.new()
	_info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_title.add_theme_font_size_override("font_size", 16)
	_info_title.clip_text = true
	header.add_child(_info_title)
	var close_button := Button.new()
	close_button.name = "InfoCloseButton"
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(64, 48)
	close_button.pressed.connect(close_secondary_surface)
	header.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.name = "InfoScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_info_body = Label.new()
	_info_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.add_theme_font_size_override("font_size", 13)
	scroll.add_child(_info_body)
	# The whole existing summary is the 48px Info target, with a small visible
	# header handle. It consumes no additional command-row width or dock height.
	_selection_name_header = HBoxContainer.new()
	_selection_name_header.name = "SelectionNameHeader"
	_selection_name_header.add_theme_constant_override("separation", 6)
	selection_info_column.add_child(_selection_name_header)
	selection_info_column.move_child(_selection_name_header, 0)
	selection_name.reparent(_selection_name_header)
	selection_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var info_handle := Label.new()
	info_handle.text = "Info ›"
	info_handle.add_theme_font_size_override("font_size", 10)
	info_handle.add_theme_color_override("font_color", KingdomTheme.AMBER)
	_selection_name_header.add_child(info_handle)
	_selection_info_button = Button.new()
	_selection_info_button.name = "SelectionInfoButton"
	_selection_info_button.flat = true
	_selection_info_button.focus_mode = Control.FOCUS_NONE
	_selection_info_button.z_index = 1
	_selection_info_button.tooltip_text = "Info: names, costs, roles and current orders"
	for style_name: String in ["normal", "hover", "pressed", "focus"]:
		_selection_info_button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	_selection_info_button.pressed.connect(_show_selection_information)
	$Root.add_child(_selection_info_button)
	_hotkey_panel.z_index = 60
	_attach_hud_hold(_unit_more_button, _selection_information, _more_hold_choices)


func _layout_summary_info_target() -> void:
	if _selection_info_button == null:
		return
	_selection_info_button.position = selection_info_column.get_global_rect().position
	_selection_info_button.size = Vector2(selection_info_column.size.x, maxf(48.0, selection_info_column.size.y))


func _layout_secondary_cards() -> void:
	var card_area: Rect2 = get_hold_safe_rect()
	var card_size := Vector2(minf(440.0, card_area.size.x - 24.0), minf(300.0, card_area.size.y - 16.0))
	var card_position: Vector2 = card_area.position + (card_area.size - card_size) * 0.5
	if _info_panel:
		_info_panel.position = card_position
		_info_panel.size = card_size
	if _hotkey_panel:
		_hotkey_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_hotkey_panel.position = card_position
		_hotkey_panel.size = card_size


func _refresh_dismissal_shield() -> void:
	if _secondary_dismissal_shield:
		var protected: Array[Rect2] = []
		if is_instance_valid(_pause_button) and _pause_button.is_visible_in_tree() and not _pause_button.disabled:
			protected.append(_pause_button.get_global_rect())
		if _strategy_overview and _strategy_overview.rail.is_visible_in_tree():
			protected.append(_strategy_overview.rail.get_global_rect())
		_secondary_dismissal_shield.set("protected_rects", protected)
		_secondary_dismissal_shield.call("set_active", _secondary_surface in [SecondarySurface.HELP, SecondarySurface.WORLD_CONTEXT, SecondarySurface.ECONOMY, SecondarySurface.ARMY] or (_secondary_surface == SecondarySurface.INFO and _active_hold_component == null))


func _show_selection_information() -> void:
	if not _selection_context_active:
		return
	show_card_information(_selection_information())


func show_card_information(info: Dictionary) -> void:
	# Build's tap-inspection mode uses the same persistent card while retaining
	# its modal palette. The shield owns an outside dismissal through release.
	if _placement_mode_active or _ui_modal_state not in [UIModalState.NONE, UIModalState.BUILD_MENU]:
		return
	_cancel_hud_holds("tap information")
	_info_from_build_menu = _ui_modal_state == UIModalState.BUILD_MENU
	_info_title.text = str(info.get("title", "Info"))
	_info_body.text = str(info.get("body", ""))
	(_info_panel.find_child("InfoScroll", true, false) as ScrollContainer).scroll_vertical = 0
	# Native GUI hit testing traverses sibling order. Build is added after HUD
	# ready, so raise both direct CanvasLayer children whenever Info is opened.
	move_child(_secondary_dismissal_shield, get_child_count() - 1)
	move_child(_info_panel, get_child_count() - 1)
	_set_secondary_surface(SecondarySurface.INFO)


func _selection_information() -> Dictionary:
	var lines: PackedStringArray = []
	lines.append("HP %d / %d" % [int(selection_hp_bar.value), int(selection_hp_bar.max_value)])
	if not selection_details.text.is_empty():
		lines.append(selection_details.text)
	if _selection_kind == "unit":
		lines.append("Move: choose a destination. Attack: move and fight on the way. Tap the armed command again to cancel.")
		lines.append("More: Stop, Stance and %s. Hold More, slide to preview, release to choose; return to the center to cancel." % ("Patrol" if _unit_commands_have_military else "Idle workers"))
	elif is_instance_valid(_selected_building_ref):
		for container: Control in [_train_buttons_container, _research_container, queue_container]:
			if container:
				for child: Node in container.get_children():
					if child is Button and child.has_meta("hud_hold_control"):
						var component: Node = child.get_meta("hud_hold_control") as Node
						if is_instance_valid(component):
							_append_information(lines, component.call("get_info"))
		# Refund rules remain inspectable when no queue has been purchased yet.
		if _last_queue_items.is_empty():
			_append_information(lines, _refund_information(-1))
			_append_information(lines, _refund_information(-2))
	lines.append("Hold action buttons to inspect. Short taps keep their normal action. Hold shortcuts can be disabled in Settings.")
	return {"title": _selection_full_name, "body": "\n\n".join(lines)}


func _append_information(lines: PackedStringArray, info: Dictionary) -> void:
	var title: String = str(info.get("title", ""))
	var body: String = str(info.get("body", ""))
	if not body.is_empty():
		lines.append((title + "\n" if not title.is_empty() else "") + body)


func _more_hold_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = [
		{"id": "stop", "label": "Stop", "description": "Stop the selected units.", "enabled": _unit_commands_authorized},
	]
	if _unit_commands_have_military:
		choices.append({"id": "patrol", "label": "Patrol", "description": "Arm Patrol, then tap a world destination.", "enabled": true})
	choices.append({"id": "stance", "label": "Stance", "description": _unit_stance_button.tooltip_text, "enabled": _unit_commands_authorized})
	if _selection_is_worker and not _unit_commands_have_military:
		choices.append({"id": "idle", "label": "Idle workers", "description": "Select the next idle worker.", "enabled": _last_idle_villager_count > 0})
	return choices


func _attach_hud_hold(button: Button, info_provider: Callable, choices_provider: Callable = Callable()) -> void:
	if button == null or button.has_meta("hud_hold_control"):
		return
	var component: Node = HUD_HOLD_SCRIPT.attach_to(button, self, info_provider, _hud_hold_context.bind(button), get_hold_safe_rect, choices_provider)
	component.set("admission_provider", func() -> bool:
		var gm: Node = _get_game_manager()
		return (gm == null or gm.current_state == gm.GameState.PLAYING) and _ui_modal_state == UIModalState.NONE and not _placement_mode_active and _secondary_surface not in [SecondarySurface.INFO, SecondarySurface.HELP, SecondarySurface.WORLD_CONTEXT]
	)
	register_hold_component(component)


func register_hold_component(component: Node) -> void:
	_prune_hold_components()
	if component == null or _hold_components.has(component):
		return
	_hold_components.append(component)
	if component.has_signal("ownership_started"):
		component.connect("ownership_started", func(_contact_id: int) -> void: world_gesture_cancel_requested.emit())
	component.connect("surface_opened", _on_hold_surface_opened.bind(component))
	component.connect("surface_closed", _on_hold_surface_closed.bind(component))
	component.connect("choice_selected", _on_hold_choice_selected)


func _on_hold_surface_opened(kind: String, component: Node) -> void:
	_cancel_hud_holds("replacement hold", component)
	_active_hold_component = component
	_hold_chooser_active = kind == "chooser"
	_set_secondary_surface(SecondarySurface.MORE if _hold_chooser_active else SecondarySurface.INFO, false, true)
	if _secondary_surface not in [SecondarySurface.MORE, SecondarySurface.INFO]:
		_cancel_hud_holds("modal priority")
	elif not _hold_hints_shown.has(kind):
		_hold_hints_shown[kind] = true
		show_notification("Slide to preview. Return to center to cancel." if kind == "chooser" else "Holding only inspects. Release to close.", KingdomTheme.MUTED, 2.5)


func _on_hold_surface_closed(component: Node) -> void:
	if _active_hold_component != component:
		return
	_active_hold_component = null
	_hold_chooser_active = false
	if _secondary_surface in [SecondarySurface.MORE, SecondarySurface.INFO]:
		_set_secondary_surface(SecondarySurface.NONE)


func _on_hold_choice_selected(action_id: Variant) -> void:
	match str(action_id):
		"stop": _on_unit_stop_pressed()
		"patrol": _on_unit_patrol_pressed()
		"stance": _on_unit_stance_pressed()
		"idle":
			close_secondary_surface()
			_on_idle_villager_pressed()


func _cancel_hud_holds(reason: String, except_component: Node = null) -> void:
	_prune_hold_components()
	if _active_hold_component != except_component:
		_active_hold_component = null
		_hold_chooser_active = false
	for component: Node in _hold_components:
		if is_instance_valid(component) and component != except_component:
			component.call("cancel_gesture", reason)


func _prune_hold_components() -> void:
	for index: int in range(_hold_components.size() - 1, -1, -1):
		if not is_instance_valid(_hold_components[index]):
			_hold_components.remove_at(index)


func _hud_hold_context(button: Button) -> Dictionary:
	var context: Dictionary = {"revision": _selection_context_revision}
	if not is_instance_valid(button):
		return context
	if String(button.name).begins_with("Queue"):
		if button.has_meta("unit_type"):
			var unit_type: int = int(button.get_meta("unit_type"))
			context["waiting_count"] = int(_queue_counts_by_unit.get(unit_type, 0))
		else:
			context["size"] = _last_queue_items.size()
			if String(button.name) == "QueueClearLastButton" and not _last_queue_items.is_empty():
				context["last_type"] = int((_last_queue_items.back() as Dictionary).get("unit_type", -1))
	return context


func _full_cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for resource: String in ["food", "wood", "gold"]:
		if int(cost.get(resource, 0)) > 0:
			parts.append("%d %s" % [int(cost[resource]), resource])
	return " · ".join(parts)


func _train_information(unit_type: int) -> Dictionary:
	var stats: Dictionary = UnitData.UNITS.get(unit_type, {})
	var body: String = "Cost: %s\nPopulation: %d · Training: %ds\nHP %d · Attack %d · Armor %d" % [_full_cost_text(UnitData.get_unit_cost(unit_type)), int(stats.get("pop_cost", 1)), int(stats.get("build_time", 15)), int(stats.get("hp", 0)), int(stats.get("damage", 0)), int(stats.get("armor", 0))]
	var role: String = UnitData.get_unit_counter_description(unit_type)
	if not role.is_empty():
		body += "\n" + role
	body += "\nRequires an active producer, enough resources and free committed population.\nTap to train one. Holding only inspects."
	return {"title": UnitData.get_unit_name(unit_type), "body": body}


func _repeat_information() -> Dictionary:
	var unit_type: int = -1
	var enabled := false
	if _is_human_owned_building(_selected_building_ref):
		var queue: Node = _selected_building_ref.get_production_queue()
		if queue:
			unit_type = int(queue.get("auto_queue_unit_type"))
			enabled = bool(queue.get("auto_queue_enabled"))
	var unit_name: String = UnitData.get_unit_name(unit_type) if unit_type >= 0 else "the last unit trained"
	var body: String = "Repeat is %s.\nRepeats %s through the normal paid training queue.\nEach unit costs %s.\nWaits for resources or population space.\nCurrent status: %s\nTap to toggle. Holding only inspects." % ["ON" if enabled else "OFF", unit_name, _full_cost_text(UnitData.get_unit_cost(unit_type)) if unit_type >= 0 else "its normal resource cost", _get_repeat_wait_reason()]
	return {"title": "Repeat training", "body": body}


func _research_information(research_id: String) -> Dictionary:
	for research: Dictionary in RESEARCH_DEFS:
		if str(research.get("id", "")) == research_id:
			return {"title": research.get("name", "Research"), "body": "%s\nCost: %s\nRequires your active Blacksmith and sufficient resources. Completed research cannot be bought again.\nTap to research. Holding only inspects." % [research.get("desc", ""), _full_cost_text(research.get("cost", {}))]}
	return {"title": "Research", "body": "Unavailable in this context."}


func _refund_information(unit_type: int) -> Dictionary:
	var title: String = "Cancel queued %s" % UnitData.get_unit_name(unit_type) if unit_type >= 0 else ("Clear production" if unit_type == -2 else "Undo last queued unit")
	var body: String = "Refunds the full paid resource cost and releases reserved population.\n"
	if unit_type == -2:
		body += "Stops Repeat and cancels all current and queued training. Even the active unit receives its full cost."
	elif unit_type == -1:
		body += "Cancels the last queue item. Repeat stays at its current setting."
	else:
		body += "Cancels the first waiting unit of this type; current training continues. Repeat stays at its current setting.\nRefund: " + _full_cost_text(UnitData.get_unit_cost(unit_type))
	body += "\nTap to cancel. Holding only inspects and refunds nothing."
	return {"title": title, "body": body}


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


func setup_strategy_overview() -> StrategyOverview:
	if _strategy_overview:
		return _strategy_overview
	_strategy_overview = preload("res://scripts/ui/strategy_overview.gd").new()
	_strategy_overview.name = "StrategyOverview"
	add_child(_strategy_overview)
	_strategy_overview.surface_requested.connect(_on_strategy_surface_requested)
	_strategy_overview.world_gesture_cancel_requested.connect(func() -> void: world_gesture_cancel_requested.emit())
	_strategy_overview.base_requested.connect(func() -> void:
		close_secondary_surface()
		town_center_pressed.emit())
	_strategy_overview.army_requested.connect(func() -> void:
		close_secondary_surface()
		select_all_military_pressed.emit())
	_strategy_overview.army_focus_requested.connect(func() -> void:
		close_secondary_surface()
		find_army_pressed.emit())
	_strategy_overview.idle_requested.connect(_on_idle_villager_pressed)
	_queue_mobile_layout_refresh()
	return _strategy_overview


func _on_strategy_surface_requested(surface: String) -> void:
	# Native GUI uses sibling order as well as z-index. Raise the shield then
	# the sheet so later BuildMenu children cannot receive management contacts.
	move_child(_secondary_dismissal_shield, get_child_count() - 1)
	move_child(_strategy_overview, get_child_count() - 1)
	_set_secondary_surface(SecondarySurface.ECONOMY if surface == "economy" else (SecondarySurface.ARMY if surface == "army" else SecondarySurface.NONE))


func get_strategy_overview_bounds() -> Array[Rect2]:
	return _strategy_overview.get_visible_bounds() if _strategy_overview else []


func get_base_navigation_button() -> Button:
	return _strategy_overview.rail.get_node("BaseButton") as Button if _strategy_overview else _town_center_button
