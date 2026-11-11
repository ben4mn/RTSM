class_name WildlifeData
extends RefCounted
## Opening wildlife: herdable sheep, huntable deer and lurable boar.
## Every number the opening ritual depends on lives here so pacing work can
## retune it in one place. Nodes: scripts/map/wildlife_node.gd; placement:
## scripts/map/wildlife_placement.gd; rules: scripts/main/wildlife_director.gd.

const SHEEP: String = "sheep"
const DEER: String = "deer"
const BOAR: String = "boar"
const KINDS: Array[String] = [SHEEP, DEER, BOAR]

const NAMES: Dictionary = {SHEEP: "Sheep", DEER: "Deer", BOAR: "Wild Boar"}
const FOOD: Dictionary = {SHEEP: 100, DEER: 140, BOAR: 340}
## Villagers work wildlife this much faster than berries or farms.
const GATHER_MULTIPLIER: float = 1.3

# --- Per-player placement (mirrored for the second player) -------------------
const HOME_SHEEP: int = 4
const STRAY_PAIRS: int = 2
const DEER_COUNT: int = 4
const BOAR_COUNT: int = 2
## Chebyshev rings around the 4x4 Town Center footprint for the home pasture.
const HOME_RING_MIN: int = 2
const HOME_RING_MAX: int = 3
## Euclidean tile distances from the Town Center tile.
const STRAY_DISTANCE: Vector2 = Vector2(15.0, 19.0)
const DEER_DISTANCE: Vector2 = Vector2(9.0, 11.0)
const BOAR_DISTANCE: Vector2 = Vector2(12.0, 13.0)

# --- Sheep ------------------------------------------------------------------
const CLAIM_RADIUS_TILES: float = 3.0
const STEAL_RADIUS_TILES: float = 2.0
## A sheep cannot be stolen while one of its owner's units is this close, or
## while it stands this close to one of its owner's Town Centers.
const STEAL_GUARD_RADIUS_TILES: float = 4.0
const SHEEP_SPEED: float = 40.0
## A manual herd order also moves the owner's other live sheep this close.
const FLOCK_RADIUS_TILES: float = 2.5
## An opened carcass spoils at this rate while no villager is working it.
const CARCASS_DECAY_PER_SECOND: float = 0.25

# --- Boar ---------------------------------------------------------------------
# Round 2 E scale: a villager has 25 HP (35 with Loom), speed 60 and one gather
# tick every 0.75 s on food. HP, bite, strike and arrow were halved together
# from the first wildlife pass, so the outcomes below are unchanged:
#   - a lone villager who stands and fights dies (about 10 s) long before the
#     boar does (about 22 s);
#   - three villagers win with the bitten one nearly dead, four win cleanly;
#   - a 12-tile lure costs two to four bites, about 60% of an un-Loomed
#     villager (a running villager is bitten far less often than a standing
#     one, see BOAR_BITE_RECOIL_SECONDS);
#   - near a Town Center or tower the boar falls in about 4 s on its own.
# tools/test_boar_fight.gd pins these outcomes and prints the measured values.
const BOAR_MAX_HP: float = 60.0
const BOAR_BITE_DAMAGE: float = 4.0
const BOAR_BITE_INTERVAL: float = 1.5
## After a bite the boar gathers itself; a fleeing villager opens a gap here.
const BOAR_BITE_RECOIL_SECONDS: float = 0.4
const BOAR_BITE_RANGE: float = 30.0
## Chase speed relative to its target's own speed, never below the base.
const BOAR_CHASE_SPEED_FACTOR: float = 1.1
const BOAR_BASE_SPEED: float = 66.0
const BOAR_WALK_SPEED: float = 44.0
## HP removed by each villager gather tick while the boar is alive.
const BOAR_VILLAGER_STRIKE: float = 2.0
## A villager ordered to gather a boar enrages it once this close.
const BOAR_AGGRO_RANGE: float = 56.0
## Town Centers and towers in range each loose one hunting arrow per interval.
const BOAR_ARROW_DAMAGE: float = 15.0
const BOAR_ARROW_INTERVAL: float = 1.0
const BOAR_RETARGET_RADIUS_TILES: float = 4.0
## The boar gives up and walks home when its target gets this far away.
const BOAR_LEASH_TILES: float = 10.0
## The warning toast shows when fewer own villagers than this are nearby.
const BOAR_SAFE_VILLAGERS: int = 4

# --- Discovery ------------------------------------------------------------------
## "Gather nearest food" treats owned sheep and open carcasses within this
## range as much closer than they are, so they are worked before berries.
const PREFER_RADIUS_TILES: float = 12.0
const PREFER_OPEN_CARCASS: float = 0.02
const PREFER_OWNED_SHEEP: float = 0.1


## Tile-space distance between two world positions. One tile step is 32x16
## world pixels on the isometric axes, so screen distance alone misreads it.
static func tile_distance(a: Vector2, b: Vector2) -> float:
	var delta: Vector2 = b - a
	var half_w: float = float(MapData.TILE_WIDTH) * 0.5
	var half_h: float = float(MapData.TILE_HEIGHT) * 0.5
	var tx: float = (delta.x / half_w + delta.y / half_h) * 0.5
	var ty: float = (delta.y / half_h - delta.x / half_w) * 0.5
	return sqrt(tx * tx + ty * ty)


## World radius that is guaranteed to contain every point within `tiles`.
static func tiles_to_world_bound(tiles: float) -> float:
	return tiles * float(MapData.TILE_WIDTH) * 0.75
