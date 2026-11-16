extends Node
## Beta 30: in the workers panel, food + with no free food in sight starts Farm
## placement instead of a cut-off sentence; wood with nothing in sight explains
## itself in a few words.

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
	var map: Node = main.get("game_map")
	var controller: Node = main.get_node("StrategyController")
	# One idle worker; every food and wood node out of sight.
	var worker: Villager = null
	for unit: Variant in (main.get("_player_units") as Array)[0]:
		if is_instance_valid(unit) and unit is Villager:
			worker = unit as Villager
			break
	_expect(worker != null, "a starting villager exists")
	if worker != null:
		worker.command_stop()
		await get_tree().process_frame
	var fog: Node = map.get("fog_of_war")
	for tile: Vector2i in map.resource_nodes:
		var resource: Node = map.resource_nodes[tile]
		if str(resource.get("resource_type")) in ["food", "wood"]:
			fog.fog_grid[tile.y][tile.x] = MapData.FogState.EXPLORED
	var wood_result: Dictionary = controller.call("try_allocate_worker", 0, "idle", "wood")
	_expect(str(wood_result.get("error", "")) == "No wood in sight. Scout for more.", "wood with nothing in sight says so briefly: %s" % wood_result)
	ResourceManager.add_resource(0, "wood", 200)
	controller.call("_allocate_worker", "idle", "food")
	await get_tree().process_frame
	var placement: Node = main.get("_building_placement")
	_expect(bool(placement.get("active")) and int(placement.get("current_building_type")) == BuildingData.BuildingType.FARM, "food + with no free food starts Farm placement")
	main.free()
	if _failures.is_empty():
		print("[PASS] food_plus_starts_farm: food + opens Farm placement; short no-work copy")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] food_plus_starts_farm: %s" % failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
