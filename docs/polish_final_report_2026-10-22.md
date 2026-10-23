# AOEM polish report — 22 October 2026

Working tree based on 8493a48. Over 3 hours of active development and repeated native play/test loops. Implementation, visual checks and the final focused performance repeat are complete; the performance check finished on 23 October after the Mac was unlocked. Complete progress and failed-attempt history are in [the session log](polish_session_2026-10-22.md). A subsequent user request authorized publication and continued work on crowding; the [23 October follow-up](polish_crowding_2026-10-23.md) supersedes this report's local-avoidance handoff.

## What improved

- Navigation: consistent Back/Escape through secondary surfaces, selection and Pause; shortcut/help text stays current.
- Construction: named age locks, current shortages and tap Info agree. A faint grid follows the actual tiles; exact reserved cells remain visible over the ghost, with red/X blocked cells and disabled touch Place. Owned buildings require one open tile between footprints, including foundations/corners; rejected purchases preserve money, orders and cargo.
- Farming: exactly one worker reserves a Farm through travel, harvesting and delivery. Rejected followers retain their jobs/cargo. Strategy, AI, authoritative commands and production rallies respect capacity and find visible alternatives.
- Combat: repeated same-target orders retain their strike; moving-target pursuit reuses routes. Scout stays unarmed after Forge. Recruit/selection Info shows live upgrades. Ages unlock content, Forge adds 2 armed attack, Mail adds 1 armor; Loom applies to existing/new workers.
- Maps: River/Woodland resources are scattered after lane carving, protecting food/gold from that stage. Openings/expansions and 72×72 size were audited; online mixed catalogs fall back to unchanged Plains.
- Presentation: original Company style retained with smaller infantry, distinct mounted/siege sizes, lower/broader architecture, corrected ground centers, Farm/Tower art, smaller props and proportionate resources. Buildings sort from their ground centers; camera, previews, bars and defensive arrows follow the actual art. All 20 active building SVGs now import at 2× resolution, with normalized transforms preserving world size while sharpening close zoom.
- Movement: automatic/player spacing prevents the observed sealed courtyard. Route-relative friendly passing reduces near-coincident contact; blocked selected-unit orders get useful feedback.

## Final completed matches

These four combined-gameplay matches preceded the final geometry-preserving HD texture pass. They all have normal paid construction, training, gathering/drop-off, AI attacks, natural victory, result→menu return, and 0 engine errors/warnings.

| Run | Game time | Natural result | Unit hits human/AI | Navigation failures human/AI |
| --- | ---: | --- | ---: | ---: |
| Direct-control River, 1× | 07:29 | Human Sacred win | 28/16 | 0/0 |
| plains-desktop, scripted 3× | 14:07 | Human Sacred win | 89/81 | 0/0 |
| river-phone, scripted 3× | 10:37 | Human Sacred win | 131/72 | 0/0 |
| woodland-phone, scripted 3× | 11:29 | Human Sacred win | 53/34 | 0/0 |

The directly controlled River match bought Feudal, 2 workers, 3 Warriors, 3 Archers, Barracks, Range, Blacksmith, Forge and Mail; the army reinforced a contest and repositioned inside the objective. The three scripted runs reached Castle on both sides and exercised all roles across the set. They use a slower paid learner against ordinary Easy AI; they are scripted observations rather than directly controlled play or balance benchmarks.

Across the session, nine native skirmish journeys completed naturally: four directly controlled through the native UI and five scripted. Three earlier direct-control runs were intermittent while developing; one completed Woodland journey failed its separate combat-coverage criterion because no human unit hit landed. Short openings and capped navigation reproductions are not counted as completed matches. All actual play was native macOS at desktop/phone-sized windows; no physical phone was tested.

## Verification and performance

- The final HD candidate passes 30 integration/presentation/selection suites. Its 128px/256px owner-swap tests preserve authored corners, ground and fire origins to 0.001 world units. A clean import and menu boot in the actual project pass; settings are unchanged and player preferences restored.
- Combat progression: 22,007 checks / 11,520 damage cells across 48 age/owner/upgrade states, including actual impact and release snapshots.
- Maps: 105 generated maps, 932 real resource-approach routes, protected home/expansion access and mixed-catalog compatibility. Later reserved-pocket operations can still replace some deposits; this is not a claim that every seed's total stock increased.
- Movement: 36 building lane layouts, 216 single-unit routes, 432 crowd arrivals, 20 focused encounters and real worker approaches. Near-coincident crowd contact fell 72%, with all arrivals retained.
- Native HD presentation: 64 final world-scale views, 18 placement states, 42 camera images, 24 paired depth images and four controlled paused defensive release/flight/impact instants. Blocked-cell and Farm occupancy feedback were inspected. Across all paired galleries, normalized world transforms are unchanged; raster-edge differences remain under 0.7 world pixels.
- Final HD controlled paid desktop battle: whole-window p95 = 17.27 ms versus 17.25 ms baseline; p99 = 21.65 ms versus 38.93 ms; intervals over 33 ms = 3 versus 20. All validity gates pass, with 7.12 seconds of dense combat, zero engine errors/warnings and zero navigation failures. No material cadence regression found in this short desktop case; it is not proof of a speedup or physical-phone performance. The earlier locked-Mac preflights stopped before warmup and are preserved. [Metrics, scope and raw evidence](polish_native_comparison_2026-10-22.md).

## Representative images

[Close-up before](images/polish-detail-before-hd-20261022.png) · [Close-up after](images/polish-detail-after-hd-20261022.png) · [Scale before](images/polish-scale-before-20261022.png) · [Scale after](images/polish-scale-after-20261022.png) · [Settlement](images/polish-settlement-after-20261022.png) · [Blocked squares](images/polish-844x390-04-house-blocked-terrain-20261022.png) · [Occupied Farm](images/polish-farm-occupied-20261022.png) · [Paid upgrades](images/polish-paid-upgrades-20261022.png) · [Natural victory](images/polish-native-victory-20261022.png)

## Remaining rough edges / next priorities

Brief contacts remain at mandatory/shared waypoints; the current point-navigation model is not rigid-body traffic or collision-free passing. One-tile spacing provides a movement lane, not universal connectivity through every water/terrain arrangement. Large 3× late-game observation runs show occasional frame spikes; the controlled 1× desktop result does not establish physical-phone/Web performance.

Next priorities are physical-device touch/performance testing and improving local avoidance around occupied endpoints. Long-run strategic balance and a new fully rendered two-client network match remain useful follow-ups.
