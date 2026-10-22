extends "res://tools/test_company_specialist_buildings.gd"
## Explicit funded transaction fixture. Ages, foundations, research and a Siege
## Engine are all purchased through Main; workers/queues complete naturally.

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.guided_opening_enabled = false
	if await _start_match():
		await _paid_industry()
		_expect(_paid_complete, "Industry fixture did not reach final production assertions")
	await _close_match()
	Engine.time_scale = 1.0
	for failure: String in _failures:
		push_error("[FAIL] company_industry: " + failure)
	if _failures.is_empty():
		print("[PASS] company_industry: funded paid age progression, Blacksmith/Workshop placement, natural construction, exact Forge Weapons research, paid Siege Engine queue and walkable egress")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _paid_industry() -> void:
	for resource: String in ["food", "wood", "gold"]:
		ResourceManager.add_resource(0, resource, maxi(0, 5000 - ResourceManager.get_resource(0, resource)))
	while GameManager.get_player_age(0) < 3:
		var age: int = GameManager.get_player_age(0)
		var cost: Dictionary = GameManager.get_age_up_cost(0, age + 1)
		var before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
		_main.call("_on_age_up_requested")
		_expect(GameManager.get_player_age(0) == age + 1, "Paid age progression failed")
		_check_spend(before, cost, "Age %d" % (age + 1))
		if GameManager.get_player_age(0) == age:
			return
	var map: Node2D = _main.get("game_map")
	var home: Vector2i = map.map_generator.spawn_positions[0]
	var buildings: Array[BuildingBase] = []
	for kind: int in [BuildingData.BuildingType.BLACKSMITH, BuildingData.BuildingType.SIEGE_WORKSHOP]:
		var before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
		var building: BuildingBase = _place(kind, home)
		if building == null:
			return
		buildings.append(building)
		_check_spend(before, BuildingData.get_building_cost(kind), building.building_name)
		_expect(building.state == BuildingBase.State.CONSTRUCTING and building.build_progress == 0.0, building.building_name + " starts as a real foundation")
		_expect(_builder_count(building) == 1, building.building_name + " receives one real worker")
	var durations: Dictionary = await _wait_for_natural_construction(buildings, 120.0)
	for building: BuildingBase in buildings:
		_expect(building.state == BuildingBase.State.ACTIVE and durations.has(building.get_instance_id()), building.building_name + " completes with normal labor")
		_expect((building.get_node("BuildingSprite") as Sprite2D).texture.resource_path == BuildingBase.get_sprite_texture_path(building.building_type, 0), building.building_name + " uses its original art after construction")
	if not _failures.is_empty():
		return
	var smith: BuildingBase = buildings[0]
	var workshop: BuildingBase = buildings[1]
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	_main.call("_on_research_requested", smith, "forging")
	_check_spend(bank, TechData.get_research_definition("forging").cost, "Forge Weapons")
	_expect(GameManager.has_research(0, "forging"), "Blacksmith research did not complete")
	bank = ResourceManager.get_all_resources(0).duplicate()
	_main.call("_on_research_requested", smith, "forging")
	_check_spend(bank, {}, "Duplicate research")
	var starting_count: int = _role_count(UnitData.UnitType.SIEGE)
	bank = ResourceManager.get_all_resources(0).duplicate()
	_main.call("_on_train_unit_requested", workshop, UnitData.UnitType.SIEGE)
	_check_spend(bank, UnitData.get_unit_cost(UnitData.UnitType.SIEGE), "Siege Engine")
	_expect(workshop.get_production_queue().get_queue_size() == 1, "Paid Siege Engine queue missing")
	var deadline: float = GameManager.game_time + 60.0
	var wall_deadline: int = Time.get_ticks_msec() + 20000
	while _role_count(UnitData.UnitType.SIEGE) == starting_count and GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		await get_tree().process_frame
	_expect(_role_count(UnitData.UnitType.SIEGE) == starting_count + 1, "Normal queue must produce exactly one Siege Engine")
	for unit: Node in _main.get("_player_units")[0]:
		if unit.unit_type == UnitData.UnitType.SIEGE:
			_expect(map.pathfinding.is_walkable(map.world_to_tile(unit.global_position)), "Produced Siege Engine emerges on walkable terrain")
	_paid_complete = true
