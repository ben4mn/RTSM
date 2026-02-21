# Phase 4 Baseline Gameplay Report

Date: 2026-02-16
Project: `/Users/ben/Documents/1_Projects/aoem`

## Commands Run

```bash
/Applications/Godot.app/Contents/MacOS/Godot --version
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1
# Background editor session for MCP bridge
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -e
python3 tools/mcp_smoke_test.py --verbose --phase4-sim-seconds 75
```

## Notes

1. The long Phase 4 simulation path was split into sub-30s segments to avoid MCP input-command timeout limits.
2. The full smoke run now validates Phases 1-4 in one pass, including a 75-second simulation window.

## Result

Final smoke status: `PASS`

Checks passed:

1. tooling_available
2. addon_connection
3. startup_to_gameplay
4. camera_movement_smoke
5. selection_command_smoke
6. build_menu_and_production_smoke
7. phase2_action_bindings
8. phase2_touch_select_move_smoke
9. phase2_touch_villager_gather_smoke
10. phase2_hud_shortcuts_smoke
11. phase2_invalid_placement_feedback_smoke
12. phase3_action_bindings
13. phase3_patrol_command_smoke
14. phase3_stance_attack_move_smoke
15. phase4_long_simulation_smoke
16. phase4_performance_guardrail
17. performance_guardrail
18. runtime_errors

Performance snapshot:

1. `fps=1526.00`
2. `frame_time_ms=2.48`

## Conclusion

Phase 4 kickoff changes are regression-safe across Phases 1-4 on the deterministic MCP path, with the economy/AI loop remaining stable during the extended simulation segment.
