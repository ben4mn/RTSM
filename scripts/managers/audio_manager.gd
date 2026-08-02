extends Node
## Manages all game audio: SFX, UI sounds, and music.
## Generates sounds procedurally — no external audio assets needed.

# --- Volume / enable state ---
var sfx_enabled: bool = true
var ui_enabled: bool = true
var music_enabled: bool = true

# --- Players ---
var _sfx_player: AudioStreamPlayer
var _ui_player: AudioStreamPlayer

# --- Sound library ---
var _sounds: Dictionary = {}

# --- Cooldowns to prevent sound spam ---
var _cooldowns: Dictionary = {}
const MIN_INTERVAL: float = 0.05


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "Master"
	add_child(_sfx_player)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "Master"
	add_child(_ui_player)
	_generate_all_sounds()


func play_sfx(sound_name: String) -> void:
	if not sfx_enabled:
		return
	_play_sound(sound_name, _sfx_player)


func play_ui(sound_name: String) -> void:
	if not ui_enabled:
		return
	_play_sound(sound_name, _ui_player)


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled


func set_ui_enabled(enabled: bool) -> void:
	ui_enabled = enabled


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled


func set_all_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	ui_enabled = enabled
	music_enabled = enabled


func _play_sound(sound_name: String, player: AudioStreamPlayer) -> void:
	if not _sounds.has(sound_name):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if _cooldowns.has(sound_name) and now - _cooldowns[sound_name] < MIN_INTERVAL:
		return
	_cooldowns[sound_name] = now
	# Create a one-shot player so sounds can overlap
	var oneshot := AudioStreamPlayer.new()
	oneshot.bus = player.bus
	oneshot.stream = _sounds[sound_name]
	oneshot.volume_db = -6.0
	add_child(oneshot)
	oneshot.play()
	oneshot.finished.connect(oneshot.queue_free)


# ==========================================================================
#  PROCEDURAL SOUND GENERATION
# ==========================================================================

func _generate_all_sounds() -> void:
	# UI sounds
	_sounds["button_click"] = _gen_click(220.0, 0.06)
	_sounds["select_unit"] = _gen_ping(880.0, 0.1)
	_sounds["command_move"] = _gen_ping(660.0, 0.08)
	_sounds["command_attack"] = _gen_ping(440.0, 0.1)

	# Combat
	_sounds["attack_hit"] = _gen_noise_burst(0.12)
	_sounds["unit_death"] = _gen_descending(300.0, 0.25)

	# Gathering (keyed by resource type: food, wood, gold)
	_sounds["gather_food"] = _gen_ping(520.0, 0.08)
	_sounds["gather_wood"] = _gen_chop(0.1)
	_sounds["gather_gold"] = _gen_mine(0.08)

	# Buildings
	_sounds["building_place"] = _gen_thud(180.0, 0.15)
	_sounds["building_complete"] = _gen_chord([523.25, 659.25, 783.99], 0.4)
	_sounds["building_invalid"] = _gen_buzz(0.15)

	# Production
	_sounds["unit_trained"] = _gen_ding(1046.5, 0.2)

	# Game events
	_sounds["age_up"] = _gen_fanfare(0.6)
	_sounds["under_attack"] = _gen_alarm(0.4)


# --- Generator helpers ---

const SAMPLE_RATE: int = 22050


func _make_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	# Convert float samples to 16-bit PCM bytes
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var s: float = clampf(samples[i], -1.0, 1.0)
		@warning_ignore("narrowing_conversion")
		var val: int = int(s * 32767.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	wav.data = data
	return wav


func _gen_ping(freq: float, duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = 1.0 - (t / duration)
		samples[i] = sin(TAU * freq * t) * envelope * 0.5
	return _make_stream(samples)


func _gen_click(freq: float, duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = maxf(0.0, 1.0 - t / (duration * 0.3))
		samples[i] = sin(TAU * freq * t) * envelope * 0.3
	return _make_stream(samples)


func _gen_noise_burst(duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = 1.0 - (t / duration)
		samples[i] = (randf() * 2.0 - 1.0) * envelope * 0.4
	return _make_stream(samples)


func _gen_descending(start_freq: float, duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var freq: float = start_freq * (1.0 - t / duration * 0.6)
		var envelope: float = 1.0 - (t / duration)
		samples[i] = sin(TAU * freq * t) * envelope * 0.4
	return _make_stream(samples)


func _gen_chop(duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = maxf(0.0, 1.0 - t / (duration * 0.5))
		# Mix noise with a low thud
		var noise: float = (randf() * 2.0 - 1.0) * 0.3
		var thud: float = sin(TAU * 120.0 * t) * 0.3
		samples[i] = (noise + thud) * envelope
	return _make_stream(samples)


func _gen_mine(duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = maxf(0.0, 1.0 - t / (duration * 0.4))
		# Metallic ring: high sine + noise
		var ring: float = sin(TAU * 1200.0 * t) * 0.25
		var hit: float = (randf() * 2.0 - 1.0) * 0.2
		samples[i] = (ring + hit) * envelope
	return _make_stream(samples)


func _gen_thud(freq: float, duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = maxf(0.0, 1.0 - t / duration)
		samples[i] = sin(TAU * freq * t) * envelope * envelope * 0.5
	return _make_stream(samples)


func _gen_chord(freqs: Array, duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var amp: float = 0.3 / freqs.size()
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = 1.0 - (t / duration)
		var val: float = 0.0
		for freq in freqs:
			val += sin(TAU * freq * t)
		samples[i] = val * amp * envelope
	return _make_stream(samples)


func _gen_buzz(duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = 1.0 - (t / duration)
		# Square wave at low frequency = buzzy error sound
		var sq: float = 1.0 if fmod(t * 150.0, 1.0) < 0.5 else -1.0
		samples[i] = sq * envelope * 0.25
	return _make_stream(samples)


func _gen_ding(freq: float, duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = exp(-t * 8.0)
		samples[i] = sin(TAU * freq * t) * envelope * 0.4
	return _make_stream(samples)


func _gen_fanfare(duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	# Three ascending notes: C5, E5, G5
	var notes: Array = [523.25, 659.25, 783.99]
	var note_dur: float = duration / notes.size()
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		@warning_ignore("narrowing_conversion")
		var note_idx: int = mini(int(t / note_dur), notes.size() - 1)
		var note_t: float = t - note_idx * note_dur
		var envelope: float = maxf(0.0, 1.0 - note_t / note_dur)
		samples[i] = sin(TAU * notes[note_idx] * t) * envelope * 0.35
	return _make_stream(samples)


func _gen_alarm(duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = 1.0 - (t / duration)
		# Alternating between two frequencies for urgency
		var freq: float = 600.0 if fmod(t * 6.0, 1.0) < 0.5 else 800.0
		samples[i] = sin(TAU * freq * t) * envelope * 0.35
	return _make_stream(samples)
