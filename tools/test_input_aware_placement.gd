extends Node
## Paid placement through actual GUI/input dispatch, at desktop and phone size.
## Simulates genuine device events and Godot emulation; not physical touch QA.

var _failures: Array[String] = []
var _main: Node = null
var _hud: CanvasLayer = null
var _placement: BuildingPlacement = null
var _map: Node2D = null
var _completed_cases: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	Input.emulate_touch_from_mouse = true
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		await _exercise(viewport_size)
	_expect(_completed_cases == 2, "both viewport workflows must run to completion")
	for failure: String in _failures:
		push_error("[FAIL] input_aware_placement: " + failure)
	if _failures.is_empty():
		print("[PASS] input_aware_placement: 1280x720 and 844x390 paid mouse/card/world placement, touch explicit/duplicate/invalid/cancel, device switching and emulation-safe instructions")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _exercise(viewport_size: Vector2i) -> void:
	get_window().size = viewport_size
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = viewport_size
	get_window().content_scale_factor = 1.0
	await _frames()
	GameManager.guided_opening_enabled = true
	GameManager.selected_population_limit = 30
	GameManager.selected_map_seed = 424242
	GameManager.selected_difficulty = 0
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for _frame: int in 900:
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_hud = _main.get_node("HUD") as CanvasLayer
	_map = _main.get_node("GameMap") as Node2D
	_placement = _main.get("_building_placement") as BuildingPlacement
	if _placement == null:
		_expect(false, "Main did not initialize placement")
		_main.free()
		return
	# Freeze economy/AI timing so exact costs and production reservations are
	# attributable to input. The real placement, GUI and command wiring runs.
	_main.set_process(false)
	_main.get_node("AIController").set_process(false)
	_map.set_process(false)
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_physics_process(false)
	_main.set("_guided_stage", 1)
	_main.set("_opening_gather_complete", true)
	_main.call("_update_progression_hint")
	await _frames()
	await _mouse_click((_hud.call("get_base_navigation_button") as Button).get_global_rect().get_center())
	_map.get("selection_mgr").deselect_all()
	await _frames()
	var town_center: BuildingBase = _main.get("_player_buildings")[0][0] as BuildingBase
	var production: ProductionQueue = town_center.get_production_queue() as ProductionQueue
	var resources_before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var buildings_before: int = _main.get("_player_buildings")[0].size()
	var house_cost: Dictionary = BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE)
	await _mouse_click((_hud.get("build_menu_button") as Button).get_global_rect().get_center())
	var palette: Node = _main.get("_build_menu")
	_expect(bool(palette.get("visible")), "mouse Build did not open the palette")
	await _mouse_click((palette.get("_button_map")[BuildingData.BuildingType.HOUSE] as Button).get_global_rect().get_center())
	_expect(_placement.active, "mouse House card did not begin placement")
	_expect(ResourceManager.get_all_resources(0) == resources_before, "House card spent resources before placement")
	# H (G1): placement starts in the device's touch language whenever touch is
	# available (Godot reports it under mouse-to-touch emulation too); the first
	# real mouse movement switches it to mouse instructions.
	var valid_world: Vector2 = _placement.ghost_position
	var screen: Vector2 = _placement.get_canvas_transform() * valid_world
	await _mouse_motion(screen)
	_expect(not _placement.uses_touch_input(), "genuine mouse movement did not switch the card's placement to mouse")
	_assert_mouse_ui()
	_expect(str(_main.get("_first_session_hint_text")).contains("Click clear ground"), "House guide does not say mouse click places immediately")
	var emulated_touch := InputEventScreenTouch.new()
	emulated_touch.device = InputEvent.DEVICE_ID_EMULATION
	emulated_touch.pressed = true
	emulated_touch.position = screen
	get_viewport().push_input(emulated_touch, true)
	await _frames()
	_expect(not _placement.uses_touch_input(), "emulated touch changed the real mouse instructions")
	_expect(_placement.active and ResourceManager.get_all_resources(0) == resources_before, "emulated touch purchased a foundation")
	# L2: a real touch that lands on the ghost builds it, even the one that
	# switches from mouse (the ghost is put back on its valid opening spot).
	_placement.update_preview_at_world(valid_world)
	await _frames()
	var ghost_center: Vector2 = _placement.get_ghost_footprint_screen_rect().get_center()
	await _touch(ghost_center, true)
	await _touch(ghost_center, false)
	_expect(not _placement.active, "first real tap on the ghost did not build")
	_expect(_main.get("_player_buildings")[0].size() == buildings_before + 1, "first ghost tap did not create exactly one foundation")
	_assert_cost(resources_before, house_cost, "first ghost tap")
	_expect(production.get_queue_size() == 0, "placement tap accidentally trained a unit")
	(_hud.call("get_placement_ghost_card") as PlacementGhostCard).dismiss_repeat()

	# Touch placement with the Build button on the ghost: a drag off the ghost
	# pans and buys nothing; Build confirms exactly once.
	await _real_wait(400)
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	resources_before = ResourceManager.get_all_resources(0).duplicate()
	buildings_before = _main.get("_player_buildings")[0].size()
	var card: PlacementGhostCard = _hud.call("get_placement_ghost_card")
	await _frames()
	_expect(_placement.uses_touch_input(), "touch placement forgot its last touch input")
	_expect(card.is_build_visible(), "touch did not show Build on the ghost")
	_expect(not (_hud.get("_placement_confirm_button") as Button).is_visible_in_tree(), "touch still shows the old bottom-bar Place")
	_expect(_placement.active and ResourceManager.get_all_resources(0) == resources_before, "starting touch placement purchased a foundation")
	_expect(_placement.is_valid_placement and card.build_button.text.begins_with("Build"), "valid touch preview lacks a Build label with its cost")
	var field: Rect2 = _hud.call("get_placement_search_safe_rect")
	var pan_from := Vector2(field.position.x + 40.0, field.get_center().y)
	if _placement.is_screen_point_on_ghost(pan_from):
		pan_from = Vector2(field.end.x - 40.0, field.get_center().y)
	await _touch(pan_from, true)
	await _touch(pan_from + Vector2(30.0, 0.0), false)
	_expect(_placement.active, "a drag off the ghost confirmed")
	_expect(ResourceManager.get_all_resources(0) == resources_before, "a drag off the ghost spent")
	var place_button: Button = card.build_button
	await _touch(card.get_build_button_rect().get_center(), true)
	await _touch(card.get_build_button_rect().get_center(), false)
	_expect(not _placement.active, "Build did not complete touch placement")
	_expect(_main.get("_player_buildings")[0].size() == buildings_before + 1, "touch Build did not create exactly one foundation")
	_assert_cost(resources_before, house_cost, "touch Build")
	_hud.emit_signal("placement_confirm_requested")
	_hud.emit_signal("placement_confirm_requested")
	_expect(_main.get("_player_buildings")[0].size() == buildings_before + 1, "duplicate confirmation created another foundation")
	_assert_cost(resources_before, house_cost, "duplicate Build")
	card.dismiss_repeat()

	# A recent touch must not suppress genuine mouse movement or direct click.
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	await _frames()
	_expect(card.is_build_visible(), "new placement forgot its last touch input")
	valid_world = _placement.ghost_position
	screen = _placement.get_ghost_footprint_screen_rect().get_center()
	await _mouse_motion(screen)
	_expect(not _placement.uses_touch_input(), "genuine mouse movement did not switch immediately after touch")
	_assert_mouse_ui()
	_expect(_placement.ghost_position.distance_to(valid_world) < 1.0, "mouse movement lost immediate preview control after touch")
	resources_before = ResourceManager.get_all_resources(0).duplicate()
	buildings_before = _main.get("_player_buildings")[0].size()
	await _mouse_click(screen)
	_expect(_main.get("_player_buildings")[0].size() == buildings_before + 1, "mouse placement failed after switching from touch")
	_assert_cost(resources_before, house_cost, "mouse after touch")
	_expect(production.get_queue_size() == 0, "device switching accidentally trained a unit")
	card.dismiss_repeat()

	# Invalid confirmation and cancellation neither purchase nor reserve pop.
	resources_before = ResourceManager.get_all_resources(0).duplicate()
	buildings_before = _main.get("_player_buildings")[0].size()
	var reserved_before: int = GameManager.get_reserved_population(0)
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	_placement.update_preview_at_world(_map.call("tile_to_world", Vector2i(-2, -2)))
	_expect(not _placement.confirm_preview(), "invalid ground confirmed")
	_expect(_placement.active, "invalid confirmation canceled the inspectable preview")
	# The placement bar relayouts when its Place button appears; tap Cancel
	# where it is drawn after that frame, as a player would.
	await _frames()
	var cancel_card: PlacementGhostCard = _hud.call("get_placement_ghost_card")
	var cancel_rect: Rect2 = cancel_card.get_cancel_button_rect() if cancel_card.is_cancel_visible() else (_hud.get("_placement_cancel_button") as Button).get_global_rect()
	await _touch(cancel_rect.get_center(), true)
	await _touch(cancel_rect.get_center(), false)
	_expect(not _placement.active, "Cancel failed after input switching")
	_expect(ResourceManager.get_all_resources(0) == resources_before, "invalid/cancel placement spent resources")
	_expect(_main.get("_player_buildings")[0].size() == buildings_before, "invalid/cancel placement created a foundation")
	_expect(GameManager.get_reserved_population(0) == reserved_before, "placement reserved production population")
	_main.free()
	await _frames()
	_completed_cases += 1


func _assert_mouse_ui() -> void:
	_expect(not (_hud.get("_placement_confirm_button") as Button).is_visible_in_tree(), "mouse placement exposes a misleading second Place action")
	_expect(not (_hud.call("get_placement_ghost_card") as PlacementGhostCard).is_build_visible(), "mouse placement shows a Build button chasing the cursor")
	if _placement.is_valid_placement:
		# L2 copy: "House · click to build · Shift+click for more".
		_expect((_hud.get("_placement_status_label") as Label).text.contains("click to build"), "valid mouse preview lacks click-to-place instructions")


func _assert_cost(before: Dictionary, cost: Dictionary, phase: String) -> void:
	var after: Dictionary = ResourceManager.get_all_resources(0)
	for resource: String in before:
		_expect(int(after[resource]) == int(before[resource]) - int(cost.get(resource, 0)), "%s did not charge exactly one %s cost" % [phase, resource])


func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = 0
	event.position = position
	event.global_position = position
	event.relative = Vector2(1.0, 0.0)
	get_viewport().push_input(event, true)
	await _frames()


func _mouse_click(position: Vector2) -> void:
	await _mouse_motion(position)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.device = 0
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await _frames()


func _touch(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 51
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [get_window().size, message])


## Real (wall-clock) time: the 0.35 s double-confirm guard is measured in it.
func _real_wait(msec: int) -> void:
	var until: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
