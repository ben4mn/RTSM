class_name Pathfinding
extends RefCounted
## A* pathfinding on the isometric grid using AStarGrid2D.
## Water and building tiles are obstacles; forest tiles incur higher movement cost.

var _astar := AStarGrid2D.new()
var _map_generator: MapGenerator


func _init(map_gen: MapGenerator) -> void:
	_map_generator = map_gen
	_setup_grid()


## Initialize the AStarGrid2D from the generated map.
func _setup_grid() -> void:
	_astar.region = Rect2i(0, 0, MapData.MAP_WIDTH, MapData.MAP_HEIGHT)
	_astar.cell_size = Vector2(MapData.TILE_WIDTH, MapData.TILE_HEIGHT)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.update()

	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			var tile_type: MapData.TileType = _map_generator.grid[y][x] as MapData.TileType
			var pos := Vector2i(x, y)

			if MapData.is_obstacle(tile_type):
				_astar.set_point_solid(pos, true)
			elif tile_type == MapData.TileType.FOREST:
				_astar.set_point_weight_scale(pos, MapData.FOREST_MOVE_COST)


## Get a path between two tile positions.
## Returns an array of Vector2i tile coordinates.
func get_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if _is_solid(from) or _is_solid(to):
		return PackedVector2Array()
	return _astar.get_point_path(from, to)


## Get a path as tile coordinates (Vector2i array).
func get_tile_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var raw_path := get_path(from, to)
	var tile_path: Array[Vector2i] = []
	for point in raw_path:
		tile_path.append(Vector2i(roundi(point.x), roundi(point.y)))
	return tile_path


## Check if a tile position is walkable.
func is_walkable(pos: Vector2i) -> bool:
	return not _is_solid(pos)


## Mark a tile as solid (e.g., when a building is placed).
func set_solid(pos: Vector2i, solid: bool = true) -> void:
	if _in_bounds(pos):
		_astar.set_point_solid(pos, solid)


## Mark a rectangular area as solid (for buildings).
func set_area_solid(origin: Vector2i, size: Vector2i, solid: bool = true) -> void:
	for dy in range(size.y):
		for dx in range(size.x):
			set_solid(origin + Vector2i(dx, dy), solid)


## Update a single tile's walkability/weight (e.g., after building placement/destruction).
func update_tile(pos: Vector2i, tile_type: MapData.TileType) -> void:
	if not _in_bounds(pos):
		return
	if MapData.is_obstacle(tile_type):
		_astar.set_point_solid(pos, true)
	else:
		_astar.set_point_solid(pos, false)
		if tile_type == MapData.TileType.FOREST:
			_astar.set_point_weight_scale(pos, MapData.FOREST_MOVE_COST)
		else:
			_astar.set_point_weight_scale(pos, 1.0)


func _is_solid(pos: Vector2i) -> bool:
	if not _in_bounds(pos):
		return true
	return _astar.is_point_solid(pos)


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < MapData.MAP_WIDTH and pos.y >= 0 and pos.y < MapData.MAP_HEIGHT
