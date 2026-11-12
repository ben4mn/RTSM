extends Node
## L2: the one placement language, by real input dispatch at 844x390 and
## 667x375 (touch with synthesized mouse), plus a desktop mouse.
## - Picking a building opens a valid ghost with a Build button on it, clear
##   of the HUD. Build founds exactly one building, charges once, and the
##   confirming tap changes no selection. A second quick tap cannot buy again.
## - Tapping other ground moves the ghost (centred under the finger) and never
##   builds; a drag from the ghost carries it; a drag elsewhere pans the map.
## - Tapping the ghost itself builds it exactly where it was drawn.
## - "+1" on a just-placed House/Farm opens the next ghost beside it, so five
##   Farms take 3 + 4 x 2 taps; x cancels for free.
## - Mouse: the ghost follows the cursor; click builds; Shift+click keeps the
##   building in hand; right click cancels.

var _failures: Array[String] = []
var _checks: int = 0
var main: Node
var hud: CanvasLayer
var map: Node2D
var placement: BuildingPlacement
var card: PlacementGhostCard
var _taps: int = 0
var _index: int = 40


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
	if GameManager.current_state == GameManager.GameState.PAUSED:
		GameManager.set_paused(false)
	hud = main.get_node("HUD")
	map = main.get_node("GameMap")
	placement = main.get("_building_placement")
	card = hud.call("get_placement_ghost_card")
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	ResourceManager.refund(0, {"food": 5000, "wood": 5000, "gold": 5000})
	var town_center: BuildingBase = main.get("_player_buildings")[0][0]
	for size: Vector2i in [Vector2i(844, 390), Vector2i(667, 375)]:
		get_window().size = size
		await _frames(4)
		var label: String = "%dx%d" % [size.x, size.y]
		_frame_camera(town_center.global_position, 1.0)
		await _frames(2)
		await _house_two_taps(label)
		await _tap_moves_never_builds(label)
		await _drag_ghost_and_pan(label)
		await _tap_ghost_builds_in_place(label)
		await _five_farms(label)
		await _barracks_at_spot(label)
	get_window().size = Vector2i(844, 390)
	await _frames(4)
	await _mouse_flow()
	# After L1's coast rim: the outermost tile ring is shore, never a site.
	main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	await _frames(2)
	for edge: Vector2i in [Vector2i(0, 40), Vector2i(40, 0), Vector2i(MapData.MAP_WIDTH - 2, 40), Vector2i(40, MapData.MAP_HEIGHT - 2)]:
		_expect(not placement.revalidate_confirmation(BuildingData.BuildingType.HOUSE, map.tile_to_world(edge), 0) and placement.get_invalid_reason() == BuildingPlacement.SHORE_INVALID_REASON, "a House at %s on the shore ring is refused (%s)" % [edge, placement.get_invalid_reason()])
	for beyond: Vector2i in [Vector2i(-6, 40), Vector2i(40, MapData.MAP_HEIGHT + 4)]:
		placement.update_preview_at_world(map.tile_to_world(beyond))
		var pinned: Vector2i = map.world_to_tile(placement.ghost_position)
		_expect(pinned.x >= 1 and pinned.y >= 1 and pinned.x + placement.current_footprint.x <= MapData.MAP_WIDTH - 1 and pinned.y + placement.current_footprint.y <= MapData.MAP_HEIGHT - 1, "a ghost dragged past the coast stays on land (%s -> %s)" % [beyond, pinned])
	main.call("_cancel_placement")
	main.free()
	if _failures.is_empty():
		print("[PASS] placement_ghost_build: %d checks; ghost Build/tap/drag/pan/+1/undo-safe flow at 844x390 and 667x375, mouse click/shift/right-click" % _checks)
	else:
		for failure: String in _failures:
			push_error("[FAIL] placement_ghost_build: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Cases -------------------------------------------------------------------

func _house_two_taps(label: String) -> void:
	var name: String = "%s House" % label
	var count_before: int = _count(BuildingData.BuildingType.HOUSE)
	var resources_before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	map.get("selection_mgr").deselect_all()
	_taps = 0
	await _pick_from_menu(BuildingData.BuildingType.HOUSE)
	_expect(placement.active and placement.is_valid_placement, "%s: the ghost opens on a valid spot (reason '%s')" % [name, placement.get_invalid_reason()])
	_expect(ResourceManager.get_all_resources(0) == resources_before, "%s: picking spends nothing" % name)
	var build: Rect2 = card.get_build_button_rect()
	_expect(card.is_build_visible() and build.has_area(), "%s: a Build button rides on the ghost" % name)
	_expect(build.size.y >= 44.0 and card.get_cancel_button_rect().size.y >= 44.0, "%s: Build and x are thumb sized (%s / %s)" % [name, build.size, card.get_cancel_button_rect().size])
	_expect(get_viewport().get_visible_rect().encloses(build), "%s: Build is on screen (%s)" % [name, build])
	for obstacle: Rect2 in hud.call("get_world_occlusion_rects"):
		_expect(not obstacle.intersects(build), "%s: Build is clear of HUD panel %s (%s)" % [name, obstacle, build])
	var ghost_rect: Rect2 = placement.get_ghost_footprint_screen_rect()
	_expect(build.position.y >= ghost_rect.end.y - 1.0 or build.end.y <= placement.get_ghost_screen_rect().position.y + 1.0 or build.position.x >= ghost_rect.end.x or build.end.x <= ghost_rect.position.x, "%s: Build does not cover the footprint" % name)
	var place_button: Button = hud.get("_placement_confirm_button")
	var find_button: Button = hud.get("_placement_find_space_button")
	_expect(not place_button.is_visible_in_tree() and not find_button.is_visible_in_tree(), "%s: no bottom-bar check or Find" % name)
	var ghost_world: Vector2 = placement.ghost_position
	await _tap(build.get_center())
	_expect(not placement.active, "%s: Build confirms" % name)
	_expect(_count(BuildingData.BuildingType.HOUSE) == count_before + 1, "%s: exactly one House (%d -> %d)" % [name, count_before, _count(BuildingData.BuildingType.HOUSE)])
	_expect(_last_building().global_position.distance_to(ghost_world) < 1.0, "%s: built where the ghost was" % name)
	_assert_cost(resources_before, BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE), name)
	_expect(_taps == 3, "%s: Build menu, card, Build = 3 taps (was %d)" % [name, _taps])
	_expect(map.get("selection_mgr").selected.is_empty(), "%s: the confirming tap selected nothing" % name)
	_expect(card.is_repeat_visible(), "%s: +1 House is offered on the foundation" % name)
	# A nervous second tap on the same spot opens a ghost at most; it buys nothing.
	var resources_after: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _tap(build.get_center())
	_expect(_count(BuildingData.BuildingType.HOUSE) == count_before + 1, "%s: a quick second tap does not build again" % name)
	_expect(ResourceManager.get_all_resources(0) == resources_after, "%s: a quick second tap spends nothing" % name)
	if placement.active:
		var cancel: Rect2 = card.get_cancel_button_rect()
		_expect(cancel.has_area(), "%s: x is on the ghost" % name)
		await _tap(cancel.get_center())
		_expect(not placement.active, "%s: x cancels" % name)
		_expect(ResourceManager.get_all_resources(0) == resources_after, "%s: cancel spends nothing" % name)
	card.dismiss_repeat()


func _tap_moves_never_builds(label: String) -> void:
	var name: String = "%s tap-to-move" % label
	var count_before: int = _all_buildings()
	await _pick_from_menu(BuildingData.BuildingType.HOUSE)
	var ghost_rect: Rect2 = placement.get_ghost_screen_rect()
	var safe: Rect2 = hud.call("get_placement_search_safe_rect")
	# A spot well away from the ghost, inside the field.
	var target := Vector2(safe.position.x + safe.size.x * 0.2, safe.position.y + safe.size.y * 0.6)
	var card_rect: Rect2 = card.get_build_button_rect().merge(card.get_cancel_button_rect()).grow(20.0)
	if ghost_rect.grow(30.0).has_point(target) or card_rect.has_point(target):
		target = Vector2(safe.position.x + safe.size.x * 0.8, safe.position.y + safe.size.y * 0.6)
	if ghost_rect.grow(30.0).has_point(target) or card_rect.has_point(target):
		target = Vector2(safe.position.x + safe.size.x * 0.5, safe.position.y + safe.size.y * 0.15)
	await _tap(target)
	_expect(placement.active, "%s: tapping other ground keeps placing" % name)
	_expect(_all_buildings() == count_before, "%s: tapping other ground never builds" % name)
	var center: Vector2 = placement.get_ghost_footprint_screen_rect().get_center()
	_expect(center.distance_to(target) < 40.0, "%s: the footprint centres under the finger (%s vs %s)" % [name, center, target])
	main.call("_cancel_placement")
	await _frames(2)


func _drag_ghost_and_pan(label: String) -> void:
	var name: String = "%s drag" % label
	await _pick_from_menu(BuildingData.BuildingType.HOUSE)
	var camera_before: Vector2 = map.camera.position
	var ghost_before: Vector2 = placement.ghost_position
	var start: Vector2 = placement.get_ghost_footprint_screen_rect().get_center()
	await _drag(start, start + Vector2(-90.0, 30.0))
	_expect(map.camera.position.distance_to(camera_before) < 0.5, "%s: dragging the ghost does not pan" % name)
	_expect(placement.ghost_position.distance_to(ghost_before) > 40.0, "%s: dragging the ghost carries it" % name)
	_expect(placement.active, "%s: a drag never builds" % name)
	var ghost_after: Vector2 = placement.ghost_position
	var safe: Rect2 = hud.call("get_placement_search_safe_rect")
	var empty := Vector2(safe.position.x + safe.size.x * 0.25, safe.get_center().y)
	if placement.get_ghost_screen_rect().grow(30.0).has_point(empty) or card.get_build_button_rect().grow(20.0).has_point(empty):
		empty = Vector2(safe.position.x + safe.size.x * 0.75, safe.get_center().y)
	await _drag(empty, empty + Vector2(-120.0, 40.0))
	_expect(map.camera.position.distance_to(camera_before) > 10.0, "%s: a drag off the ghost pans the map" % name)
	_expect(placement.ghost_position == ghost_after, "%s: panning leaves the ghost on its ground" % name)
	_expect(placement.active, "%s: panning never builds or cancels" % name)
	main.call("_cancel_placement")
	map.camera.position = camera_before
	await _frames(2)


func _tap_ghost_builds_in_place(label: String) -> void:
	var name: String = "%s tap ghost" % label
	var count_before: int = _count(BuildingData.BuildingType.HOUSE)
	await _pick_from_menu(BuildingData.BuildingType.HOUSE)
	_expect(placement.is_valid_placement, "%s: valid ghost" % name)
	var ghost_world: Vector2 = placement.ghost_position
	# The roof: the part a player naturally taps, far above the anchor tile.
	var art: Rect2 = placement.get_ghost_screen_rect()
	await _tap(Vector2(art.get_center().x, art.position.y + art.size.y * 0.3))
	_expect(not placement.active and _count(BuildingData.BuildingType.HOUSE) == count_before + 1, "%s: tapping the ghost builds it" % name)
	_expect(_last_building().global_position.distance_to(ghost_world) < 1.0, "%s: exactly where it was drawn" % name)
	card.dismiss_repeat()


func _five_farms(label: String) -> void:
	var name: String = "%s five Farms" % label
	var count_before: int = _count(BuildingData.BuildingType.FARM)
	var town_center: BuildingBase = main.get("_player_buildings")[0][0]
	_frame_camera(town_center.global_position, 0.8)
	await _frames(2)
	_taps = 0
	await _pick_from_menu(BuildingData.BuildingType.FARM)
	for farm: int in 5:
		if not placement.active:
			_expect(false, "%s: farm %d has no ghost" % [name, farm + 1])
			break
		_expect(placement.is_valid_placement, "%s: farm %d ghost is valid ('%s')" % [name, farm + 1, placement.get_invalid_reason()])
		# Human pace: a confirm within 0.35 s of the last one is ignored on purpose.
		await _real_wait(400)
		await _tap(card.get_build_button_rect().get_center())
		if farm < 4:
			_expect(card.is_repeat_visible(), "%s: +1 Farm after farm %d" % [name, farm + 1])
			await _tap(card.get_build_button_rect().get_center())
			await _frames(2)
	_expect(_count(BuildingData.BuildingType.FARM) == count_before + 5, "%s: five Farms (%d)" % [name, _count(BuildingData.BuildingType.FARM) - count_before])
	_expect(_taps == 11, "%s: 3 + 4 x 2 = 11 taps (was %d)" % [name, _taps])
	card.dismiss_repeat()


func _barracks_at_spot(label: String) -> void:
	var name: String = "%s Barracks" % label
	var count_before: int = _count(BuildingData.BuildingType.BARRACKS)
	var town_center: BuildingBase = main.get("_player_buildings")[0][0]
	_frame_camera(town_center.global_position, 0.8)
	await _frames(2)
	main.call("_on_building_selected_for_placement", BuildingData.BuildingType.BARRACKS)
	await _frames(3)
	var start: Vector2 = placement.get_ghost_footprint_screen_rect().get_center()
	await _drag(start, start + Vector2(70.0, -20.0))
	await _frames(2)
	if not placement.is_valid_placement:
		# Nudge until it fits, like a player would.
		for offset: Vector2 in [Vector2(40, 0), Vector2(-80, 0), Vector2(0, 30), Vector2(0, -60), Vector2(140, 20), Vector2(-200, 0), Vector2(60, 60), Vector2(200, -40)]:
			var from: Vector2 = placement.get_ghost_footprint_screen_rect().get_center()
			await _drag(from, from + offset)
			if placement.is_valid_placement:
				break
	var ghost_world: Vector2 = placement.ghost_position
	_expect(placement.is_valid_placement, "%s: a dragged Barracks fits somewhere" % name)
	await _tap(card.get_build_button_rect().get_center())
	_expect(_count(BuildingData.BuildingType.BARRACKS) == count_before + 1, "%s: Build founds it" % name)
	_expect(_last_building().global_position.distance_to(ghost_world) < 1.0, "%s: at the dragged spot" % name)
	card.dismiss_repeat()


func _mouse_flow() -> void:
	var name := "mouse"
	var town_center: BuildingBase = main.get("_player_buildings")[0][0]
	_frame_camera(town_center.global_position, 1.0)
	await _frames(2)
	main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	await _frames(2)
	var target: Vector2 = placement.get_ghost_footprint_screen_rect().get_center() + Vector2(10.0, 5.0)
	await _mouse_move(target)
	_expect(not placement.uses_touch_input(), "%s: a real mouse switches placement to mouse" % name)
	_expect(not card.is_build_visible(), "%s: no Build button chases the cursor" % name)
	_expect((hud.get("_placement_cancel_button") as Button).is_visible_in_tree(), "%s: a bottom Cancel exists for mouse" % name)
	_expect(placement.get_ghost_footprint_screen_rect().get_center().distance_to(target) < 40.0, "%s: the ghost centres under the cursor" % name)
	if not placement.is_valid_placement:
		await _mouse_move(placement.get_canvas_transform() * placement.ghost_position)
	var count_before: int = _count(BuildingData.BuildingType.HOUSE)
	var shift_target: Vector2 = placement.get_ghost_footprint_screen_rect().get_center()
	await _mouse_click(shift_target, true)
	_expect(_count(BuildingData.BuildingType.HOUSE) == count_before + 1, "%s: Shift+click builds" % name)
	_expect(placement.active, "%s: Shift+click keeps the House in hand" % name)
	var field: Rect2 = hud.call("get_placement_search_safe_rect")
	# Clear of the toast lane (the undo toast is a button).
	var open_point := Vector2(field.position.x + field.size.x * 0.2, field.end.y - 30.0)
	await _mouse_move(open_point)
	var hovered: Control = get_viewport().gui_get_hovered_control()
	_expect(hovered == null, "%s: open field under the cursor (hovering %s)" % [name, hovered.get_path() if hovered != null else ""])
	await _mouse_button(MOUSE_BUTTON_RIGHT, open_point)
	_expect(not placement.active, "%s: right click cancels" % name)
	_expect(_count(BuildingData.BuildingType.HOUSE) == count_before + 1, "%s: cancel builds nothing" % name)


# --- Helpers -----------------------------------------------------------------

func _pick_from_menu(building_type: int) -> void:
	var launcher: Control = hud.get("build_menu_button") as Control
	await _tap(launcher.get_global_rect().get_center())
	await _frames(4)
	var menu: Node = main.get("_build_menu")
	for category: String in ["Economy", "Army", "Defence"]:
		var card_button: Button = menu.get("_button_map").get(building_type) as Button
		if card_button != null and card_button.is_visible_in_tree():
			await _tap(card_button.get_global_rect().get_center())
			await _frames(3)
			return
		# Not in this tab (a tab tap is not counted: the menu opens on the recommended tab).
		menu.call("_on_category_pressed", category)
		await _frames(2)
	var card_button: Button = menu.get("_button_map").get(building_type) as Button
	if card_button != null and card_button.is_visible_in_tree():
		await _tap(card_button.get_global_rect().get_center())
		await _frames(3)
	else:
		_expect(false, "card for %s not reachable" % BuildingData.get_building_name(building_type))


func _count(building_type: int) -> int:
	var count: int = 0
	for building: Variant in main.get("_player_buildings")[0]:
		if is_instance_valid(building) and (building as BuildingBase).building_type == building_type:
			count += 1
	return count


func _all_buildings() -> int:
	return (main.get("_player_buildings")[0] as Array).size()


func _last_building() -> BuildingBase:
	var list: Array = main.get("_player_buildings")[0]
	return list[list.size() - 1] as BuildingBase


func _assert_cost(before: Dictionary, cost: Dictionary, label: String) -> void:
	var after: Dictionary = ResourceManager.get_all_resources(0)
	for resource: String in before:
		_expect(int(after[resource]) == int(before[resource]) - int(cost.get(resource, 0)), "%s: charged exactly once (%s)" % [label, resource])


func _frame_camera(world: Vector2, zoom: float) -> void:
	map.camera.position = world
	map.camera.zoom = Vector2(zoom, zoom)
	map.call("_clamp_camera")


func _frames(count: int) -> void:
	for index: int in count:
		await get_tree().process_frame


func _tap(position: Vector2) -> void:
	_taps += 1
	_index += 1
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = _to_window(position)
		event.index = _index
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)
	await _frames(1)


func _drag(from: Vector2, to: Vector2) -> void:
	_index += 1
	var press := InputEventScreenTouch.new()
	press.position = _to_window(from)
	press.index = _index
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(1)
	var previous: Vector2 = from
	for step: int in range(1, 11):
		var point: Vector2 = from.lerp(to, float(step) / 10.0)
		var drag := InputEventScreenDrag.new()
		drag.index = _index
		drag.position = _to_window(point)
		drag.relative = point - previous
		previous = point
		Input.parse_input_event(drag)
		await _frames(1)
	var release := InputEventScreenTouch.new()
	release.position = _to_window(to)
	release.index = _index
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(3)


func _mouse_move(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = position
	motion.global_position = position
	motion.relative = Vector2(2.0, 0.0)
	get_viewport().push_input(motion, true)
	await _frames(2)


func _mouse_click(position: Vector2, shift: bool = false) -> void:
	await _mouse_move(position)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.device = 0
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.shift_pressed = shift
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await _frames(2)


func _mouse_button(button: MouseButton, position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.device = 0
		event.position = position
		event.global_position = position
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await _frames(2)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _to_window(viewport_position: Vector2) -> Vector2:
	return get_viewport().get_screen_transform() * viewport_position


## Real (wall-clock) time: the 0.35 s double-confirm guard is measured in it.
func _real_wait(msec: int) -> void:
	var until: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
