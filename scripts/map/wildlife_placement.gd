class_name WildlifePlacement
extends RefCounted
## Decides where the opening wildlife stands. This is a separate pass over a
## finished battlefield: it reads the generated grid and never advances the
## generator's own random stream, so terrain and deposits for a seed are the
## same with or without animals. Player 1 receives the exact reflection of
## player 0's layout across the map diagonal, like every other start feature.
##
## Each row: {"kind": String, "tile": Vector2i, "owner": int (-1 neutral),
## "group": String ("home", "stray_a", "stray_b", "deer", "boar"), "side": int}.

const EDGE_MARGIN: int = 3
const TOWN_CENTER_SIZE: int = 4


static func plan(generator: MapGenerator, seed_value: int = -1) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if generator == null or generator.spawn_positions.size() < 2 or generator.grid.is_empty():
		return rows
	var rng := RandomNumberGenerator.new()
	var base_seed: int = seed_value if seed_value >= 0 else int(generator._rng.seed)
	# Integer mixing only: identical on every platform and engine build.
	rng.seed = ((base_seed * 2654435761) ^ 0x5bd1e995 ^ (generator.archetype * 40503)) & 0x7fffffffffff
	var spawn: Vector2i = generator.spawn_positions[0]
	var reachable: Dictionary = generator._find_connected_tiles()
	var taken: Dictionary = {}
	# Toward the map centre; the two flanks are measured from this heading.
	var forward: float = Vector2(1.0, -1.0).angle() if spawn.x <= spawn.y else Vector2(-1.0, 1.0).angle()
	var side: float = 1.0 if rng.randi_range(0, 1) == 0 else -1.0

	var half: float = (TOWN_CENTER_SIZE - 1) * 0.5
	var town_center := Vector2(spawn) + Vector2(half, half)
	var home_heading: float = rng.randf_range(-PI, PI)
	var home_center: Vector2 = town_center + Vector2.from_angle(home_heading) * (half + WildlifeData.HOME_RING_MAX)
	var home_tiles: Array[Vector2i] = _choose(generator, reachable, taken, spawn, home_center, WildlifeData.HOME_SHEEP, 1.0, 1,
		func(tile: Vector2i) -> bool:
			var ring: int = _ring_from_town_center(tile, spawn)
			return ring >= WildlifeData.HOME_RING_MIN and ring <= WildlifeData.HOME_RING_MAX,
		1.5, base_seed)
	for tile: Vector2i in home_tiles:
		rows.append({"kind": WildlifeData.SHEEP, "tile": tile, "owner": 0, "group": "home"})

	var deer_heading: float = forward + deg_to_rad(rng.randf_range(-22.0, 22.0))
	var deer_tiles: Array[Vector2i] = _choose_band(generator, reachable, taken, spawn, deer_heading, WildlifeData.DEER_DISTANCE, WildlifeData.DEER_COUNT, 1.4, 2, 2.5, base_seed + 1)
	for tile: Vector2i in deer_tiles:
		rows.append({"kind": WildlifeData.DEER, "tile": tile, "owner": -1, "group": "deer"})

	for index: int in WildlifeData.BOAR_COUNT:
		var flank: float = side if index == 0 else -side
		var heading: float = forward + flank * deg_to_rad(rng.randf_range(34.0, 62.0))
		var tiles: Array[Vector2i] = _choose_band(generator, reachable, taken, spawn, heading, WildlifeData.BOAR_DISTANCE, 1, 1.0, 3, 0.01, base_seed + 2)
		for tile: Vector2i in tiles:
			rows.append({"kind": WildlifeData.BOAR, "tile": tile, "owner": -1, "group": "boar"})

	for index: int in WildlifeData.STRAY_PAIRS:
		var flank: float = -side if index == 0 else side
		var heading: float = forward + flank * deg_to_rad(rng.randf_range(38.0, 72.0))
		var tiles: Array[Vector2i] = _choose_band(generator, reachable, taken, spawn, heading, WildlifeData.STRAY_DISTANCE, 2, 1.0, 3, 0.01, base_seed + 3)
		for tile: Vector2i in tiles:
			rows.append({"kind": WildlifeData.SHEEP, "tile": tile, "owner": -1, "group": "stray_a" if index == 0 else "stray_b"})

	# The second player's animals are the reflection of the first player's.
	var mirrored: Array[Dictionary] = []
	for row: Dictionary in rows:
		row["side"] = 0
		var twin: Dictionary = row.duplicate()
		twin["tile"] = Vector2i(row.tile.y, row.tile.x)
		twin["owner"] = 1 if int(row.owner) == 0 else -1
		twin["side"] = 1
		mirrored.append(twin)
	rows.append_array(mirrored)
	return rows


## Tiles in a distance band from the start, nearest to a point on `heading`.
static func _choose_band(generator: MapGenerator, reachable: Dictionary, taken: Dictionary, spawn: Vector2i, heading: float, band: Vector2, count: int, spacing: float, clearance: int, scatter: float = 0.0, scatter_seed: int = 0) -> Array[Vector2i]:
	var center: Vector2 = Vector2(spawn) + Vector2.from_angle(heading) * ((band.x + band.y) * 0.5)
	return _choose(generator, reachable, taken, spawn, center, count, spacing, clearance,
		func(tile: Vector2i) -> bool:
			var distance: float = Vector2(tile - spawn).length()
			return distance >= band.x and distance <= band.y,
		scatter, scatter_seed)


static func _choose(generator: MapGenerator, reachable: Dictionary, taken: Dictionary, spawn: Vector2i, center: Vector2, count: int, spacing: float, clearance: int, accept: Callable, scatter: float = 0.0, scatter_seed: int = 0) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y: int in range(EDGE_MARGIN, MapData.MAP_HEIGHT - EDGE_MARGIN):
		for x: int in range(EDGE_MARGIN, MapData.MAP_WIDTH - EDGE_MARGIN):
			var tile := Vector2i(x, y)
			# The reflection must land on a different tile on the same side of
			# the diagonal as this start, so the two layouts can never overlap.
			if (x <= y) != (spawn.x <= spawn.y) or x == y:
				continue
			if not accept.call(tile) or not _is_open(generator, reachable, tile):
				continue
			if _near_taken(taken, tile, clearance):
				continue
			# Animals graze in the open, not pressed against a mine or grove.
			if scatter > 0.0 and not _has_open_neighbours(generator, tile):
				continue
			candidates.append(tile)
	# `scatter` loosens a herd: a per-tile hash nudges the ordering so the
	# chosen tiles form an irregular group instead of a neat diamond.
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var first: float = (Vector2(a) - center).length_squared() + _tile_noise(a, scatter_seed) * scatter
		var second: float = (Vector2(b) - center).length_squared() + _tile_noise(b, scatter_seed) * scatter
		return first < second if not is_equal_approx(first, second) else (a.y < b.y or (a.y == b.y and a.x < b.x)))
	var chosen: Array[Vector2i] = []
	for tile: Vector2i in candidates:
		if chosen.size() >= count:
			break
		var clear: bool = true
		for other: Vector2i in chosen:
			if Vector2(tile - other).length() < spacing:
				clear = false
				break
		if clear:
			chosen.append(tile)
	for tile: Vector2i in chosen:
		taken[tile] = true
	return chosen


static func _is_open(generator: MapGenerator, reachable: Dictionary, tile: Vector2i) -> bool:
	if not reachable.has(tile) or not MapData.is_grass(generator.get_tile(tile)):
		return false
	return _ring_from_town_center(tile, generator.spawn_positions[0]) >= 1 and _ring_from_town_center(tile, generator.spawn_positions[1]) >= 1


static func _has_open_neighbours(generator: MapGenerator, tile: Vector2i) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if not MapData.is_grass(generator.get_tile(tile + Vector2i(dx, dy))):
				return false
	return true


## Stable 0..1 value for a tile; integer mixing only.
static func _tile_noise(tile: Vector2i, salt: int) -> float:
	var mixed: int = ((tile.x * 73856093) ^ (tile.y * 19349663) ^ (salt * 83492791)) & 0x7fffffff
	mixed = ((mixed >> 13) ^ mixed) * 1274126177 & 0x7fffffff
	return float(mixed & 0xffff) / 65535.0


## Where an animal stands inside its tile and which way it faces, so a herd
## does not look stamped onto the grid. `side` 1 is the reflection of side 0
## (the map mirror flips world x), so both players see the same picture.
static func presentation(row: Dictionary, salt: int) -> Dictionary:
	var tile: Vector2i = row.tile
	var base: Vector2i = tile if int(row.get("side", 0)) == 0 else Vector2i(tile.y, tile.x)
	var offset := Vector2((_tile_noise(base, salt) - 0.5) * 18.0, (_tile_noise(base, salt + 7) - 0.5) * 8.0)
	var facing_left: bool = _tile_noise(base, salt + 13) < 0.5
	if int(row.get("side", 0)) == 1:
		offset.x = -offset.x
		facing_left = not facing_left
	return {"offset": offset, "facing_left": facing_left}


static func _near_taken(taken: Dictionary, tile: Vector2i, clearance: int) -> bool:
	for dy: int in range(-clearance, clearance + 1):
		for dx: int in range(-clearance, clearance + 1):
			if taken.has(tile + Vector2i(dx, dy)):
				return true
	return false


## Chebyshev distance from the Town Center's 4x4 footprint (0 = inside it).
static func _ring_from_town_center(tile: Vector2i, spawn: Vector2i) -> int:
	var dx: int = maxi(maxi(spawn.x - tile.x, tile.x - (spawn.x + TOWN_CENTER_SIZE - 1)), 0)
	var dy: int = maxi(maxi(spawn.y - tile.y, tile.y - (spawn.y + TOWN_CENTER_SIZE - 1)), 0)
	return maxi(dx, dy)


## Audit used by the fairness probe and regression: one entry per problem.
static func audit(generator: MapGenerator, rows: Array[Dictionary]) -> Array[String]:
	var problems: Array[String] = []
	var reachable: Dictionary = generator._find_connected_tiles()
	var by_tile: Dictionary = {}
	var counts: Array[Dictionary] = [{}, {}]
	for row: Dictionary in rows:
		var tile: Vector2i = row.tile
		if by_tile.has(tile):
			problems.append("two animals on %s" % tile)
		by_tile[tile] = row
		if not _is_open(generator, reachable, tile):
			problems.append("%s at %s is not on open reachable grass" % [row.kind, tile])
		var side: int = int(row.side)
		counts[side][row.group] = int(counts[side].get(row.group, 0)) + 1
		var spawn: Vector2i = generator.spawn_positions[side]
		var rival: Vector2i = generator.spawn_positions[1 - side]
		var distance: float = Vector2(tile - spawn).length()
		if Vector2(tile - rival).length() <= distance:
			problems.append("%s at %s is nearer the other start" % [row.kind, tile])
		match str(row.group):
			"home":
				var ring: int = _ring_from_town_center(tile, spawn)
				if ring < WildlifeData.HOME_RING_MIN or ring > WildlifeData.HOME_RING_MAX or int(row.owner) != side:
					problems.append("home sheep at %s is outside the pasture ring" % tile)
			"deer":
				if distance < WildlifeData.DEER_DISTANCE.x or distance > WildlifeData.DEER_DISTANCE.y:
					problems.append("deer at %s is %.1f tiles from its start" % [tile, distance])
			"boar":
				if distance < WildlifeData.BOAR_DISTANCE.x or distance > WildlifeData.BOAR_DISTANCE.y:
					problems.append("boar at %s is %.1f tiles from its start" % [tile, distance])
			_:
				if distance < WildlifeData.STRAY_DISTANCE.x or distance > WildlifeData.STRAY_DISTANCE.y or int(row.owner) != -1:
					problems.append("stray sheep at %s is %.1f tiles from its start" % [tile, distance])
	for row: Dictionary in rows:
		var twin: Vector2i = Vector2i(row.tile.y, row.tile.x)
		if not by_tile.has(twin) or by_tile[twin].kind != row.kind or by_tile[twin].group != row.group or int(by_tile[twin].side) == int(row.side):
			problems.append("%s at %s has no reflected twin" % [row.kind, row.tile])
	var expected: Dictionary = {"home": WildlifeData.HOME_SHEEP, "stray_a": 2, "stray_b": 2, "deer": WildlifeData.DEER_COUNT, "boar": WildlifeData.BOAR_COUNT}
	for side: int in 2:
		for group: String in expected:
			if int(counts[side].get(group, 0)) != int(expected[group]):
				problems.append("player %d has %d %s, expected %d" % [side, int(counts[side].get(group, 0)), group, int(expected[group])])
	return problems
