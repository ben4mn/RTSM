# Economy standing positions — 23 October 2026

The reproduced endpoint problem was independent of route passing: eight loaded
villagers chose the same Town Center delivery point, and six natural-resource
gatherers stopped within 0.36 world pixels of one another. The previous resource
offset did not prevent convergence because arrival was accepted anywhere inside
the resource interaction radius.

`scripts/units/villager.gd` now reserves a reachable standing point for each
economic route. Building work and delivery use legal, walkable perimeter cells;
natural resources use points inside the existing interaction radius. A free
original endpoint keeps its existing route. When occupied, alternatives favor
space first, then actual path length. Sorted straight-line lower bounds stop
unnecessary path queries once a free shortest route cannot be improved.

Work begins at the chosen point, rather than the first place inside the action
radius. Reservations use weak references, are scoped to the navigation map and
owner, and are released on new orders, delivery, target clearing, death or free.
Standing friendly workers are also considered when selecting a route. Neither
the reservation scan nor alternative path selection runs every frame. Legacy
minimal maps retain their direct interaction behavior.

These positions reserve space, not resource capacity. Natural sources still
accept multiple workers; when every reachable point is occupied, the least
crowded route remains usable. Farm ownership remains one assigned worker through
travel, harvesting, delivery and return. No harvest rates, carry capacity,
resource amounts, costs, footprints or fog rules changed.

## Reproduction and validation

`tools/test_economy_traffic.tscn` manually steps real Villagers, BuildingBase,
GameMap and pathfinding on a deliberately revealed synthetic grass map. It uses
the production Terrain TileSet for coordinate conversion. The detached fallback
conversion truncates positions near cell-center turns; an initial fixture using
that fallback reproduced a Farm-route failure on both versions. That diagnostic
was corrected before the evidence below. No production conversion was changed.

The same comparison fixture ran in separate private project snapshots, with private
user data. Baseline retained the pre-change movement and economy scripts;
candidate combined the Villager change with the independently tested UnitBase
passing change.

| Scenario | Baseline | Candidate |
| --- | --- | --- |
| Eight simultaneous TC deliveries | 1 endpoint | 8 endpoints |
| Six natural-food workers, minimum standing separation | 0.36 world px | 22.42 world px |
| Eight initial 15-wood bags | Exactly 120 deposited | Exactly 120 deposited |
| Four adjacent legal Farms, two normal loads per farmer | Exactly 120 food | Exactly 120 food |
| Farm claims during all work/delivery/return phases | Retained | Retained |

Every natural-resource worker harvested. Each of the four farmers physically
returned to work between deposits, delivered two complete 15-food loads and had
zero remaining cargo afterward. Explicit Stop released both Farm assignment and
the economic standing position. These are deterministic correctness checks,
not paid-match or performance evidence.

A further candidate regression blocks an upcoming waypoint while a dispersed
natural worker still has a populated route. The reserved sub-tile endpoint stays
legal. The inherited navigation repath reaches that same endpoint within 3.68
world pixels and the worker resumes harvesting (three wood), without changing
the production arrival contract.

Ten combined-candidate headless suites passed with exit 0 and no error output:

- `test_economy_traffic`
- `test_mobile_economy_orders`
- `test_farm_single_worker`
- `test_farm_command_integration`
- `test_building_perimeter_work` with `--fixed-fps 60`
- `test_resource_fog_targeting`
- `test_fog_command_legality`
- `test_worker_raid_recovery`
- `test_worker_proactive_threats`
- `test_ai_strategic_policy`

Local logs and exact source hashes are in
`output/polish-economy-traffic-2026-10-23/`. The comparison logs are
`baseline/economy-traffic-production-coordinates.log` and
`candidate/economy-traffic-production-coordinates.log`; final regression logs
use their test names. `candidate/source.json` identifies both snapshots and
runtime/fixture SHA-256 hashes. Native full-match observation and performance
validation are handled separately by the coordinating agent.

## Follow-up: settled friendly troops

The native assembly sweep reproduced productive economic overlap with settled
friendly military. Plains recorded a farmer 3.89 world pixels from an idle
Scout; River recorded a builder at the same position as an idle Archer while
the House still completed normally. Woodland retained four farmer/military
contacts at 2.17–5.83 pixels. These were not worker route stalls. The unchanged
automated learner directly orders every reserve to one base position, which
explains the military pile but exposed a real gap in economic endpoint choice.

The bounded follow-up changes only the existing route-time stationary occupant
scan from Villagers to UnitBase units. It preserves self, owner, navigation-map,
dead-state and active-navigation filters. There is no new per-frame scan or
physics behavior. Enemy or other-map troops do not influence economic choices.

The added regression places a settled friendly Scout at the ordinary Farm work
edge and Warriors at the ordinary TC delivery and House construction edges.
It performs actual harvesting, delivery, return, House labor and saved Farm
resume. The exact prior Villager version (`51bed569…`) fails all four spacing
assertions, choosing zero-pixel separation at all three edges. The follow-up
(`35507194…`) chooses 32, 35.78 and 35.78 world-pixel separation. Both versions
deposit exactly 15 food and retain one freshly harvested food through building;
the corrected version also retains Farm ownership throughout the gather cycle,
releases it for the explicit build order and reacquires it on completion.

The extended `test_economy_traffic` passed with exit 0 and no error output in its
private snapshot. Logs are `candidate/test_economy_traffic_settled_military.log`
and `candidate/test_economy_traffic_before_settled_military.log`. The previously
listed ten-suite result predates this tiny follow-up; the independent reviewer
is running its affected compatibility checks separately. Native validation of
the follow-up is likewise separate from the assembly receipts below.

| Assembly sweep (prior Villager) | Severe idle AI contacts, before → after | Economic travel stalls | Paid Farms, human / AI | Farm-associated food, human / AI |
| --- | --- | --- | --- | --- |
| Plains | 37 → 0 | 0 | 5 / 8 | 1743 / 2269 |
| River | 40 → 0 | 0 | 3 / 4 | 1066 / 1068 |
| Woodland | 50 → 0 | 0 | 4 / 6 | 1377 / 1262 |

Severe means a retained contact under eight world pixels with both units idle
and owned by AI. These are episode counts from naturally different match
durations, not normalized performance comparisons. Plains final details cover
80 of 82 contacts; Woodland earlier details cover 80 of 153. River and Woodland
final details are complete (34 and 19). All three final receipts have zero
navigation failure signals and passing Farm/drop-off coverage. River has three
long low-displacement observations involving attacking military, separately
referred to combat review; no economic actor appears in those stall records.
