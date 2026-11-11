extends "res://tools/garrison_fixture.gd"
## Round 2 E finite Farms: a sown Farm holds BuildingData "farm_food", then lies
## fallow (no work, its farmer idles), is reseeded by the context action or a
## gather order, and the optional Auto-reseed assist replants from the bank.

const SOLO_STATE := preload("res://scripts/main/solo_match_state.gd")


func run_cases() -> void:
	case_name = "farm_reseed"
	await step(1.0)
	var farm_type: int = BuildingData.BuildingType.FARM
	var base_food: int = int(BuildingData.BUILDINGS[farm_type].farm_food)
	var reseed_wood: int = int(BuildingData.get_reseed_cost(farm_type, 0).get("wood", 0))
	expect(base_food == 250 and int(BuildingData.BUILDINGS[farm_type].cost.wood) == 60, "a Farm costs 60 wood and holds 250 food")
	expect(reseed_wood > 0 and reseed_wood <= 40, "reseeding costs at most 40 wood (%d for this kingdom)" % reseed_wood)
	expect("farm_fallow" in SOLO_STATE.BUILDING_FIELDS and "farm_food_remaining" in SOLO_STATE.BUILDING_FIELDS, "Farm stock is saved with the building")

	var farm: BuildingBase = main._spawn_building(farm_type, 0, free_tile(tc_tile() + Vector2i(5, 1)))
	farm.complete_instantly()
	var workers: Array[Villager] = own_villagers()
	var farmer: Villager = workers[0]
	for index: int in range(1, workers.size()):
		workers[index].process_mode = Node.PROCESS_MODE_DISABLED
	expect(farmer.command_gather(farm), "a villager takes the Farm")
	FarmPlots.ensure_sown(farm)
	expect(farm.farm_food_total == base_food and farm.farm_food_remaining == base_food and not farm.farm_fallow, "the first use sows %d food" % base_food)
	expect(FarmPlots.summary(farm, true) == "%d / %d food" % [base_food, base_food], "the card shows the stock")

	# --- Run it dry.
	farm.farm_food_remaining = 6
	var dry: bool = await step_until(func() -> bool: return farm.farm_fallow, 40.0)
	expect(dry and farm.farm_food_remaining == 0, "the Farm lies fallow when its food is gone")
	expect(farm.harvest(5, farmer) == 0 and not farm.is_available_to_worker(farmer), "a fallow Farm yields nothing and offers no work")
	var idled: bool = await step_until(func() -> bool: return farmer.current_state == UnitBase.State.IDLE and farmer.carried_amount == 0, 40.0)
	expect(idled, "its farmer delivers what he carries and stands idle (counts as an idle villager)")
	var actions: Array = farm.get_context_actions(0).map(func(action: Dictionary) -> String: return action.id)
	expect(FarmPlots.ACTION_RESEED in actions and FarmPlots.ACTION_AUTO in actions, "a fallow Farm offers Reseed and Auto-reseed")
	expect(FarmPlots.summary(farm, true) == "Fallow", "the card says Fallow")

	# --- No wood, no reseed.
	ResourceManager._player_resources[0]["wood"] = 0
	expect(farm.perform_context_action(0, FarmPlots.ACTION_RESEED) != "" and farm.farm_fallow, "reseeding needs the wood")

	# --- Reseed by the context action: paid, sown again, farmer recalled.
	ResourceManager._player_resources[0]["wood"] = 500
	expect(farm.perform_context_action(0, FarmPlots.ACTION_RESEED) == "", "Reseed is accepted")
	expect(not farm.farm_fallow and farm.farm_food_remaining == base_food, "the Farm is sown again")
	expect(int(ResourceManager.get_resource(0, "wood")) == 500 - reseed_wood, "and %d wood was paid" % reseed_wood)
	expect(farmer.gather_target == farm and farmer.current_state != UnitBase.State.IDLE, "its idle farmer goes back to work")
	expect(farm.perform_context_action(0, FarmPlots.ACTION_RESEED) != "", "a growing Farm cannot be reseeded")

	# --- Auto-reseed: off by default, prepaid when the Farm runs out.
	expect(not FarmPlots.is_auto_reseed(0), "Auto-reseed is off by default")
	expect(farm.perform_context_action(0, FarmPlots.ACTION_AUTO) == "" and FarmPlots.is_auto_reseed(0), "Auto-reseed can be switched on")
	var wood_before: int = int(ResourceManager.get_resource(0, "wood"))
	farm.farm_food_remaining = 3
	var replanted: bool = await step_until(func() -> bool: return farm.farm_food_remaining > 100, 40.0)
	expect(replanted and not farm.farm_fallow, "an Auto-reseed Farm is replanted as it runs out")
	expect(int(ResourceManager.get_resource(0, "wood")) == wood_before - reseed_wood, "from the bank")
	expect(farmer.gather_target == farm, "and the farmer never stops")

	# --- Auto-reseed with an empty bank waits fallow, then replants on income.
	ResourceManager._player_resources[0]["wood"] = 0
	farm.farm_food_remaining = 3
	var waited: bool = await step_until(func() -> bool: return farm.farm_fallow, 40.0)
	expect(waited, "with no wood it waits fallow")
	ResourceManager._player_resources[0]["wood"] = 100
	var resumed: bool = await step_until(func() -> bool: return not farm.farm_fallow, 10.0)
	expect(resumed and int(ResourceManager.get_resource(0, "wood")) == 100 - reseed_wood, "and replants once the wood arrives")
	farm.perform_context_action(0, FarmPlots.ACTION_AUTO)
	expect(not FarmPlots.is_auto_reseed(0), "Auto-reseed can be switched off")

	# --- Horse Collar: +75 food in every later sowing.
	GameManager.set_modifier(0, FarmPlots.BONUS_KEY, 75.0)
	expect(FarmPlots.capacity_for(0) == base_food + 75 and FarmPlots.capacity_for(1) == base_food, "Horse Collar adds 75 food per Farm for its owner")

	# --- A gather order on a fallow Farm reseeds it.
	farm.farm_food_remaining = 0
	farm.farm_fallow = true
	ResourceManager._player_resources[0]["wood"] = 200
	map.selection_mgr.selected.assign([farmer])
	main._on_gather_command(farm)
	expect(not farm.farm_fallow and farm.farm_food_remaining == base_food + 75 and int(ResourceManager.get_resource(0, "wood")) == 200 - reseed_wood, "ordering a villager onto a fallow Farm reseeds it")
