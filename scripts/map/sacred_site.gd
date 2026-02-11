extends Node2D
## Sacred Site — a neutral capturable building at the center of the map.
## Generates gold per second when captured. Becomes contested if both
## players have units nearby.

signal captured(player_id: int)
signal contested()
signal neutralized()
signal victory_timer_tick(player_id: int, remaining: float, total: float)

enum SiteState {
	NEUTRAL,
	CAPTURING,
	CAPTURED,
	CONTESTED,
}

## Current state of the sacred site.
var state: SiteState = SiteState.NEUTRAL

## Which player currently owns/is capturing this site (-1 = none).
var owning_player: int = -1

## Capture progress (0.0 to 1.0). Resets when contested.
var capture_progress: float = 0.0

## Time in seconds to fully capture.
@export var capture_time: float = 30.0

## Gold generated per second when captured.
@export var gold_per_second: float = 2.0

## Radius in tiles to detect nearby units.
@export var capture_radius: int = 3

## Time to hold sacred site for a victory (seconds).
@export var victory_hold_time: float = 180.0  # 3 minutes

## Accumulated hold time for the current owner.
var victory_timer: float = 0.0

## Tile position on the map grid.
var tile_position: Vector2i = Vector2i.ZERO

## Visual indicator node.
@onready var progress_bar: Node2D = $ProgressIndicator if has_node("ProgressIndicator") else null
@onready var sprite: Node2D = $Sprite if has_node("Sprite") else null


func _ready() -> void:
	add_to_group("sacred_sites")
	add_to_group("buildings")


func _process(delta: float) -> void:
	var nearby := _count_nearby_players()
	var p1_count: int = nearby[0]
	var p2_count: int = nearby[1]

	match state:
		SiteState.NEUTRAL:
			_handle_neutral(p1_count, p2_count, delta)
		SiteState.CAPTURING:
			_handle_capturing(p1_count, p2_count, delta)
		SiteState.CAPTURED:
			_handle_captured(p1_count, p2_count, delta)
		SiteState.CONTESTED:
			_handle_contested(p1_count, p2_count, delta)

	_update_visuals()


func _handle_neutral(p1: int, p2: int, _delta: float) -> void:
	if p1 > 0 and p2 == 0:
		state = SiteState.CAPTURING
		owning_player = 0
		capture_progress = 0.0
		victory_timer = 0.0
	elif p2 > 0 and p1 == 0:
		state = SiteState.CAPTURING
		owning_player = 1
		capture_progress = 0.0
		victory_timer = 0.0


func _handle_capturing(p1: int, p2: int, delta: float) -> void:
	var friendly := p1 if owning_player == 0 else p2
	var enemy := p2 if owning_player == 0 else p1

	if enemy > 0 and friendly > 0:
		state = SiteState.CONTESTED
		contested.emit()
		return

	if friendly == 0:
		# Capturing player left — decay progress.
		capture_progress -= delta / capture_time
		if capture_progress <= 0.0:
			capture_progress = 0.0
			state = SiteState.NEUTRAL
			owning_player = -1
			neutralized.emit()
		return

	# Continue capturing — more units = faster capture.
	var speed_mult := minf(friendly, 5) * 0.5 + 0.5  # 1x to 3x speed.
	capture_progress += (delta / capture_time) * speed_mult
	if capture_progress >= 1.0:
		capture_progress = 1.0
		state = SiteState.CAPTURED
		captured.emit(owning_player)


func _handle_captured(p1: int, p2: int, delta: float) -> void:
	var enemy := p2 if owning_player == 0 else p1
	var friendly := p1 if owning_player == 0 else p2

	if enemy > 0 and friendly > 0:
		state = SiteState.CONTESTED
		contested.emit()
		return

	if enemy > 0 and friendly == 0:
		# Enemy is de-capturing.
		capture_progress -= (delta / capture_time) * (minf(enemy, 5) * 0.5 + 0.5)
		if capture_progress <= 0.0:
			capture_progress = 0.0
			state = SiteState.NEUTRAL
			var _old_owner := owning_player
			owning_player = -1
			victory_timer = 0.0
			neutralized.emit()
		return

	# Generate gold for the owning player.
	_generate_gold(delta)

	# Tick victory timer.
	victory_timer += delta
	victory_timer_tick.emit(owning_player, victory_hold_time - victory_timer, victory_hold_time)


func _handle_contested(p1: int, p2: int, delta: float) -> void:
	if p1 == 0 and p2 == 0:
		state = SiteState.NEUTRAL if capture_progress <= 0.0 else SiteState.CAPTURING
		return
	if p1 > 0 and p2 == 0:
		if owning_player == 0:
			state = SiteState.CAPTURING
		else:
			# Switch capturing player.
			capture_progress -= delta / capture_time
			if capture_progress <= 0.0:
				owning_player = 0
				capture_progress = 0.0
				state = SiteState.CAPTURING
		return
	if p2 > 0 and p1 == 0:
		if owning_player == 1:
			state = SiteState.CAPTURING
		else:
			capture_progress -= delta / capture_time
			if capture_progress <= 0.0:
				owning_player = 1
				capture_progress = 0.0
				state = SiteState.CAPTURING
		return
	# Both players present — no progress.


func _generate_gold(delta: float) -> void:
	# Add gold to the owning player via the ResourceManager autoload.
	if Engine.has_singleton("ResourceManager") or get_node_or_null("/root/ResourceManager"):
		var rm: Node = get_node_or_null("/root/ResourceManager")
		if rm and rm.has_method("add_resource"):
			rm.add_resource(owning_player, "gold", gold_per_second * delta)


## Count how many units each player has within the capture radius.
func _count_nearby_players() -> Array[int]:
	var counts: Array[int] = [0, 0]
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or not unit is Node2D:
			continue
		var unit_node := unit as Node2D
		var dist := global_position.distance_to(unit_node.global_position)
		# Convert pixel distance to approximate tile distance.
		var tile_dist := dist / float(MapData.TILE_WIDTH)
		if tile_dist <= capture_radius:
			var pid := 0
			if unit_node.has_method("get_player_id"):
				pid = unit_node.get_player_id()
			elif unit_node.has_meta("player_id"):
				pid = unit_node.get_meta("player_id")
			if pid >= 0 and pid <= 1:
				counts[pid] += 1
	return counts


func _update_visuals() -> void:
	# Color the sprite based on state.
	if sprite == null:
		return
	match state:
		SiteState.NEUTRAL:
			sprite.modulate = Color(0.75, 0.65, 0.85)
		SiteState.CAPTURING:
			var owner_color := Color(0.3, 0.5, 1.0) if owning_player == 0 else Color(1.0, 0.3, 0.3)
			sprite.modulate = owner_color.lerp(Color(0.75, 0.65, 0.85), 1.0 - capture_progress)
		SiteState.CAPTURED:
			sprite.modulate = Color(0.3, 0.5, 1.0) if owning_player == 0 else Color(1.0, 0.3, 0.3)
		SiteState.CONTESTED:
			sprite.modulate = Color(1.0, 0.85, 0.2)  # Yellow when contested.

	# Update progress indicator bar.
	var fill_node: Node = get_node_or_null("ProgressIndicator/ProgressFill")
	if fill_node and fill_node is Polygon2D:
		var bar_w: float = 40.0 * capture_progress
		(fill_node as Polygon2D).polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(bar_w, 0), Vector2(bar_w, 4), Vector2(0, 4)
		])
		# Color the fill bar based on owner
		if owning_player == 0:
			(fill_node as Polygon2D).color = Color(0.3, 0.6, 1.0, 0.9)
		elif owning_player == 1:
			(fill_node as Polygon2D).color = Color(1.0, 0.3, 0.3, 0.9)

	queue_redraw()


func _draw() -> void:
	# Pulsing glow aura
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.003)
	var aura_radius := 50.0 + pulse * 10.0

	# Base aura (always visible, purple neutral)
	var aura_color: Color
	match state:
		SiteState.NEUTRAL:
			aura_color = Color(0.6, 0.4, 0.8, 0.06 + pulse * 0.04)
		SiteState.CAPTURING:
			var base_col := Color(0.3, 0.5, 1.0) if owning_player == 0 else Color(1.0, 0.3, 0.3)
			aura_color = Color(base_col.r, base_col.g, base_col.b, 0.08 + pulse * 0.05)
		SiteState.CAPTURED:
			var base_col := Color(0.3, 0.5, 1.0) if owning_player == 0 else Color(1.0, 0.3, 0.3)
			aura_color = Color(base_col.r, base_col.g, base_col.b, 0.10 + pulse * 0.06)
		SiteState.CONTESTED:
			aura_color = Color(1.0, 0.85, 0.2, 0.08 + pulse * 0.05)
		_:
			aura_color = Color(0.6, 0.4, 0.8, 0.06)

	draw_circle(Vector2.ZERO, aura_radius, aura_color)
	draw_arc(Vector2.ZERO, aura_radius, 0, TAU, 48, Color(aura_color.r, aura_color.g, aura_color.b, aura_color.a * 2.0), 1.5)

	# Victory timer ring (when captured, shows progress toward victory)
	if state == SiteState.CAPTURED and victory_timer > 0.0:
		var timer_ratio := clampf(victory_timer / victory_hold_time, 0.0, 1.0)
		var ring_color := Color(0.3, 0.7, 1.0, 0.6) if owning_player == 0 else Color(1.0, 0.4, 0.3, 0.6)
		var arc_end := TAU * timer_ratio - PI * 0.5
		draw_arc(Vector2.ZERO, 35.0, -PI * 0.5, arc_end, 48, ring_color, 3.0)


## API for external systems.
func get_player_id() -> int:
	return owning_player

func get_state() -> SiteState:
	return state

func get_capture_progress() -> float:
	return capture_progress
