# Three kingdoms — integration notes, 24 October 2026

`0.3.0-beta.1` is the current working release draft. It has **not been deployed**. The production service remains on beta.13 during these checks. Implementation, copy and balance may still change during the integrated playthrough; this document is not release acceptance.

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

The Workers summary shows a maximum two-line food-income alert. After twelve startup seconds and six continuous gameplay seconds without food workers, the closed Economy launcher reads **No food**. Food work clears it immediately; recovering workers suppress this alert. Job counts remain on their chips. Farm guidance now explains that its builder starts farming on completion, preserving existing cargo and respecting the Farm's single-worker claim.

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

That smoke validates the Windows-to-Linux packaging path for the old baseline, **not** the draft kingdom release. Final committed-source exports, paired online acceptance, public browser validation, match-duration assessment and guarded deployment remain integration work.
