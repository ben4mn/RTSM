extends Node
## Controlled real-scene presentation fixture. Synthetic positions/actors,
## normal runtime movement, no paid-match or physical-device claim.

var failures: Array[String] = []
var profiles: Array[Dictionary] = []
var assertions: int = 0
var output_dir: String = "res://output/selected-unit-cues"
var report_path: String = ""
var main: Node2D
var map: Node2D
var selection: SelectionManager
var overlay: Node2D
var scout: UnitBase
var enemies: Array[UnitBase] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			report_path = argument.trim_prefix("--output=")
	if not report_path.is_empty():
		output_dir = report_path.get_basename() + "-captures"
	elif not OS.get_environment("AOEM_CAPTURE_UX_DIR").is_empty():
		output_dir = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if report_path.is_empty():
		report_path = output_dir.path_join("receipt.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = 1
	GameManager.selected_population_limit = 30
	GameManager.clearer_player_markers = true
	GameManager.reduced_motion = false
	GameManager.reduced_flashes = false
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.15]:
			await _profile(phone, interface_scale)
	var hashes: Dictionary = {}
	for path: String in ["scripts/ui/command_path_overlay.gd", "scripts/managers/selection_manager.gd", "scripts/units/unit_base.gd", "tools/test_selected_unit_cues.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify({"scope": "Controlled actual Main/SelectionManager/UnitBase; four phone/scale profiles and three zooms. Geometry and native on/off pixel comparisons when rendered. No paid, network, physical-phone or performance claim.", "renderer": DisplayServer.get_name(), "assertions": assertions, "profiles": profiles, "source_hashes": hashes, "user_data_dir": OS.get_user_data_dir(), "failures": failures}, "  "))
	for failure: String in failures:
		push_error("[FAIL] selected_unit_cues: " + failure)
	if failures.is_empty():
		print("[PASS] selected_unit_cues: crowd, movement/idle/preview expiry, ownership/visibility/lifecycle/settings, fixed-screen geometry and native hollow pixels")
	get_tree().quit(0 if failures.is_empty() else 1)


func _profile(phone: Vector2i, interface_scale: float) -> void:
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = interface_scale
	GameManager.ui_scale = interface_scale
	GameManager.set_process(true)
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_expect(main.get("_building_placement") != null, "Main initializes")
	main.set_process(false)
	GameManager.set_process(false)
	(main.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	map = main.get("game_map")
	map.set_process(false)
	selection = map.get("selection_mgr")
	overlay = map.get_node("CommandPaths")
	_expect(overlay.has_method("get_selected_unit_cue_points"), "foreground cue geometry API present")
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	(map.get("sacred_site") as Node).set_process(false)
	(map.get("fog_of_war") as Node).set_process(false)
	var center: Vector2 = (map.get("sacred_site") as Node2D).global_position
	scout = _unit("scout", 0, center)
	enemies.clear()
	for offset: Vector2 in [Vector2(-6, -2), Vector2(7, 5), Vector2(15, -8)]:
		enemies.append(_unit("infantry", 1, center + offset))
	selection.select_single(scout)
	_refresh_vision()
	await _frames(3)
	var bank_before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var nodes_before: int = overlay.get_child_count()
	var sprite_z: int = scout.get_node("UnitSprite").z_index
	var camera: Camera2D = map.get("camera")
	map.call("note_camera_interaction")
	for zoom: float in [0.65, 0.952, 1.6]:
		camera.zoom = Vector2.ONE * zoom
		camera.position = center
		camera.reset_smoothing()
		camera.force_update_scroll()
		await _frames(3)
		var points: PackedVector2Array = _points()
		_expect(points.size() == 8, "one Scout has exactly four bracket segments")
		var bounds: Rect2 = _screen_bounds(points)
		_expect(bounds.size.distance_to(Vector2(12, 6)) < 0.01, "bracket remains12×6 screen units at zoom" + str(zoom))
		if points.size() == 8:
			var anchor: Vector2 = scout.get_global_transform_with_canvas().origin
			var first: Vector2 = overlay.get_global_transform_with_canvas() * points[0]
			_expect(first.is_equal_approx(anchor + Vector2(-6, -2)), "bracket follows the exact own foot anchor")
		var record: Dictionary = {"phone": [phone.x, phone.y], "ui_scale": interface_scale, "zoom": zoom, "points": points.size(), "screen_size": [bounds.size.x, bounds.size.y]}
		if DisplayServer.get_name() != "headless":
			await _render_pair(phone, interface_scale, zoom, record)
		profiles.append(record)
	_contracts(center)
	_expect(ResourceManager.get_all_resources(0) == bank_before, "visual reads preserve bank")
	_expect(overlay.get_child_count() == nodes_before, "cue adds no permanent overlay nodes")
	_expect(scout.get_node("UnitSprite").z_index == sprite_z and overlay.z_index == 15, "unit depth and existing foreground layer stay unchanged")
	selection.select_single(scout)
	if DisplayServer.get_name() != "headless":
		await _deselection_pixels()
	main.free()
	await _frames(3)


func _contracts(center: Vector2) -> void:
	_check_online_owner_remap()
	var original_hp: float = scout.hp
	var state: int = scout.current_state
	GameManager.clearer_player_markers = false
	_expect(_points().is_empty(), "Clear player markers off removes only the extra cue")
	GameManager.clearer_player_markers = true
	GameManager.reduced_motion = true
	GameManager.reduced_flashes = true
	_expect(_points().size() == 8, "static cue remains in reduced motion/flashes")
	GameManager.reduced_motion = false
	GameManager.reduced_flashes = false
	scout.hide()
	_expect(_points().is_empty(), "hidden own unit has no foreground cue")
	scout.show()
	var fog: FogManager = map.get("fog_of_war")
	var tile: Vector2i = map.call("world_to_tile", scout.global_position)
	var original_fog: int = fog.fog_grid[tile.y][tile.x]
	fog.fog_grid[tile.y][tile.x] = MapData.FogState.EXPLORED
	_expect(_points().is_empty(), "explored own tile is not current vision")
	fog.fog_grid[tile.y][tile.x] = original_fog
	_refresh_vision()
	scout.is_selected = false
	_expect(_points().is_empty(), "stale deselected entry is filtered")
	scout.is_selected = true
	scout.current_state = UnitBase.State.DEAD
	_expect(_points().is_empty(), "dead own unit has no cue")
	scout.current_state = state
	scout.hp = 0
	_expect(_points().is_empty(), "zero HP cannot retain a cue before state cleanup")
	scout.hp = original_hp
	var enemy: UnitBase = enemies[0]
	enemy.is_selected = true
	selection.selected.append(enemy)
	_expect(_points().size() == 8, "selected visible enemy cannot add a foreground marker")
	selection.selected.erase(enemy)
	enemy.is_selected = false
	var building: Node2D = (main.get("_player_buildings")[0] as Array)[0]
	selection.selected.append(building)
	_expect(_points().size() == 8, "selected building cannot add a unit marker")
	selection.selected.erase(building)
	var second: UnitBase = _unit("infantry", 0, center + Vector2(-60, 0))
	second.is_selected = true
	selection.selected.append(second)
	_refresh_vision()
	_expect(_points().size() == 16, "multiple selected own units share one batched segment list")
	second.queue_free()
	_expect(_points().size() == 8, "queued own unit cannot retain a cue")
	selection.selected.erase(second)
	(main.get("_player_units")[0] as Array).erase(second)
	second.free()
	var freed: UnitBase = _unit("infantry", 0, center)
	freed.is_selected = true
	selection.selected.append(freed)
	(main.get("_player_units")[0] as Array).erase(freed)
	freed.free()
	_expect(_points().size() == 8, "freed retained entry is validated before typed access")
	selection._prune_stale_selection()
	scout.command_move_path(PackedVector2Array([center, center + Vector2(64, 0)]))
	var path_before: PackedVector2Array = scout.path.duplicate()
	var goal_before: Vector2 = scout.move_target
	for repeat: int in 10:
		_points()
	_expect(scout.path == path_before and scout.move_target == goal_before and scout.hp == original_hp, "cue reads never mutate route, intent or HP")
	for step: int in 6:
		scout.call("_process_moving", 0.05)
	_refresh_vision()
	_expect(scout.global_position.distance_to(center) > 10.0 and _points().size() == 8, "real passive movement keeps the foreground foot cue")
	var routes: Array = overlay.call("get_display_routes")
	_expect(not routes.is_empty(), "ordinary route preview remains available")
	var observed: Dictionary = overlay.get("_observed_orders")
	if observed.has(scout.get_instance_id()):
		(observed[scout.get_instance_id()] as Dictionary)["started"] = Time.get_ticks_msec() / 1000.0 - 2.1
	_expect((overlay.call("get_display_routes") as Array).is_empty() and _points().size() == 8, "cue survives unchanged two-second route expiry")
	scout.command_stop()
	scout.global_position = center
	_refresh_vision()
	_expect(_points().size() == 8, "idle selected unit remains locatable")
	selection.deselect_all()
	_expect(_points().is_empty(), "deselect clears the cue")
	selection.select_single(scout)
	_expect(_points().size() == 8, "reselection restores the cue")


func _check_online_owner_remap() -> void:
	var adapter: Node = load("res://scripts/network/network_match.gd").new()
	var original_slot: int = NetworkSession.player_slot
	for slot: int in 2:
		NetworkSession.player_slot = slot
		scout.player_owner = adapter.call("_local_owner", slot)
		_expect(scout.player_owner == 0 and _points().size() == 8, "server slot%d maps own cue to local0" % slot)
		scout.player_owner = adapter.call("_local_owner", 1 - slot)
		_expect(scout.player_owner == 1 and _points().is_empty(), "server slot%d never marks opposing actor" % slot)
	scout.player_owner = 0
	NetworkSession.player_slot = original_slot
	adapter.free()


func _render_pair(phone: Vector2i, interface_scale: float, zoom: float, record: Dictionary) -> void:
	overlay.show()
	overlay.queue_redraw()
	await _frames(3)
	await RenderingServer.frame_post_draw
	var with_cue: Image = get_viewport().get_texture().get_image()
	overlay.hide()
	await _frames(2)
	await RenderingServer.frame_post_draw
	var reference: Image = get_viewport().get_texture().get_image()
	var center: Vector2 = scout.get_global_transform_with_canvas().origin
	var ratio: float = float(with_cue.get_width()) / get_viewport().get_visible_rect().size.x
	var changed: int = _changed_pixels(with_cue, reference, Rect2(center + Vector2(-8, -4), Vector2(16, 10)), ratio)
	var hollow: int = _changed_pixels(with_cue, reference, Rect2(center + Vector2(-1, -1), Vector2(2, 3)), ratio)
	var bodies: int = _changed_pixels(with_cue, reference, Rect2(center + Vector2(-30, -65), Vector2(60, 58)), ratio)
	_expect(changed > 8, "foreground cue remains visible over the crowded Scout")
	_expect(hollow == 0, "foot center stays hollow, without a filled badge")
	_expect(bodies == 0, "foreground cue leaves body pixels unchanged")
	var name_tag: String = "%dx%d-scale%.2f-zoom%.3f" % [phone.x, phone.y, interface_scale, zoom]
	with_cue.save_png(output_dir.path_join(name_tag + "-cue.png"))
	reference.save_png(output_dir.path_join(name_tag + "-reference.png"))
	record["cue_pixels"] = changed
	record["center_pixels"] = hollow
	record["body_pixels"] = bodies
	overlay.show()


func _deselection_pixels() -> void:
	selection.deselect_all()
	await _frames(3)
	await RenderingServer.frame_post_draw
	var cleared: Image = get_viewport().get_texture().get_image()
	overlay.hide()
	await _frames(2)
	await RenderingServer.frame_post_draw
	var reference: Image = get_viewport().get_texture().get_image()
	var center: Vector2 = scout.get_global_transform_with_canvas().origin
	var ratio: float = float(cleared.get_width()) / get_viewport().get_visible_rect().size.x
	_expect(_changed_pixels(cleared, reference, Rect2(center + Vector2(-10, -5), Vector2(20, 12)), ratio) == 0, "deselect signal clears the last drawn pixels")
	overlay.show()


func _unit(scene: String, owner: int, at: Vector2) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/" + scene + ".tscn").instantiate()
	unit.player_owner = owner
	unit.position = at
	map.get_node("UnitsContainer").add_child(unit)
	unit.set_process(false)
	(main.get("_player_units")[owner] as Array).append(unit)
	return unit


func _refresh_vision() -> void:
	main.call("_update_fog_of_war")
	main.call("_update_fog_entity_visibility")


func _points() -> PackedVector2Array:
	return overlay.call("get_selected_unit_cue_points") if overlay.has_method("get_selected_unit_cue_points") else PackedVector2Array()


func _screen_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var transform: Transform2D = overlay.get_global_transform_with_canvas()
	var bounds := Rect2(transform * points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(transform * point)
	return bounds


func _changed_pixels(a: Image, b: Image, rectangle: Rect2, ratio: float) -> int:
	var pixels := Rect2i(rectangle.position * ratio, rectangle.size * ratio)
	pixels = pixels.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var changed: int = 0
	for y: int in range(pixels.position.y, pixels.end.y):
		for x: int in range(pixels.position.x, pixels.end.x):
			if a.get_pixel(x, y).to_rgba32() != b.get_pixel(x, y).to_rgba32():
				changed += 1
	return changed


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
