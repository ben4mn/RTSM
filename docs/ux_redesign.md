# Pocket Kingdoms UX and character redesign

Local review milestone, 11 October 2026. The work extends the incoming dirty R4 checkout at `a79d800b4006`; it does not start from the default branch. Source, incoming diff and evidence are recorded under `output/evolution/ux-redesign-20261011/`.

## Design and demonstrated improvements

The baseline had three dominant problems: competing detached HUD cards, worker feedback occupying selected terrain, and a tiny worker design beside inconsistent military silhouettes. The redesign uses a friendly miniature medieval style with forest panels, warm text, charcoal outlines and amber for the primary action.

- **One spatial hierarchy.** A 56px top rail holds resources, population, age, the Sacred objective, time and Pause. Map selection and View stay at the lower left. Selection, worker tasks, production and commands share one bottom dock. Build and Age sit with the relevant actions; the detached utility column and duplicate unit Clear are removed.
- **Stable everyday actions.** Move, Attack, More and Clear remain completely visible, including armed Move at Large UI with a notch. Armed commands use an amber two-line label and a destination instruction. View reveals zoom and Center; More reveals secondary unit actions. Home and Army return through Clear/Back. Touch targets normally retain at least 48 logical pixels.
- **Useful context.** Production retains names, costs, role descriptions, named Repeat state, waiting reasons and queue Undo/Clear refunds. Guidance uses two readable lines and a separate Skip target. Phone notifications occupy one card. The minimap caption fits inside its panel. Construction keeps the existing confirmation, validity and cancellation behavior.
- **Center sees rendered content.** The camera frames complete selected artwork, rings, health bars, cargo/stance badges and building roofs/flags against actual visible HUD rectangles, including Build and shortcut help. It first finds a legal pan at the current zoom, then fits only if needed. A single worker keeps a feasible manual 2× view; the larger redesigned four-worker group needs a modest reduction in the constrained Large/notched corridor. Natural movement, arrival, map edges and live resizing are exercised separately from visual fixtures.
- **Five implemented character roles.** Workers now have broad straw hats and picks; Warriors have kite shields and spears; Archers have hoods, bows and quivers; Scouts ride chestnut ponies with pennants; cavalry use pale armored horses and lances. Transparent 128px SVGs share a y104 foot baseline. Contact shadows, walking sway, tool rocking and attack anticipation/recoil add movement while preserving hit timing, collision sizes and stats. Team tint still recovers after canonical damage flashes.

## Review and evidence

- [Play the local Web build](http://127.0.0.1:8785/index.html).
- [Compare before and after](http://127.0.0.1:8785/review.html): identical frozen game fixtures at exact phone pixels, plus the character comparison board.
- `before/manifest.json`: 144 incoming R4 captures. `after/manifest.json`: 648 final states plus 36 crowded queue-page captures, covering both 844×390 and 932×430, all three UI scales, ordinary/notched safe areas and overview/default/detail zoom.
- `center/native-receipt.json`: 130 actual keyboard/touch Center cases and screenshots. `input/input-receipt.json`: paid Train/Repeat/refund, selection, actual Move/Attack destinations, Build/Place/Cancel, minimap, keyboard/touch Center and live resize across all 12 phone/scale/safe profiles.
- `character-after/manifest.json`: 12 native lineup captures, including damage/tint recovery. `character-geometry.json` records 30 current and 1,020 future pose containment checks.

The render matrix uses frozen scenes with synthetic banks, armies and queues to stress presentation; it is not paid-match evidence. Input receipts use normal starting resources, with processing isolated for deterministic payments/refunds. Safe-area insets are simulated. The browser smoke uses ordinary mouse/keyboard input in the exported build.

## Source identity and preservation

`final-source-manifest.json` hashes the complete final source. The Web payload records the production-stage fingerprint in `build/ux-redesign-20261011/version.json` and `SOURCE_SHA256SUMS.txt`; its checksum manifest closes the exported payload. The local server can be restarted with `python3 output/evolution/ux-redesign-20261011/serve-local.py`.

All 637 incoming source files remain present; intentional modifications and untouched paths are audited in `incoming-preservation-audit.json`. The original source and incoming Git diff are backed up. Economy, combat, fog, AI and balance rules are retained.

Three older probe JSONs were inadvertently refreshed during early regressions: `output/evolution/camera-edge-20261010/after-headless-camera-edges.json` and `output/critical-play-2026-10-10/camera/framing.json` and `output/aoe-iteration/mobile-readability.json`. No exact original duplicate was recovered; no replacement was fabricated. `evidence-integrity-note.json` records the incident. Of 482 files in the earlier R4 evidence manifest, 481 remain byte-identical; the changed entry is the older headless probe JSON. R4 release builds, screenshots and native/browser receipts remain intact. The broader final suite runs in isolated frozen source copies.

## Validation and limits

Final checks pass: **110/110 focused regressions**, **28/28 Python tests**, headless boot and `git diff --check`. This includes economy/drop-off, paid production/construction, AI building/training/attacks, fog, Sacred victory and all match-ending flows. Native Center passes all 130 cases; paid touch journeys pass all 12 profiles with no GUI world-order leakage. The exported game loads from its menu and exercises paid training, Repeat/queue cancellation, worker selection, Move, Center, minimap, live resize and Pause in the browser, with no captured warnings/errors. Two independent Web exports pass checksum closure, production audit and substantive reproducibility verification. The final production source fingerprint is `dbae3669309610705ae7f8889c108fb990b019ac31213df33c92a6a4ab2603a7`.

A pre-existing pinch test used a 40px drag that could snap to the previous tile after zooming. It now projects a distinct visible tile and asserts admitted ownership, the exact resulting preview, a stationary camera and unchanged resources before explicit Place; the final full suite reruns with that stronger check. Logs are `focused-final.log`, `python-final.log`, `boot-final.log`, `native-center-final.log`, `native-input-final.log` and `web-verify.log`.

Dense production details remain small on Large UI phones. Center and worker Idle require one disclosure tap. The existing F2 keyboard-help card retains its desktop layout and is tall on phones, although Center now avoids it. Physical-phone performance, readability, touch feel and human enjoyment remain unverified. This is a local review build; publication requires separate authorization.
