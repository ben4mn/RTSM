# AI assembly positions, 2026-10-23

The first native Plains run with the worker/movement fixes completed normally at 562.26 game seconds, with no navigation failures or qualifying long travel stalls. Its contact observer nevertheless recorded 69 long proximity episodes, including 56 idle military episodes below eight pixels. These are observed center distances, not hard-body collision failures.

The main production-AI pile was at tile `(58,14)`: 31 sub-eight-pixel idle contact records, beginning at 114.4 seconds. Ordinary staging and Easy reserve recall sent each fighter to the same `_staging_point`, overwriting the separate destinations already allocated by Main's production-rally code. A later Farm blocked the old assembly tile; six further close idle contacts appeared at `(57,13)`. UnitBase correctly preserved final Move destinations and did not move idle units by itself, so travelling separation could not fix those order endpoints.

## Scoped change

AIController now uses the existing GroupOrderPlanner for ordinary staging, Easy recall, base reserves and retreat. The planner sees owned living positions and pending Move destinations; there is no second reservation cache. Existing valid in-flight assembly orders are retained. Clear settled positions within the hold area are retained with normal arrival tolerance. Death and retasking release pending occupancy through the same live-state checks. Newly blocked positions are replanned on a policy call.

GroupOrderPlanner gains one optional destination predicate, applied before candidate sorting/path selection. AI uses it to keep new destinations within the existing 64-pixel staging/retreat and 56-pixel reserve areas, with four pixels reserved for arrival tolerance. Ordinary human group commands omit this argument and retain their existing behavior. A full or sealed area does not fall back to a shared point: idle units hold, and an obsolete active assembly/recall order is stopped. Planning runs on AI command decisions, not every frame.

Strategy timing, squad thresholds, stances, target selection, exact unit Move APIs, worker/Farm positions and production costs are unchanged. The learner fixture's separate early/recovery commands to its base remain unchanged; those fixture-specific contacts are not evidence against the production-rally allocator. Common field attack destinations and combat spacing are outside this assembly change.

## Reproduction and validation

`tools/test_ai_assembly_2026_10_23.tscn` loads the actual Main/GameMap. A fixture Barracks produces five Warriors through its real queue, paid entirely from the ordinary AI opening bank: 250 Food and 100 Wood. The bank moves from `{food:250, wood:250, gold:100}` to `{food:0, wood:150, gold:100}` and population reservations are consumed once. The Barracks and later mixed roster/obstacles are synthetic fixtures; this is not an economic full-match benchmark.

| Minimum center distance | Baseline | Candidate |
| --- | ---: | ---: |
| Main's pending production rally destinations | 32.00 px | 32.00 px |
| Pending destinations after AI recall | 0.00 px | 32.00 px |
| Five paid Warriors after settling | 0.83 px | 27.31 px |
| Six mixed units after ordinary staging | 1.06 px | 30.38 px |
| Six mixed units after base reserve movement | 0.28 px | 32.28 px |
| Six mixed units after retreat | 1.14 px | 32.22 px |
| Six mixed units after a late Farm blocks assembly positions | 1.14 px | 29.29 px |

The candidate passes repeated-decision checks that preserve state, destination and path progress both in flight and after settling. It also passes fractional-anchor bounds, occupied-area exhaustion, in-flight reservation, death/retask release, blocked-terrain rejection and reopening, speed and sampled solid-crossing checks. All five paid fighters and all six mixed-role fighters finish their candidate routes. The baseline's `arrived` field counts only idle positions within 4.1 pixels of the literal requested goal; an unsnapped common staging request can legitimately finish at a nearest tile farther away, so that field alone must not be treated as a baseline navigation failure.

Independent review caught two issues before integration: mock maps needed the planner's complete capability guard, and post-filtering only the first returned destination could reject a valid alternative around a fractional anchor. Both were corrected. The optional predicate now rejects out-of-area candidates before path selection. The focused fixture and existing Easy-pressure/strategic-policy tests pass privately. The parent owns the subsequent integrated AI/group/rally suite, native three-map replay and exclusive performance comparison.

Evidence: `output/polish-ai-assembly-2026-10-23/{baseline,candidate,validation}.json` and logs. The exact baseline and candidate use the same fixture source. Frozen AIController SHA-256: `0d80e8a3d354cc2e5fd3e438b887a8d5b0a59f076883cc392ada53b3330c2edc`; GroupOrderPlanner: `7dbbaa059193273934ddc7a7b407311cecb79475ca9ce6b0e67cd9963cb2ce12`. No root-project or graphical Godot process was launched for this regression. No claim of zero overlap or native performance follows from these headless results.
