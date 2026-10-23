# Scout visual validation — 2026-10-22

Scope: the coordinating agent revised `assets/units/scout.svg` and `scout_enemy.svg`. This independent validation adds only `tools/test_company_scout_art.gd` and its scene. It does not change artwork, gameplay, collision, selection, animation, or balance.

## Headless evidence

Command:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/test_company_scout_art.tscn
```

Passed in Godot 4.6 with no runtime errors:

- The owner variants have identical alpha at every source pixel. Of 4,827 opaque pixels, 3,215 remain identical neutral material; only part of the art changes owner color.
- Current imported textures match source alpha and opaque colors. The comparison permits Godot's normal RGB repair in transparent texture borders.
- Both live Scout scenes retain their 128×128 canvas, 0.48 world scale, `(0, -40)` sprite offset, 12px collision radius, neutral white modulation, and correct owner texture. Source opaque bounds are `(14, 6)` to `(118, 104)`, preserving the hoof baseline.
- 120 pose checks cover both owners, both facings, idle and sampled mounted gait, selection, critical health, and stand-ground shields. Artwork and overlays fit reported visual bounds. The central rider/mount body remains a valid touch target and adjacent terrain remains outside it.
- Framing checks span 844×390 and 932×430 logical phone viewports at overview 0.65, normal 0.952, and close 1.6 zoom.

The latest result is written to `output/polish-2026-10-22/scout-art/scout-art-contracts.json` and explicitly records whether native rendering ran. `git diff --check` also passed.

## Native presentation fixture

The coordinating agent ran the native fixture through MCP and inspected the before/after contact sheet, normal-scale roster, feedback, and 24-unit formation screenshots. The native result passed all contracts, saved all eleven PNGs, and reported no runtime errors. The reviewed captures showed clear owner cloth, an unarmored mounted silhouette distinct from Cavalry, and readable selected/critical-health overlays at phone scale.

Reproduce the native gallery with:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/test_company_scout_art.tscn
```

Native mode automatically writes eleven PNGs to `output/polish-2026-10-22/scout-art/` and exits:

- `scout-before-after.png`: archived and current artwork for home/opponent cloth, each facing both directions. Baselines come from `output/polish-2026-10-22/scout-baseline/`.
- `roster-<width>x<height>-zoom<zoom>.png`: six views using the actual Worker, Warrior, Scout, Cavalry, Archer, and Siege scenes on the game map, with both owners and all three zoom levels. Scout sits beside armored Cavalry for silhouette comparison.
- `feedback-<width>x<height>.png`: selected home Scout with stand-ground indicator, critical-health opponent Scout, and optional owner markers.
- `formation-24-units-<width>x<height>.png`: two mixed formations at normal zoom in each phone viewport.

These are a native presentation gallery and deterministic geometry/input-contract checks. They are not hands-on battle evidence, actual mobile-device testing, or performance measurements. Native launch and visual review were performed by the coordinating agent; this validation agent supplied the fixture and headless checks.
