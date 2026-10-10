extends SceneTree
## Tutorial exit must retire a previously visible banner and preserve preferences.

var _failures: Array[String] = []
var _preferences_existed: bool = false
var _preferences_bytes: PackedByteArray


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	root.get_node("AudioManager").call("set_all_enabled", false)
	_preferences_existed = FileAccess.file_exists("user://preferences.cfg")
	if _preferences_existed:
		_preferences_bytes = FileAccess.get_file_as_bytes("user://preferences.cfg")
	gm.set("selected_map_seed", 424242)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		gm.set("guided_opening_enabled", true)
		var main: Node = await _start_match()
		var hud: Node = main.get_node("HUD")
		_expect(str(hud.get("_progression_hint_label").text).begins_with("1 / 4"), "%s fresh guidance starts at step one" % dimensions)
		# Display the real final instruction, then finish via its accepted move command.
		main.set("_guided_stage", 3)
		main.set("_opening_gather_complete", true)
		main.set("_opening_house_complete", true)
		main.set("_opening_scout_queued", true)
		var map: Node = main.get_node("GameMap")
		var scout: Node2D = main.call("_spawn_unit", 4, 0, main.get("_player_units")[0][0].global_position)
		map.get("selection_mgr").call("select_single", scout)
		main.call("_update_progression_hint")
		_expect(hud.get("_progression_hint_panel").visible, "%s final instruction is initially visible" % dimensions)
		main.call("_on_move_command", scout.global_position + Vector2(32, 16))
		await process_frame
		await process_frame
		_expect(not bool(main.get("_guided_opening_active")), "%s accepted military move completes guidance" % dimensions)
		_expect(bool(gm.get("guided_opening_enabled")), "completion preserves guided preference")
		_check_cleared(main, str(dimensions) + " completion")
		await _check_stays_cleared(main)
		main.free()
		current_scene = null
		await process_frame

		main = await _start_match()
		hud = main.get_node("HUD")
		_expect(str(hud.get("_progression_hint_label").text).begins_with("1 / 4"), "%s replay guidance starts at step one" % dimensions)
		main.call("_apply_primary_guidance", "2 / 4 · Choose the House in Economy.", "build_button", -1, 1, true)
		main.get("_build_menu").call("set_recommended_building", 1)
		hud.get("_guidance_dismiss_button").pressed.emit()
		_expect(not bool(gm.get("guided_opening_enabled")), "Skip preserves intentional disabled preference")
		var saved := ConfigFile.new()
		_expect(saved.load("user://preferences.cfg") == OK and not bool(saved.get_value("onboarding", "guided_opening", true)), "Skip saves disabled preference")
		_check_cleared(main, str(dimensions) + " skip")
		await _check_stays_cleared(main)
		main.free()
		current_scene = null
		await process_frame

		main = await _start_match()
		_expect(not bool(main.get("_guided_opening_active")), "new match respects skipped preference")
		_check_cleared(main, "new unguided match")
		main.free()
		current_scene = null
		await process_frame
	_restore_preferences()
	if _failures.is_empty():
		print("[PASS] guidance_cleanup: complete, Skip, repeat refresh and fresh preferences at 1280x720 and 844x390")
		quit(0)
	else:
		quit(1)


func _start_match() -> Node:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for _frame in range(900):
		if main.get("_building_placement") != null:
			break
		await process_frame
	await process_frame
	main.call("_update_progression_hint")
	return main


func _check_cleared(main: Node, context: String) -> void:
	var hud: Node = main.get_node("HUD")
	_expect(not hud.get("_progression_hint_panel").visible, context + ": banner hidden")
	_expect(hud.get("_progression_hint_label").text == "", context + ": obsolete text removed")
	_expect(not hud.get("_guidance_dismiss_button").visible, context + ": Skip hidden")
	_expect(hud.get("_primary_action_focus") == "" and int(hud.get("_primary_action_unit_type")) == -1 and int(hud.get("_primary_action_building_type")) == -1, context + ": interaction targets cleared")
	_expect(not bool(hud.get("_pending_military_shortcut")) and not bool(hud.get("_guided_military_shortcuts_visible")), context + ": tutorial shortcuts cleared")
	_expect(main.get("_first_session_hint_text") == "" and not bool(main.get("_first_session_hint_emphasis")), context + ": text/emphasis telemetry cleared")
	var style: StyleBoxFlat = hud.get("_progression_hint_panel").get_theme_stylebox("panel")
	_expect(style.border_width_left == 1, context + ": emphasis border cleared")
	_expect(int(main.get("_build_menu").get("_recommended_building_type")) == -1, context + ": House recommendation cleared")


func _check_stays_cleared(main: Node) -> void:
	main.call("_on_pause_requested")
	await process_frame
	main.call("_on_resume_requested")
	root.get_node("ResourceManager").call("add_resource", 0, "food", 1)
	main.get_node("GameMap").get("selection_mgr").call("deselect_all")
	for _frame in range(4):
		await process_frame
		main.call("_update_progression_hint")
	_check_cleared(main, "subsequent updates")


func _restore_preferences() -> void:
	if _preferences_existed:
		var file := FileAccess.open("user://preferences.cfg", FileAccess.WRITE)
		file.store_buffer(_preferences_bytes)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://preferences.cfg"))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[FAIL] guidance_cleanup: " + message)
