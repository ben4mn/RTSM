# Combat progression audit — 22 October 2026

This audit separates the current damage rules from match balance. The values below come from UnitData, TechData, Combat and the paid GameManager transactions. No cost, attack, armor, HP, counter multiplier or attack cadence is being rebalanced in this pass.

## Ages and research

Dark, Feudal and Castle ages use the same unit base stats. Advancing age is an immediate paid unlock: Feudal enables Archery Range, Stable and Watch Tower; Castle enables Siege Workshop and additional Town Centers. It does not increase the HP, attack or armor of existing or future units. The former UnitData comment describing all values as Age 1 stats was misleading.

An active owned Blacksmith offers four immediate, one-time purchases from Dark Age onward:

| Technology | Cost | Scope |
| --- | --- | --- |
| Forge Weapons | 100 food, 50 gold | +2 attack to existing and future armed units, including Villagers and Siege Engines. Scouts remain unarmed; building weapons are unchanged. |
| Scale Mail | 100 food, 50 gold | +1 armor to existing and future units, including Scouts. Buildings have no armor upgrade. |
| Wheelbarrow | 175 food, 50 wood | +25% gathering amount per gather tick for existing and future Villagers. Carry capacity and walking speed are unchanged, so delivered resources per minute do not rise by exactly 25% on every route. |
| Loom | 50 gold | +15 maximum and current HP for existing living Villagers; future Villagers spawn with 40 HP. Other units are unchanged. |

Forge and Mail are read dynamically by Combat, leaving unit base fields unchanged. Loom and Wheelbarrow use Main's research-completed signal for existing Villagers and stored player bonuses when new Villagers spawn. Both players use the same payment and eligibility transaction; duplicate purchases cannot stack.

## Exact stats

The upgraded columns assume the relevant single Blacksmith purchase. Ages alone do not change any entry.

| Unit | HP | Attack → Forge | Armor → Mail | Attack interval |
| --- | ---: | ---: | ---: | ---: |
| Villager | 25 → 40 with Loom | 3 → 5 | 0 → 1 | 1.00 s |
| Warrior | 60 | 8 → 10 | 2 → 3 | 1.10 s |
| Archer | 35 | 7 → 9 | 0 → 1 | 1.10 s |
| Horseman | 80 | 10 → 12 | 1 → 2 | 1.05 s |
| Scout | 45 | 0 → 0 | 0 → 1 | Unarmed |
| Siege Engine | 100 | 30 → 32 | 3 → 4 | 1.00 s |

Unit impact damage is `max(1, (base attack + Forge) × counter − (base armor + Mail))`. Warrior versus Horseman and Archer versus Warrior receive ×2; Horseman versus Archer receives ×1.5. The counter multiplies the weapon bonus too. These are per-impact values; pursuit, range, windup, projectile travel, targets and attack intervals determine observed battle output.

| Attacker → defender | Neither upgrade | Attacker Forge | Defender Mail | Both |
| --- | ---: | ---: | ---: | ---: |
| Warrior → Warrior | 6 | 8 | 5 | 7 |
| Warrior → Horseman | 15 | 19 | 14 | 18 |
| Archer → Warrior | 12 | 16 | 11 | 15 |
| Horseman → Archer | 15 | 18 | 14 | 17 |
| Horseman → Warrior | 8 | 10 | 7 | 9 |
| Warrior → Archer | 8 | 10 | 7 | 9 |
| Archer → Horseman | 6 | 8 | 5 | 7 |
| Siege Engine → Warrior | 28 | 30 | 27 | 29 |

For example, Forge makes a Horseman kill a full-health, unupgraded 35-HP Archer in two impacts instead of three. Giving that Archer Mail restores three impacts. Archer versus Warrior improves from five impacts to four with Forge, including when the Warrior has Mail. These are exact HP breakpoints, not predictions of whole-army outcomes.

Buildings have no armor. Unit attacks use rounded `(attack + Forge) × building multiplier`; only Siege has the ×3 multiplier, giving 90 → 96 damage per building hit. A Town Center or Watch Tower has 6 attack independent of Forge; target unit armor still applies. Their intervals are 2.0 s and 1.5 s respectively. A Tower hit against a Warrior is 4 HP without Mail and 3 HP with it. Forge and Mail do not change building HP or defenses.

Arrows and committed melee hits calculate final damage when released. Research completed during projectile flight affects subsequent releases, not an already released arrow. The minimum of 1 applies to valid armed attacks after armor; it does not authorize Scouts to attack.

## Findings and bounded changes

The attack getter previously added Forge to the Scout's zero attack, although Scout command and automatic acquisition paths correctly rejected all attacks. This created a misleading Attack 2 selection value, not a functioning combat upgrade. The scoped correction keeps zero-attack units at zero in the live getter.

Recruit Info previously read only base UnitData, hiding Forge, Mail and Loom. A shared `Combat.get_effective_unit_type_stats(unit_type, player_id)` preview supplies the same owner bonuses for future units. The HUD pass uses this preview and states that ages unlock options, while technology descriptions explain who benefits and that purchases complete immediately.

No numerical balance change is justified by these discrepancies. Counters and armor match the stated equations. A strategic assessment of age price versus early Blacksmith purchases would need matched paid openings with repeated seeds and army mixes; neither arithmetic nor the synthetic tactical fixture establishes that balance.

## Validation record

After the native performance session released the engine slot, the new `tools/test_combat_progression_matrix.tscn` baseline completed with twelve distinct failures, all for Scout effective attack after Forge: both owners, ages 1–3, with Forge alone or Forge plus Mail. The 11,520 armed-attacker/defender damage cells passed. `output/polish-combat-stats-2026-10-22/baseline.log` and `matrix-before.json` preserve that result and its source hashes.

After the scoped getter/preview correction, the expanded matrix passed **22,007 checks across 48 paid progression states and 11,520 damage cells**, with no script errors or warnings. `matrix.log` and `matrix.json` in the same directory contain the final result, source hashes and representative exact impacts. The checks cover:

- Ages 1–3 and independent Forge/Mail states for both owners, existing and newly instantiated units, exact research payment and duplicate rejection.
- All five armed attacker roles against all six defender roles, including counters, armor and the minimum-damage floor; actual unit, building, Tower and Town Center HP dispatch verifies mitigation happens once.
- Shared recruit previews against live existing/new units, combined Loom/Forge/Mail preview, owner isolation and immutable nested UnitData.
- Scout attack-order rejection and zero effective attack despite Forge.
- Arrow and committed melee damage captured at release, followed by a new impact using research completed afterward.

The existing `test_combat_damage.tscn` and `test_shared_technology_rules.gd` also passed without script errors or warnings. The latter uses actual Main wiring and paid Blacksmith construction by real workers, checks ownership/affordability/duplicates/interrupted purchases, verifies existing Villager effects and trains a paid replacement through the production queue. It measured gather amount 1.25 and HP 40 for both the upgraded worker and replacement, attack bonus 2, armor bonus 1, and exact Castle payment 600 food/300 gold at a 30-population limit for both owners.

Reproduce with `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/test_combat_progression_matrix.tscn`; the real-match technology check uses `--script res://tools/test_shared_technology_rules.gd`. These deterministic tests establish numerical behavior. They do not establish win rates, upgrade purchase priority, rendered readability or performance. Native upgrade-info observation is owned by the parallel HUD pass.
