extends Node
## Funded real placement/queue transactions with explicitly stepped construction
## and training clocks. Natural paid pacing is measured by the match probe.

var _failures: Array[String] = []
var _checks: int = 0
var _main: Node
var _profile: String

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	AudioManager.set_all_enabled(false)
	_expect(SkirmishData.DEFAULT_POPULATION_LIMIT == 100, "normal default100")
	for old: int in [20, 30, 40]:
		_expect(SkirmishData.restore_population_limit(old, 0) == (100 if old == 30 else old), "legacy migration %d" % old)
	for choice: int in SkirmishData.POPULATION_OPTIONS:
		_expect(SkirmishData.restore_population_limit(choice, 1) == choice, "new explicit choice survives reload %d" % choice)
	_expect(SkirmishData.get_economy_target(100) == 30 and SkirmishData.get_easy_economy_target(100) == 30, "large target leaves70slots for armies")
	for limit: int in [20,30,40]:
		_expect(SkirmishData.get_economy_target(limit) == int(limit / 2) and SkirmishData.get_easy_economy_target(limit) == int(limit * 2 / 5), "small economy split preserved")
	for civ: int in CivilizationData.ORDERED_IDS:
		for mode: int in [SkirmishData.MatchMode.STANDARD, SkirmishData.MatchMode.QUICK_CONTROL]:
			await _match(civ, mode)
	for failure: String in _failures: push_error("[FAIL] population_100: " + failure)
	if _failures.is_empty(): print("[PASS] population_100: %d checks; 3 civilizations × 2 modes, paid Houses15→25→35→…→100, partial/reserve gains, building loss, refunds, queue reservations/completion while overcap, migration and unchanged small budgets" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _match(civ: int, mode: int) -> void:
	_profile = "civ%d mode%d" % [civ, mode]
	GameManager.selected_population_limit = 100
	GameManager.selected_civilization = civ
	GameManager.selected_opponent_civilization = civ
	GameManager.selected_match_mode = mode
	GameManager.selected_map_seed = 101
	GameManager.guided_opening_enabled = false
	GameManager.set_state(GameManager.GameState.MENU)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null: break
		await get_tree().process_frame
	_expect(_main.get("_building_placement") != null, "initialized")
	if _main.get("_building_placement") == null: return
	_main.set_process(false)
	_main.ai_controller.set_process(false)
	_main.ai_controller.get("_decision_timer").stop()
	_main.game_map.fog_of_war.set_process(false)
	_main.game_map.fog_of_war.reveal_all()
	for unit: Node in get_tree().get_nodes_in_group("units"): unit.set_process(false)
	ResourceManager.initialize_player(0, {"food":10000,"wood":10000,"gold":10000})
	_expect(_cap() == 15 and GameManager.get_player_population_limit(1) == 100, "symmetric100 with initial15housing")
	var houses: Array[BuildingBase] = []
	for number: int in 10:
		var expected: int = mini(100, 15 + number * 10)
		var menu: Control = _main.get("_build_menu")
		var gain: Dictionary = menu.call("_housing_gain", BuildingData.get_building_stats(BuildingData.BuildingType.HOUSE,0))
		_expect(gain.gain == mini(10,100-expected), "House shows remaining capacity before house%d" % number)
		var house: BuildingBase = _paid_house()
		if house == null: break
		houses.append(house)
		_expect(_cap() == expected, "foundation grants no capacity")
		house.add_build_progress(house.build_time)
		_expect(_cap() == mini(100,expected+10), "paid House raises actual capacity beyond30")
	_expect(houses.size() == 10 and _cap() == 100, "ten paid Houses reach100 withreserve")
	var hud: Node = _main.get("hud")
	hud.update_population(GameManager.get_committed_population(0),_cap())
	_expect(hud.get("pop_label").text.contains("100"), "visible global max")
	var house_info: String = _main.get("_build_menu").call("_format_tooltip",BuildingData.get_building_stats(BuildingData.BuildingType.HOUSE,0),BuildingData.BuildingType.HOUSE)
	_expect(house_info.contains("Match limit reached") and house_info.contains("reserve"), "max card explains why extra House cannot increase max")
	# Explicit synthetic pressure isolates ledger boundaries without recruiting
	# ninety-four units or changing costs/timing; real paid queues still run.
	_expect(GameManager.add_population(0,99-int(GameManager.players[0].population)), "pressure fixture fills99living")
	var tc: BuildingBase = _main.get("_player_buildings")[0][0]
	var queue: ProductionQueue = tc.get_production_queue()
	queue.set_process(false)
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	_expect(queue.enqueue_unit(UnitData.UnitType.VILLAGER), "lastslot accepts paidreservation")
	_expect(GameManager.get_committed_population(0)==100 and GameManager.get_reserved_population(0)==1, "queue reserves slot100")
	var paid_bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	_expect(not queue.enqueue_unit(UnitData.UnitType.VILLAGER) and ResourceManager.get_all_resources(0)==paid_bank, "slot101 rejected withoutcharge")
	_expect(queue.cancel_unit(0) and ResourceManager.get_all_resources(0)==bank and GameManager.get_committed_population(0)==99, "cancel refunds and frees slot")
	_expect(queue.enqueue_unit(UnitData.UnitType.VILLAGER), "requeue uses restoredslot")
	if houses.size()==10:
		houses[9].take_damage(houses[9].max_hp)
		_expect(_cap()==100, "first loss absorbed by nominalreserve")
		houses[8].take_damage(houses[8].max_hp)
		_expect(_cap()==95 and GameManager.get_reserved_population(0)==1, "second loss reduces95 but preserves paidqueue")
		queue.advance(float(UnitData.get_unit_stats(UnitData.UnitType.VILLAGER,0).build_time)+0.1)
		_expect(int(GameManager.players[0].population)==100 and GameManager.get_reserved_population(0)==0, "paid training finishes overcap")
		_expect(not queue.enqueue_unit(UnitData.UnitType.VILLAGER), "no newtraining whileovercap")
		var replacement: BuildingBase = _paid_house()
		if replacement != null: replacement.add_build_progress(replacement.build_time)
		_expect(_cap()==100, "paid rebuilding restores100")
	GameManager.selected_population_limit=20
	_expect(GameManager.get_player_population_limit(0)==100, "setup change cannot mutate active agreedlimit")
	_main.free()
	await get_tree().process_frame

func _paid_house() -> BuildingBase:
	var placement: BuildingPlacement = _main.get("_building_placement")
	var position := Vector2.ZERO
	for y: int in range(4, MapData.MAP_HEIGHT-4, 3):
		for x: int in range(4, MapData.MAP_WIDTH-4, 3):
			var candidate: Vector2 = _main.game_map.tile_to_world(Vector2i(x,y))
			if placement.revalidate_confirmation(BuildingData.BuildingType.HOUSE,candidate,0):
				position=candidate
				break
		if position != Vector2.ZERO: break
	_expect(position != Vector2.ZERO,"legal House footprint")
	if position==Vector2.ZERO: return null
	var count: int = _main.get("_player_buildings")[0].size()
	var wood: int = ResourceManager.get_resource(0,"wood")
	_main.call("_on_placement_confirmed",BuildingData.BuildingType.HOUSE,position)
	_expect(_main.get("_player_buildings")[0].size()==count+1,"normal placement transaction createdhouse")
	_expect(ResourceManager.get_resource(0,"wood")==wood-int(BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE).wood),"House charged normalcost")
	return _main.get("_player_buildings")[0].back() as BuildingBase if _main.get("_player_buildings")[0].size()==count+1 else null

func _cap() -> int:
	return int(GameManager.players[0].population_cap)

func _expect(condition: bool, message: String) -> void:
	_checks+=1
	if not condition: _failures.append(_profile+" "+message)
