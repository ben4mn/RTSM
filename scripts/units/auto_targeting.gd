class_name UnitAutoTargeting
extends RefCounted
## Current-vision acquisition shared by idle, patrol and attack-move orders.
## Explicit target orders keep their authority in UnitBase.


static func find_target(attacker: UnitBase, unit_radius: float, building_radius: float, buildings_first: bool) -> Node2D:
	if buildings_first:
		var building: BuildingBase = _nearest_building(attacker, building_radius)
		if building != null:
			return building
	var unit: UnitBase = _nearest_unit(attacker, unit_radius)
	if unit != null:
		return unit
	if not buildings_first:
		return _nearest_building(attacker, building_radius)
	return null


static func _nearest_unit(attacker: UnitBase, radius: float) -> UnitBase:
	var nearest: UnitBase = null
	var nearest_distance: float = radius
	var best_priority: int = -1
	for candidate: Node in attacker.get_nearby_units(radius):
		if not is_instance_valid(candidate) or not candidate is UnitBase or candidate == attacker:
			continue
		var unit: UnitBase = candidate as UnitBase
		if unit.player_owner == attacker.player_owner:
			continue
		var distance: float = attacker.global_position.distance_to(unit.global_position)
		if distance > radius:
			continue
		# Most opponents are elsewhere on the map. Reject them before the live
		# fog query, which may inspect every vision source for this player.
		if not attacker._is_valid_target(unit) or attacker._is_auto_target_temporarily_ignored(unit):
			continue
		var priority: int = _unit_priority(attacker, unit)
		if priority > best_priority or (priority == best_priority and distance < nearest_distance):
			best_priority = priority
			nearest_distance = distance
			nearest = unit
	return nearest


static func find_nearby_threat(attacker: UnitBase, radius: float) -> UnitBase:
	var target := _nearest_unit(attacker, radius)
	return target if target != null and _unit_priority(attacker, target) >= 2 else null


static func _unit_priority(attacker: UnitBase, target: UnitBase) -> int:
	if is_instance_valid(target.attack_target) and target.attack_target.player_owner == attacker.player_owner:
		return 3
	if is_instance_valid(target.attack_building_target) and target.attack_building_target.player_owner == attacker.player_owner:
		return 3
	if target.damage > 0.0 and target.unit_type != UnitData.UnitType.VILLAGER:
		return 2
	return 1


static func _nearest_building(attacker: UnitBase, radius: float) -> BuildingBase:
	var nearest: BuildingBase = null
	var nearest_distance: float = radius
	for candidate: Node in attacker.get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(candidate) or not candidate is BuildingBase:
			continue
		var building: BuildingBase = candidate as BuildingBase
		if building.player_owner == attacker.player_owner:
			continue
		var distance: float = attacker._get_building_attack_distance(building)
		if distance < nearest_distance:
			if not attacker._is_valid_building_target(building) or attacker._is_auto_target_temporarily_ignored(building):
				continue
			nearest_distance = distance
			nearest = building
	return nearest
