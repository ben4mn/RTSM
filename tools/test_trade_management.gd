extends "res://tools/test_ux_redesign_journey.gd"
## Synthetic late-game actors isolate real touch dispatch, finder ownership,
## camera intent and trade-specific controls. This is not a paid-match benchmark.

func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	# A UI fixture must never replace a player's native checkpoint.
	SoloSave._pending = true
	for phone: Vector2i in [Vector2i(667, 375), Vector2i(844, 390)]:
		await _trade_journey(phone)
	for failure: String in _failures: push_error("[FAIL] trade_management: " + failure)
	print(JSON.stringify({"test": "trade_management", "profiles": 2, "failures": _failures, "scope": "real native ScreenTouch dispatch and Main/HUD with synthetic late-game actors; no paid-match or physical-device claim"}))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _trade_journey(phone: Vector2i) -> void:
	_profile = "%dx%d" % [phone.x, phone.y]
	_hud = null
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	GameManager.ui_scale = 1.0
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 4
	GameManager.selected_population_limit = 100
	GameManager.guided_opening_enabled = false
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null: break
		await get_tree().process_frame
	_map = _main.game_map
	_hud = _main.hud
	_selection = _map.selection_mgr
	_main.set_process(false)
	_main.ai_controller.set_process(false)
	_main.ai_controller._decision_timer.stop()
	for unit: Node in get_tree().get_nodes_in_group("units"): unit.set_process(false)
	var controller: Node = _main.get_node("StrategyController")
	controller.set_process(false)
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	await _frames(6)
	controller._refresh()
	await _button(overview._economy_button)
	_expect(not overview._trade_actions.is_visible_in_tree(), "opening has no trade clutter")
	var center: Vector2i = _map.map_generator.get_expansion_pocket_centers()[0]
	var post: BuildingBase = _main._spawn_building(BuildingData.BuildingType.TRADE_POST, 0, center)
	post.complete_instantly()
	post.set_process(false)
	controller._refresh()
	await _frames(4)
	var finder: Button = overview._trader_button
	_expect(finder.is_visible_in_tree() and finder.disabled, "post reserves a stable disabled finder before first trader")
	var finder_rect: Rect2 = finder.get_global_rect()
	var assign_rect: Rect2 = (overview._destination_buttons.food as Button).get_global_rect()
	var active: Trader = _main._spawn_unit(UnitData.UnitType.TRADER, 0, post.global_position + Vector2(80, 0))
	active.set_process(false)
	_expect(active.command_trade(post), "fixture has a real automatic route")
	var paused: Trader = _main._spawn_unit(UnitData.UnitType.TRADER, 0, post.global_position + Vector2(-80, 0))
	paused.set_process(false)
	paused.command_stop()
	var enemy: Trader = _main._spawn_unit(UnitData.UnitType.TRADER, 1, post.global_position + Vector2(40, 80))
	enemy.set_process(false)
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var camera: Vector2 = _map.camera.position
	var selected: Array = _selection.selected.duplicate()
	controller._refresh()
	await _frames(4)
	_expect(overview._snapshot.traders == 2 and overview._snapshot.waiting_traders == 1, "only owned living traders count; paused has attention")
	_expect(finder.get_node("CommandIconBadge").text == "2" and finder.get_node("CommandIconBadge").get_meta("attention"), "finder displays bounded count with waiting cue")
	_expect(finder.get_global_rect() == finder_rect and (overview._destination_buttons.food as Button).get_global_rect() == assign_rect, "first birth changes badge without moving targets")
	_expect(_map.camera.position == camera and _selection.selected == selected, "refresh never moves camera or selection")
	_expect(overview.panel.get_global_rect().encloses(finder.get_global_rect()) and overview._scroll.get_global_rect().encloses(finder.get_global_rect()), "finder stays inside the visible tiny sheet")
	await _capture("trade-workers")
	await _button(finder)
	_expect(_selection.selected == [paused] and _map.camera.position.distance_to(paused.global_position) < 1.0, "first explicit contact finds paused trader before older active trader")
	_expect(paused._manual_pause and active.trade_route_active and ResourceManager.get_all_resources(0) == bank, "finding cannot resume orders or change the bank")
	await _button(overview._economy_button)
	await _button(finder)
	_expect(_selection.selected == [active], "second contact cycles to the active trader")
	paused.current_state = UnitBase.State.DEAD
	controller._refresh()
	_expect(overview._snapshot.traders == 1 and overview._snapshot.waiting_traders == 0, "dead trader disappears from count and attention")
	await _button(overview._economy_button)
	await _button(finder)
	_expect(_selection.selected == [active], "cycling skips dead and enemy traders")
	# A replica has no local route assignment: authoritative trip income is used.
	var old_online: bool = NetworkSession.online
	var old_server: bool = NetworkSession.server_mode
	NetworkSession.online = true
	NetworkSession.server_mode = false
	active.set_meta("network_trade_income", 32)
	_expect(not controller._trader_needs_attention(active), "replica route does not look idle because local route fields are absent")
	active.set_meta("network_trade_income", 0)
	_expect(controller._trader_needs_attention(active), "replica with no confirmed trip income needs attention")
	NetworkSession.online = old_online
	NetworkSession.server_mode = old_server
	_selection.select_single(post)
	await _frames(4)
	_expect(not (_hud.get("_building_rally_button") as Button).is_visible_in_tree(), "selected Trade Post cannot offer an ignored rally flag")
	_expect((_hud.get("selection_details") as Label).text.contains("trade"), "selected Trade Post names its automatic route")
	await _capture("trade-post")
	controller._refresh()
	await _button(overview._economy_button)
	await _button(overview._production_tab)
	overview._economy_producer_id = post.get_instance_id()
	overview._refresh_pages()
	await _frames(4)
	var row: Dictionary = overview._producer_rows[post.get_instance_id()]
	_expect(not row.rally.is_visible_in_tree() and not row.sacred.is_visible_in_tree(), "post overview hides army and Sacred rally actions")
	_expect(finder.is_visible_in_tree() and overview._scroll.get_global_rect().encloses(finder.get_global_rect()), "trade production keeps the finder reachable")
	await _capture("trade-production")
	await _button(overview._info_button)
	var information: String = ""
	for line: Label in overview._detail_lines: information += line.text + "\n"
	_expect(information.contains("Gold pays on return") and information.contains("Move or Stop pauses trade"), "Info explains payment and deliberate recovery")
	_expect(not finder.is_visible_in_tree(), "Info replaces actions without duplicating persistent help")
	await _button(overview._info_button)
	var tc: BuildingBase = _main._player_town_center
	overview._economy_producer_id = tc.get_instance_id()
	overview._refresh_pages()
	await _frames(3)
	_expect(overview._producer_rows[tc.get_instance_id()].rallies.is_visible_in_tree(), "ordinary Town Center rally controls remain")
	_hud.close_secondary_surface()
	_selection.select_single(tc)
	await _frames(3)
	_expect((_hud.get("_building_rally_button") as Button).is_visible_in_tree(), "Town Center flag remains available")
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)
