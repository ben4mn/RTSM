extends "res://tools/test_ux_redesign_journey.gd"
## Real Main and ScreenTouch dispatch with controlled banks and frozen units.
## The optional guide never gates paid Age Up; only accepted player food orders
## complete Gather. This is a functional fixture, not ordinary-match evidence.

var _accepted_allocations: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _apply_profile_layout() -> void:
	if _synthetic_notch:
		super._apply_profile_layout()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _guided_journey(phone, interface_scale, notched)
	for failure: String in _failures:
		push_error("[FAIL] guided_optional_actions: " + failure)
	if _failures.is_empty():
		print("[PASS] guided_optional_actions: 12 phone/scale/notch profiles; guided own-TC Age Up survives resource/layout refresh and pause, exact paid touch transaction; only accepted player food allocation advances Gather; automatic, authority-only, rejected, nonfood and unacknowledged client requests do not")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _guided_journey(phone: Vector2i, interface_scale: float, notched: bool) -> void:
	_profile = "%dx%d-scale%.3f-%s" % [phone.x, phone.y, interface_scale, "notched" if notched else "ordinary"]
	_synthetic_notch = notched
	_hud = null
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = interface_scale
	GameManager.ui_scale = interface_scale
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_population_limit = 30
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.selected_opponent_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.guided_opening_enabled = true
	await _frames(3)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_expect(_main.get("_player_town_center") != null, "real match must finish initialization")
	if _main.get("_player_town_center") == null:
		_main.free()
		_main = null
		return
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
	_accepted_allocations.clear()
	controller.connect("worker_allocation_accepted", _record_allocation)
	await _frames(6)
	_main.call("_update_fog_of_war")
	var workers: Array = (_main.get("_player_units")[0] as Array).filter(func(unit: UnitBase) -> bool: return unit is Villager)
	var automatic_food: int = 0
	for worker: Villager in workers:
		if controller.call("_worker_source", worker) == "food":
			automatic_food += 1
	_expect(automatic_food > 0 and not bool(_main.get("_opening_gather_complete")), "automatic food settlement must not impersonate a player lesson action")
	var tc: BuildingBase = _main.get("_player_town_center")
	_selection.select_single(tc)
	_main.call("_update_progression_hint")
	await _frames(4)
	var age_button: Button = _hud.get("age_up_button")
	_expect(bool(_main.get("_guided_opening_active")) and bool(_hud.get("_early_game_ui_active")), "guide must remain active for the Age Up regression")
	_expect(age_button.is_visible_in_tree(), "guide hides own Town Center Age Up")
	var cost: Dictionary = GameManager.get_age_up_cost(0, 2)
	_expect(cost == {"food": 250, "gold": 125}, "30-population authoritative Feudal price must match the ordinary public scenario")
	ResourceManager.try_spend(0, ResourceManager.get_all_resources(0))
	ResourceManager.add_resource(0, "food", int(cost.food) - 1)
	ResourceManager.add_resource(0, "gold", int(cost.gold))
	_hud.call("set_early_game_ui_state", true)
	_hud.call("refresh_match_state")
	await _frames(3)
	_expect(age_button.is_visible_in_tree() and age_button.disabled, "guide and bank refresh must retain visible, unaffordable Age Up")
	_expect(age_button.text.contains("250F") and age_button.text.contains("125G"), "Age Up must disclose the authoritative price")
	ResourceManager.add_resource(0, "food", 1)
	await _frames(3)
	_expect(age_button.is_visible_in_tree() and not age_button.disabled, "final food deposit must enable guided Age Up")
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	_expect(safe.encloses(age_button.get_global_rect()) and age_button.size.x >= 48.0 and age_button.size.y >= 48.0, "guided Age Up must fit the safe area as a complete touch target")
	GameManager.set_paused(true)
	await _frames(2)
	_expect(age_button.disabled and GameManager.current_state == GameManager.GameState.PAUSED, "Pause must keep paid Age Up disabled")
	controller.call("_allocate_worker", "wood", "food")
	_expect(_accepted_allocations.is_empty() and not bool(_main.get("_opening_gather_complete")), "paused allocation cannot complete the guide")
	GameManager.set_paused(false)
	await _frames(3)
	_expect(not age_button.disabled, "Resume must restore affordability without skipping the guide")
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _button(age_button)
	_expect(GameManager.get_player_age(0) == 2, "actual guided Age Up touch must advance exactly once")
	for resource: String in ResourceManager.RESOURCE_NAMES:
		_expect(ResourceManager.get_resource(0, resource) == int(bank.get(resource, 0)) - int(cost.get(resource, 0)), "guided Age Up must charge exact " + resource + " cost")
	_expect(bool(_main.get("_guided_opening_active")) and int(_main.get("_guided_stage")) == 0 and not bool(_main.get("_opening_gather_complete")), "Age Up must not fabricate opening progress or dismiss the optional guide")
	_selection.select_single(workers[0])
	await _frames(3)
	_hud.call("set_early_game_ui_state", false)
	_hud.call("set_early_game_ui_state", true)
	await _frames(3)
	_expect(not age_button.is_visible_in_tree(), "guide toggles cannot expose Age Up for worker selection")
	var enemy_tc: BuildingBase = _main.get("_player_buildings")[1][0]
	_hud.call("show_building_selection", "Enemy Town Center", enemy_tc.hp, enemy_tc.max_hp, [], [], enemy_tc)
	_hud.call("set_early_game_ui_state", true)
	await _frames(3)
	_expect(not age_button.is_visible_in_tree(), "optional guide must preserve own-building command authority")
	_selection.select_single(tc)
	await _frames(3)
	_expect(age_button.is_visible_in_tree(), "own TC selection must restore the next supported paid age")
	await _capture("guided-age-up-paid")
	await _check_allocation(controller, workers)
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)


func _check_allocation(controller: Node, workers: Array) -> void:
	for worker: Villager in workers:
		worker.command_stop()
	var authority_result: Dictionary = controller.call("try_allocate_worker", 0, "idle", "food")
	_expect(authority_result.has("worker"), "authority-only fixture must issue a real accepted food assignment")
	_expect(not bool(_main.get("_opening_gather_complete")) and _accepted_allocations.is_empty(), "generic authority API must not impersonate the local player's Economy action")
	controller.call("_allocate_worker", "wood", "food")
	_expect(not bool(_main.get("_opening_gather_complete")) and _accepted_allocations.is_empty(), "rejected empty-source allocation cannot complete Gather")
	NetworkSession.online = true
	controller.call("_allocate_worker", "idle", "food")
	NetworkSession.online = false
	_expect(not bool(_main.get("_opening_gather_complete")) and _accepted_allocations.is_empty(), "unacknowledged client request cannot complete Gather")
	controller.call("_allocate_worker", "idle", "wood")
	_expect(_accepted_allocations == ["wood"] and not bool(_main.get("_opening_gather_complete")), "accepted nonfood assignment must retain Gather")
	controller.call("_refresh")
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	var selection_before: Array = _selection.selected.duplicate()
	var bank_before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _button(overview.rail.get_node("EconomyButton"))
	await _button(overview.get("_source_buttons")["wood"])
	await _button(overview.get("_destination_buttons")["food"])
	_expect(_accepted_allocations == ["wood", "food"] and bool(_main.get("_opening_gather_complete")), "actual Economy food touch must credit its accepted worker assignment once")
	_expect(int(_main.get("_guided_stage")) == 1 and bool(_main.get("_guided_opening_active")), "accepted food assignment must advance only to Build House")
	_expect(_selection.selected == selection_before and ResourceManager.get_all_resources(0) == bank_before, "food allocation must preserve selection and charge no resources")
	_expect(_hud.call("get_secondary_surface_name") == "economy" and not (_hud.get("_progression_hint_panel") as Control).visible, "new guide step must not displace the open Economy sheet")
	await _button(overview.find_child("CloseStrategyButton", true, false) as Button)
	_expect((_hud.get("_progression_hint_panel") as Control).visible, "closing Economy must restore the updated optional lesson")


func _record_allocation(resource_type: String) -> void:
	_accepted_allocations.append(resource_type)
