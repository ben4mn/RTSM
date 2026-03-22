# Phase 2 Mobile-First UX Kickoff

Date: 2026-02-16

Validation update: Revalidated by MCP on 2026-03-07. The baseline touch loop is live; the current Phase 2 work is about stricter acceptance and feel polish, not initial enablement.

## Objective

Ship touch-first controls that let players complete core RTS loops without keyboard or right-click dependency.

## Scope for Phase 2

1. Touch command flow (`scripts/managers/selection_manager.gd`)
2. Mobile action shortcuts (`scripts/ui/hud.gd`, `scripts/main/main.gd`)
3. Build placement feedback (`scripts/buildings/building_placement.gd`, `scripts/ui/build_menu.gd`)
4. Regression checks (`tools/mcp_smoke_test.py`)

## Current Gaps (updated after 2026-03-07 MCP pass)

1. MCP coverage still allowed build-menu visibility to pass without proving real visible controls in the open state.
2. Long-press context exists in code, but the audit did not yet require it as a hard regression gate.
3. The touch-only military loop could still pass with timing ambiguity instead of a hard failure.
4. Mobile controls work, but the next pass should improve command feedback and repeatability around build placement.

## Task Breakdown

## A. Touch Command Flow

1. Add tap-to-command behavior for touch:
   - If own units are selected and user taps walkable ground, emit `move_command`.
2. Add touch attack/gather/build target routing:
   - Tap enemy target => `attack_command`
   - Tap resource with selected villagers => `gather_command`
   - Tap unfinished building with selected villagers => `build_command`
3. Add long-press detection:
   - Introduce hold threshold and movement tolerance.
   - Open a compact context panel for action disambiguation when needed.
4. Keep drag-select intact:
   - Do not regress box-select behavior and double-tap same-type selection.

## B. HUD Mobile Shortcuts

1. Convert shortcut cluster into a bottom action strip with larger touch targets.
2. Keep parity shortcuts wired:
   - Idle villager
   - Select all military
   - Find army
3. Add context-aware enable/disable states (no military/no idle villagers).
4. Preserve keyboard support and existing hotkeys.

## C. Build Placement UX

1. Promote invalid reason text to HUD notification channel in addition to footprint text.
2. Ensure cancel path is always reachable during placement on touch devices.
3. Improve blocked-tile clarity:
   - Highlight invalid footprint tiles.
4. Add one-tap reselect of last building type after cancel/invalid confirm.

## D. Gameplay Regression Coverage

1. Extend deterministic smoke checks with Phase 2 scenarios:
   - Touch select -> touch move
   - Touch villager -> touch resource gather
   - HUD idle villager / military shortcuts
   - Invalid placement feedback
   - Strict build-menu visibility
   - Touch-only build -> place -> resume economy
   - Long-press context
   - Pinch zoom
2. Capture one screenshot per scenario and verify runtime log cleanliness.
3. Keep performance guardrail (`fps >= 15`, `frame_time_ms <= 120`) as minimum gate.

## Definition of Done

1. A full opening loop can be played on touch only:
   - Select villager
   - Gather resources
   - Place one building
   - Train one unit
   - Move at least one military unit
2. Phase 1 smoke still passes.
3. New Phase 2 scenarios pass.
4. No new runtime errors in `editor(get_log_messages)` output.

## Implementation Order

1. Touch command flow in `selection_manager.gd`
2. HUD layout/actions in `hud.gd` and `main.gd`
3. Placement UX in `building_placement.gd` and `build_menu.gd`
4. Scenario expansion in `tools/mcp_smoke_test.py`
