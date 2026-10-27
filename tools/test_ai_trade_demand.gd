extends "res://tools/test_ai_economic_investment.gd"
## Controlled policy fixtures. Paid construction and delivery are a separate case.
var checks: int = 0
var builds: Array = []
var trains: Array = []
var trade_map: DemandMap

class DemandMap extends InvestmentMap:
	var route_blocked: bool = false
	var mine: ResourceNode
	func get_building_dropoff_world_path(from: Vector2, to: Vector2, _size: Vector2i, _radius: float) -> PackedVector2Array:
		return PackedVector2Array() if route_blocked else PackedVector2Array([from, to])
	func get_nearest_reachable_resource_node(kind: String, _from: Vector2, _owner: int, excluded: Dictionary) -> Node2D:
		return mine if kind == "gold" and is_instance_valid(mine) and enemy_visible and not excluded.has(mine.get_instance_id()) else null

func _expect(ok: bool, label: String) -> void:
	checks += 1
	super._expect(ok, label)

func _reset() -> void:
	_setup()
	GameManager.players[1].max_population = 100
	GameManager.players[1].population_cap = 100
	GameManager.players[1].age = 3
	ai._game_time = 900.0
	trade_map = DemandMap.new()
	fixture.add_child(trade_map)
	ai.game_map = trade_map
	builds.clear()
	trains.clear()
	ai.ai_wants_to_build.connect(func(kind: int, tile: Vector2i, _rebuild: bool) -> void: builds.append({"kind": kind, "tile": tile}))
	ai.ai_wants_to_train.connect(func(_building: Node, kind: int) -> void: trains.append(kind))
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 500, "gold": 120})

func _run() -> void:
	AudioManager.set_all_enabled(false)
	_reset()
	var rich := {"food": 1000, "wood": 100, "gold": 1500}
	ResourceManager.initialize_player(1, rich)
	var targets: Dictionary = ai._get_economy_worker_targets(10, rich)
	_expect(targets.gold == 0 and targets.food + targets.wood == 10 and targets.wood > 3, "100-pop surplus gold releases labor to scarce wood")
	ai._check_trade_economy()
	_expect(builds.is_empty() and ai._trade_capital.is_empty(), "rich bank never builds trade merely because ten minutes elapsed")
	_expect(ai._get_economy_worker_targets(10, {"food": 1000, "wood": 100, "gold": 0}).gold > 0, "real gold deficit restores mining demand")
	_reset()
	var mine := ResourceNode.new()
	mine.resource_type = "gold"
	mine.total_amount = 300
	mine.tile_position = Vector2i(10, 8)
	mine.position = map.tile_to_world(mine.tile_position)
	fixture.add_child(mine)
	trade_map.mine = mine
	ai._check_trade_economy()
	_expect(builds.is_empty() and ai._trade_capital.is_empty(), "low bank with a safe known rich mine avoids redundant trade")
	mine.position = map.tile_to_world(Vector2i(40, 25))
	mine.tile_position = Vector2i(40, 25)
	camp.position = mine.position + Vector2(40, 0)
	_expect(ai._has_productive_known_gold(ai._find_building_of_type(BuildingData.BuildingType.TOWN_CENTER)), "active owned camp makes a remote known mine productive")
	camp.state = BuildingBase.State.CONSTRUCTING
	_expect(not ai._has_productive_known_gold(ai._find_building_of_type(BuildingData.BuildingType.TOWN_CENTER)), "unfinished remote camp provides no dropoff")
	trade_map.enemy_visible = false
	trade_map.resource_queries = 0
	_expect(not ai._has_productive_known_gold(ai._find_building_of_type(BuildingData.BuildingType.TOWN_CENTER)) and trade_map.resource_queries == 0, "hidden mine stock is never read")
	_reset()
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 259, "gold": 40})
	var bank: Dictionary = ResourceManager.get_all_resources(1).duplicate()
	ai._check_trade_economy()
	_expect(builds.is_empty() and ai._trade_capital == {"wood": 260, "gold": 40}, "post waits for its complete paid first-caravan budget")
	_expect(ResourceManager.get_all_resources(1) == bank, "capital reservation never grants or spends money")
	_expect(not ai._try_train_from_building(BuildingData.BuildingType.BARRACKS, UnitData.UnitType.INFANTRY), "optional military cannot consume trade bootstrap wood")
	_expect(not ai._allows_trade_capital_spend(UnitData.get_unit_cost(UnitData.UnitType.SCOUT)), "scout replacement preserves the last bootstrap gold")
	ai._is_under_pressure = true
	_expect(ai._allows_trade_capital_spend({"wood": 40}), "current pressure immediately releases optional capital")
	ai._is_under_pressure = false
	ai._game_time = ai._trade_capital_until
	_expect(ai._allows_trade_capital_spend({"wood": 40}), "stale capital expires after its short decision window")
	_reset()
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 260, "gold": 0})
	ai._check_trade_economy()
	_expect(builds.is_empty() and ai._allows_trade_capital_spend({"food": 100, "wood": 40}), "zero-gold bootstrap cannot starve an otherwise affordable army")
	_expect(not ai._allows_trade_capital_spend({"gold": 10}), "unfunded bootstrap can preserve future gold without locking wood")
	var unfunded_post := _building("trade_post", Vector2i(26, 6))
	ai._game_time += 20.0
	ai._check_trade_economy()
	_expect(trains.is_empty() and ai._allows_trade_capital_spend({"food": 100, "wood": 40}), "existing post also releases wood when replacement Trader lacks gold")
	unfunded_post.free()
	_reset()
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 260, "gold": 40})
	ai._check_trade_economy()
	_expect(builds.size() == 1 and builds[0].kind == BuildingData.BuildingType.TRADE_POST, "exact affordable bootstrap requests one post")
	builds.clear()
	ai._check_building_construction()
	_expect(builds.size() == 1 and builds[0].kind == BuildingData.BuildingType.FARM, "needed Farm remains exempt from optional trade capital")
	builds.clear()
	GameManager.players[1].population_cap = GameManager.get_committed_population(1) + 1
	ai._check_house_need()
	_expect(builds.size() == 1 and builds[0].kind == BuildingData.BuildingType.HOUSE, "needed House remains exempt from optional trade capital")
	_reset()
	trade_map.route_blocked = true
	ai._check_trade_economy()
	_expect(builds.is_empty() and ai._trade_capital.is_empty(), "blocked path creates neither purchase nor capital lock")
	trade_map.route_blocked = false
	trade_map.hide_terrain = true
	ai._game_time += 20.0
	ai._check_trade_economy()
	_expect(builds.is_empty() and ai._trade_capital.is_empty(), "unseen building sites never create a trade commitment")
	_reset()
	var post: BuildingBase = _building("trade_post", Vector2i(26, 6))
	var home: BuildingBase = ai._find_building_of_type(BuildingData.BuildingType.TOWN_CENTER)
	var enemy: UnitBase = _unit("infantry", 0)
	enemy.position = (post.position + home.position) * 0.5
	ai._check_trade_economy()
	_expect(trains.is_empty() and ai._trade_capital.is_empty(), "visible enemy on compressed route segment rejects investment")
	trade_map.enemy_visible = false
	ai._game_time += 20.0
	ai._check_trade_economy()
	_expect(trains == [UnitData.UnitType.TRADER], "unseen enemies never veto a route")
	var farther: BuildingBase = _building("town_center", Vector2i(0, 0))
	var route: PackedVector2Array = ai._get_prospective_trade_route(post.position)
	_expect(route[-1] == farther.position, "planning checks Trader's farthest reachable active home")
	farther.state = BuildingBase.State.CONSTRUCTING
	_expect(ai._get_prospective_trade_route(post.position)[-1] == home.position, "unfinished home is excluded from trade planning")
	farther.state = BuildingBase.State.ACTIVE
	farther.player_owner = 0
	_expect(ai._get_prospective_trade_route(post.position)[-1] == home.position, "foreign home is excluded even in a stale owned registry")
	var queue: ProductionQueue = post.get_production_queue()
	_expect(queue.enqueue_unit(UnitData.UnitType.TRADER), "real queue accepts one ordinarily paid caravan")
	ai._game_time += 20.0
	ai._check_trade_economy()
	_expect(trains.size() == 1, "queued caravan counts toward speculative supply cap")
	queue.cancel_all()
	var trader := _unit("trader", 1) as Trader
	ai._my_units.append(trader)
	ai._game_time += 20.0
	ai._check_trade_economy()
	_expect(trains.size() == 1, "live undelivered caravan also prevents speculative overbuy")
	trader.delivered_gold = 25
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 500, "gold": 40})
	ai._game_time += 20.0
	ai._check_trade_economy()
	_expect(trains.size() == 2, "proven income with ongoing deficit permits one second caravan")
	_reset()
	while ai._get_fighting_units().size() < ai._get_attack_threshold(): ai._my_units.append(_unit("infantry", 1))
	var workshop: BuildingBase = _building("siege_workshop", Vector2i(20, 14))
	ai._update_building_counts()
	var plan: Array = ai._get_military_training_plan(ResourceManager.get_all_resources(1))
	_expect(ai._needs_compact_siege_purchase() and plan[0] == UnitData.UnitType.SIEGE, "standard 100-pop army funds one real siege need ahead of cheap endless escorts")
	_expect(workshop.get_production_queue().enqueue_unit(UnitData.UnitType.SIEGE), "siege demand uses the ordinary paid queue")
	_expect(not ai._needs_compact_siege_purchase(), "queued siege removes replacement demand without duplicate spending")
	fixture.free()
	print(JSON.stringify({"test": "ai_trade_demand", "checks": checks, "failures": failures, "scope": "controlled policy fixtures with ordinary queue payments, no natural-match timing claim"}))
	get_tree().quit(0 if failures.is_empty() else 1)
