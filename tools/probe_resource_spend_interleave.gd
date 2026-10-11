extends Node
## Synthetic synchronous-notification reproduction, not an ordinary match.
## A research-sized purchase and another legal resource purchase interleave.

var _nested_accepted: bool = false
var _nested_attempted: bool = false
var _output: String = "res://output/evolution/rules-independent-resource-interleave-before.json"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	var report: Dictionary = {"evidence_kind": "synthetic synchronous resources_changed callback; no actual AI or human input", "resource_manager_loaded_sha256": (load("res://scripts/managers/resource_manager.gd") as Script).source_code.sha256_text()}
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 100, "wood": 0, "gold": 50})
	report["before"] = ResourceManager.get_all_resources(0)
	ResourceManager.resources_changed.connect(_during_spend)
	report["outer_accepted"] = ResourceManager.try_spend(0, {"food": 100, "gold": 50})
	ResourceManager.resources_changed.disconnect(_during_spend)
	report["nested_attempted"] = _nested_attempted
	report["nested_accepted"] = _nested_accepted
	report["after"] = ResourceManager.get_all_resources(0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output).get_base_dir())
	FileAccess.open(_output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	get_tree().quit(0)


func _during_spend(player_id: int, resource_type: String, _amount: int) -> void:
	if player_id != 0 or resource_type != "food" or _nested_attempted:
		return
	_nested_attempted = true
	_nested_accepted = ResourceManager.try_spend(0, {"gold": 50})
