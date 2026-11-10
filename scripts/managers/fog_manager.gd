class_name FogManager
extends Node2D
## Manages fog of war with three states: unexplored, explored (dimmed), visible.
## Uses delta-based updates — only cells whose sight changed are touched.

## The fog grid — Array[Array] of MapData.FogState (row-major).
var fog_grid: Array = []
## Changes whenever the canonical visible grid changes, independent of frames.
var visibility_revision: int = 0

## Optional diagnostic TileMapLayer mirror. The match renders fog from
## fog_image through FogVeil instead, so GameMap leaves this unset.
var fog_layer: TileMapLayer

## Which player this fog belongs to (0 = Player 1, 1 = Player 2).
@export var owning_player: int = 0

## Tiles currently in sight. Kept for save data and diagnostics; it is derived
## on demand from the canonical grid so the per-frame update never rebuilds it.
var _previously_visible: Array[Vector2i]:
	get:
		var cells: Array[Vector2i] = []
		for y: int in fog_grid.size():
			var row: Array = fog_grid[y]
			for x: int in row.size():
				if row[x] == MapData.FogState.VISIBLE:
					cells.append(Vector2i(x, y))
		return cells
	set(_value):
		_visibility_cache_valid = false
var _last_visibility_sources: Dictionary = {}
var _visibility_cache_valid: bool = false
## How many live sources see each cell (row-major). Only sources that moved,
## appeared or left touch it, so a hundred standing units cost nothing.
var _sight_counts: PackedInt32Array = PackedInt32Array()
var _touched_stamp: PackedInt32Array = PackedInt32Array()
var _touched_cells: PackedInt32Array = PackedInt32Array()
var _touch_generation: int = 0
var _circle_offsets: Dictionary = {}

## Presentation copy of the grid for the soft fog veil and other shaders:
## red = in sight, green = explored. Updated per changed cell.
var fog_image: Image = null
var fog_image_revision: int = 0

## Cache of registered units for vision computation.
## Each entry: { "position": Vector2i, "vision_radius": int, "is_scout": bool }
var _vision_sources: Array[Dictionary] = []

## Cells whose fog state changed this frame (need layer update).
var _dirty_cells: Array[Vector2i] = []

## Fog overlay atlas coordinates for each state.
const FOG_UNEXPLORED_ATLAS := Vector2i(0, 0)
const FOG_EXPLORED_ATLAS := Vector2i(1, 0)
# VISIBLE = no fog tile (cell cleared).
const _IMAGE_UNEXPLORED := Color(0.0, 0.0, 0.0)
const _IMAGE_EXPLORED := Color(0.0, 1.0, 0.0)
const _IMAGE_VISIBLE := Color(1.0, 1.0, 0.0)

## Whether initial full-apply has happened.
var _initial_apply_done: bool = false


func _ready() -> void:
	_init_fog_grid()


func _init_fog_grid() -> void:
	visibility_revision += 1
	fog_grid.clear()
	_visibility_cache_valid = false
	_initial_apply_done = false
	_last_visibility_sources = {}
	var cell_count: int = MapData.MAP_WIDTH * MapData.MAP_HEIGHT
	_sight_counts.resize(cell_count)
	_sight_counts.fill(0)
	_touched_stamp.resize(cell_count)
	_touched_stamp.fill(0)
	_touched_cells.clear()
	_touch_generation = 0
	for y in range(MapData.MAP_HEIGHT):
		var row: Array = []
		row.resize(MapData.MAP_WIDTH)
		row.fill(MapData.FogState.UNEXPLORED)
		fog_grid.append(row)
	fog_image = Image.create(MapData.MAP_WIDTH, MapData.MAP_HEIGHT, false, Image.FORMAT_RGB8)
	fog_image.fill(_IMAGE_UNEXPLORED)
	fog_image_revision += 1


func _process(_delta: float) -> void:
	refresh_visibility_now()


## Recompute and render current visibility immediately. Match setup uses this
## once after spawning starting vision sources so initial fog-aware assignments
## never need an omniscient first-frame fallback.
func refresh_visibility_now() -> void:
	var _pp: int = Time.get_ticks_usec() if PerfProbe.on else 0
	_dirty_cells.clear()
	_update_visibility()
	_apply_fog_delta()
	if PerfProbe.on: PerfProbe.add(&"fog.refresh", _pp)


## Register a vision source (unit). Call this when a unit spawns or moves.
func register_vision_source(tile_pos: Vector2i, vision_radius: int, is_scout: bool) -> void:
	_vision_sources.append({
		"position": tile_pos,
		"vision_radius": vision_radius,
		"is_scout": is_scout,
	})


## Clear all vision sources — call at start of each frame before re-registering.
func clear_vision_sources() -> void:
	_vision_sources.clear()


## Bulk-set vision sources for the frame (more efficient than individual register calls).
func set_vision_sources(sources: Array[Dictionary]) -> void:
	_vision_sources = sources


## Core visibility update — runs each frame.
func _update_visibility() -> void:
	_dirty_cells.clear()
	# Tile vision changes only when a source crosses a tile, changes radius or
	# enters/leaves the world. Scout identity is queried from live sources below.
	# Deduplicate overlapping sources without relying on registration order.
	var signature: Dictionary = {}
	for source in _vision_sources:
		var origin: Vector2i = source["position"]
		var radius: int = source["vision_radius"]
		signature[Vector3i(origin.x, origin.y, radius)] = true
	if _visibility_cache_valid and signature == _last_visibility_sources:
		return
	# Only circles that appeared or left are walked; a large standing army and
	# town cost nothing when one scout crosses a tile.
	_touch_generation += 1
	_touched_cells.clear()
	for key: Vector3i in _last_visibility_sources:
		if not signature.has(key):
			_count_circle(key, -1)
	for key: Vector3i in signature:
		if not _last_visibility_sources.has(key):
			_count_circle(key, 1)
	_last_visibility_sources = signature

	# Compare final states. Persistent visible cells never flicker through
	# EXPLORED and never incur redundant updates.
	var width: int = MapData.MAP_WIDTH
	if not _visibility_cache_valid:
		# A restore, reset or diagnostic override: reconcile the whole grid once.
		_visibility_cache_valid = true
		for y: int in MapData.MAP_HEIGHT:
			var row: Array = fog_grid[y]
			for x: int in width:
				_settle_cell(row, x, y, _sight_counts[y * width + x] > 0)
	else:
		for index: int in _touched_cells:
			@warning_ignore("integer_division")
			var y: int = index / width
			_settle_cell(fog_grid[y], index - y * width, y, _sight_counts[index] > 0)
	if not _dirty_cells.is_empty():
		visibility_revision += 1


func _settle_cell(row: Array, x: int, y: int, in_sight: bool) -> void:
	if in_sight:
		if row[x] != MapData.FogState.VISIBLE:
			row[x] = MapData.FogState.VISIBLE
			_dirty_cells.append(Vector2i(x, y))
	elif row[x] == MapData.FogState.VISIBLE:
		row[x] = MapData.FogState.EXPLORED
		_dirty_cells.append(Vector2i(x, y))


## Add or remove one circle of sight from the per-cell counts.
func _count_circle(source: Vector3i, change: int) -> void:
	var offsets: PackedInt32Array = _get_circle_offsets(source.z)
	var width: int = MapData.MAP_WIDTH
	var height: int = MapData.MAP_HEIGHT
	var generation: int = _touch_generation
	for i: int in range(0, offsets.size(), 2):
		var x: int = source.x + offsets[i]
		var y: int = source.y + offsets[i + 1]
		if x < 0 or y < 0 or x >= width or y >= height:
			continue
		var index: int = y * width + x
		_sight_counts[index] += change
		if _touched_stamp[index] != generation:
			_touched_stamp[index] = generation
			_touched_cells.append(index)


func _get_circle_offsets(radius: int) -> PackedInt32Array:
	if _circle_offsets.has(radius):
		return _circle_offsets[radius]
	var offsets := PackedInt32Array()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				offsets.append(dx)
				offsets.append(dy)
	_circle_offsets[radius] = offsets
	return offsets


## Apply only changed fog cells to the presentation image (and to the optional
## diagnostic TileMapLayer when a fixture supplies one).
func _apply_fog_delta() -> void:
	# First frame: apply all cells to initialise the presentation.
	if not _initial_apply_done:
		_initial_apply_done = true
		for y in range(MapData.MAP_HEIGHT):
			for x in range(MapData.MAP_WIDTH):
				_apply_cell(Vector2i(x, y), fog_grid[y][x] as MapData.FogState)
		return

	# Delta: only update cells that changed.
	for pos in _dirty_cells:
		_apply_cell(pos, fog_grid[pos.y][pos.x] as MapData.FogState)


## Apply a single cell's fog state to the presentation targets.
func _apply_cell(pos: Vector2i, state: MapData.FogState) -> void:
	fog_image_revision += 1
	match state:
		MapData.FogState.UNEXPLORED:
			fog_image.set_pixelv(pos, _IMAGE_UNEXPLORED)
			if fog_layer != null: fog_layer.set_cell(pos, 0, FOG_UNEXPLORED_ATLAS)
		MapData.FogState.EXPLORED:
			fog_image.set_pixelv(pos, _IMAGE_EXPLORED)
			if fog_layer != null: fog_layer.set_cell(pos, 0, FOG_EXPLORED_ATLAS)
		MapData.FogState.VISIBLE:
			fog_image.set_pixelv(pos, _IMAGE_VISIBLE)
			if fog_layer != null: fog_layer.erase_cell(pos)


## Check if a tile is currently visible to this player.
func is_tile_visible(pos: Vector2i) -> bool:
	if not _in_bounds(pos):
		return false
	return fog_grid[pos.y][pos.x] == MapData.FogState.VISIBLE


## Check if a tile has ever been explored.
func is_explored(pos: Vector2i) -> bool:
	if not _in_bounds(pos):
		return false
	return fog_grid[pos.y][pos.x] != MapData.FogState.UNEXPLORED


## Check if any scout can see a specific stealth tile.
func is_revealed_by_scout(pos: Vector2i) -> bool:
	for source in _vision_sources:
		if source["is_scout"]:
			var origin: Vector2i = source["position"]
			var radius: int = source["vision_radius"]
			var diff := pos - origin
			if diff.x * diff.x + diff.y * diff.y <= radius * radius:
				return true
	return false


## Preserve an authoritative past sighting when intermediate network snapshots
## were skipped. This grants explored memory only, never current vision.
func remember_explored(pos: Vector2i) -> void:
	if not _in_bounds(pos) or fog_grid[pos.y][pos.x] != MapData.FogState.UNEXPLORED: return
	fog_grid[pos.y][pos.x] = MapData.FogState.EXPLORED
	visibility_revision += 1
	_apply_cell(pos, MapData.FogState.EXPLORED)


## Reveal the entire map (cheat / debug).
func reveal_all() -> void:
	visibility_revision += 1
	_visibility_cache_valid = false
	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			fog_grid[y][x] = MapData.FogState.VISIBLE
	# Capture fixtures read the veil without waiting for another refresh.
	fog_image.fill(_IMAGE_VISIBLE)
	fog_image_revision += 1


## Diagnostic overrides must invalidate readers just like normal fog updates.
func set_debug_tile_state(pos: Vector2i, state: MapData.FogState) -> void:
	if not _in_bounds(pos) or fog_grid[pos.y][pos.x] == state:
		return
	fog_grid[pos.y][pos.x] = state
	_visibility_cache_valid = false
	visibility_revision += 1
	_dirty_cells.append(pos)


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < MapData.MAP_WIDTH and pos.y >= 0 and pos.y < MapData.MAP_HEIGHT
