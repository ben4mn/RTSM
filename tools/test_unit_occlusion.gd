extends Node
## Real world/actors/art, with staged positions solely for occlusion checks.

var _failures: Array[String] = []
var _output: String = ""
var _main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): _output = argument.trim_prefix("--output=")
	if not _output.is_empty(): DirAccess.make_dir_recursive_absolute(_output)
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_population_limit = 40
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	for civilization: int in CivilizationData.ORDERED_IDS:
		GameManager.selected_civilization = civilization
		GameManager.selected_opponent_civilization = civilization
		GameManager.set_state(GameManager.GameState.MENU)
		_main = load("res://scenes/main/main.tscn").instantiate()
		add_child(_main)
		for frame: int in 900:
			if _main.get("_building_placement") != null: break
			await get_tree().process_frame
		_expect(_main.get("_building_placement") != null, "main initialized")
		if _main.get("_building_placement") == null: break
		_main.ai_controller.set_process(false)
		_main.ai_controller.get("_decision_timer").stop()
		_main.set_process(false) # Freeze staged positions/vision while rendering evidence.
		var map: Node2D = _main.game_map
		var overlay: Node = map.get_node("UnitOcclusionOverlay")
		if DisplayServer.get_name() == "headless":
			_expect(not overlay.is_processing() and overlay.get("_entries").is_empty(), "authority skips all presentation scans")
		overlay.set("allow_headless_fixture", true)
		overlay.set_process(false)
		var fog: Node = map.fog_of_war
		fog.set_process(false)
		fog.reveal_all()
		fog.set("_initial_apply_done", false)
		fog.call("_apply_fog_delta")
		for node: Node in get_tree().get_nodes_in_group("units"): node.set_process(false)
		var unit: UnitBase = _main.get("_player_units")[0][0]
		var tc: BuildingBase = _main.get("_player_buildings")[0][0]
		unit.position = tc.get("_sprite").global_position + Vector2(0, -8)
		map.note_camera_interaction()
		map.set("_user_zoom_override", true)
		map.camera.position = tc.global_position
		map.camera.zoom = Vector2(1.3, 1.3)
		map.camera.reset_smoothing()
		map.camera.force_update_scroll()
		await get_tree().process_frame
		overlay.call("_process", 0.11)
		_expect(_echo_visible(unit), "building overlap " + str(civilization))
		await _shot("civ%d-building" % civilization)
		var tree: Node2D
		var distance: float = INF
		for resource: Node2D in map.resource_nodes.values():
			if resource.resource_type == "wood" and resource.global_position.distance_to(tc.global_position) < distance:
				tree = resource
				distance = resource.global_position.distance_to(tc.global_position)
		tree.visible = true
		unit.position = tree.global_position + Vector2(0, -5)
		map.camera.position = tree.global_position
		map.camera.reset_smoothing()
		map.camera.force_update_scroll()
		await get_tree().process_frame
		overlay.call("_process", 0.11)
		_expect(_echo_visible(unit), "tree overlap " + str(civilization))
		await _shot("civ%d-tree" % civilization)
		var center: Vector2 = map.tile_to_world(Vector2i(36, 36))
		unit.position = center
		GameManager.grant_population_cap(1, 94001, 40)
		var front: UnitBase = _main.call("_spawn_unit", UnitData.UnitType.CAVALRY, 1, center + Vector2(0, 6))
		front.set_process(false)
		front.visible = true
		map.camera.position = center
		map.camera.reset_smoothing()
		map.camera.force_update_scroll()
		await get_tree().process_frame
		overlay.call("_process", 0.11)
		_expect(_echo_visible(unit), "other owner unit overlap " + str(civilization))
		# Swap front/back to prove currently visible enemy units receive the same
		# treatment, independent of selection, ownership and civilization.
		front.position = center + Vector2(0, -4)
		unit.position = center + Vector2(0, 8)
		overlay.call("_process", 0.11)
		_expect(_echo_visible(front), "revealed enemy silhouette " + str(civilization))
		await _shot("civ%d-units" % civilization)
		var echo: Sprite2D = front.get_node_or_null("OccludedUnitEcho")
		if echo == null:
			_failures.append("missing enemy echo; remaining gating checks skipped for civ" + str(civilization))
			_main.queue_free()
			await get_tree().process_frame
			continue
		_expect(echo.z_index < map.get_node("FogLayer").z_index and not echo.z_as_relative, "echo remains below fog")
		_expect(not front.is_selected, "echo never selects enemy")
		var tile: Vector2i = map.world_to_tile(front.global_position)
		for fog_state: int in [MapData.FogState.EXPLORED, MapData.FogState.UNEXPLORED]:
			fog.fog_grid[tile.y][tile.x] = fog_state
			# Don't refresh overlap: the immediate per-frame gate must be enough.
			overlay.call("_process", 0.0)
			_expect(not echo.visible, "no stale fog echo state=" + str(fog_state))
		fog.fog_grid[tile.y][tile.x] = MapData.FogState.VISIBLE
		front.visible = false
		overlay.call("_process", 0.0)
		_expect(not echo.visible, "remote/ancestor-hidden unit does not echo")
		front.visible = true
		front.get("_sprite").visible = false
		overlay.call("_process", 0.0)
		_expect(not echo.visible, "hidden source sprite does not echo")
		front.get("_sprite").visible = true
		front.current_state = UnitBase.State.DEAD
		overlay.call("_process", 0.0)
		_expect(not echo.visible, "dead unit does not echo")
		front.current_state = UnitBase.State.IDLE
		front.position = center + Vector2(300, 0)
		overlay.call("_process", 0.11)
		_expect(not _echo_visible(front), "unoccluded unit has no echo")
		var source: Sprite2D = unit.get("_sprite")
		var empty := Sprite2D.new()
		var empty_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		empty.texture = ImageTexture.create_from_image(empty_image)
		map.add_child(empty)
		empty.position = unit.position
		_expect(not overlay.call("_opaque_overlap", source, empty), "transparent texture padding is not an occluder")
		empty.free()
		front.queue_free()
		await get_tree().process_frame
		overlay.call("_process", 0.11)
		_main.queue_free()
		await get_tree().process_frame
	if _failures.is_empty(): print("[PASS] unit_occlusion: three civilizations, building/tree/unit opaque overlap, both owners, no selection change, below fog, immediate explored/unexplored/hidden/dead gating, transparent padding and removal")
	else:
		for failure: String in _failures: push_error("[FAIL] unit_occlusion: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _echo_visible(unit: UnitBase) -> bool:
	var echo: Sprite2D = unit.get_node_or_null("OccludedUnitEcho")
	return echo != null and echo.visible


func _shot(name: String) -> void:
	if _output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_output.path_join(name + ".png"))


func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)
