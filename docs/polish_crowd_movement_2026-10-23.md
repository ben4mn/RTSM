# Crowded route points, 2026-10-23

This pass addresses travellers converging through workers standing on intermediate route points. Worker service-position allocation is a separate Villager change. UnitBase retains its existing public navigation API, final arrival checks, movement speed, separation limit, combat timing and bounded unreachable retries.

The baseline disables separation within 10 world pixels of every mandatory route point. A worker standing at that point therefore draws a passing unit back through its center. The new regression reproduces exact overlap in one-tile House and Barracks gaps, using the actual GameMap and Pathfinding.

Intermediate points occupied by a nearby ally can now be passed within 24 pixels if the next route segment is clear. Final destinations are never skipped. Nearby allies come from the existing throttled separation scan. Separation remains active near intermediate points; each actual movement step checks solid cells and diagonal corners, and sideways steering must preserve a clear segment to the next point. The latter check prevents slipping behind a corner after an initially safe shortcut. Short ordinary steps use the convex adjacent-cell case; longer segments sample every four world pixels with orthogonal corner checks.

## Evidence

`tools/test_crowd_movement_2026_10_23.tscn` uses a cleared synthetic patch in the real map, free units/buildings, and variable simulation deltas. It covers all 2×2/3×3/4×4 building pairs in both grid directions with one- and two-tile gaps, six unit roles, stationary workers, coincident/opposing movers, an occupied corner and an arriving stream. Every simulated step checks speed and 17 points along the traveled segment against solid tiles. Separate large-delta stress checks reject diagonal corner cutting and movement through a blocked tile to a clear endpoint; reopening restores movement.

| Measure | Baseline | Candidate |
| --- | ---: | ---: |
| Single routes arrived | 216/216 | 216/216 |
| Opposing mixed-crowd routes arrived | 432/432 | 432/432 |
| Crowd navigation failures | 0 | 0 |
| Summed pair-seconds below 8 px | 341.000 | 18.974 |
| Summed pair-seconds below 1 px | 5.146 | 0.180 |
| Stationary-worker lane minimum center distance | 0–3.304 px | 12.457–12.699 px |
| Slowest opposing crowd completion | 24.672 sim s | 23.952 sim s |
| Occupied-corner / arriving-stream arrivals | 8/8 + 4/4 | 8/8 + 4/4 |

Thirteen headless suites pass: this matrix, navigation/range, live congestion, autonomous navigation recovery, group movement, combat spacing, repeated attack orders, moving-target pursuit, mobile commands, proactive worker threats, raid recovery, paid building perimeter work, and the combat progression matrix. The latter retains 22,007 numerical checks. The first perimeter invocation used a nonexistent scene name; that launch was excluded, retained in the validation record, and followed by the correct passing scene.

The first private candidate passed the lane matrix but failed one additional occupied-corner arrival: safe shortcut selection alone allowed later steering to hide the next waypoint behind a solid corner. It was rejected. The route-visibility guard fixes that case; the rejected report remains in the evidence directory.

Reports, source hashes and logs: `output/polish-crowd-movement-2026-10-23/`. Baseline UnitBase SHA-256: `8f7e56dc05e332b4ba62b6a124104e23edd6ae05520547e332bbf67214842990`. Integrated candidate: `4f10fbcd7c0829fa5ff0581d146064781718f6c54e897477833e059aff290b13`. Both comparison runs use the same regression source hash. An independent read-only review found no concrete lifecycle or geometry defect and identified the additional segment checks as the remaining native performance question.

## Limits and integration

This is center navigation with soft unit separation, not hard-circle physics. One tile is about 28.62 world pixels across the lane; configured unit diameters reach 36 pixels. Brief overlap remains in dense crowds, and the results do not establish zero visual contact, paid-economy throughput, balance or rendered performance. Existing escape behavior for a unit already inside a newly blocked cell is preserved. Shared final destinations are not reassigned by UnitBase.

Only UnitBase and this new fixture were copied from the private stage into the working tree. No root-project or graphical Godot process was launched for these tests. Combined Villager integration, native full matches and the exclusive dense performance comparison belong to the parent validation pass and were pending when this note was written.
