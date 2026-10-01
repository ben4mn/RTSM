extends "res://tools/test_paid_worker_recovery.gd"
## Paid Main placement and real worker harvest/build/navigation. Explicit natural
## wood depletion isolates a saved job that disappears before its House finishes.
## No fixture harvest amount is credited to either player's resource bank.

func _run() -> void:
	AudioManager.set_all_enabled(false)
	for mode: String in ["return", "stop", "move", "missing_depot", "manual_return"]:
		await _start()
		if mode == "manual_return":
			await _manual_partial_return()
		else:
			await _builder_cargo_case(mode)
		_main.free()
		_workers.clear()
		GameManager.set_state(GameManager.GameState.MENU)
		await get_tree().process_frame
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("[PASS] paid_builder_cargo_return: five paid Main cargo/ownership cases; House resource removal, exact partial return, Stop/Move, waiting/missing depot with paid replacement, manual return and damaged return-only intent")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] paid_builder_cargo_return: " + failure)
		get_tree().quit(1)


func _builder_cargo_case(mode: String) -> void:
	var worker: Villager = _workers[0]
	worker.set_process(true)
	_track(worker)
	var wood: ResourceNode = _map.get_nearest_reachable_resource_node("wood", worker.global_position, 0) as ResourceNode
	_expect(wood != null and worker.command_gather(wood), mode + ": real wood job required")
	if wood == null:
		return
	await _until(func() -> bool: return worker.carried_amount >= 4, 40.0)
	_expect(worker.carried_amount == 4, mode + ": natural partial harvest must be four wood")
	var cargo_before: int = worker.carried_amount
	var wood_before: int = ResourceManager.get_resource(0, "wood")
	for other: Villager in _workers:
		if other != worker:
			other.command_move(_map.tile_to_world(_map.map_generator.spawn_positions[0] + Vector2i(7, 5)))
	var house: BuildingBase = _place_paid_house()
	if house == null:
		return
	_expect(worker.build_target == house and worker.current_state == UnitBase.State.BUILDING, mode + ": actual loaded worker must accept the paid House")
	if mode == "missing_depot":
		# Remove availability, without destroying the sole TC and ending the match.
		# The replacement below is a normal paid/buildable Wood depot.
		for depot: Node in get_tree().get_nodes_in_group("dropoff_buildings"):
			if depot is BuildingBase and (depot as BuildingBase).player_owner == 0:
				depot.remove_from_group("dropoff_buildings")
	var saved_ref: WeakRef = weakref(wood)
	# Deplete through the production API and registry signal. The removed natural
	# stock is an explicit diagnostic fixture; the worker's own four wood remains.
	for value: Variant in _map.resource_nodes.values().duplicate():
		if value is ResourceNode and (value as ResourceNode).resource_type == "wood":
			var resource := value as ResourceNode
			resource.harvest(resource.remaining)
	await _until(func() -> bool: return house.state == BuildingBase.State.ACTIVE, 60.0)
	_expect(house.state == BuildingBase.State.ACTIVE and saved_ref.get_ref() == null, mode + ": House must complete naturally after saved target is removed")
	if mode == "missing_depot":
		_expect(worker.get_work_status() == "Waiting for drop-off" and worker.get_economy_task() == "" and worker.carried_amount == cargo_before, "missing depot: partial cargo must wait without claiming a gather job")
		var camp: BuildingBase = _place_paid_building(BuildingData.BuildingType.LUMBER_CAMP)
		if camp == null:
			return
		_expect(worker.build_target == camp, "replacement depot: waiting worker must accept paid construction")
		await _until(func() -> bool: return camp.state == BuildingBase.State.ACTIVE, 60.0)
		await _until(func() -> bool: return int(_deposits["wood"]) == cargo_before, 40.0)
		_expect(worker.current_state == UnitBase.State.IDLE and worker.carried_amount == 0 and worker.get_economy_task() == "", "replacement depot: one real deposit must return worker to Idle")
		_expect(int(_deposits["wood"]) == cargo_before and ResourceManager.get_resource(0, "wood") == wood_before - 50 - 100 + cargo_before, "replacement depot: paid 50+100 wood and exactly one original cargo deposit")
		print("PAID_BUILDER_MISSING_DEPOT ", JSON.stringify({"cargo_before":cargo_before,"deposits":_deposits,"bank_wood":ResourceManager.get_resource(0,"wood"),"replacement_active":camp.state == BuildingBase.State.ACTIVE,"status":worker.get_work_status()}))
		return
	_expect(worker.is_returning_resources() and worker.carried_amount == cargo_before, mode + ": natural completion must accept exact cargo return")
	_expect(not worker.path.is_empty() and worker.dropoff_target != null, mode + ": accepted return must have a reachable real depot route")
	if mode == "stop":
		worker.command_stop()
	elif mode == "move":
		worker.command_move(_map.tile_to_world(_map.map_generator.spawn_positions[0] + Vector2i(9, 3)))
	if mode != "return":
		var command_time: float = GameManager.game_time
		await _until(func() -> bool: return GameManager.game_time > command_time + 25.0, 30.0)
		_expect(not worker.is_returning_resources() and worker.carried_amount == cargo_before, mode + ": explicit command must cancel deferred return and preserve cargo")
		_expect(int(_deposits["wood"]) == 0 and ResourceManager.get_resource(0, "wood") == wood_before - 50, mode + ": canceled return deposited cargo anyway")
	else:
		await _until(func() -> bool: return int(_deposits["wood"]) == cargo_before, 45.0)
		var deposited_time: float = GameManager.game_time
		await _until(func() -> bool: return GameManager.game_time > deposited_time + 10.0, 15.0)
		_expect(worker.current_state == UnitBase.State.IDLE and worker.carried_amount == 0 and worker.get_economy_task() == "", "return: delivered worker must idle without inventing a gather job")
		_expect(int(_deposits["wood"]) == cargo_before and ResourceManager.get_resource(0, "wood") == wood_before - 50 + cargo_before, "return: old cargo must deposit exactly once under its original type")
	print("PAID_BUILDER_CARGO ", JSON.stringify({"mode": mode, "house_cost": 50, "house_progress": house.build_progress, "saved_target_removed": saved_ref.get_ref() == null, "cargo_before": cargo_before, "cargo_after": worker.carried_amount, "deposits": _deposits, "bank_wood": ResourceManager.get_resource(0, "wood"), "state": worker.current_state, "status": worker.get_work_status()}))


func _place_paid_house() -> BuildingBase:
	return _place_paid_building(BuildingData.BuildingType.HOUSE)


func _place_paid_building(building_type: int) -> BuildingBase:
	var placement: BuildingPlacement = _main.get("_building_placement")
	var anchor: Vector2i = _map.map_generator.spawn_positions[0]
	var cost: int = int(BuildingData.get_building_cost(building_type).get("wood", 0))
	for radius: int in range(5, 10):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var point: Vector2 = _map.tile_to_world(anchor + Vector2i(dx, dy))
				if not placement.revalidate_confirmation(building_type, point, 0):
					continue
				var before: int = ResourceManager.get_resource(0, "wood")
				_main.call("_on_placement_confirmed", building_type, point)
				_expect(ResourceManager.get_resource(0, "wood") == before - cost, "depot/House placement must spend its exact normal wood cost")
				return (_main.get("_player_buildings")[0] as Array).back() as BuildingBase
	_expect(false, "no legal paid depot/House site")
	return null


func _manual_partial_return() -> void:
	var worker: Villager = _workers[0]
	worker.set_process(true)
	_track(worker)
	var wood: Node2D = _map.get_nearest_reachable_resource_node("wood", worker.global_position, 0)
	_expect(wood != null and worker.command_gather(wood), "manual return: real harvest required")
	if wood == null:
		return
	await _until(func() -> bool: return worker.carried_amount >= 4, 40.0)
	var cargo: int = worker.carried_amount
	var bank: int = ResourceManager.get_resource(0, "wood")
	worker.command_stop()
	_expect(worker.command_return_resources(), "manual return: partial idle cargo rejected")
	_expect(worker.is_returning_resources() and worker.get_economy_task() == "" and not worker.has_active_gather_order(), "manual return: cargo return invented a gather job")
	worker.take_damage(1.0)
	_expect(worker.is_auto_recovering() and worker._recovery_work_state == UnitBase.State.IDLE, "manual return: damage invented a retained gather order")
	await _until(func() -> bool: return int(_deposits["wood"]) == cargo, 80.0)
	var completion_time: float = GameManager.game_time
	await _until(func() -> bool: return GameManager.game_time > completion_time + 10.0, 15.0)
	_expect(worker.current_state == UnitBase.State.IDLE and worker.carried_amount == 0 and worker.get_economy_task() == "", "manual return: completed return/recovery resumed canceled gathering")
	_expect(int(_deposits["wood"]) == cargo and ResourceManager.get_resource(0, "wood") == bank + cargo, "manual return: damage lost/duplicated/retyped exact old cargo")
	print("PAID_MANUAL_PARTIAL_RETURN ", JSON.stringify({"cargo_before":cargo,"cargo_after":worker.carried_amount,"deposits":_deposits,"bank_wood":ResourceManager.get_resource(0,"wood"),"status":worker.get_work_status()}))
