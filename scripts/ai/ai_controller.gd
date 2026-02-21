class_name AIController
extends Node
## Main AI brain for a computer-controlled player.
##
## Runs a decision loop on a timer that mirrors the same systems a human
## player uses: ResourceManager for spending, GameManager for population
## and age-up, unit commands for movement/attack, and BuildingData costs
## for construction. NO cheating — the AI has the same resources, vision,
## and unit stats as a human player.

signal ai_wants_to_build(building_type: int, tile_pos: Vector2i)
signal ai_wants_to_train(building: Node, unit_type: int)
signal ai_wants_to_age_up()
signal ai_attack_launched(units: Array, target_pos: Vector2)

# ── Difficulty ───────────────────────────────────────────────────────────
enum Difficulty { EASY, MEDIUM, HARD }
enum AIState { EARLY_GAME, MID_GAME, LATE_GAME }

@export var difficulty: Difficulty = Difficulty.MEDIUM
@export var player_id: int = 1  # AI is player 1 by default
@export var enemy_id: int = 0   # Human is player 0

# ── Decision timer ───────────────────────────────────────────────────────
var _decision_timer: Timer
var _decision_interval: float = 1.5

# ── Game phase ───────────────────────────────────────────────────────────
var _ai_state: AIState = AIState.EARLY_GAME

# ── References set from main scene ───────────────────────────────────────
var map_generator: MapGenerator = null
var pathfinding: Pathfinding = null
var game_map: Node2D = null

# ── Tracking ─────────────────────────────────────────────────────────────
var _my_buildings: Array = []  # BuildingBase references
var _my_units: Array = []      # UnitBase references
var _base_position: Vector2 = Vector2.ZERO  # Town Center world position
var _base_tile: Vector2i = Vector2i.ZERO    # TC tile coord

# Army staging
var _staging_point: Vector2 = Vector2.ZERO
var _attack_in_progress: bool = false
var _retreat_threshold: float = 0.3  # Pull back if army drops below 30%
var _game_time: float = 0.0  # Track elapsed time for timed aggression
var _last_harass_time: float = 0.0  # Cooldown for harassment raids
var _scout_trained: bool = false  # Track if we've trained a scout
var _income_accumulator: Dictionary = { "food": 0.0, "wood": 0.0, "gold": 0.0 }

# Build-order tracking (what we have built so far)
var _town_center_count: int = 0
var _house_count: int = 0
var _barracks_count: int = 0
var _archery_range_count: int = 0
var _stable_count: int = 0
var _lumber_camp_count: int = 0
var _mining_camp_count: int = 0
var _mill_count: int = 0
var _farm_count: int = 0
var _siege_workshop_count: int = 0
var _blacksmith_count: int = 0
var _watch_tower_count: int = 0
var _is_under_pressure: bool = false
var _pressure_memory: float = 0.0
var _saving_for_age_up: bool = false

# ── Difficulty tuning tables ─────────────────────────────────────────────
const DECISION_INTERVALS: Dictionary = {
	Difficulty.EASY: 2.0,
	Difficulty.MEDIUM: 1.5,
	Difficulty.HARD: 1.0,
}

const VILLAGER_TARGETS: Dictionary = {
	Difficulty.EASY: 12,
	Difficulty.MEDIUM: 18,
	Difficulty.HARD: 22,
}

const ARMY_ATTACK_THRESHOLDS: Dictionary = {
	Difficulty.EASY: 6,
	Difficulty.MEDIUM: 8,
	Difficulty.HARD: 5,
}

## Passive resource income per second by difficulty (food, wood, gold).
## Simulates the AI's faster macro and fewer micro mistakes.
const DIFFICULTY_INCOME: Dictionary = {
	Difficulty.EASY: 0.0,
	Difficulty.MEDIUM: 1.0,
	Difficulty.HARD: 2.5,
}

## Bonus starting resources by difficulty.
const DIFFICULTY_START_BONUS: Dictionary = {
	Difficulty.EASY: 0,
	Difficulty.MEDIUM: 50,
	Difficulty.HARD: 150,
}

const PRESSURE_MEMORY_SECONDS: float = 8.0

const AGE_UP_COSTS: Dictionary = {
	2: {"food": 400, "gold": 200},
	3: {"food": 1200, "gold": 600},
}

const AGE_UP_TARGET_TIMES: Dictionary = {
	Difficulty.EASY: 285.0,
	Difficulty.MEDIUM: 225.0,
	Difficulty.HARD: 170.0,
}

const AGE_UP_RESERVE_THRESHOLDS: Dictionary = {
	Difficulty.EASY: 0.72,
	Difficulty.MEDIUM: 0.62,
	Difficulty.HARD: 0.52,
}

const AGE_UP_MIN_VILLAGERS: Dictionary = {
	Difficulty.EASY: {2: 11, 3: 18},
	Difficulty.MEDIUM: {2: 9, 3: 16},
	Difficulty.HARD: {2: 7, 3: 14},
}

const AGE_UP_MIN_MILITARY: Dictionary = {
	Difficulty.EASY: {2: 1, 3: 4},
	Difficulty.MEDIUM: {2: 1, 3: 5},
	Difficulty.HARD: {2: 0, 3: 5},
}


func _ready() -> void:
	_decision_interval = DECISION_INTERVALS.get(difficulty, 1.5)
	_setup_timer()


func _process(delta: float) -> void:
	if GameManager.current_state == GameManager.GameState.PLAYING:
		_game_time += delta
		# Passive resource income for Medium/Hard difficulty
		var income: float = DIFFICULTY_INCOME.get(difficulty, 0.0)
		if income > 0.0:
			_income_accumulator["food"] += income * delta * 2.0
			_income_accumulator["wood"] += income * delta * 1.5
			_income_accumulator["gold"] += income * delta
			var rm: Node = get_node_or_null("/root/ResourceManager")
			if rm:
				for res_type in _income_accumulator:
					var whole: int = int(_income_accumulator[res_type])
					if whole >= 1:
						rm.add_resource(player_id, res_type, whole)
						_income_accumulator[res_type] -= float(whole)


func _setup_timer() -> void:
	_decision_timer = Timer.new()
	_decision_timer.wait_time = _decision_interval
	_decision_timer.one_shot = false
	_decision_timer.timeout.connect(_on_decision_tick)
	add_child(_decision_timer)


## Call this once the game scene is ready and the TC is placed.
func start_ai(base_tile: Vector2i, base_world_pos: Vector2) -> void:
	_base_tile = base_tile
	_base_position = base_world_pos
	# Staging point is a short distance in front of our base toward map center
	var center := Vector2(
		MapData.MAP_WIDTH / 2.0 * MapData.TILE_WIDTH,
		MapData.MAP_HEIGHT / 2.0 * MapData.TILE_HEIGHT
	)
	_staging_point = _base_position.lerp(center, 0.25)
	_decision_timer.start()
	# Apply difficulty starting bonus
	var bonus: int = DIFFICULTY_START_BONUS.get(difficulty, 0)
	if bonus > 0:
		var rm: Node = get_node_or_null("/root/ResourceManager")
		if rm:
			rm.add_resource(player_id, "food", bonus)
			rm.add_resource(player_id, "wood", bonus)
			rm.add_resource(player_id, "gold", int(bonus * 0.5))


## Register a building the AI owns (called by main scene when build completes).
func register_building(building: Node) -> void:
	if building not in _my_buildings:
		_my_buildings.append(building)
		_update_building_counts()


## Register a unit the AI owns (called when a unit is spawned for this player).
func register_unit(unit: Node) -> void:
	if unit not in _my_units:
		_my_units.append(unit)
		if unit.has_signal("unit_died"):
			unit.unit_died.connect(_on_unit_died)


func _on_unit_died(unit: UnitBase) -> void:
	_my_units.erase(unit)


# ═════════════════════════════════════════════════════════════════════════
#  MAIN DECISION LOOP
# ═════════════════════════════════════════════════════════════════════════

func _on_decision_tick() -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if not GameManager.players.has(player_id):
		return
	if GameManager.players[player_id].get("is_defeated", false):
		_decision_timer.stop()
		return

	# Clean stale references
	_cleanup_references()

	# Update game phase
	_update_ai_state()
	_update_pressure_state()
	_update_age_up_reserve()

	# Run decision tree in priority order
	_check_villager_production()
	_check_house_need()
	_assign_idle_villagers()
	_check_age_up()
	_check_building_construction()
	_check_military_production()
	_check_research()
	_check_scouting()
	_check_attack_or_defend()


# ═════════════════════════════════════════════════════════════════════════
#  PHASE MANAGEMENT
# ═════════════════════════════════════════════════════════════════════════

func _update_ai_state() -> void:
	var age: int = GameManager.get_player_age(player_id)
	var military_count: int = _get_military_units().size()

	if age >= 3 or military_count >= 20:
		_ai_state = AIState.LATE_GAME
	elif age >= 2 or military_count >= 5:
		_ai_state = AIState.MID_GAME
	else:
		_ai_state = AIState.EARLY_GAME


func _update_pressure_state() -> void:
	var enemy_pressure_strength: float = 0.0
	var enemy_nearby_count: int = 0
	for enemy in _get_visible_enemies():
		if enemy.global_position.distance_to(_base_position) > 240.0:
			continue
		enemy_nearby_count += 1
		if enemy is UnitBase:
			enemy_pressure_strength += enemy.hp * enemy.damage

	var own_strength: float = maxf(1.0, _evaluate_army_strength())
	var pressure_now: bool = enemy_nearby_count >= 2 or enemy_pressure_strength > own_strength * 0.65
	if pressure_now:
		_pressure_memory = PRESSURE_MEMORY_SECONDS
	else:
		_pressure_memory = maxf(0.0, _pressure_memory - _decision_interval)
	_is_under_pressure = _pressure_memory > 0.0


func _update_age_up_reserve() -> void:
	var age: int = GameManager.get_player_age(player_id)
	if age >= GameManager.MAX_AGE:
		_saving_for_age_up = false
		return

	var target_age: int = age + 1
	var cost: Dictionary = AGE_UP_COSTS.get(target_age, {})
	if cost.is_empty():
		_saving_for_age_up = false
		return

	var resources: Dictionary = ResourceManager.get_all_resources(player_id)
	var completion: float = _resource_completion_ratio(resources, cost)
	var reserve_threshold: float = AGE_UP_RESERVE_THRESHOLDS.get(difficulty, 0.62)
	var target_time: float = _get_age_up_target_time(target_age)
	if target_age == 2 and _game_time >= target_time - 45.0:
		reserve_threshold = maxf(0.45, reserve_threshold - 0.18)
	if _is_under_pressure:
		reserve_threshold += 0.08

	var military_count: int = _get_military_units().size()
	var military_gate: int = _get_min_military_for_age_up(target_age)
	if _is_under_pressure:
		military_gate += 1
	if target_age == 2 and _game_time >= target_time:
		military_gate = maxi(0, military_gate - 1)
	_saving_for_age_up = completion >= reserve_threshold and military_count >= military_gate


# ═════════════════════════════════════════════════════════════════════════
#  VILLAGER PRODUCTION
# ═════════════════════════════════════════════════════════════════════════

func _check_villager_production() -> void:
	var villagers: Array = _get_villagers()
	var target: int = _get_target_villager_count()

	if villagers.size() >= target:
		return

	# Check pop room
	var player_data: Dictionary = GameManager.players.get(player_id, {})
	var pop: int = player_data.get("population", 0)
	var cap: int = player_data.get("population_cap", 5)
	if pop >= cap:
		return  # Need houses first

	# Find the least busy Town Center to train from.
	var tc: Node = _find_trainable_building_of_type(BuildingData.BuildingType.TOWN_CENTER)
	if tc == null:
		return

	var cost: Dictionary = UnitData.get_unit_cost(UnitData.UnitType.VILLAGER)
	if ResourceManager.can_afford(player_id, cost):
		ai_wants_to_train.emit(tc, UnitData.UnitType.VILLAGER)


# ═════════════════════════════════════════════════════════════════════════
#  HOUSE CHECK — build if population is close to cap
# ═════════════════════════════════════════════════════════════════════════

func _check_house_need() -> void:
	var player_data: Dictionary = GameManager.players.get(player_id, {})
	var pop: int = player_data.get("population", 0)
	var cap: int = player_data.get("population_cap", 5)

	# Build a house when within 2 pop of cap
	if pop < cap - 2:
		return
	if _house_count >= 12:
		return

	var cost: Dictionary = BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE)
	if ResourceManager.can_afford(player_id, cost):
		var pos: Vector2i = _find_build_location(BuildingData.BuildingType.HOUSE)
		if pos != Vector2i(-1, -1):
			ai_wants_to_build.emit(BuildingData.BuildingType.HOUSE, pos)


# ═════════════════════════════════════════════════════════════════════════
#  IDLE VILLAGER ASSIGNMENT
# ═════════════════════════════════════════════════════════════════════════

func _assign_idle_villagers() -> void:
	var idle: Array = _get_idle_villagers()
	if idle.is_empty():
		return

	# Figure out current resource ratios vs desired
	var resources: Dictionary = ResourceManager.get_all_resources(player_id)
	var total: float = float(resources.get("food", 0) + resources.get("wood", 0) + resources.get("gold", 0))
	if total < 1.0:
		total = 1.0
	var target_ratio: Dictionary = _get_target_resource_ratio()

	# Determine which resource is most below target ratio
	var deficits: Dictionary = {}
	for res_type in target_ratio:
		var current_ratio: float = float(resources.get(res_type, 0)) / total
		deficits[res_type] = target_ratio[res_type] - current_ratio

	# Sort by largest deficit
	var priority: Array = ["food", "wood", "gold"]
	priority.sort_custom(func(a: String, b: String) -> bool:
		return deficits.get(a, 0.0) > deficits.get(b, 0.0)
	)

	# Assign each idle villager to the most needed resource
	for villager in idle:
		var assigned: bool = false
		for res_type in priority:
			var resource_node: Node2D = _find_nearest_resource_node(res_type, villager.global_position)
			if resource_node != null:
				_assign_villager_to_resource(villager, resource_node)
				assigned = true
				break
		# If no resource found, move toward base
		if not assigned:
			villager.command_move(_base_position)


# ═════════════════════════════════════════════════════════════════════════
#  BUILDING CONSTRUCTION
# ═════════════════════════════════════════════════════════════════════════

func _check_building_construction() -> void:
	var age: int = GameManager.get_player_age(player_id)
	var target_counts: Dictionary = _get_target_building_counts(age)
	var build_order: Array = _get_build_order(age)

	for b_type in build_order:
		var b_stats: Dictionary = BuildingData.get_building_stats(b_type)
		var req_age: int = b_stats.get("age_required", 0)
		if age < req_age:
			continue

		var max_count: int = target_counts.get(b_type, 0)
		if max_count <= 0:
			continue

		var current_count: int = _get_building_count(b_type)
		if current_count >= max_count:
			continue

		if _saving_for_age_up and not _is_essential_building_while_saving(b_type):
			continue

		var cost: Dictionary = BuildingData.get_building_cost(b_type)
		if not ResourceManager.can_afford(player_id, cost):
			continue

		var pos: Vector2i = _find_build_location(b_type)
		if pos == Vector2i(-1, -1):
			continue

		ai_wants_to_build.emit(b_type, pos)
		return  # Only build one thing per tick to stay responsive


# ═════════════════════════════════════════════════════════════════════════
#  MILITARY PRODUCTION
# ═════════════════════════════════════════════════════════════════════════

func _check_military_production() -> void:
	var military_count: int = _get_military_units().size()
	if _ai_state == AIState.EARLY_GAME and not _is_under_pressure and military_count >= 5:
		return  # In early game, cap military production

	if _saving_for_age_up and not _is_under_pressure and military_count >= 4:
		return

	# Train a scout early for scouting
	if not _scout_trained:
		var tc: Node = _find_trainable_building_of_type(BuildingData.BuildingType.TOWN_CENTER)
		if tc:
			var cost: Dictionary = UnitData.get_unit_cost(UnitData.UnitType.SCOUT)
			if ResourceManager.can_afford(player_id, cost):
				ai_wants_to_train.emit(tc, UnitData.UnitType.SCOUT)
				_scout_trained = true
				return

	var resources: Dictionary = ResourceManager.get_all_resources(player_id)
	var training_plan: Array = _get_military_training_plan(resources)
	var trains_allowed: int = 2 if _is_under_pressure else 1
	var trains_done: int = 0

	for unit_type in training_plan:
		var building_type: int = _get_training_building_type_for_unit(unit_type)
		if building_type < 0:
			continue
		if _try_train_from_building(building_type, unit_type):
			trains_done += 1
			if trains_done >= trains_allowed:
				break


func _try_train_from_building(building_type: int, unit_type: int) -> bool:
	var building: Node = _find_trainable_building_of_type(building_type)
	if building == null:
		return false

	# Check pop room
	var player_data: Dictionary = GameManager.players.get(player_id, {})
	var pop: int = player_data.get("population", 0)
	var cap: int = player_data.get("population_cap", 5)
	var pop_cost: int = UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1)
	if pop + pop_cost > cap:
		return false

	var cost: Dictionary = UnitData.get_unit_cost(unit_type)
	if ResourceManager.can_afford(player_id, cost):
		ai_wants_to_train.emit(building, unit_type)
		return true
	return false


# ═════════════════════════════════════════════════════════════════════════
#  AGE UP
# ═════════════════════════════════════════════════════════════════════════

func _check_age_up() -> void:
	var age: int = GameManager.get_player_age(player_id)
	if age >= GameManager.MAX_AGE:
		_saving_for_age_up = false
		return

	var target_age: int = age + 1
	var cost: Dictionary = AGE_UP_COSTS.get(target_age, {})
	if cost.is_empty():
		_saving_for_age_up = false
		return

	var resources: Dictionary = ResourceManager.get_all_resources(player_id)
	var completion: float = _resource_completion_ratio(resources, cost)
	var timing_target: float = _get_age_up_target_time(target_age)
	var min_villagers_to_age: int = _get_min_villagers_for_age_up(target_age)
	var min_military: int = _get_min_military_for_age_up(target_age)
	if _is_under_pressure:
		min_villagers_to_age += 1
		min_military += 1

	if target_age == 2 and _game_time >= timing_target:
		min_villagers_to_age = maxi(8, min_villagers_to_age - 2)
		min_military = maxi(0, min_military - 1)

	if _get_villagers().size() < min_villagers_to_age:
		_saving_for_age_up = false
		return

	var military_count: int = _get_military_units().size()
	if military_count < min_military:
		var allow_feudal_fallback: bool = (
			target_age == 2
			and completion >= 0.95
			and _game_time >= timing_target - 20.0
		)
		if not allow_feudal_fallback:
			return

	if ResourceManager.can_afford(player_id, cost):
		_saving_for_age_up = false
		ai_wants_to_age_up.emit()


func _get_age_up_target_time(target_age: int) -> float:
	if target_age != 2:
		return INF
	return AGE_UP_TARGET_TIMES.get(difficulty, 225.0)


func _get_min_villagers_for_age_up(target_age: int) -> int:
	var by_age: Dictionary = AGE_UP_MIN_VILLAGERS.get(difficulty, {})
	var fallback: int = 10 if target_age == 2 else 16
	return int(by_age.get(target_age, fallback))


func _get_min_military_for_age_up(target_age: int) -> int:
	var by_age: Dictionary = AGE_UP_MIN_MILITARY.get(difficulty, {})
	var fallback: int = 1 if target_age == 2 else 5
	return int(by_age.get(target_age, fallback))


func _resource_completion_ratio(resources: Dictionary, cost: Dictionary) -> float:
	var total: float = 0.0
	var achieved: float = 0.0
	for res_type in cost:
		var needed: float = float(cost[res_type])
		if needed <= 0.0:
			continue
		total += needed
		achieved += minf(needed, float(resources.get(res_type, 0)))
	if total <= 0.0:
		return 1.0
	return achieved / total


func _get_target_villager_count() -> int:
	var base_target: int = VILLAGER_TARGETS.get(difficulty, 18)
	var age: int = GameManager.get_player_age(player_id)
	if age >= 2:
		base_target += 2
	if age >= 3:
		base_target += 4
	if _is_under_pressure:
		base_target = maxi(10, base_target - 3)
	return base_target


func _get_target_resource_ratio() -> Dictionary:
	var age: int = GameManager.get_player_age(player_id)
	if _is_under_pressure:
		return {"food": 0.45, "wood": 0.35, "gold": 0.20}
	if _saving_for_age_up and age == 1:
		match difficulty:
			Difficulty.EASY:
				return {"food": 0.62, "wood": 0.22, "gold": 0.16}
			Difficulty.MEDIUM:
				return {"food": 0.58, "wood": 0.20, "gold": 0.22}
			Difficulty.HARD:
				return {"food": 0.54, "wood": 0.18, "gold": 0.28}
	if _saving_for_age_up and age == 2:
		return {"food": 0.56, "wood": 0.14, "gold": 0.30}
	if age <= 1:
		return {"food": 0.5, "wood": 0.35, "gold": 0.15}
	if age == 2:
		return {"food": 0.4, "wood": 0.3, "gold": 0.3}
	return {"food": 0.35, "wood": 0.3, "gold": 0.35}


func _get_target_building_counts(age: int) -> Dictionary:
	var villagers: int = _get_villagers().size()
	var farm_target: int = clampi(villagers / 4, 2, 12)
	if age <= 1:
		farm_target = clampi(villagers / 6, 1, 4)
	if _saving_for_age_up and age <= 1:
		farm_target = clampi(villagers / 8, 0, 2)
	if _is_under_pressure:
		farm_target = maxi(1, farm_target)

	var targets: Dictionary = {
		BuildingData.BuildingType.HOUSE: 12,
		BuildingData.BuildingType.MILL: 1 if age <= 2 else 2,
		BuildingData.BuildingType.LUMBER_CAMP: 1 if age <= 1 else 2,
		BuildingData.BuildingType.MINING_CAMP: 1 if age <= 2 else 2,
		BuildingData.BuildingType.FARM: farm_target,
		BuildingData.BuildingType.BARRACKS: 1 if age <= 1 else 2,
		BuildingData.BuildingType.ARCHERY_RANGE: 0 if age < 2 else 1,
		BuildingData.BuildingType.STABLE: 0 if age < 2 else 1,
		BuildingData.BuildingType.BLACKSMITH: 1 if age >= 2 else 0,
		BuildingData.BuildingType.WATCH_TOWER: 0 if age < 2 else 1,
		BuildingData.BuildingType.SIEGE_WORKSHOP: 0 if age < 3 else 1,
		BuildingData.BuildingType.TOWN_CENTER: 1,
	}

	if age >= 3 and villagers >= 18 and not _is_under_pressure:
		targets[BuildingData.BuildingType.TOWN_CENTER] = 2
	if difficulty == Difficulty.HARD and age >= 3:
		targets[BuildingData.BuildingType.ARCHERY_RANGE] = maxi(targets[BuildingData.BuildingType.ARCHERY_RANGE], 2)
		targets[BuildingData.BuildingType.STABLE] = maxi(targets[BuildingData.BuildingType.STABLE], 2)
	if _is_under_pressure:
		targets[BuildingData.BuildingType.BARRACKS] = maxi(targets[BuildingData.BuildingType.BARRACKS], 2)
		if age >= 2:
			targets[BuildingData.BuildingType.WATCH_TOWER] = 2
			targets[BuildingData.BuildingType.ARCHERY_RANGE] = maxi(targets[BuildingData.BuildingType.ARCHERY_RANGE], 1)
		targets[BuildingData.BuildingType.MILL] = 1
		targets[BuildingData.BuildingType.TOWN_CENTER] = 1
	return targets


func _get_build_order(age: int) -> Array:
	if _is_under_pressure:
		return [
			BuildingData.BuildingType.HOUSE,
			BuildingData.BuildingType.MILL,
			BuildingData.BuildingType.BARRACKS,
			BuildingData.BuildingType.WATCH_TOWER,
			BuildingData.BuildingType.LUMBER_CAMP,
			BuildingData.BuildingType.MINING_CAMP,
			BuildingData.BuildingType.FARM,
			BuildingData.BuildingType.ARCHERY_RANGE,
			BuildingData.BuildingType.STABLE,
			BuildingData.BuildingType.BLACKSMITH,
			BuildingData.BuildingType.SIEGE_WORKSHOP,
			BuildingData.BuildingType.TOWN_CENTER,
		]
	if age >= 3:
		return [
			BuildingData.BuildingType.HOUSE,
			BuildingData.BuildingType.MILL,
			BuildingData.BuildingType.LUMBER_CAMP,
			BuildingData.BuildingType.MINING_CAMP,
			BuildingData.BuildingType.FARM,
			BuildingData.BuildingType.BARRACKS,
			BuildingData.BuildingType.ARCHERY_RANGE,
			BuildingData.BuildingType.STABLE,
			BuildingData.BuildingType.BLACKSMITH,
			BuildingData.BuildingType.SIEGE_WORKSHOP,
			BuildingData.BuildingType.TOWN_CENTER,
			BuildingData.BuildingType.WATCH_TOWER,
		]
	return [
		BuildingData.BuildingType.HOUSE,
		BuildingData.BuildingType.MILL,
		BuildingData.BuildingType.LUMBER_CAMP,
		BuildingData.BuildingType.MINING_CAMP,
		BuildingData.BuildingType.FARM,
		BuildingData.BuildingType.BARRACKS,
		BuildingData.BuildingType.BLACKSMITH,
		BuildingData.BuildingType.ARCHERY_RANGE,
		BuildingData.BuildingType.STABLE,
		BuildingData.BuildingType.WATCH_TOWER,
	]


func _is_essential_building_while_saving(building_type: int) -> bool:
	if building_type == BuildingData.BuildingType.HOUSE:
		return true
	if building_type == BuildingData.BuildingType.LUMBER_CAMP:
		return true
	if building_type == BuildingData.BuildingType.MINING_CAMP:
		return true
	if building_type == BuildingData.BuildingType.MILL:
		return true
	if building_type == BuildingData.BuildingType.FARM:
		return true
	return _is_under_pressure and building_type == BuildingData.BuildingType.WATCH_TOWER


func _get_military_training_plan(resources: Dictionary) -> Array:
	var plan: Array = []
	if _is_under_pressure:
		plan = [
			UnitData.UnitType.INFANTRY,
			UnitData.UnitType.INFANTRY,
			UnitData.UnitType.ARCHER,
			UnitData.UnitType.CAVALRY,
		]
	elif _ai_state == AIState.EARLY_GAME:
		plan = [UnitData.UnitType.INFANTRY, UnitData.UnitType.INFANTRY]
	elif _ai_state == AIState.MID_GAME:
		plan = [UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY]
	else:
		plan = [UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY, UnitData.UnitType.SIEGE]

	var food: int = resources.get("food", 0)
	var wood: int = resources.get("wood", 0)
	var gold: int = resources.get("gold", 0)
	var filtered: Array = []
	for unit_type in plan:
		if unit_type == UnitData.UnitType.ARCHER and wood < 45:
			continue
		if unit_type == UnitData.UnitType.CAVALRY and gold < 40:
			continue
		if unit_type == UnitData.UnitType.SIEGE and (wood < 150 or gold < 100):
			continue
		filtered.append(unit_type)
	if filtered.is_empty():
		filtered.append(UnitData.UnitType.INFANTRY)
	if _ai_state == AIState.LATE_GAME and wood >= 220 and gold >= 130:
		filtered.append(UnitData.UnitType.SIEGE)
	return filtered


func _get_training_building_type_for_unit(unit_type: int) -> int:
	match unit_type:
		UnitData.UnitType.INFANTRY:
			return BuildingData.BuildingType.BARRACKS
		UnitData.UnitType.ARCHER:
			return BuildingData.BuildingType.ARCHERY_RANGE
		UnitData.UnitType.CAVALRY:
			return BuildingData.BuildingType.STABLE
		UnitData.UnitType.SIEGE:
			return BuildingData.BuildingType.SIEGE_WORKSHOP
	return -1


# ═════════════════════════════════════════════════════════════════════════
#  RESEARCH (Blacksmith upgrades)
# ═════════════════════════════════════════════════════════════════════════

func _check_research() -> void:
	if _blacksmith_count == 0:
		return
	if _saving_for_age_up and not _is_under_pressure:
		return

	# Research forging first, then scale mail
	var research_order: Array = [
		{"id": "forging", "cost": {"food": 100, "gold": 50}, "type": "attack", "amount": 2},
		{"id": "scale_mail", "cost": {"food": 100, "gold": 50}, "type": "armor", "amount": 1},
	]

	for r in research_order:
		if GameManager.has_research(player_id, r["id"]):
			continue
		if ResourceManager.can_afford(player_id, r["cost"]):
			ResourceManager.try_spend(player_id, r["cost"])
			GameManager.complete_research(player_id, r["id"])
			if r["type"] == "attack":
				GameManager.apply_attack_upgrade(player_id, r["amount"])
			elif r["type"] == "armor":
				GameManager.apply_armor_upgrade(player_id, r["amount"])
			return  # One research per tick


# ═════════════════════════════════════════════════════════════════════════
#  SCOUTING
# ═════════════════════════════════════════════════════════════════════════

func _check_scouting() -> void:
	# Find idle scouts and send them to explore
	for unit in _my_units:
		if not is_instance_valid(unit) or not (unit is UnitBase):
			continue
		if unit.unit_type != UnitData.UnitType.SCOUT:
			continue
		if unit.current_state != UnitBase.State.IDLE:
			continue
		# Send to a random point biased toward enemy half of map
		var target := Vector2(
			randf_range(0.0, MapData.MAP_WIDTH * MapData.TILE_WIDTH),
			randf_range(0.0, MapData.MAP_HEIGHT * MapData.TILE_HEIGHT)
		)
		unit.command_move(target)


# ═════════════════════════════════════════════════════════════════════════
#  ATTACK / DEFENSE
# ═════════════════════════════════════════════════════════════════════════

func _check_attack_or_defend() -> void:
	# Check if under attack first
	if _is_base_under_attack():
		_rally_defense()
		return

	# Evaluate army strength
	var military: Array = _get_military_units()
	var threshold: int = ARMY_ATTACK_THRESHOLDS.get(difficulty, 8)

	if _attack_in_progress:
		# Check if we should retreat
		if military.size() < maxi(2, int(threshold * _retreat_threshold)):
			_retreat_army()
			_attack_in_progress = false
		return

	# Gather idle military at staging point
	var idle_military: Array = _get_idle_military()
	for unit in idle_military:
		if unit.global_position.distance_to(_staging_point) > 64.0:
			unit.command_move(_staging_point)

	# Timed aggression: force attack after 3 minutes even with small army
	var force_attack_time: float = 180.0
	match difficulty:
		Difficulty.EASY: force_attack_time = 300.0
		Difficulty.MEDIUM: force_attack_time = 180.0
		Difficulty.HARD: force_attack_time = 120.0

	var force_attack: bool = _game_time >= force_attack_time and military.size() >= 3

	# Launch full attack if army is strong enough or timed threshold reached
	if military.size() >= threshold or force_attack:
		var target: Vector2 = _find_enemy_target()
		if target != Vector2(-1, -1):
			_send_attack(military, target)
			_attack_in_progress = true
		return

	# Harassment raids: send small groups to pressure the enemy
	var harass_cooldown: float = 60.0 if difficulty == Difficulty.HARD else 90.0
	if military.size() >= 3 and _game_time - _last_harass_time > harass_cooldown:
		# Send 2-3 units as a raiding party
		var raid_size: int = mini(3, military.size())
		var raiders: Array = idle_military.slice(0, raid_size)
		if raiders.size() >= 2:
			var target: Vector2 = _find_enemy_target()
			if target != Vector2(-1, -1):
				for unit in raiders:
					if unit.has_method("command_attack_move"):
						unit.command_attack_move(target)
				_last_harass_time = _game_time


func _is_base_under_attack() -> bool:
	var enemies: Array = _get_visible_enemies()
	for enemy in enemies:
		if enemy.global_position.distance_to(_base_position) < 200.0:
			return true
	return false


func _rally_defense() -> void:
	var military: Array = _get_military_units()
	var enemies: Array = _get_visible_enemies()
	if enemies.is_empty():
		return

	# Sort enemies by distance to base
	enemies.sort_custom(func(a: Node, b: Node) -> bool:
		return a.global_position.distance_to(_base_position) < b.global_position.distance_to(_base_position)
	)

	# Distribute military units across enemies (focus fire but not all on one)
	for i in military.size():
		var unit: UnitBase = military[i]
		var enemy_idx: int = i % enemies.size()
		var target_enemy: Node = enemies[enemy_idx]
		if target_enemy is UnitBase:
			unit.command_attack(target_enemy)
		elif target_enemy is BuildingBase:
			unit.command_attack_building(target_enemy)

	# Pull idle villagers back to TC
	for villager in _get_idle_villagers():
		villager.command_move(_base_position)


func _retreat_army() -> void:
	var military: Array = _get_military_units()
	for unit in military:
		unit.command_move(_staging_point)


func _send_attack(units: Array, target: Vector2) -> void:
	for unit in units:
		if unit.has_method("command_attack_move"):
			unit.command_attack_move(target)
		else:
			unit.command_move(target)
	ai_attack_launched.emit(units, target)


func _find_enemy_target() -> Vector2:
	## Try to find an enemy building or unit to attack.
	## Target priority: military > production buildings > town center.
	## Uses only visible information (units the AI has seen).

	# Look for visible enemy units first
	var enemies: Array = _get_visible_enemies()
	if not enemies.is_empty():
		# Target the cluster center
		var avg_pos := Vector2.ZERO
		for e in enemies:
			avg_pos += e.global_position
		return avg_pos / float(enemies.size())

	# Fall back to enemy spawn position (known from map symmetry)
	if map_generator and map_generator.spawn_positions.size() > enemy_id:
		var spawn: Vector2i = map_generator.spawn_positions[enemy_id]
		return Vector2(
			spawn.x * MapData.TILE_WIDTH + MapData.TILE_WIDTH / 2.0,
			spawn.y * MapData.TILE_HEIGHT + MapData.TILE_HEIGHT / 2.0
		)

	return Vector2(-1, -1)


# ═════════════════════════════════════════════════════════════════════════
#  HELPER FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════

func _cleanup_references() -> void:
	_my_units = _my_units.filter(func(u: Node) -> bool:
		return is_instance_valid(u) and u.is_inside_tree()
	)
	_my_buildings = _my_buildings.filter(func(b: Node) -> bool:
		return is_instance_valid(b) and b.is_inside_tree()
	)
	_update_building_counts()


func _update_building_counts() -> void:
	_town_center_count = 0
	_house_count = 0
	_barracks_count = 0
	_archery_range_count = 0
	_stable_count = 0
	_lumber_camp_count = 0
	_mining_camp_count = 0
	_mill_count = 0
	_farm_count = 0
	_siege_workshop_count = 0
	_blacksmith_count = 0
	_watch_tower_count = 0

	for b in _my_buildings:
		if not is_instance_valid(b):
			continue
		if not b.has_method("get_building_type") and not ("building_type" in b):
			continue
		var btype: int = b.building_type if "building_type" in b else -1
		match btype:
			BuildingData.BuildingType.TOWN_CENTER: _town_center_count += 1
			BuildingData.BuildingType.HOUSE: _house_count += 1
			BuildingData.BuildingType.BARRACKS: _barracks_count += 1
			BuildingData.BuildingType.ARCHERY_RANGE: _archery_range_count += 1
			BuildingData.BuildingType.STABLE: _stable_count += 1
			BuildingData.BuildingType.LUMBER_CAMP: _lumber_camp_count += 1
			BuildingData.BuildingType.MINING_CAMP: _mining_camp_count += 1
			BuildingData.BuildingType.MILL: _mill_count += 1
			BuildingData.BuildingType.FARM: _farm_count += 1
			BuildingData.BuildingType.SIEGE_WORKSHOP: _siege_workshop_count += 1
			BuildingData.BuildingType.BLACKSMITH: _blacksmith_count += 1
			BuildingData.BuildingType.WATCH_TOWER: _watch_tower_count += 1


func _get_building_count(building_type: int) -> int:
	match building_type:
		BuildingData.BuildingType.TOWN_CENTER: return _town_center_count
		BuildingData.BuildingType.HOUSE: return _house_count
		BuildingData.BuildingType.BARRACKS: return _barracks_count
		BuildingData.BuildingType.ARCHERY_RANGE: return _archery_range_count
		BuildingData.BuildingType.STABLE: return _stable_count
		BuildingData.BuildingType.LUMBER_CAMP: return _lumber_camp_count
		BuildingData.BuildingType.MINING_CAMP: return _mining_camp_count
		BuildingData.BuildingType.MILL: return _mill_count
		BuildingData.BuildingType.FARM: return _farm_count
		BuildingData.BuildingType.SIEGE_WORKSHOP: return _siege_workshop_count
		BuildingData.BuildingType.BLACKSMITH: return _blacksmith_count
		BuildingData.BuildingType.WATCH_TOWER: return _watch_tower_count
	return 0


func _get_villagers() -> Array:
	var result: Array = []
	for unit in _my_units:
		if is_instance_valid(unit) and unit is UnitBase:
			if unit.unit_type == UnitData.UnitType.VILLAGER and unit.current_state != UnitBase.State.DEAD:
				result.append(unit)
	return result


func _get_idle_villagers() -> Array:
	var result: Array = []
	for unit in _get_villagers():
		if unit.current_state == UnitBase.State.IDLE:
			result.append(unit)
	return result


func _get_military_units() -> Array:
	var result: Array = []
	for unit in _my_units:
		if not is_instance_valid(unit):
			continue
		if not (unit is UnitBase):
			continue
		if unit.current_state == UnitBase.State.DEAD:
			continue
		if unit.unit_type != UnitData.UnitType.VILLAGER:
			result.append(unit)
	return result


func _get_idle_military() -> Array:
	var result: Array = []
	for unit in _get_military_units():
		if unit.current_state == UnitBase.State.IDLE:
			result.append(unit)
	return result


func _get_visible_enemies() -> Array:
	## Returns enemy units that are close enough for any of our units to see.
	var result: Array = []
	var all_units: Array = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if not (unit is UnitBase):
			continue
		if unit.player_owner == player_id:
			continue
		if unit.current_state == UnitBase.State.DEAD:
			continue
		# Check if any of our units can see this enemy
		for my_unit in _my_units:
			if not is_instance_valid(my_unit):
				continue
			if my_unit.global_position.distance_to(unit.global_position) <= my_unit.vision_radius:
				result.append(unit)
				break
	return result


func _evaluate_army_strength() -> float:
	## Returns a simple strength score: sum of (hp * damage) for all military.
	var strength: float = 0.0
	for unit in _get_military_units():
		strength += unit.hp * unit.damage
	return strength


func _evaluate_enemy_visible_strength() -> float:
	var strength: float = 0.0
	for unit in _get_visible_enemies():
		if unit is UnitBase:
			strength += unit.hp * unit.damage
	return strength


func _get_buildings_of_type(building_type: int) -> Array:
	var result: Array = []
	for b in _my_buildings:
		if not is_instance_valid(b):
			continue
		if "building_type" in b and b.building_type == building_type:
			result.append(b)
	return result


func _find_building_of_type(building_type: int) -> Node:
	var buildings: Array = _get_buildings_of_type(building_type)
	if buildings.is_empty():
		return null
	return buildings[0]


func _find_trainable_building_of_type(building_type: int) -> Node:
	var buildings: Array = _get_buildings_of_type(building_type)
	if buildings.is_empty():
		return null

	var best: Node = null
	var best_queue: int = 999
	for b in buildings:
		if not is_instance_valid(b):
			continue
		if "state" in b and b.state != BuildingBase.State.ACTIVE:
			continue
		var q_size: int = 0
		if b.has_method("get_production_queue"):
			var pq: Node = b.get_production_queue()
			if pq and pq.has_method("get_queue_size"):
				q_size = int(pq.get_queue_size())
		if q_size >= 5:
			continue
		if q_size < best_queue:
			best_queue = q_size
			best = b
	if best != null:
		return best
	return _find_building_of_type(building_type)


func _find_nearest_resource_node(resource_type: String, from_pos: Vector2) -> Node2D:
	## Finds the nearest resource node of the given type using the game_map lookup.
	if game_map and game_map.has_method("get_nearest_resource_node"):
		return game_map.get_nearest_resource_node(resource_type, from_pos)
	return null


func _assign_villager_to_resource(villager: UnitBase, resource_node: Node2D) -> void:
	## Sends a villager to gather from a resource node.
	if villager.has_method("command_gather"):
		villager.command_gather(resource_node)
	else:
		villager.command_move(resource_node.global_position)


func _find_build_location(building_type: int) -> Vector2i:
	## Finds a valid build location near the base.
	## Searches in expanding rings around the Town Center tile.
	var stats: Dictionary = BuildingData.get_building_stats(building_type)
	var footprint: Vector2i = stats.get("footprint", Vector2i(2, 2))

	# Special placement for resource-gathering buildings
	if building_type == BuildingData.BuildingType.MILL:
		return _find_build_near_resource(MapData.TileType.BERRY_BUSH, footprint)
	if building_type == BuildingData.BuildingType.LUMBER_CAMP:
		return _find_build_near_resource(MapData.TileType.FOREST, footprint)
	if building_type == BuildingData.BuildingType.MINING_CAMP:
		return _find_build_near_resource(MapData.TileType.GOLD_MINE, footprint)

	# General placement: spiral out from base
	for ring in range(3, 15):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if abs(dx) != ring and abs(dy) != ring:
					continue  # Only check ring perimeter
				var tile := Vector2i(_base_tile.x + dx, _base_tile.y + dy)
				if _is_valid_build_spot(tile, footprint):
					return tile

	return Vector2i(-1, -1)


func _find_build_near_resource(resource_tile: MapData.TileType, footprint: Vector2i) -> Vector2i:
	## Place a gathering building adjacent to a resource cluster.
	if map_generator == null:
		return Vector2i(-1, -1)

	var best_pos := Vector2i(-1, -1)
	var best_dist: float = INF

	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			if map_generator.grid[y][x] != resource_tile:
				continue
			# Try spots adjacent to this resource
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var candidate: Vector2i = Vector2i(x, y) + offset
				if _is_valid_build_spot(candidate, footprint):
					var dist: float = _base_tile.distance_to(candidate)
					if dist < best_dist:
						best_dist = dist
						best_pos = candidate

	return best_pos


func _is_valid_build_spot(origin: Vector2i, footprint: Vector2i) -> bool:
	## Check that all tiles in footprint are in-bounds, walkable grass, and
	## not too close to existing buildings.
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			var tx: int = origin.x + dx
			var ty: int = origin.y + dy
			if tx < 0 or tx >= MapData.MAP_WIDTH or ty < 0 or ty >= MapData.MAP_HEIGHT:
				return false
			if map_generator and not MapData.is_grass(map_generator.grid[ty][tx] as MapData.TileType):
				return false
			if pathfinding and not pathfinding.is_walkable(Vector2i(tx, ty)):
				return false
	return true
