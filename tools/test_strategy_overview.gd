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
	# Deliberate logical stress size, separate from the twelve device profiles.
	await _strategy_journey(Vector2i(550, 338), 1.0, false, Vector2i(550, 338))
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("strategy-overview-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"profiles": _receipts, "failures": _failures, "scope": "Twelve device profiles plus a separate 550x338 logical geometry stress case. Engine ScreenTouch dispatch; ordinary starting resources, paid House and Scout; controlled construction/training time; no physical device claim."}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] strategy_overview: " + failure)
	if _failures.is_empty():
		print("[PASS] strategy_overview: 12 phone/scale/notch profiles plus 550x338 logical stress; 48px persistent navigation, army-preserving paid training/refund/repeat/rally, explicit worker reallocation, two saved groups, bounded worker/producer pages with owned gesture boundaries and outside dismissal with no world orders")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _strategy_journey(phone: Vector2i, interface_scale: float, notched: bool, logical_size: Vector2i = Vector2i(844, 390)) -> void:
	_profile = "%dx%d-scale%.3f-%s" % [phone.x, phone.y, interface_scale, "notched" if notched else "ordinary"]
	_synthetic_notch = notched
	_hud = null
	get_window().size = phone
	get_window().content_scale_size = logical_size
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
		_expect(action.icon != null and action.text.is_empty() and not action.tooltip_text.is_empty() and action.accessibility_name == action.tooltip_text, "compact rail loses icon or full action name: " + str(action.name))
		_expect(action.size.is_equal_approx(Vector2(48, 48)), "persistent icon must remain a true 48px square: " + str(action.name))
		var hover_pressed: StyleBox = action.get_theme_stylebox("hover_pressed")
		_expect(action.theme == overview.theme and hover_pressed is StyleBoxTexture and (hover_pressed as StyleBoxTexture).texture.resource_path == "res://assets/ui/plates/secondary_pressed.svg", "selected hover must use the custom command plate, not the Godot fallback: " + str(action.name))
		_expect(action.get_theme_color("font_hover_pressed_color").is_equal_approx(KingdomTheme.INK) and action.get_theme_color("icon_hover_pressed_color").is_equal_approx(KingdomTheme.INK), "selected hover text and icon must contrast with the selected plate: " + str(action.name))
		var focus: StyleBox = action.get_theme_stylebox("focus")
		_expect(focus is StyleBoxTexture and (focus as StyleBoxTexture).texture.resource_path == "res://assets/ui/plates/secondary_focus.svg", "strategy icon focus must use the custom outline: " + str(action.name))
	_expect(overview.rail.size.is_equal_approx(Vector2(156, 48)), "strategy rail must use three 48px squares with 6px gaps")
	_expect(overview.get_visible_bounds().has(overview.rail.get_global_rect()), "compact rail omitted from camera occlusion")
	# The rail follows both dock heights rather than keeping a producer-sized gap.
	var held_area: Rect2 = _hud.call("get_hold_safe_rect")
	for dock_height: float in [64.0, 72.0]:
		overview.apply_layout(safe, true, held_area, dock_height)
		_expect(is_equal_approx(overview.rail.get_rect().end.y, safe.end.y - dock_height - 16.0), "strategy rail ignores the current selection dock height")
	_hud.call("_apply_mobile_layout_for_current_viewport")
	await _frames(2)
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
	var economy_button: Button = overview.rail.get_node("EconomyButton")
	var army_button: Button = overview.rail.get_node("ArmyButton")
	_expect(economy_button.button_pressed and not army_button.button_pressed, "expanded Economy lacks exclusive selected state")
	var army_badge: Label = army_button.get_node("CommandIconBadge")
	var economy_badge: Label = economy_button.get_node("CommandIconBadge")
	_expect(army_badge.visible and army_badge.text == "1" and army_badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Army badge must show the paid Scout without intercepting contacts")
	var snapshot: Dictionary = overview.get("_snapshot")
	var workers: Dictionary = snapshot.get("workers", {})
	var attention: bool = not str((snapshot.get("economy", {}) as Dictionary).get("attention", "")).is_empty()
	for resource: String in ["food", "wood", "gold"]:
		if int(workers.get(resource, 0)) == 0:
			attention = true
			_expect(economy_button.tooltip_text.contains("No " + resource) and (overview.get("_economy_health") as Label).text.contains("No " + resource), "unstaffed job warning must remain in the tooltip and expanded sheet")
	_expect(economy_badge.visible == attention and (not attention or economy_badge.text == "!") and economy_badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Economy badge loses current attention or intercepts contacts")
	var economy_identity: int = economy_button.get_instance_id()
	controller.call("_refresh")
	await _frames(2)
	_expect(economy_button.get_instance_id() == economy_identity and economy_button.button_pressed and economy_button.text.is_empty(), "snapshot refresh replaces or expands the selected icon launcher")
	await _button(economy_button)
	_expect(_hud.call("get_secondary_surface_name") == "none" and not economy_button.button_pressed and _orders == 0, "second Economy icon tap fails to collapse safely")
	await _button(economy_button)
	_expect(safe.encloses(overview.panel.get_global_rect()), "economy sheet outside safe bounds")
	_expect(not overview.panel.get_global_rect().intersects(overview.rail.get_global_rect()), "management sheet covers its persistent launchers")
	_expect(overview.panel.size.x >= overview.panel.get_combined_minimum_size().x, "management content exceeds the reserved-rail sheet width")
	_expect(overview.panel.get_global_rect().end.x <= overview.rail.get_global_rect().position.x - 7.5, "sheet minimum consumes the reserved 8px launcher gap")
	_expect(overview.panel.size.x <= 480.5, "management sheet exceeds the compact 480px maximum")
	var economy_height: float = overview.panel.size.y
	var farm_button: Button = overview.get("_farm_button")
	_expect(farm_button.text.contains("75W") and farm_button.text.contains("Unlimited food"), "Farm loses its visible paid cost and permanent food")
	_expect((overview.get("_farm_blocker") as Label).text == str(snapshot.get("farm_blocker", "")), "Farm blocker or paid-placement instruction was discarded")
	var scroll: ScrollContainer = overview.get("_scroll")
	await _check_info_page(overview, false)
	await _check_wheel_ownership(overview, false)
	var chip_width: float = ((overview.get("_source_buttons") as Dictionary)["idle"] as Button).custom_minimum_size.x
	_expect(chip_width >= 80.0 and chip_width <= 96.0, "job grid width leaves the readable 80–96px range")
	if logical_size.x == 550:
		_expect(get_viewport().get_visible_rect().size.x <= 550.5 and chip_width < 96.0, "narrow stress must use the actual 550px logical viewport and adapted chips")
	var rows: Dictionary = overview.get("_producer_rows")
	var row: Dictionary = rows[tc.get_instance_id()]
	var train: Button = row.train[UnitData.UnitType.VILLAGER]
	_expect((row.repeat as Button).text.contains("Scout") and (row.repeat as Button).text.contains("OFF"), "Repeat must visibly identify the previously paid Scout and its OFF state")
	var villager_food_cost: int = int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).get("food", 0))
	_expect(train.icon != null and train.text.contains("Villager") and train.text.contains("%dF" % villager_food_cost), "remote producer loses unit portrait, name or paid cost")
	_expect(train.size.is_equal_approx(Vector2(156, 48)), "remote training card expands beyond its deliberate 156x48 rectangle")
	for resource: String in ["idle", "food", "wood", "gold"]:
		var source_button: Button = (overview.get("_source_buttons") as Dictionary)[resource]
		_expect(source_button.icon != null and source_button.text.contains(resource.capitalize()), "worker source icon loses its explicit job name")
		_expect(source_button.size.is_equal_approx(Vector2(chip_width, 48)), "source job chip breaks the equal 48px-high grid: " + resource)
		_check_caption_fit(source_button)
	for resource: String in ["food", "wood", "gold"]:
		var destination: Button = (overview.get("_destination_buttons") as Dictionary)[resource]
		_expect(destination.size.is_equal_approx(Vector2(chip_width, 48)) and destination.text.contains(resource.capitalize()), "destination job chip loses its equal grid or job name: " + resource)
		_check_caption_fit(destination)
	_expect((overview.get("_idle_button") as Button).size.is_equal_approx(Vector2(chip_width, 48)), "Find idle must complete the same job grid")
	for action: Button in [row.repeat, row.undo, row.clear]:
		_expect(action.size.y == 48.0 and action.size.x <= 120.5 and action.size.x >= 104.0, "paid producer action breaks the compact captioned proportions: " + str(action.name))
		_expect(is_equal_approx(action.size.x, (row.repeat as Button).size.x), "producer captions force unequal button widths: " + str(action.name))
		_check_caption_fit(action)
	var repeat_preview := Button.new()
	repeat_preview.theme = overview.theme
	for unit_type: int in UnitData.UNITS:
		StrategyOverview.apply_repeat_caption(repeat_preview, unit_type, true)
		_check_caption_fit(row.repeat, repeat_preview.text)
		_expect(repeat_preview.accessibility_name.contains(UnitData.get_unit_name(unit_type)) and repeat_preview.accessibility_name == repeat_preview.tooltip_text, "Repeat accessible action loses the full unit name")
		if unit_type == UnitData.UnitType.SIEGE:
			_expect(repeat_preview.text == "Siege\nON" and repeat_preview.accessibility_name.contains("Repeat Siege Engine: ON") and UnitData.get_unit_name(unit_type) == "Siege Engine", "Siege Repeat alias must retain its full accessible and recruitment name")
	repeat_preview.free()
	await _button(overview.get("_production_tab"))
	await _frames(3)
	_expect(not (overview.get("_farm_button") as Control).is_visible_in_tree(), "Train page failed to hide worker actions")
	await _overview_button(overview, train)
	var bank_after_train: int = ResourceManager.get_resource(0, "food")
	_expect(queue.queue == [UnitData.UnitType.VILLAGER] and int(GameManager.players[0].population_reserved) == 1, "overview Train must pay and reserve one unit")
	await _check_info_page(overview, true)
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
	await _button(overview.get("_workers_tab"))
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
	var outside: Vector2 = safe.position + Vector2(4, 80)
	_expect(not overview.panel.get_global_rect().has_point(outside), "dismissal contact must remain outside the relocated sheet")
	await _tap(outside)
	_expect(_hud.call("get_secondary_surface_name") == "none", "outside contact did not close economy")
	await _button(overview.rail.get_node("ArmyButton"))
	_expect(army_button.button_pressed and not economy_button.button_pressed, "expanded Army lacks exclusive selected state")
	_expect(overview.panel.size.y < economy_height and overview.panel.size.y <= 260.0, "Army sheet retains the tall Economy height instead of fitting its rows")
	_expect(safe.encloses(overview.panel.get_global_rect()) and not overview.panel.get_global_rect().intersects(overview.rail.get_global_rect()), "compact Army sheet must stay safe and leave launchers reachable")
	await _check_wheel_ownership(overview, false)
	var groups: Dictionary = overview.get("_group_rows")
	_expect((groups[1].save as Button).icon != null and (groups[1].save as Button).text == "Save" and (groups[1].recall as Button).icon != null and (groups[1].recall as Button).text == "Recall", "group controls lose understandable icon captions")
	for index: int in [1, 2]:
		_expect((groups[index].save as Button).size.is_equal_approx(Vector2(104, 48)) and (groups[index].recall as Button).size.is_equal_approx(Vector2(104, 48)), "group actions must share the same 104x48 proportions")
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


func _check_info_page(overview: StrategyOverview, production: bool) -> void:
	var info: Button = overview.get("_info_button")
	_expect(info.size.is_equal_approx(Vector2(48, 48)) and info.icon != null, "Info must be a 48px touch target")
	await _button(info)
	await _frames(3)
	var details: Control = overview.get("_details")
	_expect(details.is_visible_in_tree() and not (overview.get("_economy") as Control).is_visible_in_tree(), "Info must replace action rows with details")
	_expect(info.button_pressed and info.tooltip_text == "Back to actions", "Info must identify its return action")
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	_expect(safe.encloses(overview.panel.get_global_rect()) and overview.panel.size.y <= 240.5, "details page must remain bounded within 240px and the safe area")
	_expect(not overview.panel.get_global_rect().intersects(overview.rail.get_global_rect()), "Info header consumes the rail gap")
	var scroll: ScrollContainer = overview.get("_scroll")
	_expect(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "details must not require scrolling")
	var text: String = _visible_detail_text(overview)
	if production:
		_expect(text.contains("Villager") and text.contains("50F") and text.contains("Recon") and text.contains("Training:") and text.contains("Paid: Villager ×1") and text.contains("Rally:"), "producer Info omits roles, cost, blockers, paid queue or rally")
	else:
		_expect(text.contains("recovering") and text.contains("Population") and text.contains("Visible berry food") and text.contains("permanent Farms"), "worker Info omits recovery, population or observed food stock")
	for line: Label in overview.get("_detail_lines"):
		if line.is_visible_in_tree():
			_expect(scroll.get_global_rect().grow(1).encloses(line.get_global_rect()), "detail text falls outside the unscrolled content: " + line.text)
	# Update the existing page while it stays open: no close/reopen is required.
	var original: Dictionary = overview.get("_snapshot")
	var changed: Dictionary = original.duplicate(true)
	if production:
		(changed.producers[0] as Dictionary)["status"] = "Live producer status"
	else:
		(changed.economy_facts as Dictionary)["berry_food"] = 73
	overview.update_snapshot(changed)
	await _frames(2)
	_expect(_visible_detail_text(overview).contains("Live producer status" if production else "Visible berry food 73"), "open Info page did not refresh with its snapshot")
	overview.update_snapshot(original)
	await _capture("production-info" if production else "workers-info")
	await _button(info)
	_expect(not details.is_visible_in_tree() and (overview.get("_economy") as Control).is_visible_in_tree() and _orders == 0, "Back must restore actions without a world order")


func _visible_detail_text(overview: StrategyOverview) -> String:
	var parts: PackedStringArray = []
	for line: Label in overview.get("_detail_lines"):
		if line.is_visible_in_tree():
			parts.append(line.text)
	return "\n".join(parts)


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
	var outside: Vector2 = safe.position + Vector2(4, 80)
	_expect(not overview.panel.get_global_rect().has_point(outside), "outside wheel contact must remain outside the relocated sheet")
	var shield: Control = _hud.get("_secondary_dismissal_shield")
	_expect(shield.visible and shield.call("_has_point", outside - shield.global_position), "outside wheel fixture must belong to active dismissal shield")
	await _overview_wheel(outside, MOUSE_BUTTON_WHEEL_UP)
	await _overview_wheel(outside, MOUSE_BUTTON_WHEEL_DOWN)
	_expect(camera.zoom.is_equal_approx(zoom_before) and camera.position.is_equal_approx(position_before), surface + " header/button/padding wheel changed camera")
	_expect(_selection.selected == selection_before and _hud.call("get_secondary_surface_name") == surface, surface + " wheel changed selection or dismissed sheet")
	scroll.scroll_vertical = 0
	await _frames(2)


func _check_caption_fit(button: Button, caption: String = "") -> void:
	var text: String = button.text if caption.is_empty() else caption
	var font: Font = button.get_theme_font("font")
	var font_size: int = button.get_theme_font_size("font_size")
	var text_size: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var icon_size: Vector2 = button.icon.get_size() if button.icon != null else Vector2.ZERO
	var icon_limit: float = float(button.get_theme_constant("icon_max_width"))
	if icon_limit > 0.0 and icon_size.x > icon_limit:
		icon_size *= icon_limit / icon_size.x
	var padding: Vector2 = button.get_theme_stylebox("normal").get_minimum_size()
	var gap: float = float(button.get_theme_constant("h_separation")) if icon_size.x > 0.0 and not text.is_empty() else 0.0
	var required := Vector2(text_size.x + icon_size.x + gap, maxf(text_size.y, icon_size.y)) + padding
	_expect(required.x <= button.size.x + 0.5 and required.y <= button.size.y + 0.5, "visible caption/icon exceed button: %s %s; required=%s actual=%s" % [button.name, text.replace("\n", "/"), required, button.size])


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
	_expect(scroll.get_global_rect().encloses(button.get_global_rect()), "management action clipped: %s; scroll=%s action=%s" % [button.name, scroll.get_global_rect(), button.get_global_rect()])
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
