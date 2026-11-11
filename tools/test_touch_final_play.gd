extends "res://tools/garrison_fixture.gd"
## Workstream I2: the last touch frictions from real play.
## Build from the Economy sheet whatever is selected (nearest free worker
## builds), Build beside a mixed selection with villagers, toasts that stay
## while their offer applies, the persistent "Work" chip for Back to work, and
## the running-out / bottleneck economy hints.


func run_cases() -> void:
	case_name = "touch_final_play"
	await step(1.0)
	var overview: StrategyOverview = main.hud.get("_strategy_overview") as StrategyOverview
	expect(overview != null, "the strategy overview exists")
	if overview == null:
		return
	await _economy_build(overview)
	await _mixed_selection_build()
	await _sticky_toast()
	await _work_chip(overview)
	await _running_out()
	await _bottleneck()


func _economy_build(overview: StrategyOverview) -> void:
	map.selection_mgr.select_single(tc)
	await step(0.2)
	overview.build_requested.emit(-1)
	await step(0.2)
	expect(map.selection_mgr.selected.is_empty(), "Economy > Build puts a Town Center selection away")
	expect(main.hud.is_build_menu_open(), "and opens the Build menu")
	main.hud.close_build_menu()
	await step(0.2)
	# A House tile goes straight to placement.
	map.selection_mgr.select_single(tc)
	overview.build_requested.emit(BuildingData.BuildingType.HOUSE)
	await step(0.2)
	expect(bool(main.get("_placement_active")) and int(main.get("_placement_type")) == BuildingData.BuildingType.HOUSE, "the House tile starts House placement")
	main._cancel_placement()
	await step(0.2)
	# Selected villagers stay the builders.
	var worker: Villager = own_villagers()[0]
	map.selection_mgr.select_single(worker)
	overview.build_requested.emit(-1)
	await step(0.2)
	expect(worker in map.selection_mgr.selected, "a villager selection is kept as the builders")
	expect(main.hud.is_build_menu_open(), "and the Build menu opens")
	main.hud.close_build_menu()
	map.selection_mgr.deselect_all()
	await step(0.2)


func _mixed_selection_build() -> void:
	var soldier: UnitBase = spawn(UnitData.UnitType.INFANTRY, 0, Vector2i(3, 3))
	var worker: Villager = own_villagers()[0]
	var mixed: Array[Node2D] = [worker, soldier]
	map.selection_mgr.select_many(mixed)
	await step(0.3)
	main.hud._apply_context_actions(main.get_viewport().get_visible_rect().size)
	expect(main.hud.build_menu_button.visible, "Build stays on screen for a villager + soldier selection")
	map.selection_mgr.deselect_all()
	kill(soldier)
	await step(0.3)


func _sticky_toast() -> void:
	var lane: ToastLane = main.hud.get("_notification_container") as ToastLane
	var holding: Array = [true]
	main.hud.show_notification("Sticky test offer", Color.WHITE, 0.3, func() -> void: pass, 2, func() -> bool: return bool(holding[0]))
	main.hud.show_notification("Plain test note", Color.WHITE, 0.3)
	await _real_wait(1.2)
	expect(lane.is_showing("Sticky test offer"), "an offer that still applies outlives its duration")
	expect(not lane.is_showing("Plain test note"), "a plain note does not")
	holding[0] = false
	await _real_wait(1.4)
	expect(not lane.is_showing("Sticky test offer"), "once it no longer applies, the offer leaves")
	for index: int in 4:
		main.hud.show_notification("Stack %d" % index, Color.WHITE, 3.0, func() -> void: pass, 2)
	expect(lane.visible_count() <= 2, "never more than two toasts (%d)" % lane.visible_count())
	lane.clear()


func _real_wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _work_chip(overview: StrategyOverview) -> void:
	var economy: TouchEconomy = TouchEconomy.of(main)
	var pair: Array[Villager] = []
	for candidate: Villager in own_villagers():
		if pair.size() >= 2:
			break
		var wood: Node2D = map.get_nearest_reachable_resource_node("wood", candidate.global_position, 0, {}, candidate)
		if wood != null and candidate.command_gather(wood):
			pair.append(candidate)
	await step(6.0)
	for candidate: Villager in pair:
		candidate.command_stop()
	map.selection_mgr.deselect_all()
	var shown: bool = await step_until(func() -> bool: return overview.get_back_to_work_count() >= 2, 4.0)
	expect(shown, "the Work chip counts villagers who can go back (%d)" % overview.get_back_to_work_count())
	overview.back_to_work_requested.emit()
	await step(0.3)
	var working: int = 0
	for candidate: Villager in pair:
		if candidate.current_state != UnitBase.State.IDLE:
			working += 1
	expect(working == pair.size(), "one tap on the chip sends them back to work")
	var cleared: bool = await step_until(func() -> bool: return overview.get_back_to_work_count() == 0, 3.0)
	expect(cleared and economy != null, "the chip clears once nobody waits")


func _running_out() -> void:
	var hints: EconomyHints = EconomyHints.of(main)
	expect(hints != null, "the economy hints are installed")
	if hints == null:
		return
	var fog: Node = map.get("fog_of_war") as Node
	if fog != null and fog.has_method("reveal_all"):
		fog.call("reveal_all")
	var miner: Villager = own_villagers()[2]
	var gold: ResourceNode = map.get_nearest_resource_node("gold", miner.global_position, -1, miner) as ResourceNode
	expect(gold != null, "the map has gold")
	if gold == null:
		return
	miner.command_gather(gold)
	await step(0.3)
	var radius: float = EconomyHints.LOCAL_RADIUS_TILES * float(MapData.TILE_WIDTH)
	for node: ResourceNode in hints._resource_nodes("gold"):
		if node.global_position.distance_to(gold.global_position) <= radius:
			node.remaining = mini(node.remaining, 10)
	var facts: Dictionary = hints.assess("gold")
	expect(bool(facts.running_out), "a nearly mined-out patch is running out (%s)" % str(facts))
	expect(facts.next != null, "the next explored gold is known")
	hints._running_out_msec.clear()
	hints.refresh()
	var lane: ToastLane = main.hud.get("_notification_container") as ToastLane
	expect(lane.is_showing("Gold is running out · tap: next gold"), "the running-out toast shows")
	var target: Node2D = facts.next as Node2D
	expect(hints.show_next_patch("gold"), "a tap shows the next patch")
	await step(0.2)
	expect(map.camera.position.distance_to(target.global_position) < float(MapData.TILE_WIDTH) * 4.0, "the camera jumps to it")
	if hints.needs_camp_near(target.global_position):
		expect(bool(main.get("_placement_active")) and int(main.get("_placement_type")) == BuildingData.BuildingType.RESOURCE_CAMP, "and a Camp placement starts there")
	main._cancel_placement()
	miner.command_stop()
	lane.clear()
	await step(0.2)


func _bottleneck() -> void:
	var hints: EconomyHints = EconomyHints.of(main)
	if hints == null:
		return
	var food_workers: int = 0
	for worker: Villager in own_villagers():
		var food: Node2D = map.get_nearest_reachable_resource_node("food", worker.global_position, 0, {}, worker)
		if food != null and worker.command_gather(food):
			food_workers += 1
	while food_workers < EconomyHints.BOTTLENECK_MOVE + 1:
		var extra: Villager = spawn(UnitData.UnitType.VILLAGER, 0, Vector2i(2, -2), food_workers) as Villager
		var food: Node2D = map.get_nearest_reachable_resource_node("food", extra.global_position, 0, {}, extra)
		if food == null or not extra.command_gather(food):
			break
		food_workers += 1
	await step(0.5)
	ResourceManager._player_resources[0] = {"food": 2000, "wood": 0, "gold": 500}
	hints._bottleneck_msec = -EconomyHints.BOTTLENECK_COOLDOWN_MSEC * 2
	hints._refresh_bottleneck(own_villagers())
	hints._bottleneck_since = GameManager.game_time - EconomyHints.BOTTLENECK_SECONDS - 1.0
	hints._refresh_bottleneck(own_villagers())
	expect(hints._bottleneck_text.begins_with("Food 2000 banked, wood short"), "a floating food bank with no wood offers a rebalance (%s)" % hints._bottleneck_text)
	var moved: int = hints.rebalance("food", "wood")
	expect(moved >= 1, "one tap moves food workers to wood (%d)" % moved)
	ResourceManager._player_resources[0] = {"food": 5000, "wood": 5000, "gold": 5000}
