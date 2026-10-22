# Mobile economy and task orders — 2026-10-21

Targets: a paid first fighter by 120 seconds, first fight around 150–180 seconds, Feudal in 120–180 seconds, and a contested objective ending in roughly 6–10 minutes. These are opening targets for a 30-population, medium-AI duel, not guarantees for every map or player policy.

## Balance model

A worker's delivery rate is `60 × cargo / (cargo / raw_rate + 2 × path_distance / speed)`. The estimates below use the actual 60-world-unit villager speed, a 120-world-unit one-way path from work to a legal drop-off perimeter, zero congestion, no upgrade, and instantaneous deposit. They exclude the first trip to the resource and construction time. Real paid-match totals below include those overheads.

| Value | Before | After |
|---|---:|---:|
| Starting food / wood / gold | 200 / 150 / 100 | 250 / 250 / 100 |
| Starting workers | 4 | 4 |
| Starting housing (5 base + TC) | 10 | 15 |
| Carry slots, shared across cargo types | 10 | 15 |
| Base harvest interval | 1.15 s | 0.90 s |
| Food / wood at source | 62.6 per min | 80.0 per min |
| Gold at source | 52.2 per min | 66.7 per min |
| Food / wood delivered, 120-unit route | 44.2 per min | 59.0 per min |
| Gold delivered, same route | 38.7 per min | 51.4 per min |
| Villager / Warrior train | 16 / 12 s | 12 / 10 s |
| Archer / Horseman / Siege train | 16 / 18 / 35 s | 12 / 14 / 25 s |
| Barracks / Range / Stable cost | 150 wood | 120 wood |
| Barracks / Range / Stable construction | 30 s | 20 s |
| House construction | 15 s | 10 s |
| Three separate camp choices | 100 wood each, 15–18 s | One camp: 80 wood, 10 s |
| Farm | 75 wood, 300 food then destroyed | 75 wood, unlimited food |
| Default 30-pop Feudal / Castle cost | 300F150G / 900F450G | 250F125G / 600F300G |
| Medium / easy first raid delay | 240 / 360 s | 120 / 240 s |
| Sacred hold target | 240 s | 180 s |

The 250-wood bank supports a 120W Barracks, 80W camp and 50W House. A Farm-first opening spends another 75W and must earn that difference. Extra housing postpones the first interruption without changing the 20/30/40 match limits. The larger bag amortizes travel and retains exact mixed cargo on reassignment; it does not grant free resources.

Continuous Villager production costs 250 food/min after the change: about 4.24 nearby food workers, versus 4.24 before (187.5/44.2). Training speed therefore tracks income instead of creating an unpayable queue. Continuous Warrior production needs about 5.08 food workers plus 2.03 wood workers; Archers 2.12 food plus 3.81 wood; Horsemen 6.54 food plus 2.18 wood. A 15-worker economy cannot continuously fund all three lines plus worker growth. Unit combat costs/counters stay intact, so a faster Horseman queue still carries its higher food opportunity cost.

Permanent Farms remove the recurring 0.25-wood-per-food reseed tax. Harvest still requires a living friendly completed Farm, worker time, ordinary carry capacity, a reachable drop-off, and an actual deposit. Farms remain destructible. No new one-worker limit was invented: the previous game allowed multiple workers, and their ordinary speed/cargo rules remain.

## Concrete fixes

- A fresh resource tap activates immediately. The cargo manifest retains each original resource type in one shared bag, and a deposit credits each type exactly once. Stop, move and another assignment supersede stale delivery callbacks. Full bags must still be delivered before more harvesting.
- Only active friendly drop-offs compatible with every cargo type qualify. Compare real path length to legal building perimeter cells across all candidates; do not choose a Euclidean nearest candidate or an arbitrary first-eight subset.
- Reconsider active delivery within one second of completed/destroyed camps or obstacle revision changes. Failed routes retry; valid work resumes after depositing. Fog-safe accepted target identity remains intact.
- One Resource Camp accepts food, wood and gold. AI counts, build priority and placement use the same building. Its first placement favors the wood bottleneck.
- Rally feedback is a selected-producer flag with screen-scaled size; no persistent map-spanning dashed line.

## Actual verification

Automated paid gameplay used Godot 4.6, fixed 60 simulation frames/s, seed 424242, standard 30-population mode, and two medium controllers. Player 0 used the ordinary human construction/training/age transactions; neither controller received free resources. This is automated gameplay, not a hands-on phone play session. The baseline was captured before this pass, and the after run includes the concurrent combat improvements.

| Initial 300-second comparison | Before P0 / P1 | After P0 / P1 |
|---|---:|---:|
| First Barracks foundation | 141.0 / 207.0 s | 3.0 / 3.0 s |
| First Warrior produced | 184.5 / 250.5 s | 95.5 / 101.5 s |
| First raid | 240.0 / none by 300 s | 120.0 / 123.0 s |
| First contact | 267.5 s | 148.9 s |
| Feudal | 232.5 / 274.5 s | 144.0 / 145.5 s |
| Food deposited by 300 s | 830 / 1020 | 1631 / 1381 |
| Wood deposited by 300 s | 370 / 326 | 1225 / 1120 |
| Gold deposited by 300 s | 98 / 150 | 158 / 243 |

The first longer run ended naturally at 409.25 seconds (6:49). Its zero Archer hits exposed a separate production-egress bug: boundary Archery Ranges could spawn troops in a disconnected two-cell pocket. That bug was fixed, and the final run also uses the shortest reachable drop-off perimeter rather than the first reachable perimeter cell. The final paid match ended naturally at **401.93 seconds (6:41)** with `Sacred Site held for 3:00`.

| Final paid economy run | P0 / P1 |
|---|---:|
| First Warrior | 88.0 / 101.5 s |
| First raid | 120.0 / 126.0 s |
| First combat contact | 151.8 s |
| Feudal | 141.0 / 145.5 s |
| Archer produced | 184.5 / 198.0 s |
| Horseman produced | 219.5 / 237.5 s |
| Landed Warrior / Archer / Horseman hits | 61 / 51 / 42 and 32 / 15 / 12 |
| Peak workers | 16 / 15 |
| Housing-blocked time | 4.4 / 0.0 s |
| Food / wood / gold deposited at match end | 2350 / 1701 / 197 and 2284 / 1750 / 246 |

No engine/runtime errors appeared in these paid probes. An independent receipt review confirmed every final metric and verified that the current balance data, worker, map and AI files match the final run's recorded source hashes. The large wood gain includes the corrected perimeter delivery routes and earlier camp, beyond the raw-rate increase alone. One seed establishes liveness, not broad balance or a proof that no dominant strategy exists. Additional map seeds and human opponents remain useful balance coverage.

Focused passing checks: `test_mobile_economy_orders` (immediate retasks, 3-type conservation, shared capacity, path-distance choice, incompatible/enemy/unfinished/sealed rejection, new-camp and topology rerouting, stale callback cancellation; real obstacle fixture shortens a legal perimeter route from 389.77 to 382.22 world units); `test_economy_balance`; `test_farm_economy` (15,000-food stress); `test_farm_depletion_feedback` (now permanent food and destruction ledger; label measured 80px within 148px at 844×390); `test_ai_economy_recovery`; `test_building_perimeter_work`; `test_strategy_cargo`; `test_resource_fog_targeting`; `test_quick_skirmish_rules`. `test_paid_builder_cargo_return` and `test_skirmish_population`, `test_ai_recovery_composition`, `test_population_cap_building_loss`, and `test_worker_status_feedback` (four phone profiles) also pass after the camp-cost and housing updates. The old fixtures were updated where they explicitly required depletion, deferred retasks, or old prices.

Compact receipts: [mobile_economy_probe_2026-10-21.json](mobile_economy_probe_2026-10-21.json). Reproduction: `Godot --headless --path . --fixed-fps 60 res://tools/probe_paid_economy_trace.tscn -- --duration=720 --output=/tmp/aoem-economy.json`.

Broad regression follow-up: the isolated snapshot initially passed 108/134 cases. Two online cases require the separate paired service/client runner. All 24 applicable failures were classified, corrected where needed, and passed targeted reruns, yielding passing evidence for all 132 applicable cases. These were chiefly old prices/capacity/timers, deferred cargo expectations, and previous UI page/hold contracts; one 75-second timeout passed with 125 seconds and two receipt writers needed output directories. This is a reconciled snapshot plus targeted reruns, not a second full run of every test on the final source. See [the case-by-case receipt](mobile_focused_regression_2026-10-21.json).
