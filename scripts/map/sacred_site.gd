extends Node2D
## Sacred Site — a neutral capturable building at the center of the map.
## Generates gold per second when captured. Becomes contested if both
## players have units nearby.

signal captured(player_id: int)
signal contested()
signal neutralized()

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


func _handle_neutral(p1: int, p2: int, delta: float) -> void:
	if p1 > 0 and p2 == 0:
		state = SiteState.CAPTURING
		owning_player = 0
		capture_progress = 0.0
	elif p2 > 0 and p1 == 0:
		state = SiteState.CAPTURING
		owning_player = 1
		capture_progress = 0.0


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
			var old_owner := owning_player
			owning_player = -1
			neutralized.emit()
		return

	# Generate gold for the owning player.
	_generate_gold(delta)


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
		var rm := get_node_or_null("/root/ResourceManager")
		if rm and rm.has_method("add_resource"):
			rm.add_resource(owning_player, "gold", gold_per_second * delta)


## Count how many units each player has within the capture radius.
func _count_nearby_players() -> Array[int]:
	var counts: Array[int] = [0, 0]
	for unit in get_tree().get_nodes_in_group("units"):
		if not unit is Node2D:
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

	# Update progress indicator.
	if progress_bar and progress_bar.has_method("set_progress"):
		progress_bar.set_progress(capture_progress)


## API for external systems.
func get_player_id() -> int:
	return owning_player

func get_state() -> SiteState:
	return state

func get_capture_progress() -> float:
	return capture_progress
