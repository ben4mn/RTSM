extends SceneTree
## A duel needs open center approaches, reachable resources and an unobstructed
## ordinary-game view after optional opening help ends.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for seed_value: int in [101, 202, 303, 404, 505, 424242]:
		var generator := MapGenerator.new(seed_value)
		generator.generate()
		var navigation := Pathfinding.new(generator)
		var center := Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2)
		for y: int in range(center.y - 7, center.y + 8):
			for x: int in range(center.x - 7, center.x + 8):
				var tile: int = generator.grid[y][x]
				_check(MapData.is_grass(tile) or tile == MapData.TileType.SACRED_SITE, "seed%d: center blocked at%d,%d" % [seed_value, x, y])
		for spawn: Vector2i in generator.spawn_positions:
			_check(not navigation.get_tile_path(spawn, center).is_empty(), "seed%d: home cannot reach center" % seed_value)
			for resource_type: int in [MapData.TileType.BERRY_BUSH, MapData.TileType.GOLD_MINE, MapData.TileType.FOREST]:
				var reachable := false
				for y: int in range(maxi(0, spawn.y - 13), mini(MapData.MAP_HEIGHT, spawn.y + 14)):
					for x: int in range(maxi(0, spawn.x - 13), mini(MapData.MAP_WIDTH, spawn.x + 14)):
						if generator.grid[y][x] == resource_type and not navigation.get_tile_path(spawn, Vector2i(x, y)).is_empty():
							reachable = true
				_check(reachable, "seed%d: no reachable starting resource%d" % [seed_value, resource_type])
	var gm: Node = root.get_node("GameManager")
	root.get_node("AudioManager").set_all_enabled(false)
	gm.guided_opening_enabled = false
	gm.selected_map_seed = 303
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null:
			break
		await process_frame
	main.call("_update_progression_hint")
	var hud: Node = main.get("hud")
	_check(not (hud.get("_progression_hint_panel") as Control).visible, "ordinary match is covered by opening/age guidance")
	main.set("_guided_opening_active", true)
	main.set("_guided_stage", 4)
	main.call("_update_progression_hint")
	_check(not (hud.get("_progression_hint_panel") as Control).visible, "completed opening keeps covering battlefield")
	main.free()
	if failures.is_empty():
		print("[PASS] battlefield_room: six seeds, both bases/resources reachable, open center, optional guidance ends")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
