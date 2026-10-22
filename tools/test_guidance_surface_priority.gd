extends "res://tools/test_strategy_first_open.gd"
## Real screen-touch management transitions preserve the live opening lesson.


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.15]:
			await _guidance_journey(phone, interface_scale)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("guidance-surface-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Actual Main scene ScreenTouch dispatch at four phone/scale profiles. AI and economy held; one selected worker receives controlled lethal damage to exercise automatic selection cleanup and hidden lesson refresh. No full-match or physical-device claim.", "profiles": _receipts, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] guidance_surface_priority: " + failure)
	if _failures.is_empty():
		print("[PASS] guidance_surface_priority: real Economy/Army/Build/Pause touches suppress guidance; two raid targets remain reachable and close management without losing selection; live lesson updates restore; placement retains guidance; Skip stays cleared; no world-order leakage")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _guidance_journey(phone: Vector2i, interface_scale: float) -> void:
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
	_main.call("_update_progression_hint")
	await _frames(5)
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	var banner: Control = _hud.get("_progression_hint_panel")
	var label: Label = _hud.get("_progression_hint_label")
	var skip: Button = _hud.get("_guidance_dismiss_button")
	var initial_text: String = label.text
	_expect(banner.is_visible_in_tree() and initial_text.begins_with("1 / 4"), "opening lesson missing")
	_orders = 0
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	_selection.gather_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.build_command.connect(func(_target: Node2D) -> void: _orders += 1)
	var selected_worker: UnitBase = _main.get("_player_units")[0][0]
	_selection.select_single(selected_worker)
	_main.call("_update_progression_hint")
	var worker_text: String = label.text
	_expect(worker_text != initial_text and worker_text.contains("berry bush"), "selection did not update lesson")
	await _button(overview.rail.get_node("EconomyButton"))
	_expect(overview.panel.is_visible_in_tree() and not banner.is_visible_in_tree() and not skip.is_visible_in_tree(), "Economy leaves lesson/Skip over its card")
	# Automatic removal keeps management open; unlike deliberate selection it
	# must update the lesson without reviving its floating presentation.
	var fallen_position: Vector2 = selected_worker.global_position
	selected_worker.take_damage(selected_worker.hp)
	await _frames(5)
	_main.call("_update_progression_hint")
	await _frames(3)
	var selected_text: String = label.text
	_expect(selected_text == initial_text and selected_text != worker_text, "automatic selection cleanup did not update hidden lesson")
	_expect(not banner.visible and _hud.call("get_secondary_surface_name") == "economy", "lesson refresh displaced Economy")
	var feedback: Control = _main.get("_battlefield_feedback")
	feedback.call("report_attack", "Town Center", fallen_position + Vector2(800, 0))
	await _frames(4)
	_check_raid_lane(feedback, overview)
	await _capture("economy-hidden-guide")
	var camera_before: Vector2 = _map.get("camera").position
	await _button(feedback.get("_buttons")[1])
	_expect(_hud.call("get_secondary_surface_name") == "none" and _map.get("camera").position.distance_to(camera_before) > 8.0, "raid touch did not close management and show its location")
	_expect(banner.is_visible_in_tree() and label.text == selected_text, "closing Economy did not restore latest lesson")
	_selection.select_single(_main.get("_player_units")[0][0])
	_main.call("_update_progression_hint")
	selected_text = label.text
	var selection_before: Array = _selection.selected.duplicate()
	await _button(overview.rail.get_node("ArmyButton"))
	_expect(not banner.visible, "Army leaves lesson visible")
	_check_raid_lane(feedback, overview)
	await _button(feedback.get("_buttons")[0])
	_expect(_hud.call("get_secondary_surface_name") == "none" and _selection.selected == selection_before, "raid touch changed selection or left Army open")
	_expect(banner.visible and label.text == selected_text, "Army close loses lesson")
	await _button(_hud.get("build_menu_button"))
	var build_menu: Node = _main.get("_build_menu")
	_expect(build_menu.visible and not banner.visible, "Build palette leaves lesson visible")
	await _button(build_menu.get("_button_map")[BuildingData.BuildingType.HOUSE])
	_expect(_main.get("_building_placement").active and banner.visible, "placement loses field guidance")
	await _button(_hud.get("_placement_cancel_button"))
	await _button(_hud.get("_pause_button"))
	_expect(GameManager.current_state == GameManager.GameState.PAUSED and not banner.visible, "Pause leaves lesson visible")
	await _capture("pause-hidden-guide")
	await _button(_hud.get("_pause_overlay").get_node("PauseMenu/ResumeButton"))
	_expect(GameManager.current_state == GameManager.GameState.PLAYING and banner.visible, "Resume loses lesson")
	_expect(bool(_main.get("_guided_opening_active")) and int(_main.get("_guided_stage")) == 0, "management advanced or disabled the guide")
	await _capture("returned-guide")
	await _button(skip)
	_expect(not bool(_main.get("_guided_opening_active")) and not banner.visible and label.text.is_empty(), "Skip did not clear lesson")
	await _button(overview.rail.get_node("EconomyButton"))
	await _button(overview.panel.find_child("CloseStrategyButton", true, false))
	_expect(not banner.visible and label.text.is_empty(), "closing management revived skipped lesson")
	_expect(_orders == 0, "management contacts leaked world orders")
	_receipts.append({"profile": _profile, "initial_instruction": initial_text, "selected_instruction": selected_text, "world_orders": _orders})
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(3)


func _check_raid_lane(feedback: Control, overview: StrategyOverview) -> void:
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	var bounds: Array[Rect2] = feedback.call("get_visible_bounds")
	_expect(bounds.size() == 2, "management lost an attack location")
	for rectangle: Rect2 in bounds:
		_expect(safe.encloses(rectangle) and rectangle.size.x >= 48.0 and rectangle.size.y >= 48.0, "raid response target is unsafe or too small")
		_expect(not rectangle.intersects(overview.panel.get_global_rect()) and not rectangle.intersects(overview.rail.get_global_rect()), "management covers a raid response target")
