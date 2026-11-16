extends SceneTree
func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261026
	var failures: Array[Dictionary] = []
	var repairs: Array[Dictionary] = []
	var maps: int = 0
	for index: int in range(100):
		var seed_value: int = rng.randi_range(1, 2147483646)
		for style: int in MapData.MAP_ARCHETYPES:
			var generator := MapGenerator.new(seed_value, style)
			generator.generate()
			maps += 1
			if not generator.validation_report.valid: failures.append({"seed": seed_value, "style": style, "validation": generator.validation_report})
			if generator._expanded_fringe_count > 0 or generator._resource_bridge_count > 0: repairs.append({"seed": seed_value, "style": style, "expanded_fringes": generator._expanded_fringe_count, "resource_bridges": generator._resource_bridge_count})
	print(JSON.stringify({"test": "expansion_seed_sweep", "maps": maps, "failures": failures, "repairs": repairs}))
	quit(0 if failures.is_empty() else 1)
