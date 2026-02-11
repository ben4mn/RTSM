extends PanelContainer
## Age-up dialog. Shows costs, landmark choice for Age 3, and confirm/cancel.

signal age_up_confirmed(age: int, landmark_choice: int)
signal age_up_cancelled()

const AGE_UP_COSTS: Dictionary = {
	2: {"food": 400, "gold": 200},
	3: {"food": 1200, "gold": 600},
}

const LANDMARK_CHOICES: Array = [
	{"name": "Fortress of the Kings", "description": "Defensive landmark. Attacks nearby enemies."},
	{"name": "Grand Market", "description": "Economic landmark. Boosts gold income."},
]

@onready var title_label: Label = %AgeUpTitle
@onready var cost_label: Label = %CostLabel
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton
@onready var progress_bar: ProgressBar = %AgeUpProgress
@onready var landmark_container: VBoxContainer = %LandmarkContainer
@onready var landmark_option_a: Button = %LandmarkOptionA
@onready var landmark_option_b: Button = %LandmarkOptionB

var _target_age: int = 2
var _selected_landmark: int = -1
var _is_researching: bool = false
var _research_progress: float = 0.0
var _research_duration: float = 30.0  # seconds


func _ready() -> void:
	visible = false
	confirm_button.pressed.connect(_on_confirm)
	cancel_button.pressed.connect(_on_cancel)
	landmark_option_a.pressed.connect(_on_landmark_selected.bind(0))
	landmark_option_b.pressed.connect(_on_landmark_selected.bind(1))
	progress_bar.visible = false


func _process(delta: float) -> void:
	if _is_researching:
		_research_progress += delta
		progress_bar.value = (_research_progress / _research_duration) * 100.0
		if _research_progress >= _research_duration:
			_complete_research()


func show_dialog(current_age: int) -> void:
	_target_age = current_age + 1
	_selected_landmark = -1
	_is_researching = false
	_research_progress = 0.0
	progress_bar.visible = false
	progress_bar.value = 0

	if _target_age > 3:
		return  # Max age reached

	var gm := get_node_or_null("/root/GameManager")
	var age_name: String = "Age %d" % _target_age
	if gm:
		age_name = gm.get_age_name(_target_age)

	title_label.text = "Advance to %s" % age_name

	var cost: Dictionary = AGE_UP_COSTS.get(_target_age, {})
	cost_label.text = "Cost: %d Food, %d Gold" % [cost.get("food", 0), cost.get("gold", 0)]

	# Show landmark choices only for Age 3
	var show_landmarks: bool = _target_age == 3
	landmark_container.visible = show_landmarks
	if show_landmarks:
		landmark_option_a.text = "%s\n%s" % [LANDMARK_CHOICES[0]["name"], LANDMARK_CHOICES[0]["description"]]
		landmark_option_b.text = "%s\n%s" % [LANDMARK_CHOICES[1]["name"], LANDMARK_CHOICES[1]["description"]]
		landmark_option_a.button_pressed = false
		landmark_option_b.button_pressed = false
		confirm_button.disabled = true  # Must pick a landmark first
	else:
		confirm_button.disabled = false

	confirm_button.text = "Confirm"
	cancel_button.disabled = false
	visible = true


func _on_landmark_selected(index: int) -> void:
	_selected_landmark = index
	landmark_option_a.button_pressed = (index == 0)
	landmark_option_b.button_pressed = (index == 1)
	# Highlight selected
	landmark_option_a.modulate = Color.WHITE if index == 0 else Color(0.6, 0.6, 0.6)
	landmark_option_b.modulate = Color.WHITE if index == 1 else Color(0.6, 0.6, 0.6)
	confirm_button.disabled = false


func _on_confirm() -> void:
	if _target_age == 3 and _selected_landmark < 0:
		return  # Must pick a landmark

	# Start research progress
	_is_researching = true
	_research_progress = 0.0
	progress_bar.visible = true
	confirm_button.disabled = true
	cancel_button.text = "Cancel Research"


func _on_cancel() -> void:
	if _is_researching:
		_is_researching = false
		progress_bar.visible = false
		_research_progress = 0.0
		confirm_button.disabled = false
		cancel_button.text = "Cancel"
		return

	visible = false
	age_up_cancelled.emit()


func _complete_research() -> void:
	_is_researching = false
	progress_bar.visible = false
	visible = false
	age_up_confirmed.emit(_target_age, _selected_landmark)


func get_age_up_cost(target_age: int) -> Dictionary:
	return AGE_UP_COSTS.get(target_age, {}).duplicate()
