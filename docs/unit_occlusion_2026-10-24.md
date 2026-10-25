# Units behind world artwork

The beta7 visibility addition preserves the shared isometric depth sorting and
all original civilization art. When a currently revealed unit is behind opaque
building, tree or another unit's artwork, it receives a thin parchment edge and
a restrained translucent body silhouette above the occluding world art. It
applies to French, English and Mongol units, either owner, selected or not.

`scripts/ui/unit_occlusion_overlay.gd` is a presentation observer attached to the
map. Every echo is a noninteractive Sprite2D child of the real unit. Absolute
z=5 places it over ordinary world art and below the fog layer at z=10. It never
adds a target, collision shape, group, command, stat or selection region. The
shader draws inside the existing body alpha, keeping visual bounds unchanged.

Every frame it checks the canonical local-player visibility query, the unit's
alive state, ancestor visibility and source sprite visibility. Explored-only,
unexplored, dead and remotely hidden enemies have no echo, even between overlap
refreshes. The overlap scan also excludes unrevealed occluders. It uses actual
opaque pixels after a screen/depth/bounds/spatial-bin filter, rather than treating
transparent texture padding as an obstacle. Pose transforms update each frame;
overlap scans start about every 100 ms and process at most 32 units per frame.
At 200 actors a complete pass takes seven rendered frames; the next scan waits
for completion. Per-frame fog/death/source visibility gates remain immediate,
so batching cannot retain an enemy silhouette after vision is lost. Cached
opaque body samples and spatial bins bound repeated texture work. Headless
authority runs perform no scans and create no echoes.

`tools/test_unit_occlusion.tscn` uses actual Main, map, unit/building/tree art and
staged positions. It checks all three civilizations and both owners across the
three occlusion types, the below-fog ordering, immediate explored/unexplored,
parent/source-hidden and death suppression, transparent pixels and removal. With
a native renderer and `-- --output=<directory>`, it saves staged in-game evidence
for each civilization and occluder. These fixtures demonstrate rendering and fog
contracts; they do not claim ordinary human play or physical-device testing.

## 200-actor CPU probe

`tools/probe_unit_occlusion_cost.tscn` uses 200 actual infantry art nodes with
synthetic dispersed/crowded positions, headless rendering and an explicit test
override. Forty calls per case request the next scan whenever its batches finish.
Before batching, a complete crowded refresh averaged 27.06 ms at an 844×390
viewport and 18.96 ms at 1280×720 (p95 33.71/22.98 ms). This exposed a large
single-frame burst at the newly requested 100-per-side scale.

After caching opaque body samples, avoiding unchanged render-property writes,
and processing at most 32 units per call, crowded calls averaged 5.29/5.34 ms
(p95 8.16/9.71 ms; maxima 8.91/11.27 ms), with 200 opaque candidate checks over a
complete pass. Dispersed calls averaged 2.18/2.24 ms. These measurements compare
an old complete-refresh burst with amortized calls, not equal-work throughput;
they do not establish GPU frame rate or physical-phone performance. Canonical
fog/death visibility still updates on every frame, regardless of batch position.
