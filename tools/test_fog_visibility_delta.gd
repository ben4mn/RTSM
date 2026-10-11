extends SceneTree
## Visibility transitions, overlapping sources and live scout identity.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fog := FogManager.new()
	root.add_child(fog)
	fog.set_process(false)
	var layer := TileMapLayer.new()
	layer.tile_set = TilesetBuilder.build_fog_tileset()
	root.add_child(layer)
	fog.fog_layer = layer
	var sources: Array[Dictionary] = [
		{"position": Vector2i(8, 8), "vision_radius": 3, "is_scout": true},
		{"position": Vector2i(9, 8), "vision_radius": 3, "is_scout": false},
	]
	fog.set_vision_sources(sources)
	fog.refresh_visibility_now()
	_expect(fog.is_tile_visible(Vector2i(8, 8)), "new source reveals immediately")
	_expect(layer.get_cell_source_id(Vector2i(8, 8)) == -1, "current vision clears the rendered overlay")
	_expect(fog.is_revealed_by_scout(Vector2i(8, 8)), "live scout reveals stealth")
	var initial: Array = fog.fog_grid.duplicate(true)
	var reordered: Array[Dictionary] = [sources[1], sources[0], sources[0]]
	fog.set_vision_sources(reordered)
	fog.refresh_visibility_now()
	_expect(fog.fog_grid == initial and fog._dirty_cells.is_empty(), "duplicates and source ordering do not change visibility")
	sources[0]["is_scout"] = false
	fog.set_vision_sources(sources)
	fog.refresh_visibility_now()
	_expect(not fog.is_revealed_by_scout(Vector2i(8, 8)), "scout loss changes stealth detection even at unchanged tile vision")
	_expect(fog._dirty_cells.is_empty(), "scout identity does not redraw unchanged terrain")
	sources[0]["position"] = Vector2i(30, 30)
	fog.set_vision_sources(sources)
	fog.refresh_visibility_now()
	_expect(fog.is_tile_visible(Vector2i(30, 30)), "moving vision arrives in the same refresh")
	_expect(not fog.is_tile_visible(Vector2i(5, 8)) and fog.is_explored(Vector2i(5, 8)), "lost overlap retains explored terrain but loses current vision")
	var unique: Dictionary = {}
	for cell: Vector2i in fog._dirty_cells:
		unique[cell] = true
	_expect(unique.size() == fog._dirty_cells.size(), "each changed cell is rendered once")
	fog.clear_vision_sources()
	fog.refresh_visibility_now()
	_expect(not fog.is_tile_visible(Vector2i(30, 30)) and fog.is_explored(Vector2i(30, 30)), "last source removal hides immediately")
	fog.reveal_all()
	fog.refresh_visibility_now()
	_expect(not fog.is_tile_visible(Vector2i(47, 47)) and fog.is_explored(Vector2i(47, 47)), "debug reveal does not poison visibility cache")
	fog._init_fog_grid()
	fog.refresh_visibility_now()
	_expect(not fog.is_explored(Vector2i(8, 8)), "new match resets explored terrain and cache")
	_expect(layer.get_cell_source_id(Vector2i(8, 8)) == 0 and layer.get_cell_atlas_coords(Vector2i(8, 8)) == Vector2i.ZERO, "reset restores opaque unexplored overlay on a reused layer")
	fog.free()
	layer.free()
	for failure: String in failures:
		push_error(failure)
	print("[PASS] fog_visibility_delta" if failures.is_empty() else "[FAIL] fog_visibility_delta")
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
