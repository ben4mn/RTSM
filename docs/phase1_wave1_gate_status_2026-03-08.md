# Phase 1 Wave 1 Gate Status

Date: 2026-03-08

## Gate Results

- `python3 tools/mcp_smoke_test.py`: `PASS (18/18)`
- `python3 tools/mcp_phone_playability.py`: `PASS (60/60)` on March 8, 2026 after direct opener-stage checks were added
- Phone audit reports regenerated:
  - `docs/mobile_ux_touch_report_2026-02-22.json`
  - `docs/mobile_ux_touch_report_2026-02-22.md`

## Current Beta Blockers Mapped To Automated Gates

- None in the current Wave 1 gate set.

The previous phone-audit blocker was validation drift, then a real touch-command reliability gap in the diagnostics-based opener flow. Both are now resolved in the current passing run.

## What Wave 1 Now Proves

- Main menu touch start reaches gameplay without fallback.
- Main-menu diagnostics are exported from runtime UI state instead of brittle scene-path assumptions.
- Smoke still covers the broader startup, touch, production, patrol, and long-sim regression surface.
- The phone audit can now validate guided opener stages directly instead of inferring them from HUD visibility.
- The touch-only opener now reliably advances through direct villager gather, House placement, Scout queueing, and military move under MCP.
- Runtime logs stayed clear during both gates.
- Current phone-layout and touch-target contracts are machine-verifiable.

## Remaining Phase 1 Work After Wave 1

- Improve first-session guided-opener messaging beyond the current passing baseline.
- Tighten pause/resume discoverability and failure feedback polish for real testers.
- Extend telemetry for blocker diagnosis once external playtesting starts.
- Draft the external tester go/no-go checklist after any additional Phase 1 UX changes settle.

## Next-Stage Update

Follow-on Phase 1 work has now started on top of the passing Wave 1 gates:

- Guided opener flow has been moved toward the intended first-session sequence:
  - gather food
  - place a House
  - train a Scout
  - move military
- Pause overlay copy is clearer for touch users during resume flow.
- `first_session_diagnostics` is now exported from `/root/Main` so opener progress, pause usage, and invalid-placement feedback can be inspected by MCP.
- `tools/mcp_phone_playability.py` now asserts opener stages directly through `first_session_diagnostics`, and the March 8, 2026 passing run confirms those stricter checks are stable.
