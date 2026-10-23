# World proportions and ground anchoring — 2026-10-22

The user requested a coherent relationship between characters, buildings and items. The earlier native paid-economy frames (`output/polish-2026-10-22/manual-integrated/09-paid-military-builds.png` and `10-economy.png`) showed people nearly as tall as Houses and Town Center doors smaller than workers. All textures used 128px canvases, but their opaque content and runtime scales varied substantially. The correction uses measured visible artwork and the existing 64×32 tile projection; it does not change building costs, logical footprints, collision dimensions, stock, worker capacity, paths, movement speed or attack origins.

## Measured geometry

The table records opaque world bounds, including source shadows and flags. It is not a collision box or physical height estimate. Units were independently reduced to approximately 28–30 world pixels for foot soldiers; mounted units remain larger. The full source measurements and runtime hashes are in `output/polish-2026-10-22/proportions/geometry-contracts.json`.

| Building | Reserved tiles | Original opaque size | Final opaque size | Scale X × Y |
| --- | --- | --- | --- | --- |
| Town Center | 4×4 | 129×122 | 202×181 | 1.70 × 1.60 |
| House | 2×2 | 45×54 | 100×114 | 1.00 × 0.96 |
| Barracks | 3×3 | 62×50 | 154×118 | 1.48 × 1.40 |
| Archery Range | 3×3 | 62×58 | 151×136 | 1.35 × 1.28 |
| Stable | 3×3 | 62×60 | 153×140 | 1.35 × 1.28 |
| Resource Camp | 2×2 | 52×41 | 103×79 | 0.90 × 0.86 |
| Siege Workshop | 3×3 | 70×71 | 153×149 | 1.32 × 1.25 |
| Blacksmith | 2×2 | 56×60 | 103×105 | 0.92 × 0.88 |
| Farm | 2×2 | 103×77 | 115×68 | 1.00 × 1.00 |
| Watch Tower | 1×1 | 47×63 | 52×141 | 1.12 × 1.12 |

Most visible buildings now use about78–81% of their reserved ground width, with open space around their walls; the low Farm uses90%. The final House entrance is about25world pixels high, the Town Center opening32and Tower27, beside29px workers. These are readable stylized relationships rather than physical simulation dimensions.

The first enlarged candidate used86–90% ground widths and taller roofs. After the user found it too large, root inspected two AoE IV gameplay references: [Town Center scene on the Age of Empires forum](https://forums.ageofempires.com/t/macedonian-doesnt-get-silver-when-you-garrison-your-villagers/281780) and [Town Center resource gathering in GamesRadar](https://www.gamesradar.com/age-of-empires-4-tips-and-tricks-aoe/). The broad compounds and lower main rooflines informed a visual retune: most architecture became about10% narrower and14–16% lower than the first candidate, while units and resource sizes stayed fixed. This is an art-direction judgment from screenshots, not an exact measurement of AoE IV's3D units or copied assets. Final measurements are recorded in `output/polish-2026-10-22/final-presentation-checks/geometry-contracts.json`.

The Farm is a Company crop field with waist-high planting bands, a basket, pail and fork. Its former miniature dwelling was removed. The Watch Tower is a narrow Company lookout with a taller shaft and human-sized entrance; it now rises above the House. Both new owner variants change cloth colors while preserving neutral crop/stone colors and identical alpha silhouettes.

| Natural resource | Previous opaque size | Current opaque size | Scale |
| --- | --- | --- | --- |
| Tree | 19×46 | 27×66 | 0.72 |
| Berry bush | 26×29 | 19×22 | 0.48 |
| Gold rocks | 36×34 | 40×36 | 0.52 |
| Stone | 34×29 | 38×32 | 0.50 |

Resource source images and palette materials are unchanged. Per-type offsets place visible trunks/roots/bases on the harvest tile: all four source lower edges are within 6 world pixels below the anchor. Tree canopy selection still uses the imported opaque mask and transformed sprite; transparent texture padding remains untargetable.

## Anchoring and feedback

A building node is the first reserved tile, rather than the center of its footprint. Earlier art, selection outlines and preview outlines treated that node as a centered footprint. Presentation now uses the midpoint between the first and last reserved tile centers, through the canonical `GameMap.tile_to_world()` conversion. This shifts the presentation center 16 world pixels down for 2×2, 32 for 3×3 and 48 for 4×4. Node positions, footprint registration, collision dimensions and combat origins stay unchanged.

Each building also has a calibrated source-art ground center. Its sprite, selection outline and placement preview use the same transform. Health and construction bars and drop-off badges sit above actual visible artwork; `BuildingBase.get_visual_bounds()` exposes the complete presentation to Main camera framing. The duplicate procedural Town Center flag and shadow were removed because those elements already exist in the Company SVGs. Placement labels and initial preview fitting use cached opaque bounds, so transparent Farm canvas padding does not consume the available field.

Selection keeps the existing narrow facade rule and deliberate unit-foot priority. No broader roof hit area was added. Main camera integration and defensive projectile visual origins are coordinated separately by the root and combat agent.

## Verification

All scoped headless checks passed without runtime errors:

- `test_world_proportions`: all 10 building ground widths, canonical centers, matching preview/final transforms, unchanged collision dimensions, facade targets, framing including bars/ground, resource proportions/base alignment, and Farm/Tower owner alpha.
- `test_company_building_art`: eight established Company families, calibrated coverage/anchors, unchanged footprints/collision, home/enemy/construction material contracts.
- `test_company_resource_materials`: unchanged source textures, shared palette shaders, stock/collision and opaque selection masks.
- `test_resource_visual_targeting`: actual mouse/touch tree canopy and Farm gathering, direct resource/enemy priority, visibility/ownership/construction guards. Sample points were moved from exact texel boundaries to pixel centers to avoid floating-point edge ambiguity after scaling.
- `test_farm_command_integration`: paid Farm construction, group refusal feedback and cargo preservation, alternative allocation, authoritative command results and paid production-rally recovery.
- `test_touch_placement_preview`, `test_building_placement_input`, `test_building_placement_fog`: explicit touch placement, dragging/camera gestures, desktop parity, GUI isolation and hidden-footprint validation.
- Combat agent separately reported all 130 `test_center_selection_occlusion` cases pass, covering Town Center and units under actual HUD occlusion.

Logs are under `output/polish-2026-10-22/proportions/`; the Center log is `output/polish-world-proportions-2026-10-22/center.log`. No performance claim is inferred from these fixtures. Native before/after phone composition is handled by the integrated proportions gallery; this document will record its result after root inspection.


## Opening and Home camera integration (first enlarged candidate)

The complete Town Center presentation is now approximately 226×215 world pixels before selection ground and overhead badges. At the maximum manual zoom of 2.2, the opaque sprite alone projects to about 497×472 pixels, while the usable phone field is only 246–286 pixels high. Requiring the entire roof in that field would contradict the retained manual zoom.

Main uses the building's actual visual bounds for automatic opening composition. Real opening boots retain the full Town Center, one nearby living worker and visible starting food, including Guide ON/OFF and notch-safe layouts. The configured mobile default remains 1.25; automatic fits in the tested profiles range from about 0.60 to 1.03 because the larger architecture and nearby resources need more room. No art or collision dimensions were reduced to meet a camera test.

When Home cannot fit the complete Town Center at the player's chosen close zoom, it instead frames the central facade, porch and canonical ground center. The fallback requires this target region to clear the HUD, then minimizes overlap with the remainder of the building. It does not change the chosen zoom. At 2.2 the roof can extend above the field; the visible entrance and ground remain available.

`test_mobile_camera_framing` independently projects the source SVG entrance (x32–62/y78–118) and the corrected footprint center. Its automatic checks use actual artwork, current ground outline and drop-off badges; the removed procedural flag is no longer counted. The remote-Farm check compares local Home zoom with and without that distant food source, replacing the obsolete requirement that the larger Town Center fit above zoom 0.9.

Evidence under `output/polish-2026-10-22/proportions/`:

- `camera-before.log`: original test on enlarged art failed the four maximum-zoom checks and the old fixed remote-Farm threshold.
- `camera-regression-baseline.log`: the updated entrance/ground assertions still failed all four maximum-zoom cases when only the new fallback was removed in the private stage. The old camera placed the entrance down to y412 on 844×390 and y432 on 932×430, below the accessible field.
- `camera-after.log` and `camera-after/framing.json`: all 12 real Main phone boots, 24 full/notched compositions, four manual 2.2 Home cases, manual zoom/resize preservation, remote-Farm isolation and unchanged fog passed. This is headless geometry evidence, not a native screenshot or physical-phone frame-rate result.
- `camera-zoom.log`: anchored reciprocal wheel/pinch, eased steps, cancellation, overview and edge-limit regression passed.
- `camera-map-edges.log`: 12 phone/scale/zoom Center profiles and all four map-edge pans passed with runtime limits intact.
- `camera-stage/source.json` plus `camera-stage/camera-overlay.json`: private source snapshot and final camera/test hashes. User preferences were isolated from the primary project throughout.

Native opening/Home images remain a separate root-coordinated verification step.

## Native candidate review and internal props

Root inspected all eight native candidate gallery views and confirmed a substantial improvement in the relationship between buildings, units and resources. The review exposed three props that had originally been exaggerated to read inside very small building sprites. This follow-up edits only `company_stable`, `company_archery_range` and `company_siege_workshop` SVGs and their matching enemy variants. Building shells, source canvases, runtime scale, source ground anchors, logical footprints and collision are unchanged.

- **Stable:** the head detail is scaled to 40%, giving an approximately 15 world-pixel head (21 including the neck). It is raised to an adult horse's standing height, with the chest continuing behind the existing gate; it does not sink to the floor like a pony. The horse and its neutral material colors match both owners.
- **Archery Range:** the two target assemblies are scaled to 39% and 46% about their feet. Imported face bounds are 18×24 and 17×22 world pixels; complete stands are 31 and 32 high. The bow sign is scaled to 46% about its post base: the bow is approximately 45 high, plus a 16 high post. The targets remain distinct from the existing roof, bench and back-wall bow stock.
- **Siege Workshop:** the stored carriage is scaled to 58% about its ground position, with further wheel-only reductions of 45% and 70%. Imported bounds are 49 world pixels wide for the carriage, with near/far wheel heights 13 and 12. This is comparable to the deployed field engine rather than larger than a person.

The unmodified six SVGs are retained under `output/polish-2026-10-22/proportions/prop-baseline/`. Direct Godot SVG parsing/raster checks passed for all six final files. All 128×128 home/enemy alpha samples match exactly. Pixel comparisons against the baseline find **zero changed pixels outside the three bounded prop regions**, confirming unchanged shells and ground platforms. Measured bounds, source hashes and results are in `output/polish-2026-10-22/proportions/prop-check/contracts.json`; isolated SVG group probes and the headless receipt script are alongside it. Native after-v2 composition is reserved for root capture and review; the SVG-only probes make no performance claim.


## Final native review

Root inspected all building pairs, units, resources and settlement in the64-view final native gallery (`output/polish-2026-10-22/proportions/final-native`). These include844×390 and1280×720 at normal and overview zoom, matching canonical footprint references and owner variants. The lower architecture keeps the unit hierarchy while reducing the heavy roof mass noted by the user. Curated comparison: `docs/images/polish-scale-before-20261022.png` and `polish-scale-after-20261022.png`; settlement `polish-settlement-after-20261022.png`.

Native depth pairs proved the centered sort correction using upper-perimeter workers:477visible pixels became0under the TC roof, with front workers and overhead feedback unchanged. The first paired fixture happened to miss the overlap and showed no change; those captures remain preserved. The updated12-state evidence is `proportions/depth-retuned-native`.

The source-window defensive-fire attachment uses current sprite transforms. Native midpoint inspection then found the existing flash was hidden behind the opaque sprite. A small child canvas item now draws it above the artwork; the same window patch changes42pixels versus0before. The4frame release/flight/impact fixture retains ordinary damage and timing (`proportions/fire-visible-native`).


## Close-zoom texture pass

The retained world dimensions expose a separate issue at maximum zoom: the 128×128 imported building textures are magnified up to 3.74×. The final pass imports only the 20 active home/enemy building SVGs at 256×256 and normalizes their sprite transforms against the original 128×128 authored space. Canonical world scales, footprint centers, collision, movement, source ground anchors and defensive-fire attachment coordinates stay fixed. Placement ghosts use the same normalization. Approximate added uncompressed RGBA8 texture storage without mipmaps is 3.75 MiB for the 20 shared textures.

Import metadata is now included in diagnostic source manifests, since SVG bytes alone no longer determine the raster resolution. Native inspection and regression results are recorded below; the pass is accepted.

The HD candidate passed all 30 repeated integration/presentation suites in `output/polish-2026-10-22/hd-validation/`, including 136 defensive attachment/release/impact checks. Tests cover all ten types with a synthetic 128px raster, enemy 256px texture, then home 256px texture: full authored canvas corners, ground and fire attachments remain within 0.001 world units; actual collision and placement transforms stay fixed.

Native replay produced 64 gallery views, 42 camera images, 18 placement states, four defensive-fire instants and 24 paired depth images with no engine errors/warnings. Root inspected every building family at phone gameplay zoom, the maximum-zoom TC entrance, settlement, blocked preview, firing flight and front/behind workers. Comparing all 64 galleries with the pre-HD set confirms 128 building records preserve ground/tile positions and normalized scale/offset exactly to 1e-6. The largest opaque-bounds component change is 0.699951 world pixels from raster antialiasing; all nonbuilding bounds are unchanged. The actual TC flash changes 42 window-patch pixels; target HP stays 60 until impact, then becomes 56.

Evidence: `hd-geometry-comparison.json`, `hd-native-results.json`, and the `hd-{gallery,camera,grid,fire,depth}` folders under the session output. Source manifests now include import metadata. The paired close-up is retained as `docs/images/polish-detail-{before,after}-hd-20261022.png`.

The separate HD performance repeat initially stopped twice at its focus preflight because macOS was locked; no paid setup or frames ran in those attempts. After the user unlocked the Mac on 23 October, the third focus check and full paid measurement passed. The final HD sample has 1,800 intervals across 30.026 actual wall seconds, whole-window p95 17.271 ms, dense p95 17.189 ms over 7.117 dense-active seconds, no engine errors/warnings and no navigation failures. Baseline whole p95 was 17.254 ms. No material cadence regression was found in this short controlled desktop case; see the final HD section of the native comparison for limits and raw evidence. The earlier pre-HD result remains intact.
