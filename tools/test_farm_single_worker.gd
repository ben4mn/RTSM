extends Node
## Real Farm/Villager/AI APIs on a revealed grass fixture with real canonical
## routes and solid footprints. Manually stepped work is not an income benchmark.

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const TC_SCENE: PackedScene = preload("res://scenes/buildings/town_center.tscn")
const HOUSE_SCENE: PackedScene = preload("res://scenes/buildings/house.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const RESOURCE_SCENE: PackedScene = preload("res://scenes/map/resource_node.tscn")

class FarmMap extends "res://scripts/map/game_map.gd":
	func _ready() -> void:
		# The fixture omits visual tile generation; use GameMap's canonical
		# conversion fallback instead of an unconfigured TerrainLayer TileSet.
		terrain_layer = null
		set_process(false)

	func is_entity_visible_to_player(_entity: Node2D, _owner: int = 0) -> bool:
		return true

	func is_tile_visible_to_player(_tile: Vector2i, _owner: int = 0) -> bool:
		return true

var _failures: Array[String] = []
var _map: FarmMap
var _workers: Array[Villager] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	ResourceManager.initialize_player(1, {"food": 0, "wood": 0, "gold": 0})
	var map_scene: Node2D = load("res://scenes/map/game_map.tscn").instantiate() as Node2D
	map_scene.set_script(FarmMap)
	_map = map_scene as FarmMap
	_map.map_generator = MapGenerator.new(101)
	_map.map_generator.call("_init_grid")
	_map.pathfinding = Pathfinding.new(_map.map_generator)
	add_child(_map)
	var tc: BuildingBase = _building(TC_SCENE, Vector2i(22, 30))
	var farm: BuildingBase = _building(FARM_SCENE, Vector2i(30, 30))
	var other_farm: BuildingBase = _building(FARM_SCENE, Vector2i(35, 30))
	var wood: ResourceNode = _resource("wood", Vector2i(25, 35))
	var first: Villager = _worker(Vector2i(26, 31))
	var second: Villager = _worker(Vector2i(25, 35))
	var third: Villager = _worker(Vector2i(24, 35))
	_expect(second.command_gather(wood), "second worker starts its real wood job")
	second.call("_process_gathering", 0.11)
	var old_cargo: int = second.carried_amount
	_expect(old_cargo > 0, "rejected-order fixture must carry real wood")
	_expect(first.command_gather(farm), "first Farm order is accepted before travel")
	_expect(farm.get_assigned_worker() == first, "approaching farmer owns the only slot")
	_expect(not second.command_gather(farm) and not third.command_gather(farm), "group followers cannot claim the same Farm")
	_expect(second.gather_target == wood and second.carried_amount == old_cargo, "rejection preserves prior work and exact cargo")
	_expect(farm.is_harvestable_by(0) and not farm.is_available_to_worker(second), "raw harvestability and worker availability remain distinct")
	_expect(farm.is_available_to_worker(first), "the assigned farmer can still work its own Farm")
	_expect(_map.get_nearest_resource_node("food", farm.global_position, 0) == other_farm, "ordinary discovery skips occupied Farm")
	_expect(_map.get_nearest_resource_node("food", farm.global_position, 0, first) == farm, "requester discovery retains its own Farm")
	_expect(_map.get_nearest_reachable_resource_node("food", farm.global_position, 0, {}, second) == other_farm, "path-aware recovery chooses the next available Farm")
	_expect(third.command_gather(wood), "natural wood still supports multiple assigned workers")
	var start: Vector2 = first.global_position
	var saw_delivery: bool = false
	var claim_held: bool = true
	for _tick: int in range(4000):
		first._process(0.05)
		claim_held = claim_held and farm.get_assigned_worker() == first
		if bool(first.get("_dropoff_route_active")):
			saw_delivery = true
			_expect(not second.command_gather(farm), "delivery does not free the Farm slot")
		if ResourceManager.get_resource(0, "food") >= 20:
			break
	_expect(start.distance_to(first.global_position) > 10.0, "farmer physically travels using canonical paths")
	_expect(saw_delivery and claim_held, "one claim spans work, delivery and return")
	_expect(ResourceManager.get_resource(0, "food") == 20, "two real ten-food loads reach the TC exactly once")
	_expect(first.gather_target == farm, "farmer resumes its Farm after both deposits")

	_expect(first.command_retreat(tc.global_position), "automatic evacuation accepts a legal route")
	_expect(farm.get_assigned_worker() == first, "temporary economic retreat retains Farm intent")
	first.command_stop()
	_expect(farm.get_assigned_worker() == null, "explicit Stop frees the Farm immediately")
	_expect(first.command_gather(farm) and first.command_gather(other_farm), "farmer can change Farms")
	_expect(farm.get_assigned_worker() == null and other_farm.get_assigned_worker() == first, "new Farm releases the previous claim")
	first.command_move(_map.tile_to_world(Vector2i(26, 31)))
	_expect(other_farm.get_assigned_worker() == null, "explicit Move frees the Farm")
	_expect(first.command_gather(farm), "Farm is claimable again")
	var house: BuildingBase = _building(HOUSE_SCENE, Vector2i(26, 27), false)
	first.command_build(house)
	_expect(first.current_state == UnitBase.State.BUILDING and farm.get_assigned_worker() == null, "construction releases Farm capacity while retaining resumable old intent")
	_expect(second.command_gather(farm), "a new farmer can occupy a builder's old Farm")
	first.call("_resume_or_idle")
	_expect(farm.get_assigned_worker() == second and first.gather_target != farm, "builder resume cannot steal the replacement farmer's claim")
	second.command_gather(wood)
	_expect(farm.get_assigned_worker() == null, "natural-resource reassignment releases Farm")

	var freed: Villager = _worker(Vector2i(29, 29))
	_expect(freed.command_gather(farm), "free-lifecycle worker claims Farm")
	_workers.erase(freed)
	freed.free()
	_expect(farm.get_assigned_worker() == null, "freed worker leaves no stale reservation")
	var dead: Villager = _worker(Vector2i(29, 29))
	_expect(dead.command_gather(farm), "death-lifecycle worker claims Farm")
	dead.die()
	_expect(farm.get_assigned_worker() == null, "death releases before delayed corpse removal")

	_test_ai_assignment(other_farm)
	# A loaded farmer keeps its earned cargo when the Farm is destroyed.
	first.command_stop()
	first.global_position = _map.tile_to_world(Vector2i(29, 30))
	_expect(first.command_gather(farm), "destruction case starts an assigned farmer")
	first.call("_process_gathering", 0.11)
	var food_before: int = ResourceManager.get_resource(0, "food")
	var cargo_before: int = first.carried_amount
	_expect(cargo_before > 0, "destruction fixture must have earned cargo")
	farm.take_damage(farm.hp)
	_expect(farm.get_assigned_worker() == null, "destroyed Farm exposes no assigned worker")
	first.command_return_resources()
	for _tick: int in range(2000):
		first._process(0.05)
		if first.carried_amount == 0:
			break
	_expect(first.carried_amount == 0 and ResourceManager.get_resource(0, "food") == food_before + cargo_before, "destroyed Farm's earned food reaches TC without loss")
	_map.free()
	_workers.clear()
	ResourceManager.reset()
	if _failures.is_empty():
		print("[PASS] farm_single_worker: atomic assignment, real work/delivery, cargo-safe rejection, reassignment/build/retreat/death/free/destruction, natural multiworker and AI recovery")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] farm_single_worker: " + failure)
		get_tree().quit(1)


func _test_ai_assignment(farm: BuildingBase) -> void:
	for worker: Villager in _workers:
		if is_instance_valid(worker) and worker.current_state != UnitBase.State.DEAD:
			worker.command_stop()
	var ai := AIController.new()
	ai.player_id = 0
	ai.game_map = _map
	_map.add_child(ai)
	ai.set_process(false)
	(ai.get("_decision_timer") as Timer).stop()
	for worker: Villager in _workers:
		if is_instance_valid(worker) and worker.current_state != UnitBase.State.DEAD:
			ai.register_unit(worker)
	ai.register_building(farm)
	ai.call("_assign_safe_worker_to_completed_farm", farm)
	var farmer: UnitBase = farm.get_assigned_worker()
	_expect(farmer != null, "AI completed Farm assigns one available worker")
	ai.call("_assign_safe_worker_to_completed_farm", farm)
	_expect(farm.get_assigned_worker() == farmer, "repeat AI completion cannot steal or duplicate assignment")
	for worker: Villager in _workers:
		if is_instance_valid(worker) and worker.current_state != UnitBase.State.DEAD and worker != farmer:
			var candidate: Node2D = ai.call("_find_resource_for_villager", "food", worker) as Node2D
			_expect(candidate != farm, "AI recovery skips a Farm reserved by another worker")
	for _index: int in range(7):
		ai.register_unit(_worker(Vector2i(20, 35)))
	for other: Node2D in _map.get("_additional_resource_nodes"):
		if other is BuildingBase and other != farm and (other as BuildingBase).state == BuildingBase.State.ACTIVE:
			ai.register_building(other)
			for worker: Villager in _workers:
				if worker.current_state != UnitBase.State.DEAD and worker != farmer and worker.command_gather(other):
					break
	var targets: Dictionary = ai.call("_get_target_building_counts", 1)
	_expect(int(targets[BuildingData.BuildingType.FARM]) > 2, "AI requests additional paid capacity when two single-worker Farms are the only food")
	ai.free()
	for worker: Villager in _workers:
		if is_instance_valid(worker) and worker.current_state != UnitBase.State.DEAD:
			worker.command_stop()


func _building(scene: PackedScene, tile: Vector2i, complete: bool = true) -> BuildingBase:
	var building: BuildingBase = scene.instantiate() as BuildingBase
	building.player_owner = 0
	building.position = _map.tile_to_world(tile)
	_map.add_child(building)
	building.set_process(false)
	building.state = BuildingBase.State.ACTIVE if complete else BuildingBase.State.CONSTRUCTING
	building.hp = building.max_hp
	_map.place_building_obstacle(tile, building.footprint)
	if building.provides_food:
		_map.register_harvestable(building)
	return building


func _resource(kind: String, tile: Vector2i) -> ResourceNode:
	var resource: ResourceNode = RESOURCE_SCENE.instantiate() as ResourceNode
	resource.resource_type = kind
	resource.position = _map.tile_to_world(tile)
	_map.add_child(resource)
	_map.resource_nodes[tile] = resource
	return resource


func _worker(tile: Vector2i) -> Villager:
	var worker: Villager = WORKER_SCENE.instantiate() as Villager
	worker.player_owner = 0
	worker.position = _map.tile_to_world(tile)
	_map.add_child(worker)
	worker.set_process(false)
	worker.carry_capacity = 10
	worker.gather_rate = 5.0
	worker.gather_tick_time = 0.1
	_workers.append(worker)
	return worker


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
