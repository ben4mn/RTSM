extends SceneTree
## Focused regression for production egress and rally separation.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const PLAYER_ID: int = 0
const UNIT_SCOUT: int = 4
const GAME_STATE_PLAYING: int = 2
const READY_FRAME_LIMIT: int = 900
const MAX_EGRESS_RING: int = 3

var _failures: Array[String] = []
var _game_manager: Node
var _resource_manager: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game_manager = root.get_node("GameManager")
	_resource_manager = root.get_node("ResourceManager")
	root.get_node("AudioManager").call("set_all_enabled", false)
	_game_manager.set("selected_map_seed", 424242)
	_game_manager.set("guided_opening_enabled", false)

	var main_scene: PackedScene = load(MAIN_SCENE_PATH)
	var match_scene: Node = main_scene.instantiate()
	root.add_child(match_scene)
	current_scene = match_scene
	if not await _wait_for(func() -> bool:
		var buildings_by_player: Array = match_scene.get("_player_buildings") as Array
		return (
			int(_game_manager.get("current_state")) == GAME_STATE_PLAYING
			and not (buildings_by_player[PLAYER_ID] as Array).is_empty()
		)
	):
		_expect(false, "main scene reaches PLAYING with a player production building")
		_finish(match_scene)
		return

	var game_map: Node2D = match_scene.get_node("GameMap") as Node2D
	var town_center: Node = _find_town_center(match_scene)
	if town_center == null:
		_expect(false, "player Town Center is available")
		_finish(match_scene)
		return
	var production_queue: Node = town_center.call("get_production_queue") as Node
	_game_manager.call("increase_population_cap", PLAYER_ID, 8)
	_resource_manager.call("add_resource", PLAYER_ID, "food", 1000)

	var initial_egress: Dictionary = match_scene.call("_resolve_production_egress", town_center)
	_expect(bool(initial_egress.get("valid", false)), "Town Center has an ordinary walkable egress")
	if not bool(initial_egress.get("valid", false)):
		_finish(match_scene)
		return
	var far_tile: Vector2i = _find_far_reachable_tile(
		game_map,
		initial_egress.get("world_position", town_center.get("global_position")),
		game_map.call("world_to_tile", town_center.get("global_position"))
	)
	_expect(far_tile.x >= 0, "test map has a far reachable rally tile")
	if far_tile.x < 0:
		_finish(match_scene)
		return

	_test_rally_acceptance_without_fog_leak(match_scene, game_map, town_center, far_tile)
	await _test_far_rally_spawn_and_movement(
		match_scene,
		game_map,
		town_center,
		production_queue,
		far_tile
	)
	_test_blocked_egress_fallback(
		match_scene,
		game_map,
		town_center,
		production_queue,
		far_tile
	)
	_finish(match_scene)


func _test_rally_acceptance_without_fog_leak(
	match_scene: Node,
	game_map: Node2D,
	town_center: Node,
	far_tile: Vector2i
) -> void:
	var fog: Node = game_map.get("fog_of_war") as Node
	var selection_manager: Node = game_map.get("selection_mgr") as Node
	selection_manager.call("select_single", town_center)

	var origin: Vector2i = game_map.call("world_to_tile", town_center.get("global_position"))
	var rally_before: Vector2 = town_center.get("rally_point") as Vector2
	_set_fog_state(fog, origin, MapData.FogState.VISIBLE)
	match_scene.call("_on_move_command", origin)
	_expect(
		(town_center.get("rally_point") as Vector2).distance_to(rally_before) < 0.01,
		"a visible solid tile is rejected as a rally destination"
	)
	_expect(not bool(town_center.call("has_custom_rally_point")), "rejected rally does not become custom")

	var far_was_walkable: bool = bool(game_map.call("is_tile_walkable", far_tile))
	var old_far_fog: int = int((fog.get("fog_grid") as Array)[far_tile.y][far_tile.x])
	(game_map.get("pathfinding") as RefCounted).call("set_solid", far_tile, true)
	_set_fog_state(fog, far_tile, MapData.FogState.UNEXPLORED)
	match_scene.call("_on_move_command", far_tile)
	var far_world: Vector2 = game_map.call("tile_to_world", far_tile)
	_expect(
		(town_center.get("rally_point") as Vector2).distance_to(far_world) < 0.01,
		"an unseen rally tile is accepted without leaking its hidden blocker"
	)
	(game_map.get("pathfinding") as RefCounted).call("set_solid", far_tile, not far_was_walkable)
	_set_fog_state(fog, far_tile, old_far_fog)


func _test_far_rally_spawn_and_movement(
	match_scene: Node,
	game_map: Node2D,
	town_center: Node,
	production_queue: Node,
	far_tile: Vector2i
) -> void:
	var far_world: Vector2 = game_map.call("tile_to_world", far_tile)
	town_center.call("set_rally_point", far_world)
	var player_units: Array = (match_scene.get("_player_units") as Array)[PLAYER_ID]
	var units_before: int = player_units.size()
	_expect(bool(production_queue.call("enqueue_unit", UNIT_SCOUT)), "far-rally Scout queues")
	production_queue.call("_complete_current_unit")
	_expect_eq(player_units.size(), units_before + 1, "far-rally completion spawns one unit")
	if player_units.size() != units_before + 1:
		return

	var scout: Node2D = player_units.back() as Node2D
	var spawn_position: Vector2 = scout.global_position
	var spawn_tile: Vector2i = game_map.call("world_to_tile", spawn_position)
	var origin: Vector2i = game_map.call("world_to_tile", town_center.get("global_position"))
	var footprint: Vector2i = town_center.get("footprint") as Vector2i
	var spawn_ring: int = _footprint_ring(spawn_tile, origin, footprint)
	_expect_eq(spawn_ring, 1, "ordinary production starts on the adjacent perimeter ring")
	_expect(bool(game_map.call("is_tile_walkable", spawn_tile)), "ordinary production egress is walkable")
	_expect(spawn_position.distance_to(far_world) > 128.0, "far rally is never used as the spawn origin")
	_expect_eq(int(scout.get("current_state")), 1, "spawned unit receives a rally movement order")
	var scout_path: PackedVector2Array = scout.get("path") as PackedVector2Array
	_expect(not scout_path.is_empty(), "rally movement starts with a bounded navigation route")
	if not scout_path.is_empty():
		var destination_tile: Vector2i = game_map.call("world_to_tile", scout_path[scout_path.size() - 1])
		_expect(bool(game_map.call("is_tile_walkable", destination_tile)), "rally route ends on a valid walkable tile")

	for _step: int in range(80):
		scout.call("_process", 0.05)
		if scout.global_position.distance_to(spawn_position) >= 24.0:
			break
	_expect(scout.global_position.distance_to(spawn_position) >= 24.0, "spawned unit navigates away from its egress")
	_expect(
		scout.global_position.distance_to(far_world) < spawn_position.distance_to(far_world),
		"spawned unit makes progress toward the rally"
	)


func _test_blocked_egress_fallback(
	match_scene: Node,
	game_map: Node2D,
	town_center: Node,
	production_queue: Node,
	far_tile: Vector2i
) -> void:
	var pathfinding: RefCounted = game_map.get("pathfinding") as RefCounted
	var origin: Vector2i = game_map.call("world_to_tile", town_center.get("global_position"))
	var footprint: Vector2i = town_center.get("footprint") as Vector2i
	var restored_walkability: Dictionary = {}
	_set_perimeter_solid(pathfinding, origin, footprint, 1, restored_walkability)
	var fallback: Dictionary = match_scene.call("_resolve_production_egress", town_center)
	_expect(bool(fallback.get("valid", false)), "blocked adjacent ring uses a bounded legal fallback")
	var fallback_ring: int = int(fallback.get("ring", 0))
	_expect(
		fallback_ring >= 2 and fallback_ring <= MAX_EGRESS_RING,
		"fallback remains within the configured three-tile bound"
	)

	var player_units: Array = (match_scene.get("_player_units") as Array)[PLAYER_ID]
	var units_before_fallback: int = player_units.size()
	town_center.call("set_rally_point", game_map.call("tile_to_world", far_tile))
	_expect(bool(production_queue.call("enqueue_unit", UNIT_SCOUT)), "fallback Scout queues")
	production_queue.call("_complete_current_unit")
	_expect_eq(player_units.size(), units_before_fallback + 1, "bounded fallback still spawns the trained unit")
	if player_units.size() == units_before_fallback + 1:
		var fallback_scout: Node2D = player_units.back() as Node2D
		var fallback_tile: Vector2i = game_map.call("world_to_tile", fallback_scout.global_position)
		_expect_eq(
			_footprint_ring(fallback_tile, origin, footprint),
			fallback_ring,
			"spawn uses the resolved fallback ring"
		)
		_expect(bool(game_map.call("is_tile_walkable", fallback_tile)), "fallback spawn tile is walkable")
		_expect(fallback_scout.global_position.distance_to(town_center.get("rally_point")) > 96.0, "fallback never teleports to rally")

	for ring: int in range(2, MAX_EGRESS_RING + 1):
		_set_perimeter_solid(pathfinding, origin, footprint, ring, restored_walkability)
	var sealed_result: Dictionary = match_scene.call("_resolve_production_egress", town_center)
	_expect(not bool(sealed_result.get("valid", false)), "fully sealed bounded search reports no egress")
	var units_before_sealed: int = player_units.size()
	var population_before_sealed: int = int((_game_manager.get("players") as Dictionary)[PLAYER_ID].get("population", 0))
	var food_before_sealed: int = int(_resource_manager.call("get_resource", PLAYER_ID, "food"))
	var gold_before_sealed: int = int(_resource_manager.call("get_resource", PLAYER_ID, "gold"))
	_expect(bool(production_queue.call("enqueue_unit", UNIT_SCOUT)), "sealed-egress Scout queues")
	production_queue.call("_complete_current_unit")
	_expect_eq(player_units.size(), units_before_sealed, "sealed producer creates no unit at a remote rally")
	_expect_eq(
		int((_game_manager.get("players") as Dictionary)[PLAYER_ID].get("population", 0)),
		population_before_sealed,
		"sealed producer does not consume live population"
	)
	_expect_eq(
		int(_game_manager.call("get_reserved_population", PLAYER_ID)),
		0,
		"sealed producer releases the completion reservation"
	)
	_expect_eq(
		int(_resource_manager.call("get_resource", PLAYER_ID, "food")),
		food_before_sealed,
		"sealed producer refunds the trained unit food cost"
	)
	_expect_eq(
		int(_resource_manager.call("get_resource", PLAYER_ID, "gold")),
		gold_before_sealed,
		"sealed producer refunds the trained unit gold cost"
	)

	for tile: Vector2i in restored_walkability:
		pathfinding.call("set_solid", tile, not bool(restored_walkability[tile]))


func _set_perimeter_solid(
	pathfinding: RefCounted,
	origin: Vector2i,
	footprint: Vector2i,
	ring: int,
	restored_walkability: Dictionary
) -> void:
	var min_x: int = origin.x - ring
	var max_x: int = origin.x + footprint.x - 1 + ring
	var min_y: int = origin.y - ring
	var max_y: int = origin.y + footprint.y - 1 + ring
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			if x != min_x and x != max_x and y != min_y and y != max_y:
				continue
			var tile := Vector2i(x, y)
			if not restored_walkability.has(tile):
				restored_walkability[tile] = bool(pathfinding.call("is_walkable", tile))
			pathfinding.call("set_solid", tile, true)


func _find_far_reachable_tile(game_map: Node2D, start_world: Vector2, origin: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			var tile := Vector2i(x, y)
			if bool(game_map.call("is_tile_walkable", tile)):
				candidates.append(tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return origin.distance_squared_to(a) > origin.distance_squared_to(b)
	)
	var checks: int = mini(candidates.size(), 64)
	for index: int in range(checks):
		var tile: Vector2i = candidates[index]
		var route: PackedVector2Array = game_map.call(
			"get_navigation_world_path",
			start_world,
			game_map.call("tile_to_world", tile),
			4.0
		)
		if not route.is_empty() and origin.distance_squared_to(tile) >= 100:
			return tile
	return Vector2i(-1, -1)


func _footprint_ring(tile: Vector2i, origin: Vector2i, footprint: Vector2i) -> int:
	var max_footprint_x: int = origin.x + footprint.x - 1
	var max_footprint_y: int = origin.y + footprint.y - 1
	var dx: int = maxi(maxi(origin.x - tile.x, tile.x - max_footprint_x), 0)
	var dy: int = maxi(maxi(origin.y - tile.y, tile.y - max_footprint_y), 0)
	return maxi(dx, dy)


func _find_town_center(match_scene: Node) -> Node:
	var buildings: Array = (match_scene.get("_player_buildings") as Array)[PLAYER_ID]
	for building: Node in buildings:
		if int(building.get("building_type")) == 0:
			return building
	return null


func _set_fog_state(fog: Node, tile: Vector2i, state: int) -> void:
	var grid: Array = fog.get("fog_grid") as Array
	var row: Array = grid[tile.y] as Array
	row[tile.x] = state


func _wait_for(predicate: Callable) -> bool:
	for _frame: int in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await process_frame
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] production_rally_spawn: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_expect(false, "%s (expected %s, got %s)" % [message, expected, actual])


func _finish(match_scene: Node) -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(match_scene):
		match_scene.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] production_rally_spawn: adjacent spawn, routed far rally, fog-safe acceptance, bounded fallback, sealed failure")
		quit(0)
	else:
		quit(1)
