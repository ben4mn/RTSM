# Mobile-beta browser QA — 932x430

Date: 2026-09-13

## Status

**PASS — local Chromium touch emulation against the canonical production Web artifact.** This is exact-size browser-rendering evidence, not an outside-human or physical-phone result.

Evidence directory: `output/playwright/mobile-beta/closing-final-2026-09-13/932x430/`

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
| Playwright session | `aoem-closing-932` |
| Viewport / screen / canvas CSS / canvas buffer | `932x430` throughout |
| Device scale / touch | DPR `1`; mobile touch and coarse pointer; max touch points raised from 1 to 5 only for CDP pinch dispatch |
| QA record | `qa-results.json`, SHA-256 `7ebab7e2a8425341d7e107d67ffbf217e401477b2976ba03244a224c9fec7509` |
| Closed evidence manifest | `SHA256SUMS.txt`, 32 entries, SHA-256 `b794d40afb0a6eb489444e7311b9beecfa0407a428d2ba14958881be4ab8dbac` |
| Generated | `2026-09-13T12:25:03Z` |

## Touch-flow result

All 25 PNGs were inspected and have exact `932x430` headers. The sequence proves:

- main menu, Settings, Hard difficulty, seed `424242`, guided opener, Skip, and free-HUD transition;
- direct friendly Town Center selection;
- Villager queue reservation `4/10 → 5/10`, cancellation `5/10 → 4/10`, and the normalized 50-food refund while gathering continued;
- Scout production and the stable Move / A-Move / Patrol / Stop / Stance / Clear command rail;
- separate Build sheet, red invalid House ghost with `Blocked terrain`, placement cancellation, and restored normal controls;
- pause held at `03:20` across 2.2 wall-clock seconds, then resume to `03:22`;
- actual touch/CDP camera drag, accepted pinch out/in, minimap drag, long-press Town Center context, and 3x speed;
- supported terminal state and return to Main Menu with Hard and seed `424242` retained.

The first match reached its supported ending before the complete gesture block. `Play Again` preserved Hard/`424242`, and the same browser session completed pinch, minimap, long-press, speed, a second supported ending, and Main Menu return. This replay is disclosed in `qa-results.json`; each individual acceptance gate remains directly evidenced.

The free-HUD capture still shows `Build one House.`. This is the intended non-modal progression hint after Skip: the Skip control is gone and normal controls are exposed.

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
| Ending / Main Menu | **PASS** — Defeat `04:51`; Sacred Site held `3:00`; score `82–265`; gathered `470/1059`; AI sacred control `180s` |
| Console | **PASS** — 3 informational messages, 0 errors, 0 warnings |
| Requests | **PASS** — 9 recorded, 0 failed and 0 non-2xx responses |

## Screenshot index

The closed directory contains `01-main-menu.png` through `25-returned-main-menu.png`, including settings, free HUD, Town Center production, command rail/actions, Build, invalid placement, pause/hold/resume, pan, the disclosed first ending, accepted replay gestures, speed, final game over, and Main Menu.

## Claim boundary

Reviewer: Codex browser QA plus independent visual reinspection. No outside human or physical phone participated. Real-device ergonomics, browser chrome, notch behavior, accessibility, audio, and long-session comfort remain external validation work.
