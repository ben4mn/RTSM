# Farm, delivery and building-lane follow-up

The user requested another pass on crowded Farms, shared resource drop-offs and gaps between buildings, complete matches on every map, publication of all accumulated changes, and a restart of the game. This follows the completed [22 October polish pass](polish_final_report_2026-10-22.md).

## Changes

Villagers allocate separate reachable working and delivery positions. The Farm's exclusive worker claim remains independent of its temporary delivery position, so a farmer retains the Farm through harvest, delivery and return. Unit movement can pass occupied intermediate route centers while preserving exact final destinations; actual steps reject blocked cells and diagonal corners and retain a clear route to the next point.

Detailed implementation and focused evidence are in [the movement note](polish_crowd_movement_2026-10-23.md) and [economy note](polish_economy_traffic_2026-10-23.md). The [match observer](polish_congestion_observer_2026-10-23.md) records actual deposits, paid Farm completions, repeated Farm activity, observed passage through real building gaps, and prolonged low-displacement travel. Contact alone is not treated as a navigation failure.

## Baseline and scope

The pre-change baseline is the final HD runtime from the previous pass. Its native three-map comparison copy differs only in the observational skirmish harness. Source manifests and the exact overlay are preserved in `output/polish-crowding-2026-10-23/baseline-preparation/`.

An additional directly controlled Plains baseline match ran at 1× and ended naturally in an enemy Sacred victory at 10:21. It bought four workers, three Scouts, five Warriors, a Barracks and two Farms, and deposited 1088 food, 1090 wood and 475 gold. The army was sent too late to land a human unit hit, so the combat-coverage check failed. This is retained as a completed economy/placement journey, not a passing combined battle. Evidence: `output/crowding-2026-10-23/manual-baseline-plains/`.

The comparison full matches use the paid learner versus ordinary Easy AI, 3× simulation speed, normal resources and production, and natural endings. These are native rendered scripted matches, distinct from direct UI control. No physical-device result is claimed. Their timing is not an exclusive performance benchmark; private headless behavioral tests could run alongside them.

## Integrated worker validation

Thirty combined headless regressions passed with zero engine errors/warnings and unchanged source hashes. They cover Farm occupancy/rallies, mixed cargo, paid builder/worker recovery, Strategy map compatibility, movement, live congestion, pursuit, repeated attacks, fog, legal construction lanes and visual geometry. The later additional topology case also passed: a dispersed worker replanned around a newly blocked route waypoint, reached its original sub-tile work point within 3.68 world pixels, and harvested normally.

The deterministic movement matrix retained all 216 single and 432 opposing arrivals; summed pair-time below 8 pixels fell from 341.0 to 18.97 simulated seconds. Eight simultaneous delivery bags used eight endpoints rather than one and deposited exactly 120 wood. Six gatherers' minimum standing separation rose from 0.36 to 22.42 world pixels. Four adjacent legal Farms each completed two full loads with exclusive claims retained, exactly 120 food deposited and empty cargo.

The first integrated worker-only native sweep completed all three maps with normal results and menu returns:

| Map | Game time | Human/AI hits | Paid Farms human/AI | Farm-associated food human/AI | Observed gap crossings |
| --- | ---: | ---: | ---: | ---: | ---: |
| Plains | 9:22 | 48/42 | 5/6 | 1598/1285 | 227 |
| River | 8:13 | 26/34 | 3/3 | 952/923 | 97 |
| Woodland | 11:27 | 45/36 | 10/4 | 3298/1664 | 391 |

Every owner had zero navigation failures; every map had zero long attempted-travel or near-goal stalls and passed the required economy coverage. All three ended in natural human-policy Sacred victories. Retained standing worker contacts were generally about 20–24 world pixels apart and still gathering. One moving delivery pair was 11.04 pixels apart without a stalled-travel episode. Detailed contact lists are capped at 80; aggregate counters continue, so these are sampled observations, not proof of zero contact.

The sweep exposed a separate real AI issue: ordinary staging/recall commands replaced production's spaced rally destinations with a single assembly point. This was not caused solely by the learner fixture. AI staging, recall, reserve and retreat now use the existing group-order planner, preserve valid occupied slots, and hold safely when an area is full. The worker-only receipt is retained rather than presented as the final candidate.

The [assembly regression](polish_ai_assembly_2026-10-23.md) passes 46,799 checks. Five Warriors trained from ordinary paid queues retain destinations 32 pixels apart and settle at least 27.31 pixels apart. Mixed staging, reserve, retreat, a late Farm blocker, fractional anchors, occupied/full areas and repeated orders pass. Eighteen integrated behavioral suites also pass with no runtime errors. Two warnings are scoped separately: a deliberate sealed production exit and an audio teardown leak reproduced in the existing group-endpoint fixture before the assembly change.

The next three-map native sweep reached natural results and returned to the menu on all maps. Severe retained enemy idle contacts below 8 pixels dropped to zero on all three maps. It nevertheless failed the engine-log gate: a freed combat target reached a typed validator before that validator could check its lifetime. There were 777 such errors across River and Woodland. River also recorded three late attack-route stalls; the failed validator can abort the attack update before route cleanup, although those receipts do not identify each attacker's target. The same sweep revealed productive worker/idle-Scout and builder/idle-Archer overlaps. Those led to a final service-position follow-up. This intermediate candidate is explicitly rejected, with its complete receipts and error log retained in `docs/evidence/polish-crowding-assembly-rejected-20261023.json.gz` (uncompressed SHA-256 `2c462bbe3f5f49c3865b1c4bdfa45f7bc3e0f9ce683184209f0fbb26c8146cd9`).

The last worker adjustment includes settled friendly military in the existing route-time occupancy scan. A real Farm → TC → Farm → House → Farm regression reproduces zero-distance Scout/Warrior overlap before the change and 32–35.78 pixels of separation afterward. Both versions preserve exactly 15 food deposited and one fresh food carried through construction; the fixed version also checks Farm ownership release/resume. Eight affected compatibility suites pass with no engine errors/warnings. This avoids already occupied destinations; it does not continuously displace a worker if a soldier subsequently arrives at its spot.

The [combat lifetime fix](polish_freed_combat_targets_2026-10-23.md) admits an unvalidated reference only at the two lifetime predicates, checks validity/class, and then uses typed locals. Its same-fixture reproduction goes from 37 script errors and 17 failed assertions to zero errors and all 138 assertions passing. Both stale unit and building routes clear correctly after actual target deletion; attack-move resumes its authorized destination. Seven existing combat regressions also pass, including the 22,007-check progression matrix. Those private combat checks used the preceding Villager revision; the final native sweep combines both last changes.

Some human military piles in these scripted matches originate in the learner fixture's direct per-unit move to one base point. That bypasses the actual human group-order planner; it is not evidence that normal player formation commands use the same endpoint. The policy is unchanged across comparisons. Working-neighbor contacts and deliberately identical direct orders remain distinct from failed navigation.

## Combined replay and last defense follow-up

The combined worker/lifetime replay completed Plains (11:13), River (8:31) and Woodland (12:18), all with natural human-policy Sacred wins, verified menu returns, passing economy coverage and zero engine errors/warnings. There were zero navigation failures and zero long attempted-travel/near-goal stalls across all three. It observed 275, 107 and 621 actual building-gap crossings. The previous freed-target error and stalled attack routes did not recur.

The subsequent contact audit found one more distinct AI branch: after a base threat disappears, remembered-defense investigation sends every fighter to the same last-seen point. River retained ten severe idle pair episodes there. That prompted another bounded defense-order change; this clean-engine replay is preserved as intermediate evidence in `docs/evidence/polish-crowding-combined-review-20261023.json.gz`, rather than being presented as the final crowding result.

The [defense-search fix](polish_ai_defense_assembly_2026-10-23.md) reuses the assembly allocator while preserving attack-move intent, visible-threat targeting and the twelve-second memory. Its actual River-map reproduction keeps all five fighters arriving, raises minimum settled distance from 0.306 to 31.755 pixels and passes 6,316 checks. Eight existing AI/rally/group suites pass, with an independent review finding no blocker. Its compressed red/green evidence is `docs/evidence/polish-ai-defense-assembly-20261023.json.gz`.

## Accepted final full matches

The final publication snapshot combines Villager `35507194…`, UnitBase `c3786684…`, AI `7e972a7d…` and group planner `7dbbaa05…`. All 444 runtime, scene and asset files matched the checkout after the actual-project import. Each native scripted 3× match ended naturally in a human-policy Sacred victory and returned to the menu. Both owners built, trained, gathered, delivered and fought; all economy coverage gates passed.

| Map | Game time | Human/AI hits | Paid Farms human/AI | Farm-associated food human/AI | Observed gap crossings |
| --- | ---: | ---: | ---: | ---: | ---: |
| Plains | 10:48 | 39/31 | 5/8 | 2063/1808 | 288 |
| River | 11:13 | 54/50 | 8/10 | 2059/2575 | 200 |
| Woodland | 11:59 | 47/33 | 8/11 | 2700/2920 | 464 |

All three have zero engine errors/warnings, zero navigation failure signals and zero long attempted-travel or near-goal stalls. All contact details were retained (33/78/79), with zero severe idle AI pairs and zero severe worker/military pairs below eight world pixels. Productive worker pairs remain roughly 18–24 pixels apart; some workers stand around 23–26 pixels from friendly military. Brief passing contacts and the learner's deliberately shared human reserve point are not eliminated or claimed to be rigid-body collision-free. The previous River remembered-defense pile and freed-target stalls did not recur.

This follow-up completed five three-map native scripted sweeps plus one direct-control baseline journey. Intermediate failures and corrections are preserved. The accepted three-map receipts are in `docs/evidence/polish-crowding-publication-20261023.json.gz`; expanded source manifests, screenshots and logs are under `output/polish-crowding-2026-10-23/native-publication/`. [Final base lane and deliveries](images/polish-final-base-lane-20261023.png).

The actual project imports and boots into its menu without errors/warnings. Its original `project.godot` bytes and player preferences are preserved; receipt: `output/polish-crowding-2026-10-23/publication-project-check/receipt.json`.

## Exclusive native performance

The final frozen build passed the separate focus preflight and all paid-battle validity gates. No other Godot process ran during import, focus or measurement. On the Apple M4 desktop, the default Metal/mobile renderer and VSync remained unchanged at 844×390. Each owner began with four ordinary workers, recruited six more and paid for all twelve military through the existing normal-bank purchasing policy. The unmeasured setup runs at 3×; the measured battle runs at 1×, with muted audio and fixed purchasing logic rather than normal strategic AI.

| Render-completion interval | Pre-crowding HD baseline | Final crowding build |
| --- | ---: | ---: |
| Whole-window p95 | 17.271 ms | 17.046 ms |
| Whole-window p99 | 21.652 ms | 20.770 ms |
| Whole intervals above 33.33 ms | 3 / 1800 | 2 / 1799 |
| Dense-active duration | 7.117 s | 7.217 s |
| Dense-active p95 | 17.189 ms | 16.961 ms |
| Dense-active p99 | 22.685 ms | 17.776 ms |
| Dense-active maximum | 27.207 ms | 47.019 ms |

The 30.00-second final sample includes 152 real damage events, 1264 damage and two surviving military units. It has zero engine errors/warnings, zero navigation failures, no focus loss and no intervals over 50 ms. One of the two intervals above 33.33 ms occurs during dense combat; the established-dense subset has none. These short desktop samples show no material cadence regression, not a proven speedup, display/GPU timing, physical-phone result or full strategic-AI benchmark. The much larger 3× observational matches retain their separate scope.

[Exact metrics](polish_crowding_native_metrics_2026-10-23.json) include both baseline and final summaries. The final source, raw frame/transaction evidence, validity receipts and engine logs are archived in `docs/evidence/polish-native-crowding-final-20261023.json.gz` (uncompressed SHA-256 `2277ac3e63b8c64fbd960cab3e4899e5468783aac91e62257fb3e4a3bb20d866`). All earlier prepared but unused performance snapshots remain separate from this accepted measurement.

## Remaining limits

Movement uses soft separation, so brief contact and tightly adjacent productive workers remain possible. Economic occupancy is chosen when a route starts, not a continuous displacement system. Building clearance supplies open lanes but cannot guarantee connectivity across arbitrary terrain. The unchanged learner fixture can still stack its own reserves through direct identical per-unit orders; actual player group commands use the existing formation planner. Physical-device touch/performance and longer strategic/network coverage remain separate follow-ups.

[Representative resource workers](images/polish-worker-service-positions-20261023.png). Compressed evidence preserves baseline and worker-only full receipts and focused regressions, including rejected attempts, in `docs/evidence/polish-crowding-{baseline,workers,regressions}-20261023.json.gz`. Local expanded evidence is under `output/polish-crowding-2026-10-23/`.
