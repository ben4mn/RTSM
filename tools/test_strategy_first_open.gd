extends "res://tools/test_strategy_overview.gd"
## Unlike older phone fixtures, never call apply_mobile_layout every frame.
## Exercise the real HUD's queued layout and container minimum notifications.


func _apply_profile_layout() -> void:
	pass


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.15]:
			await _first_open(phone, interface_scale)
	for failure: String in _failures:
		push_error("[FAIL] strategy_first_open: " + failure)
	if _failures.is_empty():
		print("[PASS] strategy_first_open: actual first Economy/Train/Info taps and stable producer controls at both phone sizes/scales, with no fixture layout calls")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _first_open(phone: Vector2i, interface_scale: float) -> void:
	_profile = "%dx%d-scale%.3f" % [phone.x, phone.y, interface_scale]
	_hud = null
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	GameManager.ui_scale = interface_scale
	get_window().content_scale_factor = interface_scale
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 30
	GameManager.guided_opening_enabled = false
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
	_main.get_node("AIController").set_process(false)
	_main.get_node("AIController").get("_decision_timer").stop()
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	await _frames(3)
	await _button(overview.rail.get_node("EconomyButton"))
	_check_first_open_bounds(overview, "Workers")
	await _capture("first-workers")
	await _button(overview.get("_production_tab"))
	_check_first_open_bounds(overview, "Train")
	await _button(overview.get("_info_button"))
	_check_first_open_bounds(overview, "Info")
	await _button(overview.get("_info_button"))
	var tc: BuildingBase = _main.get("_player_buildings")[0][0]
	var row: Dictionary = (overview.get("_producer_rows") as Dictionary)[tc.get_instance_id()]
	# Repeated snapshots must not move a button after the user touches down.
	var repeat: Button = row.repeat
	var before: Rect2 = repeat.get_global_rect()
	var controller: Node = _main.get_node("StrategyController")
	for index: int in range(5):
		controller.call("_refresh")
		await _frames(2)
		_expect(repeat.get_global_rect().is_equal_approx(before), "snapshot moved the paid Repeat target")
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)


func _check_first_open_bounds(overview: StrategyOverview, page: String) -> void:
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	var bounds: Rect2 = overview.panel.get_global_rect()
	print("FIRST_OPEN %s %s bounds=%s minimum=%s" % [_profile, page, bounds, overview.panel.get_combined_minimum_size()])
	_expect(overview.panel.is_visible_in_tree() and safe.encloses(bounds), page + " first opening exceeds safe bounds: " + str(bounds))
	_expect(bounds.size.y <= (240.5 if page == "Info" else 310.5), page + " first opening retains oversized height: " + str(bounds.size))
	_expect(not bounds.intersects(overview.rail.get_global_rect()), page + " covers persistent rail")
	var scroll: ScrollContainer = overview.get("_scroll")
	var content: Control = overview.get("_details") if page == "Info" else overview.get("_producer_list") if page == "Train" else overview.get("_economy")
	_expect(scroll.get_global_rect().grow(1).encloses(content.get_global_rect()), page + " content needs hidden scrolling")
