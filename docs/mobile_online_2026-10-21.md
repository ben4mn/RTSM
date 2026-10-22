# Mobile gameplay and online 1v1 — 2026-10-21

This pass implements the eleven requested areas in the existing Godot 4.6 game. Balance stays in the existing data files; gameplay uses the current signals, map conversions, pathfinding and paid transactions. No engine-wide speed multiplier was used to obtain faster matches.

## Fix and verification checklist

| Request | Change | Evidence |
| --- | --- | --- |
| Mobile UX | Build categories fit one row. Workers and production have separate bounded pages; producers have previous/next buttons. Settings have five short pages. Essential details have tap access. | Native engine ScreenTouch journeys at 844×390 and 932×430, three interface scales and ordinary/simulated notched safe areas. Menu, build, strategy, contextual HUD and secondary-surface checks. |
| Movement and task changes | New orders supersede old delivery callbacks. Mixed cargo shares one capacity and deposits exact original types. Routes recover after obstacles change. Production exits avoid disconnected pockets. | Mixed-cargo conservation, blocked-route recovery, 20-unit congestion, formation arrival and production-egress regressions. |
| Touch intent | Tap ground for passive movement; hold ground for 350 ms for attack-move. Drag pans; pinch zooms; arm area selection before dragging around units. | Actual input dispatch checks for tap/hold, release deduplication, pan-return, pinch, GUI contact, OS cancellation and time-scale independence. |
| Brief order feedback | Distinct move circle, gather diamond, attack cross and rally flag. Thin route previews hold for 1.4 seconds and fade out by two seconds, with at most three route groups. | Route-following/fade/reselection tests and rendered phone captures. |
| Economy | Larger starting supplies and carry capacity, faster paid training/construction and deliberately matched gathering throughput. | Explicit delivery-rate model, before/after paid openings and population/refund checks. |
| Faster matches | First meaningful choices and paid armies arrive earlier; Standard Sacred control requires 180 seconds. | Seeded paid AI match with natural combat and Sacred ending; see economy receipt for latest timing. |
| Permanent farms | Unlimited food, ordinary worker rates/carry capacity, still destructible. | 15,000-food harvest stress and destruction/resource-ledger tests. |
| One camp | Resource Camp accepts food, wood and gold for 80W; redundant camp scenes and choices removed. | Menu, AI, construction and all-resource drop-off checks. |
| Automatic drop-off | Choose the shortest reachable legal perimeter path across compatible active friendly buildings; reconsider topology/building changes. | Farther-in-world-but-shorter-by-path, mixed cargo, blocked/friendly/unfinished checks and new-camp rerouting. |
| Automatic combat | Passive movement has priority. Explicit attacks persist. Attack-move resumes after fighting. Autonomous targets favor threats; pursuit is bounded. | Damage-driven priority, stand-ground, chase/return, building footprint, congestion and paid combat tests. |
| Real online play | Public WSS queue, authoritative headless simulation, private per-player state and interpolated clients. Search/cancel/error/disconnect/result flows. | Independent native clients through public TLS: paid workers, completed buildings, real deposits, movement by both owners, paid infantry and replicated combat damage. |

## Economy and pacing

Starting resources move from 200F/150W/100G to 250F/250W/100G, with four workers retained and initial housing increased from 10 to 15. Carry capacity rises from 10 to 15. At a representative 120-world-unit one-way route, the calculated delivered food/wood rate rises from 44.2 to 59.0 per worker-minute; gold rises from 38.7 to 51.4. Villager training changes from 16 to 12 seconds, so continuous worker production needs about 4.24 nearby food workers both before and after. Faster queues remain payable rather than merely appearing faster.

The paired seed-424242 opening reduced first fighters from 184.5/250.5 seconds to 95.5/101.5 seconds, first combat from 267.5 to 148.9 seconds, and Feudal from 232.5/274.5 seconds to 144/145.5 seconds. The final paid economy run, including the shortest-perimeter drop-off correction, ended naturally at 401.93 seconds (6:41), with first combat at 151.8 seconds and first Warriors at 88.0/101.5 seconds. Archers landed 51/15 hits where both sides previously landed none before the production-egress fix. These are paid automated opponents on one seed, not a universal match-duration guarantee or proof of competitive balance. The final drop-off refinement is documented in the linked economy receipt.

Full calculations, costs, production-line staffing and before/after receipts: [economy report](mobile_economy_2026-10-21.md). Command priorities, reproduced path defects and individual checks: [movement/combat report](mobile_movement_combat_2026-10-21.md).

## What the checks establish

- Native rendered runs use actual engine touch events with ordinary paid resources. Some fixtures pause or advance simulation deterministically; isolated combat/congestion tests explicitly construct their test state.
- A completed paid AI match exercises resource delivery, construction, recruitment, age progression, autonomous attacks and a natural Sacred victory. Separate ending tests cover elimination, defeat/restart and return to menu.
- The Godot gameplay bridge was used to launch and observe the running game, inspect state/errors, capture screenshots and sample performance. One desktop midgame sample reported 115 FPS, about 98 MB static memory and zero orphan nodes. This is not phone GPU or battery evidence.
- Public multiplayer checks use separate client processes and a remote server at `wss://game.4mn.org/match`, not a mocked queue or a local-only listener. The dedicated harness is `python3 tools/run_online_tests.py --url wss://game.4mn.org/match --combat`.
- Native phone screenshots and focused logs are under `output/mobile-online-2026-10-21/`; online integration evidence is under `output/online-public/`; browser evidence is under `output/playwright/`. Generated artifacts are intentionally outside version control.

Physical iPhone/Android touch feel, mobile GPU/battery performance, installed-PWA background suspension and a broad human balance study remain unverified. Simulated safe areas and browser touch emulation do not establish those properties.

## Online operating limits

The initial server hosts one active two-player arena, with a bounded waiting queue. It supports no accounts, rankings or reconnect/resume. Leaving or losing connectivity forfeits; a server transport failure is reported as connection loss. The match menu clearly says that online play continues, and local speed controls are disabled. A replacement of the server interrupts an active match, so maintenance must wait for the arena to be idle. See [architecture and deployment](online_multiplayer.md).

## Regression reconciliation

The isolated snapshot ran **134 cases: 108 passed initially, 24 applicable failures were corrected or resolved and passed targeted reruns, and two standalone online cases required separate server/client orchestration**. This provides passing evidence for **132 applicable cases**, combining the snapshot with those reruns. It is not a full rerun of every test against the final source. The [case-by-case receipt](mobile_focused_regression_2026-10-21.json) records each classification and rerun log; the separate public online checks are listed above. The latest paid phone journey also passed all 12 phone/scale/safe-area profiles after the first-open layout correction.

## Public release and browser evidence

Live at **https://game.4mn.org**, version `0.2.0-beta.1`, release `33ac3713-mobile-online-20261021`, published `2026-10-22T01:25:12Z`. Both exports share source tree SHA-256 `33ac37134deb6a9bdc71f3603b1344c07559f85cb374e458748ebede6cf37dcf`; substantive payloads match and all 26 public decoded hashes match the canonical manifest. The artifact was exported before the task's changes were committed and records base revision `3a26757f1ed3` with an explicit dirty flag. Exact rollback paths are in the [deployment receipt](debian_game_deployment.md).

Two independent Chromium contexts at 844×390, with touch enabled, joined public match 3, seed 773544858, as opposite slots. Ordinary touchscreen taps opened the Economy panel at its first opening, reassigned Food to Wood, trained a Villager for exactly 50F, enabled Repeat, set Sacred rally, cleared the queue, and left through the online match menu. Passive WebSocket observation confirmed the actual commands and authoritative state. The reassigned worker retained its seven food and subsequently carried seven food plus five wood; counts changed from Food 2/Wood 1 to Food 1/Wood 2. Repeat was true on the server, Clear emptied the queue and released reservations, and the other browser received a real disconnect victory with its own gathered-resource statistics.

These browser checks found and fixed two defects absent from isolated fixtures: first-open panel height used an unsettled minimum, and Strategy allocation/Repeat changed only inert client replicas. The first-opening regression now avoids manually invoking layout, and both real-control client slots pass the server-backed Strategy regression. The browser-tested runtime was `1ef2c92e`; final `33ac3713` differs only in a confirmation string, replacing a missing-font arrow with “to”. Browser receipts and rendered captures are in `output/playwright/browser-{one,two}-final-receipt.log` and `output/playwright/final-*.png`. The public native harness separately establishes combat/building behavior; these browser sessions do not claim a complete human-versus-human battle or physical-phone validation.

Both browsers subsequently loaded final `33ac3713`, paired again in match 4, and repeated touch worker reassignment with the corrected text visible. The server changed Food 2/Wood 1 to Food 1/Wood 2 and preserved five carried food on the reassigned worker. Evidence: `output/playwright/final-wording-receipt.log` and `final-wording-worker-reassigned.png`.

A final browser console check exposed an existing diagnostics collector failure (HTTP 502): unreaped timed-out health probes had exhausted its process limit. Docker child reaping and an exec-form healthcheck restored it; three scheduled probes and a public 202/private-storage check passed, with all 19 collector tests passing. Only that collector was recreated; gameplay, online server and tunnel stayed running. The exact operating receipt is in the deployment guide.
