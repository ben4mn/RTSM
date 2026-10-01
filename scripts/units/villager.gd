class_name Villager
extends UnitBase
## Villager unit: can gather resources and construct buildings.

signal resource_deposited(resource_type: String, amount: int)
signal gathering_started(resource_node: Node2D)
signal building_started(building: Node2D)
signal building_completed(building: Node2D)

enum GatherType { NONE, FOOD, WOOD, GOLD }

# Gathering stats
@export var gather_rate: float = 2.0  # resources per gather tick
@export var carry_capacity: int = 15
@export var gather_tick_time: float = 1.5  # seconds between gather ticks

# Gathering state
var gather_target: Node2D = null
var gather_type: int = GatherType.NONE
var carried_resource_type: String = ""
var carried_amount: int = 0
var gather_timer: float = 0.0
var dropoff_target: Node2D = null
var _dropoff_retry_timer: float = 0.0
var _dropoff_route_active: bool = false
var _gather_last_known_position: Vector2 = Vector2.ZERO
var _has_gather_last_known_position: bool = false
var _gather_last_known_is_building: bool = false
var _gather_last_known_instance_id: int = 0
var _unreachable_resource_ids_until: Dictionary = {}
var _unreachable_dropoff_ids_until: Dictionary = {}

const DROP_OFF_RETRY_INTERVAL: float = 1.0
const DROP_OFF_ANY_ADVANTAGE_RATIO: float = 0.7
# GameMap preflight and the interaction check share one exact route contract.
const GATHER_APPROACH_DISTANCE: float = MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD
const BUILD_APPROACH_DISTANCE: float = 40.0
const BUILDING_APPROACH_DISTANCE: float = 48.0
const UNREACHABLE_TARGET_IGNORE_MSEC: int = 5000
const MAX_DROPOFF_PATH_CHECKS: int = 8

# Building state
var build_target: Node2D = null
var build_timer: float = 0.0
var _gather_offset: Vector2 = Vector2.ZERO  # Small random offset to prevent villager stacking

# Saved gather state (restored after building completes)
var _saved_gather_target: Node2D = null
var _saved_gather_type: int = GatherType.NONE
var _saved_carried_resource_type: String = ""
var _saved_gather_last_known_position: Vector2 = Vector2.ZERO
var _saved_has_gather_last_known_position: bool = false
var _saved_gather_last_known_is_building: bool = false
var _saved_gather_last_known_instance_id: int = 0
var _pending_gather_resource_type: String = ""
var _pending_gather_last_known_position: Vector2 = Vector2.ZERO
var _pending_gather_last_known_is_building: bool = false
var _pending_gather_last_known_instance_id: int = 0
var _preserve_pending_gather_on_command: bool = false
var _building_work_target_id: int = 0
var _building_work_destination: Vector2 = Vector2.ZERO

# Automatic raid recovery retains the economic order independently of the
# movement state. A fresh player/AI command always supersedes this intent.
var _auto_recovering: bool = false
var _recovery_waiting: bool = false
var _recovery_work_state: int = State.IDLE
var _recovery_refuge: BuildingBase = null
var _recovery_check_timer: float = 0.0
var _recovery_quiet_seconds: float = 0.0
var _recovery_damage_remaining: float = 0.0
var _recovery_danger_present: bool = true
var _preserve_recovery_on_command: bool = false
var _recovery_return_only: bool = false
var _recovery_alternate_retry_remaining: float = 0.0
var _avoid_recovery_dropoff_danger: bool = false
var _economic_threat_check_timer: float = 0.0
var _observed_worker_threat_distances: Dictionary = {}

const RECOVERY_CHECK_INTERVAL: float = 0.5
const ECONOMIC_THREAT_CHECK_INTERVAL: float = 0.25
const ECONOMIC_THREAT_MIN_DISTANCE: float = 80.0
const ECONOMIC_THREAT_RANGE_MARGIN: float = 48.0
const ECONOMIC_THREAT_CLOSING_STEP: float = 4.0
const RECOVERY_QUIET_SECONDS: float = 3.0
const RECOVERY_DAMAGE_DELAY: float = 4.0
const RECOVERY_THREAT_MARGIN: float = 56.0
const RECOVERY_MIN_THREAT_DISTANCE: float = 96.0


func _ready() -> void:
	unit_type = UnitData.UnitType.VILLAGER
	super._ready()
	add_to_group("villagers")


## Villagers don't auto-attack; they stay focused on economic tasks.
func _try_auto_attack() -> void:
	pass


func can_auto_retaliate() -> bool:
	return false


func _process(delta: float) -> void:
	if not _auto_recovering and _has_active_economic_work():
		_economic_threat_check_timer -= delta
		if _economic_threat_check_timer <= 0.0:
			_economic_threat_check_timer = ECONOMIC_THREAT_CHECK_INTERVAL
			_check_visible_economic_threats()
	else:
		_observed_worker_threat_distances.clear()
		_economic_threat_check_timer = float(posmod(get_index(), 5)) * 0.05
	if _auto_recovering and current_state != State.DEAD:
		_process_recovery(delta)
	super._process(delta)


## Economic work flees without forgetting its job. Explicit combat and manual
## movement retain control; another command also cancels any deferred recovery.
func take_damage(amount: float) -> void:
	super.take_damage(amount)
	if current_state == State.DEAD:
		return
	if _auto_recovering:
		_recovery_damage_remaining = RECOVERY_DAMAGE_DELAY
		_recovery_quiet_seconds = 0.0
		_recovery_check_timer = 0.0
		if _recovery_waiting:
			_flee_to_safety()
		return
	if current_state in [State.GATHERING, State.BUILDING, State.IDLE] or _dropoff_route_active:
		_begin_recovery()
		_flee_to_safety()


func _process_moving(delta: float) -> void:
	if not _auto_recovering:
		super._process_moving(delta)
		return
	if _recovery_waiting:
		return
	var result: int = _navigate_toward(move_target, NAVIGATION_POINT_TOLERANCE, delta, false, true)
	if result == NavigationResult.ARRIVED:
		_reset_navigation()
		_recovery_waiting = true
		_recovery_quiet_seconds = 0.0
	elif result == NavigationResult.UNREACHABLE:
		_on_navigation_unreachable(move_target)


func is_retreating() -> bool:
	return _auto_recovering and current_state != State.DEAD


func is_auto_recovering() -> bool:
	return _auto_recovering and current_state != State.DEAD


func has_active_build_order() -> bool:
	return (
		current_state != State.DEAD
		and _is_build_target_valid(build_target)
		and (current_state == State.BUILDING or (_auto_recovering and _recovery_work_state == State.BUILDING))
	)


func _has_active_economic_work() -> bool:
	if current_state == State.DEAD or current_state == State.ATTACKING:
		return false
	return (
		has_active_build_order()
		or (has_active_gather_order() and (gather_type != GatherType.NONE or _pending_gather_resource_type != ""))
		or _dropoff_route_active
	)


func _check_visible_economic_threats() -> void:
	# Only observed motion enters this cache; hidden orders, paths and targets
	# never decide when an economic worker should flee. Replacing the sample
	# dictionary drops any enemy no longer in this owner's current vision.
	var observed: Dictionary = {}
	var threatened: bool = false
	for candidate: Node in get_tree().get_nodes_in_group("units"):
		if not candidate is UnitBase or candidate == self:
			continue
		var enemy: UnitBase = candidate as UnitBase
		if enemy.player_owner == player_owner or not _can_track_entity(enemy):
			continue
		if enemy.current_state == State.DEAD or enemy.damage <= 0.0:
			continue
		if enemy is Villager and enemy.current_state != State.ATTACKING:
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		var instance_id: int = enemy.get_instance_id()
		observed[instance_id] = distance
		if distance > maxf(ECONOMIC_THREAT_MIN_DISTANCE, enemy.attack_range + ECONOMIC_THREAT_RANGE_MARGIN):
			continue
		var closing: bool = (
			_observed_worker_threat_distances.has(instance_id)
			and float(_observed_worker_threat_distances[instance_id]) - distance >= ECONOMIC_THREAT_CLOSING_STEP
		)
		if distance <= enemy.attack_range + 8.0 or enemy.current_state == State.ATTACKING or closing:
			threatened = true
	_observed_worker_threat_distances = observed
	if threatened:
		_begin_recovery()
		_flee_to_safety()


func has_active_gather_order() -> bool:
	if _auto_recovering or _recovery_return_only or current_state == State.DEAD:
		return false
	return current_state == State.GATHERING or _dropoff_route_active


func is_returning_resources() -> bool:
	return not _auto_recovering and _dropoff_route_active and carried_amount > 0


func get_economy_task() -> String:
	if _auto_recovering or current_state == State.DEAD:
		return ""
	if current_state == State.BUILDING:
		return "build"
	if has_active_gather_order():
		if _pending_gather_resource_type != "":
			return _pending_gather_resource_type
		return carried_resource_type
	return ""


func get_work_status() -> String:
	if current_state == State.DEAD:
		return "Dead"
	if _auto_recovering:
		return "Sheltering" if _recovery_waiting else "Retreating"
	if is_returning_resources():
		return "Returning " + carried_resource_type
	if current_state == State.GATHERING:
		if _recovery_return_only or carried_amount >= carry_capacity or _pending_gather_resource_type != "":
			return "Waiting for drop-off"
		if _has_gather_last_known_position and not _is_gather_order_position_visible():
			return "Seeking " + carried_resource_type
		if _is_new_gather_target_currently_visible(gather_target) and _is_gather_target_valid(gather_target):
			var distance: float = _building_work_distance(gather_target) if gather_target is BuildingBase else global_position.distance_to(gather_target.global_position)
			var radius: float = BUILD_APPROACH_DISTANCE if gather_target is BuildingBase else GATHER_APPROACH_DISTANCE
			return ("Gathering " if distance <= radius else "Seeking ") + carried_resource_type
		return "Seeking " + carried_resource_type
	match current_state:
		State.BUILDING: return "Building"
		State.MOVING: return "Moving"
		State.ATTACKING: return "Attacking"
	return "Idle"


func _process_gathering(delta: float) -> void:
	# A cross-resource retask is a two-step transaction: first return the cargo
	# under its original type, then activate the newly requested gather order.
	# This also handles a missing drop-off by retrying without harvesting more of
	# the old resource or inspecting the pending target while it is hidden.
	if _pending_gather_resource_type != "":
		if carried_amount <= 0:
			_activate_pending_gather_order()
			return
		if dropoff_target != null and is_instance_valid(dropoff_target):
			return
		_dropoff_retry_timer -= delta
		if _dropoff_retry_timer <= 0.0:
			_dropoff_retry_timer = DROP_OFF_RETRY_INTERVAL
			_find_and_go_to_dropoff()
		return

	if carried_amount >= carry_capacity:
		if dropoff_target != null and is_instance_valid(dropoff_target):
			return
		_dropoff_retry_timer -= delta
		if _dropoff_retry_timer <= 0.0:
			_dropoff_retry_timer = DROP_OFF_RETRY_INTERVAL
			_find_and_go_to_dropoff()
		return

	# Once an assigned resource leaves current vision, only its last legally
	# observed position remains usable. Do not inspect the live node (including
	# validity, remaining stock, ownership, or type) until that tile is visible.
	if _has_gather_last_known_position and not _is_gather_order_position_visible():
		_process_hidden_gather_approach(delta)
		return
	if gather_target == null and _gather_last_known_instance_id != 0:
		# A position-only pending order has now revealed its accepted tile. Resolve
		# exactly that observed identity through the current-visible registry; never
		# silently substitute a nearer resource or a replacement at the same tile.
		if _try_resume_observed_gather_target():
			return
		_clear_gather_target_knowledge()
		set_state(State.IDLE)
		return

	if not _is_new_gather_target_currently_visible(gather_target) or not _is_gather_target_valid(gather_target):
		# Resource depleted or removed
		_clear_gather_target_knowledge()
		if carried_amount > 0:
			_find_and_go_to_dropoff()
		elif not _try_retarget_resource():
			set_state(State.IDLE)
		return

	var resource_position: Vector2 = gather_target.global_position
	var approach_distance: float = BUILD_APPROACH_DISTANCE if gather_target is BuildingBase else GATHER_APPROACH_DISTANCE
	var is_farm: bool = gather_target is BuildingBase and (gather_target as BuildingBase).provides_food
	var work_distance: float = _building_work_distance(gather_target) if is_farm else global_position.distance_to(resource_position)
	if work_distance > approach_distance:
		var navigation_result: int
		if is_farm:
			navigation_result = _navigate_toward_building_work(gather_target, delta)
		else:
			navigation_result = _navigate_toward_gather_center(resource_position, approach_distance, delta)
		if navigation_result == NavigationResult.UNREACHABLE:
			_remember_unreachable_target(gather_target, _unreachable_resource_ids_until)
			_clear_gather_target_knowledge()
			_reset_navigation()
			if not _try_retarget_resource():
				set_state(State.IDLE)
		return
	_reset_navigation()

	# We are at the resource, gather
	gather_timer += delta
	if gather_timer >= gather_tick_time:
		gather_timer = 0.0
		var gathered: int = _harvest_from_target()
		carried_amount += gathered

		if carried_amount >= carry_capacity:
			_find_and_go_to_dropoff()


func _harvest_from_target() -> int:
	# Try calling harvest on the resource node if it has the method
	if gather_target.has_method("harvest"):
		var amount: int = gather_target.harvest(int(gather_rate))
		if amount > 0 and is_instance_valid(gather_target) and get_tree() and get_tree().current_scene:
			VFX.gather_particles(get_tree(), gather_target.global_position, carried_resource_type)
			var sfx_name: String = "gather_" + carried_resource_type if carried_resource_type != "" else "gather_food"
			AudioManager.play_sfx(sfx_name)
		if amount <= 0:
			# Resource exhausted
			_clear_gather_target_knowledge()
		return amount
	# Fallback: just produce resources
	return int(gather_rate)


func _find_and_go_to_dropoff() -> void:
	# Prefer resource-specific drop-offs unless a generic one is at least 30%
	# closer, but only commit to a candidate with a bounded reachable route.
	_prune_expired_unreachable_targets(_unreachable_dropoff_ids_until)
	var candidates: Array[Node2D] = []
	for building in get_tree().get_nodes_in_group("dropoff_buildings"):
		if not is_instance_valid(building):
			continue
		if building.has_method("get_player_owner") and building.get_player_owner() != player_owner:
			continue
		if building is BuildingBase and (building as BuildingBase).state != BuildingBase.State.ACTIVE:
			continue
		if _unreachable_dropoff_ids_until.has(building.get_instance_id()):
			continue
		candidates.append(building as Node2D)
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var a_distance: float = global_position.distance_to(a.global_position)
		var b_distance: float = global_position.distance_to(b.global_position)
		if a.has_method("is_drop_off_point") and bool(a.call("is_drop_off_point", carried_resource_type)):
			a_distance *= DROP_OFF_ANY_ADVANTAGE_RATIO
		if b.has_method("is_drop_off_point") and bool(b.call("is_drop_off_point", carried_resource_type)):
			b_distance *= DROP_OFF_ANY_ADVANTAGE_RATIO
		return a_distance < b_distance
	)

	var chosen_building: Node2D = null
	var chosen_route := PackedVector2Array()
	var checked: int = 0
	var recovery_threats: Array[Node2D] = []
	if _avoid_recovery_dropoff_danger:
		recovery_threats = _get_visible_recovery_threats()
	for candidate: Node2D in candidates:
		if checked >= MAX_DROPOFF_PATH_CHECKS:
			break
		checked += 1
		var route: PackedVector2Array = _get_navigation_route(candidate.global_position, BUILD_APPROACH_DISTANCE)
		if route.is_empty():
			_remember_unreachable_target(candidate, _unreachable_dropoff_ids_until)
			continue
		if route[route.size() - 1].distance_to(candidate.global_position) > BUILDING_APPROACH_DISTANCE:
			_remember_unreachable_target(candidate, _unreachable_dropoff_ids_until)
			continue
		if _avoid_recovery_dropoff_danger and _route_is_threatened(route, recovery_threats):
			continue
		chosen_building = candidate
		chosen_route = route
		break

	if chosen_building != null:
		_dropoff_retry_timer = 0.0
		_preserve_pending_gather_on_command = true
		_preserve_recovery_on_command = true
		command_move_path(chosen_route)
		_preserve_recovery_on_command = false
		_preserve_pending_gather_on_command = false
		dropoff_target = chosen_building
		_dropoff_route_active = true
		if arrived_at_destination.is_connected(_on_arrived_for_dropoff):
			arrived_at_destination.disconnect(_on_arrived_for_dropoff)
		arrived_at_destination.connect(_on_arrived_for_dropoff, CONNECT_ONE_SHOT)
	else:
		# No dropoff available yet - stay in gather state and retry.
		dropoff_target = null
		_dropoff_retry_timer = DROP_OFF_RETRY_INTERVAL
		set_state(State.GATHERING)


func _on_arrived_for_dropoff(_unit: UnitBase) -> void:
	if not _dropoff_route_active:
		return
	_dropoff_route_active = false
	var deposited: bool = _deposit_resources()
	if not deposited and carried_amount > 0:
		_find_and_go_to_dropoff()
		return
	if _activate_pending_gather_order():
		return
	if _recovery_return_only:
		_recovery_return_only = false
		_clear_gather_target_knowledge()
		gather_type = GatherType.NONE
		carried_resource_type = ""
		set_state(State.IDLE)
		return
	# Resume the last-known order without consulting a hidden resource's live state.
	_resume_gather_order_or_retarget()


func _deposit_resources() -> bool:
	if carried_amount <= 0:
		return true
	var deposited_amount: int = carried_amount
	var deposited_type: String = carried_resource_type
	if dropoff_target == null or not is_instance_valid(dropoff_target):
		return false
	if dropoff_target is BuildingBase and (dropoff_target as BuildingBase).state != BuildingBase.State.ACTIVE:
		return false
	if global_position.distance_to(dropoff_target.global_position) > BUILDING_APPROACH_DISTANCE:
		return false
	if not dropoff_target.has_method("deposit_resource"):
		return false
	dropoff_target.deposit_resource(carried_resource_type, carried_amount)
	resource_deposited.emit(carried_resource_type, carried_amount)
	carried_amount = 0
	dropoff_target = null
	_avoid_recovery_dropoff_danger = false
	# Floating resource text
	if get_tree() and get_tree().current_scene:
		var float_color: Color
		match deposited_type:
			"food": float_color = Color(0.95, 0.4, 0.3)
			"wood": float_color = Color(0.45, 0.8, 0.3)
			"gold": float_color = Color(0.95, 0.85, 0.2)
			_: float_color = Color.WHITE
		VFX.resource_float(get_tree(), global_position, "+%d %s" % [deposited_amount, deposited_type.capitalize()], float_color)
	return true


func _process_building(delta: float) -> void:
	if not _is_build_target_valid(build_target):
		build_target = null
		_reset_navigation()
		_resume_or_idle()
		return

	var dist: float = _building_work_distance(build_target)
	if dist > BUILD_APPROACH_DISTANCE:
		var navigation_result: int = _navigate_toward_building_work(build_target, delta)
		if navigation_result == NavigationResult.UNREACHABLE:
			build_target = null
			_reset_navigation()
			_resume_or_idle()
		return
	_reset_navigation()

	# We are at the building, construct
	build_timer += delta
	if build_target.has_method("add_build_progress"):
		build_target.add_build_progress(delta)
		if not is_instance_valid(build_target):
			build_target = null
			_resume_or_idle()
			return
		if build_target.has_method("is_construction_complete") and build_target.is_construction_complete():
			var completed_building: Node2D = build_target
			building_completed.emit(build_target)
			build_target = null
			if (
				is_instance_valid(completed_building)
				and completed_building is BuildingBase
				and (completed_building as BuildingBase).provides_food
				and _saved_gather_type == GatherType.NONE
				and not _saved_has_gather_last_known_position
			):
				# Unassigned farmers start work on the paid Farm they just finished.
				# Established workers keep their saved assignment. Loaded builders
				# use the normal cross-resource cargo delivery transaction.
				if command_gather(completed_building):
					_clear_saved_gather_order()
					return
			_resume_or_idle()


func _building_work_distance(building: Node2D) -> float:
	var game_map: Node2D = _get_navigation_map()
	if building is BuildingBase and game_map != null and game_map.has_method("get_building_work_distance"):
		return float(game_map.call("get_building_work_distance", global_position, building.global_position, (building as BuildingBase).footprint))
	return global_position.distance_to(building.global_position)


func _navigate_toward_building_work(building: Node2D, delta: float) -> int:
	var game_map: Node2D = _get_navigation_map()
	if not building is BuildingBase or game_map == null or not game_map.has_method("get_building_work_world_path"):
		return _navigate_toward(building.global_position, BUILD_APPROACH_DISTANCE, delta, false, false)
	var endpoint_blocked: bool = (
		_building_work_target_id == building.get_instance_id()
		and game_map.has_method("is_tile_walkable")
		and not bool(game_map.call("is_tile_walkable", game_map.call("world_to_tile", _building_work_destination)))
	)
	if not _navigation_active or _building_work_target_id != building.get_instance_id() or endpoint_blocked:
		var route: PackedVector2Array = game_map.call(
			"get_building_work_world_path", global_position, building.global_position,
			(building as BuildingBase).footprint, BUILD_APPROACH_DISTANCE
		)
		if route.is_empty():
			return NavigationResult.UNREACHABLE
		_reset_navigation()
		_building_work_target_id = building.get_instance_id()
		_building_work_destination = route[route.size() - 1]
		path = route
		path_index = 0
	# The endpoint is a walkable perimeter tile. Work starts only when the
	# footprint-distance check succeeds, never from a nearby path fallback.
	return _navigate_toward(_building_work_destination, 4.0, delta, false, false)


# --- Commands ---

func command_gather(resource_node: Node2D) -> bool:
	if current_state == State.DEAD:
		return false
	# Visibility is checked before harvestability so an explicit or stale caller
	# cannot query hidden remaining stock through command acceptance.
	if not _is_new_gather_target_currently_visible(resource_node):
		return false
	if not _is_gather_target_valid(resource_node):
		return false
	var requested_resource_type: String = _get_resource_type_from_target(resource_node)
	if requested_resource_type == "":
		return false
	_before_new_command()
	_clear_patrol()
	attack_target = null
	attack_building_target = null
	attack_move = false
	_forced_attack = false
	_reset_navigation()
	if carried_amount > 0:
		# Never rewrite the accounting type of resources already in hand. A
		# different-type order remains accepted, but is activated only after the
		# current cargo has reached a real friendly drop-off.
		if carried_resource_type == "":
			return false
		if carried_resource_type != requested_resource_type:
			_pending_gather_resource_type = requested_resource_type
			_pending_gather_last_known_position = resource_node.global_position
			_pending_gather_last_known_is_building = resource_node is BuildingBase
			_pending_gather_last_known_instance_id = resource_node.get_instance_id()
			_find_and_go_to_dropoff()
			return true
	_clear_pending_gather_order()
	gather_target = resource_node
	_gather_last_known_position = resource_node.global_position
	_has_gather_last_known_position = true
	_gather_last_known_is_building = resource_node is BuildingBase
	_gather_last_known_instance_id = resource_node.get_instance_id()
	gather_timer = 0.0
	# Stable per-worker slots keep several villagers from stacking while ensuring
	# audio/VFX RNG consumption cannot change a seeded match's economy outcome.
	_gather_offset = _get_deterministic_gather_offset(resource_node)

	carried_resource_type = requested_resource_type

	# Determine gather type enum
	match carried_resource_type:
		"food":
			gather_type = GatherType.FOOD
		"wood":
			gather_type = GatherType.WOOD
		"gold":
			gather_type = GatherType.GOLD
		_:
			gather_type = GatherType.NONE

	gathering_started.emit(resource_node)
	set_state(State.GATHERING)
	return true


func _get_deterministic_gather_offset(resource_node: Node2D) -> Vector2:
	# get_index() is stable for the unit's spawn order. Mix in the observed target
	# position so the same worker does not always approach every resource from the
	# same side; the target was already visibility-validated by command_gather().
	var unit_slot: int = maxi(0, get_index())
	var target_x: int = roundi(resource_node.global_position.x / 16.0)
	var target_y: int = roundi(resource_node.global_position.y / 16.0)
	var slot: int = posmod(unit_slot * 5 + target_x * 3 + target_y * 7 + player_owner * 11, 8)
	var angle: float = TAU * float(slot) / 8.0
	return Vector2(cos(angle) * 10.0, sin(angle) * 6.0)


func command_return_resources() -> bool:
	## Safely returns even a partial load. AI recovery uses this for an IDLE
	## villager left holding cargo after an interrupted construction or route.
	if current_state == State.DEAD or carried_amount <= 0 or carried_resource_type == "":
		return false
	var has_gather_intent: bool = (
		has_active_gather_order()
		or _pending_gather_resource_type != ""
		or (_auto_recovering and _recovery_work_state == State.GATHERING and gather_type != GatherType.NONE)
	)
	# A direct return command is compatible with an already accepted cross-type
	# order: keep that position-only intent so it can activate after delivery.
	_preserve_pending_gather_on_command = true
	_before_new_command()
	_preserve_pending_gather_on_command = false
	_clear_patrol()
	attack_target = null
	attack_building_target = null
	attack_move = false
	_forced_attack = false
	_reset_navigation()
	if not has_gather_intent:
		_recovery_return_only = true
		_clear_gather_target_knowledge()
		gather_type = GatherType.NONE
	_find_and_go_to_dropoff()
	return true


func command_build(building_site: Node2D) -> void:
	if current_state == State.DEAD:
		return
	if not _is_build_target_valid(building_site):
		return
	# Resource approach stays GATHERING, but a natural delivery leg is MOVING.
	# Explicit Move and fleeing cancel this route flag while leaving stale target
	# knowledge, so those canceled orders must not be restored after construction.
	var active_gather_delivery: bool = (
		current_state == State.MOVING
		and _dropoff_route_active
		and gather_type != GatherType.NONE
		and is_instance_valid(gather_target)
	)
	if current_state == State.GATHERING or active_gather_delivery:
		_saved_gather_target = gather_target
		_saved_gather_type = gather_type
		_saved_carried_resource_type = carried_resource_type
		_saved_gather_last_known_position = _gather_last_known_position
		_saved_has_gather_last_known_position = _has_gather_last_known_position
		_saved_gather_last_known_is_building = _gather_last_known_is_building
		_saved_gather_last_known_instance_id = _gather_last_known_instance_id
	else:
		_saved_gather_target = null
		_saved_gather_type = GatherType.NONE
		# An interrupted loaded IDLE worker has no gather order to restore, but
		# its cargo type must survive construction completion unchanged.
		_saved_carried_resource_type = carried_resource_type if carried_amount > 0 else ""
		_saved_gather_last_known_position = Vector2.ZERO
		_saved_has_gather_last_known_position = false
		_saved_gather_last_known_is_building = false
		_saved_gather_last_known_instance_id = 0
	_before_new_command()
	_clear_patrol()
	attack_target = null
	attack_building_target = null
	attack_move = false
	_forced_attack = false
	_reset_navigation()
	build_target = building_site
	build_timer = 0.0
	building_started.emit(building_site)
	set_state(State.BUILDING)


func _resume_or_idle() -> void:
	gather_target = _saved_gather_target
	gather_type = _saved_gather_type
	carried_resource_type = _saved_carried_resource_type
	_gather_last_known_position = _saved_gather_last_known_position
	_has_gather_last_known_position = _saved_has_gather_last_known_position
	_gather_last_known_is_building = _saved_gather_last_known_is_building
	_gather_last_known_instance_id = _saved_gather_last_known_instance_id
	_resume_gather_order_or_retarget()
	_clear_saved_gather_order()


func _clear_saved_gather_order() -> void:
	_saved_gather_target = null
	_saved_gather_type = GatherType.NONE
	_saved_carried_resource_type = ""
	_saved_gather_last_known_position = Vector2.ZERO
	_saved_has_gather_last_known_position = false
	_saved_gather_last_known_is_building = false
	_saved_gather_last_known_instance_id = 0


func command_retreat(safe_position: Vector2) -> bool:
	## Strategic evacuation uses the same economic recovery as a damage reaction.
	if current_state == State.DEAD or current_state == State.ATTACKING:
		return false
	if not _auto_recovering:
		_begin_recovery()
	var route: PackedVector2Array = _get_navigation_route(safe_position, NAVIGATION_POINT_TOLERANCE)
	if route.is_empty():
		_flee_to_safety()
		return true
	_recovery_refuge = null
	_move_for_recovery(route)
	return true


func _begin_recovery() -> void:
	_recovery_work_state = State.IDLE
	if current_state == State.BUILDING:
		_recovery_work_state = State.BUILDING
	elif not _recovery_return_only and (current_state == State.GATHERING or _dropoff_route_active):
		_recovery_work_state = State.GATHERING
	_auto_recovering = true
	_recovery_waiting = false
	_recovery_quiet_seconds = 0.0
	_recovery_damage_remaining = RECOVERY_DAMAGE_DELAY
	_recovery_check_timer = 0.0
	_recovery_danger_present = true
	_recovery_return_only = false
	_recovery_alternate_retry_remaining = RECOVERY_DAMAGE_DELAY
	_cancel_dropoff_route()
	_reset_navigation()


func _move_for_recovery(route: PackedVector2Array) -> void:
	_preserve_pending_gather_on_command = true
	_preserve_recovery_on_command = true
	command_move_path(route)
	_preserve_recovery_on_command = false
	_preserve_pending_gather_on_command = false
	_recovery_waiting = false
	_recovery_quiet_seconds = 0.0


func _flee_to_safety() -> void:
	## Prefer completed defensive buildings. Never choose an unreachable facade
	## or unfinished foundation as shelter, and penalize exposed arrival tiles.
	var threats: Array[Node2D] = _get_visible_recovery_threats()
	var candidates: Array[BuildingBase] = []
	for building: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not building is BuildingBase:
			continue
		if (building as BuildingBase).player_owner != player_owner:
			continue
		if (building as BuildingBase).state != BuildingBase.State.ACTIVE:
			continue
		candidates.append(building as BuildingBase)
	candidates.sort_custom(func(a: BuildingBase, b: BuildingBase) -> bool:
		var a_distance: float = global_position.distance_to(a.global_position)
		var b_distance: float = global_position.distance_to(b.global_position)
		if a.tower_attack_damage > 0 or a.building_type == BuildingData.BuildingType.TOWN_CENTER:
			a_distance *= 0.5
		if b.tower_attack_damage > 0 or b.building_type == BuildingData.BuildingType.TOWN_CENTER:
			b_distance *= 0.5
		return a_distance < b_distance
	)
	var best_route := PackedVector2Array()
	var best_refuge: BuildingBase = null
	var best_score: float = INF
	for candidate: BuildingBase in candidates.slice(0, MAX_DROPOFF_PATH_CHECKS):
		var route: PackedVector2Array = _get_refuge_world_path(candidate, threats)
		if route.is_empty():
			continue
		var endpoint: Vector2 = route[route.size() - 1]
		var score: float = global_position.distance_to(endpoint)
		if candidate.tower_attack_damage > 0 or candidate.building_type == BuildingData.BuildingType.TOWN_CENTER:
			score *= 0.5
		for threat: Node2D in threats:
			var distance: float = endpoint.distance_to(threat.global_position)
			score += maxf(0.0, _recovery_threat_distance(threat) - distance) * 4.0
		if score < best_score:
			best_score = score
			best_route = route
			best_refuge = candidate
	if not best_route.is_empty():
		_recovery_refuge = best_refuge
		_move_for_recovery(best_route)
		return
	# With no surviving/reachable base, a visible threat still supplies a legal
	# escape direction. A blocked escape holds the order and retries safely.
	if not threats.is_empty():
		var away := Vector2.ZERO
		for threat: Node2D in threats:
			var offset: Vector2 = global_position - threat.global_position
			if offset.length() < RECOVERY_MIN_THREAT_DISTANCE * 2.0:
				away += offset.normalized()
		if away.length() > 0.001:
			var route: PackedVector2Array = _get_navigation_route(global_position + away.normalized() * RECOVERY_MIN_THREAT_DISTANCE, NAVIGATION_POINT_TOLERANCE)
			if not route.is_empty() and route[-1].distance_to(global_position) > NAVIGATION_POINT_TOLERANCE:
				_recovery_refuge = null
				_move_for_recovery(route)
				return
	_reset_navigation()
	_recovery_refuge = null
	_recovery_waiting = true
	set_state(State.MOVING)


func _get_refuge_world_path(building: BuildingBase, threats: Array[Node2D]) -> PackedVector2Array:
	var game_map: Node2D = _get_navigation_map()
	if game_map == null or not game_map.has_method("get_building_work_distance"):
		return _get_navigation_route(building.global_position, BUILD_APPROACH_DISTANCE)
	var origin: Vector2i = game_map.call("world_to_tile", building.global_position)
	var goals: Array[Vector2] = []
	for dy: int in range(-1, building.footprint.y + 1):
		for dx: int in range(-1, building.footprint.x + 1):
			if dx >= 0 and dx < building.footprint.x and dy >= 0 and dy < building.footprint.y:
				continue
			var tile: Vector2i = origin + Vector2i(dx, dy)
			if not bool(game_map.call("is_tile_walkable", tile)):
				continue
			var point: Vector2 = game_map.call("tile_to_world", tile)
			if float(game_map.call("get_building_work_distance", point, building.global_position, building.footprint)) > BUILD_APPROACH_DISTANCE:
				continue
			# Defensive shelter must be inside the actual fire disk, not merely
			# adjacent to one of a large building's distant footprint corners.
			if building.tower_attack_damage > 0 and point.distance_to(building.global_position) > building.tower_attack_range:
				continue
			goals.append(point)
	goals.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return _refuge_point_score(a, threats) < _refuge_point_score(b, threats)
	)
	for point: Vector2 in goals.slice(0, MAX_DROPOFF_PATH_CHECKS):
		var route: PackedVector2Array = _get_navigation_route(point, NAVIGATION_POINT_TOLERANCE)
		if route.is_empty() or route[-1].distance_to(point) > NAVIGATION_POINT_TOLERANCE:
			continue
		if building.tower_attack_damage > 0 and route[-1].distance_to(building.global_position) > building.tower_attack_range:
			continue
		return route
	return PackedVector2Array()


func _refuge_point_score(point: Vector2, threats: Array[Node2D]) -> float:
	var score: float = global_position.distance_to(point)
	for threat: Node2D in threats:
		score += maxf(0.0, _recovery_threat_distance(threat) - point.distance_to(threat.global_position)) * 4.0
	return score


func _get_visible_recovery_threats() -> Array[Node2D]:
	var threats: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not node is UnitBase or node == self or not _can_track_entity(node as Node2D):
			continue
		var unit := node as UnitBase
		if unit.player_owner == player_owner or unit.current_state == State.DEAD or unit.damage <= 0.0:
			continue
		if unit is Villager and unit.current_state != State.ATTACKING:
			continue
		threats.append(unit)
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not node is BuildingBase or not _can_track_entity(node as Node2D):
			continue
		var building := node as BuildingBase
		if building.player_owner != player_owner and building.state == BuildingBase.State.ACTIVE and building.tower_attack_damage > 0:
			threats.append(building)
	return threats


func _recovery_threat_distance(threat: Node2D) -> float:
	var range_world: float = (threat as UnitBase).attack_range if threat is UnitBase else (threat as BuildingBase).tower_attack_range
	return maxf(RECOVERY_MIN_THREAT_DISTANCE, range_world + RECOVERY_THREAT_MARGIN)


func _process_recovery(delta: float) -> void:
	_recovery_damage_remaining = maxf(0.0, _recovery_damage_remaining - delta)
	_recovery_alternate_retry_remaining = maxf(0.0, _recovery_alternate_retry_remaining - delta)
	_recovery_check_timer -= delta
	if _recovery_check_timer <= 0.0:
		_recovery_check_timer = RECOVERY_CHECK_INTERVAL
		var threats: Array[Node2D] = _get_visible_recovery_threats()
		_recovery_danger_present = _recovery_work_is_threatened(threats)
		if (
			_recovery_waiting and _recovery_danger_present
			and _recovery_damage_remaining <= 0.0 and _recovery_alternate_retry_remaining <= 0.0
			and not _position_is_threatened(global_position, threats)
		):
			_recovery_alternate_retry_remaining = RECOVERY_QUIET_SECONDS
			if _try_resume_safer_resource(threats):
				return
		if _recovery_waiting and (
			(_recovery_refuge != null and (not is_instance_valid(_recovery_refuge) or _recovery_refuge.state != BuildingBase.State.ACTIVE))
			or _position_is_threatened(global_position, threats)
		):
			_flee_to_safety()
	if not _recovery_waiting:
		return
	if _recovery_damage_remaining > 0.0 or _recovery_danger_present:
		_recovery_quiet_seconds = 0.0
		return
	_recovery_quiet_seconds += delta
	if _recovery_quiet_seconds >= RECOVERY_QUIET_SECONDS:
		_resume_after_recovery()


func _position_is_threatened(position: Vector2, threats: Array[Node2D]) -> bool:
	for threat: Node2D in threats:
		if position.distance_to(threat.global_position) < _recovery_threat_distance(threat):
			return true
	return false


func _route_is_threatened(route: PackedVector2Array, threats: Array[Node2D]) -> bool:
	for point: Vector2 in route:
		if _position_is_threatened(point, threats):
			return true
	return false


func _try_resume_safer_resource(threats: Array[Node2D]) -> bool:
	# A camper can outlast the base's fire range. Once sheltered and no longer
	# taking hits, keep the same kind of work on a currently visible safe target
	# rather than freezing the economy or walking back into that known danger.
	if _recovery_work_state != State.GATHERING:
		return false
	var game_map: Node2D = _find_resource_game_map()
	if game_map == null or not game_map.has_method("get_nearest_reachable_resource_node"):
		return false
	var requested_type: String = _pending_gather_resource_type if _pending_gather_resource_type != "" else carried_resource_type
	var exclusions: Dictionary = _unreachable_resource_ids_until.duplicate()
	for index: int in range(MAX_DROPOFF_PATH_CHECKS):
		var candidate: Node2D = game_map.call("get_nearest_reachable_resource_node", requested_type, global_position, player_owner, exclusions) as Node2D
		if candidate == null or not _is_new_gather_target_currently_visible(candidate):
			return false
		var route: PackedVector2Array
		if candidate is BuildingBase and game_map.has_method("get_building_work_world_path"):
			route = game_map.call("get_building_work_world_path", global_position, candidate.global_position, (candidate as BuildingBase).footprint, BUILD_APPROACH_DISTANCE)
		else:
			route = _get_navigation_route(candidate.global_position, GATHER_APPROACH_DISTANCE)
		if not route.is_empty() and not _position_is_threatened(candidate.global_position, threats) and not _route_is_threatened(route, threats):
			if not command_gather(candidate):
				return false
			if carried_amount > 0:
				_avoid_recovery_dropoff_danger = true
				_find_and_go_to_dropoff()
			return true
		exclusions[candidate.get_instance_id()] = true
	return false


func _recovery_work_is_threatened(threats: Array[Node2D]) -> bool:
	if _position_is_threatened(global_position, threats):
		return true
	if threats.is_empty():
		return false
	var work_position: Vector2 = global_position
	var has_work_position: bool = false
	if _recovery_work_state == State.BUILDING and _is_build_target_valid(build_target):
		work_position = build_target.global_position
		has_work_position = true
	elif _recovery_work_state == State.GATHERING:
		if _pending_gather_resource_type != "":
			work_position = _pending_gather_last_known_position
			has_work_position = true
		elif _has_gather_last_known_position:
			work_position = _gather_last_known_position
			has_work_position = true
	if not has_work_position:
		return false
	if _position_is_threatened(work_position, threats):
		return true
	# Only the accepted position is used here; a hidden resource's live node is
	# never queried to decide whether its old route is safe.
	var route: PackedVector2Array = _get_navigation_route(work_position, GATHER_APPROACH_DISTANCE)
	return _route_is_threatened(route, threats)


func _resume_after_recovery() -> void:
	var work_state: int = _recovery_work_state
	_clear_recovery()
	_reset_navigation()
	if work_state == State.BUILDING:
		if _is_build_target_valid(build_target):
			set_state(State.BUILDING)
		else:
			build_target = null
			_resume_or_idle()
		return
	if carried_amount > 0:
		_avoid_recovery_dropoff_danger = true
		_recovery_return_only = work_state != State.GATHERING
		if _recovery_return_only:
			_clear_gather_target_knowledge()
			gather_type = GatherType.NONE
		_find_and_go_to_dropoff()
		return
	if work_state == State.GATHERING:
		if not _activate_pending_gather_order():
			_resume_gather_order_or_retarget()
		return
	set_state(State.IDLE)


func _clear_recovery() -> void:
	_auto_recovering = false
	_recovery_waiting = false
	_recovery_work_state = State.IDLE
	_recovery_refuge = null
	_recovery_quiet_seconds = 0.0
	_recovery_damage_remaining = 0.0


func _try_retarget_resource() -> bool:
	if carried_resource_type == "":
		return false
	var game_map: Node2D = _find_resource_game_map()
	if game_map == null:
		return false
	_prune_expired_unreachable_targets(_unreachable_resource_ids_until)
	var new_target: Node2D = null
	if game_map.has_method("get_nearest_reachable_resource_node"):
		new_target = game_map.call(
			"get_nearest_reachable_resource_node",
			carried_resource_type,
			global_position,
			player_owner,
			_unreachable_resource_ids_until
		)
	else:
		new_target = game_map.get_nearest_resource_node(carried_resource_type, global_position, player_owner)
	if new_target != null and is_instance_valid(new_target):
		return command_gather(new_target)
	return false


func _resume_gather_order_or_retarget() -> void:
	if _has_gather_last_known_position and not _is_gather_order_position_visible():
		_cancel_dropoff_route()
		_reset_navigation()
		gather_timer = 0.0
		set_state(State.GATHERING)
		return
	if (
		gather_target != null
		and is_instance_valid(gather_target)
		and _is_new_gather_target_currently_visible(gather_target)
		and _is_gather_target_valid(gather_target)
		and command_gather(gather_target)
	):
		return
	_clear_gather_target_knowledge()
	if not _try_retarget_resource():
		if carried_amount > 0 and carried_resource_type != "":
			# Natural construction/resume can outlast the last reachable resource.
			# Deliver its remaining cargo once before idling; explicit Stop/Move
			# cancel this return through the ordinary new-command boundary.
			_recovery_return_only = true
			gather_type = GatherType.NONE
			_find_and_go_to_dropoff()
		else:
			set_state(State.IDLE)


func _activate_pending_gather_order() -> bool:
	if _pending_gather_resource_type == "":
		return false
	var pending_type: String = _pending_gather_resource_type
	var pending_position: Vector2 = _pending_gather_last_known_position
	var pending_is_building: bool = _pending_gather_last_known_is_building
	var pending_instance_id: int = _pending_gather_last_known_instance_id
	_clear_pending_gather_order()

	# The original cargo is already zero. The pending command retained no live
	# resource reference: if its tile is visible now, resolve a reachable current-
	# vision resource of the requested type. Otherwise approach only the legally
	# observed position and resolve after the worker reveals it.
	gather_target = null
	carried_resource_type = pending_type
	gather_type = _gather_type_for_resource(pending_type)
	_gather_last_known_position = pending_position
	_has_gather_last_known_position = true
	_gather_last_known_is_building = pending_is_building
	_gather_last_known_instance_id = pending_instance_id
	if not _is_world_position_visible(pending_position):
		_cancel_dropoff_route()
		_reset_navigation()
		gather_timer = 0.0
		set_state(State.GATHERING)
		return true
	if _try_resume_observed_gather_target():
		return true
	_clear_gather_target_knowledge()
	set_state(State.IDLE)
	return true


func _try_resume_observed_gather_target() -> bool:
	if (
		_gather_last_known_instance_id == 0
		or not _has_gather_last_known_position
		or not _is_world_position_visible(_gather_last_known_position)
	):
		return false
	var game_map: Node2D = _find_resource_game_map()
	if game_map == null or not game_map.has_method("get_nearest_resource_node"):
		return false
	# Registry lookup is called only after the observed tile is currently visible;
	# its player-id contract filters hidden, depleted, enemy-owned, and unregistered
	# candidates before returning a live object.
	var registered_target: Node2D = game_map.call(
		"get_nearest_resource_node",
		carried_resource_type,
		_gather_last_known_position,
		player_owner
	) as Node2D
	if registered_target == null:
		return false
	if not _is_new_gather_target_currently_visible(registered_target):
		return false
	if registered_target.get_instance_id() != _gather_last_known_instance_id:
		return false
	return command_gather(registered_target)


func _process_hidden_gather_approach(delta: float) -> void:
	var approach_distance: float = (
		BUILD_APPROACH_DISTANCE if _gather_last_known_is_building else GATHER_APPROACH_DISTANCE
	)
	# Fog-safe memory retains the observed center. Offset is only a movement
	# preference, so reaching the center-based action radius waits for reveal
	# without blacklisting a legally reachable hidden target.
	if global_position.distance_to(_gather_last_known_position) <= approach_distance:
		_reset_navigation()
		return
	var navigation_result: int = _navigate_toward_gather_center(
		_gather_last_known_position,
		approach_distance,
		delta
	)
	if navigation_result == NavigationResult.UNREACHABLE:
		# A hidden target cannot be validated or replaced from registry knowledge.
		# Preserve no live reference-based conclusion and recover to a stable idle.
		_clear_gather_target_knowledge()
		_reset_navigation()
		set_state(State.IDLE)


func _navigate_toward_gather_center(
	resource_center: Vector2,
	action_radius: float,
	delta: float
) -> int:
	# An offset is a traffic preference, not a different interaction contract.
	# Shrinking its arrival disk by the offset length means ARRIVED implies the
	# worker is also inside the center-based action disk (triangle inequality).
	# If that stricter offset route is unavailable (notably beside a solid Farm),
	# retain a canonical center/full-radius fallback before declaring the observed
	# resource unreachable.
	var offset_length: float = _gather_offset.length()
	var using_center_fallback: bool = (
		_navigation_active
		and _navigation_goal.distance_to(resource_center) <= 2.0
	)
	var navigation_target: Vector2 = (
		resource_center if using_center_fallback else resource_center + _gather_offset
	)
	var navigation_radius: float = (
		action_radius if using_center_fallback else maxf(0.0, action_radius - offset_length)
	)
	var result: int = _navigate_toward(
		navigation_target,
		navigation_radius,
		delta,
		false,
		false
	)
	if (
		result == NavigationResult.UNREACHABLE
		and not using_center_fallback
		and offset_length > 0.001
	):
		_reset_navigation()
		return _navigate_toward(resource_center, action_radius, delta, false, false)
	return result


func _is_new_gather_target_currently_visible(resource_node: Variant) -> bool:
	if not is_instance_valid(resource_node) or not resource_node is Node2D:
		return false
	var target_node: Node2D = resource_node as Node2D
	var game_map: Node2D = _find_resource_game_map()
	if game_map == null or not game_map.has_method("is_entity_visible_to_player"):
		# Detached unit fixtures and legacy embedders have no fog authority.
		return true
	return bool(game_map.call("is_entity_visible_to_player", target_node, player_owner))


func _is_gather_order_position_visible() -> bool:
	if not _has_gather_last_known_position:
		return true
	var game_map: Node2D = _find_resource_game_map()
	if game_map == null:
		return true
	if game_map.has_method("world_to_tile") and game_map.has_method("is_tile_visible_to_player"):
		var tile: Vector2i = game_map.call("world_to_tile", _gather_last_known_position) as Vector2i
		return bool(game_map.call("is_tile_visible_to_player", tile, player_owner))
	if (
		game_map.has_method("is_entity_visible_to_player")
		and gather_target != null
		and is_instance_valid(gather_target)
	):
		return bool(game_map.call("is_entity_visible_to_player", gather_target, player_owner))
	return true


func _is_world_position_visible(world_position: Vector2) -> bool:
	var game_map: Node2D = _find_resource_game_map()
	if game_map == null:
		return true
	if game_map.has_method("world_to_tile") and game_map.has_method("is_tile_visible_to_player"):
		var tile: Vector2i = game_map.call("world_to_tile", world_position) as Vector2i
		return bool(game_map.call("is_tile_visible_to_player", tile, player_owner))
	return false


func _find_resource_game_map() -> Node2D:
	var parent: Node = get_parent()
	while parent != null:
		if parent.has_method("get_nearest_resource_node"):
			return parent as Node2D
		parent = parent.get_parent()
	return null


func _clear_gather_target_knowledge() -> void:
	gather_target = null
	_gather_last_known_position = Vector2.ZERO
	_has_gather_last_known_position = false
	_gather_last_known_is_building = false
	_gather_last_known_instance_id = 0


func _clear_pending_gather_order() -> void:
	_pending_gather_resource_type = ""
	_pending_gather_last_known_position = Vector2.ZERO
	_pending_gather_last_known_is_building = false
	_pending_gather_last_known_instance_id = 0


func _get_resource_type_from_target(resource_node: Node2D) -> String:
	# Callers must establish current visibility before using this helper.
	if resource_node.has_method("get_resource_type"):
		return str(resource_node.call("get_resource_type"))
	if resource_node.is_in_group("food_resources"):
		return "food"
	if resource_node.is_in_group("wood_resources"):
		return "wood"
	if resource_node.is_in_group("gold_resources"):
		return "gold"
	return ""


func _gather_type_for_resource(resource_type: String) -> int:
	match resource_type:
		"food":
			return GatherType.FOOD
		"wood":
			return GatherType.WOOD
		"gold":
			return GatherType.GOLD
	return GatherType.NONE


func _before_new_command() -> void:
	_observed_worker_threat_distances.clear()
	# Spread a selected worker group's four-Hz vision checks across five phases.
	_economic_threat_check_timer = float(posmod(get_index(), 5)) * 0.05
	if not _preserve_recovery_on_command:
		_clear_recovery()
		_recovery_return_only = false
		_avoid_recovery_dropoff_danger = false
	_building_work_target_id = 0
	_cancel_dropoff_route()
	if not _preserve_pending_gather_on_command:
		_clear_pending_gather_order()


func _cancel_dropoff_route() -> void:
	_dropoff_route_active = false
	dropoff_target = null
	if arrived_at_destination.is_connected(_on_arrived_for_dropoff):
		arrived_at_destination.disconnect(_on_arrived_for_dropoff)


func _on_navigation_unreachable(target_position: Vector2) -> void:
	if _auto_recovering:
		_reset_navigation()
		_recovery_refuge = null
		_recovery_waiting = true
		_recovery_quiet_seconds = 0.0
		navigation_failed.emit(self, target_position)
		return
	if _dropoff_route_active and dropoff_target != null and is_instance_valid(dropoff_target):
		_remember_unreachable_target(dropoff_target, _unreachable_dropoff_ids_until)
		_cancel_dropoff_route()
		_reset_navigation()
		navigation_failed.emit(self, target_position)
		set_state(State.GATHERING)
		_find_and_go_to_dropoff()
		return
	super._on_navigation_unreachable(target_position)


func _remember_unreachable_target(target: Node2D, cache: Dictionary) -> void:
	if target != null and is_instance_valid(target):
		cache[target.get_instance_id()] = Time.get_ticks_msec() + UNREACHABLE_TARGET_IGNORE_MSEC


func _prune_expired_unreachable_targets(cache: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	for instance_id: Variant in cache.keys():
		if now >= int(cache[instance_id]):
			cache.erase(instance_id)


func _is_gather_target_valid(resource_node: Node2D) -> bool:
	if resource_node == null or not is_instance_valid(resource_node):
		return false
	if not resource_node.has_method("get_resource_type") or not resource_node.has_method("harvest"):
		return false
	if resource_node.has_method("is_harvestable_by"):
		return bool(resource_node.call("is_harvestable_by", player_owner))
	return true


func _is_build_target_valid(building_site: Variant) -> bool:
	# A destroyed job can retain a freed Object until the worker's next tick.
	# Accept it at this validation boundary so the check can reject it safely.
	if building_site == null or not is_instance_valid(building_site):
		return false
	if not building_site is Node2D:
		return false
	if building_site is BuildingBase:
		var building := building_site as BuildingBase
		return building.player_owner == player_owner and building.state == BuildingBase.State.CONSTRUCTING
	return building_site.has_method("add_build_progress")


# --- Override draw for carried resource indicator ---

func _draw() -> void:
	super._draw()
	# Show resource indicator when gathering or carrying resources
	if current_state == State.GATHERING or carried_amount > 0:
		var res_color: Color
		match carried_resource_type:
			"food":
				res_color = Color(1.0, 0.3, 0.3)  # red
			"wood":
				res_color = Color(0.5, 0.3, 0.1)  # brown
			"gold":
				res_color = Color(1.0, 0.85, 0.0) # gold
			_:
				res_color = Color.WHITE
		var size: float = UNIT_SIZES.get(unit_type, 8.0)
		var dot_pos := Vector2(size + 4.0, 0)
		# Black outline
		draw_circle(dot_pos, 6.0, Color(0, 0, 0, 0.6))
		# Colored dot (larger)
		draw_circle(dot_pos, 5.0, res_color)
