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
	_expect(not _placement.uses_touch_input(), "mouse card's emulated touch changed input mode")
	_assert_mouse_ui()
	_expect(str(_main.get("_first_session_hint_text")).contains("Click clear ground"), "House guide does not say mouse click places immediately")
	_expect(ResourceManager.get_all_resources(0) == resources_before, "House card spent resources before placement")
	var valid_world: Vector2 = _placement.ghost_position
	var screen: Vector2 = _placement.get_canvas_transform() * valid_world
	var emulated_touch := InputEventScreenTouch.new()
	emulated_touch.device = InputEvent.DEVICE_ID_EMULATION
	emulated_touch.pressed = true
	emulated_touch.position = screen
	get_viewport().push_input(emulated_touch, true)
	await _frames()
	_expect(not _placement.uses_touch_input(), "emulated touch changed the real mouse instructions")
	await _touch(screen, true)
	await _touch(screen, false)
	_expect(str(_main.get("_first_session_hint_text")).contains("tap Place") or str(_main.get("_first_session_hint_text")).contains("Tap open ground"), "House instructions did not switch to touch placement")
	_expect(_placement.active and ResourceManager.get_all_resources(0) == resources_before, "switching House instructions to touch purchased a foundation")
	await _mouse_motion(screen)
	_expect(str(_main.get("_first_session_hint_text")).contains("Click clear ground"), "House instructions did not switch back to mouse")
	await _mouse_click(screen)
	_expect(not _placement.active, "one instructed mouse click did not finish placement")
	_expect(_main.get("_player_buildings")[0].size() == buildings_before + 1, "one mouse click did not create exactly one foundation")
	_assert_cost(resources_before, house_cost, "mouse click")
	_expect(production.get_queue_size() == 0, "literal mouse instructions accidentally trained a unit")

	# Switch from mouse to touch while a preview is active. The first touch is
	# at the future Place button position, which was invisible at touch-down.
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	_assert_mouse_ui()
	resources_before = ResourceManager.get_all_resources(0).duplicate()
	buildings_before = _main.get("_player_buildings")[0].size()
	var place_button: Button = _hud.get("_placement_confirm_button") as Button
	_hud.call("set_placement_input_mode", true)
	await _frames()
	var future_button_position: Vector2 = place_button.get_global_rect().get_center()
	_hud.call("set_placement_input_mode", false)
	await _frames()
	await _touch(future_button_position, true)
	await _touch(future_button_position, false)
	_expect(_placement.uses_touch_input(), "touch did not switch the active input")
	_expect(place_button.is_visible_in_tree(), "touch did not expose explicit Place")
	_expect(_placement.active and _main.get("_player_buildings")[0].size() == buildings_before, "first touch activated an initially invisible Place action")
	_expect(ResourceManager.get_all_resources(0) == resources_before, "first touch purchased a foundation")
	valid_world = _placement.call("_find_initial_preview_position", valid_world)
	_placement.update_preview_at_world(valid_world)
	await _frames()
	# Beta 25 shortened the hint to "House · tap a spot"; the Place button beside it confirms.
	_expect((_hud.get("_placement_status_label") as Label).text.contains("tap a spot") and (_hud.get("_placement_confirm_button") as Button).is_visible_in_tree(), "valid touch preview lacks confirmation instructions")
	# A positioning drag (not a tap) leaves the preview for the explicit Place.
	await _touch(_placement.get_canvas_transform() * valid_world - Vector2(30.0, 0.0), true)
	await _touch(_placement.get_canvas_transform() * valid_world, false)
	_expect(_placement.active, "a positioning drag confirmed before Place")
	_expect(ResourceManager.get_all_resources(0) == resources_before, "a positioning drag spent before Place")
	await _touch(place_button.get_global_rect().get_center(), true)
	await _touch(place_button.get_global_rect().get_center(), false)
	_expect(not _placement.active, "explicit Place did not complete touch placement")
	_expect(_main.get("_player_buildings")[0].size() == buildings_before + 1, "touch Place did not create exactly one foundation")
	_assert_cost(resources_before, house_cost, "touch Place")
	_hud.emit_signal("placement_confirm_requested")
	_hud.emit_signal("placement_confirm_requested")
	_expect(_main.get("_player_buildings")[0].size() == buildings_before + 1, "duplicate confirmation created another foundation")
	_assert_cost(resources_before, house_cost, "duplicate Place")

	# A recent touch must not suppress genuine mouse movement or direct click.
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	_expect(place_button.is_visible_in_tree(), "new placement forgot its last touch input")
	valid_world = _placement.ghost_position
	screen = _placement.get_canvas_transform() * valid_world
	await _mouse_motion(screen)
	_expect(not _placement.uses_touch_input(), "genuine mouse movement did not switch immediately after touch")
	_assert_mouse_ui()
	_expect(_placement.ghost_position == valid_world, "mouse movement lost immediate preview control after touch")
	resources_before = ResourceManager.get_all_resources(0).duplicate()
	buildings_before = _main.get("_player_buildings")[0].size()
	await _mouse_click(screen)
	_expect(_main.get("_player_buildings")[0].size() == buildings_before + 1, "mouse placement failed after switching from touch")
	_assert_cost(resources_before, house_cost, "mouse after touch")
	_expect(production.get_queue_size() == 0, "device switching accidentally trained a unit")

	# Invalid confirmation and cancellation neither purchase nor reserve pop.
	resources_before = ResourceManager.get_all_resources(0).duplicate()
	buildings_before = _main.get("_player_buildings")[0].size()
	var reserved_before: int = GameManager.get_reserved_population(0)
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	_placement.update_preview_at_world(_map.call("tile_to_world", Vector2i(-2, -2)))
	_expect(not _placement.confirm_preview(), "invalid ground confirmed")
	_expect(_placement.active, "invalid confirmation canceled the inspectable preview")
	await _touch((_hud.get("_placement_cancel_button") as Button).get_global_rect().get_center(), true)
	await _touch((_hud.get("_placement_cancel_button") as Button).get_global_rect().get_center(), false)
	_expect(not _placement.active, "Cancel failed after input switching")
	_expect(ResourceManager.get_all_resources(0) == resources_before, "invalid/cancel placement spent resources")
	_expect(_main.get("_player_buildings")[0].size() == buildings_before, "invalid/cancel placement created a foundation")
	_expect(GameManager.get_reserved_population(0) == reserved_before, "placement reserved production population")
	_main.free()
	await _frames()
	_completed_cases += 1


func _assert_mouse_ui() -> void:
	_expect(not (_hud.get("_placement_confirm_button") as Button).is_visible_in_tree(), "mouse placement exposes a misleading second Place action")
	if _placement.is_valid_placement:
		# Beta 25 copy: "House · click a spot" (was "Click ground to build").
		_expect((_hud.get("_placement_status_label") as Label).text.contains("click a spot"), "valid mouse preview lacks click-to-place instructions")


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
