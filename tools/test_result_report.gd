extends Node
## Actual dispatched contacts on the result actions in 12 phone profiles, plus
## the real Main -> private diagnostic bridge with a concluded synthetic match.

const RESULT_SCENE := preload("res://scenes/ui/game_over_screen.tscn")
var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _profile: String = ""
var _contact: int = 700
var _reports: int = 0
var _restarts: int = 0
var _menus: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	PlaytestDiagnostics.reset_for_test()
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _check_profile(phone, interface_scale, notched)
	await _check_real_match_report()
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("result-report-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({
			"scope": "Engine ScreenTouch dispatch; 12 phone/scale/synthetic-safe-area profiles; synthetic concluded match tests report context, not gameplay outcome or physical-device comfort.",
			"profiles": _records, "failures": _failures,
		}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] result_report: " + failure)
	if _failures.is_empty():
		print("[PASS] result_report: 12 phone profiles, all three result actions >=48 logical px, dispatched Report/restart/menu, ended match and private result context preserved")
	get_tree().paused = false
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_profile(phone: Vector2i, interface_scale: float, notched: bool) -> void:
	_profile = "%dx%d-scale%.3f-%s" % [phone.x, phone.y, interface_scale, "notched" if notched else "ordinary"]
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	GameManager.ui_scale = interface_scale
	get_window().content_scale_factor = interface_scale
	await _frames(3)
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var inset := Vector2(44, 18) * logical / Vector2(phone) if notched else Vector2.ZERO
	var safe := Rect2(Vector2(inset.x, 0), logical - Vector2(inset.x * 2, inset.y))
	var screen: CanvasLayer = RESULT_SCENE.instantiate()
	add_child(screen)
	screen.problem_report_requested.connect(func() -> void: _reports += 1)
	screen.restart_requested.connect(func() -> void: _restarts += 1)
	screen.main_menu_requested.connect(func() -> void: _menus += 1)
	var stats: Dictionary = {"game_time": "09:42", "victory_reason": "Sacred Site held for 10:00", "winner_id": 1, "is_victory": false, "learning": {"paid_army": 8, "worker_losses": 3, "objective_contests": 4}}
	screen.show_defeat(stats)
	screen.call("_fit_panel_to_size", logical, safe)
	await _frames(4)
	var panel: Control = screen.get("panel")
	_expect(safe.grow(0.5).encloses(panel.get_global_rect()), "result panel outside safe area")
	var buttons: Dictionary = {}
	for button_name: String in ["PlayAgainButton", "MainMenuButton", "ReportButton"]:
		var button: Button = screen.get_node("GameOverPanel/Margin/VBox/ButtonRow/" + button_name)
		_expect(button.is_visible_in_tree() and button.can_process(), button_name + " unavailable while paused")
		_expect(button.size.x >= 48 and button.size.y >= 48, button_name + " smaller than 48 logical px")
		_expect(button.get_global_rect().size.x >= 48 and button.get_global_rect().size.y >= 48, button_name + " transition shrank its actual touch target")
		_expect(safe.grow(0.5).encloses(button.get_global_rect()), button_name + " outside safe area")
		buttons[button_name] = str(button.get_global_rect())
	var summary: Dictionary = screen.get("summary_diagnostics").duplicate(true)
	var report_button: Button = screen.get("report_button")
	var reports_before: int = _reports
	await _tap(report_button.get_global_rect().get_center())
	_expect(_reports == reports_before + 1, "Report contact did not emit exactly one request")
	_expect(get_tree().paused and screen.visible, "Report left the paused result")
	_expect(screen.get("summary_diagnostics") == summary, "Report changed the result receipt")
	_expect(not report_button.disabled, "Report could not be reopened")
	await _capture()
	var restarts_before: int = _restarts
	await _tap((screen.get("play_again_button") as Button).get_global_rect().get_center())
	_expect(_restarts == restarts_before + 1 and not screen.visible and not get_tree().paused, "Play Again contact did not request restart")
	_expect(report_button.disabled, "Report remained active during restart transition")
	screen.show_victory(stats)
	screen.call("_fit_panel_to_size", logical, safe)
	await _frames(4)
	var menus_before: int = _menus
	await _tap((screen.get("main_menu_button") as Button).get_global_rect().get_center())
	_expect(_menus == menus_before + 1 and not screen.visible and not get_tree().paused, "Main Menu contact did not request exit")
	_expect(report_button.disabled, "Report remained active during menu transition")
	_records.append({"profile": _profile, "safe": str(safe), "buttons": buttons, "report_contact_count": _reports - reports_before})
	screen.free()
	await _frames(2)


func _check_real_match_report() -> void:
	_profile = "real-match-result-report"
	GameManager.selected_map_seed = 424242
	GameManager.selected_match_mode = SkirmishData.MatchMode.QUICK_CONTROL
	GameManager.guided_opening_enabled = false
	var main: Node2D = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await _frames(1)
	_expect(GameManager.current_state == GameManager.GameState.PLAYING, "real match did not reach PLAYING")
	main.call("_conclude_match", 1, "Report fixture: Sacred Site held")
	await _frames(5)
	# A later setup preference and an evicted match_start event must not erase
	# which latched rules produced the ended match being reported.
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	for index: int in PlaytestDiagnostics.MAX_EVENTS:
		PlaytestDiagnostics.record_event("report_fixture_history", {"index": index})
	var screen: CanvasLayer = main.get_node("GameOverScreen")
	var game_map: Node2D = main.get_node("GameMap")
	var selection: SelectionManager = game_map.get("selection_mgr")
	var selected_before: Array = selection.selected.duplicate()
	var summary: Dictionary = main.get("match_summary_diagnostics").duplicate(true)
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var game_seconds: float = GameManager.game_time
	var camera: Camera2D = game_map.get("camera")
	var camera_position: Vector2 = camera.position
	var camera_zoom: Vector2 = camera.zoom
	var before: Dictionary = PlaytestDiagnostics.get_report()
	_expect(before.events[0].kind != "match_start", "fixture failed to evict initial match event")
	await _tap((screen.get("report_button") as Button).get_global_rect().get_center())
	var report: Dictionary = PlaytestDiagnostics.get_report()
	_expect(int(report.counters.get("problem_marked", 0)) == int(before.counters.get("problem_marked", 0)) + 1, "real result Report did not use existing mark_report flow")
	_expect(GameManager.current_state == GameManager.GameState.GAME_OVER and get_tree().paused, "real result Report resumed gameplay")
	_expect(main.get("match_summary_diagnostics") == summary and is_equal_approx(GameManager.game_time, game_seconds), "real result Report altered ended match")
	_expect(ResourceManager.get_all_resources(0) == bank and selection.selected == selected_before, "real result Report altered economy or selection")
	_expect(camera.position == camera_position and camera.zoom == camera_zoom, "real result Report moved the camera")
	var report_context: Dictionary = {}
	var result_context: Dictionary = {}
	for event: Dictionary in report.problem.get("preceding_events", []):
		if event.kind == "report_context": report_context = event.fields
		if event.kind == "match_result": result_context = event.fields
	_expect(report_context.get("entry_point") == "result", "report did not identify result entry point")
	for context: Dictionary in [report_context, result_context]:
		_expect(context.get("match_mode") == SkirmishData.MatchMode.QUICK_CONTROL and context.get("match_mode_name") == SkirmishData.get_mode_name(SkirmishData.MatchMode.QUICK_CONTROL), "latest report event lost the ended match's latched rules")
	_expect(result_context.get("victory_reason") == "Report fixture: Sacred Site held" and result_context.get("winner_id") == 1 and result_context.get("is_victory") == false, "report omitted or changed the concluded result")
	_expect(report.problem.context == before.context and report.problem.context.get("map_seed") == "424242", "report lost original match/seed context")
	var hud: CanvasLayer = main.get_node("HUD")
	for dialog: Node in hud.get_children():
		if dialog is AcceptDialog:
			dialog.free()
	await _frames(2)
	_expect(screen.visible and get_tree().paused, "closing report failed to retain the result")
	main.free()
	get_tree().paused = false
	await _frames(2)


func _tap(position: Vector2) -> void:
	_contact += 1
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = _contact
		event.position = get_viewport().get_final_transform() * position
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(3)


func _capture() -> void:
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(_profile + "-result-report.png"))


func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(_profile + ": " + message)
