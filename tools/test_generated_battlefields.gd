extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []
	var samples: Array[Dictionary] = []
	var style_signatures: Dictionary = {}
	_test_reflection_groups(failures)
	for archetype: int in MapData.MAP_ARCHETYPES:
		var layouts: Dictionary = {}
		for seed_value: int in [1, 2, 3, 7, 19, 42, 99, 501, 12345, 424242, 8675309, 2147483646, 1298326314, 1505321194, 108016561, 1888842373]:
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
				if first.get_resource_amount(tile) <= 0: failures.append("empty initial resource")
				if key == "food" and first._is_near_spawn(tile, 12) and first.get_resource_amount(tile) != 90: failures.append("opening food changed")
			if stock != SkirmishData.NATURAL_RESOURCE_BUDGETS: failures.append("style changed finite budget: %s" % str(stock))
			if first._resource_amounts != second._resource_amounts: failures.append("non deterministic stock")
			var rng_state: int = first._rng.state
			var grid_signature: int = hash(first.grid)
			first._budget_natural_stock()
			if first._rng.state != rng_state or hash(first.grid) != grid_signature: failures.append("stock allocation changed terrain or RNG")
			layouts[str(first._flank_crossings) + str(first._expansion_centers) + str(first._opening_rotation)] = true
			samples.append({"style": archetype, "seed": seed_value, "stock": stock, "validation": first.validation_report})
		if layouts.size() < 10: failures.append("insufficient strategic variety")
	if style_signatures.values().size() != 5 or style_signatures[0] == style_signatures[3]: failures.append("lake style lacks distinctive terrain")
	print(JSON.stringify({"test": "generated_battlefields", "maps": samples.size(), "failures": failures, "samples": samples}))
	quit(0 if failures.is_empty() else 1)


func _test_reflection_groups(failures: Array[String]) -> void:
	# Exhaust feasible remainder parities, including multiple diagonal singles
	# and no pairs. The public failure had three singles, 33 pairs and R=68.
	for single_count: int in range(5):
		for pair_count: int in range(5):
			var tiles: Array[Vector2i] = []
			for index: int in range(single_count): tiles.append(Vector2i(index, index))
			for index: int in range(pair_count):
				tiles.append(Vector2i(index, 10))
				tiles.append(Vector2i(10, index))
			if tiles.is_empty(): continue
			for remainder: int in range(tiles.size()):
				if single_count == 0 and remainder % 2 == 1: continue
				var generator := MapGenerator.new(123, 0)
				var budget: int = 3 * tiles.size() + remainder
				generator._distribute_symmetric_stock(tiles, budget)
				var total: int = 0
				for tile: Vector2i in tiles:
					var amount: int = generator.get_resource_amount(tile)
					total += amount
					if amount not in [3, 4] or amount != generator.get_resource_amount(Vector2i(tile.y, tile.x)):
						failures.append("invalid reflection-group stock")
				if total != budget or generator._resource_amounts.size() != tiles.size():
					failures.append("reflection-group budget lost")
