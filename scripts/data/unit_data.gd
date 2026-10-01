class_name UnitData
extends RefCounted
## Static data definitions for all unit types in AOEM.

enum UnitType {
	VILLAGER,
	INFANTRY,
	ARCHER,
	CAVALRY,
	SCOUT,
	SIEGE
}

# Cost format: { "food": int, "wood": int, "gold": int }
# All units defined with base stats for Age 1. Upgrades scale from here.
# `attack_range` and `vision_radius` are range tiles, converted through
# MapData.range_tiles_to_world() when a unit enters the world.

const UNITS: Dictionary = {
	UnitType.VILLAGER: {
		"name": "Villager",
		"hp": 25,
		"damage": 3,
		"armor": 0,
		"speed": 60.0,
		"cost": { "food": 50, "wood": 0, "gold": 0 },
		"build_time": 16.0,
		"vision_radius": 4,
		"attack_range": 1,
		"pop_cost": 1,
		"can_gather": true,
		"can_build": true,
	},
	UnitType.INFANTRY: {
		"name": "Warrior",
		"role": "Spear infantry",
		"counter_name": "Horsemen",
		"hp": 60,
		"damage": 8,
		"armor": 2,
		"speed": 55.0,
		"cost": { "food": 50, "wood": 20, "gold": 0 },
		"build_time": 12.0,
		"attack_interval": 1.1,
		"attack_windup": 0.16,
		"vision_radius": 4,
		"attack_range": 1,
		"pop_cost": 1,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.ARCHER: {
		"name": "Archer",
		"role": "Ranged infantry",
		"counter_name": "Warriors",
		"hp": 35,
		"damage": 7,
		"armor": 0,
		"speed": 55.0,
		"cost": { "food": 25, "wood": 45, "gold": 0 },
		"build_time": 16.0,
		"attack_interval": 1.1,
		"attack_windup": 0.18,
		"projectile_speed": 300.0,
		"vision_radius": 6,
		"attack_range": 5,
		"pop_cost": 1,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.CAVALRY: {
		"name": "Horseman",
		"role": "Fast cavalry",
		"counter_name": "Archers",
		"hp": 80,
		"damage": 10,
		"armor": 1,
		"speed": 95.0,
		"cost": { "food": 90, "wood": 30, "gold": 0 },
		"build_time": 18.0,
		"attack_interval": 1.05,
		"attack_windup": 0.14,
		"vision_radius": 5,
		"attack_range": 1,
		"pop_cost": 1,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.SCOUT: {
		"name": "Scout",
		"role": "Reconnaissance",
		"hp": 45,
		"damage": 0,
		"armor": 0,
		"speed": 100.0,
		"cost": { "food": 40, "wood": 0, "gold": 10 },
		"build_time": 8.0,
		"vision_radius": 8,
		"attack_range": 1,
		"pop_cost": 1,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.SIEGE: {
		"name": "Siege Engine",
		"hp": 100,
		"damage": 30,
		"armor": 3,
		"speed": 30.0,
		"cost": { "food": 0, "wood": 150, "gold": 100 },
		"build_time": 35.0,
		"vision_radius": 3,
		"attack_range": 7,
		"pop_cost": 3,
		"can_gather": false,
		"can_build": false,
		"bonus_vs_buildings": 3.0,
	},
}

# Compact battles use spear infantry rather than a generic heavy swordsman.
# These are our small-army multipliers, inspired by the AoE counter roles.
const COUNTER_BONUSES: Dictionary = {
	UnitType.INFANTRY: { UnitType.CAVALRY: 2.0 },
	UnitType.ARCHER: { UnitType.INFANTRY: 2.0 },
	UnitType.CAVALRY: { UnitType.ARCHER: 1.5 },
}

const UNIT_ICONS: Dictionary = {
	UnitType.VILLAGER: "res://assets/units/unit_01.png",
	UnitType.INFANTRY: "res://assets/units/warrior.svg",
	UnitType.ARCHER: "res://assets/units/archer.svg",
	UnitType.CAVALRY: "res://assets/units/cavalry.svg",
	UnitType.SCOUT: "res://assets/units/scout.svg",
	UnitType.SIEGE: "res://assets/units/siege.svg",
}


static func get_unit_stats(unit_type: int) -> Dictionary:
	if UNITS.has(unit_type):
		return UNITS[unit_type].duplicate(true)
	return {}


static func get_unit_cost(unit_type: int) -> Dictionary:
	if UNITS.has(unit_type):
		return UNITS[unit_type]["cost"].duplicate()
	return { "food": 0, "wood": 0, "gold": 0 }


static func get_unit_name(unit_type: int) -> String:
	if UNITS.has(unit_type):
		return UNITS[unit_type]["name"]
	return "Unknown"


static func get_unit_icon_path(unit_type: int) -> String:
	if UNIT_ICONS.has(unit_type):
		return UNIT_ICONS[unit_type]
	return ""


static func get_unit_role_description(unit_type: int) -> String:
	return str(UNITS.get(unit_type, {}).get("role", ""))


static func get_unit_counter_name(unit_type: int) -> String:
	return str(UNITS.get(unit_type, {}).get("counter_name", ""))


static func get_unit_counter_description(unit_type: int) -> String:
	if unit_type == UnitType.SCOUT:
		return "Recon · wide vision"
	var counter_name: String = get_unit_counter_name(unit_type)
	return "Beats %s" % counter_name if not counter_name.is_empty() else ""
