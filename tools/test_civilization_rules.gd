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
	_expect(CivilizationData.get_civilization_name(0) == "Crownlands", "civilization name lookup does not shadow Resource.get_name")
	for civilization: int in CivilizationData.ORDERED_IDS:
		var definition: Dictionary = CivilizationData.get_definition(civilization)
		_expect(not str(definition.weakness).is_empty() and not str(definition.strengths).is_empty(), "strength and weakness disclosed")
	for type: int in UnitData.UNITS:
		_expect(UnitData.get_unit_stats(type, 0) == UnitData.UNITS[type], "baseline unit unchanged: " + str(type))
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
	mutable.unit_overrides[2].hp = 999
	_expect(int(CivilizationData.get_definition(1).unit_overrides[2].hp) == 30, "returned metadata cannot mutate shared rules")

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
	_expect(longbow.get_unit_type() == "Longbow" and longbow.hp == 30.0 and longbow.attack_range == MapData.range_tiles_to_world(6), "Longbow actual name, HP and range")
	_expect(outrider.get_unit_type() == "Outrider" and outrider.hp == 70.0 and outrider.speed == 110.0, "Outrider actual name, HP and speed")
	_expect(fragile_cavalry.hp == 65.0, "Verdant cavalry weakness applies to actual unit")
	_expect(Combat.get_counter_bonus(UnitData.UnitType.CAVALRY, UnitData.UnitType.ARCHER) == 1.5, "signature units retain familiar counter roles")
	GameManager.player_upgrades[0]["attack_bonus"] = 2
	_expect(Combat.get_effective_attack(longbow) == 9.0, "shared research stacks once on signature unit")
	var preview: Dictionary = Combat.get_effective_unit_type_stats(UnitData.UnitType.ARCHER, 0)
	_expect(int(preview.hp) == 30 and int(preview.damage) == 9 and int(preview.attack_range) == 6, "recruitment preview agrees with signature stats and research")
	var house: BuildingBase = HOUSE.instantiate()
	house.player_owner = 1
	house.state = BuildingBase.State.ACTIVE
	add_child(house)
	_expect(house.hp == 400 and house.max_hp == 400, "Sunstride actual buildings have 20% less health")
	var production: BuildingBase = RANGE.instantiate()
	production.player_owner = 0
	production.state = BuildingBase.State.ACTIVE
	add_child(production)
	var queue: ProductionQueue = production.get_production_queue()
	var bank_before: Dictionary = ResourceManager.get_all_resources(0)
	_expect(queue.enqueue_unit(UnitData.UnitType.ARCHER), "paid signature recruitment accepted")
	_expect(ResourceManager.get_resource(0, "food") == int(bank_before.food) - 25 and ResourceManager.get_resource(0, "wood") == int(bank_before.wood) - 45, "signature unit charges ordinary published cost")
	_expect(str(queue.get_queue_info()[0].name) == "Longbow" and queue.current_train_time == 12.0, "queue names signature unit and retains training time")
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
	_expect(UnitData.get_unit_counter_name(UnitData.UnitType.INFANTRY, 1) == "Horsemen", "opponent counter names Crown cavalry from its own perspective")
	_setup(2, 1)
	_expect(UnitData.get_unit_counter_description(UnitData.UnitType.CAVALRY, 0) == "Beats Longbows", "cavalry counter names opposing Verdant signature")
	_expect(UnitData.get_unit_counter_description(UnitData.UnitType.CAVALRY) == "Beats Archers", "baseline counter descriptions remain independent of match setup")
	_expect(UnitData.get_unit_counter_description(UnitData.UnitType.SCOUT, 0) == "Unarmed · wide vision", "scout remains unarmed across civilizations")

func _harvest(civilization: int, resource: String, ticks: int, research_bonus: float = 0.0) -> int:
	_setup(civilization, 0)
	var worker: Villager = VILLAGER.instantiate()
	worker.player_owner = 0
	add_child(worker)
	var supply := Supply.new()
	add_child(supply)
	worker.gather_target = supply
	worker.carried_resource_type = resource
	worker.gather_rate += research_bonus
	worker.carry_capacity = 100
	var gathered: int = 0
	for tick: int in ticks:
		var amount: int = worker._harvest_from_target()
		gathered += amount
		worker.carried_amount += amount
	_expect(supply.remaining == 1000 - gathered, "gather bonus removes real resources; no minted income")
	worker.carried_amount = 99
	_expect(worker._harvest_from_target() <= 1, "gather bonus respects shared cargo capacity")
	worker.free()
	supply.free()
	return gathered

func _test_gathering() -> void:
	_expect(_harvest(0, "wood", 20) == 20, "baseline harvesting unchanged")
	_expect(_harvest(1, "wood", 20) == 24, "Verdant earns exactly +20% wood across fractional ticks")
	_expect(_harvest(1, "food", 20) == 20, "Verdant bonus does not leak to food")
	_expect(_harvest(2, "food", 20) == 23, "Sunstride earns exactly +15% food across fractional ticks")
	_expect(_harvest(2, "gold", 20) == 20, "Sunstride bonus does not leak to gold")
	_expect(_harvest(1, "wood", 20, UnitData.WHEELBARROW_GATHER_BONUS) == 30, "Wood bonus and Wheelbarrow compose without rounding loss")

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
