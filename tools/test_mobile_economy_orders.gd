extends Node
## Focused route and cargo fixtures; real Villager/BuildingBase accounting and
## command lifecycle. Scripted navigation costs isolate shortest-route decisions.

class RouteRevision extends RefCounted:
	var walkability_revision: int = 0

class RouteMap extends Node2D:
	var pathfinding: RouteRevision = RouteRevision.new()
	var routes: Dictionary = {}
	func get_navigation_world_path(_origin: Vector2, target: Vector2, _radius: float) -> PackedVector2Array:
		return routes.get(target, PackedVector2Array([target]))
	func get_building_work_world_path(origin: Vector2, target: Vector2, _footprint: Vector2i, radius: float) -> PackedVector2Array:
		return get_navigation_world_path(origin, target, radius)
	func get_building_work_distance(origin: Vector2, target: Vector2, _footprint: Vector2i) -> float:
		return origin.distance_to(target)

var failures: Array[String] = []
var world: RouteMap

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	world = RouteMap.new()
	add_child(world)
	var worker: Villager = load("res://scenes/units/villager.tscn").instantiate()
	world.add_child(worker)
	worker.set_process(false)
	var gold: ResourceNode = _resource("gold")
	var food: ResourceNode = _resource("food")
	worker.carried_resource_type = "wood"
	worker.carried_amount = 7
	_expect(worker.command_gather(gold), "partial wood cargo accepts a gold assignment")
	_expect(worker.current_state == UnitBase.State.GATHERING and worker.gather_target == gold, "gold becomes the immediate task without an old dropoff detour")
	_expect(worker.get_carried_resources() == {"wood": 7}, "retask neither renames nor destroys wood")
	worker.call("_process_gathering", 0.91)
	_expect(worker.get_carried_resources() == {"wood": 7, "gold": 1}, "mixed resources occupy a common cargo bag")
	_expect(worker.command_gather(food), "a second retask replaces the first immediately")
	worker.call("_process_gathering", 0.76)
	_expect(worker.get_carried_resources() == {"wood": 7, "gold": 1, "food": 1}, "three resource switches conserve every harvested resource")
	var nearer: BuildingBase = _camp(Vector2(100, 0))
	world.routes[nearer.position] = PackedVector2Array([Vector2(0, 500), Vector2(100, 500), nearer.position])
	var shorter: BuildingBase = _camp(Vector2(150, 0))
	var incompatible: BuildingBase = _camp(Vector2(10, 0))
	incompatible.drop_off_resources = ["food"]
	var hostile: BuildingBase = _camp(Vector2(20, 0))
	hostile.player_owner = 1
	var unfinished: BuildingBase = _camp(Vector2(30, 0))
	unfinished.state = BuildingBase.State.CONSTRUCTING
	var sealed: BuildingBase = _camp(Vector2(40, 0))
	world.routes[sealed.position] = PackedVector2Array()
	_expect(worker.command_return_resources(), "mixed cargo can request a normal delivery")
	_expect(worker.dropoff_target == shorter, "dropoff chooses shortest reachable path, rejecting enemy, unfinished, incompatible and sealed buildings")
	var new_camp: BuildingBase = _camp(Vector2(60, 0))
	worker.call("_process_moving", 0.01)
	_expect(worker.dropoff_target == new_camp, "a newly completed nearer camp reroutes an active delivery")
	world.routes[new_camp.position] = PackedVector2Array()
	world.pathfinding.walkability_revision += 1
	worker.call("_process_moving", 1.01)
	_expect(worker.dropoff_target == shorter, "route topology changes invalidate the active camp and unreachable cache")
	worker.global_position = shorter.global_position
	worker.call("_on_arrived_for_dropoff", worker)
	_expect(ResourceManager.get_all_resources(0) == {"food": 1, "wood": 7, "gold": 1}, "one deposit accounts for each cargo type exactly")
	_expect(worker.carried_amount == 0 and worker.get_economy_task() == "food", "deposit resumes the newest assignment")
	worker.global_position = Vector2.ZERO
	worker.gather_rate = 100.0
	worker.call("_process_gathering", 0.76)
	_expect(worker.carried_amount == UnitData.VILLAGER_CARRY_CAPACITY, "mixed cargo uses the ordinary shared capacity limit")
	worker.command_move(Vector2(400, 0))
	worker.call("_on_arrived_for_dropoff", worker)
	_expect(worker.carried_amount == UnitData.VILLAGER_CARRY_CAPACITY, "a newer move cancels old delivery callbacks without losing cargo")
	world.free()
	_test_perimeter_route_choice()
	if failures.is_empty():
		print("[PASS] mobile_economy_orders: instant mixed-cargo retasks, shortest compatible reachable routes, camp and topology updates, exact deposits, capacity and command supersession")
		get_tree().quit(0)
	else:
		for message: String in failures: push_error("[FAIL] mobile_economy_orders: " + message)
		get_tree().quit(1)

func _resource(resource_type: String) -> ResourceNode:
	var node: ResourceNode = load("res://scenes/map/resource_node.tscn").instantiate()
	node.resource_type = resource_type
	world.add_child(node)
	return node

func _camp(position: Vector2) -> BuildingBase:
	var camp: BuildingBase = load("res://scenes/buildings/resource_camp.tscn").instantiate()
	camp.position = position
	world.add_child(camp)
	camp.complete_instantly()
	camp.set_process(false)
	return camp

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _test_perimeter_route_choice() -> void:
	var game_map: Node2D = load("res://scripts/map/game_map.gd").new()
	var map_gen: MapGenerator = MapGenerator.new(424242)
	map_gen.call("_init_grid")
	var navigation: Pathfinding = Pathfinding.new(map_gen)
	game_map.set("map_generator", map_gen)
	game_map.set("pathfinding", navigation)
	for y: int in range(4, 17):
		navigation.set_solid(Vector2i(10, y), true)
	navigation.set_area_solid(Vector2i(12, 12), Vector2i(2, 2), true)
	var origin: Vector2 = game_map.call("tile_to_world", Vector2i(8, 12))
	var anchor: Vector2 = game_map.call("tile_to_world", Vector2i(12, 12))
	var first_edge: PackedVector2Array = game_map.call("get_building_work_world_path", origin, anchor, Vector2i(2, 2), 40.0)
	var shortest: PackedVector2Array = game_map.call("get_building_dropoff_world_path", origin, anchor, Vector2i(2, 2), 40.0)
	_expect(not shortest.is_empty(), "detoured camp has a reachable legal perimeter")
	_expect(_route_length(origin, shortest) < _route_length(origin, first_edge), "dropoff finds a shorter far-side route instead of the first reachable near-side edge")
	print("[METRIC] dropoff_perimeter_distance ", _route_length(origin, first_edge), " -> ", _route_length(origin, shortest))
	game_map.free()

func _route_length(origin: Vector2, route: PackedVector2Array) -> float:
	var length: float = 0.0
	for point: Vector2 in route:
		length += origin.distance_to(point)
		origin = point
	return length
