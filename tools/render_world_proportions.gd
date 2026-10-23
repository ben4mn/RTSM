extends Node
## Synthetic free-object visual fixture. Real Main spawns, sprites and anchors;
## flat revealed terrain and stopped simulation, with no economy/balance claim.

const VIEWS: Array[String] = ["units", "town-house", "barracks-range", "stable-farm", "camp-workshop", "smith-tower", "resources", "settlement"]
const PROFILES: Array[Dictionary] = [
	{"size": Vector2i(844, 390), "zooms": [0.90, 0.65]},
	{"size": Vector2i(1280, 720), "zooms": [1.0, 0.65]},
]
var _output: String = "res://output/polish-2026-10-22/proportions/rendered"
var _only_view: String = ""
var _show_hud: bool = false
var _main: Node2D
var _map: Node2D
var _camera: Camera2D
var _viewport: SubViewport
var _presentation: TextureRect
var _references: Node2D
var _caption: Label
var _actors: Array[Dictionary] = []
var _captures: Array[Dictionary] = []
var _failures: Array[String] = []
var _had_preferences: bool
var _preferences_before: PackedByteArray
var _source_before: Dictionary
var _center: Vector2

class GroundReferences extends Node2D:
	var cells: Array[PackedVector2Array] = []
	var anchors: Array[Vector2] = []
	func _draw() -> void:
		for cell: PackedVector2Array in cells:
			draw_colored_polygon(cell, Color(0.2, 0.8, 0.8, 0.10))
			var closed: PackedVector2Array = cell.duplicate()
			closed.append(cell[0])
			draw_polyline(closed, Color(0.18, 0.55, 0.56, 0.85), 1.0, true)
		for anchor: Vector2 in anchors:
			draw_line(anchor - Vector2(5, 0), anchor + Vector2(5, 0), Color(1.0, 0.75, 0.2), 1.5)
			draw_line(anchor - Vector2(0, 5), anchor + Vector2(0, 5), Color(1.0, 0.75, 0.2), 1.5)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): _output = argument.trim_prefix("--output=")
		elif argument.begins_with("--view="): _only_view = argument.trim_prefix("--view=")
		elif argument == "--show-hud": _show_hud = true
	_had_preferences = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_preferences:
		_preferences_before = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	_source_before = _source_hashes()
	GameManager.audio_enabled = false
	AudioManager.set_all_enabled(false)
	GameManager.ui_scale = 1.0
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_population_limit = 40
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(844, 390)
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
	_expect(_main.get("_building_placement") != null, "actual Main initialization")
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
	_main.get_node("HUD").visible = _show_hud
	var overlay := CanvasLayer.new()
	overlay.layer = 110
	_viewport.add_child(overlay)
	_caption = Label.new()
	_caption.position = Vector2(12, 8)
	_caption.add_theme_font_override("font", KingdomTheme.FONT_MEDIUM)
	_caption.add_theme_font_size_override("font_size", 12)
	_caption.add_theme_color_override("font_color", KingdomTheme.INK)
	_caption.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.7))
	_caption.add_theme_constant_override("shadow_offset_x", 1)
	_caption.add_theme_constant_override("shadow_offset_y", 1)
	overlay.add_child(_caption)
	# Let Main's deferred opening assignments settle before removing fixtures.
	await get_tree().process_frame
	await get_tree().process_frame
	for view: String in VIEWS:
		if not _only_view.is_empty() and view != _only_view:
			continue
		_reset_field()
		_build_view(view)
		for profile: Dictionary in PROFILES:
			var pixels: Vector2i = profile.size
			_viewport.size = pixels
			get_window().size = pixels
			_presentation.size = Vector2(pixels)
			for zoom_value: float in profile.zooms:
				_map.call("note_camera_interaction")
				_map.set("_user_zoom_override", true)
				_camera.position = _center + Vector2(0, -16)
				_camera.zoom = Vector2.ONE * zoom_value
				_camera.reset_smoothing()
				_camera.force_update_scroll()
				for frame: int in 5:
					await get_tree().process_frame
				for show_references: bool in [false, true]:
					_references.visible = show_references
					_caption.text = "%s  |  %dx%d  |  %.2fx  |  %s\nSynthetic Main scene; free objects, flat ground, no economy/performance claim" % [view, pixels.x, pixels.y, zoom_value, "tile footprints + ground anchors" if show_references else "production artwork"]
					await _capture(view, pixels, zoom_value, show_references)
	_finish()


func _reset_field() -> void:
	if is_instance_valid(_references):
		_references.free()
	_actors.clear()
	for group: String in ["UnitsContainer", "BuildingsContainer", "ResourcesContainer", "SacredSiteContainer"]:
		for child: Node in _map.get_node(group).get_children():
			child.free()
	_map.resource_nodes.clear()
	for owner: int in 2:
		_main.get("_player_units")[owner].clear()
		_main.get("_player_buildings")[owner].clear()
		GameManager.players[owner]["population"] = 0
		GameManager.increase_population_cap(owner, 40)
	for y: int in MapData.MAP_HEIGHT:
		for x: int in MapData.MAP_WIDTH:
			_map.map_generator.grid[y][x] = MapData.TileType.GRASS
	_map.call("_build_terrain")
	_map.pathfinding = Pathfinding.new(_map.map_generator)
	var fog: FogManager = _map.fog_of_war
	fog.set_process(false)
	for y: int in MapData.MAP_HEIGHT:
		for x: int in MapData.MAP_WIDTH:
			fog.fog_grid[y][x] = MapData.FogState.VISIBLE
	fog.set("_initial_apply_done", false)
	fog.call("_apply_fog_delta")
	_center = _map.tile_to_world(Vector2i(36, 36))
	_references = GroundReferences.new()
	_references.z_index = 90
	_map.add_child(_references)


func _build_view(view: String) -> void:
	if view == "units":
		for owner: int in 2:
			for role: int in UnitData.UNITS:
				_unit(role, owner, _center + Vector2((float(role) - 2.5) * 100.0, -55.0 + owner * 120.0), true)
	elif view == "resources":
		var kinds: Array[String] = ["food", "wood", "gold"]
		for index: int in kinds.size():
			var position: Vector2 = _center + Vector2((index - 1) * 200.0, 0)
			_resource(kinds[index], _map.world_to_tile(position), true)
			_unit(UnitData.UnitType.VILLAGER, 0, position + Vector2(43, 28), false)
	elif view == "settlement":
		_building(BuildingData.BuildingType.TOWN_CENTER, Vector2i(35, 35), false)
		_building(BuildingData.BuildingType.HOUSE, Vector2i(31, 38), false)
		_building(BuildingData.BuildingType.FARM, Vector2i(39, 37), false)
		_building(BuildingData.BuildingType.BARRACKS, Vector2i(39, 31), false)
		_building(BuildingData.BuildingType.RESOURCE_CAMP, Vector2i(31, 33), false)
		_building(BuildingData.BuildingType.STABLE, Vector2i(34, 29), false)
		for tile: Vector2i in [Vector2i(29, 38), Vector2i(29, 39), Vector2i(30, 40)]:
			_resource("wood", tile, false)
		_resource("food", Vector2i(42, 41), false)
		_resource("gold", Vector2i(44, 36), false)
		for role: int in UnitData.UNITS:
			_unit(role, 0, _map.tile_to_world(Vector2i(36 + role % 3, 40 + role / 3)), false)
	else:
		var pairs: Dictionary = {
			"town-house": [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.HOUSE],
			"barracks-range": [BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.ARCHERY_RANGE],
			"stable-farm": [BuildingData.BuildingType.STABLE, BuildingData.BuildingType.FARM],
			"camp-workshop": [BuildingData.BuildingType.RESOURCE_CAMP, BuildingData.BuildingType.SIEGE_WORKSHOP],
			"smith-tower": [BuildingData.BuildingType.BLACKSMITH, BuildingData.BuildingType.WATCH_TOWER],
		}
		for index: int in 2:
			var tile := Vector2i(36, 36) + (Vector2i(-3, 3) if index == 0 else Vector2i(3, -3))
			var building: BuildingBase = _building(int(pairs[view][index]), tile, true)
			if building != null:
				_unit(UnitData.UnitType.VILLAGER, 0, _map.tile_to_world(tile + Vector2i(building.footprint.x, building.footprint.y - 1)), false)
				_unit(UnitData.UnitType.CAVALRY, 0, _map.tile_to_world(tile + Vector2i(building.footprint.x - 1, building.footprint.y + 1)), false)
	_references.queue_redraw()


func _unit(role: int, owner: int, position: Vector2, label: bool) -> UnitBase:
	var unit: UnitBase = _main.call("_spawn_unit", role, owner, position)
	_expect(unit != null, "spawn actual unit " + UnitData.get_unit_name(role))
	if unit == null: return null
	unit.command_stop()
	unit.set_process(false)
	unit.set_physics_process(false)
	unit.visible = true
	_record_actor(UnitData.get_unit_name(role), unit, unit.get("_sprite"), "unit", role, owner)
	if label: _reference_label(UnitData.get_unit_name(role) + (" · P1" if owner == 0 else " · P2"), position + Vector2(-46, 15), 92)
	return unit


func _building(kind: int, tile: Vector2i, label: bool) -> BuildingBase:
	var building: BuildingBase = _main.call("_spawn_building", kind, 0, tile)
	_expect(building != null, "spawn actual building " + BuildingData.get_building_name(kind))
	if building == null: return null
	building.complete_instantly()
	building.set_process(false)
	building.set_physics_process(false)
	_record_actor(BuildingData.get_building_name(kind), building, building.get_node("BuildingSprite"), "building", kind, 0)
	for y: int in building.footprint.y:
		for x: int in building.footprint.x:
			var cell := tile + Vector2i(x, y)
			_expect(not _map.pathfinding.is_walkable(cell), "blocked canonical building tile " + str(cell))
			_references.cells.append(_cell_polygon(cell))
	if label: _reference_label(BuildingData.get_building_name(kind), building.global_position + Vector2(-100, -110), 200)
	return building


func _resource(kind: String, tile: Vector2i, label: bool) -> void:
	var node: ResourceNode = load("res://scenes/map/resource_node.tscn").instantiate()
	node.resource_type = kind
	node.tile_position = tile
	node.total_amount = {"food": 200, "wood": 250, "gold": 400}[kind]
	node.position = _map.tile_to_world(tile)
	_map.get_node("ResourcesContainer").add_child(node)
	node.set_process(false)
	_record_actor(kind.capitalize(), node, node.get_node("Sprite"), "resource", -1, -1)
	_references.cells.append(_cell_polygon(tile))
	if label: _reference_label(kind.capitalize(), node.position + Vector2(-50, -90), 100)


func _record_actor(title: String, node: Node2D, sprite: Sprite2D, kind: String, type: int, owner: int) -> void:
	_expect(sprite != null and sprite.texture != null, "production artwork exists for " + title)
	if sprite == null or sprite.texture == null:
		return
	_actors.append({"title": title, "node": node, "sprite": sprite, "kind": kind, "type": type, "owner": owner})
	_references.anchors.append(node.global_position)


func _cell_polygon(tile: Vector2i) -> PackedVector2Array:
	var center: Vector2 = _map.tile_to_world(tile)
	var right: Vector2 = (_map.tile_to_world(tile + Vector2i.RIGHT) - center) * 0.5
	var down: Vector2 = (_map.tile_to_world(tile + Vector2i.DOWN) - center) * 0.5
	return PackedVector2Array([center - right - down, center + right - down, center + right + down, center - right + down])


func _reference_label(text: String, at: Vector2, width: float) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", KingdomTheme.FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", KingdomTheme.INK)
	_references.add_child(label)


func _capture(view: String, pixels: Vector2i, zoom_value: float, references: bool) -> void:
	await get_tree().process_frame
	var actors: Array[Dictionary] = []
	var canvas: Transform2D = _viewport.get_canvas_transform()
	for item: Dictionary in _actors:
		var sprite: Sprite2D = item.sprite
		var opaque: Rect2i = sprite.texture.get_image().get_used_rect()
		var local := Rect2(Vector2(opaque.position) - sprite.texture.get_size() * 0.5 + sprite.offset, Vector2(opaque.size))
		var world: Rect2 = sprite.global_transform * local
		var screen: Rect2 = canvas * world
		if view != "settlement":
			_expect(Rect2(Vector2.ZERO, Vector2(pixels)).encloses(screen), "%s %s %.2f cropped artwork: %s" % [view, item.title, zoom_value, screen])
		actors.append({"title": item.title, "kind": item.kind, "type": item.type, "owner": item.owner, "ground_world": _point(item.node.global_position), "ground_tile": _point(_map.world_to_tile(item.node.global_position)), "sprite_scale": _point(sprite.scale), "sprite_offset": _point(sprite.offset), "texture": sprite.texture.resource_path, "opaque_world": _rect(world), "opaque_screen": _rect(screen)})
	var filename: String = "%s-%dx%d-z%.2f-%s.png" % [view, pixels.x, pixels.y, zoom_value, "references" if references else "art"]
	var saved := false
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
		await RenderingServer.frame_post_draw
		saved = _viewport.get_texture().get_image().save_png(_output.path_join(filename)) == OK
		_expect(saved, "save native image " + filename)
	_captures.append({"view": view, "size": _point(pixels), "camera": _point(_camera.position), "zoom": zoom_value, "references": references, "filename": filename if saved else "", "actors": actors})


func _source_hashes() -> Dictionary:
	var result: Dictionary = {"project.godot": FileAccess.get_sha256("res://project.godot")}
	for folder: String in ["scripts", "scenes", "assets"]:
		_hash_directory(folder, result)
	for path: String in ["tools/render_world_proportions.gd", "tools/render_world_proportions.tscn"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result


func _hash_directory(folder: String, hashes: Dictionary) -> void:
	for name: String in DirAccess.get_files_at("res://" + folder):
		if name.ends_with(".uid"):
			continue
		var path: String = folder.path_join(name)
		hashes[path] = FileAccess.get_sha256("res://" + path)
	for child: String in DirAccess.get_directories_at("res://" + folder):
		_hash_directory(folder.path_join(child), hashes)


func _point(value: Variant) -> Array:
	return [value.x, value.y]


func _rect(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	_expect(_captures.size() == (64 if _only_view.is_empty() else 8), "all requested geometry/capture records complete")
	var unchanged: bool = _source_before == _source_hashes()
	_expect(unchanged, "source inputs remain unchanged during capture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	FileAccess.open(_output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Synthetic free objects spawned by actual Main, production sprites/scales/anchors; stopped simulation, flat revealed ground. HUD hidden by default solely for world inspection; references are a separate overlay. No paid economy, balance, movement or performance claim.", "engine": Engine.get_version_info(), "display": DisplayServer.get_name(), "user_data": OS.get_user_data_dir(), "hud_visible": _show_hud, "source_unchanged": unchanged, "source_sha256": _source_before, "captures": _captures, "failures": _failures}, "\t") + "\n")
	if is_instance_valid(_viewport): _viewport.free()
	if _had_preferences:
		FileAccess.open(GameManager.PREFERENCES_PATH, FileAccess.WRITE).store_buffer(_preferences_before)
	else:
		DirAccess.remove_absolute(GameManager.PREFERENCES_PATH)
	for failure: String in _failures:
		push_error("[FAIL] world_proportions: " + failure)
	if _failures.is_empty():
		print("[PASS] world_proportions: %d views/profiles, actual Main sprites and canonical building cells; native images only when rendered" % _captures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
