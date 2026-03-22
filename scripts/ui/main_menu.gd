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

@onready var title_label: Label = %TitleLabel
@onready var promise_label: Label = %PromiseLabel
@onready var map_summary_label: Label = %MapSummaryLabel
@onready var start_button: Button = %StartButton
@onready var difficulty_option: OptionButton = %DifficultyOption
@onready var difficulty_description: Label = %DifficultyDescription
@onready var seed_input: LineEdit = %SeedInput
@onready var random_seed_button: Button = %RandomSeedButton
@onready var guided_opening_toggle: CheckButton = %GuidedOpeningToggle

@export var main_menu_diagnostics: Dictionary = {}

var _selected_difficulty: int = Difficulty.MEDIUM


func _ready() -> void:
	title_label.text = "Age of Empires Mobile"
	promise_label.text = "Fast 1v1 skirmish. You begin with a Town Center, four villagers, and a guided opener."
	map_summary_label.text = "Pocket Duel (40x40)\nGuaranteed nearby food, wood, and gold with a central sacred-site fight."
	start_button.pressed.connect(_on_start_pressed)
	random_seed_button.pressed.connect(_on_random_seed_pressed)
	guided_opening_toggle.toggled.connect(_on_guided_opening_toggled)
	seed_input.text_changed.connect(_on_seed_text_changed)

	# Populate difficulty dropdown
	difficulty_option.clear()
	for i in range(DIFFICULTY_NAMES.size()):
		difficulty_option.add_item(DIFFICULTY_NAMES[i], i)
	difficulty_option.selected = _selected_difficulty
	difficulty_option.item_selected.connect(_on_difficulty_changed)
	_apply_difficulty_description()

	if GameManager.selected_map_seed >= 0:
		seed_input.text = str(GameManager.selected_map_seed)
	else:
		seed_input.placeholder_text = "Random each match"
	guided_opening_toggle.button_pressed = bool(GameManager.guided_opening_enabled)
	_refresh_main_menu_diagnostics()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_refresh_main_menu_diagnostics()


func _on_difficulty_changed(index: int) -> void:
	_selected_difficulty = index
	_apply_difficulty_description()
	_refresh_main_menu_diagnostics()


func _apply_difficulty_description() -> void:
	difficulty_description.text = DIFFICULTY_DESCRIPTIONS[_selected_difficulty]
	_refresh_main_menu_diagnostics()


func _on_random_seed_pressed() -> void:
	seed_input.text = ""
	seed_input.grab_focus()
	_refresh_main_menu_diagnostics()


func _on_guided_opening_toggled(_pressed: bool) -> void:
	_refresh_main_menu_diagnostics()


func _on_seed_text_changed(_new_text: String) -> void:
	_refresh_main_menu_diagnostics()


func _on_start_pressed() -> void:
	GameManager.selected_difficulty = _selected_difficulty
	GameManager.guided_opening_enabled = guided_opening_toggle.button_pressed
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
