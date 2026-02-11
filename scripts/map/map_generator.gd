class_name MapGenerator
extends RefCounted
## Generates a symmetric 32x32 map with resources, water, forests,
## a central sacred site, and player spawn positions.

## Emitted after map generation with the resulting tile grid.
## grid is Array[Array] of MapData.TileType values (row-major).

var _rng := RandomNumberGenerator.new()

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
	_place_water_features()
	_place_forest_clusters()
	_place_resources()
	_place_spawn_positions()
	_ensure_spawn_clearance()
	_place_guaranteed_near_spawn_resources()
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
	var num_lakes := _rng.randi_range(2, 4)
	for i in range(num_lakes):
		@warning_ignore("integer_division")
		var lx := _rng.randi_range(4, MapData.MAP_WIDTH / 2 - 3)
		var ly := _rng.randi_range(4, MapData.MAP_HEIGHT - 5)
		var lake_size := _rng.randi_range(3, 6)
		_place_blob(lx, ly, lake_size, MapData.TileType.WATER)
		# Mirror horizontally for symmetry
		var mx := MapData.MAP_WIDTH - 1 - lx
		_place_blob(mx, ly, lake_size, MapData.TileType.WATER)


## Place stealth forest clusters symmetrically.
func _place_forest_clusters() -> void:
	var num_clusters := _rng.randi_range(4, 7)
	for i in range(num_clusters):
		@warning_ignore("integer_division")
		var fx := _rng.randi_range(2, MapData.MAP_WIDTH / 2 - 2)
		var fy := _rng.randi_range(2, MapData.MAP_HEIGHT - 3)
		var cluster_size := _rng.randi_range(4, 8)
		_place_blob(fx, fy, cluster_size, MapData.TileType.FOREST)
		# Mirror
		var mx := MapData.MAP_WIDTH - 1 - fx
		_place_blob(mx, fy, cluster_size, MapData.TileType.FOREST)


## Place gold mines, berry bushes, and stone deposits symmetrically.
func _place_resources() -> void:
	# Gold mines — 3 pairs
	_place_resource_pair(MapData.TileType.GOLD_MINE, 3)
	# Berry bushes — 4 pairs
	_place_resource_pair(MapData.TileType.BERRY_BUSH, 4)
	# Stone deposits — 3 pairs
	_place_resource_pair(MapData.TileType.STONE, 3)


func _place_resource_pair(tile_type: MapData.TileType, count: int) -> void:
	for i in range(count):
		for _attempt in range(50):
			@warning_ignore("integer_division")
			var rx := _rng.randi_range(2, MapData.MAP_WIDTH / 2 - 2)
			var ry := _rng.randi_range(2, MapData.MAP_HEIGHT - 3)
			if grid[ry][rx] == MapData.TileType.GRASS:
				_set_tile(rx, ry, tile_type)
				var mx := MapData.MAP_WIDTH - 1 - rx
				_set_tile(mx, ry, tile_type)
				break


## Set player spawn positions at opposite corners.
func _place_spawn_positions() -> void:
	spawn_positions.clear()
	# Player 1 — bottom-left area
	spawn_positions.append(Vector2i(3, MapData.MAP_HEIGHT - 4))
	# Player 2 — top-right area
	spawn_positions.append(Vector2i(MapData.MAP_WIDTH - 4, 3))


## Clear an 11x11 area around each spawn so the Town Center has a visible clearing.
func _ensure_spawn_clearance() -> void:
	for spawn in spawn_positions:
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				var tx := spawn.x + dx
				var ty := spawn.y + dy
				if _in_bounds(tx, ty):
					_set_tile(tx, ty, MapData.TileType.GRASS)


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
		# 3 berry bushes just outside clearance (food access)
		_place_near_spawn(spawn, MapData.TileType.BERRY_BUSH, 3, 6, 8)
		# 2 gold mines nearby
		_place_near_spawn(spawn, MapData.TileType.GOLD_MINE, 2, 7, 10)
		# Forest cluster for easy wood
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
	for _attempt in range(30):
		var dx := _rng.randi_range(-11, 11)
		var dy := _rng.randi_range(-11, 11)
		var dist := maxi(absi(dx), absi(dy))
		if dist < 6 or dist > 11:
			continue
		var fx := spawn.x + dx
		var fy := spawn.y + dy
		if _in_bounds(fx, fy) and grid[fy][fx] == MapData.TileType.GRASS:
			_place_blob(fx, fy, 6, MapData.TileType.FOREST)
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


## Get the tile type at a position.
func get_tile(pos: Vector2i) -> MapData.TileType:
	if _in_bounds(pos.x, pos.y):
		return grid[pos.y][pos.x] as MapData.TileType
	return MapData.TileType.WATER  # Out-of-bounds treated as obstacle
