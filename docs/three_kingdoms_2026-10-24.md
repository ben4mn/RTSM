# Three kingdoms — integration notes, 24 October 2026

`0.3.0-beta.1`, runtime commit `d4830dc9fc4196336d9a1840679bbd1a4d7d567f`, is live at https://game.4mn.org following the coordinated protocol 2 cutover at **04:14:14 UTC on 24 October 2026**. The acceptance record below distinguishes committed artifacts, local and public automated witnesses, and ordinary rendered play. Later guide, camera, learning and movement experiments are outside this deployed release.

## Kingdom rules and presentation

`CivilizationData` supplies one shared catalog for the local simulation, online authority and owner-aware UI previews. Kingdom choices persist as next-match preferences; active matches latch their identities independently.

| Kingdom | Specialty | Tradeoff |
| --- | --- | --- |
| Crownlands | Baseline combined arms and full building health | No specialized gathering or signature-unit bonus |
| Verdant League | Wood harvesting per tick ×1.20; Longbow replaces Archer with range 6 and vision 7 | Longbow 30 HP; Horseman 65 HP |
| Sunstride Clans | Food harvesting per tick ×1.15; Outrider replaces Horseman with speed 110 | Outrider 70 HP; building health ×0.80 |

Gathering multipliers affect harvested work, not travel or free resource grants. Signature units keep the existing unit IDs, costs, counters and production buildings. Shared base dictionaries remain unchanged; unit/building queries resolve the owning player's kingdom.

The menu offers player and solo-rival selection, with original crests and an explicit confirmation. Online rooms display both public identities. Protocol 2 carries the server's ordered kingdom pair into match setup and snapshots; a guest remaps its own server slot to local player 0 before replicas are created. A peer may change only its own lobby identity, before host Start. This requires a coordinated client/server release; old clients must refresh.

Longbow and Outrider SVGs have distinct equipment and silhouettes, plus matching enemy palettes. Longbow uses a tall bow and light hooded protection. Outrider uses a light rider, curved saber, small shield and streaming scarf. Their imported alpha, neutral materials, 128px canvas and ground anchor are checked against the existing unit scale conventions.

## Mobile army and economy

Army now has **Recruit** and **Groups** pages. The first opening offers Recruit when no armed fighters exist; a Scout alone does not count as a fighting force. Each surface remembers its selected producer. Recruit lists owned military producers and reuses the existing paid training, Repeat, refund and rally requests. An empty Recruit page offers a priced Barracks action through the normal placement/confirmation flow. Foundations appear with training disabled until construction completes. Economy retains Workers and all-producer Train access.

The Workers summary uses a short, single-line food alert so larger text still fits above the command dock. After twelve startup seconds and six continuous gameplay seconds without food workers, the closed Economy launcher reads **No food**. Food work clears it immediately; recovering workers suppress this alert. **Food low** considers the deduplicated visible berry supply within 192 world units of currently worked visible berries, rather than warning whenever one small patch is nearly empty. It is a nearby-supply hint, not a pathfinding guarantee. Job counts remain on their chips. Farm guidance explains that its builder starts farming on completion, preserving existing cargo and respecting the Farm's single-worker claim.

## Checks completed in this working session

- Signature art: 42 headless and 47 native assertions passed; five rendered galleries cover both phone sizes, two zooms and owner markers. Evidence: `output/civilization-art-20261024/`.
- Army recruitment: four native ScreenTouch profiles passed at 844×390 and 932×430, default and largest interface scales. Default scale uses the HUD's own deferred layout; largest scale includes a synthetic notch. Checks cover paid Barracks placement/cancel, construction gating, exact Warrior payment/refunds/reservations, Repeat, rally, producer filtering/memory, rejected enemy/unaffordable requests, food-alert grace/recovery and zero GUI world orders. All four retain the selected producer. Evidence: `output/army-recruit-20261024/native-final/`.
- Existing strategy journey: twelve phone/scale/notch profiles plus 550×338 logical stress passed. Army field notes and selected-unit death/context preservation each passed twelve profiles. Their fixtures now explicitly choose Groups.
- Packaging: seven Windows Web builder tests, seven server-context builder tests and eighteen Web-shell artifact tests passed. The nested-manifest regression failed before the one-line verifier correction and passes afterward: only the root checksum manifest is exempt from file-set closure.

These are controlled functional/rendering fixtures, not physical-phone, frame-rate or full-match duration evidence. Production time is advanced only where disclosed for fixture setup; the paid recruitment fixture uses the ordinary starting bank.

## Server build path and baseline Linux smoke

`tools/prepare_match_server.py` is a reusable committed-only CLI. It resolves one revision, ignores checkout edits, rejects unsafe/existing output paths and archive entries, disables Git checkout line-ending conversion, strips developer configuration, imports with Godot 4.6, rechecks committed inputs and seals the complete context. Usage:

```sh
python tools/prepare_match_server.py --revision COMMIT --godot GODOT_BINARY --output build/RELEASE-server
```

The promoted tool reproduced all 466 original input hashes and the sanitized project from the beta.13 baseline commit `ebdd07f539a9`. Separately, the existing sealed baseline context passed a disposable Linux Docker smoke in candidate `windows-baseline-smoke-20261024022103-1a897e0e`. All 799 runtime hashes and the exact file set matched. The server reported ready and exited 0, with no runtime errors or OOM, under UID 10002, no network, read-only root, dropped capabilities, no-new-privileges, 768 MiB, 1.5 CPUs and 128 PIDs. Both deployment locks were held. The disposable container was removed; live container identities/start times, live image tag, release pointers and Compose hashes stayed unchanged. Evidence: `output/windows-baseline-server-smoke-20261024/`.

That historical smoke validates the Windows-to-Linux packaging path for the old baseline, **not** the kingdom release. The later d483 artifact and public acceptance are recorded below; match-duration assessment remains separate from functional acceptance.

## Historical follow-up checkpoint (935, not deployed)

The committed `93582e322396` frontend was built twice and passed substantive reproducibility, sealed file-set, production-exclusion and stock-WASM checks. Its matching server context passed a separate Linux smoke with all 831 runtime files matched and protocol 2 ready. At that checkpoint production was still beta.13; it was not the later d483 cutover.

The next development checkpoint added witnessed counter-unit loss advice to results (including recipient-private online results), offline background pausing with explicit Resume, context-aware opening reminders, visible paid-queue counts, clearer Repeat/rally explanations, kingdom-aware producer copy, an earlier Food low cue from existing observed food facts, and stable management-tab positions. At that checkpoint focused battle/online-result and lifecycle checks had passed; expanded mobile UI and full integrated acceptance were still pending. These historical checks alone were not release acceptance.

A completed935 browser match used only visible controls at932x430: Sunstride vs Crownlands, Medium, Woodland Flanks, natural Defeat11:07,21contests,135vs180seconds of Sacred control,32vs39troops produced,31vs29lost,6230vs7427resources gathered, both sides ending in Castle Age. All buildings, units and upgrades used ordinary costs. This is one tool-paced rendered match, not a physical-device test or a duration average. Earlier notes describing keyboard A as attack-move were corrected: A pans the camera; the completed11:07 match used the actual Attack control.

The local two-client browser harness verifies matching committed artifacts, redirects only the exact shipped socket endpoint to its own loopback authority, rejects public sockets, and records source/transport/cleanup receipts. Its initial lightweight guard/provenance tests and short authority startup/cleanup passed before the completed d483 paired gameplay recorded below.

Late AI scouting and mixed-army marching are separate experiments. Neither is part of this stable development checkpoint.

## Rendered follow-up before final acceptance

A second committed browser match, on `c323e885bbc2`, ended naturally at 10:56: Verdant versus Sunstride, Medium, River Crossings, 844×390. The player produced 50 troops to the AI's 43 but lost 49 units to 32, gathered 4,710 resources to 7,285, and stayed in Feudal while the opponent reached Castle. The visible result correctly reported 22 Warrior losses finished by enemy Archers and recommended Horsemen. The match used ordinary costs and visible controls, with explicit pauses for separate test windows. It is game-clock evidence, not a wall-time benchmark or match-duration average. The requested design target is a good ordinary game around 11 minutes, an average up to 14, and 20 minutes exceptional; victory timers have not been changed to manufacture that result.

Actual exported Chrome testing confirmed that a paid solo queue and clock pause while the tab is hidden and remain paused until Resume. A separate rendered rotation check exposed gameplay continuing behind the portrait blocker; the follow-up guard included that blocker and its exact JavaScript passed browser tests. Full exported rotation acceptance was still pending at that checkpoint. Online matches remain live.

The management header now anchors below the resource bar across pages. Geometry checks cover 143 states over 13 profiles, including both food warnings, with no overflow. The former hidden-node minimum-size approach was rejected after regression tests caught unlaid-out wrapped labels moving the header. The final Army Recruit, Economy Resilience and Strategy Overview contact regressions pass on an explicitly frozen source overlay. Matching committed exports/server context, two-client gameplay and guarded deployment were the remaining gates at that point; their d483 results follow.

## Accepted live release: d483, 24 October 2026

The canonical Web export `build/mobile-release-d4830dc-web` and its independent reproduction matched all 39 sealed files, substantive content and source closure. The matching committed server context passed Linux readiness and all 835 runtime-file checks under the documented hardening. Runtime identity is `d4830dc9fc4196336d9a1840679bbd1a4d7d567f`, version `0.3.0-beta.1`, protocol 2. Web manifest SHA-256: `a696450c573ab7e59d7a947b7a1c4563ec6314e69c310d9edf69999808d9925d`; server manifest: `6ed1fb80bc9651f38644093acd2d756c765a6fec5a375741d83b765b335e5a2c`.

The guarded cutover replaced only the online service at 04:14:14 UTC and moved the matching static/server pointers. Its original public `urllib` verification received HTTP 403 with Cloudflare 1010, so `activation-attempt1.json` remains **FAILED_NO_AUTOMATIC_ROLLBACK**. This failure was not overwritten or retrospectively renamed a pass. A separate stock-curl check with verified TLS then passed all 40 decoded public files, hashes, required headers and private-path denial, plus runtime/hardening and unrelated-service checks: `public-postflight-curl.json` records **PASS_READ_ONLY_POSTFLIGHT** at 04:16:15 UTC. No second restart, rollback or security relaxation was used. Both receipts are retained in the session workspace `yo/work/d483-release-preflight/`.

### Matching local and public touch witnesses

The matching local pair passed first using a private authority and exact shipped-endpoint redirection to loopback; no public socket was allowed. It used two 844×390 native Chromium touch contexts, real kingdom/lobby/paid Villager/Attack/result/menu taps, and ordinary paid protocol orders for the disclosed gameplay policy. The server ended the match naturally at 854.0 seconds, with 795 same-tick samples and 7,000 shared actor fields agreeing. Artifacts and the private runtime stayed unchanged, and owned processes were cleaned up. Evidence: `output/overnight-civilizations/paired-touch-d483-second/`. The earlier pre-start verifier failure is preserved separately in `paired-touch-d483-first/`; its narrow generated-UID correction accepted only identical sealed `.gd.uid` derivatives with matching committed parent scripts.

The subsequent public pair used **https://game.4mn.org/** and the actual **wss://game.4mn.org/match** endpoint, with no redirect. Verdant League and Sunstride Clans were selected through the picker, and protocol 2 room, match and recipient snapshot identities agreed. Both clients passed all **36 acceptance gates**. Their 809 common snapshot ticks and 6,544 shared actor fields had zero mismatches; there were no shared resource tiles to compare. The live authority ended match 1 at **862.4 seconds**, winner 0, `Sacred Site held for 3:00`; both rendered results displayed **14:22**. The remote container ID, image, start time and zero restart count still matched the cutover receipt afterward.

Read-only timing of those received snapshots found 860.645 game seconds over 860.610 host and 860.715 guest browser-arrival seconds. Each client's seven 120-game-second windows stayed between 0.9990 and 1.0019 game seconds per arrival-wall second. Thus this public two-player authority stayed near real time through the observed match. Peak recipient-visible packet actor counts were 42 and 43, not full-world unit counts. This is not server CPU, rendering FPS, physical-phone or AI-load evidence; network and browser scheduling are included. The source-bound calculation is `yo/work/public-d483-snapshot-throughput.json`.

| Public recipient | Outcome | Army produced | Units lost | Buildings lost | Gathered | Signature births / observed final blows |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Verdant League | Victory | 38 | 24 | 1 | 9,320 | 10 Longbows at 30 HP / 7 final blows witnessed by the opponent |
| Sunstride Clans | Defeat | 47 | 33 | 1 | 9,024 | 9 Outriders at 70 HP / 2 final blows witnessed by the opponent |

Both result lessons matched the recipient's bounded observed combat facts: enemy Archers finished five of the host's Warriors, suggesting Horsemen; enemy Longbows finished five of the guest's Warriors, suggesting Outriders. Counts and text were transcribed from inspected screenshots and checked against each recipient's terminal packet. Both clients returned to the actual menu through native taps.

A supplemental touch Age Up witness succeeded on both clients. The guest's single tap changed its visible bank from 2,179 food / 175 wood / 300 gold to 1,579 / 175 / 0 and its authoritative age from Feudal to Castle, exactly charging 600 food and 300 gold. The host also advanced on one tap; its first auxiliary assertion reported an 899-resource debit because it omitted concurrent Sacred Site gold. That failed receipt remains intact. Separate accounting over retained surrounding snapshots and the sealed 2-gold-per-second implementation reconciles the exact cost, explicitly as an income inference rather than an additional transaction event.

Public evidence: `output/overnight-civilizations/paired-touch-d483-public-first/`, particularly `analysis.json`, `public-authority-identity.json`, `public-source-final.json`, `process-cleanup.json`, both terminal/screen-review receipts, and the paid-age receipts. Revalidated analysis SHA-256: `ffa4702a4dc301584800ac4bd5521ee1636ed9c25fcffd817aaf896a8236dce4`. The preceding `07fab7e73467dbb36e6233bb48f4739a85a533215cd1a7f98013bbb7e64c4033` report remains byte-for-byte in `analysis-before-review-fixes.json`. No browser console/page/socket/HTTP errors or warnings occurred. Browser/controller processes closed cleanly; the sealed artifacts remained unchanged.

### Evidence limits and remaining experiments

These automated pairs are separate from the root agent's ordinary CUA play. They exercise Chromium's native touch translation, not a physical phone, soft keyboard, handset frame rate or human reaction time. The gameplay policy uses ordinary costs and gathering, grows toward 12 workers, builds up to six paid Farms, and deliberately sends the host to Sacred and the guest home after 650 seconds. The public run paused only that command policy around 6:51–7:49 to save ordinary wood, and again after the scheduled Sacred/home orders to perform the touch age-up checks; simulation, gathering, paid queues, combat and the hold timer continued. The policy then resumed unchanged. Its natural terminal time is **not** a normal-human pacing average or proof of the 11–14-minute target. Ordinary solo sessions with pauses or attention gaps, including the later 3:42→5:40 unattended interval, also cannot supply clean pacing estimates.

The public fixture retained 21 authoritative placement rejections: host two `Outside map` and eight `Choose clear, visible ground`; guest eleven `Choose clear, visible ground`. The scripted placement search has a known visibility/perimeter limitation. Requests are not counted as completed buildings or signature births, and no resource, clock, state or result was injected to satisfy a gate. The policy does not cover Resource Camps.

Browser-captured version and JavaScript bodies directly match sealed SHA-256 hashes. Chromium could not retain the large service-worker WASM/PCK bodies, and all four body-read failures remain recorded. Their actual 200 responses' ETag, Last-Modified, MIME and encoding match the independently TLS-fetched and SHA-256-verified public postflight responses. This is **correlated deployment evidence**, not a claim of browser-body hashing. The local run instead correlated browser response IDs/headers to its owned byte-verifying server.

The hardened tooling passes 15 Node cases (one optional real-Chrome guard smoke skipped in that unit run) and 21 Python evidence cases. Negative checks reject missing protocol, revision, required hashes, body proof, TLS success, header files, matching validators, or safe header paths. Protocol 2 civilization, signature, Attack and reviewed result/menu gates remain mandatory in public mode. An initial independent review closed missing-protocol and missing-digest bypasses. A later review reproduced three further synthetic gaps: two absent manifest hashes comparing equal, a contradictory captured body hash being masked by validator fallback, and aggregate payment accepting 25 food plus 25 gold as a 50-food Villager. Both manifest digests must now be valid; any known body mismatch and controller-client error fails acceptance; Python and JavaScript require feasible nonnegative deposits for each resource. The original mutation receipts and preceding reports remain preserved. All four real local/public Villager transactions still validate at exactly 50 food with unchanged wood/gold, and both complete runs pass read-only reanalysis without replaying gameplay.

The mixed-army cohesion prototype remains isolated in the session workspace and is not in d483. Its focused correctness slot is queued after guide validation and the Woodland AI baseline. It still requires passing tests and ordinary rendered comparison before any integration claim. Later guide, camera and live-learning changes likewise have their own validation and release decisions.
