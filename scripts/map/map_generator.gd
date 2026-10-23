class_name MapGenerator
extends RefCounted
## Generates a symmetric duel map with readable spawn pockets,
## central contest space, and mobile-friendly lanes between bases.

## Emitted after map generation with the resulting tile grid.
## grid is Array[Array] of MapData.TileType values (row-major).

var _rng := RandomNumberGenerator.new()
const SPAWN_EDGE_PADDING := 6
const SPAWN_CLEAR_RADIUS := 6
const CENTER_CLEAR_RADIUS := 7
const FEATURE_SPAWN_BUFFER := 8
const FEATURE_CENTER_BUFFER := 8
const CORRIDOR_HALF_WIDTH := 3

## The generated tile grid — Array of rows, each row is Array of MapData.TileType.
var grid: Array = []

## Spawn positions for each player (tile coords). Index 0 = P1, 1 = P2.
var spawn_positions: Array[Vector2i] = []
var archetype: int = MapData.MapArchetype.OPEN_PLAINS
var _flank_crossings: Array[Vector2i] = [Vector2i(20, 20), Vector2i(52, 52)]


func _init(seed_value: int = -1, map_archetype: int = MapData.MapArchetype.OPEN_PLAINS) -> void:
	archetype = MapData.normalize_archetype(map_archetype)
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
	_place_archetype_features()
	# Keep established Open Plains seeds intact. On the terrain-heavy maps,
	# finish carving routes before scattering finite expansion resources so
	# a river crossing cannot silently erase most of a seed's food deposits.
	if archetype == MapData.MapArchetype.OPEN_PLAINS:
		_place_resources()
	_ensure_spawn_clearance()
	_ensure_center_lane()
	_ensure_tactical_lanes()
	if archetype != MapData.MapArchetype.OPEN_PLAINS:
		_place_resources()
	_place_guaranteed_near_spawn_resources()
	_place_contested_mid_resources()
	_place_expansion_resources()
	_add_grass_variety()
	return grid


## The default performs no additional random draws or edits, preserving existing
## seeded maps. New layouts retain the same reflected starts and opening stock.
func _place_archetype_features() -> void:
	if archetype == MapData.MapArchetype.OPEN_PLAINS:
		return
	var upper: int = _rng.randi_range(18, 21)
	var lower: int = _rng.randi_range(50, 53)
	_flank_crossings = [Vector2i(upper, upper), Vector2i(lower, lower)]
	if archetype == MapData.MapArchetype.RIVER_CROSSINGS:
		_place_crossing_river()
	else:
		_place_flanking_woodlands()


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
	var centers: Array[Vector2i] = [Vector2i(15, 39), Vector2i(31, 56), Vector2i(24, 44)]
	for base: Vector2i in centers:
		var center: Vector2i = base + Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-2, 2))
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
	if archetype == MapData.MapArchetype.OPEN_PLAINS:
		return
	for route: Dictionary in get_tactical_routes():
		var points: Array = route["waypoints"]
		for index: int in range(1, points.size()):
			var from_tile: Vector2i = points[index - 1]
			var to_tile: Vector2i = points[index]
			_carve_grass_corridor(from_tile, to_tile, CORRIDOR_HALF_WIDTH)
			# Explicit reflection also handles round-to-nearest ties at bends.
			_carve_grass_corridor(_mirror_tile(from_tile), _mirror_tile(to_tile), CORRIDOR_HALF_WIDTH)


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


## Place guaranteed resources near each spawn so players always have nearby food, gold, and wood.
## Called AFTER _ensure_spawn_clearance so resources won't be overwritten.
func _place_guaranteed_near_spawn_resources() -> void:
	# Draw one opening pocket and reflect it to the other spawn. The reflection
	# preserves isometric world distances and the anchored 4x4 TC footprint.
	var spawn: Vector2i = spawn_positions[0]
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
		if not _is_in_starting_resource_reveal(spawn, Vector2i(tx, ty)):
			continue
		if _is_near_center(Vector2i(tx, ty), CENTER_CLEAR_RADIUS):
			continue
		if _in_bounds(tx, ty) and grid[ty][tx] == MapData.TileType.GRASS:
			_set_symmetric_tile(Vector2i(tx, ty), tile_type)
			placed += 1
	# Random draws provide variety, but a crowded seed must still receive its
	# promised opening stock after the finite attempt budget is exhausted.
	for dy: int in range(-max_dist, max_dist + 1):
		for dx: int in range(-max_dist, max_dist + 1):
			if placed >= count:
				return
			var distance: int = maxi(absi(dx), absi(dy))
			var tile: Vector2i = spawn + Vector2i(dx, dy)
			if distance < min_dist or not _in_bounds(tile.x, tile.y):
				continue
			if not _is_in_starting_resource_reveal(spawn, tile) or _is_near_center(tile, CENTER_CLEAR_RADIUS):
				continue
			var mirrored: Vector2i = _mirror_tile(tile)
			if grid[tile.y][tile.x] == MapData.TileType.GRASS and grid[mirrored.y][mirrored.x] == MapData.TileType.GRASS:
				_set_symmetric_tile(tile, tile_type)
				placed += 1


func _place_forest_near_spawn(spawn: Vector2i) -> void:
	var candidates: Array[Vector2i] = []
	var forward_candidates: Array[Vector2i] = []
	var radius: int = SPAWN_CLEAR_RADIUS + 5
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var tile: Vector2i = spawn + Vector2i(dx, dy)
			if not _can_place_starting_tree(spawn, tile):
				continue
			candidates.append(tile)
			if dx > 0 and dy < 0:
				forward_candidates.append(tile)
	if candidates.is_empty():
		return
	# Grow a connected patch inside the real circular starting reveal. The old
	# random walk could move every tree out of vision, idling the wood worker.
	var starts: Array[Vector2i] = forward_candidates if not forward_candidates.is_empty() else candidates
	var frontier: Array[Vector2i] = [starts[_rng.randi_range(0, starts.size() - 1)]]
	var visited: Dictionary = {}
	var placed: int = 0
	while placed < 8:
		if frontier.is_empty():
			# A crowded patch may be enclosed by pre-existing resources. Continue
			# from another legal pocket tile rather than losing guaranteed stock.
			while not candidates.is_empty():
				var next: Vector2i = candidates.pop_back()
				if _can_place_starting_tree(spawn, next):
					frontier.append(next)
					break
			if frontier.is_empty():
				break
		var index: int = _rng.randi_range(0, frontier.size() - 1)
		var tile: Vector2i = frontier[index]
		frontier.remove_at(index)
		if visited.has(tile) or not _can_place_starting_tree(spawn, tile):
			continue
		visited[tile] = true
		_set_symmetric_tile(tile, MapData.TileType.FOREST)
		placed += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var adjacent: Vector2i = tile + offset
			if not visited.has(adjacent) and _can_place_starting_tree(spawn, adjacent):
				frontier.append(adjacent)


func _can_place_starting_tree(spawn: Vector2i, tile: Vector2i) -> bool:
	if not _in_bounds(tile.x, tile.y):
		return false
	var distance: int = maxi(absi(tile.x - spawn.x), absi(tile.y - spawn.y))
	if distance <= SPAWN_CLEAR_RADIUS or distance > SPAWN_CLEAR_RADIUS + 5:
		return false
	if not _is_in_starting_resource_reveal(spawn, tile) or _is_near_center(tile, CENTER_CLEAR_RADIUS):
		return false
	var mirrored: Vector2i = _mirror_tile(tile)
	return grid[tile.y][tile.x] == MapData.TileType.GRASS and grid[mirrored.y][mirrored.x] == MapData.TileType.GRASS


func _is_in_starting_resource_reveal(spawn: Vector2i, tile: Vector2i) -> bool:
	# Read the authoritative building vision instead of assuming a Chebyshev
	# ring fits a circular reveal. AI and human commands share this same circle.
	var stats: Dictionary = BuildingData.get_building_stats(BuildingData.BuildingType.TOWN_CENTER)
	var vision: int = int(stats.get("vision_radius", 3))
	return spawn.distance_squared_to(tile) <= float(vision * vision)


func _place_contested_mid_resources() -> void:
	_place_center_resource_pair(MapData.TileType.GOLD_MINE, 2, 4, 7)
	_place_center_resource_pair(MapData.TileType.STONE, 1, 5, 8)
	_place_center_resource_pair(MapData.TileType.BERRY_BUSH, 1, 4, 6)


## Two finite expansion pockets flank each approach. They sit beyond starting
## vision and outside the direct center lane: scouting and a paid drop-off make
## them useful without replacing the protected opening with a larger free bank.
func get_expansion_pocket_centers() -> Array[Vector2i]:
	var spawn: Vector2i = spawn_positions[0]
	return [spawn + Vector2i(8, -22), spawn + Vector2i(22, -8)]


func _place_expansion_resources() -> void:
	var pocket: Dictionary = {
		Vector2i(-1, 0): MapData.TileType.BERRY_BUSH,
		Vector2i(1, 0): MapData.TileType.BERRY_BUSH,
		Vector2i(0, -1): MapData.TileType.GOLD_MINE,
		Vector2i(-2, 2): MapData.TileType.FOREST,
		Vector2i(-1, 2): MapData.TileType.FOREST,
		Vector2i(0, 2): MapData.TileType.FOREST,
		Vector2i(1, 2): MapData.TileType.FOREST,
	}
	for center: Vector2i in get_expansion_pocket_centers():
		# Clear the stock and immediate work perimeter out of any random lake.
		# Seeded route checks also verify approaches through the surrounding map.
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				_set_symmetric_tile(center + Vector2i(dx, dy), MapData.TileType.GRASS)
		for offset: Vector2i in pocket:
			_set_symmetric_tile(center + offset, pocket[offset])


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
