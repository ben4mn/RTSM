extends SceneTree
## Deterministic CPU work probe, not a device frame-rate benchmark.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var results: Array[Dictionary] = []
	for source_count: int in [10, 20, 40]:
		var fog: Node = load("res://scripts/managers/fog_manager.gd").new()
		root.add_child(fog)
		fog.set_process(false)
		var sources: Array[Dictionary] = []
		for index: int in range(source_count):
			sources.append({"position": Vector2i(10 + index % 8, 10 + index / 8), "vision_radius": 6, "is_scout": index == 0})
		fog.set_vision_sources(sources)
		fog.refresh_visibility_now()
		var first_grid: Array = fog.fog_grid.duplicate(true)
		var start_usec: int = Time.get_ticks_usec()
		var stationary_dirty: int = 0
		for iteration: int in range(300):
			fog.refresh_visibility_now()
			stationary_dirty += fog._dirty_cells.size()
		var elapsed_usec: int = Time.get_ticks_usec() - start_usec
		if fog.fog_grid != first_grid:
			failures.append("stationary sources changed visibility")
		sources[0]["position"] = Vector2i(35, 35)
		fog.set_vision_sources(sources)
		fog.refresh_visibility_now()
		if not fog.is_tile_visible(Vector2i(35, 35)):
			failures.append("moving source did not reveal its new tile")
		results.append({"sources": source_count, "iterations": 300, "stationary_dirty_total": stationary_dirty, "refresh_mean_usec": float(elapsed_usec) / 300.0, "moving_dirty": fog._dirty_cells.size(), "grid_hash": JSON.stringify(fog.fog_grid).sha256_text()})
		fog.free()
	var output_path: String = "res://output/evolution/fog-before.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	var result: Dictionary = {"evidence_scope": "deterministic fog CPU work fixture; no rendering or physical device claim", "source_sha256": load("res://scripts/managers/fog_manager.gd").get_source_code().sha256_text(), "results": results, "failures": failures}
	FileAccess.open(output_path, FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
