# Mobile UI and onboarding fixes — 2026-10-10

Published at https://game.4mn.org/index.html. Runtime commit: `d87e54c41995`, pushed to `ben4mn/RTSM` `main`. Version remains `0.1.0-beta.1`; the source revision identifies this update.

## Changes

- Refresh age, next-age UI, resources, population and clock from authoritative managers after match initialization, including Play Again and menu restarts.
- Completing or skipping the guided opener clears banner visibility, obsolete text, emphasis, action targets and House recommendations. Completion preserves the guided preference; Skip saves the intentional disabled preference. Re-enabled guided games start at step one.
- Genuine mouse placement says click to build and shows Cancel. Touch placement shows explicit Place and remains unpaid until confirmation. Switching devices updates instructions after the current input dispatch; synthesized events do not change the mode.
- Whole-queue Clear disables Repeat before refund/reservation signals, clears training and refreshes Repeat OFF immediately. Individual cancellation and Undo preserve Repeat. Deliberate Repeat ON can resume the remembered unit.
- Age-up costs stay visible on mobile; affordability updates on resource changes and respects pause. A passive eight-second completion cue links food/wood gathering to Barracks, Warriors and the central Sacred Site. Tester instructions now specify ten game minutes (`10:00`) of Sacred Site control.

## Verification actually run

- Godot 4.6 headless boot and editor import in recovery mode: passed.
- Full focused suite: **80/80**, exit 0, no `SCRIPT ERROR` or `ERROR` diagnostics. Four expected warnings exercise population-full, missing-scene and blocked-egress rejection. This includes new guidance, input-aware placement and age-affordability checks, paid gathering/construction/training, individual cancellation, AI behavior, pause/resume and lifecycle regression coverage.
- Python unit/artifact suite: **28/28**, exit 0.
- Lifecycle fixtures perform paid Feudal advancement, alter resources/time/reservations, trigger Sacred defeat or victory using the actual 600-second callback total, and test Play Again and Main Menu → Start. They assert immediate Dark Age HUD, costs, locks, bank, clock and population. These are injected ending callbacks, not a ten-minute physical playthrough.
- Guidance completion and Skip tested at 1280×720 and 844×390; tests restore prior saved preference bytes. Age-cost/affordability checks cover both sizes at 20/30/40 population.
- Local Chromium canvas interaction at 1280×720 and 844×390, Easy/seed 424242: literal mouse House placement, tutorial completion and Skip, fresh guidance, simulated-touch explicit placement and duplicate confirmation, Repeat/Clear refund and reservation release beyond the retry interval, natural paid Feudal advancement, and Pause Quit → Main Menu → Start returning immediately to Dark Age. Zero browser errors. The development browser candidate preceded the final placement feedback wording and single-Cancel centering; the full suite and public smoke cover the committed release.
- Public committed build at 844×390: trusted HTTPS startup, simulated-touch guided start/Skip, visible costs, Villager training, Repeat ON, queue swipe and Clear remaining OFF after 1.2 seconds with 50 food refunded and population reservation released, unpaid House preview and explicit paid confirmation. Zero browser errors. Observed DPR: 1.

Evidence is in `output/ui-onboarding-2026-10-10/` (focused log, Python summary, artifact verifier, browser evidence and public payload verification) and `output/playwright/ui-onboarding-*.png`. Browser evidence labels superseded targeting attempts separately from successful observations.

## Release and Debian

- Compared checkout against tested/live revision `8229a2093669` before editing. Gameplay/UI files matched the deployed source manifest; later checkout commits covered deployment/docs. Existing modified QA reports and untracked historical logs were preserved and excluded from these commits.
- Canonical export: `build/game-web-2026-10-10/`; reproducibility witness: `build/game-web-repro-2026-10-10/`. Substantive files and staged source manifest reproduce.
- Staged source SHA-256: `ca7a4d8870dce7633a312ac199d7d6752ba1596f9f15a9b654087173ab418fe7`.
- Payload manifest SHA-256: `dcbd008c3956d1b3c8b7d739dfb5c3dc15aec5b06c389299daa05b898046c6ef`.
- `source_dirty=true` records preserved historical reports/logs outside the production stage; runtime, tests and tester guidance are committed.
- Debian release: `/home/ben/aoem/site/releases/d87e54c41995-20261010/`, activated through atomic `site/current` symlink replacement. All 19 payload checksum entries pass on Debian; **20/20** exact public hashes pass, including the checksum manifest itself. HTTPS, MIME, no-store/CDN cache headers and WASM/PCK gzip passed.
- Latest user instruction authorized GitHub update and Debian game restart, superseding the initial no-deploy instruction. Restarted only `aoem-game` and `aoem-game-tunnel`; both returned to running. Both retain `unless-stopped`; Docker is enabled at boot. Whole-host reboot was not performed. Server configuration hashes match the repository; shared services were not changed.
- Previous `8229a2093669-20261001` release remains available for rollback. Installed clients should close and reopen online to pick up the updated worker/build.

Physical-device touch, phone performance, audible audio, offline/PWA behavior, harder difficulties, balance and full victory routes were not newly validated. No broad balance changes were made.
