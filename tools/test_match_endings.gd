extends SceneTree
## Headless integration scenarios for match conclusion and post-game navigation.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const READY_FRAME_LIMIT := 900
const GAME_STATE_PLAYING := 2
const GAME_STATE_GAME_OVER := 4

var _scenario: String = "victory_menu"
var _failures: Array[String] = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="):
			_scenario = argument.trim_prefix("--scenario=")
	call_deferred("_run")


func _run() -> void:
	if _scenario not in ["victory_menu", "elimination_menu", "defeat_restart"]:
		_fail("unknown scenario %s" % _scenario)
		_finish()
		return

	var packed: PackedScene = load(MAIN_SCENE)
	var game_manager: Node = root.get_node("GameManager")
	var audio_manager: Node = root.get_node("AudioManager")
	audio_manager.call("set_all_enabled", false)
	var match_scene: Node = packed.instantiate()
	root.add_child(match_scene)
	current_scene = match_scene
	if not await _wait_for(func() -> bool: return int(game_manager.get("current_state")) == GAME_STATE_PLAYING and not (game_manager.get("players") as Dictionary).is_empty()):
		_fail("match did not reach PLAYING")
		_finish()
		return

	var winner_id: int = 1 if _scenario == "defeat_restart" else 0
	var expected_result: String = "VICTORY" if winner_id == 0 else "DEFEAT"
	var expected_reason: String = "Sacred Site held for 3:00" if winner_id == 0 else "Town Center destroyed"
	if _scenario == "elimination_menu":
		expected_reason = "Town Center destroyed"
	if _scenario == "victory_menu":
		match_scene.call("_on_sacred_site_timer_tick", 0, 0.0, 180.0)
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
		if not await _wait_for(func() -> bool: return current_scene != null and current_scene.scene_file_path == MENU_SCENE):
			_fail("Main Menu action did not load %s" % MENU_SCENE)
	else:
		var restart_button: Button = game_over.get_node("GameOverPanel/Margin/VBox/ButtonRow/PlayAgainButton")
		restart_button.pressed.emit()
		if not await _wait_for(func() -> bool: return current_scene != null and current_scene.scene_file_path == MAIN_SCENE and current_scene.get_instance_id() != old_match_id):
			_fail("Play Again did not reload a new match scene")
		elif not await _wait_for(func() -> bool: return int(game_manager.get("current_state")) == GAME_STATE_PLAYING and not (game_manager.get("players") as Dictionary).is_empty()):
			_fail("restarted match did not return to PLAYING")

	await process_frame
	await process_frame
	_finish()


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
	if is_instance_valid(current_scene):
		current_scene.free()
		current_scene = null
	if _failures.is_empty():
		print("[PASS] match_ending_%s: result, reason, game state, and navigation" % _scenario)
		quit(0)
	else:
		quit(1)
