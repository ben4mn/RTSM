class_name UnitBase
extends Area2D
## Base class for all units in AOEM. Handles movement, selection,
## health, state machine, auto-attack behavior, and sprite-based rendering.

signal unit_died(unit: UnitBase)
signal unit_selected(unit: UnitBase)
signal unit_deselected(unit: UnitBase)
signal health_changed(unit: UnitBase, new_hp: float, max_hp: float)
signal attack_landed(attacker: UnitBase, defender: UnitBase, hp_loss: float, counter_bonus: float)
signal state_changed(unit: UnitBase, new_state: int)
signal arrived_at_destination(unit: UnitBase)
signal navigation_failed(unit: UnitBase, target_position: Vector2)

enum State { IDLE, MOVING, ATTACKING, GATHERING, BUILDING, DEAD }
enum Stance { AGGRESSIVE, STAND_GROUND }
enum NavigationResult { MOVING, ARRIVED, UNREACHABLE }

# --- Stats (overridden per unit type) ---
@export var unit_type: int = UnitData.UnitType.VILLAGER
@export var player_owner: int = 0
@export var max_hp: float = 25.0
@export var hp: float = 25.0
@export var damage: float = 3.0  # Base stat; Combat adds the owner's live upgrade.
@export var armor: float = 0.0  # Base stat; Combat adds the owner's live upgrade.
@export var speed: float = 60.0
@export var attack_range: float = 10.0
@export var vision_radius: float = 4.0
@export var attack_speed: float = 1.0  # attacks per second
@export var is_ranged: bool = false

# --- Runtime state ---
var current_state: int = State.IDLE
var stance: int = Stance.AGGRESSIVE
var move_target: Vector2 = Vector2.ZERO
var attack_target: UnitBase = null
var attack_building_target: BuildingBase = null
var is_selected: bool = false
var attack_cooldown: float = 0.0
var path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var team_color: Color = Color.BLUE
var attack_move: bool = false
var kills: int = 0
var _auto_attack_timer: float = 0.0  # Throttles enemy scanning (seconds until next scan)
var _stuck_timer: float = 0.0        # Detects stuck units during movement
var _last_move_pos: Vector2 = Vector2.ZERO
var _forced_attack: bool = false      # True when explicit player/AI attack command should override stance chase limits.
var _force_move_active: bool = false  # Explicit Move ignores enemies until arrival, failure, or another command.
var _patrol_active: bool = false
var _patrol_point_a: Vector2 = Vector2.ZERO
var _patrol_point_b: Vector2 = Vector2.ZERO
var _patrol_to_b: bool = true
var _separation_timer: float = 0.0
var _separation_vector: Vector2 = Vector2.ZERO
var _navigation_active: bool = false
var _navigation_goal: Vector2 = Vector2.ZERO
var _navigation_target_snapshot: Vector2 = Vector2.ZERO
var _navigation_repath_cooldown: float = 0.0
var _navigation_failed_repaths: int = 0
var _navigation_stall_repaths: int = 0
var _navigation_map: Node2D = null
var _ignored_auto_targets_until: Dictionary = {}
var _attack_windup_remaining: float = -1.0
var _attack_windup_target: Node2D = null
var _attack_windup_building: bool = false
var _attack_animation_remaining: float = 0.0
var _attack_animation_duration: float = 0.3
var _attack_animation_direction: Vector2 = Vector2.RIGHT
var _animation_clock: float = 0.0
var _last_visual_position: Vector2 = Vector2.ZERO

# --- Node references ---
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# --- Sprite mapping per unit type from Kenney Medieval RTS pack ---
const UNIT_SPRITES: Dictionary = {
	UnitData.UnitType.VILLAGER: "res://assets/units/unit_01.png",
	UnitData.UnitType.INFANTRY: "res://assets/units/warrior.svg",
	UnitData.UnitType.ARCHER: "res://assets/units/archer.svg",
	UnitData.UnitType.CAVALRY: "res://assets/units/cavalry.svg",
	UnitData.UnitType.SCOUT: "res://assets/units/scout.svg",
	UnitData.UnitType.SIEGE: "res://assets/units/siege.svg",
}

# --- Sizes per unit type ---
const UNIT_SIZES: Dictionary = {
	UnitData.UnitType.VILLAGER: 12.0,
	UnitData.UnitType.INFANTRY: 14.0,
	UnitData.UnitType.ARCHER: 13.0,
	UnitData.UnitType.CAVALRY: 16.0,
	UnitData.UnitType.SCOUT: 12.0,
	UnitData.UnitType.SIEGE: 18.0,
}

# --- Sprite scales per unit type (128x128 sprites scaled down) ---
const UNIT_SPRITE_SCALES: Dictionary = {
	UnitData.UnitType.VILLAGER: Vector2(0.43, 0.43),
	UnitData.UnitType.INFANTRY: Vector2(0.46, 0.46),
	UnitData.UnitType.ARCHER: Vector2(0.43, 0.43),
	UnitData.UnitType.CAVALRY: Vector2(0.50, 0.50),
	UnitData.UnitType.SCOUT: Vector2(0.48, 0.48),
	UnitData.UnitType.SIEGE: Vector2(0.50, 0.50),
}

var _sprite: Sprite2D = null

const FRIENDLY_SEPARATION_RADIUS: float = 34.0
const FRIENDLY_SEPARATION_WEIGHT: float = 1.15
const FRIENDLY_SEPARATION_MAX_STEER: float = 0.75
const FRIENDLY_SEPARATION_REFRESH: float = 0.06
const NAVIGATION_POINT_TOLERANCE: float = 4.0
const NAVIGATION_REPATH_INTERVAL: float = 0.45
const NAVIGATION_DYNAMIC_REPATH_INTERVAL: float = 0.65
const NAVIGATION_DYNAMIC_REPATH_DISTANCE: float = 20.0
const NAVIGATION_STUCK_TIMEOUT: float = 1.25
const NAVIGATION_MAX_FAILED_REPATHS: int = 4
const NAVIGATION_MAX_STALL_REPATHS: int = 3
const AUTO_TARGET_IGNORE_MSEC: int = 3000


func _ready() -> void:
	_setup_collision()
	_load_stats_from_data()
	_setup_sprite()
	add_to_group("units")
	add_to_group("player_%d" % player_owner)
	queue_redraw()


func _setup_collision() -> void:
	var shape := CircleShape2D.new()
	shape.radius = UNIT_SIZES.get(unit_type, 10.0)
	collision_shape.shape = shape


func _load_stats_from_data() -> void:
	var stats: Dictionary = UnitData.get_unit_stats(unit_type)
	if stats.is_empty():
		return
	max_hp = float(stats.get("hp", max_hp))
	hp = max_hp
	damage = float(stats.get("damage", damage))
	armor = float(stats.get("armor", armor))
	speed = float(stats.get("speed", speed))
	# Data files use canonical range tiles; runtime movement/combat uses world units.
	attack_range = MapData.range_tiles_to_world(float(stats.get("attack_range", attack_range)))
	vision_radius = MapData.range_tiles_to_world(float(stats.get("vision_radius", vision_radius)))
	is_ranged = stats.get("attack_range", 1) > 1
	attack_speed = 1.0 / maxf(0.1, float(stats.get("attack_interval", 1.0)))


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "UnitSprite"
	var tex_path: String = UNIT_SPRITES.get(unit_type, "")
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_sprite.texture = load(tex_path)
	_sprite.scale = UNIT_SPRITE_SCALES.get(unit_type, Vector2(0.20, 0.20))
	_sprite.offset = Vector2(0, -18)  # Put the feet on the ground marker.
	if unit_type != UnitData.UnitType.VILLAGER:
		_sprite.offset.y = -40.0
	add_child(_sprite)
	# Apply team color tint to enemy units
	if player_owner != 0:
		_sprite.modulate = Color(1.0, 0.4, 0.4)  # Bold red tint for enemies
	_last_visual_position = global_position


func _process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	_auto_attack_timer = maxf(0.0, _auto_attack_timer - delta)
	_separation_timer = maxf(0.0, _separation_timer - delta)
	_navigation_repath_cooldown = maxf(0.0, _navigation_repath_cooldown - delta)
	_advance_attack_windup(delta)

	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.MOVING:
			_process_moving(delta)
		State.ATTACKING:
			_process_attacking(delta)
		State.GATHERING:
			_process_gathering(delta)
		State.BUILDING:
			_process_building(delta)
	_update_sprite_motion(delta)

	# Continuous redraw for pulsing selection
	if is_selected:
		queue_redraw()


func _draw() -> void:
	var size: float = UNIT_SIZES.get(unit_type, 10.0)

	# A ground ellipse reads as a person standing on the isometric map.
	var ground_ring := PackedVector2Array()
	for i in range(33):
		var angle: float = float(i) / 32.0 * TAU
		ground_ring.append(Vector2(cos(angle) * (size + 1.0), sin(angle) * size * 0.48 + 3.0))
	draw_colored_polygon(ground_ring, Color(0.04, 0.09, 0.10, 0.28))
	draw_polyline(ground_ring, team_color.lightened(0.18), 1.6, true)

	# Selection indicator (pulsing circle under unit)
	if is_selected:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		var sel_alpha := lerpf(0.45, 0.95, pulse)
		draw_polyline(ground_ring, Color(1.0, 0.86, 0.49, sel_alpha), 3.0, true)

	# Critical HP pulsing red ring (< 25% HP)
	var hp_ratio: float = hp / max_hp if max_hp > 0 else 0.0
	if hp_ratio > 0.0 and hp_ratio < 0.25:
		var crit_pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
		draw_arc(Vector2.ZERO, size + 3.0, 0, TAU, 24, Color(1.0, 0.2, 0.1, crit_pulse * 0.6), 2.0)
		queue_redraw()

	# Health bar (above unit)
	var bar_width: float = size * 2.5
	var bar_height: float = 3.0
	var bar_y: float = -(size + 12.0) if unit_type == UnitData.UnitType.VILLAGER else -43.0

	# Healthy unselected villagers need no floating meter clutter.
	if is_selected or hp < max_hp:
		draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width, bar_height), Color(0.06, 0.12, 0.14, 0.9))
		var hp_color := Color("9dcd81") if hp_ratio > 0.5 else (Color("e2bd67") if hp_ratio > 0.25 else Color("e97865"))
		draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width * hp_ratio, bar_height), hp_color)

	# Ranged indicator (small diamond on top)
	if is_ranged:
		var pts := PackedVector2Array([
			Vector2(0, -size - 6),
			Vector2(3, -size - 3),
			Vector2(0, -size),
			Vector2(-3, -size - 3),
		])
		draw_colored_polygon(pts, Color(1, 1, 1, 0.7))

	# Stance indicator: shield icon for Stand Ground
	if stance == Stance.STAND_GROUND:
		var sx := size + 4.0
		var sy := -2.0
		var shield_pts := PackedVector2Array([
			Vector2(sx - 3, sy - 4),
			Vector2(sx + 3, sy - 4),
			Vector2(sx + 3, sy + 1),
			Vector2(sx, sy + 4),
			Vector2(sx - 3, sy + 1),
		])
		draw_colored_polygon(shield_pts, Color(0.9, 0.75, 0.2, 0.85))
		draw_polyline(shield_pts, Color(0.6, 0.45, 0.1, 0.9), 1.0)


# --- State Machine ---

func set_state(new_state: int) -> void:
	if current_state == State.DEAD:
		return
	# Force-move is movement intent, not a stance. Any non-moving task must
	# discard it even when the state itself does not change.
	if new_state != State.MOVING:
		_force_move_active = false
	if current_state == new_state:
		return
	current_state = new_state
	# Reset stuck detection when entering MOVING state
	if new_state == State.MOVING:
		_stuck_timer = 0.0
		_last_move_pos = global_position
	state_changed.emit(self, new_state)
	queue_redraw()


func _process_idle(_delta: float) -> void:
	# Look for nearby enemies to auto-attack (stand ground uses shorter range)
	_try_auto_attack()


func _process_moving(delta: float) -> void:
	var navigation_result: int = _navigate_toward(
		move_target,
		NAVIGATION_POINT_TOLERANCE,
		delta,
		false,
		true
	)
	if navigation_result == NavigationResult.ARRIVED:
		_on_reached_destination()
		return
	if navigation_result == NavigationResult.UNREACHABLE:
		_on_navigation_unreachable(move_target)
		return

	# A-Move and Patrol always scan. Other movement respects stance, while an
	# explicit Move is gated by its no-engagement intent.
	if not _force_move_active and attack_target == null and (attack_move or stance == Stance.AGGRESSIVE):
		_try_auto_attack()


func _on_reached_destination() -> void:
	_reset_navigation()
	_force_move_active = false
	if _patrol_active and _patrol_point_a.distance_to(_patrol_point_b) > 8.0:
		_patrol_to_b = not _patrol_to_b
		move_target = _patrol_point_b if _patrol_to_b else _patrol_point_a
		set_state(State.MOVING)
		return
	set_state(State.IDLE)
	arrived_at_destination.emit(self)


## Advance along a bounded A* route. `accept_nearest_endpoint` is only for
## ground/flee orders; interactions must actually enter their action radius.
func _navigate_toward(
	target_position: Vector2,
	arrival_radius: float,
	delta: float,
	dynamic_target: bool = false,
	accept_nearest_endpoint: bool = false
) -> int:
	if global_position.distance_to(target_position) <= arrival_radius:
		return NavigationResult.ARRIVED

	var had_existing_path: bool = not path.is_empty() and path_index < path.size()
	if not _navigation_active or (not dynamic_target and _navigation_goal.distance_to(target_position) > 2.0):
		_navigation_active = true
		_navigation_goal = target_position
		_navigation_target_snapshot = target_position
		_navigation_failed_repaths = 0
		_navigation_stall_repaths = 0
		_navigation_repath_cooldown = NAVIGATION_REPATH_INTERVAL if had_existing_path else 0.0
		_stuck_timer = 0.0
		_last_move_pos = global_position
	elif dynamic_target:
		_navigation_goal = target_position

	var game_map := _get_navigation_map()
	if game_map == null:
		# Unit-only fixtures and editor previews do not have a GameMap. The real
		# match always does; retain deterministic direct motion only for that case.
		_move_in_direction(target_position - global_position, delta, null)
		return NavigationResult.MOVING

	var target_moved: bool = _navigation_target_snapshot.distance_to(target_position) >= NAVIGATION_DYNAMIC_REPATH_DISTANCE
	if dynamic_target and target_moved and _navigation_repath_cooldown <= 0.0:
		path = PackedVector2Array()
		path_index = 0

	if not path.is_empty() and path_index < path.size() and game_map.has_method("world_to_tile") and game_map.has_method("is_tile_walkable"):
		var waypoint_tile: Vector2i = game_map.call("world_to_tile", path[path_index])
		if not bool(game_map.call("is_tile_walkable", waypoint_tile)):
			path = PackedVector2Array()
			path_index = 0
			_navigation_repath_cooldown = 0.0

	if path.is_empty() or path_index >= path.size():
		if _navigation_repath_cooldown > 0.0:
			return NavigationResult.MOVING
		if not _request_navigation_path(game_map, target_position, arrival_radius, dynamic_target):
			return _navigation_failure_result()

	while path_index < path.size() and global_position.distance_to(path[path_index]) <= NAVIGATION_POINT_TOLERANCE:
		path_index += 1
	if path_index >= path.size():
		if global_position.distance_to(target_position) <= arrival_radius:
			return NavigationResult.ARRIVED
		if accept_nearest_endpoint:
			return NavigationResult.ARRIVED
		path = PackedVector2Array()
		path_index = 0
		_navigation_repath_cooldown = NAVIGATION_REPATH_INTERVAL
		_navigation_failed_repaths += 1
		return _navigation_failure_result()

	var direction: Vector2 = path[path_index] - global_position
	_move_in_direction(direction, delta, game_map)

	if global_position.distance_to(_last_move_pos) > 2.0:
		_stuck_timer = 0.0
		_last_move_pos = global_position
		_navigation_failed_repaths = 0
		_navigation_stall_repaths = 0
	else:
		_stuck_timer += delta
		if _stuck_timer >= NAVIGATION_STUCK_TIMEOUT:
			_stuck_timer = 0.0
			_navigation_stall_repaths += 1
			path = PackedVector2Array()
			path_index = 0
			_navigation_repath_cooldown = 0.0
			if _navigation_stall_repaths >= NAVIGATION_MAX_STALL_REPATHS:
				return NavigationResult.UNREACHABLE
	return NavigationResult.MOVING


func _request_navigation_path(
	game_map: Node2D,
	target_position: Vector2,
	arrival_radius: float,
	dynamic_target: bool
) -> bool:
	if not game_map.has_method("get_navigation_world_path"):
		return false
	var route: PackedVector2Array = game_map.call(
		"get_navigation_world_path",
		global_position,
		target_position,
		arrival_radius
	)
	_navigation_target_snapshot = target_position
	_navigation_repath_cooldown = NAVIGATION_DYNAMIC_REPATH_INTERVAL if dynamic_target else NAVIGATION_REPATH_INTERVAL
	if route.is_empty():
		_navigation_failed_repaths += 1
		return false
	path = route
	path_index = 0
	return true


func _navigation_failure_result() -> int:
	if _navigation_failed_repaths >= NAVIGATION_MAX_FAILED_REPATHS:
		return NavigationResult.UNREACHABLE
	return NavigationResult.MOVING


func _move_in_direction(direction: Vector2, delta: float, game_map: Node2D) -> void:
	if direction.length() < 0.001:
		return
	var desired_dir: Vector2 = direction.normalized()
	_update_friendly_separation()
	var move_dir: Vector2 = desired_dir
	if direction.length() > 10.0 and _separation_vector.length() > 0.0:
		move_dir = (desired_dir + _separation_vector).normalized()
	var separation_drag: float = clampf(_separation_vector.length() * 0.16, 0.0, 0.18)
	var step_distance: float = minf(speed * (1.0 - separation_drag) * delta, direction.length())
	var proposed_position: Vector2 = global_position + move_dir * step_distance
	if game_map != null and game_map.has_method("world_to_tile") and game_map.has_method("is_tile_walkable"):
		var current_tile: Vector2i = game_map.call("world_to_tile", global_position)
		var proposed_tile: Vector2i = game_map.call("world_to_tile", proposed_position)
		var current_walkable: bool = bool(game_map.call("is_tile_walkable", current_tile))
		if current_walkable and not bool(game_map.call("is_tile_walkable", proposed_tile)):
			# Separation must never push a pathed unit into a solid cell. Fall back
			# to the route direction, then wait for a repath if even that is blocked.
			proposed_position = global_position + desired_dir * step_distance
			proposed_tile = game_map.call("world_to_tile", proposed_position)
			if not bool(game_map.call("is_tile_walkable", proposed_tile)):
				return
	global_position = proposed_position


func _get_navigation_map() -> Node2D:
	if _navigation_map != null and is_instance_valid(_navigation_map):
		return _navigation_map
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor is Node2D and ancestor.has_method("get_navigation_world_path"):
			_navigation_map = ancestor as Node2D
			return _navigation_map
		ancestor = ancestor.get_parent()
	return null


func _get_navigation_route(target_position: Vector2, arrival_radius: float) -> PackedVector2Array:
	var game_map := _get_navigation_map()
	if game_map == null or not game_map.has_method("get_navigation_world_path"):
		return PackedVector2Array([target_position])
	return game_map.call("get_navigation_world_path", global_position, target_position, arrival_radius)


func _reset_navigation(clear_path: bool = true) -> void:
	_navigation_active = false
	_navigation_goal = Vector2.ZERO
	_navigation_target_snapshot = Vector2.ZERO
	_navigation_repath_cooldown = 0.0
	_navigation_failed_repaths = 0
	_navigation_stall_repaths = 0
	_stuck_timer = 0.0
	_last_move_pos = global_position
	if clear_path:
		path = PackedVector2Array()
		path_index = 0


func _on_navigation_unreachable(target_position: Vector2) -> void:
	_reset_navigation()
	_clear_patrol()
	attack_move = false
	_forced_attack = false
	_force_move_active = false
	navigation_failed.emit(self, target_position)
	set_state(State.IDLE)


## Subclasses use this to invalidate task-specific callbacks whenever a fresh
## player/AI command supersedes the old intent.
func _before_new_command() -> void:
	pass


func _process_attacking(delta: float) -> void:
	# Handle building attacks
	if attack_building_target != null:
		if not _is_valid_building_target(attack_building_target):
			attack_building_target = null
			_forced_attack = false
			_reset_navigation()
			if not _resume_post_combat_movement():
				set_state(State.IDLE)
			return
		var dist: float = global_position.distance_to(attack_building_target.global_position)
		if dist > attack_range + 24.0:
			var building_result: int = _navigate_toward(
				attack_building_target.global_position,
				attack_range + 24.0,
				delta,
				true,
				false
			)
			if building_result == NavigationResult.UNREACHABLE:
				_temporarily_ignore_auto_target(attack_building_target)
				attack_building_target = null
				_forced_attack = false
				_reset_navigation()
				if not _resume_post_combat_movement():
					set_state(State.IDLE)
		else:
			_reset_navigation()
			if attack_cooldown <= 0.0:
				_perform_building_attack()
		return

	if not _is_valid_target(attack_target):
		attack_target = null
		_forced_attack = false
		_reset_navigation()
		if not _resume_post_combat_movement():
			set_state(State.IDLE)
		return

	var dist: float = global_position.distance_to(attack_target.global_position)
	if dist > attack_range + 8.0:
		# Stand ground only blocks chase for passive auto-targets.
		if stance == Stance.STAND_GROUND and not attack_move and not _forced_attack:
			attack_target = null
			_forced_attack = false
			if not _resume_post_combat_movement():
				set_state(State.IDLE)
			return
		var unit_result: int = _navigate_toward(
			attack_target.global_position,
			attack_range + 8.0,
			delta,
			true,
			false
		)
		if unit_result == NavigationResult.UNREACHABLE:
			_temporarily_ignore_auto_target(attack_target)
			attack_target = null
			_forced_attack = false
			_reset_navigation()
			if not _resume_post_combat_movement():
				set_state(State.IDLE)
	else:
		_reset_navigation()
		# In range, attack
		if attack_cooldown <= 0.0:
			_perform_attack()


func _process_gathering(_delta: float) -> void:
	# Overridden in villager.gd
	pass


func _process_building(_delta: float) -> void:
	# Overridden in villager.gd
	pass


# --- Combat ---

func _try_auto_attack() -> void:
	if _force_move_active:
		return
	if damage <= 0.0:
		return  # Non-combat units (scouts with 0 damage)
	if _auto_attack_timer > 0.0:
		return  # Throttle: only scan every 0.3s to reduce O(n²) group queries
	_auto_attack_timer = 0.3
	# Stand ground: only engage within attack range, not full vision
	var search_radius: float = attack_range + 16.0 if stance == Stance.STAND_GROUND else vision_radius
	# Check for enemy units first (priority over buildings)
	var closest_enemy: UnitBase = null
	var closest_dist: float = search_radius
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or unit == self or not (unit is UnitBase):
			continue
		var candidate_unit := unit as UnitBase
		if candidate_unit.player_owner == player_owner:
			continue
		if not _is_valid_target(candidate_unit) or _is_auto_target_temporarily_ignored(candidate_unit):
			continue
		var dist: float = global_position.distance_to(candidate_unit.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_enemy = candidate_unit
	if closest_enemy != null:
		command_attack(closest_enemy, false, false)
		return

	# Check for enemy buildings nearby
	var closest_building: BuildingBase = null
	var closest_b_dist: float = search_radius * 0.5  # shorter range for building auto-attack
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not (building is BuildingBase):
			continue
		if building.player_owner == player_owner:
			continue
		if not _is_valid_building_target(building as BuildingBase) or _is_auto_target_temporarily_ignored(building as Node2D):
			continue
		var dist: float = global_position.distance_to(building.global_position)
		if dist < closest_b_dist:
			closest_b_dist = dist
			closest_building = building
	if closest_building != null:
		command_attack_building(closest_building, false, false)


func can_auto_retaliate() -> bool:
	## Unit roles can opt out without disabling explicit attack commands.
	return damage > 0.0 and not _force_move_active


func _perform_attack() -> void:
	if damage <= 0.0 or not _is_valid_target(attack_target) or _attack_windup_remaining >= 0.0:
		return
	attack_cooldown = 1.0 / attack_speed
	_begin_attack_windup(attack_target, false)


func _perform_building_attack() -> void:
	if damage <= 0.0 or not _is_valid_building_target(attack_building_target) or _attack_windup_remaining >= 0.0:
		return
	attack_cooldown = 1.0 / attack_speed
	_begin_attack_windup(attack_building_target, true)


func _begin_attack_windup(target: Node2D, building_target: bool) -> void:
	var stats: Dictionary = UnitData.UNITS.get(unit_type, {})
	_attack_windup_remaining = maxf(0.0, float(stats.get("attack_windup", 0.12)))
	_attack_windup_target = target
	_attack_windup_building = building_target
	_attack_animation_duration = _attack_windup_remaining + 0.16
	_attack_animation_remaining = _attack_animation_duration
	_attack_animation_direction = (target.global_position - global_position).normalized()
	if _sprite != null and absf(_attack_animation_direction.x) > 0.01:
		_sprite.flip_h = _attack_animation_direction.x < 0.0


func _advance_attack_windup(delta: float) -> void:
	if _attack_windup_remaining < 0.0:
		return
	_attack_windup_remaining -= delta
	if _attack_windup_remaining > 0.0:
		return
	var target: Node2D = _attack_windup_target
	var building_target: bool = _attack_windup_building
	_cancel_attack_windup()
	if current_state != State.ATTACKING or not is_instance_valid(target):
		return
	if building_target:
		var building := target as BuildingBase
		if building != attack_building_target or not _is_valid_building_target(building):
			return
		if global_position.distance_to(building.global_position) > attack_range + 28.0:
			return
		Combat.deal_damage_to_building(self, building)
		if get_tree().current_scene != null:
			VFX.hit_burst(get_tree(), building.global_position, Color(1.0, 0.7, 0.3))
	else:
		var unit := target as UnitBase
		if unit != attack_target or not _is_valid_target(unit):
			return
		if global_position.distance_to(unit.global_position) > attack_range + 12.0:
			return
		if is_ranged:
			Combat.launch_ranged_attack(self, unit)
		else:
			Combat.queue_melee_attack(self, unit)


func _cancel_attack_windup() -> void:
	_attack_windup_remaining = -1.0
	_attack_windup_target = null
	_attack_windup_building = false


func _update_sprite_motion(delta: float) -> void:
	if _sprite == null:
		return
	_animation_clock += delta
	_attack_animation_remaining = maxf(0.0, _attack_animation_remaining - delta)
	var displacement: Vector2 = global_position - _last_visual_position
	_last_visual_position = global_position
	var sprite_offset := Vector2.ZERO
	if displacement.length_squared() > 0.001:
		if absf(displacement.x) > 0.01:
			_sprite.flip_h = displacement.x < 0.0
		var gait_rate: float = 17.0 if unit_type in [UnitData.UnitType.CAVALRY, UnitData.UnitType.SCOUT] else 12.0
		sprite_offset.y = -absf(sin(_animation_clock * gait_rate)) * 2.5
		_sprite.rotation = sin(_animation_clock * gait_rate) * 0.025
	else:
		_sprite.rotation = 0.0
	if _attack_animation_remaining > 0.0:
		var phase: float = 1.0 - _attack_animation_remaining / _attack_animation_duration
		var thrust: float = sin(phase * PI)
		sprite_offset += _attack_animation_direction * thrust * (2.0 if is_ranged else 5.0)
		_sprite.rotation += thrust * (0.035 if is_ranged else 0.06) * (-1.0 if _sprite.flip_h else 1.0)
	_sprite.position = sprite_offset


func _is_valid_target(target: UnitBase) -> bool:
	if target == null:
		return false
	if not is_instance_valid(target):
		return false
	if not _can_track_entity(target):
		return false
	return target.current_state != State.DEAD


func _is_valid_building_target(target: BuildingBase) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not _can_track_entity(target):
		return false
	return target.state != BuildingBase.State.DESTROYED


func _can_track_entity(entity: Node2D) -> bool:
	var game_map := _get_navigation_map()
	if game_map != null and game_map.has_method("is_entity_visible_to_player"):
		return bool(game_map.call("is_entity_visible_to_player", entity, player_owner))
	return true


func _temporarily_ignore_auto_target(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_ignored_auto_targets_until[target.get_instance_id()] = Time.get_ticks_msec() + AUTO_TARGET_IGNORE_MSEC


func _is_auto_target_temporarily_ignored(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	var instance_id: int = target.get_instance_id()
	if not _ignored_auto_targets_until.has(instance_id):
		return false
	var expires_at: int = int(_ignored_auto_targets_until[instance_id])
	if Time.get_ticks_msec() >= expires_at:
		_ignored_auto_targets_until.erase(instance_id)
		return false
	return true


# --- Commands (called by selection/AI systems) ---

func command_move(target_pos: Vector2) -> void:
	if current_state == State.DEAD:
		return
	_before_new_command()
	_cancel_attack_windup()
	_attack_animation_remaining = 0.0
	_clear_patrol()
	move_target = target_pos
	attack_target = null
	attack_building_target = null
	attack_move = false
	_forced_attack = false
	_force_move_active = true
	_reset_navigation()
	set_state(State.MOVING)


func command_move_path(nav_path: PackedVector2Array) -> void:
	if current_state == State.DEAD:
		return
	if nav_path.is_empty():
		return
	_before_new_command()
	_cancel_attack_windup()
	_attack_animation_remaining = 0.0
	_clear_patrol()
	_reset_navigation()
	path = nav_path
	path_index = 0
	move_target = nav_path[nav_path.size() - 1]
	attack_target = null
	attack_building_target = null
	attack_move = false
	_forced_attack = false
	_force_move_active = true
	set_state(State.MOVING)


func command_attack(target: UnitBase, force_chase: bool = true, clear_patrol: bool = true) -> void:
	if current_state == State.DEAD or damage <= 0.0:
		return
	if not _is_valid_target(target):
		return
	_before_new_command()
	_cancel_attack_windup()
	_attack_animation_remaining = 0.0
	if clear_patrol:
		_clear_patrol()
	_reset_navigation()
	attack_target = target
	attack_building_target = null
	_forced_attack = force_chase
	_force_move_active = false
	set_state(State.ATTACKING)


func command_attack_building(target: BuildingBase, force_chase: bool = true, clear_patrol: bool = true) -> void:
	if current_state == State.DEAD or damage <= 0.0:
		return
	if not _is_valid_building_target(target):
		return
	_before_new_command()
	_cancel_attack_windup()
	_attack_animation_remaining = 0.0
	if clear_patrol:
		_clear_patrol()
	_reset_navigation()
	attack_building_target = target
	attack_target = null
	_forced_attack = force_chase
	_force_move_active = false
	set_state(State.ATTACKING)


func command_attack_move(target_pos: Vector2) -> void:
	if current_state == State.DEAD:
		return
	_before_new_command()
	_cancel_attack_windup()
	_attack_animation_remaining = 0.0
	_clear_patrol()
	attack_move = true
	_forced_attack = false
	_force_move_active = false
	move_target = target_pos
	attack_target = null
	attack_building_target = null
	_reset_navigation()
	set_state(State.MOVING)


func command_attack_move_path(nav_path: PackedVector2Array) -> void:
	if current_state == State.DEAD:
		return
	if nav_path.is_empty():
		return
	_before_new_command()
	_cancel_attack_windup()
	_attack_animation_remaining = 0.0
	_clear_patrol()
	_reset_navigation()
	attack_move = true
	_forced_attack = false
	_force_move_active = false
	path = nav_path
	path_index = 0
	move_target = nav_path[nav_path.size() - 1]
	attack_target = null
	attack_building_target = null
	set_state(State.MOVING)


func command_patrol(target_pos: Vector2) -> void:
	if current_state == State.DEAD:
		return
	var distance: float = global_position.distance_to(target_pos)
	if distance < 8.0:
		return
	_before_new_command()
	_cancel_attack_windup()
	_attack_animation_remaining = 0.0
	_patrol_active = true
	_patrol_point_a = global_position
	_patrol_point_b = target_pos
	_patrol_to_b = true
	attack_move = true
	_forced_attack = false
	_force_move_active = false
	move_target = target_pos
	attack_target = null
	attack_building_target = null
	_reset_navigation()
	set_state(State.MOVING)


func command_stop() -> void:
	if current_state == State.DEAD:
		return
	_before_new_command()
	_cancel_attack_windup()
	_attack_animation_remaining = 0.0
	_clear_patrol()
	attack_target = null
	attack_building_target = null
	attack_move = false
	_forced_attack = false
	_force_move_active = false
	# Allow the issued Stop to settle visibly before idle stance scanning.
	_auto_attack_timer = maxf(_auto_attack_timer, 0.35)
	_reset_navigation()
	set_state(State.IDLE)


func _clear_patrol() -> void:
	_patrol_active = false
	_patrol_point_a = Vector2.ZERO
	_patrol_point_b = Vector2.ZERO
	_patrol_to_b = true


func _resume_post_combat_movement() -> bool:
	if _patrol_active:
		var patrol_target: Vector2 = _patrol_point_b if _patrol_to_b else _patrol_point_a
		if global_position.distance_to(patrol_target) > 5.0:
			move_target = patrol_target
			_reset_navigation()
			set_state(State.MOVING)
			return true
	if attack_move and not path.is_empty() and path_index < path.size():
		set_state(State.MOVING)
		return true
	if attack_move and global_position.distance_to(move_target) > 5.0:
		_reset_navigation()
		set_state(State.MOVING)
		return true
	return false


func _update_friendly_separation() -> void:
	if _separation_timer > 0.0:
		return
	_separation_timer = FRIENDLY_SEPARATION_REFRESH
	var repel := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("units"):
		if node == self or not (node is UnitBase):
			continue
		var other: UnitBase = node as UnitBase
		if not is_instance_valid(other) or other.current_state == State.DEAD:
			continue
		if other.player_owner != player_owner:
			continue
		var offset: Vector2 = global_position - other.global_position
		var dist: float = offset.length()
		var desired_spacing: float = UNIT_SIZES.get(unit_type, 12.0) + UNIT_SIZES.get(other.unit_type, 12.0) + 8.0
		var separation_radius: float = maxf(FRIENDLY_SEPARATION_RADIUS, desired_spacing)
		if dist <= 0.001 or dist > separation_radius:
			continue
		var strength: float = (separation_radius - dist) / separation_radius
		var moving_bias: float = 1.0
		if other.current_state == State.MOVING:
			moving_bias = 1.2
		repel += offset.normalized() * strength * moving_bias
	if repel.length() > 0.0:
		# Preserve the overlap-derived magnitude: normalizing here made even an
		# epsilon overlap a full-strength shove. Keep steering strictly below the
		# unit direction's magnitude so separation can bend, but never reverse,
		# forward progress along a valid route.
		_separation_vector = (repel * FRIENDLY_SEPARATION_WEIGHT).limit_length(
			FRIENDLY_SEPARATION_MAX_STEER
		)
	else:
		_separation_vector = Vector2.ZERO


# --- Health ---

func take_damage(amount: float) -> void:
	## `amount` is final HP loss. Armor and upgrades are resolved once by Combat.
	if current_state == State.DEAD:
		return
	var actual_damage: float = maxf(1.0, amount)
	hp = maxf(0.0, hp - actual_damage)
	health_changed.emit(self, hp, max_hp)
	_flash_damage()
	# Floating damage number
	if get_tree() and get_tree().current_scene:
		VFX.damage_float(get_tree(), global_position, actual_damage)
	AudioManager.play_sfx("attack_hit")
	queue_redraw()
	if hp <= 0.0:
		die()


func _flash_damage() -> void:
	if _sprite == null:
		return
	var original: Color = _sprite.modulate
	_sprite.modulate = Color(1.0, 1.0, 1.0)  # White flash — visible on both friendly and enemy units
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", original, 0.15)


func heal(amount: float) -> void:
	if current_state == State.DEAD:
		return
	hp = minf(max_hp, hp + amount)
	health_changed.emit(self, hp, max_hp)
	queue_redraw()


func die() -> void:
	_cancel_attack_windup()
	set_state(State.DEAD)
	unit_died.emit(self)
	# Death puff particles
	if get_tree() and get_tree().current_scene:
		VFX.death_puff(get_tree(), global_position)
	AudioManager.play_sfx("unit_death")
	# Brief delay before removal for death animation opportunity
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


# --- Selection ---

func select() -> void:
	is_selected = true
	unit_selected.emit(self)
	AudioManager.play_sfx("select_unit")
	queue_redraw()


func deselect() -> void:
	is_selected = false
	unit_deselected.emit(self)
	queue_redraw()


# --- Team Color ---

func set_team_color(color: Color) -> void:
	team_color = color
	queue_redraw()


func get_player_id() -> int:
	return player_owner


func get_unit_type() -> String:
	return UnitData.get_unit_name(unit_type)
