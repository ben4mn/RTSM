extends Node
## Isolated synthetic actor geometry plus real Main/network authority seams.
## This is not a paid match, rendered playthrough or a balance/performance claim.

const MARCH := preload("res://scripts/main/attack_march_cohesion.gd")
const PENDING := preload("res://scripts/main/pending_attack_march.gd")
const NETWORK := preload("res://scripts/network/network_match.gd")
const SCENES: Dictionary = {
	UnitData.UnitType.INFANTRY: preload("res://scenes/units/infantry.tscn"),
	UnitData.UnitType.ARCHER: preload("res://scenes/units/archer.tscn"),
	UnitData.UnitType.CAVALRY: preload("res://scenes/units/cavalry.tscn"),
	UnitData.UnitType.SIEGE: preload("res://scenes/units/siege.tscn"),
	UnitData.UnitType.VILLAGER: preload("res://scenes/units/villager.tscn"),
	UnitData.UnitType.SCOUT: preload("res://scenes/units/scout.tscn"),
}
var failures: Array[String] = []
var checks: int = 0
var container: Node2D

class NavigationMap extends Node2D:
	var visible_enemy: bool = false
	var requests: int = 0
	var reject_routes: bool = false
	func get_navigation_world_path(from: Vector2, to: Vector2, _radius: float = 4.0) -> PackedVector2Array:
		requests += 1
		if reject_routes:
			return PackedVector2Array()
		return PackedVector2Array([from, to])
	func is_entity_visible_to_player(entity: Node2D, owner: int = 0) -> bool:
		return entity.player_owner == owner or visible_enemy
	func world_to_tile(point: Vector2) -> Vector2i:
		return Vector2i(point / 16.0)
	func is_tile_walkable(_tile: Vector2i) -> bool:
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.selected_civilization = CivilizationData.Civilization.SUNSTRIDE_CLANS
	GameManager.selected_opponent_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	container = NavigationMap.new()
	add_child(container)
	_test_motion_and_gates()
	_test_route_length_boundary()
	await _test_lifecycle()
	_test_contact_release()
	_test_lazy_admission()
	container.free()
	await _test_authority_seams()
	for failure: String in failures:
		push_error("[FAIL] attack_march_cohesion: " + failure)
	print("ATTACK_MARCH_COHESION checks=%d failures=%s scope=isolated-synthetic-prototype" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _spawn(type: int, point: Vector2, owner: int = 0) -> UnitBase:
	var unit: UnitBase = (SCENES[type] as PackedScene).instantiate()
	unit.player_owner = owner
	unit.position = point
	container.add_child(unit)
	# Entering the tree enables a scripted _process; disable after _ready so
	# synthetic navigation timers survive until their explicit fixture step.
	unit.set_process(false)
	return unit


func _orders(units: Array[UnitBase], destination: Vector2 = Vector2(600, 0)) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: UnitBase in units:
		var goal: Vector2 = destination + Vector2(0, unit.position.y)
		var route := PackedVector2Array([unit.position, goal])
		unit.command_attack_move_path(route)
		result.append({"unit": unit, "path": route, "destination": goal})
	return result


func _clear() -> void:
	for child: Node in container.get_children():
		child.free()


func _test_motion_and_gates() -> void:
	for owner: int in [0, 1]:
		var warrior := _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO, owner)
		var rider := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48), owner)
		var native_speed: float = 110.0 if owner == 0 else 95.0
		_expect(rider.speed == native_speed and warrior.speed == 55.0, "fixture uses actual civilization base speeds")
		var orders: Array[Dictionary] = _orders([warrior, rider])
		var routes: Array[PackedVector2Array] = [warrior.path.duplicate(), rider.path.duplicate()]
		var march: RefCounted = MARCH.attach_orders(orders)
		_expect(march != null and rider.get_movement_speed() == 55.0, "coherent mixed attack march caps cavalry for both owners")
		warrior.call("_move_in_direction", Vector2(600, 0), 1.0, null)
		rider.call("_move_in_direction", Vector2(600, 0), 1.0, null)
		_expect(is_equal_approx(warrior.position.x, 55.0) and is_equal_approx(rider.position.x, 55.0), "actual movement displacement keeps parallel coherent members together")
		_expect(rider.speed == native_speed and warrior.path == routes[0] and rider.path == routes[1], "march never rewrites public speed or accepted route")
		for index: int in 20:
			rider.get_movement_speed()
			warrior.get_movement_speed()
		_expect(int(march.get("member_scans")) == 1, "all unchanged members share one cached member scan in the frame")
		rider.command_move(Vector2(600, 48))
		_expect(rider.get_movement_speed() == native_speed and rider.get_attack_march() == null, "ordinary Move immediately restores native cavalry speed")
		_clear()
	var cavalry_a := _spawn(UnitData.UnitType.CAVALRY, Vector2.ZERO)
	var cavalry_b := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48))
	_expect(MARCH.attach_orders(_orders([cavalry_a, cavalry_b])) == null, "homogeneous cavalry need no speed-cap token")
	_expect(MARCH.attach_orders(_orders([cavalry_a])) == null, "single-unit attack move remains native")
	_clear()
	var warrior := _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
	var rider := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 180))
	_expect(MARCH.attach_orders(_orders([warrior, rider])) == null, "dispersed reinforcements do not form a march")
	rider.position = Vector2(0, 48)
	var divergent: Array[Dictionary] = _orders([warrior, rider])
	divergent[0].path = PackedVector2Array([warrior.position, Vector2(300, 250), Vector2(600, 0)])
	divergent[1].path = PackedVector2Array([rider.position, Vector2(300, -202), Vector2(600, 48)])
	warrior.command_attack_move_path(divergent[0].path)
	rider.command_attack_move_path(divergent[1].path)
	_expect(MARCH.attach_orders(divergent) == null, "split obstacle corridors are excluded even with equal route lengths")
	var blocked: Array[Dictionary] = _orders([warrior, rider])
	blocked[0].path = PackedVector2Array()
	_expect(MARCH.attach_orders(blocked) == null, "unreachable blind route does not establish a march")
	var worker := _spawn(UnitData.UnitType.VILLAGER, Vector2(0, 80))
	var scout := _spawn(UnitData.UnitType.SCOUT, Vector2(0, 110))
	MARCH.attach_orders(_orders([warrior, rider, worker, scout]))
	_expect(worker.get_attack_march() == null and scout.get_attack_march() == null and worker.get_movement_speed() == worker.speed and scout.get_movement_speed() == scout.speed, "workers and unarmed Scouts never join or inherit a cap")
	_clear()
	warrior = _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
	var siege := _spawn(UnitData.UnitType.SIEGE, Vector2(0, 48))
	MARCH.attach_orders(_orders([warrior, siege]))
	_expect(siege.speed == 30.0 and warrior.get_movement_speed() == 30.0, "deliberately selected siege imposes its actual strategic march speed")
	_clear()



func _test_route_length_boundary() -> void:
	_expect(MARCH.MAX_ROUTE_LENGTH_DIFFERENCE == 128.0, "v2 changes only the absolute spread limit to 128")
	var warrior := _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
	var rider := _spawn(UnitData.UnitType.CAVALRY, Vector2(-128.0, 0.0))
	var orders: Array[Dictionary] = _orders([warrior, rider])
	var spread: float = MARCH._route_length(rider.path) - MARCH._route_length(warrior.path)
	_expect(is_equal_approx(spread, 128.0), "boundary fixture establishes exactly 128 accepted route-length difference")
	var march: RefCounted = MARCH.attach_orders(orders)
	_expect(march != null and warrior.get_attack_march() == rider.get_attack_march() and rider.get_movement_speed() == 55.0, "exact 128 spread remains admitted inside unchanged corridor/direction gates")
	_clear()
	warrior = _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
	rider = _spawn(UnitData.UnitType.CAVALRY, Vector2(-126.0, 0.0))
	orders = _orders([warrior, rider])
	# A 1.5-unit accepted backtrack adds 3 units to the 726 direct route. Its
	# endpoint/corridor/direction still pass; only the 129 length spread rejects.
	var route := PackedVector2Array([rider.position, Vector2(-127.5, 0.0), Vector2(600.0, 0.0)])
	orders[1].path = route
	rider.command_attack_move_path(route)
	spread = MARCH._route_length(route) - MARCH._route_length(warrior.path)
	var a: PackedVector2Array = MARCH._sample_route(warrior.path, MARCH._route_length(warrior.path))
	var b: PackedVector2Array = MARCH._sample_route(route, MARCH._route_length(route))
	var widest: float = 0.0
	for index: int in MARCH.ROUTE_SAMPLES + 1:
		widest = maxf(widest, a[index].distance_to(b[index]))
	var dot: float = (a[1] - a[0]).normalized().dot((b[1] - b[0]).normalized())
	_expect(is_equal_approx(spread, 129.0) and widest <= MARCH.START_DIAMETER and dot >= 0.7 and rider.path == route, "explicit 129 detour fixture isolates length rejection from unchanged geometry/identity gates")
	_expect(MARCH.attach_orders(orders) == null, "129 route-length spread still rejects despite a common corridor")
	_expect(rider.get_attack_march() == null and rider.get_movement_speed() == rider.speed, "rejected 129 route keeps native cavalry movement")
	print("V2_ROUTE_BOUNDARY ", JSON.stringify({"accepted_spread": 128.0, "rejected_spread": spread, "rejected_max_sample_distance": widest, "rejected_direction_dot": dot}))
	_clear()


func _test_lifecycle() -> void:
	for action: String in ["stop", "patrol", "retask", "death", "arrival", "unreachable", "repath", "freed", "stalled"]:
		var warrior := _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
		var rider := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48))
		var second := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 96))
		var march: RefCounted = MARCH.attach_orders(_orders([warrior, rider, second]))
		_expect(march != null and rider.get_movement_speed() == 55.0, action + " starts with a live mixed cohort")
		match action:
			"stop": warrior.command_stop()
			"patrol": warrior.command_patrol(Vector2(500, 0))
			"retask": warrior.command_attack_move(Vector2(900, 0))
			"death": warrior.die()
			"arrival": warrior.call("_on_reached_destination")
			"unreachable": warrior.call("_on_navigation_unreachable", warrior.move_target)
			"repath": warrior.call("_request_navigation_path", container, warrior.move_target, 4.0, false)
			"freed": warrior.free()
			"stalled": warrior.set("_stuck_timer", 0.6)
		if action == "stop":
			_expect(rider.get_movement_speed() == 110.0 and second.get_movement_speed() == 110.0, "detaching the slowest member invalidates the cap in the same frame")
			_expect(int(march.get("member_scans")) == 2, "survivors share one additional scan after same-frame membership removal")
		if action == "stalled":
			_expect(not warrior.is_processing(), "synthetic stalled member remains frozen until the next shared scan")
		await get_tree().process_frame
		_expect(rider.get_movement_speed() == 110.0 and second.get_movement_speed() == 110.0, action + " cannot keep the remaining cavalry capped")
		var weak_march: WeakRef = weakref(march)
		march = null
		_clear()
		_expect(weak_march.get_ref() == null, "weak-member cohort releases when all actors are gone: " + action)


func _test_contact_release() -> void:
	var warrior := _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
	var rider := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48))
	var enemy := _spawn(UnitData.UnitType.INFANTRY, Vector2(50, 0), 1)
	var march: RefCounted = MARCH.attach_orders(_orders([warrior, rider]))
	container.visible_enemy = false
	warrior.command_attack(enemy, false)
	_expect(warrior.current_state == UnitBase.State.MOVING and rider.get_movement_speed() == 55.0, "unseen enemy alone cannot release the march or change intent")
	container.visible_enemy = true
	warrior.command_attack(enemy, false)
	_expect(warrior.current_state == UnitBase.State.ATTACKING and rider.get_movement_speed() == 110.0, "actual valid combat acquisition releases the entire group immediately")
	warrior.attack_target = null
	warrior.call("_resume_post_combat_movement")
	_expect(warrior.get_attack_march() == null and rider.get_attack_march() == null, "resuming attack-move after combat does not reform the march")
	MARCH.attach_orders(_orders([warrior, rider]))
	var before_hp: float = warrior.hp
	warrior.take_damage(1.0)
	_expect(warrior.hp == before_hp - 1.0 and rider.get_movement_speed() == 110.0, "actual HP loss releases all members")
	march = null
	_clear()


func _test_lazy_admission() -> void:
	container.visible_enemy = false
	var first_warrior := _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
	var first_rider := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48))
	var first_target := Vector2(600, 24)
	first_warrior.command_attack_move(first_target)
	first_rider.command_attack_move(first_target)
	PENDING.watch_wave([first_warrior, first_rider], first_target, 0)
	first_rider.call("_process_moving", 1.0 / 60.0)
	var native_first_step: float = first_rider.position.distance_to(Vector2(0, 48))
	_expect(is_equal_approx(native_first_step, 110.0 / 60.0) and first_rider.get_attack_march() == null, "first lazy mover takes one ordinary native-speed frame without waiting")
	first_warrior.call("_process_moving", 1.0 / 60.0)
	_expect(first_rider.get_movement_speed() == 55.0, "last lazy route acceptance activates the cap within the same frame")
	print("LAZY_MARCH_FIRST_STEP ", JSON.stringify({"dt": 1.0 / 60.0, "native_cavalry_step": native_first_step, "subsequent_speed_cap": first_rider.get_movement_speed(), "scope": "synthetic sequential member processing; no waiting or extra route query"}))
	_clear()
	for interruption: String in ["none", "same_target_retask", "damage", "stop", "failed_path", "expired", "freed"]:
		var warrior := _spawn(UnitData.UnitType.INFANTRY, Vector2.ZERO)
		var rider := _spawn(UnitData.UnitType.CAVALRY, Vector2(0, 48))
		var target := Vector2(600, 24)
		warrior.command_attack_move(target)
		rider.command_attack_move(target)
		var pending: RefCounted = PENDING.watch_wave([warrior, rider], target, 0)
		_expect(pending != null and warrior.get_pending_attack_march() == rider.get_pending_attack_march() and rider.get_movement_speed() == 110.0, "lazy candidate has no cap before navigation accepts paths: " + interruption)
		var requests: int = int(container.requests)
		warrior.call("_request_navigation_path", container, target, 4.0, false)
		warrior.call("_process_moving", 1.0 / 60.0)
		_expect(rider.get_attack_march() == null, "one accepted route alone cannot admit an AI wave")
		match interruption:
			"same_target_retask": warrior.command_attack_move(target)
			"damage": warrior.take_damage(1.0)
			"stop": warrior.command_stop()
			"failed_path": container.reject_routes = true
			"expired": GameManager.game_time += 1.1
			"freed": warrior.free()
		rider.call("_request_navigation_path", container, target, 4.0, false)
		container.reject_routes = false
		_expect(int(container.requests) == requests + 2, "pending admission must add zero planner queries")
		if interruption == "none":
			_expect(rider.get_attack_march() != null and rider.get_movement_speed() == 55.0, "all original accepted paths admit the same conservative cap")
		else:
			_expect(rider.get_attack_march() == null and rider.get_movement_speed() == 110.0, "pending admission aborts after " + interruption)
		_expect(rider.get_pending_attack_march() == null, "resolved or canceled pending ownership clears")
		var weak_pending: WeakRef = weakref(pending)
		pending = null
		_clear()
		_expect(weak_pending.get_ref() == null, "pending token owns no strong unit references")


func _test_authority_seams() -> void:
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	main.set_process(false)
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("StrategyController").set_process(false)
	var map: Node2D = main.get("game_map")
	map.set_process(false)
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var generator := MapGenerator.new(101)
	generator.call("_init_grid")
	map.set("pathfinding", Pathfinding.new(generator))
	container = map.get_node("UnitsContainer")
	var first := _spawn(UnitData.UnitType.INFANTRY, map.tile_to_world(Vector2i(20, 20)))
	var second := _spawn(UnitData.UnitType.CAVALRY, map.tile_to_world(Vector2i(21, 20)))
	main.get("_player_units")[0].append(first)
	main.get("_player_units")[0].append(second)
	map.selection_mgr.select_many([first, second] as Array[Node2D])
	main.call("_arm_attack_move_command")
	main.call("_on_move_command", Vector2i(30, 20))
	_expect(first.get_attack_march() != null and first.get_attack_march() == second.get_attack_march() and second.get_movement_speed() == 55.0, "real offline Main attaches the common cap after accepted planner routes")
	main.call("_arm_move_command")
	main.call("_on_move_command", Vector2i(31, 20))
	_expect(first.get_attack_march() == null and second.get_movement_speed() == 110.0, "real Main forced Move immediately detaches march intent")
	var adapter: Node = NETWORK.new()
	main.add_child(adapter)
	adapter.main = main
	adapter.game_map = map
	for owner: int in [0, 1]:
		var a: UnitBase = first if owner == 0 else _spawn(UnitData.UnitType.INFANTRY, map.tile_to_world(Vector2i(20, 22)), owner)
		var b: UnitBase = second if owner == 0 else _spawn(UnitData.UnitType.CAVALRY, map.tile_to_world(Vector2i(21, 22)), owner)
		if owner == 1:
			main.get("_player_units")[owner].append(a)
			main.get("_player_units")[owner].append(b)
		adapter.call("_register_server_entities")
		var goal: Vector2 = map.tile_to_world(Vector2i(30, 22))
		var ids: Array = [NetworkSession.entity_id(a), NetworkSession.entity_id(b)]
		var response: String = adapter.execute_command(owner, {"command": "attack_move", "ids": ids, "position": [goal.x, goal.y]})
		_expect(response.is_empty() and a.get_attack_march() != null and a.get_attack_march() == b.get_attack_march() and b.get_movement_speed() == 55.0, "NetworkMatch authority attaches the same rule for server owner %d" % owner)
		var token: RefCounted = a.get_attack_march()
		adapter.execute_command(1 - owner, {"command": "stop", "ids": ids})
		_expect(a.get_attack_march() == token, "foreign server slot cannot detach an owned cohort")
		adapter.execute_command(owner, {"command": "stop", "ids": ids})
		_expect(a.get_attack_march() == null and b.get_attack_march() == null, "authority Stop detaches every selected member")
		if owner == 1:
			var ai: Node = main.get_node("AIController")
			ai.call("_send_attack", [a, b], goal)
			_expect(a.get_pending_attack_march() != null and b.get_pending_attack_march() == a.get_pending_attack_march(), "fresh actual AI wave installs one pending cohort")
			a.call("_request_navigation_path", map, goal, 4.0, false)
			b.call("_request_navigation_path", map, goal, 4.0, false)
			_expect(a.get_attack_march() != null and a.get_attack_march() == b.get_attack_march() and b.get_movement_speed() == 55.0, "actual lazy AI routes use the same accepted-route admission")
			var retargeted: bool = bool(ai.call("_retarget_attack_wave", [a, b]))
			_expect(retargeted and a.get_attack_march() == null and a.get_pending_attack_march() == null and b.get_pending_attack_march() == null, "actual AI retarget refresh cannot reform an active or pending wave")
	main.free()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
