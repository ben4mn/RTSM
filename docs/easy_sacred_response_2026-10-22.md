# Easy Sacred response — 22 October 2026

A normal early Scout purchase won uncontested before Easy's old response gate on every tested map and seed. The separate 150-second reactive gate interrupts all nine openings while keeping the 300-second ordinary raid gate and 390-second neutral-site initiative. The matched study contains 30 natural paid runs: nine earliest openings, three delayed arrivals and three reinforced openings, before and after. All transaction, path, source, squad and grace checks pass.

## Defect and runtime scope

The original seed101 investigation used clean `c61918e45853`; its two complete runs per map remain under `output/early-scout-investigation/`. One Scout costs40Food/10Gold and normally trains8s. It enters the192-world-unit capture disk at23.42s, completes its30s claim at53.45s, then wins after180s of control at233.45s. Easy sees it around42s and has paid fighters by78–84s, but both objective response and recon return early before300s. The opponent can therefore lose66.55s before it is allowed to respond. No blocked terrain or free production causes this result.

The final matched baseline is receipt commit `6cf0cda669a357ef6554348d2692f42155eaf98e`. Its mechanics reproduce that result. The candidate adds `SkirmishData.EASY_SACRED_RESPONSE_SECONDS = 150.0` and shares `_is_easy_sacred_response_delayed()` between the recon and fighter objective paths. The helper preserves the existing regroup deadline and applies only to compact Easy. The downstream policy still requires hostile public control/contest or a currently visible nearby enemy before neutral initiative opens. Costs, damage, movement, fog and the existing240-unit threat radius do not change.

Frozen runtime SHA256:

- `scripts/ai/ai_controller.gd`: `935ee0485f56b36845adbb70bdb398c56f9d1b447fc77420832d74111ffcdf35`
- `scripts/data/skirmish_data.gd`: `7de3eb1d90294f25f5066ada460369a51b5f66a5ef4a0be97a70a0bfede95c57`

These are the only differences among the11 measured gameplay source files. Every run verifies its actual loaded sources against its frozen project. The [machine-readable receipt](easy_sacred_response_metrics_2026-10-22.json) binds both source sets, the identical probe/runner hashes,30 raw reports/logs and all matched results.

## Natural paid policies

`tools/probe_easy_sacred_response.gd` instantiates actual Main on Easy, Standard mode, population30. Each side starts with its ordinary four workers and250Food/250Wood/100Gold. All normal workers, AI, construction, production, movement, combat, fog and Sacred simulation remain active. There are no grants, extra spawned actors, relocation, direct damage, fog reveal or disabled simulation. Guided opening is explicitly off so its training shortcut cannot affect the8s queue. Headless fixed60Hz/time-scale1 execution measures simulated match events, not render performance or human skill.

The earliest policy buys one Scout at time0 through Main's Train handler, then selects the paid spawn and issues one ordinary passive ground Move to the center. The delayed policy makes the same purchase but waits until180s for that Move; ordinary production rally behavior continues while it waits. The reinforced policy adds a Barracks placement at90s on currently visible legal ground, lets a real worker build it, buys two Warriors and sends each through Main's attack-move handler on birth. Its seven total transactions/orders spend140Food/160Wood/10Gold, including the Scout and Barracks. It uses no retreat, focus fire or other micro.

The runner verifies normal payment, queue duration, legal route waypoints, exact bank-ledger reconciliation, declared purchases, loaded sources, no ordinary field attack or quiet-home damage before300s, and at most three objective fighters before480s. The two sides have identical terrain records, paid Scout completion, ring entry and every sampled Scout position/health/state before150s. All30 processes use distinct private preference directories. Logs contain no errors or warnings.

## Earliest opening: nine matched pairs

The Scout always completes at8.0167s. All nine baselines produce an uncontested human Sacred win with no Scout damage or AI ring entry. Every candidate first assigns its three-fighter contest at150.0167s. The tested150s gate leaves at least60.63s of the old hold remaining when the opponent physically reaches the disk; no120s alternative was needed.

| Map | Seed | Baseline win | Candidate contest | First damage to Scout |
| --- | ---: | ---: | ---: | ---: |
| Open Plains |101|233.45s|172.77s|176.05s|
| Open Plains |424242|233.52s|172.72s|175.98s|
| Open Plains |20261021|233.45s|172.82s|176.08s|
| River Crossings |101|233.45s|172.78s|176.07s|
| River Crossings |424242|233.45s|172.78s|176.05s|
| River Crossings |20261021|233.50s|172.77s|176.03s|
| Woodland Flanks |101|233.45s|172.77s|176.03s|
| Woodland Flanks |424242|233.45s|172.78s|176.07s|
| Woodland Flanks |20261021|233.45s|172.82s|176.08s|

All nine candidate Scouts die at180.38–181.58s. Their matches remain unfinished at the420s observation limit; this is not an AI-victory or draw claim. After the hostile claim decays, the AI returns to recon/staging and withdraws the fighter group. Its first deliberate neutral capture order remains390.0167s in every case. Physical departure and later raid transit can briefly start automatic capture progress, which decays after the units leave. No candidate completes an AI capture before390s. Ordinary field raids begin300.0167s; measured quiet-home damage occurs later.

## Delayed arrival and paid reinforcements

The three seed101 delayed cases enter the ring194.45s. Baselines claim224.48s, then respond300.02s and contest313.13–314.57s. Candidates respond196.02s, after the visible arrival/public capture begins, and contest218.60–218.70s. The Scouts die before completing their first claim. Both sets remain unfinished at420s; candidate home damage still begins after300s.

The reinforced baselines all win uncontested at233.45s. Candidates contest172.78–172.80s and fight the actual paid defenders. The two Warriors deal120/102/114HP damage to AI fighters on Plains/River/Woodland before300s; these figures exclude later home-raid damage. The Scout and both Warriors die by187.10/185.90/186.50s. No AI fighter dies in those initial fights, so these particular cases do not exercise the casualty-triggered regroup. All three candidate matches remain unfinished at420s. Two unmicroed Warriors do not establish a guaranteed defense or a broader counter-price result.

The [independent paired regression](easy_response_regression_2026-10-22.md) supplies the complementary learning-space evidence: three slower paid learners still win with natural losses and paid replacements, and their workers/Town Center/home area take no damage. Medium and Hard controls reproduce every behavioral JSON field exactly. Focused tests separately cover150s boundaries, the45s casualty regroup, home defense, fog and shared squad limits. Earlier objective interaction changes match outcomes and pacing; human beginner balance is not established by these scripted policies.

## Reproduction and limits

```sh
python3 tools/run_easy_sacred_response.py --revision 6cf0cda \
  --extra-scenarios delayed reinforced --jobs 2 \
  --output output/easy-sacred-response-20261022/baseline
python3 tools/run_easy_sacred_response.py \
  --extra-scenarios delayed reinforced --jobs 2 --expect-response \
  --baseline output/easy-sacred-response-20261022/baseline \
  --output output/easy-sacred-response-20261022/candidate
```

Defaults cover three maps and seeds101/424242/20261021. Extra scenarios use the first selected seed. `--project` accepts another frozen source tree; `--revision` snapshots a Git revision while copying the same current probe. The runner snapshots inputs, creates private projects/settings, retains source receipts and rejects stale/mismatched outcomes. Each report includes full bank/production/deposit ledgers, terrain and actual Scout world/tile paths, position samples, AI order changes, losses and site transitions.

A120s development smoke run intentionally ended before both paid Warriors completed; that incomplete plan is excluded from the final30 runs. The earlier output-only pilot used the same150s logic before extraction into the final shared helper; the matrix above uses the exact final hashes. In raw time-limit reports, `winner=-1` and `end=limit_or_fixture_failure` determine the unresolved outcome; Main's dormant default victory-reason string is not treated as a win. The compact receipt normalizes that display. These cases cover one practical early opening and limited reinforcements, not a globally fastest strategy, all population limits, all seeds, touch hitboxes or phone performance.
