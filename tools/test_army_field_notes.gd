extends "res://tools/test_strategy_overview.gd"
## Actual touch routing and phone typography for optional, non-mutating tactics.

func _apply_profile_layout() -> void:
	if _synthetic_notch:
		super._apply_profile_layout()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _notes_journey(phone, interface_scale, notched)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("army-field-notes.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Twelve native phone/scale profiles; synthetic notches supplied only in six inset cases. Actual engine ScreenTouch events. Economy and AI held, existing starting worker selected. No paid-match or physical-phone claim.", "profiles": _receipts, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] army_field_notes: " + failure)
	if _failures.is_empty():
		print("[PASS] army_field_notes: 12 touch profiles; notes/back/close/switch preserve selection, orders and banks; three readable tactics fit without scrolling; guide/raid priorities remain intact")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _notes_journey(phone: Vector2i, interface_scale: float, notched: bool) -> void:
	_profile = "%dx%d-scale%.3f-%s" % [phone.x, phone.y, interface_scale, "notch" if notched else "plain"]
	_synthetic_notch = notched
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
	var worker: UnitBase = _main.get("_player_units")[0][0]
	_selection.select_single(worker)
	_main.call("_update_progression_hint")
	await _frames(5)
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	var notes: Control = overview.get("_army_notes")
	var guide: Control = _hud.get("_progression_hint_panel")
	var selected: Array = _selection.selected.duplicate()
	var banks: Dictionary = {}
	for resource: String in ["food", "wood", "gold"]:
		banks[resource] = ResourceManager.get_resource(0, resource)
	_orders = 0
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	_selection.attack_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.gather_command.connect(func(_target: Node2D) -> void: _orders += 1)
	await _button(overview.rail.get_node("ArmyButton"))
	_expect(not notes.is_visible_in_tree() and not guide.visible, "Army should begin with actions and no guide overlap")
	var info: Button = overview.get("_info_button")
	_expect(info.is_visible_in_tree() and info.size.x >= 48 and info.size.y >= 48 and info.accessibility_name.contains("Army field notes"), "Army Info lacks a reachable named target")
	await _button(info)
	_expect(notes.is_visible_in_tree() and not overview.get("_army").visible and not guide.visible, "Info failed to replace army actions cleanly")
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	var scroll: ScrollContainer = overview.get("_scroll")
	_expect(safe.encloses(overview.panel.get_global_rect()), "notes panel escapes safe area")
	_expect(scroll.get_global_rect().grow(1).encloses(notes.get_global_rect()), "notes need hidden scrolling")
	_expect(not overview.panel.get_global_rect().intersects(overview.rail.get_global_rect()), "notes cover persistent launchers")
	var text: PackedStringArray = []
	for row: Node in notes.get_children():
		var icon: TextureRect = row.get_child(0)
		_expect(icon.texture != null and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tactic glyph missing or consumes input")
		for label: Label in row.get_child(1).get_children():
			text.append(label.text)
			_expect(label.get_visible_line_count() == label.get_line_count() and label.size.y + 1.0 >= label.get_line_count() * label.get_line_height(), "tactic clipped: " + label.text)
			_expect(scroll.get_global_rect().grow(1).encloses(label.get_global_rect()), "tactic outside visible sheet: " + label.text)
	_expect(text.size() == 6 and text[1].contains("Warriors catch up with Horsemen"), "staging advice lost its concrete mixed-speed tradeoff")
	var bounds: Rect2 = overview.panel.get_global_rect()
	for index: int in range(4):
		_main.get_node("StrategyController").call("_refresh")
		await _frames(2)
		_expect(notes.is_visible_in_tree() and overview.panel.get_global_rect().is_equal_approx(bounds), "snapshot moved or dismissed notes")
	await _capture("army-field-notes")
	var feedback: Control = _main.get("_battlefield_feedback")
	feedback.call("report_attack", "Villager", worker.global_position)
	feedback.call("report_attack", "Town Center", worker.global_position + Vector2(800, 0))
	await _frames(4)
	for alert: Rect2 in feedback.call("get_visible_bounds"):
		_expect(safe.encloses(alert) and not alert.intersects(overview.panel.get_global_rect()), "notes obscure an urgent raid target")
	await _button(info)
	_expect(not notes.is_visible_in_tree() and overview.get("_army").visible, "Back loses army actions")
	await _button(info)
	await _button(overview.rail.get_node("EconomyButton"))
	_expect(not notes.is_visible_in_tree() and overview.get("_economy").visible and not bool(overview.get("_details_page")), "switch carries Army notes into Economy")
	await _button(overview.rail.get_node("ArmyButton"))
	_expect(not notes.is_visible_in_tree() and overview.get("_army").visible, "Army does not reopen on actions")
	await _button(info)
	await _button(overview.panel.find_child("CloseStrategyButton", true, false))
	_expect(not notes.is_visible_in_tree() and not overview.panel.visible and guide.visible, "Close failed to restore the field guide")
	_expect(_selection.selected == selected and _orders == 0, "notes changed selection or issued a world order")
	for resource: String in banks:
		_expect(ResourceManager.get_resource(0, resource) == banks[resource], "notes changed the paid bank")
	_receipts.append({"profile": _profile, "panel": str(bounds), "texts": text, "orders": _orders})
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(3)
