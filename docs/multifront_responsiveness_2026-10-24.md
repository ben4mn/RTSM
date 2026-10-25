# Multiple-front responsiveness audit - 2026-10-24

This bounded follow-up preserves combat, movement, networking, production costs and action timing. It removes two measured sources of redundant interface work:

- HUD refreshes reuse the final command decoration when glyph/caption is unchanged. Caching the complete icon-to-cloth block prevents helpers alternating corner radii. Labels, accessible descriptions, badges, pressed/disabled states and hit targets still update. Area-selection arming updates state without rebuilding its fixed glyph.
- Construction recommendations refresh only when their value changes. Previously an ordinary selection/status update rebuilt hidden construction cards twice even with guidance disabled. Resources, age, housing, opening, placement and Info retain independent refresh paths.

## Active-world input audit

`tools/probe_multifront_interaction.tscn` loads real Main, stages two fronts (26 synthetic fighters plus the normal starting economy), disables AI decisions, and leaves unit movement/combat and paid production running. Actual ScreenTouch contacts exercise 844 x 390 at 115% UI scale and 1280 x 720 at 100%. The fixture selects, arms Move/Attack, orders destinations, saves/recalls two groups, opens Economy/Army, buys three Villagers per profile, uses minimap/Base and desktop group/M/F shortcuts. Destinations survive switching, unselected fronts fight, and all four starting workers continue their jobs. Before and final audits both pass 152 assertions.

Economy recruitment avoids selecting a producer. Army groups return to each front; desktop number keys recall directly, M selects fighters, F finds army and H selects Base. Touch group recall takes Army then Recall when that page was last used. Final actual contact release-to-observed-state samples: unit select 14-24 ms, accepted Move/Attack 16-22 ms, group recall 21-30 ms, Base 34-71 ms. Every action was accepted in the next observed frame; minimap acts on contact-down. These are local engine observations, not physical-device/browser/network latency.

Ten alternating synchronous SelectionManager.select_single calls per context separate handling cost from frame waits:

| Context | Before median(range), ms | Final median (range), ms |
| --- | --- | --- |
| Phone viewport, unit |71.52(65.61-103.98)|2.91(2.32-4.92)|
| Phone viewport, Town Center |79.18(75.72-146.80)|13.84(13.01-17.26)|
| Desktop viewport, unit |70.96(64.69-82.36)|2.91(2.35-4.60)|
| Desktop viewport, Town Center |81.47(77.98-97.36)|14.43(12.90-16.04)|

Causal subcalls: unchanged icons 15-31 ms to 0.08-0.13 ms; layout 18-33 ms to 2-4 ms. The remaining guidance call cost 24-29 ms after the first fix; the recommendation guard reduced it to 0.20-0.27 ms. Final synchronous samples were collected while a separate paid simulation could run; they are not an uncontended FPS comparison.

## Native rendered battle and limits

`tools/probe_native_busy_front.tscn` uses native Compatibility 1280 x 720 on RTX 3080: synthetic 50+50 and 100+100 armies plus normal actors, live orders/combat,5 s warmup and about 20 s sampling per case. Only this offscreen fixture bypasses background pause. Four real touch select/Move cycles run during each fight. Armies lose units naturally: this is a battle workload, not a constant 200-living-unit benchmark.

| Workload | Before mean/median/p 95 frame interval, ms | Command-decoration cache only, ms |
| --- | --- | --- |
|50+50|25.56/16.77/79.02|20.72/16.71/43.97|
|100+100, quiet local baseline|43.65/22.11/140.75|39.05/20.45/124.02|

All 24 after-cache touch actions were accepted next observed frame, but the large battle still reached 175 ms release-to-observed response and 220 ms worst frame. Do not call it uniformly smooth or 60 FPS. This native run predates the final recommendation guard; that guard is supported by synchronous measurements only. A diagnostic ablation of occlusion improved the large baseline to 38.24/18.66/127.64 ms: it contributes but is not the sole cause. The shipped observer and fog rules remain unchanged.

Frame intervals use the monotonic clock every frame. Godot process/physics performance-monitor fields are cached/coarse and must not be treated as per-frame CPU averages. Canvas object counts are not draw calls. No physical-phone, browser-rendering, public-network or sustained late-game performance is established. Larger fights still need profiling; no broad engine/balance change is included.

## Correctness

All passed:

- test_field_interface: three civilizations; progress, paused Guide, repeated armed/enabled/stance/pause transitions, stable style identity and 48 px targets.
- test_command_icons:38 glyphs, names, theme/override state and badges.
- test_mobile_hud_composition:13 phone/scale/notch profiles, rail/dock, paid production, placement and pause.
- test_selection_dock_geometry:848 assertions, eight phone/scale/safe-area profiles, queue, coalesced selection and resizing.
- test_contextual_hud_touch:four actual ScreenTouch phone/scale profiles.
- test_build_menu_age_ownership:unchanged recommendation style identity, changed/cleared highlight, independent resource shortage/recovery, own/enemy age and Info.
- test_build_menu_mobile_layout:12 phone profiles, unlocks, scrolling and target readability.
- test_build_menu_placement_transition:preview, explicit Place, cancel/reopen and no spending from preview touches.
- test_mobile_production_feedback:eight desktop/phone/scale profiles, actual Queue/Train/Undo/Clear, refunds, scroll, repeat shortages/housing and age locks.
- test_guided_optional_actions:12 phone/scale/notch profiles, paid Age Up, placement/gather authority and pause/layout refresh.

Compact before/after metrics and two native battle screenshots are saved under the task output verification directory. The probe uses synthetic armies/funds; paid pacing and AI have separate evidence.
