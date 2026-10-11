class_name TechData
extends RefCounted
## Research prices, requirements and effects shared by UI and both players.

const RESEARCH_DEFS: Array[Dictionary] = [
	{"id": "forging", "name": "Forge Weapons", "desc": "+2 Attack", "cost": {"food": 100, "gold": 50}, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 1, "attack_bonus": 2},
	{"id": "scale_mail", "name": "Scale Mail", "desc": "+1 Armor", "cost": {"food": 100, "gold": 50}, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 1, "armor_bonus": 1},
	{"id": "wheelbarrow", "name": "Wheelbarrow", "desc": "+25% Gather", "cost": {"food": 175, "wood": 50}, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 1, "gather_bonus": UnitData.WHEELBARROW_GATHER_BONUS},
	{"id": "loom", "name": "Loom", "desc": "+15 Villager HP", "cost": {"gold": 50}, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 1, "villager_hp_bonus": 15},
]


static func get_research_definition(research_id: String) -> Dictionary:
	for definition: Dictionary in RESEARCH_DEFS:
		if String(definition["id"]) == research_id:
			return definition.duplicate(true)
	return {}
