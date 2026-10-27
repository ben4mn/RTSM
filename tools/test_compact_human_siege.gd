extends "res://tools/test_company_specialist_buildings.gd"
## Funded human transaction fixture, not an ordinary economy/pacing claim.
## Actual touch card/Place/Train inputs; normal worker travel/labor and queue.
## No free units, worker relocation, construction progress or queue-time grants.

const WORKSHOP := BuildingData.BuildingType.SIEGE_WORKSHOP
var _checks: int = 0
var _contact_id: int = 100

# A stable synthetic device safe area, used by every ordinary HUD refresh.
# Reapplying layout after a full-width refresh would clamp a drag's offset.
class NotchedHUD extends "res://scripts/ui/hud.gd":
	func _get_safe_area_rect(viewport_size: Vector2) -> Rect2:
		var inset: Vector2 = Vector2(44, 18) * viewport_size / Vector2(get_window().size)
		return Rect2(Vector2(inset.x, 0), viewport_size - Vector2(inset.x * 2.0, inset.y))


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	super._expect(condition, message)


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.selected_opponent_civilization = CivilizationData.Civilization.CROWNLANDS
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.15
	GameManager.ui_scale = 1.15
	for population: int in [20, 30, 40]:
		GameManager.selected_population_limit = population
		if await _start_match():
			_main.get("ai_controller").get("_decision_timer").stop()
			await _paid_mobile_workshop(population)
		await _close_match()
	Engine.time_scale = 1.0
	for failure: String in _failures:
		push_error("[FAIL] compact_human_siege: " + failure)
	if _failures.is_empty():
		print("[PASS] compact_human_siege: %d checks;20/30/40 population; Dark/Feudal locked Castle card, shortage guard, actual touch swipe/card/Place/Train; paid natural Workshop labor and one Siege/3-pop reservation per match" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _start_match() -> bool:
	GameManager.set_state(GameManager.GameState.MENU)
	_main = load("res://scenes/main/main.tscn").instantiate()
	_main.get_node("HUD").set_script(NotchedHUD)
	root.add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	if _main.get("_building_placement") == null:
		_expect(false, "real Main initialization timed out")
		return false
	await _frames(8)
	Engine.time_scale = 4.0
	GameManager.game_speed = 1.0
	_main.get("ai_controller").set_process(false)
	_workers.clear()
	for unit: Node in _main.get("_player_units")[0]:
		if unit is Villager:
			_workers.append(unit)
	var expected_workers: int = UnitData.get_starting_villager_count()
	_expect(_workers.size() == expected_workers, "ordinary starting roster matches the configured worker count")
	return _workers.size() == expected_workers


func _paid_mobile_workshop(population: int) -> void:
	var label: String = "%d-pop" % population
	var hud: CanvasLayer = _main.get("hud")
	var map: Node2D = _main.get("game_map")
	var menu: PanelContainer = _main.get("_build_menu")
	var placement: BuildingPlacement = _main.get("_building_placement")
	# Stop existing jobs before exact debit assertions; funded budget is explicit.
	for worker: Villager in _workers:
		worker.command_stop()
	ResourceManager.initialize_player(0, {"food": 5000, "wood": 5000, "gold": 5000})
	await _frames(4)
	await _touch_button(hud.get("build_menu_button"))
	_expect(menu.visible, label + " actual Build touch opens palette")
	await _frames(4)
	await _touch_button((menu.get("_category_buttons") as Dictionary)["Army"])
	_expect(String(menu.get("_active_category")) == "Army", label + " actual Army tab touch selects its category")
	if String(menu.get("_active_category")) != "Army":
		_input_trace(label + " failed Army tab", menu)
		return
	var cards: Dictionary = menu.get("_button_map")
	_expect(cards.has(WORKSHOP), label + " human compact Army must expose the Castle Workshop")
	if not cards.has(WORKSHOP):
		return
	var card: Button = cards[WORKSHOP]
	_expect(card.visible and card.disabled and card.tooltip_text.contains(GameManager.get_age_name(3)), label + " locked card exposes its Castle requirement through Info/accessibility")
	_expect(str(hud.call("_get_age_up_preview", 3)).contains("Siege Engine"), label + " Castle preview promises reachable Siege recruitment")
	for target_age: int in [2, 3]:
		var before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
		var cost: Dictionary = GameManager.get_age_up_cost(0, target_age)
		_expect(GameManager.try_advance_age(0), label + " normal paid age transaction succeeds")
		_check_spend(before, cost, label + " age %d" % target_age)
		await _frames(4)
		card = (menu.get("_button_map") as Dictionary)[WORKSHOP]
		_expect(card.visible and card.disabled == (target_age < 3), label + " age gate and visible card agree")
	var cost: Dictionary = BuildingData.get_building_cost(WORKSHOP)
	var funded: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	ResourceManager.initialize_player(0, {"food": 0, "wood": int(cost.wood) - 1, "gold": int(cost.gold)})
	menu.call("update_resources", ResourceManager.get_all_resources(0))
	await _frames(4)
	card = (menu.get("_button_map") as Dictionary)[WORKSHOP]
	_expect(card.disabled and card.tooltip_text.contains("Need 1 wood"), label + " Castle shortage remains inspectable and unpurchasable")
	ResourceManager.initialize_player(0, funded)
	menu.call("update_resources", ResourceManager.get_all_resources(0))
	await _frames(4)
	card = (menu.get("_button_map") as Dictionary)[WORKSHOP]
	var scroll: ScrollContainer = menu.get("scroll_container")
	_expect(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, label + " large notched Army keeps readable cards in a scrollable row")
	var overflows: bool = (menu.get("grid") as GridContainer).size.x > scroll.size.x + 1.0
	var before_camera: Vector2 = map.camera.position
	var before_scroll: int = scroll.scroll_horizontal
	await _swipe_left(card.get_global_rect())
	_expect(scroll.scroll_horizontal > before_scroll if overflows else scroll.scroll_horizontal == before_scroll, label + " touch drag scrolls overflow and leaves a fitting icon row stable")
	_expect(map.camera.position.distance_to(before_camera) < 0.01, label + " Army swipe cannot pan the battlefield")
	_expect(not placement.active, label + " Army swipe cannot start a building placement")
	var last_card: Button = (menu.get("_button_map") as Dictionary)[BuildingData.BuildingType.BLACKSMITH]
	_expect(scroll.get_global_rect().encloses(last_card.get_global_rect()), label + " actual swipe reveals the entire last Castle card (Blacksmith)")
	if (overflows and scroll.scroll_horizontal <= before_scroll) or not scroll.get_global_rect().encloses(last_card.get_global_rect()):
		_input_trace(label + " failed swipe", menu)
		return
	_expect(scroll.get_global_rect().encloses(card.get_global_rect()), label + " entire Siege card is reachable by touch")
	if not scroll.get_global_rect().encloses(card.get_global_rect()):
		return
	_expect(card.size.x >= 48.0 and card.size.y >= 48.0, label + " Siege keeps a usable icon touch target")
	var before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _touch_button(card)
	_expect(placement.active and placement.current_building_type == WORKSHOP, label + " actual Siege card enters Workshop placement")
	_check_spend(before, {}, label + " preview")
	if not placement.active:
		return
	var site: Vector2i = _legal_site(map, placement)
	_expect(site.x >= 0, label + " visible legal Workshop site exists")
	if site.x < 0:
		return
	# Select a legal preview, then pay through the same explicit phone Place action.
	placement.update_preview_at_world(map.tile_to_world(site))
	await _frames(3)
	var place: Button = hud.get("_placement_confirm_button")
	_expect(place.is_visible_in_tree() and not place.disabled, label + " legal Workshop enables explicit Place")
	var building_count: int = _main.get("_player_buildings")[0].size()
	await _touch_button(place)
	_check_spend(before, cost, label + " Workshop")
	var owned: Array = _main.get("_player_buildings")[0]
	_expect(owned.size() == building_count + 1, label + " Place creates one paid foundation")
	if owned.size() != building_count + 1:
		return
	var workshop: BuildingBase = owned.back()
	_expect(workshop.building_type == WORKSHOP and workshop.state == BuildingBase.State.CONSTRUCTING, label + " foundation has ordinary construction state")
	_expect(_builder_count(workshop) == 1, label + " Main assigns one existing real worker")
	var durations: Dictionary = await _wait_for_natural_construction([workshop], 110.0)
	_expect(workshop.state == BuildingBase.State.ACTIVE and durations.has(workshop.get_instance_id()), label + " Workshop completes through natural travel/labor")
	if workshop.state != BuildingBase.State.ACTIVE:
		return
	_expect(absf(float(durations[workshop.get_instance_id()]) - workshop.build_time / UnitData.VILLAGER_BUILD_SPEED) <= 0.6, label + " Workshop uses data-defined labor and worker build speed")
	for worker: Villager in _workers:
		worker.command_stop()
	map.selection_mgr.select_single(workshop)
	await _frames(4)
	var training: HBoxContainer = hud.get("_train_buttons_container")
	var recruit := training.get_node_or_null("TrainButton_%d" % UnitData.UnitType.SIEGE) as Button
	_expect(recruit != null and recruit.is_visible_in_tree() and not recruit.disabled, label + " completed Workshop offers paid Siege")
	if recruit == null or not recruit.is_visible_in_tree() or recruit.disabled:
		return
	var before_units: int = _role_count(UnitData.UnitType.SIEGE)
	var before_committed: int = GameManager.get_committed_population(0)
	before = ResourceManager.get_all_resources(0).duplicate()
	await _touch_button(recruit)
	_check_spend(before, UnitData.get_unit_cost(UnitData.UnitType.SIEGE), label + " Siege queue")
	_expect(workshop.get_production_queue().get_queue_size() == 1, label + " real Train touch buys exactly one queue item")
	_expect(GameManager.get_committed_population(0) == before_committed + 3, label + " paid Siege reserves three population")
	var deadline: float = GameManager.game_time + 60.0
	var wall_deadline: int = Time.get_ticks_msec() + 20000
	while _role_count(UnitData.UnitType.SIEGE) == before_units and GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		await get_tree().process_frame
	_expect(_role_count(UnitData.UnitType.SIEGE) == before_units + 1, label + " unchanged normal queue births exactly one Siege")
	_expect(GameManager.get_committed_population(0) == before_committed + 3, label + " birth converts reservation without extra population")
	for unit: Node in _main.get("_player_units")[0]:
		if unit.unit_type == UnitData.UnitType.SIEGE:
			_expect(map.is_tile_walkable(map.world_to_tile(unit.global_position)), label + " paid Siege emerges on walkable ground")
	print("COMPACT_HUMAN_SIEGE ", JSON.stringify({"population": population, "workshop_cost": cost, "siege_cost": UnitData.get_unit_cost(UnitData.UnitType.SIEGE), "construction_seconds": durations.get(workshop.get_instance_id()), "committed_population": GameManager.get_committed_population(0), "scope": "funded budget,4x engine time, natural labor/queue, actual touch purchases"}))


func _legal_site(map: Node2D, placement: BuildingPlacement) -> Vector2i:
	var home: Vector2i = map.map_generator.spawn_positions[0]
	for radius: int in range(1, 10):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				var candidate: Vector2i = home + Vector2i(x, y)
				if placement.revalidate_confirmation(WORKSHOP, map.tile_to_world(candidate), 0):
					return candidate
	return Vector2i(-1, -1)


func _touch_button(button: Button) -> void:
	_expect(button != null and button.is_visible_in_tree(), "touch control must be visible")
	if button == null:
		return
	var position: Vector2 = get_viewport().get_final_transform() * button.get_global_rect().get_center()
	_contact_id += 1
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = _contact_id
		event.position = position
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(3)


func _swipe_left(rect: Rect2) -> void:
	var point: Vector2 = rect.get_center()
	_contact_id += 1
	var press := InputEventScreenTouch.new()
	press.index = _contact_id
	press.position = get_viewport().get_final_transform() * point
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await _frames(2)
	for step: int in 6:
		point.x -= 25.0
		var drag := InputEventScreenDrag.new()
		drag.index = _contact_id
		drag.position = get_viewport().get_final_transform() * point
		drag.relative = get_viewport().get_final_transform().basis_xform(Vector2(-25.0, 0.0))
		Input.parse_input_event(drag)
		Input.flush_buffered_events()
		await _frames(2)
	press.position = get_viewport().get_final_transform() * point
	press.pressed = false
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await _frames(4)


func _input_trace(label: String, menu: PanelContainer) -> void:
	var scroll: ScrollContainer = menu.get("scroll_container")
	var events: Array = get_node("/root/PlaytestDiagnostics").get("_events")
	var contacts: Array = []
	for event: Dictionary in events:
		if String(event.get("kind", "")).begins_with("gui_"):
			contacts.append(event)
	print("COMPACT_SIEGE_INPUT ", JSON.stringify({"label": label, "category": menu.get("_active_category"), "panel": str(menu.get_global_rect()), "scroll": str(scroll.get_global_rect()), "offset": scroll.scroll_horizontal, "scroll_max": scroll.get_h_scroll_bar().max_value, "page": scroll.get_h_scroll_bar().page, "contacts": contacts.slice(maxi(0, contacts.size() - 16))}))


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame
