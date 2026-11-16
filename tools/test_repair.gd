extends "res://tools/garrison_fixture.gd"
## Repair through the build order: rate, wood cost, pausing when broke,
## returning to the previous job, and no automatic repair by idle villagers.


func run_cases() -> void:
	case_name = "repair"
	await step(1.0)
	var workers: Array[Villager] = own_villagers()
	var mason: Villager = workers[0]
	expect(mason.has_active_gather_order(), "fixture villager has a gather job to return to")
	# Only the mason moves wood in or out of the bank during the measurements.
	for index: int in range(1, workers.size()):
		workers[index].process_mode = Node.PROCESS_MODE_DISABLED
	var house: BuildingBase = main._spawn_building(BuildingData.BuildingType.HOUSE, 0, free_tile(tc_tile() + Vector2i(7, 1)))
	house.complete_instantly()
	var selection: Node = map.selection_mgr

	# --- Nothing to do on a healthy building.
	expect(not Garrison.needs_repair(house) and Garrison.order_repair([mason], house) == 0, "a healthy building takes no repair order")
	expect(not selection._is_under_construction(house), "tapping a healthy building is not a villager work order")

	# --- No automatic repair: wood in the bank, idle villager beside the wall.
	house.hp = house.max_hp - 300
	var idler: Villager = spawn_at(UnitData.UnitType.VILLAGER, 0, free_tile(map.world_to_tile(house.global_position) + Vector2i(2, 2))) as Villager
	idler.command_stop()
	await step(3.0)
	expect(house.hp == house.max_hp - 300, "idle villagers do not repair by themselves")
	expect(Garrison.needs_repair(house) and selection._is_under_construction(house), "a damaged own building takes the villager work order")
	kill(idler)

	# --- Rate and cost with one villager.
	ResourceManager._player_resources[0]["wood"] = 100
	expect(main.ext.run_command("repair", 1, {"target": 1, "ids": [1]}, [mason], house, Vector2.ZERO) == "Select your building", "the rival cannot order this repair")
	expect(main.ext.run_command("repair", 0, {"target": 1, "ids": [1]}, [mason], house, Vector2.ZERO) == "", "repair command accepted")
	expect(mason.current_state == UnitBase.State.BUILDING and mason.build_target == house and mason.has_active_build_order(), "repair uses the build order")
	var started: bool = await step_until(func() -> bool: return house.hp > house.max_hp - 300, 30.0)
	expect(started, "villager reaches the wall and starts repairing")
	expect(Garrison.is_being_repaired(house) and mason.get_work_status() == "Repairing", "repair is visible as work in progress")
	var hp_start: int = house.hp
	await step(4.0)
	var rate: float = float(house.hp - hp_start) / 4.0
	expect(rate > Garrison.REPAIR_HP_PER_SECOND * 0.85 and rate < Garrison.REPAIR_HP_PER_SECOND * 1.15, "one villager repairs about %d HP/s (measured %.1f)" % [int(Garrison.REPAIR_HP_PER_SECOND), rate])
	var done: bool = await step_until(func() -> bool: return house.hp >= house.max_hp, 20.0)
	expect(done and house.hp == house.max_hp, "repair finishes at full health, never above")
	var wood_spent: int = 100 - int(ResourceManager.get_resource(0, "wood"))
	expect(wood_spent == 15, "300 HP costs 15 wood at 1 wood per 20 HP (spent %d)" % wood_spent)
	await step(1.0)
	expect(mason.build_target == null and (mason.has_active_gather_order() or mason.current_state == UnitBase.State.GATHERING), "villager returns to its previous gather job")

	# --- Out of wood: the villager waits; wood arriving resumes the work.
	house.hp = house.max_hp - 200
	house.repair_credit = 0.0
	ResourceManager._player_resources[0]["wood"] = 0
	expect(Garrison.order_repair([mason], house) == 1, "repair order accepted with an empty bank")
	await step_until(func() -> bool: return mason._building_work_distance(house) <= Villager.BUILD_APPROACH_DISTANCE, 30.0)
	await step(3.0)
	expect(house.hp == house.max_hp - 200, "no wood, no repair")
	expect(mason.current_state == UnitBase.State.BUILDING and mason.build_target == house, "villager keeps the order and waits")
	expect(int(ResourceManager.get_resource(0, "wood")) == 0, "nothing was charged")
	ResourceManager.add_resource(0, "wood", 4)
	await step(80.0 / Garrison.REPAIR_HP_PER_SECOND + 1.5)
	var bought: int = house.hp - (house.max_hp - 200)
	expect(bought == 79 or bought == 80, "4 wood buys 80 HP and not a point more (got %d)" % bought)
	expect(int(ResourceManager.get_resource(0, "wood")) == 0, "the 4 wood were spent")

	# --- Two villagers repair twice as fast.
	ResourceManager._player_resources[0]["wood"] = 500
	house.hp = 100
	var helper: Villager = workers[1]
	helper.process_mode = Node.PROCESS_MODE_INHERIT
	expect(Garrison.order_repair([helper], house) == 1, "second villager joins")
	await step_until(func() -> bool: return helper._building_work_distance(house) <= Villager.BUILD_APPROACH_DISTANCE and helper._presentation_working, 30.0)
	house.hp = 100
	await step(3.0)
	rate = float(house.hp - 100) / 3.0
	expect(rate > Garrison.REPAIR_HP_PER_SECOND * 1.7 and rate < Garrison.REPAIR_HP_PER_SECOND * 2.3, "two villagers repair about twice as fast (measured %.1f HP/s)" % rate)

	# --- Farms are not repair targets; a foundation is still built, not repaired.
	var farm: BuildingBase = main._spawn_building(BuildingData.BuildingType.FARM, 0, free_tile(tc_tile() + Vector2i(-6, 6)))
	farm.complete_instantly()
	farm.hp = farm.max_hp - 10
	expect(not Garrison.needs_repair(farm), "a damaged Farm is worked, not repaired")
	var site: BuildingBase = main._spawn_building(BuildingData.BuildingType.HOUSE, 0, free_tile(tc_tile() + Vector2i(10, 4)))
	site.start_construction()
	expect(not Garrison.needs_repair(site) and selection._is_under_construction(site), "a foundation is construction, not repair")
