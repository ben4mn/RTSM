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

const UNITS: Dictionary = {
	UnitType.VILLAGER: {
		"name": "Villager",
		"hp": 25,
		"damage": 3,
		"armor": 0,
		"speed": 60.0,
		"cost": { "food": 50, "wood": 0, "gold": 0 },
		"build_time": 20.0,
		"vision_radius": 4,
		"attack_range": 1,
		"pop_cost": 1,
		"can_gather": true,
		"can_build": true,
	},
	UnitType.INFANTRY: {
		"name": "Infantry",
		"hp": 60,
		"damage": 8,
		"armor": 2,
		"speed": 55.0,
		"cost": { "food": 60, "wood": 0, "gold": 20 },
		"build_time": 15.0,
		"vision_radius": 4,
		"attack_range": 1,
		"pop_cost": 1,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.ARCHER: {
		"name": "Archer",
		"hp": 35,
		"damage": 6,
		"armor": 0,
		"speed": 55.0,
		"cost": { "food": 25, "wood": 45, "gold": 0 },
		"build_time": 18.0,
		"vision_radius": 6,
		"attack_range": 5,
		"pop_cost": 1,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.CAVALRY: {
		"name": "Cavalry",
		"hp": 80,
		"damage": 10,
		"armor": 1,
		"speed": 90.0,
		"cost": { "food": 80, "wood": 0, "gold": 40 },
		"build_time": 22.0,
		"vision_radius": 5,
		"attack_range": 1,
		"pop_cost": 2,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.SCOUT: {
		"name": "Scout",
		"hp": 45,
		"damage": 4,
		"armor": 0,
		"speed": 100.0,
		"cost": { "food": 40, "wood": 0, "gold": 10 },
		"build_time": 12.0,
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
