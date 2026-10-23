extends Node
## Native diagnostic using actual Main and HUD with the ordinary seeded map/fog.
## Preview-only synthetic setup: no purchase, terrain edits or revealed-map cheat.

const PROFILES: Array[Vector2i] = [Vector2i(844, 390), Vector2i(932, 430), Vector2i(1280, 720)]
var _output := "res://output/polish-2026-10-22/placement-grid/rendered"
var _main: Node2D
var _map: Node2D
var _camera: Camera2D
var _placement: BuildingPlacement
var _hud: Node
var _viewport: SubViewport
var _presentation: TextureRect
var _clear_origin := Vector2i(-1, -1)
var _blocked_origin := Vector2i(-1, -1)
var _captures: Array[Dictionary] = []
var _failures: Array[String] = []
var _previous: Dictionary = {}
var _had_preferences: bool
var _preferences_before: PackedByteArray
var _source_hashes: Dictionary = {}
var _wood_before: int
var _building_count_before: int

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	for property: String in ["selected_map_seed", "selected_map_archetype", "selected_population_limit", "selected_difficulty", "selected_match_mode", "guided_opening_enabled", "ui_scale", "audio_enabled"]:
		_previous[property] = GameManager.get(property)
	_had_preferences = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_preferences:
		_preferences_before = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	for path: String in ["scripts/buildings/building_placement.gd", "scripts/buildings/building_base.gd", "scripts/map/game_map.gd", "scripts/managers/fog_manager.gd", "scripts/main/main.gd", "scripts/ui/hud.gd", "tools/render_placement_grid.gd", "assets/buildings/company_house.svg.import", "assets/buildings/farm.svg.import", "assets/buildings/company_barracks.svg.import"]:
		_source_hashes[path] = FileAccess.get_sha256("res://" + path)
	AudioManager.set_all_enabled(false)
	GameManager.audio_enabled = false
	GameManager.ui_scale = 1.0
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_population_limit = 30
	GameManager.selected_difficulty = AIController.Difficulty.EASY
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.set_state(GameManager.GameState.MENU)
	_viewport = SubViewport.new()
	_viewport.size = PROFILES[0]
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_presentation = TextureRect.new()
	_presentation.texture = _viewport.get_texture()
	_presentation.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_presentation)
	_main = load("res://scenes/main/main.tscn").instantiate()
	_viewport.add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_expect(_main.get("_building_placement") != null, "actual Main initializes")
	if _main.get("_building_placement") == null:
		_finish()
		return
	await _frames(3)
	_main.set_process(false)
	_main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	(_main.get_node("AIController").get("_decision_timer") as Timer).stop()
	_main.get_node("StrategyController").set_process(false)
	_map = _main.get_node("GameMap")
	_map.set_process(false)
	_camera = _map.get("camera")
	_camera.position_smoothing_enabled = false
	_placement = _main.get("_building_placement")
	_hud = _main.get_node("HUD")
	var selected_worker: Villager
	for side: Array in _main.get("_player_units"):
		for unit: UnitBase in side:
			unit.command_stop()
			unit.set_process(false)
			unit.set_physics_process(false)
			if selected_worker == null and unit is Villager and unit.player_owner == 0:
				selected_worker = unit as Villager
	for side: Array in _main.get("_player_buildings"):
		for building: BuildingBase in side:
			building.set_process(false)
	_main.call("_update_fog_of_war")
	_main.call("_update_fog_entity_visibility")
	(_map.get("fog_of_war") as FogManager).set_process(false)
	_map.selection_mgr.select_single(selected_worker)
	_clear_origin = _find_clear_origin()
	_blocked_origin = _find_visible_blocked_origin()
	_expect(_clear_origin.x >= 0, "ordinary starting vision contains a legal 3×3 preview")
	_expect(_blocked_origin.x >= 0, "ordinary starting vision contains visible blocked terrain")
	_wood_before = ResourceManager.get_resource(0, "wood")
	_building_count_before = (_main.get("_player_buildings")[0] as Array).size()
	if _clear_origin.x < 0 or _blocked_origin.x < 0:
		_finish()
		return
	for pixels: Vector2i in PROFILES:
		_viewport.size = pixels
		get_window().size = pixels
		get_window().content_scale_size = pixels
		_presentation.size = Vector2(pixels)
		await _frames(4)
		var touch: bool = pixels.y < 500
		_set_input_profile(touch)
		await _show("01-house-valid", pixels, BuildingData.BuildingType.HOUSE, _clear_origin, 0.95, Vector2.ZERO, true)
		await _show("02-farm-valid", pixels, BuildingData.BuildingType.FARM, _clear_origin, 0.95, Vector2.ZERO, true)
		await _show("03-barracks-valid", pixels, BuildingData.BuildingType.BARRACKS, _clear_origin, 0.95, Vector2.ZERO, true)
		await _show("04-house-blocked-terrain", pixels, BuildingData.BuildingType.HOUSE, _blocked_origin, 0.95, Vector2.ZERO, false)
		await _show("05-barracks-pan-zoom", pixels, BuildingData.BuildingType.BARRACKS, _clear_origin, 0.70, Vector2(110, -20), true)
		_main.call("_cancel_placement")
		await _frames(3)
		var grid: Node2D = _placement.get_node("PlacementGrid")
		_expect(not grid.is_visible_in_tree() and not _hud.get("_placement_mode_active"), "Cancel removes grid and actual placement HUD")
		await _capture("06-cancel-grid-gone", pixels)
	_expect(ResourceManager.get_resource(0, "wood") == _wood_before and (_main.get("_player_buildings")[0] as Array).size() == _building_count_before, "preview diagnostic neither pays nor creates a building")
	_finish()

func _find_clear_origin() -> Vector2i:
	var spawn: Vector2i = _map.map_generator.spawn_positions[0]
	var desired: Vector2i = spawn + Vector2i(4, 4)
	for radius: int in range(12):
		for dx: int in range(-radius, radius + 1):
			for dy: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile: Vector2i = desired + Vector2i(dx, dy)
				if _placement.revalidate_confirmation(BuildingData.BuildingType.BARRACKS, _map.tile_to_world(tile), 0):
					return tile
	return Vector2i(-1, -1)

func _find_visible_blocked_origin() -> Vector2i:
	var nearest := Vector2i(-1, -1)
	var nearest_distance: float = INF
	for tile: Vector2i in _map.resource_nodes:
		if not _all_visible(tile, Vector2i(2, 2)):
			continue
		var world: Vector2 = _map.tile_to_world(tile)
		if _placement.revalidate_confirmation(BuildingData.BuildingType.HOUSE, world, 0) or _placement.get_invalid_reason() != "Blocked terrain":
			continue
		var distance: float = world.distance_squared_to(_map.tile_to_world(_clear_origin))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = tile
	return nearest

func _all_visible(origin: Vector2i, size: Vector2i) -> bool:
	for dx: int in size.x:
		for dy: int in size.y:
			if not _map.is_tile_visible_to_player(origin + Vector2i(dx, dy), 0):
				return false
	return true

func _set_input_profile(touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.pressed = true
		_placement.call("_observe_input_mode", event)
	else:
		var event := InputEventMouseMotion.new()
		event.relative = Vector2.ONE
		_placement.call("_observe_input_mode", event)

func _show(label: String, pixels: Vector2i, kind: int, tile: Vector2i, zoom: float, pan: Vector2, valid: bool) -> void:
	_main.call("_cancel_placement")
	_main.call("_on_building_selected_for_placement", kind)
	_placement.update_preview_at_world(_map.tile_to_world(tile))
	_map.call("note_camera_interaction")
	_map.set("_user_zoom_override", true)
	_camera.position = _map.tile_to_world(tile) + BuildingBase.get_footprint_center_offset(_placement.current_footprint, _map) + Vector2(0, -24) + pan
	_camera.zoom = Vector2.ONE * zoom
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	await _frames(5)
	_placement.call("_refresh_placement_grid", true)
	_expect(_placement.is_valid_placement == valid, label + " uses actual expected placement validity")
	_expect((_hud.get("_placement_status_panel") as Control).is_visible_in_tree(), label + " retains actual HUD placement status")
	_expect((_hud.get("_placement_cancel_button") as Control).is_visible_in_tree(), label + " retains actual Cancel control")
	if pixels.y < 500:
		_expect((_hud.get("_placement_confirm_button") as Control).is_visible_in_tree(), label + " retains actual touch Place control")
	if not valid:
		_expect(_placement.get_invalid_reason() == "Blocked terrain" and not (_placement.get("_invalid_tiles") as Array).is_empty(), "visible blocked preview marks real invalid cells")
	await _capture(label, pixels)

func _capture(label: String, pixels: Vector2i) -> void:
	var grid: Node2D = _placement.get_node("PlacementGrid")
	var fog_counts := {"unexplored": 0, "explored": 0, "visible": 0}
	for row: Array in _map.fog_of_war.fog_grid:
		for state: int in row:
			var key: String = ["unexplored", "explored", "visible"][state]
			fog_counts[key] += 1
	_expect(int(fog_counts.unexplored) > 0 and int(fog_counts.visible) > 0, "ordinary fog is preserved")
	var filename: String = "%dx%d-%s.png" % [pixels.x, pixels.y, label]
	var saved := false
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
		await RenderingServer.frame_post_draw
		saved = _viewport.get_texture().get_image().save_png(_output.path_join(filename)) == OK
		_expect(saved, "save native capture " + filename)
	var invalid_cells: Array = []
	for tile: Vector2i in _placement.get("_invalid_tiles"):
		invalid_cells.append([tile.x, tile.y])
	_captures.append({"state":label, "size":[pixels.x, pixels.y], "filename":filename if saved else "", "active":_placement.active, "valid":_placement.is_valid_placement, "reason":_placement.get_invalid_reason() if _placement.active and not _placement.is_valid_placement else "", "invalid_cells":invalid_cells, "grid_visible":grid.is_visible_in_tree(), "grid_lines":(grid.get("segments") as PackedVector2Array).size() / 2, "grid_screen_width":float(grid.get("line_width")) * _placement.get_canvas_transform().x.length(), "camera":[_camera.position.x,_camera.position.y], "zoom":_camera.zoom.x, "fog_counts":fog_counts})

func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if is_instance_valid(_viewport):
		_viewport.free()
	for property: String in _previous:
		GameManager.set(property, _previous[property])
	GameManager.set_state(GameManager.GameState.MENU)
	var preferences_unchanged: bool = FileAccess.file_exists(GameManager.PREFERENCES_PATH) == _had_preferences
	if _had_preferences:
		preferences_unchanged = preferences_unchanged and FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH) == _preferences_before
	_expect(preferences_unchanged, "diagnostic leaves saved preferences untouched")
	_expect(_captures.size() == 18, "all 18 requested native states complete")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	FileAccess.open(_output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope":"Synthetic preview-only actual Main/HUD diagnostic; ordinary seeded terrain and fog, stopped actors. No paid placement, terrain edits, hidden-map reveal or performance claim.", "display":DisplayServer.get_name(), "source_sha256":_source_hashes, "preferences_unchanged":preferences_unchanged, "captures":_captures, "failures":_failures}, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] render_placement_grid: " + failure)
	if _failures.is_empty():
		print("[PASS] render_placement_grid: 18 actual Main/HUD placement states, ordinary fog, visible per-cell blockers, pan/zoom, Cancel; PNGs only on native renderer")
	get_tree().quit(0 if _failures.is_empty() else 1)
