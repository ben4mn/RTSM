# Live browser multiplayer witness

`run_live_browser_multiplayer.cjs` opens two isolated, headed Chrome contexts of the deployed game. It does not automatically enter multiplayer or start its gameplay policy. Run only after the release owner confirms the public backend and frontend are ready:

```sh
node tools/run_live_browser_multiplayer.cjs --allow-public \
  --output output/playwright/live-multiplayer-unique-run --port 8876
```

Playwright is resolved from the local installation or the Codex CLI's npm cache. Override with `--playwright-module /absolute/path/to/playwright`. Optional `--width`/`--height` set the browser viewport (default 1600 × 900). Only this harness's own Browser object is closed; other browser sessions remain untouched.

The controller listens on `127.0.0.1` only. Send JSON POST bodies to these endpoints:

| Endpoint | Body / result |
| --- | --- |
| `/page` | `{ "role": "host" }` returns visible document text, canvas geometry and HTML buttons |
| `/capture` | `{ "role": "guest", "label": "river-lobby" }` saves a viewport PNG |
| `/input` | `{ "role": "host", "kind": "click", "x": 100, "y": 100 }`; also `press` with `key`, `type` with `text`, or `scroll` with `x`/`y` |
| `/viewport` | `{ "role": "host", "width": 1280, "height": 800 }` performs an ordinary viewport resize |
| `/start-policy` | `{}` enables paid orders only after both clients entered the match through the actual UI |
| `/stop-policy` | `{}` stops paid orders |
| `/ui-check` | `{ "role": "host", "check": "q_trained", "passed": true, "detail": "..." }` records an operator's already-verified observation |
| `/save` | `{}` saves current controller metadata |
| `/shutdown` | `{}` saves metadata and closes these two contexts |

GET `/state` provides passive authority metadata, elapsed real time, economy statistics, errors and rejection counts. Select host/join/map/start through canvas mouse input. Verify H/Q training and B construction UI before starting the policy, so the policy cannot be mistaken for the keyboard action. Record `q_trained` and `b_menu_open` only after inspecting the screenshot and command/authority receipts. On completion, capture both settled result screens and click Main menu through each rendered UI; record `menu_return` only after inspecting those screenshots.

The test-only WebSocket wrapper retains the actual browser-created game connection. It normalizes only outgoing command sequence numbers, so UI and policy commands share one monotonic counter. The policy issues ordinary allocate, train, place, age, research, attack-move and own-House demolition orders. Ownership, resource payment, visibility and placement remain server-validated. It does not change objects, snapshots, resources, simulation speed or terminal outcomes. Host troops claim the Sacred Site after the economy/combat phase while the guest withdraws; a completed Sacred result must arrive from the live server.

For a separate final-release UI/result check, `--objective-only` trains one paid Scout per side, sends the host Scout to the Sacred Site and leaves the guest Scout at home. It still waits for the normal 180-second Sacred hold at 1×. Its analyzer gates are explicitly narrower: paid recruitment/gathering, UI, identity, normal result and menu return; it does not claim construction, combat, destruction, age or research coverage.

This is browser renderer + lobby/keyboard UI + transport gameplay integration. Most gameplay orders are scripted protocol commands, not mouse gameplay. It is not a physical phone test or performance benchmark. Building destruction coverage includes normal paid House demolition; it does not establish an enemy-building combat kill. The private protocol omits Farm claim IDs and exact worker resource/dropoff IDs, so those cannot be verified from these receipts.

After closing the harness, analyze its immutable receipts:

```sh
python3 tools/analyze_live_browser_multiplayer.py output/playwright/live-multiplayer-unique-run
```

The analyzer exits nonzero for incomplete or failed gates and writes a separate `analysis.json`. It checks non-null match/seed/map identity, opposite slots, each packet's match identity, terminal agreement, shared authoritative ticks/actors/resources, same-unit HP decreases, economy/age/research, ordinary destruction, recorded UI checks and errors. All request cancellations remain in the report. Startup engine-fetch cancellations can be classified as recovered only with same-URL successful responses and actual loaded gameplay; asset response timestamps and request-finished events are retained when supported by that recorded controller revision. A 200 response header does not by itself prove that its body completed; actual gameplay is a separate observation.

Raw transport/snapshot logs belong under `output/`. Preserve a compact compressed archive and selected actual screenshots when committing evidence, with SHA-256 hashes and a candid run description. Never replace a failed raw receipt with a pass flag from a later run.

## Local paired mode

The harness can serve an existing sealed Web export and start a private copy of its matching sealed match-server context. Both must come from the same clean commit; every manifest entry and all shared scripts, scenes and assets are verified before launch. This mode changes no production artifact and makes no production connection.

```sh
node tools/run_live_browser_multiplayer.cjs --local \
  --artifact-dir build/three-kingdoms-93582e3-web \
  --server-context build/three-kingdoms-93582e3-server \
  --godot /absolute/path/to/Godot_v4.6-stable_win64_console.exe \
  --output output/playwright/local-935-unique --port 8876
```

`--local` cannot be combined with `--allow-public` or `--url`. It chooses free loopback ports for the Web files and authority, defaults to 844 × 390 browser viewports, disables service workers in these fresh test contexts, and requires an empty evidence folder. The controller's `invocation.json` records both actual endpoints. Do not start this three-process game witness while another rendering benchmark or broad Godot suite is active.

Native Godot supports `AOEM_MATCH_URL`, and its network methods accept an explicit endpoint. The exported Web boot exposes neither an endpoint query/config option nor a bridge from the harness environment to Godot's environment. Its supported game arguments currently select server mode only. Therefore local browser mode discloses one test-only interception: it rewrites **exactly** `wss://game.4mn.org/match` to the owned loopback socket URL. Any other socket destination is rejected before constructing a native socket; an independent Playwright context guard also blocks nonlocal sockets if the page wrapper is bypassed. HTTP requests are restricted to the owned artifact origin. No incoming packet, game object, resource, timer or result is rewritten.

The source receipts include original client/server manifests, 479 shared runtime source hashes for checkpoint 935, the private authority project and user directory, Godot executable hash, command, PID, ready port/protocol, and final source-integrity/termination checks. Browser response bodies for JS/WASM/PCK are hashed against the sealed export. The private runtime copy is retained at the recorded path for inspection. `local-source-final.json` is written only when the harness shuts down its own authority. Use `/shutdown`, or terminate the harness gracefully, to finish that receipt.

Local browser fixtures are automated tests, separate from the root agent's CUA play. Lobby entry still uses actual canvas input. `/start-policy` enables only the existing ordinary paid command policy, and `/stop-policy` stops it. Capture and inspect each side's selection/HUD before testing attack-move. **A is not an attack-move shortcut.** With both policies stopped and a living armed unit selected, use:

```json
{"role":"host","button":{"x":123,"y":321},"destination":{"x":456,"y":180}}
```

Send that body to `POST /attack-ui`, replacing the example coordinates with the observed Attack HUD button and visible ground. The harness takes before/armed/after screenshots, performs both real canvas clicks, and waits for a game-generated `attack_move` packet. A normal move, an A keypress or a policy-generated attack-move cannot pass. The packet is cross-checked against its actual WebSocket transmission by the analyzer. Repeat for the guest. No click location is inferred from internal game objects.

Complete the ordinary paid economy/combat journey, inspect the actual result screens and return to the menu. A new build that supports battle receipts should be exercised with repeated observed counter losses; record its visible lesson separately from the authority count. Checkpoint 935 has no battle-receipt lesson and must not be credited with one. This scenario is a functional authority/UI witness, not evidence of natural human match duration or physical-phone performance.

Analyze local runs with the same Python command above. In addition to existing gameplay gates, local mode requires source integrity, the recorded local authority, actual endpoint routing, loaded engine byte hashes, and both Attack HUD receipts. Run short harness checks independently with `node --test tools/test_local_browser_harness.cjs` and `python -m unittest discover -s tools -p test_local_browser_evidence.py`. Setting `POCKET_BROWSER_SMOKE=1` adds a roughly four-second real headless Chromium socket-guard check against a tiny loopback handshake fixture; it does not start Godot or play a match.

## Retained public runs — 23 October 2026

`docs/evidence/live-browser-multiplayer-20261023.json.gz` contains exact UTF-8 receipts and their SHA-256 hashes, separated by run, plus hashes for every local PNG. Selected unchanged PNGs are under `docs/images/live-beta9-*` and `docs/images/live-beta10-*`. The beta.9 River run was frozen before the beta.10 cutover so later assets cannot replace its startup evidence. The beta.10 Open Plains run uses the narrower objective scenario. An initial beta.9 lobby-only run records the footer defect; an optional keyboard-reload attempt is explicitly unverified and is separate from both matches.

This archive is gzip-compressed JSON, not a tarball. `runs[run_name].files[file_name].text` is the original text; recompute its UTF-8 SHA-256 against the adjacent `sha256` before reconstructing it. `runs[run_name].images` retains names, sizes and SHA-256 hashes of raw screenshots. The image mapping lists the selected copies kept in Git.

The final beta.11 Woodland objective check is preserved separately in `docs/evidence/live-browser-beta11-woodland-20261023.json.gz`; it does not modify the earlier archive. Both fresh clients enter directly through Home → Join a friend, inspect all map previews/names and Create/Join controls at 1280 × 800, then cycle all three shared maps and start Woodland. This remains the narrow objective scenario, with broad paid gameplay coverage attributed to the earlier River run.
