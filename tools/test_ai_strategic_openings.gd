extends "res://tools/test_ai_trade_demand.gd"
## Bounded policy/paid transaction checks; full-match results are separate.

func _profile(name: String) -> void:
	for seed_value: int in range(1, 10):
		GameManager.selected_map_seed = seed_value
		if ai.get_opening_strategy() == name: return
	_expect(false, "requested deterministic profile exists: " + name)

func _run() -> void:
	AudioManager.set_all_enabled(false)
	_reset()
	GameManager.players[1].age = 2
	var seen: Dictionary = {}
	for civ: int in [0, 1, 2]:
		GameManager.players[1].civilization = civ
		for seed_value: int in range(1, 7):
			GameManager.selected_map_seed = seed_value
			var chosen: String = ai.get_opening_strategy()
			seen[chosen] = true
			_expect(chosen == ai.get_opening_strategy(), "opening is stable for seed/player/civilization")
	_expect(seen.size() == 3, "seeds expose three bounded strategies")
	GameManager.players[1].civilization = 0
	_profile("two_tc_boom")
	ai._update_building_counts()
	var base_workers: int = ai._get_target_villager_count()
	_expect(not ai._get_boom_reserve_cost().is_empty(), "safe established boom banks a real second TC")
	_expect(ai._get_target_building_counts(2)[BuildingData.BuildingType.TOWN_CENTER] == 2, "boom can request its second TC in Feudal")
	var cost: Dictionary = BuildingData.get_building_cost(BuildingData.BuildingType.TOWN_CENTER)
	ResourceManager.initialize_player(1, {"food": 1000, "wood": int(cost.wood), "gold": int(cost.gold)})
	_expect(not ai._allows_boom_spend({"wood": 40}), "optional troops preserve the actual TC investment")
	ai._is_under_pressure = true
	_expect(ai._get_boom_reserve_cost().is_empty() and ai._allows_boom_spend({"wood": 40}), "home pressure releases boom capital immediately")
	ai._is_under_pressure = false
	var second: BuildingBase = _building("town_center", Vector2i(22, 8))
	second.state = BuildingBase.State.CONSTRUCTING
	ai._update_building_counts()
	_expect(ai._get_target_villager_count() == base_workers, "foundation grants no extra economy target")
	second.state = BuildingBase.State.ACTIVE
	_expect(ai._get_target_villager_count() == mini(18, base_workers + 6), "completed second TC supports six additional workers within18 cap")
	second.player_owner = 0
	_expect(ai._get_target_villager_count() == base_workers, "foreign TC never grants an economy target")
	second.free()
	ai._update_building_counts()
	ResourceManager.initialize_player(1, {"food": 400, "wood": 500, "gold": 300})
	_profile("castle_priority")
	ai._update_age_up_reserve()
	_expect(ai._saving_for_age_up, "Castle profile protects a nearly funded advance with a real escort")
	var target: Dictionary = ai._get_economy_worker_targets(10, ResourceManager.get_all_resources(1))
	_expect(int(target.gold) > 0 and int(target.food) > 0, "Castle saving allocates actual remaining food/gold demand")
	_profile("feudal_pressure")
	ai._update_age_up_reserve()
	_expect(not ai._saving_for_age_up, "Feudal profile keeps producing at the same intermediate bank")
	ai._ai_state = AIController.AIState.MID_GAME
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 1000, "gold": 1000})
	GameManager.players[1].civilization = 1
	var plan: Array = ai._get_military_training_plan(ResourceManager.get_all_resources(1))
	_expect(plan[0] == UnitData.UnitType.ARCHER, "100-pop English plan favors its actual Longbow identity")
	GameManager.players[1].civilization = 2
	plan = ai._get_military_training_plan(ResourceManager.get_all_resources(1))
	_expect(plan[0] == UnitData.UnitType.CAVALRY, "100-pop Mongol plan favors its actual Outrider identity")
	GameManager.players[1].civilization = 1
	var enemy: UnitBase = _unit("archer", 0)
	plan = ai._get_military_training_plan(ResourceManager.get_all_resources(1))
	_expect(plan[0] == UnitData.UnitType.CAVALRY, "visible counter overrides civilization preference at100pop")
	trade_map.enemy_visible = false
	plan = ai._get_military_training_plan(ResourceManager.get_all_resources(1))
	_expect(plan[0] == UnitData.UnitType.ARCHER, "hidden enemy cannot alter composition")
	enemy.free()
	_reset()
	GameManager.players[1].age = 2
	ai._game_time = 350.0
	_profile("feudal_pressure")
	var mine := ResourceNode.new()
	mine.resource_type = "gold"
	mine.total_amount = 200
	mine.tile_position = Vector2i(10, 8)
	mine.position = map.tile_to_world(mine.tile_position)
	fixture.add_child(mine)
	trade_map.mine = mine
	ai._check_trade_economy()
	_expect(builds.size() == 1 and builds[0].kind == BuildingData.BuildingType.TRADE_POST, "visible200-gold runway starts paid trade before mine exhaustion and ten minutes")
	_expect(mine.remaining == 200 and ResourceManager.get_resource(1, "gold") == 120, "planning reads visible stock without harvesting or granting income")
	var target_gold: int = ai._get_gold_bank_target()
	var recurring: int = 2 * int(UnitData.get_unit_cost(UnitData.UnitType.ARCHER).gold) + int(UnitData.get_unit_cost(UnitData.UnitType.CAVALRY).gold)
	_expect(target_gold >= int(GameManager.get_age_up_cost(1, 3).gold) + recurring, "gold labor budget includes recurring mixed-army costs")
	fixture.free()
	print(JSON.stringify({"test": "ai_strategic_openings", "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
