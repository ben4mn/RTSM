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
overlap checks refresh every 100 ms. Headless authority runs perform no scans and
create no echoes.

`tools/test_unit_occlusion.tscn` uses actual Main, map, unit/building/tree art and
staged positions. It checks all three civilizations and both owners across the
three occlusion types, the below-fog ordering, immediate explored/unexplored,
parent/source-hidden and death suppression, transparent pixels and removal. With
a native renderer and `-- --output=<directory>`, it saves staged in-game evidence
for each civilization and occluder. These fixtures demonstrate rendering and fog
contracts; they do not claim ordinary human play or physical-device testing.
