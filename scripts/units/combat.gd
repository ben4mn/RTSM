class_name Combat
extends RefCounted
## Handles damage calculation, counter bonuses, and combat resolution.

# Counter bonus table: attacker_type -> target_type -> bonus multiplier
# Infantry +50% vs Cavalry
# Archer +50% vs Infantry
# Cavalry +50% vs Archers
# Siege +300% vs Buildings (handled via bonus_vs_buildings stat)
const COUNTER_BONUSES: Dictionary = {
	UnitData.UnitType.INFANTRY: { UnitData.UnitType.CAVALRY: 1.5 },
	UnitData.UnitType.ARCHER: { UnitData.UnitType.INFANTRY: 1.5 },
	UnitData.UnitType.CAVALRY: { UnitData.UnitType.ARCHER: 1.5 },
}


static func get_counter_bonus(attacker_type: int, defender_type: int) -> float:
	if COUNTER_BONUSES.has(attacker_type):
		var bonuses: Dictionary = COUNTER_BONUSES[attacker_type]
		if bonuses.has(defender_type):
			return bonuses[defender_type]
	return 1.0


static func calculate_damage(attacker: UnitBase, defender: UnitBase) -> float:
	var base_damage: float = attacker.damage
	var bonus: float = get_counter_bonus(attacker.unit_type, defender.unit_type)
	return base_damage * bonus


static func deal_damage(attacker: UnitBase, defender: UnitBase) -> void:
	var final_damage: float = calculate_damage(attacker, defender)
	defender.take_damage(final_damage)

	# Hit particles at impact
	var tree := attacker.get_tree()
	if tree and tree.current_scene:
		VFX.hit_burst(tree, defender.global_position)

	# If the defender isn't already attacking something, make it fight back
	if defender.current_state != UnitBase.State.DEAD and defender.attack_target == null:
		if defender.damage > 0.0:
			defender.command_attack(attacker)
