extends Node
## Actual GameMap/Pathfinding/UnitBase movement over a deliberately cleared
## synthetic patch. Building pairs cover every 2x2/3x3/4x4 combination.
## This verifies center navigation, not swept-circle physics or native appearance.

const MAP: PackedScene = preload("res://scenes/map/game_map.tscn")
const SCENES: Array[String] = ["villager", "infantry", "archer", "cavalry", "scout", "siege"]
const KINDS: Array[int] = [BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.TOWN_CENTER]
const DELTAS: Array[float] = [1.0 / 60.0, 0.05, 0.0333, 0.08]
var failures: Array[String] = []
var records: Array[Dictionary] = []
var encounters: Array[Dictionary] = []
var map: Node2D
var checks: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	map = MAP.instantiate() as Node2D
	map.set("map_seed", 101)
	add_child(map)
	await get_tree().process_frame
	map.process_mode = Node.PROCESS_MODE_DISABLED
	var generator: MapGenerator = map.get("map_generator")
	var pathfinder: Pathfinding = map.get("pathfinding")
	for y: int in range(20, 56):
		for x: int in range(20, 56):
			generator.grid[y][x] = MapData.TileType.GRASS
			pathfinder.update_tile(Vector2i(x, y), MapData.TileType.GRASS)
	_run_focused_encounters()
	_run_stationary_lanes()
	_run_corner_encounters()
	_run_segment_guards()
	_run_worker_approaches()
	for left_kind: int in KINDS:
		for right_kind: int in KINDS:
			for axis: int in 2:
				for gap: int in [1, 2]:
					_run_pair(left_kind, right_kind, axis, gap)
	var output: String = "res://output/polish-crowd-movement-2026-10-23"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var hashes: Dictionary = {}
	for source: String in ["scripts/units/unit_base.gd", "scripts/map/game_map.gd", "scripts/map/pathfinding.gd", "scripts/buildings/building_base.gd", "scripts/data/building_data.gd", "tools/test_crowd_movement_2026_10_23.gd"]:
		hashes[source] = FileAccess.get_sha256("res://" + source)
	FileAccess.open(output.path_join("routing.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Headless actual GameMap on synthetic cleared patch; free buildings and units, variable-delta movement. Point-navigation and crowd behavior evidence, not swept collision or native appearance.", "checks": checks, "failures": failures, "records": records, "encounters": encounters, "source_sha256": hashes}, "  ") + "\n")
	map.free()
	for failure: String in failures:
		push_error("[FAIL] crowd_movement_2026_10_23: " + failure)
	if failures.is_empty():
		print("[PASS] crowd_movement_2026_10_23: %d checks; 36 building-pair/orientation/gap layouts, 216 single-unit routes and 36 opposing mixed crowds" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_focused_encounters() -> void:
	var center := Vector2i(42, 42)
	for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 1)]:
		for kind: String in ["head_on", "overtaking", "settled_ally", "coincident_opposed", "coincident_parallel"]:
			var first: UnitBase = _unit(1, center - step * 2)
			var second: UnitBase = _unit(1, center + step * 2)
			var goals: Array = [map.call("tile_to_world", center + step * 3), map.call("tile_to_world", center - step * 3)]
			if kind == "overtaking":
				first.free()
				second.free()
				first = _unit(4, center - step * 4)
				second = _unit(5, center - step * 2)
				goals = [map.call("tile_to_world", center + step * 6), map.call("tile_to_world", center + step * 4)]
			elif kind == "settled_ally":
				second.position = map.call("tile_to_world", center)
				goals[1] = null
			elif kind.begins_with("coincident"):
				first.position = map.call("tile_to_world", center)
				second.position = first.position
				if kind == "coincident_parallel": goals[1] = map.call("tile_to_world", center + step * 4)
			var measured: Dictionary = _drive([first, second], goals, 24.0)
			measured.merge({"kind": kind, "direction": str(step)})
			encounters.append(measured)
			_expect(measured.arrivals == (1 if kind == "settled_ally" else 2) and measured.navigation_failures == 0, "focused friendly encounters retain arrival")
			if kind == "settled_ally":
				_expect(measured.minimum_pair_distance >= 10.0, "travellers pass settled allies without returning through their occupied waypoint")
			if kind == "head_on":
				_expect(measured.minimum_pair_distance >= 3.0, "opposing movers choose a side before their centers coincide")
			if kind == "coincident_parallel":
				_expect(measured.near_coincidence_pair_seconds < 0.1, "initially coincident parallel movers separate instead of travelling as one")
			first.free()
			second.free()

func _run_stationary_lanes() -> void:
	for size_kind: int in KINDS:
		for axis: int in 2:
			var first: BuildingBase = _building(size_kind, Vector2i(32, 32))
			var second_origin := Vector2i(33 + first.footprint.x, 32)
			if axis == 1: second_origin = Vector2i(32, 33 + first.footprint.y)
			var second: BuildingBase = _building(size_kind, second_origin)
			var lane: int = 32 + first.footprint.x
			var start := Vector2i(lane, 30)
			var finish := Vector2i(lane, 35 + first.footprint.y)
			var work := Vector2i(lane, 32 + first.footprint.y / 2)
			if axis == 1:
				start = Vector2i(30, lane)
				finish = Vector2i(35 + first.footprint.x, lane)
				work = Vector2i(32 + first.footprint.x / 2, lane)
			var settled: UnitBase = _unit(0, work)
			var mover: UnitBase = _unit(0, start)
			var result: Dictionary = _drive([settled, mover], [null, map.call("tile_to_world", finish)], 20.0)
			result.merge({"kind": "stationary_worker_in_one_tile_lane", "building": first.building_name, "axis": axis})
			encounters.append(result)
			_expect(result.arrivals == 1 and result.navigation_failures == 0, "stationary worker lane remains reachable")
			_expect(result.minimum_pair_distance >= 10.0, "travellers pass settled workers without center overlap in a one-tile lane")
			settled.free()
			mover.free()
			map.call("remove_building_obstacle", Vector2i(32, 32), first.footprint)
			map.call("remove_building_obstacle", second_origin, second.footprint)
			first.free()
			second.free()

func _run_corner_encounters() -> void:
	for kind: String in ["occupied_corner", "arriving_stream"]:
		var building: BuildingBase = _building(BuildingData.BuildingType.BARRACKS, Vector2i(35, 35))
		var settled: UnitBase = _unit(0, Vector2i(34, 34))
		var units: Array[UnitBase] = [settled]
		var goals: Array = [null]
		for index: int in 4:
			units.append(_unit(0, Vector2i(32 - index, 36)))
			goals.append(map.call("tile_to_world", Vector2i(36 + index, 32)))
		if kind == "occupied_corner":
			for index: int in 4:
				units.append(_unit(1, Vector2i(36 + index, 32)))
				goals.append(map.call("tile_to_world", Vector2i(32 - index, 36)))
		var measured: Dictionary = _drive(units, goals, 30.0)
		measured["kind"] = kind
		encounters.append(measured)
		_expect(measured.arrivals == units.size() - 1 and measured.navigation_failures == 0 and measured.remaining.is_empty(), "arriving and opposing traffic retains every destination around a blocked corner")
		for unit: UnitBase in units: unit.free()
		map.call("remove_building_obstacle", Vector2i(35, 35), building.footprint)
		building.free()

func _run_segment_guards() -> void:
	# Directly exercise the final movement safety boundary: neither a large
	# delta nor a waypoint shortcut may tunnel through a newly blocked cell or
	# squeeze diagonally between two cell corners. Canonical A* is unchanged.
	map.call("place_building_obstacle", Vector2i(44, 44), Vector2i.ONE)
	var unit: UnitBase = _unit(0, Vector2i(43, 44))
	var origin: Vector2 = unit.position
	var across_corner: Vector2 = map.call("tile_to_world", Vector2i(44, 43))
	unit._move_in_direction(across_corner - origin, 2.0, map)
	_expect(unit.position.is_equal_approx(origin), "movement cannot cut a blocked diagonal corner even with a large delta")
	unit.position = origin
	var through_solid: Vector2 = map.call("tile_to_world", Vector2i(45, 44))
	unit._move_in_direction(through_solid - origin, 2.0, map)
	_expect(unit.position.is_equal_approx(origin), "movement cannot tunnel across a solid tile to a walkable endpoint")
	map.call("remove_building_obstacle", Vector2i(44, 44), Vector2i.ONE)
	unit._move_in_direction(through_solid - origin, 2.0, map)
	_expect(unit.position.distance_to(origin) > 20.0, "opening the obstruction restores movement without a changed speed")
	unit.free()

func _run_worker_approaches() -> void:
	var fog: FogManager = map.get_node("FogOfWar")
	fog.set_script(load("res://tools/fixtures/polish_revealed_fog.gd"))
	fog.fog_layer = map.get_node("FogLayer")
	fog.refresh_visibility_now()
	for kind: String in ["gather", "build"]:
		var workers: Array[Villager] = []
		var targets: Array[Node2D] = []
		var origin: Vector2 = map.call("tile_to_world", Vector2i(38, 42))
		for index: int in 2:
			var worker: Villager = _unit(0, Vector2i(38, 42)) as Villager
			workers.append(worker)
			if kind == "gather":
				var resource := ResourceNode.new()
				resource.resource_type = "wood"
				resource.position = map.call("tile_to_world", Vector2i(42 + index, 38 - index))
				map.add_child(resource)
				targets.append(resource)
				_expect(worker.command_gather(resource), "real gather approach accepts a visible resource")
			else:
				var site: BuildingBase = _building(BuildingData.BuildingType.HOUSE, Vector2i(42 + index * 3, 38))
				site.start_construction()
				targets.append(site)
				worker.command_build(site)
		var elapsed: float = 0.0
		var travel_coincidence: float = 0.0
		for tick: int in 240:
			var delta: float = DELTAS[tick % DELTAS.size()]
			for worker: Villager in workers:
				var before: Vector2 = worker.position
				worker._process(delta)
				_expect(worker.position.distance_to(before) <= worker.speed * delta + 0.01, "work approach respects normal speed")
				_expect(map.call("is_tile_walkable", map.call("world_to_tile", worker.position)), "work approach stays outside building tiles")
			if workers[0]._navigation_active and workers[1]._navigation_active and workers[0].position.distance_to(workers[1].position) < 1.0:
				travel_coincidence += delta
			elapsed += delta
		for index: int in workers.size():
			_expect(workers[index].position.distance_to(origin) > 100.0, "gathering/building states follow their actual routes")
			if kind == "gather":
				_expect(workers[index].carried_amount > 0, "workers arrive and gather after separating")
			else:
				_expect((targets[index] as BuildingBase).build_progress > 0.0, "workers arrive and construct after separating")
			workers[index].free()
			if kind == "build":
				map.call("remove_building_obstacle", map.call("world_to_tile", targets[index].position), (targets[index] as BuildingBase).footprint)
			targets[index].free()
		_expect(travel_coincidence < 0.1, "working movers do not remain coincident while approaching jobs")
		encounters.append({"kind": kind, "travel_coincidence_seconds": travel_coincidence, "elapsed_seconds": elapsed})

func _run_pair(left_kind: int, right_kind: int, axis: int, gap: int) -> void:
	var left: BuildingBase = _building(left_kind, Vector2i(32, 32))
	var right_origin: Vector2i = Vector2i(32 + left.footprint.x + gap, 32)
	if axis == 1:
		right_origin = Vector2i(32, 32 + left.footprint.y + gap)
	var right: BuildingBase = _building(right_kind, right_origin)
	var length: int = maxi(left.footprint.y, right.footprint.y)
	var corridor: int = 32 + left.footprint.x
	var start_tile := Vector2i(corridor, 30)
	var end_tile := Vector2i(corridor, 32 + length + 2)
	if axis == 1:
		start_tile = Vector2i(30, corridor)
		end_tile = Vector2i(32 + length + 2, corridor)
	var route: PackedVector2Array = map.call("get_navigation_world_path", map.call("tile_to_world", start_tile), map.call("tile_to_world", end_tile))
	_expect(not route.is_empty(), "nonempty lane route")
	for point: Vector2 in route:
		var tile: Vector2i = map.call("world_to_tile", point)
		_expect(tile.x == corridor if axis == 0 else tile.y == corridor, "single-unit route uses the lane instead of detouring around buildings")
	var singles: Array[Dictionary] = []
	for role: int in SCENES.size():
		var unit: UnitBase = _unit(role, start_tile)
		var measured: Dictionary = _drive([unit], [map.call("tile_to_world", end_tile)], 15.0)
		measured["role"] = SCENES[role]
		measured["radius"] = (unit.collision_shape.shape as CircleShape2D).radius
		_expect(measured.arrivals == 1 and measured.navigation_failures == 0, "each role arrives through the open lane")
		singles.append(measured)
		unit.free()
	var crowd: Array[UnitBase] = []
	var destinations: Array[Vector2] = []
	for side: int in 2:
		for role: int in SCENES.size():
			var offset := Vector2i(0, role)
			if axis == 1: offset = Vector2i(role, 0)
			var origin: Vector2i = start_tile - offset if side == 0 else end_tile + offset
			var goal: Vector2i = end_tile + offset if side == 0 else start_tile - offset
			crowd.append(_unit(role, origin))
			destinations.append(map.call("tile_to_world", goal))
	var crowd_metrics: Dictionary = _drive(crowd, destinations, 45.0)
	# Record crowd capacity honestly; clearance guarantees a route, not a
	# particular throughput. Safety invariants are checked during every step.
	for unit: UnitBase in crowd:
		unit.free()
	var basis_x: Vector2 = map.call("tile_to_world", Vector2i(1, 0)) - map.call("tile_to_world", Vector2i.ZERO)
	var basis_y: Vector2 = map.call("tile_to_world", Vector2i(0, 1)) - map.call("tile_to_world", Vector2i.ZERO)
	var lane_width: float = absf(basis_x.cross(basis_y)) / (basis_y.length() if axis == 0 else basis_x.length()) * gap
	records.append({"left": left.building_name, "right": right.building_name, "axis": axis, "gap_tiles": gap, "perpendicular_world_width": lane_width, "single_units": singles, "opposing_crowd": crowd_metrics})
	map.call("remove_building_obstacle", Vector2i(32, 32), left.footprint)
	map.call("remove_building_obstacle", right_origin, right.footprint)
	left.free()
	right.free()

func _drive(units: Array, destinations: Array, maximum_seconds: float) -> Dictionary:
	var events: Dictionary = {"arrivals": 0, "navigation_failures": 0}
	var initial_positions: Array[Vector2] = []
	for index: int in units.size():
		var unit: UnitBase = units[index]
		initial_positions.append(unit.position)
		unit.arrived_at_destination.connect(func(_unit: UnitBase) -> void: events.arrivals += 1)
		unit.navigation_failed.connect(func(_unit: UnitBase, _goal: Vector2) -> void: events.navigation_failures += 1)
		if destinations[index] != null: unit.command_move(destinations[index])
	var elapsed: float = 0.0
	var tick: int = 0
	var minimum_pair_distance: float = INF
	var closest_pair: Dictionary = {}
	var severe_overlap_pair_seconds: float = 0.0
	var near_coincidence_pair_seconds: float = 0.0
	while elapsed < maximum_seconds:
		var delta: float = DELTAS[tick % DELTAS.size()]
		var moving: bool = false
		for unit: UnitBase in units:
			var before: Vector2 = unit.position
			unit._process(delta)
			_expect(unit.position.distance_to(before) <= unit.speed * delta + 0.01, "movement respects speed without teleporting")
			for sample: int in range(17):
				var phase: float = float(sample) / 16.0
				_expect(map.call("is_tile_walkable", map.call("world_to_tile", before.lerp(unit.position, phase))), "unit center never crosses a solid building tile")
			moving = moving or unit.current_state == UnitBase.State.MOVING
		for a: int in units.size():
			for b: int in range(a + 1, units.size()):
				var distance: float = units[a].position.distance_to(units[b].position)
				if distance < 8.0: severe_overlap_pair_seconds += delta
				if distance < 1.0: near_coincidence_pair_seconds += delta
				if distance < minimum_pair_distance:
					minimum_pair_distance = distance
					closest_pair = {"indices": [a, b], "states": [units[a].current_state, units[b].current_state], "positions": [str(units[a].position), str(units[b].position)], "elapsed": elapsed}
		elapsed += delta
		tick += 1
		if not moving: break
	var remaining: Array[Dictionary] = []
	for index: int in units.size():
		var unit: UnitBase = units[index]
		if destinations[index] != null and (unit.current_state == UnitBase.State.MOVING or unit.position.distance_to(destinations[index]) > 4.1):
			remaining.append({"role": SCENES[unit.unit_type] if unit.unit_type < SCENES.size() else str(unit.unit_type), "state": unit.current_state, "goal_distance": unit.position.distance_to(destinations[index]), "travelled": unit.position.distance_to(initial_positions[index]), "position": str(unit.position), "path_index": unit.path_index, "path": str(unit.path), "separation": str(unit._separation_vector), "stall_repaths": unit._navigation_stall_repaths, "stuck_timer": unit._stuck_timer})
	events.merge({"elapsed_seconds": elapsed, "remaining": remaining, "minimum_pair_distance": minimum_pair_distance if is_finite(minimum_pair_distance) else -1.0, "closest_pair": closest_pair, "severe_overlap_pair_seconds": severe_overlap_pair_seconds, "near_coincidence_pair_seconds": near_coincidence_pair_seconds})
	return events

func _building(kind: int, tile: Vector2i) -> BuildingBase:
	var building := BuildingBase.new()
	building.building_type = kind
	building.position = map.call("tile_to_world", tile)
	map.get_node("BuildingsContainer").add_child(building)
	building.complete_instantly()
	map.call("place_building_obstacle", tile, building.footprint)
	return building

func _unit(role: int, tile: Vector2i) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/" + SCENES[role] + ".tscn").instantiate()
	unit.position = map.call("tile_to_world", tile)
	map.get_node("UnitsContainer").add_child(unit)
	return unit

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)
