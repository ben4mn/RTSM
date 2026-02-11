class_name BuildingData
extends RefCounted
## Static data definitions for all building types in AOEM.

enum BuildingType {
	TOWN_CENTER,
	HOUSE,
	BARRACKS,
	ARCHERY_RANGE,
	STABLE,
	FARM,
	LUMBER_CAMP,
	MINING_CAMP,
	SIEGE_WORKSHOP,
}

# Cost format: { "food": int, "wood": int, "gold": int }
# footprint: tile size in isometric grid (width x height)

const BUILDINGS: Dictionary = {
	BuildingType.TOWN_CENTER: {
		"name": "Town Center",
		"hp": 5000,
		"cost": { "food": 0, "wood": 400, "gold": 0 },
		"build_time": 60.0,
		"pop_provided": 5,
		"footprint": Vector2i(4, 4),
		"can_train": [UnitData.UnitType.VILLAGER],
		"age_required": 0,
		"drop_off": ["food", "wood", "gold"],
		"color": Color(0.85, 0.75, 0.35),
	},
	BuildingType.HOUSE: {
		"name": "House",
		"hp": 500,
		"cost": { "food": 0, "wood": 50, "gold": 0 },
		"build_time": 15.0,
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
		"cost": { "food": 0, "wood": 150, "gold": 0 },
		"build_time": 30.0,
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
		"cost": { "food": 0, "wood": 200, "gold": 0 },
		"build_time": 30.0,
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
		"cost": { "food": 0, "wood": 200, "gold": 50 },
		"build_time": 30.0,
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
	BuildingType.LUMBER_CAMP: {
		"name": "Lumber Camp",
		"hp": 500,
		"cost": { "food": 0, "wood": 100, "gold": 0 },
		"build_time": 15.0,
		"pop_provided": 0,
		"footprint": Vector2i(2, 2),
		"can_train": [],
		"age_required": 0,
		"drop_off": ["wood"],
		"color": Color(0.45, 0.35, 0.2),
	},
	BuildingType.MINING_CAMP: {
		"name": "Mining Camp",
		"hp": 500,
		"cost": { "food": 0, "wood": 100, "gold": 0 },
		"build_time": 15.0,
		"pop_provided": 0,
		"footprint": Vector2i(2, 2),
		"can_train": [],
		"age_required": 0,
		"drop_off": ["gold"],
		"color": Color(0.5, 0.5, 0.55),
	},
	BuildingType.SIEGE_WORKSHOP: {
		"name": "Siege Workshop",
		"hp": 1500,
		"cost": { "food": 0, "wood": 300, "gold": 100 },
		"build_time": 40.0,
		"pop_provided": 0,
		"footprint": Vector2i(3, 3),
		"can_train": [UnitData.UnitType.SIEGE],
		"age_required": 3,
		"drop_off": [],
		"color": Color(0.4, 0.4, 0.45),
	},
}


static func get_building_stats(building_type: int) -> Dictionary:
	if BUILDINGS.has(building_type):
		return BUILDINGS[building_type].duplicate(true)
	return {}


static func get_building_cost(building_type: int) -> Dictionary:
	if BUILDINGS.has(building_type):
		return BUILDINGS[building_type]["cost"].duplicate()
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
