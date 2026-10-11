# Mobile orders and opening balance — 2026-10-10

Selected friendly units now show their remaining navigation route and destination.
Move is green, combat is coral, and work is gold. The overlay reads live waypoints,
so obstacle detours, movement progress and repaths stay accurate without additional
pathfinding. Nearby formation destinations share a leader route, with at most four
independent routes visible. An attack-move goal remains marked during engagement;
an explicit target attack replaces the previous attack-move order. Stop, arrival,
death and deselection remove stale feedback.

The reference is Age of Empires' [group waypoint markers](https://support.ageofempires.com/hc/en-us/articles/10188989888916-Waypoint-Markers)
and AoE IV's [ground-based attack-move behavior](https://www.ageofempires.com/news/age-of-empires-iv-update-11-0-782/).
The continuous navigation line is this prototype's mobile adaptation.

## Touch behavior

- Tap **Select area**, then drag around friendly units. This one-shot gesture draws
  a box and keeps the camera fixed. **Cancel area**, a second finger, OS cancellation,
  a GUI-consumed release, or a modal change safely ends it.
- Unit actions are **Move / Attack / More / Clear**. **Attack** chooses a destination
  and engages enemies on the way, even when the tap lands on an entity. Ordinary
  military ground taps already use this behavior. **Move** travels without engaging.
- **More** contains Stop, Patrol and Stance. Pressing an armed Move or Attack again
  cancels it. Button state and the selection details show the current mode and clear
  immediately after its destination is accepted.
- Tap empty ground to close a building, resource or objective inspection. With units
  selected, double-tap empty ground or press Clear to deselect while their order
  continues. Resource-to-ground taps remain distinct, and same-type unit double-tap
  selection still works.
- Hold ground with a production building selected to set a ground rally. Tapping a
  visible resource with a villager producer selected still sets its resource rally.

## Shared economy and AI pacing

Both players start with **200 food, 150 wood, 100 gold**; wood was previously 200.
Villagers gather one resource per tick and carry ten. Food ticks every 1.25 seconds,
versus 1.5 for wood and gold, giving food a 20% source-rate increase. Travel, finite
source depletion and actual drop-offs still determine deposited income. Wheelbarrow's
advertised 25% bonus now accumulates fractional harvest instead of rounding it away,
and harvesting respects the carry limit. Balance constants live in UnitData and
SkirmishData rather than conflicting scene overrides.

For the existing 20/30/40-population skirmishes:

| Difficulty | Earliest ordinary raid | Minimum time between launches |
| --- | --- | --- |
| Easy | 6:00 | 120 seconds |
| Medium | 4:00 | 75 seconds |
| Hard | Existing ready-army pressure | Existing cadence |

Defense and Sacred Site contests remain immediate. Site defenders return when a
target leaves current vision or the contest area, preventing that chase from bypassing the opening
raid delay. Harassment requires three idle fighters. Difficulty supplies no resource,
cost or unit-strength bonuses.

In the paid seed-42, 30-population Medium probe with a passive human opening economy,
the first launch moved from **196.5 to 271.5 game seconds**, and launches through
720 seconds fell from **21 to 6**. The lower bank still funded workers, production,
buildings and age advancement. This is a pacing sample, not a general win-rate claim.

A final 600-second, seed-42 contested run with paid AI policies on both sides reached
Feudal at 279/283.5 seconds, retained fifteen workers each, produced 19/22 paid military
units and eleven buildings each, and harvested 3,232/3,595 resources. Both sides replaced
troops after losses and fielded all three combat roles. The paid run loaded the final
bank, gathering, Wheelbarrow and raid cadence. It precedes the removal of three
command-arming notifications and an isolated visibility guard that recalls Sacred
defenders before consulting a hidden target's position; affected regressions passed
after both refinements. Exact cached-source differences are recorded in
`output/mobile-orders-2026-10-10/balance/balance-summary.json`.

## Verification

- 18 controls regressions passed; final affected tests were repeated after the
  resource-boundary and command-feedback refinements.
- 12 integration scenarios passed: gathering/farms, paid construction and production,
  resource rallies, placement, fog command legality, main-menu transitions, Sacred
  Site behavior and all four match-ending transitions.
- Navigation and force-move engagement checks passed. The new route regression
  proves an actual A* gap detour, natural waypoint consumption, no feedback-driven
  A*, group limits, ownership, and combat/selection lifecycle cleanup.
- Eight economy/AI suites passed, plus final current-vision and Sacred-pursuit
  checks after the visibility guard. Paid seeded runs verify production and
  replacement through combat losses; they do not establish a general win rate.
- Twelve native renders cover 844×390 and 932×430 at overview, default and detail
  zoom. They use real Main/HUD and production navigation with explicitly injected
  presentation fixtures. Routes and targets remain readable outside the HUD.
- Headless boot and `git diff --check` passed.

Primary evidence is in `output/mobile-orders-2026-10-10/`; native renders and their
manifest are in its `native/` directory. Controls evidence is copied there from the
isolated controls runner. These checks simulate touch and phone dimensions; physical
device feel still needs a playtest. This change updates local source, not the public
web export.
