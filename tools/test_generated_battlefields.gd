extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []
	var samples: Array[Dictionary] = []
	var style_signatures: Dictionary = {}
	for archetype: int in MapData.MAP_ARCHETYPES:
		var layouts: Dictionary = {}
		for seed_value: int in [1, 2, 3, 7, 19, 42, 99, 501, 12345, 424242, 8675309, 2147483646]:
			var first := MapGenerator.new(seed_value, archetype)
			var second := MapGenerator.new(seed_value, archetype)
			first.generate()
			second.generate()
			if seed_value == 424242: style_signatures[archetype] = hash(first.grid)
			if first.grid != second.grid: failures.append("non deterministic %d/%d" % [archetype, seed_value])
			if not first.validation_report.valid: failures.append("invalid %d/%d: %s" % [archetype, seed_value, first.validation_report.errors])
			var stock: Dictionary = {"food": 0, "wood": 0, "gold": 0}
			for tile: Vector2i in first._resource_amounts:
				if first.get_resource_amount(tile) != first.get_resource_amount(Vector2i(tile.y, tile.x)): failures.append("unequal stock")
				var kind: int = first.get_tile(tile)
				var key: String = "wood" if kind == MapData.TileType.FOREST else ("food" if kind == MapData.TileType.BERRY_BUSH else "gold")
				stock[key] += first.get_resource_amount(tile)
			layouts[str(first._flank_crossings) + str(first._expansion_centers) + str(first._opening_rotation)] = true
			samples.append({"style": archetype, "seed": seed_value, "stock": stock, "validation": first.validation_report})
		if layouts.size() < 10: failures.append("insufficient strategic variety")
	if style_signatures.values().size() != 5 or style_signatures[0] == style_signatures[3]: failures.append("lake style lacks distinctive terrain")
	print(JSON.stringify({"test": "generated_battlefields", "maps": samples.size(), "failures": failures, "samples": samples}))
	quit(0 if failures.is_empty() else 1)
