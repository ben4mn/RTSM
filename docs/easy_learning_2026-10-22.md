# Easy learning space — 2026-10-22

Easy now gives a slower opening time to develop, sends small field squads, and withdraws after a field casualty. Against the fixed slower paid learner policy below, the old build produced four learner losses and two unresolved 15-minute matches; the verified build produced six learner wins. This is repeatable automated evidence, not a claim that Easy is balanced for every human beginner.

## Behavior

- First ordinary raid: 300 seconds instead of 240; ordinary raid spacing: 150 seconds instead of 120. Current home defense remains responsive.
- Easy cannot turn an early Sacred probe into an all-army contest before five minutes. It starts an uncontested neutral-site initiative at 390 seconds; an enemy claim can receive a small response after five minutes.
- Field raids and objective fighters share a three-fighter pressure budget, rising to four after eight minutes. Redirected and unassigned troops return to staging and hold ground, so automatic pursuit cannot quietly add reserves. Local in-range self-defense is still allowed.
- The ordinary fighter target is 4 / 6 / 8 at 20 / 30 / 40 population, formerly 6 / 9 / 12. The existing separate zero-damage Scout and one paid Castle Siege exception remain. Full-match peak committed fighters can therefore reach seven at 30 population; this is not a six-unit absolute population cap.
- A death in an assigned field/objective squad starts one 45-second regroup. Retreat deaths do not prolong it. Home defense can override it, then the remaining interval still applies. A Scout already occupying Sacred leaves on a validated outbound path.
- Worker targets, starting banks, gathering rates, shared costs, damage, health, movement, research and victory rules are unchanged. Medium and Hard retain their existing policy.

## Paired paid matches

Each case uses the same map seed and fixed learner fixture before/after. Both sides start with four workers and 250 food / 250 wood / 100 gold. All additional buildings, troops, research and ages use ordinary transactions and deposits. Full matches contain no injected losses. The only loaded runtime source differences are `ai_controller.gd` and `skirmish_data.gd`; the instrumentation and learner hashes are identical.

| Map / seed | First damage before → after | Before | Verified after | Learner first fighter loss before → after |
|---|---:|---|---|---:|
| Open Plains / 101 | 258.8s → 314.8s | learner loss at 551.1s | learner win at 659.9s | 286.8s → 324.5s |
| Open Plains / 424242 | 258.0s → 275.1s | learner loss at 670.2s | learner win at 625.5s | 291.5s → 308.9s |
| River Crossings / 101 | 262.7s → 294.1s | learner loss at 521.3s | learner win at 735.4s | 275.2s → 329.4s |
| River Crossings / 424242 | 257.5s → 293.7s | unresolved at 900.0s | learner win at 720.2s | 291.8s → 319.7s |
| Woodland Flanks / 101 | 258.9s → 274.9s | learner loss at 561.3s | learner win at 677.3s | 275.7s → 404.5s |
| Woodland Flanks / 424242 | 258.3s → 314.8s | unresolved at 900.0s | learner win at 750.0s | 275.9s → 356.8s |

First damage includes learner-initiated combat and local self-defense; it is not an AI raid timer. The JSON receipt separates AI raid orders, objective orders, damage and recovery. Longer quiet gaps in Easy are intentional learning/regroup intervals, not evidence about Medium/Hard battle cadence. Every verified case includes natural military losses followed by paid replacements.

The learner is an automated Medium policy with deliberate limitations: its first decision is delayed 18 seconds; decisions are six seconds apart; training inputs per building are spaced 18 seconds and use one queue item; construction inputs are spaced 20 seconds; first Barracks is no earlier than 90 seconds; field/age inputs start at 240 seconds; wounded-unit micro is disabled; the first natural fighter death triggers one 45-second retreat. Starting workers still auto-gather normally. This proxy can still manage economy and choose counters more reliably than a new human; testing real beginners remains necessary.

## Checks

Nine focused suites pass on the final AI source: Easy pressure bounds, compact paid caps, strategic policy, live vision, economy recovery, attack-wave recovery, recovery composition, paid Easy siege budget, and real-map Scout withdrawal. The pressure regression exercises actual commands at 20/30/40/60 population, near-expiry objective redirects, active raid plus objective guard, real death signals, finite regroup, home-defense override, staged auto-acquisition and stale attack-move cancellation.

The Scout terrain fixture uses naturally purchased units on all three generated maps, then explicitly relocates the Scout and kills one assigned fighter to isolate the transition. It is a focused fixture, not a full-match pacing result. All three Scouts leave capture plus safety clearance in 2.35 seconds along six-point walkable routes; the ordinary recon chord guard remains unchanged.

Two paid Medium/Hard control pairs have identical measured JSON fields before/after the initial candidate: Plains / 101 Medium ends at 472.1s and Woodland / 424242 Hard ends at 493.8s, with first contact at 150.65s and 147.53s respectively. Those controls predate the final Easy-only Scout/hold fixes; final focused tests independently exercise Medium/Hard urgency and unchanged large-match behavior.

Intermediate candidates and intentionally stopped superseded runs are kept separately under the local evidence directory and are not counted as verified results. Initial harness mistakes (running a Node scene as a script, and a missing fixture output folder) were corrected and clean final runs recorded.

## Reproduction and receipts

`python3 tools/run_paid_ai_cadence.py --beginner --project <frozen-project> --output <directory> --duration 900 --jobs 3` with six explicit `--case` values: `0:101:0`, `0:424242:0`, `1:101:0`, `1:424242:0`, `2:101:0`, `2:424242:0`. Each subprocess gets a separate Godot user directory, avoiding saved-preference races. Use `--case 0:101:1 --case 2:424242:2` without `--beginner` for the two normal-policy difficulty controls.

- Baseline snapshot: `/tmp/aoem-easy-baseline-20261022` (runtime 334fd81 plus the new observer/learner tooling).
- Verified snapshot: `/tmp/aoem-easy-verified-20261022` (same runtime except the two AI/data changes).
- Verified AI SHA256: `2af6d8141e758000d3c7f1ab9988ac7cfe13f812fbe008c79053e23a04e7d43e`.
- Verified SkirmishData SHA256: `55f29f70336392629f1879d7988827c334fee01e4df8c5f75cb9788f59334de4`.
- Committed compact receipt: [easy_learning_metrics_2026-10-22.json](easy_learning_metrics_2026-10-22.json).
- Full local reports/logs: `output/easy-learning-20261022/{baseline,baseline-second-seed,verified,controls-before,controls-after,focused-final}/`.
