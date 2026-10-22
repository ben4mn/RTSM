# Independent presentation integrity — 22 October 2026

The integrated beta.6 candidate preserves the baseline's map and resource behavior in all tested cases. Nine paired maps match exactly, six controlled resource replication cases match exactly, and the complete ten-check local authoritative multiplayer suite passes. This receipt is independent of the authors' [terrain](terrain_readability_2026-10-22.md), [resource material](company_resources_2026-10-22.md) and notification UI checks.

## Source and isolation

Baseline is clean commit `ec6a3da3b656a783038816956d21df0ca5beb302`. The candidate was copied only after all runtime owners declared a freeze, into `/tmp/aoem-presentation-candidate-final`. Its 455 script/scene/project/shader/Python hashes and 237 runtime input hashes are retained in the [compact machine-readable receipt](presentation_integrity_metrics_2026-10-22.json). The latter includes assets, scenes, scripts and project settings, excluding generated import metadata and UID sidecars. They still match the shared tree after validation. The runtime changes from baseline are the five approved scripts, the new resource shader, and beta.6 project metadata; no map generation, pathfinding, unit, combat, AI, economic data or PNG texture bytes changed.

Every independent case uses a unique temporary project configuration and custom Godot user-data directory. All 20 recorded preference directories are distinct, including baseline and candidate. Frozen source hashes are checked before and after each runner. All local clients and servers exited; no public service was contacted. Headless timings are not rendering or mobile-device performance measurements.

## Paired map contracts

The same final probe runs against baseline and candidate for all three archetypes and seeds 101, 424242 and 20261021. Actual GameMap scenes are instantiated. The probe checks every terrain cell, exact generated grids, resource stocks/collision radii/world positions/texture scales and offsets, TC footprints, all navigation solids and weights, and exact tile and world paths along all three tactical routes and expansion routes. Diagonal paths may not cut blocked corners. Each River crossing is additionally tested with the other two crossing areas blocked; all nine independent crossing checks pass.

| Map | Seed | Resource nodes | Grid SHA-256 prefix | Tactical paths SHA-256 prefix |
|---|---:|---:|---|---|
| Open Plains | 101 | 160 | `6f89107e2597` | `40d993cf4c03` |
| Open Plains | 424242 | 174 | `73efc0faf0df` | `cd09308fd7f1` |
| Open Plains | 20261021 | 209 | `d1a136315473` | `6f7604188417` |
| River Crossings | 101 | 114 | `111c6c817c86` | `b51e2867bda7` |
| River Crossings | 424242 | 140 | `3bd86b9cbf58` | `346991569451` |
| River Crossings | 20261021 | 156 | `fd3aaeae827d` | `6e16d809ae10` |
| Woodland Flanks | 101 | 417 | `cb63a69d974c` | `12322d469db5` |
| Woodland Flanks | 424242 | 420 | `8a57c4fc855b` | `917fa750c5f7` |
| Woodland Flanks | 20261021 | 478 | `5ec7b3109ae4` | `7817680821da` |

All listed hashes and all remaining mechanical records are identical before and after. Full hashes and raw-array report digests are in the JSON receipt. Atlas assignments change for all nine maps, with the atlas growing from nine to twenty-four tiles; these presentation differences are kept separate from mechanical comparisons.

## Resource snapshots and fog memory

`test_presentation_resource_replication.gd` uses the real matched-packet handler to load Main for each archetype and both player slots. A second actual GameMap supplies resources to the production snapshot serializer; payloads pass through JSON and the actual client snapshot handler. Socket polling is disabled in this controlled fixture. Visibility and harvest amounts are controlled, so this is serialization/replication evidence, not a paid economy or live-transport claim.

For each of six cases, food/wood/gold begin at 200/250/400. Real partial harvests of 7/13/19 leave exactly 193/237/381 on both source and replica. Hidden stock is omitted and unchanged. Over-requested harvest returns only available stock; exhausted nodes retire on both sides. Live grid/navigation updates immediately while explored-only terrain and minimap retain their old resource memory. Repeated zero-stock packets are harmless. Reveal updates both rendered ground and minimap, clears pending memory, and leaves water atlas assignments unchanged. The six full result records equal baseline exactly.

## Integrated local checks

All ten checks in `run_online_tests.py --stand-ground-combat` pass: Strategy controller commands for both slots; connection failure; terminal result during loading; connection failure during loading; queue/lifecycle/malformed packet handling; two paid production clients; and two paid combat clients. The combat pair verifies paid Barracks and Infantry, attack-move, visible enemies, replicated damage, requested Stand Ground, effectively inert replicas, and surrender results. A separate `--maps-only` run passes three real local catalog pairings: legacy, mixed and current clients share the chosen seed/archetype. Server logs are clean.

Existing camera-map-edges, resource-production-rally and resource-fog-targeting checks also pass. Successful import, map, resource and these three regression runs contain no errors or warnings. The full online run has no runtime errors and three existing `ObjectDB instances leaked at exit` warnings (client-one, loading-ended and combat-one); those cleanup warnings remain visible in the receipt. This result does not claim a warning-free online harness.

The first resource fixture draft failed compilation because its SceneTree script eagerly preloaded scenes before autoload identifiers were available. Loading the scene inside the deferred fixture entry point fixed the test harness. The unsuccessful draft logs remain under `baseline-resource/`; only the corrected baseline and final candidate are used in comparisons. No application fix was needed.

Read-only review of the HUD change found no additional input/state risk: HUD owns toast visibility, modal/secondary sheets suppress ordinary toasts without extending lifetime, BattlefieldFeedback reports alert activity through the HUD setter, canceled touches are excluded, and emulated duplicate events are consumed. Root's separate real-touch regression validates this path; this independent receipt does not substitute headless geometry checks for rendered UI evidence.

## Reproduction

From an isolated frozen source copy, import and run the map and resource contracts with private preferences:

```sh
python3 tools/run_presentation_integrity.py --project <frozen-source> --output <evidence> \
  --import-assets --case res://tools/probe_presentation_map_integrity.tscn \
  --case res://tools/test_presentation_resource_replication.gd \
  --compare-map <baseline-evidence>/probe_presentation_map_integrity.json
python3 tools/run_online_tests.py --project <frozen-source> --output <online-evidence> --stand-ground-combat
python3 tools/run_online_tests.py --project <frozen-source> --output <catalog-evidence> --maps-only
```

Omit `--compare-map` for the baseline run. Existing cases may be passed repeatedly with `--case`. Raw evidence is under `output/presentation-integrity-20261022/`; its source receipts and log/report SHA-256 digests are recorded in the committed JSON. This pass changes only independent test tooling and documentation. Broader seed balance, actual-device rendering speed and public multiplayer deployment remain outside this receipt.
