# Phase 1 Beta Foundation Kickoff

Date: 2026-03-08

## Objective

Convert the current skirmish prototype into a closed-mobile-beta candidate by removing validation drift, tightening the first-session touch flow, and defining a blocker-first execution order.

## Baseline

- `python3 tools/mcp_smoke_test.py`: `PASS (18/18)` on March 8, 2026
- `python3 tools/mcp_phone_playability.py`: `PASS (60/60)` on March 8, 2026 with direct `first_session_diagnostics` opener-stage assertions
- Current product target: one polished, mobile-first 1v1 skirmish mode

## Progress Update

Updated: 2026-03-08

- Wave 1 validation repair is complete:
  - menu/HUD touch diagnostics are live
  - smoke still passes
  - phone playability now reads opener stages from `first_session_diagnostics`
  - blocker discovery is now driven by current automation instead of stale audit assumptions
  - the direct-touch opener loop now passes under MCP without weakening the diagnostics-based gate
- First-session UX work has started beyond Wave 1:
  - guided opener now teaches `gather -> place House -> train Scout -> move military`
  - pause overlay messaging is clearer for touch resume flow
  - runtime now exports `first_session_diagnostics` from `scripts/main/main.gd` for MCP-readable opener progress and failure-state inspection
- Active follow-up focus inside Phase 1:
  - keep tightening guided-opener copy and recovery cues from real-touch runs
  - expand tester-facing go/no-go documentation once the UX pass settles

## Phase 1 Task List

### A. Validation Truth

1. Export stable `main_menu_diagnostics` from `scripts/ui/main_menu.gd`.
2. Update `tools/mcp_phone_playability.py` to consume diagnostics instead of brittle menu hierarchy paths.
3. Treat the following MCP-readable diagnostics as stable regression surfaces:
   - `main_menu_diagnostics`
   - `touch_target_diagnostics`
   - `mobile_layout_profiles`
   - `touch_context_diagnostics`
4. Keep screenshot-backed failure output in the audit report.
5. Tighten checks for:
   - main-menu touch start
   - build-menu visible/open state
   - long-press context
   - pinch zoom
   - touch-only opening flow

### B. First-Session UX

1. Audit the main menu for clarity of:
   - difficulty choice
   - map seed behavior
   - guided opener expectation
2. Make the guided opener teach a complete opening loop:
   - gather
   - place building
   - train unit
   - move military
3. Improve pause/resume discoverability during touch play.
4. Ensure failed actions produce readable feedback without relying on desktop workflows.

### C. Touch-Command Reliability

1. Verify empty-ground tap, gather tap, build tap, and enemy tap remain distinct and reliable.
2. Ensure invalid placement and cancel recovery can always be completed on touch.
3. Reduce minimap and action-surface conflicts during command issuing.
4. Recheck touch-target sizing for all primary opening-loop controls.

### D. Stability And Telemetry

1. Keep runtime logs clean during menu startup, opening loop, and long-run AI sim.
2. Extend exported telemetry where needed for blocker diagnosis:
   - guided-opener progress or first-session completion markers
   - idle villager / military shortcut availability
   - AI economy stall indicators
3. Preserve guardrails:
   - `fps >= 15`
   - `frame_time_ms <= 120`
4. Publish a short go/no-go checklist for external testers once Wave 1 passes.

## Wave 1 Plan

Wave 1 is the first implementation batch inside Phase 1. It should be completed before broader polish.

### Wave 1 Goals

- Make the phone audit trustworthy again
- Prove that the first two minutes of play are touch-completable
- Produce a blocker list that maps directly to automated failures

### Wave 1 Changes

1. Runtime contract
   - Add `main_menu_diagnostics` to the main menu scene script.
   - Include stable control bounds and key setup state so MCP can inspect the menu without relying on scene nesting.

2. MCP audit alignment
   - Replace hardcoded menu-node lookups in `tools/mcp_phone_playability.py`.
   - Read start-button and difficulty touch-target data from exported diagnostics.
   - Use diagnostic bounds for menu tap targeting.

3. Opening-loop validation
   - Keep the smoke harness as the broad regression gate.
   - Use the phone audit as the stricter touch-first gate for menu entry and early-session flow.
   - Record blocker findings only when they map to current gameplay or UI behavior, not stale audit assumptions.

4. Roadmap and execution hygiene
   - Treat `roadmap.md` as the active beta sequence.
   - Keep older phase docs as references only.

### Wave 1 Acceptance Criteria

1. `python3 tools/mcp_phone_playability.py` passes against the current menu scene contract.
2. `python3 tools/mcp_smoke_test.py` continues to pass.
3. Main menu touch start reaches gameplay without fallback.
4. No new runtime errors appear in MCP log capture.
5. Any remaining failures are real product blockers, not audit drift.

## Exit Criteria For Phase 1

Phase 1 is complete when:

1. The first-session touch loop is reliable under automated testing.
2. Beta blockers are tracked through automated gates, not manual guesswork.
3. The game is stable enough for closed external testers to complete a first match and report issues against a known baseline.
