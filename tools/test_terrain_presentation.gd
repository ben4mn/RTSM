extends Node
## Actual Main/GameMap renders at phone size; revealed/stopped visual fixtures.

var _output: String = "res://output/terrain-20261022"
var _baseline: bool = false
var _failures: Array[String] = []
var _captures: Array[String] = []
var _maps: Array[Dictionary] = []
var _checks: int = 0
var _completed_maps: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		if argument == "--baseline":
			_baseline = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.ui_scale = 1.0
	if not _baseline:
		_test_atlas()
		if DisplayServer.get_name() != "headless":
			await _test_material_alpha()
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for archetype: int in [MapData.MapArchetype.RIVER_CROSSINGS, MapData.MapArchetype.WOODLAND_FLANKS]:
			await _inspect_map(phone, archetype)
	_expect(_completed_maps == 4, "all four map/profile checks complete")
	if DisplayServer.get_name() != "headless":
		_expect(_captures.size() == 16, "all sixteen requested phone views are captured")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "captures": _captures,
		"checks": _checks, "maps": _maps,
		"atlas": _atlas_metrics(),
		"tileset_sha256": FileAccess.get_sha256("res://scripts/map/tileset_builder.gd"),
		"game_map_sha256": FileAccess.get_sha256("res://scripts/map/game_map.gd"),
		"user_data": OS.get_user_data_dir(), "baseline": _baseline}
	FileAccess.open(_output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] terrain_presentation: " + failure)
	if _failures.is_empty():
		print("[PASS] terrain_presentation: ", JSON.stringify(report))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _inspect_map(phone: Vector2i, archetype: int) -> void:
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	GameManager.set_state(GameManager.GameState.MENU)
	GameManager.selected_map_archetype = archetype
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_expect(main.get("_building_placement") != null, "Main completes initialization")
	if main.get("_building_placement") == null:
		main.free()
		return
	var map: Node2D = main.get("game_map")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	map.fog_of_war.reveal_all()
	map.get_node("FogLayer").clear()
	map.update_resource_visibility_for_player(0)
	var routes: Array[Dictionary] = map.map_generator.get_tactical_routes()
	_record_map(map, phone, archetype, routes)
	for index: int in routes.size():
		if archetype == MapData.MapArchetype.WOODLAND_FLANKS and index == 0:
			continue
		var focus: Vector2i = routes[index].waypoints[1]
		var zooms: Array[float] = [0.952]
		if archetype == MapData.MapArchetype.RIVER_CROSSINGS:
			zooms.append(0.65)
		for zoom_value: float in zooms:
			map.note_camera_interaction()
			map.camera.zoom = Vector2.ONE * zoom_value
			map.camera.position = map.tile_to_world(focus)
			map.camera.reset_smoothing()
			map.camera.force_update_scroll()
			for frame: int in 4:
				await get_tree().process_frame
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var filename: String = "map%d-%s-%dx%d-zoom%.3f.png" % [archetype, str(routes[index].name).to_snake_case().replace(" ", "_"), phone.x, phone.y, zoom_value]
				get_viewport().get_texture().get_image().save_png(_output.path_join(filename))
				_captures.append(filename)
	if not _baseline:
		_test_map_cells(map)
		_test_depletion_memory(map)
	main.free()
	_completed_maps += 1
	GameManager.set_state(GameManager.GameState.MENU)
	await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and not _failures.has(message):
		_failures.append(message)

func _test_atlas() -> void:
	var tileset: TileSet = TilesetBuilder.build_terrain_tileset()
	var source := tileset.get_source(0) as TileSetAtlasSource
	var atlas: Image = source.texture.get_image()
	_expect(source.get_tiles_count() == 24, "nine unchanged base columns plus fifteen shoreline variants")
	_expect(tileset.get_physics_layers_count() == 0, "visual atlas adds no collision")
	var middle_edges: Array[Vector2i] = [Vector2i(16, 8), Vector2i(48, 8), Vector2i(48, 24), Vector2i(16, 24)]
	for mask: int in range(1, 16):
		var column: int = 9 + mask - 1
		var alpha_equal: bool = true
		for y: int in 32:
			for x: int in 64:
				alpha_equal = alpha_equal and atlas.get_pixel(64 + x, y).a == atlas.get_pixel(column * 64 + x, y).a
		_expect(alpha_equal, "mask%d retains exact base-water alpha" % mask)
		_expect(atlas.get_pixel(column * 64 + 32, 16) == atlas.get_pixel(96, 16), "mask%d retains deep-water interior" % mask)
		for edge: int in 4:
			var point: Vector2i = middle_edges[edge]
			var altered: bool = atlas.get_pixel(column * 64 + point.x, point.y) != atlas.get_pixel(64 + point.x, point.y)
			_expect(altered == bool(mask & (1 << edge)), "mask%d paints only the requested edge%d" % [mask, edge])
	var bright: Color = atlas.get_pixel(MapData.TileType.GRASS_ALT * 64 + 32, 16)
	var dark: Color = atlas.get_pixel(MapData.TileType.GRASS_DARK * 64 + 32, 16)
	_expect(bright.r - dark.r <= 4.1 / 255.0 and bright.g - dark.g <= 3.1 / 255.0, "grass variation is restrained to half the prior channel contrast")

func _record_map(map: Node2D, phone: Vector2i, archetype: int, routes: Array[Dictionary]) -> void:
	var paths: Array = []
	for route: Dictionary in routes:
		var path_tiles: Array = []
		var points: Array = route.waypoints
		for index: int in range(1, points.size()):
			var path: Array[Vector2i] = map.pathfinding.get_tile_path(points[index - 1], points[index])
			_expect(not path.is_empty(), "each center/side route is reachable")
			for tile: Vector2i in path:
				path_tiles.append([tile.x, tile.y])
		paths.append({"name": route.name, "tiles": path_tiles})
	_maps.append({"phone": [phone.x, phone.y], "archetype": archetype,
		"grid_sha256": JSON.stringify(map.map_generator.grid).sha256_text(),
		"paths_sha256": JSON.stringify(paths).sha256_text(), "resource_count": map.resource_nodes.size(),
		"terrain_cells": map.terrain_layer.get_used_cells().size()})

func _test_map_cells(map: Node2D) -> void:
	var before_grid: String = JSON.stringify(map.map_generator.grid).sha256_text()
	var before_nodes: int = _node_count(map)
	map._build_terrain()
	_expect(before_grid == JSON.stringify(map.map_generator.grid).sha256_text(), "terrain rebuild cannot mutate simulation grid")
	_expect(before_nodes == _node_count(map), "terrain rebuild adds no scene nodes")
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
	for y: int in MapData.MAP_HEIGHT:
		for x: int in MapData.MAP_WIDTH:
			var tile := Vector2i(x, y)
			var type: int = map.map_generator.grid[y][x]
			var mask: int = 0
			if type == MapData.TileType.WATER:
				for edge: int in 4:
					var neighbor: Vector2i = tile + directions[edge]
					if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < MapData.MAP_WIDTH and neighbor.y < MapData.MAP_HEIGHT and map.map_generator.grid[neighbor.y][neighbor.x] != MapData.TileType.WATER:
						mask |= 1 << edge
			var expected: Vector2i = Vector2i(9 + mask - 1, 0) if mask > 0 else Vector2i(type, 0)
			_expect(map.terrain_layer.get_cell_atlas_coords(tile) == expected, "tile%s uses only its land-adjacent shoreline bits" % tile)

func _test_material_alpha() -> void:
	var source: TileSetAtlasSource = TilesetBuilder.build_terrain_tileset().get_source(0)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 32)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var tint := Node2D.new()
	viewport.add_child(tint)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tint.add_child(sprite)
	for column: int in [MapData.TileType.GRASS, MapData.TileType.WATER, TilesetBuilder.SHORE_VARIANT_START]:
		var texture := AtlasTexture.new()
		texture.atlas = source.texture
		texture.region = Rect2(column * 64, 0, 64, 32)
		sprite.texture = texture
		sprite.material = null
		tint.modulate = Color.WHITE
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var original: Image = viewport.get_texture().get_image()
		sprite.material = source.get_tile_data(Vector2i(column, 0), 0).material
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var shaded: Image = viewport.get_texture().get_image()
		var changed_colors: int = 0
		for y: int in 32:
			for x: int in 64:
				var before: Color = original.get_pixel(x, y)
				var after: Color = shaded.get_pixel(x, y)
				_expect(is_equal_approx(before.a, after.a), "material%d retains every rendered alpha pixel" % column)
				changed_colors += int(before.a > 0.9 and before != after)
		_expect(changed_colors > 0, "material%d adds visible surface variation" % column)
		tint.modulate = Color(0.5, 0.5, 0.5, 0.5)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var faded: Image = viewport.get_texture().get_image()
		for y: int in 32:
			for x: int in 64:
				var before: Color = shaded.get_pixel(x, y)
				var after: Color = faded.get_pixel(x, y)
				_expect(absf(after.a - before.a * 0.5) < 1.1 / 255.0, "material%d retains inherited half-alpha" % column)
				if before.a > 0.9:
					_expect(after.r <= before.r and after.g <= before.g and after.b <= before.b, "material%d retains inherited darkness" % column)
	viewport.free()

func _test_depletion_memory(map: Node2D) -> void:
	var resource_tile: Vector2i = map.resource_nodes.keys()[0]
	var resource: ResourceNode = map.resource_nodes[resource_tile]
	var old_type: int = map.map_generator.grid[resource_tile.y][resource_tile.x]
	var old_atlas: Vector2i = map.terrain_layer.get_cell_atlas_coords(resource_tile)
	var water_before: Dictionary = {}
	for tile: Vector2i in map.terrain_layer.get_used_cells():
		if map.map_generator.grid[tile.y][tile.x] == MapData.TileType.WATER:
			water_before[tile] = map.terrain_layer.get_cell_atlas_coords(tile)
	map.fog_of_war.fog_grid[resource_tile.y][resource_tile.x] = MapData.FogState.EXPLORED
	resource.harvest(resource.remaining)
	_expect(map.map_generator.grid[resource_tile.y][resource_tile.x] == MapData.TileType.GRASS, "depletion changes simulation terrain immediately")
	_expect(map.terrain_layer.get_cell_atlas_coords(resource_tile) == old_atlas, "hidden depletion retains the observed terrain tile")
	_expect(map.get_minimap_grid_for_player(0)[resource_tile.y][resource_tile.x] == old_type, "hidden depletion retains minimap terrain memory")
	map.update_resource_visibility_for_player(0)
	_expect(map.terrain_layer.get_cell_atlas_coords(resource_tile) == old_atlas, "explored-only refresh cannot reveal depletion")
	map.fog_of_war.fog_grid[resource_tile.y][resource_tile.x] = MapData.FogState.VISIBLE
	map.update_resource_visibility_for_player(0)
	_expect(map.terrain_layer.get_cell_atlas_coords(resource_tile) == Vector2i(MapData.TileType.GRASS, 0), "reveal applies base grass after depletion")
	_expect(map.get_minimap_grid_for_player(0)[resource_tile.y][resource_tile.x] == MapData.TileType.GRASS, "reveal updates minimap memory")
	for tile: Vector2i in water_before:
		_expect(map.terrain_layer.get_cell_atlas_coords(tile) == water_before[tile], "land depletion leaves every shore unchanged")

func _node_count(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _node_count(child)
	return count

func _atlas_metrics() -> Dictionary:
	var source := TilesetBuilder.build_terrain_tileset().get_source(0) as TileSetAtlasSource
	var image: Image = source.texture.get_image()
	var water: Image = image.get_region(Rect2i(64, 0, 64, 32))
	var fog_source := TilesetBuilder.build_fog_tileset().get_source(0) as TileSetAtlasSource
	return {"size": [image.get_width(), image.get_height()], "rgba_bytes": image.get_data().size(),
		"water_base_sha256": _hash_bytes(water.get_data()), "fog_sha256": _hash_bytes(fog_source.texture.get_image().get_data())}

func _hash_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
