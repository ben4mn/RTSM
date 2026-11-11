extends "res://tools/garrison_fixture.gd"
## Workstream H: touch economy helpers in a real seeded match.
## Back to work, the housing warning and one-tap House (with Undo), the Farm
## ring for "+ Food", the Town Center idle mark, Auto-reseed on by default,
## soldiers' attack-move ground tap (double tap falls back), villagers tapped
## onto their Town Center (deliver / lure), and the army group chips.


func run_cases() -> void:
	case_name = "touch_economy"
	await step(1.0)
	var economy: TouchEconomy = TouchEconomy.of(main)
	expect(economy != null, "the touch economy helper is installed")
	if economy == null:
		return
	expect(FarmPlots.is_auto_reseed(0) and not FarmPlots.is_auto_reseed(1), "Auto-reseed starts on for the player only")
	await _back_to_work(economy)
	await _housing(economy)
	await _farm_ring(economy)
	await _idle_town_center(economy)
	await _ground_taps()
	await _town_center_taps(economy)
	await _group_chips()


func _wood_worker() -> Villager:
	var workers: Array[Villager] = own_villagers()
	var worker: Villager = workers[0]
	var wood: Node2D = map.get_nearest_reachable_resource_node("wood", worker.global_position, 0, {}, worker)
	expect(wood != null, "there is wood to cut")
	worker.command_gather(wood)
	return worker


func _back_to_work(economy: TouchEconomy) -> void:
	var worker: Villager = _wood_worker()
	var tree: Node2D = worker.gather_target
	var working: bool = await step_until(func() -> bool: return worker.current_state == UnitBase.State.GATHERING and worker.carried_amount > 0, 40.0)
	expect(working, "a villager cuts wood")
	await step(1.5)
	worker.command_stop()
	await step(0.2)
	expect(worker.current_state == UnitBase.State.IDLE, "stopped, the villager stands idle")
	expect(economy.is_waiting_for_work(worker), "an idle villager with a job counts as waiting for work")
	var job: Dictionary = economy.resumable_job(worker)
	expect(job.get("kind") == "gather" and job.get("target") == tree, "its job is the same tree")
	expect(economy.back_to_work(0) >= 1, "Back to work sends it")
	expect(worker.current_state != UnitBase.State.IDLE and worker.carried_resource_type == "wood", "it is cutting wood again")
	# A worker waiting out a scare resumes at once.
	await step(1.0)
	worker._begin_recovery()
	worker._recovery_waiting = true
	worker.set_state(UnitBase.State.MOVING)
	expect(economy.is_waiting_for_work(worker), "a villager waiting out a raid counts too")
	expect(economy.back_to_work(0, [worker]) == 1 and not worker.is_auto_recovering(), "and goes back without waiting for the quiet timer")
	# The tappable offer appears once two or more unselected villagers wait.
	var idle_pair: Array[Villager] = []
	for candidate: Villager in own_villagers():
		if candidate != worker and idle_pair.size() < 2:
			var food: Node2D = map.get_nearest_reachable_resource_node("food", candidate.global_position, 0, {}, candidate)
			if food != null and candidate.command_gather(food):
				idle_pair.append(candidate)
	await step(4.0)
	for candidate: Villager in idle_pair:
		candidate.command_stop()
	map.selection_mgr.deselect_all()
	var offered: bool = await step_until(func() -> bool: return economy._offer_text.begins_with("Back to work"), 8.0)
	expect(offered, "a 'Back to work' toast is offered for idle villagers with jobs")
	expect(economy.request_back_to_work() >= 2, "one tap sends them all")
	await step(0.5)


func _housing(economy: TouchEconomy) -> void:
	var player: Dictionary = GameManager.players[0]
	var cap: int = int(player.population_cap)
	player["population_reserved"] = maxi(0, cap - int(player.population) - 1)
	economy._house_warned_cap = -1
	var warned: bool = await step_until(func() -> bool: return economy._house_toast.contains("House"), 3.0)
	expect(warned, "one slot from housed, a House toast appears (%s)" % economy._house_toast)
	expect(economy._house_toast.contains("tap"), "it is tappable while wood allows")
	var site: Variant = economy.find_site(BuildingData.BuildingType.HOUSE, 0)
	expect(site != null, "a House site is found near the base")
	var wood_before: int = ResourceManager.get_resource(0, "wood")
	var houses_before: int = _count(BuildingData.BuildingType.HOUSE)
	expect(economy.request_auto_house(), "one tap places a House")
	expect(_count(BuildingData.BuildingType.HOUSE) == houses_before + 1, "the House foundation stands")
	var cost: int = int(BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE, 0).get("wood", 0))
	expect(ResourceManager.get_resource(0, "wood") == wood_before - cost, "it was paid")
	var house: BuildingBase = _newest(BuildingData.BuildingType.HOUSE)
	var builder_found: bool = false
	for villager: Villager in own_villagers():
		builder_found = builder_found or villager.build_target == house
	expect(builder_found, "a villager goes to build it")
	expect(economy._undo_toast.contains("undo"), "an Undo toast follows")
	economy._undo_placement(weakref(house), map.world_to_tile(house.global_position), {"wood": cost})
	await step(0.2)
	expect(_count(BuildingData.BuildingType.HOUSE) == houses_before and ResourceManager.get_resource(0, "wood") == wood_before, "Undo removes it and refunds every coin")
	player["population_reserved"] = 0


func _farm_ring(economy: TouchEconomy) -> void:
	var worker: Villager = own_villagers()[1]
	var farms_before: int = _count(BuildingData.BuildingType.FARM)
	expect(economy.place_farm_for(worker), "the +Food helper founds a Farm")
	expect(_count(BuildingData.BuildingType.FARM) == farms_before + 1, "a Farm foundation stands")
	var farm: BuildingBase = _newest(BuildingData.BuildingType.FARM)
	expect(worker.build_target == farm, "the chosen worker builds it")
	var gap: float = map.world_to_tile(farm.global_position).distance_to(tc_tile())
	expect(gap <= 9.0, "it sits on the ring around the Town Center (%.1f tiles)" % gap)


func _idle_town_center(economy: TouchEconomy) -> void:
	var queue: ProductionQueue = tc.get_production_queue()
	while queue.get_queue_size() > 0:
		queue.cancel_unit(queue.get_queue_size() - 1)
	var idle: bool = await step_until(func() -> bool: return tc in economy.get_idle_town_centers(), 6.0)
	expect(idle, "an idle Town Center gets the idle mark")
	queue.enqueue_unit(UnitData.UnitType.VILLAGER)
	var busy: bool = await step_until(func() -> bool: return tc not in economy.get_idle_town_centers(), 3.0)
	expect(busy, "training clears it")
	while queue.get_queue_size() > 0:
		queue.cancel_unit(queue.get_queue_size() - 1)


func _ground_taps() -> void:
	var soldier: UnitBase = spawn(UnitData.UnitType.INFANTRY, 0, Vector2i(4, 4))
	var target_tile: Vector2i = free_tile(tc_tile() + Vector2i(8, 6))
	map.selection_mgr.select_single(soldier)
	map.selection_mgr.ground_tap_order = "attack"
	main._on_move_command(target_tile)
	map.selection_mgr.ground_tap_order = ""
	expect(soldier.attack_move, "a plain ground tap sends soldiers as an attack-move")
	map.selection_mgr.ground_tap_order = "retreat"
	main._on_move_command(target_tile)
	map.selection_mgr.ground_tap_order = ""
	expect(not soldier.attack_move and soldier.current_state == UnitBase.State.MOVING, "tapping the spot again falls back with a plain move")
	main._on_move_command(target_tile)
	expect(not soldier.attack_move, "the Move button (no ground tap) stays a plain move")
	map.selection_mgr.deselect_all()


func _town_center_taps(economy: TouchEconomy) -> void:
	var worker: Villager = _wood_worker()
	var loaded: bool = await step_until(func() -> bool: return worker.carried_amount > 0 and worker.current_state == UnitBase.State.GATHERING, 40.0)
	expect(loaded, "a woodcutter carries wood")
	map.selection_mgr.select_single(worker)
	expect(map.selection_mgr._home_building_order(tc) == "dropoff", "tapping the Town Center with cargo means deliver it")
	map.selection_mgr.dropoff_command.emit(tc)
	expect(bool(worker.get("_dropoff_route_active")), "the villager walks the cargo home")
	var delivered: bool = await step_until(func() -> bool: return worker.carried_amount == 0, 30.0)
	expect(delivered, "and delivers it")
	var back: bool = await step_until(func() -> bool: return worker.current_state == UnitBase.State.GATHERING, 20.0)
	expect(back, "then goes back to the trees")
	worker.command_stop()
	worker.carried_amount = 0
	expect(map.selection_mgr._home_building_order(tc) == "", "with empty hands the tap still selects the Town Center")
	tc.bell_active = true
	expect(map.selection_mgr._home_building_order(tc) == "garrison", "while the bell rings the tap shelters them")
	tc.bell_active = false
	map.selection_mgr.deselect_all()


func _group_chips() -> void:
	var overview: StrategyOverview = main.hud.get("_strategy_overview")
	expect(overview != null and overview._group_chip_buttons.size() == 3, "three group chips exist")
	var soldiers: Array[Node2D] = []
	for index: int in 3:
		soldiers.append(spawn(UnitData.UnitType.ARCHER, 0, Vector2i(5, 3), index))
	map.selection_mgr.select_many(soldiers)
	overview._snapshot["selection_count"] = soldiers.size()
	overview._group_chip_held = 3
	overview._on_group_chip_hold()
	await step(0.5)
	var controller: Node = main.get_node("StrategyController")
	controller.call("_refresh")
	expect(int((overview._snapshot.get("groups", {}) as Dictionary).get(3, 0)) == 3, "holding chip 3 saves the selection as group 3")
	expect(overview._group_chip_buttons[2].text == "3", "the chip shows the count")
	expect(overview._group_chips_wanted, "chips are wanted once there are fighters")
	map.selection_mgr.deselect_all()
	overview._group_chip_consumed = false
	overview._on_group_chip_pressed(3)
	expect(map.selection_mgr.selected.size() == 3, "tapping the chip selects the group")


func _count(building_type: int) -> int:
	var count: int = 0
	for building: Variant in main._player_buildings[0]:
		if is_instance_valid(building) and (building as BuildingBase).building_type == building_type and (building as BuildingBase).state != BuildingBase.State.DESTROYED and not (building as BuildingBase).is_queued_for_deletion():
			count += 1
	return count


func _newest(building_type: int) -> BuildingBase:
	var newest: BuildingBase = null
	for building: Variant in main._player_buildings[0]:
		if is_instance_valid(building) and (building as BuildingBase).building_type == building_type:
			newest = building
	return newest
