# Resource placement and map compatibility — 2026-10-22

River Crossings and Woodland Flanks previously scattered random food/gold before carving their tactical lanes. Across 35 seeds per layout, lane clearing could remove up to 12 River food deposits or six gold deposits. The generator now finishes lane clearing before placing random resources on these two layouts. Open Plains retains its original generation order. This pass reviewed that production change and updated the diagnostic replay; it did not further change the generator.

The original resource report was preserved byte-for-byte as `output/polish-2026-10-22/maps/resources-before.json` (SHA-256 `8e62ee3b0ffd582720843a58e496b370d06dc894caea1d6cdb4f2e1d66cf8d48`). The updated 105-map report is `resources.json`; `comparison.json` records counts, all before/after grid hashes, route comparisons, source hashes and runtime dimension profiles. Seeds are 0–31, 101, 424242 and 20261021 for each layout.

| Layout, 35 seeds each | Food nodes before → after, mean (range) | Gold nodes before → after, mean (range) | Grid hashes unchanged |
|---|---|---|---:|
| Open Plains | 28.83 (26–32) → unchanged | 20.74 (18–22) → unchanged | 35/35 |
| River Crossings | 25.94 (20–32) → 30.77 (26–32) | 18.23 (16–22) → 21.14 (18–22) | 0/35 |
| Woodland Flanks | 28.03 (24–32) → 31.00 (28–32) | 19.17 (16–22) → 21.23 (16–22) | 0/35 |

Every new-layout seed now loses **zero food or gold to spawn, center and tactical-lane clearing**. Forest and water counts stay unchanged for every paired seed. All 35 Open Plains grids, resource counts and expansion/tactical route records are identical to the original reports. River tactical route records change in eight seeds and Woodland in ten; both change ten expansion-route records as the altered random-placement draws shift subsequent opening woods. Geometry and access remain valid. No claim is made that every path remains identical on the revised layouts.

Later guaranteed expansion-pocket replacement still clears its small stock/work area. Consequently final stock does not increase for every individual seed: Woodland 8 has 20→16 gold nodes, Woodland 26 has 20→18 gold nodes, and Woodland 9 has 31→29 food nodes. The stage trace exposes those losses at `_place_expansion_resources`, separately from the corrected lane loss. The bounded change preserves that pre-existing replacement behavior.

## Size and resource interpretation

Actual GameMap initialization passed **18 combinations**: all three layouts, Standard/Control race rules, and population limits 20/30/40. At seed 101 each combination produces its layout's identical 72×72 grid. Neither rule mode nor population limit changes the map dimensions. “Pocket Duel (40x40)” was a stale hidden scene label still exposed through menu diagnostics; its text now comes from `MapData.MAP_WIDTH`/`MAP_HEIGHT`. The fixture checks that diagnostic too. There is no runtime Pocket40 mode in this source.

The 72×72 grid contains 5,184 cells. The isometric tile dimensions are 64×32 world units; the full projected diamond spans 4,608×2,304 world units, not a square of 72 combat-range tiles. One combat-range tile is 16 world units. Each food deposit holds 200, each tree 250 and each gold deposit 400; multiplying node counts gives finite starting stock, not income. Farms are a separately built unlimited food source with one assigned worker. Stone-colored tiles are decorative and are excluded from the three-resource stock totals.

Route seconds in the diagnostic divide canonical world length by the base Villager speed of 60. They are nominal travel estimates, not simulated deposits per minute or observed match duration. Forests have A* destination weight 2.5; this is a route preference, not evidence of a 2.5× reduction to unit walking speed. The diagnostic world-distance reference changes no runtime pathfinding.

## Validation

All recorded runs below passed without runtime errors or warnings, using private project/user-data stages so native review preferences were not modified:

- `probe_polish_map_resources`: 105 maps, exact generation-stage replay, protected opening stock, both-side expansion routes, plus **932/932 production GameMap gather-radius approaches** to every food/gold source in the nine detailed maps with both starting Town Centers solid. These are route preflights, not harvest simulation.
- `test_map_archetypes`: 105 deterministic reflected maps, intact Town Center/objective cells, opening stock/deposit fairness, connected expansion pockets and three independently viable River crossings. Minimum connected land is 99.980% Plains, 99.958% River and 99.980% Woodland; the largest opposing opening-return travel difference is 0.041 seconds.
- `test_map_opening_fairness`: 64 original-layout seeds and 1,792 reachable expansion harvest approaches around both Town Centers.
- `probe_presentation_map_integrity`: nine actual GameMap scenes, resource registry/stock/collision receipts, legal tile/world paths, and nine independent River crossing checks.
- `test_presentation_resource_replication`: three layouts and both player slots; real partial harvest/depletion through the production serializer, JSON and client handler, with fog memory and shoreline checks.
- `test_strategy_overview`: 12 phone/scale/notch profiles plus 550×338 logical stress after using the shared unarmed/wide-vision Scout description in producer Info. Economy's Farm explanation also states one worker per Farm.

Raw logs and output reports are under `output/polish-2026-10-22/maps/`. The initial map stage is recorded in `validation-stage/source.json`; final mode/population/diagnostic and Strategy checks use `final-validation-stage/source.json`. The final resource probe file is included in that final working-tree input manifest. Its source was not modified during the run. Other agents may continue work outside these frozen stages.

## Online generation compatibility

Changing the River/Woodland grid for an existing seed requires a catalog compatibility boundary. `NetworkSession.MAP_CATALOG_VERSION` is now **2**. An older catalog-1 peer and a version-2 peer both use unchanged Open Plains when their advertised catalog does not match the server. The version-1 server already treats unknown version 2 as unsupported, so this protects the reverse connection direction without changing the protocol shape.

The expanded `test_online_maps.gd` runs nine real local WebSocket pairs: absent/absent, literal 1/1, 1/2, 2/1, absent/2, 2/absent, 999/2, 2/999 and 2/2. Paired clients agree on seed, map, match and snapshot readiness; only a pair matching the server catalog may use the seeded non-Plains layouts. Invalid map IDs remain rejected before loading. Deterministic selection covers all three catalog entries.

The nine pairs passed against the new version-2 authoritative server (`online-catalog-v2/`) and against a separately launched frozen **8493a48c9a41c1ef4b922345faa76440c4517833** version-1 server (`online-current-client-legacy-server/`). On the old server, any current-2 advertisement falls back to Plains; literal 1/1 retains the old catalog. The reverse-run receipt records the legacy server's source hashes. These are actual protocol/snapshot-readiness checks using raw test clients, not a claim of full cross-version rendered-client gameplay. No public service was contacted or deployed, and all owned local server processes were stopped.

## Visual artifacts and reproduction

`geometry-after/map-contact-sheet.png` was rendered and inspected from the actual exported topology grid and route coordinates. It is a data diagram, without fog or units. The preserved topology baseline remains `output/map-archetypes-2026-10-22/topology.json`; the candidate is `maps/topology-after.json`.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <private-stage> res://tools/probe_polish_map_resources.tscn -- --output=<absolute-evidence>/resources.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <private-stage> res://tools/test_map_archetypes.tscn -- --output=<absolute-evidence>/topology-after.json
python3 tools/render_map_archetypes.py <absolute-evidence>/topology-after.json --output <absolute-evidence>/geometry-after
python3 tools/run_online_tests.py --project <private-stage> --maps-only --output <absolute-evidence>/online-catalog-v2
```

For root's native atlas inspection, the existing `tools/test_terrain_presentation.tscn` captures 16 actual Main views of River crossings and Woodland flanks at 844×390/932×430. Pass `-- --output=<absolute-evidence>/native-terrain` and use a private stage because that fixture changes preferences. The menu-only `capture_field_atlas_menu` also writes `web/field_atlas.svg`; it is not the gameplay atlas fixture. No performance claim follows from any of these map checks.
