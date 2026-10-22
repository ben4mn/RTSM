# Stand Ground acquisition — 22 October 2026

Stand Ground now acquires unit targets only within its existing engagement reach. This removes a false acquisition/abandon cycle and a resulting three-second delay against enemies moving into range. It does not extend weapon reach or permit stationary guards to chase.

## Reproduced defect and scope

The clean beta.4 baseline is `1ea5bf0`. An Archer has 80 world units of weapon range and begins an attack through 88 units, but its Stand Ground scan searched through 96. At 89 and 96, the Archer acquired the target, immediately abandoned it without moving, and put it in the three-second autonomous-target ignore cache. A Warrior had the same mismatch at 25/32 versus its 24-unit engagement boundary.

A second acquisition path reproduced the same problem. While attacking a reachable building, `_consider_nearby_threat()` searched the unit's vision radius. An aggressor just outside engagement reach could replace the building target, then be abandoned in the same frame. The original building attack was lost even though the guard could still hit it.

The only runtime edit is `scripts/units/unit_base.gd`. Both acquisition paths use `_get_auto_unit_acquisition_radius()` to apply `attack_range + 8` when stance is Stand Ground and `attack_move` is false. Existing scan radii remain for attack-move, patrol and Aggressive stance. Explicit attacks retain their priority and permitted pursuit; retaliation already used the correct stationary boundary. Building reach remains unchanged. Combat damage, stats, windups, committed-projectile rules, movement, chase limits, fog validation and target priorities are unchanged.

Frozen UnitBase SHA256: `394d2ab4676726a225f23a5c045124a7cdc9b24357a6d19daeeab0861d6cfea3`.

## Focused before/after evidence

The new `tools/test_stand_ground_acquisition.tscn` uses actual Archer/Warrior scenes and their data-driven stats, the normal command/state machine, real combat windups and projectile/melee resolution. A deterministic visible arena supplies a direct walkable route and a controllable current-visibility boundary. Both player owners are tested at 60 Hz with private user data. No resources, paid armies, browser clients or render-performance measurements are involved.

The same 146 assertions produce 28 expected failures on the baseline and zero failures on the candidate. Final candidate logs contain no runtime errors or warnings.

| Case | Baseline | Candidate |
|---|---|---|
| Standing Archer at 88 | Acquires; 36 damage over 3 seconds | Identical |
| Standing Archer at 89 / 96 | Acquires, abandons, adds ignore entry; no damage | No acquisition or ignore entry; no damage |
| Standing Warrior at 24 | Acquires; 18 damage over 3 seconds | Identical |
| Standing Warrior at 25 / 32 | Acquires, abandons, adds ignore entry | No acquisition or ignore entry |
| Enemy walks from 96 toward 80; crosses 88 at 0.150s | Acquires in range at 3.183s; first hit 3.650s | Acquires at 0.333s; first hit 0.800s |
| Reachable building plus out-of-reach aggressor | Building target discarded | Building target retained |

These results match for owners 0 and 1. The moving enemy uses a real passive Move and its own Stand Ground stance, so arrival does not turn the controlled approach into retaliation. After its inward approach it retreats to 140; the guard releases it without leaving its exact starting position. Damage already released follows the existing projectile rules.

Other passing assertions cover explicit unit attacks at 89/96 despite another attacker's damage, explicit building priority, attack-move and patrol acquiring at their original 96-unit radius and resuming after the target dies, Aggressive vision-radius acquisition/pursuit, advancing threat switches, passive Move under actual damage until arrival, retaliation at 88 but not 89/96, hidden-target rejection, and loss of an acquired target when current visibility disappears. Threats exactly in reach still interrupt autonomous building attacks.

Existing `test_combat_order_priorities` and `test_combat_spacing` also pass. Spacing still reports 26.779 world units minimum separation and 120 damage in each of its two terrain cases.

## Reproduction and limits

Run the new scene in an isolated project copy with `config/use_custom_user_dir=true` and a unique `config/custom_user_dir_name` under `[application]`:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <isolated-project> \
  res://tools/test_stand_ground_acquisition.tscn -- --output=<absolute-report.json>
```

For the baseline, keep the same fixture and replace only UnitBase with `git show 1ea5bf0:scripts/units/unit_base.gd`. The local raw logs/reports are under `output/stand-ground-20261022/`; its `stage.txt` records the private project. The [compact receipt](stand_ground_metrics_2026-10-22.json) includes source hashes, before/after metrics and assertion failures. The first fixture draft used a property name reserved by Node2D; that parse error was corrected before either recorded comparison.

This isolates acquisition and order semantics rather than testing map routing, economy, network transport or human balance. The [separate paid tactical comparison](paid_tactics_boundary_regression_2026-10-22.md) records fifteen pairs and three slower-learner Easy matches against this frozen runtime. Faster responses can change combat timing and outcomes; identical tactical results are not promised. Existing ignore behavior after an already engaged enemy retreats out of reach is preserved. A stationary guard and an enemy both outside effective reach can still end a fight without further damage, as intended by the no-chase stance.
