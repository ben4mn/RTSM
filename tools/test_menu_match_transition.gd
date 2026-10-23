extends SceneTree
## Exercises the same menu-button scene transition used by the Web build.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MAIN_SCENE := "res://scenes/main/main.tscn"
const READY_FRAME_LIMIT := 900
const GAME_STATE_PLAYING := 2
const PREFERENCES_PATH := "user://preferences.cfg"

var _failures: Array[String] = []
var _had_preferences: bool = false
var _preferences_before: PackedByteArray = PackedByteArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_had_preferences = FileAccess.file_exists(PREFERENCES_PATH)
	if _had_preferences:
		_preferences_before = FileAccess.get_file_as_bytes(PREFERENCES_PATH)
	var game_manager: Node = root.get_node("GameManager")
	var audio_manager: Node = root.get_node("AudioManager")
	# MainMenu applies the saved preference during _ready(), so set the test-owned
	# preference before instantiation instead of letting it re-enable one-shots.
	game_manager.set("audio_enabled", false)
	game_manager.set("guided_opening_enabled", false)
	game_manager.set("selected_map_seed", 424242)
	audio_manager.call("set_all_enabled", false)

	var menu: Control = (load(MENU_SCENE) as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame

	menu.call("_open_new_game", "solo")
	var start_button: Button = menu.get("start_button")
	start_button.pressed.emit()
	# The menu must survive until the current input dispatch has unwound. A
	# synchronous scene removal leaves Viewport's touch/mouse focus referencing a
	# detached Control and produces Node.can_process() errors in Web exports.
	if current_scene != menu or not menu.is_inside_tree():
		_failures.append("Start Skirmish removed the focused menu synchronously")
	if not start_button.disabled:
		_failures.append("Start Skirmish remained enabled during the deferred transition")
	if not await _wait_for(func() -> bool: return _is_ready_match()):
		_failures.append("Start Skirmish did not reach a PLAYING main scene")
	else:
		_assert_fresh_hud("first Start")
		var first_match: Node = current_scene
		var resource_manager: Node = root.get_node("ResourceManager")
		var cost: Dictionary = game_manager.call("get_age_up_cost", 0, 2)
		for resource: String in cost:
			resource_manager.call("add_resource", 0, resource, int(cost[resource]) + 100)
		first_match.call("_on_age_up_requested")
		var first_hud: Node = first_match.get_node("HUD")
		if int(game_manager.call("get_player_age", 0)) != 2 or (first_hud.get("age_label") as Label).text != str(game_manager.call("get_age_name", 2)):
			_failures.append("paid advancement did not synchronize the Feudal HUD")
		game_manager.set("game_time", 974.0)
		first_match.call("_on_pause_requested")
		var quit_button: Button = first_hud.get_node("Root/PauseOverlay/PauseMenu/DepartureRow/QuitButton")
		quit_button.pressed.emit()
		if current_scene != first_match or not quit_button.disabled:
			_failures.append("Pause Quit did not defer and lock its transition")
		if not await _wait_for(func() -> bool: return current_scene != null and current_scene.scene_file_path == MENU_SCENE):
			_failures.append("Pause Quit did not return to Main Menu")
		else:
			var next_menu: Node = current_scene
			next_menu.call("_open_new_game", "solo")
			var next_start: Button = next_menu.get("start_button")
			next_start.pressed.emit()
			if current_scene != next_menu or not next_start.disabled:
				_failures.append("second Start did not defer and lock its transition")
			if not await _wait_for(func() -> bool: return _is_ready_match()):
				_failures.append("Main Menu -> Start did not reach a fresh match")
			else:
				_assert_fresh_hud("Feudal Pause Quit -> Main Menu -> Start")

	await process_frame
	await process_frame
	if is_instance_valid(current_scene):
		paused = false
		current_scene.free()
		current_scene = null
	await process_frame
	if _had_preferences:
		var preferences: FileAccess = FileAccess.open(PREFERENCES_PATH, FileAccess.WRITE)
		if preferences != null:
			preferences.store_buffer(_preferences_before)
			preferences.close()
		else:
			_failures.append("could not restore test-owned preference writes")
	elif FileAccess.file_exists(PREFERENCES_PATH):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES_PATH)) != OK:
			_failures.append("could not remove test-created preference file")
	if _failures.is_empty():
		print("[PASS] menu_match_transition: deferred Start, paid Feudal, Pause Quit and immediate fresh HUD/progression")
		quit(0)
	else:
		for failure in _failures:
			push_error("[FAIL] menu_match_transition: %s" % failure)
		quit(1)


func _is_ready_match() -> bool:
	return (
		current_scene != null
		and current_scene.scene_file_path == MAIN_SCENE
		and int(root.get_node("GameManager").get("current_state")) == GAME_STATE_PLAYING
		and current_scene.get("_building_placement") != null
	)


func _assert_fresh_hud(context: String) -> void:
	var game_manager: Node = root.get_node("GameManager")
	var resource_manager: Node = root.get_node("ResourceManager")
	var hud: Node = current_scene.get_node("HUD")
	if int(game_manager.call("get_player_age", 0)) != 1 or (hud.get("age_label") as Label).text != str(game_manager.call("get_age_name", 1)):
		_failures.append("%s: initial age and HUD disagree" % context)
	var cost: Dictionary = game_manager.call("get_age_up_cost", 0, 2)
	var preview: String = (hud.get("age_up_button") as Button).tooltip_text
	if not preview.contains(str(game_manager.call("get_age_name", 2))) or not preview.contains("%d food" % int(cost.get("food", 0))) or not preview.contains("%d gold" % int(cost.get("gold", 0))):
		_failures.append("%s: initial age action target/cost preview is stale" % context)
	var resources: Dictionary = resource_manager.call("get_all_resources", 0)
	var starting: Dictionary = resource_manager.get_script().get_script_constant_map().get("STARTING_RESOURCES")
	if resources != starting or (hud.get("_resource_values") as Dictionary) != resources:
		_failures.append("%s: initial bank and HUD disagree" % context)
	var player: Dictionary = (game_manager.get("players") as Dictionary)[0]
	if int(player.get("population", 0)) != 4 or int(player.get("population_reserved", -1)) != 0 or int(hud.get("_population_current")) != int(game_manager.call("get_committed_population", 0)) or int(hud.get("_population_cap")) != int(player.get("population_cap", 0)):
		_failures.append("%s: initial population and HUD disagree" % context)
	if float(game_manager.get("game_time")) >= 1.0 or (hud.get("game_time_label") as Label).text != str(game_manager.call("get_formatted_time")) or paused:
		_failures.append("%s: initial clock or pause state is stale" % context)
	var build_menu: Node = current_scene.get("_build_menu")
	var range_card: Button = (build_menu.get("_button_map") as Dictionary).get(3) as Button
	if int(build_menu.get("_current_age")) != 1 or range_card == null or not bool(range_card.get_meta("age_locked", false)) or not range_card.disabled:
		_failures.append("%s: initial Archery Range lock is stale" % context)


func _wait_for(predicate: Callable) -> bool:
	for _frame in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await process_frame
	return false
