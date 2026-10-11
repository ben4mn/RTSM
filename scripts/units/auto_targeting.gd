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
	for candidate: Node in attacker.get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(candidate) or not candidate is UnitBase or candidate == attacker:
			continue
		var unit: UnitBase = candidate as UnitBase
		if unit.player_owner == attacker.player_owner:
			continue
		if not attacker._is_valid_target(unit) or attacker._is_auto_target_temporarily_ignored(unit):
			continue
		var distance: float = attacker.global_position.distance_to(unit.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = unit
	return nearest


static func _nearest_building(attacker: UnitBase, radius: float) -> BuildingBase:
	var nearest: BuildingBase = null
	var nearest_distance: float = radius
	for candidate: Node in attacker.get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(candidate) or not candidate is BuildingBase:
			continue
		var building: BuildingBase = candidate as BuildingBase
		if building.player_owner == attacker.player_owner:
			continue
		if not attacker._is_valid_building_target(building) or attacker._is_auto_target_temporarily_ignored(building):
			continue
		var distance: float = attacker.global_position.distance_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest
