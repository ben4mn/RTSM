class_name Combat
extends RefCounted
## Canonical damage calculation and combat resolution.
##
## Contract:
## - Unit `damage` and `armor` fields are base stats. Player upgrades are read
##   dynamically here, so existing and newly trained units receive them once.
## - Every function named `calculate_*_damage` returns final HP loss after all
##   relevant multipliers and armor. `take_damage()` never mitigates it again.
## - Buildings currently have no armor. Towers use their data-defined attack,
##   do not inherit unit weapon upgrades, and subtract a unit's effective armor.

# Counter bonus table: attacker_type -> target_type -> bonus multiplier
# Warriors +100% vs Horsemen
# Archers +100% vs Warriors
# Horsemen +50% vs Archers
# Siege +300% vs Buildings (handled via bonus_vs_buildings stat)
const COUNTER_BONUSES: Dictionary = UnitData.COUNTER_BONUSES


class CommittedMeleeHit extends Node:
	var attacker_ref: WeakRef
	var defender_ref: WeakRef
	var final_damage: float = 0.0
	var counter_bonus: float = 1.0
	var finished: bool = false

	func _ready() -> void:
		# All units release their attacks before coincident hits resolve. A
		# committed blow still lands if its attacker dies in that same frame.
		call_deferred("advance_committed_hit")

	func advance_committed_hit() -> void:
		if finished:
			return
		finished = true
		Combat.resolve_unit_hit(attacker_ref.get_ref() as UnitBase, defender_ref.get_ref() as UnitBase, final_damage, counter_bonus)
		queue_free()


class RangedProjectile extends Node2D:
	var attacker_ref: WeakRef
	var defender_ref: WeakRef
	var visibility_map_ref: WeakRef
	var final_damage: float = 0.0
	var counter_bonus: float = 1.0
	var start_position: Vector2
	var elapsed: float = 0.0
	var flight_seconds: float = 0.2
	var finished: bool = false
	var _heading: Vector2 = Vector2.RIGHT

	func _process(delta: float) -> void:
		advance_projectile(delta)

	func advance_projectile(delta: float) -> void:
		if finished:
			return
		var defender: UnitBase = defender_ref.get_ref() as UnitBase
		if not is_instance_valid(defender) or defender.current_state == UnitBase.State.DEAD:
			finished = true
			queue_free()
			return
		elapsed += delta
		var phase: float = minf(1.0, elapsed / flight_seconds)
		var previous: Vector2 = global_position
		global_position = start_position.lerp(defender.global_position + Vector2(0.0, -16.0), phase)
		global_position.y -= sin(phase * PI) * 12.0
		_heading = (global_position - previous).normalized()
		# A shot already released remains valid, but its rendering must not
		# reveal a target that subsequently enters unexplored fog.
		var visibility_map: Node2D = visibility_map_ref.get_ref() as Node2D if visibility_map_ref != null else null
		if is_instance_valid(visibility_map) and visibility_map.has_method("is_entity_visible_to_player"):
			visible = bool(visibility_map.call("is_entity_visible_to_player", self, 0))
		else:
			visible = defender.visible
		queue_redraw()
		if phase >= 1.0:
			finished = true
			var attacker: UnitBase = attacker_ref.get_ref() as UnitBase
			Combat.resolve_unit_hit(attacker, defender, final_damage, counter_bonus)
			queue_free()

	func _draw() -> void:
		draw_line(-_heading * 7.0, _heading * 3.0, Color(0.88, 0.78, 0.46), 2.0, true)
		var normal := Vector2(-_heading.y, _heading.x)
		draw_colored_polygon(PackedVector2Array([
			_heading * 5.0, normal * 2.0, -normal * 2.0
		]), Color(0.92, 0.94, 0.80))


static func get_counter_bonus(attacker_type: int, defender_type: int) -> float:
	if COUNTER_BONUSES.has(attacker_type):
		var bonuses: Dictionary = COUNTER_BONUSES[attacker_type]
		if bonuses.has(defender_type):
			return bonuses[defender_type]
	return 1.0


static func get_effective_attack(unit: UnitBase) -> float:
	var result: float = unit.damage
	var gm: Node = unit.get_node_or_null("/root/GameManager")
	if gm != null:
		result += float(gm.get_attack_bonus(unit.player_owner))
	return result


static func get_effective_armor(unit: UnitBase) -> float:
	var result: float = unit.armor
	var gm: Node = unit.get_node_or_null("/root/GameManager")
	if gm != null:
		result += float(gm.get_armor_bonus(unit.player_owner))
	return result


static func calculate_unit_damage(attacker: UnitBase, defender: UnitBase) -> float:
	var counter_multiplier: float = get_counter_bonus(attacker.unit_type, defender.unit_type)
	return maxf(
		1.0,
		get_effective_attack(attacker) * counter_multiplier - get_effective_armor(defender)
	)


static func calculate_damage(attacker: UnitBase, defender: UnitBase) -> float:
	## Compatibility alias for callers that predate the explicit target name.
	return calculate_unit_damage(attacker, defender)


static func get_building_damage_multiplier(attacker: UnitBase) -> float:
	var stats: Dictionary = UnitData.get_unit_stats(attacker.unit_type)
	return float(stats.get("bonus_vs_buildings", 1.0))


static func calculate_building_damage(attacker: UnitBase) -> int:
	var raw_damage: float = get_effective_attack(attacker) * get_building_damage_multiplier(attacker)
	return maxi(1, roundi(raw_damage))


static func calculate_tower_damage(attacker: BuildingBase, defender: UnitBase) -> float:
	## Tower damage follows the same post-mitigation contract as unit damage,
	## but tower weapons do not receive the player unit-attack upgrade.
	return maxf(1.0, float(attacker.tower_attack_damage) - get_effective_armor(defender))


static func calculate_tower_building_damage(attacker: BuildingBase) -> int:
	## Buildings have no armor in the current ruleset.
	return maxi(1, attacker.tower_attack_damage)


static func deal_damage(attacker: UnitBase, defender: UnitBase) -> void:
	var final_damage: float = calculate_unit_damage(attacker, defender)
	resolve_unit_hit(attacker, defender, final_damage, get_counter_bonus(attacker.unit_type, defender.unit_type))


static func queue_melee_attack(attacker: UnitBase, defender: UnitBase) -> void:
	var hit := CommittedMeleeHit.new()
	hit.attacker_ref = weakref(attacker)
	hit.defender_ref = weakref(defender)
	hit.final_damage = calculate_unit_damage(attacker, defender)
	hit.counter_bonus = get_counter_bonus(attacker.unit_type, defender.unit_type)
	attacker.get_parent().add_child(hit)


static func launch_ranged_attack(attacker: UnitBase, defender: UnitBase) -> void:
	## Calculate at release; apply HP loss only when the visible arrow arrives.
	var projectile := RangedProjectile.new()
	projectile.attacker_ref = weakref(attacker)
	projectile.defender_ref = weakref(defender)
	var visibility_map: Node2D = attacker.call("_get_navigation_map") as Node2D
	if visibility_map != null:
		projectile.visibility_map_ref = weakref(visibility_map)
	projectile.final_damage = calculate_unit_damage(attacker, defender)
	projectile.counter_bonus = get_counter_bonus(attacker.unit_type, defender.unit_type)
	var shot_direction: Vector2 = (defender.global_position - attacker.global_position).normalized()
	projectile.start_position = attacker.global_position + shot_direction * 14.0 + Vector2(0.0, -18.0)
	var projectile_speed: float = float(UnitData.UNITS[attacker.unit_type].get("projectile_speed", 300.0))
	projectile.flight_seconds = clampf(attacker.global_position.distance_to(defender.global_position) / projectile_speed, 0.10, 0.40)
	projectile.z_index = 80
	attacker.get_parent().add_child(projectile)
	projectile.global_position = projectile.start_position
	projectile.visible = attacker.visible


static func resolve_unit_hit(attacker: UnitBase, defender: UnitBase, final_damage: float, counter_bonus: float) -> void:
	if not is_instance_valid(defender) or defender.current_state == UnitBase.State.DEAD:
		return
	var was_alive: bool = defender.hp > 0.0
	var previous_hp: float = defender.hp
	defender.take_damage(final_damage)
	if is_instance_valid(attacker):
		attacker.attack_landed.emit(attacker, defender, maxf(0.0, previous_hp - maxf(0.0, defender.hp)), counter_bonus)

	var tree := defender.get_tree()
	if tree and tree.current_scene and defender.visible:
		VFX.hit_burst(tree, defender.global_position + Vector2(0.0, -14.0))
		# Show counter bonus text when type advantage applies
		if counter_bonus > 1.0:
			VFX.counter_bonus_float(tree, defender.global_position, "x%.1f!" % counter_bonus)

	# Track kill
	if is_instance_valid(attacker) and was_alive and defender.hp <= 0.0:
		attacker.kills += 1

	# If the defender isn't already attacking something, make it fight back
	if (
		is_instance_valid(attacker)
		and attacker.current_state != UnitBase.State.DEAD
		and defender.current_state != UnitBase.State.DEAD
		and defender.attack_target == null
		and defender.can_auto_retaliate()
	):
		defender.command_attack(attacker)


static func deal_damage_to_building(attacker: UnitBase, defender: BuildingBase) -> void:
	defender.take_damage(calculate_building_damage(attacker))


static func deal_tower_damage(attacker: BuildingBase, defender: UnitBase) -> void:
	defender.take_damage(calculate_tower_damage(attacker, defender))


static func deal_tower_damage_to_building(attacker: BuildingBase, defender: BuildingBase) -> void:
	defender.take_damage(calculate_tower_building_damage(attacker))
