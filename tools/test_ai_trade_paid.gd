extends Node
## Controlled depleted-gold economy. Main and AI make ordinary paid requests;
## builder and caravan movement are integrated at 60Hz without passive income.
var checks: int = 0
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.selected_population_limit = 100
	GameManager.guided_opening_enabled = false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	check(main.get("_building_placement") != null, "real Main scene initialized")
	var ai: AIController = main.ai_controller
	ai._decision_timer.stop()
	ai._game_time = 900.0
	ai._is_under_pressure = false
	ai._saving_for_age_up = false
	GameManager.players[1].age = 2
	GameManager.players[1].population_cap = 100
	# Only fixture setup grants starting state. Neither policy nor full-match
	# observer receives these resources, extra workers or revealed terrain.
	while ai._get_villagers().size() < 5:
		main._spawn_unit(UnitData.UnitType.VILLAGER, 1, ai._base_position + Vector2(60, 70))
	for worker: Villager in ai._get_villagers(): worker.command_stop()
	main.game_map.fog_of_war.owning_player = 1
	main.game_map.fog_of_war.reveal_all()
	for source: ResourceNode in main.game_map.resource_nodes.values():
		if source.resource_type == "gold": source.remaining = 0
	ResourceManager.initialize_player(1, {"food": 0, "wood": 260, "gold": 40})
	var other_bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var population: int = int(GameManager.players[1].population)
	var post: BuildingBase
	for attempt: int in 4:
		ai._check_trade_economy()
		var posts: Array = ai._get_buildings_of_type(BuildingData.BuildingType.TRADE_POST)
		if not posts.is_empty():
			post = posts[0]
			break
		ai._game_time += 20.0
	check(post != null, "AI chooses legal visible site and Main accepts paid foundation")
	if post != null:
		check(post.state == BuildingBase.State.CONSTRUCTING, "post is a foundation, never instant completion")
		check(ResourceManager.get_all_resources(1) == {"food": 0, "wood": 60, "gold": 40}, "foundation pays exact 200 wood and preserves first Trader capital")
		check(main._ai_construction_jobs.has(post.get_instance_id()), "normal Main recovery ledger owns real construction")
		var build_seconds: float = 0.0
		for tick: int in 14400:
			for worker: Villager in ai._get_villagers(): worker._process(1.0 / 60.0)
			build_seconds += 1.0 / 60.0
			if post.state == BuildingBase.State.ACTIVE: break
		check(post.state == BuildingBase.State.ACTIVE and build_seconds > 5.0, "builder walks to post and completes real work over time")
		ai._game_time += 20.0
		ai._check_trade_economy()
		var queue: ProductionQueue = post.get_production_queue()
		check(queue.queue == [UnitData.UnitType.TRADER], "AI intent enqueues the real Main Trade Post")
		check(ResourceManager.get_all_resources(1) == {"food": 0, "wood": 0, "gold": 0}, "Trader pays exact 60 wood and 40 gold once")
		check(GameManager.get_reserved_population(1) == 2 and int(GameManager.players[1].population) == population, "paid finite queue reserves two population before spawn")
		ai._game_time += 20.0
		ai._check_trade_economy()
		check(queue.queue.size() == 1, "queued supply prevents a second purchase")
		main._advance_production_queues(queue.current_train_time + 0.01)
		var traders: Array[Trader] = []
		for unit: UnitBase in main._player_units[1]:
			if unit is Trader: traders.append(unit)
		check(traders.size() == 1 and queue.queue.is_empty(), "ordinary finite completion spawns exactly one Trader")
		check(GameManager.get_reserved_population(1) == 0 and int(GameManager.players[1].population) == population + 2, "birth converts reservation into exactly two live population")
		if traders.size() == 1:
			var trader: Trader = traders[0]
			check(trader.trade_route_active, "Main assigns completed Trader to its producer's reachable route")
			var delivery_seconds: float = 0.0
			for tick: int in 14400:
				trader._process(1.0 / 60.0)
				delivery_seconds += 1.0 / 60.0
				if trader.delivered_gold > 0: break
			check(delivery_seconds > 10.0 and trader.delivered_gold == trader.get_trip_income(), "actual caravan movement earns exactly one advertised completed round trip")
			check(ResourceManager.get_resource(1, "gold") == trader.delivered_gold and trader.delivered_gold > 0, "renewable income reaches the depleted owning bank")
			trader.command_stop()
			var gold: int = ResourceManager.get_resource(1, "gold")
			for tick: int in 120: trader._process(1.0 / 60.0)
			check(ResourceManager.get_resource(1, "gold") == gold, "stopped route grants no passive gold")
			print(JSON.stringify({"fixture_build_seconds": build_seconds, "fixture_first_trip_seconds": delivery_seconds, "gold": trader.delivered_gold}))
	check(ResourceManager.get_all_resources(0) == other_bank, "paid AI investment and delivery never affect enemy bank")
	main.queue_free()
	await get_tree().process_frame
	print(JSON.stringify({"test": "ai_trade_paid", "checks": checks, "failures": failures, "scope": "controlled starting state, actual AI/Main paid foundation, real 60Hz builder work and caravan travel, manually advanced finite production; not natural match evidence"}))
	get_tree().quit(0 if failures.is_empty() else 1)
