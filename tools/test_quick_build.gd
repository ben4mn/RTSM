extends Node
## Hold Build, slide to a building, release: placement starts without the menu.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	var hud: Node = main.get("hud")
	var choices: Array = hud.call("_quick_build_choices")
	_expect(choices.size() == 4, "four quick choices, got %d" % choices.size())
	_expect(str(choices[0].get("id")) == "build:%d" % BuildingData.BuildingType.HOUSE, "House leads before anything is built")
	_expect(bool(choices[0].get("enabled")), "an affordable House is enabled")
	hud.call("_on_hold_choice_selected", "build:%d" % BuildingData.BuildingType.FARM)
	await get_tree().process_frame
	var placement: Node = main.get("_building_placement")
	_expect(bool(placement.get("active")) and int(placement.get("current_building_type")) == BuildingData.BuildingType.FARM, "choosing Farm starts Farm placement")
	main.call("_cancel_placement")
	hud.call("set_last_built_type", BuildingData.BuildingType.BARRACKS)
	choices = hud.call("_quick_build_choices")
	_expect(str(choices[0].get("id")) == "build:%d" % BuildingData.BuildingType.BARRACKS, "the last building placed leads the choices")
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	choices = hud.call("_quick_build_choices")
	_expect(not bool(choices[0].get("enabled")), "an unaffordable choice is disabled")
	hud.call("_on_hold_choice_selected", "build:%d" % BuildingData.BuildingType.HOUSE)
	await get_tree().process_frame
	_expect(not bool(placement.get("active")), "an unaffordable quick choice does not start placement")
	main.free()
	if _failures.is_empty():
		print("[PASS] quick_build: four choices, last built first, choice starts placement, unaffordable refused")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] quick_build: %s" % failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
