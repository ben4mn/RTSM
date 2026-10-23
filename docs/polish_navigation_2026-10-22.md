# Navigation polish — 22 October 2026

## Observed friction

The parent playtest reproduced **P → Escape remaining paused** in the native game through MCP before implementation. Code inspection confirmed that Main stops processing while paused and the always-processing HUD only handled P. Escape also stopped doing anything after the last selection was cleared. Icon refresh replaced useful keyboard hints with short action names.

## Changes

- Escape closes one layer per press: secondary surface, placement, Build menu, armed order, area selection, selected objects, then match menu. Escape returns from the match menu.
- Settings keeps its existing one-layer Back behavior: Escape or P closes Settings and leaves the match menu open. The following press returns to play.
- P retains its direct pause/resume behavior. Pause and Help shortcuts no longer act behind a concluded match.
- Refreshed icon tooltips preserve P, B, Space, T, R, G, period and Escape hints. Repeated refreshes do not duplicate them, and existing concise accessibility action names remain intact. Move/Attack-move tooltips explain targeting and canceling; the pause menu and hotkey reference explain Back.

## Validation

All commands below exited 0 with no reported runtime errors or warnings:

- `Godot --headless --path . --scene res://tools/test_match_back_navigation.tscn`: **33 assertions** using actual viewport-dispatched keys in the real match. Covers Info/selection/armed orders/area selection, empty-field pause, P → Escape, nested Settings with Escape and P, Build Info and menu, placement cancellation without spending, refreshed tooltip hints, and game-over shortcut isolation.
- `Godot --headless --path . --resolution 844x390 --scene res://tools/test_build_menu_placement_transition.tscn`: preview, explicit paid placement, cancel/reopen and touch routing.
- `Godot --headless --path . --scene res://tools/test_hud_secondary_surfaces.tscn`: 12 phone/scale/inset profiles; surface exclusivity, modal cleanup and outside-touch containment.
- `Godot --headless --path . --script res://tools/test_menu_match_transition.gd`: menu Start, paid Feudal advance, Pause Quit, fresh-match state.
- `Godot --headless --path . --scene res://tools/test_audio_settings.tscn`: 12 phone/safe-area profiles, settings layout/scrolling, preferences and paused selection/camera behavior.

`git diff --check` passed. Headless checks establish behavior and layout contracts, not visual feel or physical-phone evidence. The parent owns integrated native gameplay and screenshot replay. No graphical process was launched by this subtask.
