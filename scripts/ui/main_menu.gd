extends Control
## Main menu screen. Title, skirmish setup, and start button.

enum Difficulty {
	EASY,
	MEDIUM,
	HARD,
}

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Medium", "Hard"]
const DIFFICULTY_DESCRIPTIONS: Array[String] = [
	"Easy: slower attacks and lighter pressure while you learn the loop.",
	"Medium: the intended first skirmish pace with steady raiding pressure.",
	"Hard: faster macro, earlier attacks, and little room for idle time.",
]
const CAMERA_SPEED_VALUES: Array[float] = [0.75, 1.0, 1.25]
const UI_SCALE_VALUES: Array[float] = [0.9, 1.0, 1.15]

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

@export var main_menu_diagnostics: Dictionary = {}

var _selected_difficulty: int = Difficulty.MEDIUM


func _ready() -> void:
	title_label.text = "Pocket Kingdoms"
	promise_label.text = "Fast 1v1 skirmish. You begin with a Town Center, four villagers, and a guided opener."
	map_summary_label.text = "Pocket Duel (40x40)\nGuaranteed nearby food, wood, and gold with a central sacred-site fight."
	start_button.pressed.connect(_on_start_pressed)
	random_seed_button.pressed.connect(_on_random_seed_pressed)
	guided_opening_toggle.toggled.connect(_on_guided_opening_toggled)
	settings_button.pressed.connect(_on_settings_pressed)
	settings_close_button.pressed.connect(_on_settings_close_pressed)
	audio_toggle.toggled.connect(_on_audio_toggled)
	camera_speed_option.item_selected.connect(_on_camera_speed_selected)
	ui_scale_option.item_selected.connect(_on_ui_scale_selected)
	seed_input.text_changed.connect(_on_seed_text_changed)

	# Populate difficulty dropdown
	difficulty_option.clear()
	for i in range(DIFFICULTY_NAMES.size()):
		difficulty_option.add_item(DIFFICULTY_NAMES[i], i)
	_selected_difficulty = clampi(GameManager.selected_difficulty, Difficulty.EASY, Difficulty.HARD)
	difficulty_option.selected = _selected_difficulty
	difficulty_option.item_selected.connect(_on_difficulty_changed)
	_apply_difficulty_description()

	if GameManager.selected_map_seed >= 0:
		seed_input.text = str(GameManager.selected_map_seed)
	else:
		seed_input.placeholder_text = "Random each match"
	guided_opening_toggle.button_pressed = bool(GameManager.guided_opening_enabled)
	_setup_settings_controls()
	_refresh_main_menu_diagnostics()


func _setup_settings_controls() -> void:
	audio_toggle.button_pressed = GameManager.audio_enabled
	camera_speed_option.clear()
	for label in ["Relaxed", "Standard", "Fast"]:
		camera_speed_option.add_item(label)
	camera_speed_option.selected = _nearest_value_index(CAMERA_SPEED_VALUES, GameManager.camera_speed_scale)
	ui_scale_option.clear()
	for label in ["Compact", "Standard", "Large"]:
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
		_refresh_main_menu_diagnostics()


func _on_difficulty_changed(index: int) -> void:
	_selected_difficulty = index
	GameManager.selected_difficulty = _selected_difficulty
	GameManager.save_preferences()
	_apply_difficulty_description()
	_refresh_main_menu_diagnostics()


func _apply_difficulty_description() -> void:
	difficulty_description.text = DIFFICULTY_DESCRIPTIONS[_selected_difficulty]
	_refresh_main_menu_diagnostics()


func _on_random_seed_pressed() -> void:
	seed_input.text = ""
	seed_input.grab_focus()
	_refresh_main_menu_diagnostics()


func _on_guided_opening_toggled(pressed: bool) -> void:
	GameManager.guided_opening_enabled = pressed
	GameManager.save_preferences()
	_refresh_main_menu_diagnostics()


func _on_settings_pressed() -> void:
	settings_overlay.visible = true
	_refresh_main_menu_diagnostics()


func _on_settings_close_pressed() -> void:
	settings_overlay.visible = false
	_refresh_main_menu_diagnostics()


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
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _refresh_main_menu_diagnostics() -> void:
	main_menu_diagnostics = {
		"ready": is_node_ready(),
		"title": title_label.text,
		"promise": promise_label.text,
		"map_summary": map_summary_label.text,
		"selected_difficulty": _selected_difficulty,
		"difficulty_name": DIFFICULTY_NAMES[_selected_difficulty],
		"difficulty_description": difficulty_description.text,
		"guided_opening_enabled": guided_opening_toggle.button_pressed,
		"seed_text": seed_input.text,
		"start_button": _control_diag(start_button, "main_menu_start"),
		"difficulty_option": _control_diag(difficulty_option, "main_menu_difficulty"),
		"random_seed_button": _control_diag(random_seed_button, "main_menu_random_seed"),
		"guided_opening_toggle": _control_diag(guided_opening_toggle, "main_menu_guided_opening"),
		"seed_input": _control_diag(seed_input, "main_menu_seed_input"),
		"settings_open": settings_overlay.visible,
		"settings_button": _control_diag(settings_button, "main_menu_settings"),
		"settings_close_button": _control_diag(settings_close_button, "main_menu_settings_close"),
		"audio_toggle": _control_diag(audio_toggle, "main_menu_audio_toggle"),
		"camera_speed_option": _control_diag(camera_speed_option, "main_menu_camera_speed"),
		"ui_scale_option": _control_diag(ui_scale_option, "main_menu_ui_scale"),
		"audio_enabled": audio_toggle.button_pressed,
		"camera_speed_scale": GameManager.camera_speed_scale,
		"ui_scale": GameManager.ui_scale,
	}


func _control_diag(control: Control, role: String) -> Dictionary:
	var screen_pos: Vector2 = control.get_screen_position()
	var size: Vector2 = control.size
	var width: float = size.x
	var height: float = size.y
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
		"x": screen_pos.x,
		"y": screen_pos.y,
		"min_width": control.custom_minimum_size.x,
		"min_height": control.custom_minimum_size.y,
	}
