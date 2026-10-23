# Multiplayer stability and private lobbies — 23 October 2026

The investigation reproduced and fixed two transport failures during delayed client polling, plus a network input lifetime error. A native loading failure and an intermittent missing combat result led to actual-service red/green reproductions. The historical user exit cannot be uniquely identified from retained logs, so these fixes are not presented as a proven attribution of that specific incident. Explicit host/join lobbies now share the host’s map selection, while Quick match remains available. Native sustained gameplay is recorded by the final redesign report; the evidence below distinguishes those runs from headless tests and controlled fixtures.

## Baseline and deployed service

The original checkout was frozen at `/tmp/aoem-network-baseline-20261023` before network changes. Its actual local WebSocket server and two independent **headless** Godot clients passed Strategy allocation, paid training/construction/gathering, combat with enemy visibility and replicated damage, both result mappings, queue cancellation, malformed commands, disconnected opponents, unavailable connections, and terminal results during map loading. Logs and unchanged-source receipt: `output/multiplayer-stability-2026-10-23/baseline-headless/`.

A read-only inspection of the configured public service found image `sha256:5be908a828aa74006355a5253e0902bacfb6a7b5983fb6e86292e0ba8c2179a2`, started on 22 October at 06:35:37 UTC. The running process had **zero restarts, zero OOM events, and no script/runtime errors** in its complete retained logs. Its last pre-investigation match ended after 126.6 game seconds at 23 October 01:29:31 UTC (22 October, 8:29 p.m. Chicago), with `Opponent disconnected`. This may correspond to the reported incident, but the available evidence cannot identify the player or distinguish a client exit, browser suspension, or network loss. No service was changed or deployed during this inspection.

That deployment still has map catalog version 1 and predates the recent crowding and combat-lifetime fixes. A second read-only source check confirmed its five-second native heartbeat, delta-based clock and two-second terminal cleanup are also still present (`deployed-inspection/transport-before.txt`). It also lacks the new private-lobby operations. Quick match remains backward compatible; mixed catalogs still use unchanged Open Plains. Private hosting/joining requires an updated authoritative service. The new client reports this explicitly after a bounded handshake instead of waiting forever while an old server answers heartbeats. Raw inspection: `output/multiplayer-stability-2026-10-23/deployed-inspection/server.txt`.

## Confirmed transport defects

A newly rendered River pair disconnected just after `matched/loading`, with no script errors and server close code `-1`. Although the server logged only 0.12 seconds since its last packet, timestamps showed roughly nine seconds of loading. A separate repeated headless combat match reached Surrender on the authority and the guest, while the host never received its result and timed out. Both failures are retained, rather than counted as passing matches.

Two distinct mechanisms were then reproduced against an actual separate authoritative process:

1. **Premature native heartbeat.** Godot 4.6 checks its automatic WebSocket heartbeat deadline before reading an already queued Pong. The application configured a five-second heartbeat. A scene/render stall after a ping could therefore destroy a healthy socket before reading its reply. The controlled test polls to send the production heartbeat, lets the independent server reply, and blocks only the client for 5.6 seconds. Before the fix it reports `state=error`; afterward it remains `state=searching`, connected, with no errors. The application now uses its existing four-second JSON ping and twenty-second silence deadline on native and Web alike, with the redundant native automatic heartbeat disabled. This follows the inspected [Godot 4.6 source](https://github.com/godotengine/godot/blob/4.6-stable/modules/websocket/wsl_peer.cpp) and its [polling/closure contract](https://docs.godotengine.org/en/4.6/classes/class_websocketpeer.html).
2. **Terminal result discarded on close.** The server previously destroyed finished connections after two seconds. Godot clears queued incoming messages when a socket closes; draining after `poll()` cannot recover a result erased inside that call. A second real peer surrenders while the visual client cannot poll for 4.2 seconds. Before the fix the client receives `Connection lost` instead of the result. Afterward it receives the correct winner and `Surrender`, and the server records `result_acknowledged`. Clients now acknowledge terminal receipt before constructing results UI; the server retains the connection until that acknowledgement or a bounded twenty-second fallback for older clients.

Transport timeouts and rate limits now use monotonic wall time rather than engine delta, which can be capped during a stall or scaled for simulation. Both endpoints drain received messages before deciding that a connection is silent. The existing thirty-second map-readiness deadline and twenty-second connection-silence limit remain bounded. Long suspension beyond those supported limits still ends a match; reconnect/resume is not claimed.

Tests: `tools/test_online_delayed_poll.gd` and `tools/test_online_delayed_result.gd`. Exact red/green logs are `output/multiplayer-stability-2026-10-23/delayed-{poll,result}-{before,after}/`. The independently observed native failure is in `output/multiplayer-native-2026-10-23/final-river/`; the earlier missing-result replay is in `output/multiplayer-stability-2026-10-23/final-headless/`. An immediate diagnostic combat replay passed both clients, demonstrating why a single passing retry would not have resolved the defect.

## Confirmed lifetime defect

`NetworkSession.entity_id(Node)`, `target_payload(Node2D)`, and the typed iterator in `selection_ids()` accepted retained UI references. If a snapshot removed the referenced unit before the input callback ran, GDScript rejected the already-freed object at the typed boundary **before** the intended `is_instance_valid()` checks.

The regression loads the real network Main scene, creates a real replica, selects it, removes it through an empty authoritative snapshot, waits for actual deletion, and invokes the delayed command helpers with the retained reference. Selection maintenance is deliberately delayed to expose that boundary deterministically. It then checks normal selection cleanup, registry removal, reconstruction and the inert replica process mode.

The same fixture produces three script errors and two failed completion assertions on the baseline. The fix accepts an unvalidated Variant only at these input boundaries, checks lifetime/class/queued deletion, and returns no ID or target for an unusable entity. The fixed run passes all **15 checks**, with zero engine errors. This demonstrates the defect and fix; it does not prove that it caused the user's original exit.

- Test: `tools/test_network_reference_lifetime.gd`
- Red/green evidence: `output/multiplayer-stability-2026-10-23/reference-lifetime-before.log` and `reference-lifetime-after.log`

## Private lobby and transport behavior

The server now creates six-character private lobby codes. The host selects the map, both participants receive the same selection, and only the host can start after the guest joins. A guest leaving restores the host's one-player lobby; a replacement guest receives its current map. Closing the host lobby tells the guest what happened. Hosted matches use the existing paired map-readiness barrier and authoritative simulation. One active arena remains the capacity limit; a requested hosted match waits if that arena is occupied.

The original `find_match()` API and FIFO Quick match remain available. New session APIs are `host_game(map_archetype, endpoint)`, `join_game(code, endpoint)`, `set_hosted_map(map_archetype)`, and `start_hosted_match()`. `room_changed` publishes `room_code`, `room_host`, `room_players` and `match_map_archetype` to the New Game flow.

The transport now validates finite integral match-envelope values, tags started/rejected/ended messages with their match ID, ignores terminal/control messages for another match, resets per-match snapshot timing, and records why a peer was removed (explicit leave, closed socket/code, silence timeout, packet limit, acknowledged result or receipt timeout). Old servers omitting those match tags remain accepted.

A final menu review also found that the Web update gate considered `lobby` safe to reload, and both menu initialization and closing Settings could override an earlier unsafe state. The menu now permits worker activation only while idle or in an error state with Settings closed. Live rooms, rooms waiting for an arena, connecting/loading/playing states and open Settings remain protected. Settings emits its existing close signal and lets the owner restore the appropriate gate. A lightweight actual-menu/controller fixture passes **57 checks** across initial states, network transitions and Settings open/close. This verifies the GDScript gate and signal wiring, not a new browser service-worker end-to-end run; it does not change the frozen native network revision.

## Focused verification

| Check | Mode and result |
| --- | --- |
| Existing baseline online integration | Actual local server plus independent headless clients; all checks passed, source unchanged |
| Accepted final online integration | Frozen transport revision, actual local authority and independent headless clients; all 13 client/probe processes passed, including the three new regressions, paid economy/combat and both results; source unchanged |
| Delayed polling with a queued server reply | Actual separate authoritative process; same 5.61-second client stall changes from connection loss to a healthy connection |
| Delayed terminal receipt | Actual two-peer match; same 4.2-second client stall changes from lost result to correct Surrender/winner and server acknowledgement |
| Replica reference lifetime | Real-scene controlled fixture; 3 baseline script errors to 15 passing checks and zero errors |
| Private lobbies on all three maps | Actual local WebSocket service; 34 passing assertions, including shared seed/map, host authority, third-player rejection, guest replacement, disconnect result and host cancellation |
| Nine legacy/mixed/current catalog pairs | Actual local WebSocket service; all passed, including safe unchanged-Plains fallback |
| New client with frozen old server | Actual old authoritative process answers pings but ignores host requests; client exits negotiation explicitly after 12.04 seconds, without loading a match |
| Menu Web update guard | Actual menu and Settings controller fixture; 57 passing checks, no map/socket creation, zero errors/warnings |

Lobby tests are `tools/test_online_rooms.gd` and `python3 tools/run_online_tests.py --rooms-only`. Catalog tests use `--maps-only`. The legacy negotiation probe is `tools/test_online_lobby_compatibility.gd`; it intentionally requires an older service without lobby support.

The menu guard test is `tools/test_menu_update_safety.gd`, with its log and exact source receipt at `output/multiplayer-stability-2026-10-23/menu-update-safety*`.

These are functional tests, not performance measurements. The accepted output directories are `final-transport-headless/`, `rooms-final-transport/` and `maps-final-transport/` below `output/multiplayer-stability-2026-10-23/`. Earlier intermediate results and the failed replay remain in their separately named directories. The final full suite has zero script/runtime errors and three ObjectDB shutdown warnings in fixtures that quit immediately from result callbacks; the baseline also has three such shutdown warnings. No runtime-leak or long-run-memory conclusion is inferred from those short fixtures. Runtime session SHA-256 for the accepted focused candidate is `692f19947b270efd88a9daab889d8ffc4443539055c285a2ea97a63b64b084b8`.

The compact tracked archive `docs/evidence/multiplayer-focused-20261023.json.gz` preserves the baseline, rejected replay, exact red/green tests, final client/server logs, source receipts and read-only production inspection.

## Interrupted native Woodland run

The first final Woodland soak stopped after 1039.2 game seconds and did not meet the requested thirty-minute duration. The host produced no final report; the surviving guest correctly received `Opponent disconnected`. Investigation found a native window-close request, not an observed engine crash: at 17:43:10.805 UTC the host PID 39476 logged an AppKit mouse-up action, at .809 its main `GodotWindow` received `windowShouldClose`, and at .829 AppKit began normal termination. Launchd recorded exit status zero. No new Godot crash report was found in either user or system diagnostic directories. The host's anonymous playtest diagnostics were saved immediately before teardown, with ordinary game samples and no preceding recorded error.

Godot's [macOS window delegate](https://github.com/godotengine/godot/blob/4.6-stable/platform/macos/godot_window_delegate.mm#L51) forwards this native close request and returns `NO`, explaining AppKit's “prevented close” wording; the default [SceneTree close handler](https://github.com/godotengine/godot/blob/4.6-stable/scene/main/scene_tree.cpp#L821) then ends the main loop. The logs do not identify who or what originated the mouse action. The run remains rejected/interrupted evidence; no multiplayer or engine fix is claimed for this exit. The pertinent OS lines, diagnostic tails and summary are preserved under `output/multiplayer-stability-2026-10-23/native-woodland-exit/` and in the compact tracked archive.

## Limits

Disconnect/resume of the same live match remains unsupported. A connection loss ends the match, and recovery means returning to the menu and creating/joining another lobby. Private rooms are access-by-code, not authenticated accounts. The public authoritative service was inspected but not redeployed; merely pushing this repository does not update that running server. The historical reported crash remains unconfirmed; the concrete loading and terminal failures observed during this investigation were independently reproduced and fixed. No physical phone or separate remote participant was involved in these focused checks.
