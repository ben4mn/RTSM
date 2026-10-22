# Paid AI match cadence experiments

These are automated policy-versus-policy matches using the normal starting economy, paid construction, training and age transactions, 30 population, and fixed 60 Hz simulation at time scale 1. Player 0 uses the Medium AI policy through the human transaction entry points. No resources, units, damage or victory outcomes are injected. They measure simulated gameplay; they do not establish human APM, phone touch feel or rendered frame rate.

`tools/probe_ai_compact_paid_match.gd` now observes actual unit/building HP-loss signals, damage-active one-second bins, fight bursts separated by more than five seconds without damage, long gaps after first damage, paid replacement production, counter hits, victims' unit roles and strategic decision time. A damage-free terminal tail is included in the longest gap. Fighter-near-enemy and idle durations are summed fighter-seconds, not match duration. The `worker_raid_hits` field means military hits on villagers, which can also occur during defense; it does not by itself prove a deliberate raid.

`tools/run_paid_ai_cadence.py` runs bounded parallel processes, rejects runtime errors, records actual generated archetypes and source hashes, and flags damage-free gaps longer than 45 seconds for investigation. Reports retain detailed snapshots and fight bursts rather than treating a single number as a playability verdict.

## Frozen classic baseline

The baseline runtime was copied before map or combat changes to `/tmp/aoem-paid-baseline-20261022`. Loaded-script SHA-256 values in each JSON report identify that source even while the working tree changes. Each run has a 900-second simulation horizon and exits earlier on a natural result.

| Opponent / seed | First damage | End / horizon | Damage-active seconds | Longest post-contact gap | Military hits on workers, P0/P1 | Outcome |
|---|---:|---:|---:|---:|---:|---|
| Medium / 101 | 150.6 s | 514.2 s | 141 | 33.9 s | 0 / 0 | P1 Sacred victory |
| Medium / 424242 | 151.8 s | 401.9 s | 79 | 38.9 s | 0 / 0 | P0 Sacred victory |
| Easy / 101 | 160.9 s | 900.0 s | 264 | 40.7 s | 0 / 2 | Unresolved at the horizon |
| Hard / 424242 | 147.6 s | 418.7 s | 69 | 46.2 s | 0 / 0 | P0 Sacred victory |

Both Medium first contacts are actual infantry-versus-infantry hits, near the working 2–3 minute target. Both field and land counter hits with Warriors, Archers and Horsemen. Their longest quiet gaps stay below the 45-second investigation threshold. Medium seed 101 produces 55/25 military and 49/11 unit losses, while seed 424242 produces 19/29 military and 6/21 losses; the changed winner is meaningful evidence against inferring a universal outcome from one seed.

Hard's sole gap over 45 seconds is 179.3–225.5 seconds. Its snapshots show the opening army eliminated, then paid replacements in production and moving to contest. This is an observed recovery interval, not evidence that two live armies stopped attacking each other. Easy remains contested and fighting at 15 minutes, so these experiments do not establish that every match resolves within that time.

The baseline is strongly Sacred-centered. The two Medium runs land no hits on workers, so their healthy combat cadence does not establish deliberate economic-raiding variety. No AI policy change was made on the strength of these results: increasing aggression globally would risk shortening recovery without fixing a demonstrated stall.

Evidence: `output/ai-cadence-20261022/baseline/classic-101-medium.json`, and the three cases plus generated summary in `output/ai-cadence-20261022/baseline-matrix/`.

## Archetype matrix before the final fixes

The final map geometry was frozen after its separate topology checks. These six paid matches ran from `/tmp/aoem-paid-maps-20261022`, **with the intermediate spacing candidate and before the final spacing and AI allocation fixes**, with an explicit archetype so saved user settings cannot select a different map. Their unit SHA-256 is `6516c70150e52ad1dc99bca3c9fb8c07de39b1403fb465f7afd8005854e1f0d0`; the classic baseline used `3a20c9b377ebf8ec8b6939a438484286ee8a9e5c1acdc2fa2cf8cb15b0640c4b`. This matrix is not a map-only A/B against the classic baseline. The JSON includes both requested and actual archetype values.

| Map / seed | First damage | End / horizon | Damage-active seconds | Longest post-contact gap | Outcome |
|---|---:|---:|---:|---:|---|
| Open Plains / 101 | 150.6 s | 486.0 s | 135 | 33.7 s | P1 Sacred victory |
| Open Plains / 424242 | 151.8 s | 421.6 s | 102 | 42.5 s | P0 Sacred victory |
| River Crossings / 101 | 150.8 s | 458.0 s | 97 | 34.7 s | P0 Sacred victory |
| River Crossings / 424242 | 152.5 s | 776.8 s | 187 | 137.0 s | P0 Sacred victory |
| Woodland Flanks / 101 | 153.7 s | 900.0 s | 258 | 34.6 s | Unresolved at the horizon |
| Woodland Flanks / 424242 | 147.0 s | 510.0 s | 125 | 39.6 s | P0 Sacred victory |

All six first contacts occur near 2½ minutes, and each run lands real counter hits with all three fighting roles. Woodland 101 keeps fighting through the horizon; its unresolved result is not a long combat stall. All six record zero military hits on workers, so these experiments demonstrate alternate terrain and recurring mixed-army contests, not deliberate raiding variety. Evidence is in `output/ai-cadence-20261022/final-maps/` (the directory name identifies the map freeze, not the final combat runtime).

River 424242 exposed a real late economy defect. During its 627.6–764.6-second quiet interval, the losing side retained one fighter and an idle worker, gathered with 14 Food / 1 Wood, and floated Food from 1,401 to 2,671 while Wood remained 10→5. It repeatedly chose to contest but could not fund replacements. `_rebalance_gathering_villagers()` skipped the entire productive workforce whenever **any** worker was idle. A parked/search-wait worker could therefore block the existing Wood target indefinitely.

The fix removes that blanket idle gate. It retains the existing resource targets, normal rebalance interval, maximum one donor per correction, current visibility/reachability checks, and cargo-preserving gather transaction. No income, costs, unit stats or aggression multipliers change. A focused late-bank regression reproduces the failure before the fix and verifies one Food-to-Wood change, unchanged seven-Food cargo, no bank grants, no interruption of the idle worker, and no second correction before the interval after the fix. The full economy-recovery regression and five adjacent AI suites pass.

## Final runtime confirmation

Three representative paid cases use the frozen final runtime at `/tmp/aoem-paid-spacing-final-20261022`: Open Plains 101, River Crossings 424242 and Woodland Flanks 101. Unit source SHA-256 is `952915c81c13fa1410c8cabf5e5cc57b05093483ec3c2c8258ab055bdf047cc3`; AI source is `b42eeb98ed8287f2d5ad44c75b07dc8a0a3ec94ef46343dce752d9cf3acbcacd`. A separate River 424242 control at `/tmp/aoem-paid-ai-fix-20261022` uses the previous combat runtime with only the AI correction, allowing the allocation change to be assessed separately.

The AI-only River control ends naturally at 695.0 seconds, with first damage at 152.3 seconds, 201 damage-active seconds and a 40.95-second longest gap, compared with 137.03 seconds in the corresponding prior-AI case. Comparing every recorded loaded-script hash confirms that only `scripts/ai/ai_controller.gd` differs. At 600–680 seconds, player 1 retains four Wood workers despite its one idle worker, and paid military queues continue. The outcome also changes to P1 Sacred victory, so this is a whole-match policy comparison, not an identical battle replay with a single late intervention. The focused regression isolates the gate itself.

| Final gameplay case | First damage | End / horizon | Damage-active seconds | Longest post-contact gap | Military hits on workers, P0/P1 | Outcome |
|---|---:|---:|---:|---:|---:|---|
| Open Plains / 101 | 150.7 s | 472.1 s | 132 | 36.4 s | 0 / 0 | P1 Sacred victory |
| River Crossings / 424242 | 152.3 s | 900.0 s | 252 | 41.3 s | 0 / 1 | Unresolved at the horizon |
| Woodland Flanks / 101 | 153.7 s | 900.0 s | 379 | 36.0 s | 0 / 0 | Unresolved at the horizon |

All three retain the working 2–3-minute contact target, land counter hits with all three fighting roles, and have no post-contact gap over 45 seconds. The two unresolved cases remain active contests rather than silent stalls: River records 31/62 kills and Woodland 44/75 kills. River's late snapshots keep five/four Wood workers, with paid replacement production, despite an idle worker on one side. These outcomes support ongoing paid combat and recovery; they do not establish short match duration or balance across every seed. The one military hit on a worker does not demonstrate a deliberate raiding strategy.

Across the 14 runs, ten reach natural Sacred results and four remain unresolved at their 900-second horizons. All paid-match process logs are free of engine/script errors. The final gameplay snapshot predates subsequent visual-only restyling; it is evidence for the recorded gameplay sources, not a rendered-performance benchmark or a claim that the complete release source has the same hash.

Final gameplay evidence is in `output/ai-cadence-20261022/final-spacing/`; the AI-only control is in `output/ai-cadence-20261022/ai-fix-control/`. Adjacent AI regressions are recorded in `output/ai-cadence-20261022/ai-focused.log`. To repeat the representative paid cases against the current working tree:

```sh
python3 tools/run_paid_ai_cadence.py --output output/ai-cadence-recheck \
  --case 0:101:1 --case 1:424242:1 --case 2:101:1 --duration 900 --jobs 3
```
