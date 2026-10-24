extends "res://tools/test_strategy_first_open.gd"
## Actual touch transitions; transient messages never paint through full sheets.

var _notification_actions: int = 0


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.15]:
			await _notification_journey(phone, interface_scale)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("notification-surface-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Four native natural-layout phone profiles. Actual ScreenTouch transitions; AI/economy held, synthetic toast/raid reports. Existing notification lifetimes retained. No physical-device or paid-match claim.", "profiles": _receipts, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] notification_surface_priority: " + failure)
	if _failures.is_empty():
		print("[PASS] notification_surface_priority: four touch profiles; management/modal suppression survives raid refresh; current messages restore, expired messages stay retired; field action works without world orders; selection/banks preserved")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _notification_journey(phone: Vector2i, interface_scale: float) -> void:
	_profile = "%dx%d-scale%.3f" % [phone.x, phone.y, interface_scale]
	_hud = null
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	GameManager.ui_scale = interface_scale
	get_window().content_scale_factor = interface_scale
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 30
	GameManager.guided_opening_enabled = true
	await _frames(3)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_map = _main.get_node("GameMap")
	_hud = _main.get_node("HUD")
	_selection = _map.get("selection_mgr")
	_main.set_process(false)
	_main.get_node("AIController").set_process(false)
	_main.get_node("AIController").get("_decision_timer").stop()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	var feed: Control = _hud.get("_notification_container")
	var feedback: Control = _main.get("_battlefield_feedback")
	var selected: UnitBase = _main.get("_player_units")[0][0]
	_selection.select_single(selected)
	_main.call("_update_progression_hint")
	await _frames(4)
	var selection_before: Array = _selection.selected.duplicate()
	var banks: Dictionary = ResourceManager.get_all_resources(0)
	_orders = 0
	_notification_actions = 0
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	_selection.gather_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.build_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_hud.call("show_notification", "Current field message", KingdomTheme.TEAL, 30.0)
	await _frames(3)
	_expect(feed.is_visible_in_tree(), "ordinary field message missing")
	await _button(overview.rail.get_node("EconomyButton"))
	_check_hidden(feed, feedback, "Economy")
	_hud.call("show_notification", "Unit trained: Warrior", KingdomTheme.TEAL, 30.0)
	await _frames(3)
	_check_hidden(feed, feedback, "new message under Economy")
	await _capture("economy-no-toast")
	await _button(overview.panel.find_child("CloseStrategyButton", true, false))
	_expect(feed.is_visible_in_tree() and _message(feed) == "Unit trained: Warrior", "current toast did not restore")
	await _button(overview.rail.get_node("ArmyButton"))
	await _button(overview.get("_groups_tab"))
	_check_hidden(feed, feedback, "Army")
	await _button(overview.get("_info_button"))
	_check_hidden(feed, feedback, "Army notes")
	feedback.call("report_attack", "Town Center", selected.global_position + Vector2(800, 0))
	feedback.call("report_attack", "Villager", selected.global_position + Vector2(-800, 0))
	await _frames(4)
	var raid_bounds: Array[Rect2] = feedback.call("get_visible_bounds")
	_expect(raid_bounds.size() == 2, "toast suppression hides a raid")
	for bounds: Rect2 in raid_bounds:
		_expect(not bounds.intersects(overview.panel.get_global_rect()), "sheet covers a raid target")
	_check_hidden(feed, feedback, "active raids under notes")
	await _capture("army-notes-raids")
	(feedback.get("fronts") as Array).clear()
	_check_hidden(feed, feedback, "raid expiry under notes")
	await _button(overview.panel.find_child("CloseStrategyButton", true, false))
	_expect(feed.is_visible_in_tree(), "raid expiry prevents current field feedback")
	await _button(_hud.get("build_menu_button"))
	_check_hidden(feed, feedback, "Build")
	await _action("cancel")
	_expect(feed.is_visible_in_tree(), "closing Build leaves feed hidden")
	await _button(_hud.get("_pause_button"))
	_check_hidden(feed, feedback, "Pause")
	await _button(_hud.get("_pause_overlay").get_node("PauseMenu/ResumeButton"))
	_expect(feed.is_visible_in_tree(), "Resume leaves feed hidden")
	await _button(overview.rail.get_node("EconomyButton"))
	_hud.call("show_notification", "Already expired", KingdomTheme.MUTED, 0.05)
	await get_tree().create_timer(0.7).timeout
	await _frames(3)
	await _button(overview.panel.find_child("CloseStrategyButton", true, false))
	_expect(feed.get_child_count() == 0, "expired message replayed after close")
	_hud.call("show_notification", "Sacred Site · tap to view", KingdomTheme.AMBER, 30.0, func() -> void: _notification_actions += 1)
	await _frames(4)
	var action: Control = feed.get_child(0)
	_expect(action.is_visible_in_tree() and action.size.y >= 48.0, "field action lost its touch target")
	await _tap(action.get_global_rect().get_center())
	_expect(_notification_actions == 1, "one touch must invoke the notification once: " + str(_notification_actions))
	Input.emulate_touch_from_mouse = true
	await _physical_mouse_tap(action.get_global_rect().get_center())
	Input.emulate_touch_from_mouse = false
	_expect(_notification_actions == 2, "one physical mouse contact must invoke once despite touch emulation: " + str(_notification_actions))
	var canceled := InputEventScreenTouch.new()
	canceled.index = _contact_id + 1
	canceled.position = get_viewport().get_final_transform() * action.get_global_rect().get_center()
	canceled.pressed = true
	canceled.canceled = true
	Input.parse_input_event(canceled)
	await _frames(2)
	canceled.pressed = false
	Input.parse_input_event(canceled)
	await _frames(2)
	_expect(_notification_actions == 2, "canceled touch invoked notification")
	_expect(_orders == 0 and _selection.selected == selection_before, "surface contacts changed selection or issued world orders")
	_expect(ResourceManager.get_all_resources(0) == banks, "presentation changed bank")
	await _capture("field-feedback-restored")
	_receipts.append({"profile": _profile, "world_orders": _orders, "notification_actions": _notification_actions, "selection_preserved": _selection.selected == selection_before})
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(3)


func _check_hidden(feed: Control, feedback: Control, context: String) -> void:
	for index: int in 3:
		feedback.call("_refresh")
	_expect(not feed.is_visible_in_tree(), context + " reveals ordinary notifications")


func _message(feed: Control) -> String:
	if feed.get_child_count() == 0:
		return ""
	return (feed.get_child(feed.get_child_count() - 1).get_child(0) as Label).text


func _physical_mouse_tap(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = get_viewport().get_final_transform() * position
		event.global_position = event.position
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(3)
