# Small sounds, clearer choices — beta7

This pass builds on beta6's soft illustrated French, English and Mongol civilizations. It preserves unit costs/stats, action timing, map generation and existing keyboard/touch commands. The owner added readable units behind scenery, one starting Scout for each player, and a normal population ceiling of at least 100. The new default is 100 per player, with smaller options retained. Protocol 5 prevents older clients from silently interpreting that limit as 30; map catalog 3 is unchanged.

## Design

The [reference review](interface_research_2026-10-24.md) records the previous flow's unclear online entry label, competing setup controls, lore-first civilization comparison and dark map cards. Official Clash of Clans and Age of Empires IV screenshots informed contextual grouping, visible costs/progress and overview-before-detail. Polytopia's official guidance informed comparison by play style. All game artwork remains Pocket Kingdoms' own beta6 assets.

Play solo and Play online now state their destinations. Warm paper map cards retain generated tactical layouts, add terrain traits and distinguish town markers by shape as well as color. The setup summary stays visible, rules have an explanation, and population/seed remain under More options. Civilizations share a consistent illustrated-town, strengths and tradeoff comparison.

In battle, cloth-like grouped surfaces and round utility controls reduce the rigid grid appearance. Recruitment progress appears beneath the relevant portrait. Familiar utility actions use icons; unit/building names, costs and status retain text. Settings has a Guide tab with tappable icon explanations, also reachable from the match menu. Construction's Info mode explains a building without purchasing it.

The [original sound recipes and provenance](tactile_audio_2026-10-24.md) document eighteen synthesized banks, quiet wood/cloth impacts and felt-like plucked accents. Frequent events have restrained nonrepeating variations, shared cooldowns, bounded voice pools and priorities. Hidden/offscreen world effects are dropped. Persistent master/world/interface levels and mutes remain available; browser activation, backgrounding and scene changes discard stale cues.

## Requested visibility and opening additions

During the pass, the owner requested readable units behind buildings, trees and other troops, plus a starting Scout for both players. The rendering observer shows a restrained silhouette only through actual overlaps and only for units already in the local player's current vision. The selection system recognizes the silhouette's actual opaque pixels, so a head/body tap can reach the unit behind the obstruction; collision and targets remain unchanged. Fog still conceals unseen opponents. Town Centers now keep their close footprint selection outline without the large defensive-range circle; Watch Towers retain their useful range preview.

Both solo and authoritative online starts now spawn one Scout per owner through the normal connected-space spawn solver, alongside the existing four villagers. Normal population accounting applies (5/15 at the opening); starting resource banks, building queues and unit costs are unchanged. The guide recognizes a living starting Scout and retains its recruitment fallback if the Scout is lost.

## Population and economy

The [resource and queue calculations](population_economy_2026-10-24.md) budget a 100-population army with 25 workers, the starting Scout and 74 fighters. It requires about 4,880 additional food, 3,970 wood and 60 gold after the opening bank, including nine Houses, fourteen Farms, three Camps and three production buildings. These are arithmetic estimates, not a promised build order or measured human pace.

The normal match limit is now 100, with 20/30/40/60 still selectable. Housing starts at 15 and grows through paid Houses to the selected ceiling. House cards display the actual remaining gain, including the last five slots, and explain when the ceiling is reached. The population explanation separates housing from the match limit. The shared economy helper is capped at 30 workers, but a later branch audit confirmed that 100-population matches retain the pre-existing difficulty/age targets rather than calling that helper. See the corrected population analysis. No live large-match economy scaling adjustment, gathering-rate increase or unit-strength change is claimed.

## Verification scope

Baseline public-browser screenshots were saved before changes at 844×390. Automated menu layout/reflow, civilization, gameplay, housing, audio and online checks accompany native rendered captures and browser journeys. Final counts, paid simulation outcomes and release identity are recorded at publication below.

Browser viewport checks and native renders do not certify physical phones, browser-specific mobile audio, touch latency, safe areas or prolonged performance. The controlled native audio fixture uses actual gathering/construction/production and active combat, with explicitly staged free armies to exercise a busy mix. Its debug-only capture mode keeps that simulation running offscreen; it is not a foreground lifecycle test, ordinary paid match or balance test. Audio input is unavailable to this agent, so the recording and signal/repetition checks do not constitute subjective listening. Separate lifecycle tests cover foreground/background muting and pause behavior.

## Release checkpoint

The published build is committed source `1f2efe48f9d1173151759ca86bf708a95eb85f66` (0.3.0-beta.7, protocol 5). Two independent Web exports passed substantive-file/source-manifest reproducibility, checksum closure, shell checks and content scanning. The matching Linux server passed its disposable smoke check before activation.

Completed verification includes:

- 969 starting-Scout checks across maps, civilizations, both owners and authority/client roles; online protocol-5 startup agreement on all maps.
- 493 population checks across all civilizations and both modes, including paid Houses 15→25→35→100, final partial gain, reserve housing, loss, refunds and queue reservations. These use stepped clocks and synthetic near-cap pressure, not natural pacing.
- 216 real engine ScreenTouch assertions for head/body taps behind roofs, trees and enemies, Move, Attack-move, direct enemy attack and fog rejection. Existing touch-dispatch, zoom, facade, selection-dock and command tests also pass.
- Settings at 12 viewport/scale/safe-area profiles with four tabs, expanded Guide, paused state and contrast assertions; HUD at 13 profiles and selection-dock geometry at 848 assertions.
- 26 Web shell/export unit tests and 21 guarded-deployment tests. Six combat/presentation suites plus the five-case Sacred/result/navigation preservation batch pass. A stale pre-beta6 SVG defensive-fire fixture was corrected in test-only commit `773ff78`; the revised 544 checks cover legacy SVGs and all three illustrated civilizations, both owners and transforms. The original failure is retained in local evidence.
- Controlled native gameplay recordings at 844×390 and 1280×720: respectively 145/156 actual battle hits produced 48/49 audible impacts over about 25 seconds, peak two voices, zero dropped audio frames and zero clipped samples. Overall peaks are about −18 dBFS. Original synthesis recipes/provenance remain documented separately.
- Actual Chrome journeys at 844×390 and 1280×720 verified solo setup, 100 default, starting Scout, paid recruitment, Scout Move, two paid Houses raising capacity to 35, selection without the large Town Center range circle and pause-preserving resize. The final Guide contrast fix was checked in the exported `1f2efe4` build. Mouse/browser viewport checks are distinct from engine ScreenTouch fixtures and physical-device testing. Browser warning/error logs were empty in these checks.

Natural paid automated rounds and the final publication receipt are recorded below. The existing release guard checks active/closing match connections immediately before replacement and retains the previous static bytes, server context and image for rollback. It has an existing short admission race between the socket check and replacement; no force bypass is used.

## Published and verified

[Play Pocket Kingdoms](https://game.4mn.org/). Release `v030beta7-1f2efe48f9d1-d23fe63667-e8c58739d2` activated at 03:53 UTC on 25 October (22:53 Chicago, 24 October). The immediate pre-replacement TCP check found zero non-listening connections. The match service was replaced/restarted with the matching image; static, tunnel and diagnostics container identities and configuration were preserved.

Beta6 static release `v030beta6-a1aabfeb94fe-90136bbe63-a56bbb6f91` remains available with its server context archive and image tag `aoem-online:rollback-v030beta7-1f2efe48f9d1-d23fe63667-e8c58739d2`. No rollback was needed.

The fresh read-only postflight passed public file hashes/MIME checks, 935 active runtime files, protocol 5, hardening and unchanged live identities. Its first attempt rejected an obsolete embedded deployment-helper checksum. A new verifier changed only that checksum to the reviewed protocol-5 guard, passed 15 independent binding/rejection checks, and completed without service mutations; both attempts are retained in local evidence.

Public WSS acceptance passed 40 checks across all three maps using only freshly created private test rooms: host/join, authority rejection, full-room rejection, leave/rejoin, settings/map agreement, both owners' 100 maximum and four workers plus Scout, match snapshots, disconnect results and host cancellation. All test sockets closed. Separately, two independent-client civilization pairings passed 104 checks for French/English and Mongol/French paid advancement, buildings, signature units, replicas, combat and agreed surrender results. This bounded test used the supported 3× clock; it is not a 1× human pacing measurement.

Chrome public acceptance exercised the ordinary cached-beta6-to-beta7 update, Mongol civilization selection, Woodland setup, the normal 100 limit, a free starting Scout, paid Villager recruitment, Scout Move, pause, Settings > Guide expansion and return to the main menu. The Guide title remained readable and browser warning/error logs were empty. Screenshots and WAVs are included in the accompanying local verification report. [Paid simulation outcomes and scope](beta7_paid_rounds_2026-10-24.md) distinguish complete ordinary-cost rounds from superseded partial traces and synthetic capacity tests.

Remaining validation limits: no physical phone/tablet was tested; no subjective audio listening sign-off was possible; the 200-actor observer CPU probe is not a full-game mobile GPU/FPS benchmark. Estimated 100-population build times remain planning estimates rather than measured human build orders.
