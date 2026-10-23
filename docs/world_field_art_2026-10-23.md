# Company landscape and resource art — 23 October 2026

The battlefield now uses original faceted oak, elm and pine crowns, clustered fruit, visible gold veins and cut-stone deposits. Their warm highlights, dark green contours and grounded trunks share the existing Company buildings and people’s visual language. The three tree silhouettes are selected deterministically from their tile coordinates, without consuming the simulation’s random stream.

Ground has restrained, continuous meadow variation rather than repeating diamond stamps beneath each resource. Deeper mineral-blue water, tiered shallows and sparse static glints make River Crossings easier to distinguish from land. These are static surface treatments; this batch does not add water or foliage animation.

| View | Frozen baseline | Accepted art |
| --- | --- | --- |
| Ordinary-zoom home, 844×390 | [Before](images/field-art-home-before-20261023.png) | [After](images/field-art-home-after-20261023.png) |
| Woodland grove, 844×390 | [Before](images/field-art-grove-before-20261023.png) | [After](images/field-art-grove-after-20261023.png) |
| River crossing, 1280×720 | [Before](images/field-art-crossing-before-20261023.png) | [After](images/field-art-crossing-after-20261023.png) |

The grove is a 1.35× detail view; home uses 0.952× and the crossing 0.65×. The complete comparison contains eighteen matching cameras per version across all three maps and both window sizes. These are actual Main/GameMap scenes, deliberately stopped and revealed for presentation comparison. They are native desktop renders, not physical-phone play or a paid-match claim. The isolated comparison retains the preceding HUD and worker indicators; later combined captures include those independent changes.

## Preserved gameplay and rendering boundaries

Only the resource and terrain presentation changes in this batch. Every compared grid hash, tactical path hash, resource count, resource position, source stock, sprite scale/offset and terrain-cell count agrees exactly across all six map/profile records. The existing 16-pixel resource collision radius, grounded proportions, harvesting arithmetic, depletion signal/fade and fog memory are preserved. Canopy input samples the new visible art; transparent padding stays untargetable and direct food/enemy targeting retains priority.

The six new resource textures are authored SVGs on 128-pixel canvases. The previous source PNGs remain unchanged. Contact shade is baked into each new vector, with its footprint inside the existing ground interaction circle. Resource artwork uses no palette shader, extra nodes or per-frame presentation code. The existing terrain atlas remains 1536×32 (196,608 raw RGBA bytes); two shared static materials add world-space surface variation. Their fragment output preserves source alpha and inherited tint. Fog atlas bytes remain unchanged.

The first shadow implementation added one Sprite2D per resource. Counters exposed 421 additional nodes on Woodland and up to 105 extra draw calls in the inspected views, so that implementation was rejected. Baking the shade restored exact node-count equality in every comparison. Final sampled draw calls are equal or lower in seventeen of eighteen views. The fully revealed, wide Woodland phone route increases from 88 to 118; the corresponding desktop view falls from 157 to 142. These are scene counters, not a frame-rate or GPU benchmark. An isolated combined-build performance check is recorded separately by the coordinator.

## Verification and retained attempts

- `test_terrain_presentation` passes 37,223 assertions and sixteen native River/Woodland views. It covers shoreline alpha/direction/interiors, all cells, unchanged scene topology, hidden depletion memory and rendered land/water/shore alpha plus inherited half-alpha/darkness.
- `test_company_resource_materials` passes all four resource kinds and all three tree variants: exact visible-alpha picking, calibrated scales/anchors, two-child resource structure, direct authored colors, GPU inherited fade and exact final harvesting/depletion. Six native resource-map views and the enlarged material sheet were also produced.
- `test_world_proportions`, `test_resource_visual_targeting`, `test_resource_fog_targeting`, `test_touch_military_resource_routing`, `test_resource_production_rally` and all five `test_paid_builder_cargo_return` cases pass. Visual targeting used a native window and actual dispatched input; the other compatibility suites used headless Godot. No final test log contains an engine error or warning.

The initial archive import tried to import an existing documentation image whose JPEG bytes had a `.png` extension. Its failure log remains; documentation was excluded from both private stages, and the coordinator added the same `docs/.gdignore` protection to the repository. An early art fixture used a five-pixel base allowance instead of the existing world-proportion contract’s six pixels; the fixture now uses that established contract, with gold at 5.2 pixels and stone at 5.5. Two mistyped fixture paths produced missing-scene logs; those launches are excluded and the correctly named fixtures were rerun and checked for explicit PASS plus clean logs. Superseded captures remain separate from the accepted final set.

## References and evidence

The [official Age of Empires IV atmosphere guide](https://support.ageofempires.com/hc/en-us/articles/8330758084628-Ultimate-Atmosphere-Guide) recommends assessing ground, water, units and buildings together. The design inference here is coordinated warm terrain, cooler shadows and restrained surface detail. The [22 October official update preview](https://www.ageofempires.com/news/age-of-empires-iv-update-17-0/) discusses withdrawing color options that caused readability problems; our inference is to reserve stronger contrast for actors and meaningful cues. No Age of Empires artwork was copied.

Frozen baseline: `c864169`. Stages, all native comparisons, rejected attempts and final logs: `output/world-art-2026-10-23/`. The reusable comparison is `tools/capture_world_field_art.tscn`; pass `-- --output=<absolute-directory>` in either frozen stage. Exact source hashes, paired geometry/camera records, final counters and test receipts are preserved in [the compact evidence archive](evidence/world-field-art-20261023.json.gz). This batch does not claim physical-device performance or replace the coordinator’s combined gameplay, browser and deployment verification.
