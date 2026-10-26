# Mobile polish validation — beta.10

Work was split into controls/combat (#1), presentation/production (#2), and economy/audio (#3), each in a separate Git worktree. Three Astra Ultra agents worked bounded implementation passes and stopped before integration. Integration used ordinary tooling and actual browser play; no additional Ultra agents were launched. Account-wide weekly usage rose from43% at start to56% at the final checkpoint; account usage is not an exact task-token measure.

## Changes

- Shared vector crest and wordmark, illustrated village medallion, gold primary action plaques and quieter navigation on web and in-engine Home.
- Persistent selection during rapid repeated ground/enemy taps and camera navigation. Holds append passive waypoints; Attack remains explicit. Numbered formation routes are deduplicated to avoid stacked labels on tiny screens.
- Ordered production-building rallies, queued owned-depot deliveries, invalid-target skipping, fresh-order/Stop cancellation, and owner-validated protocol8 commands/snapshots.
- Building assaults briefly retaliate against actual attackers, then resume the prior valid building target. Explicit unit attacks and fresh player orders take priority; autonomous pursuit remains bounded.
- Stable recruitment layout, active progress/time, waiting counts, cancellation/refunds and repeat state. Secondary guidance is available through touch-accessible Info controls. Clear replaces a clipped Stop all label. Existing malformed punctuation was repaired.
- Two double-output starting workers and two-pop ordinary recruits preserve the modeled workforce/army investment with fewer physical actors. Single-worker Undo now works after the workforce reduction. See the economy document for prices, travel math, alternative rejected and balance limits.
- Forty-six edited Kenney CC0 recordings replace synthesized playback. Shared work cooldowns, visible-source gates, gain, voice priorities and variation control overlap. Source originals, licenses, hashes and transformation script remain in the repository.

## Actual browser play

Desktop browser input at667×375 landscape, with tap-like clicks, held presses, drags and wheel zoom. This is not a physical touchscreen test.

The beta9.1 baseline visibly lost scout selection on repeated ground taps. In the candidate, repeated moves retained the scout through pan/zoom/re-entry. Multiple holds appended destinations, and fresh taps replaced them. A Town Center with two queued rally stops produced two paid workers that followed the route. Three consecutive recruit taps stayed in place; cancelling a waiting worker refunded100 food and released2 population. Queue inspection and return preserved recruit placement.

Played normal gathering, a queued chosen Town Center delivery, House construction, gold reassignment, Feudal advancement, Barracks construction, three paid warriors, and defensive rally orders. Repeated friendly selection/enemy taps beside the Town Center and Barracks produced attacks and defeated an enemy. Used Army/Select fighters and the Sacred shortcut, then issued a group route toward the contested site. The match ended naturally in a Sacred defeat at8:14. Deliberate UI inspection makes this unsuitable as a skill or win-rate benchmark.

This play exposed duplicated waypoint labels across formation members and clipped queue wording. Both were changed; the route regression now verifies shared and distinct routes separately.

A separate staged browser encounter used the real Main/selection/unit/combat code with AI and fog progression disabled, one friendly Warrior, an enemy House and a24HP attacker released only after an actual building hit. Manually selected and attacked the House twice; both cycles logged actual attacker damage, retaliation and return to the same House. Fresh ground taps then replaced the assault. This isolates command behavior; the staged attacker health and free entities are not balance evidence. The reproducible scene is `tools/playtest_assault_resume.tscn` and is excluded from production exports.

## Automated and rendered evidence

Integration passed: combat order priorities; military role/timing and actual damage; live congestion/navigation; population100 (493 assertions); queued destinations (28 assertions); worker Undo; population reservations/refunds; production feedback across ten size/scale combinations including667×375; sample-bank scheduling/headroom/nonrepetition; economy rates/cargo/real deposits; Farm ownership/harvest/deposit loops. A real local WebSocket server and two clients passed room creation/join/map agreement/cancellation/recovery at protocol8.

Implementation passes also passed gesture dispatch across eight phone profiles, hold/pan/pinch cancellation, area selection, long-press context,192 pan/re-entry cases, menu layout4335 assertions, and compact HUD profiles. One broader mobile hold journey reached its60-second cap after three profiles without an observed assertion failure; it is not counted as a pass. No full repository suite was run; older unrelated scenario fixtures still contain one-pop/50-food assumptions.

The production export is a committed archive ofcd0f8ca, protocol8, source tree SHA256 aa315184cc313fb3f4bbbe17c0cb864645e81e616cfd22379638b64cdef9377a, payload manifest SHA256 224acd0cfa2437a40535706086adf53121a6db77c42a1b28678cb1a28ca5492d. Its strict staged payload check excludes tools/debug sources. Later commits only document validation and refine the excluded manual test scene.

## Limits

No iPhone/Android hardware, physical pinch gestures, Safari installed-app audio, or speaker/headphone listening judgement was verified. Sound-bank tests establish playback data and scheduling, not subjective quality. No public deployment or public online match was performed; protocol8 needs a matching server rollout. Controlled paid balance runs had a360-second wall-time limit and do not certify late-game pacing, every map, matchup or win rate. The economy report records both encouraging early-contact timing and the observed income/pressure differences.

Final production smoke: fresh launch at667x375, corrected opening punctuation, paid recruitment, queue navigation and the fully visible Clear label verified. No browser warning/error entries were reported for the final origin. PR #4 is open and mergeable; there are no configured GitHub status checks. The local preview remains at http://127.0.0.1:8901/. Older preview and staging servers were stopped.
