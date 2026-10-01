class_name SkirmishData
extends RefCounted
## Small skirmish budgets for comparing mobile economy and army sizes.
## Population counts workers and troops; cavalry/siege can consume extra slots.

const POPULATION_OPTIONS: Array[int] = [20, 30, 40]
const DEFAULT_POPULATION_LIMIT: int = 30
const REFERENCE_POPULATION_LIMIT: int = 40
const SACRED_VICTORY_HOLD_SECONDS: float = 600.0
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


static func get_age_up_cost(target_age: int, population_limit: int) -> Dictionary:
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
