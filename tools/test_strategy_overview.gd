extends "res://tools/test_ux_redesign_journey.gd"
## Real contacts on both phone sizes/scales/safe areas; paid management while
## an army remains selected. Production time is advanced only for fixture setup.

func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _strategy_journey(phone, interface_scale, notched)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("strategy-overview-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"profiles": _receipts, "failures": _failures, "scope": "Engine ScreenTouch dispatch; ordinary starting resources, paid House and Scout; controlled construction/training time; no physical device claim."}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] strategy_overview: " + failure)
	if _failures.is_empty():
		print("[PASS] strategy_overview: 12 phone/scale/notch profiles; 48px persistent navigation, army-preserving paid training/refund/repeat/rally, explicit worker reallocation, two saved groups, touch/wheel scrolling with owned top/bottom/header boundaries and outside dismissal with no world orders")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _strategy_journey(phone: Vector2i, interface_scale: float, notched: bool) -> void:
	_profile = "%dx%d-scale%.3f-%s" % [phone.x, phone.y, interface_scale, "notched" if notched else "ordinary"]
	_synthetic_notch = notched
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
	var queue: ProductionQueue = tc.get_production_queue() as ProductionQueue
	var before_house: int = ResourceManager.get_resource(0, "wood")
	var house: BuildingBase = _paid_house()
	_expect(house != null and ResourceManager.get_resource(0, "wood") == before_house - 50, "House fixture must use paid legal placement")
	if house:
		house.complete_instantly()
	_main.call("_on_train_unit_requested", tc, UnitData.UnitType.SCOUT)
	_expect(queue.queue == [UnitData.UnitType.SCOUT], "Scout fixture was not paid")
	queue.advance(queue.current_train_time)
	var scout: UnitBase = _main.get("_player_units")[0].back()
	scout.set_process(false)
	_expect(scout.unit_type == UnitData.UnitType.SCOUT, "paid Scout not spawned")
	_selection.select_single(scout)
	controller.call("_refresh")
	await _frames(3)
	var camera: Vector2 = _map.get("camera").position
	_orders = 0
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	_selection.attack_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.gather_command.connect(func(_target: Node2D) -> void: _orders += 1)
	_selection.build_command.connect(func(_target: Node2D) -> void: _orders += 1)
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	for action: Button in overview.rail.get_children():
		_expect(action.is_visible_in_tree() and action.size.x >= 48 and action.size.y >= 48 and safe.encloses(action.get_global_rect()), "persistent rail unsafe: " + str(action.name))
	await _button(_hud.get("_unit_more_button"))
	var more: Control = _hud.get("_advanced_command_panel")
	_expect(not more.get_global_rect().intersects(overview.rail.get_global_rect()), "More overlaps persistent strategy navigation")
	await _button(_hud.get("_unit_more_button"))
	await _button(_hud.get("_camera_view_button"))
	var camera_controls: Control = _hud.get("_camera_controls")
	for action: Button in camera_controls.get_children():
		if action.is_visible_in_tree():
			_expect(not action.get_global_rect().intersects(overview.rail.get_global_rect()), "expanded View overlaps persistent strategy navigation")
	await _button(_hud.get("_camera_view_button"))
	await _button(overview.rail.get_node("EconomyButton"))
	_expect(_hud.call("get_secondary_surface_name") == "economy", "Economy did not open")
	_expect(safe.encloses(overview.panel.get_global_rect()), "economy sheet outside safe bounds")
	var scroll: ScrollContainer = overview.get("_scroll")
	await _check_wheel_ownership(overview, true)
	var rows: Dictionary = overview.get("_producer_rows")
	var row: Dictionary = rows[tc.get_instance_id()]
	var train: Button = row.train[UnitData.UnitType.VILLAGER]
	await _overview_button(overview, train)
	var bank_after_train: int = ResourceManager.get_resource(0, "food")
	_expect(queue.queue == [UnitData.UnitType.VILLAGER] and int(GameManager.players[0].population_reserved) == 1, "overview Train must pay and reserve one unit")
	await _overview_button(overview, row.repeat)
	_expect(queue.auto_queue_enabled, "overview Repeat did not turn on")
	await _overview_button(overview, row.rally)
	_expect(tc.has_custom_rally_point() and _map.world_to_tile(tc.rally_point) == _map.world_to_tile(scout.global_position), "Rally to army did not use selected army position")
	await _overview_button(overview, row.clear)
	_expect(queue.queue.is_empty() and not queue.auto_queue_enabled and int(GameManager.players[0].population_reserved) == 0, "Clear must stop Repeat and release reservation")
	_expect(ResourceManager.get_resource(0, "food") == bank_after_train + 50, "Clear must refund exact paid food")
	_expect(_selection.selected == [scout] and _map.get("camera").position == camera, "production management changed battlefield selection/camera")
	# Stop one worker explicitly, then reassign from the named Idle source.
	var worker: Villager = _main.get("_player_units")[0][0]
	worker.command_stop()
	controller.call("_refresh")
	scroll.scroll_vertical = 0
	await _frames(3)
	await _overview_button(overview, (overview.get("_source_buttons") as Dictionary)["idle"])
	await _overview_button(overview, (overview.get("_destination_buttons") as Dictionary)["gold"])
	_expect(worker.get_economy_task() == "gold", "explicit Idle→Gold reallocation failed")
	_expect(_selection.selected == [scout] and _map.get("camera").position == camera, "worker management changed battlefield selection/camera")
	await _capture("economy-army-retained")
	# A sheet drag and retained outside-dismissal contact must never issue a move.
	var center: Vector2 = scroll.get_global_rect().get_center()
	await _contact_drag(center, center - Vector2(0, 75))
	await _tap(Vector2(safe.position.x + 8, safe.position.y + 80))
	_expect(_hud.call("get_secondary_surface_name") == "none", "outside contact did not close economy")
	await _button(overview.rail.get_node("ArmyButton"))
	await _check_wheel_ownership(overview, false)
	var groups: Dictionary = overview.get("_group_rows")
	await _overview_button(overview, groups[1].save)
	await _overview_button(overview, groups[2].save)
	_expect(_main.get("_control_groups")[1] == [scout] and _main.get("_control_groups")[2] == [scout], "two visible Save buttons did not save own selected army")
	await _capture("army-groups")
	await _overview_button(overview, groups[1].recall)
	_expect(_selection.selected == [scout] and _hud.call("get_secondary_surface_name") == "none", "Recall did not preserve army and return to field")
	_expect(_orders == 0, "GUI contacts emitted %d world orders" % _orders)
	_receipts.append({"profile": _profile, "army_retained": _selection.selected == [scout], "world_orders": _orders, "paid_refund": ResourceManager.get_resource(0, "food") == bank_after_train + 50, "sheet_bounds": str(overview.panel.get_global_rect()), "safe": str(safe)})
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)


func _check_wheel_ownership(overview: StrategyOverview, expects_scrolling: bool) -> void:
	var scroll: ScrollContainer = overview.get("_scroll")
	var camera: Camera2D = _map.get("camera")
	var position_before: Vector2 = camera.position
	var zoom_before: Vector2 = camera.zoom
	var selection_before: Array = _selection.selected.duplicate()
	var surface: String = _hud.call("get_secondary_surface_name")
	scroll.scroll_vertical = 0
	await _frames(2)
	var center: Vector2 = scroll.get_global_rect().get_center()
	await _overview_wheel(center, MOUSE_BUTTON_WHEEL_UP)
	_expect(scroll.scroll_vertical == 0, surface + " wheel crossed top scroll limit")
	_expect(camera.zoom.is_equal_approx(zoom_before), surface + " top-limit wheel leaked map zoom")
	await _overview_wheel(center, MOUSE_BUTTON_WHEEL_DOWN)
	if expects_scrolling:
		_expect(scroll.scroll_vertical > 0, "Economy wheel did not scroll real content")
	_expect(camera.zoom.is_equal_approx(zoom_before), surface + " scrolling wheel leaked map zoom")
	scroll.scroll_vertical = int(ceilf(scroll.get_v_scroll_bar().max_value))
	await _frames(2)
	var bottom: int = scroll.scroll_vertical
	await _overview_wheel(center, MOUSE_BUTTON_WHEEL_DOWN)
	_expect(scroll.scroll_vertical == bottom, surface + " wheel crossed bottom scroll limit")
	_expect(camera.zoom.is_equal_approx(zoom_before), surface + " bottom-limit wheel leaked map zoom")
	await _overview_wheel(center, MOUSE_BUTTON_WHEEL_UP)
	if expects_scrolling:
		_expect(scroll.scroll_vertical < bottom, "Economy upward wheel did not scroll real content")
	var title: Label = overview.get("_title")
	await _overview_wheel(title.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP)
	await _overview_wheel(overview.panel.find_child("CloseStrategyButton", true, false).get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	await _overview_wheel(overview.panel.get_global_rect().position + Vector2(3, 3), MOUSE_BUTTON_WHEEL_UP)
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	var outside: Vector2 = safe.position + Vector2(8, 80)
	var shield: Control = _hud.get("_secondary_dismissal_shield")
	_expect(shield.visible and shield.call("_has_point", outside - shield.global_position), "outside wheel fixture must belong to active dismissal shield")
	await _overview_wheel(outside, MOUSE_BUTTON_WHEEL_UP)
	await _overview_wheel(outside, MOUSE_BUTTON_WHEEL_DOWN)
	_expect(camera.zoom.is_equal_approx(zoom_before) and camera.position.is_equal_approx(position_before), surface + " header/button/padding wheel changed camera")
	_expect(_selection.selected == selection_before and _hud.call("get_secondary_surface_name") == surface, surface + " wheel changed selection or dismissed sheet")
	scroll.scroll_vertical = 0
	await _frames(2)


func _overview_wheel(position: Vector2, direction: int) -> void:
	var camera: Camera2D = _map.get("camera")
	var position_before: Vector2 = camera.position
	var zoom_before: Vector2 = camera.zoom
	var motion := InputEventMouseMotion.new()
	motion.position = get_viewport().get_final_transform() * position
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await _frames(1)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.global_position = motion.position
		event.button_index = direction
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(1)
	_expect(camera.zoom.is_equal_approx(zoom_before) and camera.position.is_equal_approx(position_before), "sheet wheel %d at %s leaked to camera" % [direction, position])


func _paid_house() -> BuildingBase:
	var placement: BuildingPlacement = _main.get("_building_placement")
	var anchor: Vector2i = _map.get("map_generator").spawn_positions[0]
	for radius: int in range(5, 10):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var point: Vector2 = _map.tile_to_world(anchor + Vector2i(dx, dy))
				if placement.revalidate_confirmation(BuildingData.BuildingType.HOUSE, point, 0):
					_main.call("_on_placement_confirmed", BuildingData.BuildingType.HOUSE, point)
					return _main.get("_player_buildings")[0].back()
	return null


func _overview_button(overview: StrategyOverview, button: Button) -> void:
	var scroll: ScrollContainer = overview.get("_scroll")
	scroll.ensure_control_visible(button)
	await _frames(3)
	_expect(scroll.get_global_rect().encloses(button.get_global_rect()), "management action clipped: " + str(button.name))
	await _button(button)


func _contact_drag(start: Vector2, finish: Vector2) -> void:
	_contact_id += 1
	var press := InputEventScreenTouch.new()
	press.index = _contact_id
	press.position = get_viewport().get_final_transform() * start
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(2)
	var drag := InputEventScreenDrag.new()
	drag.index = _contact_id
	drag.position = get_viewport().get_final_transform() * finish
	drag.relative = get_viewport().get_final_transform().basis_xform(finish - start)
	Input.parse_input_event(drag)
	await _frames(2)
	press.pressed = false
	press.position = drag.position
	Input.parse_input_event(press)
	await _frames(2)
