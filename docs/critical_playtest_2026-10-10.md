# Critical mobile playtest — 2026-10-10

## Change list and rationale

The gameplay improvements and mobile density pass below are implemented. Costs, AI difficulty, capture speed, and the ten-game-minute Sacred hold rule are unchanged.

1. **Make the objective findable and understandable.** The old neutral site had no HUD entry, its timer was passive, and a contest silently froze the clock. A persistent 48px Sacred Site control now focuses the objective without dropping the army selection. It reports neutral, capture percentage, holding, contested, and disrupted states. Site inspection works, and the visible capture boundary matches the actual detection radius. Locating the objective does not reveal fogged units or terrain.
2. **Make queues reachable with a tap.** The old phone shelf required discovering an 11px “Swipe for queue” hint. A 48px Queue/count control now switches to queue management and back to training. Changing producer resets the shelf; refreshing the same producer preserves queue inspection. Swiping remains available.
3. **Explain stalled production and unaffordable buildings.** Repeat previously stayed ON with an empty queue and no reason. It now shows missing resources, population capacity, or construction status. Waiting Repeat still exposes Clear, which turns Repeat off. Build cards display the current shortage; age-locked cards keep their unlock requirement. Selected foundations show construction percentage or “Needs builder” after work is interrupted.
4. **Give new villagers useful resource rallies.** Tapping a visible resource with a Town Center selected now sets a gather rally. The TC visibly explains this action and shows its current resource or ground rally. New paid villagers approach the last observed location, gather and deposit through the existing fog-aware worker behavior. A normal ground rally clears the gather intent, and later direct orders override it.
5. **Let rallying reinforcements defend themselves.** Armed units now use attack-move on production rallies, engage visible enemies, and retain the rally destination. Scouts and ground-rallied villagers keep ordinary Move behavior.
6. **Make attacks actionable.** Real damage to owned units and buildings creates a named, throttled, 48px alert. Tapping it focuses the attack location. Healing and zero-loss building calls do not trigger an attack alert.
7. **Explain finite farms accurately.** Selected farms show remaining food. Natural exhaustion says to build another farm and no longer counts as a building lost in combat; destruction by damage retains the loss and destruction notice.
8. **Use phone space more efficiently.** The Queue/count control lives inside the bottom production shelf, beside the recruitment or cancellation controls. The Town Center shelf uses compact costs and keeps its rally cue and training progress visible. Worker, army and info-only foundation shelves also size to their contents while preserving the information widths, fonts and actions. Build categories size to their contents: Defence uses a single full-width card in a roughly half-width sheet; larger categories retain three visible cards and a peek at the next one. The mobile camera starts closer when the Town Center and visible food fit, and automatically fits that opening economy when a seed places them farther apart. Home preserves deliberate zoom changes.

## Baseline observations

Played the deployed `d87e54c41995` build in Chromium at 844×390 using simulated touch, ordinary resources, the guided opener, and Medium difficulty. Paused to inspect controls and switched to 3× for longer production/combat intervals. This is a desktop browser phone-size simulation, not physical-phone evidence.

The opener successfully reached gathering, paid House placement, Scout training and movement. Building the Barracks consumed the normal 150 wood. An AI raid killed workers and housing; recovery training reached the reduced housing cap. The selected TC still displayed Repeat ON with an empty queue, no visible waiting reason, and the queue controls off the initial scroll page. The enemy Sacred clock was visible, but could not focus the objective. The partially built Barracks also illustrates why interrupting a builder during a raid requires attention. The match ended naturally in defeat at **13:35**, with “Sacred Site held for 10:00,” five units lost and one building lost. The army count was one Scout; this poorly defended run is usability evidence and does not establish that Medium needs a balance change.

Baseline screenshots are `output/playwright/critical-baseline-*.png`. The separate `output/critical-play-2026-10-10/gameplay-audit/baseline.json` contains deterministic main-scene probes for resource rallies, forced military movement, contested countdown and farm exhaustion. Those probes use ordinary paid production plus explicitly labeled synthetic building fixtures; they are behavioral regression evidence, not hands-on balance results.

## Try the improved controls

- Select the Town Center, tap a visible tree or berry bush, then train a villager. Its rally is shown in the information shelf, and the new villager gathers after reaching the resource. Tap clear ground to set a normal ground rally instead.
- Queue units, tap **Queue (count)**, use **Undo** or **Clear**, then tap **Train** to return. Clear also stops an empty, waiting Repeat order.
- Select your army, tap **Sacred Site · tap to view**, then tap the ring on the battlefield to send the army there. The locator keeps your selection. Any living unit can capture; enemy presence pauses the hold.
- Tap a named attack alert to check the fight. If construction says **Needs builder**, select a villager and tap the foundation to resume it.

## Validation and release

The first gameplay candidate is committed as `07036f2522a1`. Its full Godot suite passed **86/86**, Python tests passed **28/28**, and canonical/witness exports passed checksum closure, production-content audit, source-manifest equality, and substantive reproducibility. Staged source SHA-256: `88a234f020db5dd8c863230f0e1d161fc2d55c0d4ad2751f71dbf30b831f6d84`.

Played that exact export at 844×390, Easy, seed 424242, using simulated touch and ordinary costs. Direct Queue → Undo → Train worked; the TC accepted a Food rally and paid villager production. Built a paid House and Barracks, trained Warriors, enabled Repeat, focused the fogged objective with the producer selected, and set a ground rally near it. Reinforcements reached the site and fought; the enemy clock visibly paused at 9:28 during the contest. Repeat later stalled with zero queued units and correctly showed “Need 10W”; its Queue page exposed Clear. Browser console errors: zero. Initial imprecise tree/berry taps are retained in the screenshots as unsuccessful targeting attempts; the accepted resource rally is explicitly labeled.

The later `53ef9fc` density candidate reached **Guide stage 4** in the phone browser after paid House construction and Scout production. That browser session subsequently became `about:blank`; Guide completion and a match outcome were not observed on that candidate.

Played the final `3e1e3519be2b` export at 844×390, Easy, seed 42, Guide ON, ordinary resources/costs and audio OFF. The four-step guide completed after gathering, paid House construction, paid Scout recruitment and a ground movement order. Both the 700×158 Economy sheet and the 334×150 Defence sheet were inspected in the actual browser. The worker and Scout shelves retained all four readable commands.

With the TC selected, a visible berry bush accepted a Food rally. Two paid villagers reduced the Food bank by 100; the Queue page exposed Undo/Clear/Train, Undo removed the pending villager and refunded it, and the accepted Train tap returned to recruitment. The Sacred locator focused the fogged objective while retaining the producer. After restoring the Food rally and training another paid villager, the worker count showed three Food jobs, and a selected worker showed **Returning Food — Cargo Food 10/10** at 3:45. Console: zero errors and warnings. Screenshots are `output/playwright/critical-final-*.png`; shots tagged `accepted` identify the accepted Train, Home and restored resource rally. Earlier coordinate attempts after selection changes or queue resizing include ground rallies and a Scout More panel, and are retained as diagnostic attempts rather than counted as successful navigation.

### Final density and evidence limits

Selection-shelf measurements below are logical Godot Control bounds. They use a 72px height and at least 48px action targets. Ordinary unit information retains its existing fonts and widths; compact TC information uses an 11px name and 10px details so the rally and production progress fit. Build-sheet rows identify their native or browser measurement scope separately.

| Context | Measured size | Evidence scope |
| --- | --- | --- |
| Worker / army commands | 432×72 | Normal phone profile; content ends beside Clear instead of leaving the former empty tail. |
| Info-only House foundation | 166×72 | Information and Back remain available. |
| Town Center recruitment | 399×72 | Villager, Scout, Repeat and the pinned Queue control remain visible. |
| Town Center queue | 406×72 | The mixed Villager/Scout fixture shows both groups, Undo, Clear and Train. |
| Defence build sheet | 334×150; 404×150 with “Again” | The wider state accommodates the repeat-build label. |
| Economy build sheet | 700×158 | Actual 844×390 phone-size browser measurement at normal UI scale; native profile sizes vary. |

The narrowest 844×390 Large/notched worker corridor caps its shelf at approximately 420.48×72. Its existing horizontal scroll makes the complete Clear target reachable. This pass keeps the 120px unit information width, 148px info-only width and 64px command widths. The Siege Engine queue group grows naturally to 75px, so its full name and count fit with the cancellation actions.

The native Godot readability check covers **12 profiles** in phone-sized SubViewports: two phone sizes, UI scales 1.0/1.075/1.15, and full or synthetic notched safe areas. It checks settled text and Control bounds, all six production names with maximum queue badges, costs and roles, worker/army/foundation density, full target reachability, and the More controls. Measurements are recorded in `output/aoe-iteration/mobile-readability.json`. The native screenshots in `output/critical-play-2026-10-10/mobile-audit/` use actual match scenes with fixture-controlled resources and production progress; they establish shelf layout and text visibility. Real simulated-touch dispatch, paid refunds and producer navigation are separate focused regression checks. These results do not establish physical-phone touch accuracy or performance.

The camera check covers **24 profiles**: two phone sizes, seeds 42/101/424242, Guide ON/OFF, and full or synthetic notched safe areas. It uses frozen real main scenes and projected sprite, flag and marker bounds to check the Town Center, a local worker and known starting food against the HUD overlays. It also checks Home, deliberate zoom preservation and fog behavior. `output/critical-play-2026-10-10/camera/framing.json` and the native renders are geometry evidence; this camera matrix does not test Large UI scale, physical devices or sustained gameplay. The ordinary-cost browser sessions above provide the paid-play evidence.

### Final candidate binding

The final runtime commit is `3e1e3519be2b`. The canonical export is `build/critical-mobile-final-2026-10-10`; the witness export is `build/critical-mobile-final-repro-2026-10-10`. Both `version.json` files record source-tree SHA-256 `86d5dad7dcf6d6c3a34451b59434f9672b2023615260d3dce8a968c75a166244` and `source_dirty: true`.

All **87** focused Godot checks have passing final evidence. The full frozen-runtime run passed **86/87**; its sole failure was the fog test's `FakeVisibilityMap` lacking the new camera-interaction method. Test-only commit `e0f118b` updated that contract and added assertions for hidden, single and double recalls; the isolated rerun passed with clean diagnostics. Runtime and export source did not change. The full-run and rerun logs remain separate, with their coverage recorded in `output/critical-play-2026-10-10/release-focused-coverage.json`. Python tests passed **28/28**, headless boot was clean, and both exports passed checksum closure, production-content audit, source-manifest equality and substantive reproducibility. The export's dirty metadata includes existing historical reports and this documentation, excluded from the production source manifest.

Promoted the verified canonical export to Debian release `releases/3e1e3519be2b-20261010`, atomically changed `site/current`, and restarted only `aoem` and `cloudflared`. Both dedicated containers are running with `unless-stopped`, and Docker is enabled at host boot. Nginx configuration and all copied checksums passed. The previous `d87e54c41995-20261010` release remains available for rollback; deployment configuration did not change. Runtime and test changes are pushed to the existing [GitHub repository](https://github.com/ben4mn/RTSM).

The public [game](https://game.4mn.org/index.html) returns the exact final revision and source hash. **20/20** public files pass exact decoded payload hashes, trusted HTTPS certificate/hostname checks, MIME, WASM/PCK gzip and no-store headers. Evidence: `output/critical-play-2026-10-10/public-payload-verification.json`. A fresh public browser at 844×390, Easy, seed 42, Guide OFF and audio OFF booted, accepted a Food rally, charged the normal 50 Food for a villager, and opened the compact Queue/Undo/Clear/Train shelf. The public console has zero errors and warnings. Close old game windows and reopen online to let an installed service worker pick up the new release.

Physical-device touch, audible audio, sustained phone performance, offline behavior and broad difficulty/balance tuning remain outside this pass.
