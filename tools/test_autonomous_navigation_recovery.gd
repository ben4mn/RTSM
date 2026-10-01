extends Node
## Focused autonomous MOVE-001 regression for economic tasks and chase recovery.

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const INFANTRY_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")
const RESOURCE_SCENE: PackedScene = preload("res://scenes/map/resource_node.tscn")
const HOUSE_SCENE: PackedScene = preload("res://scenes/buildings/house.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const TOWN_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/town_center.tscn")
const GAME_MAP_SCENE: PackedScene = preload("res://scenes/map/game_map.tscn")

var _failures: Array[String] = []


class FakeNavigationMap extends Node2D:
	var reject_routes: bool = false
	var direct_routes: bool = false
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
		if direct_routes:
			return PackedVector2Array([from_world, target_world])
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

	func get_nearest_resource_node(
		_type: String,
		_from: Vector2,
		_player_id: int = -1
	) -> Node2D:
		return null

	func get_nearest_reachable_resource_node(
		_type: String,
		_from: Vector2,
		_player_id: int = -1,
		_excluded_instance_ids: Dictionary = {}
	) -> Node2D:
		return null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager != null:
		audio_manager.call("set_all_enabled", false)
	_test_gather_build_and_chase_use_routes()
	_test_unreachable_tasks_recover_once()
	_test_interrupted_dropoff_cannot_deposit_remotely()
	_test_offset_arrival_shell_advances_to_harvest()
	await _test_farm_one_open_edge_harvests_and_sealed_edge_recovers()
	_test_separation_preserves_overlap_magnitude()
	_test_clustered_gatherers_keep_forward_progress()
	await _test_real_map_adjacent_resource_endpoint_harvests()
	_finish()


func _test_gather_build_and_chase_use_routes() -> void:
	var navigation_map := FakeNavigationMap.new()
	add_child(navigation_map)
	var container := Node2D.new()
	navigation_map.add_child(container)

	var resource: Node2D = RESOURCE_SCENE.instantiate() as Node2D
	resource.global_position = Vector2(96.0, 0.0)
	container.add_child(resource)
	var gatherer: Villager = VILLAGER_SCENE.instantiate() as Villager
	container.add_child(gatherer)
	gatherer.command_gather(resource)
	gatherer.set("_gather_offset", Vector2.ZERO)
	gatherer._process(0.1)
	_expect(gatherer.global_position.y > 0.0, "gathering follows the detour waypoint instead of moving directly")
	gatherer.free()
	resource.free()

	var house: BuildingBase = HOUSE_SCENE.instantiate() as BuildingBase
	house.player_owner = 0
	house.global_position = Vector2(96.0, 0.0)
	container.add_child(house)
	house.start_construction()
	var builder: Villager = VILLAGER_SCENE.instantiate() as Villager
	container.add_child(builder)
	builder.command_build(house)
	builder._process(0.1)
	_expect(builder.global_position.y > 0.0, "construction follows the detour waypoint instead of moving directly")
	builder.free()
	house.free()

	var attacker: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	attacker.player_owner = 0
	container.add_child(attacker)
	var enemy: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	enemy.player_owner = 1
	enemy.global_position = Vector2(160.0, 0.0)
	container.add_child(enemy)
	attacker.command_attack(enemy)
	attacker._process(0.1)
	_expect(attacker.global_position.y > 0.0, "unit chase follows the detour waypoint instead of moving directly")
	attacker.free()
	enemy.free()
	navigation_map.free()


func _test_unreachable_tasks_recover_once() -> void:
	var navigation_map := FakeNavigationMap.new()
	navigation_map.reject_routes = true
	add_child(navigation_map)
	var container := Node2D.new()
	navigation_map.add_child(container)

	var resource: Node2D = RESOURCE_SCENE.instantiate() as Node2D
	resource.global_position = Vector2(96.0, 0.0)
	container.add_child(resource)
	var gatherer: Villager = VILLAGER_SCENE.instantiate() as Villager
	container.add_child(gatherer)
	gatherer.command_gather(resource)
	gatherer.set("_gather_offset", Vector2.ZERO)
	for _step in range(100):
		gatherer._process(0.1)
		if gatherer.current_state == UnitBase.State.IDLE:
			break
	_expect_eq(navigation_map.path_requests, UnitBase.NAVIGATION_MAX_FAILED_REPATHS, "unreachable gather obeys the retry cap")
	_expect(gatherer.gather_target == null, "unreachable gather target is abandoned")
	_expect(gatherer.current_state == UnitBase.State.IDLE, "unreachable gather recovers to idle when no alternative exists")
	gatherer.free()
	resource.free()

	navigation_map.path_requests = 0
	var house: BuildingBase = HOUSE_SCENE.instantiate() as BuildingBase
	house.player_owner = 0
	house.global_position = Vector2(96.0, 0.0)
	container.add_child(house)
	house.start_construction()
	var builder: Villager = VILLAGER_SCENE.instantiate() as Villager
	container.add_child(builder)
	builder.command_build(house)
	for _step in range(100):
		builder._process(0.1)
		if builder.current_state == UnitBase.State.IDLE:
			break
	_expect_eq(navigation_map.path_requests, UnitBase.NAVIGATION_MAX_FAILED_REPATHS, "unreachable construction obeys the retry cap")
	_expect(builder.build_target == null, "unreachable construction target is abandoned")
	builder.free()
	house.free()

	navigation_map.path_requests = 0
	var attacker: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	attacker.player_owner = 0
	container.add_child(attacker)
	var enemy: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	enemy.player_owner = 1
	enemy.global_position = Vector2(160.0, 0.0)
	container.add_child(enemy)
	attacker.command_attack(enemy)
	for _step in range(100):
		attacker._process(0.1)
		if attacker.current_state == UnitBase.State.IDLE:
			break
	_expect_eq(navigation_map.path_requests, UnitBase.NAVIGATION_MAX_FAILED_REPATHS, "unreachable chase obeys the retry cap")
	_expect(attacker.attack_target == null, "unreachable chase clears the live target")
	attacker.free()
	enemy.free()
	navigation_map.free()


func _test_interrupted_dropoff_cannot_deposit_remotely() -> void:
	var navigation_map := FakeNavigationMap.new()
	add_child(navigation_map)
	var container := Node2D.new()
	navigation_map.add_child(container)
	var town_center: BuildingBase = TOWN_CENTER_SCENE.instantiate() as BuildingBase
	town_center.player_owner = 0
	town_center.global_position = Vector2(96.0, 0.0)
	container.add_child(town_center)
	town_center.complete_instantly()
	var villager: Villager = VILLAGER_SCENE.instantiate() as Villager
	container.add_child(villager)
	villager.carried_resource_type = "food"
	villager.carried_amount = 5
	villager.call("_find_and_go_to_dropoff")
	_expect(bool(villager.get("_dropoff_route_active")), "drop-off route arms its purpose token")
	villager.command_move(Vector2(240.0, 0.0))
	villager.call("_on_arrived_for_dropoff", villager)
	_expect_eq(villager.carried_amount, 5, "superseding move prevents a stale remote deposit")
	_expect(villager.dropoff_target == null, "superseding command clears stale drop-off target")
	villager.free()
	town_center.free()
	navigation_map.free()


func _test_offset_arrival_shell_advances_to_harvest() -> void:
	## The worker begins outside the natural-resource action disk but inside the
	## old offset-target arrival disk. That mismatch used to report ARRIVED every
	## frame without moving or gathering.
	var navigation_map := FakeNavigationMap.new()
	navigation_map.direct_routes = true
	add_child(navigation_map)
	var resource: ResourceNode = RESOURCE_SCENE.instantiate() as ResourceNode
	resource.resource_type = "wood"
	resource.total_amount = 100
	resource.global_position = Vector2(96.0, 0.0)
	navigation_map.add_child(resource)
	var gatherer: Villager = VILLAGER_SCENE.instantiate() as Villager
	gatherer.global_position = Vector2(138.0, 0.0)
	gatherer.gather_tick_time = 0.1
	navigation_map.add_child(gatherer)
	_expect(bool(gatherer.command_gather(resource)), "offset-shell resource accepts gather command")
	gatherer.set("_gather_offset", Vector2(10.0, 0.0))
	var start_position: Vector2 = gatherer.global_position
	for _step in range(80):
		gatherer._process(0.1)
		if gatherer.carried_amount > 0:
			break
	_expect(gatherer.global_position.distance_to(start_position) > 0.1, "offset-only ARRIVED shell cannot pin a natural gatherer")
	_expect(
		gatherer.global_position.distance_to(resource.global_position) <= Villager.GATHER_APPROACH_DISTANCE,
		"natural gatherer enters the center-based action radius"
	)
	_expect(gatherer.carried_amount > 0, "offset-shell gatherer advances through a real harvest tick")
	navigation_map.free()


func _test_farm_one_open_edge_harvests_and_sealed_edge_recovers() -> void:
	## Use production isometric navigation with one legal far-side Farm edge.
	## The anchor disk is sealed; only footprint-aware work can reach a harvest.
	var game_map: Node2D = GAME_MAP_SCENE.instantiate() as Node2D
	game_map.set("map_seed", 424242)
	add_child(game_map)
	await get_tree().process_frame
	game_map.set_process(false)
	(game_map.get_node("FogOfWar") as FogManager).set_process(false)
	for resource: Node in game_map.get_node("ResourcesContainer").get_children():
		resource.free()
	(game_map.get("resource_nodes") as Dictionary).clear()
	(game_map.get("_additional_resource_nodes") as Array).clear()
	var navigation: Pathfinding = game_map.get("pathfinding") as Pathfinding
	var farm_tile := Vector2i(12, 12)
	var edge_tile: Vector2i = farm_tile + Vector2i(0, 2)
	var origin_tile: Vector2i = farm_tile + Vector2i(0, 4)
	var fog: FogManager = game_map.get_node("FogOfWar") as FogManager
	for dy: int in range(2):
		for dx: int in range(2):
			fog.fog_grid[farm_tile.y + dy][farm_tile.x + dx] = MapData.FogState.VISIBLE
	for dy: int in range(-2, 6):
		for dx: int in range(-2, 5):
			navigation.set_solid(farm_tile + Vector2i(dx, dy), false)
	for dy: int in range(-1, 3):
		for dx: int in range(-1, 3):
			var tile: Vector2i = farm_tile + Vector2i(dx, dy)
			navigation.set_solid(tile, tile != edge_tile)
	var origin_world: Vector2 = game_map.call("tile_to_world", origin_tile) as Vector2
	var farm: BuildingBase = FARM_SCENE.instantiate() as BuildingBase
	farm.player_owner = 0
	farm.global_position = game_map.call("tile_to_world", farm_tile) as Vector2
	game_map.get_node("BuildingsContainer").add_child(farm)
	farm.complete_instantly()
	game_map.call("register_harvestable", farm)
	var anchor_route: PackedVector2Array = game_map.call("get_navigation_world_path", origin_world, farm.global_position, Villager.BUILD_APPROACH_DISTANCE) as PackedVector2Array
	_expect(anchor_route.is_empty() or anchor_route[-1].distance_to(farm.global_position) > Villager.BUILD_APPROACH_DISTANCE, "Farm fixture seals the anchor interaction disk")
	var work_route: PackedVector2Array = game_map.call("get_building_work_world_path", origin_world, farm.global_position, farm.footprint, Villager.BUILD_APPROACH_DISTANCE) as PackedVector2Array
	_expect(not work_route.is_empty() and game_map.call("world_to_tile", work_route[-1]) == edge_tile, "Farm footprint route reaches its only legal edge")
	_expect(game_map.call("get_nearest_reachable_resource_node", "food", origin_world, 0, {}) == farm, "reachable food lookup accepts the Farm's open footprint edge")
	var gatherer: Villager = VILLAGER_SCENE.instantiate() as Villager
	gatherer.player_owner = 0
	gatherer.global_position = origin_world
	gatherer.gather_tick_time = 0.1
	game_map.get_node("UnitsContainer").add_child(gatherer)
	_expect(bool(gatherer.command_gather(farm)), "active owned Farm accepts the open-edge gather command")
	gatherer.set("_gather_offset", Vector2(10.0, 0.0))
	var farm_remaining_before: int = farm.farm_remaining
	for _step in range(160):
		gatherer._process(0.1)
		if farm.farm_remaining < farm_remaining_before:
			break
	print("[METRIC] Farm single-edge navigation: ", JSON.stringify({"position": str(gatherer.global_position), "origin": str(origin_world), "edge": str(work_route[-1]) if not work_route.is_empty() else "none", "work_distance": game_map.call("get_building_work_distance", gatherer.global_position, farm.global_position, farm.footprint), "state": gatherer.current_state, "path": str(gatherer.path), "stock": farm.farm_remaining, "stock_before": farm_remaining_before, "gather_target": str(gatherer.gather_target)}))
	_expect(gatherer.global_position.distance_to(farm.global_position) > Villager.BUILD_APPROACH_DISTANCE, "Farm harvest genuinely occurs beyond its sealed anchor disk")
	_expect(float(game_map.call("get_building_work_distance", gatherer.global_position, farm.global_position, farm.footprint)) <= Villager.BUILD_APPROACH_DISTANCE, "Farm harvester enters the exact footprint work radius")
	_expect(navigation.is_walkable(game_map.call("world_to_tile", gatherer.global_position) as Vector2i), "Farm harvester works from real walkable edge terrain")
	_expect(gatherer.carried_amount > 0 and farm.farm_remaining < farm_remaining_before, "Farm edge navigation advances through a real harvest tick")
	gatherer.free()

	# Close the final edge: no arbitrary nearby fallback may harvest remotely.
	navigation.set_solid(edge_tile, true)
	_expect((game_map.call("get_building_work_world_path", origin_world, farm.global_position, farm.footprint, Villager.BUILD_APPROACH_DISTANCE) as PackedVector2Array).is_empty(), "sealed Farm has no legal footprint route")
	_expect(game_map.call("get_nearest_reachable_resource_node", "food", origin_world, 0, {}) == null, "reachable lookup rejects the completely sealed Farm")
	var stranded: Villager = VILLAGER_SCENE.instantiate() as Villager
	stranded.player_owner = 0
	stranded.global_position = origin_world
	stranded.gather_tick_time = 0.1
	game_map.get_node("UnitsContainer").add_child(stranded)
	_expect(bool(stranded.command_gather(farm)), "visible valid sealed Farm initially accepts an explicit order")
	var sealed_stock: int = farm.farm_remaining
	for _step in range(100):
		stranded._process(0.1)
		if stranded.current_state == UnitBase.State.IDLE:
			break
	_expect(stranded.current_state == UnitBase.State.IDLE and stranded.gather_target == null, "unreachable Farm recovers to idle and clears its target")
	_expect(stranded.carried_amount == 0 and farm.farm_remaining == sealed_stock, "unreachable Farm never grants a remote harvest")
	game_map.free()


func _test_separation_preserves_overlap_magnitude() -> void:
	var navigation_map := FakeNavigationMap.new()
	add_child(navigation_map)
	var center: Villager = VILLAGER_SCENE.instantiate() as Villager
	center.global_position = Vector2.ZERO
	navigation_map.add_child(center)
	var right_neighbor: Villager = VILLAGER_SCENE.instantiate() as Villager
	right_neighbor.global_position = Vector2(UnitBase.FRIENDLY_SEPARATION_RADIUS - 0.1, 0.0)
	navigation_map.add_child(right_neighbor)
	center.set("_separation_timer", 0.0)
	center.call("_update_friendly_separation")
	var tiny_overlap_force: Vector2 = center.get("_separation_vector") as Vector2
	_expect(tiny_overlap_force.length() > 0.0, "tiny friendly overlap still produces separation")
	_expect(tiny_overlap_force.length() < 0.02, "tiny overlap remains tiny instead of normalizing to full force")

	var left_neighbor: Villager = VILLAGER_SCENE.instantiate() as Villager
	left_neighbor.global_position = Vector2(-UnitBase.FRIENDLY_SEPARATION_RADIUS + 0.1, 0.0)
	navigation_map.add_child(left_neighbor)
	center.set("_separation_timer", 0.0)
	center.call("_update_friendly_separation")
	var symmetric_force: Vector2 = center.get("_separation_vector") as Vector2
	_expect(symmetric_force.length() < 0.001, "symmetric neighbor overlap cancels without a normalized shove")
	_expect(UnitBase.FRIENDLY_SEPARATION_MAX_STEER < 1.0, "separation steering cannot reverse unit progress")
	navigation_map.free()


func _test_clustered_gatherers_keep_forward_progress() -> void:
	## Two stationary in-range workers each sit just ahead of a trailing worker.
	## Normalizing the slightest overlap used to reverse both trailing workers;
	## magnitude-preserving steering lets all four reach and harvest normally.
	var navigation_map := FakeNavigationMap.new()
	navigation_map.direct_routes = true
	add_child(navigation_map)
	var resources: Array[ResourceNode] = []
	var workers: Array[Villager] = []
	for lane_y: float in [0.0, 80.0]:
		var resource: ResourceNode = RESOURCE_SCENE.instantiate() as ResourceNode
		resource.resource_type = "wood"
		resource.total_amount = 1000
		resource.global_position = Vector2(96.0, lane_y)
		navigation_map.add_child(resource)
		resources.append(resource)
		for worker_x: float in [130.0, 160.0]:
			var worker: Villager = VILLAGER_SCENE.instantiate() as Villager
			worker.global_position = Vector2(worker_x, lane_y)
			worker.gather_tick_time = 0.1
			worker.carry_capacity = 1000
			navigation_map.add_child(worker)
			worker.command_gather(resource)
			worker.set("_gather_offset", Vector2.ZERO)
			workers.append(worker)
	for _step in range(120):
		for worker: Villager in workers:
			worker._process(0.1)
		var all_harvesting: bool = true
		for worker: Villager in workers:
			if worker.carried_amount <= 0:
				all_harvesting = false
				break
		if all_harvesting:
			break
	var aggregate_cargo: int = 0
	for worker: Villager in workers:
		aggregate_cargo += worker.carried_amount
		_expect(worker.carried_amount > 0, "each clustered gatherer reaches a harvest tick")
	_expect(aggregate_cargo >= workers.size(), "clustered workers produce non-stagnant aggregate cargo")
	navigation_map.free()


func _test_real_map_adjacent_resource_endpoint_harvests() -> void:
	## Exercise the production GameMap/Pathfinding route rather than a distance-only
	## fixture. A solid target tile routes to the nearest isometric neighbor, whose
	## center is ~35.78px away: outside the old 28px action radius but inside the
	## shared 36px resource contract.
	var game_map: Node2D = GAME_MAP_SCENE.instantiate() as Node2D
	game_map.set("map_seed", 424242)
	add_child(game_map)
	await get_tree().process_frame
	game_map.set_process(false)
	var fog: FogManager = game_map.get_node("FogOfWar") as FogManager
	fog.set_process(false)
	var resources_container: Node = game_map.get_node("ResourcesContainer")
	for existing_resource: Node in resources_container.get_children():
		existing_resource.free()
	var registry: Dictionary = game_map.get("resource_nodes") as Dictionary
	registry.clear()
	var additional: Array = game_map.get("_additional_resource_nodes") as Array
	additional.clear()

	var generator: MapGenerator = game_map.get("map_generator") as MapGenerator
	var navigation: Pathfinding = game_map.get("pathfinding") as Pathfinding
	var origin_tile: Vector2i = generator.spawn_positions[0]
	var target_tile: Vector2i = origin_tile + Vector2i(3, 0)
	_expect(navigation.is_walkable(origin_tile), "real route fixture starts on a walkable spawn tile")
	_expect(navigation.is_walkable(target_tile), "real route fixture target begins walkable")
	# Leave only the west adjacent endpoint open. The production +10px opposing
	# offset is farther than 36px from that endpoint, while the resource center is
	# still exactly reachable under the shared action contract.
	var blocked_tiles: Array[Vector2i] = [
		target_tile,
		target_tile + Vector2i(1, 0),
		target_tile + Vector2i(0, 1),
		target_tile + Vector2i(0, -1),
		target_tile + Vector2i(1, 1),
		target_tile + Vector2i(-1, -1),
	]
	for blocked_tile: Vector2i in blocked_tiles:
		navigation.set_solid(blocked_tile, true)
	var origin_world: Vector2 = game_map.call("tile_to_world", origin_tile) as Vector2
	var target_world: Vector2 = game_map.call("tile_to_world", target_tile) as Vector2
	var route: PackedVector2Array = game_map.call(
		"get_navigation_world_path",
		origin_world,
		target_world,
		MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD
	) as PackedVector2Array
	_expect(not route.is_empty(), "real GameMap finds a route to the adjacent resource tile")
	if route.is_empty():
		for blocked_tile: Vector2i in blocked_tiles:
			navigation.set_solid(blocked_tile, false)
		game_map.free()
		return
	var endpoint: Vector2 = route[route.size() - 1]
	var endpoint_distance: float = endpoint.distance_to(target_world)
	_expect(endpoint_distance > 28.0, "real route endpoint reproduces the former 28px interaction gap")
	_expect(
		endpoint_distance <= MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD,
		"real route endpoint satisfies the exact shared gather radius"
	)

	var resource: ResourceNode = RESOURCE_SCENE.instantiate() as ResourceNode
	resource.resource_type = "food"
	resource.total_amount = 20
	resource.tile_position = target_tile
	resource.global_position = target_world
	resources_container.add_child(resource)
	registry[target_tile] = resource
	fog.fog_grid[target_tile.y][target_tile.x] = MapData.FogState.VISIBLE
	_expect(
		game_map.call(
			"get_nearest_reachable_resource_node",
			"food",
			origin_world,
			0,
			{}
		) == resource,
		"reachable lookup accepts only the resource whose real endpoint is actionable"
	)

	var villager: Villager = VILLAGER_SCENE.instantiate() as Villager
	villager.player_owner = 0
	villager.global_position = origin_world
	game_map.get_node("UnitsContainer").add_child(villager)
	_expect(bool(villager.command_gather(resource)), "visible route-accepted resource accepts a gather order")
	villager.set("_gather_offset", Vector2(10.0, 0.0))
	_expect(
		endpoint.distance_to(target_world + Vector2(10.0, 0.0))
		> MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD,
		"opposing production offset lies outside the radius at the only legal endpoint"
	)
	var remaining_before: int = resource.remaining
	for _step in range(120):
		villager._process(0.1)
		if villager.carried_amount > 0:
			break
	_expect(villager.carried_amount > 0, "villager harvests after reaching the lookup-accepted endpoint")
	_expect(resource.remaining < remaining_before, "endpoint harvest decrements real resource stock")
	_expect_eq(Villager.BUILD_APPROACH_DISTANCE, 40.0, "building and Farm interaction radius remains unchanged")

	for blocked_tile: Vector2i in blocked_tiles:
		navigation.set_solid(blocked_tile, false)
	game_map.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] autonomous_navigation_recovery: exact gather disks, Farm open/sealed footprint edges, bounded separation, route recovery, and drop-off cancellation")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] autonomous_navigation_recovery: %s" % failure)
	get_tree().quit(1)
