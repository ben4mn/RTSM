extends Node
## Record the actual engine mix from living economy actors and a staged battle.
## This is an audio/render fixture, not an economy, balance or human-play claim.

var _main: Node
var _capture: AudioEffectCapture
var _frames := PackedVector2Array()
var _recording: bool = false
var _output: String
var _report: Dictionary = {"scope": "Native rendered real-time game mix. Funded paid house/recruit, natural labor/gathering; explicitly staged free 12-vs-12 armies, unchanged combat. Not browser or physical-device evidence, not subjective listening.", "phases": [], "failures": [], "focus_events": []}
var _start_ms: int
var _hits: int = 0
var _sample_peak: float = 0.0
var _sum_squares: float = 0.0


func _ready() -> void:
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _recording or _capture == null: return
	var count: int = _capture.get_frames_available()
	if count == 0: return
	var block: PackedVector2Array = _capture.get_buffer(count)
	_frames.append_array(block)
	for sample: Vector2 in block:
		_sample_peak = maxf(_sample_peak, maxf(absf(sample.x), absf(sample.y)))
		_sum_squares += sample.x * sample.x + sample.y * sample.y


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): _output = argument.trim_prefix("--output=")
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Requires native rendered game and -- --output=absolute-directory")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_factor = 1.0
	get_window().grab_focus()
	get_window().focus_exited.connect(func() -> void: _report.focus_events.append({"seconds": _elapsed(), "focused": false}))
	get_window().focus_entered.connect(func() -> void: _report.focus_events.append({"seconds": _elapsed(), "focused": true}))
	GameManager.guided_opening_enabled = false
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_population_limit = 40
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.audio_enabled = true
	GameManager.master_volume = 0.8
	GameManager.sfx_volume = 0.75
	GameManager.ui_alert_volume = 0.9
	GameManager.sfx_muted = false
	GameManager.ui_alert_muted = false
	AudioManager.apply_preferences()
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 1.0
	AudioServer.add_bus_effect(0, _capture)
	_start_ms = Time.get_ticks_msec()
	_recording = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null: break
		await get_tree().process_frame
	if _main.get("_building_placement") == null:
		_report.failures.append("Main initialization timed out")
		_finish()
		return
	_main.ai_controller.set_process(false)
	_main.ai_controller.get("_decision_timer").stop()
	GameManager.game_speed = 1.0
	Engine.time_scale = 1.0
	_phase("economy_start")
	var map: Node2D = _main.game_map
	var buildings: Array = _main.get("_player_buildings")[0]
	var tc: BuildingBase = buildings[0]
	map.selection_mgr.select_single(tc)
	ResourceManager.initialize_player(0, {"food": 1000, "wood": 1000, "gold": 500})
	_main.call("_on_train_unit_requested", tc, UnitData.UnitType.VILLAGER)
	await get_tree().create_timer(0.5).timeout
	# Use the existing placement validity/payment/worker assignment path.
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	var placement: BuildingPlacement = _main.get("_building_placement")
	var spawn: Vector2i = map.map_generator.spawn_positions[0]
	var found: bool = false
	for x: int in range(-5, 6):
		if found: break
		for y: int in range(-5, 6):
			placement.update_preview_at_world(map.tile_to_world(spawn + Vector2i(x, y)))
			if placement.is_valid_placement:
				placement.confirm_preview()
				found = true
				break
	if not found: _report.failures.append("No legal house site")
	await get_tree().create_timer(2.0).timeout
	await _screenshot("economy.png")
	await get_tree().create_timer(22.0).timeout
	_phase("economy_end")
	# Free, explicit scenario staging: no modified attacks, stats or time scale.
	var center: Vector2 = map.tile_to_world(Vector2i(36, 36))
	map.note_camera_interaction()
	map.set("_user_zoom_override", true)
	map.camera.position = center
	map.camera.zoom = Vector2(0.90, 0.90)
	map.camera.reset_smoothing()
	var armies: Array = [[], []]
	for owner: int in 2:
		GameManager.grant_population_cap(owner, 900000 + owner, 40)
		for index: int in 12:
			var kind: int = UnitData.UnitType.INFANTRY if index < 6 else (UnitData.UnitType.ARCHER if index < 10 else UnitData.UnitType.CAVALRY)
			var position: Vector2 = center + Vector2((-130.0 if owner == 0 else 130.0) + (index % 3) * 24.0, (index / 3) * 26.0 - 40.0)
			var unit: UnitBase = _main.call("_spawn_unit", kind, owner, position)
			if unit == null:
				_report.failures.append("Staged spawn rejected")
				continue
			unit.attack_landed.connect(func(_a: UnitBase, _d: UnitBase, _hp: float, _bonus: float) -> void: _hits += 1)
			armies[owner].append(unit)
	await get_tree().create_timer(0.5).timeout
	var selected: Array[Node2D] = []
	for unit: UnitBase in armies[0]: selected.append(unit)
	map.selection_mgr.call("select_units", selected) if map.selection_mgr.has_method("select_units") else map.selection_mgr.select_single(armies[0][0])
	for owner: int in 2:
		for unit: UnitBase in armies[owner]: unit.command_attack_move(center)
	AudioManager.play_ui("command_attack")
	_phase("battle_start")
	await get_tree().create_timer(5.0).timeout
	await _screenshot("battle.png")
	await get_tree().create_timer(20.0).timeout
	_phase("battle_end")
	_report.attack_landed_events = _hits
	if _hits < 20: _report.failures.append("Busy battle produced fewer than 20 actual hits")
	AudioManager.stop_all()
	await get_tree().create_timer(0.4).timeout
	_finish()


func _phase(name: String) -> void:
	_report.phases.append({"name": name, "seconds": _elapsed(), "audio": AudioManager.get_audio_diagnostics(), "game_seconds": GameManager.game_time, "focused": get_window().has_focus()})


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _start_ms) / 1000.0


func _screenshot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_output.path_join(filename))


func _finish() -> void:
	_process(0.0)
	_recording = false
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(AudioServer.get_mix_rate())
	wav.stereo = true
	var data := PackedByteArray()
	data.resize(_frames.size() * 4)
	for i: int in _frames.size():
		data.encode_s16(i * 4, int(clampf(_frames[i].x, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(_frames[i].y, -1.0, 1.0) * 32767.0))
	wav.data = data
	wav.save_to_wav(_output.path_join("gameplay-mix.wav"))
	_report.frames = _frames.size()
	_report.mix_rate = wav.mix_rate
	_report.duration_seconds = float(_frames.size()) / wav.mix_rate
	_report.peak = _sample_peak
	_report.rms = sqrt(_sum_squares / maxf(1.0, _frames.size() * 2.0))
	_report.discarded_capture_frames = _capture.get_discarded_frames()
	_report.audio_driver = AudioServer.get_driver_name()
	_report.final_audio = AudioManager.get_audio_diagnostics()
	if _sample_peak <= 0.00001: _report.failures.append("Captured signal is silent")
	if _sample_peak >= 0.99: _report.failures.append("Captured signal approaches clipping")
	var file := FileAccess.open(_output.path_join("gameplay-audio.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	print("[AUDIO CAPTURE] " + JSON.stringify(_report))
	get_tree().quit(0 if _report.failures.is_empty() else 1)
