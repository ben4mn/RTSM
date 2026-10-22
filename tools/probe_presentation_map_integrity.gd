extends Node
## Real generated GameMap scenes. Presentation may change; geometry must not.
## No AI, economic grants, live socket, or frame-rate measurement.

const SEEDS: Array[int] = [101, 424242, 20261021]
const MAP_SCENE: PackedScene = preload("res://scenes/map/game_map.tscn")
var failures: Array[String] = []
var cases: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	for archetype: int in range(3):
		for seed_value: int in SEEDS:
			await _measure(archetype, seed_value)
	var source: Dictionary = {}
	for path: String in ["scripts/map/game_map.gd", "scripts/map/map_generator.gd", "scripts/map/pathfinding.gd", "scripts/map/map_data.gd", "scripts/map/resource_node.gd", "scripts/map/tileset_builder.gd", "tools/probe_presentation_map_integrity.gd"]:
		source[path] = FileAccess.get_sha256("res://" + path)
	var output: String = "res://output/presentation-integrity/map.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var report: Dictionary = {"source_hashes": source, "user_data_dir": OS.get_user_data_dir(), "cases": cases, "failures": failures}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	for failure: String in failures: push_error("[FAIL] presentation_map_integrity: " + failure)
	if failures.is_empty(): print("[PASS] presentation_map_integrity: nine real maps, exact grid/stock/collision/path receipts and nine independent River crossing paths")
	get_tree().quit(0 if failures.is_empty() else 1)

func _measure(archetype: int, seed_value: int) -> void:
	GameManager.selected_map_seed = seed_value
	GameManager.selected_map_archetype = archetype
	var map: Node2D = MAP_SCENE.instantiate()
	map.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(map)
	await get_tree().process_frame
	var generator: MapGenerator = map.map_generator
	var pathfinder: Pathfinding = map.pathfinding
	var label: String = "%d/%d" % [archetype, seed_value]
	var replay := MapGenerator.new(seed_value, archetype)
	_check(generator.grid == replay.generate(), label + " runtime map differs from same-seed generation")
	var terrain: TileMapLayer = map.terrain_layer
	var atlas: TileSetAtlasSource = terrain.tile_set.get_source(0) as TileSetAtlasSource
	var cells: Array = []
	var stocks: Array = []
	var expected_resources: int = 0
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			var tile := Vector2i(x, y)
			var kind: int = generator.grid[y][x]
			var coords: Vector2i = terrain.get_cell_atlas_coords(tile)
			_check(terrain.get_cell_source_id(tile) == 0 and atlas.has_tile(coords), label + " missing rendered tile " + str(tile))
			cells.append([x, y, coords.x, coords.y])
			if kind not in [MapData.TileType.FOREST, MapData.TileType.BERRY_BUSH, MapData.TileType.GOLD_MINE]: continue
			expected_resources += 1
			var resource: ResourceNode = map.get_resource_node_at(tile) as ResourceNode
			_check(is_instance_valid(resource), label + " missing natural resource " + str(tile))
			if not is_instance_valid(resource): continue
			var sprite: Sprite2D = resource.get_node("Sprite") as Sprite2D
			var collision: CollisionShape2D = null
			for child: Node in resource.get_children():
				if child is CollisionShape2D: collision = child
			_check(collision != null and collision.shape is CircleShape2D, label + " natural resource collision missing")
			stocks.append([x, y, resource.resource_type, resource.total_amount, resource.remaining, _point(resource.position), collision.shape.radius if collision != null else -1, sprite.texture.resource_path, _point(sprite.scale), _point(sprite.offset)])
	_check(map.resource_nodes.size() == expected_resources, label + " resource registry count differs")
	var spawns: Array = []
	for spawn: Vector2i in generator.spawn_positions:
		spawns.append([spawn.x, spawn.y])
		map.place_building_obstacle(spawn, Vector2i(4, 4))
	var walkability: Array = []
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			var tile := Vector2i(x, y)
			walkability.append([pathfinder.is_walkable(tile), pathfinder._astar.get_point_weight_scale(tile)])
	var routes: Array[Dictionary] = []
	var isolated_routes: Array[Dictionary] = []
	for route: Dictionary in generator.get_tactical_routes():
		var tile_paths: Array = []
		var world_paths: Array = []
		var points: Array = route.waypoints
		for index: int in range(1, points.size()):
			var path: Array[Vector2i] = pathfinder.get_tile_path(points[index - 1], points[index])
			_validate_path(pathfinder, path, label + " " + route.name)
			tile_paths.append(_tiles(path))
			var world_path: PackedVector2Array = map.get_navigation_world_path(map.tile_to_world(points[index - 1]), map.tile_to_world(points[index]))
			_check(not world_path.is_empty(), label + " empty world route " + route.name)
			var world_points: Array = []
			for point: Vector2 in world_path:
				_check(pathfinder.is_walkable(map.world_to_tile(point)), label + " world route enters solid tile")
				world_points.append(_point(point))
			world_paths.append(world_points)
		var waypoints: Array = []
		for point: Vector2i in points: waypoints.append([point.x, point.y])
		routes.append({"name": route.name, "waypoints": waypoints, "tile_paths": tile_paths, "world_paths": world_paths})
		if archetype == MapData.MapArchetype.RIVER_CROSSINGS:
			var isolated := Pathfinding.new(generator)
			for spawn: Vector2i in generator.spawn_positions: isolated.set_area_solid(spawn, Vector2i(4, 4))
			for other: Dictionary in generator.get_tactical_routes():
				if other.name != route.name: isolated.set_area_solid((other.waypoints[1] as Vector2i) - Vector2i(7, 7), Vector2i(15, 15))
			var segments: Array = []
			for index: int in range(1, points.size()):
				var path: Array[Vector2i] = isolated.get_tile_path(points[index - 1], points[index])
				_validate_path(isolated, path, label + " isolated " + route.name)
				segments.append(_tiles(path))
			isolated_routes.append({"name": route.name, "paths": segments})
	var expansion_paths: Array = []
	var origin: Vector2i = generator.get_tactical_routes()[0].waypoints[0]
	for pocket: Vector2i in generator.get_expansion_pocket_centers():
		var path: Array[Vector2i] = pathfinder.get_tile_path(origin, pocket)
		_validate_path(pathfinder, path, label + " expansion")
		expansion_paths.append(_tiles(path))
	cases.append({"map": archetype, "seed": seed_value, "mechanics": {"grid_sha256": _hash(generator.grid), "resources_sha256": _hash(stocks), "resource_count": expected_resources, "spawns": spawns, "walkability_and_weights_sha256": _hash(walkability), "tactical_paths_sha256": _hash(routes), "independent_crossings_sha256": _hash(isolated_routes), "expansion_paths_sha256": _hash(expansion_paths), "routes": routes, "independent_crossings": isolated_routes}, "presentation": {"atlas_assignments_sha256": _hash(cells), "atlas_tile_count": atlas.get_tiles_count()}})
	map.free()

func _validate_path(pathfinder: Pathfinding, path: Array[Vector2i], label: String) -> void:
	_check(not path.is_empty(), label + " has no route")
	for index: int in range(path.size()):
		var tile: Vector2i = path[index]
		_check(pathfinder.is_walkable(tile), label + " route is blocked")
		if index == 0: continue
		var delta: Vector2i = tile - path[index - 1]
		_check(absi(delta.x) <= 1 and absi(delta.y) <= 1, label + " route jumps a tile")
		if delta.x != 0 and delta.y != 0:
			_check(pathfinder.is_walkable(tile - Vector2i(delta.x, 0)) and pathfinder.is_walkable(tile - Vector2i(0, delta.y)), label + " cuts a blocked diagonal")

func _tiles(path: Array[Vector2i]) -> Array:
	var result: Array = []
	for point: Vector2i in path: result.append([point.x, point.y])
	return result

func _point(point: Vector2) -> Array:
	return [point.x, point.y]

func _hash(value: Variant) -> String:
	return JSON.stringify(value).sha256_text()

func _check(condition: bool, message: String) -> void:
	if not condition and failures.size() < 100: failures.append(message)
