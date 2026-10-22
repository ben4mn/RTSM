# Map archetypes — 2026-10-22

Three selectable layouts use the existing 72×72 battlefield, player starts, Sacred Site and economy. The default remains Open Plains. `MapGenerator.new(seed, archetype = MapData.MapArchetype.OPEN_PLAINS)` accepts the optional layout; `MapData.MAP_ARCHETYPES` supplies names and short tactical descriptions. Unknown values normalize to the default.

| Layout | Intended decision | Generation |
| --- | --- | --- |
| Open Plains | Fight across the center or split raids toward the side expansions. | Existing scattered lakes/woods and seeded generation are unchanged. |
| River Crossings | Hold a crossing while threatening a different one; shift reinforcements between routes. | A separating river has a broad central crossing and two separate flank crossings. Each crossing contains at least a clear 7×7 tile area. |
| Woodland Flanks | Scout the side routes and choose between the open center, lateral paths and expansion approaches. | Larger forest bands surround open attack lanes. Existing forest pathfinding weight remains; no concealment, armor or movement-speed bonus is introduced. |

The new layouts carve three seven-cell-wide tactical corridors before placing guaranteed opening stock and mirrored expansion pockets. River crossing centers sit 448–576 world units above/below the center crossing. The resulting flank routes are only about 5–8% longer than the center route in the tested new layouts, avoiding a large travel penalty for tactical repositioning. `get_tactical_routes()` exposes the three waypoint chains for probes; it does not issue orders or grant AI map knowledge.

## Geometry and fairness evidence

`test_map_archetypes` passed 105 generated maps: seeds 0–31, 101, 424242 and 20261021 for each of the three layouts. It checks deterministic replay, exact x=y terrain reflection, intact 4×4 Town Center footprints, all four objective cells, visible guaranteed food/wood/gold and real outbound/shortest-perimeter deposit paths with both TC footprints blocked.

For every River Crossings seed, the test blocks the other two crossing regions and confirms a real path through the remaining crossing. Thus one blocked crossing or contested central objective cannot disconnect the bases. Both expansion pockets remain reachable, and every food, gold and forest tile within the opening 13-tile vision radius belongs to the reachable land component. A cardinal flood-fill from the base approach reaches more than 99.95% of available land across the matrix; rare isolated cells beside random ponds are not used for any guaranteed route or resource pocket.

| Measurement across 35 seeds each | Open Plains | River Crossings | Woodland Flanks |
| --- | ---: | ---: | ---: |
| Forest tiles | 108–191 | 54–146 | 335–576 |
| Water tiles | 10–36 | 343–375 | 0–30 |
| Minimum connected land | 99.980% | 99.958% | 99.980% |
| Maximum opposing opening-delivery travel difference | 0.000 s | 0.000 s | 0.041 s |

Five captured Open Plains grid hashes (seeds 0, 1, 101, 424242 and 20261021) remain exactly unchanged. The existing `test_map_opening_fairness` also passes its 64 seeds and 1,792 expansion-resource approach checks. The fairness probe now measures the current shortest legal TC-perimeter return route rather than its obsolete TC-anchor route.

These are actual generated geometry and runtime pathfinding checks, not a claim about player feel, combat outcomes or balance. Paid multi-seed matches and controlled battle scenarios are recorded separately by the gameplay experiment pass.

## Reproduce and inspect

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/test_map_archetypes.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/test_map_opening_fairness.tscn
python3 tools/render_map_archetypes.py output/map-archetypes-2026-10-22/topology.json
```

The renderer draws the actual exported tiles and runtime A* paths. It does not generate illustrative terrain. The [contact sheet](images/map-archetypes-2026-10-22.png) compares three seeds across all layouts; individual overviews, raw routes, tile grids and test logs are in `output/map-archetypes-2026-10-22/`. Generated output is ignored by Git. The compact [metrics receipt](map_archetype_metrics_2026-10-22.json) records the ranges and source hashes in the repository.
