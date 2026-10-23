# Gameplay preservation — 23 October 2026

Ten focused regressions passed against a frozen copy of the current checkout, with zero engine errors/warnings. They ran sequentially with only one headless Godot subprocess at a time and separate private preferences for every case. The frozen source manifest remained unchanged. No runtime files were edited for this verification.

| Suite | Preservation evidence |
| --- | --- |
| Farm single worker | Atomic exclusivity through actual work/delivery, cargo-safe rejection, reassignment, building, retreat, death/free/destruction, and AI recovery. |
| Farm command integration | Paid Farm construction, real Main group feedback/cargo, Strategy alternatives, authoritative group rejection and paid rally recovery when a Farm is occupied. |
| Economy traffic | Eight concurrent bags use eight distinct delivery points and deposit exactly 120 wood. Four adjacent Farms retain claims through two cycles and deposit exactly 120 food. Six natural-resource workers remain at least 22.42 world pixels apart while harvesting. Blocked-waypoint replanning and 32–35.78px service separation from settled friendly military also pass. |
| Building placement clearance | 68 checks cover real preview cells, edge/corner/foundation spacing, exactly one open tile, owner/destruction/fog rules, no-charge/no-order-change rejection and paid legal placement. |
| Building perimeter work | Two paid interrupted Farms/Ranges preserve legal edge progress, loaded cargo, cancel/reassign recovery, Farm harvest and TC deposits. Uses the fixture’s established `--fixed-fps 60` requirement. |
| Crowd movement | 4,588,667 checks across 36 building pair/orientation/gap layouts, 216 single-unit routes and 36 opposing mixed crowds. |
| AI assembly | Paid birth→AI recall, mixed staging/reserve/retreat, stable orders, blocked slots, fractional bounds and released occupancy. |
| AI remembered-defense assembly | 6,316 checks retain spread destinations, attack-move intent, stable orders, actual visible combat, target loss, blocked-slot recovery and memory expiry. |
| Freed combat targets | 138 checks use actual queued target deletion during pursuit/windup, preserve explicit cleanup and attack-move resume, and exercise retaliation. |
| Combat progression | 22,007 checks, 11,520 damage cells and 48 paid progression states. |

Villager `35507194…`, UnitBase `c3786684…` and AI `7e972a7d…` match the accepted crowding publication described in `polish_crowding_2026-10-23.md`. The frozen copies of those scripts, building placement, pathfinding and GameMap all still matched the current checkout when this receipt was finalized.

The complete source manifest, commands, private preference paths, logs and fixture JSON are preserved in [the compressed evidence](evidence/gameplay-preservation-20261023.json.gz). Expanded evidence is in `output/gameplay-preservation-2026-10-23/`, including `receipt.json` and individual logs.

These are deterministic/headless correctness regressions, often using synthetic terrain or rosters. They establish preservation of those covered behaviors; they are not additional completed matches, native two-client play, physical-device testing or performance measurements. The session’s native match and sustained multiplayer receipts remain separate.
