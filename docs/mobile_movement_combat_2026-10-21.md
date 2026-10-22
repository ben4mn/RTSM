# Movement and combat verification — 2026-10-21

## Command contract

| Touch/order | Runtime behavior |
| --- | --- |
| Tap open ground | Passive movement. No automatic acquisition or retaliation until arrival, failure, or another order. |
| Hold open ground for 350 ms | Attack-move. Engage visible enemies and resume the accepted formation destination afterward. Release cannot duplicate the order. |
| Tap an enemy | Explicit attack. Remains the priority even when another enemy attacks the unit. |
| Idle military | Prefer enemies attacking friendly forces, then armed military, then other targets; siege preserves its building preference. |
| Stand ground | Automatic engagement does not chase. Explicit attacks can still approach their target. |
| Pan, pinch, OS cancellation | Cancel the pending world command. Returning the finger to its initial position does not revive a canceled hold. |

Autonomous pursuit uses a leash of at least 128 world units, extended for longer vision/weapons, and at most six seconds of continuous chasing. A guard returns to its engagement origin after abandoning pursuit. Attack-move and patrol resume their original destination. Targets already in weapon range are retained rather than switched on every scan. Explicit attack orders are exempt from the autonomous leash.

Orders briefly preview the existing navigation route, fade between 1.4 and 2 seconds, and disappear. Reselecting a moving unit offers another brief preview. The overlay never asks A* to invent a route and shows at most three formation route groups.

## Reproduced defects and fixes

- [x] Damage during attack-move called the explicit attack API and lost the original journey. Retaliation now preserves attack-move/patrol intent.
- [x] Retaliation replaced an explicit building attack and bypassed stand-ground limits. Both now obey the same command priority as unit attacks.
- [x] An autonomous pursuer could follow a faster enemy indefinitely. Bounded pursuit and return-to-guard behavior prevent this.
- [x] Nearby active attackers lost priority to unarmed distractions. Threat-aware acquisition and restrained retargeting now address nearby fights.
- [x] Soldiers could not attack a Town Center from its only reachable far edge because range/navigation used its corner anchor. Acquisition, approach and impact now use the existing footprint/perimeter APIs.
- [x] A paid seed-424242 match produced Archers that never fought. Tracing proved their spawn tiles were in disconnected two-cell pockets beside boundary Archery Ranges. Egress now selects the largest reachable region among its existing three-ring candidates, preserving nearest-ring/rally-distance preference within that region.
- [x] Network slot 1 was rejected by the group planner's local-player filter. Planning now accepts an explicit owner while preserving owner 0 as the local default.
- [x] Route changes lacked an invalidation signal for worker drop-off caches. `Pathfinding.walkability_revision` increments only on actual obstacle changes.

## Executed checks

Godot 4.6 headless checks completed without script errors; the intentional sealed-producer warning is noted below:

- New `test_combat_order_priorities`: actual damage dispatch, passive travel under fire, retaliation/resume, explicit unit/building priority, stand ground, bounded chase and nearby threat acquisition. Its new assertions reproduced the defects before the fixes.
- New `test_navigation_live_congestion`: actual GameMap conversion, A* and UnitBase motion on synthetic terrain. All 20 units traversed a single-cell gap and arrived in 16.9 simulated seconds; minimum final spacing was 28.95 world units. A newly blocked waypoint rerouted successfully. A soldier damaged the Town Center from its reachable far edge; that assertion failed before the footprint fix. Local CPU time was about 86 ms for the stepped congestion case, not a phone performance measurement.
- `test_world_hold_real_time`: actual `Input.parse_input_event` and Main dispatch at 844×390 and 932×430. Tap, real-time hold, release deduplication, pan-return, pinch, and OS cancellation passed. One injected military unit isolates intent; it is not a paid training test. Existing real-time timing at 0.5×/1×/2×/3× simulation speed, emulated-mouse suppression, GUI ownership, focus/resize cancellation and selection replacement also passed.
- New `test_production_egress_connectivity`: the boundary pocket reproduced both disconnected egress and failure to reach the battlefield before the fix; afterward the Archer naturally reached its destination. Existing `production_rally_spawn` and `production_rally_spacing` also passed; the sealed-producer test emits its expected refund/failure warning.
- `test_group_order_endpoints`: ordinary starting workers, natural movement and actual touch dispatch at both phone sizes; every worker arrived at its distinct accepted endpoint.
- `test_command_path_feedback`: obstacle detours, live progress, two-second fade, reselection, no feedback A* calls, arrival/death/Stop cleanup, explicit attack-move destination retention and three-group cap.
- Existing `force_move_engagement`, `group_movement_combat_scale`, `navigation_and_range`, `military_roles_and_timing`, `autonomous_navigation_recovery`, `combat_damage`, `simulation_target_cooldowns`, `paid_siege_acquisition`, `group_order_topology`, `mobile_unit_commands`, `touch_military_resource_routing` and `touch_long_press_context` passed.

The paid AI-vs-AI seed-424242 run immediately after the egress fix, with ordinary resource spending, ended naturally at 390.12 simulated seconds (6:30) after a three-minute Sacred Site hold. First contact was 148.9 seconds. Warriors landed 71/22 hits, Archers 52/14, and Horsemen 32/6 for players 0/1. Before the egress fix, Archers landed zero hits on both sides in this seeded opening. The later final run including the shortest-perimeter drop-off refinement ended at 401.93 seconds (6:41), with first contact at 151.8 seconds and Archer hits of 51/15; see the economy receipt for exact source hashes. These corrected runs logged no script/runtime errors. They are automated opponent witnesses, not hands-on play or a broad multi-seed balance study.

These are automated runtime and input checks on macOS. They do not establish physical-device touch feel, mobile GPU performance, or internet deployment success. Those require the separate rendered-play and multiplayer evidence in the overall task report.

## First-open management panel follow-up

A public browser screenshot exposed an oversized Economy background on its first opening. The previous journey helper reapplied HUD layout every frame, masking the bug. New `test_strategy_first_open` overrides that helper and uses actual ScreenTouch dispatch with only the runtime's queued layout. Before the fix, all four 844×390/932×430 and 1.0/1.15-scale cases retained a 480×1652 panel at y=0, even after the content minimum settled to 263 pixels.

StrategyOverview now requests the HUD's existing coalesced deferred layout only when the visible panel's measured minimum changes. This lets wrapped labels settle at their actual width without rebuilding layout for each snapshot. The unchanged regression passes headless and native Metal rendering: Workers is 310 pixels high at normal scale and 263 at 1.15; Train is 310/259; Info is 240. Five repeated snapshots preserve the producer control rectangles. Native first-open screenshots were inspected and copied to `output/mobile-online-2026-10-21/first-open-native/`; no test-side layout calls were used. The separate paid-control journey remains responsible for purchase/Repeat/refund interaction checks.
