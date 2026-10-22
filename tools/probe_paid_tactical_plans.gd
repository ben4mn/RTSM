extends Node
## Paid opening, then disclosed controlled placement and tactical group orders.
const POLICY: Script = preload("res://tools/fixtures/tactical_paid_opening.gd")
const PLANNER: Script = preload("res://scripts/main/group_order_planner.gd")
const STEP: float = 1.0 / 60.0
const ROSTERS: Dictionary = {
	"infantry_pressure": {UnitData.UnitType.INFANTRY: 6},
	"ranged_screen": {UnitData.UnitType.INFANTRY: 2, UnitData.UnitType.ARCHER: 4},
	"mounted_flank": {UnitData.UnitType.INFANTRY: 2, UnitData.UnitType.CAVALRY: 3},
	"mounted_direct": {UnitData.UnitType.INFANTRY: 2, UnitData.UnitType.CAVALRY: 3},
	"mounted_staged": {UnitData.UnitType.INFANTRY: 2, UnitData.UnitType.CAVALRY: 3},
}
var main: Node
var game_map: Node2D
var human: AIController
var units: Array[UnitBase] = []
var tracked: Dictionary = {}
var registered: Dictionary = {}
var deposits: Array[Dictionary] = [{"food": 0, "wood": 0, "gold": 0}, {"food": 0, "wood": 0, "gold": 0}]
var commands: Array[Dictionary] = []
var events: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var metrics: Dictionary = {}
var clock: float = -1.0
var plan: String = "infantry_pressure"
var center: Vector2
var upper: Vector2
var flags: Dictionary = {}
var retreaters: Array[UnitBase] = []
var result_path: String = ""
var failures: Array[String] = []
var ready_at: Array[float] = [-1.0, -1.0]
var capture_directory: String = ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var options: Dictionary = {"seed": "101", "map": "0", "plan": "infantry_pressure", "output": ""}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
			options[parts[0]] = parts[1]
	plan = str(options.plan)
	result_path = str(options.output)
	capture_directory = str(options.get("capture", ""))
	if not capture_directory.is_empty():
		RenderingServer.set_render_loop_enabled(false)
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_population_limit = 30
	GameManager.selected_difficulty = AIController.Difficulty.MEDIUM
	GameManager.selected_map_seed = int(options.seed)
	GameManager.selected_map_archetype = int(options.map)
	main = load("res://scenes/main/main.tscn").instantiate()
	main.get_node("AIController").set_script(POLICY)
	add_child(main)
	game_map = main.game_map
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	human = POLICY.new() as AIController
	human.set("roster", ROSTERS[plan].duplicate())
	human.player_id = 0
	human.enemy_id = 1
	human.difficulty = AIController.Difficulty.MEDIUM
	human.game_map = game_map
	human.map_generator = game_map.map_generator
	human.pathfinding = game_map.pathfinding
	main.add_child(human)
	human.ai_wants_to_build.connect(func(kind: int, tile: Vector2i, _rebuild: bool) -> void: main._on_placement_confirmed(kind, game_map.tile_to_world(tile)))
	human.ai_wants_to_train.connect(main._on_train_unit_requested)
	human.ai_wants_to_age_up.connect(main._on_age_up_requested)
	_register()
	var spawn: Vector2i = game_map.map_generator.spawn_positions[0]
	human.start_ai(spawn, game_map.tile_to_world(spawn))
	metrics = {"seed": int(options.seed), "map": int(options.map), "plan": plan, "initial_resources": [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)], "initial_workers": [4, 4], "first_hit": -1.0, "last_hit": -1.0, "largest_hit_gap": 0.0, "damage": [0.0, 0.0], "hits": [0, 0], "counter_hits": [0, 0], "kills": [0, 0], "navigation_failures": 0, "navigation_stall_unit_seconds": 0.0, "severe_friendly_overlap_pair_seconds": 0.0, "order_response_seconds": [], "unanswered_orders": 0, "target_changes": 0, "role_damage": [{}, {}], "user_data_dir": OS.get_user_data_dir(), "runtime_source_hashes": _hashes()}
	while GameManager.current_state == GameManager.GameState.PLAYING and GameManager.game_time < 700.0:
		_register()
		for owner: int in 2:
			if ready_at[owner] < 0.0 and _roster_ready(owner):
				ready_at[owner] = GameManager.game_time
		if ready_at[0] >= 0.0 and ready_at[1] >= 0.0:
			break
		await get_tree().process_frame
	metrics["paid_ready_at"] = ready_at
	metrics["opening_seconds"] = GameManager.game_time
	metrics["deposits"] = deposits.duplicate(true)
	metrics["bank_after_opening"] = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	metrics["opening_stats"] = main.get("_stats").duplicate(true)
	metrics["ages"] = [GameManager.get_player_age(0), GameManager.get_player_age(1)]
	metrics["economic_bonus_active"] = main.get("balance_ai_economic_bonus_active")
	metrics["paid_army_cost"] = [_roster_cost(ROSTERS[plan]), _roster_cost(main.ai_controller.get("roster"))]
	if ready_at[0] < 0.0 or ready_at[1] < 0.0:
		failures.append("Paid roster did not complete within 700 seconds")
		_finish()
		return
	# Controlled scenario begins here. Purchased armies keep their real stats.
	# Economy/buildings/AI are frozen; tactical units/projectiles advance at 60Hz.
	_disable(main)
	GameManager.set_process(false)
	main.ai_controller.get("_decision_timer").stop()
	human.get("_decision_timer").stop()
	(game_map.get_node("FogOfWar") as FogManager).owning_player = -1
	center = game_map.tile_to_world(Vector2i(36, 36))
	var routes: Array[Dictionary] = game_map.map_generator.get_tactical_routes()
	upper = game_map.tile_to_world(routes[1].waypoints[1])
	metrics["upper_crossing"] = [upper.x, upper.y]
	for owner: int in 2:
		for unit: UnitBase in main._player_units[owner]:
			if unit.unit_type not in [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT]:
				units.append(unit)
	_place_paid_armies()
	if not capture_directory.is_empty():
		game_map.get_node("FogLayer").hide()
		for unit: UnitBase in units:
			unit.show()
		var selected: Array[Node2D] = []
		selected.assign(_group(0))
		game_map.selection_mgr.select_many(selected)
		RenderingServer.set_render_loop_enabled(true)
	clock = 0.0
	_initial_orders()
	var ended: String = "90 second tactical limit"
	for tick: int in 5400:
		clock = float(tick) * STEP
		_schedule()
		for offset: int in units.size():
			var index: int = offset if tick % 2 == 0 else units.size() - 1 - offset
			var unit: UnitBase = units[index]
			if _alive(unit):
				unit._process(STEP)
		_advance_attacks()
		_track_tick()
		if tick % 30 == 0:
			_overlap()
		if tick % 60 == 0:
			samples.append(_sample())
		if not capture_directory.is_empty() or tick % 60 == 0:
			await get_tree().process_frame
			if tick % 60 == 0 and not capture_directory.is_empty() and int(clock) in [8, 16, 20, 24, 32]:
				await _capture()
		var alive: Array[int] = _alive_counts()
		if alive[0] == 0 or alive[1] == 0:
			ended = "elimination"
			break
		if clock >= 60.0 and float(metrics.last_hit) >= 0.0 and clock - float(metrics.last_hit) > 15.0:
			ended = "disengaged"
			break
	metrics["tactical_seconds"] = clock + STEP
	metrics["end"] = ended
	metrics["survivors"] = _alive_counts()
	metrics["remaining_hp"] = _hp_totals()
	metrics["final_unit_diagnostics"] = _unit_diagnostics()
	metrics["distance_by_unit"] = tracked.values().map(func(entry: Dictionary) -> float: return float(entry.distance))
	metrics["orders"] = commands
	metrics["group_orders_per_minute"] = float(commands.filter(func(order: Dictionary) -> bool: return int(order.owner) == 0).size()) * 60.0 / (clock + STEP)
	metrics["events"] = events
	metrics["samples"] = samples
	for entry: Dictionary in tracked.values():
		if float(entry.get("command_at", -1.0)) >= 0.0:
			metrics.unanswered_orders += 1
	_finish()


func _register() -> void:
	for owner: int in 2:
		for unit: UnitBase in main._player_units[owner]:
			if registered.has(unit.get_instance_id()):
				continue
			registered[unit.get_instance_id()] = true
			if owner == 0:
				human.register_unit(unit)
			if unit is Villager:
				unit.resource_deposited.connect(func(resource: String, amount: int) -> void: deposits[owner][resource] += amount)
		for building: BuildingBase in main._player_buildings[owner]:
			if owner == 0:
				human.register_building(building)


func _roster_ready(owner: int) -> bool:
	var wanted: Dictionary = ROSTERS[plan] if owner == 0 else main.ai_controller.get("roster")
	for role: int in wanted:
		var count: int = 0
		for unit: UnitBase in main._player_units[owner]:
			if _alive(unit) and unit.unit_type == role:
				count += 1
		if count != int(wanted[role]):
			return false
		var policy: AIController = human if owner == 0 else main.ai_controller
		if policy._count_queued_unit(role) > 0:
			return false
	return GameManager.get_player_age(owner) == 2


func _roster_cost(roster: Dictionary) -> Dictionary:
	var result: Dictionary = {"food": 0, "wood": 0, "gold": 0}
	for role: int in roster:
		var cost: Dictionary = UnitData.get_unit_cost(role)
		for resource: String in result:
			result[resource] += int(cost.get(resource, 0)) * int(roster[role])
	return result


func _place_paid_armies() -> void:
	var counts: Array[Dictionary] = [{}, {}]
	var used: Array[Vector2] = []
	for unit: UnitBase in units:
		var owner: int = unit.player_owner
		var index: int = int(counts[owner].get(unit.unit_type, 0))
		counts[owner][unit.unit_type] = index + 1
		var ranged: bool = unit.unit_type == UnitData.UnitType.ARCHER
		var desired: Vector2 = center + Vector2(-620.0 if owner == 0 else (290.0 if ranged else 220.0), 0.0)
		if owner == 0 and unit.unit_type != UnitData.UnitType.INFANTRY:
			desired.x -= 90.0
		desired.y += (float(index) - 1.0) * 44.0
		var position: Vector2 = _legal_slot(desired, used)
		used.append(position)
		unit.command_stop()
		unit.global_position = position
		unit.stance = UnitBase.Stance.STAND_GROUND if owner == 1 else UnitBase.Stance.AGGRESSIVE
		unit.attack_landed.connect(_hit)
		unit.unit_died.connect(_death)
		unit.navigation_failed.connect(func(_unit: UnitBase, _target: Vector2) -> void: metrics.navigation_failures += 1)
		tracked[unit.get_instance_id()] = {"last": position, "stall": 0.0, "target": 0, "command_at": -1.0, "distance": 0.0}
	metrics["initial_tactical_units"] = _sample()


func _legal_slot(desired: Vector2, used: Array[Vector2]) -> Vector2:
	var origin: Vector2i = game_map.world_to_tile(desired)
	var best: Vector2 = Vector2(INF, INF)
	var score: float = INF
	for dy: int in range(-6, 7):
		for dx: int in range(-6, 7):
			var tile: Vector2i = origin + Vector2i(dx, dy)
			if not game_map.pathfinding.is_walkable(tile):
				continue
			var world: Vector2 = game_map.tile_to_world(tile)
			var legal: bool = true
			for other: Vector2 in used:
				if other.distance_to(world) < 36.0:
					legal = false
			if legal and world.distance_squared_to(desired) < score and not game_map.pathfinding.get_tile_path(tile, Vector2i(36, 36)).is_empty():
				best = world
				score = world.distance_squared_to(desired)
	assert(best.is_finite(), "No legal connected tactical slot")
	return best


func _initial_orders() -> void:
	if plan == "mounted_staged":
		_issue(_group(0), center + Vector2(80.0, 0.0), false, "passive staging before the defended line")
	elif plan == "mounted_flank":
		_issue(_group(0, UnitData.UnitType.INFANTRY), center + Vector2(200.0, 0.0), true, "warriors pressure center")
		_issue(_group(0, UnitData.UnitType.CAVALRY), upper + Vector2(100.0, 0.0), false, "horsemen take upper crossing")
	elif plan == "ranged_screen":
		_issue(_group(0, UnitData.UnitType.INFANTRY), center + Vector2(180.0, 0.0), true, "warriors screen")
		_issue(_group(0, UnitData.UnitType.ARCHER), center + Vector2(300.0, 0.0), true, "archers follow screen")
	else:
		_issue(_group(0), center + Vector2(300.0, 0.0), true, "single-group direct pressure")


func _schedule() -> void:
	if plan == "mounted_staged" and not flags.has("staged"):
		var staging_ready: bool = true
		for unit: UnitBase in _group(0):
			if unit.global_position.distance_to(center + Vector2(80.0, 0.0)) > 90.0:
				staging_ready = false
		if staging_ready or clock >= 20.0:
			flags.staged = clock
			_issue(_group(0), center + Vector2(300.0, 0.0), true, "attack after the slower screen reaches staging")
	if plan == "mounted_flank" and not flags.has("flank"):
		var cavalry: Array[UnitBase] = _group(0, UnitData.UnitType.CAVALRY)
		if not cavalry.is_empty() and (_centroid(cavalry).distance_to(upper + Vector2(100.0, 0.0)) < 90.0 or clock >= 22.0):
			flags.flank = clock
			_issue(cavalry, center + Vector2(360.0, -32.0), true, "flank engages ranged rear")
	var first: float = float(metrics.first_hit)
	if plan in ["ranged_screen", "mounted_flank"] and first >= 0.0:
		if not flags.has("retreat") and clock >= first + 6.0:
			var role: int = UnitData.UnitType.ARCHER if plan == "ranged_screen" else UnitData.UnitType.CAVALRY
			var candidates: Array[UnitBase] = _group(0, role)
			candidates.sort_custom(func(a: UnitBase, b: UnitBase) -> bool: return a.hp / a.max_hp < b.hp / b.max_hp)
			for unit: UnitBase in candidates:
				if unit.hp < unit.max_hp and retreaters.size() < 2:
					retreaters.append(unit)
			flags.retreat = clock
			metrics["retreat_ordered"] = retreaters.size()
			_issue(retreaters, center + Vector2(-360.0, -120.0), false, "withdraw up to two wounded specialists")
		if flags.has("retreat") and not flags.has("reengage") and clock >= float(flags.retreat) + 8.0:
			flags.reengage = clock
			metrics["retreat_survivors_at_reengage"] = retreaters.filter(_alive).size()
			_issue(retreaters, center + Vector2(300.0, 0.0), true, "specialists reengage after eight seconds")


func _issue(group: Array[UnitBase], destination: Vector2, attack: bool, reason: String) -> void:
	var valid: Array[UnitBase] = []
	for unit: UnitBase in group:
		if _alive(unit):
			valid.append(unit)
	if valid.is_empty():
		return
	var orders: Array[Dictionary] = PLANNER.plan(game_map, valid, game_map.world_to_tile(destination), _group(valid[0].player_owner), valid[0].player_owner)
	for order: Dictionary in orders:
		var unit: UnitBase = order.unit
		var route: PackedVector2Array = order.path
		if attack:
			unit.command_attack_move_path(route) if not route.is_empty() else unit.command_attack_move(order.destination)
		else:
			unit.command_move_path(route) if not route.is_empty() else unit.command_move(order.destination)
		tracked[unit.get_instance_id()]["command_at"] = clock
		tracked[unit.get_instance_id()]["command_position"] = unit.global_position
	commands.append({"at": clock, "owner": valid[0].player_owner, "units": valid.size(), "planned_orders": orders.size(), "attack_move": attack, "destination": [destination.x, destination.y], "reason": reason})


func _track_tick() -> void:
	for unit: UnitBase in units:
		if not _alive(unit):
			continue
		var entry: Dictionary = tracked[unit.get_instance_id()]
		var moved: float = unit.global_position.distance_to(entry.last)
		entry.distance += moved
		var should_move: bool = unit.current_state == UnitBase.State.MOVING
		if unit.current_state == UnitBase.State.ATTACKING and is_instance_valid(unit.attack_target):
			should_move = unit.global_position.distance_to(unit.attack_target.global_position) > unit.attack_range + 8.0
		if should_move and moved < unit.speed * STEP * 0.05:
			entry.stall += STEP
			if float(entry.stall) > 1.0:
				metrics.navigation_stall_unit_seconds += STEP
		else:
			entry.stall = 0.0
		var target: int = unit.attack_target.get_instance_id() if is_instance_valid(unit.attack_target) else 0
		if target != 0 and target != int(entry.target):
			metrics.target_changes += 1
		entry.target = target
		if float(entry.command_at) >= 0.0 and (unit.global_position.distance_to(entry.command_position) > 0.1 or unit.current_state == UnitBase.State.ATTACKING):
			metrics.order_response_seconds.append(clock - float(entry.command_at) + STEP)
			entry.command_at = -1.0
		entry.last = unit.global_position


func _overlap() -> void:
	for i: int in units.size():
		var a: UnitBase = units[i]
		if not _alive(a):
			continue
		for j: int in range(i + 1, units.size()):
			var b: UnitBase = units[j]
			if _alive(b) and a.player_owner == b.player_owner and a.global_position.distance_to(b.global_position) < float(UnitBase.UNIT_SIZES[a.unit_type] + UnitBase.UNIT_SIZES[b.unit_type]) * 0.5:
				metrics.severe_friendly_overlap_pair_seconds += 0.5


func _hit(attacker: UnitBase, defender: UnitBase, amount: float, bonus: float) -> void:
	if clock < 0.0 or amount <= 0.0:
		return
	if float(metrics.first_hit) < 0.0:
		metrics.first_hit = clock
	if float(metrics.last_hit) >= 0.0:
		metrics.largest_hit_gap = maxf(float(metrics.largest_hit_gap), clock - float(metrics.last_hit))
	metrics.last_hit = clock
	metrics.damage[attacker.player_owner] += amount
	metrics.hits[attacker.player_owner] += 1
	metrics.counter_hits[attacker.player_owner] += 1 if bonus > 1.0 else 0
	var role: String = str(attacker.unit_type)
	metrics.role_damage[attacker.player_owner][role] = float(metrics.role_damage[attacker.player_owner].get(role, 0.0)) + amount
	events.append({"at": clock, "owner": attacker.player_owner, "role": attacker.unit_type, "target_role": defender.unit_type, "damage": amount, "counter": bonus})


func _death(unit: UnitBase) -> void:
	metrics.kills[1 - unit.player_owner] += 1


func _advance_attacks() -> void:
	for child: Node in game_map.get_node("UnitsContainer").get_children():
		if child.has_method("advance_committed_hit"):
			child.call("advance_committed_hit")
			child.free()
		elif child.has_method("advance_projectile"):
			child.set_process(false)
			child.call("advance_projectile", STEP)
			if bool(child.get("finished")):
				child.free()


func _alive(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD


func _group(owner: int, role: int = -1) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for unit: UnitBase in units:
		if _alive(unit) and unit.player_owner == owner and (role < 0 or unit.unit_type == role):
			result.append(unit)
	return result


func _centroid(group: Array[UnitBase]) -> Vector2:
	var result: Vector2 = Vector2.ZERO
	for unit: UnitBase in group:
		result += unit.global_position
	return result / maxf(1.0, group.size())


func _alive_counts() -> Array[int]:
	return [_group(0).size(), _group(1).size()]


func _hp_totals() -> Array[float]:
	var result: Array[float] = [0.0, 0.0]
	for unit: UnitBase in units:
		if _alive(unit):
			result[unit.player_owner] += unit.hp
	return result


func _sample() -> Dictionary:
	var state: Array[Dictionary] = []
	for unit: UnitBase in units:
		if _alive(unit):
			state.append({"id": unit.get_instance_id(), "owner": unit.player_owner, "role": unit.unit_type, "hp": unit.hp, "max_hp": unit.max_hp, "position": [unit.global_position.x, unit.global_position.y], "state": unit.current_state, "attack_move": unit.attack_move})
	return {"at": clock, "units": state}


func _unit_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: UnitBase in units:
		if not _alive(unit):
			continue
		var enemies: Array[Dictionary] = []
		for enemy: UnitBase in _group(1 - unit.player_owner):
			enemies.append({"id": enemy.get_instance_id(), "role": enemy.unit_type, "distance": unit.global_position.distance_to(enemy.global_position), "currently_visible": game_map.is_entity_visible_to_player(enemy, unit.player_owner), "ignored": unit._is_auto_target_temporarily_ignored(enemy)})
		result.append({"id": unit.get_instance_id(), "owner": unit.player_owner, "role": unit.unit_type, "hp": unit.hp, "state": unit.current_state, "position": [unit.global_position.x, unit.global_position.y], "move_target": [unit.move_target.x, unit.move_target.y], "stance": unit.stance, "attack_move": unit.attack_move, "force_move": unit.get("_force_move_active"), "forced_attack": unit.get("_forced_attack"), "target": unit.attack_target.get_instance_id() if is_instance_valid(unit.attack_target) else 0, "path_size": unit.path.size(), "path_index": unit.path_index, "navigation_active": unit.get("_navigation_active"), "failed_repaths": unit.get("_navigation_failed_repaths"), "stall_repaths": unit.get("_navigation_stall_repaths"), "attack_range": unit.attack_range, "vision_radius": unit.vision_radius, "enemies": enemies})
	return result


func _disable(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_disable(child)


func _capture() -> void:
	var camera: Camera2D = game_map.get_node("Camera2D")
	camera.position = center + (Vector2(0.0, -190.0) if clock < 12.0 else Vector2(220.0, 0.0))
	camera.zoom = Vector2.ONE * (0.55 if clock < 12.0 else 1.25)
	camera.reset_smoothing()
	camera.force_update_scroll()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_directory)
	get_viewport().get_texture().get_image().save_png(capture_directory.path_join("%s-%02d.png" % [plan, int(clock)]))


func _hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in ["scripts/main/main.gd", "scripts/ai/ai_controller.gd", "scripts/data/skirmish_data.gd", "scripts/data/unit_data.gd", "scripts/data/building_data.gd", "scripts/units/unit_base.gd", "scripts/units/villager.gd", "scripts/map/map_generator.gd", "scripts/map/game_map.gd", "scripts/map/pathfinding.gd", "scripts/main/group_order_planner.gd", "scripts/units/combat.gd", "scripts/units/auto_targeting.gd", "scripts/buildings/building_base.gd", "scripts/managers/game_manager.gd", "scripts/managers/resource_manager.gd", "scripts/managers/fog_manager.gd", "scripts/map/map_data.gd", "scripts/map/resource_node.gd", "scripts/buildings/production_queue.gd", "tools/fixtures/tactical_paid_opening.gd", "tools/probe_paid_tactical_plans.gd"]:
		if FileAccess.file_exists("res://" + path):
			result[path] = (load("res://" + path) as Script).get_source_code().sha256_text()
	_add_cached_script_hashes("res://scripts", result)
	return result


func _add_cached_script_hashes(folder: String, result: Dictionary) -> void:
	# Bind every loaded runtime dependency, including UI/autoloads and scripts
	# loaded lazily during the paid opening or combat. Read the cached source.
	for filename: String in DirAccess.get_files_at(folder):
		var path: String = folder.path_join(filename)
		if filename.ends_with(".gd") and ResourceLoader.has_cached(path):
			var script: Script = load(path) as Script
			if script != null:
				result[path.trim_prefix("res://")] = script.get_source_code().sha256_text()
	for dirname: String in DirAccess.get_directories_at(folder):
		_add_cached_script_hashes(folder.path_join(dirname), result)


func _finish() -> void:
	metrics["runtime_source_hashes"] = _hashes()
	metrics["failures"] = failures
	metrics["method"] = "Ordinary paid 30-pop opening then disclosed relocation of purchased armies; frozen economy/AI, fixed 60Hz real unit navigation/combat. Group order counts are not human APM; no rendering/performance claim."
	DirAccess.make_dir_recursive_absolute(result_path.get_base_dir())
	var file: FileAccess = FileAccess.open(result_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics, "\t"))
	print("[PAID_TACTICAL_COMPLETE] ", result_path, " ", failures)
	main.free()
	get_tree().quit(0 if failures.is_empty() else 1)
