extends Node
## Wildlife placement on real generated battlefields, every archetype: both
## players get the same animals at reflected positions and equal walking
## distance, strays start outside the opening vision, everything stands on
## reachable grass, the layout is a pure function of the map seed, and the
## pass never touches the generator's own random stream.
## Sibling of tools/probe_map_opening_fairness.gd, which reports the numbers.

const GAME_MAP_SCRIPT = preload("res://scripts/map/game_map.gd")
const SEEDS: Array[int] = [1, 2, 7, 42, 101, 202, 303, 404, 777, 424242]
const TOWN_CENTER_VISION: float = 13.0

var failures: Array[String] = []
var checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and failures.size() < 40 and message not in failures:
		failures.append(message)


func _run() -> void:
	var layouts: Dictionary = {}
	var worst_ratio: float = 1.0
	for archetype: int in MapData.MAP_ARCHETYPES.size():
		for seed_value: int in SEEDS:
			var label: String = "%s seed %d" % [MapData.get_archetype_name(archetype), seed_value]
			var generator := MapGenerator.new(seed_value, archetype)
			generator.generate()
			var grid_before: Array = generator.grid.duplicate(true)
			var state_before: int = generator._rng.state
			var rows: Array[Dictionary] = WildlifePlacement.plan(generator)
			expect(generator._rng.state == state_before and generator.grid == grid_before, label + ": placement leaves the generator stream and terrain untouched")
			expect(rows.size() == 2 * (WildlifeData.HOME_SHEEP + WildlifeData.STRAY_PAIRS * 2 + WildlifeData.DEER_COUNT + WildlifeData.BOAR_COUNT), label + ": 14 animals per player, got %d rows" % rows.size())
			for problem: String in WildlifePlacement.audit(generator, rows):
				expect(false, label + ": " + problem)
			var again := MapGenerator.new(seed_value, archetype)
			again.generate()
			expect(str(WildlifePlacement.plan(generator)) == str(rows) and str(WildlifePlacement.plan(again, seed_value)) == str(rows), label + ": the plan is deterministic for its seed")
			layouts[str(rows.slice(0, rows.size() / 2).map(func(row: Dictionary) -> Vector2i: return row.tile))] = true
			for side: int in 2:
				expect(_opening_berries(generator, side) == 6, label + ": player %d has six opening berry bushes, found %d" % [side, _opening_berries(generator, side)])
			var map: Node2D = GAME_MAP_SCRIPT.new()
			map.set("map_generator", generator)
			var pathfinder := Pathfinding.new(generator)
			var footprint: Vector2i = BuildingData.BUILDINGS[BuildingData.BuildingType.TOWN_CENTER]["footprint"]
			for spawn: Vector2i in generator.spawn_positions:
				pathfinder.set_area_solid(spawn, footprint)
			map.set("pathfinding", pathfinder)
			var walk: Array[float] = [0.0, 0.0]
			for row: Dictionary in rows:
				var side: int = int(row.side)
				var spawn: Vector2i = generator.spawn_positions[side]
				var from: Vector2 = map.call("tile_to_world", spawn + (Vector2i(1, 4) if side == 0 else Vector2i(4, 1)))
				var to: Vector2 = map.call("tile_to_world", row.tile)
				var route: PackedVector2Array = map.call("get_navigation_world_path", from, to, 4.0)
				expect(not route.is_empty() and route[route.size() - 1].distance_to(to) <= 4.0, label + ": a villager can walk to the %s at %s" % [row.kind, row.tile])
				walk[side] += _route_length(from, route)
				if str(row.group).begins_with("stray"):
					expect(Vector2(row.tile - spawn).length() > TOWN_CENTER_VISION + 1.0, label + ": stray at %s starts outside Town Center vision" % row.tile)
					for offset: Vector2i in generator.get_starting_villager_offsets(side):
						expect(Vector2(row.tile - spawn - offset).length() > 10.0, label + ": stray at %s is beyond the opening units' sight" % row.tile)
				else:
					expect(Vector2(row.tile - spawn).length() <= TOWN_CENTER_VISION, label + ": %s at %s is visible from the start" % [row.kind, row.tile])
			var ratio: float = maxf(walk[0], walk[1]) / maxf(1.0, minf(walk[0], walk[1]))
			worst_ratio = maxf(worst_ratio, ratio)
			expect(ratio <= 1.03, label + ": both players walk the same total distance to their wildlife (ratio %.3f)" % ratio)
			map.free()
	expect(layouts.size() >= SEEDS.size(), "different seeds give different wildlife layouts: %d distinct" % layouts.size())
	print(JSON.stringify({"test": "wildlife_placement", "checks": checks, "failures": failures, "maps": MapData.MAP_ARCHETYPES.size() * SEEDS.size(), "worst_walk_ratio": snappedf(worst_ratio, 0.0001), "distinct_layouts": layouts.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _opening_berries(generator: MapGenerator, side: int) -> int:
	var spawn: Vector2i = generator.spawn_positions[side]
	var count: int = 0
	for dy: int in range(-12, 13):
		for dx: int in range(-12, 13):
			if generator.get_tile(spawn + Vector2i(dx, dy)) == MapData.TileType.BERRY_BUSH:
				count += 1
	return count


func _route_length(from: Vector2, route: PackedVector2Array) -> float:
	var distance: float = 0.0
	for waypoint: Vector2 in route:
		distance += from.distance_to(waypoint)
		from = waypoint
	return distance
