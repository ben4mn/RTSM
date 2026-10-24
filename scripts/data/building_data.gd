class_name BuildingData
extends RefCounted

## Static data definitions for all building types in AOEM.
## `attack_range` values are range tiles and use MapData's shared conversion.

enum BuildingType {
	TOWN_CENTER,
	HOUSE,
	BARRACKS,
	ARCHERY_RANGE,
	STABLE,
	FARM,
	RESOURCE_CAMP = 6,
	SIEGE_WORKSHOP = 8,
	BLACKSMITH = 9,
	WATCH_TOWER = 10,
}

## Keep a walkable tile between owned foundations, including their corners.
const BUILDING_CLEARANCE_TILES: int = 1

# Cost format: { "food": int, "wood": int, "gold": int }
# footprint: tile size in isometric grid (width x height)

const BUILDINGS: Dictionary = {
	BuildingType.TOWN_CENTER: {
		"name": "Town Center",
		"hp": 5000,
		"cost": { "food": 0, "wood": 400, "gold": 0 },
		"build_time": 60.0,
		"pop_provided": 10,
		"footprint": Vector2i(4, 4),
		"can_train": [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT],
		"age_required": 3,  # Extra TCs available in Castle Age
		"drop_off": ["food", "wood", "gold"],
		# One short-range arrow buys retreat time; it does not shelter workers
		# across the whole resource pocket or replace a defending army.
		"attack_damage": 6,
		"attack_range": 8,
		"attack_interval": 2.0,
		"attack_projectile_speed": 300.0,
		"attack_buildings": false,
		# Guaranteed spawn resources are placed up to nine Chebyshev tiles
		# away. A 13-tile reveal covers that full starting pocket without
		# exposing the central objective roughly nineteen tiles away.
		"vision_radius": 13,
		"color": Color(0.85, 0.75, 0.35),
	},
	BuildingType.HOUSE: {
		"name": "House",
		"hp": 500,
		"cost": { "food": 0, "wood": 50, "gold": 0 },
		"build_time": 10.0,
		"pop_provided": 10,
		"footprint": Vector2i(2, 2),
		"can_train": [],
		"age_required": 0,
		"drop_off": [],
		"color": Color(0.6, 0.45, 0.3),
	},
	BuildingType.BARRACKS: {
		"name": "Barracks",
		"hp": 1500,
		"cost": { "food": 0, "wood": 120, "gold": 0 },
		"build_time": 20.0,
		"pop_provided": 0,
		"footprint": Vector2i(3, 3),
		"can_train": [UnitData.UnitType.INFANTRY],
		"age_required": 1,
		"drop_off": [],
		"color": Color(0.65, 0.3, 0.3),
	},
	BuildingType.ARCHERY_RANGE: {
		"name": "Archery Range",
		"hp": 1200,
		"cost": { "food": 0, "wood": 120, "gold": 0 },
		"build_time": 20.0,
		"pop_provided": 0,
		"footprint": Vector2i(3, 3),
		"can_train": [UnitData.UnitType.ARCHER],
		"age_required": 2,
		"drop_off": [],
		"color": Color(0.3, 0.55, 0.3),
	},
	BuildingType.STABLE: {
		"name": "Stable",
		"hp": 1200,
		"cost": { "food": 0, "wood": 120, "gold": 0 },
		"build_time": 20.0,
		"pop_provided": 0,
		"footprint": Vector2i(3, 3),
		"can_train": [UnitData.UnitType.CAVALRY],
		"age_required": 2,
		"drop_off": [],
		"color": Color(0.5, 0.4, 0.25),
	},
	BuildingType.FARM: {
		"name": "Farm",
		"hp": 300,
		"cost": { "food": 0, "wood": 75, "gold": 0 },
		"build_time": 10.0,
		"pop_provided": 0,
		"footprint": Vector2i(2, 2),
		"can_train": [],
		"age_required": 0,
		"drop_off": [],
		"provides_food": true,
		"color": Color(0.75, 0.7, 0.3),
	},
	BuildingType.RESOURCE_CAMP: {
		"name": "Resource Camp",
		"hp": 600,
		"cost": { "food": 0, "wood": 80, "gold": 0 },
		"build_time": 10.0,
		"pop_provided": 0,
		"footprint": Vector2i(2, 2),
		"can_train": [],
		"age_required": 0,
		"drop_off": ["food", "wood", "gold"],
		"color": Color(0.65, 0.53, 0.33),
	},
	BuildingType.SIEGE_WORKSHOP: {
		"name": "Siege Workshop",
		"hp": 1500,
		"cost": { "food": 0, "wood": 300, "gold": 100 },
		"build_time": 28.0,
		"pop_provided": 0,
		"footprint": Vector2i(3, 3),
		"can_train": [UnitData.UnitType.SIEGE],
		"age_required": 3,
		"drop_off": [],
		"color": Color(0.4, 0.4, 0.45),
	},
	BuildingType.BLACKSMITH: {
		"name": "Blacksmith",
		"hp": 1200,
		"cost": { "food": 0, "wood": 120, "gold": 0 },
		"build_time": 18.0,
		"pop_provided": 0,
		"footprint": Vector2i(2, 2),
		"can_train": [],
		"age_required": 1,
		"drop_off": [],
		"color": Color(0.45, 0.35, 0.35),
		"has_research": true,
	},
	BuildingType.WATCH_TOWER: {
		"name": "Watch Tower",
		"hp": 800,
		"cost": { "food": 0, "wood": 100, "gold": 25 },
		"build_time": 20.0,
		"pop_provided": 0,
		"footprint": Vector2i(1, 1),
		"can_train": [],
		"age_required": 2,
		"drop_off": [],
		"color": Color(0.55, 0.45, 0.35),
		"attack_damage": 6,
		"attack_range": 6,
		"attack_interval": 1.5,
		"vision_radius": 8,
	},
}


static func get_building_stats(building_type: int, player_id: int = -1) -> Dictionary:
	if BUILDINGS.has(building_type):
		var stats: Dictionary = BUILDINGS[building_type].duplicate(true)
		stats["cost"] = get_building_cost(building_type)
		stats["hp"] = roundi(float(stats["hp"]) * CivilizationData.get_building_hp_multiplier(CivilizationData.for_player(player_id)))
		return stats
	return {}


static func get_building_cost(building_type: int) -> Dictionary:
	if BUILDINGS.has(building_type):
		var cost: Dictionary = BUILDINGS[building_type]["cost"].duplicate()
		# SceneTree --script fixtures can compile data before autoload symbols exist.
		# Resolve the live singleton at call time so its latched match mode still owns costs.
		var match_mode: int = SkirmishData.MatchMode.STANDARD
		var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
		if scene_tree != null and scene_tree.root != null:
			var game_manager: Node = scene_tree.root.get_node_or_null("GameManager")
			if game_manager != null and game_manager.has_method("get_match_mode"):
				match_mode = int(game_manager.call("get_match_mode"))
		if match_mode != SkirmishData.MatchMode.STANDARD and building_type in [BuildingType.BARRACKS, BuildingType.ARCHERY_RANGE, BuildingType.STABLE]:
			cost["wood"] = 100
		return cost
	return { "food": 0, "wood": 0, "gold": 0 }


static func get_building_name(building_type: int) -> String:
	if BUILDINGS.has(building_type):
		return BUILDINGS[building_type]["name"]
	return "Unknown"


static func can_train_units(building_type: int) -> bool:
	if BUILDINGS.has(building_type):
		return BUILDINGS[building_type]["can_train"].size() > 0
	return false


static func is_drop_off_for(building_type: int, resource: String) -> bool:
	if BUILDINGS.has(building_type):
		return resource in BUILDINGS[building_type]["drop_off"]
	return false


static func get_buildings_for_age(age: int) -> Array:
	var result: Array = []
	for key in BUILDINGS:
		if BUILDINGS[key]["age_required"] <= age:
			result.append(key)
	return result
