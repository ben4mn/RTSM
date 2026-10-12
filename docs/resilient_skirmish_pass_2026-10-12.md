# Resilient skirmish pass — 12 October 2026

## Verified starting point

Local and remote main are `5ea06fdcc15e2566ed8e300f5a8688adad25653b`; one checkout, no stash or divergent branch, initially clean. Public version.json confirms clean runtime `3331fc659798`, source fingerprint `b6b4afb8340f0d9e484b54bad276e5bf812dce4654a8adb741dc8ec436131145`. The documentation/runtime difference is intentional.

Played the public build at 932×430, seed424242, Easy, 1× from opening through4:11. Bought a Scout and three Villagers, built a paid Farm, advanced to Feudal, saved Group1, scouted/contested Sacred and reassigned workers remotely. The Scout died at the objective. This is an opening investigation, not a completed acceptance match. Screenshots and private report PK-63B0266A0E93 are under ignored `output/playwright/resilient-skirmish-20261012/before/`.

## Three consequential problems and plan

1. **Economy trouble is diagnosed too late.** Finite Farms are described as steady food; zero-staff warnings do not distinguish depletion, recovering workers, queued replacements, refundable purchases or a lost economy. Add visible-source stock, advance depletion warning, explicit costs and deliberate paid recovery actions. Preserve bank/cargo/reservations/refunds/repeat. Judge by before/after depleted-food and36F/no-worker scenarios and paid recovery tests.
2. **Counter access and objective stalls dominate pacing.** Old paid probes show Feudal around5min but first Archers/Horsemen around9–13min; earlier raids and closer starts barely changed contact. Audit AI fairness, then compare a small number of optional paid-counter/banked-control rules across424242,202,404. Keep standard mode intact. Reject an8–12min claim unless measured; retain scouting, investment, counters and contest/recovery opportunities.
3. **Phone management hides consequential information.** Remote producers omit counter descriptions and show blockers in tooltips; rally confirmation can scroll away; results have no Report action. Add visible blockers/counters/rally feedback and a result Report using private diagnostics. Verify actual contacts, all12 size/scale/safe-area profiles, and complete final paid Easy/Medium matches with normal-speed portions.

## Evidence boundaries

All new evidence uses fresh directories and isolated test/export stages. Old reports remain intact. Desktop browser contacts and synthetic phone profiles are not physical-thumb evidence. Device discovery found only six shutdown iPhone simulators. No installed Pocket Kingdoms PWA was found. This session has no audio-input/listening capability; waveform checks will not be described as subjective quality verification.

## Economy findings and changes

The prior 36-food/no-worker state was economically terminal, not a lost cargo or payment bug: replacement Villagers cost 50 food, Farms require a worker and 75 wood, and finite fields contain 300 food. The AI pays through the same resource, construction, training, population and age transactions. Sacred income is available to either owner. No recovery grants, automatic purchases or unit-stat changes were added.

The Economy rail now signals low worked food, sheltering workers and workforce loss. The sheet totals currently visible berries and owned harvestable Farms, checking visibility before inspecting neutral resource stock. It explains finite Farms, queued replacements, refundable food and the cost of recovery. The paid Farm shortcut enters the existing placement/confirmation flow. Construction, recovering and attacking workers retain their orders.

Remote production now exposes cost shortages, construction, queue capacity and population blockers directly beneath the paid training buttons. Counter roles are visible on the buttons. Producers show their fixed rally destination and offer a Sacred rally through the existing legal setter. Town Center rally text explicitly includes future Villagers. Saved groups display membership counts without implying those members are currently selected.

## Native Web audio and lifecycle

An isolated native Chrome Incognito window ran the unchanged clean runtime `3331fc659798`, served locally with test-only observation of the game's existing audio destination. The observer neither unlocked audio nor synthesized cues. Real visible controls opened Settings, previewed, muted/unmuted, started gameplay, paused/resumed and returned to the menu. The test window was closed afterwards.

The context changed from suspended to running after the first actual pointer contact. Preview peak was 0.1546; muted preview remained zero and unmuting restored output. A real minimize/restore produced 22.7 seconds hidden, with zero output after a 500 ms grace period and successful preview afterwards. The desktop subsequently locked during gameplay; the actual hidden interval lasted 38.4 seconds. All 598 sampled levels after the grace period were zero, and gathering sounds resumed after unlock. Pause was silent for 13.8 seconds, resume restored gameplay output, and returning to the menu left no lingering world sound. The final attempted minimize restored after 0.6 seconds when observed through accessibility; it is not counted as a sustained background test.

Evidence: ignored `output/evolution/resilient-skirmish-20261012/native-audio-lifecycle.jsonl` and `native-audio-lifecycle-summary.json`. These measurements establish routing/lifecycle behavior on desktop Chrome, not subjective clarity, repetition, alarm priority, phone audio or installed-PWA behavior.

## Pacing decision

The initial audit found short travel rather than a distant-front problem: first contact was around 4:43, with raid travel about 16–22 seconds. Paid Feudal arrived around 4:52/5:29, but Archers at 10:20/11:02 and Horsemen at 11:33/11:46. Wood investment, producer availability and repeated objective resets explain more of the inactive time than walking speed.

Three justified candidates were compared with a fixed 60 Hz automated paid policy, separately from browser acceptance. Both players start with 200 food, 150 wood and 100 gold; no economic bonus or forced result is used. Player zero uses the real human transaction routes driven by the policy. The comparison is about game seconds and events, not wall-clock performance or human skill.

| Candidate, Medium seed 424242 | Natural Sacred finish | First Archer, player / AI | First Horseman, player / AI |
| --- | --- | --- | --- |
| A: four-minute bank, paid counter access | 15:54 | 8:18 / 8:45 | 8:44 / 9:20 |
| B: five-minute bank scoring during numerical superiority | 15:31 | 8:18 / 8:45 | 8:44 / 9:20 |
| C: A plus first counter producer before Mill | 15:35 | 7:48 / 8:31 | 8:08 / 8:54 |

Probe times in this table are rounded to the nearest second; raw JSON retains exact simulation seconds.

B was rejected: greater rule complexity saved only 22 seconds and did not improve counter access. Its implementation was removed, with the tested stage retained as evidence. C keeps the simpler contest-pauses-scoring rule and improves the actual production sequence. Every counter relationship landed in these probes; C produced 29 paid army replacements per side after the first loss. First contact stayed at 4:15. These are modest, measured improvements, not evidence of an 8–12 minute match.

The optional mode is therefore called **Control race**, not advertised with a duration. Each side keeps its earned Sacred control across recaptures; the first to bank four minutes wins. Contests pause scoring. Feudal costs 250 food / 125 gold and Barracks, Range and Stable cost 100 wood for either side. The AI still invests in a Farm and Lumber Camp before its first counter producer, with the Mill immediately afterwards. Map size, starts, movement, unit statistics and raid gates are unchanged. Standard remains the default with its previous economy and uninterrupted ten-minute hold.

The additional Control race policy runs ended at 16:39 on seed 202 and 17:23 on seed 404. The opponent AI unlocked both counter producers on every seed. However, the automated human policy failed to unlock either counter role on 202/404: repeated Warrior losses, replacement purchases and finite-Farm replenishment consumed its wood before the Lumber Camp/counter investment. Standard 202 did unlock those roles (Archer 9:55, Horseman 10:59). This is a material policy outcome, not a successful counter loop for both sides or evidence that shorter rules guarantee recovery. The human-facing cost/blocker information and explicit saving/reallocation decisions must be judged separately in visible-control acceptance.

The paired Standard 202/404 probes both reached the 20:00 observation cap unresolved, with all three fighter roles available to both sides. The historical Standard 424242 probe also reached that cap; incoming gameplay-core hashes were checked, but it is labelled historical rather than a final-source rerun. Exact candidate sources, harness hashes, invocation headers, traces and the comparison summary are preserved in ignored `output/evolution/next-pass-20261012/pacing/`. None of these runs lost workers or buildings, so their army replacement counts do not establish worker recovery.

## Phone and input evidence

The new economy fixture passed all 12 rendered profiles (844×390 and 932×430, scales 1.0/1.075/1.15, ordinary/notched safe areas) with actual dispatched ScreenTouch contacts. It verifies paid training/refunds, population reservations, Farm planning cancellation and payment, eligibility, Sacred rally, selection retention and fog/input isolation. Final population-copy edge cases passed all 12 headless profiles. The initial legacy strategy matrix had one failure during a concurrent native Chrome focus transition; that failure remains preserved. An isolated instrumented reproduction passed, keeping the sheet open through every wheel/paid/reassignment action. Focus interference is a supported explanation, not a proven historical cause.

Result Report passed all 12 native rendered profiles, including transformed 48-pixel targets during animation, actual Report/restart/menu contacts and an integrated concluded-match report. The full result history test retains the ended match’s latched rules even after the next-match preference changes and the initial event has been evicted. The Web report dialog correctly returns to the result.

Additional Sacred presentation QA covers both modes across the same 12 profiles: 432 phase/owner/guide text-and-layout cases, 24 actual Sacred contacts, unchanged selection/fog, zero world orders and clear notification lanes. This last matrix is headless engine layout/contact evidence, not a screenshot or device claim. Its fixture inherits the existing live Sacred state-machine check.

Evidence directories: `output/evolution/resilient-skirmish-20261012/economy/`, `output/evolution/kingdoms-result-report-20261012/`, and `output/evolution/resilient-skirmish-20261012/sacred-profiles/`.
