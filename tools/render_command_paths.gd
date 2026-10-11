extends Node
## Native layout evidence: real seeded Main, production navigation and HUD,
## frozen pending orders. Additional infantry are explicitly injected fixtures.
## This is not paid play, touch dispatch, or physical-device evidence.

const OUTPUT := "res://output/mobile-orders-2026-10-10/native"
const PHONES: Array[Vector2i] = [Vector2i(844, 390), Vector2i(932, 430)]
const INFANTRY_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")
var _records: Array[Dictionary] = []
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("render_command_paths requires a native renderer; omit --headless")
		get_tree().quit(1)
		return
	AudioManager.set_all_enabled(false)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for phone: Vector2i in PHONES:
		await _profile(phone)
	var evidence := FileAccess.open(OUTPUT + "/manifest.json", FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"evidence": "Native root-window captures at real requested phone pixels, seed101 and ordinary production terrain/navigation. Frozen real Main/HUD and pending runtime orders; worker moved to a legal nearby tile and infantry injected to show military feedback. No paid match, simulated-touch, or physical-device claim.", "captures": _records, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] render_command_paths: " + failure)
	if _failures.is_empty():
		print("[PASS] render_command_paths: %d actual phone captures, two sizes, overview/default/detail, worker Move and grouped military Attack" % _records.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile(phone: Vector2i) -> void:
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	await _frames(2)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 30
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	if main.get("_building_placement") == null:
		_failures.append("%s did not initialize Main" % phone)
		main.free()
		return
	await _frames(4)
	var map: Node2D = main.get("game_map") as Node2D
	var selection: SelectionManager = map.get("selection_mgr") as SelectionManager
	var overlay: Node2D = map.get_node("CommandPaths") as Node2D
	var hud: CanvasLayer = main.get("hud") as CanvasLayer
	var camera: Camera2D = map.get("camera") as Camera2D
	var worker: UnitBase = (main.get("_player_units")[0] as Array)[0] as UnitBase
	var tc: BuildingBase = main.get("_player_town_center") as BuildingBase
	main.set_process(false)
	map.set_process(false)
	(main.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	worker.command_stop()
	var fixture: Dictionary = _find_short_detour(map, tc)
	if fixture.is_empty():
		_failures.append("%s has no bounded natural route fixture" % phone)
		main.free()
		return
	var worker_origin: Vector2 = map.tile_to_world(fixture["start"])
	var target: Vector2i = fixture["target"]
	worker.global_position = worker_origin
	var infantry: Array[Node2D] = []
	for index: int in 3:
		var troop := INFANTRY_SCENE.instantiate() as UnitBase
		troop.player_owner = 0
		troop.position = worker_origin + Vector2(index * 16.0, -index * 8.0)
		map.get_node("UnitsContainer").add_child(troop)
		troop.set_process(false)
		infantry.append(troop)
	main.call("_update_fog_of_war")
	var zoom_state: Dictionary = map.call("get_zoom_state")
	for zoom_name: String in ["overview", "default", "detail"]:
		var zoom: float = float(zoom_state["min" if zoom_name == "overview" else ("max" if zoom_name == "detail" else "default")])
		camera.zoom = Vector2(zoom, zoom)
		for state: String in ["worker_move", "army_attack"]:
			if state == "worker_move":
				worker.global_position = worker_origin
				worker.command_stop()
				selection.select_single(worker)
				main.call("_arm_move_command")
				main.call("_on_move_command", target)
				worker.call("_process_moving", 0.01)
			else:
				selection.select_many(infantry)
				main.call("_on_move_command", target)
				for troop: UnitBase in infantry:
					troop.call("_process_moving", 0.01)
			for toast: Node in (hud.get("_notification_container") as Control).get_children():
				hud.call("_retire_dynamic_control", toast)
			var routes: Array[Dictionary] = overlay.call("get_display_routes")
			if routes.is_empty():
				_failures.append("%s %s %s produced no live navigation feedback" % [phone, zoom_name, state])
				continue
			var bounds: Rect2 = _route_bounds(routes)
			camera.position = bounds.get_center() + Vector2(0.0, 16.0 / zoom)
			camera.reset_smoothing()
			camera.force_update_scroll()
			hud.call("update_camera_zoom", zoom, float(zoom_state["min"]), float(zoom_state["max"]))
			main.call("_on_selection_changed", selection.selected)
			await _frames(3)
			hud.call("apply_mobile_layout", get_viewport().get_visible_rect().size, Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size))
			main.call("_update_minimap")
			overlay.queue_redraw()
			await _frames(2)
			await RenderingServer.frame_post_draw
			var bitmap: Image = get_viewport().get_texture().get_image()
			if bitmap.get_size() != phone:
				_failures.append("%s actual bitmap size is %s" % [phone, bitmap.get_size()])
			var filename: String = "%dx%d-%s-%s.png" % [phone.x, phone.y, zoom_name, state]
			bitmap.save_png(OUTPUT + "/" + filename)
			hud.call("_refresh_touch_target_diagnostics")
			var route_records: Array[Dictionary] = []
			for route: Dictionary in routes:
				route_records.append({"mode": route["mode"], "world_points": str(route["points"]), "destination": str(route["destination"]), "order_destination": str(route["order_destination"]), "projected_destination": str(get_viewport().get_canvas_transform() * (route["destination"] as Vector2))})
			_records.append({"image": filename, "phone": str(phone), "bitmap_size": str(bitmap.get_size()), "logical_viewport": str(get_viewport().get_visible_rect().size), "zoom_name": zoom_name, "zoom": zoom, "state": state, "routes": route_records, "selection_name": (hud.get("selection_name") as Label).text, "selection_details": (hud.get("selection_details") as Label).text, "touch_targets": hud.get("touch_target_diagnostics").duplicate(true), "tc_position": str(tc.global_position), "fixture": str(fixture)})
	selection.deselect_all()
	main.free()
	await _frames(2)


func _find_short_detour(map: Node2D, tc: BuildingBase) -> Dictionary:
	var origin: Vector2i = map.world_to_tile(tc.global_position)
	var best: Dictionary = {}
	var best_score: float = -INF
	for start_offset: Vector2i in [Vector2i(-3, 0), Vector2i(-3, -1), Vector2i(-2, -2), Vector2i(0, -3), Vector2i(1, -3), Vector2i(3, -2), Vector2i(4, 0), Vector2i(4, 2)]:
		var start_tile: Vector2i = origin + start_offset
		if not map.is_tile_walkable(start_tile):
			continue
		var start: Vector2 = map.tile_to_world(start_tile)
		for dy: int in range(-5, 6):
			for dx: int in range(-5, 6):
				var tile := start_tile + Vector2i(dx, dy)
				if not map.is_tile_walkable(tile):
					continue
				var target: Vector2 = map.tile_to_world(tile)
				var direct: float = start.distance_to(target)
				if direct < 100.0 or direct > 175.0:
					continue
				var tiles: Array[Vector2i] = map.get_movement_path(start_tile, tile)
				if tiles.size() < 3:
					continue
				var bounds := Rect2(start, Vector2.ZERO)
				var length: float = 0.0
				for index: int in range(tiles.size()):
					bounds = bounds.expand(map.tile_to_world(tiles[index]))
					if index > 0:
						length += map.tile_to_world(tiles[index - 1]).distance_to(map.tile_to_world(tiles[index]))
				if bounds.size.y > 64.0 or bounds.size.x > 200.0:
					continue
				var score: float = length / direct + bounds.size.x * 0.001
				if score > best_score:
					best = {"start": start_tile, "target": tile, "route_length": length, "direct_length": direct}
					best_score = score
	return best


func _route_bounds(routes: Array[Dictionary]) -> Rect2:
	var first: Vector2 = (routes[0]["points"] as PackedVector2Array)[0]
	var bounds := Rect2(first, Vector2.ZERO)
	for route: Dictionary in routes:
		for point: Vector2 in route["points"]:
			bounds = bounds.expand(point)
	return bounds


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame
