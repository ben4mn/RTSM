extends "res://tools/test_strategy_overview.gd"
## Real worker Stop -> visible idle count -> explicit touch allocation.
## Units and economy are frozen for deterministic UI/geometry assertions.


func _apply_profile_layout() -> void:
	if _synthetic_notch:
		super._apply_profile_layout()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _idle_journey(phone, interface_scale, notched)
	for failure: String in _failures:
		push_error("[FAIL] strategy_idle_attention: " + failure)
	if _failures.is_empty():
		print("[PASS] strategy_idle_attention: 12 phone/scale/notch profiles; real idle worker visible with every resource staffed, explicit touch allocation clears count without changing selection/bank; urgent food precedence, bounded 99+ badge, no automatic jobs")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _idle_journey(phone: Vector2i, interface_scale: float, notched: bool) -> void:
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
	GameManager.guided_opening_enabled = false
	await _frames(3)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
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
	await _frames(6)
	_main.call("_update_fog_of_war")
	var workers: Array = (_main.get("_player_units")[0] as Array).filter(func(unit: UnitBase) -> bool: return unit is Villager)
	var idle_worker: Villager = null
	for worker: Villager in workers:
		if controller.call("_worker_source", worker) == "food":
			idle_worker = worker
			break
	_expect(idle_worker != null, "starting economy needs a real food worker")
	if idle_worker == null:
		_main.free()
		_main = null
		return
	idle_worker.command_stop()
	_selection.select_single(_main.get("_player_town_center"))
	controller.call("_refresh")
	await _frames(3)
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	var snapshot: Dictionary = overview.get("_snapshot")
	var observed: Dictionary = snapshot.get("workers", {})
	_expect(int(observed.get("idle", 0)) == 1, "Stop must produce exactly one observed idle worker")
	for resource: String in ["food", "wood", "gold"]:
		_expect(int(observed.get(resource, 0)) > 0, "regression requires staffed " + resource)
	_expect(str((snapshot.get("economy", {}) as Dictionary).get("attention", "")).is_empty(), "idle badge must not rely on a food/job warning")
	var button: Button = overview.rail.get_node("EconomyButton")
	var badge: Label = button.get_node("CommandIconBadge")
	_expect(button.text == "Economy" and badge.visible and badge.text == "1" and bool(badge.get_meta("attention", false)), "staffed economy hides idle count")
	_expect(button.accessibility_name.contains("1 idle worker.") and button.tooltip_text == button.accessibility_name, "idle count needs an explicit accessible meaning")
	_expect(badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "count cannot intercept the launcher tap")
	var selection_before: Array = _selection.selected.duplicate()
	var bank_before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _button(button)
	_expect(_hud.call("get_secondary_surface_name") == "economy", "count overlay blocks Economy touch")
	var summary: Label = overview.get("_summary")
	_expect(summary.text == "1 idle · choose Idle, then a job.", "panel must explain the idle action visibly")
	_expect(idle_worker.current_state == UnitBase.State.IDLE, "opening Economy must not assign a job")
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	_expect(safe.encloses(overview.panel.get_global_rect()) and button.get_global_rect().encloses(badge.get_global_rect()), "idle cue escapes the safe panel/button")
	var width: float = summary.get_theme_font("font").get_string_size(summary.text, HORIZONTAL_ALIGNMENT_LEFT, -1, summary.get_theme_font_size("font_size")).x
	_expect(width <= summary.size.x and summary.get_visible_line_count() == 1, "idle instruction must fit one visible line")
	await _capture("idle-worker-attention")
	await _button(overview.get("_source_buttons")["idle"])
	await _button(overview.get("_destination_buttons")["food"])
	_expect(controller.call("_worker_source", idle_worker) == "food", "explicit touch must assign the idle worker to visible food")
	_expect(not badge.visible and not button.accessibility_name.contains("idle worker"), "accepted assignment must clear the stale idle count")
	_expect(_selection.selected == selection_before and ResourceManager.get_all_resources(0) == bank_before, "management touch must preserve selected Town Center and resources")
	var live_snapshot: Dictionary = overview.get("_snapshot").duplicate(true)
	# Synthetic maximum/priority typography, separate from the real Stop/assign proof.
	var fixture: Dictionary = live_snapshot.duplicate(true)
	fixture.workers.idle = 150
	overview.update_snapshot(fixture)
	await _frames(2)
	_expect(badge.text == "99+" and button.get_global_rect().encloses(badge.get_global_rect()), "large idle count must remain bounded to the launcher")
	fixture.food_attention_ready = true
	overview.update_snapshot(fixture)
	_expect(summary.text == "No food · assign food workers.", "idle cue cannot displace urgent food instructions")
	fixture.food_attention_ready = false
	fixture.food_low_attention_ready = true
	overview.update_snapshot(fixture)
	_expect(summary.text == "Food low · scout or build a Farm.", "idle cue cannot displace the food transition warning")
	overview.update_snapshot(live_snapshot)
	_expect(not badge.visible and idle_worker.current_state != UnitBase.State.IDLE, "clearing fixture must restore observed workers without new orders")
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)
