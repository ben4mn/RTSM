# Placement grid — 2026-10-22

The user requested a subtle grid while placing buildings. `BuildingPlacement` now draws a faint neutral isometric grid only while its placement mode is active. Existing stronger footprint fill, valid/invalid cell edges and confirmation controls remain unchanged.

The grid is a separate canvas item at absolute z=-5: above the terrain at -10, below world objects at 0 and the fog layer at 10. Its uniform color and geometry never query terrain, resources, occupancy or visibility. Fog covers it through the existing rendering order, so it cannot disclose hidden resource locations or buildings.

Viewport corners are projected through the current camera and canonical `GameMap.world_to_tile()`/`tile_to_world()` conversions. The resulting tile range is clamped to the real 72×72 map. Continuous boundary lines produce the visible grid with at most 146 segments, avoiding one draw per cell or a walk over resource nodes. The cached geometry updates when the camera, viewport or preview transform changes. Stroke width remains 0.9 screen pixels across zoom levels; line alpha is 0.18. The preview can move while the surrounding world grid stays fixed.

Cancel and successful Place both hide the grid and clear its geometry immediately. A subsequent placement reuses the canvas item. Touch and desktop placement use the same layer.

Headless validation passed without errors:

- `test_placement_grid`: every selected footprint corner aligns with canonical grid lines; grid weight stays constant at 0.42, 0.95 and 2.2 zoom; camera movement and phone-to-desktop resizing update coverage; endpoints stay within map edges; off-map cameras produce no grid; hidden-content changes produce identical geometry without queries; Cancel/Place lifecycle clears the grid.
- `test_touch_placement_preview`: touch preview, dragging, camera gestures, explicit Place, final validation and desktop parity.
- `test_building_placement_input`: GUI Cancel/Place isolation, preview input and restoration of camera/selection behavior.
- `test_building_placement_fog`: generic unseen-footprint feedback and blocked stale-preview/confirmation races.

Logs are retained under `output/polish-2026-10-22/placement-grid/`. These are correctness checks, not timing evidence. Native appearance is reserved for root inspection. No building scales, source art, logical footprint or collision dimensions were changed in this pass.

## Native diagnostic fixture

`tools/render_placement_grid.tscn` instantiates the actual Main scene, ordinary Open Plains seed 101 terrain and fog, and the actual HUD inside a rendered SubViewport. It stops actors and AI after the starting settlement initializes, selects a real human worker, and invokes the normal Main placement handlers. It does not purchase buildings, alter terrain, reveal hidden map cells or write saved preferences. This is a controlled preview diagnostic, not evidence of a paid match or performance.

The fixture prepares six states at each of 844×390, 932×430 and 1280×720: valid House, valid Farm, valid 3×3 Barracks, House over visible blocked terrain, Barracks after camera pan and zoom, and Cancel at the same camera position. Phone profiles exercise the actual touch placement mode and assert that its Place and Cancel controls remain visible. The invalid preview uses an actual visible resource cell; the current seed produces one blocked square at (14,70) alongside three available squares. All captures retain the normal placement status bar and the ordinary fog boundary.

The headless run passed all 18 states, including unchanged saved preference bytes, unchanged wood/building count, the real blocked-cell list, and grid removal after Cancel. Each state retained 336 visible and 4,848 unexplored cells. Headless generates a receipt but intentionally does not claim rendered PNGs. Evidence is in `output/polish-2026-10-22/placement-grid/render-fixture-headless.log` and `output/polish-2026-10-22/placement-grid/headless/receipt.json`.

Root can launch the scene with the native renderer to save 18 PNGs plus a receipt containing source SHA-256 hashes, viewport sizes, camera positions, zoom, validity, blocked cells and fog counts:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/ben/Documents/1_Projects/aoem res://tools/render_placement_grid.tscn
```

Default output is `output/polish-2026-10-22/placement-grid/rendered/`. An alternate output directory can be passed after `--` as `--output=/absolute/path`. Native appearance remains pending root inspection. This fixture does not decide or change building clearance policy.

## Owned-building clearance regression

After the user explicitly requested room between buildings, root added the shared one-tile clearance rule. `tools/test_building_placement_clearance.tscn` validates it through actual Main, GameMap, BuildingPlacement and HUD. A bounded synthetic grass/vision patch isolates spacing from random terrain; it is test setup, not ordinary-map or native-play evidence. A real opening worker harvests wood before the geometry cases, so rejection checks preserve genuinely gathered cargo as well as existing gathering, moving and idle orders.

All 68 checks passed headlessly. Each touching edge marks precisely two conflicting squares; each touching corner marks precisely one. The actual placement HUD gives the path-spacing reason. Foundations reserve the same space, foreign buildings do not claim an adjacent lane, and actual destruction releases clearance before its fading node is freed. A hidden footprint returns the generic reason and marks all four squares, unchanged when hidden terrain changes. Exactly one open tile is legal in each direction. Both the preview's Place guard and Main's final purchase guard reject a newly conflicting location without changing resource accounts, workers' orders, cargo or building count. A legal one-tile lane then accepts one normally priced House at the exact preview tile. A real worker, positioned at the approach for this check, completes an ordinary move order through the separating tiles between the existing House and the new foundation.

The existing paid `test_farm_command_integration` also passed with clearance enabled: normal Farm cost and worker construction, one-worker group feedback and cargo preservation, Strategy alternatives, authoritative network rejection, and paid worker rally recovery. Logs are in `output/polish-2026-10-22/placement-clearance/`. These are correctness checks and do not claim measured gameplay performance.

An independent agent reran `test_placement_grid`, `test_touch_placement_preview`, `test_building_placement_input` and `test_building_placement_fog` against a frozen copy containing the clearance change. All four exited 0 with no warnings or errors; source hashes and results are in `output/polish-2026-10-22/placement-clearance/compatibility-results.json`. The 18-state actual Main/HUD render fixture also passed headlessly again with clearance enabled.

`test_building_perimeter_work` was updated for the intentional lane rule: its paid Farm moves from spawn+(0,4) to +(0,5), and its paid Range moves from x=-3 to x=-4, leaving one full tile beside the starting TC. Open Plains and Standard mode are pinned. The old sealed anchor is now required to be reachable within the same work radius. The old attempted House on a cached Farm work edge must be rejected without a charge, foundation, lost construction order or changed cargo; that work endpoint remains walkable. The existing genuine interrupted progress, builder death, paid Feudal/Range, replacement labor, cancel/reassign, work-radius, exact-once wood delivery and Farm food delivery assertions remain. Both cases passed with `--fixed-fps 60`; the loaded case preserved and deposited 15 wood, and each Farm delivered 15 food. Evidence: `output/polish-2026-10-22/placement-clearance/test_building_perimeter_work.log`. These results replace the old impossible adjacent-building test premise; they do not claim coverage of a new dynamic obstacle on the work endpoint.


## Completed native inspection

Root rendered and inspected all18states at844×390,932×430 and1280×720 in `output/polish-2026-10-22/placement-grid/native-marks/`. The initial native pass exposed footprint feedback hidden under the translucent ghost; the ghost now renders behind cell edges, with a cross on each blocked cell. The mixed valid/blocked House shows exactly its blocked square while Place remains disabled. Grid positions remain fixed through camera movement and disappear after Cancel. The ordinary fog boundary is intact. Curated images are `docs/images/polish-844x390-04-house-blocked-terrain-20261022.png` and `polish-844x390-03-barracks-valid-20261022.png`.

Root also used the grid in ordinary paid native Woodland and River matches. The final River match paid Barracks/Range/Blacksmith with separate approaches, zoomed while placing, and completed a natural Sacred victory with0navigation failures for either side. The earlier Woodland replay deliberately hit an out-of-bounds candidate, which was refused before purchase. These are native desktop inputs at phone sizes; physical touch-device testing remains separate.
