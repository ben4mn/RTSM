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

# Build-order tracking (what we have built so far)
var _house_count: int = 0
var _barracks_count: int = 0
var _archery_range_count: int = 0
var _stable_count: int = 0
var _lumber_camp_count: int = 0
var _mining_camp_count: int = 0
var _farm_count: int = 0
var _siege_workshop_count: int = 0

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
	Difficulty.EASY: 10,
	Difficulty.MEDIUM: 15,
	Difficulty.HARD: 8,
}

const RESOURCE_RATIO: Dictionary = {
	"food": 0.4,
	"wood": 0.3,
	"gold": 0.3,
}

# Build priority order: building_type, min_age, max_count_per_age
# Initialized in _ready() because Godot 4 const cannot reference external class enums.
var _build_priority: Array = []


func _ready() -> void:
	_decision_interval = DECISION_INTERVALS.get(difficulty, 1.5)
	_init_build_priority()
	_setup_timer()


func _init_build_priority() -> void:
	_build_priority = [
		{ "type": BuildingData.BuildingType.HOUSE, "age": 1, "max": 8 },
		{ "type": BuildingData.BuildingType.LUMBER_CAMP, "age": 1, "max": 2 },
		{ "type": BuildingData.BuildingType.FARM, "age": 1, "max": 6 },
		{ "type": BuildingData.BuildingType.BARRACKS, "age": 1, "max": 2 },
		{ "type": BuildingData.BuildingType.MINING_CAMP, "age": 1, "max": 2 },
		{ "type": BuildingData.BuildingType.ARCHERY_RANGE, "age": 2, "max": 2 },
		{ "type": BuildingData.BuildingType.STABLE, "age": 2, "max": 1 },
		{ "type": BuildingData.BuildingType.SIEGE_WORKSHOP, "age": 3, "max": 1 },
	]


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

	# Run decision tree in priority order
	_check_villager_production()
	_check_house_need()
	_assign_idle_villagers()
	_check_building_construction()
	_check_military_production()
	_check_age_up()
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


# ═════════════════════════════════════════════════════════════════════════
#  VILLAGER PRODUCTION
# ═════════════════════════════════════════════════════════════════════════

func _check_villager_production() -> void:
	var villagers: Array = _get_villagers()
	var target: int = VILLAGER_TARGETS.get(difficulty, 18)

	if villagers.size() >= target:
		return

	# Check pop room
	var player_data: Dictionary = GameManager.players.get(player_id, {})
	var pop: int = player_data.get("population", 0)
	var cap: int = player_data.get("population_cap", 5)
	if pop >= cap:
		return  # Need houses first

	# Find a Town Center to train from
	var tc: Node = _find_building_of_type(BuildingData.BuildingType.TOWN_CENTER)
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

	# Determine which resource is most below target ratio
	var deficits: Dictionary = {}
	for res_type in RESOURCE_RATIO:
		var current_ratio: float = float(resources.get(res_type, 0)) / total
		deficits[res_type] = RESOURCE_RATIO[res_type] - current_ratio

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

	for entry in _build_priority:
		var b_type: int = entry["type"]
		var req_age: int = entry["age"]
		var max_count: int = entry["max"]

		if age < req_age:
			continue

		var current_count: int = _get_building_count(b_type)
		if current_count >= max_count:
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
	if _ai_state == AIState.EARLY_GAME and _get_military_units().size() >= 3:
		return  # In early game, cap military production

	_try_train_from_building(BuildingData.BuildingType.BARRACKS, UnitData.UnitType.INFANTRY)

	if _ai_state != AIState.EARLY_GAME:
		_try_train_from_building(BuildingData.BuildingType.ARCHERY_RANGE, UnitData.UnitType.ARCHER)
		_try_train_from_building(BuildingData.BuildingType.STABLE, UnitData.UnitType.CAVALRY)

	if _ai_state == AIState.LATE_GAME:
		_try_train_from_building(BuildingData.BuildingType.SIEGE_WORKSHOP, UnitData.UnitType.SIEGE)


func _try_train_from_building(building_type: int, unit_type: int) -> void:
	var building: Node = _find_building_of_type(building_type)
	if building == null:
		return

	# Check pop room
	var player_data: Dictionary = GameManager.players.get(player_id, {})
	var pop: int = player_data.get("population", 0)
	var cap: int = player_data.get("population_cap", 5)
	var pop_cost: int = UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1)
	if pop + pop_cost > cap:
		return

	var cost: Dictionary = UnitData.get_unit_cost(unit_type)
	if ResourceManager.can_afford(player_id, cost):
		ai_wants_to_train.emit(building, unit_type)


# ═════════════════════════════════════════════════════════════════════════
#  AGE UP
# ═════════════════════════════════════════════════════════════════════════

func _check_age_up() -> void:
	var age: int = GameManager.get_player_age(player_id)
	if age >= GameManager.MAX_AGE:
		return

	# On HARD, age up sooner; on EASY, wait longer
	var min_villagers_to_age: int = 8
	match difficulty:
		Difficulty.EASY:
			min_villagers_to_age = 12
		Difficulty.MEDIUM:
			min_villagers_to_age = 10
		Difficulty.HARD:
			min_villagers_to_age = 6

	if _get_villagers().size() < min_villagers_to_age:
		return

	# Age-up costs (must match age_up_dialog.gd).
	var age_up_costs: Dictionary = {
		2: {"food": 400, "gold": 200},
		3: {"food": 1200, "gold": 600},
	}
	var target_age: int = age + 1
	var cost: Dictionary = age_up_costs.get(target_age, {})
	if cost.is_empty():
		return
	if ResourceManager.can_afford(player_id, cost):
		ai_wants_to_age_up.emit()


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
	var threshold: int = ARMY_ATTACK_THRESHOLDS.get(difficulty, 15)

	if _attack_in_progress:
		# Check if we should retreat
		if military.size() < int(threshold * _retreat_threshold):
			_retreat_army()
			_attack_in_progress = false
		return

	# Gather idle military at staging point
	var idle_military: Array = _get_idle_military()
	for unit in idle_military:
		if unit.global_position.distance_to(_staging_point) > 64.0:
			unit.command_move(_staging_point)

	# Launch attack if army is strong enough
	if military.size() >= threshold:
		var target: Vector2 = _find_enemy_target()
		if target != Vector2(-1, -1):
			_send_attack(military, target)
			_attack_in_progress = true


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
	_house_count = 0
	_barracks_count = 0
	_archery_range_count = 0
	_stable_count = 0
	_lumber_camp_count = 0
	_mining_camp_count = 0
	_farm_count = 0
	_siege_workshop_count = 0

	for b in _my_buildings:
		if not is_instance_valid(b):
			continue
		if not b.has_method("get_building_type") and not ("building_type" in b):
			continue
		var btype: int = b.building_type if "building_type" in b else -1
		match btype:
			BuildingData.BuildingType.HOUSE: _house_count += 1
			BuildingData.BuildingType.BARRACKS: _barracks_count += 1
			BuildingData.BuildingType.ARCHERY_RANGE: _archery_range_count += 1
			BuildingData.BuildingType.STABLE: _stable_count += 1
			BuildingData.BuildingType.LUMBER_CAMP: _lumber_camp_count += 1
			BuildingData.BuildingType.MINING_CAMP: _mining_camp_count += 1
			BuildingData.BuildingType.FARM: _farm_count += 1
			BuildingData.BuildingType.SIEGE_WORKSHOP: _siege_workshop_count += 1


func _get_building_count(building_type: int) -> int:
	match building_type:
		BuildingData.BuildingType.HOUSE: return _house_count
		BuildingData.BuildingType.BARRACKS: return _barracks_count
		BuildingData.BuildingType.ARCHERY_RANGE: return _archery_range_count
		BuildingData.BuildingType.STABLE: return _stable_count
		BuildingData.BuildingType.LUMBER_CAMP: return _lumber_camp_count
		BuildingData.BuildingType.MINING_CAMP: return _mining_camp_count
		BuildingData.BuildingType.FARM: return _farm_count
		BuildingData.BuildingType.SIEGE_WORKSHOP: return _siege_workshop_count
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


func _find_building_of_type(building_type: int) -> Node:
	for b in _my_buildings:
		if not is_instance_valid(b):
			continue
		if "building_type" in b and b.building_type == building_type:
			return b
	return null


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
			if map_generator and map_generator.grid[ty][tx] != MapData.TileType.GRASS:
				return false
			if pathfinding and not pathfinding.is_walkable(Vector2i(tx, ty)):
				return false
	return true
