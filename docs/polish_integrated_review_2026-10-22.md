# Integrated production review — 2026-10-22

Reviewed the current runtime diff in Main, HUD, Build Menu, UnitData, and UnitBase, with focused attention to live recruitment blockers and unarmed Scout commands. No high-risk runtime regression was established by this review. The combat agent's pathfinding and repeat-attack checks remain the primary validation for combat timing.

## Scout command and tooltip checks

- `test_scout_order_feedback.tscn` passed against real Main/SelectionManager/UnitBase dispatch: single and all-Scout groups reject direct unit/building attacks with the unarmed explanation; the old move order remains intact; same-role group Info retains the explanation; mixed Warrior/Scout groups can still attack; explicitly armed Move to an enemy remains a move.
- Recruitment hover and Info share costs, timing, paid population, queue capacity, and resource deficits. The selected producer refresh preserves Button identity and failed-purchase taps. Existing phone composition and touch-input tests passed.
- The added Scout explanation measured 661px at the UI's 16px Barlow body font, wider than the 632px effective phone layout. The approved sentence break after “Sacred Site.” fixes that specific width risk.
- Four old role-wording assertions expected `Recon`. They now require the current unarmed/vision description in economy, strategy Info, match-pointer, and mobile-readability checks.

## Economy fixture preference leak

An initial current-workspace `test_economy_resilience` run reported a late worked-food warning. A frozen HEAD archive, using its own copied import cache, passed all twelve profiles on Open Plains. One-profile diagnostic comparisons then showed both frozen HEAD and current runtime had the same correct facts on that map: 20 food worked by two workers at the same source.

The frozen HEAD test reproduces the warning assertion failure when launched with `AOEM_MAP_ARCHETYPE=2` (Woodland Flanks). That map's starting food workers use different sources: the fixture reduces one to 20 while the other retains 200. Runtime reports 220 total worked food and correctly withholds a low-food warning. River Crossings also passed. This establishes an existing map-preference dependency in the fixture, rather than a production warning regression.

The test now pins Open Plains while executing its known single-source scenario, then restores the previous in-memory archetype before exit. It never saves player preferences. Production economy behavior is unchanged. The final current-workspace run with `AOEM_MAP_ARCHETYPE=2` passed all twelve profiles, confirming independence from the incoming map preference. A normal current-workspace rerun also passed.

## UID scan warnings

The already-running editor logged four unrecognized IDs for newly added test scripts. A fresh read-only headless process recognized all four IDs **before loading any corresponding script**, each mapped to the correct file. There are no duplicate UID groups in active `tools/`, `scripts/`, `assets/`, or `addons/` sources. This supports stale editor-memory scan state, not invalid IDs. No UID or cache files were changed for this investigation.

The warning IDs were `uid://u7th14a7s1d6`, `uid://ne2mxx2r3aft`, `uid://ltu4vwjxp434`, and `uid://d37rqhry8gswe`. Archived source snapshots under ignored output directories were excluded from active-source duplicate analysis.

## Final fixture desk review

No further engine processes were launched for this review while native paid matches were active. Recruitment cleanup cancels its paid queue before freeing both producers and the SubViewport. Scout-order cleanup frees the complete Main scene and its child units, selection, map, and AI. The art fixture frees each contract viewport and native gallery map. Every fixture terminates its own SceneTree after reporting results.

The new fixtures do not call `save_preferences`; their audio setters only change the running process. Their temporary GameManager fields are process-local because each fixture exits. The economy test additionally restores its incoming archetype explicitly. Native capture output is kept under the ignored `output/` tree, and headless mode skips rendering waits.

The editor-generated `tools/test_scout_order_feedback.gd.uid` is present (`uid://lbwyesloa8l1`) beside the new test source and should be retained with that test. No UID was invented or rewritten by the review agent. The recruitment native receipt records sixteen captures and no failures; the coordinating agent inspected its phone shortage, phone population Info, and desktop ready views.
