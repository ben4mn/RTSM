extends SceneTree
## Component comparison against the exact allocator used by pacing revision
## 383e012. Terrain generation is shared; only stock allocation is overridden.
## This does not relabel the recorded matches as runs on a later revision.

class LegacyAllocator extends MapGenerator:
	var allocations: Array[Dictionary] = []
	func _distribute_symmetric_stock(tiles: Array[Vector2i], budget: int) -> void:
		assert(not tiles.is_empty() and budget >= tiles.size(), "Finite stock must cover every resource node")
		if tiles.is_empty(): return
		var per_tile: int = maxi(1, floori(float(budget) / float(tiles.size())))
		var remainder: int = budget - per_tile * tiles.size()
		for tile: Vector2i in tiles: _resource_amounts[tile] = per_tile
		for tile: Vector2i in tiles:
			if remainder <= 0: break
			var mirrored: Vector2i = _mirror_tile(tile)
			if tile == mirrored and remainder % 2 == 1:
				_resource_amounts[tile] += 1
				remainder -= 1
			elif tile.y * MapData.MAP_WIDTH + tile.x < mirrored.y * MapData.MAP_WIDTH + mirrored.x and remainder >= 2:
				_resource_amounts[tile] += 1
				_resource_amounts[mirrored] += 1
				remainder -= 2
		# The legacy final assert is intentionally replaced with a measurement.
		allocations.append({"tiles": tiles.duplicate(), "budget": budget, "q": per_tile, "remainder": remainder})

var checks: int = 0
var failures: Array[String] = []
var witnesses: Array[Dictionary] = []

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	for setup: Array in [[0, 424242], [1, 424242], [4, 7]]:
		var current := MapGenerator.new(setup[1], setup[0])
		var legacy := LegacyAllocator.new(setup[1], setup[0])
		current.generate()
		legacy.generate()
		var label: String = "style%d/seed%d" % [setup[0], setup[1]]
		expect(legacy.allocations.size() == 3, label + " exercised wood, food and gold allocator calls")
		var unallocated: int = 0
		for allocation: Dictionary in legacy.allocations: unallocated += int(allocation.remainder)
		expect(unallocated == 0, label + " legacy allocation succeeded")
		expect(current.grid == legacy.grid, label + " full terrain grid is unchanged")
		expect(current._resource_amounts == legacy._resource_amounts, label + " every exact resource amount is unchanged")
		expect(current._rng.seed == legacy._rng.seed and current._rng.state == legacy._rng.state, label + " RNG seed and state are unchanged")
		expect(current.validation_report.valid and legacy.validation_report.valid, label + " both layouts remain valid")
		expect(_stock(current) == SkirmishData.NATURAL_RESOURCE_BUDGETS, label + " exact finite budgets retained")
		var state_before: int = current._rng.state
		var grid_before: Array = current.grid.duplicate(true)
		var stock_before: Dictionary = current._resource_amounts.duplicate()
		current._budget_natural_stock()
		expect(current._rng.state == state_before and current.grid == grid_before and current._resource_amounts == stock_before, label + " repeated stock allocation is idempotent and consumes no RNG")
		witnesses.append({"style": setup[0], "seed": setup[1], "grid_hash": hash(current.grid), "resource_amounts_sha256": _amount_digest(current), "rng_state": current._rng.state, "stock": _stock(current), "exact_amounts_equal": current._resource_amounts == legacy._resource_amounts})

	var repaired := MapGenerator.new(1888842373, 3)
	var incomplete := LegacyAllocator.new(1888842373, 3)
	repaired.generate()
	incomplete.generate()
	expect(incomplete.allocations.size() == 3, "failed public seed has all allocation measurements")
	var wood_call: Dictionary = incomplete.allocations[0]
	expect(int(wood_call.remainder) == 2, "public seed reproduces legacy wood remainder of exactly two")
	expect(int(_stock(incomplete).wood) == 9998, "legacy public seed omitted exactly two wood")
	expect(repaired.grid == incomplete.grid, "repair does not change failing seed terrain")
	expect(repaired._rng.seed == incomplete._rng.seed and repaired._rng.state == incomplete._rng.state, "repair consumes no additional RNG")
	expect(repaired.validation_report.valid, "repaired public seed remains reachable and valid")
	expect(_stock(repaired) == SkirmishData.NATURAL_RESOURCE_BUDGETS and int(_stock(repaired).wood) == 10000, "repaired seed has exact 4000 food/10000 wood/4000 gold budgets")
	var symmetric: bool = true
	for tile: Vector2i in repaired._resource_amounts:
		if repaired.get_resource_amount(tile) != repaired.get_resource_amount(repaired._mirror_tile(tile)): symmetric = false
	expect(symmetric, "all repaired resource amounts retain reflection fairness")
	for index: int in incomplete.allocations.size():
		var allocation: Dictionary = incomplete.allocations[index]
		var balanced: bool = true
		for tile: Vector2i in allocation.tiles:
			if repaired.get_resource_amount(tile) not in [int(allocation.q), int(allocation.q) + 1]: balanced = false
		expect(balanced, "allocation %d keeps every node at q or q+1" % index)
	var replay := MapGenerator.new(1888842373, 3)
	replay.generate()
	expect(replay.grid == repaired.grid and replay._resource_amounts == repaired._resource_amounts and replay._rng.state == repaired._rng.state, "repaired failing seed replays deterministically")
	witnesses.append({"style": 3, "seed": 1888842373, "legacy_wood_remainder": wood_call.remainder, "legacy_stock": _stock(incomplete), "current_stock": _stock(repaired), "resource_amounts_sha256": _amount_digest(repaired), "rng_state": repaired._rng.state})
	print(JSON.stringify({"test": "pacing_stock_compatibility", "legacy_allocator_revision": "383e0127da8349c4ee42d60d590ebf1350949100", "scope": "Data-only allocator comparison on shared terrain generation; no matches rerun or evidence relabeled", "checks": checks, "failures": failures, "witnesses": witnesses}))
	quit(0 if failures.is_empty() else 1)

func _stock(map: MapGenerator) -> Dictionary:
	var result: Dictionary = {"food": 0, "wood": 0, "gold": 0}
	for tile: Vector2i in map._resource_amounts:
		var kind: int = map.get_tile(tile)
		var key: String = "wood" if kind == MapData.TileType.FOREST else ("food" if kind == MapData.TileType.BERRY_BUSH else "gold")
		result[key] += map.get_resource_amount(tile)
	return result

func _amount_digest(map: MapGenerator) -> String:
	var parts: PackedStringArray = []
	for y: int in MapData.MAP_HEIGHT:
		for x: int in MapData.MAP_WIDTH:
			var tile := Vector2i(x, y)
			if map._resource_amounts.has(tile): parts.append("%d,%d:%d" % [x, y, map.get_resource_amount(tile)])
	return ";".join(parts).sha256_text()
