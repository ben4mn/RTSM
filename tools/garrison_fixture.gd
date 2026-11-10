extends Node
## Shared real-match fixture for the Round 2 D1 cases (town bell, garrison,
## repair, healing). A seeded skirmish is loaded exactly as the game loads it;
## the strategic AI is frozen and time runs at 4x.

var failures: Array[String] = []
var checks: int = 0
var case_name: String = "garrison"
var main: Node = null
var map: Node2D = null
var tc: BuildingBase = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_start")


func _start() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 100
	GameManager.guided_opening_enabled = false
	if not await boot():
		push_error("[FAIL] %s: real match did not load" % case_name)
		get_tree().quit(1)
		return
	await run_cases()
	finish()


func run_cases() -> void:
	pass


func boot() -> bool:
	main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for _frame: int in 1200:
		if is_instance_valid(main.get("_building_placement")) and GameManager.current_state in [GameManager.GameState.PLAYING, GameManager.GameState.PAUSED] and is_instance_valid(main.get("_player_town_center")):
			break
		await get_tree().process_frame
	if GameManager.current_state == GameManager.GameState.PAUSED:
		GameManager.set_paused(false)
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return false
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = 4.0
	map = main.game_map
	tc = main._player_town_center
	for owner: int in 2:
		ResourceManager._player_resources[owner] = {"food": 5000, "wood": 5000, "gold": 5000}
	return true


func finish() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	if is_instance_valid(main):
		main.free()
	if failures.is_empty():
		print("[PASS] %s: %d checks" % [case_name, checks])
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[FAIL] %s: %s" % [case_name, failure])
		get_tree().quit(1)


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func step(seconds: float) -> void:
	## Advance the real match by `seconds` of game time.
	var until: float = GameManager.game_time + seconds
	for _frame: int in 20000:
		if GameManager.game_time >= until or GameManager.current_state != GameManager.GameState.PLAYING:
			return
		await get_tree().process_frame


func step_until(done: Callable, max_seconds: float) -> bool:
	var until: float = GameManager.game_time + max_seconds
	for _frame: int in 40000:
		if bool(done.call()):
			return true
		if GameManager.game_time >= until or GameManager.current_state != GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	return bool(done.call())


func tc_tile() -> Vector2i:
	return map.world_to_tile(tc.global_position)


func free_tile(near: Vector2i, skip: int = 0) -> Vector2i:
	var tiles: Array[Vector2i] = map.pathfinding.get_walkable_tiles_near(near, 4, skip + 1)
	return tiles[mini(skip, tiles.size() - 1)] if not tiles.is_empty() else near


func spawn(unit_type: int, owner: int, offset: Vector2i, index: int = 0) -> UnitBase:
	return spawn_at(unit_type, owner, free_tile(tc_tile() + offset, index))


func spawn_at(unit_type: int, owner: int, tile: Vector2i) -> UnitBase:
	## Synthetic units, as the dev harness makes them: housing is added when full.
	var pop_cost: int = int(UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1))
	if not GameManager.can_reserve_population(owner, pop_cost):
		GameManager.increase_population_cap(owner, pop_cost)
	return main._spawn_unit(unit_type, owner, map.tile_to_world(tile))


func own_villagers() -> Array[Villager]:
	var result: Array[Villager] = []
	for unit: Variant in main._player_units[0]:
		if is_instance_valid(unit) and unit is Villager and (unit as Villager).current_state != UnitBase.State.DEAD:
			result.append(unit as Villager)
	return result


func kill(unit: UnitBase) -> void:
	if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
		unit.take_damage(unit.max_hp * 10.0)
