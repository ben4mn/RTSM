extends Node
## Actual GameMap/A* pursuit and bounded recovery when a runner is unreachable.

const GAME_MAP: PackedScene = preload("res://scenes/map/game_map.tscn")
const CAVALRY: PackedScene = preload("res://scenes/units/cavalry.tscn")
const INFANTRY: PackedScene = preload("res://scenes/units/infantry.tscn")
const STEP: float = 1.0 / 60.0
var _failures: Array[String] = []


class CountingPathfinding extends Pathfinding:
	var requests: int = 0

	func get_tile_path_to_any(from_tile: Vector2i, candidates: Array[Vector2i], max_path_checks: int = 32, recovery_radius: int = 4) -> Array[Vector2i]:
		requests += 1
		return super.get_tile_path_to_any(from_tile, candidates, max_path_checks, recovery_radius)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	get_tree().current_scene = null
	await _test_real_map_pursuit()
	await _test_live_pursuit_obstacle()
	await _test_unreachable_moving_target()
	for failure: String in _failures:
		push_error("[FAIL] moving_target_pursuit: " + failure)
	if _failures.is_empty():
		print("[PASS] moving_target_pursuit: faster pursuer sustains contact, bounded A* work, moving sealed target obeys retry cap")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _make_map() -> Node2D:
	var game_map := GAME_MAP.instantiate() as Node2D
	game_map.set("map_seed", 202)
	add_child(game_map)
	await get_tree().process_frame
	game_map.set_process(false)
	var fog := game_map.get_node("FogOfWar") as FogManager
	fog.set_process(false)
	var generator := MapGenerator.new(202)
	generator.call("_init_grid")
	game_map.set("pathfinding", CountingPathfinding.new(generator))
	for y: int in MapData.MAP_HEIGHT:
		for x: int in MapData.MAP_WIDTH:
			fog.fog_grid[y][x] = MapData.FogState.VISIBLE
	return game_map


func _test_real_map_pursuit() -> void:
	var game_map: Node2D = await _make_map()
	var navigation := game_map.get("pathfinding") as CountingPathfinding
	var origin: Vector2 = game_map.tile_to_world(Vector2i(20, 20))
	var attacker: UnitBase = _unit(game_map, CAVALRY, 0, origin)
	var target: UnitBase = _unit(game_map, INFANTRY, 1, origin + Vector2(160.0, 0.0))
	target.command_move(origin + Vector2(1000.0, 0.0))
	attacker.command_attack(target)
	var first_hit: float = -1.0
	var longest_wait: float = 0.0
	var current_wait: float = 0.0
	var started: int = Time.get_ticks_usec()
	for tick: int in 600:
		var previous: Vector2 = attacker.position
		target._process(STEP)
		attacker._process(STEP)
		_advance_impacts(attacker.get_parent())
		if first_hit < 0.0 and target.hp < target.max_hp:
			first_hit = float(tick + 1) * STEP
		var outside_reach: bool = attacker.position.distance_to(target.position) > attacker.attack_range + 8.0
		if outside_reach and attacker.position.distance_to(previous) < 0.001:
			current_wait += STEP
			longest_wait = maxf(longest_wait, current_wait)
		else:
			current_wait = 0.0
		_expect(navigation.is_walkable(game_map.world_to_tile(attacker.position)), "pursuer never leaves walkable terrain")
	var damage: float = target.max_hp - target.hp
	print("[METRIC] moving_target_pursuit ", JSON.stringify({"damage_10s": damage, "first_hit_seconds": first_hit, "longest_out_of_range_wait_seconds": longest_wait, "navigation_requests": navigation.requests, "cpu_ms": float(Time.get_ticks_usec() - started) / 1000.0}))
	_expect(damage >= 48.0, "faster cavalry sustains attacks on a moving infantry target")
	_expect(first_hit >= 0.0 and first_hit < 3.0, "pursuer connects after naturally closing the initial gap")
	_expect(longest_wait < 0.1, "expired target waypoints cannot introduce a stationary failure delay")
	_expect(navigation.requests <= 32, "brief weapon-range crossings reuse pursuit paths instead of repathing every frame")
	_expect(target.current_state == UnitBase.State.MOVING, "runner is still moving throughout the damage measurement")
	target.command_stop()
	for tick: int in 60:
		attacker._process(STEP)
		_advance_impacts(attacker.get_parent())
	_expect(attacker._navigation_active and not attacker.path.is_empty(), "in-range attacker keeps its accepted pursuit route internally")
	_expect(attacker.get_remaining_navigation_path().is_empty(), "stopped target cannot leave a visible chase route through an in-range fight")
	var settled_requests: int = navigation.requests
	for tick: int in 120:
		attacker._process(STEP)
		_advance_impacts(attacker.get_parent())
	_expect(navigation.requests == settled_requests, "in-range attacker does not request routes after its target stops")
	target.current_state = UnitBase.State.DEAD
	_expect(attacker.get_remaining_navigation_path().is_empty(), "dead target immediately disappears from route feedback")
	attacker._process(STEP)
	_expect(attacker.current_state == UnitBase.State.IDLE and attacker.attack_target == null, "target death settles explicit pursuit")
	_expect(not attacker._navigation_active and attacker.path.is_empty(), "target death clears retained navigation state")
	game_map.free()


func _test_unreachable_moving_target() -> void:
	var game_map: Node2D = await _make_map()
	var navigation := game_map.get("pathfinding") as CountingPathfinding
	for y: int in MapData.MAP_HEIGHT:
		navigation.set_solid(Vector2i(25, y), true)
	var attacker: UnitBase = _unit(game_map, CAVALRY, 0, game_map.tile_to_world(Vector2i(10, 20)))
	var target: UnitBase = _unit(game_map, INFANTRY, 1, game_map.tile_to_world(Vector2i(35, 20)))
	target.command_move(game_map.tile_to_world(Vector2i(35, 35)))
	target._process(STEP)
	var target_start: Vector2 = target.position
	navigation.requests = 0
	attacker.command_attack(target)
	var elapsed: float = 0.0
	for tick: int in 300:
		target._process(STEP)
		attacker._process(STEP)
		elapsed += STEP
		if attacker.current_state == UnitBase.State.IDLE:
			break
	_expect(target.position.distance_to(target_start) > 30.0, "unreachable target actually moves during failed pursuit")
	_expect(navigation.requests == UnitBase.NAVIGATION_MAX_FAILED_REPATHS, "moving unreachable target obeys the existing route retry cap")
	_expect(attacker.current_state == UnitBase.State.IDLE and attacker.attack_target == null, "failed explicit chase clears target and recovers to idle")
	_expect(elapsed < 3.0, "unreachable moving target cannot trap the command indefinitely")
	print("[METRIC] moving_target_unreachable ", JSON.stringify({"navigation_requests": navigation.requests, "seconds_to_idle": elapsed}))
	game_map.free()


func _test_live_pursuit_obstacle() -> void:
	var game_map: Node2D = await _make_map()
	var navigation := game_map.get("pathfinding") as CountingPathfinding
	var attacker: UnitBase = _unit(game_map, CAVALRY, 0, game_map.tile_to_world(Vector2i(10, 10)))
	var target: UnitBase = _unit(game_map, INFANTRY, 1, game_map.tile_to_world(Vector2i(16, 10)))
	attacker.command_attack(target)
	attacker._process(STEP)
	var blocked: Vector2i = game_map.world_to_tile(attacker.path[attacker.path_index])
	navigation.set_solid(blocked, true)
	for tick: int in 600:
		attacker._process(STEP)
		_advance_impacts(attacker.get_parent())
		_expect(navigation.is_walkable(game_map.world_to_tile(attacker.position)), "live pursuit reroute never enters the newly blocked tile")
		if target.hp < target.max_hp:
			break
	_expect(target.hp < target.max_hp, "pursuer invalidates blocked waypoints and reaches its target by another route")
	game_map.free()


func _unit(game_map: Node2D, scene: PackedScene, owner: int, at: Vector2) -> UnitBase:
	var unit := scene.instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = at
	game_map.get_node("UnitsContainer").add_child(unit)
	unit.set_process(false)
	if owner == 1:
		unit.damage = 0.0
		unit.max_hp = 10000.0
		unit.hp = 10000.0
	return unit


func _advance_impacts(container: Node) -> void:
	for child: Node in container.get_children():
		if child.has_method("advance_committed_hit"):
			child.call("advance_committed_hit")
			child.free()


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
