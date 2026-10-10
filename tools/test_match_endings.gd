extends SceneTree
## Headless integration scenarios for match conclusion and post-game navigation.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const READY_FRAME_LIMIT := 900
const GAME_STATE_MENU := 0
const GAME_STATE_PLAYING := 2
const GAME_STATE_GAME_OVER := 4
const PREFERENCES_PATH := "user://preferences.cfg"
const BUILDING_ARCHERY_RANGE := 3
const UNIT_ARCHER := 2

var _scenario: String = "victory_menu"
var _failures: Array[String] = []
var _had_preferences: bool = false
var _preferences_before: PackedByteArray = PackedByteArray()


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="):
			_scenario = argument.trim_prefix("--scenario=")
	call_deferred("_run")


func _run() -> void:
	_had_preferences = FileAccess.file_exists(PREFERENCES_PATH)
	if _had_preferences:
		_preferences_before = FileAccess.get_file_as_bytes(PREFERENCES_PATH)
	if _scenario not in ["victory_menu", "elimination_menu", "defeat_restart", "pause_quit"]:
		_fail("unknown scenario %s" % _scenario)
		_finish()
		return

	var packed: PackedScene = load(MAIN_SCENE)
	var game_manager: Node = root.get_node("GameManager")
	var audio_manager: Node = root.get_node("AudioManager")
	game_manager.set("audio_enabled", false)
	game_manager.set("guided_opening_enabled", false)
	game_manager.set("selected_map_seed", 424242)
	audio_manager.call("set_all_enabled", false)
	var match_scene: Node = packed.instantiate()
	root.add_child(match_scene)
	current_scene = match_scene
	if not await _wait_for(func() -> bool: return _is_ready_match()):
		_fail("match did not reach PLAYING")
		_finish()
		return
	_assert_fresh_match(match_scene, "initial match")
	if _scenario == "pause_quit":
		match_scene.call("_on_pause_requested")
		await process_frame
		var hud: CanvasLayer = match_scene.get_node("HUD") as CanvasLayer
		var quit_button: Button = hud.get_node("Root/PauseOverlay/PauseMenu/QuitButton") as Button
		quit_button.pressed.emit()
		if current_scene != match_scene or not match_scene.is_inside_tree():
			_fail("Pause Quit removed the focused match synchronously")
		if not quit_button.disabled:
			_fail("Pause Quit remained enabled during the deferred transition")
		if not await _wait_for(func() -> bool: return current_scene != null and current_scene.scene_file_path == MENU_SCENE):
			_fail("Pause Quit did not load %s" % MENU_SCENE)
		elif int(game_manager.get("current_state")) != GAME_STATE_MENU:
			_fail("Pause Quit left GameManager outside MENU")
		await process_frame
		_finish()
		return

	# Reproduce the restart defect with a real paid human advancement, so the
	# previous match's Feudal state is still present when the next HUD is ready.
	var resource_manager: Node = root.get_node("ResourceManager")
	var age_cost: Dictionary = game_manager.call("get_age_up_cost", 0, 2)
	for resource: String in age_cost:
		resource_manager.call("add_resource", 0, resource, int(age_cost[resource]) + 100)
	var resources_before_age: Dictionary = resource_manager.call("get_all_resources", 0)
	match_scene.call("_on_age_up_requested")
	_assert_progression(match_scene, 2, "paid Feudal advancement")
	for resource: String in age_cost:
		if int(resource_manager.call("get_resource", 0, resource)) != int(resources_before_age[resource]) - int(age_cost[resource]):
			_fail("paid advancement did not spend the authoritative %s cost" % resource)
	var human_tc: Node2D = match_scene.get("_player_town_center") as Node2D
	match_scene.call("_on_train_unit_requested", human_tc, 0)
	if int(game_manager.call("get_reserved_population", 0)) != 1:
		_fail("previous match failed to reserve population for the queued Villager")
	game_manager.set("game_time", 974.0)
	var winner_id: int = 1 if _scenario == "defeat_restart" else 0
	var expected_result: String = "VICTORY" if winner_id == 0 else "DEFEAT"
	var sacred_site: Node = match_scene.get_node("GameMap").get("sacred_site")
	var sacred_hold: float = float(sacred_site.get("victory_hold_time"))
	var expected_reason: String = "Sacred Site held for %s" % str(match_scene.call("_format_duration_seconds", sacred_hold))
	if _scenario == "elimination_menu":
		expected_reason = "Town Center destroyed"
	if _scenario in ["victory_menu", "defeat_restart"]:
		# This injects the ending callback, not a full ten-minute simulation.
		match_scene.call("_on_sacred_site_timer_tick", winner_id, 0.0, sacred_hold)
	else:
		var defeated_player_id: int = 0 if _scenario == "defeat_restart" else 1
		var player_buildings: Array = (match_scene.get("_player_buildings") as Array)[defeated_player_id]
		var town_center: Node2D = null
		for building in player_buildings:
			if int(building.get("building_type")) == 0:
				town_center = building as Node2D
				break
		if town_center == null:
			_fail("player %d Town Center unavailable for destruction scenario" % defeated_player_id)
			_finish()
			return
		var game_map: Node = match_scene.get_node("GameMap")
		var tile_position: Vector2i = game_map.call("world_to_tile", town_center.global_position)
		match_scene.call("_on_building_destroyed", town_center, defeated_player_id, tile_position)
	await process_frame

	var game_over: Node = match_scene.get_node_or_null("GameOverScreen")
	if game_over == null:
		_fail("game-over overlay was not created")
		_finish()
		return
	var summary: Dictionary = match_scene.get("match_summary_diagnostics")
	if int(summary.get("winner_id", -1)) != winner_id:
		_fail("summary winner mismatch: %s" % summary.get("winner_id", "missing"))
	if str(summary.get("victory_reason", "")) != expected_reason:
		_fail("summary reason mismatch: %s" % summary.get("victory_reason", "missing"))
	var result_label: Label = game_over.get_node("GameOverPanel/Margin/VBox/ResultLabel")
	if result_label.text != expected_result:
		_fail("result label mismatch: %s" % result_label.text)
	if int(game_manager.get("current_state")) != GAME_STATE_GAME_OVER:
		_fail("GameManager did not enter GAME_OVER")
	match_scene.call("_conclude_match", 1 - winner_id, "Late duplicate ending")
	await process_frame
	var overlay_count: int = 0
	for child in match_scene.get_children():
		if child.name == "GameOverScreen":
			overlay_count += 1
	if overlay_count != 1:
		_fail("duplicate conclusion created %d overlays" % overlay_count)
	var stable_summary: Dictionary = match_scene.get("match_summary_diagnostics")
	if int(stable_summary.get("winner_id", -1)) != winner_id or str(stable_summary.get("victory_reason", "")) != expected_reason:
		_fail("duplicate conclusion overwrote the first result")

	var old_match_id: int = match_scene.get_instance_id()
	if _scenario != "defeat_restart":
		var menu_button: Button = game_over.get_node("GameOverPanel/Margin/VBox/ButtonRow/MainMenuButton")
		menu_button.pressed.emit()
		if current_scene != match_scene or not match_scene.is_inside_tree():
			_fail("game-over Main Menu removed the focused match synchronously")
		if not menu_button.disabled:
			_fail("game-over Main Menu remained enabled during the deferred transition")
		if not await _wait_for(func() -> bool: return current_scene != null and current_scene.scene_file_path == MENU_SCENE):
			_fail("Main Menu action did not load %s" % MENU_SCENE)
		elif int(game_manager.get("current_state")) != GAME_STATE_MENU:
			_fail("Main Menu action left GameManager outside MENU")
		else:
			var new_menu: Control = current_scene as Control
			var start_button: Button = new_menu.get_node("CenterContainer/VBox/ActionsRow/StartButton")
			start_button.pressed.emit()
			if current_scene != new_menu or not start_button.disabled:
				_fail("Main Menu Start did not defer and lock its transition")
			if not await _wait_for(func() -> bool: return _is_ready_match() and current_scene.get_instance_id() != old_match_id):
				_fail("Main Menu -> Start did not reach a fresh ready match")
			else:
				_assert_fresh_match(current_scene, "Main Menu -> Start")
	else:
		var restart_button: Button = game_over.get_node("GameOverPanel/Margin/VBox/ButtonRow/PlayAgainButton")
		restart_button.pressed.emit()
		if current_scene != match_scene or not match_scene.is_inside_tree():
			_fail("Play Again removed the focused match synchronously")
		if not restart_button.disabled:
			_fail("Play Again remained enabled during the deferred transition")
		if not await _wait_for(func() -> bool: return current_scene != null and current_scene.scene_file_path == MAIN_SCENE and current_scene.get_instance_id() != old_match_id):
			_fail("Play Again did not reload a new match scene")
		elif not await _wait_for(func() -> bool: return _is_ready_match()):
			_fail("restarted match did not return to PLAYING")
		else:
			_assert_fresh_match(current_scene, "Play Again")

	await process_frame
	await process_frame
	_finish()


func _is_ready_match() -> bool:
	return (
		current_scene != null
		and current_scene.scene_file_path == MAIN_SCENE
		and int(root.get_node("GameManager").get("current_state")) == GAME_STATE_PLAYING
		and current_scene.get("_building_placement") != null
		and not (current_scene.get("_player_buildings") as Array)[0].is_empty()
	)


func _assert_progression(match_scene: Node, expected_age: int, context: String) -> void:
	var game_manager: Node = root.get_node("GameManager")
	var hud: Node = match_scene.get_node("HUD")
	var actual_age: int = int(game_manager.call("get_player_age", 0))
	if actual_age != expected_age or (hud.get("age_label") as Label).text != str(game_manager.call("get_age_name", actual_age)):
		_fail("%s: authoritative age and HUD label disagree" % context)
	var age_button: Button = hud.get("age_up_button") as Button
	var next_cost: Dictionary = game_manager.call("get_age_up_cost", 0, actual_age + 1)
	var preview: String = age_button.tooltip_text
	if not preview.contains(str(game_manager.call("get_age_name", actual_age + 1))):
		_fail("%s: age action preview names the wrong next age" % context)
	if not preview.contains("%d food" % int(next_cost.get("food", 0))) or not preview.contains("%d gold" % int(next_cost.get("gold", 0))):
		_fail("%s: age action preview uses stale costs" % context)
	var build_menu: Node = match_scene.get("_build_menu")
	if int(build_menu.get("_current_age")) != actual_age:
		_fail("%s: build palette age disagrees with GameManager" % context)
	var cards: Dictionary = build_menu.get("_button_map")
	var range_card: Button = cards.get(BUILDING_ARCHERY_RANGE) as Button
	if range_card == null or bool(range_card.get_meta("age_locked", false)) != (actual_age < 2):
		_fail("%s: Archery Range has the wrong age lock" % context)


func _assert_fresh_match(match_scene: Node, context: String) -> void:
	var game_manager: Node = root.get_node("GameManager")
	var resource_manager: Node = root.get_node("ResourceManager")
	var hud: Node = match_scene.get_node("HUD")
	_assert_progression(match_scene, 1, context)
	var resources: Dictionary = resource_manager.call("get_all_resources", 0)
	var starting: Dictionary = resource_manager.get_script().get_script_constant_map().get("STARTING_RESOURCES")
	if resources != starting or (hud.get("_resource_values") as Dictionary) != resources:
		_fail("%s: resources or HUD bank did not reset to starting stock" % context)
	var player: Dictionary = (game_manager.get("players") as Dictionary)[0]
	if int(player.get("population", 0)) != 4 or int(player.get("population_reserved", -1)) != 0:
		_fail("%s: starting population or reservations did not reset" % context)
	if int(hud.get("_population_current")) != int(game_manager.call("get_committed_population", 0)) or int(hud.get("_population_cap")) != int(player.get("population_cap", 0)):
		_fail("%s: HUD population differs from authoritative state" % context)
	if float(game_manager.get("game_time")) >= 1.0 or (hud.get("game_time_label") as Label).text != str(game_manager.call("get_formatted_time")):
		_fail("%s: initial clock is stale" % context)
	if paused:
		_fail("%s: fresh match retained paused state" % context)
	var range_card: Button = (match_scene.get("_build_menu").get("_button_map") as Dictionary)[BUILDING_ARCHERY_RANGE]
	if not range_card.disabled:
		_fail("%s: locked Archery Range card remains actionable" % context)
	match_scene.call("_select_town_center")
	var train_buttons: HBoxContainer = hud.get("_train_buttons_container") as HBoxContainer
	var train_types: Array[int] = []
	for button: Button in train_buttons.get_children():
		if not button.has_meta("unit_type") or button.is_queued_for_deletion() or not button.visible:
			continue
		train_types.append(int(button.get_meta("unit_type")))
		if int(button.get_meta("unit_type")) == UNIT_ARCHER:
			_fail("%s: fresh Town Center exposes Archer training" % context)
	if train_types != [0, 4]:
		_fail("%s: Town Center did not restore Villager/Scout training choices" % context)
	var before_locked_train: Dictionary = resource_manager.call("get_all_resources", 0)
	match_scene.call("_on_train_unit_requested", match_scene.get("_player_town_center"), UNIT_ARCHER)
	if str(match_scene.get("_last_train_request_result")) != "unit_unavailable" or (resource_manager.call("get_all_resources", 0) as Dictionary) != before_locked_train:
		_fail("%s: fresh Town Center accepted unavailable Archer training or spent resources" % context)
	var before_failed_age: Dictionary = resource_manager.call("get_all_resources", 0)
	match_scene.call("_on_age_up_requested")
	if int(game_manager.call("get_player_age", 0)) != 1 or (resource_manager.call("get_all_resources", 0) as Dictionary) != before_failed_age:
		_fail("%s: initial stock advanced age or spent despite shortage" % context)


func _wait_for(predicate: Callable) -> bool:
	for _frame in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await process_frame
	return false


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[FAIL] match_ending_%s: %s" % [_scenario, message])


func _finish() -> void:
	paused = false
	if is_instance_valid(current_scene):
		current_scene.free()
		current_scene = null
	if _had_preferences:
		var preferences: FileAccess = FileAccess.open(PREFERENCES_PATH, FileAccess.WRITE)
		if preferences != null:
			preferences.store_buffer(_preferences_before)
			preferences.close()
		else:
			_fail("could not restore test-owned preference writes")
	elif FileAccess.file_exists(PREFERENCES_PATH):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES_PATH)) != OK:
			_fail("could not remove test-created preference file")
	if _failures.is_empty():
		var coverage: String = "pause, deferred Quit and initial HUD/progression" if _scenario == "pause_quit" else "result, navigation, paid Feudal and immediate fresh-match HUD/progression"
		print("[PASS] match_ending_%s: %s" % [_scenario, coverage])
		quit(0)
	else:
		quit(1)
