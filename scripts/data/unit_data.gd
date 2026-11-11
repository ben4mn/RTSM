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
## Presentation-only enlargement shared by sprites, rings, bars, tool overlays
## and projectile origins. Collision, separation and ranges never read it.
const WORLD_VISUAL_SCALE: float = 1.3
const WORLD_SPRITE_SCALES: Dictionary = {
	UnitType.VILLAGER: Vector2(0.30, 0.30) * WORLD_VISUAL_SCALE,
	UnitType.INFANTRY: Vector2(0.31, 0.31) * WORLD_VISUAL_SCALE,
	UnitType.ARCHER: Vector2(0.30, 0.30) * WORLD_VISUAL_SCALE,
	UnitType.CAVALRY: Vector2(0.45, 0.45) * WORLD_VISUAL_SCALE,
	UnitType.SCOUT: Vector2(0.43, 0.43) * WORLD_VISUAL_SCALE,
	UnitType.SIEGE: Vector2(0.60, 0.60) * WORLD_VISUAL_SCALE,
	UnitType.TRADER: Vector2(0.38, 0.38) * WORLD_VISUAL_SCALE,
}

# Round 2 E (AoE2 scale): every ordinary unit is one population body. A worker
# gathers 1 per tick and hauls 15, about 59 food/wood per minute including the
# walk; wildlife is worked 1.3x faster (WildlifeData.GATHER_MULTIPLIER).
# Five opening workers start on the home flock; the economy grows to dozens.
# Shared carry slots preserve mixed cargo on retask; no harvest is discarded.
const STARTING_VILLAGERS: int = 5
const VILLAGER_BUILD_SPEED: float = 2.0
const VILLAGER_GATHER_AMOUNT: float = 1.0
const WHEELBARROW_GATHER_BONUS: float = VILLAGER_GATHER_AMOUNT * 0.25
const VILLAGER_CARRY_CAPACITY: int = 15
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
		"hp": 25,
		"damage": 3,
		"armor": 0,
		"speed": 60.0,
		"cost": { "food": 50, "wood": 0, "gold": 0 },
		"build_time": 14.0,
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
		# Round 2 E2: masonry shrugs off blades and arrows; siege razes towns.
		"bonus_vs_buildings": 0.5,
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
		"bonus_vs_buildings": 0.3,
		"hp": 35,
		"damage": 7,
		"armor": 0,
		"speed": 55.0,
		"cost": { "food": 25, "wood": 40, "gold": 10 },
		"build_time": 14.0,
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
		"bonus_vs_buildings": 0.4,
		"hp": 80,
		"damage": 10,
		"armor": 1,
		"speed": 95.0,
		"cost": { "food": 65, "wood": 10, "gold": 20 },
		"build_time": 16.0,
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
		"cost": { "food": 30, "wood": 0, "gold": 0 },
		"build_time": 8.0,
		"vision_radius": 10,
		"attack_range": 1,
		"pop_cost": 1,
		"can_gather": false,
		"can_build": false,
	},
	UnitType.TRADER: {
		"name": "Trader", "role": "Renewable gold", "hp": 35, "damage": 0,
		"armor": 0, "speed": 70.0, "cost": {"food": 0, "wood": 60, "gold": 40},
		"build_time": 22.0, "vision_radius": 4, "attack_range": 0, "pop_cost": 1,
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
		"cost": { "food": 0, "wood": 100, "gold": 150 },  # Round 2 E2: gold-heavy finishing tool
		"build_time": 25.0,
		"vision_radius": 3,
		"attack_range": 7,
		"pop_cost": 2,
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


# --- Unit line tiers (Round 2 workstream B) ---
# A tier is an overlay on the SAME UnitType, bought as research (TechData
# "tier" rows) and stored per player in the modifier registry as
# `tier_<unit_type>` (1 = base). Values are ratios of the line's own stats, so
# they stay right when the base numbers are rescaled: at the Round 2 E scale
# they give Man-at-Arms 75/10/3, Champion 95/12/3, Crossbowman 43/9 and Knight
# 105/13/2 (tools/test_unit_tiers pins the ratios, not the numbers).
# The ratios apply on top of civilization overrides, and a civilization's own
# unit name (Longbow, Outrider) wins over the tier name.
const UNIT_TIERS: Dictionary = {
	UnitType.INFANTRY: {
		2: {"name": "Man-at-Arms", "hp_mult": 1.25, "damage_mult": 1.2, "armor_mult": 1.25},
		3: {"name": "Champion", "hp_mult": 1.5834, "damage_mult": 1.45, "armor_mult": 1.5},
	},
	UnitType.ARCHER: {
		2: {"name": "Crossbowman", "hp_mult": 1.22, "damage_mult": 1.22},
	},
	UnitType.CAVALRY: {
		2: {"name": "Knight", "hp_mult": 1.3125, "damage_mult": 1.25, "armor_mult": 2.0},
	},
}
const TIER_ICONS: Dictionary = {2: "res://assets/ui/icons/tier2.svg", 3: "res://assets/ui/icons/tier3.svg"}


static func tier_modifier_key(unit_type: int) -> String:
	return "tier_%d" % unit_type


static func get_max_tier(unit_type: int) -> int:
	var best: int = 1
	for tier: int in UNIT_TIERS.get(unit_type, {}):
		best = maxi(best, tier)
	return best


static func get_unit_tier(unit_type: int, player_id: int) -> int:
	## The player's researched tier for this line; 1 when none or unknown.
	if player_id < 0 or not UNIT_TIERS.has(unit_type):
		return 1
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	var gm: Node = scene_tree.root.get_node_or_null("GameManager") if scene_tree != null else null
	if gm == null:
		return 1
	return clampi(int(gm.get_modifier(player_id, tier_modifier_key(unit_type), 1.0)), 1, get_max_tier(unit_type))


static func get_unit_stats(unit_type: int, player_id: int = -1, tier: int = -1) -> Dictionary:
	## `tier` -1 uses the player's researched tier; pass 1..n to preview one.
	if not UNITS.has(unit_type):
		return {}
	# Without a player this is the published base line, free of any kingdom.
	var stats: Dictionary = CivilizationData.get_unit_stats(UNITS[unit_type], unit_type, CivilizationData.for_player(player_id)) if player_id >= 0 else (UNITS[unit_type] as Dictionary).duplicate(true)
	if tier < 0:
		tier = get_unit_tier(unit_type, player_id)
	var overlay: Dictionary = UNIT_TIERS.get(unit_type, {}).get(tier, {})
	if not overlay.is_empty():
		for stat: String in ["hp", "damage", "armor"]:
			if overlay.has(stat + "_mult"):
				stats[stat] = int(round(float(stats.get(stat, 0)) * float(overlay[stat + "_mult"])))
		stats["tier"] = tier
		if str(stats.get("name", "")) == str(UNITS[unit_type].get("name", "")):
			stats["name"] = str(overlay.get("name", stats["name"]))
		else:
			# A civilization's own unit keeps its name and wears the tier as a rank.
			stats["name"] = "%s %s" % [str(stats["name"]), "I".repeat(mini(tier, 3))]
	_apply_line_modifiers(stats, unit_type, player_id)
	return stats


static func line_modifier_key(stat: String, unit_type: int) -> String:
	## Registry key for a researched fraction on one unit line's stat, e.g.
	## `hp_mult_3` +0.12 (Chivalry) or `speed_mult_4` +0.10 (Yam).
	return "%s_mult_%d" % [stat, unit_type]


static func _apply_line_modifiers(stats: Dictionary, unit_type: int, player_id: int) -> void:
	## Round 2 C: unique technologies scale a line's HP or speed as a fraction
	## of its own (civilization- and tier-adjusted) stat.
	if player_id < 0:
		return
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	var gm: Node = scene_tree.root.get_node_or_null("GameManager") if scene_tree != null and scene_tree.root != null else null
	if gm == null:
		return
	# Called often (cards, AI, combat): skip the key formatting until this
	# player has researched anything at all.
	var modifiers: Variant = gm.get("player_modifiers").get(player_id)
	if not modifiers is Dictionary or (modifiers as Dictionary).is_empty():
		return
	var hp_bonus: float = float(gm.get_modifier(player_id, line_modifier_key("hp", unit_type)))
	if hp_bonus != 0.0:
		stats["hp"] = int(round(float(stats.get("hp", 0)) * (1.0 + hp_bonus)))
	var speed_bonus: float = float(gm.get_modifier(player_id, line_modifier_key("speed", unit_type)))
	if speed_bonus != 0.0:
		stats["speed"] = float(stats.get("speed", 0.0)) * (1.0 + speed_bonus)


static func get_unit_cost(unit_type: int, player_id: int = -1) -> Dictionary:
	## `player_id` applies that player's kingdom price (none today; data-driven).
	if UNITS.has(unit_type):
		var cost: Dictionary = UNITS[unit_type]["cost"].duplicate()
		if player_id >= 0:
			CivilizationData.scale_cost(cost, CivilizationData.get_unit_cost_multiplier(CivilizationData.for_player(player_id), unit_type))
		return cost
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
			# The base line name: counters are about the line, not its tier.
			var target_name: String = str(get_unit_stats(target_type, 1 - player_id, 1)["name"])
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
	return clampi(int(Engine.get_meta("balance_starting_villagers", STARTING_VILLAGERS)), 3, STARTING_VILLAGERS)
