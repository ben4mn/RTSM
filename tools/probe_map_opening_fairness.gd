extends Node
## Generated-map navigation fixture: real generator, Pathfinding and canonical
## GameMap routes, with the two initial TC footprints marked solid. It measures
## geometry and travel; it does not simulate gathering, deposits or human play.

const GAME_MAP_SCRIPT = preload("res://scripts/map/game_map.gd")
const RESOURCE_TYPES: Dictionary = {
	"food": MapData.TileType.BERRY_BUSH,
	"wood": MapData.TileType.FOREST,
	"gold": MapData.TileType.GOLD_MINE,
}
var _output_path: String = "res://output/evolution/map-opening-baseline.json"
var _generator_source_path: String = "res://scripts/map/map_generator.gd"
var _archetype: int = MapData.MapArchetype.OPEN_PLAINS
var _seeds: Array[int] = [1, 2, 7, 42, 101, 202, 303, 404, 777, 424242]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--seeds="):
			_seeds.clear()
			for seed_text: String in argument.trim_prefix("--seeds=").split(","):
				_seeds.append(int(seed_text))
		elif argument.begins_with("--generator-source="):
			_generator_source_path = argument.trim_prefix("--generator-source=")
		elif argument.begins_with("--archetype="):
			_archetype = MapData.normalize_archetype(int(argument.trim_prefix("--archetype=")))
	var results: Array[Dictionary] = []
	for seed_value: int in _seeds:
		results.append(measure_seed(seed_value, _archetype))
	var report: Dictionary = {
		"evidence_kind": "generated-map navigation fixture; no gathering or deposit simulation",
		"engine": Engine.get_version_info(),
		"source_sha256": _source_hashes(),
		"generator_source_path": _generator_source_path,
		"generator_loaded_sha256": (load(_generator_source_path) as Script).source_code.sha256_text(),
		"population_caps": [20, 30, 40],
		"cap_scope": "map generation and starting TC geometry are independent of population cap",
		"method": "Nearest source by canonical TC-anchor world distance; real bounded GameMap path to 36px gather radius. trip_seconds is a geometry approach to the 48px TC footprint. deposit_trip_seconds uses the current shortest legal 40px TC-perimeter drop-off route. Two TC footprints are solid. Route length includes entry from the solid anchor to recovered route start. Seconds use unupgraded villager speed and exclude harvest ticks, crowding, visibility and combat.",
		"seeds": results,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_path).get_base_dir())
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	get_tree().quit(0)


func measure_seed(seed_value: int, archetype: int = MapData.MapArchetype.OPEN_PLAINS) -> Dictionary:
	# The one-argument branch also supports archived default-generator fixtures.
	var generator: MapGenerator = (load(_generator_source_path) as Script).new(seed_value) if archetype == MapData.MapArchetype.OPEN_PLAINS else (load(_generator_source_path) as Script).new(seed_value, archetype)
	generator.generate()
	var map: Node2D = GAME_MAP_SCRIPT.new()
	map.set("map_generator", generator)
	var pathfinder := Pathfinding.new(generator)
	var footprint: Vector2i = BuildingData.BUILDINGS[BuildingData.BuildingType.TOWN_CENTER]["footprint"]
	for spawn: Vector2i in generator.spawn_positions:
		pathfinder.set_area_solid(spawn, footprint)
	map.set("pathfinding", pathfinder)
	var sides: Array[Dictionary] = []
	var speed: float = UnitData.UNITS[UnitData.UnitType.VILLAGER]["speed"]
	for spawn: Vector2i in generator.spawn_positions:
		var anchor: Vector2 = map.call("tile_to_world", spawn)
		var side: Dictionary = {"spawn": [spawn.x, spawn.y], "resources": {}}
		for resource_name: String in RESOURCE_TYPES:
			var nearest: Vector2i = Vector2i(-1, -1)
			var nearest_distance: float = INF
			var local_count: int = 0
			for y: int in range(MapData.MAP_HEIGHT):
				for x: int in range(MapData.MAP_WIDTH):
					if generator.grid[y][x] != RESOURCE_TYPES[resource_name]:
						continue
					var tile := Vector2i(x, y)
					if spawn.distance_to(tile) <= 13.0:
						local_count += 1
					var distance: float = anchor.distance_to(map.call("tile_to_world", tile))
					if distance < nearest_distance:
						nearest_distance = distance
						nearest = tile
			var target_world: Vector2 = map.call("tile_to_world", nearest)
			var outbound: PackedVector2Array = map.call("get_navigation_world_path", anchor, target_world, MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD)
			var outbound_distance: float = _route_length(anchor, outbound)
			var arrival: Vector2 = outbound[-1] if not outbound.is_empty() else anchor
			var returning: PackedVector2Array = map.call("get_building_work_world_path", arrival, anchor, footprint, 48.0)
			var return_distance: float = _route_length(arrival, returning)
			var deposit_return: PackedVector2Array = map.call("get_building_dropoff_world_path", arrival, anchor, footprint, 40.0)
			var deposit_return_distance: float = _route_length(arrival, deposit_return)
			side["resources"][resource_name] = {
				"nearest_tile": [nearest.x, nearest.y], "local_tiles_in_13_radius": local_count,
				"straight_world": nearest_distance, "outbound_world": outbound_distance,
				"return_world": return_distance, "trip_seconds": (outbound_distance + return_distance) / speed,
				"deposit_return_world": deposit_return_distance,
				"deposit_trip_seconds": (outbound_distance + deposit_return_distance) / speed,
				"deposit_reachable": not deposit_return.is_empty() and float(map.call("get_building_work_distance", deposit_return[-1], anchor, footprint)) <= 48.0,
				"reachable": not outbound.is_empty() and not returning.is_empty(),
			}
		sides.append(side)
	var differences: Dictionary = {}
	for resource_name: String in RESOURCE_TYPES:
		var first: float = sides[0]["resources"][resource_name]["trip_seconds"]
		var second: float = sides[1]["resources"][resource_name]["trip_seconds"]
		var first_deposit: float = sides[0]["resources"][resource_name]["deposit_trip_seconds"]
		var second_deposit: float = sides[1]["resources"][resource_name]["deposit_trip_seconds"]
		differences[resource_name] = {"seconds": absf(first - second), "ratio": maxf(first, second) / maxf(0.01, minf(first, second)), "deposit_seconds": absf(first_deposit - second_deposit), "deposit_ratio": maxf(first_deposit, second_deposit) / maxf(0.01, minf(first_deposit, second_deposit))}
	map.free()
	return {"seed": seed_value, "archetype": archetype, "sides": sides, "trip_difference": differences}


func _route_length(from: Vector2, route: PackedVector2Array) -> float:
	var distance: float = 0.0
	for waypoint: Vector2 in route:
		distance += from.distance_to(waypoint)
		from = waypoint
	return distance


func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in ["scripts/map/map_generator.gd", "scripts/map/map_data.gd", "scripts/map/pathfinding.gd", "scripts/map/game_map.gd", "scripts/data/building_data.gd", "scripts/data/unit_data.gd", "scripts/main/main.gd", "tools/probe_map_opening_fairness.gd"]:
		var script: Script = load("res://" + path) as Script
		hashes[path] = script.source_code.sha256_text()
	return hashes
