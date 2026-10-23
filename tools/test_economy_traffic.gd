extends Node
## Actual Villager/BuildingBase economy on a deliberately revealed synthetic
## grass map. Manual stepping tests service points, not native performance.

class TrafficMap extends "res://scripts/map/game_map.gd":
	func _ready() -> void:
		# Use the production TileMap conversion: the detached formula fallback
		# truncates cells and cannot model close turns around real footprints.
		terrain_layer.tile_set = TilesetBuilder.build_terrain_tileset()
		set_process(false)
	func is_entity_visible_to_player(_entity: Node2D, _owner: int = 0) -> bool:
		return true
	func is_tile_visible_to_player(_tile: Vector2i, _owner: int = 0) -> bool:
		return true

var world: TrafficMap
var workers: Array[Villager] = []
var failures: Array[String] = []
var metrics: Array[Dictionary] = []
var baseline: bool = false
var farm_deposits: Dictionary = {}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	AudioManager.set_all_enabled(false)
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food":0, "wood":0, "gold":0})
	var scene: Node2D = load("res://scenes/map/game_map.tscn").instantiate()
	scene.set_script(TrafficMap)
	world = scene as TrafficMap
	world.map_generator = MapGenerator.new(101)
	world.map_generator.call("_init_grid")
	world.pathfinding = Pathfinding.new(world.map_generator)
	add_child(world)
	var tc := _building(BuildingData.BuildingType.TOWN_CENTER, Vector2i(25, 25))
	for index: int in 8:
		var worker := _worker(Vector2i(32, 26))
		worker.position += Vector2(index * 2, 0)
		worker.carried_resource_type = "wood"
		worker.carried_amount = 15
		_expect(worker.command_return_resources(), "loaded worker accepts delivery")
	var endpoints: Dictionary = {}
	for worker: Villager in workers:
		endpoints[worker.move_target] = true
	metrics.append({"case":"eight_loaded_workers", "unique_delivery_endpoints":endpoints.size()})
	_expect(endpoints.size() >= 4, "eight concurrent deliveries distribute across at least four reachable service points")
	for tick: int in 1800:
		for worker: Villager in workers:
			worker._process(1.0 / 30.0)
		if ResourceManager.get_resource(0, "wood") == 120:
			break
	_expect(ResourceManager.get_resource(0, "wood") == 120, "eight initial fifteen-wood loads deposit exactly once")
	for worker: Villager in workers:
		_expect(worker.carried_amount == 0, "delivery empties each original cargo bag")
	_clear_workers()
	var berries := ResourceNode.new()
	berries.resource_type = "food"
	berries.position = world.tile_to_world(Vector2i(35, 35))
	world.add_child(berries)
	for index: int in 6:
		var worker := _worker(Vector2i(39, 35))
		worker.position += Vector2(index * 2, 0)
		worker.carry_capacity = 1000
		_expect(worker.command_gather(berries), "natural food remains multiworker")
	for tick: int in 360:
		for worker: Villager in workers:
			worker._process(1.0 / 30.0)
	var minimum: float = INF
	var positions: Array[Dictionary] = []
	for first: int in workers.size():
		positions.append({"position":str(workers[first].position), "service":str(workers[first].get("_service_destination")), "state":workers[first].current_state, "cargo":workers[first].carried_amount})
		_expect(workers[first].carried_amount > 0, "all natural-resource workers arrive and harvest")
		for second: int in range(first + 1, workers.size()):
			minimum = minf(minimum, workers[first].position.distance_to(workers[second].position))
	metrics.append({"case":"six_natural_workers", "minimum_work_spacing":minimum, "workers":positions})
	_expect(minimum >= 14.0, "natural resource workers retain distinct standing work positions")
	_clear_workers()
	berries.free()
	_test_farm_cycles()
	if not baseline:
		_test_workpoint_repath()
		_test_settled_military_endpoints(tc)
	world.remove_building_obstacle(world.world_to_tile(tc.position), tc.footprint)
	tc.free()
	world.free()
	for record: Dictionary in metrics:
		print("[METRIC] economy_traffic ", JSON.stringify(record))
	if baseline:
		print("[BASELINE] economy_traffic observed failures: ", JSON.stringify(failures))
	else:
		for failure: String in failures:
			push_error("[FAIL] economy_traffic: " + failure)
		if failures.is_empty():
			print("[PASS] economy_traffic: distributed actual service routes, exact deposits and multiworker natural work")
	get_tree().quit(0 if baseline or failures.is_empty() else 1)

func _test_farm_cycles() -> void:
	# Four real Farms with the same one-cell lanes as legal player placement.
	# Keep the normal carry capacity, work rate and actual TC deposit callback.
	var farms: Array[BuildingBase] = []
	var tiles: Array[Vector2i] = [Vector2i(32, 25), Vector2i(35, 25), Vector2i(32, 28), Vector2i(35, 28)]
	var delivered_before: int = ResourceManager.get_resource(0, "food")
	var saw_delivery: Dictionary = {}
	var saw_second_work: Dictionary = {}
	for tile: Vector2i in tiles:
		var farm := _building(BuildingData.BuildingType.FARM, tile)
		world.register_harvestable(farm)
		farms.append(farm)
		var worker := _worker(Vector2i(31, 27))
		worker.position += Vector2(workers.size() * 2, 0)
		farm_deposits[worker.get_instance_id()] = 0
		worker.resource_deposited.connect(_record_farm_deposit.bind(worker.get_instance_id()))
		_expect(worker.command_gather(farm), "each adjacent Farm accepts its own farmer")
	var claim_held: bool = true
	var elapsed: float = 0.0
	for tick: int in 7200:
		var finished: bool = true
		for index: int in workers.size():
			var worker: Villager = workers[index]
			var id: int = worker.get_instance_id()
			if int(farm_deposits[id]) >= worker.carry_capacity * 2:
				continue
			finished = false
			worker._process(1.0 / 30.0)
			claim_held = claim_held and farms[index].get_assigned_worker() == worker
			if worker._dropoff_route_active:
				saw_delivery[id] = true
			if int(farm_deposits[id]) > 0 and worker.current_state == UnitBase.State.GATHERING and worker.carried_amount > 0:
				saw_second_work[id] = true
		elapsed = float(tick + 1) / 30.0
		if finished:
			break
	var expected_food: int = 0
	var results: Array[Dictionary] = []
	for index: int in workers.size():
		var worker: Villager = workers[index]
		var id: int = worker.get_instance_id()
		expected_food += worker.carry_capacity * 2
		_expect(int(farm_deposits[id]) == worker.carry_capacity * 2, "each farmer completes two full deliveries without stalling")
		_expect(saw_delivery.has(id) and saw_second_work.has(id), "each farmer physically delivers and re-enters work")
		_expect(worker.carried_amount == 0, "second Farm delivery empties exact cargo")
		results.append({"deposited":farm_deposits[id], "cargo":worker.carried_amount, "position":str(worker.position), "state":worker.current_state})
		worker.command_stop()
		_expect(farms[index].get_assigned_worker() == null, "Stop frees Farm after repeated cycles")
		if not baseline:
			_expect(worker.get("_service_target_id") == 0, "Stop frees economic standing position")
	_expect(claim_held, "each Farm claim remains exclusive through travel, work, delivery and re-entry")
	_expect(ResourceManager.get_resource(0, "food") - delivered_before == expected_food, "four Farms deposit exactly two normal loads each")
	metrics.append({"case":"four_farms_two_cycles", "elapsed_simulated_seconds":elapsed, "claim_held":claim_held, "food_deposited":ResourceManager.get_resource(0, "food") - delivered_before, "workers":results})
	_clear_workers()
	for farm: BuildingBase in farms:
		world.unregister_harvestable(farm)
		world.remove_building_obstacle(world.world_to_tile(farm.position), farm.footprint)
		farm.free()

func _record_farm_deposit(resource: String, amount: int, worker_id: int) -> void:
	_expect(resource == "food", "Farm deposits retain food identity")
	farm_deposits[worker_id] = int(farm_deposits[worker_id]) + amount

func _test_workpoint_repath() -> void:
	var resource := ResourceNode.new()
	resource.resource_type = "wood"
	resource.position = world.tile_to_world(Vector2i(45, 40))
	world.add_child(resource)
	for index: int in 2:
		var worker := _worker(Vector2i(50, 40))
		worker.position += Vector2(index * 2, 0)
		worker.carry_capacity = 1000
		_expect(worker.command_gather(resource), "topology case accepts actual natural-resource work")
		worker._process(1.0 / 30.0)
	var displaced: Villager = workers[1]
	var destination: Vector2 = displaced.get("_service_destination")
	var destination_tile: Vector2i = world.world_to_tile(destination)
	_expect(destination.distance_to(world.tile_to_world(destination_tile)) > 4.0, "repath case chooses a real sub-tile service point")
	_expect(displaced.path.size() >= 4, "repath case begins with a real multi-cell route")
	if displaced.path.size() >= 4:
		# Invalidate an upcoming inherited waypoint while its route is populated.
		# UnitBase discovers this during movement and requests a fresh route.
		var blocked: Vector2i = world.world_to_tile(displaced.path[2])
		_expect(blocked != destination_tile, "topology changes the route, not its reserved endpoint")
		world.place_building_obstacle(blocked, Vector2i.ONE)
		for tick: int in 1200:
			for worker: Villager in workers:
				worker._process(1.0 / 30.0)
			if displaced.carried_amount >= 3:
				break
		_expect(displaced.carried_amount >= 3, "sub-tile worker resumes real harvesting after inherited topology repath")
		_expect(displaced.position.distance_to(destination) <= 4.0, "topology repath arrives at the reserved sub-tile work point")
		_expect(world.is_tile_walkable(world.world_to_tile(displaced.position)), "repathed work stays on walkable terrain")
		metrics.append({"case":"subtile_work_repath", "cargo":displaced.carried_amount, "endpoint_error":displaced.position.distance_to(destination), "blocked_tile":str(blocked)})
		world.remove_building_obstacle(blocked, Vector2i.ONE)
	_clear_workers()
	resource.free()

func _test_settled_military_endpoints(tc: BuildingBase) -> void:
	var farm := _building(BuildingData.BuildingType.FARM, Vector2i(32, 25))
	world.register_harvestable(farm)
	var worker := _worker(Vector2i(31, 27))
	var ordinary_work: PackedVector2Array = world.get_building_work_world_path(worker.position, farm.position, farm.footprint, Villager.BUILD_APPROACH_DISTANCE)
	_expect(not ordinary_work.is_empty(), "military occupation case has an ordinary Farm work route")
	if ordinary_work.is_empty():
		_clear_workers()
		farm.free()
		return
	var scout := _settled_unit("res://scenes/units/scout.tscn", ordinary_work[-1])
	var food_before: int = ResourceManager.get_resource(0, "food")
	_expect(worker.command_gather(farm), "farmer claims Farm beside a settled Scout")
	worker._process(1.0 / 30.0)
	var workpoint: Vector2 = worker.get("_service_destination")
	_expect(workpoint.distance_to(scout.position) >= 22.0, "Farm work selects a different edge from idle friendly Scout")
	var ordinary_delivery: PackedVector2Array = world.get_building_dropoff_world_path(workpoint, tc.position, tc.footprint, Villager.BUILD_APPROACH_DISTANCE)
	_expect(not ordinary_delivery.is_empty(), "military occupation case has a real TC delivery route")
	var warrior := _settled_unit("res://scenes/units/infantry.tscn", ordinary_delivery[-1])
	var claims_held: bool = true
	var saw_delivery: bool = false
	var returned_to_work: bool = false
	var delivery_separation: float = INF
	for tick: int in 3000:
		worker._process(1.0 / 30.0)
		claims_held = claims_held and farm.get_assigned_worker() == worker
		if worker._dropoff_route_active:
			saw_delivery = true
			delivery_separation = minf(delivery_separation, worker.move_target.distance_to(warrior.position))
		if ResourceManager.get_resource(0, "food") > food_before and worker.carried_amount > 0 and worker.current_state == UnitBase.State.GATHERING:
			returned_to_work = true
			break
	_expect(saw_delivery and delivery_separation >= 22.0, "food delivery avoids the idle Warrior's standing point")
	_expect(ResourceManager.get_resource(0, "food") - food_before == worker.carry_capacity, "occupied delivery edge still deposits exactly one full food bag")
	_expect(claims_held and returned_to_work and worker.carried_amount == 1, "exclusive farmer returns and earns one fresh food after delivery")
	_expect(worker.position.distance_to(scout.position) >= 18.0, "returning farmer stands apart from the settled Scout")

	# The same allocator also serves construction. Use a real unfinished House
	# and carry the freshly harvested food through build and automatic resume.
	var house := _building(BuildingData.BuildingType.HOUSE, Vector2i(32, 30))
	house.start_construction()
	var ordinary_build: PackedVector2Array = world.get_building_work_world_path(worker.position, house.position, house.footprint, Villager.BUILD_APPROACH_DISTANCE)
	_expect(not ordinary_build.is_empty(), "construction has an ordinary legal work route")
	var builder_blocker := _settled_unit("res://scenes/units/infantry.tscn", ordinary_build[-1])
	var cargo_before: Dictionary = worker.get_carried_resources().duplicate()
	worker.command_build(house)
	_expect(farm.get_assigned_worker() == null, "building releases Farm ownership while preserving saved work intent")
	worker._process(1.0 / 30.0)
	var buildpoint: Vector2 = worker.get("_service_destination")
	_expect(buildpoint.distance_to(builder_blocker.position) >= 22.0, "builder chooses a separate edge from the idle Warrior")
	for tick: int in 3000:
		worker._process(1.0 / 30.0)
		if house.state == BuildingBase.State.ACTIVE:
			break
	_expect(house.state == BuildingBase.State.ACTIVE, "separated builder completes actual House labor")
	_expect(worker.get_carried_resources() == cargo_before, "construction retains exact freshly harvested cargo")
	_expect(farm.get_assigned_worker() == worker and worker.gather_target == farm, "completion resumes the same exclusive Farm")
	metrics.append({"case":"settled_military_economy", "farm_scout_separation":workpoint.distance_to(scout.position), "delivery_warrior_separation":delivery_separation, "builder_warrior_separation":buildpoint.distance_to(builder_blocker.position), "food_deposited":ResourceManager.get_resource(0, "food") - food_before, "retained_cargo":worker.get_carried_resources()})
	_clear_workers()
	for unit: UnitBase in [scout, warrior, builder_blocker]:
		unit.free()
	for building: BuildingBase in [farm, house]:
		world.unregister_harvestable(building)
		world.remove_building_obstacle(world.world_to_tile(building.position), building.footprint)
		building.free()

func _settled_unit(scene_path: String, at: Vector2) -> UnitBase:
	var unit: UnitBase = load(scene_path).instantiate()
	unit.position = at
	world.add_child(unit)
	unit.set_process(false)
	unit.command_stop()
	return unit

func _building(kind: int, tile: Vector2i) -> BuildingBase:
	var building := BuildingBase.new()
	building.building_type = kind
	building.position = world.tile_to_world(tile)
	world.add_child(building)
	building.complete_instantly()
	building.set_process(false)
	world.place_building_obstacle(tile, building.footprint)
	return building

func _worker(tile: Vector2i) -> Villager:
	var worker: Villager = load("res://scenes/units/villager.tscn").instantiate()
	worker.position = world.tile_to_world(tile)
	world.add_child(worker)
	worker.set_process(false)
	workers.append(worker)
	return worker

func _clear_workers() -> void:
	for worker: Villager in workers:
		worker.free()
	workers.clear()

func _expect(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)
