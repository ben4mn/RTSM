extends "res://tools/test_strategy_overview.gd"
## Real lethal damage and stale-selection processing while dispatched contacts
## operate paid remote production. Deterministic fixture, not a played match.


func _run() -> void:
	AudioManager.set_all_enabled(false)
	PlaytestDiagnostics.reset_for_test()
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _death_journey(phone, interface_scale, notched)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("strategy-selection-death-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"profiles": _receipts, "failures": _failures, "display_server": DisplayServer.get_name(), "scope": "Twelve engine phone/scale/synthetic-safe-area profiles, dispatched ScreenTouch, real death signals and automatic pruning. Ordinary paid House/Scouts/Villager, controlled production time and damage; no played-match or physical-device claim."}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] strategy_selection_death: " + failure)
	if _failures.is_empty():
		print("[PASS] strategy_selection_death: 12 profiles; partial/last selected deaths preserve Economy/Army bounded pages, next contact pays once, groups refresh, no world leakage, deliberate selection and context surfaces still dismiss")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _death_journey(phone: Vector2i, interface_scale: float, notched: bool) -> void:
	_profile = "%dx%d-scale%.3f-%s" % [phone.x, phone.y, interface_scale, "notched" if notched else "ordinary"]
	_synthetic_notch = notched
	_hud = null
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	GameManager.ui_scale = interface_scale
	get_window().content_scale_factor = interface_scale
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
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
	# SelectionManager keeps processing; deaths must prune through its real loop.
	var controller: Node = _main.get_node("StrategyController")
	controller.set_process(false)
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	await _frames(5)
	_main.call("_update_fog_of_war")
	var tc: BuildingBase = _main.get("_player_buildings")[0][0]
	var queue: ProductionQueue = tc.get_production_queue() as ProductionQueue
	var house: BuildingBase = _paid_house()
	_expect(house != null, "paid housing setup failed")
	if house:
		house.complete_instantly()
	var troops: Array[Node2D] = _paid_scouts(tc, queue)
	_selection.select_many(troops)
	controller.call("_refresh")
	_orders = 0
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	_selection.attack_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.gather_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.build_command.connect(func(_target: Node2D) -> void: _orders += 1)
	var camera: Camera2D = _map.get("camera")
	var camera_position: Vector2 = camera.position
	var camera_zoom: Vector2 = camera.zoom
	await _button(overview.rail.get_node("EconomyButton"))
	await _button(overview.get("_production_tab"))
	var row: Dictionary = (overview.get("_producer_rows") as Dictionary)[tc.get_instance_id()]
	var train: Button = row.train[UnitData.UnitType.VILLAGER]
	var scroll: ScrollContainer = overview.get("_scroll")
	await _frames(3)
	var production_scroll: int = scroll.scroll_vertical
	var intended_contact: Vector2 = train.get_global_rect().get_center()
	_expect(production_scroll == 0 and train.is_visible_in_tree() and scroll.get_global_rect().encloses(train.get_global_rect()), "fixture needs the visible unscrolled Train page")
	await _kill_selected(troops[0] as UnitBase, controller)
	_assert_surface(overview, "economy", production_scroll, 1)
	_expect(not (row.rally as Button).disabled, "partial loss disabled the surviving army rally")
	await _kill_selected(troops[1] as UnitBase, controller)
	_assert_surface(overview, "economy", production_scroll, 0)
	_expect((row.rally as Button).disabled and not (_hud.get("selection_panel") as Control).visible, "last loss retained stale unit controls")
	_expect(train.get_global_rect().has_point(intended_contact), "death moved the intended production contact")
	var bank: Dictionary = ResourceManager.get_all_resources(0)
	# Use the pre-death screen position, not a newly located button.
	await _tap(intended_contact)
	_expect(queue.queue == [UnitData.UnitType.VILLAGER] and GameManager.get_reserved_population(0) == 1, "post-death contact did not enqueue exactly one paid Villager")
	var worker_cost: Dictionary = UnitData.get_unit_cost(UnitData.UnitType.VILLAGER)
	for resource: String in ["food", "wood", "gold"]:
		_expect(ResourceManager.get_resource(0, resource) == int(bank[resource]) - int(worker_cost.get(resource, 0)), "post-death contact charged the wrong " + resource)
	await _overview_button(overview, row.clear)
	_expect(queue.queue.is_empty() and GameManager.get_reserved_population(0) == 0 and ResourceManager.get_all_resources(0) == bank, "post-death clear did not refund exactly")
	await _capture("economy-after-selected-deaths")
	# Deliberate selection must not inherit the automatic-cleanup exception.
	var worker: Villager = _main.get("_player_units")[0][0]
	_selection.select_single(worker)
	_expect(_hud.call("get_secondary_surface_name") == "none", "deliberate selection retained Economy")
	await _button(overview.rail.get_node("EconomyButton"))
	_selection.deselect_all()
	_expect(_hud.call("get_secondary_surface_name") == "none", "deliberate deselection retained Economy")
	troops = _paid_scouts(tc, queue)
	_selection.select_many(troops)
	controller.call("_refresh")
	await _button(overview.rail.get_node("ArmyButton"))
	var group: Dictionary = (overview.get("_group_rows") as Dictionary)[1]
	await _overview_button(overview, group.save)
	var army_scroll: int = scroll.scroll_vertical
	await _kill_selected(troops[0] as UnitBase, controller)
	_assert_surface(overview, "army", army_scroll, 1)
	_expect((group.label as Label).text.contains("1 units") and not (group.recall as Button).disabled, "Army did not update the surviving saved member")
	await _kill_selected(troops[1] as UnitBase, controller)
	_assert_surface(overview, "army", army_scroll, 0)
	_expect((group.label as Label).text.contains("empty") and (group.recall as Button).disabled and (group.save as Button).disabled, "Army retained dead saved/selected members")
	await _capture("army-after-selected-deaths")
	_selection.select_single(worker)
	_expect(_hud.call("get_secondary_surface_name") == "none", "deliberate selection retained Army")
	await _button(_hud.get("_unit_more_button"))
	await _kill_selected(worker, controller)
	_expect(_hud.call("get_secondary_surface_name") == "none", "automatic death retained selection-specific More")
	# Keep the existing Queue invalidation policy, even for cleanup-origin revisions.
	_selection.select_single(tc)
	_main.call("_on_train_unit_requested", tc, UnitData.UnitType.SCOUT)
	await _button(_hud.get("_queue_navigation_button"))
	_expect(_hud.call("get_secondary_surface_name") == "queue", "Queue policy fixture did not open")
	_hud.call("set_selection_context_revision", int(_hud.get("_selection_context_revision")) + 1, true)
	_expect(_hud.call("get_secondary_surface_name") == "none", "cleanup exception retained selection-specific Queue")
	queue.cancel_all()
	# Drain the existing two-frame Queue restoration before destroying this
	# fixture's HUD; the normal match keeps it alive throughout field play.
	await _frames(5)
	_expect(not _selection.is_selection_cleanup(), "cleanup origin escaped synchronous selection dispatch")
	_expect(_orders == 0 and camera.position.is_equal_approx(camera_position) and camera.zoom.is_equal_approx(camera_zoom), "management/death contacts leaked world orders or camera movement")
	_receipts.append({"profile": _profile, "economy_scroll": production_scroll, "army_scroll": army_scroll, "world_orders": _orders, "paid_contacts": 1, "automatic_prune_origin_reset": not _selection.is_selection_cleanup()})
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)


func _paid_scouts(tc: BuildingBase, queue: ProductionQueue) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for index: int in 2:
		_main.call("_on_train_unit_requested", tc, UnitData.UnitType.SCOUT)
		_expect(queue.queue == [UnitData.UnitType.SCOUT], "Scout fixture must use a paid queue")
		queue.advance(queue.current_train_time)
		var scout: UnitBase = _main.get("_player_units")[0].back()
		_expect(scout.unit_type == UnitData.UnitType.SCOUT, "paid Scout did not spawn")
		scout.set_process(false)
		result.append(scout)
	return result


func _kill_selected(unit: UnitBase, controller: Node) -> void:
	unit.take_damage(unit.hp)
	await _frames(3)
	controller.call("_refresh")
	await _frames(2)


func _assert_surface(overview: StrategyOverview, surface: String, scroll_offset: int, selected_count: int) -> void:
	_expect(_hud.call("get_secondary_surface_name") == surface and overview.panel.is_visible_in_tree(), "selected death closed " + surface)
	_expect((overview.get("_scroll") as ScrollContainer).scroll_vertical == scroll_offset, "selected death reset " + surface + " scroll")
	_expect(_selection.selected.size() == selected_count, "automatic death pruning retained a stale selection")
