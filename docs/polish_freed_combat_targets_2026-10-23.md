# Freed combat targets — 2026-10-23

The rejected `native-assembly-final` sweep exposed a target lifetime error, not evidence that A* needed another movement change. Its engine log contains 777 `Invalid type in function '_is_valid_target'` errors: 480 at `_process_attacking`, 292 at `_consider_nearby_threat`, and five at `respond_to_attacker`. By the preceding progress markers, 16 occur after River 450.82s, 623 after River 481.01s, and 138 after Woodland 481.26s. The engine exited normally, but the launcher correctly rejected the run for script errors. Keep this attempt as failed evidence.

In Godot, passing an already freed Object handle to a `UnitBase` parameter fails before the function body executes. The existing `is_instance_valid` guard inside that function therefore could not protect it. An attacking unit repeatedly aborted before clearing its old target and route. The building validator had the same unsafe parameter boundary even though the native errors named unit targets.

Only the two lifetime predicates in `scripts/units/unit_base.gd` changed: accept `Variant`, reject invalid instances or the wrong class, then narrow to typed unit/building locals. Visibility and dead/destroyed checks remain the same. Movement, speed, collision, attack timing, damage, and selection policy were not changed. Frozen UnitBase SHA-256: `c3786684c2a0d81ed7c8f0c9be4947d1432b6272ace4d2911684410b6b57327b`.

## River observation and attribution limit

The River observer flagged one Warrior and two Archers at 491.33–492.73s, near tiles (55–56, 13–14), with ATTACKING state and three remaining route points. It recorded a maximum low-displacement episode of 14.81s and no navigation failures. The screenshot `river-phone-11-long-travel-observation.png` shows spread-out fighters near trees; it does not establish an obstructed building passage or a severe overlapping crowd.

The observer already hides ordinary in-range unit combat. Its stale route signature is reproduced by the freed-target bug: the old runtime leaves both Warrior and Archer in ATTACKING with three public route points after real target deletion, while the fixed runtime clears the route and either idles or resumes its authorized attack-move in one update. The script errors occur during the same late River interval. This is strong evidence for the lifetime failure as the cause class; the native samples did not record target IDs or cooldowns, so attributing every flagged unit to that error remains an inference. No geometry or steering adjustment is justified by this record alone. A clean final native sweep is a separate gate, owned by the root agent.

## Focused verification

`tools/test_freed_combat_targets_2026_10_23.tscn` uses real unit/building scenes in a declared synthetic navigation arena. It queues target deletion and waits for actual freeing; simply marking a target DEAD would not reproduce the defect. Its 16 cases cover Warrior/Archer, unit/building target, pursuit/windup, and explicit attack/attack-move resume. It also covers retaliation after an autonomous target has been freed.

| Same fixture | Baseline | Candidate |
| --- | ---: | ---: |
| Exit status | 1 | 0 |
| Script errors | 37 | 0 |
| Failed assertions | 17 | 0 |
| Completed assertions | 122 | 138 |
| Recorded matrix cases | 16 | 16 |
| Removed unit target's remaining route | 3 points | 0 points |

The baseline aborts at its typed validator calls, so 16 direct validator assertions do not execute; this explains its lower assertion count. Each case still cleans up its arena. Candidate: all 138 assertions pass. The same fixture hash appears in both JSON reports.

Seven additional private headless regressions passed with no engine errors: repeated attack orders, moving-target pursuit, combat order priorities, combat spacing, combat damage, progression matrix (22,007 checks; 11,520 damage cells; 48 paid progression states), and simulation-time target cooldowns. Independent read-only review by the UI agent found no additional issue in the boundary change. These are correctness checks, not native performance measurements. The private stage retains the preceding Villager revision; the root's final combined native sweep separately includes the latest worker occupancy change.

Evidence is in `output/polish-freed-combat-targets-2026-10-23/`: `baseline.json`, `candidate.json`, their full logs, and `validation.json` with the seven regression logs. No root-project or graphical Godot was launched for this work.
