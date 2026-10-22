extends "res://tools/test_strategy_overview.gd"
## Dispatched-contact regression with ordinary paid purchases. Recovery/stock
## classification uses explicitly isolated facts, not a simulated played match.

const ASSESSMENT = preload("res://scripts/managers/economy_assessment.gd")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	_assessment_cases()
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _resilience_journey(phone, interface_scale, notched)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("economy-resilience-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"profiles": _receipts, "failures": _failures, "display_server": DisplayServer.get_name(), "screenshots_enabled": DisplayServer.get_name() != "headless", "scope": "Twelve engine phone profiles and actual ScreenTouch dispatch. Paid House/Scout/Villager/Farm with deterministic production/construction. Separate synthetic stock/recovery facts; not a hands-on match or physical-phone claim."}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] economy_resilience: " + failure)
	if _failures.is_empty():
		print("[PASS] economy_resilience: observed stock, early depletion warning, honest refund/queued/sheltering/hopeless recovery, paid Farm planning/cancel/place, Sacred rally, counters/blockers, 12 profiles and no world leakage")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _assessment_cases() -> void:
	_profile = "isolated-facts"
	var base: Dictionary = {"workers": 0, "food": 36, "refund_food": 0, "active_worker_producer": true}
	var cases: Array[Dictionary] = [
		{"change": {}, "title": "Economy cannot restart"},
		{"change": {"refund_food": 50}, "title": "Recover through a paid refund"},
		{"change": {"queued_workers": 1}, "title": "Replacement already paid"},
		{"change": {"food": 50}, "title": "Rebuild your workforce"},
		{"change": {"workers": 2, "recovering": 2}, "title": "Workers sheltering from danger"},
		{"change": {"workers": 3, "food_workers": 2, "worked_food": 80, "visible_food": 500}, "title": "Worked food is running low"},
		{"change": {"workers": 3, "food_workers": 0, "visible_food": 0}, "title": "No workers on food"},
		{"change": {"workers": 4, "food_workers": 2, "worked_food": 400, "visible_food": 400}, "title": "Keep food and wood staffed"},
	]
	for entry: Dictionary in cases:
		var facts: Dictionary = base.duplicate(true)
		facts.merge(entry.change, true)
		var before: Dictionary = facts.duplicate(true)
		var result: Dictionary = ASSESSMENT.describe(facts)
		_expect(result.title == entry.title, "wrong recovery classification: " + str(entry))
		_expect(facts == before, "assessment mutated economic facts")
	var full: Dictionary = base.duplicate()
	full.merge({"food": 50, "free_population": 0, "reserved_population": 0}, true)
	_expect(str(ASSESSMENT.describe(full).detail).contains("Living units fill population"), "full living population must not promise a nonexistent refund slot")
	full["reserved_population"] = 1
	_expect(str(ASSESSMENT.describe(full).detail).contains("release its reserved slots"), "paid population must explain the refund route")
	full["population_room_after_refunds"] = 0
	_expect(str(ASSESSMENT.describe(full).detail).contains("refunds cannot open a slot"), "over-cap living population must not promise a refund opens room")
	full.merge({"food": 36, "refund_food": 50}, true)
	_expect(str(ASSESSMENT.describe(full).detail).contains("Refunds cannot open a slot"), "recoverable food does not imply recoverable population")
	full["queued_workers"] = 1
	_expect(str(ASSESSMENT.describe(full).title) == "Replacement already paid", "paid replacement retains priority even after housing loss")


func _resilience_journey(phone: Vector2i, interface_scale: float, notched: bool) -> void:
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
	var controller: Node = _main.get_node("StrategyController")
	controller.set_process(false)
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	await _frames(4)
	_main.call("_update_fog_of_war")
	var house: BuildingBase = _paid_house()
	_expect(house != null, "paid House setup failed")
	if house != null:
		house.complete_instantly()
	var tc: BuildingBase = _main.get("_player_buildings")[0][0]
	var queue: ProductionQueue = tc.get_production_queue() as ProductionQueue
	_main.call("_on_train_unit_requested", tc, UnitData.UnitType.SCOUT)
	queue.advance(queue.current_train_time)
	var scout: UnitBase = _main.get("_player_units")[0].back()
	scout.set_process(false)
	_expect(scout.unit_type == UnitData.UnitType.SCOUT, "Scout must be normally paid")
	_selection.select_single(scout)
	controller.call("_refresh")
	await _frames(3)
	var camera_before: Vector2 = _map.get("camera").position
	_orders = 0
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	_selection.attack_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.gather_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.build_command.connect(func(_target: Node2D) -> void: _orders += 1)
	await _button(overview.rail.get_node("EconomyButton"))
	await _capture("economy-ready")
	_expect(overview.panel.size.x <= 560.1, "economy card grew beyond 560 logical pixels")
	_expect((_hud.call("get_world_safe_rect") as Rect2).encloses(overview.panel.get_global_rect()), "economy card outside safe area")
	await _button(overview.get("_production_tab"))
	var row: Dictionary = (overview.get("_producer_rows") as Dictionary)[tc.get_instance_id()]
	_expect(str((row.train[UnitData.UnitType.SCOUT] as Button).tooltip_text).contains("Recon"), "remote Scout omits its role")
	var site: Node2D = _map.get("sacred_site")
	var fog_before: bool = _map.is_tile_visible_to_player(_map.world_to_tile(site.global_position), 0)
	await _overview_button(overview, row.sacred)
	_expect(_map.world_to_tile(tc.rally_point) == _map.world_to_tile(site.global_position), "Sacred button did not use canonical public destination")
	_expect(str((row.rally_status as Label).text).contains("Sacred Site") and str((row.rally_status as Label).text).contains("Villagers"), "rally destination and worker consequence missing")
	_expect(_map.is_tile_visible_to_player(_map.world_to_tile(site.global_position), 0) == fog_before, "rally revealed fog")
	await _capture("sacred-rally")
	var bank_before: Dictionary = ResourceManager.get_all_resources(0)
	await _overview_button(overview, row.train[UnitData.UnitType.VILLAGER])
	_expect(ResourceManager.get_resource(0, "food") == int(bank_before.food) - 50 and GameManager.get_committed_population(0) > int(GameManager.players[0].population), "remote replacement did not pay and reserve")
	await _overview_button(overview, row.repeat)
	await _overview_button(overview, row.clear)
	_expect(ResourceManager.get_all_resources(0) == bank_before and queue.queue.is_empty() and not queue.auto_queue_enabled, "clear failed full refund/reservation/repeat semantics")
	_expect(_selection.selected == [scout] and _map.get("camera").position == camera_before, "remote controls changed selected army or camera")
	await _button(overview.get("_workers_tab"))
	await _scene_economy_facts(controller, overview, tc)
	controller.call("_refresh")
	await _overview_button(overview, overview.get("_farm_button"))
	var placement: BuildingPlacement = _main.get("_building_placement")
	_expect(placement.active and int(_main.get("_placement_type")) == BuildingData.BuildingType.FARM, "Farm shortcut did not enter existing placement")
	_expect(ResourceManager.get_all_resources(0) == bank_before, "Farm planning charged before confirmation")
	await _button(_hud.get("_placement_cancel_button"))
	_expect(not placement.active and ResourceManager.get_all_resources(0) == bank_before, "Farm cancellation changed resources")
	await _button(overview.rail.get_node("EconomyButton"))
	await _button(overview.get("_workers_tab"))
	await _overview_button(overview, overview.get("_farm_button"))
	var legal: Vector2 = placement.call("_find_initial_preview_position", placement.global_position)
	placement.call("update_preview_at_world", legal)
	await _frames(4)
	await _button(_hud.get("_placement_confirm_button"))
	_expect(not placement.active and ResourceManager.get_resource(0, "wood") == int(bank_before.wood) - 75, "Farm confirmation did not pay exactly 75 wood")
	var farm: BuildingBase = _main.get("_player_buildings")[0].back()
	_expect(farm.building_type == BuildingData.BuildingType.FARM and farm.provides_food, "Farm paid transaction created wrong permanent resource")
	_expect(_orders == 0, "new GUI controls leaked %d world orders" % _orders)
	_receipts.append({"profile": _profile, "world_orders": _orders, "paid_farm_wood": int(bank_before.wood) - ResourceManager.get_resource(0, "wood"), "rally_fog_unchanged": _map.is_tile_visible_to_player(_map.world_to_tile(site.global_position), 0) == fog_before, "panel_width": overview.panel.size.x})
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)


func _scene_economy_facts(controller: Node, overview: StrategyOverview, tc: BuildingBase) -> void:
	var workers: Array[Villager] = controller.call("_own_workers")
	var worker_state: int = workers[0].current_state
	workers[0].current_state = UnitBase.State.ATTACKING
	_expect(not bool(controller.call("_can_plan_with_worker", workers[0])), "explicitly attacking worker cannot promise automatic Farm construction")
	workers[0].current_state = worker_state
	var before: Dictionary = controller.call("_observed_food_stock", workers)
	var hidden: ResourceNode = null
	for entry: Variant in (_map.get("resource_nodes") as Dictionary).values():
		if entry is ResourceNode and entry.resource_type == "food" and not _map.is_resource_target_visible_to_player(entry, 0):
			hidden = entry
			break
	if hidden != null:
		var old_stock: int = hidden.remaining
		hidden.remaining += 9999
		_expect(controller.call("_observed_food_stock", workers) == before, "hidden live stock leaked into economy")
		hidden.remaining = old_stock
	else:
		_expect(false, "fixture needs a hidden food source")
	var food_target: ResourceNode = _map.get_nearest_resource_node("food", workers[0].global_position, 0) as ResourceNode
	if food_target != null:
		var stock: int = food_target.remaining
		workers[0].command_gather(food_target)
		food_target.remaining = 20
		controller.call("_refresh")
		_expect(str((overview.get("_economy_health") as Label).text).contains("running low"), "worked source exhaustion warning arrived too late")
		(overview.get("_scroll") as ScrollContainer).scroll_vertical = 0
		await _capture("food-running-low")
		food_target.remaining = stock
	var own: Array = (_main.get("_player_units") as Array)[0]
	var saved_units: Array = own.duplicate()
	own.clear()
	var bank: int = ResourceManager.get_resource(0, "food")
	ResourceManager.try_spend(0, {"food": bank - 36})
	controller.call("_refresh")
	_expect(str((overview.get("_economy_health") as Label).text).contains("Economy cannot restart"), "real empty registry +36 food was not diagnosed")
	(overview.get("_scroll") as ScrollContainer).scroll_vertical = 0
	await _capture("economy-cannot-restart")
	var queue: ProductionQueue = tc.get_production_queue() as ProductionQueue
	ResourceManager.refund(0, {"food": bank - 36})
	_expect(queue.enqueue_unit(UnitData.UnitType.VILLAGER), "fixture replacement must be paid")
	controller.call("_refresh")
	_expect(str((overview.get("_economy_health") as Label).text).contains("Replacement already paid"), "paid replacement incorrectly called hopeless")
	queue.cancel_all()
	own.assign(saved_units)
	# Under-construction and queue-full blockers need no resources or mutations.
	var original_state: int = tc.state
	tc.state = BuildingBase.State.CONSTRUCTING
	_expect(str(controller.call("_training_blocker", tc, UnitData.UnitType.VILLAGER)) == "under construction", "inactive producer blocker missing")
	tc.state = original_state
	var saved_queue: Array[int] = queue.queue.duplicate()
	queue.queue.assign([0, 0, 0, 0, 0])
	_expect(str(controller.call("_training_blocker", tc, UnitData.UnitType.VILLAGER)).begins_with("queue full"), "full producer queue blocker missing")
	queue.queue.assign(saved_queue)
	_population_guidance_cases(controller, overview, tc)


func _population_guidance_cases(controller: Node, overview: StrategyOverview, tc: BuildingBase) -> void:
	# Classification fixture: the bank and queue use the real paid transaction;
	# live-pop/cap facts isolate match-limit and destroyed-House conditions.
	var player: Dictionary = GameManager.players[0]
	var saved_population: int = int(player.population)
	var saved_cap: int = int(player.population_cap)
	var queue: ProductionQueue = tc.get_production_queue() as ProductionQueue
	_expect(queue.enqueue_unit(UnitData.UnitType.SCOUT), "population fixture needs a real paid reservation")
	player.population = 29
	player.population_cap = 30
	controller.call("_refresh")
	_expect(not str((overview.get("_population") as Label).text).contains("House"), "match-limit reservation blocker must not suggest more housing")
	_expect(str(controller.call("_training_blocker", tc, UnitData.UnitType.VILLAGER)).contains("refund paid slots"), "29 live +1 reserved at30 must permit refund recovery")
	player.population = 18
	player.population_cap = 15
	controller.call("_refresh")
	_expect(str((overview.get("_population") as Label).text).contains("Refunds alone cannot open"), "lost housing must distinguish live population from reservations")
	_expect(str(controller.call("_training_blocker", tc, UnitData.UnitType.VILLAGER)).contains("build a House"), "surviving workers can rebuild lost housing")
	var own: Array = (_main.get("_player_units") as Array)[0]
	var saved_units: Array = own.duplicate()
	own.clear()
	controller.call("_refresh")
	_expect(str((overview.get("_economy_health") as Label).text).contains("refunds cannot open a slot"), "no-worker housing loss must not claim its paid Scout refund opens a slot")
	_expect(not str(controller.call("_training_blocker", tc, UnitData.UnitType.VILLAGER)).contains("refund"), "over-cap living units cannot be solved by refund alone")
	own.assign(saved_units)
	player.population = 14
	controller.call("_refresh")
	_expect(str((overview.get("_population") as Label).text).contains("refund paid slots or build a House"), "14 live +1 reserved at15 can recover through refund or housing")
	player.population = saved_population
	player.population_cap = saved_cap
	queue.cancel_all()
	controller.call("_refresh")
