extends Node
## Actual Main damage routing: camera culling must never discard an owned alert.
## Headless event/scheduler check, not perceived loudness or browser evidence.

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.audio_enabled = true
	GameManager.sfx_muted = false
	GameManager.ui_alert_muted = false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for _frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	_expect(main.get("_building_placement") != null, "Main initialized")
	if main.get("_building_placement") == null:
		_finish()
		return
	main.set_process(false)
	main.ai_controller.set_process(false)
	main.ai_controller.get("_decision_timer").stop()
	var map: Node2D = main.game_map
	var center: BuildingBase = main.get("_player_town_center")
	var own: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, center.global_position + Vector2(36, 0))
	var enemy: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 1, map.tile_to_world(Vector2i(55, 55)))
	own.set_process(false)
	enemy.set_process(false)
	map.note_camera_interaction()
	map.camera.position = center.global_position + Vector2(5000, 5000)
	map.camera.reset_smoothing()
	map.camera.force_update_scroll()
	AudioManager.apply_preferences()
	AudioManager.call("_set_backgrounded", false)
	AudioManager.stop_all()
	var feedback: Control = main.get("_battlefield_feedback")
	feedback.fronts.clear()
	_expect(map.is_entity_visible_to_player(own, 0), "Owned damaged unit remains canonically revealed")
	var screen: Vector2 = map.get_viewport().get_canvas_transform() * own.global_position
	_expect(not map.get_viewport().get_visible_rect().grow(80).has_point(screen), "Owned unit is genuinely outside audible camera range")
	var before: Dictionary = AudioManager.get_audio_diagnostics().played
	AudioManager.play_world("attack_hit", own)
	_expect(AudioManager.get_audio_diagnostics().played == before, "Routine offscreen impact is discarded")
	own.take_damage(1)
	_expect(_played("under_attack") == int(before.get("under_attack", 0)) + 1, "Actual offscreen owned unit damage reaches reserved alert channel")
	var alerted: int = _played("under_attack")
	for _hit: int in 10: own.take_damage(1)
	_expect(_played("under_attack") == alerted, "Damage burst cannot turn one front into repeated warnings")
	enemy.take_damage(1)
	_expect(_played("under_attack") == alerted, "Enemy damage never becomes a local ownership alert")
	AudioManager.stop_all()
	feedback.fronts.clear()
	center.take_damage(1)
	_expect(_played("under_attack") == alerted + 1, "Actual offscreen owned building damage reaches alert channel")
	AudioManager.stop_all()
	feedback.fronts.clear()
	AudioManager.set_ui_enabled(false)
	alerted = _played("under_attack")
	own.take_damage(1)
	_expect(_played("under_attack") == alerted, "Explicit alert mute remains respected")
	AudioManager.stop_all()
	main.queue_free()
	await get_tree().process_frame
	_finish()


func _played(cue: String) -> int:
	return int(AudioManager.get_audio_diagnostics().played.get(cue, 0))


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition: _failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] tactical_audio: %d checks; real offscreen owned unit/building damage, quiet routine impacts, burst restraint, owner isolation and alert mute" % _checks)
	else:
		for failure: String in _failures: push_error("[FAIL] tactical_audio: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
