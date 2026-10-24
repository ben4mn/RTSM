extends "res://tools/test_strategy_overview.gd"
## Real mobile GUI contacts and ordinary paid orders. Only simulation time is
## controlled: no bank grants, free structures, enemy vision or free recruits.


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(_hud):
		print("RECRUIT_FIXTURE_FOCUS_OUT ", _profile, " surface=", _hud.call("get_secondary_surface_name"))


func _apply_profile_layout() -> void:
	# Default-scale runs exercise the HUD's own deferred first-open layout.
	# Only the largest-scale runs inject a synthetic physical safe-area inset.
	if _synthetic_notch:
		super._apply_profile_layout()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale: float in [1.0, 1.15]:
			if OS.get_environment("AOEM_RECRUIT_SINGLE_PROFILE") == "1" and (phone.x != 844 or scale > 1.0):
				continue
			await _recruit_journey(phone, scale)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("army-recruit-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"profiles": _receipts, "failures": _failures, "scope": "Native engine ScreenTouch dispatch on 844x390/932x430 at default/largest interface scale. Default scale uses real deferred HUD layout; largest scale adds synthetic notch. Ordinary starting bank; paid Scout and two Barracks; construction/training time controlled. No physical-device or network claim."}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] army_recruit: " + failure)
	if _failures.is_empty():
		print("[PASS] army_recruit: %d phone/scale profiles; paid Barracks planning/cancel/confirm, construction gate, military producer filter, paid Warrior reserve/refund/repeat/rally, separate Economy/Army producer memories, Groups preservation, rejected unaffordable/enemy orders, food-alert grace/recovery and zero GUI world orders" % _receipts.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _recruit_journey(phone: Vector2i, interface_scale: float) -> void:
	_synthetic_notch = interface_scale > 1.0
	_profile = "%dx%d-scale%.3f-%s" % [phone.x, phone.y, interface_scale, "notched" if _synthetic_notch else "plain"]
	_hud = null
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = interface_scale
	GameManager.ui_scale = interface_scale
	GameManager.selected_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.selected_opponent_civilization = CivilizationData.Civilization.CROWNLANDS
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
	_main.set_process(false)
	_main.get_node("AIController").set_process(false)
	_main.get_node("AIController").get("_decision_timer").stop()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var controller: Node = _main.get_node("StrategyController")
	controller.set_process(false)
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	await _frames(6)
	_main.call("_update_fog_of_war")
	var tc: BuildingBase = _main.get("_player_buildings")[0][0]
	var tc_queue: ProductionQueue = tc.get_production_queue()
	_main.call("_on_train_unit_requested", tc, UnitData.UnitType.SCOUT)
	_expect(tc_queue.queue == [UnitData.UnitType.SCOUT], "Scout setup must be paid")
	tc_queue.advance(tc_queue.current_train_time)
	var scout: UnitBase = _main.get("_player_units")[0].back()
	scout.set_process(false)
	_selection.select_single(scout)
	controller.call("_refresh")
	await _frames(3)
	var camera: Vector2 = _map.get("camera").position
	_orders = 0
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	_selection.attack_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.build_command.connect(func(_target: Node2D) -> void: _orders += 1)
	var army: Button = overview.rail.get_node("ArmyButton")
	var economy: Button = overview.rail.get_node("EconomyButton")
	await _button(army)
	_expect((overview.get("_recruit_tab") as Button).button_pressed and (overview.get("_recruit_empty") as Control).is_visible_in_tree(), "Scout-only first Army open must expose recruitment")
	_expect(not (overview.get("_producer_rows") as Dictionary)[tc.get_instance_id()].card.is_visible_in_tree(), "Town Center must stay out of Army Recruit")
	var plan: Button = overview.get("_barracks_button")
	_expect(plan.text.contains("120W") and not plan.disabled, "empty recruitment must expose affordable Barracks cost")
	_check_recruit_bounds(overview)
	await _capture("recruit-empty")
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _overview_button(overview, plan)
	var placement: BuildingPlacement = _main.get("_building_placement")
	_expect(placement.active and int(_main.get("_placement_type")) == BuildingData.BuildingType.BARRACKS, "Barracks contact must enter canonical placement")
	_expect(ResourceManager.get_all_resources(0) == bank, "planning a Barracks must not spend resources")
	await _button(_hud.get("_placement_cancel_button"))
	_expect(not placement.active and ResourceManager.get_all_resources(0) == bank, "canceling Barracks planning must be free")
	await _button(army)
	await _overview_button(overview, plan)
	var legal: Vector2 = _barracks_position()
	_expect(legal != Vector2.ZERO, "paid Barracks needs a legal explored placement")
	placement.update_preview_at_world(legal)
	await _frames(3)
	await _button(_hud.get("_placement_confirm_button"))
	var first: BuildingBase = _main.get("_player_buildings")[0].back()
	_expect(first.building_type == BuildingData.BuildingType.BARRACKS and ResourceManager.get_resource(0, "wood") == int(bank.wood) - 120, "Place must create and pay for one Barracks")
	if first.building_type != BuildingData.BuildingType.BARRACKS:
		await _capture("failed-confirm")
		print("RECRUIT_PLACEMENT_FAILURE ", _failures, " active=", placement.active, " touch=", placement.uses_touch_input(), " legal=", legal, " ghost=", placement.ghost_position, " reason=", placement.get_invalid_reason())
		_main.free()
		_main = null
		_hud = null
		GameManager.set_state(GameManager.GameState.MENU)
		await _frames(2)
		return
	controller.call("_refresh")
	await _button(army)
	var first_row: Dictionary = (overview.get("_producer_rows") as Dictionary)[first.get_instance_id()]
	var train: Button = first_row.train[UnitData.UnitType.INFANTRY]
	_expect(train.is_visible_in_tree() and train.disabled and not (overview.get("_recruit_empty") as Control).is_visible_in_tree(), "new foundation must appear with disabled training")
	first.complete_instantly()
	controller.call("_refresh")
	await _frames(3)
	_check_recruit_bounds(overview)
	var before_train: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _overview_button(overview, train)
	var queue: ProductionQueue = first.get_production_queue()
	_expect(queue.queue == [UnitData.UnitType.INFANTRY] and int(GameManager.players[0].population_reserved) == 1, "Recruit must reserve one paid Warrior")
	_expect(ResourceManager.get_resource(0, "food") == int(before_train.food) - 50 and ResourceManager.get_resource(0, "wood") == int(before_train.wood) - 20, "Recruit must spend the exact Warrior cost")
	await _button(overview.get("_info_button"))
	_expect(_visible_detail_text(overview).contains("Paid: Warrior ×1") and _visible_detail_text(overview).contains("Training:"), "Recruit Info must show this military producer's queue and blockers")
	await _button(overview.get("_info_button"))
	await _overview_button(overview, first_row.repeat)
	_expect(queue.auto_queue_enabled, "Recruit Repeat must reach the existing producer")
	await _overview_button(overview, first_row.rally)
	_expect(first.has_custom_rally_point() and _map.world_to_tile(first.rally_point) == _map.world_to_tile(scout.global_position), "Recruit Rally must target the selected army")
	await _capture("recruit-paid-warrior")
	await _overview_button(overview, first_row.clear)
	_expect(queue.queue.is_empty() and not queue.auto_queue_enabled and int(GameManager.players[0].population_reserved) == 0 and ResourceManager.get_all_resources(0) == before_train, "Recruit Clear must stop Repeat and refund exact resources/reservation")
	# A second paid Barracks exercises producer identity without a free age-up.
	var second_position: Vector2 = _barracks_position()
	_main.call("_on_placement_confirmed", BuildingData.BuildingType.BARRACKS, second_position)
	var second: BuildingBase = _main.get("_player_buildings")[0].back()
	_expect(second != first and ResourceManager.get_resource(0, "wood") == int(bank.wood) - 240, "second producer navigation fixture must be a paid Barracks")
	second.complete_instantly()
	controller.call("_refresh")
	await _frames(3)
	await _button(overview.get("_next_producer"))
	_expect(int(overview.call("_selected_producer_id")) == second.get_instance_id(), "Army next must move between military producers")
	var second_row: Dictionary = (overview.get("_producer_rows") as Dictionary)[second.get_instance_id()]
	await _button(economy)
	await _button(overview.get("_production_tab"))
	_expect(int(overview.call("_selected_producer_id")) == tc.get_instance_id(), "Economy Train must retain Town Center access")
	await _button(army)
	_expect(int(overview.call("_selected_producer_id")) == second.get_instance_id() and second_row.card.is_visible_in_tree(), "surface switching must retain the Army producer")
	await _button(overview.get("_groups_tab"))
	await _button(army)
	await _button(army)
	_expect((overview.get("_groups_tab") as Button).button_pressed and (overview.get("_army") as Control).is_visible_in_tree(), "closing/reopening Army must retain Groups")
	await _button(overview.get("_recruit_tab"))
	_expect(int(overview.call("_selected_producer_id")) == second.get_instance_id(), "Groups must not reset the Recruit producer")
	var limited_bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _overview_button(overview, second_row.train[UnitData.UnitType.INFANTRY])
	_expect(second.get_production_queue().queue.is_empty() and ResourceManager.get_all_resources(0) == limited_bank, "an unaffordable Recruit request must be rejected by paid production")
	var enemy_tc: BuildingBase = _main.get("_player_buildings")[1][0]
	var enemy_bank: Dictionary = ResourceManager.get_all_resources(1).duplicate()
	controller.call("_train", enemy_tc, UnitData.UnitType.VILLAGER)
	_expect(enemy_tc.get_production_queue().queue.is_empty() and ResourceManager.get_all_resources(1) == enemy_bank, "Recruit bridge must reject enemy producer requests")
	first.state = BuildingBase.State.DESTROYED
	controller.call("_refresh")
	await _frames(3)
	_expect(int(overview.call("_selected_producer_id")) == second.get_instance_id() and not (overview.get("_producer_rows") as Dictionary).has(first.get_instance_id()), "removing an earlier producer must preserve the selected survivor")
	_check_recruit_bounds(overview)
	await _capture("recruit-retained-producer")
	_expect(_selection.selected == [scout] and _map.get("camera").position == camera and _orders == 0, "management contacts must preserve field selection, camera and orders")
	await _check_food_alert(controller, overview)
	_receipts.append({"profile": _profile, "paid_barracks": 2, "paid_refund": true, "producer_preserved": int(overview.get("_army_producer_id")) == second.get_instance_id(), "world_orders": _orders, "safe": str(_hud.call("get_world_safe_rect")), "sheet": str(overview.panel.get_global_rect())})
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)


func _check_food_alert(controller: Node, overview: StrategyOverview) -> void:
	var held_time: float = GameManager.game_time
	controller.set("_food_gap_started", -1.0)
	GameManager.game_time = 0.0
	_expect(not bool(controller.call("_update_food_attention", 3, 0, 0)), "startup must not immediately show No food")
	GameManager.game_time = 11.0
	_expect(not bool(controller.call("_update_food_attention", 3, 0, 0)), "startup grace must last twelve gameplay seconds")
	GameManager.game_time = 12.0
	_expect(bool(controller.call("_update_food_attention", 3, 0, 0)), "persistent startup food gap must eventually alert")
	GameManager.game_time = 100.0
	_expect(not bool(controller.call("_update_food_attention", 3, 1, 0)), "food work must immediately clear the warning")
	GameManager.game_time = 101.0
	_expect(not bool(controller.call("_update_food_attention", 3, 0, 0)), "brief worker reassignment must not flash an alert")
	GameManager.game_time = 106.9
	_expect(not bool(controller.call("_update_food_attention", 3, 0, 0)), "a new food gap must receive the full six-second grace")
	GameManager.game_time = 107.0
	_expect(bool(controller.call("_update_food_attention", 3, 0, 0)), "sustained late food loss must alert")
	_expect(not bool(controller.call("_update_food_attention", 3, 0, 1)), "sheltering workers must not be mislabeled as neglected food work")
	GameManager.game_time = held_time
	controller.set("_food_gap_started", -1.0)
	var original: Dictionary = (overview.get("_snapshot") as Dictionary).duplicate(true)
	var alert: Dictionary = original.duplicate(true)
	alert["food_attention_ready"] = true
	alert["workers"]["food"] = 0
	alert["economy"] = {"title": "No workers on food", "detail": "Assign food workers or build a Farm.", "attention": "No food!", "severity": 1}
	overview.update_snapshot(alert)
	var economy: Button = overview.rail.get_node("EconomyButton")
	_expect(economy.text == "No food" and economy.icon == CommandIcons.get_icon("food"), "closed rail must visibly identify missing food income")
	# This rail stacks its icon ABOVE the label, unlike producer action buttons.
	var caption_size: Vector2 = economy.get_theme_font("font").get_string_size(economy.text, HORIZONTAL_ALIGNMENT_LEFT, -1, economy.get_theme_font_size("font_size"))
	var padding: Vector2 = economy.get_theme_stylebox("normal").get_minimum_size()
	_expect(caption_size.x + padding.x <= economy.size.x and caption_size.y + 20.0 + padding.y + 1.0 <= economy.size.y, "No food must fit the existing 48px vertically labeled rail")
	await _button(economy)
	await _button(overview.get("_workers_tab"))
	var summary: Label = overview.get("_summary")
	_expect(summary.is_visible_in_tree() and summary.text == "No food income\nAssign food workers or build a Farm." and summary.get_line_count() <= 2, "Workers must show an actionable alert in at most two lines")
	var scroll: ScrollContainer = overview.get("_scroll")
	_expect(scroll.get_global_rect().encloses(summary.get_global_rect()) and scroll.get_global_rect().encloses((overview.get("_farm_button") as Button).get_global_rect()), "food warning must fit with the Farm action on a phone")
	_expect((_hud.call("get_world_safe_rect") as Rect2).encloses(overview.panel.get_global_rect()), "food warning must not force Workers outside the safe area")
	await _capture("workers-no-food")
	await _button(economy)
	_expect(economy.text == "No food", "closing Workers must restore the visible food warning")
	await _capture("closed-no-food")
	overview.update_snapshot(original)
	_expect(economy.text == "Economy", "resumed food income must restore the ordinary rail label")


func _check_recruit_bounds(overview: StrategyOverview) -> void:
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	_expect(safe.encloses(overview.panel.get_global_rect()), "Recruit sheet must fit the safe area")
	_expect(not overview.panel.get_global_rect().intersects(overview.rail.get_global_rect()), "Recruit sheet must leave persistent rail reachable")
	var scroll: ScrollContainer = overview.get("_scroll")
	_expect(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Recruit actions must fit without scrolling")
	for button: Button in [overview.get("_recruit_tab"), overview.get("_groups_tab")]:
		_expect(button.size.y >= 48.0 and safe.encloses(button.get_global_rect()), "Recruit/Groups tabs must be safe 48px targets")
		_check_caption_fit(button)
	for row: Dictionary in (overview.get("_producer_rows") as Dictionary).values():
		if not (row.card as Control).is_visible_in_tree():
			continue
		for button: Button in [row.repeat, row.undo, row.clear, row.rally, row.sacred]:
			_expect(scroll.get_global_rect().encloses(button.get_global_rect()), "visible Recruit action is clipped: " + str(button.name))
			_check_caption_fit(button)


func _barracks_position() -> Vector2:
	var placement: BuildingPlacement = _main.get("_building_placement")
	var anchor: Vector2i = _map.get("map_generator").spawn_positions[0]
	for radius: int in range(5, 12):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var point: Vector2 = _map.tile_to_world(anchor + Vector2i(dx, dy))
				if placement.revalidate_confirmation(BuildingData.BuildingType.BARRACKS, point, 0):
					return point
	return Vector2.ZERO
