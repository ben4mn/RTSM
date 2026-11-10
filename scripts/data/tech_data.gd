class_name TechData
extends RefCounted
## Research prices, times, requirements and effects shared by UI and both players.
##
## Every research is timed and happens in one building's single research slot
## (GameManager.try_start_research). Effects land at completion:
##   "effects": {modifier key: amount} is added to the GameManager modifier
##       registry (docs/round2_contracts.md). Fraction keys (gather_*, carry,
##       villager_speed) store +0.2 for +20% so they survive a unit rescale.
##   "tier": {"unit_type", "tier"} raises a unit line (UnitData.UNIT_TIERS).
##   "requires": id of the research that must be finished first; the follow-up
##       replaces its predecessor's card once that is done.
## All amounts here are tuning data: retune freely (workstream E).

const ICON_DIR: String = "res://assets/ui/icons/"

## Age-up is research `age_<target>` in a Town Center slot. Costs stay in
## SkirmishData.get_age_up_cost; these are the timed parts.
const AGE_RESEARCH_PREFIX: String = "age_"
const AGE_UP_TIMES: Dictionary = {2: 35.0, 3: 50.0}
## target age -> {"count": completed buildings needed, "types": [BuildingType]}.
const AGE_UP_REQUIREMENTS: Dictionary = {
	2: {"count": 1, "types": [BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.RESOURCE_CAMP]},
	3: {"count": 2, "types": [BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE, BuildingData.BuildingType.BLACKSMITH]},
}

const RESEARCH_DEFS: Array[Dictionary] = [
	# --- Town Center ---
	{"id": "loom", "name": "Loom", "desc": "+15 Villager HP", "details": "Your existing and future Villagers gain +15 maximum HP. Living Villagers also gain 15 current HP.", "cost": {"gold": 50}, "time": 15.0, "building_type": BuildingData.BuildingType.TOWN_CENTER, "age_required": 1, "icon": ICON_DIR + "tech_loom.svg", "effects": {"villager_hp": 15.0}},
	{"id": "wheelbarrow", "name": "Wheelbarrow", "short": "Barrow", "desc": "Carry +33%, walk +10%", "details": "Your existing and future Villagers carry a third more per trip and walk 10% faster.", "cost": {"food": 175, "wood": 50}, "time": 35.0, "building_type": BuildingData.BuildingType.TOWN_CENTER, "age_required": 2, "icon": ICON_DIR + "tech_cart.svg", "effects": {"carry": 0.34, "villager_speed": 0.10}},
	{"id": "hand_cart", "name": "Hand Cart", "short": "Hand Cart", "desc": "+15% all gathering", "details": "Your Villagers gather every resource 15% faster.", "cost": {"food": 300, "wood": 200}, "time": 45.0, "building_type": BuildingData.BuildingType.TOWN_CENTER, "age_required": 3, "requires": "wheelbarrow", "icon": ICON_DIR + "tech_cart2.svg", "effects": {"gather_all": 0.15}},
	# --- Resource Camp ---
	{"id": "double_bit_axe", "name": "Double-Bit Axe", "short": "Axe", "desc": "+20% wood", "details": "Your Villagers chop wood 20% faster.", "cost": {"food": 100, "wood": 50}, "time": 25.0, "building_type": BuildingData.BuildingType.RESOURCE_CAMP, "age_required": 2, "icon": ICON_DIR + "tech_axe.svg", "effects": {"gather_wood": 0.20}},
	{"id": "gold_panning", "name": "Gold Panning", "short": "Panning", "desc": "+20% gold", "details": "Your Villagers mine gold 20% faster.", "cost": {"food": 100, "wood": 75}, "time": 25.0, "building_type": BuildingData.BuildingType.RESOURCE_CAMP, "age_required": 2, "icon": ICON_DIR + "tech_pan.svg", "effects": {"gather_gold": 0.20}},
	{"id": "horse_collar", "name": "Horse Collar", "short": "Collar", "desc": "+20% farms", "details": "Your Villagers harvest Farms 20% faster.", "cost": {"food": 75, "wood": 75}, "time": 25.0, "building_type": BuildingData.BuildingType.RESOURCE_CAMP, "age_required": 2, "icon": ICON_DIR + "tech_collar.svg", "effects": {"gather_food_farm": 0.20}},
	# --- Blacksmith ---
	{"id": "forging", "name": "Forging", "short": "Forging", "desc": "+2 Attack", "details": "+2 attack for your existing and future armed units, including Villagers and Siege. Scouts and building weapons are unchanged.", "cost": {"food": 100, "gold": 50}, "time": 30.0, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 2, "icon": ICON_DIR + "tech_sword.svg", "effects": {"attack": 2.0}},
	{"id": "iron_casting", "name": "Iron Casting", "short": "Iron Cast", "desc": "+2 Attack", "details": "A further +2 attack for your existing and future armed units.", "cost": {"food": 200, "gold": 120}, "time": 45.0, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 3, "requires": "forging", "icon": ICON_DIR + "tech_sword2.svg", "effects": {"attack": 2.0}},
	{"id": "scale_mail", "name": "Scale Mail", "short": "Mail", "desc": "+1 Armor", "details": "+1 armor for your existing and future units, including Scouts. Does not affect buildings.", "cost": {"food": 100, "gold": 50}, "time": 30.0, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 2, "icon": ICON_DIR + "tech_shield.svg", "effects": {"armor": 1.0}},
	{"id": "chain_mail", "name": "Chain Mail", "short": "Chain", "desc": "+1 Armor", "details": "A further +1 armor for your existing and future units.", "cost": {"food": 200, "gold": 120}, "time": 45.0, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 3, "requires": "scale_mail", "icon": ICON_DIR + "tech_shield2.svg", "effects": {"armor": 1.0}},
	{"id": "fletching", "name": "Fletching", "short": "Fletching", "desc": "+1 Range", "details": "+1 range for your archers, Watch Towers and Town Centers.", "cost": {"food": 100, "gold": 50}, "time": 30.0, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 2, "icon": ICON_DIR + "tech_arrow.svg", "effects": {"range_ranged": 1.0}},
	{"id": "stone_keep", "name": "Stone Keep", "short": "Keep", "desc": "Tough towers", "details": "Your existing and future Watch Towers gain +400 HP and +6 damage.", "cost": {"wood": 150, "gold": 100}, "time": 40.0, "building_type": BuildingData.BuildingType.BLACKSMITH, "age_required": 3, "icon": ICON_DIR + "tech_keep.svg", "effects": {"tower_hp": 400.0, "tower_damage": 6.0}},
	# --- Unit lines (same UnitType, higher tier) ---
	{"id": "man_at_arms", "name": "Man-at-Arms", "short": "Man-at-Arms", "desc": "Stronger infantry", "details": "Upgrades your infantry line: more HP, attack and armor. Living units upgrade on the spot and keep their health percentage.", "cost": {"food": 100, "gold": 40}, "time": 30.0, "building_type": BuildingData.BuildingType.BARRACKS, "age_required": 2, "icon": ICON_DIR + "tier2.svg", "tier": {"unit_type": UnitData.UnitType.INFANTRY, "tier": 2}},
	{"id": "champion", "name": "Champion", "short": "Champion", "desc": "Elite infantry", "details": "Upgrades your infantry line again: elite HP, attack and armor. Living units upgrade on the spot.", "cost": {"food": 300, "gold": 150}, "time": 45.0, "building_type": BuildingData.BuildingType.BARRACKS, "age_required": 3, "requires": "man_at_arms", "icon": ICON_DIR + "tier3.svg", "tier": {"unit_type": UnitData.UnitType.INFANTRY, "tier": 3}},
	{"id": "crossbowman", "name": "Crossbowman", "short": "Crossbow", "desc": "Stronger archers", "details": "Upgrades your archer line: more HP and attack. Living units upgrade on the spot and keep their health percentage.", "cost": {"food": 200, "gold": 125}, "time": 45.0, "building_type": BuildingData.BuildingType.ARCHERY_RANGE, "age_required": 3, "icon": ICON_DIR + "tier2.svg", "tier": {"unit_type": UnitData.UnitType.ARCHER, "tier": 2}},
	{"id": "knight", "name": "Knight", "short": "Knight", "desc": "Stronger cavalry", "details": "Upgrades your cavalry line: more HP, attack and armor. Living units upgrade on the spot and keep their health percentage.", "cost": {"food": 400, "gold": 200}, "time": 50.0, "building_type": BuildingData.BuildingType.STABLE, "age_required": 3, "icon": ICON_DIR + "tier2.svg", "tier": {"unit_type": UnitData.UnitType.CAVALRY, "tier": 2}},
	# --- Unique technologies (Round 2 workstream C) ---
	# "civilization" limits a row to one kingdom: it is hidden from, and cannot
	# be researched by, anyone else (TechData.is_available_to). Effects use the
	# registry: `civ_*` keys are read by UnitAbilities, `<stat>_mult_<unit type>`
	# fractions by UnitData.get_unit_stats.
	{"id": "chivalry", "name": "Chivalry", "short": "Chivalry", "desc": "Charge twice as often", "details": "French unique technology. Chevaliers recover their Charge in 5 seconds instead of 10 and gain 12% maximum HP. Living Chevaliers improve on the spot.", "cost": {"food": 200, "gold": 150}, "time": 40.0, "building_type": BuildingData.BuildingType.STABLE, "age_required": 3, "civilization": CivilizationData.Civilization.CROWNLANDS, "icon": ICON_DIR + "tech_chivalry.svg", "effects": {"civ_charge_recharge": -5.0, "hp_mult_3": 0.12}},
	{"id": "yeomen", "name": "Yeomen", "short": "Yeomen", "desc": "+1 Range", "details": "English unique technology. +1 range for your Longbows, Watch Towers and Town Centers, on top of Fletching and of emplaced stakes.", "cost": {"wood": 150, "gold": 150}, "time": 40.0, "building_type": BuildingData.BuildingType.ARCHERY_RANGE, "age_required": 3, "civilization": CivilizationData.Civilization.VERDANT_LEAGUE, "icon": ICON_DIR + "tech_yeomen.svg", "effects": {"range_ranged": 1.0}},
	{"id": "yam", "name": "Yam", "short": "Yam", "desc": "Riders +10% speed, Pillage x2", "details": "Mongol unique technology. Scouts and Outriders move 10% faster and Pillage pays double gold. Living riders improve on the spot.", "cost": {"food": 150, "gold": 100}, "time": 30.0, "building_type": BuildingData.BuildingType.STABLE, "age_required": 2, "civilization": CivilizationData.Civilization.SUNSTRIDE_CLANS, "icon": ICON_DIR + "tech_yam.svg", "effects": {"speed_mult_3": 0.10, "speed_mult_4": 0.10, "civ_pillage": 1.0}},
]

## Unique technologies sit in the same list; an AI skips other kingdoms' rows.
## Order an AI works through its own idle buildings (Loom first, then the
## line upgrades and economy, then the Blacksmith). Unknown ids are skipped.
const AI_PRIORITY: Array[String] = ["loom", "man_at_arms", "double_bit_axe", "wheelbarrow", "forging", "horse_collar", "scale_mail", "gold_panning", "yam", "fletching", "crossbowman", "knight", "chivalry", "yeomen", "champion", "hand_cart", "iron_casting", "chain_mail", "stone_keep"]
## The subset an Easy AI may research.
const AI_EASY_IDS: Array[String] = ["loom", "man_at_arms", "champion", "crossbowman", "knight"]

## Order research buildings appear in the Research overview.
const RESEARCH_BUILDING_ORDER: Array[int] = [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.RESOURCE_CAMP, BuildingData.BuildingType.BLACKSMITH, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE]


static func get_research_definition(research_id: String) -> Dictionary:
	for definition: Dictionary in RESEARCH_DEFS:
		if String(definition["id"]) == research_id:
			return definition.duplicate(true)
	return {}


static func is_available_to(definition: Dictionary, civilization: int) -> bool:
	## False only for another kingdom's unique technology.
	return not definition.has("civilization") or int(definition["civilization"]) == CivilizationData.normalize(civilization)


static func get_research_time(research_id: String) -> float:
	if is_age_research(research_id):
		return float(AGE_UP_TIMES.get(age_research_target(research_id), 0.0))
	return float(get_research_definition(research_id).get("time", 0.0))


static func get_research_name(research_id: String) -> String:
	if is_age_research(research_id):
		var target_age: int = age_research_target(research_id)
		return SkirmishData.AGE_NAMES[target_age - 1] if target_age >= 1 and target_age <= SkirmishData.AGE_NAMES.size() else "Next Age"
	return str(get_research_definition(research_id).get("name", research_id))


static func get_successor_id(research_id: String) -> String:
	## The research that lists `research_id` as its requirement, or "".
	for definition: Dictionary in RESEARCH_DEFS:
		if str(definition.get("requires", "")) == research_id:
			return str(definition["id"])
	return ""


static func age_research_id(target_age: int) -> String:
	return AGE_RESEARCH_PREFIX + str(target_age)


static func is_age_research(research_id: String) -> bool:
	return research_id.begins_with(AGE_RESEARCH_PREFIX) and research_id.trim_prefix(AGE_RESEARCH_PREFIX).is_valid_int()


static func age_research_target(research_id: String) -> int:
	return int(research_id.trim_prefix(AGE_RESEARCH_PREFIX)) if is_age_research(research_id) else 0


static func describe_age_requirement(target_age: int) -> String:
	## Short "Need X" copy for the blocked age card and button.
	var requirement: Dictionary = AGE_UP_REQUIREMENTS.get(target_age, {})
	if requirement.is_empty():
		return ""
	var names: PackedStringArray = []
	for building_type: int in requirement["types"]:
		names.append(BuildingData.get_building_name(building_type))
	var count: int = int(requirement["count"])
	if count <= 1:
		return "Need a %s" % " or ".join(names)
	return "Need %d of: %s" % [count, ", ".join(names)]
