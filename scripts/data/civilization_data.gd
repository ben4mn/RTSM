class_name CivilizationData
extends RefCounted
## Civilization identity is public match setup, never an undisclosed upgrade.
## All values here are shared by the local simulation and online authority.

# Serialized IDs stay stable: French, English, Mongols respectively.
enum Civilization { CROWNLANDS, VERDANT_LEAGUE, SUNSTRIDE_CLANS }

const ORDERED_IDS: Array[int] = [Civilization.CROWNLANDS, Civilization.VERDANT_LEAGUE, Civilization.SUNSTRIDE_CLANS]
## Version 2 (Round 2 workstream C): every kingdom has an economy bonus, a
## unique unit with a passive ability (scripts/units/unit_abilities.gd) and a
## unique technology (TechData rows carrying a "civilization" key).
const CATALOG_VERSION: int = 2

## Definition keys that carry rules (everything else is menu copy):
##   "modifiers": {registry key: amount} written to the GameManager modifier
##       registry once, when a match starts (docs/round2_contracts.md).
##   "unit_overrides": {unit type: {...}} merged over UnitData.UNITS. A key
##       ending in "_mult" scales the line's own stat, so it survives a rescale
##       of the base numbers. "ability" names a UnitAbilities passive.
##   "unit_cost_multipliers" / "building_cost_multipliers": {type: factor} on
##       every resource of the published price (rounded to 5). Both players and
##       the AI pay through UnitData.get_unit_cost / BuildingData.get_building_cost.
##   "extra_home_sheep": reserved for the wildlife stream (not read yet).
##   "unique_tech": TechData research id only this kingdom can research.
## Stable ids used below: units 0 Villager, 2 Archer, 3 Cavalry, 4 Scout;
## buildings 5 Farm, 6 Resource Camp. Avoids a cyclic data dependency.
## One-line data switch: until herds and game are on the map, the wildlife
## gathering bonus also applies to berry bushes (see UnitAbilities.gather_bonus).
const WILDLIFE_BONUS_INCLUDES_BERRIES: bool = false
const DEFINITIONS: Dictionary = {
	Civilization.CROWNLANDS: {
		"name": "French",
		"tagline": "Slate roofs and market mornings",
		"description": "Blue slate roofs rise over pale stone workshops. Bread cools beside the oven; a cooper rolls a barrel into the market. Blue surcoats and a single fleur-de-lis gather this small French town’s defenders.",
		"strengths": "Villagers train 20% faster · Farms cost a third less wood",
		"weakness": "No gathering bonus · a spent Chevalier must rest to charge again",
		"signature": "Chevalier — heavy cavalry with a resting Charge",
		"play_style": "Quick villages & charging knights",
		"preview_unit_icon": "res://assets/units/warrior.svg",
		"icon_path": "res://assets/ui/civilizations/crownlands.svg",
		"gather_multipliers": {},
		"modifiers": {},
		"building_hp_multiplier": 1.0,
		"unit_cost_multipliers": {},
		"building_cost_multipliers": {5: 0.67},
		"extra_home_sheep": 0,
		"unique_tech": "chivalry",
		"unit_overrides": {
			0: {"build_time_mult": 0.8},
			3: {"name": "Chevalier", "role": "Charging heavy cavalry", "ability": "charge"},
		},
	},
	Civilization.VERDANT_LEAGUE: {
		"name": "English",
		"tagline": "Thatched cottages and yew bows",
		"description": "Warm timber frames and ochre thatch shelter a village green. A bowyer checks a long yew stave while woollen hoods dry by the door. Dusty red cloth and a little rose badge identify the English company.",
		"strengths": "+20% wood gathering · Resource Camps cost half",
		"weakness": "Longbows are fragile and must stand still to excel · weaker Horsemen",
		"signature": "Longbow — archer that digs in when it stands still",
		"play_style": "Timber & longbow lines",
		"preview_unit_icon": "res://assets/units/longbow.svg",
		"icon_path": "res://assets/ui/civilizations/verdant_league.svg",
		"gather_multipliers": {},
		"modifiers": {"gather_wood": 0.20},
		"building_hp_multiplier": 1.0,
		"unit_cost_multipliers": {},
		"building_cost_multipliers": {6: 0.5},
		"extra_home_sheep": 0,
		"unique_tech": "yeomen",
		"unit_overrides": {
			2: {"name": "Longbow", "role": "Bow infantry that digs in", "hp_mult": 0.857, "vision_radius": 7, "civilization_icon": "res://assets/units/longbow.svg", "ability": "emplace"},
			3: {"hp_mult": 0.8125},
		},
	},
	Civilization.SUNSTRIDE_CLANS: {
		"name": "Mongols",
		"tagline": "Felt homes and well-kept saddles",
		"description": "Round felt gers cluster beside timber workshops and a small millet field. Saddle blankets air on a rail; a rider tightens a deel’s sash. Sage cloth and a horsehair standard give this Mongol frontier camp its identity.",
		"strengths": "+30% food from herds, game and berries",
		"weakness": "Lighter Outriders · buildings have 20% less HP",
		"signature": "Outrider — swift raider that pillages gold",
		"play_style": "Herds & raiding riders",
		"preview_unit_icon": "res://assets/units/outrider.svg",
		"icon_path": "res://assets/ui/civilizations/sunstride_clans.svg",
		"gather_multipliers": {},
		"modifiers": {"gather_wildlife": 0.30},
		"building_hp_multiplier": 0.8,
		"unit_cost_multipliers": {},
		"building_cost_multipliers": {},
		"extra_home_sheep": 2,
		"unique_tech": "yam",
		"unit_overrides": {
			3: {"name": "Outrider", "role": "Swift raiding cavalry", "hp_mult": 0.875, "speed": 110.0, "civilization_icon": "res://assets/units/outrider.svg", "ability": "pillage"},
		},
	},
}


static func normalize(value: int) -> int:
	return value if DEFINITIONS.has(value) else Civilization.CROWNLANDS


static func is_valid(value: int) -> bool:
	return DEFINITIONS.has(value)


static func get_definition(civilization: int) -> Dictionary:
	return DEFINITIONS[normalize(civilization)].duplicate(true)


static func get_civilization_name(civilization: int) -> String:
	return str(DEFINITIONS[normalize(civilization)]["name"])


static func choose_solo_opponent(civilization: int, match_seed: int) -> int:
	# An independent seeded draw leaves terrain generation untouched. A saved
	# map seed and player choice always produce the same contrasting rival.
	var choices: Array[int] = ORDERED_IDS.duplicate()
	choices.erase(normalize(civilization))
	var random := RandomNumberGenerator.new()
	random.seed = match_seed ^ 0x5B17
	return choices[random.randi_range(0, choices.size() - 1)]


static func get_unit_stats(base_stats: Dictionary, unit_type: int, civilization: int) -> Dictionary:
	var stats: Dictionary = base_stats.duplicate(true)
	var overrides: Dictionary = DEFINITIONS[normalize(civilization)]["unit_overrides"].get(unit_type, {})
	for key: String in overrides:
		if key.ends_with("_mult"):
			# A ratio of the line's own stat: whole numbers stay whole.
			var stat: String = key.trim_suffix("_mult")
			var scaled: float = float(stats.get(stat, 0.0)) * float(overrides[key])
			stats[stat] = int(round(scaled)) if stats.get(stat) is int else scaled
		else:
			stats[key] = overrides[key]
	return stats


static func get_starting_modifiers(civilization: int) -> Dictionary:
	## Registry entries a player of this kingdom starts the match with.
	return (DEFINITIONS[normalize(civilization)]["modifiers"] as Dictionary).duplicate()


static func get_unit_cost_multiplier(civilization: int, unit_type: int) -> float:
	return float(DEFINITIONS[normalize(civilization)]["unit_cost_multipliers"].get(unit_type, 1.0))


static func get_building_cost_multiplier(civilization: int, building_type: int) -> float:
	return float(DEFINITIONS[normalize(civilization)]["building_cost_multipliers"].get(building_type, 1.0))


static func scale_cost(cost: Dictionary, multiplier: float) -> Dictionary:
	## Kingdom discounts land on a multiple of 5 so prices stay easy to read.
	if is_equal_approx(multiplier, 1.0):
		return cost
	for resource: String in cost:
		if int(cost[resource]) > 0:
			cost[resource] = maxi(5, int(round(float(cost[resource]) * multiplier / 5.0)) * 5)
	return cost


static func get_extra_home_sheep(civilization: int) -> int:
	## Reserved for the wildlife stream: extra pre-claimed sheep at the start.
	return int(DEFINITIONS[normalize(civilization)].get("extra_home_sheep", 0))


static func get_unique_tech(civilization: int) -> String:
	return str(DEFINITIONS[normalize(civilization)].get("unique_tech", ""))


static func get_unit_ability(civilization: int, unit_type: int) -> String:
	## UnitAbilities id ("charge", "emplace", "pillage") or "".
	return str(DEFINITIONS[normalize(civilization)]["unit_overrides"].get(unit_type, {}).get("ability", ""))


static func get_gather_multiplier(civilization: int, resource: String) -> float:
	return float(DEFINITIONS[normalize(civilization)]["gather_multipliers"].get(resource, 1.0))


static func get_building_hp_multiplier(civilization: int) -> float:
	return float(DEFINITIONS[normalize(civilization)]["building_hp_multiplier"])


static func get_ai_unit_weight(civilization: int, unit_type: int) -> float:
	## A mild preference, multiplied by the AI's observed counter weighting.
	match normalize(civilization):
		Civilization.CROWNLANDS:
			if unit_type == 3:
				return 1.3
		Civilization.VERDANT_LEAGUE:
			if unit_type == 2:
				return 1.35
			if unit_type == 3:
				return 0.7
		Civilization.SUNSTRIDE_CLANS:
			if unit_type == 3:
				return 1.35
	return 1.0


static func for_player(player_id: int) -> int:
	## Data scripts can load before autoload symbols in SceneTree fixtures.
	if player_id < 0:
		return Civilization.CROWNLANDS
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var manager: Node = tree.root.get_node_or_null("GameManager") if tree != null and tree.root != null else null
	if manager != null and manager.has_method("get_player_civilization"):
		return normalize(int(manager.call("get_player_civilization", player_id)))
	return Civilization.CROWNLANDS
