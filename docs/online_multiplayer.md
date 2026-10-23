# Authoritative online matches

The **New Game → Multiplayer** flow can host a private lobby, join a six-character code, or use Quick match. In a private lobby the host chooses the map, both players see it, and the host starts after the guest joins. Quick match pairs two independently searching players. Both paths use a shared match ID/map seed, opposite slots, and a loading barrier before authoritative simulation starts. The default endpoint is `wss://game.4mn.org/match`. Cancel removes the player from the queue; unavailable connections show a retryable error; leaving or disconnecting awards the opponent the result. An interruption of the server connection itself shows connection loss without inventing a victory. Online Pause opens local controls; it cannot stop the opponent's simulation.

Updated clients advertise map catalog version 2. Private lobbies require a matching catalog and use the host's explicit map. In Quick match, when both players support the current catalog, the server chooses Open Plains, River Crossings or Woodland Flanks from the shared seed and sends the same archetype to both. A legacy or mixed pair always receives the original Open Plains generator, whose seeded grids remain unchanged. New clients also accept older servers that omit the archetype. Online maps use session state directly and preserve both the solo map preference and its fixed/random seed. The separate `python3 tools/run_online_tests.py --maps-only` harness exercises legacy, mixed and updated WebSocket pairs; ordinary independent economic clients additionally compare their loaded terrain with the agreed seed and archetype and verify solo map preferences survive leaving.

The public frontend and server were deployed together on 23 October, with the final beta.11 runtime revision `b48ebbb5c013`. Private rooms, shared host map selection and the delayed-poll/result fixes are now live. See the [live deployment receipt](live_deployment_2026-10-23.md) for exact image/source identity, browser verification and rollback. Private requests to older servers still fail explicitly after twelve seconds even when those servers answer heartbeats.

## Architecture and capacity

`NetworkSession` is the persistent WebSocket transport, private-lobby coordinator and Quick match FIFO matchmaker. The Godot headless server runs the same main scene, units, economy, construction, production, combat and victory code as solo play, with AI processing and AI signal registration disabled. Clients render replicas whose simulation is disabled while their selection collision shapes stay active. Every client maps its own server slot to local player 0, keeping touch UI and fog behavior consistent.

The server validates order ownership, live targets/current visibility, build placement and reachability, age, payment and population through existing gameplay transactions. Strategy allocation sends a source/destination job request; the authority chooses an eligible worker from that player's current jobs and a visible, reachable resource, preserving builders, recovering workers and cargo. Strategy Repeat uses the same authoritative queue command as the selection HUD. Packets are JSON primitives, with bounded size/queue/processing, per-connection rate limits, a protocol version and per-match command sequences. Clients never submit HP, resource totals, unit spawns or match results. Only currently visible opponents are replicated. Own resources, research, queues, protected worker states and mixed cargo are private to their owner. Snapshots run at 10 Hz; clients interpolate positions and render walking/work/attack motion, facing, hit feedback, destination markers and a bounded own-unit route preview.

The initial deployment supports **one active two-player arena**, plus at most 32 waiting/connected clients. Search honestly says “Waiting for an arena…” while occupied. After a match, the next pair starts automatically. There is a 30-minute draw limit, a 30-second load deadline, a 12-second connection/lobby-negotiation deadline and a 20-second silence timeout. Transport deadlines use monotonic wall time. Application heartbeats work identically on native and Web; native automatic WebSocket heartbeats are disabled because their pre-receive deadline can discard queued replies after loading stalls. Finished peers acknowledge their result before the server closes them, with a bounded 20-second fallback for older clients. Capacity is deliberately bounded; this version has no accounts, ranking, reconnect/resume or multi-arena process supervisor. A mobile app suspended long enough to lose connectivity forfeits the current match.

## Run and verify

Godot 4.6 is required. Native clients and browser clients use the same WebSocket protocol. Android native exports must enable the Internet permission. The shipped web endpoint uses trusted TLS through the existing Cloudflare tunnel.

```sh
# Local authoritative listener.
AOEM_MATCH_PORT=9080 /Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path . res://scenes/network/server_lobby.tscn -- --aoem-server

# Two clients may use this override for development.
AOEM_MATCH_URL=ws://127.0.0.1:9080 /Applications/Godot.app/Contents/MacOS/Godot --path .

# Starts a server and independent clients; no mocks.
python3 tools/run_online_tests.py --combat

# Explicit lobby map choice, host authority, leave/rejoin and cancellation.
python3 tools/run_online_tests.py --rooms-only

# Same checks through the deployed public TLS endpoint.
python3 tools/run_online_tests.py --url wss://game.4mn.org/match --combat \
  --output output/online-public

# Focused real-control integration: two clients, actual Strategy button signals.
python3 tools/run_online_tests.py --strategy-only --url wss://game.4mn.org/match \
  --output output/online-strategy-public
```

The dedicated harness covers queue cancellation, paired readiness, malformed packets (including array/object Repeat flags on an owned Town Center and invalid/protected allocation sources), unauthorized/nonexistent target rejection, fog omission, disconnect results, both slots arriving at explicit movement destinations, paid worker production, completed paid houses, actual resource deposits, paid barracks/infantry, attack-move to combat, visible enemies and replicated damage. The full suite also retains actual-service delayed-poll and delayed-result regressions plus a real-scene freed-replica command-input regression. Its Strategy scenario activates actual button signals through the controller, cycles Food/Wood/Gold/Idle assignments, and verifies paid Train, Repeat, Sacred rally, and Clear/refund from authoritative snapshots without mutating replicas. This is control/controller integration; browser touch dispatch is checked separately. Real-scene delayed-loading regressions also verify that a match result or connection failure received before map readiness survives attachment and opens the result screen. It runs separately from the single-process focused test runner. Logs include the endpoint and per-client evidence; a test only passes if both clients finish and all processes have no runtime errors.

## Deployment

The backend is an additional service in the existing `/home/ben/aoem` Compose project. It has no public host port. Nginx forwards only `/match`; Docker DNS is resolved at request time so an unavailable online service cannot prevent the static game from starting. The existing static game, diagnostics collector and Cloudflare tunnel remain independent.

`tools/build_match_server.sh` copies only game runtime directories into `build/match-server`, removes debug/MCP editor configuration, and imports resources with Godot 4.6. Copy this closed server context to `/home/ben/aoem/match-server`, and copy `deploy/docker-compose.online.yml` alongside the existing base Compose file. No credentials enter the runtime or image.

```sh
cd /home/ben/aoem
docker compose -f docker-compose.yml -f docker-compose.online.yml build online
docker compose -f docker-compose.yml -f docker-compose.online.yml up -d online
docker logs --tail 20 aoem-online
docker exec aoem-game nginx -t
docker exec aoem-game nginx -s reload
```

The image runs as UID 10002, with a read-only filesystem, no Linux capabilities, bounded CPU/memory/PIDs, and private writable tmpfs for Godot's user/cache files. The official Godot 4.6 Linux runtime is downloaded from the Godot release. Stop only the online service with the same Compose flags and `stop online`; `/match` then fails gracefully while solo/static play remains available. Redeploy the server after gameplay-rule changes together with the matching static frontend. An active match is interrupted by a server replacement, so wait for the arena to be idle before maintenance.

## Verification receipt — October 21, 2026

The public WSS endpoint passed the full harness twice with two independent native/headless Godot processes: both players arrived at explicitly ordered destinations, paid for and completed worker training and Houses, deposited gathered resources, then in another real match paid for Barracks/infantry and attack-moved into a visible fight with replicated damage and identical surrender results. Lifecycle checks verified search cancellation, malformed-envelope handling, invalid authority targets, hidden-enemy omission and disconnect wins. Evidence is in `output/online-public/` and `output/online-public-final/`.

The final deployed image is `sha256:121028c0531e5ab520061a41462cda493302e648df50b41f4dbe982e6c9920d7`. After the last shortest-dropoff-route, online-clock and menu refinements, `output/online-public-latest/` passed connection failure, lifecycle and both economic clients again. Independent review then found and fixed malformed Repeat flags and terminal events received during initial loading; both delayed-attachment scenarios passed against the actual Main scene, and the strengthened public lifecycle passed after redeployment (`output/online-public-hardening/lifecycle.log`). Browser testing subsequently exposed Strategy assignment and Repeat bypasses; the final server includes those fixes and protected-worker metadata. Both clients passed the actual-control Strategy scenario locally and through public WSS, followed by the expanded malformed-packet lifecycle (`output/online-strategy-public/`). Existing offline Strategy overview, cargo and selection-death regressions also passed. Runtime file hashes are in `output/online-server-runtime.sha256`. No client or backend runtime errors appeared in the passing runs. The final 60-second economic test match ended at 113 server FPS; an earlier active combat sample used 57.7% of one CPU and 120.6 MiB of the 768 MiB container limit. These automated process checks are separate from the frontend's browser/touch checks and physical-device validation.

The existing game Nginx configuration was backed up to `/home/ben/aoem/nginx.before-online.conf`, validated and gracefully reloaded. Only the new `aoem-online` container was created/replaced; the static game release, diagnostics collector and Cloudflare tunnel were preserved during backend testing. The corresponding new static frontend is published separately by the main release workflow.
