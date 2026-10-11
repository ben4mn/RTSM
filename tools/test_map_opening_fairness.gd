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
		print("[PASS] map_opening_fairness: 64 reproducible varied maps, reflected terrain, intact TC/objective and reachable food/wood/gold deposit routes on both starts")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] map_opening_fairness: " + failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
