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
	_check_easy_pacing()


func _with(level: int) -> void:
	ai.difficulty = level
	GameManager.players[1]["age"] = 1


func _check_villager_targets() -> void:
	# Round 2 E2: read the tables (Easy 10/14, Medium 16/30, Hard 18/34 at the 80-body default).
	var expected: Dictionary = {}
	for level: int in [0, 1, 2]:
		expected[level] = [maxi(int(ai.VILLAGER_TARGETS[level]), int(ai.AGE_UP_MIN_VILLAGERS[level][2])), maxi(int(ai.MATURE_VILLAGER_TARGETS[level]), int(ai.AGE_UP_MIN_VILLAGERS[level][3]))]  # never below the next age's villager gate
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
	# H: Medium lures too. With live wildlife a party fighting a boar in the
	# open lost about two villagers a match; under the Town Center none died.
	_with(1)
	ai._check_boar_hunt()
	expect(ai._get_boar_target() == boar and ai._boar_lure_id != 0 and ai._boar_hunter_ids.size() == 1, "Medium sends one villager to lure the boar")
	for villager: Variant in ai._get_villagers():
		(villager as Villager).command_stop()
	ai._boar_target_ref = null
	ai._boar_hunter_ids.clear()
	ai._boar_lure_id = 0
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
	var first_expected: Array = [int(ai.ARMY_ATTACK_THRESHOLDS[0]), int(ai.ARMY_ATTACK_THRESHOLDS[1]), int(ai.ARMY_ATTACK_THRESHOLDS[2])]
	expect(first == first_expected and int(later[1]) > int(first[1]) and int(later[2]) > int(first[2]) and int(later[0]) <= int(later[1]), "first waves from ARMY_ATTACK_THRESHOLDS, later waves larger, Easy smallest (%s / %s)" % [str(first), str(later)])
	expect(is_equal_approx(float(ai.AGE_UP_TARGET_TIMES[1]), 180.0) and is_equal_approx(float(ai.CASTLE_TARGET_TIMES[1]), 470.0), "Medium clicks Feudal at 3:00 and Castle at 7:50")


## K: Easy waits until 14:00 for any wave, sends small growing waves, keeps a
## smaller army, rests 5:00 between waves and ages up later than Medium.
func _check_easy_pacing() -> void:
	expect(float(ai.EASY_FIRST_ATTACK_SECONDS) >= 840.0 and float(SkirmishData.AI_RAID_START_SECONDS[0]) >= 840.0, "Easy's first wave and compact raid wait for 14:00")
	expect(float(ai.SHRINE_START_SECONDS[0]) >= 840.0, "Easy sends no shrine squad before 14:00")
	expect(int(ai.EASY_ARMY_CAP) <= 10 and float(ai.EASY_WAVE_REST_SECONDS) + 60.0 >= 300.0, "Easy caps its army at 10 and waits 5:00 between waves")
	expect(float(ai.TC_ASSAULT_START_SECONDS[0]) >= 1500.0, "Easy assaults no Town Center before 25:00")
	expect(float(ai.AGE_UP_TARGET_TIMES[0]) > float(ai.AGE_UP_TARGET_TIMES[1]) and float(ai.CASTLE_TARGET_TIMES[0]) > float(ai.CASTLE_TARGET_TIMES[1]), "Easy ages up later than Medium")
	expect(int(ai.TC_ASSAULT_START_SECONDS[1]) == 630 and is_equal_approx(float(SkirmishData.AI_RAID_START_SECONDS[1]), 120.0), "Medium keeps its pacing")
	_with(0)
	var saved_time: float = ai._game_time
	ai._game_time = 840.0
	var first_wave: int = ai._get_easy_wave_size()
	ai._game_time = 840.0 + 600.0
	var later_wave: int = ai._get_easy_wave_size()
	ai._game_time = 5000.0
	var late_wave: int = ai._get_easy_wave_size()
	expect(first_wave >= 4 and first_wave <= 6 and later_wave > first_wave and late_wave == int(ai.EASY_ARMY_CAP), "Easy waves start at 4-6 and grow slowly to the cap (%d, %d, %d)" % [first_wave, later_wave, late_wave])
	if not ai._uses_compact_population_policy():
		ai._has_launched_field_attack = false
		ai._attack_in_progress = false
		ai._last_field_attack_time = -INF
		ai._game_time = 839.0
		ai._check_attack_or_defend()
		expect(not ai._attack_in_progress and not ai._has_launched_field_attack, "Easy launches no field wave at 13:59 (decision %s)" % str(ai._last_strategy_decision))
	ai._game_time = saved_time
	_with(1)
