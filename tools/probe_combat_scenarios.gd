extends Node
## Reproducible tactical fixtures using the real generated GameMap, A*, formations,
## visibility, UnitBase state machine, attack windups and projectile resolution.
## Armies are free scenario fixtures: this is not an economy or human-skill test.
## Run with -- --seed=101 --map=0 --scenario=all --policy=all --output=/tmp/battles.json.

const GAME_MAP: PackedScene = preload("res://scenes/map/game_map.tscn")
const PLANNER: Script = preload("res://scripts/main/group_order_planner.gd")
const UNIT_SCENES: Dictionary = {
	UnitData.UnitType.INFANTRY: preload("res://scenes/units/infantry.tscn"),
	UnitData.UnitType.ARCHER: preload("res://scenes/units/archer.tscn"),
	UnitData.UnitType.CAVALRY: preload("res://scenes/units/cavalry.tscn"),
}
const SCENARIOS: Array[String] = ["infantry_clash", "cavalry_flank", "retreat_reengage", "crossing_reinforcements"]
const STEP: float = 1.0 / 60.0
const LIMIT: float = 90.0
var _map: Node2D
var _units: Array[UnitBase] = []
var _groups: Dictionary = {}
var _tracking: Dictionary = {}
var _metrics: Dictionary = {}
var _clock: float = 0.0
var _scenario: String = ""
var _policy: String = ""
var _center: Vector2
var _upper_crossing: Vector2
var _lower_crossing: Vector2
var _scheduled: Dictionary = {}
var _tick_costs: Array[float] = []
var _commands: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _render: bool = false
var _capture_directory: String = ""
var _capture_seconds: Array[int] = [2, 5, 8, 12, 20]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var options: Dictionary = {"seed": "101", "map": "0", "scenario": "all", "policy": "all", "output": ""}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
			options[parts[0]] = parts[1]
	_render = str(options.get("render", "0")) == "1"
	_capture_directory = str(options.get("capture", ""))
	AudioManager.set_all_enabled(false)
	GameManager.set_process(false)
	# Suppress presentation-only VFX during CPU measurements. Actual unit sprite
	# animation still runs; rendering and full-game/device FPS are not measured.
	if not _render:
		get_tree().current_scene = null
	var results: Array[Dictionary] = []
	for scenario: String in SCENARIOS:
		if str(options["scenario"]) != "all" and str(options["scenario"]) != scenario:
			continue
		for policy: String in ["automatic", "deliberate"]:
			if str(options["policy"]) != "all" and str(options["policy"]) != policy:
				continue
			results.append(await _battle(int(options["seed"]), int(options["map"]), scenario, policy))
	var report: Dictionary = {
		"scenario_version": 2,
		"unit_base_sha256": FileAccess.get_sha256("res://scripts/units/unit_base.gd"),
		"probe_sha256": FileAccess.get_sha256("res://tools/probe_combat_scenarios.gd"),
		"method": "Fixed 60 Hz real generated maps, live-source visibility for both owners, real unit/formation/navigation/combat code. Free tactical armies; no economy or human-skill inference. All units release before melee resolves; released arrows continue. CPU excludes rendering and telemetry sampling.",
		"results": results,
	}
	var destination: String = str(options["output"])
	if not destination.is_empty():
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write combat probe: " + destination)
			get_tree().quit(1)
			return
		file.store_string(JSON.stringify(report, "\t"))
	print("[COMBAT_PROBE_COMPLETE] ", destination)
	get_tree().quit(0 if not results.is_empty() else 1)


func _battle(seed_value: int, archetype: int, scenario: String, policy: String) -> Dictionary:
	seed(seed_value)
	GameManager.initialize_game(2)
	GameManager.selected_map_seed = seed_value
	GameManager.set("selected_map_archetype", archetype)
	GameManager.current_state = GameManager.GameState.PLAYING
	_scenario = scenario
	_policy = policy
	_clock = 0.0
	_units.clear()
	_groups.clear()
	_tracking.clear()
	_scheduled.clear()
	_tick_costs.clear()
	_commands.clear()
	_samples.clear()
	_metrics = {
		"seed": seed_value, "map": archetype, "scenario": scenario, "policy": policy,
		"first_hit_seconds": -1.0, "last_hit_seconds": -1.0,
		"damage": [0.0, 0.0], "kills": [0, 0], "hits": [0, 0], "hits_by_role": [{}, {}],
		"alive_unit_seconds": 0.0, "idle_near_enemy_seconds": 0.0,
		"navigation_stall_unit_seconds": 0.0, "navigation_failures": 0,
		"target_changes": 0, "friendly_overlap_pair_seconds": 0.0,
		"enemy_overlap_pair_seconds": 0.0, "minimum_friendly_spacing": 99999.0,
		"command_cpu_ms": 0.0, "command_response_ms": [], "command_unanswered": 0,
		"largest_hit_gap_seconds": 0.0,
	}
	_map = GAME_MAP.instantiate() as Node2D
	add_child(_map)
	await get_tree().process_frame
	_disable_processes(_map)
	# Use the same real-map live-source rule as the non-local simulation owner.
	# This avoids privileging one faction through stale manually stepped fog.
	(_map.get_node("FogOfWar") as FogManager).owning_player = -1
	_center = _map.tile_to_world(Vector2i(36, 36))
	var routes: Array[Dictionary] = _map.map_generator.get_tactical_routes()
	_upper_crossing = _map.tile_to_world(routes[1]["waypoints"][1])
	_lower_crossing = _map.tile_to_world(routes[2]["waypoints"][1])
	_metrics["upper_crossing_tile"] = [routes[1]["waypoints"][1].x, routes[1]["waypoints"][1].y]
	_metrics["lower_crossing_tile"] = [routes[2]["waypoints"][1].x, routes[2]["waypoints"][1].y]
	if _render:
		_map.get_node("FogLayer").hide()
		var camera: Camera2D = _map.get_node("Camera2D") as Camera2D
		camera.position = _center
		camera.zoom = Vector2(1.1, 1.1)
	_setup_armies()
	_initial_orders()
	var settled: float = 0.0
	var end_reason: String = "time_limit"
	var last_sample_tick: int = -1
	for tick: int in int(LIMIT / STEP):
		_clock = float(tick) * STEP
		_run_schedule()
		var started: int = Time.get_ticks_usec()
		# Interleave owners and alternate who updates first; committed melee
		# resolution is simultaneous regardless of faction node order.
		for offset: int in _units.size():
			var index: int = offset if tick % 2 == 0 else _units.size() - 1 - offset
			var unit: UnitBase = _units[index]
			if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
				unit._process(STEP)
		_advance_attacks()
		_tick_costs.append(float(Time.get_ticks_usec() - started) / 1000.0)
		_track_tick()
		if tick % 30 == 0:
			_sample_overlap(0.5)
		if tick % 60 == 0:
			_samples.append(_sample_state())
			last_sample_tick = tick
		if _render:
			await get_tree().process_frame
			if tick % 60 == 0 and _capture_seconds.has(int(_clock)) and not _capture_directory.is_empty():
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute(_capture_directory)
				get_viewport().get_texture().get_image().save_png(_capture_directory.path_join("%s-%s-%d.png" % [scenario, policy, int(_clock)]))
		elif tick % 60 == 0:
			# Drain deferred destruction with every simulation node disabled.
			await get_tree().process_frame
		var alive: Array[int] = _alive_counts()
		if (alive[0] == 0 or alive[1] == 0) and _reinforcements_finished():
			settled += STEP
			if settled >= 0.5:
				end_reason = "mutual_elimination" if alive[0] == 0 and alive[1] == 0 else "elimination"
				break
		elif _clock >= 35.0 and _clock - float(_metrics["last_hit_seconds"]) >= 8.0 and _all_survivors_idle():
			end_reason = "disengaged"
			break
	if last_sample_tick != roundi(_clock / STEP):
		_samples.append(_sample_state())
	_metrics["duration_seconds"] = snappedf(_clock + STEP, 0.001)
	_metrics["survivors"] = _alive_counts()
	_metrics["remaining_hp"] = _hp_totals()
	_metrics["winner"] = 0 if _alive_counts()[1] == 0 and _alive_counts()[0] > 0 else (1 if _alive_counts()[0] == 0 and _alive_counts()[1] > 0 else -1)
	_metrics["end_reason"] = end_reason
	_metrics["final_quiet_seconds"] = maxf(0.0, float(_metrics["duration_seconds"]) - float(_metrics["last_hit_seconds"]))
	_metrics["unit_update_cpu_ms_total"] = _tick_costs.reduce(func(total: float, value: float) -> float: return total + value, 0.0)
	_tick_costs.sort()
	_metrics["unit_update_cpu_ms_p50"] = _percentile(_tick_costs, 0.5)
	_metrics["unit_update_cpu_ms_p95"] = _percentile(_tick_costs, 0.95)
	_metrics["unit_update_cpu_ms_max"] = _tick_costs.back()
	_metrics["commands"] = _commands.duplicate(true)
	_metrics["intervention_orders"] = _commands.filter(func(order: Dictionary) -> bool: return bool(order["intervention"])).size()
	_metrics["intervention_orders_per_minute"] = float(_metrics["intervention_orders"]) * 60.0 / float(_metrics["duration_seconds"])
	var responses: Array[float] = []
	for value: float in _metrics["command_response_ms"]:
		responses.append(value)
	responses.sort()
	_metrics["command_response_p95_ms"] = _percentile(responses, 0.95) if not responses.is_empty() else -1.0
	_metrics["samples"] = _samples.duplicate(true)
	for entry: Dictionary in _tracking.values():
		if float(entry.get("command_at", -1.0)) >= 0.0:
			_metrics["command_unanswered"] += 1
	var result: Dictionary = _metrics.duplicate(true)
	var summary: Dictionary = result.duplicate(true)
	summary.erase("samples")
	summary.erase("commands")
	summary.erase("command_response_ms")
	print("[COMBAT_METRIC] ", JSON.stringify(summary))
	_map.free()
	await get_tree().process_frame
	return result


func _disable_processes(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_disable_processes(child)


func _setup_armies() -> void:
	if _scenario == "infantry_clash":
		_spawn_group("front0", 0, UnitData.UnitType.INFANTRY, 12, Vector2(-220.0, 0.0))
		_spawn_group("front1", 1, UnitData.UnitType.INFANTRY, 12, Vector2(220.0, 0.0))
	elif _scenario == "cavalry_flank":
		_spawn_group("front0", 0, UnitData.UnitType.INFANTRY, 4, Vector2(-180.0, 0.0))
		_spawn_group("mobile0", 0, UnitData.UnitType.CAVALRY, 6, Vector2(-280.0, 0.0))
		_spawn_group("front1", 1, UnitData.UnitType.INFANTRY, 6, Vector2(100.0, 0.0))
		_spawn_group("bow1", 1, UnitData.UnitType.ARCHER, 8, Vector2(180.0, 0.0))
	elif _scenario == "retreat_reengage":
		_spawn_group("front0", 0, UnitData.UnitType.INFANTRY, 6, Vector2(-150.0, 0.0))
		_spawn_group("bow0", 0, UnitData.UnitType.ARCHER, 8, Vector2(-250.0, 0.0))
		_spawn_group("front1", 1, UnitData.UnitType.INFANTRY, 4, Vector2(210.0, 0.0))
		_spawn_group("mobile1", 1, UnitData.UnitType.CAVALRY, 6, Vector2(290.0, 0.0))
	else:
		for owner: int in 2:
			var side: float = -1.0 if owner == 0 else 1.0
			_spawn_group("front%d" % owner, owner, UnitData.UnitType.INFANTRY, 8, Vector2(side * 250.0, 0.0))
			_spawn_group("bow%d" % owner, owner, UnitData.UnitType.ARCHER, 4, Vector2(side * 340.0, 0.0))
			_spawn_group("reserve%d" % owner, owner, UnitData.UnitType.CAVALRY, 4, _upper_crossing - _center + Vector2(side * 340.0, 0.0))
			_spawn_group("late%d" % owner, owner, UnitData.UnitType.INFANTRY, 4, _lower_crossing - _center + Vector2(side * 380.0, 0.0))
	# Stable owner-interleaved process order, with spawn order within each side.
	var ordered: Array[UnitBase] = []
	var sides: Array = [_owned(0), _owned(1)]
	for index: int in maxi(sides[0].size(), sides[1].size()):
		for owner: int in 2:
			if index < sides[owner].size():
				ordered.append(sides[owner][index])
	_units = ordered
	_metrics["initial_units"] = _alive_counts()
	_metrics["army_resource_cost"] = [0, 0]
	for unit: UnitBase in _units:
		var costs: Dictionary = UnitData.get_unit_stats(unit.unit_type).get("cost", {})
		for value: Variant in costs.values():
			_metrics["army_resource_cost"][unit.player_owner] += int(value)


func _spawn_group(label: String, owner: int, role: int, count: int, offset: Vector2) -> void:
	var group: Array[UnitBase] = []
	for index: int in count:
		var desired: Vector2 = _center + offset + Vector2(float(index / 4) * 42.0 * (-1.0 if owner == 0 else 1.0), float(index % 4) * 40.0 - 60.0)
		var tile: Vector2i = _map.world_to_tile(desired)
		var candidates: Array[Vector2i] = _map.pathfinding.get_walkable_tiles_near(tile, 10, 300)
		var position: Vector2 = Vector2.INF
		var best: float = INF
		for candidate: Vector2i in candidates:
			var world: Vector2 = _map.tile_to_world(candidate)
			var acceptable: bool = true
			for other: UnitBase in _units:
				if other.global_position.distance_to(world) < 32.0:
					acceptable = false
					break
			if acceptable and world.distance_squared_to(desired) < best and not _map.pathfinding.get_tile_path(candidate, Vector2i(36, 36)).is_empty():
				position = world
				best = world.distance_squared_to(desired)
		assert(position.is_finite(), "Scenario could not find a connected spawn slot")
		var unit: UnitBase = UNIT_SCENES[role].instantiate() as UnitBase
		unit.player_owner = owner
		unit.position = position
		unit.set_process(false)
		_map.get_node("UnitsContainer").add_child(unit)
		# Godot enables script processing while entering the tree; disable after
		# _ready as well so yielded cleanup frames never double-step the fixture.
		unit.set_process(false)
		unit.attack_landed.connect(_on_hit)
		unit.unit_died.connect(_on_death)
		unit.navigation_failed.connect(func(_unit: UnitBase, _target: Vector2) -> void: _metrics["navigation_failures"] += 1)
		_tracking[unit.get_instance_id()] = {"last": position, "stall": 0.0, "target": 0, "command_at": -1.0}
		_units.append(unit)
		group.append(unit)
	_groups[label] = group


func _initial_orders() -> void:
	for owner: int in 2:
		if _scenario == "cavalry_flank" and owner == 1:
			# A known defending infantry screen covering its archers. Both
			# policies face the same stationary defense, not a moving goalpost.
			for unit: UnitBase in _owned(1):
				unit.stance = UnitBase.Stance.STAND_GROUND
			continue
		var initial: Array[UnitBase] = []
		for label: String in _groups:
			if label.ends_with(str(owner)) and not label.begins_with("reserve") and not label.begins_with("late"):
				initial.append_array(_groups[label])
		_issue(initial, _center + Vector2(220.0 if owner == 0 else -220.0, 0.0), true, "initial advance", false)
	if _policy == "deliberate" and _scenario == "cavalry_flank":
		_issue(_group("mobile0"), _center + Vector2(200.0, -150.0), false, "ride around the known infantry screen", true)


func _run_schedule() -> void:
	if _scenario == "crossing_reinforcements":
		for wave: int in 2:
			var time: float = 12.0 + float(wave) * 12.0
			if _once("wave%d" % wave, time):
				for owner: int in 2:
					var label: String = ("reserve" if wave == 0 else "late") + str(owner)
					_issue(_group(label), _center, true, "scheduled reinforcements", false)
	if _policy != "deliberate":
		return
	if _scenario == "cavalry_flank":
		if _once("flank_engage", 7.0):
			_issue(_group("mobile0"), _group_center("bow1", _center + Vector2(180.0, 0.0)), true, "flank engages the archers", true)
		if _once("save_horses", 14.0):
			_withdraw(_group("mobile0"), 2, _center + Vector2(-260.0, -180.0), "withdraw two wounded horsemen")
	elif _scenario == "retreat_reengage":
		if _once("retreat", 4.0):
			_issue(_group("bow0"), _center + Vector2(-330.0, 30.0), false, "withdraw archers behind warriors", true)
		if _once("reengage", 14.0):
			_issue(_group("bow0"), _center + Vector2(120.0, 0.0), true, "archers reengage", true)
	elif _scenario == "crossing_reinforcements":
		if _once("upper_flank", 12.0):
			_issue(_group("reserve0"), _upper_crossing + Vector2(180.0, 0.0), false, "reinforcements cross at the upper gate", true)
		if _once("upper_engage", 19.0):
			_issue(_group("reserve0"), _group_center("bow1", _center), true, "flank joins the fight", true)
	else:
		if _once("save_warriors", 7.0):
			_withdraw(_owned(0), 3, _center + Vector2(-280.0, 0.0), "withdraw three wounded warriors")
		if _once("reengage", 14.0):
			_issue(_group("withdrawn"), _center + Vector2(160.0, 0.0), true, "withdrawn warriors reengage", true)
	# One later decision, not repeated command spam. This can cost damage while
	# protecting veterans; success is an observation, not a fixture assertion.
	if _once("late_withdraw", 28.0):
		_withdraw(_owned(0), 2, _center + Vector2(-300.0, -100.0), "preserve two wounded survivors")
	if _once("late_reengage", 35.0):
		_issue(_group("withdrawn"), _center, true, "return withdrawn survivors to the objective", true)


func _withdraw(units: Array[UnitBase], count: int, destination: Vector2, reason: String) -> void:
	var wounded: Array[UnitBase] = []
	for unit: UnitBase in units:
		if unit.hp / unit.max_hp < 0.65:
			wounded.append(unit)
	_groups["withdrawn"] = _weakest(wounded, count)
	_issue(_group("withdrawn"), destination, false, reason, true)


func _once(label: String, at: float) -> bool:
	if _clock + 0.0001 < at or _scheduled.has(label):
		return false
	_scheduled[label] = true
	return true


func _issue(units: Array[UnitBase], destination: Vector2, attack: bool, reason: String, intervention: bool) -> void:
	var valid: Array[UnitBase] = []
	for unit: UnitBase in units:
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
			valid.append(unit)
	if valid.is_empty():
		return
	var start: int = Time.get_ticks_usec()
	var planned: Array[Dictionary] = PLANNER.plan(_map, valid, _map.world_to_tile(destination), _owned(valid[0].player_owner), valid[0].player_owner)
	for order: Dictionary in planned:
		var unit: UnitBase = order["unit"] as UnitBase
		var route: PackedVector2Array = order["path"] as PackedVector2Array
		if attack:
			if route.is_empty():
				unit.command_attack_move(order["destination"])
			else:
				unit.command_attack_move_path(route)
		else:
			if route.is_empty():
				unit.command_move(order["destination"])
			else:
				unit.command_move_path(route)
		var entry: Dictionary = _tracking[unit.get_instance_id()]
		entry["command_at"] = _clock
		entry["command_position"] = unit.global_position
	_metrics["command_cpu_ms"] += float(Time.get_ticks_usec() - start) / 1000.0
	_commands.append({"at": _clock, "owner": valid[0].player_owner, "units": valid.size(), "attack_move": attack, "reason": reason, "intervention": intervention})


func _advance_attacks() -> void:
	for child: Node in _map.get_node("UnitsContainer").get_children():
		if child.has_method("advance_committed_hit"):
			child.call("advance_committed_hit")
			child.free()
		elif child.has_method("advance_projectile"):
			child.set_process(false)
			child.call("advance_projectile", STEP)
			if bool(child.get("finished")):
				child.free()


func _track_tick() -> void:
	for unit: UnitBase in _units:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		var entry: Dictionary = _tracking[unit.get_instance_id()]
		var distance: float = unit.global_position.distance_to(entry["last"] as Vector2)
		_metrics["alive_unit_seconds"] += STEP
		var should_move: bool = unit.current_state == UnitBase.State.MOVING
		if unit.current_state == UnitBase.State.ATTACKING and is_instance_valid(unit.attack_target):
			should_move = unit.global_position.distance_to(unit.attack_target.global_position) > unit.attack_range + 8.0
		if should_move and distance < unit.speed * STEP * 0.05:
			entry["stall"] = float(entry["stall"]) + STEP
			if float(entry["stall"]) > 1.0:
				_metrics["navigation_stall_unit_seconds"] += STEP
		else:
			entry["stall"] = 0.0
		if unit.current_state == UnitBase.State.IDLE and _enemy_near(unit, 220.0):
			_metrics["idle_near_enemy_seconds"] += STEP
		var target_id: int = unit.attack_target.get_instance_id() if is_instance_valid(unit.attack_target) else 0
		if target_id != int(entry["target"]) and target_id != 0:
			_metrics["target_changes"] += 1
		entry["target"] = target_id
		if float(entry["command_at"]) >= 0.0 and (unit.global_position.distance_to(entry["command_position"] as Vector2) > 0.1 or unit.current_state == UnitBase.State.ATTACKING):
			_metrics["command_response_ms"].append((_clock - float(entry["command_at"]) + STEP) * 1000.0)
			entry["command_at"] = -1.0
		entry["last"] = unit.global_position


func _sample_overlap(interval: float) -> void:
	for i: int in _units.size():
		var first: UnitBase = _units[i]
		if not is_instance_valid(first) or first.current_state == UnitBase.State.DEAD:
			continue
		for j: int in range(i + 1, _units.size()):
			var second: UnitBase = _units[j]
			if not is_instance_valid(second) or second.current_state == UnitBase.State.DEAD:
				continue
			var distance: float = first.global_position.distance_to(second.global_position)
			if first.player_owner == second.player_owner:
				_metrics["minimum_friendly_spacing"] = minf(_metrics["minimum_friendly_spacing"], distance)
			# Severe center overlap, not ordinary close melee contact.
			if distance < (float(UnitBase.UNIT_SIZES[first.unit_type]) + float(UnitBase.UNIT_SIZES[second.unit_type])) * 0.5:
				_metrics["friendly_overlap_pair_seconds" if first.player_owner == second.player_owner else "enemy_overlap_pair_seconds"] += interval


func _on_hit(attacker: UnitBase, _defender: UnitBase, hp_loss: float, _counter: float) -> void:
	if float(_metrics["first_hit_seconds"]) < 0.0:
		_metrics["first_hit_seconds"] = _clock
	if float(_metrics["last_hit_seconds"]) >= 0.0:
		_metrics["largest_hit_gap_seconds"] = maxf(float(_metrics["largest_hit_gap_seconds"]), _clock - float(_metrics["last_hit_seconds"]))
	_metrics["last_hit_seconds"] = _clock
	_metrics["damage"][attacker.player_owner] += hp_loss
	_metrics["hits"][attacker.player_owner] += 1
	var roles: Dictionary = _metrics["hits_by_role"][attacker.player_owner]
	var role: String = UnitData.get_unit_name(attacker.unit_type)
	roles[role] = int(roles.get(role, 0)) + 1


func _on_death(unit: UnitBase) -> void:
	_metrics["kills"][1 - unit.player_owner] += 1


func _owned(owner: int) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for unit: UnitBase in _units:
		if is_instance_valid(unit) and unit.player_owner == owner and unit.current_state != UnitBase.State.DEAD:
			result.append(unit)
	return result


func _group(label: String) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for unit: UnitBase in _groups.get(label, []):
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
			result.append(unit)
	return result


func _weakest(units: Array[UnitBase], count: int) -> Array[UnitBase]:
	var sorted: Array[UnitBase] = units.duplicate()
	sorted.sort_custom(func(a: UnitBase, b: UnitBase) -> bool: return a.hp < b.hp)
	sorted.resize(mini(count, sorted.size()))
	return sorted


func _group_center(label: String, fallback: Vector2) -> Vector2:
	var units: Array[UnitBase] = []
	for unit: UnitBase in _group(label):
		if unit.player_owner == 0 or _map.is_entity_visible_to_player(unit, 0):
			units.append(unit)
	var position: Vector2 = Vector2.ZERO
	for unit: UnitBase in units:
		position += unit.global_position
	return fallback if units.is_empty() else position / float(units.size())


func _alive_counts() -> Array[int]:
	return [_owned(0).size(), _owned(1).size()]


func _hp_totals() -> Array[float]:
	var values: Array[float] = [0.0, 0.0]
	for unit: UnitBase in _units:
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
			values[unit.player_owner] += unit.hp
	return values


func _enemy_near(unit: UnitBase, radius: float) -> bool:
	for other: UnitBase in _units:
		if is_instance_valid(other) and other.player_owner != unit.player_owner and other.current_state != UnitBase.State.DEAD and other.global_position.distance_to(unit.global_position) <= radius:
			return true
	return false


func _sample_state() -> Dictionary:
	var units: Array[Dictionary] = []
	for unit: UnitBase in _units:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		units.append({"owner": unit.player_owner, "type": unit.unit_type, "hp": unit.hp, "state": unit.current_state, "x": snappedf(unit.position.x - _center.x, 0.1), "y": snappedf(unit.position.y - _center.y, 0.1)})
	return {"at": snappedf(_clock, 0.01), "alive": _alive_counts(), "hp": _hp_totals(), "units": units}


func _reinforcements_finished() -> bool:
	return _scenario != "crossing_reinforcements" or _clock >= 24.0


func _all_survivors_idle() -> bool:
	for unit: UnitBase in _units:
		if is_instance_valid(unit) and unit.current_state not in [UnitBase.State.DEAD, UnitBase.State.IDLE]:
			return false
	return true


func _percentile(values: Array[float], fraction: float) -> float:
	return values[mini(values.size() - 1, floori(float(values.size() - 1) * fraction))]
