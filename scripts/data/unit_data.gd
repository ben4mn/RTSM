class_name UnitData
extends RefCounted
## Static data definitions for all unit types in AOEM.

enum UnitType {
	VILLAGER,
	INFANTRY,
	ARCHER,
	CAVALRY,
	SCOUT,
	SIEGE,
	TRADER
}

# World presentation is independent of recruitment portraits and combat stats.
# At the shared y104 foot anchor, infantry stands about 28–30 world pixels
# tall; mounted roles read taller and wider, and siege keeps its carriage size.
const WORLD_SPRITE_SCALES: Dictionary = {
	UnitType.VILLAGER: Vector2(0.30, 0.30),
	UnitType.INFANTRY: Vector2(0.31, 0.31),
	UnitType.ARCHER: Vector2(0.30, 0.30),
	UnitType.CAVALRY: Vector2(0.45, 0.45),
	UnitType.SCOUT: Vector2(0.43, 0.43),
	UnitType.SIEGE: Vector2(0.60, 0.60),
	UnitType.TRADER: Vector2(0.38, 0.38),
}

# Two-population workers deliver ~109 food/wood per minute at a 120-unit haul.
# Three opening workers support food, timber and gold without changing per-worker rates.
# Shared carry slots preserve mixed cargo on retask; no harvest is discarded.
const STARTING_VILLAGERS: int = 3
const VILLAGER_BUILD_SPEED: float = 2.0
const VILLAGER_GATHER_AMOUNT: float = 1.8
const WHEELBARROW_GATHER_BONUS: float = VILLAGER_GATHER_AMOUNT * 0.25
const VILLAGER_CARRY_CAPACITY: int = 30
const VILLAGER_GATHER_TICK_SECONDS: float = 0.9
const RESOURCE_GATHER_SPEEDS: Dictionary = {"food": 1.2, "wood": 1.2, "gold": 1.0}

# Cost format: { "food": int, "wood": int, "gold": int }
# These base stats apply at every age; ages unlock options, not stat scaling.
# Blacksmith research adds owner bonuses through Combat and Main.
# `attack_range` and `vision_radius` are range tiles, converted through
# MapData.range_tiles_to_world() when a unit enters the world.

const UNITS: Dictionary = {
	UnitType.VILLAGER: {
		"name": "Villager",
		"hp": 50,
		"damage": 6,
		"armor": 0,
		"speed": 60.0,
		"cost": { "food": 60, "wood": 0, "gold": 0 },
		"build_time": 20.0,
		"vision_radius": 4,
		"attack_range": 1,
		"pop_cost": 2,
		"can_gather": true,
		"can_build": true,
	},
	UnitType.INFANTRY: {
		"name": "Warrior",
		"role": "Spear infantry",
		"counter_name": "Horsemen",
		"hp": 120,
		"damage": 16,
		"armor": 4,
		"speed": 55.0,
		"cost": { "food": 70, "wood": 30, "gold": 0 },
		"build_time": 18.0,
		"attack_interval": 1.1,
		"attack_windup": 0.16,
		"vision_radius": 4,
		"attack_range": 1,
		"pop_cost": 2,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.ARCHER: {
		"name": "Archer",
		"role": "Ranged infantry",
		"counter_name": "Warriors",
		"hp": 70,
		"damage": 14,
		"armor": 0,
		"speed": 55.0,
		"cost": { "food": 40, "wood": 55, "gold": 20 },
		"build_time": 24.0,
		"attack_interval": 1.1,
		"attack_windup": 0.18,
		"projectile_speed": 300.0,
		"vision_radius": 6,
		"attack_range": 5,
		"pop_cost": 2,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.CAVALRY: {
		"name": "Horseman",
		"role": "Fast cavalry",
		"counter_name": "Archers",
		"hp": 160,
		"damage": 20,
		"armor": 2,
		"speed": 95.0,
		"cost": { "food": 130, "wood": 20, "gold": 40 },
		"build_time": 28.0,
		"attack_interval": 1.05,
		"attack_windup": 0.14,
		"vision_radius": 5,
		"attack_range": 1,
		"pop_cost": 2,
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
		"vision_radius": 10,
		"attack_range": 1,
		"pop_cost": 1,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.TRADER: {
		"name": "Trader", "role": "Renewable gold", "hp": 65, "damage": 0,
		"armor": 0, "speed": 70.0, "cost": {"food": 0, "wood": 60, "gold": 40},
		"build_time": 22.0, "vision_radius": 4, "attack_range": 0, "pop_cost": 2,
		"can_gather": false, "can_build": false,
	},

	UnitType.SIEGE: {
		"name": "Siege Engine",
		"role": "Siege artillery",
		"counter_name": "Buildings",
		"auto_target_buildings_first": true,
		"hp": 100,
		"damage": 30,
		"armor": 3,
		"speed": 30.0,
		"cost": { "food": 0, "wood": 150, "gold": 100 },
		"build_time": 25.0,
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
	UnitType.VILLAGER: "res://assets/units/worker.svg",
	UnitType.INFANTRY: "res://assets/units/warrior.svg",
	UnitType.ARCHER: "res://assets/units/archer.svg",
	UnitType.CAVALRY: "res://assets/units/cavalry.svg",
	UnitType.SCOUT: "res://assets/units/scout.svg",
	UnitType.SIEGE: "res://assets/units/siege.svg",
	UnitType.TRADER: "res://assets/units/trader.svg",
}


static func get_unit_stats(unit_type: int, player_id: int = -1) -> Dictionary:
	if UNITS.has(unit_type):
		return CivilizationData.get_unit_stats(UNITS[unit_type], unit_type, CivilizationData.for_player(player_id))
	return {}


static func get_unit_cost(unit_type: int) -> Dictionary:
	if UNITS.has(unit_type):
		return UNITS[unit_type]["cost"].duplicate()
	return { "food": 0, "wood": 0, "gold": 0 }


static func get_unit_name(unit_type: int, player_id: int = -1) -> String:
	if UNITS.has(unit_type):
		return str(get_unit_stats(unit_type, player_id)["name"])
	return "Unknown"


static func get_unit_icon_path(unit_type: int, player_id: int = -1) -> String:
	var miniature_path: String = KingdomArt.unit_path(CivilizationData.for_player(player_id), unit_type)
	if not miniature_path.is_empty():
		return miniature_path
	var signature_path: String = str(get_unit_stats(unit_type, player_id).get("civilization_icon", ""))
	if not signature_path.is_empty() and ResourceLoader.exists(signature_path):
		return signature_path
	if UNIT_ICONS.has(unit_type):
		return UNIT_ICONS[unit_type]
	return ""


static func get_unit_role_description(unit_type: int, player_id: int = -1) -> String:
	return str(get_unit_stats(unit_type, player_id).get("role", ""))


static func get_unit_counter_name(unit_type: int, player_id: int = -1) -> String:
	if player_id in [0, 1]:
		var target_type: int = -1
		match unit_type:
			UnitType.INFANTRY: target_type = UnitType.CAVALRY
			UnitType.ARCHER: target_type = UnitType.INFANTRY
			UnitType.CAVALRY: target_type = UnitType.ARCHER
		if target_type >= 0:
			var target_name: String = get_unit_name(target_type, 1 - player_id)
			return "Horsemen" if target_name == "Horseman" else target_name + "s"
	return str(UNITS.get(unit_type, {}).get("counter_name", ""))


static func get_unit_counter_description(unit_type: int, player_id: int = -1) -> String:
	if unit_type == UnitType.SCOUT:
		return "Unarmed · wide vision"
	var counter_name: String = get_unit_counter_name(unit_type, player_id)
	return "Beats %s" % counter_name if not counter_name.is_empty() else ""


static func get_starting_villager_count() -> int:
	# Only headless comparative probes may override; live games share this default.
	if OS.has_feature("dedicated_server") or not DisplayServer.get_name() == "headless":
		return STARTING_VILLAGERS
	return clampi(int(Engine.get_meta("balance_starting_villagers", STARTING_VILLAGERS)), 3, 4)
