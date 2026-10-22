extends Node
## Actual GameMap conversion + A* + UnitBase motion; synthetic narrow terrain.

const GAME_MAP: PackedScene = preload("res://scenes/map/game_map.tscn")
const INFANTRY: PackedScene = preload("res://scenes/units/infantry.tscn")
const TOWN_CENTER: PackedScene = preload("res://scenes/buildings/town_center.tscn")
const PLANNER: Script = preload("res://scripts/main/group_order_planner.gd")
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	var game_map := GAME_MAP.instantiate() as Node2D
	game_map.set("map_seed", 202)
	add_child(game_map)
	await get_tree().process_frame
	game_map.set_process(false)
	(game_map.get_node("FogOfWar") as Node).set_process(false)
	var generator := MapGenerator.new(202)
	generator.call("_init_grid")
	var navigation := Pathfinding.new(generator)
	game_map.set("pathfinding", navigation)
	# A one-cell opening must be traversed, with units sharing waypoints but
	# ultimately occupying their own accepted destination slots.
	for y: int in MapData.MAP_HEIGHT:
		navigation.set_solid(Vector2i(20, y), y != 25)
	var units: Array[UnitBase] = []
	for i: int in 20:
		var unit := INFANTRY.instantiate() as UnitBase
		unit.position = game_map.tile_to_world(Vector2i(10 + i % 4, 22 + i / 4))
		unit.set_process(false)
		game_map.get_node("UnitsContainer").add_child(unit)
		units.append(unit)
	var orders: Array[Dictionary] = PLANNER.plan(game_map, units, Vector2i(30, 25))
	for order: Dictionary in orders:
		(order["unit"] as UnitBase).command_move_path(order["path"] as PackedVector2Array)
	var started: int = Time.get_ticks_usec()
	var simulated: float = 0.0
	for tick: int in 1800:
		var moving: int = 0
		for unit: UnitBase in units:
			unit._process(1.0 / 30.0)
			if unit.current_state == UnitBase.State.MOVING:
				moving += 1
			_expect(navigation.is_walkable(game_map.world_to_tile(unit.position)), "congested units stay on walkable terrain")
		simulated = float(tick + 1) / 30.0
		if moving == 0:
			break
	var arrived: int = 0
	var nearest_spacing: float = INF
	for i: int in units.size():
		if units[i].position.distance_to(units[i].move_target) <= UnitBase.NAVIGATION_POINT_TOLERANCE + 0.1:
			arrived += 1
		for j: int in range(i + 1, units.size()):
			nearest_spacing = minf(nearest_spacing, units[i].position.distance_to(units[j].position))
	_expect(arrived == units.size(), "every unit reaches its formation slot through one-cell gap")
	_expect(nearest_spacing > 24.0, "final formation does not collapse into stacked units")
	print("[METRIC] live_congestion ", JSON.stringify({"units": units.size(), "arrived": arrived, "simulated_seconds": simulated, "cpu_ms": float(Time.get_ticks_usec() - started) / 1000.0, "minimum_final_spacing": nearest_spacing}))
	for unit: UnitBase in units:
		unit.free()
	# Live obstacle changes invalidate navigation while preserving command intent.
	var mover := INFANTRY.instantiate() as UnitBase
	mover.position = game_map.tile_to_world(Vector2i(10, 10))
	mover.set_process(false)
	game_map.get_node("UnitsContainer").add_child(mover)
	mover.command_move(game_map.tile_to_world(Vector2i(16, 10)))
	mover._process(0.1)
	var revision: int = navigation.walkability_revision
	var next_waypoint: Vector2i = game_map.world_to_tile(mover.path[mover.path_index])
	navigation.set_solid(next_waypoint, true)
	_expect(navigation.walkability_revision == revision + 1, "actual blocker change increments revision")
	navigation.set_solid(next_waypoint, true)
	_expect(navigation.walkability_revision == revision + 1, "unchanged blocker does not invalidate caches")
	for tick: int in 600:
		mover._process(1.0 / 30.0)
		if mover.current_state == UnitBase.State.IDLE:
			break
	_expect(mover.position.distance_to(mover.move_target) <= 4.1, "unit reroutes around newly placed blocking building tile")
	mover.free()
	_test_building_far_edge_attack(game_map, navigation)
	game_map.free()
	for failure: String in _failures:
		push_error("[FAIL] navigation_live_congestion: " + failure)
	if _failures.is_empty():
		print("[PASS] navigation_live_congestion: 20 real A* movers through a one-cell gap, unique arrivals, live route changes")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _test_building_far_edge_attack(game_map: Node2D, navigation: Pathfinding) -> void:
	var anchor := Vector2i(30, 30)
	var building := TOWN_CENTER.instantiate() as BuildingBase
	building.player_owner = 1
	building.position = game_map.tile_to_world(anchor)
	building.set_process(false)
	game_map.get_node("BuildingsContainer").add_child(building)
	building.complete_instantly()
	var size: Vector2i = building.footprint
	var open_edge := anchor + Vector2i(0, size.y)
	for y: int in range(-1, size.y + 1):
		for x: int in range(-1, size.x + 1):
			var tile := anchor + Vector2i(x, y)
			navigation.set_solid(tile, tile != open_edge)
	var fog: FogManager = game_map.get_node("FogOfWar") as FogManager
	for y: int in range(anchor.y - 1, anchor.y + size.y + 2):
		for x: int in range(anchor.x - 1, anchor.x + size.x + 2):
			fog.fog_grid[y][x] = MapData.FogState.VISIBLE
	var attacker := INFANTRY.instantiate() as UnitBase
	attacker.position = game_map.tile_to_world(open_edge + Vector2i(0, 3))
	attacker.set_process(false)
	game_map.get_node("UnitsContainer").add_child(attacker)
	attacker.command_attack_building(building)
	var hp_before: int = building.hp
	for tick: int in 600:
		attacker._process(1.0 / 30.0)
		if building.hp < hp_before:
			break
	_expect(building.hp < hp_before, "military attacks large building from reachable far footprint edge")
	_expect(navigation.is_walkable(game_map.world_to_tile(attacker.position)), "building attacker remains outside its solid footprint")
	attacker.free()
	building.free()

func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
