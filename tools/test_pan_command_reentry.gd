extends "res://tools/test_occlusion_touch_orders.gd"
## Actual ScreenTouch journeys with real camera pan and ordinary moving Scouts.
## Staged positions/vision isolate input routing; not a physical-device test.
var _orders: int = 0
var _scout: UnitBase
var _fighter: UnitBase

func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.ui_scale = 1.0
	for civ: int in CivilizationData.ORDERED_IDS:
		GameManager.selected_civilization = civ
		GameManager.selected_opponent_civilization = civ
		GameManager.set_state(GameManager.GameState.MENU)
		_main = load("res://scenes/main/main.tscn").instantiate()
		add_child(_main)
		for frame: int in 900:
			if _main.get("_building_placement") != null: break
			await get_tree().process_frame
		_main.set_process(false)
		_main.ai_controller.set_process(false)
		_main.ai_controller.get("_decision_timer").stop()
		_main.get_node("StrategyController").set_process(false)
		_map = _main.game_map
		_map.fog_of_war.set_process(false)
		_map.fog_of_war.reveal_all()
		_map.note_camera_interaction()
		_map.set("_user_zoom_override", true)
		_map.set("_touch_input_detected", true)
		_selection = _map.selection_mgr
		_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
		_overlay = _map.get_node("UnitOcclusionOverlay")
		_overlay.set("allow_headless_fixture", true)
		_overlay.set_process(false)
		for unit: Node in get_tree().get_nodes_in_group("units"):
			unit.set_process(false)
			unit.command_stop()
		_scout = (_main.get("_player_units")[0] as Array).filter(func(unit: UnitBase) -> bool: return unit.unit_type == UnitData.UnitType.SCOUT)[0]
		_fighter = _main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, _map.tile_to_world(Vector2i(38, 30)))
		_fighter.set_process(false)
		for physical: Vector2i in [Vector2i(844, 390), Vector2i(951, 669)]:
			get_window().size = physical
			get_window().content_scale_size = physical
			await _frames(3)
			for zoom: float in [1.3, 2.2]:
				_profile = "civ%d %s zoom%.1f" % [civ, physical, zoom]
				_map.camera.zoom = Vector2.ONE * zoom
				_map.camera.position_smoothing_enabled = false
				_scout.command_stop()
				_scout.global_position = _open_route()[0]
				_fighter.global_position = _scout.global_position + Vector2(-80, 50)
				await _center(_scout.global_position)
				await _pan_then_command()
				await _moving_unit_tap(false)
				await _moving_unit_tap(true)
				await _echo_reselection()
		_main.free()
		await _frames(1)
	for failure: String in _failures: push_error("[FAIL] pan_command_reentry: " + failure)
	print("[PAN COMMAND REENTRY] checks=%d failures=%d" % [_checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _pan_then_command() -> void:
	_selection.deselect_all()
	await _tap(_selection._world_to_screen(_opaque_point(_scout.get("_sprite"), Vector2(0.3, 0.6))))
	_expect(_selection.selected == [_scout], "select Scout before move/pan")
	var ground: Vector2 = _pan_safe_ground(Vector2(40, 0))
	_expect(ground != Vector2.ZERO, "empty visible ground on both sides of pan")
	var before: int = _orders
	await _quick_tap(ground)
	var old_target: Vector2 = _scout.move_target
	var camera_before: Vector2 = _map.camera.position
	_contact_id += 1
	var start := ground + Vector2(0, 25)
	await _contact(start, true)
	var drag := InputEventScreenDrag.new()
	drag.index = _contact_id
	drag.position = get_viewport().get_final_transform() * (start + Vector2(40, 0))
	drag.relative = get_viewport().get_final_transform().basis_xform(Vector2(40, 0))
	Input.parse_input_event(drag)
	await _frames(1)
	await _contact(start + Vector2(40, 0), false)
	_expect(not _map.camera.position.is_equal_approx(camera_before), "real pan changes camera")
	_expect(_orders == before + 1 and _selection.selected == [_scout], "pan preserves selection and existing order")
	await _quick_tap(ground)
	_expect(_orders == before + 2 and _selection.selected == [_scout], "rapid post-pan ground tap orders instead of clearing")
	_expect(not _scout.move_target.is_equal_approx(old_target), "new camera transform supplies new destination")
	_expect((_map.get("_touch_points") as Dictionary).is_empty() and (_selection.get("_active_touch_indices") as Dictionary).is_empty(), "pan contacts retire")
	_scout.command_stop()

func _moving_unit_tap(reselect: bool) -> void:
	var route: Array[Vector2] = _open_route()
	_scout.global_position = route[0]
	_scout.command_stop()
	_fighter.global_position = route[0] + Vector2(-90, 50)
	await _center(route[0])
	if reselect: _selection.select_single(_fighter)
	else: _selection.deselect_all()
	await _frames(2)
	_scout.command_move(route[1])
	_scout.set_process(true)
	var point: Vector2 = _selection._world_to_screen(_opaque_point(_scout.get("_sprite"), Vector2(0.3, 0.6)))
	var origin: Vector2 = _scout.global_position
	_contact_id += 1
	await _contact(point, true)
	await get_tree().create_timer(0.23).timeout
	await _contact(point, false)
	_scout.set_process(false)
	_expect(origin.distance_to(_scout.global_position) > 15.0, "ordinary moving target advances during tap")
	_expect(_selection.selected == [_scout], "touch-down moving Scout remains target on release; reselect=" + str(reselect))
	_expect(_scout.move_target.is_equal_approx(route[1]), "selecting moving unit preserves its route")
	_scout.command_stop()

func _echo_reselection() -> void:
	var tree: ResourceNode = null
	for resource: ResourceNode in _map.resource_nodes.values():
		if resource.resource_type == "wood":
			tree = resource
			break
	if tree == null: return
	tree.visible = true
	_scout.global_position = tree.global_position + Vector2(0, -5)
	_fighter.global_position = tree.global_position + Vector2(-80, 45)
	await _center(_scout.global_position)
	_overlay.call("_process", 0.2)
	_selection.select_single(_fighter)
	await _frames(3)
	var sprite: Sprite2D = _scout.get("_sprite")
	var ink: Rect2 = KingdomArt.ink_rect(sprite.texture)
	ink.position += sprite.get_rect().position
	var point := Vector2.INF
	for y: int in 20:
		for x: int in 20:
			var local: Vector2 = ink.position + ink.size * Vector2(float(x) / 19.0, float(y) / 19.0)
			var world: Vector2 = sprite.to_global(local)
			var screen: Vector2 = _selection._world_to_screen(world)
			if not _main.hud.get_hold_safe_rect().has_point(screen): continue
			var occluded: bool = false
			for rect: Rect2 in _main.hud.get_world_occlusion_rects():
				if rect.has_point(screen): occluded = true
			if occluded: continue
			if sprite.is_pixel_opaque(local) and not _selection._is_touch_on_unit_body(_scout, world) and _selection._world_to_screen(world).distance_to(_selection._world_to_screen(_scout.global_position)) > 25.0 and _selection._get_node_at(world, true) == _scout:
				point = _selection._world_to_screen(world)
				break
		if point.is_finite(): break
	_expect(point.is_finite(), "visible silhouette has deliberate outer pixel")
	if point.is_finite():
		await _quick_tap(point)
		_expect(_selection.selected == [_scout], "opaque silhouette reselects with another unit already selected: point=%s action=%s" % [point, _selection.touch_input_diagnostics.get("action", "")])

func _open_route() -> Array[Vector2]:
	for x: int in range(30, 51):
		for y: int in range(25, 46):
			var a := Vector2i(x, y)
			var b := a + Vector2i(5, -5)
			var from: Vector2 = _map.tile_to_world(a)
			var to: Vector2 = _map.tile_to_world(b)
			if not _map.is_tile_walkable(a) or not _map.is_tile_walkable(b): continue
			var path: PackedVector2Array = _map.get_navigation_world_path(from, to)
			if path.size() >= 2 and path[1].distance_to(from) > 20.0: return [from, to]
	return [_map.tile_to_world(Vector2i(36, 34)), _map.tile_to_world(Vector2i(41, 29))]

func _pan_safe_ground(delta: Vector2) -> Vector2:
	var view: Vector2 = get_viewport().get_visible_rect().size
	for y: float in [0.35, 0.42, 0.5, 0.58]:
		for x: float in [0.35, 0.42, 0.5, 0.58, 0.65]:
			var screen := view * Vector2(x, y)
			var world: Vector2 = _selection._screen_to_world(screen)
			var after: Vector2 = world - delta / _map.camera.zoom
			if _selection._get_node_at(world, true) == null and _selection._get_resource_at(world, true) == null and _selection._get_node_at(after, true) == null and _selection._get_resource_at(after, true) == null and _map.world_to_tile(world) != _map.world_to_tile(after) and _map.is_tile_walkable(_map.world_to_tile(world)) and _map.is_tile_walkable(_map.world_to_tile(after)): return screen
	return Vector2.ZERO

func _quick_tap(point: Vector2) -> void:
	_contact_id += 1
	await _contact(point, true)
	await _contact(point, false)

func _contact(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = _contact_id
	event.position = get_viewport().get_final_transform() * point
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(1)
