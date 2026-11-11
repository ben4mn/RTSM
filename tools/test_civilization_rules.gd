extends Node
## Actual actor stats, paid queue/refunds, resource conservation, latching and
## the two online slot mappings. Full paid online play uses the paired harness.

const VILLAGER := preload("res://scenes/units/villager.tscn")
const ARCHER := preload("res://scenes/units/archer.tscn")
const CAVALRY := preload("res://scenes/units/cavalry.tscn")
const HOUSE := preload("res://scenes/buildings/house.tscn")
const RANGE := preload("res://scenes/buildings/archery_range.tscn")
var failures: Array[String] = []

class Supply extends Node2D:
	var remaining: int = 1000
	func harvest(requested: int) -> int:
		var result: int = mini(requested, remaining)
		remaining -= result
		return result

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_tree().current_scene = null
	_test_identity_and_baseline()
	_test_public_counter_names()
	_test_actors_and_paid_queue()
	_test_gathering()
	_test_network_slot_latching()
	if failures.is_empty():
		print("[PASS] civilization_rules: baseline, signature units, counters, real weaknesses, paid queues/refunds, harvest conservation, match latching and both online slots")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[FAIL] civilization_rules: " + failure)
		get_tree().quit(1)

func _setup(first: int, second: int) -> void:
	NetworkSession.online = false
	GameManager.selected_civilization = first
	GameManager.selected_opponent_civilization = second
	GameManager.initialize_game(2)
	ResourceManager.initialize_player(0)
	ResourceManager.initialize_player(1)

func _test_identity_and_baseline() -> void:
	_setup(0, 1)
	_expect(CivilizationData.ORDERED_IDS.size() == 3, "three selectable civilizations")
	_expect(CivilizationData.get_civilization_name(0) == "French", "civilization name lookup does not shadow Resource.get_name")
	for civilization: int in CivilizationData.ORDERED_IDS:
		var definition: Dictionary = CivilizationData.get_definition(civilization)
		_expect(not str(definition.weakness).is_empty() and not str(definition.strengths).is_empty(), "strength and weakness disclosed")
	# Round 2 C: the French are no longer the unmodified baseline; a caller
	# without a player still reads the published base data.
	for type: int in UnitData.UNITS:
		_expect(UnitData.get_unit_stats(type) == UnitData.UNITS[type], "published base unit unchanged: " + str(type))
		if type not in [UnitData.UnitType.VILLAGER, UnitData.UnitType.CAVALRY]:
			_expect(UnitData.get_unit_stats(type, 0) == UnitData.UNITS[type], "French unit without an override unchanged: " + str(type))
	_expect(UnitData.get_unit_name(UnitData.UnitType.CAVALRY, 0) == "Chevalier" and int(UnitData.get_unit_stats(UnitData.UnitType.CAVALRY, 0).hp) == int(UnitData.UNITS[UnitData.UnitType.CAVALRY].hp), "French cavalry is the Chevalier on Horseman stats")
	_expect(float(UnitData.get_unit_stats(UnitData.UnitType.VILLAGER, 0).build_time) == float(UnitData.UNITS[UnitData.UnitType.VILLAGER].build_time) * 0.8, "French Villagers train 20% faster")
	GameManager.selected_civilization = 2
	GameManager.selected_opponent_civilization = 2
	_expect(GameManager.get_player_civilization(0) == 0 and GameManager.get_player_civilization(1) == 1, "preferences cannot rewrite live match identities")
	GameManager.set_state(GameManager.GameState.GAME_OVER)
	_expect(GameManager.get_player_civilization(1) == 1, "identity stays latched through result")
	GameManager.initialize_game(2)
	_expect(GameManager.get_player_civilization(0) == 2, "new match adopts next selection")
	_setup(900, -7)
	_expect(GameManager.get_player_civilization(0) == 0 and GameManager.get_player_civilization(1) == 0, "invalid setup normalizes safely")
	var mutable: Dictionary = CivilizationData.get_definition(1)
	mutable.unit_overrides[2].hp_mult = 9.0
	_expect(float(CivilizationData.get_definition(1).unit_overrides[2].hp_mult) < 1.0 and int(CivilizationData.get_unit_stats(UnitData.UNITS[UnitData.UnitType.ARCHER], UnitData.UnitType.ARCHER, 1).hp) < int(UnitData.UNITS[UnitData.UnitType.ARCHER].hp), "returned metadata cannot mutate shared rules")

func _test_actors_and_paid_queue() -> void:
	_setup(1, 2)
	var longbow: UnitBase = ARCHER.instantiate()
	longbow.player_owner = 0
	add_child(longbow)
	var outrider: UnitBase = CAVALRY.instantiate()
	outrider.player_owner = 1
	add_child(outrider)
	var fragile_cavalry: UnitBase = CAVALRY.instantiate()
	fragile_cavalry.player_owner = 0
	add_child(fragile_cavalry)
	_expect(longbow.get_unit_type() == "Longbow" and longbow.hp == float(UnitData.get_unit_stats(UnitData.UnitType.ARCHER, 0).hp) and longbow.hp < float(UnitData.UNITS[UnitData.UnitType.ARCHER].hp) and longbow.attack_range == MapData.range_tiles_to_world(5), "Longbow actual name, HP and (un-emplaced) range")
	_expect(outrider.get_unit_type() == "Outrider" and outrider.hp == float(UnitData.get_unit_stats(UnitData.UnitType.CAVALRY, 1).hp) and outrider.hp < float(UnitData.UNITS[UnitData.UnitType.CAVALRY].hp) and outrider.speed == 110.0, "Outrider actual name, HP and speed")
	_expect(fragile_cavalry.hp == float(UnitData.get_unit_stats(UnitData.UnitType.CAVALRY, 0).hp) and fragile_cavalry.hp < float(UnitData.UNITS[UnitData.UnitType.CAVALRY].hp), "Verdant cavalry weakness applies to actual unit")
	_expect(Combat.get_counter_bonus(UnitData.UnitType.CAVALRY, UnitData.UnitType.ARCHER) == 1.5, "signature units retain familiar counter roles")
	GameManager.set_modifier(0, "attack", 2.0)
	_expect(Combat.get_effective_attack(longbow) == float(UnitData.UNITS[UnitData.UnitType.ARCHER].damage) + 2.0, "shared research stacks once on signature unit")
	var preview: Dictionary = Combat.get_effective_unit_type_stats(UnitData.UnitType.ARCHER, 0)
	_expect(int(preview.hp) == int(longbow.max_hp) and int(preview.damage) == int(UnitData.UNITS[UnitData.UnitType.ARCHER].damage) + 2 and int(preview.attack_range) == 5, "recruitment preview agrees with signature stats and research")
	var house: BuildingBase = HOUSE.instantiate()
	house.player_owner = 1
	house.state = BuildingBase.State.ACTIVE
	add_child(house)
	var mongol_house_hp: int = roundi(float(BuildingData.BUILDINGS[BuildingData.BuildingType.HOUSE]["hp"]) * CivilizationData.get_building_hp_multiplier(CivilizationData.Civilization.SUNSTRIDE_CLANS))
	_expect(house.hp == mongol_house_hp and house.max_hp == mongol_house_hp and mongol_house_hp < int(BuildingData.BUILDINGS[BuildingData.BuildingType.HOUSE]["hp"]), "Sunstride actual buildings have less health (data multiplier)")
	var production: BuildingBase = RANGE.instantiate()
	production.player_owner = 0
	production.state = BuildingBase.State.ACTIVE
	add_child(production)
	var queue: ProductionQueue = production.get_production_queue()
	var bank_before: Dictionary = ResourceManager.get_all_resources(0)
	var published_cost: Dictionary = UnitData.get_unit_cost(UnitData.UnitType.ARCHER)
	_expect(queue.enqueue_unit(UnitData.UnitType.ARCHER), "paid signature recruitment accepted")
	for resource: String in ["food", "wood", "gold"]:
		_expect(ResourceManager.get_resource(0, resource) == int(bank_before[resource]) - int(published_cost[resource]), "signature unit charges ordinary published " + resource + " cost")
	_expect(str(queue.get_queue_info()[0].name) == "Longbow" and queue.current_train_time == float(UnitData.UNITS[UnitData.UnitType.ARCHER].build_time), "queue names signature unit and retains training time")
	_expect(queue.cancel_unit(0), "signature queue cancellation accepted")
	_expect(ResourceManager.get_all_resources(0) == bank_before and GameManager.get_reserved_population(0) == 0, "cancellation refunds exactly and releases reservation")
	production.free()
	house.free()
	longbow.free()
	outrider.free()
	fragile_cavalry.free()

func _test_public_counter_names() -> void:
	_setup(0, 2)
	_expect(UnitData.get_unit_counter_name(UnitData.UnitType.INFANTRY, 0) == "Outriders", "Warrior counter names the opposing Sunstride signature")
	_expect(UnitData.get_unit_counter_name(UnitData.UnitType.INFANTRY, 1) == "Chevaliers", "opponent counter names the French Chevalier from its own perspective")
	_setup(1, 2)
	_expect(UnitData.get_unit_counter_name(UnitData.UnitType.INFANTRY, 1) == "Horsemen", "an unnamed cavalry line keeps the grammatical plural")
	_setup(0, 2)
	_setup(2, 1)
	_expect(UnitData.get_unit_counter_description(UnitData.UnitType.CAVALRY, 0) == "Beats Longbows", "cavalry counter names opposing Verdant signature")
	_expect(UnitData.get_unit_counter_description(UnitData.UnitType.CAVALRY) == "Beats Archers", "baseline counter descriptions remain independent of match setup")
	_expect(UnitData.get_unit_counter_description(UnitData.UnitType.SCOUT, 0) == "Unarmed · wide vision", "scout remains unarmed across civilizations")

func _harvest(civilization: int, resource: String, ticks: int, research_bonus: float = 0.0, wildlife: bool = false) -> int:
	_setup(civilization, 0)
	var worker: Villager = VILLAGER.instantiate()
	worker.player_owner = 0
	add_child(worker)
	var supply := Supply.new()
	if wildlife:
		supply.add_to_group(UnitAbilities.WILDLIFE_GROUP)
	add_child(supply)
	worker.gather_target = supply
	worker.carried_resource_type = resource
	worker.gather_rate += research_bonus
	worker.carry_capacity = 1000
	var gathered: int = 0
	for tick: int in ticks:
		var amount: int = worker._harvest_from_target()
		gathered += amount
		worker.carried_amount += amount
	_expect(supply.remaining == 1000 - gathered, "gather bonus removes real resources; no minted income")
	worker.carried_amount = worker.carry_capacity - 1
	_expect(worker._harvest_from_target() <= 1, "gather bonus respects shared cargo capacity")
	worker.free()
	supply.free()
	return gathered

func _test_gathering() -> void:
	# The 1.0/tick baseline (Round 2 E) needs a longer sample for both civilization
	# bonuses to land on whole resources. Cargo must not truncate the comparison.
	_expect(_harvest(0, "wood", 100) == 100, "baseline earns 1.0 resources per tick")
	_expect(_harvest(1, "wood", 100) == 120, "Verdant earns exactly +20% wood across fractional ticks")
	_expect(_harvest(1, "food", 100) == 100, "Verdant bonus does not leak to food")
	# Round 2 C: the flat Mongol +15% food became +30% on herds and game only
	# (a plain supply here stands in for a Farm-like source; see test_civ_abilities).
	_expect(_harvest(2, "food", 100) == 100, "Mongol flat food bonus is gone for ordinary sources")
	_expect(_harvest(2, "food", 100, 0.0, true) == 130, "Mongols earn exactly +30% food from wildlife across fractional ticks")
	_expect(_harvest(1, "food", 100, 0.0, true) == 100, "the wildlife bonus does not leak to other kingdoms")
	_expect(_harvest(2, "gold", 100) == 100, "Sunstride bonus does not leak to gold")
	_expect(_harvest(1, "wood", 100, UnitData.WHEELBARROW_GATHER_BONUS) == 150, "Wood bonus and Wheelbarrow compose without rounding loss")

func _test_network_slot_latching() -> void:
	GameManager.selected_civilization = 0
	GameManager.selected_opponent_civilization = 0
	NetworkSession.online = true
	NetworkSession.match_civilizations.assign([1, 2])
	for slot: int in 2:
		NetworkSession.player_slot = slot
		GameManager.initialize_game(2)
		_expect(GameManager.get_player_civilization(0) == [1, 2][slot], "online own identity follows server slot")
		_expect(GameManager.get_player_civilization(1) == [2, 1][slot], "online opponent identity follows opposite slot")
		_expect(GameManager.selected_civilization == 0 and GameManager.selected_opponent_civilization == 0, "online setup does not overwrite solo preferences")
	NetworkSession.leave_match()
	GameManager.initialize_game(2)
	_expect(GameManager.get_player_civilization(0) == 0 and GameManager.get_player_civilization(1) == 0, "solo after online restores selected identities")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
