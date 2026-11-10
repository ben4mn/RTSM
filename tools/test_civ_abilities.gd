extends Node
## Round 2 workstream C on the real Main scene: kingdom economy bonuses, civ
## prices and train times for the human and the AI, the three passive unit
## abilities (Charge, Emplace, Pillage) with their unique technologies, the
## wildlife gathering hook, the client flag and the saved ability state.

const SOLO_STATE := preload("res://scripts/main/solo_match_state.gd")
const FRENCH: int = CivilizationData.Civilization.CROWNLANDS
const ENGLISH: int = CivilizationData.Civilization.VERDANT_LEAGUE
const MONGOLS: int = CivilizationData.Civilization.SUNSTRIDE_CLANS
const CAVALRY: int = UnitData.UnitType.CAVALRY
const ARCHER: int = UnitData.UnitType.ARCHER

var checks: int = 0
var failures: Array[String] = []
var main: Node
var _slot: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _wait_main() -> bool:
	for frame: int in 900:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and scene.get("_building_placement") != null:
			main = scene
			main.process_mode = Node.PROCESS_MODE_DISABLED
			return true
	check(false, "Main initialized within bounded frames")
	return false


func _become(player_id: int, civilization: int) -> void:
	## A fresh match identity for one player: kingdom, starting registry, age.
	GameManager.players[player_id]["civilization"] = civilization
	GameManager.player_modifiers[player_id] = CivilizationData.get_starting_modifiers(civilization)
	GameManager.researched_upgrades[player_id] = []
	GameManager.players[player_id]["age"] = 3
	ResourceManager.initialize_player(player_id, {"food": 5000, "wood": 5000, "gold": 5000})


func _building(building_type: int, owner: int) -> BuildingBase:
	_slot += 1
	var pocket: Vector2i = main.game_map.map_generator.get_expansion_pocket_centers()[0]
	var building: BuildingBase = main._spawn_building(building_type, owner, pocket + Vector2i((_slot % 4) * 5 - 8, int(_slot / 4.0) * 5 - 6))
	building.complete_instantly()
	return building


func _unit(unit_type: int, owner: int, offset: Vector2) -> UnitBase:
	return main._spawn_unit(unit_type, owner, main._player_units[0][0].global_position + offset)


func _tick(unit: UnitBase, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0001:
		var step: float = minf(0.1, left)
		UnitAbilities.tick(unit, step)
		left -= step


func _overlay_visible(unit: UnitBase) -> bool:
	var overlay: Variant = unit.get_meta(UnitAbilities.OVERLAY_NAME) if unit.has_meta(UnitAbilities.OVERLAY_NAME) else null
	return is_instance_valid(overlay) and (overlay as CanvasItem).visible


func _gold(player_id: int) -> int:
	return int(ResourceManager.get_resource(player_id, "gold"))


func _action_ids(building: BuildingBase, player_id: int) -> Array:
	return building.get_context_actions(player_id).map(func(action: Dictionary) -> String: return action.id)


func _run() -> void:
	get_tree().current_scene = null
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.guided_opening_enabled = false
	GameManager.selected_civilization = ENGLISH
	GameManager.selected_opponent_civilization = MONGOLS
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	if not await _wait_main():
		await _finish()
		return
	GameManager.increase_population_cap(0, 60)
	GameManager.increase_population_cap(1, 60)
	_check_match_start()
	_check_data_and_copy()
	await _check_prices_and_train_times()
	await _check_charge()
	_check_emplace()
	await _check_pillage()
	_check_gathering_hook()
	_check_save_and_client()
	_check_ai()
	await _finish()


func _check_match_start() -> void:
	check(GameManager.get_modifier(0, "gather_wood") == 0.2 and GameManager.get_modifier(1, "gather_wood") == 0.0, "an English player starts with +20% wood in the modifier registry")
	check(GameManager.get_modifier(1, UnitAbilities.WILDLIFE_KEY) == 0.3 and GameManager.get_modifier(0, UnitAbilities.WILDLIFE_KEY) == 0.0, "a Mongol player starts with the +30% wildlife key")
	check(CivilizationData.CATALOG_VERSION == 2, "the civilization catalog version is bumped")
	check(CivilizationData.get_gather_multiplier(MONGOLS, "food") == 1.0 and CivilizationData.get_gather_multiplier(ENGLISH, "wood") == 1.0, "the flat multipliers are gone (English wood lives in the registry, Mongol flat food is replaced)")
	check(CivilizationData.get_extra_home_sheep(MONGOLS) == 2 and CivilizationData.get_extra_home_sheep(FRENCH) == 0, "the home-sheep field is data for the wildlife stream")


func _check_data_and_copy() -> void:
	for civilization: int in CivilizationData.ORDERED_IDS:
		var definition: Dictionary = CivilizationData.get_definition(civilization)
		var tech: Dictionary = TechData.get_research_definition(str(definition.unique_tech))
		check(not tech.is_empty() and int(tech.civilization) == civilization and ResourceLoader.exists(str(tech.icon)) and TechData.AI_PRIORITY.has(str(tech.id)), "%s has a unique technology with a glyph, in the AI list" % definition.name)
		check(not str(definition.strengths).is_empty() and not str(definition.signature).is_empty() and not UnitAbilities.describe_for_civilization(civilization).is_empty(), "%s discloses economy, unique unit and ability" % definition.name)
		for other: int in CivilizationData.ORDERED_IDS:
			check(TechData.is_available_to(tech, other) == (other == civilization), "%s belongs to %s only (asked as %d)" % [tech.id, definition.name, other])
	for kind: int in UnitAbilities.OVERLAY_TEXTURES:
		check(ResourceLoader.exists(str(UnitAbilities.OVERLAY_TEXTURES[kind])), "overlay art %d is authored" % kind)
	check(TechData.is_available_to(TechData.get_research_definition("loom"), MONGOLS), "generic research stays open to everyone")
	# Names and ability kinds through the live player ids.
	_become(0, FRENCH)
	_become(1, MONGOLS)
	check(UnitData.get_unit_name(CAVALRY, 0) == "Chevalier" and UnitAbilities.kind_of(CAVALRY, 0) == UnitAbilities.Kind.CHARGE, "French cavalry is the Chevalier with Charge")
	check(UnitData.get_unit_name(CAVALRY, 1) == "Outrider" and UnitAbilities.kind_of(CAVALRY, 1) == UnitAbilities.Kind.PILLAGE, "Mongol cavalry is the Outrider with Pillage")
	_become(1, ENGLISH)
	check(UnitData.get_unit_name(ARCHER, 1) == "Longbow" and UnitAbilities.kind_of(ARCHER, 1) == UnitAbilities.Kind.EMPLACE and UnitAbilities.kind_of(CAVALRY, 1) == UnitAbilities.Kind.NONE, "English archers are Longbows with Emplace; their Horsemen have no ability")
	check(UnitAbilities.card_line(CAVALRY, 0).begins_with("Charge:") and UnitAbilities.card_line(ARCHER, 1).begins_with("Emplace:") and UnitAbilities.card_line(UnitData.UnitType.INFANTRY, 0).is_empty(), "unit cards explain the ability in one line: " + UnitAbilities.card_line(CAVALRY, 0))
	check(CivilizationData.get_ai_unit_weight(FRENCH, CAVALRY) == 1.3 and CivilizationData.get_ai_unit_weight(ENGLISH, ARCHER) > 1.0 and CivilizationData.get_ai_unit_weight(MONGOLS, CAVALRY) > 1.0, "each AI leans toward its signature line")
	# Ratios hold at the planned halved scale (Horseman 10 damage, Archer 35 HP).
	check(int(round(20.0 * UnitAbilities.CHARGE_DAMAGE_RATIO)) == 25 and int(round(10.0 * UnitAbilities.CHARGE_DAMAGE_RATIO)) == 13, "Charge is +25 today and +13 after the rescale")
	check(int(round(160.0 * 1.12)) == 179 and int(round(80.0 * 1.12)) == 90, "Chivalry HP is a ratio of the Chevalier's own HP")


func _check_prices_and_train_times() -> void:
	var farm: int = BuildingData.BuildingType.FARM
	var camp: int = BuildingData.BuildingType.RESOURCE_CAMP
	var villager: int = UnitData.UnitType.VILLAGER
	_become(0, ENGLISH)
	_become(1, FRENCH)
	var base_farm: int = int(BuildingData.BUILDINGS[farm].cost.wood)
	var base_camp: int = int(BuildingData.BUILDINGS[camp].cost.wood)
	check(int(BuildingData.get_building_cost(farm, 1).wood) == 60 and int(BuildingData.get_building_cost(farm, 0).wood) == base_farm and int(BuildingData.get_building_cost(farm).wood) == base_farm, "French Farms cost 60 wood; everyone else pays %d" % base_farm)
	check(int(BuildingData.get_building_cost(camp, 0).wood) == 40 and int(BuildingData.get_building_cost(camp, 1).wood) == base_camp, "English Resource Camps cost 40 wood; everyone else pays %d" % base_camp)
	check(int(BuildingData.get_building_stats(farm, 1).cost.wood) == 60 and int(BuildingData.get_building_stats(camp, 0).cost.wood) == 40, "build cards read the same kingdom price")
	check(float(UnitData.get_unit_stats(villager, 1).build_time) == float(UnitData.UNITS[villager].build_time) * 0.8 and float(UnitData.get_unit_stats(villager, 0).build_time) == float(UnitData.UNITS[villager].build_time), "French Villagers train 20% faster")
	check(UnitData.get_unit_cost(villager, 1) == UnitData.get_unit_cost(villager) and UnitData.get_unit_cost(CAVALRY, 1) == UnitData.UNITS[CAVALRY].cost, "no kingdom changes a unit price today")
	# The AI (player 1, French) pays the French prices through its own transaction.
	var ai_town: BuildingBase = main._player_buildings[1][0]
	var ai_queue: ProductionQueue = ai_town.get_production_queue()
	var food_before: int = int(ResourceManager.get_resource(1, "food"))
	check(ai_queue.enqueue_unit(villager) and ai_queue.current_train_time == float(UnitData.UNITS[villager].build_time) * 0.8, "the French AI's Villager trains in %.1f s" % ai_queue.current_train_time)
	check(food_before - int(ResourceManager.get_resource(1, "food")) == int(UnitData.UNITS[villager].cost.food), "and costs the published food")
	ai_queue.cancel_unit(0)
	var ai: Node = main.ai_controller
	check(ai != null and int(ai.player_id) == 1, "fixture: the opponent AI is player 1")
	var site: Vector2i = ai._find_build_location(farm)
	var wood_before: int = int(ResourceManager.get_resource(1, "wood"))
	var buildings_before: int = main._player_buildings[1].size()
	main._on_ai_wants_to_build(farm, site, false)
	check(main._player_buildings[1].size() == buildings_before + 1 and wood_before - int(ResourceManager.get_resource(1, "wood")) == 60, "the French AI is charged 60 wood for a Farm (paid %d)" % (wood_before - int(ResourceManager.get_resource(1, "wood"))))
	# The human (player 0, English) pays through the placement transaction.
	var home: Vector2i = main.game_map.world_to_tile(main._player_buildings[0][0].global_position)
	var spot: Vector2 = Vector2.INF
	for radius: int in range(5, 14):
		for dx: int in range(-radius, radius + 1):
			for dy: int in [-radius, radius]:
				var world: Vector2 = main.game_map.tile_to_world(home + Vector2i(dx, dy))
				if not spot.is_finite() and main._building_placement.revalidate_confirmation(camp, world, 0):
					spot = world
	check(spot.is_finite(), "fixture: a legal Resource Camp site exists near home")
	if spot.is_finite():
		wood_before = int(ResourceManager.get_resource(0, "wood"))
		buildings_before = main._player_buildings[0].size()
		main._on_placement_confirmed(camp, spot)
		check(main._player_buildings[0].size() == buildings_before + 1 and wood_before - int(ResourceManager.get_resource(0, "wood")) == 40, "the English player is charged 40 wood for a Resource Camp (paid %d)" % (wood_before - int(ResourceManager.get_resource(0, "wood"))))
	var town_queue: ProductionQueue = main._player_buildings[0][0].get_production_queue()
	check(town_queue.enqueue_unit(villager) and town_queue.current_train_time == float(UnitData.UNITS[villager].build_time), "the English player's Villager keeps the standard time")
	town_queue.cancel_unit(0)
	await get_tree().process_frame


func _check_charge() -> void:
	_become(0, FRENCH)
	_become(1, ENGLISH)
	var chevalier: UnitBase = _unit(CAVALRY, 0, Vector2(60, 0))
	var target: UnitBase = _unit(UnitData.UnitType.INFANTRY, 1, Vector2(80, 0))
	var horseman: UnitBase = _unit(CAVALRY, 1, Vector2(100, 0))
	target.max_hp = 5000.0
	target.hp = 5000.0
	var recharge: float = UnitAbilities.CHARGE_RECHARGE_SECONDS
	check(chevalier._ability_kind == UnitAbilities.Kind.CHARGE and not chevalier._ability_ready and horseman._ability_kind == UnitAbilities.Kind.NONE, "a new Chevalier has Charge, not yet ready; an English Horseman has none")
	_tick(chevalier, recharge - 0.5)
	check(not chevalier._ability_ready and not _overlay_visible(chevalier), "not ready before %d s" % int(recharge))
	_tick(chevalier, 0.6)
	check(chevalier._ability_ready and _overlay_visible(chevalier), "ready after %d s without attacking, pennon raised" % int(recharge))
	var plain: float = Combat.calculate_unit_damage(chevalier, target)
	var bonus: float = round(chevalier.damage * UnitAbilities.CHARGE_DAMAGE_RATIO)
	var before: float = target.hp
	Combat.queue_melee_attack(chevalier, target)
	await get_tree().process_frame
	await get_tree().process_frame
	check(is_equal_approx(before - target.hp, plain + bonus) and bonus == 25.0, "the charged hit deals +%d (%.0f, plain %.0f)" % [int(bonus), before - target.hp, plain])
	check(not chevalier._ability_ready and chevalier._ability_timer == 0.0 and not _overlay_visible(chevalier), "the Charge is spent and the pennon drops")
	before = target.hp
	Combat.queue_melee_attack(chevalier, target)
	await get_tree().process_frame
	await get_tree().process_frame
	check(is_equal_approx(before - target.hp, plain), "the next hit is an ordinary one")
	_tick(chevalier, recharge * 0.6)
	Combat.queue_melee_attack(chevalier, target)
	await get_tree().process_frame
	_tick(chevalier, recharge * 0.6)
	check(not chevalier._ability_ready, "every attack restarts the rest")
	_tick(chevalier, recharge * 0.5)
	check(chevalier._ability_ready, "and it recharges from the last attack")
	# A building takes the Charge too.
	var house: BuildingBase = _building(BuildingData.BuildingType.HOUSE, 1)
	var house_before: int = house.hp
	Combat.deal_damage_to_building(chevalier, house)
	check(house_before - house.hp == Combat.calculate_building_damage(chevalier) + int(bonus) and not chevalier._ability_ready, "a charged hit on a building adds the same bonus and spends it")
	# The unit's own frame drives the timer (one hook in UnitBase._process).
	chevalier.stance = UnitBase.Stance.STAND_GROUND
	chevalier.global_position += Vector2(4000, 0)
	var timer_before: float = chevalier._ability_timer
	chevalier._process(0.25)
	check(is_equal_approx(chevalier._ability_timer, timer_before + 0.25), "UnitBase._process advances the ability")
	chevalier.global_position -= Vector2(4000, 0)
	# Chivalry: French only, at the Stable, Castle Age.
	var stable: BuildingBase = _building(BuildingData.BuildingType.STABLE, 0)
	var foreign_stable: BuildingBase = _building(BuildingData.BuildingType.STABLE, 1)
	check(_action_ids(stable, 0).has("research:chivalry") and not _action_ids(stable, 0).has("research:yam"), "the French Stable offers Chivalry and not Yam: " + str(_action_ids(stable, 0)))
	check(not _action_ids(foreign_stable, 1).has("research:chivalry") and GameManager.get_research_failure_reason(1, foreign_stable, "chivalry") == "unknown_research" and not GameManager.try_start_research(1, foreign_stable, "chivalry"), "an English Stable cannot see or start it")
	GameManager.players[0]["age"] = 2
	check(GameManager.get_research_failure_reason(0, stable, "chivalry") == "age_required", "Chivalry needs the Castle Age")
	GameManager.players[0]["age"] = 3
	var wounded: UnitBase = _unit(CAVALRY, 0, Vector2(60, 30))
	wounded.hp = wounded.max_hp * 0.5
	var base_hp: float = chevalier.max_hp
	var bank: Dictionary = ResourceManager.get_all_resources(0)
	check(GameManager.try_start_research(0, stable, "chivalry") and int(bank.food) - int(ResourceManager.get_resource(0, "food")) == 200 and int(bank.gold) - _gold(0) == 150 and stable.research_duration == 40.0, "Chivalry costs 200 food 150 gold and takes 40 s")
	main._advance_production_queues(39.0)
	check(chevalier.max_hp == base_hp and UnitAbilities.get_charge_recharge(0) == recharge, "nothing changes until it completes")
	main._advance_production_queues(1.5)
	check(GameManager.has_research(0, "chivalry") and UnitAbilities.get_charge_recharge(0) == 5.0 and UnitAbilities.get_charge_recharge(1) == recharge, "Chivalry halves the recharge to 5 s for its owner only")
	check(chevalier.max_hp == round(base_hp * 1.12) and chevalier.hp == chevalier.max_hp and is_equal_approx(wounded.hp, round(wounded.max_hp * 0.5)), "living Chevaliers gain 12%% HP and keep their ratio (%.0f)" % chevalier.max_hp)
	var recruit: UnitBase = _unit(CAVALRY, 0, Vector2(60, 60))
	check(recruit.max_hp == chevalier.max_hp and horseman.max_hp == float(UnitData.get_unit_stats(CAVALRY, 1).hp), "new Chevaliers arrive with it; the opponent's Horsemen are untouched")
	chevalier._ability_ready = false
	chevalier._ability_timer = 0.0
	_tick(chevalier, 4.5)
	check(not chevalier._ability_ready, "with Chivalry: not ready at 4.5 s")
	_tick(chevalier, 0.6)
	check(chevalier._ability_ready, "with Chivalry: ready at 5 s")
	check(UnitAbilities.card_line(CAVALRY, 0).contains("after 5 s"), "the card follows the research: " + UnitAbilities.card_line(CAVALRY, 0))
	# Knight after Chivalry keeps the bonus on the higher tier.
	check(GameManager.try_research(0, stable, "knight"), "Knight completes (instant fixture path)")
	var knight_hp: int = int(round(float(UnitData.UNITS[CAVALRY].hp) * float(UnitData.UNIT_TIERS[CAVALRY][2].hp_mult)))
	check(UnitData.get_unit_name(CAVALRY, 0) == "Chevalier II" and chevalier.max_hp == float(int(round(knight_hp * 1.12))), "the Knight tier stacks under Chivalry: %s %.0f" % [UnitData.get_unit_name(CAVALRY, 0), chevalier.max_hp])
	for unit: UnitBase in [chevalier, target, horseman, wounded, recruit]:
		unit.global_position += Vector2(0, 3000)


func _check_emplace() -> void:
	_become(0, ENGLISH)
	_become(1, FRENCH)
	var tile: float = MapData.range_tiles_to_world(1.0)
	var longbow: UnitBase = _unit(ARCHER, 0, Vector2(-60, 0))
	var archer: UnitBase = _unit(ARCHER, 1, Vector2(-80, 0))
	var base_range: float = MapData.range_tiles_to_world(float(UnitData.UNITS[ARCHER].attack_range))
	var base_speed: float = 1.0 / float(UnitData.UNITS[ARCHER].attack_interval)
	check(longbow._ability_kind == UnitAbilities.Kind.EMPLACE and is_equal_approx(longbow.attack_range, base_range) and longbow.max_hp == 60.0 and archer._ability_kind == UnitAbilities.Kind.NONE, "a Longbow starts at ordinary archer range (%.0f), fragile, with Emplace" % longbow.attack_range)
	_tick(longbow, UnitAbilities.EMPLACE_SECONDS - 0.2)
	check(not longbow._ability_ready, "not emplaced before 2.5 s")
	_tick(longbow, 0.3)
	check(longbow._ability_ready and _overlay_visible(longbow), "emplaced after standing still 2.5 s, stakes shown")
	check(is_equal_approx(longbow.attack_range, base_range + tile) and is_equal_approx(longbow.attack_speed, base_speed / 0.8), "emplaced: +1 range and attack interval x0.8")
	longbow.attack_target = archer
	longbow.attack_cooldown = 0.0
	longbow._perform_attack()
	check(is_equal_approx(longbow.attack_cooldown, float(UnitData.UNITS[ARCHER].attack_interval) * 0.8), "the next shot comes after %.2f s" % longbow.attack_cooldown)
	longbow._cancel_attack_windup()
	longbow.attack_target = null
	longbow.global_position += Vector2(4.0, 0.0)
	_tick(longbow, 0.3)
	check(longbow._ability_ready, "a nudge from formation spacing does not pull the stakes")
	longbow.global_position += Vector2(40.0, 0.0)
	_tick(longbow, 0.1)
	check(not longbow._ability_ready and not _overlay_visible(longbow) and is_equal_approx(longbow.attack_range, base_range) and is_equal_approx(longbow.attack_speed, base_speed), "moving pulls the stakes and restores range and speed")
	_tick(longbow, UnitAbilities.EMPLACE_SECONDS + 0.1)
	check(longbow._ability_ready, "it emplaces again where it stops")
	longbow.current_state = UnitBase.State.MOVING
	_tick(longbow, 0.1)
	check(not longbow._ability_ready, "a move order breaks it at once")
	longbow.current_state = UnitBase.State.IDLE
	_tick(archer, 5.0)
	check(not archer._ability_ready and is_equal_approx(archer.attack_range, base_range), "a French Archer never emplaces")
	# Yeomen: English only, Archery Range, Castle Age.
	var archery: BuildingBase = _building(BuildingData.BuildingType.ARCHERY_RANGE, 0)
	var tower: BuildingBase = _building(BuildingData.BuildingType.WATCH_TOWER, 0)
	var tower_range: float = tower.tower_attack_range
	_tick(longbow, UnitAbilities.EMPLACE_SECONDS + 0.1)
	var bank: Dictionary = ResourceManager.get_all_resources(0)
	check(_action_ids(archery, 0).has("research:yeomen") and GameManager.try_start_research(0, archery, "yeomen") and int(bank.wood) - int(ResourceManager.get_resource(0, "wood")) == 150 and int(bank.gold) - _gold(0) == 150 and archery.research_duration == 40.0, "Yeomen costs 150 wood 150 gold and takes 40 s")
	main._advance_production_queues(41.0)
	check(GameManager.has_research(0, "yeomen") and is_equal_approx(longbow.attack_range, base_range + tile * 2.0) and is_equal_approx(tower.tower_attack_range, tower_range + tile), "Yeomen: Longbows (emplaced or not) and towers gain +1 range")
	longbow.global_position += Vector2(40.0, 0.0)
	_tick(longbow, 0.1)
	check(is_equal_approx(longbow.attack_range, base_range + tile), "packing up removes only the stakes' range")
	var foreign_range: BuildingBase = _building(BuildingData.BuildingType.ARCHERY_RANGE, 1)
	check(not _action_ids(foreign_range, 1).has("research:yeomen") and not GameManager.try_start_research(1, foreign_range, "yeomen"), "the French cannot research Yeomen")
	for unit: UnitBase in [longbow, archer]:
		unit.global_position += Vector2(0, 3000)


func _check_pillage() -> void:
	_become(0, MONGOLS)
	_become(1, FRENCH)
	var outrider: UnitBase = _unit(CAVALRY, 0, Vector2(0, 80))
	var scout: UnitBase = _unit(UnitData.UnitType.SCOUT, 0, Vector2(20, 80))
	var chevalier: UnitBase = _unit(CAVALRY, 1, Vector2(40, 80))
	var house: BuildingBase = _building(BuildingData.BuildingType.HOUSE, 1)
	var own_house: BuildingBase = _building(BuildingData.BuildingType.HOUSE, 0)
	var per_hit: int = UnitAbilities.PILLAGE_GOLD_PER_BUILDING_HIT
	var per_kill: int = UnitAbilities.PILLAGE_GOLD_PER_VILLAGER_KILL
	check(outrider._ability_kind == UnitAbilities.Kind.PILLAGE and outrider.speed == 110.0 and outrider.max_hp == 140.0, "the Outrider is fast, light and pillages")
	var gold: int = _gold(0)
	var enemy_gold: int = _gold(1)
	var hp_before: int = house.hp
	Combat.deal_damage_to_building(outrider, house)
	check(_gold(0) == gold + per_hit and house_damage_is_plain(hp_before, house, outrider) and _gold(1) == enemy_gold, "+%d gold per hit on an enemy building, minted not stolen, with ordinary damage" % per_hit)
	check(outrider._ability_ready and _overlay_visible(outrider), "the loot sack shows")
	_tick(outrider, UnitAbilities.LOOT_SHOW_SECONDS + 0.2)
	check(not outrider._ability_ready and not _overlay_visible(outrider), "and is stowed again shortly after")
	gold = _gold(0)
	Combat.deal_damage_to_building(outrider, own_house)
	Combat.deal_damage_to_building(chevalier, own_house)
	check(_gold(0) == gold and _gold(1) == enemy_gold, "no gold from one's own building or for a Chevalier")
	var villager: UnitBase = _unit(UnitData.UnitType.VILLAGER, 1, Vector2(60, 80))
	var warrior: UnitBase = _unit(UnitData.UnitType.INFANTRY, 1, Vector2(80, 80))
	Combat.resolve_unit_hit(outrider, villager, 5.0, 1.0)
	check(_gold(0) == gold, "wounding a Villager pays nothing")
	Combat.resolve_unit_hit(outrider, villager, 9999.0, 1.0)
	check(_gold(0) == gold + per_kill, "+%d gold for slaying a Villager" % per_kill)
	Combat.resolve_unit_hit(outrider, warrior, 9999.0, 1.0)
	check(_gold(0) == gold + per_kill, "soldiers carry no loot")
	var enemy_villager: UnitBase = _unit(UnitData.UnitType.VILLAGER, 0, Vector2(100, 80))
	Combat.resolve_unit_hit(chevalier, enemy_villager, 9999.0, 1.0)
	check(_gold(1) == enemy_gold, "only Outriders pillage")
	# Yam: Mongols only, Stable, Feudal Age.
	var stable: BuildingBase = _building(BuildingData.BuildingType.STABLE, 0)
	GameManager.players[0]["age"] = 2
	var bank: Dictionary = ResourceManager.get_all_resources(0)
	check(_action_ids(stable, 0).has("research:yam") and not _action_ids(stable, 0).has("research:chivalry") and GameManager.try_start_research(0, stable, "yam") and int(bank.food) - int(ResourceManager.get_resource(0, "food")) == 150 and int(bank.gold) - _gold(0) == 100 and stable.research_duration == 30.0, "Yam is a Feudal research: 150 food 100 gold, 30 s")
	main._advance_production_queues(31.0)
	check(GameManager.has_research(0, "yam") and is_equal_approx(outrider.speed, 121.0) and is_equal_approx(scout.speed, float(UnitData.UNITS[UnitData.UnitType.SCOUT].speed) * 1.1), "Yam: living Outriders and Scouts move 10%% faster (%.1f, %.1f)" % [outrider.speed, scout.speed])
	check(is_equal_approx(_unit(CAVALRY, 0, Vector2(0, 110)).speed, 121.0) and chevalier.speed == float(UnitData.UNITS[CAVALRY].speed), "new Outriders too; enemy cavalry is unchanged")
	gold = _gold(0)
	Combat.deal_damage_to_building(outrider, house)
	var second_villager: UnitBase = _unit(UnitData.UnitType.VILLAGER, 1, Vector2(60, 110))
	Combat.resolve_unit_hit(outrider, second_villager, 9999.0, 1.0)
	check(_gold(0) == gold + per_hit * 2 + per_kill * 2, "Yam doubles Pillage (+%d)" % (_gold(0) - gold))
	check(UnitAbilities.card_line(CAVALRY, 0).contains("+%d gold" % (per_hit * 2)), "the card follows the research: " + UnitAbilities.card_line(CAVALRY, 0))
	await get_tree().process_frame
	for unit: UnitBase in [outrider, scout, chevalier]:
		unit.global_position += Vector2(0, 3000)


func house_damage_is_plain(hp_before: int, house: BuildingBase, attacker: UnitBase) -> bool:
	return hp_before - house.hp == Combat.calculate_building_damage(attacker)


func _check_gathering_hook() -> void:
	_become(0, MONGOLS)
	_become(1, ENGLISH)
	var berries: ResourceNode = null
	var trees: ResourceNode = null
	for node: ResourceNode in main.game_map.resource_nodes.values():
		if node.resource_type == "food" and berries == null: berries = node
		if node.resource_type == "wood" and trees == null: trees = node
	check(berries != null and trees != null, "fixture: the map has berries and trees")
	var sheep := Node2D.new()
	sheep.add_to_group(UnitAbilities.WILDLIFE_GROUP)
	add_child(sheep)
	var farm: BuildingBase = _building(BuildingData.BuildingType.FARM, 0)
	check(is_equal_approx(UnitAbilities.gather_bonus(0, "food", sheep), 0.3) and is_equal_approx(ResearchEffects.gather_multiplier(0, "food", sheep), 1.3), "Mongols gather wildlife 30% faster through the registry key")
	check(UnitAbilities.gather_bonus(0, "food", farm) == 0.0 and UnitAbilities.gather_bonus(0, "wood", trees) == 0.0 and UnitAbilities.gather_bonus(0, "gold", sheep) == 0.0, "farms, wood and gold get nothing")
	check(UnitAbilities.gather_bonus(1, "food", sheep) == 0.0 and is_equal_approx(ResearchEffects.gather_multiplier(1, "wood", trees), 1.2) and is_equal_approx(ResearchEffects.gather_multiplier(1, "food", berries), 1.0), "the English get +20% wood and no wildlife bonus")
	check((UnitAbilities.gather_bonus(0, "food", berries) > 0.0) == CivilizationData.WILDLIFE_BONUS_INCLUDES_BERRIES, "berries follow the one-line data switch (currently %s)" % str(CivilizationData.WILDLIFE_BONUS_INCLUDES_BERRIES))
	sheep.queue_free()


func _check_save_and_client() -> void:
	_become(0, ENGLISH)
	_become(1, FRENCH)
	check(SOLO_STATE.UNIT_FIELDS.has("_ability_timer") and SOLO_STATE.UNIT_FIELDS.has("_ability_ready"), "ability state is part of the saved unit fields")
	var longbow: UnitBase = _unit(ARCHER, 0, Vector2(-60, -60))
	var chevalier: UnitBase = _unit(CAVALRY, 1, Vector2(-90, -60))
	_tick(longbow, UnitAbilities.EMPLACE_SECONDS + 0.1)
	_tick(chevalier, 6.5)
	var state: RefCounted = SOLO_STATE.new()
	var data: Dictionary = state.capture(main)
	check(SOLO_STATE.validate(data).is_empty(), "a checkpoint with ability state validates: " + SOLO_STATE.validate(data))
	check((data.get("ext", {}) as Dictionary).has(UnitAbilities.SECTION), "the ability save section is registered")
	var saved_longbow: Dictionary = {}
	var saved_chevalier: Dictionary = {}
	for record: Dictionary in data.actors:
		if record.kind == "unit" and record.id == longbow.get_instance_id(): saved_longbow = record.fields
		if record.kind == "unit" and record.id == chevalier.get_instance_id(): saved_chevalier = record.fields
	check(saved_longbow.get("_ability_ready") == true and is_equal_approx(float(saved_chevalier.get("_ability_timer", 0.0)), 6.5) and saved_chevalier.get("_ability_ready") == false, "the checkpoint holds an emplaced Longbow and a half-rested Chevalier")
	var plain: Array[String] = ["attack_range", "attack_speed", "_ability_timer", "_ability_ready"]
	var restored_longbow: UnitBase = _unit(ARCHER, 0, Vector2(-60, -90))
	var restored_chevalier: UnitBase = _unit(CAVALRY, 1, Vector2(-90, -90))
	state._write(restored_longbow, plain, saved_longbow)
	state._write(restored_chevalier, plain, saved_chevalier)
	UnitAbilities.refresh_all(main)
	check(restored_longbow._ability_ready and is_equal_approx(restored_longbow.attack_range, longbow.attack_range) and is_equal_approx(restored_longbow.attack_speed, longbow.attack_speed) and _overlay_visible(restored_longbow), "a restored Longbow is still emplaced, with its stakes")
	_tick(restored_longbow, 0.5)
	check(restored_longbow._ability_ready, "and stays emplaced while it stands")
	restored_longbow.global_position += Vector2(40, 0)
	_tick(restored_longbow, 0.1)
	check(is_equal_approx(restored_longbow.attack_range, MapData.range_tiles_to_world(float(UnitData.UNITS[ARCHER].attack_range))) and is_equal_approx(restored_longbow.attack_speed, 1.0 / float(UnitData.UNITS[ARCHER].attack_interval)), "packing up after a restore returns exactly to base")
	_tick(restored_chevalier, 3.0)
	check(not restored_chevalier._ability_ready, "a restored Chevalier keeps its elapsed rest (9.5 s)")
	_tick(restored_chevalier, 0.6)
	check(restored_chevalier._ability_ready, "and is ready on time")
	# Client: the actor's `ability` flag drives the same overlay on a replica.
	var replica: UnitBase = _unit(CAVALRY, 1, Vector2(-120, -60))
	UnitAbilities.set_replica_ready(replica, true)
	check(replica._ability_ready and _overlay_visible(replica), "a client shows the pennon from the snapshot flag")
	UnitAbilities.set_replica_ready(replica, false)
	check(not _overlay_visible(replica), "and lowers it again")
	var plain_replica: UnitBase = _unit(UnitData.UnitType.INFANTRY, 1, Vector2(-150, -60))
	UnitAbilities.set_replica_ready(plain_replica, true)
	check(not _overlay_visible(plain_replica), "a unit without an ability never grows an overlay")


func _check_ai() -> void:
	# A Mongol AI researches Yam through the data-driven priority list.
	_become(1, MONGOLS)
	GameManager.players[1]["age"] = 2
	var ai: Node = main.ai_controller
	var stable: BuildingBase = _building(BuildingData.BuildingType.STABLE, 1)
	ai._my_buildings = main._player_buildings[1]
	ai._is_under_pressure = true
	ai._saving_for_age_up = false
	ai.difficulty = 0  # Easy keeps to Loom and line upgrades.
	for attempt: int in 6:
		ai._check_research()
		main._advance_production_queues(60.0)
	check(not GameManager.has_research(1, "yam") and not _stable_researching(1, "yam"), "an Easy AI leaves unique technologies alone")
	ai.difficulty = 1
	var started: bool = false
	for attempt: int in 24:
		ai._check_research()
		if _stable_researching(1, "yam") or GameManager.has_research(1, "yam"):
			started = true
			break
		main._advance_production_queues(60.0)
	check(started, "the Mongol AI starts Yam at its Stable (researched: %s, reason: %s, trade %s, boom %s, recovery %s)" % [str(GameManager.researched_upgrades[1]), GameManager.get_research_failure_reason(1, stable, "yam"), str(ai._allows_trade_capital_spend({"food": 150, "gold": 100})), str(ai._allows_boom_spend({"food": 150, "gold": 100})), str(ai._needs_compact_worker_recovery())])
	check(not GameManager.has_research(1, "chivalry") and not GameManager.has_research(1, "yeomen"), "and never another kingdom's technology")


func _stable_researching(player_id: int, research_id: String) -> bool:
	for building: Variant in main._player_buildings[player_id]:
		if is_instance_valid(building) and building.research_id == research_id:
			return true
	return false


func _finish() -> void:
	print(JSON.stringify({"test": "civ_abilities", "checks": checks, "failures": failures, "scope": "real Main scene; civ registry bonuses, prices and train times for human and AI, Charge/Chivalry, Emplace/Yeomen, Pillage/Yam, wildlife hook, saved state, client flag, AI research"}))
	if failures.is_empty():
		print("[PASS] civ_abilities: %d checks" % checks)
	else:
		for failure: String in failures: push_error("[FAIL] civ_abilities: " + failure)
	if is_instance_valid(main): main.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
