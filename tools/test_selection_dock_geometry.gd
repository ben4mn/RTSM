extends "res://tools/test_mobile_production_feedback.gd"
## Regression for coalesced selection layouts retaining a stale larger rectangle.
## Synthetic funded producer; uses real HUD layout, queues and normal deferred sorts.

var _geometry_checks: int = 0

func _run() -> void:
	AudioManager.set_all_enabled(false)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale_factor: float in [1.0, 1.15]:
			for notched: bool in [false, true]:
				await _geometry_profile(phone, scale_factor, notched)
	for failure: String in _failures:
		push_error("[FAIL] selection_dock_geometry: " + failure)
	if _failures.is_empty():
		print("[PASS] selection_dock_geometry: %d checks; eight phone/scale/safe-area profiles, paid queue, coalesced selection, modal and resize layouts" % _geometry_checks)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _geometry_profile(phone: Vector2i, scale_factor: float, notched: bool) -> void:
	GameManager.initialize_game()
	GameManager.players[0]["population"] = 3
	GameManager.players[0]["population_cap"] = 30
	ResourceManager.initialize_player(0, {"food": 3000, "wood": 3000, "gold": 3000})
	# The real resize hook reapplies the saved UI scale; keep it consistent with
	# this profile instead of letting a synthetic resize revert to default1.0.
	GameManager.ui_scale = scale_factor
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = scale_factor
	await get_tree().process_frame
	await get_tree().process_frame
	var logical := Vector2i(get_viewport().get_visible_rect().size)
	var safe := Rect2(Vector2.ZERO, Vector2(logical))
	if notched:
		safe = Rect2(Vector2(44, 0) / scale_factor, Vector2(logical) - Vector2(88, 18) / scale_factor)
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
	producer.set_process(false)
	await get_tree().process_frame
	var profile := "%s scale %.2f notch %s" % [phone, scale_factor, notched]
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_check_rect(hud, logical, safe, profile + " empty")
	for kind: int in [UnitData.UnitType.VILLAGER, UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT]:
		_expect(producer.enqueue_unit(kind), profile + " normal paid queue accepted")
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_check_rect(hud, logical, safe, profile + " paid")
	var paid_centers: Dictionary = _train_centers(hud)
	# A cleared selection retains the hidden queue while its layout is refreshed.
	# Re-selecting before deferred minimum processing previously left width520.
	hud.clear_selection()
	hud.apply_mobile_layout(Vector2(logical), safe)
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_check_rect(hud, logical, safe, profile + " coalesced return")
	_check_train_centers(hud, paid_centers, profile + " coalesced return")
	for refresh: int in 2:
		_show(hud, tc)
		await _settle(hud, logical, safe)
		_check_rect(hud, logical, safe, profile + " later refresh")
		_check_train_centers(hud, paid_centers, profile + " later refresh")
	hud.set_ui_modal_state(preload("res://scripts/ui/hud.gd").UIModalState.BUILD_MENU)
	await _settle(hud, logical, safe)
	hud.set_ui_modal_state(preload("res://scripts/ui/hud.gd").UIModalState.NONE)
	await _settle(hud, logical, safe)
	_check_rect(hud, logical, safe, profile + " modal return")
	_check_train_centers(hud, paid_centers, profile + " modal return")
	get_window().size = Vector2i(932, 430) if phone.x == 844 else Vector2i(844, 390)
	await get_tree().process_frame
	await get_tree().process_frame
	var resized_logical := Vector2i(get_viewport().get_visible_rect().size)
	var resized_safe := Rect2(Vector2.ZERO, Vector2(resized_logical))
	if notched:
		resized_safe = Rect2(Vector2(44, 0) / scale_factor, Vector2(resized_logical) - Vector2(88, 18) / scale_factor)
	_show(hud, tc)
	await _settle(hud, resized_logical, resized_safe)
	_check_rect(hud, resized_logical, resized_safe, profile + " live resize")
	get_window().size = phone
	await get_tree().process_frame
	await get_tree().process_frame
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_check_rect(hud, logical, safe, profile + " resize return")
	producer.cancel_all()
	_show(hud, tc)
	await _settle(hud, logical, safe)
	_check_rect(hud, logical, safe, profile + " paid cancellation empty")
	fixture.free()
	await get_tree().process_frame

func _check_rect(hud: Node, logical: Vector2i, safe: Rect2, stage: String) -> void:
	var metrics: Dictionary = hud.call("_calculate_mobile_layout_metrics", Vector2(logical), safe, hud.call("_count_visible_mobile_action_buttons"))
	var expected := Rect2(Vector2(float(metrics.selection_left), float(logical.y) + float(metrics.selection_top)), Vector2(float(metrics.selection_width), float(metrics.selection_height)))
	var actual: Rect2 = (hud.get("selection_panel") as Control).get_global_rect()
	_geometry_expect(actual.position.distance_to(expected.position) < 0.6, stage + " actual panel origin must match computed dock")
	_geometry_expect(actual.size.distance_to(expected.size) < 0.6, stage + " actual panel size must match computed dock")
	_geometry_expect(safe.grow(0.6).encloses(actual), stage + " actual dock remains within safe bounds")
	var identity: Rect2 = (hud.get("selection_info_column") as Control).get_global_rect()
	_geometry_expect(actual.grow(0.6).encloses(identity), stage + " identity stays inside actual dock")
	var navigation: Control = hud.get("_queue_navigation_button")
	_geometry_expect(navigation.visible and navigation.is_visible_in_tree(), stage + " Queue remains visible")
	var nav: Rect2 = navigation.get_global_rect()
	_geometry_expect(actual.grow(0.6).encloses(nav), stage + " Queue stays inside actual dock")
	var age: Control = hud.get("age_up_button")
	_geometry_expect(not age.visible or not nav.intersects(age.get_global_rect()), stage + " Queue remains separate from Age Up")
	var shelf: Rect2 = (hud.get("command_scroll") as Control).get_global_rect()
	for child: Control in (hud.get("_train_buttons_container") as Control).get_children():
		if child.visible and not child.is_queued_for_deletion():
			_geometry_expect(shelf.grow(0.6).encloses(child.get_global_rect()), stage + " card visible: " + str(child.name))

func _geometry_expect(condition: bool, message: String) -> void:
	_geometry_checks += 1
	_expect(condition, message)

func _train_centers(hud: Node) -> Dictionary:
	var centers: Dictionary = {}
	for child: Control in (hud.get("_train_buttons_container") as Control).get_children():
		if child.visible and not child.is_queued_for_deletion():
			centers[str(child.name)] = child.get_global_rect().get_center()
	return centers

func _check_train_centers(hud: Node, expected: Dictionary, stage: String) -> void:
	var actual: Dictionary = _train_centers(hud)
	_geometry_expect(actual.size() == expected.size(), stage + " recruitment controls retain identities")
	for key: String in expected:
		_geometry_expect(actual.has(key) and (actual[key] as Vector2).distance_to(expected[key]) < 0.6, stage + " stable paid tap center: " + key)
