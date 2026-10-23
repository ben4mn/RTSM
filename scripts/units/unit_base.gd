class_name UnitBase
extends Area2D
## Base class for all units in AOEM. Handles movement, selection,
## health, state machine, auto-attack behavior, and sprite-based rendering.

signal unit_died(unit: UnitBase)
signal unit_selected(unit: UnitBase)
signal unit_deselected(unit: UnitBase)
signal health_changed(unit: UnitBase, new_hp: float, max_hp: float)
signal damage_received(unit: UnitBase, hp_loss: float)
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
var _auto_engagement_origin: Vector2 = Vector2.ZERO
var _auto_chase_elapsed: float = 0.0
var _patrol_active: bool = false
var _patrol_point_a: Vector2 = Vector2.ZERO
var _patrol_point_b: Vector2 = Vector2.ZERO
var _patrol_to_b: bool = true
var _separation_timer: float = 0.0
var _separation_vector: Vector2 = Vector2.ZERO
var _navigation_neighbors: Array[UnitBase] = []
var _combat_spacing_opponents: Array[UnitBase] = []
var _navigation_active: bool = false
var _navigation_goal: Vector2 = Vector2.ZERO
var _navigation_target_snapshot: Vector2 = Vector2.ZERO
var _navigation_repath_cooldown: float = 0.0
var _navigation_failed_repaths: int = 0
var _navigation_stall_repaths: int = 0
var _navigation_map: Node2D = null
var _ignored_auto_targets_until: Dictionary = {}
var _simulation_elapsed_seconds: float = 0.0
var _attack_windup_remaining: float = -1.0
var _attack_windup_target: Node2D = null
var _attack_windup_building: bool = false
var _attack_animation_remaining: float = 0.0
var _attack_animation_duration: float = 0.3
var _attack_animation_direction: Vector2 = Vector2.RIGHT
var _animation_clock: float = 0.0
var _last_visual_position: Vector2 = Vector2.ZERO
var _health_feedback_remaining: float = 0.0

# --- Node references ---
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# --- Flat field-piece artwork; silhouettes carry the role at phone scale. ---
const UNIT_SPRITES: Dictionary = {
	UnitData.UnitType.VILLAGER: "res://assets/units/worker.svg",
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

# World scales share a grounded size system; HUD portraits retain their size.
const UNIT_SPRITE_SCALES: Dictionary = UnitData.WORLD_SPRITE_SCALES

var _sprite: Sprite2D = null
var _sprite_team_modulate: Color = Color.WHITE
var _damage_flash_tween: Tween = null
var _sprite_opaque_rect: Rect2 = Rect2()
var _health_bar_y: float = -43.0
static var _sprite_opaque_rect_cache: Dictionary = {}

# Artwork shares a y104 foot baseline in a 128px canvas. Movement/attack
# excursion is included in framing, so a moving miniature stays in the field.
const UNIT_FOOT_OFFSET: Vector2 = Vector2(0.0, -40.0)
const UNIT_VISUAL_GAIT_MARGIN: float = 4.0
const UNIT_VISUAL_ATTACK_MARGIN: float = 10.0

const FRIENDLY_SEPARATION_RADIUS: float = 34.0
const FRIENDLY_SEPARATION_WEIGHT: float = 1.15
const FRIENDLY_SEPARATION_MAX_STEER: float = 0.75
const FRIENDLY_SEPARATION_REFRESH: float = 0.06
const COMBAT_SPACING_SPEED_FRACTION: float = 0.35
const NAVIGATION_POINT_TOLERANCE: float = 4.0
const NAVIGATION_CROWDED_WAYPOINT_RADIUS: float = 24.0
const NAVIGATION_OCCUPIED_WAYPOINT_RADIUS: float = 12.0
const NAVIGATION_SEGMENT_SAMPLE_DISTANCE: float = 4.0
const NAVIGATION_REPATH_INTERVAL: float = 0.45
const NAVIGATION_DYNAMIC_REPATH_INTERVAL: float = 0.65
const NAVIGATION_DYNAMIC_REPATH_DISTANCE: float = 20.0
const NAVIGATION_STUCK_TIMEOUT: float = 1.25
const NAVIGATION_MAX_FAILED_REPATHS: int = 4
const NAVIGATION_MAX_STALL_REPATHS: int = 3
const AUTO_TARGET_IGNORE_SECONDS: float = 3.0
const AUTO_CHASE_MAX_SECONDS: float = 6.0
const AUTO_CHASE_MIN_DISTANCE: float = 128.0


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
	if player_owner != 0:
		var alternate: String = tex_path.replace(".svg", "_enemy.svg")
		if ResourceLoader.exists(alternate):
			tex_path = alternate
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_sprite.texture = load(tex_path)
	_sprite.scale = UNIT_SPRITE_SCALES.get(unit_type, Vector2(0.20, 0.20))
	_sprite.offset = UNIT_FOOT_OFFSET
	add_child(_sprite)
	if _sprite.texture != null:
		if not _sprite_opaque_rect_cache.has(tex_path):
			var image: Image = _sprite.texture.get_image()
			_sprite_opaque_rect_cache[tex_path] = Rect2(image.get_used_rect()) if image != null else Rect2(Vector2.ZERO, _sprite.texture.get_size())
		_sprite_opaque_rect = _sprite_opaque_rect_cache[tex_path]
		_health_bar_y = floorf(_sprite.scale.y * (_sprite_opaque_rect.position.y - _sprite.texture.get_height() * 0.5 + _sprite.offset.y) - 6.0)
	# Team cloth has its own palette; neutral metal, skin and mounts retain
	# their material colors instead of receiving a full-sprite red wash.
	_sprite.modulate = Color.WHITE
	_sprite_team_modulate = _sprite.modulate
	_last_visual_position = global_position


func get_visual_bounds() -> Rect2:
	## World bounds of visible artwork and markers, including the maximum
	## small pose excursion. Opaque texture bounds are cached at sprite setup.
	var size: float = UNIT_SIZES.get(unit_type, 10.0)
	var local_bounds := Rect2(-size - 2.5, 3.0 - size * 0.48 - 1.5, (size + 2.5) * 2.0, size * 0.96 + 3.0)
	if _sprite != null and _sprite.texture != null:
		var sprite_rect := Rect2(_sprite_opaque_rect.position - _sprite.texture.get_size() * 0.5 + _sprite.offset, _sprite_opaque_rect.size)
		if _sprite.flip_h:
			sprite_rect.position.x = -sprite_rect.end.x
		# Walking/work retain a compact four-unit pose envelope. Attacking needs
		# the five-unit lunge plus up to four units of head movement from its
		# foot-pivot rotation; current-pose-only padding could miss that stroke.
		var resting_sprite_rect := Rect2(sprite_rect.position * _sprite.scale, sprite_rect.size * _sprite.scale)
		var pose_margin: float = UNIT_VISUAL_ATTACK_MARGIN if current_state == State.ATTACKING or _attack_animation_remaining > 0.0 else UNIT_VISUAL_GAIT_MARGIN
		local_bounds = local_bounds.merge(resting_sprite_rect.grow(pose_margin))
		local_bounds = local_bounds.merge((_sprite.transform * sprite_rect).grow(0.1))
	if is_selected or hp < max_hp:
		local_bounds = local_bounds.merge(Rect2(-size * 1.25, _health_bar_y, size * 2.5, 3.0))
	if stance == Stance.STAND_GROUND:
		local_bounds = local_bounds.merge(Rect2(size, -6.5, 8.0, 9.0))
	return global_transform * local_bounds


func _process(delta: float) -> void:
	if current_state == State.DEAD:
		return
	# Exclusion retries use the same elapsed simulation as movement/combat.
	# The explicit guard also keeps manually stepped units frozen while paused.
	if not is_inside_tree() or not get_tree().paused:
		_simulation_elapsed_seconds += maxf(0.0, delta)

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

	# One quiet contact shadow. Team cloth supplies the normal ownership cue;
	# only selected figures receive a surrounding ring.
	var ground_ring := PackedVector2Array()
	for i in range(33):
		var angle: float = float(i) / 32.0 * TAU
		ground_ring.append(Vector2(cos(angle) * (size + 1.0), sin(angle) * size * 0.48 + 3.0))
	draw_colored_polygon(ground_ring, Color(0.09, 0.13, 0.13, 0.12))
	var contact_shadow := PackedVector2Array()
	for point: Vector2 in ground_ring:
		contact_shadow.append(Vector2(point.x * 0.72, (point.y - 3.0) * 0.58 + 2.0))
	draw_colored_polygon(contact_shadow, Color(0.09, 0.13, 0.13, 0.12))

	if GameManager.clearer_player_markers:
		var camera: Camera2D = get_viewport().get_camera_2d()
		var inverse_zoom: float = 1.0 / maxf(0.5, camera.zoom.x) if camera != null else 1.0
		var marker_size: float = 3.0 * inverse_zoom
		var center := Vector2(0, 6.5)
		if player_owner == 0:
			draw_line(center - Vector2(marker_size, 0), center + Vector2(marker_size, 0), Color("293235"), 3.0 * inverse_zoom, true)
			draw_line(center - Vector2(marker_size, 0), center + Vector2(marker_size, 0), Color("88b7ad"), 1.5 * inverse_zoom, true)
		else:
			var chevron := PackedVector2Array([center + Vector2(-marker_size, -1.5 * inverse_zoom), center + Vector2(0, 1.5 * inverse_zoom), center + Vector2(marker_size, -1.5 * inverse_zoom)])
			draw_polyline(chevron, Color("293235"), 3.0 * inverse_zoom, true)
			draw_polyline(chevron, Color("d69477"), 1.5 * inverse_zoom, true)

	# A stable ivory selection line stays readable without permanent bright
	# team rings or pulsing graphics beneath every miniature.
	if is_selected:
		draw_polyline(ground_ring, Color("e8e5db"), 1.5, true)

	var hp_ratio: float = hp / max_hp if max_hp > 0 else 0.0

	# Recent damage, selection and critical health remain visible. A healthy
	# idle army needs neither floating meters nor permanent status badges.
	var bar_width: float = size * 2.3
	var bar_height: float = 2.0
	var bar_y: float = _health_bar_y

	if is_selected or _health_feedback_remaining > 0.0 or hp_ratio <= 0.35:
		draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width, bar_height), Color("293235"))
		var hp_color := Color("e8e5db") if hp_ratio > 0.35 else Color("d69477")
		draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width * hp_ratio, bar_height), hp_color)

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
		draw_colored_polygon(shield_pts, Color("293235"))
		draw_polyline(shield_pts, Color("b7c4ba"), 1.0)


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
	attack_move = false
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

	while path_index < path.size() and (global_position.distance_to(path[path_index]) <= NAVIGATION_POINT_TOLERANCE or _can_pass_occupied_waypoint(game_map)):
		path_index += 1
	if path_index >= path.size():
		if global_position.distance_to(target_position) <= arrival_radius:
			return NavigationResult.ARRIVED
		if accept_nearest_endpoint:
			return NavigationResult.ARRIVED
		path = PackedVector2Array()
		path_index = 0
		# Reaching an old pursuit waypoint is progress, not an unreachable
		# target. A fresh stationary-failure delay here lets a slower runner
		# repeatedly escape before its pursuer can enter weapon range.
		if dynamic_target and _navigation_target_snapshot.distance_to(target_position) > NAVIGATION_POINT_TOLERANCE:
			_navigation_repath_cooldown = 0.0
			return NavigationResult.MOVING
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


func _can_pass_occupied_waypoint(game_map: Node2D) -> bool:
	# Intermediate tile centers describe a route, not places every traveller
	# must occupy. Keep final service/Move arrival semantics, but let a unit
	# pass an occupied center when the following segment is still walkable.
	if current_state not in [State.MOVING, State.GATHERING, State.BUILDING] or path_index >= path.size() - 1:
		return false
	var waypoint: Vector2 = path[path_index]
	if global_position.distance_to(waypoint) > NAVIGATION_CROWDED_WAYPOINT_RADIUS:
		return false
	var occupied: bool = false
	var occupied_radius_squared: float = NAVIGATION_OCCUPIED_WAYPOINT_RADIUS * NAVIGATION_OCCUPIED_WAYPOINT_RADIUS
	for other: UnitBase in _navigation_neighbors:
		if is_instance_valid(other) and other.player_owner == player_owner and other.current_state != State.DEAD and waypoint.distance_squared_to(other.global_position) < occupied_radius_squared:
			occupied = true
			break
	return occupied and _is_navigation_segment_clear(global_position, path[path_index + 1], game_map)


func _is_navigation_segment_clear(from_position: Vector2, to_position: Vector2, game_map: Node2D) -> bool:
	if game_map == null or not game_map.has_method("world_to_tile") or not game_map.has_method("is_tile_walkable"):
		return true
	var previous_tile: Vector2i = game_map.call("world_to_tile", from_position)
	# Existing displacement/recovery can begin inside a newly blocked tile.
	# Preserve its escape behavior; ordinary movement starts on walkable ground.
	if not bool(game_map.call("is_tile_walkable", previous_tile)):
		return true
	var target_tile: Vector2i = game_map.call("world_to_tile", to_position)
	if not bool(game_map.call("is_tile_walkable", target_tile)):
		return false
	var tile_delta: Vector2i = (target_tile - previous_tile).abs()
	if tile_delta.x <= 1 and tile_delta.y <= 1:
		# A cell, two adjacent cells, or a fully open 2x2 block is convex.
		# These cover ordinary frame steps without a per-pixel map walk.
		if tile_delta.x == 0 or tile_delta.y == 0:
			return true
		return bool(game_map.call("is_tile_walkable", Vector2i(target_tile.x, previous_tile.y))) and bool(game_map.call("is_tile_walkable", Vector2i(previous_tile.x, target_tile.y)))
	var samples: int = maxi(1, int(ceil(from_position.distance_to(to_position) / NAVIGATION_SEGMENT_SAMPLE_DISTANCE)))
	for sample: int in range(1, samples + 1):
		var tile: Vector2i = game_map.call("world_to_tile", from_position.lerp(to_position, float(sample) / samples))
		if tile == previous_tile:
			continue
		if not bool(game_map.call("is_tile_walkable", tile)):
			return false
		if tile.x != previous_tile.x and tile.y != previous_tile.y:
			if not bool(game_map.call("is_tile_walkable", Vector2i(tile.x, previous_tile.y))) or not bool(game_map.call("is_tile_walkable", Vector2i(previous_tile.x, tile.y))):
				return false
		previous_tile = tile
	return true


func _move_in_direction(direction: Vector2, delta: float, game_map: Node2D) -> void:
	if direction.length() < 0.001:
		return
	var desired_dir: Vector2 = direction.normalized()
	_update_friendly_separation(desired_dir)
	var move_dir: Vector2 = desired_dir
	var intermediate_waypoint: bool = current_state in [State.MOVING, State.GATHERING, State.BUILDING] and path_index < path.size() - 1
	if (intermediate_waypoint or direction.length() > 10.0) and _separation_vector.length() > 0.0:
		move_dir = (desired_dir + _separation_vector).normalized()
	var separation_drag: float = clampf(_separation_vector.length() * 0.16, 0.0, 0.18)
	var step_distance: float = minf(speed * (1.0 - separation_drag) * delta, direction.length())
	var proposed_position: Vector2 = global_position + move_dir * step_distance
	# Passing must keep the next route point reachable as well. Otherwise a
	# later sideways step can tuck behind a solid corner after a safe shortcut.
	var keeps_route_visible: bool = not intermediate_waypoint or move_dir.is_equal_approx(desired_dir) or _is_navigation_segment_clear(proposed_position, global_position + direction, game_map)
	if not keeps_route_visible or not _is_navigation_segment_clear(global_position, proposed_position, game_map):
		# Check the entire actual steered step, including solid corners. A clear
		# lookahead segment alone cannot make a later sideways step safe.
		proposed_position = global_position + desired_dir * step_distance
		if not _is_navigation_segment_clear(global_position, proposed_position, game_map):
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
	_consider_nearby_threat()
	# Handle building attacks
	if attack_building_target != null:
		if not _is_valid_building_target(attack_building_target):
			attack_building_target = null
			_forced_attack = false
			_reset_navigation()
			if not _resume_post_combat_movement():
				set_state(State.IDLE)
			return
		var dist: float = _get_building_attack_distance(attack_building_target)
		if dist > attack_range + 24.0:
			if _should_abandon_auto_chase(attack_building_target, delta):
				_abandon_auto_chase()
				return
			var building_result: int = _navigate_toward_building_target(attack_building_target, delta)
			if building_result == NavigationResult.UNREACHABLE:
				_temporarily_ignore_auto_target(attack_building_target)
				attack_building_target = null
				_forced_attack = false
				_reset_navigation()
				if not _resume_post_combat_movement():
					set_state(State.IDLE)
		else:
			_auto_chase_elapsed = 0.0
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
		if _should_abandon_auto_chase(attack_target, delta):
			_abandon_auto_chase()
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
		_auto_chase_elapsed = 0.0
		# Keep the accepted pursuit route while briefly inside weapon range.
		# A moving opponent can leave it again next frame; discarding the route
		# here would ask A* for the same short approach on every other frame.
		_relax_combat_spacing(delta, attack_target.global_position)
		# In range, attack
		if attack_cooldown <= 0.0:
			_perform_attack()


func _relax_combat_spacing(delta: float, target_position: Vector2) -> void:
	# Pursuers often share a final A* waypoint. Once they enter attack range,
	# movement steering stops; without this small in-range correction they can
	# remain drawn on top of one another for the whole fight. Keep the current
	# target, attack cadence and reachable attack circle while making room.
	if stance == Stance.STAND_GROUND and not attack_move and not _forced_attack:
		return
	_update_friendly_separation()
	if _separation_vector.is_zero_approx():
		return
	var proposed: Vector2 = global_position + _separation_vector * speed * COMBAT_SPACING_SPEED_FRACTION * delta
	var from_target: Vector2 = proposed - target_position
	var allowed_radius: float = attack_range + 8.0
	# Resolve friendly pressure around the opponent, not through its body.
	# Preserve an already closer position instead of teleporting outwards.
	var inner_radius: float = minf(attack_range, global_position.distance_to(target_position))
	if from_target.length() < inner_radius:
		var radial: Vector2 = from_target.normalized() if not from_target.is_zero_approx() else (global_position - target_position).normalized()
		proposed = target_position + radial * inner_radius
		from_target = proposed - target_position
	if from_target.length() > allowed_radius:
		proposed = target_position + from_target.normalized() * allowed_radius
	for opponent: UnitBase in _combat_spacing_opponents:
		if not is_instance_valid(opponent) or opponent.current_state == State.DEAD:
			continue
		var body_clearance: float = (float(UNIT_SIZES.get(unit_type, 12.0)) + float(UNIT_SIZES.get(opponent.unit_type, 12.0))) * 0.6
		var minimum_distance: float = minf(body_clearance, global_position.distance_to(opponent.global_position))
		if proposed.distance_squared_to(opponent.global_position) < minimum_distance * minimum_distance:
			return
	var game_map: Node2D = _get_navigation_map()
	if game_map != null and game_map.has_method("is_tile_walkable") and game_map.has_method("world_to_tile"):
		if not bool(game_map.call("is_tile_walkable", game_map.call("world_to_tile", proposed))):
			return
	global_position = proposed


func _get_building_attack_distance(building: BuildingBase) -> float:
	var game_map := _get_navigation_map()
	if game_map != null and game_map.has_method("get_building_work_distance"):
		return float(game_map.call("get_building_work_distance", global_position, building.global_position, building.footprint))
	return global_position.distance_to(building.global_position)


func _navigate_toward_building_target(building: BuildingBase, delta: float) -> int:
	var game_map := _get_navigation_map()
	if game_map == null or not game_map.has_method("get_building_work_world_path"):
		return _navigate_toward(building.global_position, attack_range + 24.0, delta, true, false)
	# The building anchor is a corner of the solid footprint. As with workers,
	# military approach a reachable perimeter, including the opposite edge.
	if not path.is_empty() and path_index < path.size():
		var waypoint: Vector2i = game_map.call("world_to_tile", path[path_index])
		if not bool(game_map.call("is_tile_walkable", waypoint)):
			_reset_navigation()
	if not _navigation_active:
		if _navigation_repath_cooldown > 0.0:
			return NavigationResult.MOVING
		var route: PackedVector2Array = game_map.call("get_building_work_world_path", global_position, building.global_position, building.footprint, attack_range + 24.0)
		_navigation_repath_cooldown = NAVIGATION_REPATH_INTERVAL
		if route.is_empty():
			_navigation_failed_repaths += 1
			return _navigation_failure_result()
		path = route
		path_index = 0
		_navigation_goal = route[route.size() - 1]
	return _navigate_toward(_navigation_goal, NAVIGATION_POINT_TOLERANCE, delta, false, false)


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
	# A spotter may reveal a target beyond this unit's own sight. Acquisition
	# must include usable weapon reach; the canonical visibility check still
	# rejects hidden targets. Stand ground retains its bounded engagement.
	var search_radius: float = attack_range + 16.0 if stance == Stance.STAND_GROUND else maxf(vision_radius, attack_range + 8.0)
	search_radius = _get_auto_unit_acquisition_radius(search_radius)
	var building_radius: float = maxf(search_radius * 0.5, attack_range + 24.0)
	var buildings_first: bool = bool(UnitData.UNITS.get(unit_type, {}).get("auto_target_buildings_first", false))
	var target: Node2D = UnitAutoTargeting.find_target(self, search_radius, building_radius, buildings_first)
	if target is UnitBase:
		command_attack(target as UnitBase, false, false)
	elif target is BuildingBase:
		command_attack_building(target as BuildingBase, false, false)


func _get_auto_unit_acquisition_radius(default_radius: float) -> float:
	# Both idle acquisition and threat switches must fit a stationary guard's
	# engagement reach. Otherwise it immediately abandons/ignores that target,
	# even if the enemy then moves into reach. Advancing orders keep their scan.
	if stance == Stance.STAND_GROUND and not attack_move:
		return attack_range + 8.0
	return default_radius


func can_auto_retaliate() -> bool:
	## Unit roles can opt out without disabling explicit attack commands.
	return damage > 0.0 and not _force_move_active


func respond_to_attacker(attacker: UnitBase) -> void:
	# Damage is an autonomous stimulus. It must preserve attack-move/patrol
	# destinations and cannot replace an explicit unit or building target.
	if not can_auto_retaliate() or _forced_attack or not _is_valid_target(attacker):
		return
	if attacker.player_owner == player_owner or _is_valid_target(attack_target):
		return
	if stance == Stance.STAND_GROUND and not attack_move and global_position.distance_to(attacker.global_position) > attack_range + 8.0:
		return
	command_attack(attacker, false, false)


func _consider_nearby_threat() -> void:
	# Stay committed to a target in weapon range. A normal fighter chasing a
	# distant target or hitting a building can help an immediate nearby fight;
	# siege retains its deliberate building role and explicit orders always win.
	if _forced_attack or _auto_attack_timer > 0.0 or _attack_windup_remaining >= 0.0:
		return
	if _is_valid_target(attack_target) and global_position.distance_to(attack_target.global_position) <= attack_range + 8.0:
		return
	if attack_building_target != null and bool(UnitData.UNITS.get(unit_type, {}).get("auto_target_buildings_first", false)):
		return
	_auto_attack_timer = 0.3
	var threat_radius: float = _get_auto_unit_acquisition_radius(maxf(vision_radius, attack_range + 8.0))
	var threat: UnitBase = UnitAutoTargeting.find_nearby_threat(self, threat_radius)
	if threat != null and threat != attack_target:
		command_attack(threat, false, false)


func _should_abandon_auto_chase(target: Node2D, delta: float) -> bool:
	if _forced_attack:
		return false
	if stance == Stance.STAND_GROUND and not attack_move:
		return true
	_auto_chase_elapsed += delta
	var leash: float = maxf(AUTO_CHASE_MIN_DISTANCE, maxf(vision_radius * 2.0, attack_range + 64.0))
	return _auto_chase_elapsed >= AUTO_CHASE_MAX_SECONDS or (not target is BuildingBase and _auto_engagement_origin.distance_to(target.global_position) > leash)


func _abandon_auto_chase() -> void:
	_temporarily_ignore_auto_target(attack_target if is_instance_valid(attack_target) else attack_building_target)
	attack_target = null
	attack_building_target = null
	_cancel_attack_windup()
	_reset_navigation()
	if _resume_post_combat_movement():
		return
	# An idle defender returns to the place it was guarding. A fleeing enemy
	# cannot pull it farther away again on each acquisition cooldown.
	if global_position.distance_to(_auto_engagement_origin) > NAVIGATION_POINT_TOLERANCE:
		move_target = _auto_engagement_origin
		_force_move_active = true
		set_state(State.MOVING)
	else:
		set_state(State.IDLE)


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
		if _get_building_attack_distance(building) > attack_range + 28.0:
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
	if _health_feedback_remaining > 0.0:
		_health_feedback_remaining = maxf(0.0, _health_feedback_remaining - delta)
		if _health_feedback_remaining <= 0.0:
			queue_redraw()
	_animation_clock += delta
	_attack_animation_remaining = maxf(0.0, _attack_animation_remaining - delta)
	var displacement: Vector2 = global_position - _last_visual_position
	_last_visual_position = global_position
	var sprite_offset := Vector2.ZERO
	if displacement.length_squared() > 0.001:
		if absf(displacement.x) > 0.01:
			_sprite.flip_h = displacement.x < 0.0
		var mounted: bool = unit_type in [UnitData.UnitType.CAVALRY, UnitData.UnitType.SCOUT]
		var gait_rate: float = 17.0 if mounted else 12.0
		var stride: float = sin(_animation_clock * gait_rate)
		sprite_offset.y = -absf(stride) * (1.6 if mounted else 2.0)
		_sprite.rotation = stride * (0.014 if mounted else 0.025)
	elif current_state in [State.GATHERING, State.BUILDING]:
		var work_stroke: float = sin(_animation_clock * 7.5)
		_sprite.rotation = work_stroke * 0.04
		sprite_offset.y = -absf(work_stroke) * 0.6
	else:
		_sprite.rotation = 0.0
	if _attack_animation_remaining > 0.0:
		var phase: float = 1.0 - _attack_animation_remaining / _attack_animation_duration
		# Brief anticipation then a clear stroke/recoil, around the ground foot
		# anchor. This reads from the existing windup without changing hit timing.
		var thrust: float = -sin(phase / 0.3 * PI) * 0.25 if phase < 0.3 else sin((phase - 0.3) / 0.7 * PI)
		sprite_offset += _attack_animation_direction * thrust * (-2.0 if is_ranged else 5.0)
		_sprite.rotation += thrust * (0.035 if is_ranged else 0.06) * (-1.0 if _sprite.flip_h else 1.0)
	_sprite.position = sprite_offset


# Freed Object handles fail typed Object parameters before the body can run.
# Keep this lifetime boundary as Variant, then narrow only after validation.
func _is_valid_target(target: Variant) -> bool:
	if not is_instance_valid(target) or not target is UnitBase:
		return false
	var unit := target as UnitBase
	if not _can_track_entity(unit):
		return false
	return unit.current_state != State.DEAD


func _is_valid_building_target(target: Variant) -> bool:
	if not is_instance_valid(target) or not target is BuildingBase:
		return false
	var building := target as BuildingBase
	if not _can_track_entity(building):
		return false
	return building.state != BuildingBase.State.DESTROYED


func _can_track_entity(entity: Node2D) -> bool:
	var game_map := _get_navigation_map()
	if game_map != null and game_map.has_method("is_entity_visible_to_player"):
		return bool(game_map.call("is_entity_visible_to_player", entity, player_owner))
	return true


func _temporarily_ignore_auto_target(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_ignored_auto_targets_until[target.get_instance_id()] = _simulation_elapsed_seconds + AUTO_TARGET_IGNORE_SECONDS


func _is_auto_target_temporarily_ignored(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	var instance_id: int = target.get_instance_id()
	if not _ignored_auto_targets_until.has(instance_id):
		return false
	var expires_at: float = float(_ignored_auto_targets_until[instance_id])
	if _simulation_elapsed_seconds >= expires_at:
		_ignored_auto_targets_until.erase(instance_id)
		return false
	return true


# --- Commands (called by selection/AI systems) ---

## Read-only route feedback follows navigation's live waypoints, including
## repaths and combat detours. Never invent a straight route through blockers.
func get_remaining_navigation_path() -> PackedVector2Array:
	var remaining := PackedVector2Array()
	if current_state in [State.IDLE, State.DEAD] or path_index >= path.size():
		return remaining
	# A reusable chase route is internal while the fighter is already in
	# reach. Hide it until movement actually resumes, including target loss.
	if current_state == State.ATTACKING and attack_target != null:
		if not _is_valid_target(attack_target) or global_position.distance_to(attack_target.global_position) <= attack_range + 8.0:
			return remaining
	remaining.append(global_position)
	for index: int in range(maxi(0, path_index), path.size()):
		if remaining[remaining.size() - 1].distance_squared_to(path[index]) > 1.0:
			remaining.append(path[index])
	if remaining.size() < 2:
		remaining.clear()
	return remaining


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
	var same_target: bool = current_state == State.ATTACKING and attack_target == target
	if current_state != State.ATTACKING or _forced_attack or force_chase:
		_auto_engagement_origin = global_position
		_auto_chase_elapsed = 0.0
	_before_new_command()
	# Reconfirming the same opponent updates intent without interrupting a
	# strike already winding up or restarting the route to a moving target.
	if not same_target:
		_cancel_attack_windup()
		_attack_animation_remaining = 0.0
		_reset_navigation()
	if clear_patrol:
		_clear_patrol()
	if force_chase:
		# A fresh explicit attack replaces a previous attack-move destination;
		# auto-acquisition keeps that destination so movement resumes after combat.
		attack_move = false
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
	var same_target: bool = current_state == State.ATTACKING and attack_building_target == target
	if current_state != State.ATTACKING or _forced_attack or force_chase:
		_auto_engagement_origin = global_position
		_auto_chase_elapsed = 0.0
	_before_new_command()
	if not same_target:
		_cancel_attack_windup()
		_attack_animation_remaining = 0.0
		_reset_navigation()
	if clear_patrol:
		_clear_patrol()
	if force_chase:
		attack_move = false
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


func _update_friendly_separation(movement_direction: Vector2 = Vector2.ZERO) -> void:
	if _separation_timer > 0.0:
		return
	_separation_timer = FRIENDLY_SEPARATION_REFRESH
	var repel := Vector2.ZERO
	# Workers use GATHERING/BUILDING even while following a work route. The
	# supplied direction distinguishes actual travel from standing work/combat.
	var navigating: bool = current_state in [State.MOVING, State.GATHERING, State.BUILDING] and not movement_direction.is_zero_approx()
	_combat_spacing_opponents.clear()
	_navigation_neighbors.clear()
	for node in get_tree().get_nodes_in_group("units"):
		if node == self or not (node is UnitBase):
			continue
		var other: UnitBase = node as UnitBase
		if not is_instance_valid(other) or other.current_state == State.DEAD:
			continue
		var offset: Vector2 = global_position - other.global_position
		var dist: float = offset.length()
		var desired_spacing: float = UNIT_SIZES.get(unit_type, 12.0) + UNIT_SIZES.get(other.unit_type, 12.0) + 8.0
		var separation_radius: float = maxf(FRIENDLY_SEPARATION_RADIUS, desired_spacing)
		# Reuse the throttled neighborhood scan for crowded waypoint handling.
		# The extra margin includes allies beside the upcoming route center.
		if navigating and other.player_owner == player_owner and dist <= separation_radius + NAVIGATION_CROWDED_WAYPOINT_RADIUS:
			_navigation_neighbors.append(other)
		if dist > separation_radius:
			continue
		if other.player_owner != player_owner:
			if current_state == State.ATTACKING:
				_combat_spacing_opponents.append(other)
			continue
		var opposite_movement: bool = false
		if navigating:
			var other_direction: Vector2 = Vector2.ZERO
			if other.current_state in [State.MOVING, State.GATHERING, State.BUILDING] and other.path_index < other.path.size():
				other_direction = other.path[other.path_index] - other.global_position
			elif other.current_state == State.MOVING:
				other_direction = other.move_target - other.global_position
			opposite_movement = movement_direction.dot(other_direction.normalized()) < -0.5
		if dist <= 0.001:
			# Exact shared endpoints otherwise have no direction and never recover.
			# A stable opposite direction for each pair breaks the tie without RNG.
			var tie_direction: Vector2 = Vector2.RIGHT
			if navigating:
				tie_direction = movement_direction.orthogonal()
			if current_state == State.ATTACKING and is_instance_valid(attack_target):
				var toward_target: Vector2 = attack_target.global_position - global_position
				if not toward_target.is_zero_approx():
					tie_direction = toward_target.orthogonal().normalized()
			# Opposing movers each keep the same passing side relative to their
			# route, producing opposite world-space offsets. Same-heading exact
			# overlaps use the stable pair ordering to split to opposite sides.
			offset = tie_direction if opposite_movement else (-tie_direction if get_instance_id() < other.get_instance_id() else tie_direction)
		var strength: float = (separation_radius - dist) / separation_radius
		var moving_bias: float = 1.0
		if other.current_state == State.MOVING:
			moving_bias = 1.2
		repel += offset.normalized() * strength * moving_bias
		if navigating and dist > 0.001 and movement_direction.dot(-offset.normalized()) > 0.5:
			# Collinear repulsion only slows opposing/overtaking units or a
			# mover meeting a settled ally. Add a passing side before coincidence.
			# The existing steering cap and movement solid-tile guard still own
			# speed/progress and reject any sideways step into a building.
			repel += movement_direction.orthogonal() * strength
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
	var previous_hp: float = hp
	hp = maxf(0.0, hp - actual_damage)
	health_changed.emit(self, hp, max_hp)
	if hp < previous_hp:
		damage_received.emit(self, previous_hp - hp)
		_health_feedback_remaining = 2.0
	_flash_damage()
	# Floating damage number
	if is_selected and get_tree() and get_tree().current_scene and AudioManager.is_source_visible(self):
		VFX.damage_float(get_tree(), global_position, actual_damage)
	AudioManager.play_world("attack_hit", self)
	queue_redraw()
	if hp <= 0.0:
		die()


func _flash_damage() -> void:
	if _sprite == null or GameManager.reduced_flashes:
		return
	# Bursts may land while the previous flash is still white. Always restore
	# the stable team tint and replace the old tween instead of capturing its
	# transient color, which permanently bleached enemies after focus fire.
	if _damage_flash_tween != null and _damage_flash_tween.is_valid():
		_damage_flash_tween.kill()
	_sprite.modulate = Color(1.16, 1.12, 1.04)
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_sprite, "modulate", _sprite_team_modulate, 0.15)


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
	if get_tree() and get_tree().current_scene and AudioManager.is_source_visible(self):
		VFX.death_puff(get_tree(), global_position)
	AudioManager.play_world("unit_death", self)
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
