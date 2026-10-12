extends Node
## Real generated maps and runtime routes, with only the TC footprint fixture.
## Keeps starts equivalent without replacing seed variety with a fixed map.

const PROBE_SCRIPT = preload("res://tools/probe_map_opening_fairness.gd")
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var probe: Node = PROBE_SCRIPT.new()
	var previous_grid: Array = []
	var has_variety: bool = false
	for seed_value: int in range(64):
		var generator := MapGenerator.new(seed_value)
		generator.generate()
		var left_offsets: Array[Vector2i] = generator.get_starting_villager_offsets(0)
		var right_offsets: Array[Vector2i] = generator.get_starting_villager_offsets(1)
		for index: int in range(left_offsets.size()):
			_expect(right_offsets[index] == Vector2i(left_offsets[index].y, left_offsets[index].x), "seed %d each assigned worker starts at the corresponding resource approach" % seed_value)
		generator.spawn_positions.reverse()
		_expect(generator.get_starting_villager_offsets(0) == right_offsets and generator.get_starting_villager_offsets(1) == left_offsets, "seed %d swapped starts preserve worker orientation" % seed_value)
		generator.spawn_positions.reverse()
		var replay := MapGenerator.new(seed_value)
		_expect(generator.grid == replay.generate(), "seed %d remains reproducible" % seed_value)
		if not previous_grid.is_empty() and generator.grid != previous_grid:
			has_variety = true
		previous_grid = generator.grid.duplicate(true)
		var sacred_tiles: int = 0
		for y: int in range(MapData.MAP_HEIGHT):
			for x: int in range(MapData.MAP_WIDTH):
				_expect(generator.grid[y][x] == generator.grid[x][y], "seed %d terrain at %d,%d preserves spawn reflection" % [seed_value, x, y])
				if generator.grid[y][x] == MapData.TileType.SACRED_SITE:
					sacred_tiles += 1
		_expect(sacred_tiles == 4, "seed %d keeps the full Sacred Site" % seed_value)
		for spawn: Vector2i in generator.spawn_positions:
			for dy: int in range(4):
				for dx: int in range(4):
					_expect(MapData.is_grass(generator.get_tile(spawn + Vector2i(dx, dy))), "seed %d TC footprint remains open" % seed_value)
		var navigation := Pathfinding.new(generator)
		var expansion_map: Node2D = load("res://scripts/map/game_map.gd").new()
		expansion_map.set("map_generator", generator)
		expansion_map.set("pathfinding", navigation)
		var tc_footprint: Vector2i = BuildingData.BUILDINGS[BuildingData.BuildingType.TOWN_CENTER]["footprint"]
		for spawn: Vector2i in generator.spawn_positions:
			navigation.set_area_solid(spawn, tc_footprint)
		var start_world: Vector2 = expansion_map.call("tile_to_world", generator.spawn_positions[0])
		for pocket: Vector2i in generator.get_expansion_pocket_centers():
			_expect(generator.spawn_positions[0].distance_to(pocket) > 16.0, "seed %d expansion requires scouting beyond opening vision" % seed_value)
			var pocket_world: Vector2 = expansion_map.call("tile_to_world", pocket)
			var pocket_route: PackedVector2Array = expansion_map.call("get_navigation_world_path", start_world, pocket_world, 0.0)
			_expect(not pocket_route.is_empty(), "seed %d expansion work perimeter is reachable around starting TC" % seed_value)
			var stocks: Dictionary = {MapData.TileType.BERRY_BUSH: 0, MapData.TileType.GOLD_MINE: 0, MapData.TileType.FOREST: 0}
			for dy: int in range(-3, 4):
				for dx: int in range(-3, 4):
					var resource: int = generator.get_tile(pocket + Vector2i(dx, dy))
					if stocks.has(resource):
						stocks[resource] += 1
						for player_id: int in [0, 1]:
							var resource_tile: Vector2i = pocket + Vector2i(dx, dy)
							if player_id == 1:
								resource_tile = Vector2i(resource_tile.y, resource_tile.x)
							var approach_start: Vector2 = expansion_map.call("tile_to_world", generator.spawn_positions[player_id])
							var target_world: Vector2 = expansion_map.call("tile_to_world", resource_tile)
							var approach: PackedVector2Array = expansion_map.call("get_navigation_world_path", approach_start, target_world, MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD)
							_expect(not approach.is_empty() and approach[-1].distance_to(target_world) <= MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD + 0.1, "seed %d player %d expansion source has a real gather approach around both TC footprints" % [seed_value, player_id])
			_expect(stocks[MapData.TileType.BERRY_BUSH] == 2 and stocks[MapData.TileType.GOLD_MINE] == 1 and stocks[MapData.TileType.FOREST] == 4, "seed %d finite expansion stocks are present and reflected" % seed_value)
		expansion_map.free()
		var metrics: Dictionary = probe.call("measure_seed", seed_value)
		for resource_name: String in ["food", "wood", "gold"]:
			var sides: Array = metrics["sides"]
			var first: Dictionary = sides[0]["resources"][resource_name]
			var second: Dictionary = sides[1]["resources"][resource_name]
			_expect(first["reachable"] and second["reachable"] and first["deposit_reachable"] and second["deposit_reachable"], "seed %d %s has an outbound and real deposit route on both starts" % [seed_value, resource_name])
			_expect(first["local_tiles_in_13_radius"] == second["local_tiles_in_13_radius"], "seed %d %s revealed source count matches" % [seed_value, resource_name])
			var guaranteed_count: int = {"food": 4, "wood": 8, "gold": 2}[resource_name]
			_expect(int(first["local_tiles_in_13_radius"]) >= guaranteed_count, "seed %d %s guaranteed stock is visible before scouting" % [seed_value, resource_name])
			# AStar goal ties can select a different equivalent diagonal edge;
			# allow one tile of travel at 60px/s while rejecting the old 2x trips.
			_expect(float(metrics["trip_difference"][resource_name]["deposit_seconds"]) <= 0.60, "seed %d %s actual anchor trip is fair within one tile" % [seed_value, resource_name])
	_expect(has_variety, "the fair opening preserves seeded terrain variety")
	probe.free()
	if _failures.is_empty():
		print("[PASS] map_opening_fairness: 64 reproducible varied maps, reflected terrain, intact TC/objective, fair starting deposits and 1792 reachable expansion harvest approaches around real TC footprints")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] map_opening_fairness: " + failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
