extends RefCounted
## Licensed, edited Kenney recordings. Original files and CC0 licenses are retained.
## No synthesis and no gameplay RNG. The manager owns gain, priorities and caps.

const BANK: Dictionary = {
	"button_click": [preload("res://assets/audio/kenney/cues/button_click_01.wav"), preload("res://assets/audio/kenney/cues/button_click_02.wav"), preload("res://assets/audio/kenney/cues/button_click_03.wav")],
	"select_unit": [preload("res://assets/audio/kenney/cues/select_unit_01.wav"), preload("res://assets/audio/kenney/cues/select_unit_02.wav")],
	"command_move": [preload("res://assets/audio/kenney/cues/command_move_01.wav"), preload("res://assets/audio/kenney/cues/command_move_02.wav"), preload("res://assets/audio/kenney/cues/command_move_03.wav")],
	"command_attack": [preload("res://assets/audio/kenney/cues/command_attack_01.wav"), preload("res://assets/audio/kenney/cues/command_attack_02.wav"), preload("res://assets/audio/kenney/cues/command_attack_03.wav")],
	"attack_hit": [preload("res://assets/audio/kenney/cues/attack_hit_01.wav"), preload("res://assets/audio/kenney/cues/attack_hit_02.wav"), preload("res://assets/audio/kenney/cues/attack_hit_03.wav")],
	"unit_death": [preload("res://assets/audio/kenney/cues/unit_death_01.wav"), preload("res://assets/audio/kenney/cues/unit_death_02.wav"), preload("res://assets/audio/kenney/cues/unit_death_03.wav")],
	"gather_food": [preload("res://assets/audio/kenney/cues/gather_food_01.wav"), preload("res://assets/audio/kenney/cues/gather_food_02.wav"), preload("res://assets/audio/kenney/cues/gather_food_03.wav")],
	"gather_wood": [preload("res://assets/audio/kenney/cues/gather_wood_01.wav"), preload("res://assets/audio/kenney/cues/gather_wood_02.wav"), preload("res://assets/audio/kenney/cues/gather_wood_03.wav")],
	"gather_gold": [preload("res://assets/audio/kenney/cues/gather_gold_01.wav"), preload("res://assets/audio/kenney/cues/gather_gold_02.wav"), preload("res://assets/audio/kenney/cues/gather_gold_03.wav")],
	"construction_work": [preload("res://assets/audio/kenney/cues/construction_work_01.wav"), preload("res://assets/audio/kenney/cues/construction_work_02.wav"), preload("res://assets/audio/kenney/cues/construction_work_03.wav")],
	"building_place": [preload("res://assets/audio/kenney/cues/building_place_01.wav"), preload("res://assets/audio/kenney/cues/building_place_02.wav"), preload("res://assets/audio/kenney/cues/building_place_03.wav")],
	"building_invalid": [preload("res://assets/audio/kenney/cues/building_invalid_01.wav"), preload("res://assets/audio/kenney/cues/building_invalid_02.wav")],
	"unit_trained": [preload("res://assets/audio/kenney/cues/unit_trained_01.wav"), preload("res://assets/audio/kenney/cues/unit_trained_02.wav")],
	"building_complete": [preload("res://assets/audio/kenney/cues/building_complete_01.wav"), preload("res://assets/audio/kenney/cues/building_complete_02.wav")],
	"under_attack": [preload("res://assets/audio/kenney/cues/under_attack_01.wav"), preload("res://assets/audio/kenney/cues/under_attack_02.wav")],
	"age_up": [preload("res://assets/audio/kenney/cues/age_up_01.wav"), preload("res://assets/audio/kenney/cues/age_up_02.wav")],
	"victory": [preload("res://assets/audio/kenney/cues/victory_01.wav"), preload("res://assets/audio/kenney/cues/victory_02.wav")],
	"defeat": [preload("res://assets/audio/kenney/cues/defeat_01.wav"), preload("res://assets/audio/kenney/cues/defeat_02.wav")],
}


static func build() -> Dictionary:
	return BANK.duplicate(true)
