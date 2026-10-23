# One assigned worker per Farm — 2026-10-22

Each active Farm now reserves one worker when its gather order is accepted. The reservation spans approach, harvesting, cargo delivery, return, and temporary automatic retreat. A second worker's rejected order preserves its prior work and exact carried resources. Natural resources remain available to multiple workers.

`BuildingBase` owns a weak worker reference with constant-time availability checks. `Villager` releases its reservation on an accepted replacement order, construction, death, leaving the scene, or invalid resource recovery. Manual Move/Stop releases the slot; automatic delivery/retreat preserves it. A builder may resume its old Farm only if the slot remains available. Destroyed or freed Farms cannot retain productive claims. Raw resource validity remains independent of occupancy so input can identify an occupied Farm and explain the rejection.

Nearest-resource and path-aware discovery skip occupied Farms unless the caller supplies their assigned worker. AI Farm completion cannot assign a second farmer. When current-visible food has no available work slot, AI may request additional normally paid Farms up to its existing food-worker target, capped at 12; the existing military-building priority still applies. No resource grants or worker income multiplier were added.

## Verification

`tools/test_farm_single_worker.gd` uses real Farm/Villager/AI APIs, canonical GameMap conversions, real paths, and solid building footprints in a revealed grass fixture. It manually steps two exact ten-food deliveries; it is a transaction/navigation regression, not an ordinary income or match-performance measurement. It verifies simultaneous-group rejection, old wood cargo, owner-aware lookup, real approach/delivery/return, natural multiworker gathering, manual replacement, construction resume without stealing, temporary retreat, death, free, destruction with earned cargo, and AI capacity recovery.

The focused fixture and 12 existing compatibility checks pass without engine errors or warnings:

- `test_farm_economy`, `test_farm_depletion_feedback`
- `test_ai_economy_recovery`, `test_ai_resource_deficit_search`, `test_ai_exploration_recovery`, `test_compact_ai_policy`, `test_ai_construction_timing`
- `test_resource_fog_targeting`, `test_resource_production_rally`
- `test_autonomous_navigation_recovery`, `test_building_perimeter_work`, `test_paid_builder_cargo_return`

Two old fixtures were updated for the requested rule: AI recovery now first proves an occupied Farm keeps its farmer, then releases that worker before testing a loaded replacement; perimeter recovery supplies the assigned requester when rediscovering its own Farm. Logs are retained under `output/polish-2026-10-22/farm-single-worker/`.

Native Farm UI/group-command verification and ordinary-match pacing remain root-coordinated checks. This document does not claim either from the headless fixture.

## Command integration

`tools/test_farm_command_integration.gd/.tscn` now verifies the rule through the real Main scene. It spends 75 Wood for a selected worker to build a Farm, physically gathers the rejected follower's old wood cargo, dispatches the SelectionManager gather signal for three workers, and verifies both partial-success and fully-occupied HUD messages. Strategy allocation finds another visible food source; an explicit temporary fog fixture verifies that an occupied Farm alone does not create a second work slot, then restores every changed fog cell.

The test calls the real network adapter's authoritative command handler: a completely refused occupied-Farm order returns the existing rejection message; a group order to a newly free Farm assigns exactly one worker. It does not exercise transport or claim a two-client session. Online/enemy Farm Info deliberately shows static one-worker capacity because replicas do not contain reservations.

A production-rally gap found in this audit is fixed in Main: a newly trained worker whose observed Farm is unavailable searches current-visible, reachable food through the requester-aware lookup. Hidden position-only rallies and exact natural-resource identities retain their existing behavior. The integration test spends another 50 Food through the ordinary TC queue and verifies this alternate job without stealing the existing farmer. `test_resource_production_rally` passes its hidden/depleted natural identity checks; `test_strategy_cargo` passes exact cargo preservation and single-worker reallocation.

The integration fixture passes headless without errors/warnings. A native invocation writes three full-map screenshots under `output/polish-2026-10-22/farm-commands/`. Add `-- --hold-native` to leave the normally paid scene live for manual group input; AI decisions stay paused while workers resume ordinary processing. No native launch was performed by the test author. Headless logs are retained under `output/polish-2026-10-22/farm-single-worker/` with the other Farm evidence.
