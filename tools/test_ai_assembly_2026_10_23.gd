extends Node
## Paid production + actual AI order replacement, then explicitly synthetic
## mixed-unit/obstacle cases on the same canonical GameMap. No native claims.

const ROLES: Array[String] = ["infantry", "archer", "cavalry", "siege", "infantry", "archer"]
const DELTAS: Array[float] = [1.0 / 60.0, 0.05, 0.0333, 0.08]
var failures: Array[String] = []
var records: Array[Dictionary] = []
var checks: int = 0
var match_scene: Node
var map: Node2D
var ai: AIController

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_difficulty = AIController.Difficulty.EASY
	GameManager.selected_population_limit = 30
	match_scene = load("res://scenes/main/main.tscn").instantiate()
	add_child(match_scene)
	for frame: int in 900:
		if GameManager.current_state == GameManager.GameState.PLAYING and match_scene.get("_building_placement") != null: break
		await get_tree().process_frame
	map = match_scene.get("game_map")
	ai = match_scene.get("ai_controller")
	ai._decision_timer.stop()
	match_scene.process_mode = Node.PROCESS_MODE_DISABLED
	for y: int in range(10, 46):
		for x: int in range(30, 64):
			map.map_generator.grid[y][x] = MapData.TileType.GRASS
			map.pathfinding.update_tile(Vector2i(x, y), MapData.TileType.GRASS)
	_paid_production_recall()
	_mixed_policies_and_blockers()
	_fractional_anchor_and_exhaustion()
	var output: String = "res://output/polish-ai-assembly-2026-10-23"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var hashes: Dictionary = {}
	for source: String in ["scripts/ai/ai_controller.gd", "scripts/main/group_order_planner.gd", "scripts/main/main.gd", "scripts/units/unit_base.gd", "scripts/units/villager.gd", "tools/test_ai_assembly_2026_10_23.gd"]:
		hashes[source] = FileAccess.get_sha256("res://" + source)
	FileAccess.open(output.path_join("assembly.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Private headless canonical Main/GameMap. Five Warriors use normal starting bank and actual queue; production buildings and later mixed roster/obstacles are synthetic fixtures. Not a paid full match or performance sample.", "checks": checks, "failures": failures, "records": records, "source_sha256": hashes}, "  ") + "\n")
	match_scene.free()
	for failure: String in failures: push_error("[FAIL] ai_assembly_2026_10_23: " + failure)
	if failures.is_empty(): print("[PASS] ai_assembly_2026_10_23: paid birth→AI recall, mixed staging/reserve/retreat, stable orders, blocked slots, fractional bounds and released occupancy")
	get_tree().quit(0 if failures.is_empty() else 1)

func _paid_production_recall() -> void:
	var barracks: BuildingBase = match_scene.call("_spawn_building", BuildingData.BuildingType.BARRACKS, 1, Vector2i(60, 22))
	barracks.complete_instantly()
	barracks.set_rally_point(map.tile_to_world(Vector2i(60, 18)))
	var queue: ProductionQueue = barracks.get_production_queue()
	var before: Dictionary = ResourceManager.get_all_resources(1).duplicate()
	var previous_count: int = match_scene.get("_player_units")[1].size()
	for index: int in 5:
		_expect(queue.enqueue_unit(UnitData.UnitType.INFANTRY), "ordinary opening bank pays for five Warriors")
	for index: int in 5: queue.advance(queue.current_train_time + 0.01)
	var soldiers: Array[UnitBase] = []
	for unit: UnitBase in match_scene.get("_player_units")[1]:
		if unit.unit_type == UnitData.UnitType.INFANTRY: soldiers.append(unit)
	_expect(soldiers.size() == 5 and match_scene.get("_player_units")[1].size() == previous_count + 5, "five actual production completions create five tracked Warriors")
	_expect(ResourceManager.get_resource(1, "food") == int(before.food) - 250 and ResourceManager.get_resource(1, "wood") == int(before.wood) - 100, "five Warriors deduct exactly250Food and100Wood")
	_expect(GameManager.get_reserved_population(1) == 0, "paid population reservations consumed once")
	var initial: Dictionary = _positions(soldiers, true)
	_expect(float(initial.minimum_pair) >= 28.0, "Main already assigns distinct pending production rally slots")
	ai._recall_easy_unassigned_units([])
	var recalled: Dictionary = _positions(soldiers, true)
	_expect(float(recalled.minimum_pair) >= 28.0, "Easy recall preserves distinct destinations instead of collapsing paid births")
	_assert_no_churn(soldiers, "in_flight_recall", func() -> void: ai._recall_easy_unassigned_units([]))
	var moved: Dictionary = _drive(soldiers, 30.0)
	_expect(moved.arrived == 5 and moved.minimum_pair >= 20.0, "all paid fighters settle separately after AI recall")
	_assert_no_churn(soldiers, "settled_recall", func() -> void: ai._recall_easy_unassigned_units([]))
	for unit: UnitBase in soldiers:
		_expect(unit.stance == UnitBase.Stance.STAND_GROUND and not unit.attack_move, "Easy reserve stance and pressure ownership stay intact")
	records.append({"case": "five_paid_warriors", "starting_bank": before, "ending_bank": ResourceManager.get_all_resources(1), "production_destinations": initial, "AI_destinations": recalled, "movement": moved})
	_remove_units(soldiers)
	map.remove_building_obstacle(Vector2i(60, 22), barracks.footprint)
	ai.unregister_building(barracks)
	match_scene.get("_player_buildings")[1].erase(barracks)
	barracks.free()

func _mixed_policies_and_blockers() -> void:
	var soldiers: Array[UnitBase] = []
	for index: int in ROLES.size(): soldiers.append(_unit(ROLES[index], Vector2i(35 + index, 36)))
	ai.difficulty = AIController.Difficulty.MEDIUM
	ai._game_time = 100.0
	ai._town_center_count = 0
	ai._staging_point = map.tile_to_world(Vector2i(43, 27))
	ai._check_attack_or_defend()
	var staging: Dictionary = _drive(soldiers, 30.0)
	_expect(staging.arrived == soldiers.size() and staging.minimum_pair >= 20.0, "ordinary staging spreads mixed military")
	_expect(ai._last_strategy_decision == "opening_staging", "ordinary opening timing and strategy decision are unchanged")
	_assert_no_churn(soldiers, "ordinary_staging", func() -> void: ai._check_attack_or_defend())
	ai._base_position = map.tile_to_world(Vector2i(37, 31))
	var reserve_anchor: Vector2 = ai._base_position.lerp(ai._staging_point, 0.28)
	ai._rally_base_reserve(soldiers)
	var reserve: Dictionary = _drive(soldiers, 30.0)
	_expect(reserve.arrived == soldiers.size() and reserve.minimum_pair >= 20.0, "base reserve chooses separate reachable slots")
	for unit: UnitBase in soldiers: _expect(unit.position.distance_to(reserve_anchor) <= 56.0, "base reserve keeps its56px area")
	_assert_no_churn(soldiers, "base_reserve", func() -> void: ai._rally_base_reserve(soldiers))
	ai._staging_point = map.tile_to_world(Vector2i(42, 34))
	ai._attack_wave_units = soldiers.duplicate()
	ai._retreat_army()
	var retreat: Dictionary = _drive(soldiers, 30.0)
	_expect(retreat.arrived == soldiers.size() and retreat.minimum_pair >= 20.0, "retreat keeps separate legal endpoints")
	_assert_no_churn(soldiers, "retreat", func() -> void: ai._retreat_army())
	# A late Farm blocks accepted assembly positions; the next policy tick must
	# select legal alternatives rather than retain blocked move_target values.
	var farm_origin: Vector2i = map.world_to_tile(soldiers[0].move_target)
	var farm: BuildingBase = match_scene.call("_spawn_building", BuildingData.BuildingType.FARM, 1, farm_origin)
	farm.complete_instantly()
	ai._recall_easy_unassigned_units([])
	var after_farm: Dictionary = _drive(soldiers, 30.0)
	_expect(after_farm.arrived == soldiers.size() and after_farm.minimum_pair >= 20.0, "late Farm occupancy recovers to distinct legal assembly positions")
	for unit: UnitBase in soldiers: _expect(map.is_tile_walkable(map.world_to_tile(unit.position)), "late Farm cannot leave settled troops in its blocked footprint")
	records.append({"case": "synthetic_mixed_policies", "staging": staging, "reserve": reserve, "retreat": retreat, "late_farm": after_farm, "farm_tile": str(farm_origin)})
	map.remove_building_obstacle(farm_origin, farm.footprint)
	ai.unregister_building(farm)
	match_scene.get("_player_buildings")[1].erase(farm)
	farm.free()
	_remove_units(soldiers)

func _fractional_anchor_and_exhaustion() -> void:
	# Only these two candidates remain. They tie around the snapped map tile,
	# but only the second lies within the actual fractional AI hold radius.
	var center := Vector2i(45, 24)
	var anchor: Vector2 = map.tile_to_world(center) + Vector2(-16.0, -8.0)
	var outside: Vector2i = center + Vector2i(-1, -2)
	var inside: Vector2i = center + Vector2i(-2, -1)
	var unit: UnitBase = _unit("infantry", Vector2i(38, 26))
	var blockers: Array[UnitBase] = []
	for dy: int in range(-4, 5):
		for dx: int in range(-4, 5):
			var tile := center + Vector2i(dx, dy)
			if tile == outside or tile == inside: continue
			if map.tile_to_world(tile).distance_to(anchor) <= 60.0: blockers.append(_unit("infantry", tile))
	if ai.has_method("_move_to_assembly_slot"):
		_expect(ai.call("_move_to_assembly_slot", unit, anchor), "fractional anchor retains a reachable in-radius alternative")
		_expect(unit.move_target.distance_to(map.tile_to_world(inside)) < 0.1, "destination bound filters candidates before snapped-distance selection")
		var reserved: Vector2 = unit.move_target
		var probe: UnitBase = _unit("archer", Vector2i(38, 27))
		# In-flight ownership excludes the only legal slot. Retasking and death
		# release it with no independent reservation cache to expire.
		_expect(not ai.call("_move_to_assembly_slot", probe, anchor), "fully occupied bounded area does not fall back onto a reserved endpoint")
		unit.command_move(map.tile_to_world(Vector2i(35, 25)))
		_expect(ai.call("_move_to_assembly_slot", probe, anchor) and probe.move_target == reserved, "retasking releases the previous assembly destination")
		probe.current_state = UnitBase.State.DEAD
		unit.command_stop()
		_expect(ai.call("_move_to_assembly_slot", unit, anchor) and unit.move_target == reserved, "dead units release pending assembly occupancy")
		var original_orders: Array[Dictionary] = preload("res://scripts/main/group_order_planner.gd").plan(map, [unit] as Array[UnitBase], center, ai._my_units, 1)
		_expect(not original_orders.is_empty(), "default human planner signature remains available")
		_remove_units([probe])
	# Resource/terrain obstruction is canonical, not an enemy-position probe.
	map.pathfinding.update_tile(inside, MapData.TileType.WATER)
	if ai.has_method("_move_to_assembly_slot"):
		unit.command_stop()
		_expect(not ai.call("_move_to_assembly_slot", unit, anchor), "no in-radius route through blocked terrain is invented")
	map.pathfinding.update_tile(inside, MapData.TileType.GRASS)
	if ai.has_method("_move_to_assembly_slot"):
		_expect(ai.call("_move_to_assembly_slot", unit, anchor), "reopening terrain makes the released slot usable")
	_remove_units(blockers)
	_remove_units([unit])

func _assert_no_churn(units: Array[UnitBase], label: String, action: Callable) -> void:
	var before: Array = []
	for unit: UnitBase in units: before.append([unit.current_state, unit.move_target, unit.path, unit.path_index])
	for tick: int in 8: action.call()
	for index: int in units.size():
		var unit: UnitBase = units[index]
		_expect([unit.current_state, unit.move_target, unit.path, unit.path_index] == before[index], label + " repeated decisions preserve state, target and route progress")

func _drive(units: Array[UnitBase], maximum_seconds: float) -> Dictionary:
	var elapsed: float = 0.0
	var tick: int = 0
	while elapsed < maximum_seconds:
		var moving: bool = false
		var delta: float = DELTAS[tick % DELTAS.size()]
		for unit: UnitBase in units:
			var before: Vector2 = unit.position
			var was_walkable: bool = map.is_tile_walkable(map.world_to_tile(before))
			unit._process(delta)
			_expect(unit.position.distance_to(before) <= unit.speed * delta + 0.01, "assembly motion respects normal speed")
			if was_walkable:
				for sample: int in range(9): _expect(map.is_tile_walkable(map.world_to_tile(before.lerp(unit.position, float(sample) / 8.0))), "assembly motion never crosses solid terrain")
			moving = moving or unit.current_state == UnitBase.State.MOVING
		elapsed += delta
		tick += 1
		if not moving: break
	var result: Dictionary = _positions(units, false)
	result["elapsed_seconds"] = elapsed
	result["arrived"] = units.filter(func(unit: UnitBase) -> bool: return unit.current_state == UnitBase.State.IDLE and unit.position.distance_to(unit.move_target) <= 4.1).size()
	return result

func _positions(units: Array[UnitBase], destinations: bool) -> Dictionary:
	var positions: Array[Vector2] = []
	for unit: UnitBase in units: positions.append(unit.move_target if destinations else unit.position)
	var minimum: float = INF
	for first: int in positions.size():
		for second: int in range(first + 1, positions.size()): minimum = minf(minimum, positions[first].distance_to(positions[second]))
	return {"minimum_pair": minimum if is_finite(minimum) else -1.0, "positions": positions}

func _unit(role: String, tile: Vector2i) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/" + role + ".tscn").instantiate()
	unit.player_owner = 1
	unit.position = map.tile_to_world(tile)
	map.get_node("UnitsContainer").add_child(unit)
	ai.register_unit(unit)
	return unit

func _remove_units(units: Array[UnitBase]) -> void:
	for unit: UnitBase in units:
		ai._my_units.erase(unit)
		match_scene.get("_player_units")[1].erase(unit)
		unit.free()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message): failures.append(message)
