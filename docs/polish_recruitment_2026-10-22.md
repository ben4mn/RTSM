# Recruitment availability polish — 2026-10-22

The native baseline inspection by the coordinating agent found that recruitment showed generic unit statistics without the current reason a purchase could fail. Code inspection confirmed that hover omitted resource cost and touch Info only listed general requirements.

## Changes

- Recruitment hover, hold Info, tap-only summary Info, and accessibility text now share a live description: current availability, complete cost, population requirement, training time, combat statistics, and the applicable Q shortcut.
- A blocked phone card replaces its cost line with a compact reason (`Need 20F +`, `Pop 10/10`, or `Queue full`). Full costs and every shortage remain in Info. Desktop cards retain the cost and replace the role line while blocked.
- Unavailable cards stay enabled so normal purchase feedback still works. Button identity, touch dimensions, and queue badges are preserved through refreshes. Status text uses the existing rust accent and returns to parchment when available.
- Population feedback counts paid reservations across producers and distinguishes refundable queue reservations, insufficient housing, and the match limit. Queue-full feedback points to waiting or cancellation. Wrapped explanatory lines keep tooltip width bounded.
- The existing mobile composition fixture now creates a live, funded producer. Previously its detached building never loaded trainable units or initialized player resources, which is no longer a valid ready-to-purchase fixture.

## Validation

Godot 4.6 headless passes:

- `tools/test_recruitment_availability.tscn`: resource shortage and recovery; complete costs/time; shared tooltip and touch Info; valid Q hint; stable buttons; simulated primary-pointer activation while unavailable; unchanged spending/reservations from inspection; paid population in another producer; living-population/housing and match-limit guidance; queue-full recovery; construction status. The phone card remains at least 48 pixels in each dimension and does not widen for multiple deficits.
- `tools/test_touch_train_button_input.tscn`: recruitment, queue cancellation, Clear, and research survive synchronous HUD refresh during input.
- `tools/test_mobile_hud_composition.tscn`: 13 simulated phone, UI-scale, and notch profiles, including effective 632×356 logical space; no clipping or layout failures after fixing the funded-producer fixture.

These are headless UI and simulated pointer checks, not physical-device testing. No balance, purchasing, production, or navigation behavior was changed by this work.

Native mode of `test_recruitment_availability.tscn` now captures ready, missing-resource, paid-population, and full-queue states at 844×390 and 1280×720, each with the tap-only summary Info panel. Sixteen rendered SubViewport PNGs plus a receipt are saved to `output/polish-2026-10-22/recruitment/`. This is an isolated native HUD fixture, not a battlefield or performance test.

The coordinating agent ran this native fixture and confirmed all sixteen captures with an empty failure receipt. MCP returned no log messages. The agent inspected the phone resource-shortage card, phone population Info panel, and desktop ready state. These verify the actual rendered SubViewport controls and Info layout; the fixture contains no map and does not establish gameplay or physical-device performance.

Integrated Scout copy review measured its original explanation at 661px using the actual 16px Barlow font, exceeding the effective 632px phone viewport. A sentence break after “Sacred Site.” bounds that line without changing wording.
