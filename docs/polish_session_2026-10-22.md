# Polish and playtesting session — 22 October 2026

Starting revision: `8493a48`; clean working tree. Prior beta.8 progress preserved. No publication requested or performed. Godot 4.6 stable native macOS; MCP 2.16.1 via existing addon. Evidence in `output/polish-2026-10-22/` (local captures/logs).

## Baseline and plan

Read AGENTS.md, last eight commits, morning handoff and selected-unit cue evidence. Native MCP game launched from main menu. Initial screenshot timed out while the editor embed was unfocused; raising/enlarging its native window resolved capture. Game render surface is 844×390 with saved 1.15 UI scale; pointer inputs use render-surface coordinates, not logical coordinates. This is simulated phone-sized native testing, not a physical phone.

Baseline played: menu → solo Woodland Flanks/Medium, Town Center selection and paid villager recruitment, pause/resume, worker selection, Build palette, Info on age-locked Town Center. Captures: before-menu, before-field, before-paused, before-recruit, before-build, before-locked-info. Verified P → Esc leaves Pause open. Building Info tells the player to tap to preview even when locked and omits the current shortage; hover text also never refreshes its availability explanation.

Focused cycles underway:
1. Navigation/back and shortcut discovery (agent: main cancel chain + HUD input/icon labels).
2. Recruitment availability and Info (agent: HUD recruitment sections only).
3. Repeated combat orders (agent: unit_base + combat tests): baseline repeated same-target orders every 0.1 s deal zero damage versus 30/40 HP for one unit/building order over five simulated seconds.
4. Construction information consistency (root: build_menu).
5. Battlefield presentation/control follow-up after integrated battle play (root, scope chosen from observation).

Next: finish baseline economy/build/army interaction, implement bounded changes, replay scenarios, then multiple full matches and final integration/visual/performance review. Agent file ownership is coordinated; no graphical processes from agents until assigned.

## Cycle evidence so far

- Navigation: baseline P→Esc retained pause; integrated native P→Esc resumes. New33-assertion input regression and existing settings/secondary-surface/scene-journey checks pass. Icon tooltips keep shortcuts after refresh.
- Recruitment: paid five-unit Town Center queue on the replay shows `Queue full` in rust on both unit cards while retaining normal tappable purchase feedback. Saved `after-recruit-blocker.png`; same view after Escape resume in `after-pause-escape.png`. Replay native embed was701×324 (smaller than target phone); stored HUD diagnostics map physical input accurately.
- Construction Info: current locks/shortages now agree across hover, accessibility and tap Info. Required ages use names; locked/short cards no longer promise a placement. New assertions in age-owner regression cover age-up, shortage, recovery and Info instructions. Native `after-locked-info.png` shows readable current lock; body scrolls at701×324 with close target remaining visible.
- Combat: repeated order and moving-target pursuit defects fixed; fourteen focused headless scenarios pass. Full details in `polish_combat_2026-10-22.md`. Rendered tactical replay still pending.
- Scout: refined original SVGs, unchanged scale/collision/foot anchor, clearer hood/face/boots/horse/route pennant. Native fixture passes120 pose checks and saves11 captures. Root inspected owner/mirror before-after, normal phone roster, health/selection feedback and24-unit formation. Both owner variants have identical alpha;3215 of4827 opaque pixels retain neutral material colors. No engine messages during this native fixture.
- Scout role clarity: actual baseline Scout reached Sacred, contested, stood idle and died; code confirmed zero attack is intentional. Added `Unarmed · wide vision`, explicit Info/retreat guidance, and no-op attack feedback. No combat stats changed.

Baseline natural match completed at06:18 with enemy Sacred hold win. Human issued paid villager/Scout training, age-up, Barracks placement and objective move; inspected actual contest and home raid. Human957 resources deposited,2 units trained,1 building completed,1 Sacred contest; AI26 units trained,12 buildings built,4231 resources gathered,15 army trained. Result → Main Menu input passed. This was intermittent hands-on command play while developing, not an uninterrupted skill/balance benchmark. `baseline-match.json` records it. A second short integrated opening was deliberately stopped after UI replay; it is not counted as a complete match.

Tooling notes: initial editor cache raised existing test inheritance parse errors before game startup. Concurrent headless editor import collided with MCP's existing localhost port; no runtime code cause. New test UIDs were also unknown to the already-running editor until import/restart. Final clean editor/import and runtime error check remain required; raw messages preserved in local logs.

## Integrated stabilization

All fifteen root integration suites pass with no errors/warnings after correcting the runner to invoke SceneTree scripts with `--script` and updating the old exact `Age 2` assertion to `Feudal Age`. This includes paid construction/cargo, economy resilience, Sacred profiles, AI integrations, endings, replica feedback and selection lifecycle. The first mistaken scene invocations remain recorded in `integration/`; valid reruns are in `integration-final/`.

Independent production review found no actionable regression. Online Escape routing was source-reviewed only, not newly exercised end to end. A separate economy test leak was reproduced on baseline: Woodland retains another rich food source, invalidating the depletion expectation; the fixture now pins/restores its intended Plains archetype.

Corrected native tactical fixture completed runner, mixed8v8 and building-corridor phases with no navigation failures or engine log messages. Root inspected the actual mounted pursuit, mixed formation/death/selection feedback and building replay. Initial fog-hidden fixture captures are preserved as failed evidence. The corrected fixture uses an explicit test-only revealed-fog subclass, ordinary unit stats and free rosters; it is not paid-economy or balance evidence. Timing includes capture stalls and is not a performance comparison.

## Expanded map, progression and farming loops

User steering adds map structure/resource distribution/size, age and Blacksmith combat numbers, then explicitly one worker per Farm and smoother paths. Preserve prior polish while implementing these requirements.

Two native automated paid matches completed in8.1wall minutes before these new changes: Plains1280×720 (logical844×474) and River844×390; both natural human Sacred victories at12:05/12:03 and result→menu passed. No engine errors or warnings. Reports/PNG checkpoints in `output/polish-skirmishes-20261022/native/`. Both players trained workers and all combat roles, built their economy, gathered/deposited and hit enemies. These are scripted learner observations at3×, not hands-on or physical-device evidence. Root inspected the actual construction/developed economy/first combat checkpoints.

New findings: Forge makes Scout selection show Attack2 despite no attack; recruit Info uses base stats after tech, and Castle preview repeats already-unlocked workers/Scouts. Fixing live stat/purchase descriptions with a paid-research matrix. Current ages unlock content; no automatic military stat scaling. Farm capacity is being made atomic across assignment/travel/drop-off, with occupied feedback and AI/resource discovery respecting claims.

The Plains run revealed a paid Warrior repeatedly stuck near tile(7,64) from247–427s; unlike an isolated transient failure, this merits reproduction. Added detailed walkability/building context to subsequent observer failures, without extra path searches. Root owns this pathing investigation. Static map audit already confirms72×72, equal opening access and viable flanks; measuring resource/carve losses before any generator edits.

Performance baseline import reordered only the two private-user-directory settings in project.godot. The source guard caught the byte change. Verified no semantic differences, preserved imported copy and restored exact frozen bytes. Runner now restores frozen launch settings after import; timing gates remain unchanged. Native baseline measurement underway, current candidate will be re-frozen after the new work.

## Farming, maps and progression integrated

Atomic one-worker Farm reservation now covers assignment, travel, gathering and drop-off; manual replacement/death/destruction releases it. Group refusal keeps cargo/orders. AI and Strategy skip occupied sources, production rallies recover to visible alternative food, and authoritative network requests reject fully occupied assignments. Focused plus paid full-Main command integration and compatibility suites pass. Native synthetic technology/Scout UI fixtures saved15 clean captures; inspected upgraded Warrior stats, occupied Farm Info and unarmed Scout notice.

Combat progression matrix passes22,007 checks/11,520 damage cells across48 age/upgrade/player states. Scout remains truly zero attack after Forge. Recruitment now reports live upgraded stats, ages accurately describe instant unlock-only effects, and research descriptions explain scope. No combat base values were changed.

Map resource placement now follows lane carving on River/Woodland, preserving old Open Plains seeds.105-map audit confirms no food/gold loss during those lane stages, protected opening/expansion access and unchanged wood/water geometry. Later reserved-pocket replacement still changes some seed totals; this is not a claim of monotonic stock for every seed. Catalog v2 protects online mixed-version matches through unchanged Plains fallback, verified against the frozen old server too. Actual runtime is72×72 across both modes and population20/30/40; a hidden40×40 diagnostic placeholder was corrected.

Native enclosure replay established that repeated home failures were buildings sealing3-/8-tile pockets, not an A* or movement failure. Automatic AI placement now leaves a tile between owned footprints; manual walling remains legal. Selected units receive throttled blocked-route feedback. Variable-step enclosure/reopen and paid growth regressions pass; fresh native full matches remain pending.

## Further hands-on and proportion pass

A fresh private-stage River/Easy manual match is running through ordinary menu/controls with opening guide disabled. Native844×390. Paid2starting workers, Farm, Feudal advancement, Blacksmith, Barracks, Forge and Mail, later3workers and Archery Range. Selected woodworker carrying10 wood was ordered onto occupied Farm: visible refusal and original gathering job/cargo remained. Both paid Blacksmith upgrades show DONE. Two upgraded Warriors crossed toward Sacred and were lost to enemy control; rebuilding mixed army. First Archery placement clicked blocked terrain and was correctly refused without purchase; corrected open site accepted. Screenshots and frozen source in output/polish-2026-10-22/manual-integrated. This stage predates final rally/AI-spacing/catalog fixes and visual scales.

User adds character/building/item proportions. Audit shows foot units~42–45world pixels, doors13–25, some2-tile buildings only~45pixels wide inside128-pixel footprint. Building visuals are also centered on logical corner anchor while actual footprint center is+16/+32/+48Y. New pass underway: root data-driven smaller foot troops; building/resource agent normalizes architecture/resources and footprint-center anchors; gallery agent provides frozen before/after native views; combat agent checks six-role selection/framing/replica contracts. Scale candidates are not yet visually approved. Gameplay footprint/ranges/stats are held stable. Need verify new bigger roofs/camera framing, construction ghosts, bars/badges and Farm/Tree hit targets.


## Completed manual River match and native proportion review

The River/Easy hands-on match ended naturally at10:01 in an enemy Sacred victory. Result→Main Menu was clicked and captured. Human2865 resources deposited,13 paid units including5Warriors/3Archers,5 buildings; AI4800 gathered,16 paid units and17 buildings. Human reached Feudal and paid Forge/Mail; AI reached Castle at7:14. Occupied-Farm refusal retained the selected worker’s10Wood and existing job. This was intermittent hands-on play alongside development, not uninterrupted expert play. Natural-ending receipt and25 checkpoints are under `manual-integrated/`. That editor log contains startup test-inheritance parse errors before gameplay; it is not a clean-log claim. Independent review later imported a private copy with NO `.godot` cache and ran the relevant worker suites successfully without errors or warnings (`output/polish-independent-review-2026-10-22/`).

Native fixed-composition before/after galleries now cover all6unit roles,10buildings,4resource types and a small settlement, at844×390 and1280×720 with normal and overview zoom. Root inspected the full phone roster, every building pair, resource relationship and settlement. Doors now fit workers; mounted roles stand above infantry; siege machinery is larger; trees rise above workers and bushes remain low. The Farm is a crop field and Tower a human-scaled narrow lookout. Refinement reduced oversized Stable horse, Range targets/bow and Workshop carriage while preserving shells/ground anchors. The final refined gallery contains64 rendered views (`proportions/refined-native/`). It is a synthetic free-object composition, not economy or performance evidence.

At the new world scales the tactical runner/mixed-army/building-corridor replay completed all3phases, stop/retreat/re-engage and repeated attacks with zero navigation failures. Root inspected mixed fighting and corridor shots. Capture-containing frame intervals are not used as benchmark evidence (`proportions/tactical-after/`). Native camera framing, Farm workflow and perimeter occlusion checks are next, followed by combined full matches and the exclusive paid performance comparison.

The refined gallery stage's asset import itself completed with no script errors; its benchmarking helper rejected the post-import isolation check because an independent headless test was running. This is recorded in the receipt and is not claimed as an isolated performance run. No measurements were taken from it. The native gallery subsequently passed.


## AoE IV reference retune, exact grid and placement lanes

User found the first larger architecture excessive and requested an AoE IV reference comparison. Root visually inspected two published gameplay screenshots in the browser (Age of Empires forum Town Center scene and GamesRadar Town Center resource-gathering scene; source links in the proportion notes). The reference has broad compounds and lower main rooflines. Runtime scales were retuned by roughly10% in width and14–16% in height for most buildings; Farm, units and natural resources retain their calibrated sizes. The final64-view native gallery (`proportions/final-native`) was inspected at844×390 and1280×720, normal/overview zoom, all building pairs and settlement. Curated before/after Town Center and settlement frames are in docs/images.

The second native overlap fixture demonstrated upper-side workers being drawn in front of the Town Center roof:477visible pixels became0with centered depth sorting, while front workers stayed unchanged. Buildings now expose their centered sprite to the shared Y-sort. All12 paired native states retain positions/collision/selection and overhead feedback. The original no-op fixture is preserved rather than presented as evidence.

Placement now includes a faint camera-following isometric grid derived from canonical terrain tiles. Native18-state checks cover both phone sizes and desktop, House/Farm/Barracks, actual resource blocker, pan/zoom and Cancel. The first rendered check showed opaque ghost art obscuring exact cell feedback; the ghost now draws behind cell edges and blocked cells have an X. Root inspected the corrected red/green cells and disabled Place in `placement-grid/native-marks`. The normal fog boundary stays intact.

The user's later request to leave room between buildings supersedes the earlier deliberate manual-wall allowance. A shared one-tile owned-building clearance now applies to player confirmation and automatic construction. Touching edges/corners and foundations reserve the same gap; destroyed or foreign buildings do not create this owned clearance. It does not mark the open lane solid. New real-Main regression passes67checks, including no-charge/no-order/no-cargo-change rejection, exact legal paid placement and destruction release. A single tile is a minimum center-navigation passage, not a hard-circle or two-way traffic guarantee. Opposing-unit overlap is receiving its own bounded steering check.

A new10-minute native hands-on Woodland match used the retuned sizes and grid. Human paid Feudal,2workers,1completedFarm and2Barracks attempts, inspected a rejected out-of-bounds foundation and enemy raid. The AI destroyed the Farm and first Barracks foundation; the replacement was paid before the natural enemy Sacred ending at9:58. Result→menu passed. Human deposited890Food/710Wood/330Gold, AI3241/2049/689. This intermittent economy/placement replay did not land a human unit combat hit, so the observer correctly failed its combat-coverage criterion; it is not a passing combined battle validation. Raw report is `manual-retuned/`. A prior menu-click attempt failed and is preserved in `manual-final`; atomic injected gestures now have durable pointer/event receipts, and the successful complete replay used that helper.

Native defensive-fire inspection caught a window flash hidden behind the building sprite. A small foreground child now draws the existing flash at its actual source-art window. The same midpoint window patch changed0pixels before the fix and42after; ordinary release/flight/impact HP60→56 and timing pass. Four-frame native evidence is `proportions/fire-visible-native`. Native fixture timings are not performance data.


## Final combined hands-on battle and stabilization

The dedicated River/Easy native844×390 battle completed naturally at7:29 in a human Sacred victory. Human commands paid Feudal,2workers,3Warriors,3Archers, Barracks, Range, Blacksmith, Forge and Mail. Root inspected path travel, secured the objective, reinforced the actual contest, used the smaller unit/building presentation in play and repositioned the mixed army. One Warrior was lost and3enemies killed; both sides landed28/16unit hits. The observer recorded zero navigation failures for either side. Human deposited800Food/560Wood/315Gold and AI1975/1449/685. Both normal menu Start and result→menu inputs passed; runtime logs have no errors or warnings. The full449.6wall-second match used1×time, no learner policy or grants. Source manifest confirms every current runtime/art/scene byte matches this passed manual stage. Data and25native captures: `manual-battle-final/`.

Native captures show both paid upgrades DONE (`docs/images/polish-paid-upgrades-20261022.png`) and the natural result (`polish-native-victory-20261022.png`). The observer handles entry/result buttons; root performed the actual economy, construction, recruitment, camera and army commands. This is native phone-sized mouse play, not a physical-device or uninterrupted3-hour play claim.

Final scoped stabilization:8presentation/geometry/defense/camera/selection suites plus20integration suites. Initial integration caught three outdated diagnostic premises under the new lane policy: the paid perimeter Farm had touched the TC; the enclosure probe had unregistered off-tree building stubs; a guidance assertion checked only the red channel and rejected valid teal text. The perimeter fixture now preserves legal paid work/cargo/deposit cases and rejects an edge-blocking purchase. The enclosure replay registers actual type-correct buildings, and the guidance check measures4.5:1contrast against its actual panel. All20integration checks now pass; failed initial logs remain preserved. Four long paid-behavior checks use fixed60 simulation; native timing is measured separately. Evidence: `final-integration/final-results.json`, `final-integration-repairs/`, `final-presentation-checks/` and the repaired perimeter log in `placement-clearance/`.

Three final ordinary paid native learner-vs-Easy observations are running on the same current runtime: Plains desktop, River phone and Woodland phone. Source is frozen with private preferences and refreshed imported SVGs. Final isolated dense-battle measurement is prepared but has not run yet; no performance conclusion is made before it completes.

## Completed combined validation, before the HD pass

The three frozen native paid learner-vs-Easy matches completed at 3× simulation speed with ordinary starting resources, construction, recruitment and combat. All ended in player 0 Sacred victories, returned to the menu, and recorded zero navigation failures for either player. The combined report has no failures; engine/import logs contain no errors or warnings. These are scripted native observations, not human or physical-phone play (native-combined-final/report.json and analysis.json).

| Native case | Game duration | Unit hits, player 0 / AI | Navigation failures |
| --- | ---: | ---: | ---: |
| Plains desktop | 847.97 s | 89 / 81 | 0 / 0 |
| River phone | 637.91 s | 131 / 72 | 0 / 0 |
| Woodland phone | 689.19 s | 53 / 34 | 0 / 0 |

Together with the previously documented human River victory at 7:29 (manual-battle-final/), the session now includes nine completed native menu→match→result→menu journeys: four human-controlled and five scripted. This count includes historical development builds and the Woodland match that failed its human-combat coverage requirement; it does not recast those attempts as final acceptance passes. The final human battle remains the 1×, paid 3-Warrior/3-Archer plus Forge/Mail replay with 28/16 unit hits, zero navigation failures, a natural victory and clean runtime logs.

Final integration is 20/20 passing. The separate presentation batch contains seven additional passing suites and the historical perimeter-Farm failure; that Farm fixture was repaired and passed later in the integration batch, so the original eight-entry presentation file must not be reported as eight initial passes. All failed attempt logs remain preserved. The actual project’s final editor import and menu boot both returned 0 without errors, with project settings unchanged and saved preferences restored (final-project-import/receipt.json). The native paid Farm replay also passes after its fixture followed Main’s actual assigned builder rather than assuming the selected worker received construction, and chose a legal front-side site for visible evidence (farm-final-native-replay.log).

The controlled performance comparison below is **pre-HD**. Both isolated samples used native macOS Metal on Apple M4, an 844×390 viewport, zoom 0.952, VSync enabled, a debug build and normal runtime diagnostics, with no fixed-FPS stepping. Each recorded 1,798 render-completion intervals across approximately 30 wall seconds. Sources are performance-baseline/summary.json and performance-final/summary.json.

| Pre-HD measure | Baseline | Final |
| --- | ---: | ---: |
| Whole-window p50 / p95 / p99 | 16.665 / 17.254 / 38.928 ms | 16.669 / 17.483 / 24.904 ms |
| Whole-window intervals above 33.33 ms | 20 (1.11%) | 5 (0.28%) |
| Dense-combat intervals / sampled duration | 399 / 6.67 s | 424 / 7.06 s |
| Dense-combat p95 / p99 | 17.287 / 46.240 ms | 17.351 / 22.780 ms |

Both samples meet the dense-coverage requirement and report no errors. Median and p95 cadence remain similar; the final sample has fewer long intervals. These are bounded render-completion observations, not display FPS, GPU duration, physical-device performance or proof of a general speedup. Battle samples differ slightly (151 versus 156 damage events). The later HD rendering pass is still underway; its visual, import and performance acceptance must be recorded separately and is not established by these pre-HD results.


## Final HD texture pass and stabilization

Imported only the 20 active home/enemy building SVGs at 256×256, preserving authored 128×128 coordinates through normalized BuildingBase/placement scale and offsets. Owner swaps refresh bounds; fire landmarks use the same pixel factor. Canonical world proportions, collision, reserved cells, movement and weapon rules remain fixed. Added import metadata to source manifests. The small art pass adds an estimated 3.75 MiB uncompressed shared texture storage.

All 30 repeated integration/presentation/selection suites pass on the HD candidate, including 136 defensive-fire checks and exact 128→256 owner/ground/corner/fire transform tests. The first validation wrapper mistakenly treated the SceneTree-only AI integration test as a `.tscn`; corrected to `--script` and resumed after four passed cases. Its failed launcher log is retained, no production fix was necessary. The palette-area fixture now retains its original authored-area budget after dividing the HD pixel count by four; alpha equality remains exact. The explicit fixture overlay and initial source manifest are preserved.

Native HD replays passed with 64 gallery, 42 camera, 18 grid, four defensive-fire and 24 depth images. Root inspected all ten building families at normal phone zoom, the 2.2× TC close-up, settlement, blocked cells, window flash/arrow and depth samples. Across all 64 paired gallery records, 128 building entries retain exact logical/tile positions and normalized scale/offset; maximum raster-bound component change is 0.699951 world pixels. Units/resources remain unchanged. The actual flash patch changes 42 pixels and the real target takes damage only on impact (60→56 HP). Curated latest and paired before/after close-up images are in docs/images.

Actual root editor import and menu sanity boot are clean; original project settings and player preferences were restored byte-for-byte. The HD performance stage separately imported cleanly, but two focus preflights stopped with no paid warmup because the Mac is locked. Computer control confirmed automatic unlock is unavailable; root requested manual unlock and continued all independent stabilization work. Existing accepted cadence results remain labelled pre-HD; no HD timing is claimed. Final report: docs/polish_final_report_2026-10-22.md.


## 23 October — unlocked HD performance completion

User confirmed the Mac was unlocked. The frozen HD stage still matched both its manifest and the actual checkout for all runtime/art/import files; no unrelated Godot process was present. The third focus preflight passed. The same paid policy/roster completed a 30.026-second native 1× measurement with 1,800 render-completion intervals, 158 actual damage events and all validity gates passing. Whole p95/p99 were 17.271/21.652 ms, compared with baseline 17.254/38.928 ms. Three intervals exceeded 33.33 ms (0.17%), longest streak one; dense-active had 427 intervals/7.117 seconds at p95 17.189 ms. Established-dense had 307 intervals/5.117 seconds at p95/p99 17.189/19.445 ms. No engine errors/warnings or navigation failures. Before/after native battle captures were inspected outside sampling; no screenshots/imports/other Godot workloads ran during the measurement.

No material cadence regression was found in this short controlled desktop case. The fewer long intervals do not establish a statistical speedup, physical-phone or Web performance. Paid setup (454.195 game seconds) remains excluded from battle timing. Final raw data is archived as docs/evidence/polish-native-hd-final-20261023.json.gz with a verified decompressed SHA-256; the comparison metrics retain baseline, pre-HD and a distinct hd_final entry. The old locked handoff is preserved, current handoff marks completion, and the final report/world-proportions/native-comparison notes are updated. No production source changed during this resumed turn.

Precision note: the benchmark has ten workers per owner, comprising four ordinary starting workers plus six paid recruits. All twelve military per owner are paid recruits. No extra workers or military are granted by the benchmark. The native comparison now states this distinction explicitly; the ordinary initial TC/worker endowment is preserved.
