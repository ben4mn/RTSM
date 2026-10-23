extends Node
## Repeatable actual-map views. Stops play and reveals terrain for art comparison;
## does not claim a paid gameplay journey or physical-phone performance result.

var _output: String = "res://output/world-art-2026-10-23/captures"
var _records: Array[Dictionary] = []
var _captures: Array[String] = []
var _render_samples: Array[Dictionary] = []
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.ui_scale = 1.0
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		for archetype: int in [MapData.MapArchetype.OPEN_PLAINS, MapData.MapArchetype.RIVER_CROSSINGS, MapData.MapArchetype.WOODLAND_FLANKS]:
			await _capture_map(size, archetype)
	if DisplayServer.get_name() != "headless":
		_expect(_captures.size() == 18, "All eighteen map views are rendered")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures,
		"captures": _captures, "render_samples": _render_samples, "records": _records, "user_data": OS.get_user_data_dir(),
		"tileset_sha256": FileAccess.get_sha256("res://scripts/map/tileset_builder.gd"),
		"resources_sha256": FileAccess.get_sha256("res://scripts/map/resource_node.gd"),
		"capture_sha256": FileAccess.get_sha256("res://tools/capture_world_field_art.gd")}
	FileAccess.open(_output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] world_field_art: " + failure)
	if _failures.is_empty():
		print("[PASS] world_field_art: six seeded map/profile records; eighteen actual-map native views when rendered")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _capture_map(size: Vector2i, archetype: int) -> void:
	get_window().size = size
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
	_expect(main.get("_building_placement") != null, "Main initialized")
	if main.get("_building_placement") == null:
		main.free()
		return
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var map: Node2D = main.get("game_map")
	map.fog_of_war.reveal_all()
	map.get_node("FogLayer").clear()
	map.update_resource_visibility_for_player(0)
	var town: BuildingBase = main.get("_player_town_center")
	var wood: ResourceNode = null
	var wood_distance: float = INF
	var resource_records: Array[Dictionary] = []
	for tile: Vector2i in map.resource_nodes:
		var resource: ResourceNode = map.resource_nodes[tile]
		var sprite: Sprite2D = resource.get_node("Sprite")
		resource_records.append({"tile": [tile.x, tile.y], "kind": resource.resource_type,
			"position": [resource.position.x, resource.position.y], "stock": resource.remaining,
			"scale": [sprite.scale.x, sprite.scale.y], "offset": [sprite.offset.x, sprite.offset.y]})
		if resource.resource_type == "wood":
			var distance: float = town.global_position.distance_squared_to(resource.global_position)
			if distance < wood_distance:
				wood = resource
				wood_distance = distance
	_expect(wood != null, "Home has a real wood source")
	var routes: Array[Dictionary] = map.map_generator.get_tactical_routes()
	var paths: Array = []
	for route: Dictionary in routes:
		var route_tiles: Array = []
		var waypoints: Array = route.waypoints
		for index: int in range(1, waypoints.size()):
			for tile: Vector2i in map.pathfinding.get_tile_path(waypoints[index - 1], waypoints[index]):
				route_tiles.append([tile.x, tile.y])
		paths.append(route_tiles)
	_records.append({"size": [size.x, size.y], "archetype": archetype,
		"grid_sha256": JSON.stringify(map.map_generator.grid).sha256_text(),
		"paths_sha256": JSON.stringify(paths).sha256_text(),
		"resources_sha256": JSON.stringify(resource_records).sha256_text(),
		"resource_count": resource_records.size(), "cells": map.terrain_layer.get_used_cells().size()})
	var views: Array[Dictionary] = [
		{"name": "home", "position": town.global_position + Vector2(145, -10), "zoom": 0.952},
		{"name": "grove", "position": wood.global_position + Vector2(45, -12), "zoom": 1.35},
		{"name": "route", "position": map.tile_to_world(routes[1].waypoints[1]), "zoom": 0.65},
	]
	for view: Dictionary in views:
		map.note_camera_interaction()
		map.set("_user_zoom_override", true)
		map.set("_zoom_transition_active", false)
		map.camera.zoom = Vector2.ONE * float(view.zoom)
		map.camera.position = view.position
		map.camera.reset_smoothing()
		map.camera.force_update_scroll()
		for frame: int in 6:
			await get_tree().process_frame
		_expect(map.camera.zoom.is_equal_approx(Vector2.ONE * float(view.zoom)), "Requested zoom retained")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var filename: String = "map%d-%s-%dx%d.png" % [archetype, str(view.name), size.x, size.y]
			get_viewport().get_texture().get_image().save_png(_output.path_join(filename))
			_captures.append(filename)
			_render_samples.append({"file": filename, "draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "render_objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), "zoom": map.camera.zoom.x, "camera": [map.camera.position.x, map.camera.position.y]})
	main.free()
	GameManager.set_state(GameManager.GameState.MENU)
	await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
