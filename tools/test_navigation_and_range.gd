extends Node
## Focused MOVE-001 / COMBAT-002 regression.
## Run through: Godot --headless --path . tools/test_navigation_and_range.tscn

const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const INFANTRY_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/watch_tower.tscn")

var _failures: Array[String] = []


class FakeNavigationMap extends Node2D:
	var reject_routes: bool = false
	var path_requests: int = 0

	func get_navigation_world_path(
		from_world: Vector2,
		target_world: Vector2,
		_arrival_radius_world: float = 4.0,
		_max_goal_radius_tiles: int = 6
	) -> PackedVector2Array:
		path_requests += 1
		if reject_routes:
			return PackedVector2Array()
		return PackedVector2Array([
			from_world,
			Vector2(from_world.x, 48.0),
			Vector2(target_world.x, 48.0),
			target_world,
		])

	func world_to_tile(world_position: Vector2) -> Vector2i:
		return Vector2i(roundi(world_position.x / 16.0), roundi(world_position.y / 16.0))

	func is_tile_walkable(_tile: Vector2i) -> bool:
		return true

	func is_entity_visible_to_player(_entity: Node2D, _viewer_player_id: int = 0) -> bool:
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_path_detour_and_sealed_failure()
	_test_solid_start_and_solid_goal_recovery()
	_test_unit_navigation_retry_bound()
	_test_shared_range_conversion()
	_test_starting_town_center_reveals_food()
	_finish()


func _test_path_detour_and_sealed_failure() -> void:
	var pathfinding := _make_flat_pathfinding()
	for y in range(0, 11):
		if y != 6:
			pathfinding.set_solid(Vector2i(5, y), true)
	var detour: Array[Vector2i] = pathfinding.get_tile_path(Vector2i(2, 2), Vector2i(8, 2))
	_expect(not detour.is_empty(), "route detours through a barrier gap")
	_expect(detour.has(Vector2i(5, 6)), "detour uses the only barrier gap")
	for tile: Vector2i in detour:
		_expect(pathfinding.is_walkable(tile), "detour never contains a solid tile")

	var sealed := _make_flat_pathfinding()
	for y in range(MapData.MAP_HEIGHT):
		sealed.set_solid(Vector2i(5, y), true)
	var unreachable: Array[Vector2i] = sealed.get_tile_path_to_any(
		Vector2i(2, 2),
		[Vector2i(8, 2)],
		8
	)
	_expect(unreachable.is_empty(), "sealed destination returns failure instead of a direct path")


func _test_solid_start_and_solid_goal_recovery() -> void:
	var pathfinding := _make_flat_pathfinding()
	pathfinding.set_area_solid(Vector2i(2, 2), Vector2i(4, 4), true)
	var egress: Array[Vector2i] = pathfinding.get_tile_path_to_any(
		Vector2i(3, 3),
		[Vector2i(12, 12)],
		32,
		4
	)
	_expect(not egress.is_empty(), "unit under a 4x4 footprint gets a bounded egress route")
	if not egress.is_empty():
		_expect(pathfinding.is_walkable(egress[0]), "egress begins at a recovered walkable start")
		for tile: Vector2i in egress:
			_expect(pathfinding.is_walkable(tile), "egress A* route contains no solid tile")

	pathfinding.set_area_solid(Vector2i(12, 12), Vector2i(3, 3), true)
	var perimeter: Array[Vector2i] = pathfinding.get_walkable_tiles_near(Vector2i(12, 12), 3, 32)
	var approach: Array[Vector2i] = pathfinding.get_tile_path_to_any(Vector2i(8, 12), perimeter, 32)
	_expect(not approach.is_empty(), "solid building goal resolves to a reachable perimeter")
	if not approach.is_empty():
		_expect(pathfinding.is_walkable(approach[approach.size() - 1]), "building approach endpoint is walkable")


func _test_unit_navigation_retry_bound() -> void:
	var navigation_map := FakeNavigationMap.new()
	add_child(navigation_map)
	var container := Node2D.new()
	navigation_map.add_child(container)

	var moving_unit: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	container.add_child(moving_unit)
	moving_unit.command_move(Vector2(96.0, 0.0))
	var arrivals: Array[int] = [0]
	moving_unit.arrived_at_destination.connect(func(_unit: UnitBase) -> void: arrivals[0] += 1)
	for _step in range(160):
		moving_unit._process(0.05)
		if moving_unit.current_state == UnitBase.State.IDLE:
			break
	_expect_eq(arrivals[0], 1, "reachable route emits exactly one arrival")
	_expect(navigation_map.path_requests <= 2, "static movement does not continuously repath")

	navigation_map.reject_routes = true
	navigation_map.path_requests = 0
	var blocked_unit: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	container.add_child(blocked_unit)
	var failures: Array[int] = [0]
	blocked_unit.navigation_failed.connect(func(_unit: UnitBase, _target: Vector2) -> void: failures[0] += 1)
	blocked_unit.command_move(Vector2(160.0, 0.0))
	for _step in range(100):
		blocked_unit._process(0.1)
		if blocked_unit.current_state == UnitBase.State.IDLE:
			break
	_expect_eq(navigation_map.path_requests, UnitBase.NAVIGATION_MAX_FAILED_REPATHS, "unreachable route obeys the retry cap")
	_expect_eq(failures[0], 1, "unreachable movement emits one failure")
	_expect(blocked_unit.global_position.distance_to(Vector2.ZERO) < 0.01, "unreachable movement never falls back through obstacles")

	moving_unit.free()
	blocked_unit.free()
	navigation_map.free()


func _test_shared_range_conversion() -> void:
	_expect_float(MapData.range_tiles_to_world(1.0), 16.0, "one canonical range tile is 16 world units")
	_expect_float(MapData.world_to_range_tiles(96.0), 6.0, "world-to-range conversion is reversible")
	var archer: UnitBase = ARCHER_SCENE.instantiate() as UnitBase
	var tower: BuildingBase = TOWER_SCENE.instantiate() as BuildingBase
	add_child(archer)
	add_child(tower)
	_expect_float(archer.attack_range, MapData.range_tiles_to_world(5.0), "archer range uses canonical conversion")
	_expect_float(tower.tower_attack_range, MapData.range_tiles_to_world(6.0), "tower range uses the same conversion")
	archer.free()
	tower.free()


func _test_starting_town_center_reveals_food() -> void:
	var town_center_vision: int = int(
		BuildingData.get_building_stats(BuildingData.BuildingType.TOWN_CENTER).get("vision_radius", 0)
	)
	_expect_eq(town_center_vision, 13, "Town Center uses the starting-pocket reveal radius")
	for seed_value in [101, 202, 303, 404, 505, 424242]:
		var generator := MapGenerator.new(seed_value)
		generator.generate()
		var spawn: Vector2i = generator.spawn_positions[0]
		var visible_food: int = 0
		for y in range(MapData.MAP_HEIGHT):
			for x in range(MapData.MAP_WIDTH):
				if generator.grid[y][x] != MapData.TileType.BERRY_BUSH:
					continue
				var delta := Vector2i(x, y) - spawn
				if delta.length_squared() <= town_center_vision * town_center_vision:
					visible_food += 1
		_expect(visible_food > 0, "seed %d reveals at least one starting food node" % seed_value)


func _make_flat_pathfinding() -> Pathfinding:
	var generator := MapGenerator.new(1)
	generator.grid.clear()
	for _y in range(MapData.MAP_HEIGHT):
		var row: Array = []
		row.resize(MapData.MAP_WIDTH)
		row.fill(MapData.TileType.GRASS)
		generator.grid.append(row)
	return Pathfinding.new(generator)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s (expected %.2f, got %.2f)" % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] navigation_and_range: detours, bounded failure, solid recovery, canonical ranges, and starting vision")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] navigation_and_range: %s" % failure)
	get_tree().quit(1)
