class_name AIController
extends Node
## Main AI brain for a computer-controlled player.
##
## Runs a decision loop on a timer that mirrors the same systems a human
## player uses: ResourceManager for spending, GameManager for population
## and age-up, unit commands for movement/attack, and BuildingData costs
## for construction. NO cheating — the AI has the same resources, vision,
## and unit stats as a human player.

signal ai_wants_to_build(building_type: int, tile_pos: Vector2i, is_rebuild: bool)
signal ai_wants_to_train(building: Node, unit_type: int)
signal ai_wants_to_age_up()
signal ai_attack_launched(units: Array, target_pos: Vector2)

# ── Difficulty ───────────────────────────────────────────────────────────
enum Difficulty { EASY, MEDIUM, HARD }
enum AIState { EARLY_GAME, MID_GAME, LATE_GAME }
enum ObjectiveMode { NONE, SCOUT, CAPTURE, CONTEST, DEFEND }

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
var _military_role_last_fielded: Dictionary = {}  # own completed roles, never enemy knowledge
var _base_position: Vector2 = Vector2.ZERO  # Town Center world position
var _base_tile: Vector2i = Vector2i.ZERO    # TC tile coord

# Army staging
var _staging_point: Vector2 = Vector2.ZERO
var _attack_in_progress: bool = false
var _has_launched_field_attack: bool = false
var _attack_wave_units: Array = []
var _attack_wave_target_position: Vector2 = Vector2(-1, -1)
var _attack_wave_target_ref: WeakRef = null
var _attack_wave_best_distance: float = INF
var _attack_wave_best_target_hp: float = INF
var _attack_wave_last_progress_time: float = 0.0
var _retreat_threshold: float = 0.3  # Pull back if army drops below 30%
var _game_time: float = 0.0  # Track elapsed time for timed aggression
var _last_harass_time: float = 0.0  # Cooldown for harassment raids
var _scout_waypoints: Array[Vector2] = []
var _next_scout_waypoint_index: int = 0
var _objective_scout_sent: bool = false

# Strategic memory and task ownership. Objective units are excluded from
# ordinary raids while they capture or guard the Sacred Site.
var _objective_mode: ObjectiveMode = ObjectiveMode.NONE
var _objective_units: Array = []
var _objective_order_time: float = -INF
var _enemy_memory: Dictionary = {}  # instance_id -> last fair sighting
var _rebuild_requests: Dictionary = {}  # building_type -> replacements owed
var _last_defense_threat_position: Vector2 = Vector2.ZERO
var _last_defense_threat_time: float = -INF
var _last_strategy_decision: String = "opening"

# Fair economy recovery. Resource memory stores only positions observed while
# the resource was in current vision; it never retains a live node reference.
# The deterministic waypoint sweep is generated from public map dimensions and
# coordinate conversion only, so hidden terrain/resources do not influence it.
var _resource_memory: Dictionary = {
	"food": [],
	"wood": [],
	"gold": [],
}
var _economy_exploration_waypoints: Array[Vector2] = []
var _next_economy_exploration_waypoint: int = 0
var _economy_exploration_orders_issued: int = 0
var _economy_memory_revisit_orders_issued: int = 0
var _economy_resource_assignments: int = 0
var _economy_rebalance_orders_issued: int = 0
var _next_economy_rebalance_time: float = 0.0
var _pending_economy_rebalance_type: String = ""
var _pending_economy_rebalance_from_type: String = ""
var _pending_economy_rebalance_deadline: float = -INF
var _economy_rebalance_deferred_scheduled: bool = false
var _last_economy_action: String = "none"
var _build_site_search_cursors: Dictionary = {}  # building_type -> bounded scalar cursor

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
var _feudal_paid_farm_foundations: int = 0
var _feudal_paid_farm_foundation_ids: Dictionary = {}
var _siege_workshop_count: int = 0
var _blacksmith_count: int = 0
var _watch_tower_count: int = 0
var _is_under_pressure: bool = false
var _pressure_memory: float = 0.0
var _saving_for_age_up: bool = false
var _timed_age_up_reserve_active: bool = false

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

const SCOUT_TARGETS: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.MEDIUM: 1,
	Difficulty.HARD: 2,
}

const SACRED_SITE_START_TIMES: Dictionary = {
	Difficulty.EASY: 270.0,
	Difficulty.MEDIUM: 150.0,
	Difficulty.HARD: 90.0,
}

const SACRED_CAPTURE_FORCES: Dictionary = {
	Difficulty.EASY: 2,
	Difficulty.MEDIUM: 3,
	Difficulty.HARD: 4,
}

const SACRED_CONTEST_FORCES: Dictionary = {
	Difficulty.EASY: 3,
	Difficulty.MEDIUM: 5,
	Difficulty.HARD: 7,
}

const SACRED_DEFENDER_FORCES: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.MEDIUM: 2,
	Difficulty.HARD: 3,
}

const BASE_DEFENSE_RESERVES: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.MEDIUM: 2,
	Difficulty.HARD: 2,
}

const ENEMY_MEMORY_SECONDS: Dictionary = {
	Difficulty.EASY: 20.0,
	Difficulty.MEDIUM: 45.0,
	Difficulty.HARD: 75.0,
}

const REBUILD_PRIORITY: Array[int] = [
	BuildingData.BuildingType.TOWN_CENTER,
	BuildingData.BuildingType.HOUSE,
	BuildingData.BuildingType.BARRACKS,
	BuildingData.BuildingType.WATCH_TOWER,
	BuildingData.BuildingType.ARCHERY_RANGE,
	BuildingData.BuildingType.STABLE,
	BuildingData.BuildingType.LUMBER_CAMP,
	BuildingData.BuildingType.MINING_CAMP,
	BuildingData.BuildingType.MILL,
	BuildingData.BuildingType.BLACKSMITH,
	BuildingData.BuildingType.FARM,
	BuildingData.BuildingType.SIEGE_WORKSHOP,
]

const PRESSURE_MEMORY_SECONDS: float = 8.0
const DEFENSE_MEMORY_SECONDS: float = 12.0
const BASE_DEFENSE_RADIUS: float = 220.0
const SACRED_SITE_THREAT_RADIUS: float = 240.0
const SACRED_SITE_HOLD_RADIUS: float = 112.0
const SACRED_SITE_ORDER_REFRESH: float = 8.0
const SACRED_RECON_MARGIN: float = float(MapData.TILE_WIDTH) * 2.0
const SACRED_RECON_ROUTE_CLEARANCE: float = float(MapData.TILE_WIDTH) * 0.5
const SACRED_RECON_TARGET_TOLERANCE: float = float(MapData.TILE_WIDTH) * 0.75
const ATTACK_WAVE_ARRIVAL_RADIUS: float = 72.0
const ATTACK_WAVE_PROGRESS_EPSILON: float = 6.0
const ATTACK_WAVE_NO_PROGRESS_TIMEOUT: float = 24.0
const ECONOMY_EXPLORATION_GRID_STEP: int = 5
const ECONOMY_EXPLORATION_GRID_MARGIN: int = 2
const RESOURCE_MEMORY_LIMIT_PER_TYPE: int = 8
const ECONOMY_REBALANCE_INTERVALS: Dictionary = {
	Difficulty.EASY: 32.0,
	Difficulty.MEDIUM: 20.0,
	Difficulty.HARD: 16.0,
}
const ECONOMY_REBALANCE_RETRY_SECONDS: float = 18.0
# Three paid farms contain 900 food. Together with the opening bank and finite
# legally gathered natural food, that funds the 12-villager/3-military liveness
# floor plus the 400-food Feudal transaction without a bonus or hidden lookup.
# Depleted farms remain subject to the normal paid rebuild path.
const FEUDAL_FARM_CAPACITY_TARGET: int = 3
# The opening still needs to earn 225 wood after its first Farm and House:
# 75 for the Barracks bank plus 150 for two more finite Farms. With TC-length
# drop-off routes, a quarter of the early workforce cannot complete those real
# transactions by the liveness horizon. This temporary half-workforce floor is
# released as soon as all four foundations are registered.
const FEUDAL_FARM_WOOD_WORKER_RATIO: float = 0.50

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

const AGE_UP_SAVING_LEAD_TIMES: Dictionary = {
	Difficulty.EASY: 100.0,
	Difficulty.MEDIUM: 170.0,
	Difficulty.HARD: 85.0,
}

const AGE_UP_MIN_VILLAGERS: Dictionary = {
	Difficulty.EASY: {2: 11, 3: 18},
	Difficulty.MEDIUM: {2: 12, 3: 16},
	Difficulty.HARD: {2: 12, 3: 14},
}

const AGE_UP_MIN_MILITARY: Dictionary = {
	Difficulty.EASY: {2: 2, 3: 4},
	Difficulty.MEDIUM: {2: 3, 3: 5},
	Difficulty.HARD: {2: 4, 3: 5},
}


func _ready() -> void:
	_setup_timer()
	_apply_difficulty_profile()


func _process(delta: float) -> void:
	if GameManager.current_state == GameManager.GameState.PLAYING:
		_game_time += delta


func _setup_timer() -> void:
	_decision_timer = Timer.new()
	_decision_timer.wait_time = _decision_interval
	_decision_timer.one_shot = false
	_decision_timer.timeout.connect(_on_decision_tick)
	add_child(_decision_timer)


func _apply_difficulty_profile() -> void:
	# The scene node becomes ready before Main assigns the menu selection, so the
	# cadence must be reapplied at match start rather than only in _ready().
	_decision_interval = float(DECISION_INTERVALS.get(difficulty, 1.5))
	if _decision_timer != null:
		_decision_timer.wait_time = _decision_interval


## Call this once the game scene is ready and the TC is placed.
func start_ai(base_tile: Vector2i, base_world_pos: Vector2) -> void:
	_apply_difficulty_profile()
	_clear_attack_wave()
	_release_objective_units()
	_enemy_memory.clear()
	_rebuild_requests.clear()
	_game_time = 0.0
	_military_role_last_fielded.clear()
	for unit: UnitBase in _get_fighting_units():
		_military_role_last_fielded[unit.unit_type] = 0.0
	_last_harass_time = 0.0
	_has_launched_field_attack = false
	_last_defense_threat_time = -INF
	_objective_scout_sent = false
	_saving_for_age_up = false
	_timed_age_up_reserve_active = false
	_feudal_paid_farm_foundations = 0
	_feudal_paid_farm_foundation_ids.clear()
	_build_site_search_cursors.clear()
	_base_tile = base_tile
	_base_position = base_world_pos
	_reset_economy_recovery()
	# Staging point is a short distance in front of our base toward map center
	var center: Vector2 = _tile_to_world(Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2))
	_staging_point = _base_position.lerp(center, 0.25)
	_build_scout_waypoints(center)
	_decision_timer.start()


## Register a building the AI owns, including a foundation under construction.
func register_building(building: Node) -> void:
	if building not in _my_buildings:
		_my_buildings.append(building)
		_update_building_counts()
	_track_paid_feudal_farm_foundation(building)
	if building.has_signal("building_destroyed"):
		var callback := Callable(self, "_on_ai_building_destroyed")
		if not building.is_connected("building_destroyed", callback):
			building.connect("building_destroyed", callback)
	if building.has_signal("health_changed"):
		var damage_callback := Callable(self, "_on_ai_building_damaged").bind(building)
		if not building.is_connected("health_changed", damage_callback):
			building.connect("health_changed", damage_callback)
	if building.has_signal("construction_complete"):
		var completion_callback := Callable(self, "_on_ai_building_construction_complete")
		if not building.is_connected("construction_complete", completion_callback):
			building.connect("construction_complete", completion_callback)


## Remove a foundation that Main cancelled before it became a real loss.
## This intentionally does not create a rebuild request.
func unregister_building(building: Node) -> void:
	_untrack_cancelled_feudal_farm_foundation(building)
	_my_buildings.erase(building)
	_update_building_counts()


func _untrack_cancelled_feudal_farm_foundation(building: Node) -> void:
	## unregister_building() is Main's pre-commit cancellation/refund path, not the
	## destruction path. Undo a provisional Farm registration so failed builder
	## acceptance cannot masquerade as paid food capacity.
	if building == null or not is_instance_valid(building):
		return
	var foundation_id: int = building.get_instance_id()
	if not _feudal_paid_farm_foundation_ids.has(foundation_id):
		return
	_feudal_paid_farm_foundation_ids.erase(foundation_id)
	_feudal_paid_farm_foundations = maxi(0, _feudal_paid_farm_foundations - 1)


func restore_rebuild_request(building_type: int) -> void:
	## A rebuild request is consumed immediately before signal dispatch. Main
	## restores it through this hook if no safe builder transaction can start.
	_rebuild_requests[building_type] = int(_rebuild_requests.get(building_type, 0)) + 1


## Register a unit the AI owns (called when a unit is spawned for this player).
func register_unit(unit: Node) -> void:
	if unit not in _my_units:
		_my_units.append(unit)
		if unit is UnitBase and unit.unit_type in [UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY]:
			_military_role_last_fielded[unit.unit_type] = _game_time
		if unit.has_signal("unit_died"):
			unit.unit_died.connect(_on_unit_died)
		if unit.has_signal("resource_deposited"):
			var deposit_callback := Callable(self, "_on_ai_villager_resource_deposited")
			if not unit.is_connected("resource_deposited", deposit_callback):
				unit.connect("resource_deposited", deposit_callback)


func _on_unit_died(unit: UnitBase) -> void:
	_my_units.erase(unit)
	_attack_wave_units.erase(unit)
	_objective_units.erase(unit)


func _on_ai_villager_resource_deposited(resource_type: String, _amount: int) -> void:
	## Villager emits immediately before clearing carried_amount and resuming its
	## gather order. Defer once so the existing zero-cargo safety gate observes
	## the completed transaction rather than converting or discarding its cargo.
	if (
		_pending_economy_rebalance_type == ""
		or resource_type != _pending_economy_rebalance_from_type
		or _economy_rebalance_deferred_scheduled
	):
		return
	_economy_rebalance_deferred_scheduled = true
	call_deferred("_service_pending_economy_rebalance_after_deposit")


func _service_pending_economy_rebalance_after_deposit() -> void:
	_economy_rebalance_deferred_scheduled = false
	_service_pending_economy_rebalance()


func _on_ai_building_destroyed(building: BuildingBase) -> void:
	if not is_instance_valid(building):
		return
	var building_type: int = building.building_type
	_my_buildings.erase(building)
	_update_building_counts()
	_rebuild_requests[building_type] = int(_rebuild_requests.get(building_type, 0)) + 1


func _on_ai_building_damaged(_current_hp: int, _maximum_hp: int, building: BuildingBase) -> void:
	if not is_instance_valid(building) or building.state == BuildingBase.State.DESTROYED:
		return
	_last_defense_threat_position = building.global_position
	_last_defense_threat_time = _game_time
	_pressure_memory = PRESSURE_MEMORY_SECONDS
	_is_under_pressure = true


func _on_ai_building_construction_complete(building: BuildingBase) -> void:
	if (
		not is_instance_valid(building)
		or building.player_owner != player_id
		or building.building_type != BuildingData.BuildingType.FARM
	):
		return
	# Completion fires inside the builder's update, before it resumes its saved
	# job. Defer until that state transition finishes, while preserving the exact
	# paid Farm identity instead of redirecting its worker to nearer natural food.
	call_deferred("_assign_safe_worker_to_completed_farm", building)


func _track_paid_feudal_farm_foundation(building: Node) -> void:
	## Foundations are registered only after Main has completed the normal paid
	## construction transaction. Count each pre-Feudal Farm once even if its finite
	## stock later depletes and the node leaves _my_buildings: consumed Farm capacity
	## already contributed real food and must not keep the opening wood latch active.
	if GameManager.get_player_age(player_id) > 1:
		return
	if int(building.get("building_type")) != BuildingData.BuildingType.FARM:
		return
	var foundation_id: int = building.get_instance_id()
	if _feudal_paid_farm_foundation_ids.has(foundation_id):
		return
	_feudal_paid_farm_foundation_ids[foundation_id] = true
	_feudal_paid_farm_foundations += 1


func _assign_safe_worker_to_completed_farm(farm_node: Node) -> void:
	if (
		farm_node == null
		or not is_instance_valid(farm_node)
		or not farm_node is BuildingBase
		or farm_node not in _my_buildings
	):
		return
	var farm: BuildingBase = farm_node as BuildingBase
	if (
		farm.player_owner != player_id
		or farm.building_type != BuildingData.BuildingType.FARM
		or farm.state != BuildingBase.State.ACTIVE
		or not farm.is_harvestable_by(player_id)
	):
		return
	if _is_worker_position_exposed(farm.global_position, _get_visible_worker_threats()):
		return
	var candidates: Array = []
	for villager in _get_villagers():
		if _is_worker_retreating(villager):
			continue
		var state: int = int(villager.get("current_state"))
		# Even an IDLE worker may be holding cargo after an interrupted drop-off.
		# Keep it on the explicit return path. A GATHERING worker may be loaded because
		# Villager's cross-type command deposits that exact cargo before the Farm order.
		if state == UnitBase.State.IDLE:
			if int(villager.get("carried_amount")) == 0:
				candidates.append(villager)
			continue
		if (
			state == UnitBase.State.GATHERING
			and str(villager.get("carried_resource_type")) != "food"
		):
			candidates.append(villager)
	# Prefer idle workers, then surplus gold before the wood that is funding the
	# remaining farm capacity. Instance id makes ties deterministic.
	candidates.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		var a_score: int = _completed_farm_worker_score(a)
		var b_score: int = _completed_farm_worker_score(b)
		if a_score != b_score:
			return a_score < b_score
		var a_cargo: int = int(a.get("carried_amount"))
		var b_cargo: int = int(b.get("carried_amount"))
		if a_cargo != b_cargo:
			return a_cargo < b_cargo
		return a.get_instance_id() < b.get_instance_id()
	)
	for candidate_variant: Variant in candidates:
		var candidate: UnitBase = candidate_variant as UnitBase
		if not _is_specific_resource_reachable(candidate, farm, Villager.BUILD_APPROACH_DISTANCE):
			continue
		if not _assign_villager_to_resource(candidate, farm):
			continue
		_remember_resource_sighting("food", farm.global_position)
		_economy_resource_assignments += 1
		_last_economy_action = "farm_recovery_food"
		return


func _is_specific_resource_reachable(
	villager: UnitBase,
	resource_node: Node2D,
	interaction_radius: float
) -> bool:
	if game_map == null:
		return true
	if (
		game_map.has_method("is_entity_visible_to_player")
		and not bool(game_map.call("is_entity_visible_to_player", resource_node, player_id))
	):
		return false
	if resource_node is BuildingBase and game_map.has_method("get_building_work_world_path"):
		# Building anchors are blocked cells. The canonical footprint route ends
		# at a legal work edge, which can be farther than a center-point radius.
		var work_route: PackedVector2Array = game_map.call("get_building_work_world_path", villager.global_position, resource_node.global_position, (resource_node as BuildingBase).footprint, interaction_radius) as PackedVector2Array
		return not work_route.is_empty()
	if not game_map.has_method("get_navigation_world_path"):
		return true
	var route: PackedVector2Array = game_map.call(
		"get_navigation_world_path",
		villager.global_position,
		resource_node.global_position,
		interaction_radius
	) as PackedVector2Array
	return (
		not route.is_empty()
		and route[route.size() - 1].distance_to(resource_node.global_position)
		<= interaction_radius
	)


func _completed_farm_worker_score(villager: UnitBase) -> int:
	if int(villager.get("current_state")) == UnitBase.State.IDLE:
		return 0
	if str(villager.get("carried_resource_type")) == "gold":
		return 1
	return 2


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
	_update_enemy_memory()

	# Update game phase
	_update_ai_state()
	_update_pressure_state()
	_update_age_up_reserve()

	# Run decision tree in priority order
	_check_villager_production()
	_check_age_up()
	var rebuilding: bool = _check_rebuilding()
	if not rebuilding:
		_check_house_need()
		_check_building_construction()
	# Construction transactions need an IDLE/GATHERING builder at synchronous
	# Main preflight. Only after those intents are dispatched may recovery move
	# idle workers or rebalance their current gather jobs.
	_rebalance_gathering_villagers()
	_assign_idle_villagers()
	_check_military_production()
	_check_research()
	_check_scouting()
	_micro_damaged_units()
	_check_attack_or_defend()


func _build_scout_waypoints(map_center: Vector2) -> void:
	_scout_waypoints.clear()
	var sacred_recon: Vector2 = map_center
	var sacred_site: Node2D = _get_sacred_site()
	if sacred_site != null:
		sacred_recon = _get_sacred_recon_position(sacred_site)
	var enemy_spawn_world: Vector2 = map_center
	if map_generator:
		enemy_spawn_world = _tile_to_world(_get_symmetric_enemy_spawn_tile())
	var flank_a: Vector2 = enemy_spawn_world.lerp(map_center, 0.38) + Vector2(-160.0, 90.0)
	var flank_b: Vector2 = enemy_spawn_world.lerp(map_center, 0.38) + Vector2(160.0, -90.0)
	_scout_waypoints = [
		sacred_recon,
		flank_a,
		enemy_spawn_world,
		flank_b,
		map_center.lerp(_base_position, 0.45),
	]
	_next_scout_waypoint_index = 0


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
	var threats: Array = _find_defense_threats()
	for enemy in threats:
		if enemy is UnitBase:
			enemy_pressure_strength += _evaluate_unit_combat_strength(enemy as UnitBase)
	if not threats.is_empty():
		_last_defense_threat_position = _average_node_position(threats)
		_last_defense_threat_time = _game_time

	var own_strength: float = maxf(1.0, _evaluate_army_strength())
	var pressure_now: bool = threats.size() >= 2 or enemy_pressure_strength > own_strength * 0.65
	if pressure_now:
		_pressure_memory = PRESSURE_MEMORY_SECONDS
	else:
		_pressure_memory = maxf(0.0, _pressure_memory - _decision_interval)
	_is_under_pressure = _pressure_memory > 0.0


func _update_age_up_reserve() -> void:
	_timed_age_up_reserve_active = false
	# An economy hit is recovered with normal paid workers before optional ages.
	if _needs_compact_worker_recovery():
		_saving_for_age_up = false
		return
	var age: int = GameManager.get_player_age(player_id)
	if age >= 2 and _get_compact_missing_role_building() >= 0:
		_saving_for_age_up = false
		return
	if age >= GameManager.MAX_AGE:
		_saving_for_age_up = false
		return

	var target_age: int = age + 1
	var cost: Dictionary = GameManager.get_age_up_cost(player_id, target_age)
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
	var saving_lead: float = float(AGE_UP_SAVING_LEAD_TIMES.get(difficulty, 95.0))
	if _uses_compact_population_policy():
		# A small economy must establish a fighting force before an early reserve
		# freezes production; its reduced age transaction needs a shorter runway.
		saving_lead = minf(saving_lead, 75.0)
	var timed_reserve: bool = (
		target_age == 2
		and not _is_under_pressure
		and _game_time >= target_time - saving_lead
	)
	if timed_reserve and _uses_compact_population_policy():
		# At least one real attack packet must exist before age saving freezes
		# military production. The recon Scout occupies its own population slot.
		timed_reserve = military_count + _count_queued_military_units() >= _get_attack_threshold() + 1
	if timed_reserve:
		# The target time is a real policy boundary, not a resource bonus. Start
		# preserving earned food/gold early enough that production cannot spend each
		# deposit before the completion-ratio latch ever activates.
		_saving_for_age_up = true
		_timed_age_up_reserve_active = true
		return
	_saving_for_age_up = completion >= reserve_threshold and military_count >= military_gate


# ═════════════════════════════════════════════════════════════════════════
#  VILLAGER PRODUCTION
# ═════════════════════════════════════════════════════════════════════════

func _check_villager_production() -> void:
	var villagers: Array = _get_villagers()
	var target: int = _get_target_villager_count()
	var queued_villagers: int = _count_queued_unit(UnitData.UnitType.VILLAGER)
	if _should_pause_villager_production_for_age_up(villagers.size(), queued_villagers):
		return

	if villagers.size() + queued_villagers >= target:
		return

	# Check pop room
	var villager_pop_cost: int = int(UnitData.UNITS[UnitData.UnitType.VILLAGER].get("pop_cost", 1))
	if not GameManager.can_reserve_population(player_id, villager_pop_cost):
		return  # Need houses first

	# Find the least busy Town Center to train from.
	var tc: Node = _find_trainable_building_of_type(BuildingData.BuildingType.TOWN_CENTER)
	if tc == null:
		return

	var cost: Dictionary = UnitData.get_unit_cost(UnitData.UnitType.VILLAGER)
	if ResourceManager.can_afford(player_id, cost):
		ai_wants_to_train.emit(tc, UnitData.UnitType.VILLAGER)


func _should_pause_villager_production_for_age_up(
	villager_count: int,
	queued_villagers: int
) -> bool:
	var current_age: int = GameManager.get_player_age(player_id)
	if not _saving_for_age_up or current_age >= GameManager.MAX_AGE:
		return false
	var minimum_for_next_age: int = _get_min_villagers_for_age_up(current_age + 1)
	if _is_under_pressure:
		minimum_for_next_age += 1
	return villager_count + queued_villagers >= minimum_for_next_age


# ═════════════════════════════════════════════════════════════════════════
#  HOUSE CHECK — build if population is close to cap
# ═════════════════════════════════════════════════════════════════════════

func _check_house_need() -> void:
	var player_data: Dictionary = GameManager.players.get(player_id, {})
	var pop: int = GameManager.get_committed_population(player_id)
	var cap: int = player_data.get("population_cap", 5)
	if cap >= GameManager.get_player_population_limit(player_id):
		return
	if (
		_timed_age_up_reserve_active
		and not _is_under_pressure
		and GameManager.get_player_age(player_id) <= 1
		and _needs_feudal_wood_infrastructure()
	):
		var feudal_floor_capacity: int = (
			_get_min_villagers_for_age_up(2)
			+ _get_min_military_for_age_up(2)
		)
		# The opening House provides exactly enough room for the declared Medium
		# floor. Suppress the proactive two-slot buffer while critical paid Farms or
		# Barracks still need wood; a genuinely insufficient cap still builds now.
		if cap >= feudal_floor_capacity and pop <= feudal_floor_capacity:
			return

	# Build a house when within 2 pop of cap
	if pop < cap - 2:
		return
	if _house_count >= 12:
		return
	# Population capacity is not granted until construction completes. Without
	# this pending-state gate, the corrected real-time construction duration
	# causes a new House request every decision tick until the first one finishes.
	if _has_building_under_construction(BuildingData.BuildingType.HOUSE):
		return

	var cost: Dictionary = BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE)
	if ResourceManager.can_afford(player_id, cost):
		var pos: Vector2i = _find_build_location(BuildingData.BuildingType.HOUSE)
		if pos != Vector2i(-1, -1):
			ai_wants_to_build.emit(BuildingData.BuildingType.HOUSE, pos, false)


# ═════════════════════════════════════════════════════════════════════════
#  IDLE VILLAGER ASSIGNMENT
# ═════════════════════════════════════════════════════════════════════════

func _assign_idle_villagers() -> void:
	var idle: Array = _get_idle_villagers()
	if idle.is_empty():
		return

	# Figure out current resource ratios vs desired.
	var resources: Dictionary = ResourceManager.get_all_resources(player_id)
	var counts: Dictionary = _get_economy_work_counts()
	var assignable_workers: int = int(counts["food"]) + int(counts["wood"]) + int(counts["gold"])
	for villager in idle:
		if not _is_worker_retreating(villager) and int(villager.get("carried_amount")) == 0:
			assignable_workers += 1
	var targets: Dictionary = _get_economy_worker_targets(assignable_workers, resources)

	# Assign each idle villager to the most needed currently visible resource.
	# If vision contains no valid target, revisit a position-only fair sighting or
	# advance a finite deterministic search sweep instead of idling at the base.
	for villager in idle:
		if _is_worker_retreating(villager):
			continue
		# Recompute labor gaps after every accepted assignment. A batch of idle
		# survivors must not all take the same bank-priority job and starve wood.
		var priority: Array = _get_economy_resource_priority(resources)
		var bank_priority: Array = priority.duplicate()
		priority.sort_custom(func(a: String, b: String) -> bool:
			var a_gap: int = int(targets.get(a, 0)) - int(counts.get(a, 0))
			var b_gap: int = int(targets.get(b, 0)) - int(counts.get(b, 0))
			return a_gap > b_gap if a_gap != b_gap else bank_priority.find(a) < bank_priority.find(b)
		)
		# IDLE is not synonymous with empty-handed: canceled construction and a
		# failed route can leave a partial load. Return that exact cargo before any
		# cross-resource gather or geometry-only exploration command can supersede it.
		if int(villager.get("carried_amount")) > 0:
			if (
				villager.has_method("command_return_resources")
				and bool(villager.call("command_return_resources"))
			):
				_last_economy_action = "return_%s" % str(
					villager.get("carried_resource_type")
				)
			continue
		var assigned: bool = false
		for res_type in priority:
			var resource_node: Node2D = _find_resource_for_villager(res_type, villager)
			if resource_node != null and _assign_villager_to_resource(villager, resource_node):
				_remember_resource_sighting(res_type, resource_node.global_position)
				_economy_resource_assignments += 1
				_last_economy_action = "gather_%s" % res_type
				counts[res_type] = int(counts.get(res_type, 0)) + 1
				assigned = true
				break
		if assigned:
			continue

		var memory_target: Dictionary = _find_resource_memory_target(priority, villager.global_position)
		if not memory_target.is_empty():
			villager.command_move(memory_target.get("position", _base_position) as Vector2)
			_economy_memory_revisit_orders_issued += 1
			_last_economy_action = "revisit_%s" % str(memory_target.get("resource_type", "resource"))
			continue

		var exploration_target: Dictionary = _take_next_economy_exploration_target()
		if not exploration_target.is_empty():
			villager.command_move(exploration_target.get("position", _base_position) as Vector2)
			_economy_exploration_orders_issued += 1
			_last_economy_action = "explore"
			continue

		# A complete sweep is deliberately bounded. With no remaining legal lead,
		# keeping the worker safe at home is preferable to unbounded order churn.
		villager.command_move(_base_position)
		_last_economy_action = "sweep_complete"


func _get_economy_resource_priority(resources: Dictionary) -> Array:
	var priority: Array = ["food", "wood", "gold"]
	if _needs_compact_worker_recovery():
		return ["food", "wood", "gold"]
	var scores: Dictionary = {}
	var age: int = GameManager.get_player_age(player_id)
	if _saving_for_age_up and age == 1:
		# During the timed Feudal reserve, direct labor toward the two resources
		# the real transaction consumes. Wood remains a fallback after both gaps.
		for resource_type in ["food", "gold"]:
			var needed: float = float(GameManager.get_age_up_cost(player_id, 2).get(resource_type, 0))
			var current: float = float(resources.get(resource_type, 0))
			scores[resource_type] = maxf(0.0, needed - current) / maxf(1.0, needed)
		# Until all paid Feudal farm transactions are funded, visible wood is the
		# only feasible route back to food when natural nodes are exhausted. Keep
		# this priority aligned with _get_economy_worker_targets().
		scores["wood"] = (
			2.0
			if _timed_age_up_reserve_active and _needs_feudal_wood_infrastructure()
			else -1.0
		)
	else:
		var total: float = float(
			resources.get("food", 0)
			+ resources.get("wood", 0)
			+ resources.get("gold", 0)
		)
		total = maxf(1.0, total)
		var target_ratio: Dictionary = _get_target_resource_ratio()
		for resource_type in priority:
			var current_ratio: float = float(resources.get(resource_type, 0)) / total
			scores[resource_type] = float(target_ratio.get(resource_type, 0.0)) - current_ratio
	priority.sort_custom(func(a: String, b: String) -> bool:
		var a_score: float = float(scores.get(a, 0.0))
		var b_score: float = float(scores.get(b, 0.0))
		if not is_equal_approx(a_score, b_score):
			return a_score > b_score
		return ["food", "gold", "wood"].find(a) < ["food", "gold", "wood"].find(b)
	)
	return priority


func _rebalance_gathering_villagers() -> void:
	## Rebalancing is deliberately rate-limited to one gatherer. Loaded donors
	## use Villager's deposit-then-retarget transaction; a pending request can also
	## catch the post-dropoff zero-cargo window without discarding resources.
	_service_pending_economy_rebalance()
	if _pending_economy_rebalance_type != "":
		return
	var rapid_feudal_correction: bool = (
		_timed_age_up_reserve_active
		and not _is_under_pressure
		and GameManager.get_player_age(player_id) <= 1
	)
	var rapid_role_correction: bool = _get_compact_missing_role_building() >= 0
	var rapid_recovery_correction: bool = _needs_compact_worker_recovery()
	var rapid_correction: bool = rapid_feudal_correction or rapid_role_correction or rapid_recovery_correction
	if not rapid_correction and _game_time < _next_economy_rebalance_time:
		return
	if not rapid_correction:
		_next_economy_rebalance_time = _game_time + float(
			ECONOMY_REBALANCE_INTERVALS.get(difficulty, 28.0)
		)
	if not _get_idle_villagers().is_empty():
		return

	var counts: Dictionary = _get_economy_work_counts()
	var active_economy_workers: int = int(counts["food"]) + int(counts["wood"]) + int(counts["gold"])
	if active_economy_workers < 2:
		return

	var resources: Dictionary = ResourceManager.get_all_resources(player_id)
	var priority: Array = _get_economy_resource_priority(resources)
	var worker_targets: Dictionary = _get_economy_worker_targets(active_economy_workers, resources)
	var preferred_type: String = ""
	for resource_type_variant: Variant in priority:
		var resource_type: String = str(resource_type_variant)
		if int(counts.get(resource_type, 0)) < int(worker_targets.get(resource_type, 0)):
			preferred_type = resource_type
			break
	if preferred_type == "":
		return

	var donor_type: String = ""
	var donor_overage: int = 0
	for resource_type in ["food", "wood", "gold"]:
		if resource_type == preferred_type:
			continue
		var overage: int = (
			int(counts.get(resource_type, 0))
			- int(worker_targets.get(resource_type, 0))
		)
		if overage > donor_overage:
			donor_overage = overage
			donor_type = resource_type
	if donor_type == "":
		return

	_pending_economy_rebalance_type = preferred_type
	_pending_economy_rebalance_from_type = donor_type
	_pending_economy_rebalance_deadline = _game_time + ECONOMY_REBALANCE_RETRY_SECONDS
	_service_pending_economy_rebalance()


func _get_economy_worker_targets(worker_count: int, resources: Dictionary) -> Dictionary:
	if worker_count <= 0:
		return {"food": 0, "wood": 0, "gold": 0}
	if _needs_compact_worker_recovery():
		# One scarce food deposit must grow the workforce rather than get spent by
		# repeated low-food Archer queues. Existing gold can fund the recovery.
		var recovery_wood: int = 1 if worker_count >= 3 else 0
		return {"food": worker_count - recovery_wood, "wood": recovery_wood, "gold": 0}
	var age: int = GameManager.get_player_age(player_id)
	if _saving_for_age_up and (age == 1 or _uses_compact_population_policy()):
		var age_cost: Dictionary = GameManager.get_age_up_cost(player_id, age + 1)
		# Keep one worker on wood for houses/dropoff infrastructure, then allocate
		# every other worker in proportion to the *remaining* real Feudal cost.
		# Once gold reaches 200 its target becomes zero, preventing the observed
		# 598-gold overshoot while food remained just short of 400.
		var wood_target: int = 1 if worker_count >= 3 else 0
		if _timed_age_up_reserve_active and _needs_feudal_wood_infrastructure():
			# The opening farm is a normal paid building, but finite natural food can
			# still run out. Preserve enough wood labor until all three paid Farms and
			# the first Barracks foundation exist, then release it to the age resources.
			wood_target = mini(
				worker_count,
				maxi(2, ceili(float(worker_count) * FEUDAL_FARM_WOOD_WORKER_RATIO))
			)
		var reserve_workers: int = worker_count - wood_target
		var food_remaining: int = maxi(
			0,
			int(age_cost.get("food", 0)) - int(resources.get("food", 0))
		)
		var gold_remaining: int = maxi(
			0,
			int(age_cost.get("gold", 0)) - int(resources.get("gold", 0))
		)
		var total_remaining: int = food_remaining + gold_remaining
		if total_remaining > 0:
			var food_target: int = roundi(
				float(reserve_workers) * float(food_remaining) / float(total_remaining)
			)
			if food_remaining > 0:
				food_target = maxi(1, food_target)
			if gold_remaining > 0 and reserve_workers > 1:
				food_target = mini(reserve_workers - 1, food_target)
			food_target = clampi(food_target, 0, reserve_workers)
			return {
				"food": food_target,
				"wood": wood_target,
				"gold": reserve_workers - food_target,
			}
		# If the bank already covers the age transaction but a workforce/force gate
		# is still completing, extra food funds those fair unit queues while the
		# reserved gold remains untouched in the bank.
		return {
			"food": reserve_workers,
			"wood": wood_target,
			"gold": 0,
		}

	if _uses_compact_population_policy():
		# Paid worker/army queues spend food constantly. Keep a modest gold bank
		# for replacements, then move its labor back to food instead of floating
		# hundreds of gold while a ten-worker army waits for every food deposit.
		var wood_workers: int = maxi(1, roundi(float(worker_count) * 0.30))
		if age >= 2 and _get_compact_missing_role_building() >= 0:
			wood_workers = maxi(wood_workers, ceili(float(worker_count) * 0.45))
		if int(resources.get("wood", 0)) >= 250:
			wood_workers = 1
		var gold_workers: int = maxi(1, roundi(float(worker_count) * 0.15))
		var gold_bank_target: int = GameManager.get_player_population_limit(player_id) * 4
		if int(resources.get("gold", 0)) >= gold_bank_target:
			gold_workers = 0
		return {"food": maxi(0, worker_count - wood_workers - gold_workers), "wood": wood_workers, "gold": gold_workers}
	var ratios: Dictionary = _get_target_resource_ratio()
	var food_target: int = roundi(float(worker_count) * float(ratios.get("food", 0.0)))
	var wood_target: int = roundi(float(worker_count) * float(ratios.get("wood", 0.0)))
	food_target = clampi(food_target, 0, worker_count)
	wood_target = clampi(wood_target, 0, worker_count - food_target)
	return {
		"food": food_target,
		"wood": wood_target,
		"gold": worker_count - food_target - wood_target,
	}


func _needs_feudal_wood_infrastructure() -> bool:
	return (
		_feudal_paid_farm_foundations < _get_feudal_farm_capacity_target()
		or _barracks_count < 1
	)


func _needs_compact_worker_recovery() -> bool:
	if not _uses_compact_population_policy() or _game_time < 90.0:
		return false
	var recovery_floor: int = maxi(4, ceili(float(_get_target_villager_count()) * 0.60))
	# Paid pending workers cannot gather or defend themselves yet. Preserve the
	# recovery policy until real completions restore this live workforce floor.
	return _get_villagers().size() < recovery_floor


func _is_worker_retreating(villager: UnitBase) -> bool:
	return villager.has_method("is_retreating") and bool(villager.call("is_retreating"))


func _get_economy_work_counts() -> Dictionary:
	var counts: Dictionary = {"food": 0, "wood": 0, "gold": 0}
	for villager: UnitBase in _get_villagers():
		if _is_worker_retreating(villager):
			continue
		if villager.has_method("get_economy_task"):
			var task: String = str(villager.call("get_economy_task"))
			if counts.has(task):
				counts[task] = int(counts[task]) + 1
			continue
		var state: int = int(villager.get("current_state"))
		if state == UnitBase.State.BUILDING:
			continue
		var active_gather: bool = villager.has_method("has_active_gather_order") and bool(villager.call("has_active_gather_order"))
		var returning: bool = villager.has_method("is_returning_resources") and bool(villager.call("is_returning_resources"))
		if state != UnitBase.State.GATHERING and not active_gather and not returning:
			continue
		var resource_type: String = str(villager.get("carried_resource_type"))
		var pending_type: String = str(villager.get("_pending_gather_resource_type"))
		if counts.has(pending_type):
			resource_type = pending_type
		if counts.has(resource_type):
			counts[resource_type] = int(counts[resource_type]) + 1
	return counts


func _get_compact_missing_role_building() -> int:
	if not _uses_compact_population_policy() or GameManager.get_player_age(player_id) < 2:
		return -1
	# An observed ranged army makes the Stable the urgent unlock. Hidden enemy
	# composition never enters this choice, just as it never enters unit ranking.
	if _stable_count == 0:
		for enemy in _get_visible_enemies():
			if enemy.unit_type == UnitData.UnitType.ARCHER:
				return BuildingData.BuildingType.STABLE
	if _archery_range_count == 0:
		return BuildingData.BuildingType.ARCHERY_RANGE
	if _stable_count == 0:
		return BuildingData.BuildingType.STABLE
	return -1


func _service_pending_economy_rebalance() -> void:
	if _pending_economy_rebalance_type == "":
		return
	if _game_time > _pending_economy_rebalance_deadline:
		_clear_pending_economy_rebalance()
		return
	var candidates: Array = []
	for villager in _get_villagers():
		if _is_worker_retreating(villager):
			continue
		# BUILDING workers and MOVING dropoff workers are never interrupted. A loaded
		# GATHERING donor is safe because command_gather preserves and deposits its
		# old cargo before activating the requested resource type.
		if int(villager.get("current_state")) != UnitBase.State.GATHERING:
			continue
		if str(villager.get("carried_resource_type")) != _pending_economy_rebalance_from_type:
			continue
		candidates.append(villager)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		var a_cargo: int = int(a.get("carried_amount"))
		var b_cargo: int = int(b.get("carried_amount"))
		if a_cargo != b_cargo:
			return a_cargo < b_cargo
		return a.get_instance_id() < b.get_instance_id()
	)
	var preferred_type: String = _pending_economy_rebalance_type
	for candidate_variant: Variant in candidates:
		var chosen: UnitBase = candidate_variant as UnitBase
		# Only a direct current-visible, route-checked target may retask a loaded
		# donor. With no such target the request remains pending; memory/exploration
		# movement would strand or overwrite cargo and is intentionally forbidden.
		var resource_node: Node2D = _find_resource_for_villager(preferred_type, chosen)
		if resource_node == null or not _assign_villager_to_resource(chosen, resource_node):
			continue
		_remember_resource_sighting(preferred_type, resource_node.global_position)
		_economy_resource_assignments += 1
		_economy_rebalance_orders_issued += 1
		_last_economy_action = "rebalance_%s" % preferred_type
		_clear_pending_economy_rebalance()
		return


func _clear_pending_economy_rebalance() -> void:
	_pending_economy_rebalance_type = ""
	_pending_economy_rebalance_from_type = ""
	_pending_economy_rebalance_deadline = -INF


# ═════════════════════════════════════════════════════════════════════════
#  BUILDING CONSTRUCTION
# ═════════════════════════════════════════════════════════════════════════

func _check_building_construction() -> void:
	var age: int = GameManager.get_player_age(player_id)
	# One paid Farm secures food continuity, but the first Barracks is the hard
	# prerequisite for the declared military liveness floor. Before that force
	# floor is committed, do not let Farm 2 (or a cheaper support building) spend
	# the 150-wood Barracks bank.
	# Foundations are registered immediately, so _barracks_count also closes this
	# gate while the first Barracks is still under construction.
	var committed_military: int = _get_military_units().size() + _count_queued_military_units()
	var timed_force_floor_met: bool = (
		_timed_age_up_reserve_active
		and committed_military >= _get_min_military_for_age_up(2)
	)
	if (
		age <= 1
		and _farm_count >= 1
		and _barracks_count == 0
		and not timed_force_floor_met
	):
		if int(_rebuild_requests.get(BuildingData.BuildingType.BARRACKS, 0)) > 0:
			return
		var barracks_cost: Dictionary = BuildingData.get_building_cost(
			BuildingData.BuildingType.BARRACKS
		)
		if not ResourceManager.can_afford(player_id, barracks_cost):
			return
		var barracks_position: Vector2i = _find_build_location(
			BuildingData.BuildingType.BARRACKS
		)
		if barracks_position != Vector2i(-1, -1):
			ai_wants_to_build.emit(
				BuildingData.BuildingType.BARRACKS,
				barracks_position,
				false
			)
		return
	var target_counts: Dictionary = _get_target_building_counts(age)
	var build_order: Array = _get_build_order(age)

	for b_type in build_order:
		if _needs_compact_worker_recovery() and not _is_recovery_building(b_type):
			continue
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
		# A loss already owned by the rebuild ledger must not also be satisfied by
		# the normal target loop while its replacement foundation is constructing.
		if int(_rebuild_requests.get(b_type, 0)) > 0:
			continue

		if _saving_for_age_up and not _is_essential_building_while_saving(b_type):
			continue

		var cost: Dictionary = BuildingData.get_building_cost(b_type)
		if not ResourceManager.can_afford(player_id, cost):
			if b_type == _get_compact_missing_role_building() and _farm_count > 0:
				# Preserve the second troop-role unlock. An active paid Farm keeps
				# food flowing while wood banks; if the last Farm expires, its normal
				# paid replacement is still allowed below instead of starving workers.
				return
			# After the first paid Farm, preserve wood for the one Age-I military
			# production unlock. Otherwise an affordable Mill/camp later in the order
			# can repeatedly consume the 150-wood Barracks reserve.
			if (
				age <= 1
				and b_type == BuildingData.BuildingType.BARRACKS
				and current_count == 0
				and _farm_count > 0
			):
				return
			continue

		var pos: Vector2i = _find_build_location(b_type)
		if pos == Vector2i(-1, -1):
			continue

		ai_wants_to_build.emit(b_type, pos, false)
		return  # Only build one thing per tick to stay responsive


func _check_rebuilding() -> bool:
	## Replaces infrastructure that was actually lost, even when the normal
	## phase target has since changed. Requests persist through low resources,
	## blocked placement, and construction of an earlier replacement.
	if _rebuild_requests.is_empty() or _get_villagers().is_empty():
		return false

	var age: int = GameManager.get_player_age(player_id)
	for building_type in REBUILD_PRIORITY:
		if _needs_compact_worker_recovery() and not _is_recovery_building(building_type):
			continue
		var replacements_owed: int = int(_rebuild_requests.get(building_type, 0))
		if replacements_owed <= 0:
			continue
		var stats: Dictionary = BuildingData.get_building_stats(building_type)
		if age < int(stats.get("age_required", 0)):
			continue
		if _has_building_under_construction(building_type):
			continue
		var cost: Dictionary = BuildingData.get_building_cost(building_type)
		if not ResourceManager.can_afford(player_id, cost):
			continue
		var build_position: Vector2i = _find_build_location(building_type)
		if build_position == Vector2i(-1, -1):
			continue

		# Consume before synchronous signal dispatch so Main can restore the
		# request if preflight, spending, spawning, or assignment fails.
		if replacements_owed <= 1:
			_rebuild_requests.erase(building_type)
		else:
			_rebuild_requests[building_type] = replacements_owed - 1
		ai_wants_to_build.emit(building_type, build_position, true)
		_last_strategy_decision = "rebuild_%s" % BuildingData.get_building_name(building_type).to_snake_case()
		return true
	return false


# ═════════════════════════════════════════════════════════════════════════
#  MILITARY PRODUCTION
# ═════════════════════════════════════════════════════════════════════════

func _check_military_production() -> void:
	var military_count: int = _get_military_units().size()
	var queued_military_count: int = _count_queued_military_units()
	if _needs_compact_worker_recovery():
		# The Town Center worker transaction runs first in this same decision.
		# Preserve one earned worker cost while food is below it; do not let a
		# cheaper troop repeatedly consume the bank before replacement is possible.
		var worker_cost: Dictionary = UnitData.get_unit_cost(UnitData.UnitType.VILLAGER)
		if _find_building_of_type(BuildingData.BuildingType.TOWN_CENTER) != null and not ResourceManager.can_afford(player_id, worker_cost):
			return
	if _timed_age_up_reserve_active and not _is_under_pressure:
		var target_age: int = GameManager.get_player_age(player_id) + 1
		# Once the declared safety gate is met, military (including replacement
		# Scouts) must not consume every earned food deposit ahead of the age-up.
		# Queued units have already spent their resources and reserved population,
		# so they count toward the floor exactly like completed units.
		if military_count + queued_military_count >= _get_min_military_for_age_up(target_age):
			return
	elif _saving_for_age_up and not _is_under_pressure and military_count >= 4:
		return

	# Scouts are maintained as a real production choice. Hard fields a second
	# scout for wider memory coverage; a lost scout can be replaced instead of
	# leaving the AI permanently blind behind a one-shot boolean latch.
	var scout_target: int = int(SCOUT_TARGETS.get(difficulty, 1))
	if _uses_compact_population_policy() and GameManager.get_player_population_limit(player_id) <= 30:
		scout_target = 1
	var living_scouts: int = _get_scouts().size()
	var queued_scouts: int = _count_queued_unit(UnitData.UnitType.SCOUT)
	if living_scouts + queued_scouts < scout_target:
		var tc: Node = _find_trainable_building_of_type(BuildingData.BuildingType.TOWN_CENTER)
		if tc:
			var scout_cost: Dictionary = UnitData.get_unit_cost(UnitData.UnitType.SCOUT)
			var scout_pop_cost: int = int(UnitData.UNITS[UnitData.UnitType.SCOUT].get("pop_cost", 1))
			if GameManager.can_reserve_population(player_id, scout_pop_cost) and ResourceManager.can_afford(player_id, scout_cost):
				ai_wants_to_train.emit(tc, UnitData.UnitType.SCOUT)
				return

	if not _has_easy_compact_fighter_room():
		return

	if _uses_compact_population_policy() and GameManager.get_player_age(player_id) <= 1 and not _is_under_pressure:
		if military_count + queued_military_count >= _get_attack_threshold() + 1:
			return
	if _ai_state == AIState.EARLY_GAME and not _is_under_pressure and military_count >= 5:
		return  # In early game, cap military production

	var resources: Dictionary = ResourceManager.get_all_resources(player_id)
	var training_plan: Array = _get_military_training_plan(resources)
	var trains_allowed: int = 2 if _is_under_pressure else 1
	var trains_done: int = 0

	for unit_type in training_plan:
		var building_type: int = _get_training_building_type_for_unit(unit_type)
		if building_type < 0:
			continue
		if _uses_compact_population_policy() and (_get_fighting_units().size() >= 2 or not _is_under_pressure):
			# A cheaper fallback must not spend each first 20 wood while the ranked
			# Archer needs 45, or every first 50 food while the Horseman needs 90.
			# Wait only for an unlocked, available queue; missing structures never
			# block the opening, and a wiped army under current home pressure can
			# still buy an emergency defender. Safe rebuilding can bank the real cost.
			if _find_trainable_building_of_type(building_type) != null and not ResourceManager.can_afford(player_id, UnitData.get_unit_cost(unit_type)):
				return
		if _try_train_from_building(building_type, unit_type):
			trains_done += 1
			if trains_done >= trains_allowed:
				break


func _try_train_from_building(building_type: int, unit_type: int) -> bool:
	if unit_type != UnitData.UnitType.SCOUT and not _has_easy_compact_fighter_room():
		return false
	var building: Node = _find_trainable_building_of_type(building_type)
	if building == null:
		return false

	# Check pop room
	var pop_cost: int = UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1)
	if not GameManager.can_reserve_population(player_id, pop_cost):
		return false

	var cost: Dictionary = UnitData.get_unit_cost(unit_type)
	var role_unlock: int = _get_compact_missing_role_building()
	var committed_fighters: int = _get_fighting_units().size() + _count_queued_military_units() - _count_queued_unit(UnitData.UnitType.SCOUT)
	if role_unlock >= 0 and committed_fighters >= _get_attack_threshold():
		var unlock_wood: int = int(BuildingData.get_building_cost(role_unlock).get("wood", 0))
		if int(cost.get("wood", 0)) > 0 and ResourceManager.get_resource(player_id, "wood") - int(cost.get("wood", 0)) < unlock_wood:
			return false
	if ResourceManager.can_afford(player_id, cost):
		ai_wants_to_train.emit(building, unit_type)
		return true
	return false


# ═════════════════════════════════════════════════════════════════════════
#  AGE UP
# ═════════════════════════════════════════════════════════════════════════

func _check_age_up() -> void:
	if _needs_compact_worker_recovery():
		return
	if _get_compact_missing_role_building() >= 0:
		return
	var age: int = GameManager.get_player_age(player_id)
	if age >= GameManager.MAX_AGE:
		_saving_for_age_up = false
		return

	var target_age: int = age + 1
	var cost: Dictionary = GameManager.get_age_up_cost(player_id, target_age)
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
	var minimum: int = int(by_age.get(target_age, fallback))
	if _uses_compact_population_policy():
		var economy_target: int = _get_compact_economy_target()
		minimum = mini(minimum, economy_target - (2 if target_age == 2 else 1))
	return maxi(4, minimum)


func _get_min_military_for_age_up(target_age: int) -> int:
	var by_age: Dictionary = AGE_UP_MIN_MILITARY.get(difficulty, {})
	var fallback: int = 1 if target_age == 2 else 5
	var minimum: int = int(by_age.get(target_age, fallback))
	if _uses_compact_population_policy():
		var limit: int = GameManager.get_player_population_limit(player_id)
		var compact_gate: int = maxi(2, int(limit / 10)) if target_age == 2 else clampi(int(limit / 8), 3, 5)
		minimum = mini(minimum, compact_gate)
	return minimum


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


func _uses_compact_population_policy() -> bool:
	# Larger legacy scenarios keep their established opening and strategy gates.
	return GameManager.get_player_population_limit(player_id) < 80


func _get_compact_economy_target() -> int:
	var limit: int = GameManager.get_player_population_limit(player_id)
	if difficulty == Difficulty.EASY:
		return SkirmishData.get_easy_economy_target(limit)
	return SkirmishData.get_economy_target(limit)


func _has_easy_compact_fighter_room() -> bool:
	if not _uses_compact_population_policy() or difficulty != Difficulty.EASY:
		return true
	var committed_fighters: int = _get_fighting_units().size() + _count_queued_military_units() - _count_queued_unit(UnitData.UnitType.SCOUT)
	return committed_fighters < SkirmishData.get_easy_fighter_target(GameManager.get_player_population_limit(player_id))


func _get_feudal_farm_capacity_target() -> int:
	if not _uses_compact_population_policy():
		return FEUDAL_FARM_CAPACITY_TARGET
	return clampi(ceili(float(GameManager.get_player_population_limit(player_id)) / 20.0), 1, 3)


func _get_attack_threshold() -> int:
	var threshold: int = int(ARMY_ATTACK_THRESHOLDS.get(difficulty, 8))
	if _uses_compact_population_policy():
		threshold = mini(threshold, clampi(int(GameManager.get_player_population_limit(player_id) / 8), 3, 6))
	return threshold


func _get_target_villager_count() -> int:
	if _uses_compact_population_policy():
		var economy_target: int = _get_compact_economy_target()
		var current_age: int = GameManager.get_player_age(player_id)
		# A home defender can reach Feudal without ever dispatching a field wave.
		# Its paid workforce must still grow; otherwise repeated defense casualties
		# leave the economy permanently at the opening target with no unlock bank.
		var economy_ready: bool = current_age >= 2
		var target: int = economy_target if economy_ready else maxi(6, ceili(float(economy_target) * 0.70))
		if current_age <= 2 and (current_age == 1 or _has_launched_field_attack):
			var progression_floor: int = _get_min_villagers_for_age_up(current_age + 1)
			if _is_under_pressure:
				progression_floor += 1
			target = maxi(target, progression_floor)
		return mini(economy_target, target)
	var base_target: int = VILLAGER_TARGETS.get(difficulty, 18)
	var age: int = GameManager.get_player_age(player_id)
	if age >= 2:
		base_target += 2
	if age >= 3:
		base_target += 4
	if _is_under_pressure:
		base_target = maxi(10, base_target - 3)
	var next_age: int = age + 1
	if not GameManager.get_age_up_cost(player_id, next_age).is_empty():
		# Difficulty population targets must never make their own next-age gate
		# unreachable. Pressure asks for one additional survivor rather than letting
		# the generic target reduction deadlock progression below that gate.
		var progression_floor: int = _get_min_villagers_for_age_up(next_age)
		if _is_under_pressure:
			progression_floor += 1
		base_target = maxi(base_target, progression_floor)
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
	if _timed_age_up_reserve_active and age <= 1:
		# A depleted Farm has already delivered part or all of its paid finite stock.
		# Request only the remaining number of paid foundations, rather than resetting
		# to three simultaneous live Farms and creating an unbounded rebuild treadmill.
		var remaining_paid_farms: int = maxi(
			0,
			_get_feudal_farm_capacity_target() - _feudal_paid_farm_foundations
		)
		farm_target = maxi(farm_target, _farm_count + remaining_paid_farms)
	if _is_under_pressure:
		farm_target = maxi(1, farm_target)
	if _get_compact_missing_role_building() >= 0:
		farm_target = mini(farm_target, 1)

	var targets: Dictionary = {
		# Houses are exclusively demand-driven by _check_house_need().
		BuildingData.BuildingType.HOUSE: 0,
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
	if _uses_compact_population_policy():
		# A second TC/production duplicate cannot earn its cost back with a ten
		# to twenty worker economy and small replacement queues. Spend on troops.
		for building_type in [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE, BuildingData.BuildingType.MILL, BuildingData.BuildingType.LUMBER_CAMP, BuildingData.BuildingType.MINING_CAMP]:
			targets[building_type] = mini(int(targets[building_type]), 1)
		targets[BuildingData.BuildingType.SIEGE_WORKSHOP] = 0
	return targets


func _get_build_order(age: int) -> Array:
	if _uses_compact_population_policy() and age >= 2:
		# Real drop-offs earn the unlock bank; both combat roles precede optional
		# support. Under attack, currently visible Archers can put Stable first.
		var ranged_role: int = BuildingData.BuildingType.ARCHERY_RANGE
		var mounted_role: int = BuildingData.BuildingType.STABLE
		if _get_compact_missing_role_building() == mounted_role:
			return [BuildingData.BuildingType.FARM, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.LUMBER_CAMP, BuildingData.BuildingType.MILL, mounted_role, ranged_role, BuildingData.BuildingType.MINING_CAMP, BuildingData.BuildingType.WATCH_TOWER, BuildingData.BuildingType.BLACKSMITH]
		return [BuildingData.BuildingType.FARM, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.LUMBER_CAMP, BuildingData.BuildingType.MILL, ranged_role, mounted_role, BuildingData.BuildingType.MINING_CAMP, BuildingData.BuildingType.WATCH_TOWER, BuildingData.BuildingType.BLACKSMITH]
	if _is_under_pressure:
		return [
			BuildingData.BuildingType.HOUSE,
			BuildingData.BuildingType.FARM,
			BuildingData.BuildingType.BARRACKS,
			BuildingData.BuildingType.MILL,
			BuildingData.BuildingType.WATCH_TOWER,
			BuildingData.BuildingType.LUMBER_CAMP,
			BuildingData.BuildingType.MINING_CAMP,
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
		BuildingData.BuildingType.FARM,
		BuildingData.BuildingType.BARRACKS,
		BuildingData.BuildingType.MILL,
		BuildingData.BuildingType.LUMBER_CAMP,
		BuildingData.BuildingType.MINING_CAMP,
		BuildingData.BuildingType.BLACKSMITH,
		BuildingData.BuildingType.ARCHERY_RANGE,
		BuildingData.BuildingType.STABLE,
		BuildingData.BuildingType.WATCH_TOWER,
	]


func _is_essential_building_while_saving(building_type: int) -> bool:
	if building_type == _get_compact_missing_role_building():
		return true
	if building_type == BuildingData.BuildingType.HOUSE:
		return true
	# Unlock one real military production queue before reserving the economy for
	# an age-up. This costs the same 150 wood as it does for the human player;
	# it only prevents the fair opening from starving its own liveness.
	if building_type == BuildingData.BuildingType.BARRACKS:
		return _barracks_count == 0
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

	var filtered: Array = []
	for unit_type in plan:
		if _uses_compact_population_policy() and unit_type == UnitData.UnitType.SIEGE:
			continue
		if _uses_compact_population_policy():
			filtered.append(unit_type)
			continue
		var cost: Dictionary = UnitData.get_unit_cost(unit_type)
		var affordable: bool = true
		for resource_type in cost:
			if int(resources.get(resource_type, 0)) < int(cost[resource_type]):
				affordable = false
				break
		if not affordable:
			continue
		filtered.append(unit_type)
	if not _uses_compact_population_policy() and _ai_state == AIState.LATE_GAME and int(resources.get("wood", 0)) >= 220 and int(resources.get("gold", 0)) >= 130:
		filtered.append(UnitData.UnitType.SIEGE)
	if _uses_compact_population_policy():
		filtered = _rank_compact_military_plan(filtered)
	return filtered


func _rank_compact_military_plan(plan: Array) -> Array:
	var counts: Dictionary = {}
	for unit_type in plan:
		counts[unit_type] = _count_queued_unit(unit_type)
	for unit in _get_military_units():
		if counts.has(unit.unit_type):
			counts[unit.unit_type] = int(counts[unit.unit_type]) + 1
	var visible_counters: Dictionary = {}
	var observed_fighters: int = 0
	for enemy in _get_visible_enemies():
		if not (enemy is UnitBase) or enemy.damage <= 0.0 or enemy.unit_type == UnitData.UnitType.VILLAGER:
			continue
		observed_fighters += 1
		for unit_type in counts:
			if Combat.get_counter_bonus(unit_type, enemy.unit_type) > 1.0:
				visible_counters[unit_type] = int(visible_counters.get(unit_type, 0)) + 1
	var unique_plan: Array = []
	for unit_type in plan:
		if unit_type not in unique_plan:
			unique_plan.append(unit_type)
	unique_plan.sort_custom(func(a: int, b: int) -> bool:
		# Keep a mixed army while giving the observed counter a larger share.
		# A capped additive bonus stopped adapting once an army exceeded six units.
		# Relative committed population also includes the already-paid queue, so
		# repeated decisions cannot order five copies before the first completes.
		var a_pop: int = int(UnitData.UNITS[a].get("pop_cost", 1))
		var b_pop: int = int(UnitData.UNITS[b].get("pop_cost", 1))
		var a_weight: float = 1.0 + 2.0 * float(visible_counters.get(a, 0)) / maxf(1.0, float(observed_fighters))
		var b_weight: float = 1.0 + 2.0 * float(visible_counters.get(b, 0)) / maxf(1.0, float(observed_fighters))
		var a_score: float = float(int(counts[a]) * a_pop + 1) / a_weight
		var b_score: float = float(int(counts[b]) * b_pop + 1) / b_weight
		if is_equal_approx(a_score, b_score):
			# After a wipe, equal zero living counts must not restart the same cheap
			# Warrior indefinitely. Own completed-role history rotates the tie toward
			# the role that has been absent longest; current visible counters win first.
			var a_last: float = float(_military_role_last_fielded.get(a, -INF))
			var b_last: float = float(_military_role_last_fielded.get(b, -INF))
			return a < b if a_last == b_last else a_last < b_last
		return a_score < b_score
	)
	return unique_plan


func _is_recovery_building(building_type: int) -> bool:
	if building_type in [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.FARM]:
		return true
	return building_type == BuildingData.BuildingType.BARRACKS and _barracks_count == 0


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
	if _needs_compact_worker_recovery():
		return
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
	# Before the configured objective time, scouts take one validated route to a
	# base-side lookout and hold there. They must not cycle to an enemy-side
	# waypoint because the connecting chord can cross the Sacred capture disk.
	if _scout_waypoints.is_empty():
		var center: Vector2 = _tile_to_world(Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2))
		_build_scout_waypoints(center)
	var sacred_site: Node2D = _get_sacred_site()
	var hold_before_objective: bool = sacred_site != null and _should_hold_sacred_recon(sacred_site)
	var scouts: Array = _get_scouts()
	if hold_before_objective:
		# Task ownership keeps recon Scouts out of generic staging and raids. Live
		# base defense still releases this list and recalls every military unit.
		_objective_units = scouts.duplicate()
	for unit in scouts:
		if hold_before_objective:
			_objective_scout_sent = true
			_objective_mode = ObjectiveMode.SCOUT
			_last_strategy_decision = "scout_sacred_site"
			_maintain_safe_sacred_recon(unit as UnitBase, sacred_site)
			continue
		if unit in _objective_units:
			continue
		# Once the timer opens (or an enemy preempts it), the objective policy later
		# in this tick owns the Scout's next order.
		unit.stance = UnitBase.Stance.AGGRESSIVE
		if sacred_site != null:
			continue
		if unit.current_state != UnitBase.State.IDLE:
			continue
		if not _objective_scout_sent:
			_objective_scout_sent = true
			_objective_mode = ObjectiveMode.SCOUT
			_last_strategy_decision = "scout_sacred_site"
			unit.command_move(_scout_waypoints[0])
			continue
		var target: Vector2 = _scout_waypoints[_next_scout_waypoint_index % _scout_waypoints.size()]
		_next_scout_waypoint_index = (_next_scout_waypoint_index + 1) % _scout_waypoints.size()
		unit.command_move(target)


func _is_sacred_timing_ready() -> bool:
	if _uses_compact_population_policy() and not _has_launched_field_attack:
		return false
	return _game_time >= float(SACRED_SITE_START_TIMES.get(difficulty, 150.0))


func _should_hold_sacred_recon(sacred_site: Node2D) -> bool:
	if _is_sacred_timing_ready():
		return false
	const SITE_CAPTURING: int = 1
	const SITE_CAPTURED: int = 2
	const SITE_CONTESTED: int = 3
	var site_state: int = int(sacred_site.get("state"))
	var owner: int = int(sacred_site.get("owning_player"))
	if owner == enemy_id and site_state in [SITE_CAPTURING, SITE_CAPTURED, SITE_CONTESTED]:
		return false
	if site_state == SITE_CONTESTED or not _get_visible_site_threats(sacred_site).is_empty():
		return false
	return true


func _maintain_safe_sacred_recon(unit: UnitBase, sacred_site: Node2D) -> void:
	unit.stance = UnitBase.Stance.STAND_GROUND
	var recon_position: Vector2 = _get_sacred_recon_position(sacred_site)
	if (
		unit.current_state == UnitBase.State.IDLE
		and unit.global_position.distance_to(recon_position) <= SACRED_RECON_TARGET_TOLERANCE
	):
		return

	var remaining_route := PackedVector2Array()
	if unit.current_state == UnitBase.State.MOVING and unit.move_target.distance_to(recon_position) <= SACRED_RECON_TARGET_TOLERANCE:
		for route_index in range(unit.path_index, unit.path.size()):
			remaining_route.append(unit.path[route_index])
		if not remaining_route.is_empty() and _is_route_outside_sacred_capture(unit.global_position, remaining_route, sacred_site):
			return

	# Stop any stale/unsafe scouting leg before calculating a replacement. This
	# also prevents aggressive auto-targeting from pulling recon through the site.
	if unit.current_state != UnitBase.State.IDLE:
		unit.command_stop()
	var route: PackedVector2Array = _get_sacred_recon_route(unit.global_position, recon_position)
	if route.is_empty() or not _is_route_outside_sacred_capture(unit.global_position, route, sacred_site):
		return
	unit.command_move_path(route)


func _get_sacred_recon_position(sacred_site: Node2D) -> Vector2:
	var outward: Vector2 = (_base_position - sacred_site.global_position).normalized()
	if outward == Vector2.ZERO:
		outward = Vector2.UP
	return sacred_site.global_position + outward * (_get_sacred_capture_world_radius(sacred_site) + SACRED_RECON_MARGIN)


func _get_sacred_recon_route(from_position: Vector2, recon_position: Vector2) -> PackedVector2Array:
	if game_map != null and game_map.has_method("get_navigation_world_path"):
		return game_map.call("get_navigation_world_path", from_position, recon_position, 4.0) as PackedVector2Array
	return PackedVector2Array([recon_position])


func _is_route_outside_sacred_capture(
	from_position: Vector2,
	route: PackedVector2Array,
	sacred_site: Node2D
) -> bool:
	if route.is_empty():
		return false
	var minimum_distance: float = _get_sacred_capture_world_radius(sacred_site) + SACRED_RECON_ROUTE_CLEARANCE
	var previous: Vector2 = from_position
	if previous.distance_to(sacred_site.global_position) <= minimum_distance:
		return false
	for waypoint in route:
		if waypoint.distance_to(sacred_site.global_position) <= minimum_distance:
			return false
		if _distance_from_point_to_segment(sacred_site.global_position, previous, waypoint) <= minimum_distance:
			return false
		previous = waypoint
	return true


func _distance_from_point_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment: Vector2 = segment_end - segment_start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(segment_start)
	var interpolation: float = clampf((point - segment_start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(segment_start + segment * interpolation)


func _get_sacred_capture_world_radius(sacred_site: Node2D) -> float:
	var radius_tiles: float = float(sacred_site.get("capture_radius")) if sacred_site.get("capture_radius") != null else 3.0
	return radius_tiles * float(MapData.TILE_WIDTH)


func _check_sacred_site_strategy() -> bool:
	## Returns true when an active contest is important enough to suppress the
	## ordinary raid/attack plan for this decision tick.
	var sacred_site: Node2D = _get_sacred_site()
	if sacred_site == null:
		_release_objective_units()
		return false

	const SITE_NEUTRAL: int = 0
	const SITE_CAPTURING: int = 1
	const SITE_CAPTURED: int = 2
	const SITE_CONTESTED: int = 3
	var site_state: int = int(sacred_site.get("state"))
	var owner: int = int(sacred_site.get("owning_player"))
	var site_threats: Array = _get_visible_site_threats(sacred_site)
	var enemy_claiming: bool = owner == enemy_id and site_state in [SITE_CAPTURING, SITE_CAPTURED, SITE_CONTESTED]
	var own_claim: bool = owner == player_id and site_state in [SITE_CAPTURING, SITE_CAPTURED, SITE_CONTESTED]
	var active_contest: bool = site_state == SITE_CONTESTED or not site_threats.is_empty()
	var policy_ready: bool = (
		_is_sacred_timing_ready()
		or enemy_claiming
		or active_contest
	)

	if not policy_ready:
		if _objective_mode != ObjectiveMode.SCOUT:
			_release_objective_units()
		return false

	var new_mode: ObjectiveMode = ObjectiveMode.CAPTURE
	var desired_force: int = int(SACRED_CAPTURE_FORCES.get(difficulty, 3))
	var blocks_offense: bool = false
	var urgent: bool = false
	if enemy_claiming or active_contest:
		new_mode = ObjectiveMode.CONTEST
		desired_force = int(SACRED_CONTEST_FORCES.get(difficulty, 5))
		blocks_offense = true
		urgent = true
		if owner == enemy_id and site_state == SITE_CAPTURED:
			var hold_time: float = float(sacred_site.get("victory_hold_time"))
			var held_time: float = float(sacred_site.get("victory_timer"))
			if hold_time - held_time <= 75.0:
				desired_force += 2
	elif owner == player_id and site_state == SITE_CAPTURED:
		new_mode = ObjectiveMode.DEFEND
		desired_force = int(SACRED_DEFENDER_FORCES.get(difficulty, 2))
	elif own_claim:
		new_mode = ObjectiveMode.CAPTURE

	if _uses_compact_population_policy():
		var limit: int = GameManager.get_player_population_limit(player_id)
		# One Scout can secure an uncontested site. Keep combat units available
		# for actual pressure instead of parking most of a small army as guards.
		if new_mode == ObjectiveMode.CAPTURE:
			desired_force = 1
		elif new_mode == ObjectiveMode.DEFEND:
			desired_force = 1 if limit <= 30 else 2
		else:
			# A mature compact army must commit to the contested battlefield rather
			# than lose three replacements at a time while the rest wait at home.
			# The last two minutes of a hostile hold justify the full combat force.
			var fighters: int = _get_fighting_units().size()
			desired_force = maxi(_get_attack_threshold(), ceili(float(fighters) * 0.75))
			if owner == enemy_id and site_state == SITE_CAPTURED:
				var remaining_hold: float = float(sacred_site.get("victory_hold_time")) - float(sacred_site.get("victory_timer"))
				if remaining_hold <= 120.0:
					desired_force = maxi(desired_force, fighters)
	var mode_changed: bool = new_mode != _objective_mode
	_objective_mode = new_mode
	_assign_objective_force(sacred_site, desired_force, urgent, mode_changed, site_threats)
	match _objective_mode:
		ObjectiveMode.CAPTURE:
			_last_strategy_decision = "capture_sacred_site"
		ObjectiveMode.CONTEST:
			_last_strategy_decision = "contest_sacred_site"
		ObjectiveMode.DEFEND:
			_last_strategy_decision = "defend_sacred_site"
		_:
			pass
	return blocks_offense


func _assign_objective_force(
	sacred_site: Node2D,
	desired_force: int,
	urgent: bool,
	mode_changed: bool,
	site_threats: Array
) -> void:
	var all_military: Array = _get_military_units()
	var reserve: Array = _get_base_reserve_units(all_military)
	var candidates: Array = []
	for unit in all_military:
		if not is_instance_valid(unit):
			continue
		var hp_ratio: float = unit.hp / maxf(1.0, unit.max_hp)
		# There is no healing system in this iteration. Permanently excluding
		# wounded units from an urgent contest can immobilize a full-pop army and
		# prevent both fighting and paid replacements for the rest of the match.
		if hp_ratio <= 0.4 and not urgent:
			continue
		if _objective_mode == ObjectiveMode.CONTEST and unit.unit_type == UnitData.UnitType.SCOUT and not _get_fighting_units().is_empty():
			continue
		if unit in reserve:
			continue
		if not urgent and unit in _attack_wave_units:
			continue
		candidates.append(unit)

	# A late hostile hold can pull the normal base reserve as a last resort.
	if urgent and candidates.size() < desired_force:
		for unit in reserve:
			if unit not in candidates:
				candidates.append(unit)

	candidates.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		return _objective_candidate_score(a, sacred_site.global_position) > _objective_candidate_score(b, sacred_site.global_position)
	)
	var selected_count: int = mini(desired_force, candidates.size())
	var selected: Array = candidates.slice(0, selected_count)
	_objective_units = selected
	for unit in _objective_units:
		if is_instance_valid(unit) and unit is UnitBase:
			(unit as UnitBase).stance = UnitBase.Stance.AGGRESSIVE

	if urgent and _attack_in_progress:
		_clear_attack_wave()
	_issue_objective_orders(sacred_site, urgent, mode_changed, site_threats)


func _objective_candidate_score(unit: UnitBase, site_position: Vector2) -> float:
	var score: float = -unit.global_position.distance_to(site_position)
	if unit in _objective_units:
		score += 800.0
	if unit.unit_type == UnitData.UnitType.SCOUT:
		score += 320.0 if _objective_mode != ObjectiveMode.CONTEST else -160.0
	else:
		score += _evaluate_unit_combat_strength(unit) * 0.02
	return score


func _issue_objective_orders(
	sacred_site: Node2D,
	urgent: bool,
	mode_changed: bool,
	site_threats: Array
) -> void:
	var refresh_orders: bool = _game_time - _objective_order_time >= SACRED_SITE_ORDER_REFRESH
	var issued_order: bool = false
	var target_allocations: Dictionary = {}
	for index in _objective_units.size():
		var unit: UnitBase = _objective_units[index] as UnitBase
		if not is_instance_valid(unit):
			continue
		if _objective_mode == ObjectiveMode.CONTEST and not site_threats.is_empty() and unit.damage > 0.0:
			var threat: UnitBase = _choose_counter_target(unit, site_threats, target_allocations)
			if threat == null:
				continue
			var already_fighting_threat: bool = unit.current_state == UnitBase.State.ATTACKING and unit.attack_target == threat
			if is_instance_valid(threat) and not already_fighting_threat and (urgent or mode_changed or refresh_orders or unit.current_state == UnitBase.State.IDLE):
				unit.command_attack(threat)
				issued_order = true
			continue

		var angle: float = TAU * float(index) / float(maxi(1, _objective_units.size()))
		var slot_position: Vector2 = sacred_site.global_position + Vector2.from_angle(angle) * 38.0
		var outside_hold_area: bool = unit.global_position.distance_to(sacred_site.global_position) > SACRED_SITE_HOLD_RADIUS
		var heading_elsewhere: bool = (
			unit.current_state == UnitBase.State.MOVING
			and unit.move_target.distance_to(sacred_site.global_position) > SACRED_SITE_HOLD_RADIUS
		)
		var already_heading_to_site: bool = unit.current_state == UnitBase.State.MOVING and not heading_elsewhere
		var needs_urgent_advance: bool = urgent and outside_hold_area and not already_heading_to_site and unit.current_state != UnitBase.State.ATTACKING
		if mode_changed or heading_elsewhere or needs_urgent_advance or (outside_hold_area and (refresh_orders or unit.current_state == UnitBase.State.IDLE)):
			unit.command_attack_move(slot_position)
			issued_order = true
	if issued_order:
		_objective_order_time = _game_time


func _get_visible_site_threats(sacred_site: Node2D) -> Array:
	var threats: Array = []
	for enemy in _get_visible_enemies():
		if enemy.global_position.distance_to(sacred_site.global_position) <= SACRED_SITE_THREAT_RADIUS:
			threats.append(enemy)
	return threats


func _get_sacred_site() -> Node2D:
	if game_map == null:
		return null
	var candidate: Variant = game_map.get("sacred_site")
	if candidate is Node2D and is_instance_valid(candidate):
		return candidate as Node2D
	return null


func _release_objective_units() -> void:
	_objective_units.clear()
	_objective_mode = ObjectiveMode.NONE
	_objective_order_time = -INF


func _micro_damaged_units() -> void:
	var fallback_point: Vector2 = _base_position.lerp(_staging_point, 0.55)
	for unit in _get_military_units():
		if not is_instance_valid(unit):
			continue
		if _uses_compact_population_policy() and _objective_mode == ObjectiveMode.CONTEST and unit in _objective_units:
			continue  # Urgent committed forces must not have every attack canceled by micro.
		if unit.unit_type == UnitData.UnitType.SIEGE:
			continue
		var hp_ratio: float = unit.hp / maxf(1.0, unit.max_hp)
		if hp_ratio > 0.35:
			continue
		if unit.global_position.distance_to(fallback_point) < 48.0:
			continue
		unit.command_move(fallback_point)


# ═════════════════════════════════════════════════════════════════════════
#  ATTACK / DEFENSE
# ═════════════════════════════════════════════════════════════════════════

func _check_attack_or_defend() -> void:
	# A current or very recent threat to any critical home structure overrides
	# map objectives and offense. This prevents armies from marching away while
	# production, population, or drop-off infrastructure is being dismantled.
	var defense_threats: Array = _find_defense_threats()
	if not defense_threats.is_empty():
		_clear_attack_wave()
		_release_objective_units()
		_rally_defense(defense_threats)
		_last_strategy_decision = "base_defense"
		return
	if _has_recent_defense_threat():
		_rally_defense([])
		_last_strategy_decision = "search_last_base_threat"
		return

	if _check_sacred_site_strategy():
		return

	# Objective guards and a small home reserve are deliberately omitted from
	# ordinary raids. Difficulty changes cadence and commitment, not resources.
	var reserve: Array = _get_base_reserve_units(_get_military_units())
	_rally_base_reserve(reserve)
	var military: Array = _get_field_military(reserve)
	var threshold: int = _get_attack_threshold()
	var own_strength: float = maxf(1.0, _evaluate_units_strength(military))
	var visible_enemy_strength: float = _evaluate_enemy_visible_strength()

	if _attack_in_progress:
		if not _refresh_attack_wave_lifecycle():
			# Ended waves get one decision interval to settle before the same
			# survivors (or a replacement army) can launch again.
			return
		# Check if we should retreat
		var outmatched: bool = visible_enemy_strength > own_strength * 1.2 and visible_enemy_strength > 180.0
		if military.size() < maxi(2, int(threshold * _retreat_threshold)) or outmatched:
			_retreat_army()
			_clear_attack_wave()
			_last_strategy_decision = "retreat"
		return

	# Gather idle military at staging point
	var idle_military: Array = _get_idle_units_from(military)
	for unit in idle_military:
		if unit.global_position.distance_to(_staging_point) > 64.0:
			unit.command_move(_staging_point)

	# Easy gives a compact opening time to reach Feudal and unlock counters.
	# Visible home defense and active Sacred contests were handled above, so
	# this pacing gate only delays ordinary raids while production/recon continue.
	if _uses_compact_population_policy() and difficulty == Difficulty.EASY and _game_time < 300.0:
		_last_strategy_decision = "opening_staging"
		return

	# Difficulty-specific timed aggression can launch even with a small army.
	var force_attack_time: float = 180.0
	match difficulty:
		Difficulty.EASY: force_attack_time = 300.0
		Difficulty.MEDIUM: force_attack_time = 180.0
		Difficulty.HARD: force_attack_time = 120.0

	var force_attack: bool = _game_time >= force_attack_time and military.size() >= 3

	# Launch full attack if army is strong enough or timed threshold reached
	if military.size() >= threshold or force_attack:
		var target_selection: Dictionary = _find_enemy_target_selection()
		if not target_selection.is_empty():
			var target: Vector2 = target_selection.get("position", Vector2(-1, -1))
			var target_node: Node = target_selection.get("node") as Node
			_send_attack(military, target)
			_begin_attack_wave(military, target, target_node)
			_last_strategy_decision = "full_attack"
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
				ai_attack_launched.emit(raiders, target)
				_last_strategy_decision = "harass"


func _begin_attack_wave(units: Array, target_position: Vector2, target_node: Node = null) -> void:
	_attack_in_progress = true
	_has_launched_field_attack = true
	_attack_wave_units.clear()
	for candidate in units:
		# Keep the loop variable untyped until validity has been checked. A freed
		# Object remains in an Array as a placeholder that cannot be converted to
		# Node for a typed filter predicate.
		if not _is_live_tree_node(candidate) or not (candidate is UnitBase):
			continue
		var unit: UnitBase = candidate as UnitBase
		if unit.current_state != UnitBase.State.DEAD:
			_attack_wave_units.append(unit)
	_attack_wave_target_position = target_position
	var can_track_target: bool = is_instance_valid(target_node) and _is_enemy_currently_visible(target_node)
	_attack_wave_target_ref = weakref(target_node) if can_track_target else null
	_attack_wave_best_distance = _get_closest_wave_distance(_attack_wave_units, target_position)
	_attack_wave_best_target_hp = _get_attack_target_hp(target_node) if can_track_target else INF
	_attack_wave_last_progress_time = _game_time


func _refresh_attack_wave_lifecycle() -> bool:
	var survivors: Array = _get_attack_wave_survivors()
	_attack_wave_units = survivors
	if survivors.is_empty():
		_clear_attack_wave()
		return false

	var target_node: Node = _get_attack_wave_target_node()
	# Losing sight turns a live target into a position-only attack-move. Preserve
	# the last visible position/HP and discard the weak reference before reading
	# any current hidden state. An unresolved previously-live WeakRef is treated
	# identically: queue_free while hidden must not become a retarget oracle.
	if _attack_wave_target_ref != null and target_node == null:
		_attack_wave_target_ref = null
	elif target_node != null and not _is_enemy_currently_visible(target_node):
		_attack_wave_target_ref = null
		target_node = null
	if not _is_attack_wave_target_valid(target_node):
		if _retarget_attack_wave(survivors):
			return true
		_clear_attack_wave()
		return false

	if target_node != null:
		_attack_wave_target_position = target_node.global_position

	if _has_attack_wave_arrived_or_idled(survivors):
		_clear_attack_wave()
		return false

	var made_progress: bool = false
	var closest_distance: float = _get_closest_wave_distance(survivors, _attack_wave_target_position)
	if closest_distance + ATTACK_WAVE_PROGRESS_EPSILON < _attack_wave_best_distance:
		_attack_wave_best_distance = closest_distance
		made_progress = true

	var target_hp: float = _get_attack_target_hp(target_node)
	if target_hp + 0.5 < _attack_wave_best_target_hp:
		_attack_wave_best_target_hp = target_hp
		made_progress = true

	if made_progress:
		_attack_wave_last_progress_time = _game_time
	elif _game_time - _attack_wave_last_progress_time >= ATTACK_WAVE_NO_PROGRESS_TIMEOUT:
		_clear_attack_wave()
		return false
	return true


func _get_attack_wave_survivors() -> Array:
	var survivors: Array = []
	for unit in _attack_wave_units:
		if not is_instance_valid(unit) or not unit.is_inside_tree():
			continue
		if not (unit is UnitBase) or unit.current_state == UnitBase.State.DEAD:
			continue
		survivors.append(unit)
	return survivors


func _has_attack_wave_arrived_or_idled(survivors: Array) -> bool:
	for unit in survivors:
		if unit.current_state == UnitBase.State.ATTACKING:
			return false
		if unit.current_state == UnitBase.State.IDLE:
			continue
		if unit.global_position.distance_to(_attack_wave_target_position) <= ATTACK_WAVE_ARRIVAL_RADIUS:
			continue
		return false
	return true


func _retarget_attack_wave(survivors: Array) -> bool:
	var target_selection: Dictionary = _find_enemy_target_selection()
	if target_selection.is_empty():
		return false
	var target_position: Vector2 = target_selection.get("position", Vector2(-1, -1))
	var target_node: Node = target_selection.get("node") as Node
	_issue_attack_orders(survivors, target_position)
	_attack_wave_target_position = target_position
	var can_track_target: bool = is_instance_valid(target_node) and _is_enemy_currently_visible(target_node)
	_attack_wave_target_ref = weakref(target_node) if can_track_target else null
	_attack_wave_best_distance = _get_closest_wave_distance(survivors, target_position)
	_attack_wave_best_target_hp = _get_attack_target_hp(target_node) if can_track_target else INF
	_attack_wave_last_progress_time = _game_time
	return true


func _get_attack_wave_target_node() -> Node:
	if _attack_wave_target_ref == null:
		return null
	var target: Variant = _attack_wave_target_ref.get_ref()
	return target as Node if target is Node else null


func _is_attack_wave_target_valid(target_node: Node) -> bool:
	# A null weak reference means this wave is advancing on the known enemy
	# spawn rather than a currently visible object.
	if _attack_wave_target_ref == null:
		return true
	# Check visibility first so validity itself never reads hidden target state.
	return _is_enemy_currently_visible(target_node) and _is_attack_wave_target_alive(target_node)


func _is_attack_wave_target_alive(target_node: Node) -> bool:
	if not is_instance_valid(target_node) or not target_node.is_inside_tree():
		return false
	if target_node is UnitBase:
		return target_node.current_state != UnitBase.State.DEAD
	if target_node is BuildingBase:
		return target_node.state != BuildingBase.State.DESTROYED
	return true


func _get_attack_target_hp(target_node: Node) -> float:
	if target_node is UnitBase:
		return float(target_node.hp)
	if target_node is BuildingBase:
		return float(target_node.hp)
	return INF


func _get_closest_wave_distance(units: Array, target_position: Vector2) -> float:
	var closest_distance: float = INF
	for unit in units:
		if is_instance_valid(unit):
			closest_distance = minf(closest_distance, unit.global_position.distance_to(target_position))
	return closest_distance


func _clear_attack_wave() -> void:
	_attack_in_progress = false
	_attack_wave_units.clear()
	_attack_wave_target_position = Vector2(-1, -1)
	_attack_wave_target_ref = null
	_attack_wave_best_distance = INF
	_attack_wave_best_target_hp = INF
	_attack_wave_last_progress_time = _game_time


func _is_base_under_attack() -> bool:
	return not _find_defense_threats().is_empty()


func _find_defense_threats() -> Array:
	var anchors: Array[Vector2] = [_base_position]
	for building in _my_buildings:
		if not is_instance_valid(building) or not (building is BuildingBase):
			continue
		if building.state == BuildingBase.State.DESTROYED:
			continue
		# Farms are replaceable map economy. Everything else is infrastructure
		# worth reacting to, including a House whose loss may population-block us.
		if building.building_type != BuildingData.BuildingType.FARM:
			anchors.append(building.global_position)

	var threats: Array = []
	for enemy in _get_visible_enemies():
		if enemy.damage <= 0.0:
			continue
		for anchor in anchors:
			if enemy.global_position.distance_to(anchor) <= BASE_DEFENSE_RADIUS:
				threats.append(enemy)
				break
	threats.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		return _score_defense_threat(a, anchors) > _score_defense_threat(b, anchors)
	)
	return threats


func _score_defense_threat(enemy: UnitBase, anchors: Array[Vector2]) -> float:
	var nearest_anchor: float = INF
	for anchor in anchors:
		nearest_anchor = minf(nearest_anchor, enemy.global_position.distance_to(anchor))
	var score: float = BASE_DEFENSE_RADIUS - nearest_anchor
	if enemy.unit_type == UnitData.UnitType.SIEGE:
		score += 500.0
	elif enemy.unit_type == UnitData.UnitType.CAVALRY:
		score += 180.0
	elif enemy.unit_type == UnitData.UnitType.ARCHER:
		score += 120.0
	return score


func _has_recent_defense_threat() -> bool:
	return _game_time - _last_defense_threat_time <= DEFENSE_MEMORY_SECONDS


func _rally_defense(threats: Array = []) -> void:
	var military: Array = _get_fighting_units()
	if threats.is_empty():
		for unit in military:
			var already_investigating: bool = (
				unit.current_state == UnitBase.State.MOVING
				and unit.move_target.distance_to(_last_defense_threat_position) <= 16.0
			)
			if not already_investigating and unit.current_state != UnitBase.State.ATTACKING:
				unit.command_attack_move(_last_defense_threat_position)
		return

	# Assign the visible matchup before distributing spare defenders. Cavalry
	# should reach Archers while spear infantry meet cavalry, rather than all roles
	# cycling through the same list without regard to their paid counter purpose.
	var target_allocations: Dictionary = {}
	for i in military.size():
		var unit: UnitBase = military[i]
		var target_enemy: UnitBase = _choose_counter_target(unit, threats, target_allocations)
		if is_instance_valid(target_enemy) and not (unit.current_state == UnitBase.State.ATTACKING and unit.attack_target == target_enemy):
			unit.command_attack(target_enemy)

	# Evacuate villagers actually exposed to the remembered threat, including
	# gatherers; limiting this by proximity avoids idling the whole economy.
	var threat_center: Vector2 = _average_node_position(threats)
	var escape_direction: Vector2 = (_base_position - threat_center).normalized()
	if escape_direction == Vector2.ZERO:
		escape_direction = (_base_position - _staging_point).normalized()
	if escape_direction == Vector2.ZERO:
		escape_direction = Vector2.LEFT
	var danger_range: float = 0.0
	for threat: UnitBase in threats:
		danger_range = maxf(danger_range, threat.attack_range)
	var safe_position: Vector2 = threat_center + escape_direction * maxf(128.0, danger_range + 112.0)
	# Public map bounds are enough to clamp an escape point. No hidden terrain,
	# resource locations or enemy positions are consulted to choose it.
	var escape_tile: Vector2i = _world_to_tile(safe_position)
	escape_tile.x = clampi(escape_tile.x, 1, MapData.MAP_WIDTH - 2)
	escape_tile.y = clampi(escape_tile.y, 1, MapData.MAP_HEIGHT - 2)
	safe_position = _tile_to_world(escape_tile)
	for villager in _get_villagers():
		if _is_worker_retreating(villager):
			continue
		# Infrastructure defense and actual worker exposure have different radii.
		# Reissuing a blanket 220px evacuation at a 96px refuge canceled every
		# cargo return on the next decision and froze the entire damaged economy.
		if not _is_worker_position_exposed(villager.global_position, threats):
			continue
		if villager.current_state == UnitBase.State.MOVING and villager.move_target.distance_to(safe_position) <= 16.0:
			continue
		if villager.has_method("command_retreat"):
			villager.call("command_retreat", safe_position)
		else:
			villager.command_move(safe_position)
	for scout in _get_scouts():
		if _is_worker_position_exposed(scout.global_position, threats):
			scout.command_move(safe_position)


func _choose_counter_target(unit: UnitBase, threats: Array, allocations: Dictionary) -> UnitBase:
	var best: UnitBase = null
	var best_score: float = -INF
	for threat: UnitBase in threats:
		if not is_instance_valid(threat) or threat.current_state == UnitBase.State.DEAD:
			continue
		var score: float = Combat.get_counter_bonus(unit.unit_type, threat.unit_type) * 120.0
		score -= minf(500.0, unit.global_position.distance_to(threat.global_position)) * 0.1
		score -= float(allocations.get(threat.get_instance_id(), 0)) * 80.0
		if unit.attack_target == threat:
			score += 12.0
		if score > best_score:
			best_score = score
			best = threat
	if best != null:
		allocations[best.get_instance_id()] = int(allocations.get(best.get_instance_id(), 0)) + 1
	return best


func _is_worker_position_exposed(position: Vector2, threats: Array) -> bool:
	for threat: Node2D in threats:
		if not is_instance_valid(threat):
			continue
		var attack_damage: float = 0.0
		var attack_range: float = 0.0
		if threat is UnitBase:
			attack_damage = (threat as UnitBase).damage
			attack_range = (threat as UnitBase).attack_range
		elif threat is BuildingBase and (threat as BuildingBase).state == BuildingBase.State.ACTIVE:
			attack_damage = float((threat as BuildingBase).tower_attack_damage)
			attack_range = (threat as BuildingBase).tower_attack_range
		if attack_damage > 0.0 and position.distance_to(threat.global_position) <= maxf(80.0, attack_range + 48.0):
			return true
	return false


func _get_visible_worker_threats() -> Array:
	var threats: Array = _get_visible_enemies()
	for building: BuildingBase in _get_visible_enemy_buildings():
		if building.state == BuildingBase.State.ACTIVE and building.tower_attack_damage > 0:
			threats.append(building)
	return threats


func _average_node_position(nodes: Array) -> Vector2:
	if nodes.is_empty():
		return _base_position
	var total := Vector2.ZERO
	var count: int = 0
	for node in nodes:
		if is_instance_valid(node) and node is Node2D:
			total += node.global_position
			count += 1
	return total / float(count) if count > 0 else _base_position


func _get_base_reserve_units(military: Array) -> Array:
	if _town_center_count <= 0:
		return []
	var candidates: Array = []
	for unit in military:
		if not is_instance_valid(unit) or unit in _objective_units:
			continue
		# Scouts remain available for reconnaissance/objective capture. A current
		# home threat still recalls every unit through _rally_defense(), so this
		# role distinction does not make the base undefended in combat.
		if unit.damage <= 0.0 or unit.unit_type in [UnitData.UnitType.SCOUT, UnitData.UnitType.SIEGE]:
			continue
		candidates.append(unit)
	candidates.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		return a.global_position.distance_to(_base_position) < b.global_position.distance_to(_base_position)
	)
	var reserve_count: int = int(BASE_DEFENSE_RESERVES.get(difficulty, 2))
	if _uses_compact_population_policy():
		# Keep the first three field fighters together. A permanent home guard is
		# useful once the force can still launch its normal packet without it.
		reserve_count = 1 if military.size() >= _get_attack_threshold() + 2 else 0
	return candidates.slice(0, mini(reserve_count, candidates.size()))


func _rally_base_reserve(reserve: Array) -> void:
	var guard_position: Vector2 = _base_position.lerp(_staging_point, 0.28)
	for unit in reserve:
		if unit.current_state == UnitBase.State.IDLE and unit.global_position.distance_to(guard_position) > 56.0:
			unit.command_move(guard_position)


func _get_field_military(reserve: Array) -> Array:
	var field_units: Array = []
	for unit in _get_military_units():
		if unit.unit_type == UnitData.UnitType.SCOUT or unit.damage <= 0.0:
			continue
		if unit in _objective_units or unit in reserve:
			continue
		field_units.append(unit)
	return field_units


func _retreat_army() -> void:
	var military: Array = _get_attack_wave_survivors()
	if military.is_empty():
		military = _get_field_military(_get_base_reserve_units(_get_military_units()))
	for unit in military:
		unit.command_move(_staging_point)


func _send_attack(units: Array, target: Vector2) -> void:
	_issue_attack_orders(units, target)
	ai_attack_launched.emit(units, target)


func _issue_attack_orders(units: Array, target: Vector2) -> void:
	for unit in units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("command_attack_move"):
			unit.command_attack_move(target)
		else:
			unit.command_move(target)


func _find_enemy_target() -> Vector2:
	var target_selection: Dictionary = _find_enemy_target_selection()
	return target_selection.get("position", Vector2(-1, -1))


func _find_enemy_target_selection() -> Dictionary:
	var enemies: Array = _get_visible_enemies()
	var visible_enemy_buildings: Array = _get_visible_enemy_buildings()
	var best_score: float = -INF
	var best_target_node: Node = null

	for enemy in enemies:
		var score: float = _score_enemy_node(enemy)
		if score > best_score:
			best_score = score
			best_target_node = enemy

	for building in visible_enemy_buildings:
		var score: float = _score_enemy_node(building)
		if score > best_score:
			best_score = score
			best_target_node = building

	if best_target_node != null:
		return {
			"position": best_target_node.global_position,
			"node": best_target_node,
			"source": "visible",
		}

	var memory_target: Dictionary = _find_best_enemy_memory()
	if not memory_target.is_empty():
		return memory_target

	# This duel has public, fixed symmetric spawns. Derive the search destination
	# from our own starting tile and dimensions rather than reading enemy data.
	if map_generator:
		var spawn: Vector2i = _get_symmetric_enemy_spawn_tile()
		return {
			"position": _tile_to_world(spawn),
			"node": null,
			"source": "known_spawn",
		}

	return {}


func _get_symmetric_enemy_spawn_tile() -> Vector2i:
	return Vector2i(MapData.MAP_WIDTH - 1 - _base_tile.x, MapData.MAP_HEIGHT - 1 - _base_tile.y)


func _score_enemy_node(node: Node) -> float:
	if node == null or not is_instance_valid(node):
		return -INF
	var dist_to_base: float = _base_position.distance_to(node.global_position)
	var score: float = 2000.0 - dist_to_base
	if node is UnitBase:
		var unit: UnitBase = node as UnitBase
		if unit.unit_type == UnitData.UnitType.VILLAGER:
			score += 500.0
		elif unit.unit_type == UnitData.UnitType.SIEGE:
			score += 420.0
		elif unit.unit_type == UnitData.UnitType.ARCHER:
			score += 240.0
		elif unit.unit_type == UnitData.UnitType.CAVALRY:
			score += 220.0
		score += (1.0 - (unit.hp / maxf(1.0, unit.max_hp))) * 180.0
	elif node is BuildingBase:
		var building: BuildingBase = node as BuildingBase
		match building.building_type:
			BuildingData.BuildingType.SIEGE_WORKSHOP:
				score += 420.0
			BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE, BuildingData.BuildingType.BARRACKS:
				score += 360.0
			BuildingData.BuildingType.BLACKSMITH, BuildingData.BuildingType.WATCH_TOWER:
				score += 240.0
			BuildingData.BuildingType.TOWN_CENTER:
				score += 180.0
	var sacred_site: Node2D = _get_sacred_site()
	if sacred_site != null and node.global_position.distance_to(sacred_site.global_position) <= SACRED_SITE_THREAT_RADIUS:
		score += 520.0
	return score


func _update_enemy_memory() -> void:
	for enemy in _get_visible_enemies():
		_remember_enemy(enemy)
	for building in _get_visible_enemy_buildings():
		_remember_enemy(building)
	_prune_enemy_memory()


func _remember_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	_enemy_memory[enemy.get_instance_id()] = {
		"position": enemy.global_position,
		"last_seen": _game_time,
		"score": _score_enemy_node(enemy),
		"kind": "building" if enemy is BuildingBase else "unit",
	}


func _prune_enemy_memory() -> void:
	var lifetime: float = float(ENEMY_MEMORY_SECONDS.get(difficulty, 45.0))
	for memory_id in _enemy_memory.keys():
		var memory: Dictionary = _enemy_memory[memory_id]
		if _game_time - float(memory.get("last_seen", -INF)) > lifetime:
			_enemy_memory.erase(memory_id)


func _find_best_enemy_memory() -> Dictionary:
	_prune_enemy_memory()
	var best_memory: Dictionary = {}
	var best_score: float = -INF
	for memory in _enemy_memory.values():
		var sighting: Dictionary = memory as Dictionary
		var age: float = maxf(0.0, _game_time - float(sighting.get("last_seen", 0.0)))
		var score: float = float(sighting.get("score", 0.0)) - age * 4.0
		if score > best_score:
			best_score = score
			best_memory = sighting
	if best_memory.is_empty():
		return {}
	return {
		"position": best_memory.get("position", Vector2(-1, -1)),
		# Memory is intentionally position-only. A hidden enemy never remains a
		# live command target; units investigate its last legal sighting.
		"node": null,
		"source": "memory",
		"last_seen": best_memory.get("last_seen", 0.0),
	}


func get_strategy_snapshot() -> Dictionary:
	## Stable diagnostics for balance harnesses and focused regressions.
	return {
		"difficulty": difficulty,
		"population_limit": GameManager.get_player_population_limit(player_id),
		"target_villagers": _get_target_villager_count(),
		"worker_recovery_active": _needs_compact_worker_recovery(),
		"fighting_units": _get_fighting_units().size(),
		"pending_role_building": _get_compact_missing_role_building(),
		"attack_threshold": _get_attack_threshold(),
		"has_launched_field_attack": _has_launched_field_attack,
		"decision_interval": _decision_interval,
		"economic_modifiers": {
			"starting_food": 0,
			"starting_wood": 0,
			"starting_gold": 0,
			"passive_food_per_second": 0.0,
			"passive_wood_per_second": 0.0,
			"passive_gold_per_second": 0.0,
		},
		"objective_mode": _objective_mode_name(),
		"objective_unit_count": _objective_units.size(),
		"enemy_memory_count": _enemy_memory.size(),
		"resource_memory_count": _get_resource_memory_count(),
		"economy_exploration_waypoint_count": _economy_exploration_waypoints.size(),
		"economy_exploration_waypoints_remaining": maxi(
			0,
			_economy_exploration_waypoints.size() - _next_economy_exploration_waypoint
		),
		"economy_exploration_orders": _economy_exploration_orders_issued,
		"economy_memory_revisit_orders": _economy_memory_revisit_orders_issued,
		"economy_resource_assignments": _economy_resource_assignments,
		"economy_rebalance_orders": _economy_rebalance_orders_issued,
		"economy_rebalance_pending": _pending_economy_rebalance_type,
		"farm_count": _farm_count,
		"feudal_paid_farm_foundations": _feudal_paid_farm_foundations,
		"feudal_paid_farm_foundations_remaining": maxi(
			0,
			_get_feudal_farm_capacity_target() - _feudal_paid_farm_foundations
		),
		"feudal_farm_capacity_target": _get_feudal_farm_capacity_target(),
		"queued_military_count": _count_queued_military_units(),
		"last_economy_action": _last_economy_action,
		"rebuild_requests": _rebuild_requests.duplicate(),
		"under_pressure": _is_under_pressure,
		"timed_age_up_reserve_active": _timed_age_up_reserve_active,
		"last_decision": _last_strategy_decision,
	}


func _objective_mode_name() -> String:
	match _objective_mode:
		ObjectiveMode.SCOUT:
			return "scout"
		ObjectiveMode.CAPTURE:
			return "capture"
		ObjectiveMode.CONTEST:
			return "contest"
		ObjectiveMode.DEFEND:
			return "defend"
	return "none"


# ═════════════════════════════════════════════════════════════════════════
#  HELPER FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════

func _tile_to_world(tile: Vector2i) -> Vector2:
	if game_map != null and game_map.has_method("tile_to_world"):
		return game_map.call("tile_to_world", tile)
	push_error("AIController requires GameMap.tile_to_world() before starting")
	return _base_position

func _cleanup_references() -> void:
	_remove_invalid_node_references(_my_units)
	_remove_invalid_node_references(_my_buildings)
	_remove_invalid_node_references(_attack_wave_units)
	_remove_invalid_node_references(_objective_units)
	_update_building_counts()


func _remove_invalid_node_references(nodes: Array) -> void:
	# Iterate in reverse so invalid freed-Object placeholders can be erased
	# without first coercing them through a typed callback parameter.
	for index in range(nodes.size() - 1, -1, -1):
		if not _is_live_tree_node(nodes[index]):
			nodes.remove_at(index)


func _is_live_tree_node(candidate: Variant) -> bool:
	if typeof(candidate) != TYPE_OBJECT or not is_instance_valid(candidate):
		return false
	if not (candidate is Node):
		return false
	return (candidate as Node).is_inside_tree()


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


func _count_queued_unit(unit_type: int) -> int:
	var count: int = 0
	for building in _my_buildings:
		if not is_instance_valid(building) or not building.has_method("get_production_queue"):
			continue
		var queue: Node = building.get_production_queue()
		if queue == null or not queue.has_method("get_queue_info"):
			continue
		for entry in queue.get_queue_info():
			if int(entry.get("unit_type", -1)) == unit_type:
				count += 1
	return count


func _count_queued_military_units() -> int:
	var count: int = 0
	for building in _my_buildings:
		if not is_instance_valid(building) or not building.has_method("get_production_queue"):
			continue
		var queue: Node = building.get_production_queue()
		if queue == null or not queue.has_method("get_queue_info"):
			continue
		for entry_variant: Variant in queue.get_queue_info():
			var entry: Dictionary = entry_variant as Dictionary
			var unit_type: int = int(entry.get("unit_type", -1))
			if unit_type >= 0 and unit_type != UnitData.UnitType.VILLAGER:
				count += 1
	return count


func _get_villagers() -> Array:
	var result: Array = []
	for unit in _my_units:
		if is_instance_valid(unit) and unit is UnitBase:
			if unit.unit_type == UnitData.UnitType.VILLAGER and unit.current_state != UnitBase.State.DEAD:
				result.append(unit)
	return result


func _get_scouts() -> Array:
	var result: Array = []
	for unit in _my_units:
		if not is_instance_valid(unit) or not (unit is UnitBase):
			continue
		if unit.current_state == UnitBase.State.DEAD:
			continue
		if unit.unit_type == UnitData.UnitType.SCOUT:
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


func _get_fighting_units() -> Array:
	var result: Array = []
	for unit in _get_military_units():
		if unit.unit_type != UnitData.UnitType.SCOUT and unit.damage > 0.0:
			result.append(unit)
	return result


func _get_idle_military() -> Array:
	return _get_idle_units_from(_get_military_units())


func _get_idle_units_from(units: Array) -> Array:
	var result: Array = []
	for unit in units:
		if unit.current_state == UnitBase.State.IDLE:
			result.append(unit)
	return result


func _get_visible_enemies() -> Array:
	## Returns enemy units admitted by the map's canonical current-vision API.
	var result: Array = []
	var all_units: Array = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if not (unit is UnitBase):
			continue
		if unit.player_owner == player_id:
			continue
		if not _is_enemy_currently_visible(unit):
			continue
		if unit.current_state == UnitBase.State.DEAD:
			continue
		result.append(unit)
	return result


func _get_visible_enemy_buildings() -> Array:
	var result: Array = []
	var all_buildings: Array = get_tree().get_nodes_in_group("buildings")
	for building in all_buildings:
		if not (building is BuildingBase):
			continue
		if building.player_owner == player_id:
			continue
		if not _is_enemy_currently_visible(building):
			continue
		if building.state == BuildingBase.State.DESTROYED:
			continue
		result.append(building)
	return result


func _is_enemy_currently_visible(enemy: Node) -> bool:
	if not is_instance_valid(enemy) or not (enemy is Node2D):
		return false
	if game_map == null or not game_map.has_method("is_entity_visible_to_player"):
		return false
	return bool(game_map.call("is_entity_visible_to_player", enemy, player_id))


func _evaluate_army_strength() -> float:
	## Returns a simple strength score using the same live stats as Combat.
	return _evaluate_units_strength(_get_military_units())


func _evaluate_units_strength(units: Array) -> float:
	var strength: float = 0.0
	for unit in units:
		if unit is UnitBase:
			strength += _evaluate_unit_combat_strength(unit as UnitBase)
	return strength


func _evaluate_enemy_visible_strength() -> float:
	var strength: float = 0.0
	for unit in _get_visible_enemies():
		if unit is UnitBase:
			strength += _evaluate_unit_combat_strength(unit as UnitBase)
	return strength


func _evaluate_unit_combat_strength(unit: UnitBase) -> float:
	## Current HP times live attack plus armor. Combat owns upgrade resolution,
	## so this score cannot miss or double-apply researched bonuses.
	if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
		return 0.0
	if unit.unit_type == UnitData.UnitType.SCOUT or unit.damage <= 0.0:
		return 0.0
	var effective_attack: float = Combat.get_effective_attack(unit)
	var effective_armor: float = Combat.get_effective_armor(unit)
	return unit.hp * maxf(1.0, effective_attack + effective_armor)


func _get_buildings_of_type(building_type: int) -> Array:
	var result: Array = []
	for b in _my_buildings:
		if not is_instance_valid(b):
			continue
		if "building_type" in b and b.building_type == building_type:
			result.append(b)
	return result


func _has_building_under_construction(building_type: int) -> bool:
	for building in _my_buildings:
		if not is_instance_valid(building) or not building.is_inside_tree():
			continue
		if not (building is BuildingBase):
			continue
		var typed_building: BuildingBase = building as BuildingBase
		if (
			typed_building.building_type == building_type
			and typed_building.state == BuildingBase.State.CONSTRUCTING
		):
			return true
	return false


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
	return best


func _find_nearest_resource_node(resource_type: String, from_pos: Vector2) -> Node2D:
	## Finds the nearest resource node of the given type using the game_map lookup.
	if game_map and game_map.has_method("get_nearest_resource_node"):
		return game_map.get_nearest_resource_node(resource_type, from_pos, player_id)
	return null


func _find_resource_for_villager(resource_type: String, villager: UnitBase) -> Node2D:
	## Honor the villager's bounded unreachable-target cache so an AI decision
	## tick cannot immediately undo autonomous path recovery and recreate a loop.
	if game_map != null and game_map.has_method("get_nearest_reachable_resource_node"):
		var excluded_instance_ids: Dictionary = {}
		if villager is Villager:
			var unreachable_ids: Dictionary = (
				(villager as Villager).get("_unreachable_resource_ids_until") as Dictionary
			)
			for target_id: Variant in unreachable_ids:
				excluded_instance_ids[target_id] = unreachable_ids[target_id]
		var visible_threats: Array = _get_visible_worker_threats()
		# Query only current-visible, reachable candidates. Excluding an exposed
		# endpoint avoids immediately sending a recovered worker back into a raid.
		for _candidate_index: int in range(8):
			var candidate: Node2D = game_map.call("get_nearest_reachable_resource_node", resource_type, villager.global_position, player_id, excluded_instance_ids) as Node2D
			if candidate == null:
				return null
			if not _is_worker_position_exposed(candidate.global_position, visible_threats):
				return candidate
			if excluded_instance_ids.has(candidate.get_instance_id()):
				return null
			excluded_instance_ids[candidate.get_instance_id()] = true
		return null
	var nearest: Node2D = _find_nearest_resource_node(resource_type, villager.global_position)
	if nearest != null and _is_worker_position_exposed(nearest.global_position, _get_visible_worker_threats()):
		return null
	return nearest


func _assign_villager_to_resource(villager: UnitBase, resource_node: Node2D) -> bool:
	## Sends a villager to gather from a resource node.
	if villager.has_method("command_gather"):
		return bool(villager.call("command_gather", resource_node))
	villager.command_move(resource_node.global_position)
	return true


func _reset_economy_recovery() -> void:
	_resource_memory = {
		"food": [],
		"wood": [],
		"gold": [],
	}
	_economy_exploration_waypoints.clear()
	_next_economy_exploration_waypoint = 0
	_economy_exploration_orders_issued = 0
	_economy_memory_revisit_orders_issued = 0
	_economy_resource_assignments = 0
	_economy_rebalance_orders_issued = 0
	_next_economy_rebalance_time = float(ECONOMY_REBALANCE_INTERVALS.get(difficulty, 28.0))
	_economy_rebalance_deferred_scheduled = false
	_clear_pending_economy_rebalance()
	_last_economy_action = "none"
	_build_economy_exploration_waypoints()


func _build_economy_exploration_waypoints() -> void:
	## A five-tile lattice covers the map with a villager's four-tile
	## vision. Sorting by distance makes expansion local-first without looking at
	## generated terrain, navigation cost, fog contents, or resource registries.
	var waypoint_tiles: Array[Vector2i] = []
	var maximum_x: int = MapData.MAP_WIDTH - 1 - ECONOMY_EXPLORATION_GRID_MARGIN
	var maximum_y: int = MapData.MAP_HEIGHT - 1 - ECONOMY_EXPLORATION_GRID_MARGIN
	for y in range(
		ECONOMY_EXPLORATION_GRID_MARGIN,
		maximum_y + 1,
		ECONOMY_EXPLORATION_GRID_STEP
	):
		for x in range(
			ECONOMY_EXPLORATION_GRID_MARGIN,
			maximum_x + 1,
			ECONOMY_EXPLORATION_GRID_STEP
		):
			waypoint_tiles.append(Vector2i(x, y))
	waypoint_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance: int = (a - _base_tile).length_squared()
		var b_distance: int = (b - _base_tile).length_squared()
		if a_distance != b_distance:
			return a_distance < b_distance
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for tile: Vector2i in waypoint_tiles:
		_economy_exploration_waypoints.append(_tile_to_world(tile))


func _remember_resource_sighting(resource_type: String, position: Vector2) -> void:
	if not _resource_memory.has(resource_type):
		return
	var tile: Vector2i = _world_to_tile(position)
	var memories: Array = _resource_memory.get(resource_type, []) as Array
	for memory_variant: Variant in memories:
		var memory: Dictionary = memory_variant as Dictionary
		if (memory.get("tile", Vector2i(-1, -1)) as Vector2i) == tile:
			memory["position"] = position
			memory["last_seen"] = _game_time
			return
	memories.append({
		"tile": tile,
		"position": position,
		"last_seen": _game_time,
	})
	while memories.size() > RESOURCE_MEMORY_LIMIT_PER_TYPE:
		memories.pop_front()
	_resource_memory[resource_type] = memories


func _find_resource_memory_target(priority: Array, from_position: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_priority: int = 999
	var best_distance: float = INF
	for priority_index in range(priority.size()):
		var resource_type: String = str(priority[priority_index])
		var memories: Array = _resource_memory.get(resource_type, []) as Array
		var retained: Array = []
		for memory_variant: Variant in memories:
			var memory: Dictionary = memory_variant as Dictionary
			var tile: Vector2i = memory.get("tile", Vector2i(-1, -1)) as Vector2i
			# Every currently visible lookup already failed before memory recovery.
			# Therefore a visible remembered tile is stale and can be forgotten using
			# only fog state; no hidden/live resource object is consulted.
			if _is_tile_currently_visible(tile):
				continue
			retained.append(memory)
			var position: Vector2 = memory.get("position", _base_position) as Vector2
			var distance: float = from_position.distance_squared_to(position)
			if priority_index < best_priority or (
				priority_index == best_priority and distance < best_distance
			):
				best_priority = priority_index
				best_distance = distance
				best = {
					"resource_type": resource_type,
					"position": position,
				}
		_resource_memory[resource_type] = retained
	return best


func _take_next_economy_exploration_target() -> Dictionary:
	while _next_economy_exploration_waypoint < _economy_exploration_waypoints.size():
		var position: Vector2 = _economy_exploration_waypoints[_next_economy_exploration_waypoint]
		_next_economy_exploration_waypoint += 1
		var tile: Vector2i = _world_to_tile(position)
		if _is_tile_currently_visible(tile):
			continue
		return {
			"position": position,
			"tile": tile,
		}
	return {}


func _get_resource_memory_count() -> int:
	var count: int = 0
	for memories_variant: Variant in _resource_memory.values():
		count += (memories_variant as Array).size()
	return count


func _world_to_tile(position: Vector2) -> Vector2i:
	if game_map != null and game_map.has_method("world_to_tile"):
		return game_map.call("world_to_tile", position) as Vector2i
	return _base_tile


func _find_build_location(building_type: int) -> Vector2i:
	## Finds a valid build location near the base.
	## Searches in expanding rings around the Town Center tile. Main may
	## synchronously reject a fully visible/buildable tile when no eligible builder
	## can reach it, so a per-type scalar cursor advances across the complete stable
	## candidate order. No rolling subset can cycle before a later site is tried.
	var stats: Dictionary = BuildingData.get_building_stats(building_type)
	var footprint: Vector2i = stats.get("footprint", Vector2i(2, 2))
	var search_cursor: int = maxi(0, int(_build_site_search_cursors.get(building_type, 0)))
	var selected: Vector2i = _find_build_location_candidate(
		building_type,
		footprint,
		search_cursor
	)
	if selected == Vector2i(-1, -1) and search_cursor > 0:
		# The complete currently valid domain was exhausted or shrank. Restart once
		# from its deterministic beginning; each invocation still performs two finite
		# scans at most and stores only one bounded integer per building type.
		search_cursor = 0
		selected = _find_build_location_candidate(building_type, footprint, search_cursor)
	if selected != Vector2i(-1, -1):
		_build_site_search_cursors[building_type] = search_cursor + 1
	return selected


func _find_build_location_candidate(
	building_type: int,
	footprint: Vector2i,
	search_cursor: int
) -> Vector2i:
	if building_type == BuildingData.BuildingType.WATCH_TOWER:
		var sacred_site: Node2D = _get_sacred_site()
		if sacred_site != null and int(sacred_site.get("owning_player")) == player_id and game_map.has_method("world_to_tile"):
			var sacred_tile: Vector2i = game_map.call("world_to_tile", sacred_site.global_position)
			# Concatenate objective and base candidates under one cursor. Passing the
			# same offset into two independent scans would permanently skip the first
			# base candidates whenever the sacred-site prefix was exhausted.
			var tower_candidates: Array[Vector2i] = _collect_build_locations_near_tile(
				sacred_tile,
				footprint,
				3,
				7
			)
			for base_candidate: Vector2i in _collect_build_locations_near_tile(
				_base_tile,
				footprint,
				3,
				15
			):
				if base_candidate not in tower_candidates:
					tower_candidates.append(base_candidate)
			if search_cursor >= 0 and search_cursor < tower_candidates.size():
				return tower_candidates[search_cursor]
			return Vector2i(-1, -1)

	# Special placement for resource-gathering buildings
	if building_type == BuildingData.BuildingType.MILL:
		return _find_build_near_resource(MapData.TileType.BERRY_BUSH, footprint, search_cursor)
	if building_type == BuildingData.BuildingType.LUMBER_CAMP:
		return _find_build_near_resource(MapData.TileType.FOREST, footprint, search_cursor)
	if building_type == BuildingData.BuildingType.MINING_CAMP:
		return _find_build_near_resource(MapData.TileType.GOLD_MINE, footprint, search_cursor)

	return _find_build_location_near_tile(_base_tile, footprint, 3, 15, search_cursor)


func _find_build_location_near_tile(
	anchor_tile: Vector2i,
	footprint: Vector2i,
	minimum_ring: int,
	maximum_ring: int,
	search_cursor: int = 0
) -> Vector2i:
	var candidates: Array[Vector2i] = _collect_build_locations_near_tile(
		anchor_tile,
		footprint,
		minimum_ring,
		maximum_ring
	)
	if search_cursor < 0 or search_cursor >= candidates.size():
		return Vector2i(-1, -1)
	return candidates[search_cursor]


func _collect_build_locations_near_tile(
	anchor_tile: Vector2i,
	footprint: Vector2i,
	minimum_ring: int,
	maximum_ring: int
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for ring in range(minimum_ring, maximum_ring):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if abs(dx) != ring and abs(dy) != ring:
					continue  # Only check ring perimeter
				var tile := Vector2i(anchor_tile.x + dx, anchor_tile.y + dy)
				if _is_valid_build_spot(tile, footprint):
					candidates.append(tile)
	return candidates


func _find_build_near_resource(
	resource_tile: MapData.TileType,
	footprint: Vector2i,
	search_cursor: int = 0
) -> Vector2i:
	## Place a gathering building adjacent to a resource cluster.
	if map_generator == null:
		return Vector2i(-1, -1)

	var candidates: Array[Dictionary] = []
	var seen_candidates: Dictionary = {}

	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			var resource_position := Vector2i(x, y)
			# Vision is checked before reading the generated terrain type so this
			# search cannot use the map grid as an unexplored-resource oracle.
			if not _is_tile_currently_visible(resource_position):
				continue
			if map_generator.grid[y][x] != resource_tile:
				continue
			# Try spots adjacent to this resource
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var candidate: Vector2i = resource_position + offset
				if seen_candidates.has(candidate):
					continue
				if _is_valid_build_spot(candidate, footprint):
					seen_candidates[candidate] = true
					candidates.append({
						"tile": candidate,
						"distance": _base_tile.distance_squared_to(candidate),
					})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance: int = int(a.get("distance", 0))
		var b_distance: int = int(b.get("distance", 0))
		if a_distance != b_distance:
			return a_distance < b_distance
		var a_tile: Vector2i = a.get("tile", Vector2i.ZERO) as Vector2i
		var b_tile: Vector2i = b.get("tile", Vector2i.ZERO) as Vector2i
		if a_tile.y != b_tile.y:
			return a_tile.y < b_tile.y
		return a_tile.x < b_tile.x
	)
	if search_cursor < 0 or search_cursor >= candidates.size():
		return Vector2i(-1, -1)
	return candidates[search_cursor].get("tile", Vector2i(-1, -1)) as Vector2i


func _is_valid_build_spot(origin: Vector2i, footprint: Vector2i) -> bool:
	## Check bounds and current vision before reading terrain/pathfinding. Only a
	## fully visible footprint may disclose whether its tiles are buildable.
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			var tx: int = origin.x + dx
			var ty: int = origin.y + dy
			if tx < 0 or tx >= MapData.MAP_WIDTH or ty < 0 or ty >= MapData.MAP_HEIGHT:
				return false
			if not _is_tile_currently_visible(Vector2i(tx, ty)):
				return false
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			var tx: int = origin.x + dx
			var ty: int = origin.y + dy
			if game_map != null and game_map.has_method("is_tile_buildable"):
				if not bool(game_map.call("is_tile_buildable", Vector2i(tx, ty))):
					return false
			elif map_generator and not MapData.is_grass(map_generator.grid[ty][tx] as MapData.TileType):
				return false
			elif pathfinding and not pathfinding.is_walkable(Vector2i(tx, ty)):
				return false
	return true


func _is_tile_currently_visible(tile: Vector2i) -> bool:
	if game_map == null or not game_map.has_method("is_tile_visible_to_player"):
		return false
	return bool(game_map.call("is_tile_visible_to_player", tile, player_id))
