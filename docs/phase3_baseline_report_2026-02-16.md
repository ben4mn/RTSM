# Phase 3 Baseline Gameplay Report

Date: 2026-02-16  
Project: `/Users/ben/Documents/1_Projects/aoem`

## Commands Run

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1
/Applications/Godot.app/Contents/MacOS/Godot --path . -e
python3 tools/mcp_smoke_test.py --verbose
```

## Notes

1. The smoke run requires the Godot editor session to be active while the script runs.
2. Once editor is open, the MCP harness connects and executes deterministic gameplay scenarios.

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
15. performance_guardrail
16. runtime_errors

Performance snapshot:

1. `fps=60.00`
2. `frame_time_ms=50.98`

## Conclusion

Phase 3 kickoff implementation is regression-safe on the current smoke path, including new patrol and stance/attack-move command-flow checks.
