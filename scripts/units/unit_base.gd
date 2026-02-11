class_name UnitBase
extends Area2D
## Base class for all units in AOEM. Handles movement, selection,
## health, state machine, and auto-attack behavior.

signal unit_died(unit: UnitBase)
signal unit_selected(unit: UnitBase)
signal unit_deselected(unit: UnitBase)
signal health_changed(unit: UnitBase, new_hp: float, max_hp: float)
signal state_changed(unit: UnitBase, new_state: int)
signal arrived_at_destination(unit: UnitBase)

enum State { IDLE, MOVING, ATTACKING, GATHERING, BUILDING, DEAD }

# --- Stats (overridden per unit type) ---
@export var unit_type: int = UnitData.UnitType.VILLAGER
@export var player_owner: int = 0
@export var max_hp: float = 25.0
@export var hp: float = 25.0
@export var damage: float = 3.0
@export var armor: float = 0.0
@export var speed: float = 60.0
@export var attack_range: float = 10.0
@export var vision_radius: float = 4.0
@export var attack_speed: float = 1.0  # attacks per second
@export var is_ranged: bool = false

# --- Runtime state ---
var current_state: int = State.IDLE
var move_target: Vector2 = Vector2.ZERO
var attack_target: UnitBase = null
var is_selected: bool = false
var attack_cooldown: float = 0.0
var path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var team_color: Color = Color.BLUE

# --- Node references ---
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# --- Colors per unit type (placeholder art) ---
const UNIT_COLORS: Dictionary = {
	UnitData.UnitType.VILLAGER: Color(0.8, 0.6, 0.2),   # brown/tan
	UnitData.UnitType.INFANTRY: Color(0.7, 0.1, 0.1),   # red
	UnitData.UnitType.ARCHER: Color(0.1, 0.7, 0.1),     # green
	UnitData.UnitType.CAVALRY: Color(0.6, 0.2, 0.8),    # purple
	UnitData.UnitType.SCOUT: Color(0.9, 0.9, 0.2),      # yellow
	UnitData.UnitType.SIEGE: Color(0.4, 0.4, 0.4),      # gray
}

# --- Sizes per unit type ---
const UNIT_SIZES: Dictionary = {
	UnitData.UnitType.VILLAGER: 8.0,
	UnitData.UnitType.INFANTRY: 10.0,
	UnitData.UnitType.ARCHER: 9.0,
	UnitData.UnitType.CAVALRY: 12.0,
	UnitData.UnitType.SCOUT: 8.0,
	UnitData.UnitType.SIEGE: 14.0,
}


func _ready() -> void:
	_setup_collision()
	_load_stats_from_data()
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
	attack_range = float(stats.get("attack_range", attack_range)) * 16.0  # tile units to pixels
	vision_radius = float(stats.get("vision_radius", vision_radius)) * 16.0
	is_ranged = stats.get("attack_range", 1) > 1


func _process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	attack_cooldown = maxf(0.0, attack_cooldown - delta)

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


func _draw() -> void:
	var unit_color: Color = UNIT_COLORS.get(unit_type, Color.WHITE)
	var size: float = UNIT_SIZES.get(unit_type, 10.0)

	# Selection indicator (circle under unit)
	if is_selected:
		draw_circle(Vector2.ZERO, size + 4.0, Color(0.2, 1.0, 0.2, 0.4))

	# Team color ring
	draw_arc(Vector2.ZERO, size + 1.0, 0, TAU, 32, team_color, 2.0)

	# Unit body
	draw_circle(Vector2.ZERO, size, unit_color)

	# Health bar (above unit)
	var bar_width: float = size * 2.5
	var bar_height: float = 3.0
	var bar_y: float = -(size + 8.0)
	var hp_ratio: float = hp / max_hp if max_hp > 0 else 0.0

	# Background
	draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width, bar_height), Color(0.2, 0.0, 0.0, 0.8))
	# Foreground
	var hp_color := Color.GREEN if hp_ratio > 0.5 else (Color.YELLOW if hp_ratio > 0.25 else Color.RED)
	draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width * hp_ratio, bar_height), hp_color)

	# Ranged indicator (small diamond on top)
	if is_ranged:
		var pts := PackedVector2Array([
			Vector2(0, -size - 2),
			Vector2(3, -size + 1),
			Vector2(0, -size + 4),
			Vector2(-3, -size + 1),
		])
		draw_colored_polygon(pts, Color.WHITE)


# --- State Machine ---

func set_state(new_state: int) -> void:
	if current_state == State.DEAD:
		return
	if current_state == new_state:
		return
	current_state = new_state
	state_changed.emit(self, new_state)
	queue_redraw()


func _process_idle(_delta: float) -> void:
	# Look for nearby enemies to auto-attack
	_try_auto_attack()


func _process_moving(delta: float) -> void:
	if path.is_empty() or path_index >= path.size():
		# Direct movement to target
		var direction: Vector2 = (move_target - global_position)
		if direction.length() < 4.0:
			_on_reached_destination()
			return
		global_position += direction.normalized() * speed * delta
	else:
		# Follow path
		var next_point: Vector2 = path[path_index]
		var direction: Vector2 = next_point - global_position
		if direction.length() < 4.0:
			path_index += 1
			if path_index >= path.size():
				_on_reached_destination()
				return
		global_position += direction.normalized() * speed * delta

	# While moving, check for enemies in range (auto-attack)
	if attack_target == null:
		_try_auto_attack()


func _on_reached_destination() -> void:
	path = PackedVector2Array()
	path_index = 0
	set_state(State.IDLE)
	arrived_at_destination.emit(self)


func _process_attacking(delta: float) -> void:
	if not _is_valid_target(attack_target):
		attack_target = null
		set_state(State.IDLE)
		return

	var dist: float = global_position.distance_to(attack_target.global_position)
	if dist > attack_range + 8.0:
		# Move towards target
		var direction: Vector2 = (attack_target.global_position - global_position).normalized()
		global_position += direction * speed * delta
	else:
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
	if damage <= 0.0:
		return  # Non-combat units (scouts with 0 damage)
	var closest_enemy: UnitBase = null
	var closest_dist: float = vision_radius
	for unit in get_tree().get_nodes_in_group("units"):
		if unit == self or unit.current_state == State.DEAD:
			continue
		if unit.player_owner == player_owner:
			continue
		var dist: float = global_position.distance_to(unit.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_enemy = unit
	if closest_enemy != null:
		command_attack(closest_enemy)


func _perform_attack() -> void:
	if not _is_valid_target(attack_target):
		return
	attack_cooldown = 1.0 / attack_speed
	Combat.deal_damage(self, attack_target)


func _is_valid_target(target: UnitBase) -> bool:
	if target == null:
		return false
	if not is_instance_valid(target):
		return false
	if target.current_state == State.DEAD:
		return false
	return true


# --- Commands (called by selection/AI systems) ---

func command_move(target_pos: Vector2) -> void:
	if current_state == State.DEAD:
		return
	move_target = target_pos
	attack_target = null
	path = PackedVector2Array()
	path_index = 0
	set_state(State.MOVING)


func command_move_path(nav_path: PackedVector2Array) -> void:
	if current_state == State.DEAD:
		return
	if nav_path.is_empty():
		return
	path = nav_path
	path_index = 0
	move_target = nav_path[nav_path.size() - 1]
	attack_target = null
	set_state(State.MOVING)


func command_attack(target: UnitBase) -> void:
	if current_state == State.DEAD:
		return
	if not _is_valid_target(target):
		return
	attack_target = target
	set_state(State.ATTACKING)


func command_stop() -> void:
	if current_state == State.DEAD:
		return
	attack_target = null
	path = PackedVector2Array()
	path_index = 0
	set_state(State.IDLE)


# --- Health ---

func take_damage(amount: float) -> void:
	if current_state == State.DEAD:
		return
	var actual_damage: float = maxf(1.0, amount - armor)
	hp = maxf(0.0, hp - actual_damage)
	health_changed.emit(self, hp, max_hp)
	queue_redraw()
	if hp <= 0.0:
		die()


func heal(amount: float) -> void:
	if current_state == State.DEAD:
		return
	hp = minf(max_hp, hp + amount)
	health_changed.emit(self, hp, max_hp)
	queue_redraw()


func die() -> void:
	set_state(State.DEAD)
	unit_died.emit(self)
	# Brief delay before removal for death animation opportunity
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


# --- Selection ---

func select() -> void:
	is_selected = true
	unit_selected.emit(self)
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
