extends "res://tools/test_ai_trade_paid.gd"
## Explicitly funded Castle subsystem fixture, not a natural match. Support
## buildings/escorts are paid during setup. Thereafter only real caravan income
## may replenish gold, and the AI chooses all trade and military purchases.
var main: Node
var ai: AIController
var elapsed: float = 0.0
var deliveries: int = 0
var earned_gold: int = 0
var gold_spent: int = 0
var prior_gold: int = 0
var first_siege: float = -1.0

func _run() -> void:
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.selected_population_limit = 100
	GameManager.guided_opening_enabled = false
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	ai = main.ai_controller
	ai._decision_timer.stop()
	ai._game_time = 900.0
	ai.difficulty = AIController.Difficulty.MEDIUM
	ai._apply_difficulty_profile()
	ai._is_under_pressure = false
	ai._saving_for_age_up = false
	GameManager.players[1].age = 3
	GameManager.players[1].population_cap = 100
	while ai._get_villagers().size() < 5:
		main._spawn_unit(UnitData.UnitType.VILLAGER, 1, ai._base_position + Vector2(60, 70))
	for worker: Villager in ai._get_villagers(): worker.command_stop()
	main.game_map.fog_of_war.owning_player = 1
	main.game_map.fog_of_war.reveal_all()
	for source: ResourceNode in main.game_map.resource_nodes.values():
		if source.resource_type == "gold": source.remaining = 0
	# One initial grant, explicitly declared. Food/wood gathering stays ordinary;
	# no later grants, Sacred income, forced trade orders or free production.
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 2000, "gold": 140})
	var barracks: BuildingBase = _build_support(BuildingData.BuildingType.BARRACKS)
	var workshop: BuildingBase = _build_support(BuildingData.BuildingType.SIEGE_WORKSHOP)
	check(barracks != null and workshop != null, "support infrastructure is built by paid Main construction")
	if barracks == null or workshop == null:
		await _finish_stress()
		return
	var escorts: int = ai._get_attack_threshold()
	for index: int in escorts:
		check(barracks.get_production_queue().enqueue_unit(UnitData.UnitType.INFANTRY), "escort is normally paid")
	for tick: int in 7200:
		_tick()
		if ai._get_fighting_units().size() >= escorts: break
	check(ai._get_fighting_units().size() >= escorts, "normal queue time produces real escorts")
	check(ResourceManager.get_resource(1, "gold") == 40, "paid Workshop leaves exactly the first Trader bootstrap")
	ai._update_building_counts()
	ai._update_ai_state()
	prior_gold = ResourceManager.get_resource(1, "gold")
	ResourceManager.resources_changed.connect(_record_gold)
	var baseline: Dictionary = ResourceManager.get_all_resources(1).duplicate()
	elapsed = 0.0
	var queue_has_siege: bool = false
	var decision_frames: int = roundi(ai._decision_interval * 60.0)
	for tick: int in 18000:
		if tick % decision_frames == 0:
			ai._on_decision_tick()
		_tick()
		elapsed += 1.0 / 60.0
		queue_has_siege = queue_has_siege or ai._count_queued_unit(UnitData.UnitType.SIEGE) > 0
		if first_siege < 0.0:
			for unit: UnitBase in ai._get_fighting_units():
				if unit.unit_type == UnitData.UnitType.SIEGE: first_siege = elapsed
	var posts: Array = ai._get_buildings_of_type(BuildingData.BuildingType.TRADE_POST)
	var traders: Array[Trader] = []
	for unit: UnitBase in main._player_units[1]:
		if unit is Trader: traders.append(unit)
	check(posts.size() == 1 and posts[0].state == BuildingBase.State.ACTIVE, "AI chooses and completes exactly one paid post without a forced trade order")
	check(traders.size() in [1, 2], "AI purchases bounded real caravan supply")
	check(deliveries >= 5 and earned_gold >= 100, "repeated completed caravan trips sustain more than one payout")
	var delivered_sum: int = 0
	for trader: Trader in traders: delivered_sum += trader.delivered_gold
	check(delivered_sum == earned_gold, "every positive gold ledger entry is an actual completed caravan delivery")
	check(queue_has_siege and first_siege > 0.0, "AI spends earned trade gold on a normally paid Siege queue and completion")
	check(ResourceManager.get_resource(1, "gold") == int(baseline.gold) + earned_gold - gold_spent, "bank exactly reconciles initial bootstrap plus delivered gold minus ordinary spending")
	check(gold_spent >= 140, "actual spending includes Trader bootstrap and useful Siege, no passive minting")
	if not traders.is_empty():
		var victim: Trader = traders[0]
		var paid_before_death: int = victim.delivered_gold
		victim.take_damage(victim.hp + 1.0)
		for tick: int in 120: victim._process(1.0 / 60.0)
		check(victim.delivered_gold == paid_before_death, "a killed caravan cannot keep paying gold")
	print(JSON.stringify({"economic_seconds": elapsed, "initial_funded_state": {"age": 3, "workers": 5, "food": 1000, "wood": 2000, "gold": 140}, "after_support_bank": baseline, "trade_deliveries": deliveries, "trade_gold": earned_gold, "ordinary_gold_spending": gold_spent, "first_paid_siege_seconds": first_siege, "traders": traders.size(), "final_bank": ResourceManager.get_all_resources(1)}))
	await _finish_stress()

func _build_support(kind: int) -> BuildingBase:
	var tile: Vector2i = ai._find_build_location(kind)
	if tile == Vector2i(-1, -1): return null
	main._on_ai_wants_to_build(kind, tile, false)
	var building: BuildingBase = ai._find_building_of_type(kind)
	if building == null: return null
	for tick: int in 7200:
		_tick()
		if building.state == BuildingBase.State.ACTIVE: return building
	return null

func _tick() -> void:
	ai._game_time += 1.0 / 60.0
	main._advance_production_queues(1.0 / 60.0)
	for unit: UnitBase in main._player_units[1]:
		if unit is Villager or unit is Trader: unit._process(1.0 / 60.0)

func _record_gold(owner: int, kind: String, amount: int) -> void:
	if owner != 1 or kind != "gold": return
	var delta: int = amount - prior_gold
	if delta > 0:
		deliveries += 1
		earned_gold += delta
	else:
		gold_spent -= delta
	prior_gold = amount

func _finish_stress() -> void:
	if ResourceManager.resources_changed.is_connected(_record_gold): ResourceManager.resources_changed.disconnect(_record_gold)
	main.queue_free()
	await get_tree().process_frame
	print(JSON.stringify({"test": "ai_trade_sustained", "checks": checks, "failures": failures, "scope": "controlled funded Castle economy with finite gold absent; paid support setup, then full _on_decision_tick at normal Medium1.5s cadence and continuous60Hz production/builder/caravan simulation; combat movement excluded; no later grants or natural-duration claim"}))
	get_tree().quit(0 if failures.is_empty() else 1)
