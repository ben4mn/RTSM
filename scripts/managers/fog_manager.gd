class_name FogManager
extends Node2D
## Manages fog of war with three states: unexplored, explored (dimmed), visible.
## Uses delta-based updates — only changed cells are pushed to the TileMapLayer.

## The fog grid — Array[Array] of MapData.FogState (row-major).
var fog_grid: Array = []
## Changes whenever the canonical visible grid changes, independent of frames.
var visibility_revision: int = 0

## Reference to the fog overlay TileMapLayer (set by GameMap).
var fog_layer: TileMapLayer

## Which player this fog belongs to (0 = Player 1, 1 = Player 2).
@export var owning_player: int = 0

## Tracks tiles that were visible last frame so we can transition to EXPLORED.
var _previously_visible: Array[Vector2i] = []
var _next_visible: Dictionary = {}
var _last_visibility_sources: Dictionary = {}
var _visibility_cache_valid: bool = false

## Cache of registered units for vision computation.
## Each entry: { "position": Vector2i, "vision_radius": int, "is_scout": bool }
var _vision_sources: Array[Dictionary] = []

## Cells whose fog state changed this frame (need layer update).
var _dirty_cells: Array[Vector2i] = []

## Fog overlay atlas coordinates for each state.
const FOG_UNEXPLORED_ATLAS := Vector2i(0, 0)
const FOG_EXPLORED_ATLAS := Vector2i(1, 0)
# VISIBLE = no fog tile (cell cleared).

## Whether initial full-apply has happened.
var _initial_apply_done: bool = false


func _ready() -> void:
	_init_fog_grid()


func _init_fog_grid() -> void:
	visibility_revision += 1
	fog_grid.clear()
	_previously_visible.clear()
	_visibility_cache_valid = false
	_initial_apply_done = false
	for y in range(MapData.MAP_HEIGHT):
		var row: Array = []
		row.resize(MapData.MAP_WIDTH)
		row.fill(MapData.FogState.UNEXPLORED)
		fog_grid.append(row)


func _process(_delta: float) -> void:
	refresh_visibility_now()


## Recompute and render current visibility immediately. Match setup uses this
## once after spawning starting vision sources so initial fog-aware assignments
## never need an omniscient first-frame fallback.
func refresh_visibility_now() -> void:
	_dirty_cells.clear()
	_update_visibility()
	_apply_fog_delta()


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
	_last_visibility_sources = signature
	_visibility_cache_valid = true
	_next_visible.clear()
	for key: Vector3i in signature:
		_reveal_circle(Vector2i(key.x, key.y), key.z)

	# Compare final states. Persistent visible cells never flicker through
	# EXPLORED and never incur redundant TileMap updates.
	for pos: Vector2i in _previously_visible:
		if not _next_visible.has(pos):
			fog_grid[pos.y][pos.x] = MapData.FogState.EXPLORED
			_dirty_cells.append(pos)
	for pos: Vector2i in _next_visible:
		if fog_grid[pos.y][pos.x] != MapData.FogState.VISIBLE:
			fog_grid[pos.y][pos.x] = MapData.FogState.VISIBLE
			_dirty_cells.append(pos)
	_previously_visible.assign(_next_visible.keys())
	if not _dirty_cells.is_empty():
		visibility_revision += 1


## Reveal a circle of tiles around a position.
func _reveal_circle(center: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var pos := center + Vector2i(dx, dy)
				if _in_bounds(pos):
					_next_visible[pos] = true


## Apply only changed fog cells to the visual TileMapLayer.
func _apply_fog_delta() -> void:
	if fog_layer == null:
		return

	# First frame: apply all cells to initialise the layer.
	if not _initial_apply_done:
		_initial_apply_done = true
		for y in range(MapData.MAP_HEIGHT):
			for x in range(MapData.MAP_WIDTH):
				_apply_cell(Vector2i(x, y), fog_grid[y][x] as MapData.FogState)
		return

	# Delta: only update cells that changed.
	for pos in _dirty_cells:
		_apply_cell(pos, fog_grid[pos.y][pos.x] as MapData.FogState)


## Apply a single cell's fog state to the TileMapLayer.
func _apply_cell(pos: Vector2i, state: MapData.FogState) -> void:
	match state:
		MapData.FogState.UNEXPLORED:
			fog_layer.set_cell(pos, 0, FOG_UNEXPLORED_ATLAS)
		MapData.FogState.EXPLORED:
			fog_layer.set_cell(pos, 0, FOG_EXPLORED_ATLAS)
		MapData.FogState.VISIBLE:
			fog_layer.erase_cell(pos)


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
	if fog_layer != null: _apply_cell(pos, MapData.FogState.EXPLORED)


## Reveal the entire map (cheat / debug).
func reveal_all() -> void:
	visibility_revision += 1
	_visibility_cache_valid = false
	_previously_visible.clear()
	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			fog_grid[y][x] = MapData.FogState.VISIBLE
			_previously_visible.append(Vector2i(x, y))


## Diagnostic overrides must invalidate readers just like normal fog updates.
func set_debug_tile_state(pos: Vector2i, state: MapData.FogState) -> void:
	if not _in_bounds(pos) or fog_grid[pos.y][pos.x] == state:
		return
	fog_grid[pos.y][pos.x] = state
	_visibility_cache_valid = false
	visibility_revision += 1
	if state == MapData.FogState.VISIBLE:
		if not _previously_visible.has(pos): _previously_visible.append(pos)
	else:
		_previously_visible.erase(pos)
	_dirty_cells.append(pos)


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < MapData.MAP_WIDTH and pos.y >= 0 and pos.y < MapData.MAP_HEIGHT
