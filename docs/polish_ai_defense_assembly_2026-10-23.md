# Remembered-defense crowding — 2026-10-23

The subsequent `native-final-combined` River match removed the freed-target errors and recorded no long travel stalls, but still exposed ten severe pair episodes among five idle AI fighters at 397.42–399.42s. Three Warriors and two Archers occupied tile (56, 12), around world (1440, 1104), with sampled pair distances of 0.17–6.11 pixels. This was a different location from the earlier ordinary staging pile. That native attempt remains intermediate evidence, not acceptance of the final defense change.

The normal AI's remembered-threat branch, `_rally_defense([])`, bypassed the new assembly allocator. For twelve seconds after losing a home threat, it sent every non-attacking fighter to the identical attack-move point. Its existing-order check recognized only MOVING units near that point, so each IDLE arrival was sent there again. It also retained an old plain Move toward that point, even though plain Move suppresses automatic engagement. The native record does not include the AI decision at each contact, so that branch's attribution to this exact encounter is inferred. The same production branch reproducibly creates the same pile at the exact River tile.

The bounded fix reuses `_move_to_assembly_slot` with an optional attack-move intent flag; its default remains ordinary Move. Only remembered-defense investigation supplies the new flag. The helper uses the existing planner's current/pending friendly occupancy, retains matching unoccupied in-flight goals, converts inherited plain Move or shared attack-move goals, and issues `command_attack_move_path` to separate reachable local slots. Settled, uncrowded defenders remain idle. An actual fight is still skipped by this branch; visible threats still receive the existing matchup-selected attack targets. The twelve-second memory, strategy priorities, difficulty stance, worker handling, human commands, and other attack orders are unchanged.

The same hold radius and bounded planner limits apply. A friendly traveler occupying an accepted destination at a later decision can cause reallocation; stable-order checks cover unchanged occupancy, not every possible traffic change. A full or sealed local area retains the existing bounded Stop/hold behavior rather than inventing a common fallback destination. There is no new per-frame allocation or reservation registry.

## Reproduction and checks

`tools/test_ai_defense_assembly_2026_10_23.tscn` loads actual Main and River Crossings seed 101, using a declared synthetic roster of three Warriors and two Archers. It sets a remembered threat at the observed tile (56, 12), whose canonical world coordinate is (1440, 1104), and enters the normal decision branch. Initial orders include a plain Move and inherited common attack-move goals. The original and candidate AI use the same fixture.

| Result | Original branch | Candidate |
| --- | ---: | ---: |
| Minimum pending goal distance | 0 px | 32 px |
| Minimum settled pair distance | 0.306 px | 31.755 px |
| Arrived fighters | 5/5 | 5/5 |
| Failed assertions | 7 | 0 |
| Script errors | 0 | 0 |

Candidate passes 6,316 assertions, including normal speed and solid-terrain checks, in-flight route progress under repeated decisions, settled stability, conversion from plain Move to attack-move, actual visible target assignment, preservation of an ongoing windup, target deletion, a newly blocked endpoint, and memory expiry. Baseline fails the spacing, intent, stable-arrival and blocked-endpoint expectations. Roster and threat setup are synthetic; this is not paid production, a full match, or a performance comparison.

Eight existing regressions also pass without errors: the original paid AI assembly fixture, strategic policy, Easy learning pressure, attack-wave recovery, recovery composition, live vision, paid production rally spacing, and actual group-order endpoints. The UI agent independently reviewed the runtime diff and found no blocking issue. Final native matches and exclusive performance remain separate root-owned gates.

Frozen AI SHA-256: `7e972a7d0dc6dea440e3c8671c93029198c397dfb8ce70d6be1d0232c111b768`. No UnitBase or shared planner changes were needed in this cycle. Evidence: `output/polish-ai-defense-assembly-2026-10-23/{baseline,candidate,validation}.json` and matching logs. All new test runs used a private headless project; no graphical or root-project Godot was launched by this agent.
