# Beta9.1 startup, controls and placement follow-up

Published at [game.4mn.org](https://game.4mn.org/) from source [`0be985c`](https://github.com/ben4mn/RTSM/commit/0be985cda5ddf7a351ea3c1d6c5962acd3af9d8a), version `0.3.0-beta.9.1`. Matching Web and server artifacts use protocol 7 and map catalog 4. The game service restarted at `2026-10-25T22:47:36.734642593Z`. Active-match/connection checks passed before replacement, and the previous beta9 build is retained for rollback. Public file identity, service readiness and browser acceptance pass.

Two recent anonymous beta9 records from Safari/iOS standalone windows contain paired `Importing a module script failed.` rejections at 1.39–1.44 seconds, after Godot session initialization. Loaded and served source identities both match `e6735a63b536`. The only module imports in the unchanged engine are its two AudioWorklet processors. Neither a ResizeObserver nor a WebGL error appears in those records. No corresponding worklet request reached the origin at those times. The exact WebKit/cache failure is not directly observable in the saved records; the fix targets the failing module transport without suppressing the error notice.

The page fetches both stock worklets through its own release-bound cache and verifies SHA-256 values embedded during packaging. It passes those bytes to the native AudioWorklet loader as JavaScript Blob URLs. Only the two exact game module URLs are redirected; native receiver/options and rejection behavior are retained. Blobs survive later audio contexts and back-forward restoration, and are released on final page departure. Failed preparation remains a visible startup failure; actual import failures still reach the existing recovery notice. No engine binary, processor source or browser security policy changes.

The menu's Solo and Online glyphs now use a pennant and paired kingdoms. The browser-owned What's new/Full screen buttons reserve space beside Settings and align with its actual bounds, accounting for Godot interface scaling and browser pixels. Fullscreen stays inside its real browser click handler. Leaving the menu restores the pause toolbar's safe-area fallback.

Battlefield setup starts with a single selected-map preview and disclosure arrow. Opening it reveals the existing choices; selection closes it, and online guest/host permissions remain intact. Camera/navigation tools above the minimap start collapsed behind one View control. Existing actions remain available inside that tray.

Validation includes byte/hash/loading failure cases, retained real exceptions, native module arguments and Blob lifetime, package reproducibility/closure, native menu layout, and exported browser startup/menu/settings/resize checks. Physical Safari acceptance remains separately identified; Chrome or viewport tests are not a substitute for an iOS device.

## Movement and map scope

Panning/pinching clears the previous tap sequence. A touch can retain its visible unit target from finger-down, with ownership/liveness/visibility revalidation at release; panning cancels that target. Selected-unit reselection uses the same visible silhouette rule. A newly requested route skips only its redundant starting-cell center when the next segment passes the existing navigation clearance test. Recovered escape waypoints, later turns, endpoints, costs, movement speed and attack timing remain unchanged.

The opening grove and two guaranteed side expansions each grow from eight to twelve 200-food bushes. Per player this is 7,200 guaranteed food instead of 4,800 (+2,400), with equal mirrored placement, existing routes and five-by-five expansion pads preserved. Random/contested deposits and harvesting rates are unchanged. This deterministic terrain change advances generator/catalog to 4 and online protocol to 7; old clients must reload so both sides simulate the same resources.

Placement now draws above world objects and below fog, using canonical map projection. The actual occupied footprint has one boundary; blocked terrain and the one-tile owned-building access clearance have different marks. The validation and payment rules are unchanged.

## Worker order Undo

An accepted deliberate Move/Gather/Build involving at least two eligible Villagers saves one previous-intent record per player for ten real-time seconds. The temporary Undo control restores ordinary work/move/idle orders for surviving workers, with current target availability and visibility checks. Invalid former work stops safely and reports why; cargo, banked resources, construction progress, health, position and combat are never rewound. A subsequent deliberate worker order supersedes the record. Automatic gathering/delivery progress does not erase it. Time continues to expire while Solo is paused.

Online authority keeps the record and validates its per-player identifier; clients receive only availability/count/lifetime and submit that identifier. They cannot supply previous jobs or another player's record. The protocol 7 release also binds these new snapshot/command fields.

## Verification and remaining limits

The canonical and reproduction exports pass artifact identity and checksum closure checks. The matching Linux server candidate passes an isolated smoke run with all 939 packaged runtime files verified. That smoke did not replace the live service; publication and public checks are separate receipts.

After activation, public postflight verified all 40 Web files and the matching server runtime; 40 public private-room checks passed across the three maps. At an 844×390 Chrome viewport, the normal cached-beta9 update reached beta9.1, a private online room was created and left, and a Mongol Solo match on River Crossings started. Undo restored four workers' previous jobs while preserving the displayed mixed cargo of 16/60. A paid House completed and raised capacity from 15 to 25. All four pause Settings tabs were inspected before returning Home. The [sanitized release receipt](releases/beta91-2026-10-25.json) records the source, restart, checks and limits.

The exact final Web export was exercised in Chrome on Windows at 844×390 and 1280×720 browser viewports. Home, Settings, the expandable battlefield picker, collapsed/expanded camera tools, worker Undo, paid recruitment and touch re-entry after panning passed. A cached Solo game also started while the owned preview origin was stopped. This tests an unavailable origin, not a physical phone with its network disconnected. Both stock AudioWorklet modules reached ready state without captured startup errors. Physical Safari/iOS standalone audio activation, audible playback and human listening remain unverified.

Native menu evidence includes 15 collapsed/expanded setup views and injected touch-event journeys into matches at both phone viewport sizes and interface scales. Placement geometry and all 30 civilization/building artwork anchors pass 1,128 focused checks; 18 before and 18 after native captures retain the comparison. These are rendered viewport fixtures, not physical-device tests.

Worker Undo passes 294 final headless checks covering both owners, malformed/stale identifiers, actual touch restoration, expired/replayed requests, unavailable work and a freed saved resource. An independent 195-check continuation fixture passes for all three civilizations: remembered resources are reacquired after reveal, actual return-only movement deposits the current mixed bag, and completed construction resumes the original gathering job. The authentic pre-fix helper fails 33 of those continuation checks. Cargo earned during a mistaken assignment is retained; no resources or progress are rewound.

### Matched large-battle timing

One quiet native Windows run per whole runtime compared published beta9 (`e6735a6`) with this release (`0be985c`). The fixture, assets, settings and import cache matched; each run sampled about 30 seconds while sustaining 100 units per player. Both accepted all 84 scripted inputs.

| Frame time | Published beta9 | Beta9.1 |
| --- | ---: | ---: |
| Mean | 71.1 ms | 65.3 ms |
| p95 | 127.7 ms | 116.7 ms |
| Maximum | 175.4 ms | 217.8 ms |

Mean and p95 improved in this pair; p99 was effectively unchanged and the single worst frame worsened. This is not 60 FPS or a claim of consistently smooth controls. One short pair cannot establish a stable performance change, and it does not measure a browser or physical phone. Residual frame stalls, physical-device controls/audio, and long-session WebGL recovery remain open.
