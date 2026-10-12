extends Node
## Project real rendered subjects into phone fields; keep manual zoom untouched.

var _failures: Array[String] = []
var _render: bool = false
var _profiles: Array[Dictionary] = []
var _output: String = "res://output/evolution/large-maps-20261012-camera/framing"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	if not OS.get_environment("AOEM_CAMERA_TEST_OUTPUT").is_empty():
		_output = OS.get_environment("AOEM_CAMERA_TEST_OUTPUT")
	_render = "--render" in OS.get_cmdline_user_args()
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for seed_value: int in [42, 101, 424242]:
			for guided: bool in [false, true]:
				await _profile(phone, seed_value, guided)
	var output: String = _output
	DirAccess.make_dir_recursive_absolute(output)
	var manifest := FileAccess.open(output + "/framing.json", FileAccess.WRITE)
	var hashes: Dictionary = {}
	for path: String in ["scripts/map/game_map.gd", "scripts/map/map_data.gd", "scripts/map/map_generator.gd", "tools/test_mobile_camera_framing.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	manifest.store_string(JSON.stringify({"evidence": "Frozen real main scenes in phone-sized SubViewports; actual projected sprite/marker bounds and synthetic notch insets. Optional native render images are layout evidence, not paid play or a physical phone.", "source_sha256": hashes, "profiles": _profiles}, "  "))
	if _failures.is_empty():
		print("[PASS] mobile_camera_framing: real Guide ON/OFF boots and TC/worker/food fit two phone sizes/notches across three seeds; Home handles distant food, preserves2.2 manual zoom, TC access and fog")
	else:
		for failure: String in _failures:
			push_error("[FAIL] mobile_camera_framing: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile(phone_size: Vector2i, seed_value: int, guided: bool) -> void:
	var phone := SubViewport.new()
	phone.size = phone_size
	phone.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(phone)
	GameManager.selected_map_seed = seed_value
	GameManager.guided_opening_enabled = guided
	var match_scene: Node = load("res://scenes/main/main.tscn").instantiate()
	phone.add_child(match_scene)
	for frame: int in 900:
		if GameManager.current_state == GameManager.GameState.PLAYING and match_scene.get("_player_town_center") != null:
			break
		await get_tree().process_frame
	# Include the deferred final opening focus and real Guide layout, rather
	# than testing only a later direct call that skips the boot ordering.
	for frame: int in 4:
		await get_tree().process_frame
	match_scene.set_process(false)
	(match_scene.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var map: Node2D = match_scene.get("game_map") as Node2D
	map.set_process(false)
	var camera: Camera2D = map.get("camera") as Camera2D
	var hud: CanvasLayer = match_scene.get("hud") as CanvasLayer
	var tc: BuildingBase = match_scene.get("_player_town_center") as BuildingBase
	var food: Node2D = map.call("get_nearest_resource_node", "food", tc.global_position, 0)
	_expect(food != null, "seed %d has a currently visible starting food target" % seed_value)
	var workers: Array = (match_scene.get("_player_units") as Array)[0]
	var worker: UnitBase = _find_accessible_worker(hud, workers, tc, Rect2(Vector2.ZERO, Vector2(phone_size)))
	var prefix: String = "%dx%d seed %d guided=%s" % [phone_size.x, phone_size.y, seed_value, guided]
	_expect((hud.get("_progression_hint_panel") as Control).visible == guided, prefix + " boots the actual Guide state")
	_check_accessible(hud, tc, worker, food, Rect2(Vector2.ZERO, Vector2(phone_size)), prefix + " initial boot")
	if _render:
		await RenderingServer.frame_post_draw
		var boot_output: String = _output
		DirAccess.make_dir_recursive_absolute(boot_output)
		phone.get_texture().get_image().save_png("%s/%dx%d-seed%d-boot%s.png" % [boot_output, phone_size.x, phone_size.y, seed_value, "-guided" if guided else ""])
	var zoom_state: Dictionary = map.call("get_zoom_state")
	_expect(is_equal_approx(float(map.get("mobile_default_zoom")), 1.25), prefix + " uses the closer mobile default")
	_expect(is_equal_approx(float(zoom_state["min"]), 0.42) and is_equal_approx(float(zoom_state["max"]), 2.2), prefix + " expands overview while preserving detail limits")
	for notched: bool in [false, true]:
		var safe_area := Rect2(Vector2(44, 0), Vector2(phone_size) - Vector2(88, 18)) if notched else Rect2(Vector2.ZERO, Vector2(phone_size))
		hud.call("apply_mobile_layout", Vector2(phone_size), safe_area)
		camera.position = match_scene.call("_get_initial_camera_focus", tc.global_position, safe_area)
		map.call("_clamp_camera")
		camera.reset_smoothing()
		camera.force_update_scroll()
		await get_tree().process_frame
		await get_tree().process_frame
		worker = _find_accessible_worker(hud, workers, tc, safe_area)
		# Actual top rail and selected command shelf define the vertical corridor;
		# notch edges define horizontal accessibility independently of Main's pan.
		var top: float = (hud.get_node("Root/TopBar") as Control).get_global_rect().end.y + 8.0
		var bottom: float = safe_area.end.y - 80.0
		var field := Rect2(Vector2(safe_area.position.x + 8.0, top), Vector2(safe_area.size.x - 16.0, bottom - top))
		_check_accessible(hud, tc, worker, food, safe_area, prefix + (" notched" if notched else " full"))
		_profiles.append({"phone": str(phone_size), "seed": seed_value, "notched": notched, "guided": guided, "zoom": camera.zoom.x, "configured_default": zoom_state["default"], "field": str(field), "tc": str(_projected_visual_bounds(tc)), "worker": str(_projected_visual_bounds(worker)), "food": str(_projected_visual_bounds(food))})
		if _render:
			await RenderingServer.frame_post_draw
			var output: String = _output
			DirAccess.make_dir_recursive_absolute(output)
			phone.get_texture().get_image().save_png("%s/%dx%d-seed%d-%s%s.png" % [output, phone_size.x, phone_size.y, seed_value, "notched" if notched else "full", "-guided" if guided else ""])

	# Home can locate the economy after free play as well as the tutorial, but
	# it never changes deliberate pinch zoom or inspects resources behind fog.
	if phone_size == Vector2i(844, 390) and seed_value == 101 and not guided:
		for natural: Node2D in (map.get("resource_nodes") as Dictionary).values():
			if natural is ResourceNode and natural.resource_type == "food":
				natural.harvest(natural.remaining)
		var remote_farm: BuildingBase = match_scene.call("_spawn_building", BuildingData.BuildingType.FARM, 0, Vector2i(40, 40)) as BuildingBase
		remote_farm.complete_instantly()
		_expect(remote_farm.global_position.distance_to(tc.global_position) > 512.0, "depleted-berries fixture has only remote food context")
		_expect(map.call("get_nearest_resource_node", "food", tc.global_position, 0) == remote_farm, "owned remote Farm is the nearest known harvestable food")
		match_scene.call("_select_town_center")
		camera.reset_smoothing()
		camera.force_update_scroll()
		await get_tree().process_frame
		await get_tree().process_frame
		_check_accessible(hud, tc, worker, null, Rect2(Vector2.ZERO, Vector2(phone_size)), "Home after local berries deplete")
		_expect(camera.zoom.x > 0.9, "remote Farm does not force Home to whole-map zoom")
	map.call("zoom_in")
	map.call("zoom_in")
	map.call("_update_camera_zoom", 0.2)
	var chosen_zoom: Vector2 = camera.zoom
	var fog: FogManager = map.get("fog_of_war") as FogManager
	var fog_before: Array = fog.fog_grid.duplicate(true)
	match_scene.call("_select_town_center")
	_expect(camera.zoom == chosen_zoom, prefix + " Home preserves manual zoom")
	map.call("_apply_camera_profile", Vector2(phone_size), true)
	_expect(camera.zoom == chosen_zoom, prefix + " resize preserves manual zoom")
	_expect(fog.fog_grid == fog_before, prefix + " Home does not change fog visibility")
	_expect((map.get("selection_mgr") as SelectionManager).selected == [tc], prefix + " Home still selects its production building")
	if seed_value == 101:
		for step: int in 20:
			map.call("zoom_in")
		map.call("_update_camera_zoom", 0.2)
		var detail_zoom: Vector2 = camera.zoom
		match_scene.call("_select_town_center")
		camera.reset_smoothing()
		camera.force_update_scroll()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(is_equal_approx(detail_zoom.x, 2.2) and camera.zoom == detail_zoom, prefix + " Home preserves maximum deliberate detail zoom")
		_check_accessible(hud, tc, null, null, Rect2(Vector2.ZERO, Vector2(phone_size)), prefix + " Home at2.2", true)
		if _render:
			await RenderingServer.frame_post_draw
			phone.get_texture().get_image().save_png("%s/%dx%d-seed101-home-detail%s.png" % [_output, phone_size.x, phone_size.y, "-guided" if guided else ""])
	if _render and seed_value == 424242 and not guided:
		map.call("show_overview")
		await RenderingServer.frame_post_draw
		phone.get_texture().get_image().save_png("%s/%dx%d-seed424242-base-overview.png" % [_output, phone_size.x, phone_size.y])
	phone.free()
	await get_tree().process_frame


func _find_accessible_worker(hud: CanvasLayer, workers: Array, tc: BuildingBase, safe_area: Rect2) -> UnitBase:
	var field := Rect2(safe_area.position + Vector2(8.0, 48.0), safe_area.size - Vector2(16.0, 128.0))
	for candidate: UnitBase in workers:
		if not candidate is Villager or candidate.current_state == UnitBase.State.DEAD or candidate.global_position.distance_to(tc.global_position) > 256.0:
			continue
		var art: Rect2 = _projected_visual_bounds(candidate)
		if not field.encloses(art):
			continue
		var clear: bool = true
		for panel_name: String in ["_sacred_site_panel", "_progression_hint_panel", "_camera_controls", "_minimap_frame", "_minimap_hint_label", "_town_center_button", "build_menu_button"]:
			var overlay: Control = hud.get(panel_name) as Control
			if overlay != null and overlay.is_visible_in_tree() and art.intersects(overlay.get_global_rect().grow(3.0)):
				clear = false
		if clear:
			return candidate
	_expect(false, "a living local worker remains accessible beside the TC")
	return null


func _check_accessible(hud: CanvasLayer, tc: Node2D, worker: Node2D, food: Node2D, safe_area: Rect2, prefix: String, body_only: bool = false) -> void:
	var top: float = (hud.get_node("Root/TopBar") as Control).get_global_rect().end.y + 8.0
	var field := Rect2(Vector2(safe_area.position.x + 8.0, top), Vector2(safe_area.size.x - 16.0, safe_area.end.y - 80.0 - top))
	for subject: Node2D in [tc, worker, food]:
		if subject == null:
			continue
		var projected: Rect2 = _projected_visual_bounds(subject, not body_only, not body_only)
		_expect(field.grow(0.5).encloses(projected), "%s %s art/marker bounds %s leave field %s" % [prefix, subject.name, projected, field])
		for panel_name: String in ["_sacred_site_panel", "_progression_hint_panel", "_camera_controls", "_minimap_frame", "_minimap_hint_label", "_town_center_button", "build_menu_button"]:
			var overlay: Control = hud.get(panel_name) as Control
			if overlay != null and overlay.is_visible_in_tree():
				var obstacle: Rect2 = overlay.get_global_rect().grow(3.0)
				var art: Rect2 = _projected_visual_bounds(subject, false, not body_only)
				if body_only:
					# At 2.2 on a short Guide phone, an entire roof cannot fit beside
					# the wide guidance card. Ground access and the body take priority.
					var ground: Rect2 = subject.get_global_transform_with_canvas() * Rect2(-14.0, -14.0, 28.0, 28.0)
					_expect(not ground.intersects(obstacle), prefix + " selected TC ground remains accessible")
					_expect(art.intersection(obstacle).get_area() <= art.get_area() * 0.15, prefix + " selected TC body remains substantially visible")
				else:
					_expect(not art.intersects(obstacle), "%s %s art is covered by %s" % [prefix, subject.name, panel_name])


func _projected_visual_bounds(subject: Node2D, include_ground: bool = true, include_flag: bool = true) -> Rect2:
	var ground := Rect2(-14.0, -14.0, 28.0, 28.0)
	if subject is BuildingBase and include_ground and (subject as BuildingBase).is_selected:
		var footprint: Vector2i = (subject as BuildingBase).footprint
		var size := Vector2(footprint.x * MapData.TILE_WIDTH, footprint.y * MapData.TILE_HEIGHT)
		ground = Rect2(-size * 0.5, size)
	elif subject is ResourceNode:
		ground = Rect2(-20.0, -34.0, 40.0, 54.0)
	var projected: Rect2 = subject.get_global_transform_with_canvas() * ground
	if include_flag and subject is BuildingBase and (subject as BuildingBase).building_type == BuildingData.BuildingType.TOWN_CENTER:
		# Include the procedural pole stroke and flag independently of the sprite.
		projected = projected.merge(subject.get_global_transform_with_canvas() * Rect2(47.0, -79.0, 26.0, 45.0))
	for child: Node in subject.get_children():
		if child is Sprite2D:
			var sprite: Sprite2D = child as Sprite2D
			if sprite.texture != null:
				var art: Rect2i = sprite.texture.get_image().get_used_rect()
				projected = projected.merge(sprite.get_global_transform_with_canvas() * Rect2(sprite.get_rect().position + Vector2(art.position), Vector2(art.size)))
	return projected


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
