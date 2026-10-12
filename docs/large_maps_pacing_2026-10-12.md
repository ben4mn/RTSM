# Larger battlefields and camera pacing — 12 October 2026

## Verified baseline and investigation

The pass started from clean, pushed `main` at `4e21e51263076ff801427e21d52e5a5c7a99e7b2`. Public runtime `8e6fe0ecfb78`, version `0.1.0-beta.2`, matched the handoff and canonical export. Independent trusted-HTTPS checks matched all 27 payload hashes; SSH confirmed the active relative release link, rollback, origin configuration and dedicated service identities. The runtime/documentation commit difference was intentional.

Public browser play used Easy, Standard, seed `424242`, 932×430, at 1× until Pause at 1:06. Visible controls bought a Scout, three Villagers and a House, and sent the Scout to contest Sacred. The private report `PK-C1B77176A5C7` confirms the seed and clean loaded/served runtime. Screenshots and its private local download are under ignored `output/playwright/large-maps-20261012/before/`. This short opening is investigative evidence, not a completed match or balance trial.

Three consequential problems define this pass:

1. **Too little room to explore.** Every population option used the same 48×48 map. Increase the battlefield to 72×72 (2.25 times the area), retain fair nearby opening resources and reachable attack lanes, and add finite expansion pockets that require scouting. Verify reflection, real deposit routes, terrain variety and expansion reachability across seeds.
2. **Abrupt zoom with a restricted overview.** Wheel/buttons jumped 16%; fractional wheel input was treated as a whole notch. Ease wheel/button intent around its world anchor, preserve direct pinch behavior, expand overview range, and verify actual dispatch, interruption, GUI isolation and reduced motion.
3. **Economy and distance can delay useful choices.** A wider map adds travel before armies meet. Compare shared gathering rates and resource inventories with ordinary paid policy runs on `424242`, `202` and `404`. Keep exact cargo, finite stock, costs, refunds and population accounting; compare real deposits and counter access rather than claiming a source-rate increase is the same as income. Target typical 8–15 minute games while retaining early aggression; do not claim that range without evidence.

Fresh evidence belongs under `output/evolution/large-maps-20261012*` and `output/playwright/large-maps-20261012/`. Frozen test stages have unique preferences/output paths. Automated paid policies and visible-control matches are reported separately.

## Camera implementation and focused evidence

Mobile overview now reaches 0.42 instead of 0.62; desktop reaches 0.4 instead of 0.5. Detail limits remain 2.2/2.5. Wheel and +/- controls accumulate reciprocal 12% steps, easing over 0.18 real seconds around the rendered terrain beneath the pointer or view center. Fractional wheel events retain their smaller distance; oversized wheel factors are bounded to one step. Pinch and magnify follow contact motion directly. Panning, centering, new contacts, modal changes and resize retire pending zoom. Reduced motion applies steps immediately.

Actual dispatched wheel, magnify, touch and HUD-button regressions pass, including rapid reversal before an animation finishes, repeated +/- presses, bounded factors, every intermediate anchor, all four overview corners, cancellation and reduced motion. Eighty recorded intermediate samples had maximum anchor error below 0.0002 world units. Both phone dimensions, all three UI scales and ordinary/notched safe areas retain routed target hits at 0.42, 0.62 and 2.2 zoom.

Native rendered framing produced 42 screenshots on the larger map, including opening guidance, simulated safe areas, detail and overview. The rendered contact matrix and ordinary paid HUD training/Repeat checks also pass. These are native-window and synthetic-contact fixtures, not physical phones. Evidence is in `output/evolution/large-maps-20261012-camera/`; a first native fixture stage omitted its icon and was repaired in that stage before the clean retained rerun.

The broader suite then exposed three genuine Center failures behind held Info cards. At a map edge, minimum zoom can fail to clear the card even though an intermediate zoom fits: the legal camera boundary limits how far the subject can move on screen. Center now scans downward for a feasible bracket before refining the closest fitting view. The original 130 Center cases, all 36 held-card cases and a new explicit non-monotonic framing regression pass. Another 36 native screenshots verify the held panels, retaining selection and gesture ownership. A verbose exit warning identified only audio mixer references; the fixture now stops playback and drains 150 ms before exiting, and the final native run is clean. No runtime audio behavior changed.

A separate actual Web preflight exercised eased wheel overview and a dispatched two-contact pinch at 932×430, then resized to 844×390 and reached the same 0.42 overview. The private local report `PK-6F630064E9AA` records completed eased steps, pinch ownership/release and the correct seed, with no error/warning counters. The visible Settings text correctly identifies 72×72 for every population limit. This was deliberately a dirty preflight (`4e21e5126307`, source `9d33bfae07849943a2331930c9252c28882b0b03919088b8f43cebd21bdc5be7`) while balance work continued, not final-match or performance acceptance. Its screenshots/report are in the separate `preflight/` directory.

## Map and economy design

Every population preset now uses 72×72 terrain. Opening pockets still contain four berries, eight trees and two gold mines per side. Each side also has two mirrored expansion pockets beyond opening vision; each pocket has 400 food, 1,000 wood and 400 gold of finite stock. Random lakes, forest clusters and resource pairs increase without multiplying the protected opening bank. The clear work perimeter is guaranteed; the surrounding approach is verified by seeded path tests rather than a new corridor carved through every map.

The 64-seed map check covers reflection, starting drop-off access and all 1,792 expansion harvest endpoints with solid Town Center footprints. The separate inventory probe rejects missing paths and uses actual unit speeds. On seed 424242, an unopposed infantry trip between starting bases grows from about 41 to 69 seconds; a Scout trip grows from 22 to 38 seconds. These are route estimates, not battle-duration measurements.

The shared gathering cycle changes from 1.5 to 1.15 seconds. Food retains its 1.2 work multiplier; wood now also uses 1.2, while gold remains 1.0. Starting banks, unit/building costs, ten-unit cargo, finite source stock and unit strength are unchanged. Effective delivered income still includes travel, congestion and drop-offs. The source fixture verifies seven food, seven wood and six gold work units over 7.5 seconds, plus exact stock, cargo, deposits and upgrades.

An initial blanket speed increase made replacement Warriors easy to fund while the paid policy delayed wood-heavy counter buildings. A separate wood-rate experiment improved the 424242 Control race from the fresh baseline's 15:35 to 12:59, with Archers and Horsemen present earlier. This is one automated policy observation, not a promise of match length. The old exploration policy also let three trapped workers exhaust all 196 shared geometry leads by issuing failed trips. The final candidate comparisons below use the corrected search policy, where actual vision completes a lead and failed movement cannot consume another worker's chance to investigate it.

## Regression coverage

A fresh isolated run covered 126 Godot cases. Four failures were stale assumptions about the old map or reused screen positions: fixed 48×48 perimeter coordinates, old far corners, an empty-ground point subsequently occupied by a moving villager, and a placement drag that snapped to its original tile. Their fixtures now use canonical map geometry or refresh the observed target, retaining and strengthening their behavioral assertions. The fifth failure was the real held-Info Center issue fixed above. All 126 distinct cases pass across the broad run and focused repairs; this is not represented as one clean full rerun. Audio fixture shutdown now drains the mixer before exit where required. Intentional rejected production/population/egress warnings remain diagnostic assertions.

The later Settings and lesson copy checks pass in a fresh isolated stage: all 12 phone/scale/safe-area profiles retain 48-pixel primary targets, scrolling and pointer containment. A custom 360-second site status displays 6:00 instead of a hardcoded timer. These checks are in `output/evolution/large-maps-20261012/settings-copy/`.

## Preservation and evidence limits

The welcome page, optional browser play, installation guidance, safe update protocol, release notes, protected live-match/Pause/results/report states and private collector remain in scope for preservation. The existing 52 Python checks, 18 worker/updater cases and private Web-report checks passed at baseline. Cache cleanup was reviewed and deferred: deleting predecessor caches without proving that no late navigation needs them would weaken release coherence. No observed quota failure justified such a change in this gameplay pass.

Desktop phone-size viewports and dispatched contacts do not establish physical-thumb comfort. Physical-phone play, actual installed-PWA lifecycle and subjective audio remain unverified unless separately recorded below.

## AI expansion-search recovery

The 72×72 Standard paid-policy trace on seed `424242` stopped depositing AI wood at exactly 2,000, the eight opening trees. A separate 610-second instrumented replay preserved all costs, commands and vision while logging navigation. Three workers at tile `(64, 5)` never changed position: they issued 179 geometry search orders between 8:21 and 9:53, each failing four navigation attempts. Issuance nevertheless consumed all 196 shared waypoints, so other workers had no expansion leads when nearby wood later ran out. This demonstrates shared-search exhaustion; it does not establish that the trapped workers themselves can escape their enclosure.

Search now reserves an accepted route for its own worker and completes the waypoint only when current vision reveals it. Interrupted or failed trips release the reservation, leaving the unseen destination available to another worker. A worker that finds no accepted trip gets at most two geometry route checks before a 15-second retry cooldown. Geometry remains derived from public map dimensions; natural resources still require current visibility, resource memory remains plain last-seen position data, and the reservation contains only an own-worker weak reference and accepted endpoint. Transient military/scout vision does not preemptively retire the map before economy search examines it. No unit navigation, grants, costs or hidden-resource targeting changed in this fix.

Seven focused checks pass on final AI source SHA-256 `206e2d6d75e89c88e9977d55fda42965f4f599dbe64c26409016e6966e54ce6f`, each exit 0 with no runtime warning/error:

- `test_ai_exploration_recovery.gd`: 392 trapped-worker decisions preserve all 196 unseen leads, with 80 route checks over 588 simulated seconds. A second worker then physically follows its route, reveals a destination, gathers and deposits exactly 10 Wood through the real Villager and ResourceManager transaction. Replacement Move ownership and incidental vision are also checked.
- `test_ai_resource_deficit_search.gd`: one missing-wood explorer, productive fallback, stale/fresh memory, visible-threat avoidance, retreat ownership and exact carried cargo.
- `test_ai_economy_recovery.gd`: visibility-safe recovery, cargo transactions and ordinary paid build order.
- `test_compact_ai_policy.gd`: equal budgets, age/army/population and counter-composition contracts.
- `test_ai_live_vision.gd`: canonical current-vision admission and last-seen memory.
- `test_ai_strategic_policy.gd`: fair difficulty, objective, defense and rebuilding decisions.
- `test_ai_freed_reference_cleanup.gd`: safe cleanup of freed unit, building and wave references.

These are controlled regressions, with explicit blocked-route/visibility setup where stated; the ten-Wood deposit is not a measured ordinary-match income rate. Final paid match comparisons are separate evidence. Exact logs, source hashes, unchanged-position navigation samples and the replay receipt are retained in `output/evolution/large-maps-20261012-ai-search/ai-search-receipt.json`. The temporary editor import generated the new test UID and recreated four unrelated missing test UIDs from cache; those unrelated files were not copied into the repository.

## Final pacing decision and paired evidence

Standard remains the default and now requires four minutes of retained Sacred ownership. Contests pause the clock, retreat before completed neutralization resumes the same owner's clock, and losing ownership resets it. Optional Control race keeps its established four-minute bank for each player across ownership changes. Starting banks, costs and unit strength are unchanged. This is a pacing improvement to evaluate further, **not evidence that typical games already fit 8–15 minutes**.

The fresh automated comparisons use Medium policies on both sides, population 30, fixed 60 Hz simulation and time scale 1. Player zero buys through ordinary human construction, training and age transactions; neither side receives grants, injected losses or a forced ending. Baselines preserve the original 48×48 gameplay and AI. Final candidates include the 72×72 terrain, shared work/wood changes and corrected exploration policy. They compare the complete pass, not a pure gather-rate effect or human play.

| Seed and mode | Fresh baseline | Final candidate | First Archer, player / AI | First Horseman, player / AI |
| --- | --- | --- | --- | --- |
| 424242 Standard | Unresolved at 20:00 | Natural end at 19:41 | 10:21 / 11:03 → 8:12 / 8:40 | 11:33 / 11:47 → 8:24 / 8:54 |
| 202 Control race | Natural end at 16:39 | Natural end at 18:24 | None / 7:22 → 6:34 / 5:43 | None / 8:32 → 6:53 / 6:09 |
| 404 Control race | Natural end at 17:23 | Natural end at 14:51 | None / 7:13 → 8:01 / 6:21 | None / 7:30 → 8:24 / 6:45 |

The negative result on 202 is material: a broader counter game lasted longer. Both sides landed all three counter bonuses in the final cases; baseline player zero never produced an Archer or Horseman on 202 or 404. At the ten-minute progress sample, player-zero wood deposits rose from 760 to 1,560 on 202 and from 820 to 1,512 on 404. The final Standard deposited 3,002 / 2,892 wood, beyond the protected opening forest. Its geometry-search counters remained zero because ordinary revealed-resource gathering sustained this sequence; the separate trapped-worker regression directly verifies the search fix, rather than assigning it causal credit for these deposits.

The corrected-AI, final-wood six-minute Standard experiment also capped at 20:00, with a largest sampled retained hold of 239.68 seconds at 19:41. Sampling was every 20 seconds, so that is not an exact maximum. The otherwise identical four-minute experiment ended naturally at 19:41. It provides a defensible shorter ownership requirement while preserving real contests and paid counters, but still exceeds the requested duration range. No further timer variants were fitted to this policy. There is no pooled duration statistic across modes, no typical-human duration claim and no demonstrated few-minute aggressive finish; visible-control matches provide separate observations.

All completed final invocation receipts verify immutable disk sources, cached loaded-script hashes, equal starting resources and no economic bonus. The Control traces are named `final-six-v2`: their manifests contain an inactive 360-second Standard constant because they ran before the final Standard decision. Their active Control target is the unchanged 240 seconds, and their remaining gameplay sources match the four-minute Standard stage. This narrow manifest difference is retained explicitly rather than relabeling the traces as byte-identical release source.

The older `standard-six` experiment is different again: cached hashes prove it loaded wood multiplier 1.0 before an attempted staging edit to 1.2. Its natural 17:09 result belongs to that blanket-rate, old-AI experiment and is affected by the observed wood-search failure. The provenance correction and raw record are preserved. Likewise, the earlier 12:59 wood experiment used the old AI and is not the final pacing result.

The selected four-minute mobile objective fixture and distinct Standard/Control ownership-reset rules pass in a separate frozen test stage. Custom 600-second telemetry and dynamic lesson-duration coverage also pass; an initial telemetry command incorrectly named a nonexistent scene, so its error log remains alongside the successful `--script` rerun. Full traces, manifests, comparison tables, source-cycle tests and map inventories are under `output/evolution/large-maps-20261012-balance/`.
