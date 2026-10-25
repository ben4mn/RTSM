# Beta9 — Room to command — 25 October 2026

Release candidate: production runtime checkpoint `26ce388`, with version/release metadata committed afterward. Publishing and public verification are pending at this checkpoint; beta8 remains live until the guarded activation succeeds.

## Changes

The live spatial index narrows separation and target searches while preserving exact distance predicates and SceneTree ordering. Vision lookups use the same tile circles and published local fog grid. Nearby movement invalidates only affected vision-cache regions. Workers share an ordered visible-enemy roster; current damage, owner, death and worker attack state are still checked when consumed. Parent transforms, reparenting, ownership, source radius, death, tile movement, fog revision and building vision invalidate the appropriate result.

Full-army selection now emits one completed selection update. Replacing a selection still retires armed commands, but an ordinary selected-unit death no longer cancels a held destination gesture for survivors. Repeated labeled icon/count updates reuse their final styles rather than creating twelve StyleBoxes per button. No costs, damage, speed, attack cadence, movement arrival rules or network authority rules change.

Scouts see **10 tiles instead of 8**, a 25% radius increase, in all three civilizations and for both players. Their starting availability, speed, cost and unarmed role remain unchanged. Online protocol 6 ensures both clients use this same sight; map catalog remains 3.

The [menu review](menu_flow_2026-10-25.md) inventories Home, Solo/Online setup, kingdom selection, map/rules/population controls, every Settings tab, pause, Guide, results and management sheets. The [offline record](offline_cache_2026-10-25.md) documents warm-cache Solo and verified reuse of unchanged files. The [protocol record](protocol6_compatibility_2026-10-25.md) covers old-client reload paths and the reviewed deployment helpers.

## Battle evidence

The native Windows/RTX3080 Compatibility fixture has exactly 100 population per player: 30 working Villagers, one Scout and 69 fighters. Normal damage/deaths continue; fixture-only free replacements maintain load. Four rounds exercise 84 ScreenTouch/keyboard inputs, including 69-unit selection, Move, direct Attack, attack-move, saved groups, Base, Economy and Army. One ordinary fighter on each side is repositioned between input rounds for an isolated order target; the other 136 fighters continue combat. This is a stress fixture, not a claim about match duration, economy or balance.

The baseline restores only four pre-optimization runtime files from `f098cd5` (game_map, unit_base, auto_targeting and building_base); it retains current menus, Scout sight and selection transaction behavior. The final candidate adds `26ce388` refinements. The identical input fixture, assets, renderer and sound scheduler are used; no instrumentation runs during acceptance. Each phase uses private preferences and a frozen source with hashes. Native audio uses Dummy output: scheduler counts are evidence, human listening is not asserted.

| Measurement | Baseline | Final candidate |
| --- | ---: | ---: |
| Mean frame ms | 132.0 | 51.7 |
| Median frame ms | 122.0 | 47.3 |
| 95th percentile frame ms | 211.1 | 88.9 |
| 99th percentile frame ms | 295.8 | 125.8 |
| Worst frame ms | 373.0 | 160.7 |
| Frames above 100 ms | 253/324 | 19/583 |
| 95th percentile input acceptance ms | 218.9 | 104.4 |
| 95th percentile input-to-render ms | 395.1 | 174.0 |
| Inputs accepted | 84/84 | 84/84 |
| Population in every sampled frame | 100 / 100 | 100 / 100 |

The candidate samples 30.17 seconds of wall time and 30.10 seconds of simulation, with 30 working Villagers per owner and 41/55 actors actively attacking at the end. The baseline takes 42.77 seconds to complete its input sequence. Percentiles use the fixture's discrete sorted-index method. The largest candidate input-to-render response is 232.4 ms. These results show substantially reduced stalls, **not a stable 60 FPS guarantee**. Full-army orders still produce outliers. Native screenshot HUDs can show the prior transient 99 count because fixture replacements occur after the death HUD update; the authoritative living count and every sampled population are 100. Those paused images are not used as visual population proof.

Separate 69-unit selection measurements dropped from 110–122 ms and 69 refresh callbacks to 1.7–2.3 ms and one callback. Worker roster CPU subsection timings are historical isolated measurements, not additional whole-frame claims.

## Regression evidence

- Live unit index: 709 checks, including exact boundary distances, order, parent movement, reparenting and cached vision.
- Shared worker visibility: 172 checks against an independent geometry/grid oracle; warm-cache mutation coverage.
- Starting Scouts: 975 checks across civilizations, starts and inert network replicas; exact 160-world-unit sight.
- Selection transaction: 29 integrated checks including ordinary death during held Move/direct Attack/attack-move gestures.
- Six final selection/occlusion/phone-order suites pass; same-type double-tap selects four Villagers, area selection includes their Scout.
- Menu review: 10 focused suites plus final layout reruns, 96 native after views, zero failures. Phone layouts include 844×390 and 932×430, max UI scale and modeled insets.
- Final refinement checks: fog legality/delta, worker proactive threats, index and roster pass; 600 stable icon-style identities plus theme/shape transitions; paid Army recruitment, all-civilization field interface and 3,092 menu-layout checks pass.
- Offline cache: 26 Node cases, two packaging and 20 shell checks. Real Chrome warm-cache update reused 40,664,987 bytes, downloaded four changed files totaling 16,724,718 bytes, with zero WASM payload requests. Fresh cached Solo launch, paid recruitment, Scout movement and gathering passed with the disposable HTTP origin stopped.
- Protocol compatibility: 49 loopback events, 34 actual-client checks and 25 deployment-helper tests; final public acceptance is recorded after activation.

## Limits

Physical phones, human audio listening and browser storage longevity remain untested. Viewport/input injection is distinct from physical-device testing. Warm cached Solo is supported; an unfinished match is not saved across reloads. A changed monolithic PCK still downloads in full. Gameplay balance, ordinary human match duration and late-game economic diversity are not established by this stress fixture. Existing fog-aware occlusion silhouettes and touch targeting remain enabled.
