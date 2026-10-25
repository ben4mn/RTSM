# Large armies, map routes and meaningful decisions

The three completed beta7 ordinary-cost rounds exposed a tactical limitation worth addressing before enlarging the maps. These are automated policies, not human APM measurements. Each used actual gathering, paid construction, training and age advancement, fixed 60 Hz stepping and the supported 3x development clock. The completed receipts and scope are recorded in [the paid-round report](beta7_paid_rounds_2026-10-24.md).

| Round | First paid fighter, owners 0 / 1 | First HP loss | Feudal, owners 0 / 1 | Natural result |
| --- | ---: | ---: | ---: | --- |
| French / English, Plains, Medium / Medium | 122.5 / 134.5 s | 184.2 s | 150.0 / 150.0 s | French Sacred victory at 531.7 s |
| English / Mongols, River, Hard / Easy | 111.0 / 96.0 s | 136.5 s | 166.0 / 228.0 s | Mongol Sacred victory at 380.9 s |
| Mongols / French, Woodland, Hard / Easy | 109.0 / 102.0 s | 139.6 s | 162.0 / 232.0 s | Mongol Sacred victory at 573.7 s |

All six armies remained in Feudal. Archers first appeared at 396–506 seconds in the longer rounds; no cavalry or siege appeared. Of 32 recorded field-wave destinations, 30 were within 324 world units of the Sacred Site. Across 1,225 HP-loss events, there was one landed hit on a worker and no Town Center damage. River also had home-building damage. This demonstrates active combat and a strong center focus, not sustained fighting on multiple fronts. Mixed difficulties and three seeds do not establish civilization balance.

The current 88x88 maps already have three broad routes and two stocked expansion compounds per side. At the authored Open Plains waypoints, straight segment lengths are approximately 3,264 world units through center and 3,472 / 3,518 around the flanks: only 6.4% / 7.8% farther. At base Warrior speed 55, those routes imply 59.3 / 63.1 / 64.0 seconds before path discretization, obstacles and collisions. Home-to-Sacred straight distance gives a Scout lower bound of 18.9 seconds at speed 100. These are geometry calculations, not measured trips. Both expansion centers are about 986 world units from home, but only 448 apart; direct worker travel is 16.4 seconds and infantry can cross that separation in 8.1 seconds. Actual routes can take longer. First paid camps appeared at 28–32 seconds; second camps at 164–342 seconds. Final observed mean natural-resource haul distances were 228–318 world units. There is room for economic decisions, but the traces do not show frequent expansion raids.

The runtime AI does not consume the authored flank waypoints. Its target selector ranks visible enemies and remembered targets, including a Sacred-area bonus, then falls back to the public symmetric spawn. The new tactical change does not replace that selector or add flank navigation. A future route experiment should prove useful off-center pressure and reliable wave progress before changing map size, stock, pathfinding or victory time.

## What changes

At population limits of 80 or more, Medium and Hard now assign at least their existing attack threshold and otherwise 75% of living fighters to a Sacred contest. A hostile retained victory clock with 120 seconds or less remaining recalls the full force, including when the site is currently contested. Nonurgent contests permit the existing field-offense path to use the unassigned surplus. This is one existing tracked wave, not an extra independent wave system. Recalled members leave wave tracking immediately; survivors retain their target and accepted orders. The progress watchdog is rebased only when membership shrinks. Committed wounded fighters retain their center orders rather than alternating retreat and attack each decision.

The contest borrows only the necessary nominal home reserves when its other candidates cannot fill that force, preserving an active opening even with just two fighters. Actual home danger still preempts objectives and field offense. Easy, population limits below 80, economy planning, training, costs, unit statistics, match clocks, maps and networking retain their existing behavior. This improves force assignment; it does not claim a new raiding strategy or faster human input.

## Existing 100-population economy targets

The beta7 budget helper caps `SkirmishData.get_economy_target()` at 30, but the live AI calls it only below 80 population. At 100, `_get_target_villager_count()` still starts from Easy 12 / Medium 18 / Hard 22, adds 2 at Feudal and another 4 at Castle, subtracts 3 under pressure with a minimum 10, then takes the maximum with the next-age villager gate (plus 1 under pressure). Feudal gates are 11 / 12 / 12; Castle gates 18 / 16 / 14. There is no next-age gate after Castle. These are planning targets, not guaranteed worker counts.

| Difficulty | Dark / Feudal / Castle targets | Targets under pressure |
| --- | --- | --- |
| Easy | 12 / 18 / 18 | 12 / 19 / 15 |
| Medium | 18 / 20 / 24 | 15 / 17 / 21 |
| Hard | 22 / 24 / 28 | 19 / 21 / 25 |

The tactical patch leaves this formula unchanged. Changing the population ceiling or its budget helper alone did not make the live 100-population AI use a 30-worker target. Baseline end banks had low food (17–113) and substantially more gold (380–1,520), so any later economy/progression adjustment needs its own paid comparison rather than being inferred from housing capacity.

## Verification

Focused assignment/lifecycle regressions passed: 1,261 new assertions with real actors, 42 existing armed-garrison assertions, and the existing attack-wave arrival/loss/retarget/timeout/relaunch regression. Independent static review identified and resolved wounded-unit order churn and the stale distance watchdog after partial recall.

The first candidate comparison was rejected and stopped. Its 240-game-second partial receipt had no damage: at 200 seconds each side had two fighters but zero center assignments because both were held as nominal home reserves. The corrected candidate borrows only the reserve deficit and adds two-, three-, five-, eight- and nine-fighter checks through the real strategy seam. The rejected trace is preserved without a completed-match claim.

The corrected isolated comparison completed naturally. It copied the preserved French/English Plains seed 101 Medium/Medium baseline and replaced only `ai_controller.gd`, with fresh private preferences and the same 1,200-game-second / 600-wall-second bound. The source hashes stayed unchanged during the run, and there were no runtime errors or warnings.

| Measure | Baseline | Corrected candidate |
| --- | ---: | ---: |
| First paid fighters, owners 0 / 1 | 122.52 / 134.52 s | 122.52 / 134.52 s |
| Feudal, owners 0 / 1 | 150.02 / 150.02 s | 150.02 / 150.02 s |
| First HP loss | 184.22 s | 184.22 s |
| Natural French Sacred victory | 531.72 s | 498.97 s |
| Damage events | 418 | 647 |
| One-second bins containing HP loss | 106 | 183 |
| Kills by owners 0 / 1 | 32 / 2 | 39 / 4 |
| Wave destinations within 324 world units of Sacred | 15 of 15 | 2 of 8 |
| Buildings lost by owners 0 / 1 | 0 / 0 | 0 / 1 |

The opening timings match exactly, resolving the rejected candidate's delay. Later the French retained two Sacred guards while their field wave advanced toward the English paid camp at world position (672,1296); a 432-second order targeted that camp. The English lost one building and paid for a third camp while their observed camp count remained two. This is evidence of off-center camp pressure, not a measured count of simultaneous combat fronts or an authored flank maneuver. Neither side took worker or home-area damage, both finished in Feudal, and the longest quiet interval after contact stayed almost unchanged (58.55 versus 58.85 seconds).

The corrected run took 246.33 wall seconds. The baseline ran with different CPU contention, so that wall-time difference is not a performance improvement claim. One seed cannot establish balance or human pacing. Runtime checkpoints are `5f98cb0` and its required opening correction `9176284`; the session artifacts `large-army-strategy-comparison.json` and `large-army-focused.log` retain the compact receipts and checks. No map, economy or further AI expansion was added after the corrected comparison.
