class_name TechData
extends RefCounted
## Research prices, requirements and effects shared by UI and both players.

const RESEARCH_DEFS: Array[Dictionary] = [
	{"id": "forging", "name": "Forge Weapons", "desc": "+2 Attack", "details": "Instant, one-time +2 attack for your existing and future armed units, including Villagers and Siege. Scouts and building weapons are unchanged.", "cost": {"food": 100, "gold": 50}, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 1, "attack_bonus": 2},
	{"id": "scale_mail", "name": "Scale Mail", "desc": "+1 Armor", "details": "Instant, one-time +1 armor for your existing and future units, including Scouts. Does not affect buildings.", "cost": {"food": 100, "gold": 50}, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 1, "armor_bonus": 1},
	{"id": "wheelbarrow", "name": "Wheelbarrow", "desc": "+25% Gather", "details": "Instant, one-time +25% gathered per tick for your existing and future Villagers. Walking speed and carry capacity are unchanged.", "cost": {"food": 175, "wood": 50}, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 1, "gather_bonus": UnitData.WHEELBARROW_GATHER_BONUS},
	{"id": "loom", "name": "Loom", "desc": "+15 Villager HP", "details": "Instant, one-time +15 maximum HP for your existing and future Villagers. Living Villagers also gain 15 current HP.", "cost": {"gold": 50}, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 1, "villager_hp_bonus": 15},
]


static func get_research_definition(research_id: String) -> Dictionary:
	for definition: Dictionary in RESEARCH_DEFS:
		if String(definition["id"]) == research_id:
			return definition.duplicate(true)
	return {}
