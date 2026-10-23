# Automatic base lanes and blocked-route feedback — 22 October 2026

The native match's repeated navigation failures were traced to valid building enclosures. This iteration changes automatic building placement and failure feedback. It does not alter A*, unit speed, obstacle collision or bounded navigation recovery.

## Native evidence and exact replay

In `output/polish-skirmishes-20261022/native/plains-desktop.json`, Warrior 7142094408927 repeatedly failed at world (-1824.973, 1133.346) from 247–307 seconds, then near the same position at 421–427 seconds. Actual GameMap conversion places it in tile (6,64). The human learner placed an Archery Range at (3,64) at 240 seconds, sealing the last opening between these footprints:

| Side | Building | Tile origin | Footprint |
| --- | --- | --- | --- |
| North | Barracks | (6,61) | 3×3 |
| South | Town Center | (6,65) | 4×4 |
| East | Farm | (9,63) | 2×2 |
| West, added at 240s | Archery Range | (3,64) | 3×3 |

The actual seeded map replay has a 15-waypoint path before the Range is placed. After placement, the reachable component contains exactly three tiles: (6,64), (7,64), (8,64). No legal exit exists. Repeated orders from the learner explain repeated failure events; each individual order remains bounded.

The second variable-step native diagnostic ended at 480 seconds, recording 23 human navigation failures and no AI navigation failures. The match was intentionally capped and had no natural result. Its record is `output/polish-2026-10-22/path-reproduction-native/plains-desktop.json`. Here, a Watch Tower at (5,62) closed an eight-tile courtyard after 366 seconds. Outside Warriors at (5,61) were ordered toward the Town Center tile (6,65); its nearby legal approach endpoints were inside the newly sealed courtyard. Those Warriors retained a nine-waypoint route to open ground, while the Archer inside the courtyard could not leave. This distinguishes an unreachable requested destination from a movement stall. The native process exited cleanly.

`tools/probe_navigation_native_stall.tscn` reconstructs both observed layouts on the actual seed-101 GameMap. With variable steps of 1/60, 0.05, 0.0333 and 0.08 seconds, the enclosed original Warrior reports one failure after 1.4564 simulated seconds without moving through a wall. Removing the closing Range restores its route and normal movement to the accepted legal endpoint. Every movement step remains walkable and within speed × delta. The requested target is between tile centers, so the accepted endpoint is the ordinary nearest legal tile; arrival is checked against that endpoint, not an invented exact target position.

## Cause and scoped changes

The learner fixture extends AIController and reuses its building allocator. These placements were not hand-authored fixture coordinates: production AI uses the same automatic candidate search. It previously accepted a foundation whenever its visible footprint was buildable, with no spacing from existing buildings. Gradual growth could therefore surround units already standing in a courtyard. Production egress already chooses the largest nearby connected region for new units, but that does not free existing troops enclosed by a later placement.

The automatic allocator now reserves one tile of clearance from its own existing building footprints, including foundations. It uses owned structure positions only, preserves the existing bounded search/cursor and checks footprint vision before terrain. Destroyed or other-owner structures do not reserve this automatic clearance. It selects another spaced candidate when available; if its bounded domain has none, it returns no site rather than silently relaxing the gap. It does not query a ring of hidden terrain, so the guarantee is spacing from owned structures, not universal connectivity around every natural obstacle.

On the recorded first layout, the automatic allocator rejects the closing Range at (3,64), chooses a legal alternative at (11,66), and leaves the occupied courtyard's exit open. The initial change left manual walling available; the user later explicitly requested open passages for player construction too. Player confirmation now rejects this closing layout using the same shared one-tile rule. No units are teleported or displaced, and no footprint is made passable.

Main now connects the existing `navigation_failed` signal for human units. A selected living owned unit receives: “Route blocked. Choose another destination or leave a gap between buildings.” One three-second wall-clock throttle collapses a group failure burst. Unselected units, enemy inspection, stale selection, paused/inactive matches and dead units remain quiet. The message names no hidden blocker or coordinate.

## Validation and limits

The following checks passed without script errors or warnings in `output/polish-pathing-2026-10-22/`:

- `probe_navigation_native_stall`: actual-map before/enclosed/reopened behavior, legal variable-step movement, alternate automatic site and player confirmation rejecting the same closing wall.
- `test_ai_building_clearance`: adjacency rejection, one-tile gap at a map edge, alternate-site search, cursor reset, bounded no-site result in a cramped base, ownership, destruction and vision ordering.
- `test_navigation_failure_feedback`: actual Main spawn/signal/HUD wiring from a genuinely unreachable selected-unit move; group throttling, context and inactive/dead gates.
- Existing `test_ai_economy_recovery`, `test_compact_ai_policy`, `test_ai_construction_timing`: shared build-site progression, paid construction/recovery, population policy and real builder timing.

A 480-second fixed-step paid Plains seed-101 learner-versus-Easy run completed to its requested time cap with ordinary banks and production (`paid-growth-plains101.json`). The last 460-second snapshot recorded 20/16 units trained, 9/8 army units trained, ages 3/2 and 3/8 Farms for players 0/1. Total deposits by the run's end were 2,179/2,102 food, 1,562/1,672 wood and 408/480 gold. Both economies continued to build and train after the spacing change. No natural winner had occurred by the cap. This is a growth smoke check, not a balance result or performance measurement, and that probe does not count navigation failures.

The original native report also contains four later failures for different units near the map center. Their complete live obstacle context was not captured; this replay establishes the repeated home-courtyard diagnosis only. A final native paid match should check the new automatic layout and overall navigation behavior. Spacing may change walking distances and building locations, so long-run strategic balance remains outside this bounded regression.
