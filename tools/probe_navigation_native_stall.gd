extends Node
## Diagnostic replay of positions captured from the variable-step paid match.
const MAP: PackedScene = preload("res://scenes/map/game_map.tscn")
const UNIT: PackedScene = preload("res://scenes/units/infantry.tscn")
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	var map := MAP.instantiate() as Node2D
	map.set("map_seed", 101)
	add_child(map)
	await get_tree().process_frame
	map.set_process(false)
	map.get_node("FogOfWar").set_process(false)
	var fog: FogManager = map.get_node("FogOfWar") as FogManager
	for y: int in MapData.MAP_HEIGHT:
		for x: int in MapData.MAP_WIDTH:
			fog.fog_grid[y][x] = MapData.FogState.VISIBLE
	var pathfinder: Pathfinding = map.get("pathfinding")
	for spawn: Vector2i in (map.get("map_generator") as MapGenerator).spawn_positions:
		pathfinder.set_area_solid(spawn, Vector2i(4, 4))
	for item: Array in [[Vector2i(3, 62), Vector2i(2, 2)], [Vector2i(6, 61), Vector2i(3, 3)], [Vector2i(17, 69), Vector2i(2, 2)], [Vector2i(9, 63), Vector2i(2, 2)], [Vector2i(3, 67), Vector2i(2, 2)]]:
		pathfinder.set_area_solid(item[0], item[1])
	var position := Vector2(-1824.97314453125, 1133.34631347656)
	var target := Vector2(-1384.0, 1156.0)
	var tile: Vector2i = map.world_to_tile(position)
	var row: Dictionary = {"position": position, "tile": tile, "center": map.tile_to_world(tile), "spawn_positions": (map.get("map_generator") as MapGenerator).spawn_positions, "before_closure": map.get_navigation_world_path(position, target)}
	_expect(not (row.before_closure as PackedVector2Array).is_empty(), "original courtyard has a route before the Range closes it")
	var ai := AIController.new()
	ai.player_id = 0
	ai.game_map = map
	ai.pathfinding = pathfinder
	ai.map_generator = map.get("map_generator") as MapGenerator
	ai._base_tile = Vector2i(6, 65)
	for item: Array in [[Vector2i(6, 65), Vector2i(4, 4)], [Vector2i(3, 62), Vector2i(2, 2)], [Vector2i(6, 61), Vector2i(3, 3)], [Vector2i(17, 69), Vector2i(2, 2)], [Vector2i(9, 63), Vector2i(2, 2)], [Vector2i(3, 67), Vector2i(2, 2)]]:
		var building := BuildingBase.new()
		building.building_type = BuildingData.BuildingType.TOWN_CENTER if item[1] == Vector2i(4, 4) else (BuildingData.BuildingType.BARRACKS if item[1] == Vector2i(3, 3) else BuildingData.BuildingType.HOUSE)
		building.player_owner = 0
		building.position = map.tile_to_world(item[0])
		building.state = BuildingBase.State.ACTIVE
		map.get_node("BuildingsContainer").add_child(building)
		building.set_process(false)
		ai._my_buildings.append(building)
	_expect(not ai._is_valid_build_spot(Vector2i(3, 64), Vector2i(3, 3)), "automatic allocator rejects observed courtyard closure")
	var alternative: Vector2i = ai._find_build_location(BuildingData.BuildingType.ARCHERY_RANGE)
	row["automatic_range_alternative"] = alternative
	_expect(alternative != Vector2i(-1, -1), "same real map offers a spaced Range alternative")
	if alternative != Vector2i(-1, -1):
		pathfinder.set_area_solid(alternative, Vector2i(3, 3))
		_expect(not map.get_navigation_world_path(position, target).is_empty(), "automatic alternate preserves occupied courtyard egress")
		pathfinder.set_area_solid(alternative, Vector2i(3, 3), false)
	var placement := BuildingPlacement.new()
	map.add_child(placement)
	row["manual_closure_legal"] = placement.revalidate_confirmation(BuildingData.BuildingType.ARCHERY_RANGE, map.tile_to_world(Vector2i(3, 64)), 0)
	_expect(not row.manual_closure_legal, "player placement now also rejects the observed closing wall")
	placement.free()
	for building: Node in ai._my_buildings:
		building.free()
	ai.free()
	pathfinder.set_area_solid(Vector2i(3, 64), Vector2i(3, 3))
	row["after_closure"] = map.get_navigation_world_path(position, target)
	row["reachable_component"] = _component(pathfinder, tile)
	_expect((row.after_closure as PackedVector2Array).is_empty() and (row.reachable_component as Array).size() == 3, "manual Range creates the observed three-tile enclosure")
	var unit := UNIT.instantiate() as UnitBase
	unit.position = position
	unit.set_process(false)
	map.get_node("UnitsContainer").add_child(unit)
	var navigation_failures: Array[float] = []
	var elapsed: float = 0.0
	unit.navigation_failed.connect(func(_unit: UnitBase, _target: Vector2) -> void: navigation_failures.append(1.0))
	unit.command_move(target)
	for tick: int in 300:
		var delta: float = [1.0 / 60.0, 0.05, 0.0333, 0.08][tick % 4]
		unit._process(delta)
		elapsed += delta
		if unit.current_state == UnitBase.State.IDLE:
			break
	row["blocked_move_seconds"] = elapsed
	row["navigation_failures"] = navigation_failures.size()
	row["blocked_move_final"] = unit.position
	_expect(navigation_failures.size() == 1 and elapsed < 2.0 and unit.position.distance_to(position) < 0.01, "sealed movement fails once within its bound without crossing or teleporting")
	pathfinder.set_area_solid(Vector2i(3, 64), Vector2i(3, 3), false)
	row["after_reopening"] = map.get_navigation_world_path(unit.position, target)
	unit.command_move(target)
	for tick: int in 1800:
		var delta: float = [1.0 / 60.0, 0.05, 0.0333, 0.08][tick % 4]
		var before: Vector2 = unit.position
		unit._process(delta)
		_expect(map.is_tile_walkable(map.world_to_tile(unit.position)), "reopened route never enters a solid tile")
		_expect(unit.position.distance_to(before) <= unit.speed * delta + 0.01, "reopened route obeys movement speed without teleporting")
		if unit.current_state == UnitBase.State.IDLE:
			break
	row["reopened_move_final"] = unit.position
	row["reopened_target_distance"] = unit.position.distance_to(target)
	var reopened_route: PackedVector2Array = row.after_reopening
	_expect(not reopened_route.is_empty() and unit.position.distance_to(reopened_route[-1]) <= 4.1 and navigation_failures.size() == 1, "reopening restores normal arrival at the accepted legal endpoint")
	print(JSON.stringify(row))
	unit.free()
	pathfinder = Pathfinding.new(map.get("map_generator") as MapGenerator)
	map.set("pathfinding", pathfinder)
	for item: Array in [[Vector2i(6, 65), Vector2i(4, 4)], [Vector2i(3, 62), Vector2i(2, 2)], [Vector2i(6, 61), Vector2i(3, 3)], [Vector2i(9, 63), Vector2i(2, 2)], [Vector2i(3, 66), Vector2i(2, 2)], [Vector2i(3, 68), Vector2i(3, 3)], [Vector2i(10, 65), Vector2i(3, 3)], [Vector2i(10, 61), Vector2i(2, 2)], [Vector2i(3, 64), Vector2i(2, 2)]]:
		pathfinder.set_area_solid(item[0], item[1])
	position = Vector2(-1758.16662597656, 1073.64501953125)
	target = Vector2(-1856.0, 1152.0)
	row = {"case": "second native Tower closes northern entrance", "position": position, "tile": map.world_to_tile(position), "target_tile": map.world_to_tile(target), "before_closure": map.get_navigation_world_path(position, target)}
	pathfinder.set_solid(Vector2i(5, 62))
	row["after_closure"] = map.get_navigation_world_path(position, target)
	row["pocket_component"] = _component(pathfinder, Vector2i(5, 64))
	row["outside_to_open_ground"] = map.get_navigation_world_path(position, map.tile_to_world(Vector2i(12, 58)))
	row["inside_to_open_ground"] = map.get_navigation_world_path(Vector2(-1852.78015136719, 1121.60229492188), map.tile_to_world(Vector2i(12, 58)))
	_expect(not (row.before_closure as PackedVector2Array).is_empty() and (row.after_closure as PackedVector2Array).is_empty(), "second native Tower closes the formerly reachable target approaches")
	_expect((row.pocket_component as Array).size() == 8 and not (row.outside_to_open_ground as PackedVector2Array).is_empty() and (row.inside_to_open_ground as PackedVector2Array).is_empty(), "second native failures distinguish sealed pocket from open outside movement")
	print(JSON.stringify(row))
	map.free()
	for failure: String in self.failures:
		push_error("[FAIL] native_stall_replay: " + failure)
	if self.failures.is_empty():
		print("[PASS] native_stall_replay: real-map before/enclosed/reopened geometry, bounded variable-step failure, automatic and player spacing reject the closing wall")
	get_tree().quit(0 if self.failures.is_empty() else 1)


func _component(pathfinder: Pathfinding, start: Vector2i) -> Array[Vector2i]:
	var visited: Array[Vector2i] = [start]
	var index: int = 0
	while index < visited.size():
		var current: Vector2i = visited[index]
		index += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + step
			if pathfinder.is_walkable(next) and not visited.has(next):
				visited.append(next)
	return visited


func _expect(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
