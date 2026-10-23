extends "res://tools/render_world_proportions.gd"
## Diagnostic only: compare root-depth vs centered-art depth in the same real
## Main scene. No runtime production property is changed by this test file.

var _depth_records: Array[Dictionary] = []
var _geometry: Dictionary = {}
var _overlap_candidates: Array[Dictionary] = []
var _native_changed_probes: int = 0


func _run() -> void:
	_output = "res://output/polish-2026-10-22/proportions/depth-sort"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): _output = argument.trim_prefix("--output=")
	_had_preferences = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_preferences: _preferences_before = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	_source_before = _source_hashes()
	GameManager.audio_enabled = false
	AudioManager.set_all_enabled(false)
	GameManager.ui_scale = 1.0
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_population_limit = 40
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(844, 390)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_presentation = TextureRect.new()
	_presentation.texture = _viewport.get_texture()
	_presentation.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_presentation.size = Vector2(844, 390)
	add_child(_presentation)
	get_window().size = Vector2i(844, 390)
	_main = load("res://scenes/main/main.tscn").instantiate()
	_viewport.add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null: break
		await get_tree().process_frame
	_expect(_main.get("_building_placement") != null, "actual Main initializes")
	if _main.get("_building_placement") == null:
		_finish()
		return
	_main.set_process(false)
	_main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	_main.get_node("AIController").get("_decision_timer").stop()
	_main.get_node("StrategyController").set_process(false)
	_map = _main.get_node("GameMap")
	_map.set_process(false)
	_camera = _map.get("camera")
	_main.get_node("HUD").visible = false
	var overlay := CanvasLayer.new()
	overlay.layer = 110
	_viewport.add_child(overlay)
	_caption = Label.new()
	_caption.position = Vector2(12, 8)
	_caption.add_theme_font_size_override("font_size", 13)
	_caption.add_theme_color_override("font_color", KingdomTheme.INK)
	overlay.add_child(_caption)
	for frame: int in 3: await get_tree().process_frame
	for kind: int in [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.HOUSE]:
		_reset_field()
		var building: BuildingBase = _building(kind, Vector2i(36, 36), false)
		var n: float = building.footprint.x
		var right: Vector2 = _map.tile_to_world(Vector2i.RIGHT) - _map.tile_to_world(Vector2i.ZERO)
		var down: Vector2 = _map.tile_to_world(Vector2i.DOWN) - _map.tile_to_world(Vector2i.ZERO)
		# Two static, synthetic worker positions on every edge. Coordinates are
		# outside the occupied cell squares; no navigation/movement claim.
		var samples: Array[Vector2] = [Vector2(-0.7, 0.6), Vector2(-0.7, n - 0.6), Vector2(0.6, -0.7), Vector2(n - 0.6, -0.7), Vector2(n - 0.3, 0.6), Vector2(n - 0.3, n - 0.6), Vector2(0.6, n - 0.3), Vector2(n - 0.6, n - 0.3)]
		var workers: Array[UnitBase] = []
		for index: int in samples.size():
			var tile_offset: Vector2 = samples[index]
			var worker: UnitBase = _unit(UnitData.UnitType.VILLAGER, 0, building.global_position + right * tile_offset.x + down * tile_offset.y, false)
			workers.append(worker)
			_expect(not Rect2(-0.5, -0.5, n, n).has_point(tile_offset), "worker perimeter sample outside building cells")
		# The original outer-corner samples can miss the ink entirely. Sweep
		# upper edges every half tile and keep the strongest actual alpha overlap
		# while feet lie strictly between the root and the sprite's sort anchor.
		_overlap_candidates.clear()
		_choose_upper_overlap(building, workers[1], right, down, true)
		_choose_upper_overlap(building, workers[3], right, down, false)
		_geometry = _logical_geometry(building, workers)
		_map.call("note_camera_interaction")
		_map.set("_user_zoom_override", true)
		_camera.zoom = Vector2.ONE
		_camera.position = building.global_position + BuildingBase.get_footprint_center_offset(building.footprint, _map) + Vector2(0, -65)
		_camera.reset_smoothing()
		_camera.force_update_scroll()
		_references.visible = false
		for selected: bool in [false, true]:
			building.is_selected = selected
			building.hp = building.max_hp - 5 if selected else building.max_hp
			building.queue_redraw()
			var reference_image: Image = null
			for centered_sort: bool in [false, true]:
				building.y_sort_enabled = centered_sort
				_caption.text = "%s | Building Y-sort %s | %s\nSynthetic static perimeter workers; same logical positions, collision and camera" % [building.building_name, "ON (art center)" if centered_sort else "OFF (first tile)", "selected + damaged" if selected else "normal"]
				for frame: int in 3: await get_tree().process_frame
				_expect(_logical_geometry(building, workers) == _geometry, "sort toggle preserves every logical position, footprint and collision")
				var selection: SelectionManager = _map.get("selection_mgr")
				for worker: UnitBase in workers:
					_expect(selection.call("_get_node_at", worker.global_position, true) == worker, "worker feet retain deliberate selection priority")
				var image: Image = await _capture_depth(building, workers, centered_sort, selected)
				if image != null and centered_sort:
					var before: Dictionary = _depth_records[-2]
					var after: Dictionary = _depth_records[-1]
					var deltas: Array[int] = []
					for index: int in workers.size():
						var delta: int = int(before.worker_pixels[index].visible_difference_pixels) - int(after.worker_pixels[index].visible_difference_pixels)
						deltas.append(delta)
						if index in [1, 3] and delta > 0: _native_changed_probes += 1
					after["worker_visible_pixel_reduction"] = deltas
				if image != null and selected:
					if not centered_sort:
						reference_image = image
					else:
						var art: Rect2 = _sprite_screen_rect(building.get_node("BuildingSprite"))
						var feedback_strip := Rect2(art.position + Vector2(0, -30), Vector2(art.size.x, 29))
						var changed: int = _changed_pixels(reference_image, image, feedback_strip)
						_expect(changed == 0, "%s health/badges above roof unchanged by sort toggle (%d pixels)" % [building.building_name, changed])
	_finish()


func _capture_depth(building: BuildingBase, workers: Array[UnitBase], centered_sort: bool, selected: bool) -> Image:
	var filename: String = "%s-%s-%s" % [building.building_name.to_snake_case(), "center-sort" if centered_sort else "root-sort", "feedback" if selected else "normal"]
	var record := {"filename": filename, "building": building.building_name, "centered_sort": centered_sort, "selected_damaged": selected, "geometry": _geometry, "worker_pixels": [], "upper_edge_alpha_sweep": _overlap_candidates.duplicate(true), "building_root_y": building.global_position.y, "sprite_sort_y": building.get_node("BuildingSprite").global_position.y}
	var rendered: Image = null
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
		await RenderingServer.frame_post_draw
		rendered = _viewport.get_texture().get_image()
		_expect(rendered.save_png(_output.path_join(filename + ".png")) == OK, "save " + filename)
		for worker: UnitBase in workers: worker.visible = false
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var without_workers: Image = _viewport.get_texture().get_image()
		_expect(without_workers.save_png(_output.path_join(filename + "-no-workers.png")) == OK, "save workerless reference " + filename)
		for worker: UnitBase in workers:
			var rect: Rect2 = _sprite_screen_rect(worker.get("_sprite"))
			record.worker_pixels.append({"ground_y": worker.global_position.y, "screen_rect": _rect(rect), "visible_difference_pixels": _changed_pixels(rendered, without_workers, rect)})
			worker.visible = true
	_depth_records.append(record)
	return rendered


func _logical_geometry(building: BuildingBase, workers: Array[UnitBase]) -> Dictionary:
	var positions: Array = []
	for worker: UnitBase in workers: positions.append(_point(worker.global_position))
	var collision: CollisionShape2D = null
	for child: Node in building.get_children():
		if child is CollisionShape2D: collision = child
	_expect(collision != null, "real building collision exists")
	return {"building_position": _point(building.global_position), "tile": _point(_map.world_to_tile(building.global_position)), "footprint": _point(building.footprint), "collision_position": _point(collision.global_position), "collision_size": _point((collision.shape as RectangleShape2D).size), "workers": positions}


func _choose_upper_overlap(building: BuildingBase, worker: UnitBase, right: Vector2, down: Vector2, left_edge: bool) -> void:
	var art: Sprite2D = building.get_node("BuildingSprite")
	var person: Sprite2D = worker.get("_sprite")
	var best_position: Vector2 = worker.global_position
	var best_overlap: int = 0
	for half_tile: int in range(2, building.footprint.x * 2):
		var along: float = half_tile * 0.5
		var tile_offset := Vector2(-0.7, along) if left_edge else Vector2(along, -0.7)
		worker.global_position = building.global_position + right * tile_offset.x + down * tile_offset.y
		var within_depth_gap: bool = worker.global_position.y > building.global_position.y and worker.global_position.y < art.global_position.y
		var overlap: int = _opaque_world_overlap(person, art) if within_depth_gap else 0
		_overlap_candidates.append({"edge": "upper-left" if left_edge else "upper-right", "tile_offset": _point(tile_offset), "ground_y": worker.global_position.y, "between_depth_anchors": within_depth_gap, "opaque_world_pixel_overlap": overlap})
		if overlap > best_overlap:
			best_overlap = overlap
			best_position = worker.global_position
	worker.global_position = best_position
	if building.building_type == BuildingData.BuildingType.TOWN_CENTER:
		_expect(best_overlap > 20, "TC upper-edge probe contains substantial actual opaque overlap")


func _opaque_world_overlap(person: Sprite2D, art: Sprite2D) -> int:
	var ink: Rect2i = person.texture.get_image().get_used_rect()
	var area := Rect2i(person.global_transform * Rect2(person.get_rect().position + Vector2(ink.position), Vector2(ink.size)))
	var overlap: int = 0
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var world := Vector2(x + 0.5, y + 0.5)
			if person.is_pixel_opaque(person.to_local(world)) and art.is_pixel_opaque(art.to_local(world)):
				overlap += 1
	return overlap


func _sprite_screen_rect(sprite: Sprite2D) -> Rect2:
	var ink: Rect2i = sprite.texture.get_image().get_used_rect()
	return sprite.get_global_transform_with_canvas() * Rect2(sprite.get_rect().position + Vector2(ink.position), Vector2(ink.size))


func _changed_pixels(first: Image, second: Image, region: Rect2) -> int:
	var clipped: Rect2i = Rect2i(region).intersection(Rect2i(0, 0, first.get_width(), first.get_height()))
	var changed: int = 0
	for y: int in range(clipped.position.y, clipped.end.y):
		for x: int in range(clipped.position.x, clipped.end.x):
			if first.get_pixel(x, y) != second.get_pixel(x, y): changed += 1
	return changed


func _source_hashes() -> Dictionary:
	var result: Dictionary = super._source_hashes()
	for name: String in ["tools/test_building_depth_sort.gd", "tools/test_building_depth_sort.tscn"]:
		result[name] = FileAccess.get_sha256("res://" + name)
	return result


func _finish() -> void:
	_expect(_depth_records.size() == 12, "all three buildings, two feedback states and both sort modes recorded")
	if DisplayServer.get_name() != "headless":
		_expect(_native_changed_probes > 0, "native pixels prove at least one overlapping worker changes visibility across sort anchors")
	_expect(_source_before == _source_hashes(), "source unchanged during diagnostic")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	FileAccess.open(_output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Actual Main classes and renderer, synthetic free static objects. Only BuildingBase.y_sort_enabled toggles between each pair. Upper-edge half-tile alpha sweeps choose actual overlapping probes. Headless checks geometry/input only; native workerless pixel references measure visible worker differences, not movement or performance.", "display": DisplayServer.get_name(), "source_sha256": _source_before, "native_changed_probes": _native_changed_probes, "records": _depth_records, "failures": _failures}, "\t") + "\n")
	if is_instance_valid(_viewport): _viewport.free()
	if _had_preferences: FileAccess.open(GameManager.PREFERENCES_PATH, FileAccess.WRITE).store_buffer(_preferences_before)
	else: DirAccess.remove_absolute(GameManager.PREFERENCES_PATH)
	for failure: String in _failures: push_error("[FAIL] building_depth_sort: " + failure)
	if _failures.is_empty(): print("[PASS] building_depth_sort: 12 paired states, canonical geometry unchanged, worker feet selection preserved; native mode checks overhead feedback pixels")
	get_tree().quit(0 if _failures.is_empty() else 1)
