extends Node
## Tests real preferences, modal state, viewport layouts, fog and bounded audio.
## This is structural/audio-lifecycle validation, not a listening-quality claim.

var _failures: Array[String] = []
const PHONE_SIZES: Array[Vector2] = [Vector2(844, 390), Vector2(932, 430)]
const SCALES: Array[float] = [1.0, 1.075, 1.15]
const PREFS: Array[String] = ["audio_enabled", "master_volume", "sfx_volume", "sfx_muted", "ui_alert_muted", "ui_alert_volume", "camera_speed_scale", "zoom_sensitivity_scale", "ui_scale", "hold_shortcuts_enabled", "reduced_motion", "reduced_flashes", "clearer_player_markers", "selected_difficulty", "selected_population_limit", "selected_map_seed", "guided_opening_enabled"]
var _saved: Dictionary = {}
var _had_file: bool = false
var _file_contents: PackedByteArray

class FogFixture extends Node2D:
	var revealed: bool = false
	func is_entity_visible_to_player(_entity: Node2D, _owner: int) -> bool:
		return revealed


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for property: String in PREFS:
		_saved[property] = GameManager.get(property)
	_had_file = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_file: _file_contents = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	for physical: Vector2 in PHONE_SIZES:
		for scale_value: float in SCALES:
			for notch: bool in [false, true]:
				await _check_layout(physical, scale_value, notch)
	_check_persistence()
	await _check_audio()
	await _check_match_state()
	for property: String in PREFS:
		GameManager.set(property, _saved[property])
	GameManager.apply_preferences()
	if _had_file:
		var file := FileAccess.open(GameManager.PREFERENCES_PATH, FileAccess.WRITE)
		file.store_buffer(_file_contents)
	else:
		DirAccess.remove_absolute(GameManager.PREFERENCES_PATH)
	AudioManager.stop_all()
	await get_tree().create_timer(0.15, true).timeout
	if _failures.is_empty():
		print("[PASS] audio_settings: 12 phone/safe-area layouts × 4 tabs, live preferences/reload/reset, real paused selection/camera, fog, voice bounds, mute/background lifecycle")
		get_tree().quit(0)
	else:
		for failure: String in _failures: push_error("[FAIL] audio_settings: " + failure)
		get_tree().quit(1)


func _check_layout(physical: Vector2, scale_value: float, notched: bool) -> void:
	var logical := (physical / scale_value).floor()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(logical)
	add_child(viewport)
	var root_control := Control.new()
	root_control.size = logical
	viewport.add_child(root_control)
	var panel: Control = load("res://scripts/ui/settings_panel.gd").open(root_control)
	await get_tree().process_frame
	var safe := Rect2(Vector2.ZERO, logical)
	if notched: safe = Rect2(Vector2(44.0 / scale_value, 0), logical - Vector2(88.0 / scale_value, 18.0 / scale_value))
	panel.call("apply_mobile_layout", logical, safe)
	for section: int in 4:
		panel.call("_show_section", section)
		await get_tree().process_frame
		await get_tree().process_frame
		var card: Control = panel.get("_panel")
		var suffix := "%s %.3f notch=%s tab=%d" % [physical, scale_value, notched, section]
		_expect(safe.grow(0.5).encloses(card.get_global_rect()), "card outside safe area " + suffix)
		for node: Node in panel.find_children("*", "BaseButton", true, false):
			var control := node as Control
			if not control.is_visible_in_tree(): continue
			_expect(control.size.y >= 47.5, "short logical button " + str(control.name) + " " + suffix)
		var scroll: ScrollContainer = panel.get("_scroll")
		_expect(scroll.size.y >= 80, "insufficient scroll area " + suffix)
		if section == 0:
			scroll.scroll_vertical = 1000
			await get_tree().process_frame
			var preview: Control = panel.find_child("AudioPreviewButton", true, false)
			_expect(scroll.get_global_rect().grow(1).intersects(preview.get_global_rect()), "preview unreachable by scroll " + suffix)
		if section == 1:
			var pan: OptionButton = panel.find_child("CameraSpeedScaleOption", true, false)
			pan.item_selected.emit(2)
			_expect(is_equal_approx(GameManager.camera_speed_scale, 1.25), "pan preference has no behavior value")
	panel.free()
	viewport.free()


func _check_persistence() -> void:
	GameManager.master_volume = 0.35
	GameManager.sfx_volume = 0.25
	GameManager.ui_alert_volume = 0.65
	GameManager.zoom_sensitivity_scale = 1.25
	GameManager.reduced_flashes = true
	GameManager.reduced_motion = true
	GameManager.clearer_player_markers = false
	GameManager.selected_map_seed = 712104
	GameManager.save_preferences()
	GameManager.master_volume = 0.9
	GameManager.zoom_sensitivity_scale = 0.75
	GameManager.selected_map_seed = -1
	GameManager.call("_load_preferences")
	_expect(is_equal_approx(GameManager.master_volume, 0.35) and is_equal_approx(GameManager.sfx_volume, 0.25) and is_equal_approx(GameManager.ui_alert_volume, 0.65), "volume persistence")
	_expect(is_equal_approx(GameManager.zoom_sensitivity_scale, 1.25) and GameManager.selected_map_seed == 712104, "controls/setup persistence")
	_expect(GameManager.reduced_flashes and GameManager.reduced_motion and not GameManager.clearer_player_markers, "accessibility persistence")
	GameManager.reset_preferences()
	_expect(is_equal_approx(GameManager.master_volume, 0.8) and GameManager.selected_map_seed == -1 and not GameManager.reduced_motion, "reset defaults")


func _check_audio() -> void:
	GameManager.set_state(GameManager.GameState.PLAYING)
	GameManager.audio_enabled = true
	AudioManager.apply_preferences()
	var fixture := FogFixture.new()
	add_child(fixture)
	var source := Node2D.new()
	fixture.add_child(source)
	var before: Dictionary = AudioManager.get_audio_diagnostics().played
	AudioManager.play_world("gather_wood", source)
	_expect(AudioManager.get_audio_diagnostics().played == before, "hidden world sound disclosed fog")
	fixture.revealed = true
	source.position = Vector2(40, 40)
	AudioManager.play_world("gather_wood", source)
	_expect(int(AudioManager.get_audio_diagnostics().played.get("gather_wood", 0)) > int(before.get("gather_wood", 0)), "visible world cue missing")
	for cue: String in ["button_click", "select_unit", "command_move", "under_attack", "unit_trained", "age_up", "attack_hit", "unit_death", "gather_food", "gather_gold"]:
		for repeat: int in 50: AudioManager.play_sfx(cue)
	var diag: Dictionary = AudioManager.get_audio_diagnostics()
	_expect(int(diag.active_voices) <= 12 and int(diag.peak_active_voices) <= 12, "audio voices exceeded pool")
	_expect(AudioManager.get_child_count() == 12, "audio player accumulation")
	GameManager.set_state(GameManager.GameState.PAUSED)
	_expect(int(AudioManager.get_audio_diagnostics().active_voices) == 0, "pause retained battle sound")
	AudioManager.preview()
	await get_tree().create_timer(0.1, true).timeout
	AudioManager.set_all_enabled(false)
	await get_tree().create_timer(0.8, true).timeout
	_expect(int(AudioManager.get_audio_diagnostics().active_voices) == 0, "muted preview resumed later")
	AudioManager.set_all_enabled(true)
	AudioManager.play_ui("under_attack")
	AudioManager.call("_set_backgrounded", true)
	_expect(int(AudioManager.get_audio_diagnostics().active_voices) == 0, "background retained sound")
	AudioManager.play_ui("under_attack")
	_expect(int(AudioManager.get_audio_diagnostics().active_voices) == 0, "background accepted sound")
	AudioManager.call("_set_backgrounded", false)
	GameManager.set_state(GameManager.GameState.MENU)
	fixture.free()


func _check_match_state() -> void:
	var scene: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(scene)
	for frame: int in 12: await get_tree().process_frame
	var map: Node = scene.get_node("GameMap")
	var selection: Node = map.get("selection_mgr")
	var units: Array = (scene.get("_player_units") as Array)[0]
	_expect(not units.is_empty(), "real match failed to spawn")
	if units.is_empty():
		scene.free()
		return
	selection.call("select_single", units[0])
	var camera: Camera2D = map.get("camera")
	var position_before: Vector2 = camera.position
	var selected_before: Array = (selection.get("selected") as Array).duplicate()
	scene.call("_on_pause_requested")
	var hud: Node = scene.get_node("HUD")
	var pause: Node = hud.get_node("Root/PauseOverlay")
	var panel: Control = load("res://scripts/ui/settings_panel.gd").open(pause, true)
	await get_tree().process_frame
	panel.call("_show_section", 2)
	await get_tree().process_frame
	var flashes: CheckButton = panel.find_child("ReducedFlashesToggle", true, false)
	flashes.toggled.emit(true)
	panel.call("close")
	await get_tree().process_frame
	_expect(get_tree().paused and GameManager.current_state == GameManager.GameState.PAUSED, "settings resumed match")
	_expect(camera.position.is_equal_approx(position_before), "settings moved camera")
	_expect(selection.get("selected") == selected_before, "settings lost selection")
	GameManager.set_state(GameManager.GameState.MENU)
	scene.free()


func _expect(value: bool, message: String) -> void:
	if not value: _failures.append(message)
