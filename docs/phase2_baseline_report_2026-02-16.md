# Phase 2 Baseline Gameplay Report

Date: 2026-02-16
Project: `/Users/ben/Documents/1_Projects/aoem`

## Baseline Commands Run

```bash
/Applications/Godot.app/Contents/MacOS/Godot --version
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1
python3 tools/mcp_smoke_test.py --verbose
```

## Environment Notes

1. The smoke harness requires a live Godot editor session with `godot_mcp` enabled.
2. Reliable local launch for smoke checks:
   - `/Applications/Godot.app/Contents/MacOS/Godot --path . -e`

## Harness Fixes Applied Before Baseline

File: `tools/mcp_smoke_test.py`

1. Fixed false-pass behavior when runtime exceptions happen before a check is recorded.
2. Added robust parsing for `editor(get_log_messages)` when it returns plain text (`No log messages`).
3. Added screenshot retry/warm-up handling after game enters playing state.

## Gameplay Result

Final smoke run status: `PASS`

Checks passed:

1. `tooling_available`
2. `addon_connection`
3. `startup_to_gameplay`
4. `camera_movement_smoke`
5. `selection_command_smoke`
6. `build_menu_and_production_smoke`
7. `performance_guardrail`
8. `runtime_errors`

Performance snapshot:

1. `fps=60.00`
2. `frame_time_ms=17.54`

## Baseline Conclusion

Phase 1 regression gate is green after harness hardening. Phase 2 implementation can begin against a stable gameplay baseline.
