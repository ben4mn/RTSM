# Overnight iteration — 22 October 2026

The user approved several hours of build–play–review work, GitHub checkpoints and public deployments. The first company/battlefield release is live: clean runtime `334fd81a70fb`, source `8e935c1ce9aef037f622f3be9f7ff3a26b2d0e8311b21f63ecdad3af3693b386`. See the company and Debian deployment receipts for verification and rollback.

The thread heartbeat `improve-pocket-kingdoms-overnight` runs every 45 minutes, up to six wakeups. Work ends at **2026-10-22 07:00 UTC** (02:00 America/Chicago): finish or safely checkpoint the current iteration, push, leave Git clean, record what is live and disable the heartbeat. The local host must remain available.

## First priorities

1. The user's actual phone capture has side and bottom bands. The shell currently shrinks the whole canvas with CSS safe-area insets. Fill the visual viewport with the canvas/background, and pass the browser's safe bounds to Godot controls once. Preserve notch and home-indicator clearance. Verify DPR, UI scale, asymmetric insets, orientation and menu-to-match transitions.
2. Easy is too hard for a new player. Compare a repeatable slower paid player policy across all three maps, then adjust Easy-only pressure and recovery. Preserve Medium/Hard and honest costs; bot fixtures do not establish human balance.
3. Create original Town Center, House and Barracks art that belongs with the company cast. Preserve building gameplay geometry and production. Review at actual phone scale and verify building selection/placement.

Root owns the web/layout bridge and deployment; networking agent owns Easy and its policy fixtures; economy agent owns the three building assets/mappings; movement agent owns independent safe-area tests and audit. Isolate preferences and avoid concurrent performance measurements. Keep current delivery docs separate from these edits, and commit only reviewed source.

## Evidence discipline

Distinguish native desktop renders, fixed-step simulations, browser touch emulation and the user's physical-phone image. Record failures and remaining limitations. The current public match tests have exited; check for real active connections before replacing the authoritative service.

## First iteration — implementation and verification

The phone canvas now fills the visual viewport, with safe-area clearance applied to controls. The final shell passed 80 Chromium/WebKit geometry cases, 24 pure bridge checks and 18 artifact checks. The actual exported game passed a Retina touch journey at Extra Large UI, including paid Villager/Repeat, a live notch-side reversal, Pause and return to menu. See [phone edges](phone_edges_2026-10-22.md).

Original Town Center, House and Barracks silhouettes now share the company's materials and identity, with separate clay enemy fabrics. Geometry, costs and production are preserved; native phone-scale selection, construction and authoritative replica checks passed. See [building art](company_buildings_2026-10-22.md). The local real two-client suite passed strategy, lifecycle, paid economy and replicated combat with no runtime errors; four subprocesses retained nonfatal ObjectDB cleanup warnings. Evidence is in `output/overnight-online-local/`.

The final Easy source adds a longer opening, smaller combined field force, 45-second regroup after a casualty, and delayed Sacred pressure, while retaining immediate home defense. The six final paid comparisons moved the slower learner from four losses and two unresolved matches to six wins in 625.5–750.0 seconds; see [Easy learning](easy_learning_2026-10-22.md). These slow-policy bot matches are calibration evidence, not a substitute for new-player playtesting.

### Candidates for the next wakeup

- Improve guide/panel priority: the opening-guide banner remains partially visible behind the Economy panel in the actual web game. Verify modal guidance hides cleanly and returns at the correct step.
- Extend the original building vocabulary to Resource Camp, Archery Range and Stable, prioritizing readability at phone scale. Preserve selection bounds and gameplay geometry.
- Run contrasting paid attack plans on the three tactical maps; inspect readable contact, retreat and counterplay rather than adding mechanics without evidence.
- Keep performance evidence scoped to the actual machine/browser. The phone edge fix still needs the user's physical-phone confirmation.

## First iteration published

Live at https://game.4mn.org as `0.2.0-beta.3`, clean runtime `ca46ddbfb13f`, staged source `29fa2b41ff71e53e776584b82220836febc8fbb6f6dcb39b0b205d0d9076dff3`, published `2026-10-22T03:27:05Z`. Two independent exports match. Public payloads, headers and private-path denial pass; the live Retina touch journey includes paid Villager/Repeat, reversing the cutout insets during play, and returning through Pause to the menu. Game and online containers restarted; diagnostics and tunnel were preserved. See [deployment receipt](debian_game_deployment.md) for rollback.

The current source is frozen for this release. Continue the next bounded iteration from the candidate list above. The heartbeat remains active through the agreed 07:00 UTC cutoff; `caffeinate -i -t 14800`, started around 02:53 UTC, keeps the host awake until approximately that deadline. Do not extend the overnight window automatically.

Public WSS verification also passed all ten checks against the deployed match server: two strategy clients; connection-failure, loading-ended, loading-failure and lifecycle checks; two paid economy clients; and two paid combat clients. Both players verified paid Barracks/infantry, attack-move, visible enemies and replicated damage. There were no runtime errors; four subprocesses emitted nonfatal ObjectDB exit warnings. All test clients closed and source hashes remained unchanged. Evidence: `output/overnight-online-public/source-receipt.json` and sibling logs.
