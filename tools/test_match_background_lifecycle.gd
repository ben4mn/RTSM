extends Node
## Real scene + paid queue, with synthetic OS/browser lifecycle dispatch.

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 202
	var main: Node2D = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	var guard: Node = main.get("_match_background_guard")
	# Backgrounding during map loading must pause after setup, including the
	# SceneTree flag that the outer GameManager PLAYING transition writes last.
	guard.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PAUSED:
			break
		await get_tree().process_frame
	_expect(GameManager.current_state == GameManager.GameState.PAUSED and get_tree().paused, "background load did not finish paused")
	var hud: CanvasLayer = main.get_node("HUD")
	var resume: Button = hud.get_node("Root/PauseOverlay/PauseMenu/ResumeButton")
	_expect(resume.is_visible_in_tree() and resume.can_process(), "background pause lost actionable Resume")
	resume.pressed.emit()
	_expect(GameManager.current_state == GameManager.GameState.PAUSED, "hidden Resume started the offline match")
	guard.notification(NOTIFICATION_APPLICATION_PAUSED)
	guard.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_expect(guard.backgrounded, "focus-in cleared a still-suspended native app")
	guard.notification(NOTIFICATION_APPLICATION_RESUMED)
	_expect(not guard.backgrounded, "native resume/focus-in did not clear background state")
	_expect(GameManager.current_state == GameManager.GameState.PAUSED and get_tree().paused, "foreground automatically resumed the match")
	resume.pressed.emit()
	await _frames(4)
	_expect(GameManager.current_state == GameManager.GameState.PLAYING and not get_tree().paused, "explicit Resume failed")
	var tc: BuildingBase = main.get("_player_town_center")
	var queue: ProductionQueue = tc.get_production_queue()
	_expect(queue.enqueue_unit(UnitData.UnitType.VILLAGER), "ordinary paid training request failed")
	await _frames(6)
	_expect(queue.current_progress > 0.0, "paid production did not advance before background")
	guard.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var time_before: float = GameManager.game_time
	var progress_before: float = queue.current_progress
	var opens_before: int = main.get("_pause_open_count")
	guard.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(12)
	_expect(GameManager.current_state == GameManager.GameState.PAUSED and get_tree().paused, "native focus-out did not freeze offline play")
	_expect(GameManager.game_time == time_before and queue.current_progress == progress_before, "background pause advanced the clock or paid production")
	_expect(int(main.get("_pause_open_count")) == opens_before, "duplicate background dispatch opened pause again")
	guard.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(4)
	_expect(GameManager.current_state == GameManager.GameState.PAUSED, "focus return resumed without user input")
	resume.pressed.emit()
	await _frames(4)
	_expect(GameManager.game_time > time_before and queue.current_progress > progress_before, "explicit Resume did not restart clock and production")
	# Web canvas/application focus events must not masquerade as tab hiding.
	guard.set("_web_environment", true)
	guard.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	guard.notification(NOTIFICATION_APPLICATION_PAUSED)
	_expect(not guard.backgrounded and GameManager.current_state == GameManager.GameState.PLAYING, "Web control focus loss paused the match")
	guard.call("_on_web_visibility", [true])
	_expect(GameManager.current_state == GameManager.GameState.PAUSED and get_tree().paused, "Web hidden callback did not freeze offline play")
	guard.call("_on_web_visibility", [false])
	_expect(GameManager.current_state == GameManager.GameState.PAUSED, "Web visible callback resumed play")
	resume.pressed.emit()
	# Session flags exercise the exact online/server bypass without opening a
	# socket or claiming this fixture is an online authority integration test.
	for server: bool in [false, true]:
		NetworkSession.online = not server
		NetworkSession.server_mode = server
		guard.call("_on_web_visibility", [true])
		_expect(GameManager.current_state == GameManager.GameState.PLAYING and not get_tree().paused, "background changed online/server match state")
		guard.call("_on_web_visibility", [false])
	NetworkSession.online = false
	NetworkSession.server_mode = false
	for state: int in [GameManager.GameState.MENU, GameManager.GameState.GAME_OVER]:
		GameManager.set_state(state)
		guard.call("_on_web_visibility", [true])
		_expect(GameManager.current_state == state, "background changed a terminal/menu state")
		guard.call("_on_web_visibility", [false])
	main.free()
	GameManager.set_state(GameManager.GameState.MENU)
	for failure: String in _failures:
		push_error("[FAIL] match_background_lifecycle: " + failure)
	if _failures.is_empty():
		print("[PASS] match_background_lifecycle: real scene; background loading; native suspend/focus ordering; paid clock/queue freeze; explicit Resume; Web focus exclusion; online/server bypass; terminal states")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
