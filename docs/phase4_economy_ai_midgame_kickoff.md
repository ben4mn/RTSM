# Phase 4 Economy + AI Midgame Kickoff

Date: 2026-02-16

## Objective

Stabilize the economy loop and AI progression so matches reliably move from early game into midgame without frequent stalls.

## Scope for Phase 4

1. Villager carry/drop-off hardening (`scripts/units/villager.gd`)
2. AI pressure-aware build order (`scripts/ai/ai_controller.gd`)
3. AI production + age-up timing tuning (`scripts/ai/ai_controller.gd`)
4. Long-run regression coverage (`tools/mcp_smoke_test.py`)

## Work Planned

1. Fix villager edge cases where resources could be dropped without a valid deposit target.
2. Add retry-safe drop-off behavior for destroyed/missing drop-off structures.
3. Move AI build goals from static caps to age/pressure-aware targets.
4. Improve training building selection to avoid queue/busy-building stalls.
5. Add age-up reserve logic to reduce repeated midgame timing stalls.
6. Add Phase 4 smoke checks that keep the simulation running long enough to validate stability.

## Definition of Done

1. Villagers no longer lose carried resources on invalid drop-off paths.
2. AI can keep producing buildings/units in midgame without obvious queue deadlocks.
3. AI age-up intent is more consistent under normal (non-pressure) conditions.
4. Extended smoke scenarios pass without runtime errors through the long-run segment.
