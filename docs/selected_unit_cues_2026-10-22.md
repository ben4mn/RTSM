# Selected unit position cues — 22 October 2026

Crowded melee could cover the selected friendly Scout's ground ring and body. `CommandPaths`, the existing foreground overlay, now draws two small hollow foot brackets for selected, live, currently visible own units. Bone strokes over an ink outline preserve the position without moving the sprite above other actors. Clear player markers disables the extra cue; reduced motion/flashes retain its static shape.

The four line segments occupy 12 × 6 logical viewport pixels at every camera zoom. Both inner horizontal tips stop three pixels from the center. All selected units share two `draw_multiline` calls. The helper checks retained entries as Variants before casting, then filters owner, selection, queued deletion, death/HP, node visibility and current tile vision. It reads no enemy roster and creates no nodes or input surface. Existing route rendering, two-second expiry, unit depth and simulation are unchanged.

## Paired checks

The baseline is `5d825008de1699b92e2d9b917852723595c104da`, with the same new fixture overlaid. Candidate source was frozen in `/tmp/aoem-selected-cues-5d82500`; baseline used `/tmp/aoem-selected-cues-baseline-5d82500`. Each project has separate private preferences. Root's subsequent beta.8 release metadata was outside this presentation snapshot.

| Check | Baseline | Final candidate |
| --- | --- | --- |
| Headless cue contracts | 76 failures / 136 assertions | 148 / 148 pass |
| Native Metal Mobile cue contracts | 88 failures / 176 assertions | 188 / 188 pass |
| Existing `test_command_path_feedback` | Existing regression | Pass |
| Candidate asset/script import | — | Pass |

Baseline has fewer assertions because there are no cue points on which to check the anchor. Its native images have zero foreground cue pixels. Final candidate checks four profiles (844 × 390 and 932 × 430, Standard and Extra Large) at zooms 0.65, 0.952 and 1.6. All twelve native on/off pairs contain 77–192 cue pixels, **zero changed hollow-center pixels and zero changed body pixels**. Deselect clears the final drawn pixels. Images were inspected at overview, ordinary and detail zoom.

The fixture uses actual Main, UnitBase, SelectionManager and rendering, with a held simulation and controlled synthetic Scout/Warrior crowd. It covers passive movement, idle, expired routes, multiple selection, deselect, dead, zero-HP, queued, truly freed retained entries, hidden and explored-only units, enemies, buildings and marker preferences. It calls the actual network adapter's owner-remapping helper for both assigned slots; this is an ownership contract, not a new network transport test. Repeated cue reads preserve orders, paths, HP and banks. The pre-existing route regression confirms accepted detours, movement progress, no feedback pathfinding, expiry/reselection, Stop/arrival/death, combat intent and three-group limits.

Two initial checks remain in the raw evidence. Eight headless assertions initially rejected floating-point rounding of at most 0.0001221 logical pixels; the geometry tolerance was corrected to 0.01 pixel. The first native run found two antialiased ink pixels touching the hollow-center sample at zoom 1.6. Moving the inner tips from ±2 to ±3 fixed the raster cause; the strict zero-pixel assertion was retained. Final candidate import, cue runs and route regression have zero engine errors or warnings. All validation processes exited before handing the engine back to root.

## Source and evidence

- Runtime `scripts/ui/command_path_overlay.gd`: `f94780df29b1adccf70acaa5fa05c5f8e0581e6ac15b376e5634f52530df6a21`
- Fixture `tools/test_selected_unit_cues.gd`: `762d7bc7747fd4af66405e8cb4a8d27367cfddb9a7432ea6d6526413895623a1`
- Full frozen manifests, loaded-source hashes, per-run private directories and summaries: `output/selected-unit-cues/source-receipt.json`.
- Reports/logs: `output/selected-unit-cues/{baseline,candidate}-{headless,native}.{json,log}`.
- Twelve candidate/reference image pairs: `output/selected-unit-cues/candidate-native-captures/`; baseline pairs in `baseline-native-captures/`. Initial failed logs/images are retained with `initial-` prefixes.

This is a bounded presentation and lifecycle regression, not a paid tactical match, physical-phone test, multiplayer transport run or rendering-performance measurement. Actual touch targets and input routing were not modified.
