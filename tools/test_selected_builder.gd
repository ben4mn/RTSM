extends Node
## The villagers the player selected build what they place, whatever they were
## doing; only with no villager selected does the nearest free worker go.

var _failures: Array[String] = []
var _main: Node = null
var _workers: Array[Villager] = []
@onready var root: Window = get_tree().root


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_time_scale: float = Engine.time_scale
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	root.size = Vector2i(844, 390)
	_expect(int(BuildingData.get_building_stats(BuildingData.BuildingType.HOUSE).get("pop_provided", 0)) == 20, "a House should house 20")
	if await _start_match():
		await _test_selected_busy_worker_builds()
	await _close_match()
	if await _start_match():
		await _test_every_selected_worker_builds()
	await _close_match()
	if await _start_match():
		await _test_no_selection_falls_back()
	await _close_match()
	Engine.time_scale = original_time_scale
	if _failures.is_empty():
		print("[PASS] selected_builder: selected busy worker builds, all selected build, no selection falls back, House houses 20")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] selected_builder: %s" % failure)
		get_tree().quit(1)


func _test_selected_busy_worker_builds() -> void:
	# Leave one worker idle near the site and pick a gathering one far away:
	# before the fix the idle one always won.
	var site: Vector2i = _home_tile() + Vector2i(4, 4)
	var map: Node2D = _main.get("game_map") as Node2D
	var site_world: Vector2 = map.tile_to_world(site)
	var sorted: Array[Villager] = _workers.duplicate()
	sorted.sort_custom(func(a: Villager, b: Villager) -> bool: return a.global_position.distance_squared_to(site_world) < b.global_position.distance_squared_to(site_world))
	var near: Villager = sorted[0]
	var far: Villager = sorted[sorted.size() - 1]
	near.command_stop()
	var selection: SelectionManager = (_main.get("game_map") as Node).get("selection_mgr") as SelectionManager
	selection.select_single(far)
	var house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, site)
	if house == null:
		return
	_expect(far.build_target == house, "the selected villager should build the House")
	_expect(near.build_target != house, "an unselected idle villager should not take the job")


func _test_every_selected_worker_builds() -> void:
	var selection: SelectionManager = (_main.get("game_map") as Node).get("selection_mgr") as SelectionManager
	selection.select_single(_workers[0])
	selection.call("_add_to_selection", _workers[1])
	var house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, _home_tile() + Vector2i(-4, 4))
	if house == null:
		return
	_expect(_workers[0].build_target == house and _workers[1].build_target == house, "both selected villagers should build")
	for worker: Villager in _workers.slice(2):
		_expect(worker.build_target != house, "unselected villagers should keep their work")


func _test_no_selection_falls_back() -> void:
	var selection: SelectionManager = (_main.get("game_map") as Node).get("selection_mgr") as SelectionManager
	selection.call("_clear_selection")
	var house: BuildingBase = _place(BuildingData.BuildingType.HOUSE, _home_tile() + Vector2i(4, -4))
	if house == null:
		return
	var builders: int = 0
	for worker: Villager in _workers:
		builders += int(worker.build_target == house)
	_expect(builders == 1, "with no selection one free villager should build, got %d" % builders)


func _home_tile() -> Vector2i:
	var map: Node2D = _main.get("game_map") as Node2D
	var town_center: Node2D = _main.get("_player_town_center") as Node2D
	return map.world_to_tile(town_center.global_position)


func _start_match() -> bool:
	GameManager.set_state(GameManager.GameState.MENU)
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	if _main.get("_building_placement") == null:
		_expect(false, "match initialization timed out")
		return false
	for frame: int in range(8):
		await get_tree().process_frame
	(_main.get("ai_controller") as Node).set_process(false)
	ResourceManager.add_resource(0, "wood", 500)
	_workers.clear()
	for unit: Node in _main.get("_player_units")[0]:
		if unit is Villager:
			_workers.append(unit as Villager)
	# Let the opening workers walk out to their resources first.
	Engine.time_scale = 4.0
	var deadline: int = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(_workers.size() >= 3, "the opening should have at least three workers, got %d" % _workers.size())
	return _workers.size() >= 3


func _close_match() -> void:
	_workers.clear()
	if is_instance_valid(_main):
		_main.free()
	_main = null
	GameManager.set_state(GameManager.GameState.MENU)
	await get_tree().process_frame


func _place(kind: int, anchor: Vector2i) -> BuildingBase:
	var map: Node2D = _main.get("game_map") as Node2D
	var placement: BuildingPlacement = _main.get("_building_placement") as BuildingPlacement
	var site: Vector2i = Vector2i(-1, -1)
	for radius: int in range(0, 10):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate: Vector2i = anchor + Vector2i(dx, dy)
				if placement.revalidate_confirmation(kind, map.tile_to_world(candidate), 0):
					site = candidate
					break
			if site.x >= 0:
				break
		if site.x >= 0:
			break
	_expect(site.x >= 0, "no legal visible site for %s" % BuildingData.get_building_name(kind))
	if site.x < 0:
		return null
	var count_before: int = (_main.get("_player_buildings")[0] as Array).size()
	_main.call("_on_placement_confirmed", kind, map.tile_to_world(site))
	var buildings: Array = _main.get("_player_buildings")[0]
	_expect(buildings.size() == count_before + 1, "placement did not create %s: %s" % [BuildingData.get_building_name(kind), str(_main.get("_last_placement_feedback"))])
	if buildings.size() != count_before + 1:
		return null
	return buildings.back() as BuildingBase


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
