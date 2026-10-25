extends Node
## Original felt, wood and cloth feedback palette. World cues require visible, nearby sources;
## owned alerts and interface responses use a separate, reserved voice pool.

const SAMPLE_RATE: int = 22050
const WORLD_VOICES: int = 8
const UI_VOICES: int = 4
const ALERT_SOUNDS: Array[String] = ["under_attack", "unit_trained", "building_complete", "age_up", "victory", "defeat"]
const COOLDOWNS := {"button_click": 0.08, "select_unit": 0.18, "command_move": 0.20, "command_attack": 0.24, "attack_hit": 0.20, "unit_death": 0.50, "gather_food": 1.3, "gather_wood": 1.0, "gather_gold": 1.2, "construction_work": 1.1, "under_attack": 6.0, "unit_trained": 0.65, "building_complete": 0.8, "age_up": 2.0, "victory": 3.0, "defeat": 3.0}
const GAINS := {"button_click": -13.0, "select_unit": -11.0, "command_move": -10.0, "command_attack": -10.0, "attack_hit": -15.0, "unit_death": -18.0, "gather_food": -20.0, "gather_wood": -19.0, "gather_gold": -20.0, "construction_work": -18.0, "building_place": -10.0, "building_invalid": -13.0, "unit_trained": -9.0, "building_complete": -8.0, "under_attack": -6.0, "age_up": -7.0, "victory": -5.0, "defeat": -7.0}
const GROUPS := {"gather_food": "work", "gather_wood": "work", "gather_gold": "work", "construction_work": "work", "attack_hit": "combat", "unit_death": "combat", "command_move": "orders", "command_attack": "orders"}
const GROUP_COOLDOWNS := {"work": 0.65, "combat": 0.18, "orders": 0.18}
const PRIORITIES := {"button_click": 0, "select_unit": 1, "command_move": 2, "command_attack": 2, "building_place": 2, "building_invalid": 2, "unit_trained": 3, "building_complete": 3, "under_attack": 4, "age_up": 4, "victory": 5, "defeat": 5}
var sfx_enabled: bool = true
var ui_enabled: bool = true
var music_enabled: bool = false # There is no score; no inert music control is exposed.
var _sounds: Dictionary = {}
var _cooldowns: Dictionary = {}
var _group_cooldowns: Dictionary = {}
var _last_variants: Dictionary = {}
var _last_intent_time: float = -100.0
var _web_activated: bool = false
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
	_web_activated = not OS.has_feature("web")
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


func _input(event: InputEvent) -> void:
	# Discard pre-gesture cues rather than accumulating a burst behind autoplay.
	# The browser/Godot driver remains responsible for unlocking its AudioContext.
	if (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.is_pressed():
		_web_activated = true


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
	if not _web_activated:
		_suppress("activation")
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	# A successful order/selection already supplies tactile feedback. The button
	# hookup must not layer a second click over that same gesture.
	if sound_name == "button_click" and now - _last_intent_time < 0.07:
		_suppress("gesture")
		return
	if now - float(_cooldowns.get(sound_name, -100.0)) < float(COOLDOWNS.get(sound_name, 0.15)):
		_suppress("cooldown")
		return
	var group: String = str(GROUPS.get(sound_name, ""))
	if not group.is_empty() and now - float(_group_cooldowns.get(group, -100.0)) < float(GROUP_COOLDOWNS[group]):
		_suppress("group_cooldown")
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
		# Only a more important cue may displace another. Recruitment cannot cut
		# off an attack warning, and nothing may cut off a victory/defeat cadence.
		var priority: int = int(PRIORITIES.get(sound_name, 0))
		var lowest: int = priority
		for i: int in pool.size():
			if pool == _ui_players and not alert and i >= UI_VOICES - 2: continue
			var candidate: int = int(pool[i].get_meta("priority", 0))
			if candidate < lowest:
				voice = pool[i]
				lowest = candidate
		if voice == null:
			_suppress("voice_limit")
			return
	_cooldowns[sound_name] = now
	if not group.is_empty(): _group_cooldowns[group] = now
	if pool == _ui_players and sound_name != "button_click": _last_intent_time = now
	voice.stop()
	var bank: Array = _sounds[sound_name]
	var variant: int = _rng.randi_range(0, bank.size() - 1)
	if bank.size() > 1 and variant == int(_last_variants.get(sound_name, -1)):
		variant = (variant + 1) % bank.size()
	_last_variants[sound_name] = variant
	voice.stream = bank[variant]
	voice.set_meta("priority", int(PRIORITIES.get(sound_name, 0)))
	voice.set_meta("cue", sound_name)
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
	return {"active_voices": _active_voices(), "voice_limit": WORLD_VOICES + UI_VOICES, "peak_active_voices": _peak_active_voices, "backgrounded": _backgrounded, "activated": _web_activated, "variants": _last_variants.duplicate(), "played": _played.duplicate(), "suppressed": _suppressed.duplicate(), "master_volume": GameManager.master_volume, "sfx_volume": GameManager.sfx_volume, "ui_alert_volume": GameManager.ui_alert_volume, "enabled": sfx_enabled}


func _stop_pool(pool: Array[AudioStreamPlayer]) -> void:
	for player: AudioStreamPlayer in pool:
		player.stop()


func stop_all() -> void:
	_preview_serial += 1
	_stop_pool(_world_players)
	_stop_pool(_ui_players)
	_cooldowns.clear()
	_group_cooldowns.clear()
	_last_intent_time = -100.0


func _on_game_state_changed(_state: int) -> void:
	stop_all() # No battle tails, preview timers or loops survive scene/pause boundaries.


func _notification(what: int) -> void:
	# Only the explicit native recording fixture sets this metadata. Release
	# builds cannot bypass lifecycle handling through this diagnostic hook.
	if OS.is_debug_build() and bool(get_meta("controlled_audio_capture", false)): return
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
	_sounds = preload("res://scripts/audio/tactile_palette.gd").build()
