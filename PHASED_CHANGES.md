# AOEM Phased Changes Plan

This plan is intended for iterative Codex execution with MCP-based test loops after each phase.

## Phase 0 (Completed): MCP Reliability + Project Agent Docs

### Delivered

- Added Codex project guide: `AGENTS.md`
- Added project-local Claude guide: `CLAUDE.md`
- Hardened MCP addon command handling to avoid duplicate-signal runtime errors:
  - `addons/godot_mcp/commands/input_commands.gd`
  - `addons/godot_mcp/commands/screenshot_commands.gd`
- Added safer screenshot handling in game bridge for headless/editor texture-null cases:
  - `addons/godot_mcp/game_bridge/mcp_game_bridge.gd`
- Added ScriptBacktrace API compatibility fallback in logger:
  - `addons/godot_mcp/core/mcp_logger.gd`

### MCP Validation Performed

- Connected MCP server and addon version check passed (`2.15.0`)
- Ran gameplay scene through MCP
- Retrieved input map from running game
- Executed input action sequences
- Captured game screenshot in headless mode
- Retrieved performance metrics

## Phase 1: Deterministic Playtest Harness

### Goals

- Create repeatable MCP playtest scenarios for regression checks.
- Detect runtime errors and severe performance drops early.

### Delivered (Current Iteration)

- Added deterministic MCP smoke harness:
  - `tools/mcp_smoke_test.py`
- Added scripted checklist and pass/fail contract doc:
  - `docs/phase1_playtest_checklist.md`

### Tasks

- Add a checklist doc with scripted test cases:
  - Startup to gameplay load
  - Camera movement via input actions
  - Selection command smoke path
  - Build menu toggle + production hotkey smoke path
- Add a simple terminal script that executes MCP JSON-RPC calls in sequence.
- Add pass/fail output format for quick review.

### Acceptance

- One command runs the full smoke test and prints a clear pass/fail summary.
- No blocking runtime errors during smoke run.

## Phase 2: Mobile-First UX Core

### Goals

- Improve touch-first command flow and reduce control friction.

### Tasks

- Improve tap/long-press behavior in `selection_manager.gd`.
- Add actionable HUD shortcuts for common tasks:
  - Idle villager cycle
  - Select all military
  - Find army
- Refine build placement feedback and invalid-reason UX.
- Add deterministic MCP checks for the Phase 2 touch/HUD/build-placement flows.

### Acceptance

- Core actions can be completed without keyboard dependency.
- Control flow remains functional on desktop and mobile input paths.

### Kickoff Status (2026-02-16)

- Added Phase 2 execution plan doc:
  - `docs/phase2_mobile_ux_kickoff.md`
- Added baseline gameplay report:
  - `docs/phase2_baseline_report_2026-02-16.md`
- Hardened MCP smoke harness for reliable baseline runs:
  - `tools/mcp_smoke_test.py`

## Phase 3: Unit Movement + Combat Depth

### Goals

- Improve army handling quality and tactical behavior.

### Tasks

- Add friendly collision avoidance/steering for clustered movement.
- Add patrol command flow.
- Strengthen stance behavior and attack-move interactions.

### Acceptance

- Large groups no longer over-stack badly.
- Patrol and stance actions are usable from command flow.

### Kickoff Status (2026-02-16)

- Added Phase 3 execution plan doc:
  - `docs/phase3_movement_combat_kickoff.md`
- Added Phase 3 baseline gameplay report:
  - `docs/phase3_baseline_report_2026-02-16.md`
- Implemented Phase 3 command/combat updates:
  - `scripts/units/unit_base.gd`
  - `scripts/main/main.gd`
  - `project.godot`
  - `scripts/ui/hud.gd`
- Extended regression scenarios:
  - `tools/mcp_smoke_test.py`

## Phase 4: Economy + AI Midgame

### Goals

- Close current gameplay loop gaps in economy/build order progression.

### Tasks

- Improve villager carry/retarget and drop-off logic edge cases.
- Expand AI build-order behavior by age and pressure state.
- Tune production priorities and age-up timing.

### Acceptance

- AI reaches stable midgame without stalling frequently.
- Economy loop remains smooth under longer simulation.

### Kickoff Status (2026-02-16)

- Added Phase 4 execution plan doc:
  - `docs/phase4_economy_ai_midgame_kickoff.md`
- Added Phase 4 baseline gameplay report:
  - `docs/phase4_baseline_report_2026-02-16.md`
- Implemented Phase 4 economy + AI behavior updates:
  - `scripts/units/villager.gd`
  - `scripts/ai/ai_controller.gd`
- Extended deterministic regression scenarios with long-run Phase 4 gates:
  - `tools/mcp_smoke_test.py`

## Phase 5: Visual Overhaul Foundations

### Goals

- Replace placeholder visuals with coherent art direction.

### Tasks

- Unit sprite and animation integration baseline.
- Building visual states (construction/damage/destruction).
- Terrain readability pass and UI theme baseline.

### Acceptance

- Visual style is consistent across units/buildings/terrain/UI.
- No functional regression in unit/building interactions.
