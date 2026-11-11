class_name SkirmishData
extends RefCounted
## Match budgets for comparing mobile economy and army sizes.
## Population counts bodies: every Villager and soldier is one, a Siege Engine two.

enum MatchMode { STANDARD, QUICK_CONTROL }

static func normalize_match_mode(value: int) -> int:
	return value if value in [MatchMode.STANDARD, MatchMode.QUICK_CONTROL] else MatchMode.STANDARD


static func get_mode_name(mode: int) -> String:
	match mode:
		MatchMode.QUICK_CONTROL: return "Control race"
	return "Standard"


## Standard's victory clock opens at this game time. Holding the site earlier
## still earns gold, so the center is worth fighting over from the start, but
## no Sacred win can arrive before the armies, ages and economies have grown.
static func get_sacred_wake_seconds(mode: int) -> float:
	return SACRED_VICTORY_WAKE_SECONDS if normalize_match_mode(mode) == MatchMode.STANDARD else 0.0


static func get_sacred_target(mode: int) -> float:
	match mode:
		MatchMode.QUICK_CONTROL: return 180.0
	return SACRED_VICTORY_HOLD_SECONDS


## Bodies per player (Round 2 E: one population per ordinary unit). The default
## is the one constant to change if performance work recommends another size.
const POPULATION_OPTIONS: Array[int] = [30, 40, 60, 80, 100, 120]
const DEFAULT_POPULATION_LIMIT: int = 80
## Version 2: limits are bodies. A limit saved by an older build counted two
## slots per unit, so it is reset to the default once. Version 3 (Round 2 E2):
## the default fell from 100 to 80 bodies (phone frame rate in a full clash),
## so a saved limit is reset to it once; 100 and 120 stay selectable.
const POPULATION_PREFERENCE_VERSION: int = 3
const REFERENCE_POPULATION_LIMIT: int = 60
## Castle unlocks the siege endgame. Imperial has no skirmish content yet.
const MAX_AGE: int = 3
const AGE_NAMES: Array[String] = ["Dark Age", "Feudal Age", "Castle Age"]
## Round 2 E2: the main win is destroying every enemy Town Center. The Sacred
## Site is a late tiebreaker: its clock wakes at 12:00 and then asks for a 5:00
## hold, so the earliest Sacred win is 17:00. The clock runs only while the
## owner has an armed soldier in the ring and no enemy is inside; an unguarded
## or contested clock drains at SACRED_DRAIN_RATE, and losing the site resets
## it. Control race keeps its banked 3:00 rules, awake from the first capture.
const SACRED_VICTORY_HOLD_SECONDS: float = 300.0
const SACRED_VICTORY_WAKE_SECONDS: float = 720.0
## Standard only: held seconds lost per second while unguarded or contested.
const SACRED_DRAIN_RATE: float = 1.0
const NATURAL_RESOURCE_BUDGETS: Dictionary = {"food": 4000, "wood": 10000, "gold": 4000}
const OPENING_BERRY_STOCK: int = 90
# Four Villagers, two Houses and a Resource Camp fit the bank; everything after
# that is earned by the opening flock.
const STARTING_RESOURCES: Dictionary = {"food": 200, "wood": 200, "gold": 100}
# Difficulty changes planning time, never costs, income or unit strength.
# Home defense remains immediate. Easy gives a learner until 14:00 to build and explore the
# objective, then sends small coherent squads with a visible recovery interval.
const AI_RAID_START_SECONDS: Dictionary = {0: 840.0, 1: 120.0, 2: 0.0}
const AI_RAID_COOLDOWN_SECONDS: Dictionary = {0: 300.0, 1: 75.0, 2: 0.0}
# Respond to an opponent's objective claim before its first victory. This
# does not advance the separate neutral initiative or ordinary base raids.
const EASY_SACRED_RESPONSE_SECONDS: float = 150.0
const EASY_SACRED_INITIATIVE_SECONDS: float = 390.0
const EASY_REGROUP_SECONDS: float = 45.0
const EASY_LARGER_SQUAD_SECONDS: float = 1140.0
const DARK_AGE_WORKER_WEIGHTS: Dictionary = {"food": 0.55, "wood": 0.35, "gold": 0.10}
const FEUDAL_WORKER_WEIGHTS: Dictionary = {"food": 0.55, "wood": 0.40, "gold": 0.05}
const AGE_UP_COSTS: Dictionary = {
	2: {"food": 500},
	3: {"food": 800, "gold": 200},
}
## Control race is a short mode: its Feudal Age is cheaper.
const QUICK_CONTROL_FEUDAL_COST: Dictionary = {"food": 300}
## The smallest population budgets never pay less than this share of an age.
const AGE_UP_MIN_SCALE: float = 0.5


static func normalize_population_limit(value: int) -> int:
	return value if value in POPULATION_OPTIONS else DEFAULT_POPULATION_LIMIT


static func restore_population_limit(value: int, preference_version: int) -> int:
	# Previous releases saved the implicit 30 default without recording whether
	# it was an explicit choice. Promote that legacy value once; preserve other
	# old custom sizes and every explicit choice saved by the new setup.
	if preference_version < POPULATION_PREFERENCE_VERSION:
		return DEFAULT_POPULATION_LIMIT
	return normalize_population_limit(value)


static func get_economy_target(population_limit: int) -> int:
	# About two fifths of the bodies work; the rest is room for an army.
	return clampi(int(population_limit * 2 / 5), 4, 45)


static func get_easy_economy_target(population_limit: int) -> int:
	return clampi(int(population_limit / 5), 4, 20)


static func get_easy_fighter_target(population_limit: int) -> int:
	return maxi(4, int(population_limit / 6))


static func get_easy_pressure_squad_size(game_time: float) -> int:
	return 4 if game_time < EASY_LARGER_SQUAD_SECONDS else 6


static func get_new_worker_weights(age: int) -> Dictionary:
	return DARK_AGE_WORKER_WEIGHTS if age < 2 else FEUDAL_WORKER_WEIGHTS


static func get_age_up_cost(target_age: int, population_limit: int, mode: int = MatchMode.STANDARD) -> Dictionary:
	if mode != MatchMode.STANDARD and target_age == 2:
		return QUICK_CONTROL_FEUDAL_COST.duplicate()
	var base_cost: Dictionary = AGE_UP_COSTS.get(target_age, {})
	var cost: Dictionary = {}
	# A 60-body kingdom or larger pays the published price. Smaller budgets
	# scale down with their economy, but never below half: even the smallest
	# duel must gather well beyond its starting stock before advancing.
	var scale: float = clampf(float(population_limit) / float(REFERENCE_POPULATION_LIMIT), AGE_UP_MIN_SCALE, 1.0)
	for resource: String in base_cost:
		cost[resource] = int(roundf(float(base_cost[resource]) * scale / 5.0)) * 5
	return cost
