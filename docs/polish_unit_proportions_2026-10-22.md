# Unit world proportions — 2026-10-22

The previous field art made foot troops almost as tall as mounted units and conspicuously large beside building doors. The source illustrations share a stylized, large-headed cast; shrinking every role equally would preserve the wrong cross-role hierarchy. The final candidate uses separate world scales for foot, mounted and siege roles, while recruitment portraits keep their existing size.

This review owns test updates, source/art analysis and the bounded defensive-fire attachment correction below. Root owns the runtime unit scale change; the building/resource proportions and native gallery are separate work. No SVG character redraw was made for this proportion pass.

## Measured artwork, final candidate

Dimensions are imported opaque texture bounds multiplied by the live world sprite scale, including equipment. They are world pixels, not display pixels; camera zoom changes their screen size.

| Role | Opaque width × height | Collision radius, unchanged |
| --- | ---: | ---: |
| Villager | 26.70 × 29.10 | 12 |
| Warrior | 28.21 × 31.00 | 14 |
| Archer | 29.70 × 28.20 | 13 |
| Horseman | 42.75 × 44.55 | 16 |
| Scout | 44.72 × 42.14 | 12 |
| Siege | 51.60 × 46.80 | 18 |

The Warrior spear extends slightly above the head. All sources keep the authored y104 ground anchor. The one-pixel antialiased spear/foot fringe stays within one world pixel of ground. Mounted figures are clearly taller and broader than foot troops; the siege carriage is broadest. The first candidate retained Siege at .50 (43 world pixels wide); the final .60 candidate establishes the intended carriage hierarchy.

## Internal illustration review

Reviewed the actual six SVG sources, the original unit comparison, the prior Scout comparison/roster, and `output/polish-2026-10-22/manual-integrated/14-occupied-farm-refusal.png`. The old roster showed the main problem directly: foot characters and mounted riders had almost equal total heights. The existing large heads and short legs are common across the cast. The current mounted hood/helmet widths are approximately 13–15 world pixels, versus roughly 10–13 for standing heads, depending on hat/helmet coverage. Source silhouettes remain recognizable by mallet, spear/shield, bow, light pennant mount, armored lance mount, and wheeled crossbow.

Recommendation: evaluate the scale correction in the native gallery before changing internal character proportions. A head/horse redraw would alter the established style and would need both team variants, mirrored silhouettes and portraits reviewed together. The present evidence does not identify one isolated malformed source component that needs a small correction.

## Consumer audit

- Collision radii, navigation positions, separation distances, attack range and combat stats are independent of sprite scales. They remain unchanged; visual resizing must not silently change balance or obstacle traversal.
- Desktop and touch targeting transform world points through the live sprite transform. Body targets therefore track scale, facing and animation. The deliberate ground target and generous screen-space touch discovery remain available.
- Main camera framing consumes `UnitBase.get_visual_bounds()`, which includes opaque art, current pose, a pose envelope, selection ring, stance shield and health placement. Villager cargo extends those bounds separately.
- Health height comes from the imported opaque top and live scale. Width still follows the logical unit radius. The selected ring, optional player markers and the 12-world-pixel cargo dot remain the same size; the cargo dot is consequently more prominent beside the smaller worker.
- Animation retains the 5-world-unit melee lunge and 2-world-unit walking bob. These motions are proportionally stronger on the smaller foot figures and need native visual judgment, although geometry includes the complete excursion.
- Projectile launch/impact offsets remain fixed at 18/16 world pixels above ground, with hit bursts at 14. They still lie within the new foot body height; this pass does not claim perfect hand or weapon attachment.
- Network replicas instantiate the same live unit scenes before applying snapshot animation. Both local player-slot mappings retain the same scale, foot anchor and health height. Their simulation stays disabled.

## Headless evidence

`output/polish-world-proportions-2026-10-22/validation.json` collects the four passing logs and source hashes captured after those runs. Art and Center receipts also contain their own source hashes. Final logs contain no script error or warning.

1. `tools/test_company_unit_art.tscn`: expanded from three to all six roles and both owners. The test checks equal team alpha, mostly shared neutral materials, aspect ratio, actual authored-foot-to-world-origin placement, opaque ground contact, clear idle health, qualitative size hierarchy, preserved collision, and 60 animated pose cases. Both desktop and touch resolvers select the body and deliberate ground target. Obsolete exact old-scale assertions were replaced with geometric constraints; no test asserts one chosen scale literal.
2. `tools/test_company_scout_art.tscn`: 120 mirrored pose cases across two phone sizes and three zooms. Checks current imported source pixels, selection, health, foot/ring alignment and touch geometry. Replaced the obsolete .48 assertion with mounted-size/aspect constraints.
3. `tools/test_company_unit_replica.gd`: expanded to six roles, two owners, both local slots and repeated reconstruction. Each inert replica is compared with a local scene instance, then receives actual snapshot animation/interpolation, health feedback and framing checks.
4. Existing `tools/test_center_selection_occlusion.tscn`: 130 actual Center dispatch cases. Tests moving/arrived workers, selected TC, phone/UI/notch profiles, overview through detail zoom, real HUD obstacles, touch/keyboard paths, group fallback, legal map focus and live resize. Passed with the final unit scales and new building anchor candidate.

These are deterministic geometry/integration checks, not a native appearance verdict, physical phone test, paid battle, or performance measurement. Native gallery and manual match evidence are recorded by the parent review separately.


## Linked defensive-fire attachment correction

The larger, reanchored TC still launched its arrows and drew its flash at the old fixed `(0, -52)` offset. That point no longer matched its lookout window. `BuildingBase` now stores source-art landmarks for the TC front lookout window `(101, 72)` and Tower open rampart `(64, 21)`. One helper transforms the source point through the actual sprite rectangle, sprite transform and parent transform. TC arrow release and flash use that same helper. No logical range, target priority, flight-duration, damage or cooldown expression changed.

The chosen pixels are opaque interior art: TC window `#34554b`, Tower rampart `#6c8069`, identical for both team variants. The test independently verifies those material pixels before checking their world locations. It exercises translated/rotated/scaled parents and a subsequent sprite movement, scale and rotation, so an accidentally fixed or cached offset fails. The fixture catches the pre-fix TC attachment failure, then passes after the correction.

Watch Tower's existing attack is immediate damage; it has no configured projectile speed and does not show the TC's shot flash. This correction preserves that behavior. The source anchor is available for its presentation, without introducing travel time or changing attack mode. Existing unit arrow/impact offsets and cargo dots were inspected but not edited.

Evidence in `output/polish-world-proportions-2026-10-22/`:

- `defense-before/receipt.json`: 112 baseline assertions, 16 failures confined to missing/transformed origins and detached TC releases. Combat timing/damage and source landmarks already passed.
- `defense/receipt.json`: 128 passing checks across TC/Tower, both owners, and ordinary/transformed parents. Actual building `_process` acquires targets and fires; TC still takes 0.2 seconds over 60 logical ground units at speed300, deals no early damage, resolves once, and retains its 2-second cooldown. Tower still deals immediate damage at its 1.5-second interval. Moving the art cannot extend logical range or change schedule.
- `town-center-defense.log`: existing 41 checks pass, including foundations, armor, ownership/fog, target priority, exact range, cooldown, pause and game-over.
- `combat-matrix.log` and `defense/combat-matrix.json`: unchanged 22,007 checks, 11,520 damage cells, 48 paid progression states pass.
- `combat-damage.log`: existing canonical damage/upgrades/armor/counters/siege/tower regression passes.
- `defense-validation.json`: passing logs and final relevant source hashes. No script errors or warnings in these final runs.

The source attachment is covered headlessly; its appearance in live fire still requires native review. The earlier native unit/building gallery contained no arrows and cannot validate this follow-up.

## Retuned architecture follow-up

After the later building reduction (roughly 10% narrower and 14–16% lower for the largest structures) and ground-center depth sorting, the current source passes the fire attachment test (128 checks), full combat progression matrix (22,007 checks / 11,520 damage cells / 48 paid progression states), existing TC defense test (41 checks), and world-proportion geometry test. Logs, copied matrix/geometry receipts and final relevant source hashes are in `output/polish-world-proportions-2026-10-22/retuned/validation.json`. No script errors or warnings appeared in these final runs.

The retune exposed an overly exact test comparison, rather than a displaced health bar: Barracks and Tower had measured clearances of `7.99999237060547` world pixels versus the intended 8. Transform composition and local-offset composition differ by float32 rounding. The comparison now allows the same 0.01-pixel tolerance used by adjacent framing checks. `retuned/geometry-float-diagnostic.json` preserves the original failing measurements; the passing report retains numerical art-top, bounds-top and clearance values. No runtime geometry was changed for this result.

`tools/render_defensive_fire.tscn` is a separate native diagnostic for the remaining appearance check. It loads actual Main/GameMap and the normal player TC, positions a free passive enemy Warrior on a legal tile, reveals fog, hides the HUD, and freezes the rest of the simulation. The actual TC release and DefensiveArrow methods advance by their ordinary time intervals, then pause at before/release/half-flight/impact instants. This does not modify damage, range, projectile speed or cooldown. At the observed 91.782-world-unit logical range, flight is 0.305941 seconds; the midpoint retains 0.027029 seconds of the ordinary flash timer, and HP stays60 until normal impact reduces it to56.

Run a fresh isolated native copy with:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /absolute/staged/project res://tools/render_defensive_fire.tscn -- --output=/absolute/evidence/directory --width=844 --height=390
```

The fixture writes four PNGs and a receipt with the rendering backend, exact source hashes, source-stability check, arrow/world/screen coordinates, time and damage. A headless run records state only and explicitly reports `native_rendered: false`; it produces no screenshot. These paused samples are neither a paid battle nor live cadence, performance or physical-device evidence. The current native review must specifically check whether the flash is visible on top of the opaque BuildingSprite: a positive flash timer and correct source position alone do not establish draw-order visibility.
