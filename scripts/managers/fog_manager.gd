class_name FogManager
extends Node2D
## Manages fog of war with three states: unexplored, explored (dimmed), visible.
## Updates visibility based on unit positions each frame.

## The fog grid — Array[Array] of MapData.FogState (row-major).
var fog_grid: Array = []

## Reference to the fog overlay TileMapLayer (set by GameMap).
var fog_layer: TileMapLayer

## Which player this fog belongs to (0 = Player 1, 1 = Player 2).
@export var owning_player: int = 0

## Tracks tiles that were visible last frame so we can transition to EXPLORED.
var _previously_visible: Array[Vector2i] = []

## Cache of registered units for vision computation.
## Each entry: { "position": Vector2i, "vision_radius": int, "is_scout": bool }
var _vision_sources: Array[Dictionary] = []

## Fog overlay atlas coordinates for each state.
## These map to the fog tileset source created in game_map.gd.
const FOG_UNEXPLORED_ATLAS := Vector2i(0, 0)
const FOG_EXPLORED_ATLAS := Vector2i(1, 0)
# VISIBLE = no fog tile (cell cleared).


func _ready() -> void:
	_init_fog_grid()


func _init_fog_grid() -> void:
	fog_grid.clear()
	for y in range(MapData.MAP_HEIGHT):
		var row: Array = []
		row.resize(MapData.MAP_WIDTH)
		row.fill(MapData.FogState.UNEXPLORED)
		fog_grid.append(row)


func _process(_delta: float) -> void:
	_update_visibility()
	_apply_fog_to_layer()


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
	# Transition all currently VISIBLE tiles to EXPLORED.
	for pos in _previously_visible:
		if _in_bounds(pos) and fog_grid[pos.y][pos.x] == MapData.FogState.VISIBLE:
			fog_grid[pos.y][pos.x] = MapData.FogState.EXPLORED
	_previously_visible.clear()

	# Compute visible tiles from all vision sources.
	for source in _vision_sources:
		var origin: Vector2i = source["position"]
		var radius: int = source["vision_radius"]
		_reveal_circle(origin, radius)


## Reveal a circle of tiles around a position.
func _reveal_circle(center: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var pos := center + Vector2i(dx, dy)
				if _in_bounds(pos):
					fog_grid[pos.y][pos.x] = MapData.FogState.VISIBLE
					_previously_visible.append(pos)


## Apply the fog grid state to the visual TileMapLayer.
func _apply_fog_to_layer() -> void:
	if fog_layer == null:
		return
	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			var pos := Vector2i(x, y)
			var state: MapData.FogState = fog_grid[y][x] as MapData.FogState
			match state:
				MapData.FogState.UNEXPLORED:
					fog_layer.set_cell(pos, 0, FOG_UNEXPLORED_ATLAS)
				MapData.FogState.EXPLORED:
					fog_layer.set_cell(pos, 0, FOG_EXPLORED_ATLAS)
				MapData.FogState.VISIBLE:
					fog_layer.erase_cell(pos)


## Check if a tile is currently visible to this player.
func is_visible(pos: Vector2i) -> bool:
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


## Reveal the entire map (cheat / debug).
func reveal_all() -> void:
	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			fog_grid[y][x] = MapData.FogState.VISIBLE
			_previously_visible.append(Vector2i(x, y))


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < MapData.MAP_WIDTH and pos.y >= 0 and pos.y < MapData.MAP_HEIGHT
