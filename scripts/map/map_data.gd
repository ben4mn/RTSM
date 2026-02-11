class_name MapData
## Shared tile/map constants and enums used across the map system.

## Tile types present on the map.
enum TileType {
	GRASS,
	WATER,
	FOREST,
	GOLD_MINE,
	BERRY_BUSH,
	STONE,
	SACRED_SITE,
}

## Fog-of-war visibility states.
enum FogState {
	UNEXPLORED,  ## Never seen — fully black.
	EXPLORED,    ## Previously seen — dimmed / greyed out.
	VISIBLE,     ## Currently in a unit's line of sight.
}

## Map dimensions (tiles).
const MAP_WIDTH := 32
const MAP_HEIGHT := 32

## Isometric tile size in pixels.
const TILE_WIDTH := 64
const TILE_HEIGHT := 32

## Movement cost multiplier for forest tiles (slows movement).
const FOREST_MOVE_COST := 2.5

## Default unit vision radius (in tiles).
const DEFAULT_VISION_RADIUS := 5

## Scout vision radius (in tiles).
const SCOUT_VISION_RADIUS := 8

## Tile color palette used by the procedural tileset.
const TILE_COLORS: Dictionary = {
	TileType.GRASS: Color(0.35, 0.65, 0.25),
	TileType.WATER: Color(0.2, 0.45, 0.85),
	TileType.FOREST: Color(0.15, 0.40, 0.15),
	TileType.GOLD_MINE: Color(0.85, 0.75, 0.15),
	TileType.BERRY_BUSH: Color(0.80, 0.30, 0.45),
	TileType.STONE: Color(0.55, 0.55, 0.55),
	TileType.SACRED_SITE: Color(0.75, 0.65, 0.85),
}

## Whether a tile blocks ground movement.
static func is_obstacle(tile_type: TileType) -> bool:
	return tile_type == TileType.WATER

## Whether a tile is a resource node.
static func is_resource(tile_type: TileType) -> bool:
	return tile_type in [TileType.GOLD_MINE, TileType.BERRY_BUSH, TileType.STONE]

## Whether a tile provides stealth cover (only scouts reveal units here).
static func is_stealth(tile_type: TileType) -> bool:
	return tile_type == TileType.FOREST
