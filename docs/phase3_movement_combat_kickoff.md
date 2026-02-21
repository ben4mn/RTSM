# Phase 3 Movement + Combat Kickoff

Date: 2026-02-16

## Objective

Improve army control quality under multi-unit movement and make combat command flow more tactical and predictable.

## Scope for Phase 3

1. Friendly movement separation for clustered units (`scripts/units/unit_base.gd`)
2. Patrol command flow (`scripts/main/main.gd`, `scripts/units/unit_base.gd`, `project.godot`)
3. Stance and attack-move interaction hardening (`scripts/units/unit_base.gd`)
4. Regression scenario expansion (`tools/mcp_smoke_test.py`)

## Work Planned

1. Add local friendly separation steering during movement ticks to reduce over-stacking.
2. Add patrol arming flow:
   - Press patrol hotkey
   - Issue move command
   - Unit loops between patrol endpoints
3. Ensure attack-move behavior remains intact after target engagements:
   - Resume movement after combat if destination/route remains
4. Tighten stance behavior:
   - Stand Ground blocks passive chase, but explicit attack and attack-move still function.

## Definition of Done

1. Group movement no longer collapses heavily into single points.
2. Patrol command can be issued and loops reliably.
3. Attack-move units continue toward destination after skirmish interruptions.
4. No new runtime errors during scripted smoke scenarios.
