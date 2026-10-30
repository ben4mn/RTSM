extends Node
## Two flank shrines stand equally far from both starts, pay gold while held,
## never run a victory clock, stay out of building/objective groups, and give
## the AI a target.

var _failures: Array[String] = []
@onready var root: Window = get_tree().root


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	for map_seed: int in [101, 424242]:
		GameManager.selected_map_seed = map_seed
		GameManager.set_state(GameManager.GameState.MENU)
		var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
		for frame: int in range(900):
			if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
				break
			await get_tree().process_frame
		await _check(main, map_seed)
		main.free()
		GameManager.set_state(GameManager.GameState.MENU)
		await get_tree().process_frame
	if _failures.is_empty():
		print("[PASS] flank_shrines: two fair shrines per map, gold without a clock, outside building groups, AI target")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] flank_shrines: %s" % failure)
		get_tree().quit(1)


func _check(main: Node, map_seed: int) -> void:
	var map: Node2D = main.get("game_map") as Node2D
	var shrines: Array = map.get("shrines")
	_expect(shrines.size() == 2, "seed %d should have two shrines, got %d" % [map_seed, shrines.size()])
	if shrines.size() != 2:
		return
	var town_centers: Array[Vector2] = []
	for player: int in [0, 1]:
		for building: Node in main.get("_player_buildings")[player]:
			if building is BuildingBase and (building as BuildingBase).building_type == BuildingData.BuildingType.TOWN_CENTER:
				town_centers.append((building as Node2D).global_position)
	(main.get("ai_controller") as Node).set_process(false)
	for shrine: Node2D in shrines:
		_expect(shrine.is_in_group("shrines") and not shrine.is_in_group("buildings") and not shrine.is_in_group("sacred_sites"), "seed %d shrine groups" % map_seed)
		if town_centers.size() == 2:
			var gap: float = absf(shrine.global_position.distance_to(town_centers[0]) - shrine.global_position.distance_to(town_centers[1]))
			_expect(gap <= float(MapData.TILE_WIDTH) * 2.0, "seed %d shrine is %.0f px closer to one start" % [map_seed, gap])
	var shrine: Node2D = shrines[0]
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	shrine.set_process(false)
	shrine.set("state", 2)
	shrine.set("owning_player", 0)
	shrine.set("capture_progress", 1.0)
	GameManager.game_time = 900.0
	for step: int in 10:
		shrine.call("_handle_captured", 1, 0, 1.0, 1)
	_expect(ResourceManager.get_resource(0, "gold") >= 9, "seed %d held shrine pays gold" % map_seed)
	_expect(is_zero_approx(float(shrine.get("victory_timer"))), "seed %d shrine never runs a victory clock" % map_seed)
	var ai: Node = main.get("ai_controller") as Node
	var target: Node2D = ai.call("_pick_shrine_target") as Node2D
	_expect(target == shrine, "seed %d AI should go for the shrine the player holds" % map_seed)
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
