extends Node
## Paid production-world Farm/Range placements reproduce a sealed anchor corner.
## Workers move, harvest, die, construct and deposit through normal processing.

var _failures: Array[String] = []
var _main: Node
var _map: Node2D
var _workers: Array[Villager] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_tree().root.size = Vector2i(844, 390)
	GameManager.ui_scale = 1.15
	GameManager.apply_preferences()
	for range_y: int in [43, 44]:
		await _start()
		await _corner_farm_case(range_y)
		_main.free()
		_workers.clear()
		GameManager.set_state(GameManager.GameState.MENU)
		await get_tree().process_frame
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("[PASS] building_perimeter_work: two paid interrupted Farms/Ranges, legal edge progress, loaded resume/cargo, cancel/reassign, Farm harvest and TC deposits")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] building_perimeter_work: %s" % failure)
		get_tree().quit(1)

func _start() -> void:
	GameManager.set_state(GameManager.GameState.MENU)
	GameManager.selected_map_seed = 202
	GameManager.selected_population_limit = 30
	GameManager.selected_difficulty = AIController.Difficulty.EASY
	GameManager.guided_opening_enabled = false
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_map = _main.get("game_map")
	_main.get("ai_controller").set_process(false)
	(_main.get("ai_controller").get("_decision_timer") as Timer).stop()
	_map.set_process(false)
	_main.call("_select_town_center")
	_map.camera.reset_smoothing()
	_map.camera.force_update_scroll()
	Engine.time_scale = 4.0
	for unit: Node in _main.get("_player_units")[0]:
		if unit is Villager:
			_workers.append(unit)

func _corner_farm_case(range_y: int) -> void:
	var farm: BuildingBase = _paid_place(BuildingData.BuildingType.FARM, Vector2i(6, 45))
	if farm == null:
		return
	var first: Villager = null
	for worker: Villager in _workers:
		if worker.build_target == farm:
			first = worker
	_expect(first != null, "paid opening Farm needs a natural builder")
	if first == null:
		return
	await _until(func() -> bool: return farm.build_progress >= 0.11, 60.0)
	_expect(farm.build_progress >= 0.11 and farm.state == BuildingBase.State.CONSTRUCTING, "Farm must have genuine interrupted progress")
	first.take_damage(10000.0)
	await get_tree().process_frame
	_workers.erase(first)
	for index: int in range(_workers.size()):
		var kind: String = ["food", "gold", "wood"][index]
		var resource: Node2D = _map.get_nearest_reachable_resource_node(kind, _workers[index].global_position, 0)
		_expect(resource != null and _workers[index].command_gather(resource), "paid Range setup needs normal %s labor" % kind)
	var age_cost: Dictionary = GameManager.get_age_up_cost(0, 2)
	await _until(func() -> bool: return ResourceManager.can_afford(0, age_cost) and ResourceManager.get_resource(0, "wood") >= 150, 350.0)
	_expect(ResourceManager.can_afford(0, age_cost), "natural labor did not finance Feudal")
	_main.call("_on_age_up_requested")
	_expect(GameManager.get_player_age(0) == 2, "Feudal must be purchased normally")
	var range_building: BuildingBase = _paid_place(BuildingData.BuildingType.ARCHERY_RANGE, Vector2i(3, range_y))
	if range_building == null:
		return
	await _until(func() -> bool: return range_building.state == BuildingBase.State.ACTIVE, 80.0)
	_expect(range_building.state == BuildingBase.State.ACTIVE, "paid three-tile Range must complete naturally")
	var interrupted_progress: float = farm.build_progress
	var worker: Villager = _workers.back()
	var wood: Node2D = _map.get_nearest_reachable_resource_node("wood", worker.global_position, 0)
	_expect(wood != null and worker.command_gather(wood), "replacement worker needs real original wood order")
	if wood == null:
		return
	var deposits: Dictionary = {"wood": 0, "food": 0}
	worker.resource_deposited.connect(func(kind: String, amount: int) -> void:
		deposits[kind] = int(deposits.get(kind, 0)) + amount
	)
	if range_y == 43:
		await _until(func() -> bool: return worker.current_state == UnitBase.State.MOVING and bool(worker.get("_dropoff_route_active")) and worker.carried_amount > 0, 100.0)
		_expect(worker.carried_amount > 0 and bool(worker.get("_dropoff_route_active")), "loaded case requires genuine delivery travel")
	else:
		# Cancel the active gather order, travel naturally, then interrupt the first
		# build approach with another explicit Move before deliberately reassigning.
		await _until(func() -> bool: return worker.carried_amount == 0, 100.0)
		worker.command_move_path(_map.get_navigation_world_path(worker.global_position, _map.tile_to_world(Vector2i(8, 33)), 4.0))
		await _until(func() -> bool: return worker.current_state == UnitBase.State.IDLE, 60.0)
		await _tap_farm(worker, farm)
		worker.command_move_path(_map.get_navigation_world_path(worker.global_position, _map.tile_to_world(Vector2i(8, 33)), 4.0))
		await _until(func() -> bool: return worker.current_state == UnitBase.State.IDLE, 30.0)
		await _wait_seconds(12.0)
		_expect(is_equal_approx(farm.build_progress, interrupted_progress), "explicit Move must cancel perimeter construction")
		_expect(not bool(worker.get("_dropoff_route_active")), "canceled worker must not retain a delivery route")
	var cargo_before: int = worker.carried_amount
	var deposited_before: int = int(deposits["wood"])
	var anchor_route: PackedVector2Array = _map.get_navigation_world_path(worker.global_position, farm.global_position, Villager.BUILD_APPROACH_DISTANCE)
	_expect(not anchor_route.is_empty() and anchor_route[-1].distance_to(farm.global_position) > Villager.BUILD_APPROACH_DISTANCE, "corner fixture must reproduce the old anchor-route rejection")
	var work_route: PackedVector2Array = _map.get_building_work_world_path(worker.global_position, farm.global_position, farm.footprint, Villager.BUILD_APPROACH_DISTANCE)
	_expect(not work_route.is_empty(), "reachable outer Farm edge must yield a real route")
	_expect(bool(_main.call("_can_ai_builder_reach", worker, farm.global_position, farm.footprint)), "Main preflight must accept the same reachable footprint")
	await _tap_farm(worker, farm)
	var blocking_house: BuildingBase = null
	if range_y == 44:
		# A second normal placement can occupy the chosen work endpoint while
		# the builder is traveling. It must choose another edge, preserving its
		# construction order rather than repeatedly approaching the blocked tile.
		var first_endpoint: Vector2 = worker.get("_building_work_destination")
		var endpoint_tile: Vector2i = _map.world_to_tile(first_endpoint)
		blocking_house = _paid_place(BuildingData.BuildingType.HOUSE, endpoint_tile)
		_expect(blocking_house != null and not _map.is_tile_walkable(endpoint_tile), "paid House must block the cached Farm work endpoint")
		await get_tree().process_frame
		_expect((worker.get("_building_work_destination") as Vector2).distance_to(first_endpoint) > 1.0 and worker.build_target == farm, "blocked endpoint must select another Farm edge without losing the job")
	var started: float = GameManager.game_time
	var old_progress: float = farm.build_progress
	var deadline: float = started + 80.0
	while farm.state != BuildingBase.State.ACTIVE and GameManager.game_time < deadline:
		_expect(worker.carried_amount == cargo_before, "perimeter construction must preserve original cargo")
		if farm.build_progress > old_progress:
			_expect(_map.get_building_work_distance(worker.global_position, farm.global_position, farm.footprint) <= Villager.BUILD_APPROACH_DISTANCE + 0.01, "construction progressed outside the footprint work radius")
			_expect(_map.is_tile_walkable(_map.world_to_tile(worker.global_position)), "replacement must work from real walkable perimeter terrain")
		old_progress = farm.build_progress
		await get_tree().process_frame
	_expect(farm.state == BuildingBase.State.ACTIVE, "corner Farm did not finish through natural replacement labor")
	var construction_seconds: float = GameManager.game_time - started
	if range_y == 43:
		_expect(worker.gather_target == wood and worker.gather_type == Villager.GatherType.WOOD, "loaded builder must resume exact original wood source")
		await _until(func() -> bool: return int(deposits["wood"]) - deposited_before >= cargo_before, 80.0)
		_expect(int(deposits["wood"]) - deposited_before == cargo_before, "original wood cargo must deposit exactly once")
	else:
		_expect(worker.gather_target == farm and worker.gather_type == Villager.GatherType.FOOD, "unassigned builder must start its deliberately completed Farm instead of restoring canceled wood")
	# Ignore natural berries only for the nearest-target query: no map/resource
	# mutation. The known visible owned Farm must be a reachable food candidate.
	var exclusions: Dictionary = {}
	for resource: Node in get_tree().get_nodes_in_group("resources"):
		if resource != farm:
			exclusions[resource.get_instance_id()] = true
	_expect(_map.get_nearest_reachable_resource_node("food", worker.global_position, 0, exclusions) == farm, "nearest reachable query must retain the known Farm edge")
	var stock_before: int = farm.farm_remaining
	var food_before: int = int(deposits["food"])
	_expect(worker.command_gather(farm), "completed owned Farm must accept normal gathering")
	await _until(func() -> bool: return int(deposits["food"]) > food_before, 100.0)
	_expect(farm.farm_remaining < stock_before and int(deposits["food"]) - food_before == worker.carry_capacity, "natural Farm harvest must deliver one real food load to the existing TC")
	_expect(worker.gather_target == farm, "Farm gathering must not silently retarget an old berry source")
	if blocking_house != null:
		_expect(blocking_house.state == BuildingBase.State.ACTIVE, "paid two-tile House must also finish through ordinary edge work")
	print("[METRIC] ", JSON.stringify({"range_tile": str(Vector2i(3, range_y)), "paid_farm_and_range": true, "farm_interrupted_progress": interrupted_progress, "old_anchor_endpoint_distance": anchor_route[-1].distance_to(farm.global_position), "work_endpoint_distance": _map.get_building_work_distance(work_route[-1], farm.global_position, farm.footprint), "construction_seconds": construction_seconds, "cargo_preserved": cargo_before, "wood_deposit": int(deposits["wood"]) - deposited_before, "farm_food_deposit": int(deposits["food"]) - food_before, "tc_dropoff_unchanged": true, "paid_endpoint_blocking_house": blocking_house != null}))

func _paid_place(kind: int, tile: Vector2i) -> BuildingBase:
	var before: int = (_main.get("_player_buildings")[0] as Array).size()
	var wood_before: int = ResourceManager.get_resource(0, "wood")
	_main.call("_on_placement_confirmed", kind, _map.tile_to_world(tile))
	var buildings: Array = _main.get("_player_buildings")[0]
	_expect(buildings.size() == before + 1, "paid %s placement at%s failed: %s" % [BuildingData.get_building_name(kind), tile, _main.get("_last_placement_feedback")])
	if buildings.size() != before + 1:
		return null
	_expect(wood_before - ResourceManager.get_resource(0, "wood") == int(BuildingData.get_building_cost(kind)["wood"]), "placement must pay exact building cost")
	return buildings.back()

func _tap_farm(worker: Villager, farm: BuildingBase) -> void:
	var picker: SelectionManager = _map.selection_mgr
	picker.select_single(worker)
	picker.set("_last_tap_time", 0.0)
	var physical: Vector2 = get_viewport().get_final_transform() * get_viewport().get_canvas_transform() * farm.global_position + Vector2(6, 6)
	for pressed: bool in [true, false]:
		var tap := InputEventScreenTouch.new()
		tap.index = 0
		tap.position = physical
		tap.pressed = pressed
		get_viewport().push_input(tap, false)
		await get_tree().process_frame
	_expect(str(picker.touch_input_diagnostics.get("action", "")) == "build" and worker.build_target == farm and worker.current_state == UnitBase.State.BUILDING, "actual foundation touch must start exact Farm construction")

func _until(condition: Callable, maximum_seconds: float) -> void:
	var deadline: float = GameManager.game_time + maximum_seconds
	var wall: int = Time.get_ticks_msec() + 60000
	while not bool(condition.call()) and GameManager.game_time < deadline and Time.get_ticks_msec() < wall:
		await get_tree().process_frame

func _wait_seconds(seconds: float) -> void:
	var deadline: float = GameManager.game_time + seconds
	while GameManager.game_time < deadline:
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
