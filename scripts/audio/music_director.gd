extends Node
## Two-deck music director. AudioManager chooses the mode; this node owns the
## shuffled playlist, crossfades, loop-by-crossfade and pause/resume. It never
## starts a stream until AudioManager reports a user gesture (Web autoplay).

const MUSIC_DIR := "res://assets/audio/identity/music/"
const PLAYLISTS := {
	"menu": ["menu_exploration"],
	"peace": ["peace_old_tower_inn", "peace_bards_tale", "peace_kings_feast", "peace_market_day", "menu_exploration"],
	"battle": ["battle"],
	"victory": ["stinger_victory"],
	"defeat": ["stinger_defeat"],
}
## Seconds of crossfade when ENTERING a mode; track-to-track changes use TRACK_CROSSFADE.
const MODE_FADE := {"menu": 2.5, "peace": 4.0, "battle": 1.6, "victory": 0.5, "defeat": 0.8, "silent": 1.5}
const ONE_SHOT_MODES: Array[String] = ["victory", "defeat"]
const TRACK_CROSSFADE: float = 4.0
const FIRST_START_FADE: float = 2.0

var mode: String = "silent"
var _decks: Array[AudioStreamPlayer] = []
var _gain: Array[float] = [0.0, 0.0]
var _target: Array[float] = [0.0, 0.0]
var _rate: Array[float] = [1.0, 1.0]
var _track: Array[String] = ["", ""]
var _active: int = 0
var _allowed: bool = false
var _held: bool = false
var _last_track: Dictionary = {}
var _order: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _transitions: int = 0
var _log: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize() # Own generator: the playlist order never touches gameplay random state.
	for index: int in 2:
		var deck := AudioStreamPlayer.new()
		deck.name = "MusicDeck%d" % index
		deck.bus = "Music"
		deck.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		deck.volume_db = -80.0
		add_child(deck)
		_decks.append(deck)


## AudioManager gates playback: false until the first gesture, while muted or disabled.
func set_allowed(allowed: bool) -> void:
	if _allowed == allowed:
		return
	_allowed = allowed
	if not allowed:
		for index: int in 2:
			_decks[index].stop()
			_gain[index] = 0.0
			_target[index] = 0.0
			_track[index] = ""
	elif mode != "silent":
		_start_next(FIRST_START_FADE)


## Hidden tab / lost focus: keep position, produce no sound, resume where it stopped.
func set_held(held: bool) -> void:
	_held = held
	for deck: AudioStreamPlayer in _decks:
		deck.stream_paused = held


func set_mode(next: String) -> void:
	if next == mode or not (PLAYLISTS.has(next) or next == "silent"):
		return
	mode = next
	_transitions += 1
	_note("mode " + next)
	if not _allowed:
		return
	if next == "silent":
		_fade_out_all(float(MODE_FADE["silent"]))
	else:
		_start_next(float(MODE_FADE[next]))


func _start_next(fade: float) -> void:
	var track_name: String = _pick(mode)
	var stream: AudioStream = load(MUSIC_DIR + track_name + ".ogg") as AudioStream
	if stream == null:
		_note("missing " + track_name)
		return
	var next: int = 1 - _active
	# If the idle deck is still fading the previous-but-one track, reuse it anyway:
	# at most two streams ever decode.
	_decks[next].stop()
	_decks[next].stream = stream
	_decks[next].volume_db = -80.0
	_decks[next].play()
	_decks[next].stream_paused = _held
	_track[next] = track_name
	_gain[next] = 0.0
	_target[next] = 1.0
	_rate[next] = 1.0 / maxf(0.05, fade)
	_target[_active] = 0.0
	_rate[_active] = 1.0 / maxf(0.05, fade)
	_active = next
	_note("track " + track_name)


func _pick(list_name: String) -> String:
	var list: Array = PLAYLISTS[list_name]
	if list.size() == 1:
		return str(list[0])
	var order: Array = _order.get(list_name, [])
	if order.is_empty():
		order = list.duplicate()
		# Fisher-Yates with the director's own generator.
		for index: int in range(order.size() - 1, 0, -1):
			var swap: int = _rng.randi_range(0, index)
			var held: Variant = order[index]
			order[index] = order[swap]
			order[swap] = held
		if str(order[0]) == str(_last_track.get(list_name, "")):
			order.push_back(order.pop_front())
	var picked: String = str(order.pop_front())
	_order[list_name] = order
	_last_track[list_name] = picked
	return picked


func _fade_out_all(fade: float) -> void:
	for index: int in 2:
		_target[index] = 0.0
		_rate[index] = 1.0 / maxf(0.05, fade)


func _process(delta: float) -> void:
	if not _allowed or _held:
		return
	for index: int in 2:
		if _gain[index] != _target[index]:
			_gain[index] = move_toward(_gain[index], _target[index], _rate[index] * delta)
			# Equal-power law keeps the summed loudness level through a crossfade.
			_decks[index].volume_db = linear_to_db(maxf(0.0001, sin(_gain[index] * PI * 0.5)))
			if _gain[index] <= 0.0 and _target[index] <= 0.0:
				_decks[index].stop()
				_track[index] = ""
	if mode == "silent":
		return
	var deck: AudioStreamPlayer = _decks[_active]
	if deck.stream == null:
		return
	var length: float = deck.stream.get_length()
	var one_shot: bool = mode in ONE_SHOT_MODES
	if not deck.playing:
		# A stinger ended (or a stream failed): settle into the calm menu bed.
		if one_shot:
			mode = "menu"
			_note("mode menu")
		_start_next(float(MODE_FADE["menu"]) if one_shot else 0.5)
	elif not one_shot and length > TRACK_CROSSFADE * 3.0 and deck.get_playback_position() >= length - TRACK_CROSSFADE and _target[_active] > 0.0:
		_start_next(TRACK_CROSSFADE)


func _exit_tree() -> void:
	for deck: AudioStreamPlayer in _decks:
		deck.stop()
		deck.stream = null


func _note(text: String) -> void:
	_log.append("%.1f %s" % [Time.get_ticks_msec() / 1000.0, text])
	if _log.size() > 24:
		_log.pop_front()


func get_state() -> Dictionary:
	var deck: AudioStreamPlayer = _decks[_active]
	return {
		"mode": mode, "allowed": _allowed, "held": _held, "track": _track[_active], "fading_out": _track[1 - _active],
		"playing": deck.playing and not deck.stream_paused, "position": snappedf(deck.get_playback_position(), 0.01) if deck.playing else 0.0,
		"length": snappedf(deck.stream.get_length(), 0.01) if deck.stream != null else 0.0,
		"gain": snappedf(_gain[_active], 0.01), "other_gain": snappedf(_gain[1 - _active], 0.01), "transitions": _transitions, "log": _log.duplicate(),
	}
