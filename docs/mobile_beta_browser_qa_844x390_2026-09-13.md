# Mobile-beta browser QA — 844x390

Date: 2026-09-13

## Status

**PASS — local Chromium touch emulation against the canonical production Web artifact.** This is exact-size browser-rendering evidence, not an outside-human or physical-phone result.

Evidence directory: `output/playwright/mobile-beta/closing-final-2026-09-13/844x390/`

## Candidate and environment

| Field | Final value |
| --- | --- |
| Source revision | `89567778b26e` |
| Dirty state | `true`; preserved user working tree, bound by the staged-source manifest |
| Staged-source SHA-256 | `54ada2e25cdb3c0690ef37580039b78fbe3198be2f21597fccc703b4e6458fa5` |
| Evidence manifest | `docs/mobile_beta_evidence_manifest_2026-09-13.json` |
| Web `index.pck` SHA-256 | `e8cdc4467fcb41eb3f9fb1163d279a758a25d4b59ba76848fc53e2a61649e611` |
| Test URL | `http://127.0.0.1:8060/index.html?release=54ada2e25cdb3c0690ef37580039b78fbe3198be2f21597fccc703b4e6458fa5` |
| Browser | Chromium `152.0.7977.83` |
| Playwright session | `aoem-closing-844` |
| Viewport / canvas CSS / canvas buffer | `844x390` / `844x390` / `844x390` |
| Device scale / touch | DPR `1`; touch enabled; coarse pointer; one touch point except the synthetic two-contact pinch path |
| QA record | `qa-results.json`, SHA-256 `9a71f1562aa564feeffc773728d894ea88cd1b8abe60805df3bba7ff0e0fbbcb` |
| Closed evidence manifest | `SHA256SUMS.txt`, 31 entries, SHA-256 `bc65134865589d757de8afa9db8781d669600728999d9db3593dba65255b7a61` |
| Generated | `2026-09-13T12:21:34Z` |

## Touch-flow result

All 25 PNGs were inspected and have exact `844x390` headers. The sequence proves:

- main menu, Settings, Hard difficulty, seed `424242`, guided opener, Skip, and free-HUD transition;
- direct friendly Town Center selection;
- Villager queue reservation `4/10 → 5/10`, cancellation `5/10 → 4/10`, and the exact 50-food refund after accounting for concurrent gathering;
- Scout production and the stable Move / A-Move / Patrol / Stop / Stance / Clear command rail;
- separate Build sheet, red invalid House ghost with `Blocked terrain`, placement cancellation, and restored normal controls;
- pause held at `01:35` across 1.2 wall-clock seconds, then resume;
- actual touch/CDP camera drag, pinch out/in, minimap drag, and long-press Town Center context;
- supported terminal state and return to Main Menu with Hard, seed `424242`, and guided-opener-off state retained.

The free-HUD capture still shows `Build one House.`. This is the intended non-modal progression hint after Skip: the Skip control is gone and normal Age Up, Build, pause, speed, and minimap controls are available.

## Acceptance results

| Check | Result |
| --- | --- |
| Layout / primary-control clipping | **PASS** — no clipped or blocked primary control |
| Settings / difficulty / seed | **PASS** |
| Free HUD | **PASS** |
| TC production / cancellation / refund | **PASS** |
| Fixed six-command unit rail | **PASS** |
| Build / invalid placement / cancel recovery | **PASS** |
| Drag / pinch / minimap / long press | **PASS** |
| Pause / held clock / resume | **PASS** |
| Ending / Main Menu | **PASS** — Defeat `04:55`; Sacred Site held `3:00`; score `82–288`; gathered `470/1084`; AI sacred control `180s` |
| Console | **PASS** — 3 informational messages, 0 errors, 0 warnings |
| Requests | **PASS** — 30 recorded, 0 unexpected failures; one intentional uncached forced-offline probe failed as expected |
| Offline service-worker reload | **PASS** — controlled client, PCK and WASM cached, uncached probe failed, full `844x390` Pocket Kingdoms canvas reloaded offline |

## Screenshot index

The closed directory contains `01-main-menu.png` through `25-offline-reload.png`, including settings, free HUD, Town Center selection, queued/cancelled production, Build, invalid placement, pause/hold/resume, command rail/actions, all gestures, game over, Main Menu, and offline reload.

## Claim boundary

Reviewer: Codex root, automated assertions plus visual inspection. No outside human or physical phone participated. Real-device ergonomics, browser chrome, notch behavior, accessibility, audio, and long-session comfort remain external validation work.
