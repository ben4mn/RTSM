# Movement lanes and friendly passing — 2026-10-22

The latest user request explicitly asks for visible blocked footprints and space to move between buildings. This supersedes the earlier decision to preserve manual touching-building walls. Root owns the new shared one-tile owned-building clearance and placement presentation; this review independently checked its geometry and owns the bounded friendly-separation change in UnitBase.

## What actually blocks a route

Buildings reserve their canonical integer footprint through `GameMap.place_building_obstacle` and `Pathfinding.set_area_solid`. Houses/Farms/Camps/Blacksmiths reserve2×2, military production buildings3×3, Town Centers4×4 and Towers1×1. These are solid cells in AStarGrid2D. Diagonal routes require both neighboring cardinal cells to be clear. The artwork is centered over the footprint; resizing its sprite does not resize or move the reserved tiles.

UnitBase and BuildingBase are Area2D nodes. Their CircleShape2D/RectangleShape2D nodes are interaction shapes, not rigid bodies that stop movement. The building rectangle is axis-aligned at the first reserved tile, so it must not be treated as the authoritative ground footprint. Unit movement follows the A* waypoints and guards its center against solid cells. The outline and placement rules should therefore use the canonical tile footprint, not either physics shape or artwork bounds.

The recommended minimum is one complete tile between owned footprints, including diagonal corner adjacency and construction sites. A `Rect2i` of the candidate must not intersect an existing owned footprint grown by one tile. The gap remains walkable; it must not itself be added to the building obstacle. This leaves single-file access under the current movement model. It does not ensure a complete route through unrelated water/resource obstacles, nor guarantee that arbitrary dense groups pass without touching.

With the actual64×32 isometric projection, a one-tile straight lane has perpendicular width28.62 world pixels. Unit circle diameters are24/28/26/32/24/36 for worker/Warrior/Archer/Horseman/Scout/Siege. Consequently the current point-navigation model admits every role through one tile, but this is not a swept-circle clearance guarantee, particularly for mounted and siege units. A blanket two-tile policy would consume substantially more base space while still not solving coincident route following.

## Narrow separation correction

Two same-line units formerly repelled only along their line of travel. Opposing or overtaking units slowed down but had no lateral intent. At exact coincidence the tie-break used world-right; horizontal parallel movers could therefore remain on exactly the same line for several seconds.

Actual travel now supplies its normalized route direction to the existing separation calculation. A deterministic route-relative side supplies lateral intent for an ally directly ahead. Exact parallel coincidence splits by stable instance ordering along the perpendicular; opposing movers each choose the same side relative to their own route, producing opposite world directions. Existing overlap strength, steering cap, speed limit, navigation path and solid-cell fallback remain in force. Combat's standing spacing call still has no travel direction and retains its previous behavior.

Workers also travel while their state is GATHERING or BUILDING. Those states participate only when an actual movement direction was supplied; standing work does not acquire movement from this change. No effective attack/stat helper, damage, target priority, attack cadence or A* implementation changed.

An experimental intermediate-waypoint bypass was rejected after a substep test caught a corner crossing. It is absent from the final candidate. Mandatory waypoint centers and final shared destinations can still cause brief contacts, especially when a unit has already settled there. This is a reduction in crowd overlap, not a rigid collision system or collision-free claim.

## Evidence and limits

`tools/test_building_lane_routing.tscn` uses actual GameMap, Pathfinding, unit scenes and building scenes on a deliberately cleared synthetic patch of Plains101. It issues free diagnostic orders and manually advances variable time steps; no native rendering, paid match or frame-time claim is made.

- Every2/3/4-square building-pair combination, both grid axes, and one-/two-tile gaps:36 layouts. All216 single-role routes use the lane, and all432 members of the opposing mixed crowds arrive with zero navigation failures. Each movement step and intermediate samples stay outside solid building tiles and respect the unit speed limit.
- Twenty focused encounters cover opposing, overtaking, settled allies, initially coincident opposing units and initially coincident parallel units in four world directions. Opposing pairs now maintain at least3 world pixels between their centers; initial parallel coincidence ends promptly. Baseline horizontal parallel coincidence persisted within1px for3.98 simulated seconds; candidate measured0 after the first sampled movement.
- Across the36 crowds, sampled distance under1px totals18.396 pair-seconds before and5.146 after (72% less). Distance under8px totals467.444→341.000 pair-seconds. All arrivals remain successful; the slowest crowd completes in24.672 seconds versus23.856 before. These sums include simultaneous contacts from multiple pairs and are not wall-clock timing or FPS. Minimum separation across the entire crowd is still0 for brief contacts with settled allies.
- Two actual Villager gather orders and two construction orders start from coincident positions. The workers follow real work paths, reach their jobs, collect resources or add construction progress, and record0 seconds of coincident travel while both routes are active.
- Existing navigation/range, live congestion, autonomous recovery, group movement/combat scale, combat spacing, repeated attack orders, moving-target pursuit, mobile commands, worker proactive threats and worker raid recovery regressions pass without script errors or warnings.

Evidence: `output/polish-building-lanes-2026-10-22/routing.json`, `routing-baseline-comparison.json`, their logs, and `validation.json`. The baseline comparison uses the prior clean imported stage with UnitBase hash`e0638c70…`. Its20 encounters and36 layouts match the final comparison; the final fixture additionally adds the worker cases and explicit regression assertions. Final UnitBase hash is`8f7e56dc05e332b4ba62b6a124104e23edd6ae05520547e332bbf67214842990`.

One existing perimeter-work fixture initially fails because its paid Farm at(6,69) touches the starting TC at(6,65), which the newly requested clearance now rejects. This is reported to root for a policy-compliant fixture update; it is not counted as a passing check here. Native full-match verification of the final source is owned by root and must be cited separately.


## Final integration follow-up

The perimeter fixture was updated to the explicit lane policy and passes again: Farm origin moved one tile away, the old enclosed anchor is now reachable, and a House purchase covering the cached work edge is rejected without changing cost/cargo/orders. Actual paid build completion, replacement labor, cancellation/reassignment and exact deposits remain asserted. Root's20-suite integration pass includes the corrected test.

The final dedicated native River/Easy match uses the exact final UnitBase hash and completes at7:29 with28/16unit hits, ordinary paid construction/training/upgrades, natural Sacred victory/menu return and zero navigation failures on either side. No runtime/art/scene files changed after that stage. Three further scripted native map observations are tracked in `output/polish-2026-10-22/native-combined-final/`; they are reported separately from human play.
