class_name Pathfinding
extends RefCounted
## A* pathfinding on the isometric grid using AStarGrid2D.
## Water and building tiles are obstacles; forest tiles incur higher movement cost.

var _astar := AStarGrid2D.new()
var _map_generator: MapGenerator
## Consumers can invalidate failed destinations after a route opens/closes.
var walkability_revision: int = 0
## Byte mirror of the grid's solid flags (1 = solid), row-major. Movement asks
## is_walkable several times per unit per frame; this keeps it to one read.
var _solid := PackedByteArray()

## Routes are a pure function of (start, goal, grid). Workers ask for the same
## resource <-> drop-off pairs trip after trip, and a builder's reachability
## check is followed by the same request when it sets off: remember answers
## until any tile's solidity or weight changes.
const ROUTE_CACHE_LIMIT := 2048
var _route_cache: Dictionary = {}
var _route_epoch: int = 0
var _route_cache_epoch: int = -1
var _route_failures: int = 0
## 4-connected region id per tile (0 = not flooded this epoch). The grid's
## diagonal rule needs both orthogonal neighbours open, so two tiles are joined
## by a route exactly when they share a region. Flooded lazily, only after
## searches have already failed twice on this grid.
var _regions := PackedInt32Array()
var _region_count: int = 0

const DEFAULT_MAX_PATH_CHECKS := 32
const DEFAULT_START_RECOVERY_RADIUS := 4


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
	_solid.resize(MapData.MAP_WIDTH * MapData.MAP_HEIGHT)
	_solid.fill(0)

	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			var tile_type: MapData.TileType = _map_generator.grid[y][x] as MapData.TileType
			var pos := Vector2i(x, y)

			if MapData.is_obstacle(tile_type):
				_astar.set_point_solid(pos, true)
				_solid[y * MapData.MAP_WIDTH + x] = 1
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
	if _is_solid(from) or _is_solid(to):
		return []
	var raw_path: Array[Vector2i] = _astar.get_id_path(from, to)
	var tile_path: Array[Vector2i] = []
	for tile_id in raw_path:
		tile_path.append(tile_id)
	return tile_path


## Find a path to the first reachable candidate, with hard bounds on both the
## number of A* calls and how far we search for an egress tile. The latter is
## important when a building footprint becomes solid underneath a unit (the
## starting Town Center currently does this for some villagers).
func get_tile_path_to_any(
	from: Vector2i,
	destinations: Array[Vector2i],
	max_path_checks: int = DEFAULT_MAX_PATH_CHECKS,
	start_recovery_radius: int = DEFAULT_START_RECOVERY_RADIUS
) -> Array[Vector2i]:
	if destinations.is_empty() or max_path_checks <= 0:
		return []

	var starts: Array[Vector2i] = []
	if is_walkable(from):
		starts.append(from)
	else:
		starts = get_walkable_tiles_near(from, start_recovery_radius, 12)
	if starts.is_empty():
		return []

	var checks: int = 0
	for destination: Vector2i in destinations:
		if not is_walkable(destination):
			continue
		var destination_best: Array[Vector2i] = []
		for start: Vector2i in starts:
			if checks >= max_path_checks:
				return destination_best.duplicate()
			checks += 1
			var candidate: Array[Vector2i] = _route(start, destination)
			if candidate.is_empty():
				continue
			if destination_best.is_empty() or candidate.size() < destination_best.size():
				destination_best = candidate
		# Destinations are ordered by desirability, so return the best recovered
		# start route to the first destination that can actually be reached.
		if not destination_best.is_empty():
			return destination_best.duplicate()
	return []


## _astar.get_id_path(start, destination) for two walkable tiles, remembered.
## The returned array is shared: callers copy before handing it out.
func _route(start: Vector2i, destination: Vector2i) -> Array[Vector2i]:
	if _route_cache_epoch != _route_epoch:
		_route_cache_epoch = _route_epoch
		_route_cache.clear()
		_route_failures = 0
		_region_count = 0
	var width: int = MapData.MAP_WIDTH
	var start_index: int = start.y * width + start.x
	var destination_index: int = destination.y * width + destination.x
	if _region_count > 0:
		if _regions[start_index] == 0:
			_flood_region(start)
		if _regions[start_index] != _regions[destination_index]:
			return []
	var key: int = start_index * width * MapData.MAP_HEIGHT + destination_index
	var known: Variant = _route_cache.get(key)
	if known != null:
		return known
	var found: Array[Vector2i] = _astar.get_id_path(start, destination)
	if found.is_empty() and start != destination:
		_route_failures += 1
		if _route_failures == 2:
			_regions.resize(width * MapData.MAP_HEIGHT)
			_regions.fill(0)
			_flood_region(start)
	if _route_cache.size() >= ROUTE_CACHE_LIMIT:
		_route_cache.clear()
	_route_cache[key] = found
	return found


## 4-connected region id of a walkable tile on the current grid (0 for a solid
## or off-map tile). Equal ids mean a route exists.
func region_of(tile: Vector2i) -> int:
	if not is_walkable(tile):
		return 0
	if _route_cache_epoch != _route_epoch:
		_route_cache_epoch = _route_epoch
		_route_cache.clear()
		_route_failures = 0
		_region_count = 0
	if _region_count == 0:
		_regions.resize(MapData.MAP_WIDTH * MapData.MAP_HEIGHT)
		_regions.fill(0)
	var index: int = tile.y * MapData.MAP_WIDTH + tile.x
	if _regions[index] == 0:
		_flood_region(tile)
	return _regions[index]


func _flood_region(origin: Vector2i) -> void:
	var width: int = MapData.MAP_WIDTH
	var height: int = MapData.MAP_HEIGHT
	_region_count += 1
	var region: int = _region_count
	var frontier := PackedInt32Array([origin.y * width + origin.x])
	_regions[frontier[0]] = region
	var next: int = 0
	while next < frontier.size():
		var index: int = frontier[next]
		next += 1
		@warning_ignore("integer_division")
		var y: int = index / width
		var x: int = index - y * width
		if x > 0 and _solid[index - 1] == 0 and _regions[index - 1] == 0:
			_regions[index - 1] = region
			frontier.append(index - 1)
		if x < width - 1 and _solid[index + 1] == 0 and _regions[index + 1] == 0:
			_regions[index + 1] = region
			frontier.append(index + 1)
		if y > 0 and _solid[index - width] == 0 and _regions[index - width] == 0:
			_regions[index - width] = region
			frontier.append(index - width)
		if y < height - 1 and _solid[index + width] == 0 and _regions[index + width] == 0:
			_regions[index + width] = region
			frontier.append(index + width)


## Return walkable tiles around `center`, nearest first. Search and output are
## both bounded so callers cannot accidentally turn recovery into a map scan.
func get_walkable_tiles_near(center: Vector2i, radius: int, max_results: int = 32) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var bounded_radius: int = clampi(radius, 0, maxi(MapData.MAP_WIDTH, MapData.MAP_HEIGHT))
	for dy in range(-bounded_radius, bounded_radius + 1):
		for dx in range(-bounded_radius, bounded_radius + 1):
			var candidate := center + Vector2i(dx, dy)
			if is_walkable(candidate):
				candidates.append(candidate)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return center.distance_squared_to(a) < center.distance_squared_to(b)
	)
	if max_results >= 0 and candidates.size() > max_results:
		candidates.resize(max_results)
	return candidates


## Check if a tile position is walkable.
func is_walkable(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < MapData.MAP_WIDTH and pos.y < MapData.MAP_HEIGHT and _solid[pos.y * MapData.MAP_WIDTH + pos.x] == 0


## Mark a tile as solid (e.g., when a building is placed).
func set_solid(pos: Vector2i, solid: bool = true) -> void:
	if _in_bounds(pos) and _astar.is_point_solid(pos) != solid:
		_astar.set_point_solid(pos, solid)
		_solid[pos.y * MapData.MAP_WIDTH + pos.x] = 1 if solid else 0
		walkability_revision += 1
		_route_epoch += 1


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
		set_solid(pos, true)
	else:
		set_solid(pos, false)
		_route_epoch += 1
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
