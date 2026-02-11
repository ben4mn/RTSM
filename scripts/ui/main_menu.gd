extends Control
## Main menu screen. Title, start button, difficulty picker.

signal start_game(difficulty: int)

enum Difficulty {
	EASY,
	MEDIUM,
	HARD,
}

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Medium", "Hard"]

@onready var title_label: Label = %TitleLabel
@onready var start_button: Button = %StartButton
@onready var difficulty_option: OptionButton = %DifficultyOption

var _selected_difficulty: int = Difficulty.MEDIUM


func _ready() -> void:
	title_label.text = "Age of Empires Mobile"
	start_button.pressed.connect(_on_start_pressed)

	# Populate difficulty dropdown
	difficulty_option.clear()
	for i in range(DIFFICULTY_NAMES.size()):
		difficulty_option.add_item(DIFFICULTY_NAMES[i], i)
	difficulty_option.selected = _selected_difficulty
	difficulty_option.item_selected.connect(_on_difficulty_changed)


func _on_difficulty_changed(index: int) -> void:
	_selected_difficulty = index


func _on_start_pressed() -> void:
	start_game.emit(_selected_difficulty)
