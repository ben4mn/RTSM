extends SceneTree
## Exercises the same menu-button scene transition used by the Web build.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MAIN_SCENE := "res://scenes/main/main.tscn"
const READY_FRAME_LIMIT := 900
const GAME_STATE_PLAYING := 2

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_manager: Node = root.get_node("GameManager")
	var audio_manager: Node = root.get_node("AudioManager")
	# MainMenu applies the saved preference during _ready(), so set the test-owned
	# preference before instantiation instead of letting it re-enable one-shots.
	game_manager.set("audio_enabled", false)
	audio_manager.call("set_all_enabled", false)

	var menu: Control = (load(MENU_SCENE) as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame

	var start_button: Button = menu.get_node("CenterContainer/VBox/ActionsRow/StartButton")
	start_button.pressed.emit()
	# The menu must survive until the current input dispatch has unwound. A
	# synchronous scene removal leaves Viewport's touch/mouse focus referencing a
	# detached Control and produces Node.can_process() errors in Web exports.
	if current_scene != menu or not menu.is_inside_tree():
		_failures.append("Start Skirmish removed the focused menu synchronously")
	if not start_button.disabled:
		_failures.append("Start Skirmish remained enabled during the deferred transition")
	if not await _wait_for(func() -> bool:
		return (
			current_scene != null
			and current_scene.scene_file_path == MAIN_SCENE
			and int(game_manager.get("current_state")) == GAME_STATE_PLAYING
		)
	):
		_failures.append("Start Skirmish did not reach a PLAYING main scene")

	await process_frame
	await process_frame
	if is_instance_valid(current_scene):
		current_scene.free()
		current_scene = null
	await process_frame
	if _failures.is_empty():
		print("[PASS] menu_match_transition: Start Skirmish reached a ready match")
		quit(0)
	else:
		for failure in _failures:
			push_error("[FAIL] menu_match_transition: %s" % failure)
		quit(1)


func _wait_for(predicate: Callable) -> bool:
	for _frame in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await process_frame
	return false
