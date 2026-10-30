extends Node
## Beta 30: with housing full and a House still being built, the training
## warning says the House is going up instead of asking for another House.

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
	(main.get("ai_controller") as Node).set_process(false)
	for resource: String in ["food", "wood", "gold"]:
		ResourceManager.add_resource(0, resource, 2000)
	GameManager.players[0]["population_cap"] = GameManager.get_committed_population(0)
	var tc: BuildingBase = main.get("_player_town_center")
	main.call("_on_train_unit_requested", tc, UnitData.UnitType.VILLAGER)
	_expect(str(main.get("_last_train_feedback")).contains("Build a House"), "full housing with no House going up asks for a House: %s" % main.get("_last_train_feedback"))
	var house: BuildingBase = main.call("_spawn_building", BuildingData.BuildingType.HOUSE, 0, Vector2i(12, 12))
	_expect(house != null, "fixture House spawns")
	if house != null:
		# A freshly placed House is a construction site until builders finish it.
		house.state = BuildingBase.State.CONSTRUCTING
	main.call("_on_train_unit_requested", tc, UnitData.UnitType.VILLAGER)
	_expect(str(main.get("_last_train_feedback")).contains("going up"), "full housing with a House going up says so: %s" % main.get("_last_train_feedback"))
	main.free()
	if _failures.is_empty():
		print("[PASS] house_going_up_feedback: housing warning knows about a House under construction")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] house_going_up_feedback: %s" % failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
