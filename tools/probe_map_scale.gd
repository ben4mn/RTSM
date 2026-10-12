extends SceneTree
## Generated-world inventory and canonical route measurements. These are
## unopposed travel estimates, not live gathering or match-duration claims.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	var rows: Array[Dictionary] = []
	var failed_routes: Array[int] = []
	for seed_value: int in [424242, 202, 404]:
		var generator := MapGenerator.new(seed_value)
		generator.generate()
		var map := Node2D.new()
		map.set_script(load("res://scripts/map/game_map.gd"))
		map.set("map_generator", generator)
		map.set("pathfinding", Pathfinding.new(generator))
		var stocks: Dictionary = {"food": 0, "wood": 0, "gold": 0}
		var count: Dictionary = {"food": 0, "wood": 0, "gold": 0, "water": 0}
		for row: Array in generator.grid:
			for tile: int in row:
				match tile:
					MapData.TileType.BERRY_BUSH:
						count["food"] += 1
						stocks["food"] += 200
					MapData.TileType.FOREST:
						count["wood"] += 1
						stocks["wood"] += 250
					MapData.TileType.GOLD_MINE:
						count["gold"] += 1
						stocks["gold"] += 400
					MapData.TileType.WATER: count["water"] += 1
		var start: Vector2 = map.call("tile_to_world", generator.spawn_positions[0])
		var opponent: Vector2 = map.call("tile_to_world", generator.spawn_positions[1])
		var center: Vector2 = map.call("tile_to_world", Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2))
		var route: PackedVector2Array = map.call("get_navigation_world_path", start, opponent, 0.0)
		var route_distance: float = _route_length(start, route)
		var center_route: PackedVector2Array = map.call("get_navigation_world_path", start, center, 0.0)
		var routes_reachable: bool = not route.is_empty() and not center_route.is_empty()
		if not routes_reachable:
			failed_routes.append(seed_value)
		var infantry_speed: float = float(UnitData.UNITS[UnitData.UnitType.INFANTRY]["speed"])
		var scout_speed: float = float(UnitData.UNITS[UnitData.UnitType.SCOUT]["speed"])
		rows.append({"routes_reachable": routes_reachable, "seed": seed_value, "width": MapData.MAP_WIDTH, "height": MapData.MAP_HEIGHT, "resource_nodes": count, "finite_stock": stocks, "infantry_base_to_base_seconds": route_distance / infantry_speed if not route.is_empty() else -1.0, "infantry_base_to_center_seconds": _route_length(start, center_route) / infantry_speed if not center_route.is_empty() else -1.0, "scout_base_to_base_seconds": route_distance / scout_speed if not route.is_empty() else -1.0, "gather_tick_seconds": UnitData.VILLAGER_GATHER_TICK_SECONDS})
		map.free()
	var report: Dictionary = {"kind": "Generated-map stock and unopposed canonical navigation estimates; excludes gathering/travel detours from buildings or combat", "rows": rows, "failed_route_seeds": failed_routes}
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failed_routes.is_empty() else 1)


func _route_length(start: Vector2, route: PackedVector2Array) -> float:
	var distance: float = 0.0
	for point: Vector2 in route:
		distance += start.distance_to(point)
		start = point
	return distance
