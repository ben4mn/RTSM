extends Node
## Touch queue navigation, paid cancellation and recovery feedback at phone sizes.

var _failures: Array[String] = []


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
	_expect(navigation.visible and not navigation.disabled and navigation.text.contains("3"), profile + " Queue count/control missing")
	_expect(navigation.size.x >= 48.0 and navigation.size.y >= 48.0, profile + " Queue touch target under48px")
	_expect(safe.encloses(navigation.get_global_rect()), profile + " Queue outside safe area")
	_expect((hud.get("selection_panel") as Control).get_global_rect().encloses(navigation.get_global_rect()), profile + " Queue does not share production shelf")
	for recruit: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
		_expect(shelf.get_global_rect().encloses(recruit.get_global_rect()), profile + " inline pager clips " + String(recruit.name))
	await _tap(viewport, navigation.get_global_rect().get_center())
	_expect(shelf.scroll_horizontal > 0 and navigation.text.contains("Train"), profile + " Queue touch does not open cancellation page")
	var undo: Button = (hud.get("queue_container") as HBoxContainer).get_node("QueueClearLastButton")
	var clear: Button = (hud.get("queue_container") as HBoxContainer).get_node("QueueClearAllButton")
	_expect(shelf.get_global_rect().encloses(undo.get_global_rect()) and shelf.get_global_rect().encloses(clear.get_global_rect()), profile + " Queue page hides Undo/Clear: shelf %s Undo %s Clear %s" % [shelf.get_global_rect(), undo.get_global_rect(), clear.get_global_rect()])
	var inspected_scroll: int = shelf.scroll_horizontal
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_expect(shelf.scroll_horizontal > 0 and navigation.text.contains("Train") and absf(float(shelf.scroll_horizontal) - (hud.get("queue_container") as Control).position.x) <= 1.0, profile + " same producer refresh loses queue inspection: %d -> %d (queue begins %.0f)" % [inspected_scroll, shelf.scroll_horizontal, (hud.get("queue_container") as Control).position.x])
	_show(hud, tc)
	await _tap(viewport, navigation.get_global_rect().get_center(), 0)
	await _settle(hud, logical, safe)
	_expect(shelf.scroll_horizontal == 0, profile + " pending producer refresh overrides deliberate Train return")
	await _tap(viewport, navigation.get_global_rect().get_center())
	shelf.scroll_horizontal = 0
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_expect(shelf.scroll_horizontal == 0, profile + " producer refresh overrides manual scroll back to Train")
	await _tap(viewport, navigation.get_global_rect().get_center())
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
	_expect(not navigation.disabled and navigation.text.contains("0"), profile + " empty waiting Repeat cannot open Clear")
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
	_expect(house.disabled and house.text.contains("Need +%d wood" % (house_cost - 15)), profile + " Build card shortage missing")
	_expect(stable.disabled and stable.text.contains("Unlocks in Age 2") and not stable.text.contains("Need"), profile + " shortage hides age lock")
	build_menu.call("update_resources", {"food": 10000, "wood": 10000, "gold": 10000})
	_expect(not house.disabled and house.text.contains("population") and not house.text.contains("Need"), profile + " affordability does not restore purpose")
	fixture.free()
	await get_tree().process_frame


func _show(hud: Node, building: BuildingBase) -> void:
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
		for frame: int in wait_frames:
			await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
