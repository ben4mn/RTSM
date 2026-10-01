extends Control
## Quick-start menu. The kingdom takes center stage; advanced setup lives in settings.

const THEME := preload("res://scripts/ui/kingdom_theme.gd")
const DIORAMA := preload("res://scripts/ui/menu_diorama.gd")
const WEB_SHELL_BRIDGE := preload("res://scripts/ui/web_shell_bridge.gd")

enum Difficulty {
	EASY,
	MEDIUM,
	HARD,
}

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Medium", "Hard"]
const DIFFICULTY_DESCRIPTIONS: Array[String] = [
	"A little breathing room to build your kingdom.",
	"Steady raids. A worthy rival for your kingdom.",
	"Early attacks. Every villager and order counts.",
]
const CAMERA_SPEED_VALUES: Array[float] = [0.75, 1.0, 1.25]
const UI_SCALE_VALUES: Array[float] = [1.0, 1.075, 1.15]
const COMPACT_LAYOUT_MAX_HEIGHT: float = 500.0
const COMPACT_SETTINGS_CONTROLS_TEXT: String = "Tap selects/commands • unit rail has battle orders • drag pans • pinch zooms"
const FULL_SETTINGS_CONTROLS_TEXT: String = "Touch: tap to select or command • owned buildings reselect directly • drag to pan • pinch to zoom\nSelected units expose Move, A-Move, Patrol, Stop, stance, and Clear • hold a world target for context"

@onready var title_label: Label = %TitleLabel
@onready var promise_label: Label = %PromiseLabel
@onready var map_summary_label: Label = %MapSummaryLabel
@onready var start_button: Button = %StartButton
@onready var difficulty_option: OptionButton = %DifficultyOption
@onready var difficulty_description: Label = %DifficultyDescription
@onready var seed_input: LineEdit = %SeedInput
@onready var random_seed_button: Button = %RandomSeedButton
@onready var guided_opening_toggle: CheckButton = %GuidedOpeningToggle
@onready var settings_button: Button = %SettingsButton
@onready var settings_overlay: ColorRect = %SettingsOverlay
@onready var settings_close_button: Button = %SettingsCloseButton
@onready var audio_toggle: CheckButton = %AudioToggle
@onready var camera_speed_option: OptionButton = %CameraSpeedOption
@onready var ui_scale_option: OptionButton = %UIScaleOption
@onready var content_center: CenterContainer = $CenterContainer
@onready var content_vbox: VBoxContainer = $CenterContainer/VBox
@onready var subtitle_label: Label = $CenterContainer/VBox/Subtitle
@onready var content_spacer: Control = $CenterContainer/VBox/Spacer
@onready var setup_margin: MarginContainer = $CenterContainer/VBox/SetupPanel/SetupMargin
@onready var setup_vbox: VBoxContainer = $CenterContainer/VBox/SetupPanel/SetupMargin/SetupVBox
@onready var map_heading: Label = $CenterContainer/VBox/SetupPanel/SetupMargin/SetupVBox/MapHeading
@onready var difficulty_label: Label = $CenterContainer/VBox/SetupPanel/SetupMargin/SetupVBox/DifficultyLabel
@onready var seed_label: Label = $CenterContainer/VBox/SetupPanel/SetupMargin/SetupVBox/SeedLabel
@onready var actions_spacer: Control = $CenterContainer/VBox/Spacer2
@onready var actions_row: VBoxContainer = $CenterContainer/VBox/ActionsRow
@onready var settings_center: CenterContainer = $SettingsOverlay/Center
@onready var settings_panel: PanelContainer = $SettingsOverlay/Center/Panel
@onready var settings_margin: MarginContainer = $SettingsOverlay/Center/Panel/Margin
@onready var settings_vbox: VBoxContainer = $SettingsOverlay/Center/Panel/Margin/VBox
@onready var settings_title: Label = $SettingsOverlay/Center/Panel/Margin/VBox/Title
@onready var settings_controls: Label = $SettingsOverlay/Center/Panel/Margin/VBox/Controls
@onready var camera_speed_label: Label = $SettingsOverlay/Center/Panel/Margin/VBox/CameraSpeedLabel
@onready var ui_scale_label: Label = $SettingsOverlay/Center/Panel/Margin/VBox/UIScaleLabel
@onready var guidance_note: Label = $SettingsOverlay/Center/Panel/Margin/VBox/GuidanceNote

@export var main_menu_diagnostics: Dictionary = {}

var _selected_difficulty: int = Difficulty.EASY
var _compact_layout: bool = false
var _active_safe_area: Rect2 = Rect2()
var _hero: Control
var _hero_labels: VBoxContainer
var _hero_art: Control
var _hero_caption: Label
var _difficulty_buttons: Array[Button] = []
var _difficulty_row: HBoxContainer
var _settings_columns: HBoxContainer
var _preferences_column: VBoxContainer
var _advanced_column: VBoxContainer
var _advanced_title: Label
var _population_buttons: Array[Button] = []
var _population_choices: HBoxContainer = null
var _settings_header: HBoxContainer = null
var _selected_population_limit: int = SkirmishData.DEFAULT_POPULATION_LIMIT


func _ready() -> void:
	# A menu scene can be entered from pause, summary, or directly during test
	# setup. Normalize the global match state immediately in every route.
	GameManager.set_state(GameManager.GameState.MENU)
	WEB_SHELL_BRIDGE.set_controls_visible(true)
	theme = THEME.create_theme()
	_build_quick_start_presentation()
	start_button.pressed.connect(_on_start_pressed)
	random_seed_button.pressed.connect(_on_random_seed_pressed)
	guided_opening_toggle.toggled.connect(_on_guided_opening_toggled)
	settings_button.pressed.connect(_on_settings_pressed)
	settings_close_button.pressed.connect(_on_settings_close_pressed)
	audio_toggle.toggled.connect(_on_audio_toggled)
	camera_speed_option.item_selected.connect(_on_camera_speed_selected)
	ui_scale_option.item_selected.connect(_on_ui_scale_selected)
	seed_input.text_changed.connect(_on_seed_text_changed)
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	# Populate difficulty dropdown
	difficulty_option.clear()
	for i in range(DIFFICULTY_NAMES.size()):
		difficulty_option.add_item(DIFFICULTY_NAMES[i], i)
	_selected_difficulty = clampi(GameManager.selected_difficulty, Difficulty.EASY, Difficulty.HARD)
	_selected_population_limit = GameManager.selected_population_limit
	_refresh_population_choices()
	difficulty_option.selected = _selected_difficulty
	difficulty_option.item_selected.connect(_on_difficulty_changed)
	_apply_difficulty_description()

	if GameManager.selected_map_seed >= 0:
		seed_input.text = str(GameManager.selected_map_seed)
	else:
		seed_input.placeholder_text = "Random each match"
	guided_opening_toggle.button_pressed = bool(GameManager.guided_opening_enabled)
	_setup_settings_controls()
	_apply_responsive_layout()
	# Container geometry settles after `_ready()`. Refresh on the next frame so
	# diagnostics and injected touch coordinates describe the rendered controls,
	# not their pre-layout positions.
	call_deferred("_refresh_responsive_layout")


func _exit_tree() -> void:
	WEB_SHELL_BRIDGE.set_controls_visible(false)


func _build_quick_start_presentation() -> void:
	$Background.color = THEME.INK
	$BackdropGlow.color = Color(0.17, 0.29, 0.32, 0.18)
	$BackdropGlow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$BackdropGlow.hide()
	_hero = Control.new()
	_hero.name = "KingdomPreview"
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)
	move_child(_hero, $CenterContainer.get_index())
	_hero_labels = VBoxContainer.new()
	_hero_labels.add_theme_constant_override("separation", 3)
	_hero_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(_hero_labels)
	for label: Label in [subtitle_label, title_label, promise_label]:
		label.reparent(_hero_labels)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.text = "Pocket Kingdoms"
	title_label.add_theme_color_override("font_color", THEME.PARCHMENT)
	subtitle_label.text = "A KINGDOM IN YOUR POCKET"
	subtitle_label.add_theme_color_override("font_color", THEME.AMBER)
	promise_label.text = "Build a village. Raise an army.\nHold the sacred ground."
	promise_label.add_theme_color_override("font_color", THEME.MUTED)
	_hero_art = Control.new()
	_hero_art.set_script(DIORAMA)
	_hero.add_child(_hero_art)
	_hero_caption = Label.new()
	_hero_caption.text = "1v1 VS AI  /  20–40 POPULATION"
	_hero_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_caption.add_theme_color_override("font_color", THEME.MUTED)
	_hero_caption.add_theme_font_size_override("font_size", 12)
	_hero.add_child(_hero_caption)
	content_spacer.hide()
	actions_spacer.hide()
	map_summary_label.hide()
	map_heading.text = "PLAY A SKIRMISH"
	map_heading.add_theme_color_override("font_color", THEME.AMBER)
	difficulty_label.text = "Choose your rival"
	difficulty_option.hide()
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.name = "DifficultyChoices"
	_difficulty_row.add_theme_constant_override("separation", 6)
	setup_vbox.add_child(_difficulty_row)
	setup_vbox.move_child(_difficulty_row, difficulty_option.get_index())
	var group := ButtonGroup.new()
	for index: int in DIFFICULTY_NAMES.size():
		var button := Button.new()
		button.name = "%sDifficulty" % DIFFICULTY_NAMES[index]
		button.text = DIFFICULTY_NAMES[index]
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 48)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_on_difficulty_changed.bind(index))
		_difficulty_row.add_child(button)
		_difficulty_buttons.append(button)
	difficulty_description.add_theme_color_override("font_color", THEME.MUTED)
	guided_opening_toggle.text = "Guide my first steps"
	guided_opening_toggle.add_theme_color_override("font_color", THEME.PARCHMENT)
	start_button.text = "Play skirmish  ›"
	settings_button.text = "Settings & map"
	THEME.apply_primary(start_button)
	THEME.apply_secondary(settings_button)
	_settings_columns = HBoxContainer.new()
	_settings_columns.add_theme_constant_override("separation", 20)
	settings_vbox.add_child(_settings_columns)
	settings_vbox.move_child(_settings_columns, 2)
	_preferences_column = VBoxContainer.new()
	_preferences_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preferences_column.add_theme_constant_override("separation", 5)
	_settings_columns.add_child(_preferences_column)
	for control: Control in [audio_toggle, camera_speed_label, camera_speed_option, ui_scale_label, ui_scale_option]:
		control.reparent(_preferences_column)
	_advanced_column = VBoxContainer.new()
	_advanced_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_advanced_column.add_theme_constant_override("separation", 5)
	_settings_columns.add_child(_advanced_column)
	_advanced_title = Label.new()
	_advanced_title.text = "ADVANCED MAP"
	_advanced_title.add_theme_font_size_override("font_size", 12)
	_advanced_title.add_theme_color_override("font_color", THEME.AMBER)
	_advanced_column.add_child(_advanced_title)
	seed_label.text = "Map seed (optional)"
	seed_label.reparent(_advanced_column)
	seed_input.reparent(_advanced_column)
	random_seed_button.reparent(_advanced_column)
	random_seed_button.text = "Use a random map"
	settings_controls.reparent(_advanced_column)
	settings_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	settings_controls.add_theme_color_override("font_color", THEME.MUTED)
	setup_vbox.get_node("SeedRow").hide()
	guidance_note.hide()
	settings_title.text = "Make yourself at home"
	camera_speed_label.text = "Camera speed"
	ui_scale_label.text = "Interface size"
	settings_overlay.color = Color(0.025, 0.055, 0.08, 0.94)
	THEME.apply_primary(settings_close_button)
	_build_population_choices()


func _build_population_choices() -> void:
	_settings_header = HBoxContainer.new()
	_settings_header.name = "SettingsHeader"
	_settings_header.add_theme_constant_override("separation", 10)
	settings_vbox.add_child(_settings_header)
	settings_vbox.move_child(_settings_header, 0)
	settings_title.reparent(_settings_header)
	settings_title.text = "Skirmish settings"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	settings_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var population_label := Label.new()
	population_label.text = "Max pop per player\nincluding workers"
	population_label.add_theme_font_size_override("font_size", 12)
	population_label.add_theme_color_override("font_color", THEME.MUTED)
	population_label.tooltip_text = "Population limit per player, including workers. Houses provide room up to this limit."
	_settings_header.add_child(population_label)
	_population_choices = HBoxContainer.new()
	_population_choices.name = "PopulationChoices"
	_population_choices.add_theme_constant_override("separation", 4)
	_settings_header.add_child(_population_choices)
	var group := ButtonGroup.new()
	for limit: int in SkirmishData.POPULATION_OPTIONS:
		var button := Button.new()
		button.name = "Population%dButton" % limit
		button.text = str(limit)
		button.custom_minimum_size = Vector2(48, 48)
		button.add_theme_font_size_override("font_size", 15)
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = "%d population per player, including workers" % limit
		button.pressed.connect(_on_population_selected.bind(limit))
		_population_choices.add_child(button)
		_population_buttons.append(button)
	_refresh_population_choices()


func _on_population_selected(limit: int) -> void:
	_selected_population_limit = limit
	GameManager.selected_population_limit = limit
	GameManager.save_preferences()
	_refresh_population_choices()
	_refresh_main_menu_diagnostics()


func _refresh_population_choices() -> void:
	for button: Button in _population_buttons:
		button.set_pressed_no_signal(int(button.text) == _selected_population_limit)


func _setup_settings_controls() -> void:
	audio_toggle.button_pressed = GameManager.audio_enabled
	camera_speed_option.clear()
	for label in ["Relaxed", "Standard", "Fast"]:
		camera_speed_option.add_item(label)
	camera_speed_option.selected = _nearest_value_index(CAMERA_SPEED_VALUES, GameManager.camera_speed_scale)
	ui_scale_option.clear()
	for label in ["Standard", "Large", "Extra Large"]:
		ui_scale_option.add_item(label)
	ui_scale_option.selected = _nearest_value_index(UI_SCALE_VALUES, GameManager.ui_scale)


func _nearest_value_index(values: Array[float], target: float) -> int:
	var best_index: int = 0
	var best_distance: float = INF
	for i in values.size():
		var distance: float = absf(values[i] - target)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if not is_node_ready():
			return
		call_deferred("_refresh_responsive_layout")


func _on_viewport_size_changed() -> void:
	call_deferred("_refresh_responsive_layout")


func _refresh_responsive_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))
	# Web canvas resizes can publish width and height on adjacent frames. Re-read
	# the viewport once after the first layout pass so an orientation/viewport
	# change cannot leave the menu vertically centered against the old height.
	call_deferred("_settle_responsive_layout")


func _settle_responsive_layout() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))
	content_center.queue_sort()
	settings_center.queue_sort()
	# This final deferred call runs after the container sorts queued above.
	call_deferred("_refresh_main_menu_diagnostics_if_ready")


func _refresh_main_menu_diagnostics_if_ready() -> void:
	if is_inside_tree() and is_node_ready():
		_refresh_main_menu_diagnostics()


func _apply_responsive_layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))


func apply_mobile_layout(viewport_size: Vector2, safe_area: Rect2) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	var normalized_safe_area: Rect2 = safe_area.intersection(viewport_rect)
	if not normalized_safe_area.has_area():
		normalized_safe_area = viewport_rect
	_active_safe_area = normalized_safe_area
	_compact_layout = normalized_safe_area.size.y <= COMPACT_LAYOUT_MAX_HEIGHT
	var compact: bool = _compact_layout
	var landscape: bool = normalized_safe_area.size.x >= 620.0
	var inset: float = 20.0 if compact else 44.0
	var available: Rect2 = normalized_safe_area.grow(-inset)
	var card_width: float = clampf(available.size.x * 0.42, 284.0, 360.0)
	var hero_rect := Rect2(available.position, Vector2(available.size.x - card_width - 26.0, available.size.y))
	var card_rect := Rect2(Vector2(available.end.x - card_width, normalized_safe_area.position.y), Vector2(card_width, normalized_safe_area.size.y))
	if not landscape:
		card_width = minf(360.0, available.size.x)
		var hero_height: float = minf(250.0, available.size.y * 0.36)
		hero_rect = Rect2(available.position, Vector2(available.size.x, hero_height))
		card_rect = Rect2(Vector2(available.position.x, available.position.y + hero_height + 12.0), Vector2(available.size.x, available.size.y - hero_height - 12.0))
	_layout_center_in_safe_area(content_center, card_rect)
	_layout_center_in_safe_area(settings_center, normalized_safe_area)
	_hero.position = hero_rect.position
	_hero.size = hero_rect.size
	_hero_labels.position = Vector2(6.0, 8.0 if compact else 20.0)
	_hero_labels.size = Vector2(hero_rect.size.x - 12.0, 0.0)
	title_label.text = "Pocket Kingdoms"
	title_label.add_theme_font_size_override("font_size", 30 if compact else 44)
	subtitle_label.add_theme_font_size_override("font_size", 11 if compact else 13)
	promise_label.add_theme_font_size_override("font_size", 14 if compact else 17)
	var art_top: float = 124.0
	if not compact:
		art_top += 30.0
	if not landscape:
		promise_label.visible = false
		art_top = 74.0
	else:
		promise_label.visible = true
	_hero_art.position = Vector2(0.0, art_top)
	_hero_art.size = Vector2(hero_rect.size.x, maxf(70.0, hero_rect.size.y - art_top - 22.0))
	_hero_caption.position = Vector2(0.0, hero_rect.size.y - 20.0)
	_hero_caption.size = Vector2(hero_rect.size.x, 20.0)
	content_vbox.custom_minimum_size.x = card_width
	content_vbox.add_theme_constant_override("separation", 8)
	map_heading.visible = not compact
	map_heading.add_theme_font_size_override("font_size", 12)
	difficulty_label.add_theme_font_size_override("font_size", 17)
	difficulty_description.visible = true
	difficulty_description.add_theme_font_size_override("font_size", 13)
	difficulty_description.custom_minimum_size.y = 34.0
	setup_margin.add_theme_constant_override("margin_left", 12 if compact else 20)
	setup_margin.add_theme_constant_override("margin_right", 12 if compact else 20)
	setup_margin.add_theme_constant_override("margin_top", 6 if compact else 18)
	setup_margin.add_theme_constant_override("margin_bottom", 4 if compact else 16)
	setup_vbox.add_theme_constant_override("separation", 6)
	guided_opening_toggle.custom_minimum_size = Vector2(0, 48)
	guided_opening_toggle.add_theme_font_size_override("font_size", 14)
	actions_row.add_theme_constant_override("separation", 6)
	start_button.custom_minimum_size = Vector2(card_width, 56)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.add_theme_font_size_override("font_size", 20)
	settings_button.custom_minimum_size = Vector2(card_width, 48)
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_button.add_theme_font_size_override("font_size", 14)
	settings_panel.custom_minimum_size.x = minf(normalized_safe_area.size.x - 24.0, 600.0)
	settings_margin.add_theme_constant_override("margin_left", 14 if compact else 22)
	settings_margin.add_theme_constant_override("margin_right", 14 if compact else 22)
	settings_margin.add_theme_constant_override("margin_top", 2 if compact else 18)
	settings_margin.add_theme_constant_override("margin_bottom", 2 if compact else 18)
	settings_vbox.add_theme_constant_override("separation", 6)
	settings_title.add_theme_font_size_override("font_size", 20 if compact else 24)
	settings_controls.add_theme_font_size_override("font_size", 12 if compact else 14)
	settings_controls.text = "Tap to select & order.\nDrag to pan. + / − zooms."
	camera_speed_label.add_theme_font_size_override("font_size", 13)
	ui_scale_label.add_theme_font_size_override("font_size", 13)
	seed_label.add_theme_font_size_override("font_size", 13)
	audio_toggle.add_theme_font_size_override("font_size", 14)
	seed_input.custom_minimum_size = Vector2(0, 48)
	random_seed_button.custom_minimum_size = Vector2(0, 48)
	random_seed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random_seed_button.add_theme_font_size_override("font_size", 14)
	settings_close_button.custom_minimum_size = Vector2(180, 48)
	settings_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _layout_center_in_safe_area(center: CenterContainer, safe_area: Rect2) -> void:
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 0.0
	center.anchor_bottom = 0.0
	center.position = safe_area.position
	center.size = safe_area.size


func _get_safe_area_rect(viewport_size: Vector2) -> Rect2:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return viewport_rect
	# Web's safe-area fallback is the canvas, while screen_get_size() is the
	# entire monitor. Mapping one through the other shrinks a phone preview to
	# a fraction of its real canvas. The browser already supplies the usable
	# content viewport (our export does not opt into viewport-fit=cover).
	if OS.has_feature("web"):
		return viewport_rect
	if not OS.has_feature("mobile"):
		return viewport_rect
	var safe_rect_i: Rect2i = DisplayServer.get_display_safe_area()
	if safe_rect_i.size.x <= 0 or safe_rect_i.size.y <= 0:
		return viewport_rect
	var screen_id: int = DisplayServer.SCREEN_OF_MAIN_WINDOW
	var display_rect := Rect2(
		Vector2(DisplayServer.screen_get_position(screen_id)),
		Vector2(DisplayServer.screen_get_size(screen_id))
	)
	return map_display_safe_area_to_viewport(
		Rect2(Vector2(safe_rect_i.position), Vector2(safe_rect_i.size)),
		display_rect,
		viewport_size
	)


static func map_display_safe_area_to_viewport(
	raw_safe_area: Rect2,
	display_rect: Rect2,
	viewport_size: Vector2
) -> Rect2:
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
	return mapped if mapped.has_area() else viewport_rect


func _on_difficulty_changed(index: int) -> void:
	_selected_difficulty = index
	difficulty_option.selected = index
	GameManager.selected_difficulty = _selected_difficulty
	GameManager.selected_population_limit = _selected_population_limit
	GameManager.save_preferences()
	_apply_difficulty_description()
	_refresh_main_menu_diagnostics()


func _apply_difficulty_description() -> void:
	difficulty_description.text = DIFFICULTY_DESCRIPTIONS[_selected_difficulty]
	for index: int in _difficulty_buttons.size():
		_difficulty_buttons[index].set_pressed_no_signal(index == _selected_difficulty)
	_refresh_main_menu_diagnostics()


func _on_random_seed_pressed() -> void:
	seed_input.text = ""
	GameManager.selected_map_seed = -1
	seed_input.release_focus()
	_refresh_main_menu_diagnostics()


func _on_guided_opening_toggled(pressed: bool) -> void:
	GameManager.guided_opening_enabled = pressed
	GameManager.save_preferences()
	_refresh_main_menu_diagnostics()


func _on_settings_pressed() -> void:
	settings_overlay.visible = true
	# The formerly hidden overlay needs one layout frame before its child bounds
	# are meaningful to touch automation and accessibility diagnostics.
	call_deferred("_refresh_responsive_layout")


func _on_settings_close_pressed() -> void:
	settings_overlay.visible = false
	call_deferred("_refresh_responsive_layout")


func _on_audio_toggled(pressed: bool) -> void:
	GameManager.audio_enabled = pressed
	GameManager.apply_preferences()
	GameManager.save_preferences()


func _on_camera_speed_selected(index: int) -> void:
	GameManager.camera_speed_scale = CAMERA_SPEED_VALUES[clampi(index, 0, CAMERA_SPEED_VALUES.size() - 1)]
	GameManager.save_preferences()


func _on_ui_scale_selected(index: int) -> void:
	GameManager.ui_scale = UI_SCALE_VALUES[clampi(index, 0, UI_SCALE_VALUES.size() - 1)]
	GameManager.apply_preferences()
	GameManager.save_preferences()


func _on_seed_text_changed(_new_text: String) -> void:
	_refresh_main_menu_diagnostics()


func _on_start_pressed() -> void:
	GameManager.selected_difficulty = _selected_difficulty
	GameManager.guided_opening_enabled = guided_opening_toggle.button_pressed
	GameManager.save_preferences()
	var seed_text: String = seed_input.text.strip_edges()
	GameManager.selected_map_seed = int(seed_text) if seed_text != "" and seed_text.is_valid_int() else -1
	# A touch-generated Button press is still being dispatched by Viewport while
	# this callback runs. Removing the focused menu immediately leaves Web's
	# emulated mouse/touch focus pointing at a detached Control for the remainder
	# of that dispatch, which makes the engine call Node.can_process() outside the
	# tree. Defer the swap until the input event is fully unwound.
	start_button.disabled = true
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main/main.tscn")


func _refresh_main_menu_diagnostics() -> void:
	if OS.has_feature("production"):
		return
	main_menu_diagnostics = {
		"ready": is_node_ready(),
		"title": title_label.text,
		"promise": promise_label.text,
		"map_summary": map_summary_label.text,
		"selected_difficulty": _selected_difficulty,
		"selected_population_limit": _selected_population_limit,
		"population_choices": _population_choice_diagnostics(),
		"difficulty_name": DIFFICULTY_NAMES[_selected_difficulty],
		"difficulty_description": difficulty_description.text,
		"compact_layout": _compact_layout,
		"viewport_width": get_viewport().get_visible_rect().size.x,
		"viewport_height": get_viewport().get_visible_rect().size.y,
		"safe_area": {
			"x": _active_safe_area.position.x,
			"y": _active_safe_area.position.y,
			"width": _active_safe_area.size.x,
			"height": _active_safe_area.size.y,
		},
		"guided_opening_enabled": guided_opening_toggle.button_pressed,
		"seed_text": seed_input.text,
		"main_menu_bounds": _control_diag(content_vbox, "main_menu_bounds"),
		"start_button": _control_diag(start_button, "main_menu_start"),
		"difficulty_option": _control_diag(difficulty_option, "main_menu_difficulty"),
		"difficulty_choices": _difficulty_button_diagnostics(),
		"kingdom_preview": _control_diag(_hero, "main_menu_kingdom_preview"),
		"random_seed_button": _control_diag(random_seed_button, "main_menu_random_seed"),
		"guided_opening_toggle": _control_diag(guided_opening_toggle, "main_menu_guided_opening"),
		"seed_input": _control_diag(seed_input, "main_menu_seed_input"),
		"settings_open": settings_overlay.visible,
		"settings_button": _control_diag(settings_button, "main_menu_settings"),
		"settings_bounds": _control_diag(settings_panel, "main_menu_settings_bounds"),
		"settings_title": _control_diag(settings_title, "main_menu_settings_title"),
		"settings_controls": _control_diag(settings_controls, "main_menu_settings_controls"),
		"settings_close_button": _control_diag(settings_close_button, "main_menu_settings_close"),
		"audio_toggle": _control_diag(audio_toggle, "main_menu_audio_toggle"),
		"camera_speed_label": _control_diag(camera_speed_label, "main_menu_camera_speed_label"),
		"camera_speed_option": _control_diag(camera_speed_option, "main_menu_camera_speed"),
		"ui_scale_label": _control_diag(ui_scale_label, "main_menu_ui_scale_label"),
		"ui_scale_option": _control_diag(ui_scale_option, "main_menu_ui_scale"),
		"audio_enabled": audio_toggle.button_pressed,
		"camera_speed_scale": GameManager.camera_speed_scale,
		"ui_scale": GameManager.ui_scale,
	}


func _population_choice_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for button: Button in _population_buttons:
		result.append(_control_diag(button, "main_menu_population_choice"))
	return result


func _difficulty_button_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for button: Button in _difficulty_buttons:
		result.append(_control_diag(button, "main_menu_difficulty_choice"))
	return result


func _control_diag(control: Control, role: String) -> Dictionary:
	# Diagnostics and injected input use root-viewport logical coordinates. Using
	# get_screen_position() mixes in stretch/HiDPI transforms on real phones.
	var screen_pos: Vector2 = control.get_global_rect().position
	var size: Vector2 = control.size
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var within_viewport: bool = (
		screen_pos.x >= -0.5
		and screen_pos.y >= -0.5
		and screen_pos.x + size.x <= viewport_size.x + 0.5
		and screen_pos.y + size.y <= viewport_size.y + 0.5
	)
	var width: float = size.x
	var height: float = size.y
	var within_safe_area: bool = (
		screen_pos.x >= _active_safe_area.position.x - 0.5
		and screen_pos.y >= _active_safe_area.position.y - 0.5
		and screen_pos.x + size.x <= _active_safe_area.end.x + 0.5
		and screen_pos.y + size.y <= _active_safe_area.end.y + 0.5
	)
	var disabled: bool = false
	if control is BaseButton:
		disabled = (control as BaseButton).disabled
	return {
		"role": role,
		"name": control.name,
		"path": str(control.get_path()),
		"visible": control.is_visible_in_tree(),
		"disabled": disabled,
		"width": width,
		"height": height,
		"aspect_ratio": width / height if height > 0.0 else 0.0,
		# Checkboxes, text fields, and dropdowns are intentionally row-shaped.
		# Their height is the touch-target constraint; the generic sliver rule is
		# only useful for ordinary action buttons.
		"allows_wide_touch_target": control is CheckButton or control is LineEdit or control is OptionButton,
		"within_viewport": within_viewport,
		"within_safe_area": within_safe_area,
		"x": screen_pos.x,
		"y": screen_pos.y,
		"min_width": control.custom_minimum_size.x,
		"min_height": control.custom_minimum_size.y,
	}
