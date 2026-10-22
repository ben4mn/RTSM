extends "res://tools/test_human_construction_assignment.gd"
## Explicit funded transaction fixture: pays Feudal, three new-art buildings,
## and their real Archer/Horseman queues. No construction/training progress,
## worker position, resource node stock or completion state is injected.

var _paid_complete: bool = false

func _run() -> void:
	AudioManager.set_all_enabled(false)
	if await _start_match():
		await _paid_specialists()
		_expect(_paid_complete, "Paid fixture did not reach final production assertions")
	await _close_match()
	Engine.time_scale = 1.0
	for failure: String in _failures:
		push_error("[FAIL] company_specialist_buildings: " + failure)
	if _failures.is_empty():
		print("[PASS] company_specialist_buildings: funded paid Feudal, Camp/Range/Stable placement, natural builder completion, exact Archer/Horseman purchases and real production/egress")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _paid_specialists() -> void:
	# This is a deterministic transaction/production test, not an unassisted
	# match economy claim. Budget is explicit and every action still pays.
	for resource: String in ["food", "wood", "gold"]:
		ResourceManager.add_resource(0, resource, maxi(0, 1000 - ResourceManager.get_resource(0, resource)))
	var age_before: int = GameManager.get_player_age(0)
	var age_cost: Dictionary = GameManager.get_age_up_cost(0, age_before + 1)
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	_main.call("_on_age_up_requested")
	_expect(GameManager.get_player_age(0) == age_before + 1, "Feudal purchase failed")
	_check_spend(bank, age_cost, "Feudal")
	var map: Node2D = _main.get("game_map")
	var home: Vector2i = map.map_generator.spawn_positions[0]
	var buildings: Array[BuildingBase] = []
	for kind: int in [BuildingData.BuildingType.RESOURCE_CAMP, BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE]:
		bank = ResourceManager.get_all_resources(0).duplicate()
		var building: BuildingBase = _place(kind, home)
		if building == null:
			return
		buildings.append(building)
		_check_spend(bank, BuildingData.get_building_cost(kind), BuildingData.get_building_name(kind))
		_expect(building.state == BuildingBase.State.CONSTRUCTING and building.build_progress == 0.0, building.building_name + " starts as a real foundation")
		_expect(_builder_count(building) == 1, building.building_name + " gets one natural worker")
	var durations: Dictionary = await _wait_for_natural_construction(buildings, 120.0)
	for building: BuildingBase in buildings:
		_expect(building.state == BuildingBase.State.ACTIVE, building.building_name + " did not complete through normal labor")
		_expect(durations.has(building.get_instance_id()), building.building_name + " lacks natural progress evidence")
		_expect((building.get_node("BuildingSprite") as Sprite2D).texture.resource_path.ends_with(".svg"), building.building_name + " is not using original imported art")
	if not _failures.is_empty():
		return
	for resource: String in ["food", "wood", "gold"]:
		_expect(resource in buildings[0].drop_off_resources, "Resource Camp must still accept " + resource)
	var starting_counts: Dictionary = {}
	for entry: Array in [[buildings[1], UnitData.UnitType.ARCHER], [buildings[2], UnitData.UnitType.CAVALRY]]:
		var producer: BuildingBase = entry[0]
		var role: int = entry[1]
		starting_counts[role] = _role_count(role)
		bank = ResourceManager.get_all_resources(0).duplicate()
		_main.call("_on_train_unit_requested", producer, role)
		_check_spend(bank, UnitData.get_unit_cost(role), UnitData.get_unit_name(role))
		_expect(producer.get_production_queue().get_queue_size() == 1, "Paid " + UnitData.get_unit_name(role) + " queue missing")
	var deadline: float = GameManager.game_time + 60.0
	var wall_deadline: int = Time.get_ticks_msec() + 15000
	while GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		if _role_count(UnitData.UnitType.ARCHER) > int(starting_counts[UnitData.UnitType.ARCHER]) and _role_count(UnitData.UnitType.CAVALRY) > int(starting_counts[UnitData.UnitType.CAVALRY]):
			break
		await get_tree().process_frame
	for role: int in starting_counts:
		_expect(_role_count(role) == int(starting_counts[role]) + 1, "Normal production did not spawn exactly one " + UnitData.get_unit_name(role))
	for unit: Node in _main.get("_player_units")[0]:
		if unit.unit_type in starting_counts:
			_expect(map.pathfinding.is_walkable(map.world_to_tile(unit.global_position)), "Produced " + UnitData.get_unit_name(unit.unit_type) + " must emerge on walkable terrain")

	_paid_complete = true

func _role_count(role: int) -> int:
	var count := 0
	for unit: Node in _main.get("_player_units")[0]:
		count += int(unit.unit_type == role)
	return count

func _check_spend(before: Dictionary, cost: Dictionary, label: String) -> void:
	for resource: String in ["food", "wood", "gold"]:
		_expect(int(before[resource]) - ResourceManager.get_resource(0, resource) == int(cost.get(resource, 0)), label + " must pay exact " + resource)
