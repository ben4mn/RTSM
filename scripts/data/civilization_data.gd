class_name CivilizationData
extends RefCounted
## Civilization identity is public match setup, never an undisclosed upgrade.
## All values here are shared by the local simulation and online authority.

enum Civilization { CROWNLANDS, VERDANT_LEAGUE, SUNSTRIDE_CLANS }

const ORDERED_IDS: Array[int] = [Civilization.CROWNLANDS, Civilization.VERDANT_LEAGUE, Civilization.SUNSTRIDE_CLANS]
const CATALOG_VERSION: int = 1
const DEFINITIONS: Dictionary = {
	Civilization.CROWNLANDS: {
		"name": "Crownlands",
		"tagline": "A steady hand. An answer to every army.",
		"description": "A balanced kingdom with durable Horsemen, dependable Archers and full-strength buildings. Adapt your army to the enemy instead of committing to a specialty.",
		"strengths": "Balanced armies · full-strength defenses",
		"weakness": "No specialized economy or signature-unit bonus",
		"signature": "Flexible combined arms",
		"preview_unit_icon": "res://assets/units/warrior.svg",
		"icon_path": "res://assets/ui/civilizations/crownlands.svg",
		"gather_multipliers": {},
		"building_hp_multiplier": 1.0,
		"unit_overrides": {},
	},
	Civilization.VERDANT_LEAGUE: {
		"name": "Verdant League",
		"tagline": "Claim the tree line. Win the first volley.",
		"description": "Woodcutters harvest 20% faster. Longbows replace Archers, reaching one tile farther but carrying only 30 HP. Horsemen have 65 HP, so protect your bow line with Warriors.",
		"strengths": "+20% wood gathering · Longbows have +1 range",
		"weakness": "Longbows: 30 HP · Horsemen: 65 HP",
		"signature": "Longbow — long range, fragile at close quarters",
		"preview_unit_icon": "res://assets/units/longbow.svg",
		"icon_path": "res://assets/ui/civilizations/verdant_league.svg",
		"gather_multipliers": {"wood": 1.2},
		"building_hp_multiplier": 1.0,
		# Stable unit IDs: 2 Archer, 3 Cavalry. Avoid a cyclic data dependency.
		"unit_overrides": {
			2: {"name": "Longbow", "role": "Long-range bow infantry", "hp": 30, "attack_range": 6, "vision_radius": 7, "civilization_icon": "res://assets/units/longbow.svg"},
			3: {"hp": 65},
		},
	},
	Civilization.SUNSTRIDE_CLANS: {
		"name": "Sunstride Clans",
		"tagline": "Move first. Strike where they are absent.",
		"description": "Food workers harvest 15% faster. Outriders replace Horsemen: about 16% faster, but only 70 HP. Buildings have 20% less health. Keep pressure on the field and avoid a siege at home.",
		"strengths": "+15% food gathering · faster Outriders",
		"weakness": "Outriders: 70 HP · buildings: −20% HP",
		"signature": "Outrider — swift flanking cavalry",
		"preview_unit_icon": "res://assets/units/outrider.svg",
		"icon_path": "res://assets/ui/civilizations/sunstride_clans.svg",
		"gather_multipliers": {"food": 1.15},
		"building_hp_multiplier": 0.8,
		"unit_overrides": {
			3: {"name": "Outrider", "role": "Swift flanking cavalry", "hp": 70, "speed": 110.0, "civilization_icon": "res://assets/units/outrider.svg"},
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


static func get_unit_stats(base_stats: Dictionary, unit_type: int, civilization: int) -> Dictionary:
	var stats: Dictionary = base_stats.duplicate(true)
	var overrides: Dictionary = DEFINITIONS[normalize(civilization)]["unit_overrides"]
	stats.merge(overrides.get(unit_type, {}), true)
	return stats


static func get_gather_multiplier(civilization: int, resource: String) -> float:
	return float(DEFINITIONS[normalize(civilization)]["gather_multipliers"].get(resource, 1.0))


static func get_building_hp_multiplier(civilization: int) -> float:
	return float(DEFINITIONS[normalize(civilization)]["building_hp_multiplier"])


static func get_ai_unit_weight(civilization: int, unit_type: int) -> float:
	## A mild preference, multiplied by the AI's observed counter weighting.
	match normalize(civilization):
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
