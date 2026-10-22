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
