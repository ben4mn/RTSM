# Compact skirmish design notes — 29 September 2026

The target is the economy → production → counters → battlefield pressure loop at 20/30/40 population. These budgets are deliberately small experiments; the workforce ratios and timings below are our design judgments, not published Age of Empires balance rules.

## Primary-source reference

Age of Empires II counts workers and troops toward population, requires capacity before training, and expands capacity with Houses, Town Centers and Castles. Its standard limit is 200; each unit consumes one slot. Villagers gather and deposit resources, and farms take over when natural food runs out. Our cavalry and siege consume two and three slots respectively, so a 10-slot army is smaller than ten bodies. [Official AoE II resource/population guide](https://www.ageofempires.com/learn-to-play/control-resources-aoe2/)

The official military guide emphasizes varied armies and resource allocation that follows the current plan. Archers counter most infantry, spear units counter cavalry, and cavalry counter most archers. Unspent resources represent labor that could support another need. Our existing simplified Infantry/Archer/Cavalry triangle approximates those roles; it is not a full AoE II unit roster. [Official AoE II military/economy guide](https://www.ageofempires.com/learn-to-play/military-and-economy-aoe2/)

AoE IV's introductory progression teaches gathering, Villager production, drop-off buildings/housing, armies and age advancement. Its Art of War scenarios teach economy, counters, terrain and siege in separate steps. Its victory conditions include destroying landmarks and maintaining Sacred Sites. [Official AoE IV quickstart](https://www.ageofempires.com/news/quickstart-guide-age-of-empires-iv/)

AoE II supports adjustable zoom; reducing zoom exposes more battlefield and assets. The official documentation supplies no fixed sprite-to-tile or pixel ratio. Camera and visual scale should therefore be judged using the actual phone viewport, readable armies, and the amount of usable battlefield visible. [Official AoE II display/zoom guidance](https://support.ageofempires.com/hc/en-us/articles/360049024131-Tips-for-Optimizing-Age-of-Empires-II-Definitive-Edition)

## Proposed small-budget progression

| Budget | Mature workers | Military population available | First field attack packet |
| --- | ---: | ---: | ---: |
| 20 | 10 | 10 | 3 troops |
| 30 | 15 | 15 | 3 troops |
| 40 | 20 | 20 | 5 troops |

Workers grow to an opening threshold first. The next expansion to the mature half-budget workforce follows the first ordinary attack; otherwise new workers consume every food deposit and the opposing army appears after the objective timer has nearly finished. The scout secures an uncontested site alone. A home guard appears once the remaining field force can still launch its normal attack packet. A hostile site or actual base attack remains urgent regardless of this opening sequence.

Only the compact policies change. Large scenario/test budgets (80 and above) keep the established AI tables. Difficulty continues to change decision cadence and strategic commitment; both sides receive the same banks, costs, caps and unit stats.

The 40-budget economy is the cost reference. Lower-budget age costs scale through shared SkirmishData/GameManager APIs; the 20-budget Feudal cost has a 250-food/125-gold floor. Population providers stop at the match maximum. Duplicate Town Centers, barracks and other production buildings are omitted from these small economies. Paid queues and loss replacements remain transactional.

The existing military plan tried Infantry first on every unpressured decision, so other units could never enter the queue while Infantry remained affordable. Compact production now ranks living plus queued military population, with a bounded preference for counters to currently visible enemies. Essential Lumber Camp and Mill drop-offs precede the Archery Range; the Range precedes optional support/upgrade buildings after Feudal, so its unlock can actually happen on a small wood income.

## Verification limits

`tools/test_compact_ai_policy.gd` covers equal caps, room for soldiers, reachable age gates, no excess housing, no duplicate production and fog-fair counter decisions. Existing AI strategic, economy and integration tests explicitly use the legacy 200-cap policy and still pass.

`tools/probe_compact_ai_match.gd` runs the real main scene at a fixed 60 Hz simulation. The human side retains normal opening gather assignments and issues no further orders; these probes demonstrate AI liveness and transactions, not competitive fairness or player enjoyment. Its optional attrition mode applies two clearly recorded soldier deaths after the first attack and measures paid replacements. It grants no resources or population.

The initial 20-budget Medium probe exposed late offense: first attack 330 seconds, Feudal 210 seconds, 5 peak troops, and only 1 paid replacement before a 361-second unopposed Sacred victory. After compact labor and opening changes, the same seed launched at 212 seconds, reached Feudal at 296 seconds, peaked at 7 troops, and produced 5 paid troops after the explicit two-soldier loss. These are intermediate tuning results; final longer objective-timer and contested-match measurements are recorded separately in output/aoe-feel.

## Final contested-match evidence

These six runs use the production main scene and a Medium bot issuing the normal human placement, training and age-up transactions. Gathering, construction, resource spending, population reservations, combat and victory rules are real. The opponent uses the normal Medium or Hard AI. Both sides begin with the selected cap and the same 200 food / 200 wood / 100 gold. No economic bonus was observed. The simulation runs at fixed 30 Hz with 3× time, giving 100 ms simulation steps; this is engineering liveness evidence, not a competitive balance rating.

| Cap / opponent / seed | Enemy first attack | First actual contact | Enemy peak workers / troops | Enemy army trained | Enemy kills / losses | Troops trained after first loss | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 20 / Medium / 101 | 217.5s | 223.3s | 10 / 10 | 19 | 11 / 10 | 15 | unresolved at 1200s |
| 20 / Hard / 202 | 224.0s | 229.3s | 10 / 10 | 26 | 18 / 16 | 22 | unresolved at 1200s |
| 30 / Medium / 202 | 234.0s | 239.8s | 15 / 15 | 35 | 44 / 20 | 31 | unresolved at 1200s |
| 30 / Hard / 303 | 234.0s | 239.5s | 15 / 4 | 24 | 0 / 32 | 20 | Sacred Site held for 10:00 |
| 40 / Medium / 303 | 261.0s | 266.8s | 20 / 20 | 23 | 22 / 3 | 17 | Town Center destroyed |
| 40 / Hard / 101 | 296.0s | 300.7s | 20 / 11 | 38 | 9 / 38 | 32 | Sacred Site held for 10:00 |

The after-loss production metric includes continued army growth as well as replacing casualties; it is not an exact count of replacement soldiers. Deaths and subsequent paid queues demonstrate sustained replenishment without free units. Three cases reached a real ending: one Town Center destruction and two ten-minute Sacred victories. Three remained contested at the 1,200-second probe limit.

Archers appeared in five of six enemy armies: 20 Medium, 20 Hard, 30 Medium, 30 Hard and 40 Hard. Their per-type observed peaks were respectively 2, 4, 2, 2 and 3 Archers. The 30 Hard side repeatedly replaced losses under base pressure; the 40 Medium side filled its army with Infantry before the later Range unlock. Cavalry and Siege were not observed in these final cases. Later unit composition and faster resolution of stalemates remain useful next balance questions.

All six enemy economies reached Feudal; three reached Castle during the contested match window. Maximum committed population stayed within each selected budget. Essential wood/food drop-offs must precede a construction-bank reserve: the first attempt to reserve the Range before those drop-offs reduced income, so the final order preserves them and temporarily increases wood labor until the Range foundation exists.

Raw results and minute-by-minute economy snapshots: `output/aoe-skirmish/selfplay-{population}-{seed}-{difficulty}.json`. Concise comparison: `output/aoe-skirmish/ai-matrix-summary.json`. Simulation parameters and source SHA-256 hashes: `output/aoe-skirmish/ai-match-manifest.json`.

## Live control checks after the comparison runs

Two complete 30-population browser games reached Town Center defeats: Medium at 13:18 and Easy at 13:41. The second opening completed a naturally staffed Barracks and House and produced nine Infantry; the opposing army produced 25 troops. The match recorded 15 human unit losses and 10 opposing losses. These hands-on games exercised real construction, paid recruitment, camera controls, combat and endings.

Live play exposed building facades losing taps to nearby unit/resource discovery rings, a paid foundation receiving no worker while all workers were walking, and repeat production failing to resume after a shortage. The final controls give visible building faces deliberate selection priority, assign a reachable walking worker when needed, preserve carried resources and existing building jobs, and retry paid repeat production when resources or housing recover. Repeat now names the unit and displays ON/OFF within the initial phone viewport.

The final focused suite passes 56/56 in `output/aoe-skirmish/focused-suite.log`, including natural House/Barracks completion, cargo deposit, repeat recovery and facade selection at three zoom levels. Physical phone comfort and later Cavalry/Siege composition remain the next playtest questions.

A final current-source 30-population Medium smoke (seed 404) reached a human Sacred victory at 929.925 seconds with clean diagnostics and equal starting resources/caps. Actual contact began at 247.225 seconds. Both sides trained 15 military units, and the opponent trained 11 troops after its first loss. This was a one-sided game: the opponent never launched a field attack and stalled after losing most workers. It demonstrates a functioning match ending and also exposes economic recovery under pressure as unfinished balance work. Evidence: `output/aoe-skirmish/selfplay-30-404-1.json` and `final-selfplay-30-404-1.log`.

## Final playtest build

The final staged source SHA-256 is `e47d8fcde5a30ac9867b1885c513a0e5bf509ee7ef3476412e7a07c76f5b66ed`, exported to `build/aoe-skirmish`. The temporary HTTPS preview is https://adjustments-partnerships-aye-breaking.trycloudflare.com/ and requires the local server on port 8768 and its Cloudflare tunnel to stay running. The remote version manifest matches the staged build and the WebAssembly payload returns HTTP 200 with the correct MIME type.

Final browser verification at 844×390 exercised Settings → 30 population → Easy skirmish, Town Center selection, zoom-in, paid Villager training and the visible Repeat ON control. Screenshot: `output/aoe-skirmish/final-phone-preview.jpg`. The browser was left at the main menu and its temporary viewport override was reset.
