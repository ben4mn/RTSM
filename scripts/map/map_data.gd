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
	GRASS_ALT,    ## Visual variant — plain grass.
	GRASS_DARK,   ## Visual variant — darker grass.
}

## Fog-of-war visibility states.
enum FogState {
	UNEXPLORED,  ## Never seen — fully black.
	EXPLORED,    ## Previously seen — dimmed / greyed out.
	VISIBLE,     ## Currently in a unit's line of sight.
}

## Duel map dimensions. Open center and side approaches leave room for
## cavalry flanks and a retreat beyond the opponent's firing line.
const MAP_WIDTH := 48
const MAP_HEIGHT := 48

## Isometric tile size in pixels.
const TILE_WIDTH := 64
const TILE_HEIGHT := 32

## Canonical conversion for gameplay ranges. UnitData and BuildingData express
## attack/vision ranges in range tiles; runtime distance checks use world units.
## A range tile is half an isometric tile's screen height (16 world units).
const WORLD_UNITS_PER_RANGE_TILE := float(TILE_HEIGHT) * 0.5

## Exact natural-resource interaction radius shared by route preflight and
## Villager arrival checks. An adjacent isometric tile center is ~35.78px away.
const RESOURCE_GATHER_INTERACTION_RADIUS_WORLD: float = 36.0


static func range_tiles_to_world(range_tiles: float) -> float:
	return range_tiles * WORLD_UNITS_PER_RANGE_TILE


static func world_to_range_tiles(world_units: float) -> float:
	return world_units / WORLD_UNITS_PER_RANGE_TILE

## Movement cost multiplier for forest tiles (slows movement).
const FOREST_MOVE_COST := 2.5

## Default unit vision radius (in tiles).
const DEFAULT_VISION_RADIUS := 5

## Scout vision radius (in tiles).
const SCOUT_VISION_RADIUS := 8

## Tile color palette — used as fallback for procedural tiles and minimap.
const TILE_COLORS: Dictionary = {
	TileType.GRASS: Color(0.50, 0.72, 0.35),
	TileType.WATER: Color(0.25, 0.50, 0.88),
	TileType.FOREST: Color(0.12, 0.35, 0.10),
	TileType.GOLD_MINE: Color(0.85, 0.70, 0.20),
	TileType.BERRY_BUSH: Color(0.75, 0.30, 0.35),
	TileType.STONE: Color(0.70, 0.68, 0.55),
	TileType.SACRED_SITE: Color(0.65, 0.55, 0.45),
	TileType.GRASS_ALT: Color(0.45, 0.68, 0.30),
	TileType.GRASS_DARK: Color(0.35, 0.55, 0.25),
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

## Whether a tile is walkable open ground (grass or grass variant).
static func is_grass(tile_type: TileType) -> bool:
	return tile_type in [TileType.GRASS, TileType.GRASS_ALT, TileType.GRASS_DARK]
