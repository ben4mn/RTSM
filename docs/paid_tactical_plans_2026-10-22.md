# Paid tactical plans — 22 October 2026

Fifteen controlled paid scenarios compare three army plans and two mounted controls on all three maps, seed 101, frozen runtime `009bed4` (beta.3). The clearest result is that one additional staging order changes the mounted force from losing all five units to winning with three survivors. More elaborate flank/withdraw commands preserve units but fail to finish the defense. No runtime or balance change was made for this evaluation.

## Method and limits

Each case starts with the normal four workers, 250 food/250 wood/100 gold, 30 population limit, and no economic bonus. A test-only purchaser uses the existing economy policy and normal Main construction/training/age transactions. It buys six more workers, ordinary buildings with actual labor, Feudal Age, and the requested roster through real queues. All income is delivered by workers. No units, resources, research, health or training time are granted. The fixture buys two initial Warriors, saves for Feudal, then completes its composition; these are reproducible purchases, not optimized rush timings.

Once both complete full-health rosters exist, the fixture freezes economy, production, AI and victory progression. It explicitly relocates the already purchased troops to connected walkable slots around the real map center: attackers roughly 620 world units west, defending Warriors 220 east, defending Archers 290 east, with 44-unit desired row spacing. The defender holds ground. Native GameMap routes, GroupOrderPlanner, UnitBase, visibility, windups, counter damage and projectiles run at fixed 60 Hz. The flank uses the generated upper crossing. Positions, full order schedules, source hashes, deposits and purchases are recorded. These controlled placements remove travel from home and ongoing reinforcement/economy decisions; the results are not full-match winrates.

| Plan | Attacking roster | Troop cost | Group orders |
|---|---|---:|---:|
| Infantry pressure | 6 Warriors | 300F + 120W | 1 attack-move |
| Ranged screen | 2 Warriors + 4 Archers | 200F + 220W | 2 role-specific attack-moves |
| Mounted direct | 2 Warriors + 3 Horsemen | 370F + 130W | 1 attack-move |
| Mounted staged | Same mounted roster | Same cost | 1 passive Move, then 1 attack-move after the slow screen arrives |
| Mounted flank/withdraw | Same mounted roster | Same cost | 5: center pressure, upper crossing, rear engagement, wounded withdrawal, reengagement |

Every case faces the same paid 3 Warrior + 3 Archer defense (225F + 195W). Rosters have different costs/population and different infrastructure requirements; only the mounted variants hold the roster constant. The ranged plan includes a conditional wounded retreat, but no Archer was wounded at that decision, so it correctly issued no extra order. Both requested wounded horsemen survive the eight-second withdrawal interval in all three flank cases. Group orders omit selection, camera motion and touch targeting and must not be presented as human APM.

## Results

Contact and duration below start at the tactical deployment, after the paid opening. Survivors and HP list attacker/defender.

| Map | Plan | Army ready at | First damage | Tactical end | Survivors | Remaining HP |
|---|---|---:|---:|---|---:|---:|
| Open Plains | 6 Warrior pressure | 265.02s | 14.98s | disengaged at 60.02s | 1/1 | 12/35 |
| Open Plains | Mounted direct | 292.52s | 9.65s | elimination at 29.23s | 0/2 | 0/62 |
| Open Plains | Mounted flank/withdraw | 292.52s | 14.65s | disengaged at 60.02s | 3/2 | 136/79 |
| Open Plains | Mounted staged | 292.52s | 13.03s | elimination at 32.65s | 3/0 | 124/0 |
| Open Plains | 2 Warrior + 4 Archer screen | 324.02s | 15.43s | elimination at 27.17s | 5/0 | 158/0 |
| River Crossings | 6 Warrior pressure | 265.02s | 14.98s | disengaged at 60.02s | 1/1 | 12/35 |
| River Crossings | Mounted direct | 289.52s | 9.65s | elimination at 29.23s | 0/2 | 0/62 |
| River Crossings | Mounted flank/withdraw | 289.52s | 15.25s | disengaged at 60.02s | 4/1 | 159/54 |
| River Crossings | Mounted staged | 289.52s | 13.03s | elimination at 32.65s | 3/0 | 124/0 |
| River Crossings | 2 Warrior + 4 Archer screen | 295.52s | 15.43s | elimination at 27.17s | 5/0 | 158/0 |
| Woodland Flanks | 6 Warrior pressure | 265.02s | 14.98s | elimination at 32.42s | 0/2 | 0/46 |
| Woodland Flanks | Mounted direct | 292.52s | 9.65s | elimination at 29.23s | 0/2 | 0/62 |
| Woodland Flanks | Mounted flank/withdraw | 292.52s | 15.28s | disengaged at 60.02s | 3/2 | 136/53 |
| Woodland Flanks | Mounted staged | 292.52s | 13.03s | elimination at 32.65s | 3/0 | 124/0 |
| Woodland Flanks | 2 Warrior + 4 Archer screen | 298.52s | 15.43s | elimination at 27.35s | 5/0 | 158/0 |

Ranged screens win all three controlled fights with five survivors/158HP. Direct mounted charges contact early at 9.65s because 95-speed Horsemen run ahead of 55-speed Warriors; all attackers die by 29.23s. Waiting briefly with a passive group Move before engaging delays contact to 13.03s and wins at 32.65s with three survivors/124HP. This is a low-input timing decision with a concrete cost and benefit, not evidence that high APM always wins.

The flank/withdraw plan contacts at 14.65–15.28s and ends with three or four attackers alive. It improves cavalry counter hits and reduces received spear counter hits in the comparable Plains case (2→6 and 19→9), but leaves one or two defenders alive. Flank travel and withdrawal lose damage time: its longest gap between damage events reaches 7.05s, compared with 1.67s for the direct charge. Preservation and finishing are different outcomes.

All 15 cases record zero navigation failures, zero sustained navigation-stall unit-seconds and zero unanswered orders. Every order produces movement or attack state on the first 60 Hz step; this is simulation responsiveness, not touch/network latency. Severe friendly overlaps remain 1.5–11 pair-seconds per case, so this is not a claim of perfect packing. The exact mounted-staged Plains replay matches every report field after removing process-specific IDs and private user-directory paths.

## The two-survivor quiet ending

The Plains/River infantry cases have 28.283s without damage after the last hit at 31.733s. This is not a blocked path or invalid-target deadlock. The last Warrior is at (316.94, 1150.06), at its requested formation destination (320, 1152); the Archer is at (352, 1232), 89.12 units away. Both are IDLE, have no target, empty paths, inactive navigation, no forced move/attack and zero failed/stall repaths. Both can see the opponent. Warrior automatic acquisition reaches 64; the standing Archer can engage through 80+8=88 and is not permitted to chase.

There is a small concrete mismatch: Stand Ground acquisition searches through 80+16=96, then rejects targets beyond 88 and temporarily ignores them. The final Archer is in that ignore interval. This causes avoidable target reacquisition/churn while preserving the intended no-chase behavior. A separate focused patch could align the acquisition and engagement boundary without extending range; test distances 88/89/96, explicit attacks, attack-move and moving opponents. No such change is included here.

## Readability and next step

Two native 844×390 runs advance one rendered frame per tactical step so damage text and animations expire normally. Their measured combat events, damage, orders and final states match the corresponding headless cases exactly. At the recorded 1.25 zoom, role silhouettes, team colors, selection rings and recent-hit bars separate the two sides in the ranged screen. A fixed camera can crop a rider taking the upper approach; this is an observer-camera limitation, not a production camera regression. The fixture freezes match time/HUD updates, so HUD counts/time in these captures are not UI correctness evidence. No mobile FPS claim is made.

The strongest low-risk player-facing follow-up is a brief mixed-army staging lesson or feedback: use passive Move to assemble near the fight, then attack-move together. The two-order matched control is stronger evidence for this than automatically slowing cavalry or changing group movement. Keep scouting/selection and extra control meaningful. Separately, the Stand Ground scan mismatch is a narrowly testable cleanup; it should not expand engagement range or turn an intentional disengagement into forced combat.

## Reproduce and receipts

```sh
python3 tools/run_paid_tactical_plans.py --project <frozen-project> --output output/paid-tactics --maps 0 1 2 --seed 101 --jobs 3
python3 tools/run_paid_tactical_plans.py --project <frozen-project> --output output/paid-tactics-native --maps 0 --plans ranged_screen mounted_flank --render --jobs 1
```

The frozen project is a `git archive 009bed4` copy with these test tools added, locally `/tmp/aoem-paid-tactics-009bed4`. Each subprocess receives a unique private Godot user directory. All 15 final cases have the same loaded hash set, and every recorded runtime hash matches 009bed4. The compact [JSON receipt](paid_tactical_plans_metrics_2026-10-22.json) includes source hashes, all outcomes, costs/deposits, exact initial placements/orders and the final quiet-ending diagnostics. Full raw samples/events/logs are in `output/paid-tactics-20261022/final/`; deterministic repeat is under `repeat/`.

Native captures are in `native-stepped/`. They used the earlier paid purchaser before its final observer-registration synchronization; combat events/results are identical, but those opening banks/times are excluded from the final matrix. Earlier `early-infantry`, `first-three`, `verified` and `staged` runs are exploratory and excluded. Initial harness errors (a freed-object typed argument, same-frame observer overbuy, too-distant Archer destination and sparse rendered yields accumulating feedback) were corrected before the final matrix or final native captures. No runtime edits, commits or deployments were performed by this evaluation.
