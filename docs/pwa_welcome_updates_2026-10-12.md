# Browser welcome, PWA updates and release notes — 2026-10-12

The public game at https://game.4mn.org/index.html now introduces Pocket Kingdoms before downloading the engine in an ordinary browser. Installed app windows go directly to the game. This pass changes the Web entry and lifecycle; the prior gameplay pass and its paid-match evidence remain in `resilient_skirmish_pass_2026-10-12.md`.

## Delivered behavior

- Responsive forest-green/gold introduction, using existing village artwork; readable and scrollable in portrait, short landscape and desktop layouts.
- An explanation of the economy, counters and Sacred-site loop, optional **Play in browser**, and separate iPhone/iPad, Android and desktop install instructions. A native install prompt is used only when the browser supplies one; manual instructions remain available. Fullscreen does not count as installed standalone mode.
- Versioned, data-driven release notes in `web/release_notes.json`, shown on the welcome page and through **What’s new** at the main menu, Pause and results. The overlay supports keyboard focus, PageDown and touch scrolling without forwarding contacts into Godot. Closing it leaves Pause intact.
- `PocketUpdates` owns worker registration. Checks occur at launch, foreground return and reconnection. Complete releases are hash-verified before activation, and every open window must acknowledge two safe phases. Matches, Pause, results, settings, native install prompts and private reports defer activation. The update hold also prevents an already-queued Godot Start contact from launching a match.
- First visits cache only the welcome shell; Play downloads the engine and pack. Updates to an existing app must finish verifying the whole release before installation succeeds, including when the last window closes and the browser activates naturally. Complete cached games and their release notes launch offline. Diagnostics/version comparison stays network-only.
- Persistent per-client cache bindings preserve old assets across worker replacement, including a navigation that finishes during activation. Unknown late legacy clients fail closed instead of mixing engine versions. Failed downloads retain the previous complete cache. Bootstrap errors return to a usable retry screen; explicit engine preload catches a Godot 4.6 promise-propagation gap.

## Release identity

| Item | Verified value |
| --- | --- |
| Runtime commit | `8e6fe0ecfb78` |
| Game version | `0.1.0-beta.2` |
| Staged source SHA-256 | `233d47b600e0c316b456e7b3b291f98c62bba0c187f7f549ce4574de8d2aef12` |
| Canonical export | `build/pwa-onboarding-published-20261012` |
| Independent export | `build/pwa-onboarding-published-reproduced-20261012` |
| Active server release | `releases/8e6fe0ecfb78-20261012-pwa` |
| Retained pre-pass rollback | `releases/a8c20088acd1-20261012-resilience` |
| Fresh private receipt | `PK-01041A574586` |

The two clean exports have identical substantive payloads and source manifests. All **27** public files, including the checksum manifest, match their expected decoded SHA-256 values over trusted HTTPS. WASM/JS/PCK MIME, compression, isolation headers, no-store policy and denied private GETs pass. The private receipt has the exact verification note, matching loaded and served `8e6fe0ecfb78`, `source_dirty=false` and `source_mismatch=false`.

Only `aoem` was restarted. Its final start was `2026-10-12T20:16:50.793641477Z`; the tunnel and collector retained their `02:26:24` and `02:26:34` starts. The documentation commit follows the deployed runtime intentionally. No temporary Git branch or worktree was needed.

## Validation and evidence

Evidence is in `output/evolution/pwa-onboarding-20261012/`; screenshots are in `output/playwright/pwa-onboarding-20261012/`. Raw report JSON is private local evidence, outside the export and Git.

- **52 Python checks**, **18 updater/worker Node cases**, and the existing real-factory private Web-report regressions pass on the final source. The updater cases cover partial/mixed releases, eviction, offline fallback, busy/legacy/new windows, two-phase activation, persistent old-client bindings and late navigation.
- **Six isolated Godot cases** passed without engine errors or warnings: audio/settings, phone menu layout, menu/match transitions, victory-to-menu, defeat/restart and Pause/quit. The final follow-up fixes are Web bootstrap code; the tested GDScript hooks did not change afterward. Full gameplay balance suites and paid acceptance matches were not repeated for this Web-only addition.
- Actual Chromium screenshots/interactions cover **390×844**, **932×430** and **1440×900**. Final public portrait measurement has no horizontal overflow, 50-pixel primary buttons and 48-pixel platform buttons. The initial cache contains the welcome assets but no `index.js`, WASM or PCK; `Engine` is undefined until Play.
- The release overlay took keyboard focus, scrolled with PageDown, and scrolled 372 pixels from dispatched touch movement. Escape restored focus to its opener. Pause remained paused when the overlay closed.
- A real local two-window update retained the old paused game and welcome window while the next complete release waited. Visible **Quit to Main Menu** then updated both windows; the former game window resumed directly at the new menu. This tested the preview-to-`2a844fac161f` transition, with the same updater code as the final runtime.
- Actual browser network-offline reloads booted the cached game and loaded art/release notes. Standalone startup was also checked through an explicitly emulated `navigator.standalone` flag. The final public `8e6fe0ecfb78` was separately launched offline after a complete online download.
- A public legacy `a8c20088acd1` window remained open when a new worker downloaded. Closing that old window and reopening reached the new welcome shell (`ecfc838d5fe8`, the intermediate bootstrap release). A separate fresh browser verified the final `8e6fe0ecfb78` welcome, Play, release overlay, actual skirmish, Pause and private report. The online final flow logged **zero errors and zero warnings**.
- Native-install dismissal and one-shot prompt handling were exercised with a synthetic browser event, alongside manual platform instructions. This is handler coverage, not an OS installation claim.
- Real aborted script and WASM downloads exercised retry recovery. The first WASM failure exposed Godot's unchained rejection; after the fix it returned to the welcome/retry screen. Direct online play also booted with service-worker support explicitly removed in a fixture. Godot's compiled PWA callback can log an unsupported-API warning in that artificial case; the normal public browser flow is clean.

One initial Godot font-import process crashed inside the engine's parallel resource importer. A fresh isolated retry and both final exports passed. Failed export and browser-harness attempts remain in the evidence directory; they are not counted as successful checks.

## Limits and continuation

The browser controls when a closed app can update, and an offline app cannot download a new release. Users on the old stock worker should close all old game windows and reopen online once. After migration, complete updates switch automatically from safe menus. There is no periodic server push or background-install guarantee.

Predecessor caches are deliberately retained to protect live/late clients. Before many future releases, add bounded cleanup that proves a cache is no longer needed; quota failure currently preserves the old app rather than deleting it. Do not silently weaken per-client coherence to reclaim space.

No physical phone, actual OS-installed PWA, native iOS installation or subjective audio listening was available. Desktop viewport/touch dispatch, standalone emulation and browser CacheStorage tests establish only their stated coverage. This pass does not establish new match-balance or worker-wipe recovery results.

The next-session request is saved in `docs/next_session_prompt_2026-10-12.txt`. It preserves the gameplay objectives and publication authorization, records this release, and asks the next pass to verify current state rather than assume a historical SHA is still current. Keep `web/release_notes.json` updated on subsequent player-facing releases.

Platform references consulted: [Apple installation instructions](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios), [MDN standalone mode](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/How_to/Create_a_standalone_app), [MDN install prompt](https://developer.mozilla.org/en-US/docs/Web/API/BeforeInstallPromptEvent/prompt), [service-worker lifecycle](https://developer.chrome.com/docs/workbox/service-worker-lifecycle) and [update checks](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration/update).
