extends Node
## Read-only generated-map diagnostic. No running match, resource grants, saved
## preferences or gameplay mutation. Uses canonical GameMap world conversions.

const GAME_MAP_SCRIPT = preload("res://scripts/map/game_map.gd")
const FAIRNESS_PROBE = preload("res://tools/probe_map_opening_fairness.gd")
const RESOURCE_TYPES: Dictionary = {
	"food": MapData.TileType.BERRY_BUSH,
	"wood": MapData.TileType.FOREST,
	"gold": MapData.TileType.GOLD_MINE,
}
const STOCK_PER_TILE: Dictionary = {"food": 200, "wood": 250, "gold": 400}
const DETAIL_SEEDS: Array[int] = [101, 424242, 20261021]
const GENERATION_STAGES: Array[String] = [
	"_init_grid", "_place_sacred_site", "_place_spawn_positions",
	"_place_water_features", "_place_forest_clusters", "_place_archetype_features",
	"_place_resources", "_ensure_spawn_clearance", "_ensure_center_lane",
	"_ensure_tactical_lanes", "_place_guaranteed_near_spawn_resources",
	"_place_contested_mid_resources", "_place_expansion_resources", "_add_grass_variety",
]
const LANE_CLEARING_STAGES: Array[String] = [
	"_ensure_spawn_clearance", "_ensure_center_lane", "_ensure_tactical_lanes",
]
var _failures: Array[String] = []


## Diagnostic reference only: same solids, diagonal rules and forest weights as
## production, but optimize canonical world distance instead of tile-ID distance.
class WorldMetricGrid extends AStarGrid2D:
	var world_positions: Dictionary = {}

	func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		return (world_positions[from_id] as Vector2).distance_to(world_positions[to_id])

	func _estimate_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		return (world_positions[from_id] as Vector2).distance_to(world_positions[to_id])


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path: String = "res://output/polish-2026-10-22/maps/resources.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	var seeds: Array[int] = []
	for seed_value: int in range(32):
		seeds.append(seed_value)
	seeds.append_array(DETAIL_SEEDS)
	var rows: Array[Dictionary] = []
	var fairness: Node = FAIRNESS_PROBE.new()
	for archetype: int in MapData.MAP_ARCHETYPES:
		for seed_value: int in seeds:
			rows.append(_measure(seed_value, archetype, fairness))
	fairness.free()
	var runtime_profiles: Array[Dictionary] = await _runtime_size_profiles()
	var hashes: Dictionary = {}
	for source: String in ["scripts/map/map_generator.gd", "scripts/map/map_data.gd", "scripts/map/pathfinding.gd", "scripts/map/game_map.gd", "scripts/data/unit_data.gd", "tools/probe_polish_map_resources.gd"]:
		hashes[source] = (load("res://" + source) as Script).source_code.sha256_text()
	var report: Dictionary = {
		"scope": "105 generated maps; stage stock accounting and canonical routes with solid starting TCs. Nine detailed maps compare production routes to a world-distance reference. No live gathering, combat, crowding, fog decisions or match-duration claims.",
		"engine": Engine.get_version_info(), "source_sha256": hashes,
		"size": [MapData.MAP_WIDTH, MapData.MAP_HEIGHT], "rows": rows, "runtime_size_profiles": runtime_profiles, "failures": _failures,
		"reference_cost": "World-distance edge length times destination forest weight2.5. The reference changes no production code. Route seconds use nominal unupgraded speed, not simulated movement.",
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path).get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if _failures.is_empty():
		print("[PASS] map_resources: 105 canonical maps, stage replay matches generation, protected stock and expansion routes verified; diagnostics written to " + output_path)
	else:
		for failure: String in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _runtime_size_profiles() -> Array[Dictionary]:
	var saved: Dictionary = {}
	for field: String in ["selected_map_seed", "selected_map_archetype", "selected_population_limit", "selected_match_mode"]:
		saved[field] = GameManager.get(field)
	var previous_state: int = GameManager.current_state
	var reports: Array[Dictionary] = []
	GameManager.selected_map_seed = 101
	for archetype: int in MapData.MAP_ARCHETYPES:
		var expected := MapGenerator.new(101, archetype)
		expected.generate()
		GameManager.selected_map_archetype = archetype
		for mode: int in [SkirmishData.MatchMode.STANDARD, SkirmishData.MatchMode.QUICK_CONTROL]:
			GameManager.selected_match_mode = mode
			for population: int in SkirmishData.POPULATION_OPTIONS:
				GameManager.selected_population_limit = population
				var map: Node2D = load("res://scenes/map/game_map.tscn").instantiate()
				map.process_mode = Node.PROCESS_MODE_DISABLED
				add_child(map)
				await get_tree().process_frame
				var actual: Array = map.map_generator.grid
				var label: String = "%s mode%d pop%d" % [MapData.get_archetype_name(archetype), mode, population]
				_expect(actual.size() == MapData.MAP_HEIGHT and actual[0].size() == MapData.MAP_WIDTH, label + " changed runtime dimensions")
				_expect(actual == expected.grid, label + " changed terrain by mode/population")
				reports.append({"archetype": archetype, "mode": SkirmishData.get_mode_name(mode), "population_limit": population, "size": [actual[0].size(), actual.size()], "grid_sha256": JSON.stringify(actual).sha256_text()})
				map.free()
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var summary: String = "%d × %d battlefield" % [MapData.MAP_WIDTH, MapData.MAP_HEIGHT]
	_expect(menu.map_summary_label.text == summary and str(menu.main_menu_diagnostics.get("map_summary", "")) == summary, "menu diagnostic still reports obsolete Pocket Duel dimensions")
	menu.free()
	for field: String in saved:
		GameManager.set(field, saved[field])
	GameManager.set_state(previous_state)
	return reports


func _measure(seed_value: int, archetype: int, fairness: Node) -> Dictionary:
	var generator := MapGenerator.new(seed_value, archetype)
	generator.generate()
	var label: String = "%s seed%d" % [MapData.get_archetype_name(archetype), seed_value]
	var map: Node2D = GAME_MAP_SCRIPT.new()
	var pathfinder := Pathfinding.new(generator)
	var footprint: Vector2i = BuildingData.BUILDINGS[BuildingData.BuildingType.TOWN_CENTER]["footprint"]
	for spawn: Vector2i in generator.spawn_positions:
		pathfinder.set_area_solid(spawn, footprint)
	map.set("map_generator", generator)
	map.set("pathfinding", pathfinder)
	var counts: Dictionary = _counts(generator.grid)
	var stocks: Dictionary = {}
	for resource: String in RESOURCE_TYPES:
		stocks[resource] = int(counts[resource]) * int(STOCK_PER_TILE[resource])
	var home: Array[Dictionary] = []
	for spawn: Vector2i in generator.spawn_positions:
		var local: Dictionary = {"food": 0, "wood": 0, "gold": 0}
		for y: int in range(MapData.MAP_HEIGHT):
			for x: int in range(MapData.MAP_WIDTH):
				if spawn.distance_squared_to(Vector2i(x, y)) > 169.0:
					continue
				for resource: String in RESOURCE_TYPES:
					if generator.grid[y][x] == RESOURCE_TYPES[resource]:
						local[resource] += 1
		_expect(int(local.food) >= 4 and int(local.wood) >= 8 and int(local.gold) >= 2, label + " lost guaranteed opening stock")
		home.append(local)
	var start: Vector2i = generator.get_tactical_routes()[0].waypoints[0]
	var expansions: Array[Dictionary] = []
	for center: Vector2i in generator.get_expansion_pocket_centers():
		var own_path: Array[Vector2i] = pathfinder.get_tile_path(start, center)
		var opposing_start := Vector2i(start.y, start.x)
		var enemy_path: Array[Vector2i] = pathfinder.get_tile_path(opposing_start, center)
		_expect(not own_path.is_empty() and not enemy_path.is_empty(), label + " inaccessible expansion " + str(center))
		var own_length: float = _route_cost(own_path, map, generator, false)
		var enemy_length: float = _route_cost(enemy_path, map, generator, false)
		expansions.append({"tile": [center.x, center.y], "own_route_world": own_length, "opponent_route_world": enemy_length, "worker_travel_seconds": own_length / float(UnitData.UNITS[UnitData.UnitType.VILLAGER].speed), "opponent_access_ratio": enemy_length / maxf(own_length, 0.01)})
	var row: Dictionary = {
		"seed": seed_value, "archetype": archetype, "name": MapData.get_archetype_name(archetype),
		"grid_sha256": JSON.stringify(generator.grid).sha256_text(), "resource_nodes": counts,
		"finite_stock": stocks, "opening_stock_nodes": home, "expansions": expansions,
		"generation_stages": _stage_trace(seed_value, archetype, generator.grid, label),
	}
	if seed_value in DETAIL_SEEDS:
		row["opening_routes"] = fairness.call("measure_seed", seed_value, archetype)
		row["metric_comparison"] = _metric_comparisons(generator, pathfinder, map)
		row["finite_harvest_approaches"] = _finite_harvest_approaches(generator, map, label)
	map.free()
	return row


func _counts(grid: Array) -> Dictionary:
	var counts: Dictionary = {"food": 0, "wood": 0, "gold": 0, "water": 0, "decorative_stone": 0}
	for row: Array in grid:
		for tile: int in row:
			for resource: String in RESOURCE_TYPES:
				if tile == RESOURCE_TYPES[resource]:
					counts[resource] += 1
			if tile == MapData.TileType.WATER:
				counts.water += 1
			elif tile == MapData.TileType.STONE:
				counts.decorative_stone += 1
	return counts


func _stage_trace(seed_value: int, archetype: int, final_grid: Array, label: String) -> Array[Dictionary]:
	var replay := MapGenerator.new(seed_value, archetype)
	var stages: Array[Dictionary] = []
	var ordered_stages: Array[String] = GENERATION_STAGES.duplicate()
	if archetype != MapData.MapArchetype.OPEN_PLAINS:
		ordered_stages.erase("_place_resources")
		ordered_stages.insert(ordered_stages.find("_ensure_tactical_lanes") + 1, "_place_resources")
	for method: String in ordered_stages:
		var before: Array = replay.grid.duplicate(true)
		replay.call(method)
		var erased: Dictionary = {"food": 0, "wood": 0, "gold": 0}
		if not before.is_empty():
			for y: int in range(MapData.MAP_HEIGHT):
				for x: int in range(MapData.MAP_WIDTH):
					for resource: String in RESOURCE_TYPES:
						if before[y][x] == RESOURCE_TYPES[resource] and replay.grid[y][x] != RESOURCE_TYPES[resource]:
							erased[resource] += 1
		if archetype != MapData.MapArchetype.OPEN_PLAINS and method in LANE_CLEARING_STAGES:
			_expect(int(erased.food) == 0 and int(erased.gold) == 0, label + " route clearing erased finite food/gold stock in " + method)
		stages.append({"stage": method, "counts": _counts(replay.grid), "erased": erased})
	_expect(replay.grid == final_grid, label + " diagnostic generation-stage replay is stale")
	return stages


func _finite_harvest_approaches(generator: MapGenerator, map: Node2D, label: String) -> Dictionary:
	var attempted: int = 0
	var reachable: int = 0
	var radius: float = MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD
	for player_id: int in generator.spawn_positions.size():
		var spawn: Vector2i = generator.spawn_positions[player_id]
		var offset := Vector2i(4, -4) if spawn.x < spawn.y else Vector2i(-4, 4)
		var origin: Vector2 = map.call("tile_to_world", spawn + offset)
		for y: int in range(MapData.MAP_HEIGHT):
			for x: int in range(MapData.MAP_WIDTH):
				if generator.grid[y][x] not in [MapData.TileType.BERRY_BUSH, MapData.TileType.GOLD_MINE]:
					continue
				attempted += 1
				var target: Vector2 = map.call("tile_to_world", Vector2i(x, y))
				var path: PackedVector2Array = map.call("get_navigation_world_path", origin, target, radius)
				var valid: bool = not path.is_empty() and path[-1].distance_to(target) <= radius + 0.1
				_expect(valid, label + " player%d cannot reach actual food/gold gather radius at %s" % [player_id, Vector2i(x, y)])
				if valid:
					reachable += 1
	return {"attempted": attempted, "reachable": reachable, "interaction_radius_world": radius, "scope": "Both base approaches to every food/gold target through production GameMap navigation, with both starting Town Centers solid. Route preflight only; no simulated harvesting or delivery."}


func _metric_comparisons(generator: MapGenerator, pathfinder: Pathfinding, map: Node2D) -> Array[Dictionary]:
	var reference := WorldMetricGrid.new()
	reference.region = Rect2i(0, 0, MapData.MAP_WIDTH, MapData.MAP_HEIGHT)
	reference.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	reference.update()
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			var tile := Vector2i(x, y)
			reference.world_positions[tile] = map.call("tile_to_world", tile)
			reference.set_point_solid(tile, not pathfinder.is_walkable(tile))
			if generator.grid[y][x] == MapData.TileType.FOREST:
				reference.set_point_weight_scale(tile, MapData.FOREST_MOVE_COST)
	var starts: Array[Vector2i] = []
	for spawn: Vector2i in generator.spawn_positions:
		starts.append(spawn + (Vector2i(4, -4) if spawn.x < spawn.y else Vector2i(-4, 4)))
	var destinations: Array[Vector2i] = generator.get_expansion_pocket_centers()
	destinations.append(Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2))
	# Every food/gold target, plus tactical waypoints: bounded to <120 routes per
	# detailed map. Wood interiors remain represented through route forest cost.
	for route: Dictionary in generator.get_tactical_routes():
		var crossing: Vector2i = route.waypoints[1]
		if crossing not in destinations:
			destinations.append(crossing)
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			if generator.grid[y][x] in [MapData.TileType.BERRY_BUSH, MapData.TileType.GOLD_MINE]:
				destinations.append(Vector2i(x, y))
	var rows: Array[Dictionary] = []
	for start: Vector2i in starts:
		for target: Vector2i in destinations:
			var actual: Array[Vector2i] = pathfinder.get_tile_path(start, target)
			var optimal: Array[Vector2i] = reference.get_id_path(start, target)
			if actual.is_empty() or optimal.is_empty():
				_failures.append("Missing metric comparison route " + str(start) + " to " + str(target))
				continue
			var actual_cost: float = _route_cost(actual, map, generator, true)
			var optimal_cost: float = _route_cost(optimal, map, generator, true)
			rows.append({"from": [start.x, start.y], "to": [target.x, target.y], "production_weighted_world": actual_cost, "reference_weighted_world": optimal_cost, "production_world_length": _route_cost(actual, map, generator, false), "reference_world_length": _route_cost(optimal, map, generator, false), "weighted_cost_ratio": actual_cost / maxf(optimal_cost, 0.01)})
	return rows


func _route_cost(path: Array[Vector2i], map: Node2D, generator: MapGenerator, weighted: bool) -> float:
	var length: float = 0.0
	for index: int in range(1, path.size()):
		var previous: Vector2 = map.call("tile_to_world", path[index - 1])
		var point: Vector2 = map.call("tile_to_world", path[index])
		var weight: float = MapData.FOREST_MOVE_COST if weighted and generator.get_tile(path[index]) == MapData.TileType.FOREST else 1.0
		length += previous.distance_to(point) * weight
	return length


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
