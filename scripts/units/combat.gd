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
	# Apply global attack upgrade
	var gm: Node = attacker.get_node_or_null("/root/GameManager")
	if gm:
		base_damage += gm.get_attack_bonus(attacker.player_owner)
	var bonus: float = get_counter_bonus(attacker.unit_type, defender.unit_type)
	var armor: float = defender.armor
	if gm:
		armor += gm.get_armor_bonus(defender.player_owner)
	return maxf(1.0, base_damage * bonus - armor)


static func deal_damage(attacker: UnitBase, defender: UnitBase) -> void:
	var final_damage: float = calculate_damage(attacker, defender)
	var was_alive: bool = defender.hp > 0.0
	defender.take_damage(final_damage)

	var tree := attacker.get_tree()
	if tree and tree.current_scene:
		# Ranged units show arrow projectile; melee show hit burst
		if attacker.is_ranged:
			VFX.arrow_projectile(tree, attacker.global_position, defender.global_position)
		else:
			VFX.hit_burst(tree, defender.global_position)
		# Show counter bonus text when type advantage applies
		var bonus: float = get_counter_bonus(attacker.unit_type, defender.unit_type)
		if bonus > 1.0:
			VFX.counter_bonus_float(tree, defender.global_position, "x%.1f!" % bonus)

	# Track kill
	if was_alive and defender.hp <= 0.0:
		attacker.kills += 1

	# If the defender isn't already attacking something, make it fight back
	if defender.current_state != UnitBase.State.DEAD and defender.attack_target == null:
		if defender.damage > 0.0:
			defender.command_attack(attacker)
