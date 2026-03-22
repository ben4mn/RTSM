class_name MapGenerator
extends RefCounted
## Generates a symmetric 40x40 duel map with readable spawn pockets,
## central contest space, and mobile-friendly lanes between bases.

## Emitted after map generation with the resulting tile grid.
## grid is Array[Array] of MapData.TileType values (row-major).

var _rng := RandomNumberGenerator.new()
const SPAWN_EDGE_PADDING := 6
const SPAWN_CLEAR_RADIUS := 6
const CENTER_CLEAR_RADIUS := 5
const FEATURE_SPAWN_BUFFER := 8
const FEATURE_CENTER_BUFFER := 6
const CORRIDOR_HALF_WIDTH := 2

## The generated tile grid — Array of rows, each row is Array of MapData.TileType.
var grid: Array = []

## Spawn positions for each player (tile coords). Index 0 = P1, 1 = P2.
var spawn_positions: Array[Vector2i] = []


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Generate a new map and return the tile grid.
func generate() -> Array:
	_init_grid()
	_place_sacred_site()
	_place_spawn_positions()
	_place_water_features()
	_place_forest_clusters()
	_place_resources()
	_ensure_spawn_clearance()
	_ensure_center_lane()
	_place_guaranteed_near_spawn_resources()
	_place_contested_mid_resources()
	_add_grass_variety()
	return grid


## Fill the entire grid with grass.
func _init_grid() -> void:
	grid.clear()
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
	var num_lakes := _rng.randi_range(2, 3)
	for i in range(num_lakes):
		var lake_size := _rng.randi_range(3, 6)
		for _attempt in range(80):
			@warning_ignore("integer_division")
			var lx := _rng.randi_range(SPAWN_EDGE_PADDING + 2, MapData.MAP_WIDTH / 2 - FEATURE_CENTER_BUFFER - 1)
			var ly := _rng.randi_range(SPAWN_EDGE_PADDING + 1, MapData.MAP_HEIGHT - SPAWN_EDGE_PADDING - 2)
			if not _can_place_symmetric_seed(Vector2i(lx, ly), FEATURE_SPAWN_BUFFER, FEATURE_CENTER_BUFFER):
				continue
			_place_blob(lx, ly, lake_size, MapData.TileType.WATER)
			_place_blob(_mirror_x(lx), ly, lake_size, MapData.TileType.WATER)
			break


## Place stealth forest clusters symmetrically.
func _place_forest_clusters() -> void:
	var num_clusters := _rng.randi_range(6, 8)
	for i in range(num_clusters):
		var cluster_size := _rng.randi_range(5, 9)
		for _attempt in range(80):
			@warning_ignore("integer_division")
			var fx := _rng.randi_range(3, MapData.MAP_WIDTH / 2 - 3)
			var fy := _rng.randi_range(3, MapData.MAP_HEIGHT - 4)
			if not _can_place_symmetric_seed(Vector2i(fx, fy), FEATURE_SPAWN_BUFFER, FEATURE_CENTER_BUFFER):
				continue
			_place_blob(fx, fy, cluster_size, MapData.TileType.FOREST)
			_place_blob(_mirror_x(fx), fy, cluster_size, MapData.TileType.FOREST)
			break


## Place gold mines, berry bushes, and stone deposits symmetrically.
func _place_resources() -> void:
	# Forward expansion resources.
	_place_resource_pair(MapData.TileType.GOLD_MINE, 4)
	_place_resource_pair(MapData.TileType.BERRY_BUSH, 5)
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
				_set_tile(rx, ry, tile_type)
				var mx := _mirror_x(rx)
				_set_tile(mx, ry, tile_type)
				break


## Set player spawn positions inward from the corners to improve mobile camera room.
func _place_spawn_positions() -> void:
	spawn_positions.clear()
	spawn_positions.append(Vector2i(SPAWN_EDGE_PADDING, MapData.MAP_HEIGHT - 1 - SPAWN_EDGE_PADDING))
	spawn_positions.append(Vector2i(MapData.MAP_WIDTH - 1 - SPAWN_EDGE_PADDING, SPAWN_EDGE_PADDING))


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


## Place an organic blob of tiles using a random walk.
func _place_blob(cx: int, cy: int, size: int, tile_type: MapData.TileType) -> void:
	var placed := 0
	var x := cx
	var y := cy
	while placed < size:
		if _in_bounds(x, y) and grid[y][x] == MapData.TileType.GRASS:
			_set_tile(x, y, tile_type)
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


## Place guaranteed resources near each spawn so players always have nearby food, gold, and wood.
## Called AFTER _ensure_spawn_clearance so resources won't be overwritten.
func _place_guaranteed_near_spawn_resources() -> void:
	for spawn in spawn_positions:
		# Fast-start economy tuned for short duel matches.
		_place_near_spawn(spawn, MapData.TileType.BERRY_BUSH, 4, SPAWN_CLEAR_RADIUS + 1, SPAWN_CLEAR_RADIUS + 3)
		_place_near_spawn(spawn, MapData.TileType.GOLD_MINE, 2, SPAWN_CLEAR_RADIUS + 2, SPAWN_CLEAR_RADIUS + 5)
		_place_near_spawn(spawn, MapData.TileType.STONE, 1, SPAWN_CLEAR_RADIUS + 3, SPAWN_CLEAR_RADIUS + 6)
		_place_forest_near_spawn(spawn)


func _place_near_spawn(spawn: Vector2i, tile_type: MapData.TileType, count: int, min_dist: int, max_dist: int) -> void:
	var placed := 0
	for _attempt in range(200):
		if placed >= count:
			break
		var dx := _rng.randi_range(-max_dist, max_dist)
		var dy := _rng.randi_range(-max_dist, max_dist)
		var dist := maxi(absi(dx), absi(dy))  # Chebyshev distance
		if dist < min_dist or dist > max_dist:
			continue
		var tx := spawn.x + dx
		var ty := spawn.y + dy
		if _in_bounds(tx, ty) and grid[ty][tx] == MapData.TileType.GRASS:
			_set_tile(tx, ty, tile_type)
			placed += 1


func _place_forest_near_spawn(spawn: Vector2i) -> void:
	var center := Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2)
	var dir_x := signi(center.x - spawn.x)
	var dir_y := signi(center.y - spawn.y)
	for _attempt in range(30):
		var dx := dir_x * _rng.randi_range(SPAWN_CLEAR_RADIUS + 1, SPAWN_CLEAR_RADIUS + 5) + _rng.randi_range(-2, 2)
		var dy := dir_y * _rng.randi_range(SPAWN_CLEAR_RADIUS + 1, SPAWN_CLEAR_RADIUS + 5) + _rng.randi_range(-2, 2)
		var dist := maxi(absi(dx), absi(dy))
		if dist < SPAWN_CLEAR_RADIUS + 1 or dist > SPAWN_CLEAR_RADIUS + 5:
			continue
		var fx := spawn.x + dx
		var fy := spawn.y + dy
		if _in_bounds(fx, fy) and grid[fy][fx] == MapData.TileType.GRASS:
			_place_blob(fx, fy, 8, MapData.TileType.FOREST)
			break


func _place_contested_mid_resources() -> void:
	_place_center_resource_pair(MapData.TileType.GOLD_MINE, 2, 4, 7)
	_place_center_resource_pair(MapData.TileType.STONE, 1, 5, 8)
	_place_center_resource_pair(MapData.TileType.BERRY_BUSH, 1, 4, 6)


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
			var mx := _mirror_x(x)
			if not _in_bounds(mx, y):
				continue
			if grid[y][x] != MapData.TileType.GRASS or grid[y][mx] != MapData.TileType.GRASS:
				continue
			_set_tile(x, y, tile_type)
			_set_tile(mx, y, tile_type)
			break


## Randomly swap some GRASS tiles to visual variants for map variety.
func _add_grass_variety() -> void:
	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			if grid[y][x] != MapData.TileType.GRASS:
				continue
			var roll := _rng.randf()
			if roll < 0.25:
				grid[y][x] = MapData.TileType.GRASS_ALT
			elif roll < 0.35:
				grid[y][x] = MapData.TileType.GRASS_DARK


func _set_tile(x: int, y: int, tile_type: MapData.TileType) -> void:
	if _in_bounds(x, y):
		grid[y][x] = tile_type


func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < MapData.MAP_WIDTH and y >= 0 and y < MapData.MAP_HEIGHT


func _mirror_x(x: int) -> int:
	return MapData.MAP_WIDTH - 1 - x


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
	var mirrored := Vector2i(_mirror_x(tile.x), tile.y)
	if not _in_bounds(mirrored.x, mirrored.y):
		return false
	if grid[tile.y][tile.x] != MapData.TileType.GRASS or grid[mirrored.y][mirrored.x] != MapData.TileType.GRASS:
		return false
	if _is_near_spawn(tile, spawn_buffer) or _is_near_spawn(mirrored, spawn_buffer):
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


## Get the tile type at a position.
func get_tile(pos: Vector2i) -> MapData.TileType:
	if _in_bounds(pos.x, pos.y):
		return grid[pos.y][pos.x] as MapData.TileType
	return MapData.TileType.WATER  # Out-of-bounds treated as obstacle
