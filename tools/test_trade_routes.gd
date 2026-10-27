extends Node
var failures: Array[String] = []
func _ready() -> void:
	call_deferred("_run")
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.selected_population_limit = 100
	GameManager.guided_opening_enabled = false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var map: Node = main.game_map
	var center: Vector2i = map.map_generator.get_expansion_pocket_centers()[0]
	var post: BuildingBase = main._spawn_building(BuildingData.BuildingType.TRADE_POST, 0, center)
	post.complete_instantly()
	var trader: Trader = main._spawn_unit(UnitData.UnitType.TRADER, 0, map.tile_to_world(center + Vector2i(-1, 1)))
	_expect(trader.command_trade(post), "reachable exposed post starts a route")
	var initial_gold: int = ResourceManager.get_resource(0, "gold")
	var first_delivery: float = -1.0
	for tick: int in range(3600):
		trader._process(0.05)
		if trader.delivered_gold > 0:
			first_delivery = float(tick + 1) * 0.05
			break
	_expect(first_delivery > 10.0, "gold requires movement and a completed round trip")
	_expect(trader.delivered_gold == trader.get_trip_income(), "exact advertised gold paid once")
	_expect(ResourceManager.get_resource(0, "gold") - initial_gold == trader.delivered_gold, "income reaches only owning bank")
	var before_stop: int = ResourceManager.get_resource(0, "gold")
	trader.command_stop()
	for tick: int in range(400): trader._process(0.05)
	_expect(ResourceManager.get_resource(0, "gold") == before_stop, "Stop cancels trade without passive income")
	_expect(trader.command_trade(post), "trade post command resumes after Stop")
	for tick: int in range(200): trader._process(0.05)
	post.state = BuildingBase.State.DESTROYED
	trader._process(0.05)
	_expect(not trader.trade_route_active and trader.carried_gold == 0, "destroyed endpoint cancels cargo and route")
	var destroyed_gold: int = ResourceManager.get_resource(0, "gold")
	for tick: int in range(400): trader._process(0.05)
	_expect(ResourceManager.get_resource(0, "gold") == destroyed_gold, "destroyed post cannot pay")
	post.player_owner = 1
	post.state = BuildingBase.State.ACTIVE
	_expect(not trader.command_trade(post), "enemy post cannot be exploited")
	print(JSON.stringify({"test": "trade_routes", "failures": failures, "first_delivery_simulated_seconds": first_delivery, "gold_paid": trader.delivered_gold}))
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
