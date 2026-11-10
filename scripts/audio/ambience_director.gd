extends Node
## Looping ambience layers chosen by what the camera shows: a quiet daytime bed
## plus forest, water and busy-town layers. Unexplored ground contributes
## nothing, so the mix never discloses fogged terrain. Ducked during battle.

const AMBIENCE_DIR := "res://assets/audio/identity/ambience/"
const LAYERS: Array[String] = ["day_bed", "forest", "water", "town"]
## Layer trims in dB at full weight. Files are level-matched (see the audio doc).
const TRIM := {"day_bed": -9.0, "forest": -11.0, "water": -10.0, "town": -7.0}
const SAMPLE_INTERVAL: float = 0.5
const GRID := Vector2i(9, 5)
const BATTLE_DUCK: float = 0.3
const RISE_PER_SECOND: float = 0.45
const FALL_PER_SECOND: float = 0.6
const TOWN_FULL_BUILDINGS: float = 5.0

var _players: Dictionary = {}
var _gain: Dictionary = {}
var _target: Dictionary = {}
var _allowed: bool = false
var _held: bool = false
var _in_match: bool = false
var _battle: bool = false
var _sample_clock: float = 0.0
var _buildings: Array[WeakRef] = []
var _last_sample: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for layer: String in LAYERS:
		var player := AudioStreamPlayer.new()
		player.name = "Ambience_" + layer
		player.bus = "Ambience"
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		player.volume_db = -80.0
		add_child(player)
		_players[layer] = player
		_gain[layer] = 0.0
		_target[layer] = 0.0


func set_allowed(allowed: bool) -> void:
	_allowed = allowed
	if not allowed:
		for layer: String in LAYERS:
			(_players[layer] as AudioStreamPlayer).stop()
			_gain[layer] = 0.0


func set_held(held: bool) -> void:
	_held = held
	for layer: String in LAYERS:
		(_players[layer] as AudioStreamPlayer).stream_paused = held


func set_in_match(in_match: bool) -> void:
	_in_match = in_match
	if not in_match:
		for layer: String in LAYERS:
			_target[layer] = 0.0


func set_battle(active: bool) -> void:
	_battle = active


func track_building(building: Node2D) -> void:
	_buildings.append(weakref(building))


func _process(delta: float) -> void:
	if not _allowed or _held:
		return
	if _in_match and not get_tree().paused:
		_sample_clock -= delta
		if _sample_clock <= 0.0:
			_sample_clock = SAMPLE_INTERVAL
			_sample_screen()
	for layer: String in LAYERS:
		var player: AudioStreamPlayer = _players[layer]
		var goal: float = float(_target[layer]) * (BATTLE_DUCK if _battle else 1.0)
		var gain: float = float(_gain[layer])
		if gain == goal and (gain > 0.0 or not player.playing):
			continue
		gain = move_toward(gain, goal, (RISE_PER_SECOND if goal > gain else FALL_PER_SECOND) * delta)
		_gain[layer] = gain
		if gain > 0.0 and not player.playing:
			if player.stream == null:
				var stream: AudioStreamOggVorbis = load(AMBIENCE_DIR + layer + ".ogg") as AudioStreamOggVorbis
				if stream == null:
					continue
				stream.loop = true
				player.stream = stream
			player.play()
		elif gain <= 0.0 and player.playing:
			player.stop()
		player.volume_db = linear_to_db(maxf(0.0001, gain)) + float(TRIM[layer])


func _sample_screen() -> void:
	var scene: Node = get_tree().current_scene
	var map: Node = scene.get_node_or_null("GameMap") if scene != null else null
	if map == null or not map.has_method("get_tile_at_world") or not map.has_method("world_to_tile"):
		for layer: String in LAYERS:
			_target[layer] = 0.0
		return
	var viewport: Viewport = (map as Node2D).get_viewport()
	var view: Rect2 = viewport.get_visible_rect()
	var to_world: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var fog: Object = map.get("fog_of_war")
	var forest: int = 0
	var water: int = 0
	var known: int = 0
	for gx: int in GRID.x:
		for gy: int in GRID.y:
			var screen := view.position + Vector2((gx + 0.5) / GRID.x, (gy + 0.5) / GRID.y) * view.size
			var world: Vector2 = to_world * screen
			var tile: Vector2i = map.call("world_to_tile", world)
			if fog != null and fog.has_method("is_explored") and not bool(fog.call("is_explored", tile)):
				continue
			known += 1
			var kind: int = int(map.call("get_tile_at_world", world))
			if kind == MapData.TileType.FOREST:
				forest += 1
			elif kind == MapData.TileType.WATER:
				water += 1
	var total: float = float(GRID.x * GRID.y)
	var town: int = 0
	var grown: Rect2 = view.grow(40.0)
	var canvas: Transform2D = viewport.get_canvas_transform()
	for index: int in range(_buildings.size() - 1, -1, -1):
		var building: Node2D = _buildings[index].get_ref() as Node2D
		if building == null or not is_instance_valid(building):
			_buildings.remove_at(index)
			continue
		if int(building.get("player_owner")) == 0 and building.is_inside_tree() and grown.has_point(canvas * building.global_position):
			town += 1
	_target["day_bed"] = 1.0 if known > 0 else 0.4
	_target["forest"] = smoothstep(0.01, 0.15, forest / total)
	_target["water"] = smoothstep(0.01, 0.15, water / total)
	_target["town"] = clampf((town - 1) / (TOWN_FULL_BUILDINGS - 1.0), 0.0, 1.0)
	_last_sample = {"forest_tiles": forest, "water_tiles": water, "explored": known, "own_buildings": town}


func _exit_tree() -> void:
	for layer: String in LAYERS:
		(_players[layer] as AudioStreamPlayer).stop()
		(_players[layer] as AudioStreamPlayer).stream = null


func get_state() -> Dictionary:
	var gains: Dictionary = {}
	var playing: Dictionary = {}
	for layer: String in LAYERS:
		gains[layer] = snappedf(float(_gain[layer]), 0.01)
		playing[layer] = (_players[layer] as AudioStreamPlayer).playing
	return {"allowed": _allowed, "held": _held, "in_match": _in_match, "battle_duck": _battle, "gains": gains, "targets": _target.duplicate(), "playing": playing, "sample": _last_sample.duplicate()}
