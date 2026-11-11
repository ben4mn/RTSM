extends "res://tools/garrison_fixture.gd"
## Round 2 E: the opponent uses the Round 2 mechanics. The strategic AI is
## frozen by the fixture; each policy is driven directly on the real match.

const AIScript := preload("res://scripts/ai/ai_controller.gd")

var ai: Node = null


func run_cases() -> void:
	case_name = "ai_uses_round2_mechanics"
	await step(1.0)
	ai = main.get_node("AIController")
	expect(ai != null and int(ai.player_id) == 1, "fixture: the opponent AI is player 1")
	_check_villager_targets()
	_check_town_center_plan()
	await _check_continuous_villagers()
	_check_reseed()
	await _check_boar()
	_check_mixed_army()
	await _check_healing()
	_check_wave_sizes()


func _with(level: int) -> void:
	ai.difficulty = level
	GameManager.players[1]["age"] = 1


func _check_villager_targets() -> void:
	var expected: Dictionary = {0: [12, 18], 1: [16, 32], 2: [18, 42]}
	for level: int in expected:
		_with(level)
		var dark: int = ai._get_target_villager_count()
		GameManager.players[1]["age"] = 2
		var mature: int = ai._get_target_villager_count()
		expect(dark == expected[level][0] and mature == expected[level][1], "difficulty %d aims for %d villagers in the Dark Age and %d after (got %d/%d)" % [level, expected[level][0], expected[level][1], dark, mature])
	_with(1)


func _check_town_center_plan() -> void:
	var tc_type: int = BuildingData.BuildingType.TOWN_CENTER
	ai._game_time = 300.0
	for level: int in [0, 1, 2]:
		_with(level)
		GameManager.players[1]["age"] = 2
		ai._feudal_reached_at = ai._game_time
		var at_feudal: int = int(ai._get_target_building_counts(2).get(tc_type, 0))
		ai._feudal_reached_at = ai._game_time - 61.0
		var later: int = int(ai._get_target_building_counts(2).get(tc_type, 0))
		var want: Array = [[1, 1], [1, 2], [2, 2]][level]
		expect(at_feudal == want[0] and later == want[1], "difficulty %d plans %d then %d Town Centers in Feudal (got %d/%d)" % [level, want[0], want[1], at_feudal, later])
	_with(1)
	ai._feudal_reached_at = -1.0


func _check_continuous_villagers() -> void:
	_with(1)
	var second: BuildingBase = main._spawn_building(BuildingData.BuildingType.TOWN_CENTER, 1, free_tile(map.world_to_tile(main._player_buildings[1][0].global_position) + Vector2i(9, 0)))
	second.complete_instantly()
	ResourceManager._player_resources[1] = {"food": 2000, "wood": 2000, "gold": 2000}
	GameManager.increase_population_cap(1, 40)
	ai._check_villager_production()
	var queued: int = 0
	var busy_centers: int = 0
	for entry: Variant in main._player_buildings[1]:
		if entry is BuildingBase and (entry as BuildingBase).building_type == BuildingData.BuildingType.TOWN_CENTER and (entry as BuildingBase).state == BuildingBase.State.ACTIVE:
			var size: int = int((entry as BuildingBase).get_production_queue().get_queue_size())
			queued += size
			if size > 0:
				busy_centers += 1
	expect(busy_centers >= 2 and queued <= 4, "every Town Center trains villagers at once, with short queues (%d centers, %d queued)" % [busy_centers, queued])
	await step(0.5)


func _check_reseed() -> void:
	var farm: BuildingBase = main._spawn_building(BuildingData.BuildingType.FARM, 1, free_tile(map.world_to_tile(main._player_buildings[1][0].global_position) + Vector2i(-5, 2)))
	farm.complete_instantly()
	FarmPlots.ensure_sown(farm)
	farm.farm_food_remaining = 0
	farm.farm_fallow = true
	ResourceManager._player_resources[1]["wood"] = ai.FARM_RESEED_WOOD - 1
	ai._check_farm_reseeds()
	expect(farm.farm_fallow, "the AI keeps a fallow Farm while wood is under %d" % ai.FARM_RESEED_WOOD)
	ResourceManager._player_resources[1]["wood"] = ai.FARM_RESEED_WOOD + 50
	ai._check_farm_reseeds()
	expect(not farm.farm_fallow and farm.farm_food_remaining == FarmPlots.capacity_for(1), "and reseeds it once it has the wood")


func _check_boar() -> void:
	var director: WildlifeDirector = WildlifeDirector.of(map)
	expect(director != null, "fixture: wildlife is placed")
	if director == null:
		return
	var boar: WildlifeNode = null
	var ai_base: Vector2 = main._player_buildings[1][0].global_position
	for node: WildlifeNode in director.get_nodes(WildlifeData.BOAR):
		if node.is_fighting() and (boar == null or node.global_position.distance_to(ai_base) < boar.global_position.distance_to(ai_base)):
			boar = node
	expect(boar != null, "fixture: a live boar near the AI")
	if boar == null:
		return
	# Make it visible and in reach: move it beside the AI's villagers.
	boar.global_position = ai_base + Vector2(260, 60)
	boar.home_position = boar.global_position
	ai._game_time = 200.0
	ai._is_under_pressure = false
	for owner_id: int in [1]:
		while ai._get_villagers().size() < 9:
			spawn_at(UnitData.UnitType.VILLAGER, owner_id, free_tile(map.world_to_tile(ai_base) + Vector2i(3, 3), ai._get_villagers().size()))
	await step(0.5)
	main.call("_update_fog_of_war")
	ai._cleanup_references()
	# Easy leaves boars alone.
	_with(0)
	ai._boar_target_ref = null
	ai._boars_handled = 0
	ai._check_boar_hunt()
	expect(ai._get_boar_target() == null, "Easy skips the boar")
	# Medium sends a party of four.
	_with(1)
	ai._check_boar_hunt()
	var hunters: int = 0
	for villager: Variant in ai._get_villagers():
		if (villager as Villager).gather_target == boar:
			hunters += 1
	expect(ai._get_boar_target() == boar and hunters == ai.BOAR_PARTY_SIZE and ai._boar_lure_id == 0, "Medium hunts the boar with %d villagers (got %d)" % [ai.BOAR_PARTY_SIZE, hunters])
	for villager: Variant in ai._get_villagers():
		(villager as Villager).command_stop()
	# Hard lures it with one villager.
	_with(2)
	ai._boar_target_ref = null
	ai._check_boar_hunt()
	var lurer: Villager = ai._boar_villager(ai._boar_lure_id)
	expect(ai._get_boar_target() == boar and lurer != null and lurer.gather_target == boar, "Hard sends one villager to lure the boar")
	var lured: bool = await step_until(func() -> bool:
		ai._check_boar_hunt()
		return ai._boar_lure_returning or not boar.is_fighting(), 30.0)
	expect(lured, "the lurer runs for the Town Center once the boar charges")
	var felled: bool = await step_until(func() -> bool:
		ai._check_boar_hunt()
		return not boar.is_fighting(), 45.0)
	expect(felled, "the boar falls by the Town Center")
	_with(1)


func _check_mixed_army() -> void:
	_with(1)
	GameManager.players[1]["age"] = 2
	for building_type: int in [BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE]:
		var building: BuildingBase = main._spawn_building(building_type, 1, free_tile(map.world_to_tile(main._player_buildings[1][0].global_position) + Vector2i(0, 8), building_type))
		building.complete_instantly()
	for index: int in 6:
		spawn_at(UnitData.UnitType.INFANTRY, 1, free_tile(map.world_to_tile(main._player_buildings[1][0].global_position) + Vector2i(4, -4), index))
	ai._cleanup_references()
	ai._update_building_counts()
	var plan: Array = ai._get_scale_training_plan([UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY])
	expect(not plan.is_empty() and UnitData.UnitType.INFANTRY not in plan, "with six Warriors the AI trains other lines first (plan %s)" % str(plan))


func _check_healing() -> void:
	var soldier: UnitBase = null
	for unit: Variant in ai._get_fighting_units():
		soldier = unit
		break
	expect(soldier != null, "fixture: an AI soldier")
	if soldier == null:
		return
	soldier.global_position = main._player_buildings[1][0].global_position + Vector2(600, 0)
	soldier.hp = soldier.max_hp * 0.3
	ai._micro_damaged_units()
	expect(ai._healing_ids.has(soldier.get_instance_id()) and soldier.current_state == UnitBase.State.MOVING, "a soldier under 35% HP walks home to heal")
	expect(soldier not in ai._get_field_military([]), "and is left out of the field army")
	soldier.hp = soldier.max_hp
	ai._micro_damaged_units()
	expect(not ai._healing_ids.has(soldier.get_instance_id()), "a healed soldier rejoins")
	await step(0.2)


func _check_wave_sizes() -> void:
	var first: Array = []
	var later: Array = []
	for level: int in [0, 1, 2]:
		_with(level)
		ai._has_launched_field_attack = false
		first.append(ai._get_attack_threshold())
		ai._has_launched_field_attack = true
		later.append(ai._get_attack_threshold())
	ai._has_launched_field_attack = false
	expect(first == [6, 12, 10] and int(later[1]) >= 20 and int(later[2]) >= 20, "first waves 6/12/10, later waves of 20+ (%s / %s)" % [str(first), str(later)])
	expect(is_equal_approx(float(ai.AGE_UP_TARGET_TIMES[1]), 180.0) and is_equal_approx(float(ai.CASTLE_TARGET_TIMES[1]), 470.0), "Medium clicks Feudal at 3:00 and Castle at 7:50")
