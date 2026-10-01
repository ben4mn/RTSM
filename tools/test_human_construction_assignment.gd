extends Node
## Real human placement transactions and natural worker construction on a seeded
## map. No progress, cargo, worker positions, or completion states are injected.

var _failures: Array[String] = []
var _main: Node = null
var _workers: Array[Villager] = []
var _wood_deposited: int = 0
var _original_time_scale: float = 1.0
@onready var root: Window = get_tree().root


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_original_time_scale = Engine.time_scale
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	GameManager.selected_population_limit = 30
	root.size = Vector2i(844, 390)
	if await _start_match():
		await _test_moving_workers_complete_house_and_barracks()
	await _close_match()
	if await _start_match():
		await _test_loaded_moving_worker_and_busy_builder_feedback()
	await _close_match()
	if await _start_match():
		await _test_destroyed_construction_order_recovery()
	await _close_match()
	if await _start_match():
		await _test_paid_newborn_labor_after_build_spending()
	await _close_match()
	for mode: String in ["empty_return", "loaded_dropoff", "manual_move", "flee"]:
		if await _start_match():
			await _test_natural_gather_travel_builder_resume(mode)
		await _close_match()
	Engine.time_scale = _original_time_scale
	if _failures.is_empty():
		print("[PASS] human_construction_assignment: paid natural construction, newborn labor, active gather/dropoff resume, canceled orders remain idle, cargo and existing jobs preserved")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] human_construction_assignment: %s" % failure)
		get_tree().quit(1)


func _start_match() -> bool:
	GameManager.set_state(GameManager.GameState.MENU)
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	if _main.get("_building_placement") == null:
		_expect(false, "match initialization timed out")
		return false
	for frame: int in range(8):
		await get_tree().process_frame
	# Match readiness resets the engine speed. Accelerate only after that reset,
	# so the wall guard still permits travel plus a full 30-second Barracks.
	Engine.time_scale = 4.0
	GameManager.game_speed = 1.0
	# Isolate human construction from enemy strategy; every worker, map, resource
	# and building still uses its normal runtime process.
	(_main.get("ai_controller") as Node).set_process(false)
	_workers.clear()
	for unit: Node in _main.get("_player_units")[0]:
		if unit is Villager:
			_workers.append(unit as Villager)
	_expect(_workers.size() == 4, "seeded opening should have four human workers")
	return _workers.size() == 4


func _close_match() -> void:
	_workers.clear()
	if is_instance_valid(_main):
		_main.free()
	_main = null
	GameManager.set_state(GameManager.GameState.MENU)
	await get_tree().process_frame


func _test_moving_workers_complete_house_and_barracks() -> void:
	var map: Node2D = _main.get("game_map") as Node2D
	var spawn: Vector2i = map.map_generator.spawn_positions[0]
	for worker: Villager in _workers:
		worker.command_move(map.tile_to_world(spawn + Vector2i(7, 5)))
		_expect(worker.current_state == UnitBase.State.MOVING, "opening move order did not enter MOVING")
	var wood_before: int = ResourceManager.get_resource(0, "wood")
	var house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	if house == null:
		return
	_expect(wood_before - ResourceManager.get_resource(0, "wood") == 50, "House was not a paid 50-wood human placement")
	var house_builder: Villager = _builder_for(house)
	_expect(house_builder != null and _builder_count(house) == 1, "all-MOVING opening did not assign exactly one House builder")
	for worker: Villager in _workers:
		if worker != house_builder:
			_expect(worker.current_state == UnitBase.State.MOVING, "unassigned opening worker lost its move order")
	wood_before = ResourceManager.get_resource(0, "wood")
	var barracks: BuildingBase = _place(BuildingData.BuildingType.BARRACKS, map.world_to_tile(house.global_position))
	if barracks == null:
		return
	_expect(wood_before - ResourceManager.get_resource(0, "wood") == 150, "Barracks was not a paid 150-wood human placement")
	var barracks_builder: Villager = _builder_for(barracks)
	_expect(barracks_builder != null and _builder_count(barracks) == 1, "remaining MOVING workers did not staff Barracks")
	_expect(barracks_builder != house_builder, "placing Barracks stole the existing House worker")
	if house_builder != null:
		_expect(house_builder.build_target == house, "existing House construction order was replaced")
	_expect(barracks.global_position.distance_to(house.global_position) <= 256.0, "Barracks fixture should be near the House/TC opening")
	var result: Dictionary = await _wait_for_natural_construction([house, barracks], 80.0)
	for building: BuildingBase in [house, barracks]:
		var name: String = BuildingData.get_building_name(building.building_type)
		_expect(building.state == BuildingBase.State.ACTIVE and is_equal_approx(building.build_progress, 1.0), "%s never completed through worker process" % name)
		var active_seconds: float = float(result.get(building.get_instance_id(), -1.0))
		_expect(absf(active_seconds - building.build_time) <= 0.5, "%s natural build duration was %.2fs, expected %.2fs" % [name, active_seconds, building.build_time])
	print("CONSTRUCTION_TIMING ", JSON.stringify({"house_seconds": result.get(house.get_instance_id(), -1.0), "barracks_seconds": result.get(barracks.get_instance_id(), -1.0)}))


func _test_loaded_moving_worker_and_busy_builder_feedback() -> void:
	var map: Node2D = _main.get("game_map") as Node2D
	var spawn: Vector2i = map.map_generator.spawn_positions[0]
	for worker: Villager in _workers:
		worker.command_stop()
	var loaded: Villager = _workers[0]
	var wood: Node2D = map.get_nearest_reachable_resource_node("wood", loaded.global_position, 0)
	_expect(wood != null and loaded.command_gather(wood), "loaded-worker fixture could not issue a real wood gather order")
	if wood == null:
		return
	var deadline: float = GameManager.game_time + 90.0
	var wall_deadline: int = Time.get_ticks_msec() + 30000
	while GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		if loaded.carried_amount > 0 and loaded.carried_resource_type == "wood":
			break
		await get_tree().process_frame
	_expect(loaded.carried_amount > 0 and loaded.carried_resource_type == "wood", "worker never naturally harvested wood")
	if loaded.carried_amount <= 0 or loaded.carried_resource_type != "wood":
		return
	var carried_before: int = loaded.carried_amount
	loaded.command_move(map.tile_to_world(spawn + Vector2i(7, 5)))
	_expect(loaded.current_state == UnitBase.State.MOVING, "loaded worker did not enter MOVING")
	var busy_house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	if busy_house == null:
		return
	for worker: Villager in _workers:
		if worker != loaded:
			worker.command_build(busy_house)
	var loaded_house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	if loaded_house == null:
		return
	_expect(_builder_for(loaded_house) == loaded and _builder_count(loaded_house) == 1, "only free loaded MOVING worker was not assigned")
	_expect(loaded.carried_amount == carried_before and loaded.carried_resource_type == "wood", "automatic build assignment lost carried wood")
	for worker: Villager in _workers:
		if worker != loaded:
			_expect(worker.build_target == busy_house, "loaded House placement stole an existing building worker")
	_wood_deposited = 0
	loaded.resource_deposited.connect(_on_loaded_resource_deposited)
	deadline = GameManager.game_time + 90.0
	wall_deadline = Time.get_ticks_msec() + 30000
	while loaded_house.state != BuildingBase.State.ACTIVE and GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		_expect(loaded.carried_amount == carried_before and loaded.carried_resource_type == "wood", "wood cargo changed during construction")
		await get_tree().process_frame
	_expect(loaded_house.state == BuildingBase.State.ACTIVE, "loaded MOVING worker did not finish House naturally")
	_expect(loaded.carried_amount + _wood_deposited >= carried_before, "construction completion lost harvested wood")
	loaded.command_stop()
	if loaded.carried_amount > 0:
		_expect(loaded.carried_resource_type == "wood" and loaded.command_return_resources(), "preserved wood could not be returned to Town Center")
	deadline = GameManager.game_time + 60.0
	wall_deadline = Time.get_ticks_msec() + 20000
	while _wood_deposited < carried_before and GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		await get_tree().process_frame
	_expect(_wood_deposited >= carried_before, "preserved harvested wood never deposited through normal drop-off")

	# Every worker now has a live, real construction order. A second paid
	# foundation must tell the player how to staff it and leave those jobs alone.
	for worker: Villager in _workers:
		worker.command_stop()
	var occupied_house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	if occupied_house == null:
		return
	for worker: Villager in _workers:
		worker.command_build(occupied_house)
	var wood_before: int = ResourceManager.get_resource(0, "wood")
	var unstaffed_house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	if unstaffed_house == null:
		return
	_expect(wood_before - ResourceManager.get_resource(0, "wood") == 50, "no-builder foundation was not a real paid placement")
	_expect(_builder_count(unstaffed_house) == 0 and is_zero_approx(unstaffed_house.build_progress), "no-builder foundation unexpectedly stole a worker")
	for worker: Villager in _workers:
		_expect(worker.build_target == occupied_house, "no-candidate placement replaced an existing build job")
	var feedback: String = str(_main.get("_last_placement_feedback"))
	_expect(feedback.contains("free villager") and feedback.contains("foundation"), "no-builder placement has no actionable feedback")
	var texts: Array[String] = []
	_collect_labels((_main.get("hud") as Node).get("_notification_container") as Node, texts)
	_expect(feedback in texts, "no-builder feedback was not shown in the HUD")


func _test_destroyed_construction_order_recovery() -> void:
	var map: Node2D = _main.get("game_map") as Node2D
	var spawn: Vector2i = map.map_generator.spawn_positions[0]
	for worker: Villager in _workers:
		worker.command_stop()
	var old_house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	if old_house == null:
		return
	var builder: Villager = _builder_for(old_house)
	_expect(builder != null, "destroyed-job setup needs an assigned builder")
	if builder == null:
		return
	# Destruction may happen between labor assignment and a worker tick.
	builder.set_process(false)
	old_house.take_damage(old_house.max_hp)
	# Buildings finish their normal destruction fade before freeing the node.
	var fade_deadline: int = Time.get_ticks_msec() + 3000
	while is_instance_valid(old_house) and Time.get_ticks_msec() < fade_deadline:
		await get_tree().process_frame
	_expect(not is_instance_valid(builder.build_target), "destroyed construction target should be freed")
	var replacement: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	_expect(replacement != null and _builder_count(replacement) == 1, "paid replacement could not receive a free builder beside a stale job")
	builder.set_process(true)
	for frame: int in range(3):
		await get_tree().process_frame
	_expect(builder.build_target == null, "worker did not clear its destroyed construction order")


func _test_paid_newborn_labor_after_build_spending() -> void:
	var map: Node2D = _main.get("game_map") as Node2D
	var spawn: Vector2i = map.map_generator.spawn_positions[0]
	var house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	var barracks: BuildingBase = _place(BuildingData.BuildingType.BARRACKS, spawn)
	if house == null or barracks == null:
		return
	var tc: BuildingBase = _main.get("_player_town_center") as BuildingBase
	var food_before: int = ResourceManager.get_resource(0, "food")
	for count: int in range(3):
		_main.call("_on_train_unit_requested", tc, UnitData.UnitType.VILLAGER)
	var worker_cost: int = int(UnitData.get_unit_stats(UnitData.UnitType.VILLAGER)["cost"]["food"])
	_expect(food_before - ResourceManager.get_resource(0, "food") == worker_cost * 3, "three newborns must use normal paid training")
	var deadline: float = GameManager.game_time + 70.0
	var wall_deadline: int = Time.get_ticks_msec() + 20000
	var newborns: Array[Villager] = []
	while GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		newborns.clear()
		for unit: Node in _main.get("_player_units")[0]:
			if unit is Villager and unit not in _workers:
				newborns.append(unit as Villager)
		if newborns.size() == 3:
			break
		await get_tree().process_frame
	var counts: Dictionary = {"food": 0, "wood": 0, "gold": 0}
	for worker: Villager in newborns:
		match worker.gather_type:
			Villager.GatherType.FOOD: counts["food"] += 1
			Villager.GatherType.WOOD: counts["wood"] += 1
			Villager.GatherType.GOLD: counts["gold"] += 1
	_expect(newborns.size() == 3, "paid newborns did not complete naturally")
	_expect(int(counts["food"]) >= 2 and int(counts["wood"]) <= 1 and int(counts["gold"]) == 0, "opening wood purchases must not send every newborn to wood or extra gold: %s" % counts)
	print("PAID_NEWBORN_LABOR ", JSON.stringify(counts))


func _test_natural_gather_travel_builder_resume(mode: String) -> void:
	var map: Node2D = _main.get("game_map") as Node2D
	var spawn: Vector2i = map.map_generator.spawn_positions[0]
	for worker: Villager in _workers:
		worker.command_stop()
	# Hold other labor on a separate paid construction job. The observed worker
	# is the only free candidate; its travel, cargo and build progress are natural.
	var occupied: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	if occupied == null:
		return
	var target_worker: Villager = null
	for worker: Villager in _workers:
		if worker.build_target != occupied and target_worker == null:
			target_worker = worker
		else:
			worker.command_build(occupied)
			worker.set_process(false)
	if target_worker == null:
		_expect(false, "%s needs one free worker" % mode)
		return
	var nearest: Node2D = map.get_nearest_reachable_resource_node("wood", target_worker.global_position, 0)
	var original_resource: Node2D = null
	var farthest_distance: float = -1.0
	for entry: Node in get_tree().get_nodes_in_group("resources"):
		if not entry is Node2D or not map.is_resource_target_visible_to_player(entry, 0):
			continue
		if not map.is_resource_target_valid(entry, "wood", 0) or entry == nearest:
			continue
		var resource: Node2D = entry as Node2D
		var route: PackedVector2Array = map.get_navigation_world_path(target_worker.global_position, resource.global_position, Villager.GATHER_APPROACH_DISTANCE)
		if route.is_empty() or route[-1].distance_to(resource.global_position) > Villager.GATHER_APPROACH_DISTANCE + 1.0:
			continue
		var distance: float = target_worker.global_position.distance_squared_to(resource.global_position)
		if distance > farthest_distance:
			farthest_distance = distance
			original_resource = resource
	var gather_accepted: bool = original_resource != null and target_worker.command_gather(original_resource)
	_expect(gather_accepted, "%s needs an accepted visible resource beyond the nearest retarget" % mode)
	if not gather_accepted:
		return
	var start_position: Vector2 = target_worker.global_position
	var deposit_record: Dictionary = {"wood": 0}
	target_worker.resource_deposited.connect(func(kind: String, amount: int) -> void:
		if kind == "wood":
			deposit_record["wood"] = int(deposit_record["wood"]) + amount
	)
	var deadline: float = GameManager.game_time + 160.0
	var wall_deadline: int = Time.get_ticks_msec() + 40000
	while GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		if mode == "loaded_dropoff":
			if target_worker.current_state == UnitBase.State.MOVING and bool(target_worker.get("_dropoff_route_active")) and target_worker.carried_amount > 0:
				break
		elif mode == "empty_return":
			if int(deposit_record["wood"]) > 0 and target_worker.carried_amount == 0 and target_worker.current_state == UnitBase.State.GATHERING and target_worker.global_position.distance_to(original_resource.global_position) > Villager.GATHER_APPROACH_DISTANCE:
				break
		elif target_worker.carried_amount == 0 and target_worker.global_position.distance_to(start_position) > 8.0:
			break
		await get_tree().process_frame
	if mode == "loaded_dropoff":
		_expect(target_worker.current_state == UnitBase.State.MOVING and bool(target_worker.get("_dropoff_route_active")) and target_worker.carried_amount > 0, "natural loaded delivery never entered active MOVING route")
	else:
		_expect(target_worker.current_state == UnitBase.State.GATHERING and target_worker.carried_amount == 0, "%s must start with genuine empty gather travel" % mode)
	if mode == "empty_return":
		_expect(int(deposit_record["wood"]) > 0, "empty return fixture must first complete a natural paid resource deposit")
	elif mode == "manual_move":
		target_worker.command_move(map.tile_to_world(spawn + Vector2i(7, 5)))
	elif mode == "flee":
		target_worker.take_damage(1.0)
	if mode in ["manual_move", "flee"]:
		_expect(target_worker.current_state == UnitBase.State.MOVING and not bool(target_worker.get("_dropoff_route_active")), "%s must cancel the work route while retaining an observable stale target" % mode)
		_expect(target_worker.gather_target == original_resource, "%s fixture must expose stale resource identity, not a cleared target" % mode)
	var carried_before: int = target_worker.carried_amount
	var deposits_before: int = int(deposit_record["wood"])
	var bank_before: int = ResourceManager.get_resource(0, "wood")
	var house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, spawn)
	if house == null:
		return
	if mode == "flee":
		# Automatic placement must not cancel a worker's protective recovery. A
		# deliberate direct Build order still supersedes it and the saved old job.
		_expect(_builder_for(house) == null and target_worker.is_auto_recovering(), "new automatic placement must preserve a recovering worker's retreat")
		target_worker.command_build(house)
		_expect(not target_worker.is_auto_recovering() and _builder_for(house) == target_worker, "explicit Build must supersede automatic retreat")
	else:
		_expect(_builder_for(house) == target_worker, "%s automatic paid build assignment must choose the active candidate" % mode)
	await _wait_for_natural_construction([house], 80.0)
	_expect(house.state == BuildingBase.State.ACTIVE, "%s House must complete through normal worker progress" % mode)
	if mode in ["manual_move", "flee"]:
		_expect(target_worker.current_state == UnitBase.State.IDLE and target_worker.gather_type == Villager.GatherType.NONE, "%s canceled gather order must remain idle after construction" % mode)
	else:
		_expect(target_worker.gather_target == original_resource and target_worker.gather_type == Villager.GatherType.WOOD, "%s must resume the exact accepted resource after construction, not choose nearest wood" % mode)
		if mode == "loaded_dropoff":
			_expect(target_worker.carried_amount + int(deposit_record["wood"]) - deposits_before == carried_before, "loaded delivery cargo must remain conserved through completion")
			deadline = GameManager.game_time + 90.0
			wall_deadline = Time.get_ticks_msec() + 30000
			while int(deposit_record["wood"]) == deposits_before and GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
				await get_tree().process_frame
			_expect(int(deposit_record["wood"]) - deposits_before == carried_before, "loaded construction must deposit exactly the original harvested cargo")
			_expect(ResourceManager.get_resource(0, "wood") == bank_before - 50 + carried_before, "loaded construction bank must reflect only paid House and real cargo deposit")
	print("GATHER_TRAVEL_BUILD ", JSON.stringify({"mode": mode, "state_after": target_worker.current_state, "exact_resource": target_worker.gather_target == original_resource, "cargo_before": carried_before, "new_deposit": int(deposit_record["wood"]) - deposits_before}))


func _place(kind: int, anchor: Vector2i) -> BuildingBase:
	var map: Node2D = _main.get("game_map") as Node2D
	var placement: BuildingPlacement = _main.get("_building_placement") as BuildingPlacement
	var site: Vector2i = Vector2i(-1, -1)
	for radius: int in range(1, 10):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate: Vector2i = anchor + Vector2i(dx, dy)
				if placement.revalidate_confirmation(kind, map.tile_to_world(candidate), 0):
					site = candidate
					break
			if site.x >= 0:
				break
		if site.x >= 0:
			break
	_expect(site.x >= 0, "no legal visible site for %s" % BuildingData.get_building_name(kind))
	if site.x < 0:
		return null
	var count_before: int = (_main.get("_player_buildings")[0] as Array).size()
	_main.call("_on_placement_confirmed", kind, map.tile_to_world(site))
	var buildings: Array = _main.get("_player_buildings")[0]
	_expect(buildings.size() == count_before + 1, "human placement did not create %s: %s" % [BuildingData.get_building_name(kind), str(_main.get("_last_placement_feedback"))])
	if buildings.size() != count_before + 1:
		return null
	return buildings.back() as BuildingBase


func _wait_for_natural_construction(buildings: Array[BuildingBase], maximum_seconds: float) -> Dictionary:
	var first_progress: Dictionary = {}
	var result: Dictionary = {}
	var deadline: float = GameManager.game_time + maximum_seconds
	var wall_deadline: int = Time.get_ticks_msec() + 30000
	while GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		for building: BuildingBase in buildings:
			var key: int = building.get_instance_id()
			if building.build_progress > 0.0 and not first_progress.has(key):
				first_progress[key] = GameManager.game_time
			if building.state == BuildingBase.State.ACTIVE and not result.has(key):
				result[key] = GameManager.game_time - float(first_progress.get(key, GameManager.game_time))
		if result.size() == buildings.size():
			break
		await get_tree().process_frame
	return result


func _builder_for(building: BuildingBase) -> Villager:
	for worker: Villager in _workers:
		if worker.build_target == building:
			return worker
	return null


func _builder_count(building: BuildingBase) -> int:
	var count: int = 0
	for worker: Villager in _workers:
		count += int(worker.build_target == building)
	return count


func _on_loaded_resource_deposited(type: String, amount: int) -> void:
	if type == "wood":
		_wood_deposited += amount


func _collect_labels(node: Node, texts: Array[String]) -> void:
	if node is Label:
		texts.append((node as Label).text)
	for child: Node in node.get_children():
		_collect_labels(child, texts)


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
