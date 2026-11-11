extends Node
## K: after "Find", "Place" must accept the preview. Real Input dispatch (touch
## with synthesized mouse, and a desktop mouse) on a crowded home base, for
## several building types, for the on-screen search and for the fallback that
## moves the camera beside your own buildings.

var _failures: Array[String] = []
var _checks: int = 0
var main: Node
var hud: CanvasLayer
var map: Node2D
var placement: BuildingPlacement


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_population_limit = 80
	GameManager.selected_map_seed = 101
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	hud = main.get_node("HUD")
	map = main.get_node("GameMap")
	placement = main.get("_building_placement")
	ResourceManager.refund(0, {"food": 5000, "wood": 5000, "gold": 5000})
	_crowd_home_base()
	await _frames(3)
	var town_center: BuildingBase = main.get("_player_buildings")[0][0]
	# A desktop player first (mouse only), then a phone player (touch only).
	for building_type: int in [BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.BARRACKS]:
		_frame_camera(town_center.global_position, 1.0)
		await _frames(2)
		await _find_then_place(building_type, "mouse", "mouse on-screen")
		_frame_camera(town_center.global_position, 3.0)
		await _frames(2)
		await _find_then_place(building_type, "mouse", "mouse fallback")
	for size: Vector2i in [Vector2i(844, 390), Vector2i(667, 375)]:
		get_window().size = size
		await _frames(4)
		for building_type: int in [BuildingData.BuildingType.FARM, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.RESOURCE_CAMP]:
			_frame_camera(town_center.global_position, 1.0)
			await _frames(2)
			await _find_then_place(building_type, "touch", "%dx%d on-screen" % [size.x, size.y])
		# Zoomed right in over the Town Center nothing fits on screen, so Find
		# falls back to a spot beside your own buildings and moves the camera.
		for building_type: int in [BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.BARRACKS]:
			_frame_camera(town_center.global_position, 3.0)
			await _frames(2)
			await _find_then_place(building_type, "touch", "%dx%d fallback" % [size.x, size.y])
	main.free()
	if _failures.is_empty():
		print("[PASS] placement_find_then_place: %d checks; Find always leaves a preview that Place accepts (touch and mouse, on-screen and camera fallback, 844x390 and 667x375)" % _checks)
	else:
		for failure: String in _failures:
			push_error("[FAIL] placement_find_then_place: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _find_then_place(building_type: int, input: String, label: String) -> void:
	var name: String = "%s %s" % [label, BuildingData.get_building_name(building_type)]
	var count_before: int = (main.get("_player_buildings")[0] as Array).size()
	main.call("_on_building_selected_for_placement", building_type)
	await _frames(2)
	if input == "mouse":
		# A real mouse is noticed as soon as it moves, before any click; the
		# action strip then shows its mouse layout.
		var nudge := InputEventMouseMotion.new()
		nudge.device = 0
		nudge.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 160.0)
		nudge.global_position = nudge.position
		nudge.relative = Vector2(3.0, 0.0)
		get_viewport().push_input(nudge, true)
		await _frames(3)
	# Start from a blocked preview: right on the Town Center.
	var town_center: BuildingBase = main.get("_player_buildings")[0][0]
	placement.update_preview_at_world(town_center.global_position)
	_expect(not placement.is_valid_placement, "%s: fixture preview starts blocked" % name)
	var find_button: Button = hud.get("_placement_find_space_button")
	_expect(find_button != null and find_button.is_visible_in_tree() and not find_button.disabled, "%s: Find is available" % name)
	if find_button == null:
		return
	if input == "touch":
		await _tap(find_button.get_global_rect().get_center())
	else:
		await _click(find_button.get_global_rect().get_center())
	await _frames(3)
	var ghost_tile: Vector2i = map.world_to_tile(placement.ghost_position)
	_expect(placement.active and placement.is_valid_placement, "%s: Find leaves a preview Place accepts (reason '%s', tile %s)" % [name, placement.get_invalid_reason(), str(ghost_tile)])
	_expect(not _overlaps_any_building(ghost_tile, placement.current_footprint), "%s: the found footprint %s touches no building" % [name, str(ghost_tile)])
	_expect(placement.has_assisted_preview(), "%s: the found preview is held as assisted" % name)
	var place_button: Button = hud.get("_placement_confirm_button")
	_expect(place_button != null and place_button.is_visible_in_tree() and not place_button.disabled, "%s: Place is shown and enabled after Find" % name)
	if input == "mouse":
		# The pointer travels from Find to Place over the world; it must not drag
		# the found preview with it.
		var from: Vector2 = find_button.get_global_rect().get_center()
		var to: Vector2 = place_button.get_global_rect().get_center()
		for step: int in range(1, 9):
			var motion := InputEventMouseMotion.new()
			motion.device = 0
			motion.position = from.lerp(to, float(step) / 8.0) + Vector2(0.0, -40.0 * sin(PI * float(step) / 8.0))
			motion.global_position = motion.position
			motion.relative = Vector2(4.0, -2.0)
			get_viewport().push_input(motion, true)
			await get_tree().process_frame
		_expect(map.world_to_tile(placement.ghost_position) == ghost_tile, "%s: moving the mouse to Place keeps the found preview" % name)
	if place_button == null or not place_button.is_visible_in_tree():
		placement.cancel_placement()
		main.call("_cancel_placement")
		return
	if input == "touch":
		await _tap(place_button.get_global_rect().get_center())
	else:
		await _click(place_button.get_global_rect().get_center())
	await _frames(2)
	var count_after: int = (main.get("_player_buildings")[0] as Array).size()
	_expect(count_after == count_before + 1 and not placement.active, "%s: Place after Find founds exactly one building (%d -> %d)" % [name, count_before, count_after])
	if placement.active:
		main.call("_cancel_placement")
		await _frames(1)


func _overlaps_any_building(origin: Vector2i, footprint: Vector2i) -> bool:
	var area := Rect2i(origin, footprint)
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is BuildingBase and (node as BuildingBase).state != BuildingBase.State.DESTROYED:
			var occupied := Rect2i(map.world_to_tile((node as Node2D).global_position), (node as BuildingBase).footprint)
			if occupied.intersects(area):
				return true
	return false


func _crowd_home_base() -> void:
	# Ring the Town Center with Houses, Farms, a Barracks and a Camp so the
	# nearest ground is taken, like the playtesters' bases.
	var town_center: BuildingBase = main.get("_player_buildings")[0][0]
	var center: Vector2i = map.world_to_tile(town_center.global_position)
	var kinds: Array[int] = [BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.FARM, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.FARM, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.RESOURCE_CAMP, BuildingData.BuildingType.FARM, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.FARM, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.FARM]
	var placed: int = 0
	for radius: int in range(3, 9):
		for dx: int in range(-radius, radius + 1):
			for dy: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius or placed >= kinds.size():
					continue
				var kind: int = kinds[placed]
				var tile: Vector2i = center + Vector2i(dx, dy)
				if placement.revalidate_confirmation(kind, map.tile_to_world(tile), 0):
					var building: BuildingBase = main.call("_spawn_building", kind, 0, tile)
					if building != null:
						building.start_construction()
						placed += 1
	_expect(placed >= 8, "fixture crowds the base (%d buildings)" % placed)


func _frame_camera(world: Vector2, zoom: float) -> void:
	map.camera.position = world
	map.camera.zoom = Vector2(zoom, zoom)
	map.call("_clamp_camera")


func _frames(count: int) -> void:
	for index: int in count:
		await get_tree().process_frame


func _tap(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = _to_window(position)
		event.index = 0
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = position
	motion.global_position = position
	motion.relative = Vector2(1.0, 0.0)
	get_viewport().push_input(motion, true)
	await _frames(1)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.device = 0
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		# A desktop mouse enters the viewport directly (as in test_input_aware_placement).
		get_viewport().push_input(event, true)
		await _frames(2)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


## Events enter in window pixels; HUD rects are in the stretched viewport.
func _to_window(viewport_position: Vector2) -> Vector2:
	return get_viewport().get_screen_transform() * viewport_position
