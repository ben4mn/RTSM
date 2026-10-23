# Independent gameplay review — 2026-10-22

Reviewed the combined working-tree changes to Farm reservation/discovery/order handling, AI building spacing and resource capacity, pursuit/repeated attack commands, effective combat stats, new building presentation anchors, map generation order and online catalog negotiation. No additional reproducible runtime defect was found in this review. No production file was edited as part of it.

## Fresh editor/parser check

Created a complete private source/assets/addons/scenes/tools stage with **no copied `.godot` directory**. The stage uses a private user-data directory and a unique MCP port, leaving root's native session and player preferences alone. Godot 4.6 `--headless --editor --quit` completed with exit0 and no error/warning lines. Its 786-line import log includes the class/resource import sequence.

The old `manual-integrated/editor.log` contains a failure to resolve `test_worker_raid_recovery.gd`, followed by many `Villager: Cyclic reference` diagnostics in `test_worker_proactive_threats.gd`. Those errors did **not** recur in this fresh import. Both worker test scenes subsequently parsed and passed from the fresh stage: 14 proactive-threat cases and 17 raid-recovery cases. The menu and actual Main scene also booted cleanly. This disproves a deterministic fresh-import failure for the reviewed source snapshot; it does not establish the exact cause of the earlier editor incident or rule out every live-reload sequence.

The stage and exact original script hashes are recorded in `output/polish-independent-review-2026-10-22/stage.json`. `review-receipt.json` verifies that the staged GDScript contents did not change during import/tests and collects the result lines. No graphical/editor window was launched; the editor process used headless mode.

## Reviewed boundaries

- Farm reservation is acquired before replacing the prior order, so rejected group followers preserve cargo and work. Delivery and temporary recovery preserve the farmer; accepted manual replacement, construction, destruction/death and scene exit release it. Construction resume rechecks capacity and cannot steal a replacement farmer.
- Autonomous resource discovery distinguishes raw target validity from available worker capacity, passes the requesting worker through recovery paths, and checks visibility before reading target state. The assigned farmer can rediscover its own Farm. Occupied Farm production rallies recover to visible reachable food; natural hidden-rally identity semantics remain protected.
- Online commands enforce reservation on authority. Replica snapshots deliberately do not carry reservation identity, and HUD avoids claiming that an online Farm is free. Strategy allocation is sent to authority. This review ran authoritative handler integration; it did not repeat a complete two-client rendered match.
- Automatic one-tile building spacing consults owned footprints and preserves manual placement/walling. It prevents the reconstructed paid-growth courtyard closure and keeps bounded failure when the base has no spaced location. A tile gap is not a general proof of connectivity around arbitrary water/terrain; the code and documentation do not claim one.
- Repeated valid attacks retain in-progress strikes/routes while replacing movement intent. Different targets and Stop/Move still cancel. Moving-target path refresh preserves failure bounds for sealed targets; in-range retained routes are hidden from path display and cleared after target loss.
- World-art scaling remains separate from collision, navigation, range and damage. Defensive-fire attachment transforms source pixels without changing logical attack distances or deadlines.
- Map generation keeps the original Open Plains branch ordering, while River/Woodland place random resources after route carving. Catalog2 advertisements cause old/absent/mixed/unknown peers to fall back to unchanged Plains on both existing server generations. The existing map report already contains35 identical Plains hashes and actual local WebSocket checks in both server directions; source inspection found no missing negotiation branch. This review did not claim to rerun that socket matrix.

## Focused rerun results

All16 runtime tests/probes below passed from the same fresh stage, with no engine errors or warnings:

- `test_worker_proactive_threats`, `test_worker_raid_recovery`
- `test_farm_single_worker`, `test_farm_command_integration`, `test_resource_production_rally`
- `test_repeated_attack_orders`, `test_moving_target_pursuit`, `test_group_movement_combat_scale`
- `test_ai_building_clearance`, `probe_navigation_native_stall`, `test_navigation_failure_feedback`
- `test_building_perimeter_work`, `test_ai_economy_recovery`, `test_ai_construction_timing`, `test_compact_ai_policy`, `test_shared_technology_rules`

`test_building_perimeter_work` includes two genuinely paid interrupted Farm/Range arrangements, physical movement/build progress, cargo delivery, and a paid House that blocks the worker's old endpoint. Both completed; one preserved15 original wood, and each deposited15 Farm food. It used ordinary frame processing at its fixture's4× time scale; these are correctness checks, not frame-rate or match-balance evidence.

Four SceneTree tests were initially invoked with nonexistent `.tscn` paths. Those launcher errors are retained under `invocation-errors/`; the corrected `--script` runs passed and are the final logs above. They were invocation mistakes, not source parser failures.

The fresh import plus menu/Main boot logs and all16 result logs are under `output/polish-independent-review-2026-10-22/`. Every owned process completed. Root's separate native full-match and final rendered review remain necessary for appearance and game feel; this audit makes no substitute claim.
