class_name SkirmishData
extends RefCounted
## Small skirmish budgets for comparing mobile economy and army sizes.
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
		MatchMode.QUICK_CONTROL: return 240.0
	return SACRED_VICTORY_HOLD_SECONDS


const POPULATION_OPTIONS: Array[int] = [20, 30, 40]
const DEFAULT_POPULATION_LIMIT: int = 30
const REFERENCE_POPULATION_LIMIT: int = 40
## Castle unlocks the siege endgame. Imperial has no skirmish content yet.
const MAX_AGE: int = 3
const AGE_NAMES: Array[String] = ["Dark Age", "Feudal Age", "Castle Age"]
const SACRED_VICTORY_HOLD_SECONDS: float = 240.0
# Both players fund their first House and nearby drop-off from this bank, then
# must gather wood before opening military production.
const STARTING_RESOURCES: Dictionary = {"food": 200, "wood": 150, "gold": 100}
# Difficulty changes planning time, never costs, income or unit strength.
# Defense and a live Sacred contest remain immediate during these raid delays.
const AI_RAID_START_SECONDS: Dictionary = {0: 360.0, 1: 240.0, 2: 0.0}
const AI_RAID_COOLDOWN_SECONDS: Dictionary = {0: 120.0, 1: 75.0, 2: 0.0}
const DARK_AGE_WORKER_WEIGHTS: Dictionary = {"food": 0.55, "wood": 0.35, "gold": 0.10}
const FEUDAL_WORKER_WEIGHTS: Dictionary = {"food": 0.55, "wood": 0.40, "gold": 0.05}
const AGE_UP_COSTS: Dictionary = {
	2: {"food": 400, "gold": 200},
	3: {"food": 1200, "gold": 600},
}


static func normalize_population_limit(value: int) -> int:
	return value if value in POPULATION_OPTIONS else DEFAULT_POPULATION_LIMIT


static func get_economy_target(population_limit: int) -> int:
	return maxi(4, int(population_limit / 2))


static func get_easy_economy_target(population_limit: int) -> int:
	return maxi(4, int(population_limit * 2 / 5))


static func get_easy_fighter_target(population_limit: int) -> int:
	return maxi(3, int(population_limit * 3 / 10))


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
