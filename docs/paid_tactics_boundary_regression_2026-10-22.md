# Paid tactics: Stand Ground regression — 22 October 2026

The Stand Ground correction passes the paid comparison and local replication checks, but it changes real damage timing and several battle outcomes. Removing false acquisitions makes stationary ranged defenders respond sooner when enemies enter reach. No costs, attack damage, weapon range, pathing or AI policy were changed in this comparison.

## Source and test control

Baseline is clean beta.4 `1ea5bf06df68b777ab8d3da73723b92d4a3bcd18`. Candidate is that frozen copy with only `scripts/units/unit_base.gd` replaced by SHA256 `394d2ab4676726a225f23a5c045124a7cdc9b24357a6d19daeeab0861d6cfea3`. Concurrent UI/art changes are intentionally outside this mechanical comparison. The [compact receipt](paid_tactics_boundary_metrics_2026-10-22.json) includes the full source manifests, loaded-source identities, all changed comparison fields, final-unit diagnostics, beginner results and local network evidence.

Both tactical matrices contain the same five plans on all three maps at seed 101, fixed 60 Hz. Every process uses a private project configuration and unique Godot user directory. Thirty paired cases use 30 distinct preference directories. Each matrix has one consistent set of 49 loaded script/probe hashes; only UnitBase differs between them. A complete source manifest also covers the frozen addons, scenes, project configuration and test tools. Imports are reused from the local cache; these are headless mechanical results, not visual or performance measurements.

The harness now rejects wrong maps, economic bonuses, nonstandard banks/ages, missing paid worker purchases, incomplete army rosters and initially wounded tactical units. The comparator requires exactly equal starting banks, worker counts, paid readiness, deposited resources, bank after production, production statistics, ages, army costs and controlled deployment. All 15 paired cases satisfy those checks. The beta.4 baseline reproduces all behavioral fields of the previous 15-case receipt after process IDs and private paths are excluded.

## Same paid plans, changed fights

The method and exact orders remain those in [the prior tactical study](paid_tactical_plans_2026-10-22.md): each owner starts with four workers, 250F/250W/100G and a 30 population cap; buys six more workers, Feudal Age, production buildings and the declared army through ordinary deposits, construction and queues. Only after both full-health rosters are paid and ready are armies placed at the controlled battlefield and economy/AI/victory frozen. The terrain, collision, commands, combat and projectiles remain real runtime systems. This is a controlled paid encounter, not an uninterrupted full match.

Infantry uses six Warriors; ranged screen uses two Warriors/four Archers; mounted variants use two Warriors/three Horsemen. The defender always has three Warriors/three Archers on Stand Ground. Direct, assembled and flank plans retain their original one, two and five group-order schedules. Assembled cavalry first waits for its slower infantry. The flank includes the same wounded-unit withdrawal/return schedule. Reported orders per minute can change when a fight ends sooner; the input schedule did not change.

In the table, survivor and HP pairs are attacker:defender. 60.02s means both sides remain after the bounded observation, not a simulated draw or navigation failure.

| Map | Plan | Survivors before → after | HP before → after | End seconds before → after | Target transitions before → after |
|---|---|---|---|---:|---:|
| Open Plains | Infantry | 1:1 → 0:3 | 12:35 → 0:57 | 60.02 → 33.28 | 52 → 35 |
| Open Plains | Mounted direct | 0:2 → 0:3 | 0:62 → 0:97 | 29.23 → 26.73 | 34 → 31 |
| Open Plains | Mounted flank | 3:2 → 3:2 | 136:79 → 136:79 | 60.02 → 60.02 | 27 → 23 |
| Open Plains | Mounted assembled | 3:0 → 2:1 | 124:0 → 89:5 | 32.65 → 60.02 | 47 → 38 |
| Open Plains | Ranged screen | 5:0 → 5:0 | 158:0 → 158:0 | 27.17 → 27.17 | 33 → 30 |
| River Crossings | Infantry | 1:1 → 0:3 | 12:35 → 0:57 | 60.02 → 33.28 | 52 → 35 |
| River Crossings | Mounted direct | 0:2 → 0:3 | 0:62 → 0:97 | 29.23 → 26.73 | 34 → 31 |
| River Crossings | Mounted flank | 4:1 → 2:2 | 159:54 → 148:72 | 60.02 → 60.02 | 25 → 22 |
| River Crossings | Mounted assembled | 3:0 → 2:1 | 124:0 → 89:5 | 32.65 → 60.02 | 47 → 38 |
| River Crossings | Ranged screen | 5:0 → 5:0 | 158:0 → 158:0 | 27.17 → 27.17 | 33 → 30 |
| Woodland Flanks | Infantry | 0:2 → 0:3 | 0:46 → 0:57 | 32.42 → 33.38 | 52 → 46 |
| Woodland Flanks | Mounted direct | 0:2 → 0:3 | 0:62 → 0:97 | 29.23 → 26.73 | 34 → 31 |
| Woodland Flanks | Mounted flank | 3:2 → 4:1 | 136:53 → 159:60 | 60.02 → 60.02 | 23 → 23 |
| Woodland Flanks | Mounted assembled | 3:0 → 2:1 | 124:0 → 89:5 | 32.65 → 60.02 | 47 → 38 |
| Woodland Flanks | Ranged screen | 5:0 → 5:0 | 158:0 → 151:0 | 27.35 → 27.35 | 35 → 30 |

First damage is unchanged in all 15 cases. Navigation failures, stalled-navigation unit-seconds and unanswered orders remain zero. Total target transitions fall 575→481; all 15 cases have at least one changed behavioral field. Plains/River ranged screens retain exactly their damage events and outcome; Woodland's screen keeps five survivors but loses seven more HP. Flank outcomes differ by terrain. The repeated candidate Open Plains assembled-cavalry case reproduces every behavioral field and source identity exactly in a new preference directory.

The assembled group still preserves more troops than the identical paid roster sent directly: two survivors/89 HP versus none on every map. It no longer eliminates the defender in this fixture. Guidance to assemble and preserve a mixed army remains supported; a promise that it always wins would not be.

The new assembled-cavalry quiet ending was inspected directly. A 24 HP Warrior is at (316.794,1150.553), a 65 HP Horseman at (349.312,1136.831), and the 5 HP stationary Archer at (352,1232). Their distances to the Archer are 88.730 and 95.207, outside its 88-unit engagement bound and their own 64/80 acquisition radii. All three are idle with null targets, empty routes, inactive navigation, zero failed/stall repaths and no ignored opponent entries. Last damage is 28.633s. This is a valid no-chase standoff after completed orders; the fixture does not issue a further finishing command.

## Independent behavioral boundary review

The shared helper gates only stationary Stand Ground (`!attack_move`) and is called by both idle acquisition and nearby-threat switching. The second call matters: an out-of-reach aggressor must not steal a reachable building target. Explicit targets, advancing attack-move/patrol, Aggressive scanning, passive movement protection, current fog visibility, retaliation and building reach retain their existing paths.

I independently reran the movement agent's final focused fixture: 146 assertions pass with no errors or warnings. Both owners acquire at Archer 88/Warrior 24 and decline the outer mismatch band. An approaching target crosses 88 at 0.150s; acquisition improves 3.183→0.333s and first damage 3.650→0.800s without guard drift. In-range damage over the controlled interval is unchanged. [The focused receipt](stand_ground_2026-10-22.md) records the corresponding 28 baseline failures and all intent/fog/building cases. Faster response is the intended correction; later combat sequences are therefore allowed to diverge.

## Paid Easy learning guard

Three additional uninterrupted paid matches use the unchanged slower learner versus Easy, seed 101, a 30 population cap, with separate private preferences. Both versions start with the same standard banks and no economic bonus. The learner waits 18s to open, makes decisions every 6s, cannot start its first Barracks before 90s, spaces building inputs 20s and training inputs 18s, and begins field orders at 240s. Its 45s recovery after the first natural fighter loss and lack of wounded-unit micro are unchanged. No resources, free units or artificial losses are injected.

| Map | End seconds before → after | First damage before → after | Damage-active seconds before → after | Longest quiet gap before → after | Outcome |
|---|---:|---:|---:|---:|---|
| Open Plains | 659.90 → 703.13 | 314.77 → 294.13 | 35 → 50 | 67.95 → 61.75 | Learner Sacred win → win |
| River Crossings | 735.43 → 670.67 | 294.08 → 294.08 | 61 → 32 | 72.38 → 71.37 | Learner Sacred win → win |
| Woodland Flanks | 677.28 → 677.28 | 274.87 → 274.87 | 52 → 52 | 74.42 → 74.42 | Learner Sacred win → win |

All three learners still win by holding Sacred. Candidate learner workers and Town Center take no damage in all three; the learner's home-damage measure also remains absent. The candidate continues paid replacement after its first natural fighter loss: Plains 20.68s, River 46.45s and Woodland 15.52s until the next paid fighter. Plains is 43.23s longer, River 64.77s shorter, and Woodland is behaviorally identical. The first contact on Plains moves 20.63s earlier; this is disclosed rather than treating the learning run as unchanged. Only UnitBase differs among each pair's 49 loaded source/probe hashes.

These are three controlled automated policies at one seed, not beginner human testing or a broad balance guarantee. No new Easy tuning is justified by this limited check.

## Local authoritative replication and test correction

A local server plus independent clients passed the first eight checks: Strategy allocation/paid training/repeat/rally/refund on both owners, unavailable connection, both terminal-result loading races, cancel/malformed/ownership/fog/disconnect lifecycle, and both paid movement/construction/training/deposit clients. Private preferences are now explicit in the network runner.

The first attempt at the added combat check failed because the test used `is_processing()` to infer effective inertness. Replica scheduling flags can remain true while `process_mode` is DISABLED. The fixture consequently withheld attack-move and both clients timed out. Those original logs are retained under `output/paid-boundary-20261022/online-local/`, and their contents are in the included receipt. No gameplay fix was needed.

The corrected fixture checks `!can_process()` and DISABLED mode, along with replicated Stand Ground and correct local owner remapping. A fresh local server and two new clients then passed paid Barracks/Warrior production, stance replication, attack-move, enemy visibility, authoritative damage and surrender/result delivery. The runner's `--combat-only` mode permits this focused rerun. Its source receipt confirms source stability and three distinct private directories for the server and clients. This demonstrates transport/state/combat integration; the 146 exact range boundaries were checked in the separate real-unit fixture. It is not a clean single full-suite invocation, and no public server was contacted.

Successful checks have no script/runtime errors. Three existing ObjectDB shutdown warnings occurred across first-run strategy-one/client-one and corrected combat-one; these are retained rather than hidden. The corrected server log is clean.

## Reproduction and limits

Local artifacts are under `output/paid-boundary-20261022/`: baseline/candidate 15-case matrices, one deterministic candidate repeat, beginner-baseline/beginner-candidate trios, focused-candidate, initial online attempt and corrected combat. The included receipt includes their digests and relevant summaries. Frozen source copies are `/tmp/aoem-boundary-baseline-1ea5bf0` and `/tmp/aoem-boundary-candidate-394d2ab`.

```sh
python3 tools/run_paid_tactical_plans.py --project <frozen-project> --output <matrix-output> --jobs 3
python3 tools/compare_paid_tactical_plans.py --baseline <baseline-output> --candidate <candidate-output> --expected-source-change scripts/units/unit_base.gd --output <paired.json>
python3 tools/run_paid_ai_cadence.py --project <frozen-project> --output <beginner-output> --beginner --duration 900 --case 0:101:0 --case 1:101:0 --case 2:101:0 --jobs 3
python3 tools/run_online_tests.py --project <frozen-project> --stand-ground-combat --output <online-output>
python3 tools/run_online_tests.py --project <frozen-project> --combat-only --stand-ground-combat --output <combat-rerun-output>
```

The mechanical check supports the bounded fix and optional tactical guidance. It does not establish device FPS, network latency, all-seed balance, human APM, or the final integrated art/UI release. No runtime edits, commits or deployment were performed by this validation task.
