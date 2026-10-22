# Easy Sacred response: independent regression — 22 October 2026

The 150-second reactive Sacred response passes the independent learning-space regression. All three slower paid learners still win, with ordinary paid recovery after natural losses. Contact happens earlier and match timing changes substantially. The two Medium/Hard controls reproduce every behavioral field exactly. This supports the narrow response change; it does not establish human beginner balance.

## Source and method

Baseline is clean beta.6 receipt commit `6cf0cda669a357ef6554348d2692f42155eaf98e`. The mechanical candidate is an exact copy with only these two runtime files replaced:

- `scripts/ai/ai_controller.gd`: `935ee0485f56b36845adbb70bdb398c56f9d1b447fc77420832d74111ffcdf35`
- `scripts/data/skirmish_data.gd`: `7de3eb1d90294f25f5066ada460369a51b5f66a5ef4a0be97a70a0bfede95c57`

All 1,260 tracked file hashes are recorded before and checked after the runs. Only those two files differ; both match the shared runtime at completion. Every pair also verifies the source actually loaded by Godot: the learner cases record 49 script/probe hashes, with the same two changes. The paid probe and slower learner fixture are byte-identical. Full local manifests and their SHA-256 digests are bound in the [machine-readable receipt](easy_response_regression_metrics_2026-10-22.json).

The three Easy pairs use seed 101 on Open Plains, River Crossings and Woodland Flanks. Each side begins with four workers, 250 food / 250 wood / 100 gold, a 30 population cap and Standard mode. The probe confirms normal deposits, no economic bonus and no injected worker losses. All extra production, construction, research and ages use the real transactions. The unchanged [slower learner policy](easy_learning_2026-10-22.md) waits 18 seconds before opening, spaces decisions 6 seconds, building inputs 20 seconds and training inputs 18 seconds, starts no Barracks before 90 seconds, and begins field orders at 240 seconds. One natural fighter loss triggers its 45-second recovery. It performs no wounded-unit micro.

The two ordinary-policy controls retain the previous comparison cases: Medium opponent on Plains / 101 and Hard opponent on Woodland / 424242. Both players use the existing paid AI fixture, with player 0 at Medium. All ten full-match processes and both focused tests have distinct private user directories. Simulation is fixed at 60 Hz and time scale 1; wall times are not performance measurements.

## Slower learner outcomes

All six before/after outcomes are learner Sacred victories. The baseline reproduces the prior beta.5/beta.6 learner results exactly.

| Map / seed 101 | End seconds before → after | First damage before → after | Damage-active seconds before → after | Longest quiet gap before → after |
|---|---:|---:|---:|---:|
| Open Plains | 703.13 → 487.48 | 294.13 → 272.77 | 50 → 35 | 61.75 → 69.50 |
| River Crossings | 670.67 → 631.22 | 294.08 → 283.05 | 32 → 37 | 71.37 → 61.33 |
| Woodland Flanks | 677.28 → 523.40 | 274.87 → 272.80 | 52 → 32 | 74.42 → 70.78 |

The first AI objective contest moves from 300.02s to 258.02s in all three candidate learner cases, after the learner starts field orders at 240s. These are reactive responses, not ordinary base raids. Candidate Plains and Woodland issue no ordinary AI field raid before the learner wins; River's first such order is 330.02s. The 300-second raid gate remains intact.

Every candidate learner suffers a natural fighter loss and produces paid replacements. Time from that first loss to the next paid fighter is Open Plains 8.75s, River Crossings 19.25s, Woodland Flanks 12.48s. Candidate learner workers, Town Center and the measured home area take no damage on all three maps. Earlier response therefore does not remove the tested economic opening/recovery space. Earlier Sacred interaction also leads to shorter learner victories in this limited fixture; it would be misleading to describe the change as a uniform difficulty increase or an unchanged match.

## Unchanged controls and behavioral boundaries

Medium Plains ends at 472.10s with first damage at 150.65s; Hard Woodland ends at 493.85s with first damage at 147.53s. Both match their baseline's complete JSON behavior exactly, including damage events, commands, economic records and snapshots. The only excluded fields are loaded source hashes and private user-data paths. No rounding tolerance is used for the equality check.

Independent source review confirms that the shared helper gates only compact Easy and is used by both recon and fighter objective decisions. It allows responses after 150s while retaining the existing regroup deadline. The downstream policy still requires a public hostile claim/contested state or a currently visible nearby enemy until neutral initiative opens at 390s. Public ownership does not grant hidden-unit targeting: direct target choices still require current visibility. The existing visible-site threat radius remains 240 world units, including a small band outside the capture disk; this pass does not redefine that boundary.

Home defense is checked before objective response and regroup. Ordinary raids still use 300s and their existing cooldown. Neutral initiative remains 390s. Urgent objective redirects clear the old raid and recall unassigned fighters; nonurgent duties share the same three-fighter budget, rising to four after 480s. Assigned field casualties still create one 45s regroup, and retreat deaths do not extend it. Medium and Hard bypass the new Easy-only helper.

I independently ran the author's updated Easy-pressure fixture and the existing live-vision fixture from a separate frozen candidate copy. Both pass without errors or warnings. The pressure fixture exercises 149.999s/150s on all hostile site phases at 20/30/40 population; neutral recon through 389.999s; hidden visitors versus public ownership and visible threats; cleared-site return; ordinary raid grace; bounded redirects and real death/regroup/home-defense transitions. The test controls state to isolate boundaries and does not claim paid-match pacing. The separate earliest-Scout study validates whether the response arrives in time against a real paid rush.

## Reproduction and limits

```sh
python3 tools/run_paid_ai_cadence.py --project <frozen-project> --output <learner-output> \
  --beginner --duration 900 --case 0:101:0 --case 1:101:0 --case 2:101:0 --jobs 3
python3 tools/run_paid_ai_cadence.py --project <frozen-project> --output <control-output> \
  --duration 900 --case 0:101:1 --case 2:424242:2 --jobs 2
python3 tools/run_presentation_integrity.py --project <focused-project> --output <focused-output> \
  --case res://tools/test_easy_learning_pressure.gd --case res://tools/test_ai_live_vision.tscn
```

Evidence is under `output/easy-response-independent/`, with baseline/candidate source manifests, full reports, logs and focused source receipt. Successful runs contain no script/runtime errors or warnings. This validator made no runtime or test-tool edits, public connections, commits or deployments. The comparison covers one slower learner seed per map and two ordinary-policy controls; it does not promise all-seed balance, human learning outcomes or mobile rendering performance.
