# Authority CPU follow-up — 23 October 2026

Two measured sources of unnecessary work are reduced without changing packet format or target choices. This batch follows the [late public River slowdown](live_deployment_2026-10-23.md); it does **not** yet establish full-speed late gameplay on the deployed release.

## Measurement before implementation

The public River receipts show near-equal authority and wall time through the first 400 seconds, then a gradual slowdown: the final 99.84 game seconds required 174.93 wall seconds. A synthetic paused fixture recreates the recorded final positions/types of 49 units and 28 owned buildings on the same River seed, 169179283. The Sacred Site is an additional building-group entry. It uses direct spawns and completed buildings; original paths, orders, cargo, research, depletion and paid progression are deliberately absent. It is a subsection cost reproduction, not a replay of that match.

The frozen baseline is `c864169a1169aa9ecda8e5586deada553ed7e899`. Baseline/candidate payloads differ in exactly `game_map.gd`, `network_match.gd` and `auto_targeting.gd`; parallel art, HUD and cargo work is excluded. All inputs use private preferences.

The first local profile found expensive automatic target searches and guest snapshot construction. JSON encoding, stationary fog refresh and drop-off route checks were much smaller. A first fixture attempt failed when replacing typed player arrays; its rejected logs/receipt remain in the archive. The corrected fixture clears the existing typed arrays and runs cleanly.

## Changes

- Automatic acquisition rejects distant opponents before checking current fog visibility. Previously every distant enemy triggered a live-source scan for player 1. Unit priority, equal-priority ordering, inclusive unit radius, strict building radius, explicit commands and current visibility rules remain intact. Expired ignored-target entries may now be pruned later when an irrelevant distant target is next queried; internal cache scheduling is not claimed identical.
- Resource serialization collects a player's live vision sources once per synchronous snapshot and tests resource tiles against that batch. The result is discarded immediately. Movement, spawning, deletion, ownership and vision changes are visible to the next call; ordinary gameplay visibility queries retain their existing implementation. Actor serialization and the wire format are unchanged.

## Isolated results

Local measurements ran serially in the coordinated Godot slot on the Mac. Remote measurements used four serial **baseline/candidate/baseline/candidate** containers on the actual x86-64 Linux server, with network disabled, read-only root, the deployed Godot image/user and the same 1.5 CPU / 768 MiB limits. Other host services remained active; this is not exclusive ownership of the entire server.

| Late-pose subsection | Local baseline median | Local candidate median | Linux baseline medians, two runs | Linux candidate medians, two runs |
| --- | ---: | ---: | ---: | ---: |
| Automatic acquisition for all 49 units | 74.936 ms | 1.811 ms | 390.634 / 396.174 ms | 8.577 / 8.684 ms |
| Slot 1 snapshot construction | 12.673 ms | 3.335 ms | 72.318 / 70.386 ms | 18.139 / 18.515 ms |
| Slot 0 snapshot construction | 0.306 ms | 0.285 ms | 1.719 / 1.715 ms | 1.503 / 1.507 ms |
| Both JSON encodings | 0.389 ms | 0.386 ms | 1.950 / 1.880 ms | 1.971 / 1.989 ms |

Each snapshot/JSON/fog measurement has 31 timed calls after warmup; acquisition and UI have 15; all-worker drop-off route evaluation has five. The all-unit acquisition pass is an intentionally concentrated workload, not a claim that all 49 units acquire simultaneously in ordinary gameplay. These timings identify relevant server CPU work and show a large repeatable reduction. They do not measure browser rendering, socket delivery or whole-match simulation throughput.

The remote image is `sha256:b821423cfb5ea2e129cd94932a11da691f0f3fd207b52792163f274bee1831ff`. Every before/during/after observation found no public authority connections. Its container ID/start time stayed unchanged and idle CPU samples ranged 1.55–2.27%. All four temporary containers exited successfully and were removed. No public service was replaced or reconfigured.

## Correctness and evidence

The candidate passes 115,323 assertions on the Mac and independently in each Linux repeat. The fixture compares every map tile plus out-of-bounds edges for both owners and a viewer without sources. It exercises movement, zero radius, death, a newly created Scout, queued deletion, actual deletion and a destroyed/restored building. Ordered resource arrays and complete snapshot dictionaries exactly match the original baseline implementation at every lifecycle state. The old-order target oracle checks all recorded units across three radii and both building-priority modes; directed checks cover ties, radius boundaries, ignored/dead/hidden/freed targets.

Six existing compatibility suites pass without engine errors or warnings: AI live vision, fog command legality, freed combat targets (138 checks), combat order priorities, simulation exclusion cooldowns, and resource replication across all three maps/both slots. All accepted profile processes also have clean logs.

Run the standalone semantic regression with `Godot --headless --path <private-copy> res://tools/test_authority_snapshot.tscn`. The reusable profiler is `tools/probe_authority_snapshot.tscn`; `--output=<absolute-json-path>` writes its receipt. A private original `network_match.gd` can be supplied with `--original-network=res://...` for complete packet comparison. Keep original/candidate sources frozen and run serially when collecting timings.

The [compressed evidence archive](evidence/authority-performance-20261023.json.gz) preserves exact input/source hashes, original and candidate sources, raw timing arrays, lifecycle assertions, full-packet oracle use, rejected attempt, compatibility logs, Linux container identities/commands and public idleness observations. Expanded receipts are under `output/authority-profile-2026-10-23/`.

Remaining validation: an ordinary paid late match on the combined release must establish actual authority/wall-time behavior. UI refresh, per-entity snapshot visibility, pathfinding and other simulation work remain; no general server capacity, physical-device or browser-FPS claim is made.
