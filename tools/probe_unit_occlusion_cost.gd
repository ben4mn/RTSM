extends Node
## CPU-only cost probe with 200 actual art-bearing unit nodes. Not a GPU/FPS or
## physical-phone benchmark. Headless presentation is enabled only here.

class VisibleFixture extends Node2D:
	func is_entity_visible_to_player(_entity: Node2D, _owner: int) -> bool: return true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var report := {"scope": "Headless CPU-only isolated observer process-call probe; 200 real units/art, all locally revealed, synthetic positions. 0.11s delta requests refresh whenever the 32-unit batches finish. Not GPU, full-match FPS, physical-device or steady 60fps throughput evidence.", "samples": []}
	for viewport_size: Vector2i in [Vector2i(844, 390), Vector2i(1280, 720)]:
		get_window().size = viewport_size
		get_window().content_scale_size = viewport_size
		var fixture := VisibleFixture.new()
		add_child(fixture)
		var container := Node2D.new()
		container.name = "UnitsContainer"
		fixture.add_child(container)
		var units: Array[UnitBase] = []
		for index: int in 200:
			var unit: UnitBase = load("res://scenes/units/infantry.tscn").instantiate()
			unit.player_owner = index % 2
			container.add_child(unit)
			unit.set_process(false)
			units.append(unit)
		var overlay: Node = load("res://scripts/ui/unit_occlusion_overlay.gd").new()
		fixture.add_child(overlay)
		overlay.set("allow_headless_fixture", true)
		overlay.set_process(false)
		for crowded: bool in [false, true]:
			for index: int in units.size():
				units[index].position = Vector2(120, 100) + Vector2(index % 20, index / 20) * (Vector2(14, 8) if crowded else Vector2(50, 35))
			for warm: int in 8: overlay.call("_process", 0.11)
			var times: Array[int] = []
			var checks: int = 0
			for repeat: int in 40:
				var start: int = Time.get_ticks_usec()
				overlay.call("_process", 0.11)
				times.append(Time.get_ticks_usec() - start)
				checks = maxi(checks, int(overlay.get("last_candidate_checks")))
			times.sort()
			var total: int = 0
			for elapsed: int in times: total += elapsed
			report.samples.append({"viewport": [viewport_size.x, viewport_size.y], "actors": 200, "crowded": crowded, "runs": times.size(), "mean_us": float(total) / times.size(), "p95_us": times[37], "max_us": times.back(), "max_opaque_candidate_checks": checks})
		fixture.queue_free()
		await get_tree().process_frame
	print("[OCCLUSION COST] " + JSON.stringify(report))
	get_tree().quit(0)
