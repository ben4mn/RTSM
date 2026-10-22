# Tactical combat experiments — 22 October 2026

The deterministic matrix contains 72 real combat simulations: three seeds (101, 424242, 20261021), three generated maps (Open Plains, River Crossings, Woodland Flanks), four scenarios, and two command policies. It uses the actual GameMap, A*, group formation planner, UnitBase state machine, visibility rules, attack windups, melee commitment and projectiles. These are free tactical armies, not paid matches or measurements of human skill. Full paid AI match receipts are documented separately.

## Reproduction and frozen source

Run `python3 tools/run_combat_scenarios.py --seeds 101 424242 20261021 --maps 0 1 2`. Each seed/map process runs all eight scenario/policy combinations. Local final results are `output/combat-scenarios/frozen-{seed}-{map}.json`; aggregate results are `summary.json` and `summary.csv`. A compact 72-case receipt is checked in as `docs/combat_scenario_metrics_2026-10-22.json`. An exact repeat of all eight seed101/Open Plains cases (`determinism-repeat.json`) matched every gameplay metric and trajectory, excluding CPU timing.

The measured mechanical snapshot has UnitBase SHA-256 `952915c81c13fa1410c8cabf5e5cc57b05093483ec3c2c8258ab055bdf047cc3` and probe SHA-256 `3bb537a6480e95ce9f837fd68b67efb80bef8fbf36d8b0534240e16955e265ba`. Subsequent unit edits concern presentation only; damage, range, movement and attack timing are unchanged. The final art snapshot, UnitBase SHA-256 `88900a23306ff40e3a6dfbdcf432537e67b5ddcd5f6107155da97598c4c4c8a4`, was independently replayed through all eight seed101/Open Plains cases: every non-CPU metric and sampled trajectory matched the frozen mechanical results exactly (`output/battle-art-2026-10-22/presentation-parity.json`). Intermediate `spacing`, `inner`, `body` and earlier `final` files are exploratory runs, not the final matrix.

## Findings

| Measure | Final 72-case result |
|---|---:|
| Cases with actual damage | 72 / 72 |
| First damage | 3.217–5.467 seconds |
| Navigation failures | 0 |
| Navigation stall unit-seconds | 0 |
| Unanswered group orders | 0 |
| Command response, p95 | one 60 Hz step (16.667 ms) |
| Longest gap between damage events | 6.1 seconds |
| End states | 60 eliminations, 12 disengagements |
| Median case p95 unit-update CPU | 1.584 ms |

CPU excludes rendering, telemetry sampling and the rest of a complete match. The matrix ran alongside other jobs: case p95 ranged 0.760–2.691 ms and the worst single update was 85.012 ms. These measurements identify the cost of the simulated units, not device FPS or a guarantee of smooth mobile rendering. Native rendered paid probes provide the separate presentation/frame-time check.

Stationary melee units previously stopped separating once in attack range. In the directly comparable 12-versus-12 infantry fixture, the baseline accumulated 109.5 severe friendly-overlap pair-seconds; the final correction accumulated 52.0, a **52.5% reduction**. Minimum observed friendly-center spacing improved from 1.023 to 6.572 pixels. This is a reduction of serious overlap, not perfect packing. The final fixture had one transient enemy-overlap pair-second.

The correction applies a bounded fraction of existing movement speed to friendly separation while attacking. It preserves the current target's inner distance, outer attack range, nearby enemy bodies and walkability. It excludes building attacks and unforced Stand Ground attacks. An early draft crossed enemy bodies and was rejected before this matrix. No damage, movement-speed, attack-speed, range or cost buffs were introduced.

`test_combat_spacing` passes with four exactly coincident Warriors: after five seconds, minimum spacing is 26.779 pixels with exactly 120 damage in both open and blocked-terrain cases. Explicit target, inner/outer range, nearby enemy-body bounds, walkability and Stand Ground immobility checks pass. `test_combat_order_priorities`, `test_military_roles_and_timing`, `test_navigation_live_congestion` and `test_group_movement_combat_scale` also pass. The congestion regression moves 20 units through a one-cell gap in 16.9 seconds with minimum spacing 28.948 pixels.

## Commands have situational costs

The deliberate policy issues a small number of group orders, with decisions seven to ten seconds apart. Measured averages range from 1.9 to 7.76 orders per minute because fixtures can finish quickly. This counts group orders only, not selection, camera movement or human APM. Orders are not spammed to force a target rate.

| Scenario | Automatic result | Deliberate result | Interpretation |
|---|---|---|---|
| Infantry clash, 12 versus 12 | Owner0 loses at 26.167 s; enemy has 30 HP | Withdrawing wounded troops loses at 24.617 s; enemy has 150 HP | Pulling damage out of an even melee can worsen the fight. |
| Cavalry flank against infantry/archer screen | Front assault wins at 23.767 s; six units, 238 HP remain | Flank plus two withdrawals disengages at 38.683 s; seven units, 250 HP remain, but one enemy with 30 HP survives | More units are preserved, but the scripted retreat fails to finish the fight. |
| Retreat and reengage, archers protected by infantry | Wins at 12.167 s with 338 HP | Extra retreat wins at 22.150 s with 212 HP | Retreating an already adequate screen costs time and effective damage. |
| Multiple routes and reinforcements | Across nine maps/seeds: two Owner0 wins, seven losses | One Owner0 win, five losses, three disengagements | Flank travel and reinforcement timing can lose concentrated force; these commands are not universally better. |

Center fixtures intentionally occupy the guaranteed clear central area, so those outcomes repeat across terrain archetypes. Reinforcements use the seed-specific upper and lower crossing waypoints and show different paths and outcomes. The evidence supports readable, responsive fights and useful tactical tradeoffs; it does not establish competitive balance or that more input automatically improves results. Longer human play, varied army sizes and online latency remain separate evaluation work.
