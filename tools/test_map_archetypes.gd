extends Node
## Generated geometry with real runtime routes and blocked TC footprints.
## This is map structure/fairness evidence, not a combat or gathering simulation.

const FAIRNESS_PROBE = preload("res://tools/probe_map_opening_fairness.gd")
const CLASSIC_HASHES: Dictionary = {
	0: "4d7539ea5a632e703539a1984df6211b178351aa00156d78ba32be6485662001",
	1: "1c07fb650bc672897f21f51caca789e8f35a924604443bb554228bde94e25ae8",
	101: "6f89107e2597c5736c0fa13ba8e69649b1525058860d9930b000986ec3b46452",
	424242: "73efc0faf0df463acd9e69ad48fff93c265735921b0128b0335058df5fcbb809",
	20261021: "d1a136315473c8a4acaddf5b2b3cdb71e013f59cd2aeb30d7c6b89bd27e24a14",
}
var _failures: Array[String] = []
var _reports: Array[Dictionary] = []
var _overview_maps: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe: Node = FAIRNESS_PROBE.new()
	for seed_value: int in CLASSIC_HASHES:
		var classic := MapGenerator.new(seed_value)
		_expect(JSON.stringify(classic.generate()).sha256_text() == CLASSIC_HASHES[seed_value], "classic seed %d changed" % seed_value)
	_expect(MapData.normalize_archetype(-1) == MapData.MapArchetype.OPEN_PLAINS and MapData.normalize_archetype(99) == MapData.MapArchetype.OPEN_PLAINS, "unknown archetypes must normalize to classic")
	var seeds: Array[int] = []
	for value: int in range(32): seeds.append(value)
	seeds.append_array([101, 424242, 20261021])
	for archetype: int in MapData.MAP_ARCHETYPES:
		for seed_value: int in seeds:
			_check_map(seed_value, archetype, probe)
	probe.free()
	var report := {"scope": "105 seeded generated maps; real Pathfinding/GameMap routes, solid TC footprints and explicit closed-crossing geometry; no combat or harvest simulation", "maps": _reports, "overview_maps": _overview_maps, "failures": _failures}
	var output_path: String = "res://output/map-archetypes-2026-10-22/topology.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path).get_base_dir())
	FileAccess.open(output_path, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	if _failures.is_empty():
		print("[PASS] map_archetypes: 105 deterministic symmetric maps, classic hashes preserved, fair opening stock/deposit routes, connected expansions and three independently viable broad river crossings")
		get_tree().quit(0)
	else:
		for failure: String in _failures: push_error("[FAIL] map_archetypes: " + failure)
		get_tree().quit(1)

func _check_map(seed_value: int, archetype: int, probe: Node) -> void:
	var label: String = "%s seed %d" % [MapData.get_archetype_name(archetype), seed_value]
	var generator := MapGenerator.new(seed_value, archetype)
	generator.generate()
	var replay := MapGenerator.new(seed_value, archetype)
	_expect(generator.grid == replay.generate(), label + " not deterministic")
	var sacred_count: int = 0
	var forest_count: int = 0
	var water_count: int = 0
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			_expect(generator.grid[y][x] == generator.grid[x][y], label + " asymmetric at %d,%d" % [x, y])
			match generator.grid[y][x]:
				MapData.TileType.SACRED_SITE: sacred_count += 1
				MapData.TileType.FOREST: forest_count += 1
				MapData.TileType.WATER: water_count += 1
	_expect(sacred_count == 4, label + " missing objective cells")
	var pathfinder := Pathfinding.new(generator)
	var footprint := Vector2i(4, 4)
	for spawn: Vector2i in generator.spawn_positions:
		for dy: int in range(4):
			for dx: int in range(4):
				_expect(MapData.is_grass(generator.get_tile(spawn + Vector2i(dx, dy))), label + " obstructed TC footprint")
		pathfinder.set_area_solid(spawn, footprint)
	var routes: Array[Dictionary] = generator.get_tactical_routes()
	var connected_fraction: float = _land_connectivity(pathfinder, generator, routes[0].waypoints[0], label)
	_expect(connected_fraction >= 0.995, label + " disconnected land exceeds half a percent")
	var route_reports: Array[Dictionary] = []
	var overview_routes: Array[Dictionary] = []
	var map: Node2D = load("res://scripts/map/game_map.gd").new()
	map.set("map_generator", generator)
	map.set("pathfinding", pathfinder)
	for route: Dictionary in routes:
		var points: Array = route["waypoints"]
		var traversed: Array[Vector2i] = []
		for index: int in range(1, points.size()):
			var path: Array[Vector2i] = pathfinder.get_tile_path(points[index - 1], points[index])
			_expect(not path.is_empty(), label + " missing " + str(route.name))
			traversed.append_array(path)
		var length: float = 0.0
		for index: int in range(1, traversed.size()):
			length += (map.call("tile_to_world", traversed[index - 1]) as Vector2).distance_to(map.call("tile_to_world", traversed[index]))
		route_reports.append({"name": route.name, "world_length": length, "crossing": [points[1].x, points[1].y]})
		var path_coordinates: Array = []
		for tile: Vector2i in traversed: path_coordinates.append([tile.x, tile.y])
		overview_routes.append({"name": route.name, "tiles": path_coordinates})
		if archetype == MapData.MapArchetype.RIVER_CROSSINGS:
			var isolated := Pathfinding.new(generator)
			for spawn: Vector2i in generator.spawn_positions: isolated.set_area_solid(spawn, footprint)
			for other: Dictionary in routes:
				if other.name != route.name:
					isolated.set_area_solid((other.waypoints[1] as Vector2i) - Vector2i(7, 7), Vector2i(15, 15))
			for index: int in range(1, points.size()):
				_expect(not isolated.get_tile_path(points[index - 1], points[index]).is_empty(), label + " crossing depends on another: " + str(route.name))
			var crossing: Vector2i = points[1]
			for dy: int in range(-3, 4):
				for dx: int in range(-3, 4):
					_expect(not MapData.is_obstacle(generator.get_tile(crossing + Vector2i(dx, dy))), label + " crossing narrower than seven cells")
	for pocket: Vector2i in generator.get_expansion_pocket_centers():
		_expect(not pathfinder.get_tile_path(routes[0].waypoints[0], pocket).is_empty(), label + " unreachable expansion")
	var fairness: Dictionary = probe.call("measure_seed", seed_value, archetype)
	var max_trip_difference: float = 0.0
	for resource: String in ["food", "wood", "gold"]:
		var required: int = {"food": 4, "wood": 8, "gold": 2}[resource]
		for side: Dictionary in fairness.sides:
			var measurement: Dictionary = side.resources[resource]
			_expect(measurement.reachable and measurement.deposit_reachable, label + " resource route unavailable: " + resource)
			_expect(int(measurement.local_tiles_in_13_radius) >= required, label + " missing visible opening stock: " + resource)
		var difference: float = float(fairness.trip_difference[resource].deposit_seconds)
		max_trip_difference = maxf(max_trip_difference, difference)
		_expect(difference <= 0.60, label + " unfair opening deposit route: " + resource)
	if archetype == MapData.MapArchetype.WOODLAND_FLANKS:
		_expect(forest_count >= 300, label + " lacks distinct woodland routes")
	if archetype == MapData.MapArchetype.RIVER_CROSSINGS:
		_expect(water_count >= 250, label + " lacks a meaningful separating river")
	_reports.append({"seed": seed_value, "archetype": archetype, "name": MapData.get_archetype_name(archetype), "forest_tiles": forest_count, "water_tiles": water_count, "reachable_land_fraction": connected_fraction, "opening_trip_difference_seconds": max_trip_difference, "routes": route_reports})
	if seed_value in [101, 424242, 20261021]:
		var spawns: Array = []
		for spawn: Vector2i in generator.spawn_positions: spawns.append([spawn.x, spawn.y])
		_overview_maps.append({"seed": seed_value, "archetype": archetype, "name": MapData.get_archetype_name(archetype), "grid": generator.grid, "spawns": spawns, "routes": overview_routes, "metrics": _reports[-1]})
	map.free()

func _land_connectivity(pathfinder: Pathfinding, generator: MapGenerator, start: Vector2i, label: String) -> float:
	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var cursor: int = 0
	while cursor < queue.size():
		var tile: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = tile + direction
			if not visited.has(next) and pathfinder.is_walkable(next):
				visited[next] = true
				queue.append(next)
	var walkable: int = 0
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			var tile := Vector2i(x, y)
			if pathfinder.is_walkable(tile): walkable += 1
			if generator.get_tile(tile) in [MapData.TileType.BERRY_BUSH, MapData.TileType.GOLD_MINE, MapData.TileType.FOREST]:
				for spawn: Vector2i in generator.spawn_positions:
					if tile.distance_squared_to(spawn) <= 169.0:
						_expect(visited.has(tile), label + " isolated opening resource at %s" % tile)
	return float(visited.size()) / maxi(1, walkable)

func _expect(condition: bool, message: String) -> void:
	if not condition and _failures.size() < 100:
		_failures.append(message)
