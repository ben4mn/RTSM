class_name MapGenerator
extends RefCounted
## Generates a symmetric duel map with readable spawn pockets,
## central contest space, and mobile-friendly lanes between bases.

## Emitted after map generation with the resulting tile grid.
## grid is Array[Array] of MapData.TileType values (row-major).

var _rng := RandomNumberGenerator.new()
const SPAWN_EDGE_PADDING := 14
const SPAWN_CLEAR_RADIUS := 11
const CENTER_CLEAR_RADIUS := 7
const FEATURE_SPAWN_BUFFER := 13
const FEATURE_CENTER_BUFFER := 8
const CORRIDOR_HALF_WIDTH := 4
const EXPANSION_CLEAR_RADIUS := 8

## The generated tile grid: an array of rows, each containing MapData.TileType values.
var grid: Array = []
## Carved army routes stay open after the later resource-placement phase.
var _route_tiles: Dictionary = {}

## Spawn positions for each player (tile coords). Index 0 = P1, 1 = P2.
var spawn_positions: Array[Vector2i] = []
var archetype: int = MapData.MapArchetype.OPEN_PLAINS
var _flank_crossings: Array[Vector2i] = []
var _expansion_centers: Array[Vector2i] = []
var _opening_rotation: int = 0
var _lane_half_width: int = 4
var validation_report: Dictionary = {}
var _resource_amounts: Dictionary = {}


func _init(seed_value: int = -1, map_archetype: int = MapData.MapArchetype.OPEN_PLAINS) -> void:
	archetype = MapData.normalize_archetype(map_archetype)
	_flank_crossings = [_scaled_tile(Vector2i(20, 20)), _scaled_tile(Vector2i(52, 52))]
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Generate a new map and return the tile grid.
func generate() -> Array:
	_init_grid()
	_place_sacred_site()
	_place_spawn_positions()
	_roll_layout()
	_place_water_features()
	_place_forest_clusters()
	_place_archetype_features()
	_ensure_spawn_clearance()
	_ensure_center_lane()
	_ensure_tactical_lanes()
	_ensure_expansion_clearance()
	# Finish all terrain carving before placing finite stock. No crossing or
	# expansion corridor may erase a promised opening deposit.
	_place_resources()
	_place_guaranteed_near_spawn_resources()
	_place_contested_mid_resources()
	_place_expansion_resources()
	_add_grass_variety()
	_budget_natural_stock()
	validation_report = validate_layout()
	if not bool(validation_report["valid"]):
		push_error("Generated battlefield failed validation: %s" % str(validation_report))
	return grid


## One RNG owns all geometry; mirrored players receive identical access/stock.
func _roll_layout() -> void:
	var upper: int = _rng.randi_range(19, 31)
	var lower: int = _rng.randi_range(57, 69)
	_flank_crossings = [Vector2i(upper, upper), Vector2i(lower, lower)]
	_opening_rotation = _rng.randi_range(0, 3)
	_lane_half_width = _rng.randi_range(3, 4)
	var spawn: Vector2i = spawn_positions[0]
	_expansion_centers = [spawn + Vector2i(_rng.randi_range(6, 11), -_rng.randi_range(22, 27)), spawn + Vector2i(_rng.randi_range(22, 27), -_rng.randi_range(6, 11))]


func _place_archetype_features() -> void:
	match archetype:
		MapData.MapArchetype.RIVER_CROSSINGS:
			_place_crossing_river()
		MapData.MapArchetype.WOODLAND_FLANKS:
			_place_flanking_woodlands()
		MapData.MapArchetype.TWIN_LAKES:
			var lake_center := Vector2i(_rng.randi_range(9, 13), _rng.randi_range(37, 42))
			for y: int in range(-9, 10):
				for x: int in range(-8, 9):
					var tile: Vector2i = lake_center + Vector2i(x, y)
					if float(x * x) / 64.0 + float(y * y) / 81.0 <= 1.0 and not _is_near_spawn(tile, FEATURE_SPAWN_BUFFER) and not _is_near_center(tile, CENTER_CLEAR_RADIUS):
						_set_symmetric_tile(tile, MapData.TileType.WATER)
		MapData.MapArchetype.GOLDEN_BASIN:
			for center: Vector2i in [Vector2i(12, 32), Vector2i(31, 74), Vector2i(8, 49)]:
				_place_woodland_ellipse(center, 7, 10)


## A diagonal river separates the two starts. Three independent broad land
## crossings are carved afterwards; occupying the objective cannot close them.
func _place_crossing_river() -> void:
	var bank_phase: int = _rng.randi_range(0, 3)
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(y + 1):
			var tile := Vector2i(x, y)
			var half_width: int = 3 + posmod(int((x + y) / 9) + bank_phase, 2)
			if absi(x - y) <= half_width and not _is_near_center(tile, CENTER_CLEAR_RADIUS):
				_set_symmetric_tile(tile, MapData.TileType.WATER)


## Larger woods make route choice and expansion scouting matter. They keep the
## existing forest routing weight; no camouflage, armor or speed bonus is added.
func _place_flanking_woodlands() -> void:
	var centers: Array[Vector2i] = [Vector2i(12, 30), Vector2i(40, 61), Vector2i(6, 43)]
	for base: Vector2i in centers:
		var center: Vector2i = _scaled_tile(base) + Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-2, 2))
		_place_woodland_ellipse(center, _rng.randi_range(5, 7), _rng.randi_range(7, 9))
	for crossing: Vector2i in _flank_crossings:
		_place_woodland_ellipse(crossing, 7, 7)


func _place_woodland_ellipse(center: Vector2i, radius_x: int, radius_y: int) -> void:
	for dy: int in range(-radius_y, radius_y + 1):
		for dx: int in range(-radius_x, radius_x + 1):
			if pow(float(dx) / radius_x, 2.0) + pow(float(dy) / radius_y, 2.0) > 1.0:
				continue
			var tile: Vector2i = center + Vector2i(dx, dy)
			if not _in_bounds(tile.x, tile.y) or _is_near_spawn(tile, 14) or _is_near_center(tile, FEATURE_CENTER_BUFFER):
				continue
			if grid[tile.y][tile.x] == MapData.TileType.GRASS:
				_set_symmetric_tile(tile, MapData.TileType.FOREST)


## Explicit geometry for scouting/route probes; these are connected routes, not
## orders or AI knowledge. Both flank routes bypass the Sacred Site entirely.
func get_tactical_routes() -> Array[Dictionary]:
	if spawn_positions.size() < 2:
		return []
	var start: Vector2i = spawn_positions[0] + Vector2i(4, -4)
	var finish: Vector2i = _mirror_tile(start)
	var center := Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2)
	return [
		{"name": "Center", "waypoints": [start, center, finish]},
		{"name": "Upper flank", "waypoints": [start, _flank_crossings[0], finish]},
		{"name": "Lower flank", "waypoints": [start, _flank_crossings[1], finish]},
	]


func _ensure_tactical_lanes() -> void:
	for route: Dictionary in get_tactical_routes():
		var points: Array = route["waypoints"]
		for index: int in range(1, points.size()):
			var from_tile: Vector2i = points[index - 1]
			var to_tile: Vector2i = points[index]
			_carve_grass_corridor(from_tile, to_tile, _lane_half_width)
			# Explicit reflection also handles round-to-nearest ties at bends.
			_carve_grass_corridor(_mirror_tile(from_tile), _mirror_tile(to_tile), _lane_half_width)


## Fill the entire grid with grass.
func _init_grid() -> void:
	grid.clear()
	_route_tiles.clear()
	for y in range(MapData.MAP_HEIGHT):
		var row: Array = []
		row.resize(MapData.MAP_WIDTH)
		row.fill(MapData.TileType.GRASS)
		grid.append(row)


## Place the sacred site at the center of the map.
func _place_sacred_site() -> void:
	@warning_ignore("integer_division")
	var cx := MapData.MAP_WIDTH / 2
	@warning_ignore("integer_division")
	var cy := MapData.MAP_HEIGHT / 2
	# 2x2 sacred site centered at (cx-1,cy-1) to (cx,cy)
	for dy in range(-1, 1):
		for dx in range(-1, 1):
			_set_tile(cx + dx, cy + dy, MapData.TileType.SACRED_SITE)


## Place small symmetric water features (lakes).
func _place_water_features() -> void:
	var num_lakes := _rng.randi_range(3, 4)
	for i in range(num_lakes):
		var lake_size := _rng.randi_range(3, 6)
		for _attempt in range(80):
			@warning_ignore("integer_division")
			var lx := _rng.randi_range(SPAWN_EDGE_PADDING + 2, MapData.MAP_WIDTH / 2 - FEATURE_CENTER_BUFFER - 1)
			var ly := _rng.randi_range(SPAWN_EDGE_PADDING + 1, MapData.MAP_HEIGHT - SPAWN_EDGE_PADDING - 2)
			if not _can_place_symmetric_seed(Vector2i(lx, ly), FEATURE_SPAWN_BUFFER, FEATURE_CENTER_BUFFER):
				continue
			_place_blob(lx, ly, lake_size, MapData.TileType.WATER)
			break


## Place stealth forest clusters symmetrically.
func _place_forest_clusters() -> void:
	var num_clusters := _rng.randi_range(9, 12)
	for i in range(num_clusters):
		var cluster_size := _rng.randi_range(5, 9)
		for _attempt in range(80):
			@warning_ignore("integer_division")
			var fx := _rng.randi_range(3, MapData.MAP_WIDTH / 2 - 3)
			var fy := _rng.randi_range(3, MapData.MAP_HEIGHT - 4)
			if not _can_place_symmetric_seed(Vector2i(fx, fy), FEATURE_SPAWN_BUFFER, FEATURE_CENTER_BUFFER):
				continue
			_place_blob(fx, fy, cluster_size, MapData.TileType.FOREST)
			break


## Place gold mines, berry bushes, and stone deposits symmetrically.
func _place_resources() -> void:
	# Forward expansion resources.
	_place_resource_pair(MapData.TileType.GOLD_MINE, 5)
	_place_resource_pair(MapData.TileType.BERRY_BUSH, 7)
	_place_resource_pair(MapData.TileType.STONE, 4)


func _place_resource_pair(tile_type: MapData.TileType, count: int) -> void:
	for i in range(count):
		for _attempt in range(80):
			@warning_ignore("integer_division")
			var rx := _rng.randi_range(3, MapData.MAP_WIDTH / 2 - 3)
			var ry := _rng.randi_range(3, MapData.MAP_HEIGHT - 4)
			if not _can_place_symmetric_seed(Vector2i(rx, ry), SPAWN_CLEAR_RADIUS + 1, CENTER_CLEAR_RADIUS + 1):
				continue
			if grid[ry][rx] == MapData.TileType.GRASS:
				_set_symmetric_tile(Vector2i(rx, ry), tile_type)
				break


## Set player spawn positions inward from the corners to improve mobile camera room.
func _place_spawn_positions() -> void:
	spawn_positions.clear()
	spawn_positions.append(Vector2i(SPAWN_EDGE_PADDING, MapData.MAP_HEIGHT - 1 - SPAWN_EDGE_PADDING))
	spawn_positions.append(Vector2i(MapData.MAP_WIDTH - 1 - SPAWN_EDGE_PADDING, SPAWN_EDGE_PADDING))


## Preserve each worker's assigned resource approach under the map reflection.
## Resolve orientation from the actual spawn so swapped-start probes stay fair.
func get_starting_villager_offsets(player_id: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = [Vector2i(1, 2), Vector2i(-1, 2), Vector2i(0, 3), Vector2i(2, 1)]
	if player_id < 0 or player_id >= spawn_positions.size():
		return offsets
	var spawn: Vector2i = spawn_positions[player_id]
	if spawn.x > spawn.y:
		for index: int in range(offsets.size()):
			offsets[index] = _mirror_tile(offsets[index])
	return offsets


## Clear a large area around each spawn so early touch interactions stay readable.
func _ensure_spawn_clearance() -> void:
	for spawn in spawn_positions:
		for dy in range(-SPAWN_CLEAR_RADIUS, SPAWN_CLEAR_RADIUS + 1):
			for dx in range(-SPAWN_CLEAR_RADIUS, SPAWN_CLEAR_RADIUS + 1):
				var tx := spawn.x + dx
				var ty := spawn.y + dy
				if _in_bounds(tx, ty):
					_set_tile(tx, ty, MapData.TileType.GRASS)


## Keep the center readable and carve a shallow lane from each base toward mid-map.
func _ensure_center_lane() -> void:
	var center := Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2)
	for y in range(center.y - CENTER_CLEAR_RADIUS, center.y + CENTER_CLEAR_RADIUS + 1):
		for x in range(center.x - CENTER_CLEAR_RADIUS, center.x + CENTER_CLEAR_RADIUS + 1):
			if not _in_bounds(x, y):
				continue
			if grid[y][x] == MapData.TileType.SACRED_SITE:
				continue
			_set_tile(x, y, MapData.TileType.GRASS)
	for spawn in spawn_positions:
		_carve_grass_corridor(spawn, center, CORRIDOR_HALF_WIDTH)


## One random walk places both halves of a feature. Independent walks can
## create unequal obstacles and forest approach costs even with equal counts.
func _place_blob(cx: int, cy: int, size: int, tile_type: MapData.TileType) -> void:
	var placed := 0
	var x := cx
	var y := cy
	var attempts: int = 0
	while placed < size and attempts < size * 100:
		attempts += 1
		var tile := Vector2i(x, y)
		var mirrored: Vector2i = _mirror_tile(tile)
		if (
			_in_bounds(x, y) and grid[y][x] == MapData.TileType.GRASS
			and grid[mirrored.y][mirrored.x] == MapData.TileType.GRASS
			and not _is_near_center(tile, CENTER_CLEAR_RADIUS)
		):
			_set_symmetric_tile(tile, tile_type)
			placed += 1
		# Random walk step
		var dir := _rng.randi_range(0, 3)
		match dir:
			0: x += 1
			1: x -= 1
			2: y += 1
			3: y -= 1
		x = clampi(x, 0, MapData.MAP_WIDTH - 1)
		y = clampi(y, 0, MapData.MAP_HEIGHT - 1)


## Authored, finite resource groves around a broad construction clearing.
## Every source remains inside the actual 13-tile starting TC reveal. Reflection
## gives the other player the identical access and stock without resource cheats.
func _place_guaranteed_near_spawn_resources() -> void:
	var spawn: Vector2i = spawn_positions[0]
	# Add a rear row, preserving the nearest approaches and open village core.
	_place_resource_rectangle(spawn + Vector2i(-9, -6), Vector2i(4, 3), MapData.TileType.BERRY_BUSH)
	_place_resource_rectangle(spawn + Vector2i(6, 4), Vector2i(4, 6), MapData.TileType.FOREST)
	_place_resource_rectangle(spawn + Vector2i(-7, 7), Vector2i(2, 2), MapData.TileType.GOLD_MINE)
	_place_resource_rectangle(spawn + Vector2i(-8, 4), Vector2i(2, 1), MapData.TileType.STONE)


func _place_resource_rectangle(anchor: Vector2i, size: Vector2i, tile_type: MapData.TileType) -> void:
	for dy: int in range(size.y):
		for dx: int in range(size.x):
			var offset: Vector2i = anchor + Vector2i(dx, dy) - spawn_positions[0]
			for turn: int in range(_opening_rotation):
				offset = Vector2i(-offset.y, offset.x)
			_set_symmetric_tile(spawn_positions[0] + offset, tile_type)


func _place_contested_mid_resources() -> void:
	_place_center_resource_pair(MapData.TileType.GOLD_MINE, 7 if archetype == MapData.MapArchetype.GOLDEN_BASIN else 2, 4, 12)
	_place_center_resource_pair(MapData.TileType.STONE, 1, 5, 8)
	_place_center_resource_pair(MapData.TileType.BERRY_BUSH, 1, 4, 6)


## Two genuinely stocked side compounds per player, beyond starting vision.
## The central 5x5 pad stays resource-free for a paid camp, farms or a new TC;
## resource fringes and a broad approach make these buildable destinations.
func get_expansion_pocket_centers() -> Array[Vector2i]:
	var spawn: Vector2i = spawn_positions[0]
	return _expansion_centers if not _expansion_centers.is_empty() else [spawn + Vector2i(8, -22), spawn + Vector2i(22, -8)]


func _ensure_expansion_clearance() -> void:
	var approach: Vector2i = spawn_positions[0] + Vector2i(5, -5)
	for center: Vector2i in get_expansion_pocket_centers():
		_carve_grass_corridor(approach, center, CORRIDOR_HALF_WIDTH)
		_carve_grass_corridor(_mirror_tile(approach), _mirror_tile(center), CORRIDOR_HALF_WIDTH)
		for dy: int in range(-EXPANSION_CLEAR_RADIUS, EXPANSION_CLEAR_RADIUS + 1):
			for dx: int in range(-EXPANSION_CLEAR_RADIUS, EXPANSION_CLEAR_RADIUS + 1):
				_set_symmetric_tile(center + Vector2i(dx, dy), MapData.TileType.GRASS)


func _place_expansion_resources() -> void:
	for center: Vector2i in get_expansion_pocket_centers():
		_place_expansion_patch(center, Vector2i(-5, -1), 12, MapData.TileType.BERRY_BUSH)
		_place_expansion_patch(center, Vector2i(1, -5), 4, MapData.TileType.GOLD_MINE)
		_place_expansion_patch(center, Vector2i(5, -3), 2, MapData.TileType.STONE)
		_place_expansion_patch(center, Vector2i(4, 4), 20, MapData.TileType.FOREST)


func _place_expansion_patch(center: Vector2i, preferred_offset: Vector2i, count: int, tile_type: MapData.TileType) -> void:
	var candidates: Array[Vector2i] = []
	for dy: int in range(-EXPANSION_CLEAR_RADIUS, EXPANSION_CLEAR_RADIUS + 1):
		for dx: int in range(-EXPANSION_CLEAR_RADIUS, EXPANSION_CLEAR_RADIUS + 1):
			if maxi(absi(dx), absi(dy)) <= 2:
				continue
			var tile: Vector2i = center + Vector2i(dx, dy)
			var mirrored: Vector2i = _mirror_tile(tile)
			if not _route_tiles.has(tile) and not _route_tiles.has(mirrored) and get_tile(tile) == MapData.TileType.GRASS and get_tile(mirrored) == MapData.TileType.GRASS:
				candidates.append(tile)
	var preferred: Vector2i = center + preferred_offset
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var first: int = (a - preferred).length_squared()
		var second: int = (b - preferred).length_squared()
		return first < second or (first == second and (a.y < b.y or (a.y == b.y and a.x < b.x)))
	)
	for index: int in range(mini(count, candidates.size())):
		_set_symmetric_tile(candidates[index], tile_type)
	if candidates.size() < count:
		push_error("Expansion compound lacks its promised resource fringe")


func _is_in_expansion_clearance(tile: Vector2i) -> bool:
	for center: Vector2i in get_expansion_pocket_centers():
		for symmetric_center: Vector2i in [center, _mirror_tile(center)]:
			if maxi(absi(tile.x - symmetric_center.x), absi(tile.y - symmetric_center.y)) <= EXPANSION_CLEAR_RADIUS:
				return true
	return false


func _place_center_resource_pair(tile_type: MapData.TileType, count: int, min_x_offset: int, max_x_offset: int) -> void:
	for _i in range(count):
		for _attempt in range(80):
			var center := Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2)
			var x := center.x - _rng.randi_range(min_x_offset, max_x_offset)
			var y_offset := _rng.randi_range(-7, 7)
			if absi(y_offset) <= CENTER_CLEAR_RADIUS:
				y_offset = CENTER_CLEAR_RADIUS + 1 if y_offset >= 0 else -CENTER_CLEAR_RADIUS - 1
			var y := center.y + y_offset
			if not _in_bounds(x, y):
				continue
			var mirrored: Vector2i = _mirror_tile(Vector2i(x, y))
			if not _in_bounds(mirrored.x, mirrored.y):
				continue
			if grid[y][x] != MapData.TileType.GRASS or grid[mirrored.y][mirrored.x] != MapData.TileType.GRASS:
				continue
			if _route_tiles.has(Vector2i(x, y)) or _route_tiles.has(mirrored):
				continue
			_set_symmetric_tile(Vector2i(x, y), tile_type)
			break


## Randomly swap some GRASS tiles to visual variants for map variety.
func _add_grass_variety() -> void:
	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			if x > y:
				continue
			if grid[y][x] != MapData.TileType.GRASS:
				continue
			var roll := _rng.randf()
			if roll < 0.25:
				_set_symmetric_tile(Vector2i(x, y), MapData.TileType.GRASS_ALT)
			elif roll < 0.35:
				_set_symmetric_tile(Vector2i(x, y), MapData.TileType.GRASS_DARK)


func _set_tile(x: int, y: int, tile_type: MapData.TileType) -> void:
	if _in_bounds(x, y):
		grid[y][x] = tile_type


func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < MapData.MAP_WIDTH and y >= 0 and y < MapData.MAP_HEIGHT


## Authored reference coordinates use the former 72-tile field. Scale positions,
## not stock or route width; the larger field must not inflate walking distances.
func _scaled_tile(reference: Vector2i) -> Vector2i:
	return Vector2i(roundi(reference.x * float(MapData.MAP_WIDTH - 1) / 71.0), roundi(reference.y * float(MapData.MAP_HEIGHT - 1) / 71.0))


## Reflect across the map's x=y diagonal, mapping either start to the other.
## In isometric world space this flips horizontal position and preserves
## vertical position. An x-only tile reflection does not map these spawns.
func _mirror_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(tile.y, tile.x)


func _set_symmetric_tile(tile: Vector2i, tile_type: MapData.TileType) -> void:
	_set_tile(tile.x, tile.y, tile_type)
	var mirrored: Vector2i = _mirror_tile(tile)
	_set_tile(mirrored.x, mirrored.y, tile_type)


func _is_near_spawn(tile: Vector2i, buffer: int) -> bool:
	for spawn in spawn_positions:
		if maxi(absi(tile.x - spawn.x), absi(tile.y - spawn.y)) <= buffer:
			return true
	return false


func _is_near_center(tile: Vector2i, buffer: int) -> bool:
	var center := Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2)
	return maxi(absi(tile.x - center.x), absi(tile.y - center.y)) <= buffer


func _can_place_symmetric_seed(tile: Vector2i, spawn_buffer: int, center_buffer: int) -> bool:
	if not _in_bounds(tile.x, tile.y):
		return false
	var mirrored: Vector2i = _mirror_tile(tile)
	if not _in_bounds(mirrored.x, mirrored.y):
		return false
	if grid[tile.y][tile.x] != MapData.TileType.GRASS or grid[mirrored.y][mirrored.x] != MapData.TileType.GRASS:
		return false
	if _route_tiles.has(tile) or _route_tiles.has(mirrored):
		return false
	if _is_near_spawn(tile, spawn_buffer) or _is_near_spawn(mirrored, spawn_buffer):
		return false
	if _is_in_expansion_clearance(tile) or _is_in_expansion_clearance(mirrored):
		return false
	if _is_near_center(tile, center_buffer) or _is_near_center(mirrored, center_buffer):
		return false
	return true


func _carve_grass_corridor(from_tile: Vector2i, to_tile: Vector2i, half_width: int) -> void:
	var steps := maxi(absi(to_tile.x - from_tile.x), absi(to_tile.y - from_tile.y))
	if steps <= 0:
		return
	for step in range(steps + 1):
		var t := float(step) / float(steps)
		var x := int(round(lerpf(from_tile.x, to_tile.x, t)))
		var y := int(round(lerpf(from_tile.y, to_tile.y, t)))
		for dy in range(-half_width, half_width + 1):
			for dx in range(-half_width, half_width + 1):
				var tx := x + dx
				var ty := y + dy
				if not _in_bounds(tx, ty):
					continue
				if grid[ty][tx] == MapData.TileType.SACRED_SITE:
					continue
				_set_tile(tx, ty, MapData.TileType.GRASS)
				_route_tiles[Vector2i(tx, ty)] = true


## Get the tile type at a position.
func get_tile(pos: Vector2i) -> MapData.TileType:
	if _in_bounds(pos.x, pos.y):
		return grid[pos.y][pos.x] as MapData.TileType
	return MapData.TileType.WATER  # Out-of-bounds treated as obstacle


## Validate symmetry, a viable village, and reachable objectives/resources.
## Uses the same ground-obstacle contract as pathfinding, without engine nodes.
func validate_layout() -> Dictionary:
	var errors: Array[String] = []
	var reachable: Dictionary = {}
	var frontier: Array[Vector2i] = [spawn_positions[0]]
	reachable[spawn_positions[0]] = true
	var cursor: int = 0
	while cursor < frontier.size():
		var tile: Vector2i = frontier[cursor]
		cursor += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = tile + offset
			if _in_bounds(next.x, next.y) and not reachable.has(next) and not MapData.is_obstacle(get_tile(next)):
				reachable[next] = true
				frontier.append(next)
	var resource_counts: Dictionary = {}
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			var tile := Vector2i(x, y)
			var kind: int = int(grid[y][x])
			if kind != int(grid[x][y]):
				errors.append("asymmetric terrain at %s" % tile)
			if kind in [MapData.TileType.FOREST, MapData.TileType.BERRY_BUSH, MapData.TileType.GOLD_MINE]:
				resource_counts[kind] = int(resource_counts.get(kind, 0)) + 1
				if not reachable.has(tile):
					errors.append("unreachable resource at %s" % tile)
	for spawn: Vector2i in spawn_positions:
		if not reachable.has(spawn): errors.append("disconnected start")
		for y: int in range(-2, 4):
			for x: int in range(-2, 4):
				if not MapData.is_grass(get_tile(spawn + Vector2i(x, y))): errors.append("obstructed village core")
	for center: Vector2i in get_expansion_pocket_centers():
		if not reachable.has(center) or not reachable.has(_mirror_tile(center)): errors.append("disconnected expansion")
	if not reachable.has(Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2)): errors.append("disconnected objective")
	return {"valid": errors.is_empty(), "errors": errors, "reachable_tiles": reachable.size(), "resource_tiles": resource_counts, "rotation": _opening_rotation, "lane_width": _lane_half_width * 2 + 1}


## Terrain density must not silently multiply the economy. Guaranteed timber
## groves retain useful haul sizes; remaining woodland shares a finite budget.
func _budget_natural_stock() -> void:
	_resource_amounts.clear()
	var remaining_wood: int = 16000
	var outer_wood: Array[Vector2i] = []
	var food: Array[Vector2i] = []
	var gold: Array[Vector2i] = []
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			var tile := Vector2i(x, y)
			match get_tile(tile):
				MapData.TileType.FOREST:
					var amount: int = 75 if _is_near_spawn(tile, 12) else (55 if _is_in_expansion_clearance(tile) else 0)
					if amount > 0:
						_resource_amounts[tile] = amount
						remaining_wood -= amount
					else: outer_wood.append(tile)
				MapData.TileType.BERRY_BUSH: food.append(tile)
				MapData.TileType.GOLD_MINE: gold.append(tile)
	for tile: Vector2i in outer_wood: _resource_amounts[tile] = maxi(1, floori(float(remaining_wood) / maxi(1, outer_wood.size())))
	for tile: Vector2i in food: _resource_amounts[tile] = maxi(1, floori(8000.0 / maxi(1, food.size())))
	for tile: Vector2i in gold: _resource_amounts[tile] = maxi(1, floori(6000.0 / maxi(1, gold.size())))


func get_resource_amount(tile: Vector2i) -> int:
	return int(_resource_amounts.get(tile, 0))
