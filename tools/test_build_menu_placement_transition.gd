extends Node
## Integration regression for the phone Build-menu -> world-placement transition.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const READY_FRAME_LIMIT := 900
const WORLD_TAP_POSITION := Vector2(422.0, 195.0)

var _failures: Array[String] = []
var _placement_event_count: int = 0
var _preview_event_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var match_scene: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child(match_scene)
	if not await _wait_for(func() -> bool:
		return (
			match_scene.get("_building_placement") != null
			and match_scene.get("_build_menu") != null
			and GameManager.current_state == GameManager.GameState.PLAYING
		)
	):
		_expect(false, "main scene did not finish HUD and placement setup")
		_finish(match_scene)
		return

	var hud: Node = match_scene.get_node("HUD")
	var build_menu: Node = match_scene.get("_build_menu")
	var placement: Node = match_scene.get("_building_placement")
	placement.placement_confirmed.connect(_on_placement_delivered)
	placement.placement_invalid.connect(_on_placement_invalid)
	placement.preview_changed.connect(_on_preview_changed)

	# Open the same public HUD toggle used by the touch Build button.
	hud.call("_on_build_menu_pressed")
	await get_tree().process_frame
	_expect(bool(hud.call("is_build_menu_open")), "Build button did not enter menu state")
	_expect(build_menu.is_visible_in_tree(), "Build menu surface did not open")

	# Selecting House must remove the large modal panel, not cancel the ghost.
	build_menu.call("_on_building_button_pressed", BuildingData.BuildingType.HOUSE)
	await get_tree().process_frame
	_expect(bool(match_scene.get("_placement_active")), "House selection did not activate placement")
	_expect(bool(placement.get("active")), "House selection did not activate the placement ghost")
	_expect(not bool(hud.call("is_build_menu_open")), "HUD retained stale build-menu-open state")
	_expect(not build_menu.is_visible_in_tree(), "Build menu still covered the world during placement")
	_expect(not bool(build_menu.get("_placement_mode_active")), "hidden Build menu was not reset for its next open")
	_expect(str(hud.get("build_menu_button").text) == "Build", "Build button was not reset after menu dismissal")
	_expect(bool(hud.call("is_placement_cancel_visible")), "bottom PlacementCancelButton was not left available")

	# A second Build tap is a deliberate mode switch: cancel the ghost and open
	# a normal menu whose building choices are not disabled by stale state.
	hud.call("_on_build_menu_pressed")
	await get_tree().process_frame
	_expect(not bool(match_scene.get("_placement_active")), "reopening Build did not cancel the old placement")
	_expect(not bool(placement.get("active")), "placement ghost survived reopening Build")
	_expect(bool(hud.call("is_build_menu_open")), "second Build tap did not reopen the menu")
	_expect(build_menu.is_visible_in_tree(), "Build menu surface stayed hidden on reopen")
	_expect(not bool(build_menu.get("_placement_mode_active")), "reopened Build menu retained placement mode")
	_expect(not bool(hud.call("is_placement_cancel_visible")), "bottom placement Cancel remained after reopening Build")
	_expect(str(hud.get("build_menu_button").text) == "X", "reopened Build button did not show close state")

	# Re-enter placement, then tap the center of the old menu footprint.  The
	# placement system must receive it as preview positioning without spending;
	# previously the still-visible panel swallowed this part of the world.
	build_menu.call("_on_building_button_pressed", BuildingData.BuildingType.HOUSE)
	await get_tree().process_frame
	var events_before: int = _placement_event_count
	var previews_before: int = _preview_event_count
	var initial_preview_position: Vector2 = placement.get("ghost_position")
	_expect(bool(placement.get("is_valid_placement")), "House did not open on nearby clear ground")
	var ghost_art: Sprite2D = placement.get("_ghost_sprite") as Sprite2D
	if ghost_art != null:
		var art_rect: Rect2 = ghost_art.get_rect()
		var art_top: Vector2 = ghost_art.get_global_transform_with_canvas() * art_rect.position
		var art_bottom: Vector2 = ghost_art.get_global_transform_with_canvas() * art_rect.end
		_expect(art_top.y >= 112.0, "initial House art opened behind the guidance card")
		_expect(art_bottom.y <= get_viewport().get_visible_rect().size.y - 104.0, "initial House art opened behind bottom actions")
	var wood_before_preview: int = int(ResourceManager.get_all_resources(0).get("wood", 0))
	var buildings_before_preview: int = match_scene.get("_player_buildings")[0].size()
	_push_touch(WORLD_TAP_POSITION, true)
	await get_tree().process_frame
	_push_touch(WORLD_TAP_POSITION, false)
	await get_tree().process_frame
	_expect(
		_preview_event_count > previews_before,
		"world tap inside the former Build-menu footprint did not reach placement"
	)
	_expect(_placement_event_count == events_before, "world tap placed or rejected a building before explicit Place")
	_expect(bool(placement.get("active")), "preview tap unexpectedly closed placement mode")
	_expect(int(ResourceManager.get_all_resources(0).get("wood", 0)) >= wood_before_preview, "touch preview spent wood")
	_expect(match_scene.get("_player_buildings")[0].size() == buildings_before_preview, "touch preview spawned a foundation")

	# Exercise actual viewport input ordering, with SelectionManager suspended
	# and GameMap still receiving the pair for its pinch calculation.
	var camera: Camera2D = match_scene.get_node("GameMap/Camera2D") as Camera2D
	var zoom_before: float = camera.zoom.x
	var camera_before_gesture: Vector2 = camera.position
	var ghost_before_camera_gesture: Vector2 = placement.get("ghost_position")
	_push_touch(Vector2(350.0, 180.0), true, 0)
	_push_touch(Vector2(490.0, 180.0), true, 1)
	await get_tree().process_frame
	_push_drag(Vector2(530.0, 180.0), Vector2(40.0, 0.0), 1)
	await get_tree().process_frame
	_expect(camera.zoom.x > zoom_before, "two-finger placement gesture did not reach GameMap pinch zoom")
	_expect(camera.position != camera_before_gesture, "two-finger placement gesture did not move the camera with its midpoint")
	_expect(placement.get("ghost_position") == ghost_before_camera_gesture, "pinch repositioned the inspected foundation")
	_push_touch(Vector2(530.0, 180.0), false, 1)
	_push_touch(Vector2(350.0, 180.0), false, 0)
	await get_tree().process_frame
	_expect(placement.get("ghost_position") == ghost_before_camera_gesture, "pinch release became a preview tap")

	# Return to the useful initial location and exercise the actual HUD action.
	placement.call("update_preview_at_world", initial_preview_position)
	var confirm_button: Button = hud.get("_placement_confirm_button") as Button
	_expect(confirm_button != null and confirm_button.is_visible_in_tree() and not confirm_button.disabled, "Place is unavailable for a legal preview")
	var wood_before_place: int = int(ResourceManager.get_all_resources(0).get("wood", 0))
	if confirm_button != null:
		confirm_button.pressed.emit()
	_expect(_placement_event_count == events_before + 1, "explicit HUD Place did not deliver exactly one confirmation")
	_expect(not bool(placement.get("active")), "explicit HUD Place retained the ghost")
	_expect(match_scene.get("_player_buildings")[0].size() == buildings_before_preview + 1, "explicit HUD Place did not spawn one foundation")
	var house_cost: int = int(BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE).get("wood", 0))
	_expect(int(ResourceManager.get_all_resources(0).get("wood", 0)) == wood_before_place - house_cost, "explicit HUD Place did not spend exactly the House cost")

	if bool(match_scene.get("_placement_active")):
		match_scene.call("_cancel_placement")
	_finish(match_scene)


func _wait_for(predicate: Callable) -> bool:
	for _frame in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _push_touch(position: Vector2, pressed: bool, index: int = 0) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = position
	touch.pressed = pressed
	get_viewport().push_input(touch, true)


func _push_drag(position: Vector2, relative: Vector2, index: int) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = position
	drag.relative = relative
	get_viewport().push_input(drag, true)


func _on_placement_delivered(_building_type: int, _world_position: Vector2) -> void:
	_placement_event_count += 1


func _on_placement_invalid(_reason: String) -> void:
	_placement_event_count += 1


func _on_preview_changed(_valid: bool, _reason: String) -> void:
	_preview_event_count += 1


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] build_menu_placement_transition: %s" % message)


func _finish(match_scene: Node) -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(match_scene):
		match_scene.free()
	if _failures.is_empty():
		print("[PASS] build_menu_placement_transition: useful preview, no touch spending, explicit HUD Place, cancel/reopen")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
