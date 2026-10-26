# Fewer actors, the same paid population budget (2026-10-25)

This pass supersedes the **balance proposal**, not the historical measurements, in `population_economy_2026-10-24.md`. The normal ceiling remains **100 population per player**. Workers and ordinary fighters now use two slots; Scouts remain one and Siege three. A representative full town has about 50 physical actors instead of 100, improving small-screen selection and reducing navigation traffic.

## Alternatives compared

The old worker gathered one item per tick: food/wood every 0.75s, gold every 0.9s, carrying15 at speed60. At a120-world-unit one-way haul, delivered income is `carry * 60 / (carry / harvest_per_second + 2 * 120 / 60)`.

| Model | Starting workers | Gather/tick | Carry | Food/wood per worker/min | Initial equivalent total/min | Recruitment |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Old | 4 | 1 | 15 | 59.02 | 236.07 | 50F /12s /1pop |
| Alternative A | 3 | 1.5 | 24 | 90.00 | 270.00 | 75F /18s /2pop |
| **Selected B** | **2** | **2** | **30** | **118.03** | **236.07** | **100F /24s /2pop** |

A uses about17 mature workers instead of25 but boosts opening income14.4%; half workers cannot be represented, carry rounding changes travel efficiency, and two-pop pricing makes the maximum economy inconsistent with its1.5x productivity. B exactly preserves steady delivery and travel frequency for each pair. Gold is102.86/min instead of51.43. French remains the reference; English wood and Mongol food multipliers are unchanged and apply before cargo rounding. Wheelbarrow is still+25% (now+0.5 per tick).

Initial two workers auto-start food/wood instead of the former two-food/one-wood/one-gold allocation. Total modeled capacity is preserved but simultaneous allocation is deliberately coarser: a paid third/fourth worker opens the gold economy. The unchanged250F/250W/100G bank can buy two workers, not four; Feudal still needs320F/160G, so it cannot be bought on spawn. The first additional income arrives after24s instead of12s, and worker losses are correspondingly more consequential.

## Army, buildings and growth

| Unit | Cost F/W/G | Training | Population | HP /damage /armor |
| --- | --- | ---: | ---: | --- |
| Villager | 100/0/0 | 24s | 2 | 50/6/0 |
| Warrior | 100/40/0 | 20s | 2 | 120/16/4 |
| Archer | 50/90/0 | 24s | 2 | 70/14/0 |
| Horseman | 180/60/0 | 28s | 2 | 160/20/2 |
| Scout | 40/0/10 | 8s | 1 | unchanged |
| Siege | 0/150/100 | 25s | 3 | unchanged |

Half as many ordinary fighters have the same aggregate HP, attack and population investment. Their attack intervals, speeds, counters and range are unchanged. A Barracks/Range/Stable still spend810.71F and473.57W per minute together, but produce half as many units. Seven food and five wood workers now support that flow, leaving one or two for gold/construction. English Longbows/Horsemen and Mongol Outriders retain their relative HP penalties (60/130/140 respectively).

A worker builds at2x speed; one now supplies the labor of two old workers. A Farm costs150W and20 nominal build-seconds (10 real seconds for one worker), supports one double-output farmer and remains permanent. Seven Farms cost the same1050W and occupy28 tiles rather than fourteen occupying56. Houses remain50W, ten population, and10 nominal build-seconds: nine still supply the100-pop town's ceiling for450W, but take45 physical worker-seconds instead of90. Camps and production buildings keep their prices, nominal work and footprints. Overall infrastructure labor per equivalent workforce remains comparable.

Town Center/tower volleys double damage **and** interval (12/4s and12/3s). This preserves aggregate DPS after the doubled military armor, without making defense fire twice as often. Ordinary army DPS into buildings is unchanged for equal population/cost. Siege keeps its existing anti-building role; its anti-unit effectiveness relative to a single enlarged fighter decreases. Forge Weapons/Scale Mail/Loom retain fixed+2/+1/+15 bonuses, so their proportional effect is smaller; no hidden multiplicative upgrade is introduced.

A representative99-pop Feudal town: **13 villagers +1 Scout +20 Warriors +10 Archers +6 Horsemen =50 actors**. It pays5000F/4160W/160G, including eleven recruited workers, Feudal, nine Houses, seven Farms, three Camps and three military producers. Net beyond starting stock:4750F/3910W/60G. The old100-pop example paid5130F/4220W/160G. Worker queue4m24s versus4m12s; infantry queue6m40s unchanged; archer4m00s unchanged; cavalry2m48s versus3m16s because this example has one fewer pair. The analytical labor bound including160 physical worker-seconds of construction is **7.92 game minutes**, versus about8.1 previously. This is a clean-haul lower bound, not a measured completion promise.

AI physical worker targets halve: large-match Easy/Medium/Hard6/9/11 in Dark, +1 Feudal and+2 Castle, subject to reachable progression gates. Small-budget mature targets are one quarter of population (Easy one fifth), capped15. Age workforce gates, recruitment recovery floors, research workforce gates and attack thresholds are reduced to physical counts. Costs and income remain equal between human and AI.

## Bounded paid comparison and validation

Godot4.6, existing `probe_ai_compact_paid_match.tscn`,100pop, seed424242, Medium vs Medium, no free units/resources. Both sides use ordinary build/train/age transactions. The baseline is a snapshot of1fd7680. At the four-minute checkpoint:

| Receipt | Baseline | Reduced actors |
| --- | --- | --- |
| First damage contact | 183.60s | 184.35s |
| P0 delivered F/W/G at120s | 385/262/73 | 221/434/45 |
| P1 delivered F/W/G at120s | 345/240/60 | 246/456/28 |
| P0 delivered F/W/G at240s | 1518/662/192 | 1145/806/221 |
| P1 delivered F/W/G at240s | 1335/535/195 | 1136/755/232 |
| Damage-active seconds by240s | 16 | 15 |

This supports similar early combat timing with a different resource mix; it does not establish win-rate balance, late Castle pacing or every map. These started before the final defensive-volley adjustment and inherited different civilization preferences; no final defense-performance claim is made from them. The baseline eventually won at456.85s; the preliminary reduced-actor run reached600s without a winner. This is a warning against treating first-contact timing as proof of complete match pacing.

Integration repeated the comparison with both civilizations pinned to French, the same100-pop/424242/Medium configuration, and the final defensive volleys. Both processes were stopped at the explicit360-second wall-time budget. Shared checkpoint: first damage183.60s baseline versus183.45s candidate; damage-active seconds at240s16 versus14. Candidate P0 deposits at240s were1018F/846W/112G versus1429F/623W/178G baseline. The candidate reached360 simulated seconds with44 damage-active seconds and a70.92s longest quiet gap. Neither bounded run supplies a final victory result. Early contact remains close; income mix, sustained pressure and late-game balance need more seeds and human matches.

An actual browser playthrough at667×375 reached a natural Sacred defeat at8:14. The player used ordinary paid training, gathering, House/Barracks construction, Feudal advancement, rally routes, raid defense and an attempted objective contest. This was an interaction test with deliberate time spent inspecting controls, not a matched skill or win-rate benchmark.

Passed focused checks: `test_economy_balance.gd` (finite source accounting, double rates, effective fractional Wheelbarrow,30-slot cap, exact real deposits); `test_farm_economy.gd` (ownership, permanence, input and real harvest/drop-off loop); clean Godot import. Historical compact policy/cost fixtures still encode old one-pop/50F assumptions and require a separate migration before they can serve as balance assertions. No full test suite was run.
