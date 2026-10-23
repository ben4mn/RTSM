# Building depth and input review — 2026-10-22

This review uses the frozen private checkout recorded in `output/polish-2026-10-22/proportions/final-ui-review-stage/source.json`. It covers the first enlarged-building candidate before the subsequent user-requested scale reduction. No production input or sorting behavior was changed by this review. Later source changes need their own affected checks.

## Concrete depth concern

`GameMap._ready()` enables Y sorting on the map and the world containers. A `BuildingBase` root keeps its first reserved tile as its logical origin. Its sprite now sits at the reserved footprint's center (+48 world Y for 4×4, +32 for 3×3, +16 for 2×2), but the building root itself does not enable Y sorting.

Godot 4.6 sorts the descendants of a child with Y sorting disabled together at that child's Y position. Therefore the sprite offset alone does not update the building's depth anchor. A worker whose feet are between the first tile and the actual footprint center can draw over the architecture. Enabling Y sorting on the building would expose the centered sprite to the map's shared sort; native overlap evidence is required before changing production. [Godot 4.6 CanvasItem documentation](https://docs.godotengine.org/en/4.6/classes/class_canvasitem.html#class-canvasitem-property-y-sort-enabled).

`tools/test_building_depth_sort.tscn` provides matched OFF/ON captures in the same real Main scene. It covers Town Center 4×4, Barracks 3×3 and House 2×2, eight static workers around all four edges, and both normal and selected/damaged buildings. The only changed property within each pair is `building.y_sort_enabled`. Logical positions, footprint, collision dimensions and worker-foot selection are asserted unchanged. Workers are synthetic free objects placed outside occupied cell squares; this is not a movement or economy test.

Native mode writes 12 paired-state images plus 12 workerless references. It reports the pixel difference within each worker's opaque screen bounds and requires the health/badge strip above the roof to stay pixel-identical across the sort toggle. Headless mode checks geometry and selection only. The headless fixture passes; `depth-sort-headless.log` and its receipt are under `output/polish-2026-10-22/proportions/`.

The initial 24 native captures in `depth-native/` showed identical worker visibility in both sort modes. That first fixture missed the overlap: its back samples were behind both anchors and its positive-Y corner samples were outside the building ink. It did not demonstrate a visible sorting defect and is not evidence for a production change.

The revised fixture scans both upper perimeter edges in half-tile increments and measures actual sprite-alpha overlap at world-pixel centers. Only candidates with feet strictly between the logical root and centered sprite depth are eligible. On the later TC scale 1.70×1.60, the strongest samples lie at tile offsets (-0.7,1.0) and (1.0,-0.7), with feet 4.8 world pixels below the root: Town Center has 459/458 opaque overlapping pixels, Barracks 453/392, House 22/8. The complete sweep and headless input/geometry results are in `depth-sort-sweep-headless/receipt.json`. Native mode now requires at least one positive worker-visible pixel reduction across the sort toggle; a repeated no-op comparison fails instead of passing.

The revised native run passed, with all 24 PNGs and its receipt at `output/polish-2026-10-22/proportions/depth-retuned-native/`. Root visually inspected the matched captures. A Town Center upper-edge worker changed from 477 visible difference pixels with root sorting to zero under the roof with centered-art sorting, while the lower-edge workers were unchanged. The selected/damaged overhead feedback comparison also passed. This provides the previously missing rendered evidence. Root then enabled `BuildingBase.y_sort_enabled = true`; the building's logical position, collision, footprint, combat/path origin and deliberate unit-foot input priority remain unchanged.

Run with a private imported stage:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path "$STAGE" res://tools/test_building_depth_sort.tscn -- --output="$OUTPUT"
```

The fixture inherits scene setup helpers from `tools/render_world_proportions.gd`, so that file must also be present. Preferences are backed up/restored; the source receipt hashes the complete runtime/art inputs and both fixtures. No physical-device or performance claim is made.

## Focused input and UI checks

Nine headless checks passed on the frozen candidate, with original failures and corrected-fixture logs retained in `final-ui-review-stage/`:

- World geometry: all ten real building transforms, ghosts, ground centers, collision dimensions, feedback bounds and resource proportions.
- Building facade selection: seven production facades, nearby friendly/enemy bodies and resource discovery rings, mouse/touch at three zooms, armed destinations, grouping and construction.
- Touch building reselection and zoom-scaled hit radii.
- Actual tree/Farm targeting, direct resource/enemy priority, visibility and Farm guards.
- Build-menu to useful world preview, explicit touch Place, genuine mouse placement, cost/spend boundaries and cancel/reopen.
- Routed multitouch placement: arbitrary contact IDs, sticky camera gesture, HUD release ownership and one paid House.
- Mobile area selection, camera/input isolation, cancellation, double taps, attack mode and rally.

Two existing fixtures had assumptions tied to the former artwork placement. The facade test put every competing resource at fixed world (-32,-16), which was outside the discovery radius of two shifted facades. It now positions the synthetic resource relative to the transformed facade and explicitly verifies that it competes through its discovery ring rather than opaque canopy. The reselection test called TC-anchor +36 pixels empty ground, but that point lies inside the enlarged facade. It now derives exterior ground from the real opaque sprite bounds and asserts that it lies outside the facade before issuing the tap. Both corrected fixtures pass without changing production selection rules. Updated fixture hashes are in `review-fixture-overlay.json`.

The source audit found resource feedback bounded by the existing resource ring/badge region plus transformed sprite artwork; current camera helpers account for that union. Building ghosts and final sprites use the same canonical center, scale and source anchor. Sacred-site screen annotations use the site's own position and live fog state; the world proportion changes do not alter those coordinates. Native pixel checks of sacred annotations remain separate from this headless review.
