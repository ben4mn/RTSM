class_name UnitBase
extends Area2D
## Base class for all units in AOEM. Handles movement, selection,
## health, state machine, auto-attack behavior, and sprite-based rendering.

signal unit_died(unit: UnitBase)
signal unit_selected(unit: UnitBase)
signal unit_deselected(unit: UnitBase)
signal health_changed(unit: UnitBase, new_hp: float, max_hp: float)
signal state_changed(unit: UnitBase, new_state: int)
signal arrived_at_destination(unit: UnitBase)

enum State { IDLE, MOVING, ATTACKING, GATHERING, BUILDING, DEAD }
enum Stance { AGGRESSIVE, STAND_GROUND }

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

# --- Node references ---
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# --- Sprite mapping per unit type from Kenney Medieval RTS pack ---
const UNIT_SPRITES: Dictionary = {
	UnitData.UnitType.VILLAGER: "res://assets/units/unit_01.png",
	UnitData.UnitType.INFANTRY: "res://assets/units/unit_05.png",
	UnitData.UnitType.ARCHER: "res://assets/units/unit_13.png",
	UnitData.UnitType.CAVALRY: "res://assets/units/unit_04.png",
	UnitData.UnitType.SCOUT: "res://assets/units/unit_07.png",
	UnitData.UnitType.SIEGE: "res://assets/units/unit_09.png",
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
	UnitData.UnitType.VILLAGER: Vector2(0.24, 0.24),
	UnitData.UnitType.INFANTRY: Vector2(0.26, 0.26),
	UnitData.UnitType.ARCHER: Vector2(0.24, 0.24),
	UnitData.UnitType.CAVALRY: Vector2(0.30, 0.30),
	UnitData.UnitType.SCOUT: Vector2(0.24, 0.24),
	UnitData.UnitType.SIEGE: Vector2(0.32, 0.32),
}

var _sprite: Sprite2D = null


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
	attack_range = float(stats.get("attack_range", attack_range)) * 16.0  # tile units to pixels
	vision_radius = float(stats.get("vision_radius", vision_radius)) * 16.0
	is_ranged = stats.get("attack_range", 1) > 1


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "UnitSprite"
	var tex_path: String = UNIT_SPRITES.get(unit_type, "")
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_sprite.texture = load(tex_path)
	_sprite.scale = UNIT_SPRITE_SCALES.get(unit_type, Vector2(0.20, 0.20))
	_sprite.offset = Vector2(0, -4)  # Slight upward offset so unit appears above ground
	add_child(_sprite)
	# Apply team color tint to enemy units
	if player_owner != 0:
		_sprite.modulate = Color(1.0, 0.4, 0.4)  # Bold red tint for enemies


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

	# Continuous redraw for pulsing selection
	if is_selected:
		queue_redraw()


func _draw() -> void:
	var size: float = UNIT_SIZES.get(unit_type, 10.0)

	# Shadow ellipse under unit
	draw_circle(Vector2(0, 2), size * 0.6, Color(0, 0, 0, 0.2))

	# Selection indicator (pulsing circle under unit)
	if is_selected:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		var sel_alpha := lerpf(0.3, 0.8, pulse)
		var sel_radius := lerpf(size + 2.0, size + 5.0, pulse)
		draw_arc(Vector2.ZERO, sel_radius, 0, TAU, 32, Color(0.2, 1.0, 0.2, sel_alpha), 2.0)

	# Team color filled circle under unit (semi-transparent)
	draw_circle(Vector2.ZERO, size * 0.7, Color(team_color.r, team_color.g, team_color.b, 0.35))
	# Team color ring
	draw_arc(Vector2.ZERO, size + 1.0, 0, TAU, 32, team_color, 3.0)

	# Health bar (above unit)
	var bar_width: float = size * 2.5
	var bar_height: float = 3.0
	var bar_y: float = -(size + 12.0)
	var hp_ratio: float = hp / max_hp if max_hp > 0 else 0.0

	# Background
	draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width, bar_height), Color(0.15, 0.0, 0.0, 0.8))
	# Foreground
	var hp_color := Color.GREEN if hp_ratio > 0.5 else (Color.YELLOW if hp_ratio > 0.25 else Color.RED)
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
	# Look for nearby enemies to auto-attack (stand ground uses shorter range)
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

	# While moving, check for enemies in range
	# Attack-move: always look for enemies; normal move: only auto-attack if aggressive
	if attack_target == null and (attack_move or stance == Stance.AGGRESSIVE):
		_try_auto_attack()


func _on_reached_destination() -> void:
	path = PackedVector2Array()
	path_index = 0
	set_state(State.IDLE)
	arrived_at_destination.emit(self)


func _process_attacking(delta: float) -> void:
	# Handle building attacks
	if attack_building_target != null:
		if not is_instance_valid(attack_building_target) or attack_building_target.state == BuildingBase.State.DESTROYED:
			attack_building_target = null
			set_state(State.IDLE)
			return
		var dist: float = global_position.distance_to(attack_building_target.global_position)
		if dist > attack_range + 24.0:
			var direction: Vector2 = (attack_building_target.global_position - global_position).normalized()
			global_position += direction * speed * delta
		else:
			if attack_cooldown <= 0.0:
				_perform_building_attack()
		return

	if not _is_valid_target(attack_target):
		attack_target = null
		set_state(State.IDLE)
		return

	var dist: float = global_position.distance_to(attack_target.global_position)
	if dist > attack_range + 8.0:
		# Stand ground units won't chase beyond their attack range
		if stance == Stance.STAND_GROUND:
			attack_target = null
			set_state(State.IDLE)
			return
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
	# Stand ground: only engage within attack range, not full vision
	var search_radius: float = attack_range + 16.0 if stance == Stance.STAND_GROUND else vision_radius
	# Check for enemy units first (priority over buildings)
	var closest_enemy: UnitBase = null
	var closest_dist: float = search_radius
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or unit == self or unit.current_state == State.DEAD:
			continue
		if unit.player_owner == player_owner:
			continue
		var dist: float = global_position.distance_to(unit.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_enemy = unit
	if closest_enemy != null:
		command_attack(closest_enemy)
		return

	# Check for enemy buildings nearby
	var closest_building: BuildingBase = null
	var closest_b_dist: float = search_radius * 0.5  # shorter range for building auto-attack
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not (building is BuildingBase):
			continue
		if building.player_owner == player_owner:
			continue
		if building.state == BuildingBase.State.DESTROYED:
			continue
		var dist: float = global_position.distance_to(building.global_position)
		if dist < closest_b_dist:
			closest_b_dist = dist
			closest_building = building
	if closest_building != null:
		command_attack_building(closest_building)


func _perform_attack() -> void:
	if not _is_valid_target(attack_target):
		return
	attack_cooldown = 1.0 / attack_speed
	Combat.deal_damage(self, attack_target)


func _perform_building_attack() -> void:
	if attack_building_target == null or not is_instance_valid(attack_building_target):
		return
	attack_cooldown = 1.0 / attack_speed
	var dmg: int = int(damage)
	# Apply bonus_vs_buildings if the unit has one (siege units)
	var stats: Dictionary = UnitData.get_unit_stats(unit_type)
	if stats.has("bonus_vs_buildings"):
		dmg = int(dmg * stats["bonus_vs_buildings"])
	attack_building_target.take_damage(dmg)
	# Hit particles on building
	if get_tree() and get_tree().current_scene:
		VFX.hit_burst(get_tree(), attack_building_target.global_position, Color(1.0, 0.7, 0.3))


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
	attack_building_target = null
	attack_move = false
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
	attack_building_target = null
	set_state(State.ATTACKING)


func command_attack_building(target: BuildingBase) -> void:
	if current_state == State.DEAD:
		return
	if not is_instance_valid(target) or target.state == BuildingBase.State.DESTROYED:
		return
	attack_building_target = target
	attack_target = null
	set_state(State.ATTACKING)


func command_attack_move(target_pos: Vector2) -> void:
	if current_state == State.DEAD:
		return
	attack_move = true
	move_target = target_pos
	attack_target = null
	attack_building_target = null
	path = PackedVector2Array()
	path_index = 0
	set_state(State.MOVING)


func command_stop() -> void:
	if current_state == State.DEAD:
		return
	attack_target = null
	attack_building_target = null
	attack_move = false
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
	_flash_damage()
	# Floating damage number
	if get_tree() and get_tree().current_scene:
		VFX.damage_float(get_tree(), global_position, actual_damage)
	queue_redraw()
	if hp <= 0.0:
		die()


func _flash_damage() -> void:
	if _sprite == null:
		return
	var original: Color = _sprite.modulate
	_sprite.modulate = Color(1, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", original, 0.15)


func heal(amount: float) -> void:
	if current_state == State.DEAD:
		return
	hp = minf(max_hp, hp + amount)
	health_changed.emit(self, hp, max_hp)
	queue_redraw()


func die() -> void:
	set_state(State.DEAD)
	unit_died.emit(self)
	# Death puff particles
	if get_tree() and get_tree().current_scene:
		VFX.death_puff(get_tree(), global_position)
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
