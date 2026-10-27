extends "res://tools/test_ai_economic_investment.gd"
## Synthetic policy checks; the main trade suite exercises paid round trips.

class TradeMap extends InvestmentMap:
	var route_blocked: bool = false
	func get_building_dropoff_world_path(from: Vector2, to: Vector2, _footprint: Vector2i, _radius: float) -> PackedVector2Array:
		return PackedVector2Array() if route_blocked else PackedVector2Array([from, to])


func _run() -> void:
	_setup()
	var trade_map := TradeMap.new()
	fixture.add_child(trade_map)
	ai.game_map = trade_map
	ai._game_time = 700.0
	ResourceManager.initialize_player(1, {"food": 500, "wood": 500, "gold": 120})
	var builds: Array = []
	var trains: Array = []
	ai.ai_wants_to_build.connect(func(kind: int, tile: Vector2i, _rebuild: bool) -> void: builds.append({"kind": kind, "tile": tile}))
	ai.ai_wants_to_train.connect(func(_building: Node, kind: int) -> void: trains.append(kind))
	ai._check_trade_economy()
	_expect(builds.size() == 1 and builds[0].kind == BuildingData.BuildingType.TRADE_POST, "mature low-gold economy requests one paid post")
	ai._check_trade_economy()
	_expect(builds.size() == 1, "retry cooldown prevents construction spam")
	var post := _building("trade_post", Vector2i(26, 6))
	ai._game_time += 20.0
	ai._check_trade_economy()
	_expect(trains == [UnitData.UnitType.TRADER], "viable distant post requests a trader through the ordinary training signal")
	trade_map.route_blocked = true
	ai._game_time += 20.0
	ai._check_trade_economy()
	_expect(trains.size() == 1, "blockaded route does not buy a stranded trader")
	trade_map.route_blocked = false
	for index: int in 3: ai._my_units.append(_unit("trader", 1))
	ai._game_time += 20.0
	ai._check_trade_economy()
	_expect(trains.size() == 1, "three traders cap the investment")
	_expect(ai._get_military_units().size() == 3, "traders never enter army orders or count as fighting strength")
	_expect(ResourceManager.get_resource(1, "gold") == 120, "policy neither grants income nor bypasses Main payment")
	post.free()
	fixture.free()
	if failures.is_empty(): print("[PASS] ai_trade_policy: paid intents, distance/reachability, cooldown, trader cap, military exclusion")
	else:
		for failure: String in failures: push_error("[FAIL] ai_trade_policy: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
