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
	for frame: int in 10:
		await get_tree().process_frame
	# Real touch: hold Build with nothing selected, slide to House, release.
	var build_button: Button = hud.get("build_menu_button")
	var hold: Node = build_button.get_meta("hud_hold_control")
	var press := InputEventScreenTouch.new()
	press.index = 4
	press.position = get_viewport().get_final_transform() * build_button.get_global_rect().get_center()
	press.pressed = true
	Input.parse_input_event(press)
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 700:
		await get_tree().process_frame
	_expect(bool(hud.get("_hold_chooser_active")), "holding Build with nothing selected opens the building chooser")
	var house_rect: Rect2 = Rect2()
	for choice: Dictionary in hold.call("get_choice_rects"):
		if str(choice.get("id")) == "build:%d" % BuildingData.BuildingType.HOUSE:
			house_rect = choice.get("rect")
	_expect(house_rect.has_area(), "the chooser offers House")
	if house_rect.has_area():
		var slide := InputEventScreenDrag.new()
		slide.index = 4
		slide.position = get_viewport().get_final_transform() * house_rect.get_center()
		Input.parse_input_event(slide)
		for frame: int in 3:
			await get_tree().process_frame
		var release := InputEventScreenTouch.new()
		release.index = 4
		release.position = slide.position
		release.pressed = false
		Input.parse_input_event(release)
		for frame: int in 3:
			await get_tree().process_frame
		var held_placement: Node = main.get("_building_placement")
		_expect(bool(held_placement.get("active")) and int(held_placement.get("current_building_type")) == BuildingData.BuildingType.HOUSE, "sliding to House and releasing starts House placement")
		main.call("_cancel_placement")
		await get_tree().process_frame
	var choices: Array = hud.call("_quick_build_choices")
	_expect(choices.size() == 4, "four quick choices, got %d" % choices.size())
	_expect(str(choices[0].get("id")) == "build:%d" % BuildingData.BuildingType.HOUSE, "House leads before anything is built")
	_expect(bool(choices[0].get("enabled")), "an affordable House is enabled")
	hud.call("_on_hold_choice_selected", "build:%d" % BuildingData.BuildingType.FARM)
	await get_tree().process_frame
	var placement: Node = main.get("_building_placement")
	_expect(bool(placement.get("active")) and int(placement.get("current_building_type")) == BuildingData.BuildingType.FARM, "choosing Farm starts Farm placement")
	main.call("_cancel_placement")
	# Beta 30: the order is fixed so a practised slide always lands on the same
	# building. Placing a Farm must not move it in front of House; another
	# building placed takes the fourth slot.
	hud.call("set_last_built_type", BuildingData.BuildingType.FARM)
	choices = hud.call("_quick_build_choices")
	_expect(str(choices[0].get("id")) == "build:%d" % BuildingData.BuildingType.HOUSE and str(choices[1].get("id")) == "build:%d" % BuildingData.BuildingType.FARM, "House and Farm keep their places after a Farm")
	hud.call("set_last_built_type", BuildingData.BuildingType.BLACKSMITH)
	choices = hud.call("_quick_build_choices")
	_expect(str(choices[0].get("id")) == "build:%d" % BuildingData.BuildingType.HOUSE and str(choices[3].get("id")) == "build:%d" % BuildingData.BuildingType.BLACKSMITH, "the last other building takes the fourth slot")
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	choices = hud.call("_quick_build_choices")
	_expect(not bool(choices[0].get("enabled")), "an unaffordable choice is disabled")
	hud.call("_on_hold_choice_selected", "build:%d" % BuildingData.BuildingType.HOUSE)
	await get_tree().process_frame
	_expect(not bool(placement.get("active")), "an unaffordable quick choice does not start placement")
	main.free()
	if _failures.is_empty():
		print("[PASS] quick_build: four choices in a fixed order, last other building fourth, choice starts placement, unaffordable refused")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] quick_build: %s" % failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
