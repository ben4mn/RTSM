# Sizing a 100-population kingdom

Use **100 population per player as the normal/default ceiling** for this pass,
while preserving the smaller optional matches. That means up to 200 population
across both sides, not 100 fighters plus unlimited workers. Existing unit costs,
gathering rates, training times and age prices already support this scale. No
unit-stat or economy-rate increase is mathematically necessary.

These are code-derived budgets and planning estimates, not measured human-match
completion times. Source: `scripts/data/unit_data.gd`, `building_data.gd`,
`skirmish_data.gd`, `civilization_data.gd`, `scripts/units/villager.gd`,
`scripts/buildings/building_base.gd` and `scripts/managers/game_manager.gd`.
One game minute means 60 simulation seconds at 1x; at 2x/3x, uninterrupted wall
time is correspondingly shorter. Raids, idle workers, path congestion, scouting,
rebuilding and decision time are excluded from the arithmetic below.

## Income and recruitment

An unupgraded worker gathers one resource per tick. Food/wood tick every
0.9 / 1.2 = 0.75 seconds (80/min while continuously working); gold ticks every
0.9 seconds (66.67/min). A load is 15 resources and walking speed is 60 world
units/second. With a 120-world-unit one-way haul and no blockage:

`delivered/min = 15 × 60 / (15 / harvest_per_second + 2 × 120 / 60)`

This gives **59.02 food/wood/min** and **51.43 gold/min per worker**, before
construction or other idle time. English +20% wood gathering gives about
67.29 delivered wood/min in this same haul model; Mongol +15% food gives about
65.30 food/min. They do not increase delivery rates by the full percentage
because walking time is unchanged. French use the baseline. Nearby camps matter.

| Unit | Food | Wood | Gold | Train seconds | Population |
| --- | ---: | ---: | ---: | ---: | ---: |
| Villager | 50 | 0 | 0 | 12 | 1 |
| Warrior | 50 | 20 | 0 | 10 | 1 |
| Archer / Longbow | 25 | 45 | 0 | 12 | 1 |
| Horseman / Outrider | 90 | 30 | 0 | 14 | 1 |
| Scout | 40 | 0 | 10 | 8 | 1 |
| Siege engine | 0 | 150 | 100 | 25 | 3 |

One continuously operating Barracks, Range and Stable spend **810.71 F/min and
473.57 W/min** together. Fourteen food workers and nine wood workers cover this
at the stated haul distance (826.23 F/min, 531.15 W/min); two other workers can
mine the finite age costs, construct, or reinforce whichever resource falls
behind. Twenty-five to thirty workers therefore support a large mixed army.
Additional production buildings consume saved stock faster; they do not create
income. Pure cavalry needs a larger food share.

## Housing and map footprint

The player has five base housing slots and the starting Town Center provides
ten more: 15 initial capacity. Nine Houses provide another 90 nominal slots,
clamped to the 100 match ceiling. That costs **450 wood and 90 worker-seconds**
of construction, plus walking. Each House is 2×2 tiles; the nine occupy 36 tiles.

A Farm costs 75 wood, takes ten worker-seconds, supports exactly one farmer and
has no finite food stock. Fourteen food workers can eventually use fourteen
Farms (1,050 wood, 140 worker-seconds). Early berry harvesting can defer that
expense. Three nearby Resource Camps cost 240 wood/30 worker-seconds. One each
Barracks/Range/Stable costs 360 wood/60 worker-seconds. These 30 buildings,
including the starting Town Center, occupy 147 tiles before the required gaps
and access lanes. Expansion beyond the initial town clearing is expected.

The food supply can be renewed indefinitely with Farms. The baseline mixed army
below needs about 3,970 additional wood after its starting stock: roughly sixteen
full 250-wood trees per player, ignoring replacement losses. Map resource
distribution and access must still be checked in the paid simulation; this is
not a guarantee that every convenient starting tree remains uncontested.

## Example A: 100 population in Feudal Age

**25 villagers + 1 starting Scout + 40 Warriors + 20 Archers + 14 Horsemen = 100.**
Four villagers and the Scout already exist, so purchase only 21 more villagers.

| Budget | Food | Wood | Gold |
| --- | ---: | ---: | ---: |
| 21 additional villagers | 1,050 | 0 | 0 |
| 40 Warriors | 2,000 | 800 | 0 |
| 20 Archers | 500 | 900 | 0 |
| 14 Horsemen | 1,260 | 420 | 0 |
| Feudal advancement | 320 | 0 | 160 |
| 9 Houses + 14 Farms + 3 Camps + 3 production buildings | 0 | 2,100 | 0 |
| **Total paid** | **5,130** | **4,220** | **160** |
| **Gather beyond starting 250F / 250W / 100G** | **4,880** | **3,970** | **60** |

Queue lower bounds with one of each producer: villagers 4m12s, Warriors 6m40s,
Archers 4m00s, Horsemen 3m16s. These queues can overlap but cannot start before
their building/age/resources are available. Age advancement is a paid immediate
transaction, not a hidden extra training queue.

At the haul rates above, the net resources require 151.13 productive worker-
minutes. Growing from four to 25 workers with uninterrupted 12-second training
takes 4.2 minutes and contributes 58.8 worker-minutes before the last recruit
arrives. Gathering the remainder with 25 workers takes another 3.69 minutes:
about **7.9 game minutes in this idealized labor model**, or about 8.1 including
the minimum 320 worker-seconds of infrastructure labor. This is an optimistic
model, not a promised build order: allocation, tech/queue gating, walking to
foundations and combat add time. A **9–13 game-minute planning envelope** is
reasonable to investigate in paid playtests; it remains an estimate until those
receipts exist.

## Example B: Castle army with siege

**25 villagers + 1 Scout + 32 Warriors + 20 Archers + 16 Horsemen + 2 Siege = 100
population**, but 96 actual entities because each Siege occupies three slots.
Include both age payments (1,120F/560G), a 300W/100G Workshop, and the same housing,
farms, camps and three ordinary production buildings.

Total paid: **5,710F / 4,720W / 860G**. Net gathering after the starting bank:
**5,460F / 4,470W / 760G**. This needs 183.04 productive worker-minutes in the same
haul model, about **9.2 game minutes before infrastructure labor and gating**, or
about 9.4 with minimum construction labor. A **11–16 game-minute planning
envelope** merits testing, especially because Castle and the Workshop delay the
last siege purchases. Do not interpret this as a measured match duration.

## AI and performance constraints

The compact-mode helper uses half the population limit (40% on Easy), capped
at 30 workers. Extending an uncapped half-population formula to 100 would require
46 paid worker recruits and 9m12s of Town Center queue time. That is a hypothetical
budget, not the actual 100-population AI policy: the compact branch only runs
below 80 population. Larger matches retain difficulty targets of 12/18/22 workers
(Easy/Medium/Hard), plus two in Feudal and four more in Castle, adjusted for
pressure and next-age workforce floors. Beta7 changed the shared helper cap but
did not change those live large-match economy targets. The earlier statement
that this implemented a new 25–30-worker large-match policy was inaccurate.
The beta8 follow-up changes objective commitment only; economy tuning remains
a separate question. Unit costs, work rates and training times are unchanged.

The new occlusion observer does no work on the headless authority. On a rendered
client it checks current visibility per unit each frame; screen/depth/spatial
bins reduce overlap candidates. It requests a scan after 0.1 simulation seconds,
processes at most 32 units per frame and completes that scan before starting the
next. A 200-actor pass therefore spans seven rendered frames.
At 100 units per side, there are at most 39,800 directed unit pairs before those
filters. A pair tests at most 15 cached actual body samples; successful overlaps
stop early. The isolated 200-actor CPU probe measured crowded amortized calls at
5.29/5.34 ms mean and 8.16/9.71 ms p95 for 844×390/1280×720 viewports, versus
19–27 ms mean for the prior complete-refresh burst. The two measurements cover
different work per call; this demonstrates spreading the burst, not a throughput
speedup. Full scope is recorded in `docs/unit_occlusion_2026-10-24.md`; it is not
a rendered full-battle FPS or physical-phone result. A 100-pop ceiling alone
does not prove performance.
