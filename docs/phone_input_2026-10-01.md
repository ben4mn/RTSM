# Phone input and browser screen follow-up — 2026-10-01

The physical-phone test of the mechanics build exposed unusable world taps and browser bars consuming space. Both local test servers (8782 and 8783) were stopped on request. The editor was retained. This follow-up preserves the incoming dirty tree and makes a separate export; the earlier mechanics evidence remains bound to its earlier source.

## Input fixes

- Selection now adopts the actual identifier of the first world-owned contact instead of requiring index 0. Godot's exported JavaScript forwards DOM `touch.identifier` unchanged, so a world finger following menu/HUD contacts can have a different identifier.
- Touches that begin on GUI or appear only as drags cannot become world selection, placement, or camera contacts. Canceled contacts never issue a tap command. Release bookkeeping also runs before GUI routing, with deferred dispatch records removed afterward.
- Adding another finger latches navigation until every contact lifts, including after a consumed long press. Building placement keeps the pending foundation fixed in world space during pinch and midpoint pan. Either remaining finger can continue navigation after its partner lifts. A fresh single-finger gesture can move the preview after all contacts end. Only the explicit Place action purchases a foundation on touch.
- The camera retains the first two world fingers when a third contact appears. Pause, Build menu, and game-over interruptions clear camera and selection ownership, preventing old held contacts from moving the view after resuming.

The new regression scenes use `Input.parse_input_event` through the normal Main/HUD/GUI/unhandled pipeline. They measure natural unit movement, actual camera pan/zoom, GUI ownership, contact cancellation, and one ordinary paid House. The selection failure was reproduced in all eight phone/interface/emulation profiles against the pre-fix source. The placement regression also fails against an isolated pre-fix copy, demonstrating that its ownership assertions detect the original defects.

## Browser screen behavior

`web/pocket_shell.html` is the source-controlled Godot export shell. It fits the canvas to the visual viewport and safe-area rectangle, with backing dimensions multiplied by device pixel ratio once. The Mobile Web preset uses this shell and manual canvas sizing, and the build/verifier enforce those settings.

The Screen button appears on the menu, pause, and game-over screens and hides during play. It requests fullscreen only from the button's direct user gesture and provides a closeable fallback when unsupported or declined. Standalone launch hides the redundant screen control. Portrait phones receive a landscape prompt.

iPhone Safari's general element fullscreen limitation is tracked by [WebKit](https://www2.webkit.org/show_bug.cgi?id=310661). The shell provides Apple's [Add to Home Screen / Open as Web App instructions](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios). Browser permissions and support still determine whether a fullscreen request succeeds; see [MDN's API documentation](https://developer.mozilla.org/en-US/docs/Web/API/Element/requestFullscreen).

## Validation and artifact binding

The final frozen source passes **77/77 focused Godot checks**, **22/22 Python checks**, and a clean headless boot. All 67 runtime/export source hashes and 130 QA source hashes remained unchanged through the final run. The earlier 77-case run was superseded when the independently reproduced direct-pause placement edge was fixed; only `final-focused-suite.log` is the final-suite evidence.

The new export is `build/phone-input-2026-10-01/`, built with Godot `4.6.stable.official.89cea1439` from dirty revision `89567778b26e`. Its staged-source SHA-256 is `0b4193ffe40073504f2b336ec356d8d76a5852e912d9b145b86fdce7a1509f89`. The production stage continues to exclude developer/MCP tooling.

Primary local evidence:

- `output/phone-input-2026-10-01/final-focused-suite.log`
- `output/phone-input-2026-10-01/python-tests-final.log`
- `output/phone-input-2026-10-01/final-boot.log`
- `output/phone-input-2026-10-01/runtime-freeze.json` and `harness-freeze.json`
- `output/phone-input-2026-10-01/selection/final-validation.json`
- `output/phone-input-2026-10-01/placement/placement-final-tests.json`
- `output/phone-input-2026-10-01/placement/modal-lifecycle-final-readonly-audit.json`

The final compiled export ran in an isolated headless Chromium session using routed local assets at a synthetic HTTPS origin, without restarting either server or taking over the user's browser. At DPR 2, CSS sizes `844×390` and `932×430` produce backing sizes `1688×780` and `1864×860`. Real Godot canvas interactions with changing browser touch identifiers opened Settings, started a match, selected/recentered the Town Center, selected a villager through the world canvas, and issued Move followed by natural walking at both sizes. Fullscreen entry and exit were observed. Rotation showed the portrait prompt and restored the landscape canvas.

Explicit safe-inset and visual-viewport fixtures also produced the expected canvas rectangle and backing dimensions, including offset GUI taps. These were simulated values rather than measurements of an actual phone notch or toolbar. Earlier browser screenshots with attempted worker taps are diagnostic attempts, not successful selection evidence; the final selected-unit and moving/arrival screenshots show the observed outcomes.

The canonical export and its reproduction witness pass `output/playwright/web-shell/final-artifact-verification.log`, including source-manifest identity, substantive payload equality, fullscreen shell, standalone manifest, checksum closure and the existing production-stage exclusions. The browser report is `output/playwright/web-shell/report.md`, with its machine binding in `evidence-manifest.json`. It records 23 successful final compiled-game captures, two explicitly failed diagnostic tap attempts, and four controlled fixture captures. Browser logs/screenshots live in the same directory.

The routed synthetic origin blocks service-worker registration and produces audio worklet fetch failures. This browser run establishes canvas/input/fullscreen/resize behavior only; it does not verify audio, offline installation, a physical iPhone's Safari fullscreen limitation, or Home Screen launch. The owned isolated browser and its extra contexts are closed. `output/phone-input-2026-10-01/closeout-evidence-manifest.json` binds the final source, export metadata and primary evidence. Both phone-server ports remain stopped.

Physical-device verification remains open. Synthetic phone-size browser and routed-input checks do not establish that Safari's real toolbar/Home Screen launch, OS touch cancellation, or the user's specific device now work. No phone server was restarted during this follow-up.
