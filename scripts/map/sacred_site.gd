extends Node2D
## Sacred Site — a neutral capturable building at the center of the map.
## Generates gold per second when captured. Becomes contested if both
## players have units nearby.

signal captured(player_id: int)
signal contested()
signal neutralized()
signal victory_timer_tick(player_id: int, remaining: float, total: float)
signal status_changed()

enum SiteState {
	NEUTRAL,
	CAPTURING,
	CAPTURED,
	CONTESTED,
}

const NEUTRAL_COLOR: Color = Color("d5cdb5")
const FRIENDLY_COLOR: Color = Color("88b7ad")
const ENEMY_COLOR: Color = Color("d69477")
const CONTESTED_COLOR: Color = Color("c6b486")

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
@export var victory_hold_time: float = SkirmishData.SACRED_VICTORY_HOLD_SECONDS

## Game time at which the victory clock may start (Standard: 8:00).
var victory_wake_time: float = SkirmishData.SACRED_VICTORY_WAKE_SECONDS

## Accumulated hold time for the current owner.
var victory_timer: float = 0.0
var match_mode: int = SkirmishData.MatchMode.STANDARD
var control_banks: Array[float] = [0.0, 0.0]
## Public objective facts; replicas receive these from the authority, never fog actors.
var clock_ticking: bool = false
var garrison_paused: bool = false
var _armed_nearby_counts: Array[int] = [0, 0]


func configure_match_mode(mode: int) -> void:
	match_mode = SkirmishData.normalize_match_mode(mode)
	victory_hold_time = SkirmishData.get_sacred_target(match_mode)
	victory_wake_time = SkirmishData.get_sacred_wake_seconds(match_mode)
	control_banks = [0.0, 0.0]
	victory_timer = 0.0
	clock_ticking = false
	garrison_paused = false


func _reset_or_restore_timer() -> void:
	victory_timer = control_banks[owning_player] if match_mode != SkirmishData.MatchMode.STANDARD and owning_player in [0, 1] else 0.0


func _advance_victory(delta: float) -> void:
	if owning_player not in [0, 1]:
		return
	clock_ticking = true
	victory_timer += delta
	if match_mode != SkirmishData.MatchMode.STANDARD:
		control_banks[owning_player] = victory_timer
	victory_timer_tick.emit(owning_player, victory_hold_time - victory_timer, victory_hold_time)


## ResourceManager stores whole resources. Preserve sub-resource income between
## frames so a normal 60 FPS update does not truncate every award to zero.
var _gold_accumulator: float = 0.0
var _gold_accumulator_owner: int = -1

## Tile position on the map grid.
var tile_position: Vector2i = Vector2i.ZERO
var _last_status_key: String = ""
var _being_neutralized: bool = false

## Visual indicator node.
@onready var progress_bar: Node2D = $ProgressIndicator if has_node("ProgressIndicator") else null
@onready var sprite: Node2D = $Sprite if has_node("Sprite") else null


func _ready() -> void:
	add_to_group("sacred_sites")
	add_to_group("buildings")


func _process(delta: float) -> void:
	_being_neutralized = false
	clock_ticking = false
	garrison_paused = false
	var nearby := _count_nearby_players()
	var p1_count: int = nearby[0]
	var p2_count: int = nearby[1]

	match state:
		SiteState.NEUTRAL:
			_handle_neutral(p1_count, p2_count, delta)
		SiteState.CAPTURING:
			_handle_capturing(p1_count, p2_count, delta)
		SiteState.CAPTURED:
			var armed_friendly: int = _armed_nearby_counts[owning_player] if owning_player in [0, 1] else 0
			_handle_captured(p1_count, p2_count, delta, armed_friendly)
		SiteState.CONTESTED:
			_handle_contested(p1_count, p2_count, delta)
	if state != SiteState.CAPTURED:
		_reset_gold_accumulator()

	_update_visuals()
	_publish_status()


func _handle_neutral(p1: int, p2: int, _delta: float) -> void:
	if p1 > 0 and p2 == 0:
		state = SiteState.CAPTURING
		owning_player = 0
		capture_progress = 0.0
		_reset_or_restore_timer()
	elif p2 > 0 and p1 == 0:
		state = SiteState.CAPTURING
		owning_player = 1
		capture_progress = 0.0
		_reset_or_restore_timer()


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


func _handle_captured(p1: int, p2: int, delta: float, armed_friendly: int = 0) -> void:
	_being_neutralized = false
	clock_ticking = false
	garrison_paused = false
	var enemy := p2 if owning_player == 0 else p1
	var friendly := p1 if owning_player == 0 else p2

	if enemy > 0 and friendly > 0:
		state = SiteState.CONTESTED
		contested.emit()
		return

	if enemy > 0 and friendly == 0:
		# Enemy is de-capturing.
		_being_neutralized = true
		capture_progress -= (delta / capture_time) * (minf(enemy, 5) * 0.5 + 0.5)
		if capture_progress <= 0.0:
			capture_progress = 0.0
			state = SiteState.NEUTRAL
			var _old_owner := owning_player
			owning_player = -1
			_reset_or_restore_timer()
			neutralized.emit()
		return

	# Generate gold for the owning player.
	_generate_gold(delta)
	# Before the clock opens, holding pays gold but cannot advance a victory.
	if victory_wake_remaining() > 0.0:
		return

	# Standard asks an army to occupy the ground it wants to win from. Scouts
	# and workers retain capture, contest and income utility. Control race keeps
	# its established banked-ownership rules. Leaving pauses; it never resets.
	garrison_paused = match_mode == SkirmishData.MatchMode.STANDARD and armed_friendly <= 0
	if not garrison_paused:
		_advance_victory(delta)


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
				_reset_or_restore_timer()
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
				_reset_or_restore_timer()
				state = SiteState.CAPTURING
		return
	# Both players present — pause control in both rule sets.


func _generate_gold(delta: float) -> void:
	# Add gold to the owning player via the ResourceManager autoload.
	if owning_player < 0 or delta <= 0.0:
		return
	if _gold_accumulator_owner != owning_player:
		_gold_accumulator = 0.0
		_gold_accumulator_owner = owning_player
	_gold_accumulator += gold_per_second * delta
	var whole_gold: int = floori(_gold_accumulator + 0.000001)
	if whole_gold <= 0:
		return
	var rm: Node = get_node_or_null("/root/ResourceManager")
	if rm == null or not rm.has_method("add_resource"):
		return
	_gold_accumulator -= float(whole_gold)
	rm.add_resource(owning_player, "gold", whole_gold)


func _reset_gold_accumulator() -> void:
	_gold_accumulator = 0.0
	_gold_accumulator_owner = -1


## Count how many units each player has within the capture radius.
func _count_nearby_players() -> Array[int]:
	var counts: Array[int] = [0, 0]
	_armed_nearby_counts = [0, 0]
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or not unit is Node2D:
			continue
		# Unit death fades for a short time before queue_free. The visual remnant
		# must not capture, contest, or cross a victory boundary during that fade.
		if unit is UnitBase and (unit as UnitBase).current_state == UnitBase.State.DEAD:
			continue
		var unit_node := unit as Node2D
		var dist := global_position.distance_to(unit_node.global_position)
		# Convert pixel distance to approximate tile distance.
		if dist <= get_capture_radius_world():
			var pid := 0
			if unit_node.has_method("get_player_id"):
				pid = unit_node.get_player_id()
			elif unit_node.has_meta("player_id"):
				pid = unit_node.get_meta("player_id")
			if pid >= 0 and pid <= 1:
				counts[pid] += 1
				if unit is UnitBase and is_armed_garrison_unit(unit as UnitBase):
					_armed_nearby_counts[pid] += 1
	return counts


static func is_armed_garrison_unit(unit: UnitBase) -> bool:
	return is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD and unit.hp > 0.0 and unit.damage > 0.0 and unit.unit_type not in [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT]


func _update_visuals() -> void:
	# Color the sprite based on state.
	if sprite == null:
		return
	match state:
		SiteState.NEUTRAL:
			sprite.modulate = NEUTRAL_COLOR
		SiteState.CAPTURING:
			var owner_color := FRIENDLY_COLOR if owning_player == 0 else ENEMY_COLOR
			sprite.modulate = owner_color.lerp(NEUTRAL_COLOR, 1.0 - capture_progress)
		SiteState.CAPTURED:
			sprite.modulate = FRIENDLY_COLOR if owning_player == 0 else ENEMY_COLOR
		SiteState.CONTESTED:
			sprite.modulate = CONTESTED_COLOR

	# Update progress indicator bar.
	var fill_node: Node = get_node_or_null("ProgressIndicator/ProgressFill")
	if fill_node and fill_node is Polygon2D:
		var bar_w: float = 40.0 * capture_progress
		(fill_node as Polygon2D).polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(bar_w, 0), Vector2(bar_w, 4), Vector2(0, 4)
		])
		# Color the fill bar based on owner
		if owning_player == 0:
			(fill_node as Polygon2D).color = FRIENDLY_COLOR
		elif owning_player == 1:
			(fill_node as Polygon2D).color = ENEMY_COLOR

	queue_redraw()


func _draw() -> void:
	# A quiet field marker, with ownership carried by the same colors as units.
	var site_color: Color = NEUTRAL_COLOR
	match state:
		SiteState.CAPTURING:
			site_color = FRIENDLY_COLOR if owning_player == 0 else ENEMY_COLOR
		SiteState.CAPTURED:
			site_color = FRIENDLY_COLOR if owning_player == 0 else ENEMY_COLOR
		SiteState.CONTESTED:
			site_color = CONTESTED_COLOR
	draw_arc(Vector2.ZERO, 48.0, 0, TAU, 48, Color(site_color, 0.22), 1.0, true)
	# This boundary is the actual distance at
	# which troops capture or pause a hold, using the same radius as detection.
	var boundary_color := Color(site_color, 0.24)
	draw_arc(Vector2.ZERO, get_capture_radius_world(), 0, TAU, 96, boundary_color, 1.2, true)

	# Victory timer ring (when captured, shows progress toward victory)
	if state == SiteState.CAPTURED and victory_timer > 0.0:
		var timer_ratio := clampf(victory_timer / victory_hold_time, 0.0, 1.0)
		var ring_color := FRIENDLY_COLOR if owning_player == 0 else ENEMY_COLOR
		var arc_end := TAU * timer_ratio - PI * 0.5
		draw_arc(Vector2.ZERO, 35.0, -PI * 0.5, arc_end, 48, ring_color, 3.0)


## API for external systems.
func get_player_id() -> int:
	return owning_player

func get_state() -> SiteState:
	return state

func get_capture_progress() -> float:
	return capture_progress


func get_capture_radius_world() -> float:
	return float(capture_radius * MapData.TILE_WIDTH)


func victory_wake_remaining() -> float:
	return maxf(0.0, victory_wake_time - GameManager.game_time)


func get_status() -> Dictionary:
	var phase: String = "neutral"
	var wake_remaining: float = victory_wake_remaining()
	match state:
		SiteState.CAPTURING: phase = "capturing"
		SiteState.CAPTURED: phase = "neutralizing" if _being_neutralized else ("waiting" if wake_remaining > 0.0 else ("unguarded" if garrison_paused else "holding"))
		SiteState.CONTESTED: phase = "contested"
	return {
		"phase": phase,
		"owner": owning_player,
		"capture_progress": clampf(capture_progress, 0.0, 1.0),
		"remaining": maxf(0.0, victory_hold_time - victory_timer),
		"total": victory_hold_time,
		"gold_per_second": gold_per_second,
		"match_mode": match_mode,
		"control_banks": control_banks.duplicate(),
		"clock_ticking": clock_ticking,
		"garrison_paused": garrison_paused,
		"wake_remaining": wake_remaining,
	}


func _publish_status() -> void:
	# Refresh immediately when the phase/owner changes, and only on visible
	# second/percentage boundaries while a timer advances.
	var status: Dictionary = get_status()
	var key: String = "%s:%d:%d:%d:%s:%s:%d" % [status["phase"], owning_player, floori(capture_progress * 100.0), ceili(float(status["remaining"])), clock_ticking, garrison_paused, ceili(float(status["wake_remaining"]))]
	if key == _last_status_key:
		return
	_last_status_key = key
	status_changed.emit()
