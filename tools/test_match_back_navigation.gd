extends Node
## Actual viewport key routing across field, selection, placement and paused UI.

var _failures: Array[String] = []
var _assertions: int = 0
var _had_preferences: bool = false
var _preferences_before: PackedByteArray


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_had_preferences = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_preferences:
		_preferences_before = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	GameManager.audio_enabled = false
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 202
	AudioManager.set_all_enabled(false)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	if main.get("_building_placement") == null:
		_expect(false, "match did not become ready")
		_finish(main)
		return
	(main.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var hud: CanvasLayer = main.get("hud")
	var selection: SelectionManager = (main.get("game_map") as Node).get("selection_mgr")
	var palette: Control = main.get("_build_menu")
	var workers: Array[Node2D] = []
	for unit: Node in get_tree().get_nodes_in_group("units"):
		if unit is Villager and (unit as Villager).player_owner == 0:
			workers.append(unit)
	_expect(not workers.is_empty(), "ordinary opening has no worker for selection checks")
	selection.select_many([workers[0]])
	hud.call("_show_selection_information")
	await _key(KEY_ESCAPE)
	_expect(hud.call("get_secondary_surface_name") == "none", "Escape did not close selection Info")
	_expect(selection.selected.size() == 1 and _playing(), "closing Info also deselected or paused")
	main.call("_arm_move_command")
	await _key(KEY_ESCAPE)
	_expect(not bool(main.get("_move_command_armed")) and selection.selected.size() == 1 and _playing(), "Escape did not cancel only the armed Move")
	main.call("_arm_attack_move_command")
	await _key(KEY_ESCAPE)
	_expect(not bool(main.get("_attack_move_command_armed")) and selection.selected.size() == 1 and _playing(), "Escape did not cancel only armed Attack-move")
	selection.set_touch_area_selection_armed(true)
	await _key(KEY_ESCAPE)
	_expect(not selection.touch_area_selection_armed and selection.selected.size() == 1 and _playing(), "Escape did not cancel only area selection")
	await _key(KEY_ESCAPE)
	_expect(selection.selected.is_empty() and _playing(), "Escape did not deselect before opening match menu")
	await _key(KEY_ESCAPE)
	_expect(_paused(), "Escape with no context did not open match menu")
	await _key(KEY_ESCAPE)
	_expect(_playing(), "Escape did not return from match menu exactly once")

	# The original native reproduction: P pauses; Esc must return to the field.
	await _key(KEY_P)
	_expect(_paused(), "P no longer opens match menu")
	var pause_overlay: Control = hud.get("_pause_overlay")
	var settings: Control = load("res://scripts/ui/settings_panel.gd").open(pause_overlay, true)
	await get_tree().process_frame
	await _key(KEY_ESCAPE)
	_expect(not is_instance_valid(settings) and _paused(), "Settings Escape did not stop at match menu")
	await _key(KEY_ESCAPE)
	_expect(_playing(), "P → Settings → Esc → Esc did not resume")
	await _key(KEY_P)
	settings = load("res://scripts/ui/settings_panel.gd").open(pause_overlay, true)
	await get_tree().process_frame
	await _key(KEY_P)
	_expect(not is_instance_valid(settings) and _paused(), "Settings P changed existing back behavior")
	await _key(KEY_P)
	_expect(_playing(), "P no longer resumes after Settings closes")

	selection.select_many([workers[0]])
	await _key(KEY_B)
	_expect(bool(hud.call("is_build_menu_open")), "B did not open Build")
	hud.call("show_card_information", {"title": "House", "body": "Building information"})
	await _key(KEY_ESCAPE)
	_expect(hud.call("get_secondary_surface_name") == "none" and bool(hud.call("is_build_menu_open")) and _playing(), "Build Info Escape skipped its parent menu")
	await _key(KEY_ESCAPE)
	_expect(not bool(hud.call("is_build_menu_open")) and selection.selected.size() == 1 and _playing(), "Build Escape also deselected or paused")
	await _key(KEY_B)
	palette.call("_on_building_button_pressed", BuildingData.BuildingType.HOUSE)
	await get_tree().process_frame
	_expect(bool(main.get("_placement_active")), "ordinary House preview did not start")
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _key(KEY_ESCAPE)
	_expect(not bool(main.get("_placement_active")) and _playing(), "Escape did not cancel only placement")
	_expect(ResourceManager.get_all_resources(0) == bank, "canceling preview spent resources")

	hud.call("configure_unit_commands", true, true, "Stand Ground")
	for refresh: int in 3:
		hud.call("_refresh_command_icons")
	for pair: Array in [["_pause_button", "[P]"], ["build_menu_button", "[B]"], ["_camera_center_button", "[Space]"], ["_unit_stop_button", "[T]"], ["_unit_patrol_button", "[R]"], ["_unit_stance_button", "[G]"], ["_worker_idle_button", "[.]"], ["_selection_back_button", "[Esc]"]]:
		var button: Button = hud.get(pair[0])
		_expect(button.tooltip_text.count(pair[1]) == 1, "%s lost or duplicated %s after refresh" % pair)
	_expect((hud.get("_unit_stance_button") as Button).tooltip_text.contains("Stand Ground"), "stance hint lost current stance")
	_expect((hud.get("build_menu_button") as Button).accessibility_name == "Build", "shortcut changed concise accessible action name")
	await _key(KEY_P)
	_expect((hud.get("_pause_button") as Button).tooltip_text.contains("[P / Esc]"), "pause icon omitted both return keys")
	await _key(KEY_ESCAPE)

	# Gameplay shortcuts must leave the concluded match and its pause intact.
	GameManager.set_state(GameManager.GameState.GAME_OVER)
	get_tree().paused = true
	var pause_count: int = int(main.get("_pause_open_count"))
	for key: int in [KEY_ESCAPE, KEY_P, KEY_F2]:
		await _key(key)
	_expect(GameManager.current_state == GameManager.GameState.GAME_OVER and get_tree().paused, "back/pause/help changed game-over state")
	_expect(int(main.get("_pause_open_count")) == pause_count and hud.call("get_secondary_surface_name") == "none", "game-over shortcuts opened hidden HUD surfaces")
	_finish(main)


func _key(keycode: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame


func _playing() -> bool:
	return GameManager.current_state == GameManager.GameState.PLAYING and not get_tree().paused


func _paused() -> bool:
	return GameManager.current_state == GameManager.GameState.PAUSED and get_tree().paused


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(message)
		push_error("[FAIL] match_back_navigation: " + message)


func _finish(main: Node) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if _had_preferences:
		var preferences := FileAccess.open(GameManager.PREFERENCES_PATH, FileAccess.WRITE)
		preferences.store_buffer(_preferences_before)
	else:
		DirAccess.remove_absolute(GameManager.PREFERENCES_PATH)
	main.free()
	if _failures.is_empty():
		print("[PASS] match_back_navigation: %d assertions; routed keys, layered Back, nested Settings, P toggle, placement, tooltips and game-over isolation" % _assertions)
	get_tree().quit(0 if _failures.is_empty() else 1)
