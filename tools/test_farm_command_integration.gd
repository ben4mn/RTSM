extends Node
## Paid Main Farm construction and production, real group signal dispatch,
## Strategy allocation, and authoritative network command handling. Work is
## manually stepped for repeatability; native runs can capture or hold the map.

var _main: Node
var _map: Node2D
var _workers: Array[Villager] = []
var _failures: Array[String] = []
var _previous_preferences: Dictionary = {}
var _hold_native: bool = false
var _capture_path: String = "res://output/polish-2026-10-22/farm-commands"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		_hold_native = _hold_native or argument == "--hold-native"
	AudioManager.set_all_enabled(false)
	for property: String in ["selected_map_seed", "selected_map_archetype", "selected_population_limit", "selected_difficulty", "guided_opening_enabled"]:
		_previous_preferences[property] = GameManager.get(property)
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_population_limit = 30
	GameManager.selected_difficulty = AIController.Difficulty.EASY
	GameManager.guided_opening_enabled = false
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for _frame: int in range(900):
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_map = _main.get("game_map") as Node2D
	_main.set_process(false)
	_main.get("ai_controller").set_process(false)
	(_main.get("ai_controller").get("_decision_timer") as Timer).stop()
	for side: Array in _main.get("_player_units"):
		for unit: UnitBase in side:
			unit.set_process(false)
			if unit is Villager and unit.player_owner == 0:
				unit.command_stop()
				_workers.append(unit)
	_expect(_workers.size() >= 4, "natural opening provides four workers")
	if _workers.size() < 4:
		_finish()
		return
	var first: Villager = _workers[0]
	var farm: BuildingBase = _paid_farm(first)
	if farm == null:
		_finish()
		return
	# Main chooses the nearest eligible worker, independently of selection.
	# Follow that actual paid construction job when arranging the group test.
	for worker: Villager in _workers:
		if worker.build_target == farm:
			first = worker
			break
	var followers: Array[Villager] = _workers.duplicate()
	followers.erase(first)
	var second: Villager = followers[0]
	var third: Villager = followers[1]
	var fourth: Villager = followers[2]
	for _step: int in range(3600):
		first._process(1.0 / 30.0)
		if farm.state == BuildingBase.State.ACTIVE:
			break
	_expect(farm.state == BuildingBase.State.ACTIVE, "paid Farm completes through its real assigned builder")
	first.command_stop()
	var wood: Node2D = _map.get_nearest_reachable_resource_node("wood", second.global_position, 0, {}, second)
	_expect(wood != null and second.command_gather(wood), "second worker starts natural wood")
	for _step: int in range(3600):
		_main.call("_update_fog_of_war")
		second._process(1.0 / 30.0)
		if second.carried_amount > 0:
			break
	_expect(second.carried_amount > 0 and second.get_carried_resources().has("wood"), "group fixture carries genuinely harvested wood")
	var old_cargo: Dictionary = second.get_carried_resources().duplicate()
	var old_target: Node2D = second.gather_target
	_select([first, second, third])
	_map.selection_mgr.gather_command.emit(farm)
	_expect(farm.get_assigned_worker() == first, "Main group signal assigns exactly its first eligible worker")
	_expect(second.gather_target == old_target and second.get_carried_resources() == old_cargo, "Main rejected follower retains old job and exact cargo")
	_expect(third.current_state == UnitBase.State.IDLE and third.gather_target != farm, "Main rejected idle follower remains available")
	_expect(_latest_notice().contains("One worker per Farm") and _latest_notice().contains("keep their orders"), "mixed group gets clear capacity feedback")
	await _capture("01-group-one-worker")
	_select([second, third])
	_map.selection_mgr.gather_command.emit(farm)
	_expect(_latest_notice().contains("Farm occupied") and _latest_notice().contains("empty Farm"), "fully rejected group gets actionable occupied feedback")
	_expect(second.get_carried_resources() == old_cargo and second.gather_target == old_target, "fully rejected group keeps work and cargo unchanged")
	await _capture("02-occupied-feedback")

	var controller: Node = _main.get_node("StrategyController")
	var result: Dictionary = controller.call("try_allocate_worker", 0, "idle", "food")
	_expect(result.has("worker"), "Strategy finds a visible alternative for one idle worker")
	if result.has("worker"):
		var allocated: Villager = result.worker as Villager
		_expect(allocated in [third, fourth] and allocated.gather_target != farm, "Strategy skips the occupied Farm and changes one available worker")
	_expect(farm.get_assigned_worker() == first, "Strategy preserves existing farmer")
	# Explicit current-vision fixture: with berries outside current vision, the
	# occupied Farm is still visible but offers no second work slot. Restore every
	# fog cell immediately after this allocation check.
	var fog: FogManager = _map.get("fog_of_war") as FogManager
	var saved_food_visibility: Dictionary = {}
	for tile: Vector2i in _map.resource_nodes:
		var resource: ResourceNode = _map.resource_nodes[tile] as ResourceNode
		if resource.resource_type == "food":
			saved_food_visibility[tile] = fog.fog_grid[tile.y][tile.x]
			fog.fog_grid[tile.y][tile.x] = MapData.FogState.EXPLORED
	var unavailable: Dictionary = controller.call("try_allocate_worker", 0, "idle", "food")
	_expect(not unavailable.has("worker") and str(unavailable.get("error", "")).contains("work is available"), "Strategy explains unavailable work when only an occupied Farm is visible")
	_expect(fourth.current_state == UnitBase.State.IDLE, "failed Strategy allocation leaves the idle worker unchanged")
	for tile: Vector2i in saved_food_visibility:
		fog.fog_grid[tile.y][tile.x] = saved_food_visibility[tile]

	# Server authority uses the same Farm reservation. This directly tests the
	# real adapter; it does not simulate transport or claim a two-client match.
	var adapter: Node = load("res://scripts/network/network_match.gd").new()
	adapter.set("main", _main)
	adapter.set("game_map", _map)
	add_child(adapter)
	adapter.call("_register_server_entities")
	var packet: Dictionary = {"command": "gather", "target": NetworkSession.entity_id(farm), "ids": [NetworkSession.entity_id(second), NetworkSession.entity_id(fourth)]}
	var reason: String = str(adapter.call("execute_command", 0, packet))
	_expect(reason.contains("Farm occupied"), "server reports an all-refused Farm order truthfully")
	_expect(second.get_carried_resources() == old_cargo and second.gather_target == old_target, "server rejection preserves old job and cargo")
	first.command_stop()
	reason = str(adapter.call("execute_command", 0, packet))
	_expect(reason.is_empty() and farm.get_assigned_worker() == second, "server group accepts one worker when capacity opens")
	_expect(fourth.gather_target != farm, "server group cannot add a second farmer")
	adapter.free()

	# The next worker is an ordinary 50-Food paid birth, rallied to that exact
	# occupied Farm. It must find another current-visible food source.
	var tc: BuildingBase = (_main.get("_player_buildings") as Array)[0][0] as BuildingBase
	_select([tc])
	_map.selection_mgr.gather_command.emit(farm)
	_expect(tc.rally_resource_instance_id == farm.get_instance_id(), "Main accepts the selected TC's observed Farm rally")
	var queue: ProductionQueue = tc.get_production_queue() as ProductionQueue
	var food_before: int = ResourceManager.get_resource(0, "food")
	var units: Array = (_main.get("_player_units") as Array)[0]
	var count_before: int = units.size()
	_expect(queue.enqueue_unit(UnitData.UnitType.VILLAGER), "starting economy pays for the rallied worker")
	queue.advance(queue.current_train_time + 0.01)
	_expect(units.size() == count_before + 1 and ResourceManager.get_resource(0, "food") == food_before - 50, "paid production completes once for exactly50 Food")
	if units.size() == count_before + 1:
		var newborn: Villager = units.back() as Villager
		newborn.set_process(false)
		_expect(newborn.current_state == UnitBase.State.GATHERING and is_instance_valid(newborn.gather_target), "occupied Farm rally recovers to a real food job")
		_expect(newborn.gather_target != farm and newborn.carried_resource_type == "food", "new birth cannot steal its rally Farm's farmer")
		_expect(_map.is_resource_target_visible_to_player(newborn.gather_target, 0), "rally fallback reveals no hidden food")
		_expect(farm.get_assigned_worker() == second, "rally recovery leaves original farmer assigned")
		_workers.append(newborn)
	_select([farm])
	await _capture("03-paid-farm-info")
	if _hold_native and DisplayServer.get_name() != "headless" and _failures.is_empty():
		for worker: Villager in _workers:
			worker.set_process(true)
		_main.set_process(true)
		_main.get("hud").show_notification("Paid Farm ready: select two workers, then tap Farm.", KingdomTheme.TEAL)
		print("[READY] farm_command_integration: paid live native fixture; AI decisions paused for manual Farm checks")
		return
	_finish()


func _paid_farm(builder: Villager) -> BuildingBase:
	_select([builder])
	var placement: BuildingPlacement = _main.get("_building_placement")
	var spawn: Vector2i = _map.map_generator.spawn_positions[0]
	for radius: int in range(2, 10):
		# Prefer front-side ground so native evidence shows the paid field,
		# rather than hiding it behind the Town Center's roof.
		for dy: int in range(radius, -radius - 1, -1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var world: Vector2 = _map.tile_to_world(spawn + Vector2i(dx, dy))
				if not placement.revalidate_confirmation(BuildingData.BuildingType.FARM, world, 0):
					continue
				var wood: int = ResourceManager.get_resource(0, "wood")
				_main.call("_on_placement_confirmed", BuildingData.BuildingType.FARM, world)
				var farm: BuildingBase = (_main.get("_player_buildings") as Array)[0].back() as BuildingBase
				_expect(farm.building_type == BuildingData.BuildingType.FARM and ResourceManager.get_resource(0, "wood") == wood - 75, "Main placement charges the normal75 Wood")
				var assigned: bool = false
				for worker: Villager in _workers:
					assigned = assigned or worker.build_target == farm
				_expect(assigned, "Main assigns the paid construction job to a real eligible worker")
				return farm
	_expect(false, "seeded opening has no legal paid Farm location")
	return null


func _select(nodes: Array) -> void:
	_map.selection_mgr.deselect_all()
	for node: Node2D in nodes:
		_map.selection_mgr.call("_add_to_selection", node)
	_map.selection_mgr.selection_changed.emit(_map.selection_mgr.selected)


func _latest_notice() -> String:
	var feed: Node = _main.get("hud").get("_notification_container") as Node
	if feed.get_child_count() == 0:
		return ""
	return (feed.get_child(feed.get_child_count() - 1).get_child(0) as Label).text


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_capture_path))
	var screenshot: Image = get_viewport().get_texture().get_image()
	screenshot.save_png(_capture_path.path_join(name + ".png"))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_main):
		_main.free()
	for property: String in _previous_preferences:
		GameManager.set(property, _previous_preferences[property])
	GameManager.set_state(GameManager.GameState.MENU)
	if _failures.is_empty():
		print("[PASS] farm_command_integration: paid Farm build, Main group feedback/cargo, Strategy alternative, authoritative group rejection and paid occupied-Farm rally recovery")
	else:
		for failure: String in _failures:
			push_error("[FAIL] farm_command_integration: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
