class_name SkirmishData
extends RefCounted
## Match budgets for comparing mobile economy and army sizes.
## Population counts workers and troops; cavalry/siege can consume extra slots.

enum MatchMode { STANDARD, QUICK_CONTROL }

static func normalize_match_mode(value: int) -> int:
	return value if value in [MatchMode.STANDARD, MatchMode.QUICK_CONTROL] else MatchMode.STANDARD


static func get_mode_name(mode: int) -> String:
	match mode:
		MatchMode.QUICK_CONTROL: return "Control race"
	return "Standard"


static func get_sacred_target(mode: int) -> float:
	match mode:
		MatchMode.QUICK_CONTROL: return 180.0
	return SACRED_VICTORY_HOLD_SECONDS


const POPULATION_OPTIONS: Array[int] = [20, 30, 40, 60, 100]
const DEFAULT_POPULATION_LIMIT: int = 100
const POPULATION_PREFERENCE_VERSION: int = 1
const REFERENCE_POPULATION_LIMIT: int = 40
## Castle unlocks the siege endgame. Imperial has no skirmish content yet.
const MAX_AGE: int = 3
const AGE_NAMES: Array[String] = ["Dark Age", "Feudal Age", "Castle Age"]
## Standard leaves time to counter a held objective and develop renewable income.
## Town Center destruction remains available immediately; Control race stays 3m.
const SACRED_VICTORY_HOLD_SECONDS: float = 300.0
const NATURAL_RESOURCE_BUDGETS: Dictionary = {"food": 4000, "wood": 10000, "gold": 4000}
const OPENING_BERRY_STOCK: int = 90
# The first Barracks (120W), camp (80W), and House (50W) fit the bank;
# concurrent training still requires food workers and construction opportunity cost.
const STARTING_RESOURCES: Dictionary = {"food": 250, "wood": 250, "gold": 100}
# Difficulty changes planning time, never costs, income or unit strength.
# Home defense remains immediate. Easy gives a learner time to explore the
# objective, then sends small coherent squads with a visible recovery interval.
const AI_RAID_START_SECONDS: Dictionary = {0: 300.0, 1: 120.0, 2: 0.0}
const AI_RAID_COOLDOWN_SECONDS: Dictionary = {0: 150.0, 1: 75.0, 2: 0.0}
# Respond to an opponent's objective claim before its first victory. This
# does not advance the separate neutral initiative or ordinary base raids.
const EASY_SACRED_RESPONSE_SECONDS: float = 150.0
const EASY_SACRED_INITIATIVE_SECONDS: float = 390.0
const EASY_REGROUP_SECONDS: float = 45.0
const EASY_LARGER_SQUAD_SECONDS: float = 480.0
const DARK_AGE_WORKER_WEIGHTS: Dictionary = {"food": 0.55, "wood": 0.35, "gold": 0.10}
const FEUDAL_WORKER_WEIGHTS: Dictionary = {"food": 0.55, "wood": 0.40, "gold": 0.05}
const AGE_UP_COSTS: Dictionary = {
	2: {"food": 320, "gold": 160},
	3: {"food": 800, "gold": 400},
}


static func normalize_population_limit(value: int) -> int:
	return value if value in POPULATION_OPTIONS else DEFAULT_POPULATION_LIMIT


static func restore_population_limit(value: int, preference_version: int) -> int:
	# Previous releases saved the implicit 30 default without recording whether
	# it was an explicit choice. Promote that legacy value once; preserve other
	# old custom sizes and every explicit choice saved by the new setup.
	if preference_version < POPULATION_PREFERENCE_VERSION and value == 30:
		return DEFAULT_POPULATION_LIMIT
	return normalize_population_limit(value)


static func get_economy_target(population_limit: int) -> int:
	# Larger kingdoms leave room for armies instead of automatically assigning
	# half the limit to workers. Smaller custom budgets retain their old split.
	return clampi(int(population_limit / 4), 2, 15)


static func get_easy_economy_target(population_limit: int) -> int:
	return clampi(int(population_limit / 5), 2, 15)


static func get_easy_fighter_target(population_limit: int) -> int:
	return maxi(2, int(population_limit / 10))


static func get_easy_pressure_squad_size(game_time: float) -> int:
	return 2 if game_time < EASY_LARGER_SQUAD_SECONDS else 3


static func get_new_worker_weights(age: int) -> Dictionary:
	return DARK_AGE_WORKER_WEIGHTS if age < 2 else FEUDAL_WORKER_WEIGHTS


static func get_age_up_cost(target_age: int, population_limit: int, mode: int = MatchMode.STANDARD) -> Dictionary:
	if mode != MatchMode.STANDARD and target_age == 2:
		return {"food": 250, "gold": 125}
	var base_cost: Dictionary = AGE_UP_COSTS.get(target_age, {})
	var cost: Dictionary = {}
	# The existing 40-pop economy remains the reference. Legacy large match
	# fixtures retain their costs; only the smaller mobile budgets scale down.
	var scale: float = minf(1.0, float(population_limit) / float(REFERENCE_POPULATION_LIMIT))
	for resource: String in base_cost:
		cost[resource] = int(roundf(float(base_cost[resource]) * scale))
	if target_age == 2 and not cost.is_empty():
		# Even the smallest duel must gather beyond its starting stock before
		# advancing; otherwise Feudal is available the instant the match starts.
		cost["food"] = maxi(250, int(cost.get("food", 0)))
		cost["gold"] = maxi(125, int(cost.get("gold", 0)))
	return cost
