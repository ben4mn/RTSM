# Phase 1 Deterministic MCP Playtest Checklist

This checklist defines the fixed smoke path for AOEM regression checks.

## Prerequisites

- Godot editor is open with this project (`/Users/ben/Documents/1_Projects/aoem`)
- `godot_mcp` editor plugin is enabled
- MCP addon/server versions match (`project -> addon_status`)
- Node 20+ and `npx` available

## One-command smoke run

```bash
python3 tools/mcp_smoke_test.py
```

## Scripted Scenarios

1. Startup to gameplay load
- Tool calls: `project(addon_status)`, `editor(run)`, `editor(get_state)`, `editor(screenshot_game)`
- Pass criteria:
  - Game enters playing state before timeout
  - Game screenshot returns image payload
  - No new runtime errors in `editor(get_log_messages)`

2. Camera movement smoke
- Tool calls: `input(get_map)`, `input(sequence)`
- Sequence:
  - `camera_right` -> `camera_down` -> `camera_left` -> `camera_up`
- Pass criteria:
  - Required camera actions exist in input map
  - Sequence executes successfully
  - No new runtime errors

3. Selection + command smoke
- Tool calls: `input(sequence)`
- Sequence:
  - `select`, then `command`
- Pass criteria:
  - Sequence executes successfully
  - No new runtime errors

4. Build menu + production hotkey smoke
- Tool calls: `input(sequence)`
- Sequence:
  - `toggle_build_menu`, `train_unit`, `toggle_build_menu`
- Pass criteria:
  - Sequence executes successfully
  - No new runtime errors

5. Performance guardrail
- Tool calls: `editor(get_performance)`
- Default thresholds:
  - `fps >= 15`
  - `frame_time_ms <= 120`
- Pass criteria:
  - Metrics are within threshold bounds

## Output Contract

The script prints one line per check:

- `[PASS] <check_name>: <detail>`
- `[FAIL] <check_name>: <detail>`

And a final summary:

- total checks
- passed
- failed
- final status (`PASS`/`FAIL`)

Exit code:

- `0` when all checks pass
- `1` when any check fails

