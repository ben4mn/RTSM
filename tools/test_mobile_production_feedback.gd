extends Node
## Touch queue navigation, paid cancellation and recovery feedback at phone sizes.

var _failures: Array[String] = []
var _selection_revision: int = 0
var _selected_producer_id: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale_factor: float in [1.0, 1.15]:
			await _profile(phone, scale_factor)
	for failure: String in _failures:
		push_error("[FAIL] mobile_production_feedback: " + failure)
	if _failures.is_empty():
		print("[PASS] mobile_production_feedback: four phone/scale profiles; touch Queue/Train/Undo/Clear, paid refunds and producer scroll lifecycle; repeat food/pop/build waiting and unlocked/locked card shortages")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile(phone: Vector2i, scale_factor: float) -> void:
	GameManager.initialize_game()
	GameManager.players[0]["population"] = 3
	GameManager.players[0]["population_cap"] = 30
	ResourceManager.initialize_player(0, {"food": 3000, "wood": 3000, "gold": 3000})
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = scale_factor
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport: Viewport = get_viewport()
	var logical := Vector2i(viewport.get_visible_rect().size)
	var fixture := Node.new()
	add_child(fixture)
	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	fixture.add_child(hud)
	var tc := BuildingBase.new()
	tc.building_type = BuildingData.BuildingType.TOWN_CENTER
	tc.player_owner = 0
	tc.state = BuildingBase.State.ACTIVE
	fixture.add_child(tc)
	var producer := ProductionQueue.new()
	tc.add_child(producer)
	var second := BuildingBase.new()
	second.building_type = BuildingData.BuildingType.BARRACKS
	second.player_owner = 0
	second.state = BuildingBase.State.ACTIVE
	fixture.add_child(second)
	second.add_child(ProductionQueue.new())
	await get_tree().process_frame
	var safe := Rect2(Vector2(44.0 / scale_factor, 0.0), Vector2(logical) - Vector2(88.0 / scale_factor, 18.0 / scale_factor))
	var profile: String = "%s scale %.2f" % [phone, scale_factor]
	hud.cancel_queue_requested.connect(func(building: Node2D, index: int) -> void:
		var production: ProductionQueue = building.get_production_queue()
		if index == ProductionQueue.CANCEL_ALL_INDEX:
			production.cancel_all()
		else:
			production.cancel_unit(index)
		_show(hud, building)
	)
	for unit_type: int in [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT, UnitData.UnitType.VILLAGER]:
		_expect(producer.enqueue_unit(unit_type), profile + " paid queue failed")
	_show(hud, tc)
	await _settle(hud, logical, safe)
	var navigation: Button = hud.get("_queue_navigation_button")
	var shelf: ScrollContainer = hud.get("command_scroll")
	await _queue_selection_cancel(hud,tc,second,viewport,navigation,logical,safe,profile)
	_expect(navigation.visible and not navigation.disabled and navigation.get_node("CommandIconBadge").text == "3", profile + " Queue count/control missing")
	_expect(navigation.size.x >= 48.0 and navigation.size.y >= 48.0, profile + " Queue touch target under48px")
	_expect(safe.encloses(navigation.get_global_rect()), profile + " Queue outside safe area")
	_expect((hud.get("selection_panel") as Control).get_global_rect().encloses(navigation.get_global_rect()), profile + " Queue does not share production shelf")
	for recruit: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
		_expect(shelf.get_global_rect().encloses(recruit.get_global_rect()), profile + " inline pager clips " + String(recruit.name))
	await _tap(viewport, navigation.get_global_rect().get_center())
	_expect(shelf.scroll_horizontal > 0 and navigation.accessibility_name.contains("recruitment"), profile + " Queue touch does not open cancellation page")
	var undo: Button = (hud.get("queue_container") as HBoxContainer).get_node("QueueClearLastButton")
	var clear: Button = (hud.get("queue_container") as HBoxContainer).get_node("QueueClearAllButton")
	_expect(shelf.get_global_rect().encloses(undo.get_global_rect()) and shelf.get_global_rect().encloses(clear.get_global_rect()), profile + " Queue page hides Undo/Clear: shelf %s Undo %s Clear %s" % [shelf.get_global_rect(), undo.get_global_rect(), clear.get_global_rect()])
	var inspected_scroll: int = shelf.scroll_horizontal
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_expect(shelf.scroll_horizontal > 0 and navigation.accessibility_name.contains("recruitment") and _queue_actions_visible(hud), profile + " same producer refresh loses queue inspection: %d -> %d (queue begins %.0f)" % [inspected_scroll, shelf.scroll_horizontal, (hud.get("queue_container") as Control).position.x])
	_show(hud, tc)
	await _tap(viewport, navigation.get_global_rect().get_center(), 0)
	await _settle(hud, logical, safe)
	_expect(shelf.scroll_horizontal == 0, profile + " pending producer refresh overrides deliberate Train return")
	await _tap(viewport, navigation.get_global_rect().get_center())
	var old_restore_revision: int = hud.get("_queue_navigation_revision")
	shelf.scroll_horizontal = 0
	await _queue_press_race(hud, tc, viewport, navigation, logical, safe, old_restore_revision, profile)
	_expect(navigation.accessibility_name.contains("recruitment") and shelf.get_global_rect().encloses(undo.get_global_rect()) and shelf.get_global_rect().encloses(clear.get_global_rect()), profile + " immediate Queue reopen before producer refresh clips refund actions")
	shelf.scroll_horizontal = 0
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_expect(shelf.scroll_horizontal == 0, profile + " producer refresh overrides manual scroll back to Train")
	_expect(hud.call("get_secondary_surface_name") == "none", profile + " manual Train return retains Queue ownership")
	await _tap(viewport, navigation.get_global_rect().get_center())
	_expect(hud.call("get_secondary_surface_name") == "queue" and navigation.accessibility_name.contains("recruitment"), profile + " Queue does not reopen after manual Train return")
	_expect(shelf.get_global_rect().encloses(undo.get_global_rect()) and shelf.get_global_rect().encloses(clear.get_global_rect()), profile + " reopened Queue clips refund actions")
	var food_before: int = ResourceManager.get_resource(0, "food")
	var population_before: int = GameManager.get_committed_population(0)
	await _tap(viewport, undo.get_global_rect().get_center())
	_expect(producer.get_queue_size() == 2, profile + " Undo touch failed")
	_expect(ResourceManager.get_resource(0, "food") == food_before + 50 and GameManager.get_committed_population(0) == population_before - 1, profile + " Undo refund/reservation failed")
	await _tap(viewport, navigation.get_global_rect().get_center())
	_expect(shelf.scroll_horizontal == 0, profile + " Train return touch failed")
	await _tap(viewport, navigation.get_global_rect().get_center())
	_show(hud, second)
	await _settle(hud, logical, safe)
	_expect(shelf.scroll_horizontal == 0, profile + " new producer inherits queue scroll")
	for recruit: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
		_expect(shelf.get_global_rect().encloses(recruit.get_global_rect()), profile + " Barracks clips " + String(recruit.name))
		_expect(recruit.size.x >= 48.0 and recruit.size.y >= 48.0, profile + " Barracks target under48px")
		var available_width: float = recruit.size.x - recruit.get_theme_stylebox("normal").get_minimum_size().x
		for line: String in recruit.text.split("\n"):
			var text_width: float = recruit.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, recruit.get_theme_font_size("font_size")).x
			_expect(text_width <= available_width + 0.5, profile + " Barracks hides text: " + line)
	var saved_resources: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	var second_producer: ProductionQueue = second.get_production_queue()
	second_producer.auto_queue_unit_type = UnitData.UnitType.INFANTRY
	second_producer.auto_queue_enabled = true
	_show(hud, second)
	await _settle(hud, logical, safe)
	var military_repeat: Button = hud.get("_auto_queue_button")
	_expect(military_repeat.text.contains("Need 50F · 20W"), profile + " military Repeat loses a missing resource")
	_expect(shelf.get_global_rect().encloses(military_repeat.get_global_rect()), profile + " military resource wait clips Repeat")
	second_producer.auto_queue_enabled = false
	ResourceManager.initialize_player(0, saved_resources)
	_show(hud, tc)
	await _settle(hud, logical, safe)
	await _tap(viewport, navigation.get_global_rect().get_center())
	clear = (hud.get("queue_container") as HBoxContainer).get_node("QueueClearAllButton")
	producer.auto_queue_enabled = true
	await _tap(viewport, clear.get_global_rect().get_center())
	_expect(producer.get_queue_size() == 0 and not producer.auto_queue_enabled and shelf.scroll_horizontal == 0, profile + " Clear did not stop/reset production")
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	producer.auto_queue_unit_type = UnitData.UnitType.VILLAGER
	producer.auto_queue_enabled = true
	_show(hud, tc)
	await _settle(hud, logical, safe)
	var repeat: Button = hud.get("_auto_queue_button")
	_expect(repeat.text.contains("Need 50F"), profile + " Repeat lacks food shortage")
	# Fractional Window scaling can place anchored edges0.13px apart.
	# A half logical pixel allows rounding, while rejecting actual dock growth.
	var panel_rect: Rect2 = (hud.get("selection_panel") as Control).get_global_rect()
	var dock_rect: Rect2 = (hud.get("_command_dock") as Control).get_global_rect()
	_expect(panel_rect.size.y <= 72.5 and dock_rect.grow(0.5).encloses(panel_rect), profile + " waiting Repeat exceeds integrated72px dock: panel%s dock%s" % [panel_rect, dock_rect])
	_expect(shelf.get_global_rect().encloses(repeat.get_global_rect()), profile + " waiting Repeat icon/text leaves shelf")
	_expect(not navigation.disabled and navigation.get_node("CommandIconBadge").text == "0", profile + " empty waiting Repeat cannot open Clear")
	await _tap(viewport, navigation.get_global_rect().get_center())
	clear = (hud.get("queue_container") as HBoxContainer).get_node("QueueClearAllButton")
	await _tap(viewport, clear.get_global_rect().get_center())
	_expect(not producer.auto_queue_enabled, profile + " waiting Repeat Clear failed")
	producer.auto_queue_enabled = true
	GameManager.players[0]["population_cap"] = 3
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_expect(repeat.text.contains("Pop 3/3"), profile + " Repeat lacks population-cap reason")
	tc.state = BuildingBase.State.CONSTRUCTING
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_expect(repeat.text.contains("Building"), profile + " Repeat lacks construction reason")
	var host := Control.new()
	host.size = Vector2(logical)
	fixture.add_child(host)
	var build_menu: PanelContainer = load("res://scenes/ui/build_menu.tscn").instantiate()
	host.add_child(build_menu)
	build_menu.call("update_resources", {"food": 0, "wood": 15, "gold": 0})
	build_menu.call("update_age", 1)
	build_menu.call("open_menu")
	var cards: Dictionary = build_menu.get("_button_map")
	var house: Button = cards[BuildingData.BuildingType.HOUSE]
	var stable: Button = cards[BuildingData.BuildingType.STABLE]
	var house_cost: int = int(BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE).get("wood", 0))
	_expect(house.disabled and house.text.contains("Need +%dW" % (house_cost - 15)), profile + " Build card shortage missing")
	_expect(stable.disabled and stable.text.contains("Unlocks in Age 2") and not stable.text.contains("Need"), profile + " shortage hides age lock")
	build_menu.call("update_resources", {"food": 10000, "wood": 10000, "gold": 10000})
	_expect(not house.disabled and house.accessibility_name.contains("population") and not house.text.contains("Need"), profile + " affordability does not restore purpose")
	for frame: int in 3:
		await get_tree().process_frame
	fixture.free()
	await get_tree().process_frame


func _show(hud: Node, building: BuildingBase) -> void:
	if building.get_instance_id() != _selected_producer_id:
		_selected_producer_id = building.get_instance_id()
		_selection_revision += 1
		hud.call("set_selection_context_revision", _selection_revision)
	var producer: ProductionQueue = building.get_production_queue()
	hud.call("show_building_selection", building.building_name, building.hp, building.max_hp, producer.get_queue_info(), building.trainable_units, building)


func _settle(hud: Node, logical: Vector2i, safe: Rect2) -> void:
	for frame: int in 3:
		await get_tree().process_frame
	hud.call("apply_mobile_layout", Vector2(logical), safe)
	for frame: int in 3:
		await get_tree().process_frame


func _tap(viewport: Viewport, position: Vector2, wait_frames: int = 3) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 7
		event.position = viewport.get_final_transform() * position
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		for frame: int in wait_frames:
			await get_tree().process_frame


func _queue_actions_visible(hud: Node) -> bool:
	var shelf: ScrollContainer = hud.get("command_scroll")
	for child: Control in (hud.get("queue_container") as Control).get_children():
		if child is Button and child.is_visible_in_tree() and not child.is_queued_for_deletion() and not shelf.get_global_rect().encloses(child.get_global_rect()):
			return false
	return true


func _queue_touch(viewport: Viewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 7
	event.position = viewport.get_final_transform() * position
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _queue_press_race(hud: Node, building: BuildingBase, viewport: Viewport, navigation: Button, logical: Vector2i, safe: Rect2, old_revision: int, profile: String) -> void:
	var resources_before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var population_before: int = GameManager.get_committed_population(0)
	var size_before: int = building.get_production_queue().get_queue_size()
	_queue_touch(viewport,navigation.get_global_rect().get_center(),true)
	hud.call_deferred("_restore_producer_queue_view",building,0,old_revision)
	_show(hud,building)
	await _settle(hud,logical,safe)
	_expect((hud.get("command_scroll") as ScrollContainer).scroll_horizontal == 0,profile+" stale restoration moves recruitment during Queue press")
	_queue_touch(viewport,navigation.get_global_rect().get_center(),false)
	await _settle(hud,logical,safe)
	_expect(hud.call("get_secondary_surface_name") == "queue",profile+" same-producer refresh/old restore inverts press-time Queue intent")
	_expect(ResourceManager.get_all_resources(0) == resources_before and GameManager.get_committed_population(0) == population_before and building.get_production_queue().get_queue_size() == size_before,profile+" navigation race spends/refunds/trains")


func _queue_selection_cancel(hud: Node, previous: BuildingBase, next: BuildingBase, viewport: Viewport, navigation: Button, logical: Vector2i, safe: Rect2, profile: String) -> void:
	var resources_before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var population_before: int = GameManager.get_committed_population(0)
	_queue_touch(viewport,navigation.get_global_rect().get_center(),true)
	_show(hud,next)
	await _settle(hud,logical,safe)
	_queue_touch(viewport,navigation.get_global_rect().get_center(),false)
	await _settle(hud,logical,safe)
	_expect(hud.call("get_secondary_surface_name") == "none" and (hud.get("command_scroll") as ScrollContainer).scroll_horizontal == 0,profile+" stale Queue release opens replacement producer")
	_expect(ResourceManager.get_all_resources(0) == resources_before and GameManager.get_committed_population(0) == population_before and previous.get_production_queue().get_queue_size() == 3 and next.get_production_queue().get_queue_size() == 0,profile+" canceled Queue press mutates production")
	_show(hud,previous)
	await _settle(hud,logical,safe)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
