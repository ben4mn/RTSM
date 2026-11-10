extends RefCounted
## Minimap terrain colours. They follow the painted field (meadow, canopy,
## lake, ore) rather than the debug palette, and unexplored ground is a dim
## chart-paper slate instead of black so the map's shape is always readable.

const UNEXPLORED := Color("33443f")
const UNEXPLORED_ALT := Color("2f403b")
const MEMORY_TINT := Color("27353a")
const MEMORY_AMOUNT: float = 0.36
const SACRED_RING := Color("e8bf77")

const TERRAIN: Dictionary = {
	MapData.TileType.GRASS: Color("8fae6a"),
	MapData.TileType.GRASS_ALT: Color("95b26e"),
	MapData.TileType.GRASS_DARK: Color("86a765"),
	MapData.TileType.WATER: Color("4f8fa6"),
	MapData.TileType.FOREST: Color("46683f"),
	MapData.TileType.GOLD_MINE: Color("e3b84f"),
	MapData.TileType.BERRY_BUSH: Color("c9685e"),
	MapData.TileType.STONE: Color("b9b7a6"),
	MapData.TileType.SACRED_SITE: Color("d9cfae"),
}


static func terrain(tile_type: int, fog_state: int, x: int, y: int) -> Color:
	if fog_state == MapData.FogState.UNEXPLORED:
		# A faint weave keeps a large unknown area from reading as a dead panel.
		return UNEXPLORED if (x + y) % 2 == 0 else UNEXPLORED_ALT
	var color: Color = TERRAIN.get(tile_type, TERRAIN[MapData.TileType.GRASS])
	if fog_state == MapData.FogState.EXPLORED:
		return color.lerp(MEMORY_TINT, MEMORY_AMOUNT)
	return color
