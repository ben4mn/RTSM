extends Node
## Bounded medieval feedback palette. World cues require visible, nearby sources;
## owned alerts and interface responses use a separate, reserved voice pool.

const SAMPLE_RATE: int = 22050
const WORLD_VOICES: int = 8
const UI_VOICES: int = 4
const ALERT_SOUNDS: Array[String] = ["under_attack", "unit_trained", "building_complete", "age_up", "victory", "defeat"]
const COOLDOWNS := {"button_click": 0.055, "select_unit": 0.14, "command_move": 0.14, "command_attack": 0.18, "attack_hit": 0.10, "unit_death": 0.22, "gather_food": 0.8, "gather_wood": 0.55, "gather_gold": 0.65, "construction_work": 0.7, "under_attack": 1.2, "unit_trained": 0.4, "building_complete": 0.5, "age_up": 1.0, "victory": 2.0, "defeat": 2.0}
const GAINS := {"button_click": -9.0, "select_unit": -8.0, "command_move": -9.0, "command_attack": -8.0, "attack_hit": -12.0, "unit_death": -11.0, "gather_food": -17.0, "gather_wood": -16.0, "gather_gold": -17.0, "construction_work": -15.0, "under_attack": -3.0, "age_up": -5.0, "victory": -4.0, "defeat": -5.0}
var sfx_enabled: bool = true
var ui_enabled: bool = true
var music_enabled: bool = false # There is no score; no inert music control is exposed.
var _sounds: Dictionary = {}
var _cooldowns: Dictionary = {}
var _world_players: Array[AudioStreamPlayer] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _backgrounded: bool = false
var _preview_serial: int = 0
var _web_visibility_callback: JavaScriptObject
var _peak_active_voices: int = 0
var _played: Dictionary = {}
var _suppressed: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 73109 # Sound construction must never perturb gameplay random state.
	_ensure_bus("World", "Master")
	_ensure_bus("UIAlerts", "Master")
	_create_players(_world_players, WORLD_VOICES, "World")
	_create_players(_ui_players, UI_VOICES, "UIAlerts")
	_generate_all_sounds()
	apply_preferences()
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.age_advanced.connect(func(owner: int, _age: int) -> void:
		if owner == 0: play_ui("age_up")
	)
	GameManager.game_over.connect(func(winner: int) -> void: play_ui("victory" if winner == 0 else "defeat"))
	get_tree().node_added.connect(_on_node_added)
	_install_web_lifecycle()


func _ensure_bus(bus_name: String, parent_bus: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, parent_bus)


func _create_players(pool: Array[AudioStreamPlayer], count: int, bus_name: String) -> void:
	for i: int in count:
		var player := AudioStreamPlayer.new()
		player.name = "%sVoice%d" % [bus_name, i]
		player.bus = bus_name
		# Use Godot's bounded stream mixer. The Web sample backend can retain
		# stale bus indices after runtime bus changes, silently creating a cycle.
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		pool.append(player)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button.call_deferred(node.get_instance_id())


func _connect_button(instance_id: int) -> void:
	var node: Node = instance_from_id(instance_id) as Node
	if is_instance_valid(node) and node is BaseButton:
		(node as BaseButton).pressed.connect(func() -> void: play_ui("button_click"))


func play_sfx(sound_name: String) -> void:
	# Global positive feedback belongs to the player's alert channel. Repeated
	# world sounds use play_world with a source, never this notification API.
	if sound_name in ALERT_SOUNDS or sound_name in ["select_unit", "command_move", "command_attack", "building_invalid", "building_place"]:
		play_ui(sound_name)
		return
	if sfx_enabled and not _backgrounded and GameManager.current_state == GameManager.GameState.PLAYING:
		_play(sound_name, _world_players)


func play_world(sound_name: String, source: Node2D) -> void:
	if not sfx_enabled or _backgrounded or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	if not is_source_visible(source):
		_suppress("fog")
		return
	var viewport: Viewport = source.get_viewport()
	var screen: Vector2 = viewport.get_canvas_transform() * source.global_position
	var view_rect: Rect2 = viewport.get_visible_rect()
	if not view_rect.grow(80.0).has_point(screen):
		_suppress("distance")
		return
	var distance: float = screen.distance_to(view_rect.get_center()) / maxf(1.0, view_rect.size.length() * 0.5)
	_play(sound_name, _world_players, -clampf(distance, 0.0, 1.2) * 7.0)


func is_source_visible(source: Node2D) -> bool:
	if not is_instance_valid(source) or not source.is_inside_tree(): return false
	var map: Node = source.get_parent()
	while map != null and not map.has_method("is_entity_visible_to_player"):
		map = map.get_parent()
	return map != null and bool(map.call("is_entity_visible_to_player", source, 0))


func play_ui(sound_name: String) -> void:
	if ui_enabled and not _backgrounded:
		_play(sound_name, _ui_players)


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	if not enabled: _stop_pool(_world_players)


func set_ui_enabled(enabled: bool) -> void:
	ui_enabled = enabled
	if not enabled: _stop_pool(_ui_players)


func set_music_enabled(_enabled: bool) -> void:
	music_enabled = false


func set_all_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	ui_enabled = enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not enabled)
	if not enabled: stop_all()


func apply_preferences() -> void:
	set_all_enabled(GameManager.audio_enabled)
	set_sfx_enabled(GameManager.audio_enabled and not GameManager.sfx_muted)
	set_ui_enabled(GameManager.audio_enabled and not GameManager.ui_alert_muted)
	_set_volume("Master", GameManager.master_volume)
	_set_volume("World", GameManager.sfx_volume)
	_set_volume("UIAlerts", GameManager.ui_alert_volume)


func _set_volume(bus_name: String, volume: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_mute(index, volume <= 0.0 or (bus_name == "Master" and not GameManager.audio_enabled))
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.00001, clampf(volume, 0.0, 1.0))))


func _play(sound_name: String, pool: Array[AudioStreamPlayer], attenuation: float = 0.0) -> void:
	if not _sounds.has(sound_name): return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_cooldowns.get(sound_name, -100.0)) < float(COOLDOWNS.get(sound_name, 0.15)):
		_suppress("cooldown")
		return
	var voice: AudioStreamPlayer
	# The last two interface voices are reserved for alerts. Click storms cannot
	# steal an attack horn, an age confirmation or the result of the match.
	var alert: bool = sound_name in ALERT_SOUNDS
	for i: int in pool.size():
		if pool == _ui_players and not alert and i >= UI_VOICES - 2:
			continue
		if not pool[i].playing:
			voice = pool[i]
			break
	if voice == null:
		if alert:
			voice = pool[pool.size() - 1]
		else:
			_suppress("voice_limit")
			return
	_cooldowns[sound_name] = now
	voice.stop()
	voice.stream = _sounds[sound_name]
	voice.volume_db = float(GAINS.get(sound_name, -8.0)) + attenuation
	voice.pitch_scale = 1.0
	voice.play()
	_played[sound_name] = int(_played.get(sound_name, 0)) + 1
	_peak_active_voices = maxi(_peak_active_voices, _active_voices())


func _active_voices() -> int:
	var count: int = 0
	for player: AudioStreamPlayer in _world_players + _ui_players:
		if player.playing: count += 1
	return count


func _suppress(reason: String) -> void:
	_suppressed[reason] = int(_suppressed.get(reason, 0)) + 1


func get_audio_diagnostics() -> Dictionary:
	return {"active_voices": _active_voices(), "voice_limit": WORLD_VOICES + UI_VOICES, "peak_active_voices": _peak_active_voices, "backgrounded": _backgrounded, "played": _played.duplicate(), "suppressed": _suppressed.duplicate(), "master_volume": GameManager.master_volume, "sfx_volume": GameManager.sfx_volume, "ui_alert_volume": GameManager.ui_alert_volume, "enabled": sfx_enabled}


func _stop_pool(pool: Array[AudioStreamPlayer]) -> void:
	for player: AudioStreamPlayer in pool:
		player.stop()


func stop_all() -> void:
	_preview_serial += 1
	_stop_pool(_world_players)
	_stop_pool(_ui_players)
	_cooldowns.clear()


func _on_game_state_changed(_state: int) -> void:
	stop_all() # No battle tails, preview timers or loops survive scene/pause boundaries.


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_backgrounded(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_backgrounded(false)


func _set_backgrounded(value: bool) -> void:
	_backgrounded = value
	if value: stop_all()


func _install_web_lifecycle() -> void:
	if not OS.has_feature("web"): return
	# Godot's Web Audio driver owns user-gesture unlocking. This only discards
	# obsolete sounds when the tab/PWA is hidden; nothing is queued for resume.
	JavaScriptBridge.eval("window.PocketAudioLifecycle = {attach(cb) { this.cb = cb; this.listener = () => cb(document.hidden); document.addEventListener('visibilitychange', this.listener); cb(document.hidden); }, detach() { document.removeEventListener('visibilitychange', this.listener); this.cb = null; }};", true)
	_web_visibility_callback = JavaScriptBridge.create_callback(_on_web_visibility)
	var bridge: JavaScriptObject = JavaScriptBridge.get_interface("PocketAudioLifecycle")
	bridge.attach(_web_visibility_callback)


func _on_web_visibility(arguments: Array) -> void:
	if not arguments.is_empty(): _set_backgrounded(bool(arguments[0]))


func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.PocketAudioLifecycle && window.PocketAudioLifecycle.detach();", true)


func preview() -> void:
	_preview_serial += 1
	var serial: int = _preview_serial
	play_ui("button_click")
	await get_tree().create_timer(0.25, true, false, true).timeout
	if serial != _preview_serial or _backgrounded: return
	if sfx_enabled: _play("attack_hit", _world_players)
	await get_tree().create_timer(0.4, true, false, true).timeout
	if serial != _preview_serial or _backgrounded: return
	play_ui("under_attack")


func _generate_all_sounds() -> void:
	_sounds["button_click"] = _gen_texture(410.0, 0.065, 0.25, 0.32)
	_sounds["select_unit"] = _gen_texture(310.0, 0.13, 0.08, 0.12)
	_sounds["command_move"] = _gen_chord([246.94, 369.99], 0.16)
	_sounds["command_attack"] = _gen_horn([196.0, 246.94], 0.26)
	_sounds["attack_hit"] = _gen_texture(170.0, 0.17, 0.42, 0.68)
	_sounds["unit_death"] = _gen_texture(90.0, 0.30, 0.48, 0.06)
	_sounds["gather_food"] = _gen_texture(260.0, 0.10, 0.55, 0.02)
	_sounds["gather_wood"] = _gen_texture(125.0, 0.12, 0.25, 0.05)
	_sounds["gather_gold"] = _gen_texture(690.0, 0.18, 0.08, 0.62)
	_sounds["construction_work"] = _gen_texture(150.0, 0.16, 0.30, 0.18)
	_sounds["building_place"] = _gen_texture(100.0, 0.23, 0.35, 0.12)
	_sounds["building_complete"] = _gen_chord([392.0, 493.88, 587.33], 0.5)
	_sounds["building_invalid"] = _gen_horn([174.61, 146.83], 0.22)
	_sounds["unit_trained"] = _gen_chord([392.0, 587.33], 0.25)
	_sounds["age_up"] = _gen_horn([261.63, 329.63, 392.0], 0.8)
	_sounds["under_attack"] = _gen_horn([196.0, 293.66, 196.0], 0.64)
	_sounds["victory"] = _gen_horn([261.63, 329.63, 392.0, 523.25], 1.2)
	_sounds["defeat"] = _gen_horn([246.94, 196.0, 146.83], 1.15)


func _gen_texture(freq: float, duration: float, noise_mix: float, metal_mix: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var softened_noise: float = 0.0
	for i: int in count:
		var t: float = float(i) / SAMPLE_RATE
		var tail: float = 1.0 - t / duration
		var onset: float = minf(1.0, t / 0.003)
		softened_noise = lerpf(softened_noise, _rng.randf_range(-1.0, 1.0), 0.25)
		var body: float = sin(TAU * freq * t) * exp(-t * 22.0)
		var ring: float = (sin(TAU * freq * 2.71 * t) + sin(TAU * freq * 4.13 * t) * 0.35) * exp(-t * 13.0)
		samples[i] = (body * 0.48 + softened_noise * noise_mix + ring * metal_mix * 0.35) * tail * onset * 0.72
	return _make_stream(samples)


func _gen_horn(notes: Array, duration: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var note_duration: float = duration / notes.size()
	for i: int in count:
		var t: float = float(i) / SAMPLE_RATE
		var index: int = mini(int(t / note_duration), notes.size() - 1)
		var local_t: float = t - float(index) * note_duration
		var envelope: float = minf(1.0, local_t / 0.024) * minf(1.0, (note_duration - local_t) / 0.07)
		var phase: float = TAU * float(notes[index]) * local_t
		samples[i] = (sin(phase) + sin(phase * 2.0) * 0.25 + sin(phase * 3.0) * 0.10) * envelope * 0.28
	return _make_stream(samples)


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
