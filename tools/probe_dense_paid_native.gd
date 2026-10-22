extends Node
## Paid native desktop diagnostic. No renderer/gameplay source modifications.
const POLICY: Script = preload("res://tools/dense_paid_policy.gd")
const PLANNER: Script = preload("res://scripts/main/group_order_planner.gd")
const ROSTER: Dictionary = {UnitData.UnitType.INFANTRY: 6, UnitData.UnitType.ARCHER: 4, UnitData.UnitType.CAVALRY: 2}
var main: Node
var human: AIController
var game_map: Node2D
var center: Vector2
var units: Array[UnitBase] = []
var seen: Dictionary = {}
var queues_seen: Dictionary = {}
var report: Dictionary = {"failures": [], "commands": [], "created": [], "queues": [], "bank_ledger": [], "damage_events": [], "presence": [], "focus_events": []}
var banks: Array[Dictionary] = []
var output_directory: String = ""
var phase: String = "boot"
var last_presence_us: int = 0
var first_hit_us: int = 0
var last_hit_us: int = 0
var sample_started_us: int = 0
var sample_ended_us: int = 0
var previous_frame_us: int = 0
var active_count: int = 0
var on_screen_count: int = 0
var frame_rows: Array = []
var measure: bool = false
var width: int = 844
var height: int = 390
var duration: float = 30.0
var focus_only: bool = false
var nav_failures: int = 0
var observer_total_us: int = 0
var observer_peak_us: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_directory = argument.trim_prefix("--output=")
		elif argument.begins_with("--width="): width = int(argument.trim_prefix("--width="))
		elif argument.begins_with("--height="): height = int(argument.trim_prefix("--height="))
		elif argument.begins_with("--duration="): duration = float(argument.trim_prefix("--duration="))
		elif argument == "--focus-only": focus_only = true
	if output_directory.is_empty():
		get_tree().quit(1)
		return
	if focus_only:
		await _check_focus_only()
		return
	if DisplayServer.get_name() == "headless" or "--fixed-fps" in OS.get_cmdline_args():
		report.failures.append("Requires native real-time rendering without --fixed-fps")
		_finish()
		return
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.ui_scale = 1.0
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_population_limit = 30
	GameManager.selected_difficulty = AIController.Difficulty.MEDIUM
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	get_window().size = Vector2i(width, height)
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	get_window().grab_focus()
	get_window().focus_exited.connect(func(): report.focus_events.append({"at_us": Time.get_ticks_usec(), "phase": phase, "focused": false}))
	get_window().focus_entered.connect(func(): report.focus_events.append({"at_us": Time.get_ticks_usec(), "phase": phase, "focused": true}))
	var boot_focus_deadline: int = Time.get_ticks_msec() + 3000
	while not get_window().has_focus() and Time.get_ticks_msec() < boot_focus_deadline:
		await get_tree().process_frame
	if not get_window().has_focus():
		report.failures.append("Native window unavailable at boot; paid warmup not started")
		_finish()
		return
	main = load("res://scenes/main/main.tscn").instantiate()
	main.get_node("AIController").set_script(POLICY)
	main.get_node("AIController").set("roster", ROSTER.duplicate())
	add_child(main)
	for _frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	if main.get("_building_placement") == null:
		report.failures.append("Main initialization timeout")
		_finish()
		return
	game_map = main.game_map
	center = game_map.tile_to_world(Vector2i(36, 36))
	game_map.note_camera_interaction()
	game_map.set("_user_zoom_override", true)
	game_map.camera.position = center
	game_map.camera.zoom = Vector2.ONE * 0.952
	game_map.camera.reset_smoothing()
	human = POLICY.new() as AIController
	human.set("roster", ROSTER.duplicate())
	human.player_id = 0
	human.enemy_id = 1
	human.difficulty = AIController.Difficulty.MEDIUM
	human.game_map = game_map
	human.map_generator = game_map.map_generator
	human.pathfinding = game_map.pathfinding
	main.add_child(human)
	human.ai_wants_to_build.connect(func(kind: int, tile: Vector2i, _rebuild: bool): main._on_placement_confirmed(kind, game_map.tile_to_world(tile)))
	human.ai_wants_to_train.connect(main._on_train_unit_requested)
	human.ai_wants_to_age_up.connect(main._on_age_up_requested)
	banks = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	report.initial_banks = banks.duplicate(true)
	ResourceManager.resources_changed.connect(_bank)
	_register()
	var spawn: Vector2i = game_map.map_generator.spawn_positions[0]
	human.start_ai(spawn, game_map.tile_to_world(spawn))
	report.scope = "Native desktop default renderer/VSync at phone-sized viewport; paid fixed roster policies, natural staging and live Main simulation/fog. 3x unsampled opening, 1x measured combat. No grants/spawns/teleports or modified stats; no physical-phone/Web/GPU/scanout claim. Audio muted. Ordinary worker economies and purchaser decision timers remain active."
	report.engine = Engine.get_version_info()
	report.environment = {"display": DisplayServer.get_name(), "render_method": RenderingServer.get_current_rendering_method(), "render_driver": RenderingServer.get_current_rendering_driver_name(), "render_device": RenderingServer.get_rendering_device().get_device_name() if RenderingServer.get_rendering_device() != null else "Compatibility", "vsync_mode": DisplayServer.window_get_vsync_mode(), "refresh_hz": DisplayServer.screen_get_refresh_rate(), "max_fps": Engine.max_fps, "physics_ticks": Engine.physics_ticks_per_second, "debug_build": OS.is_debug_build(), "screen_scale": DisplayServer.screen_get_scale(), "user_data_dir": OS.get_user_data_dir(), "window": [width, height], "viewport": _xy(get_viewport().get_visible_rect().size), "content_scale_factor": get_window().content_scale_factor, "zoom": 0.952, "camera": _xy(center), "audio_enabled": false, "fixed_fps": false, "runtime_diagnostics_persistence": true}
	report.roster_per_owner = ROSTER
	report.roster_cost_per_owner = {"food": 580, "wood": 360, "gold": 0}
	report.economic_bonus_active = main.balance_ai_economic_bonus_active
	report.terrain_sha256 = JSON.stringify(game_map.map_generator.grid).sha256_text()
	report.source_hashes = {}
	for source: String in ["scripts/main/main.gd", "scripts/units/unit_base.gd", "scripts/ai/ai_controller.gd", "scripts/map/game_map.gd", "scripts/map/tileset_builder.gd", "scripts/map/pathfinding.gd", "scripts/ui/hud.gd", "scripts/managers/fog_manager.gd", "tools/fixtures/tactical_paid_opening.gd", "tools/dense_paid_policy.gd", "tools/probe_dense_paid_native.gd"]:
		report.source_hashes[source] = FileAccess.get_file_as_string("res://" + source).sha256_text()
	phase = "paid_opening"
	while GameManager.game_time < 700.0 and GameManager.current_state == GameManager.GameState.PLAYING:
		_register()
		if _roster_ready(0) and _roster_ready(1): break
		await get_tree().create_timer(0.2).timeout
	if not _roster_ready(0) or not _roster_ready(1):
		report.failures.append("Paid roster incomplete at700s")
		_finish()
		return
	human.set("purchases_frozen", true)
	main.ai_controller.set("purchases_frozen", true)
	report.paid_ready_at = GameManager.game_time
	report.paid_banks = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	report.paid_opening_stats = main._stats.duplicate(true)
	report.ages = [GameManager.get_player_age(0), GameManager.get_player_age(1)]
	phase = "staging"
	for owner: int in 2:
		_issue(owner, center + Vector2(-352.0 if owner == 0 else 352.0, 0), false)
	var stage_deadline: float = GameManager.game_time + 90.0
	while GameManager.game_time < stage_deadline:
		if _staged(): break
		await get_tree().create_timer(0.2).timeout
	if not _staged():
		report.failures.append("Natural staging did not complete within90s")
		_finish()
		return
	if first_hit_us > 0:
		report.failures.append("Combat occurred before measured order")
		_finish()
		return
	Engine.time_scale = 1.0
	phase = "settle"
	get_window().grab_focus()
	for _frame: int in 120:
		if get_window().has_focus(): break
		await get_tree().process_frame
	if not get_window().has_focus():
		report.failures.append("Could not focus native window before measurement")
		_finish()
		return
	await _capture("before.png")
	await get_tree().create_timer(5.0, true, false, true).timeout
	report.sample_start_game_seconds = GameManager.game_time
	report.sample_start_units = _unit_snapshot()
	report.sample_start_workers = _worker_counts()
	report.focused_at_start = get_window().has_focus()
	if not report.focused_at_start:
		report.failures.append("Native window lost focus during settle; no sample taken")
		_finish()
		return
	phase = "measured"
	_refresh_presence()
	sample_started_us = Time.get_ticks_usec()
	previous_frame_us = 0
	measure = true
	RenderingServer.frame_post_draw.connect(_frame)
	# Prime the preceding completion so synchronous group planning is measured.
	await RenderingServer.frame_post_draw
	for unit: UnitBase in units:
		if _alive(unit): unit.stance = UnitBase.Stance.AGGRESSIVE
	for owner: int in 2:
		_issue(owner, center, true)
	await get_tree().create_timer(duration, true, false, true).timeout
	measure = false
	sample_ended_us = Time.get_ticks_usec()
	RenderingServer.frame_post_draw.disconnect(_frame)
	phase = "after"
	report.sample_end_game_seconds = GameManager.game_time
	report.sample_end_units = _unit_snapshot()
	await _capture("after.png")
	_finish()

func _process(_delta: float) -> void:
	if not measure: return
	var now: int = Time.get_ticks_usec()
	if now - last_presence_us >= 500000:
		last_presence_us = now
		_refresh_presence()

func _frame() -> void:
	if not measure: return
	var now: int = Time.get_ticks_usec()
	if previous_frame_us > 0:
		frame_rows.append([float(now - sample_started_us) / 1000000.0, float(now - previous_frame_us) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), on_screen_count, active_count, last_hit_us > 0 and now - last_hit_us <= 1000000])
	previous_frame_us = now

func _refresh_presence() -> void:
	var started: int = Time.get_ticks_usec()
	active_count = 0
	on_screen_count = 0
	var alive: Array[int] = [0, 0]
	var visible: Array[int] = [0, 0]
	var screen_rect: Rect2 = get_viewport().get_visible_rect()
	var projectiles: int = 0
	var unit_container: Node = game_map.get_node_or_null("UnitsContainer")
	if unit_container != null:
		for child: Node in unit_container.get_children():
			if child is Combat.RangedProjectile: projectiles += 1
	for unit: UnitBase in units:
		if not _alive(unit): continue
		alive[unit.player_owner] += 1
		if unit.current_state == UnitBase.State.ATTACKING: active_count += 1
		var screen: Vector2 = unit.get_global_transform_with_canvas().origin
		if unit.is_visible_in_tree() and screen_rect.has_point(screen):
			on_screen_count += 1
			visible[unit.player_owner] += 1
	report.presence.append({"at_us": started, "game_time": GameManager.game_time, "alive": alive, "visible_military": visible, "attacking": active_count, "projectiles": projectiles, "time_scale": Engine.time_scale, "viewport": _xy(get_viewport().get_visible_rect().size), "window": _xy(Vector2(get_window().size)), "content_scale_factor": get_window().content_scale_factor, "total_units": get_tree().get_nodes_in_group("units").size(), "buildings": get_tree().get_nodes_in_group("buildings").size(), "camera": _xy(game_map.camera.position), "zoom": _xy(game_map.camera.zoom)})
	var elapsed: int = Time.get_ticks_usec() - started
	observer_total_us += elapsed
	observer_peak_us = maxi(observer_peak_us, elapsed)

func _register() -> void:
	for owner: int in 2:
		for unit: UnitBase in main._player_units[owner]:
			if not is_instance_valid(unit) or seen.has(unit.get_instance_id()): continue
			seen[unit.get_instance_id()] = true
			if owner == 0: human.register_unit(unit)
			report.created.append({"at": GameManager.game_time, "owner": owner, "kind": unit.unit_type, "id": unit.get_instance_id()})
			if unit.unit_type in ROSTER:
				units.append(unit)
				unit.stance = UnitBase.Stance.STAND_GROUND
				unit.damage_received.connect(_damage)
				unit.navigation_failed.connect(func(_unit: UnitBase, _target: Vector2): nav_failures += 1)
		for building: BuildingBase in main._player_buildings[owner]:
			if not is_instance_valid(building): continue
			if owner == 0: human.register_building(building)
			var queue: ProductionQueue = building.get_production_queue()
			if queue == null or queues_seen.has(queue.get_instance_id()): continue
			queues_seen[queue.get_instance_id()] = true
			queue.unit_queued.connect(func(role: int): report.queues.append({"at": GameManager.game_time, "owner": owner, "role": role, "action": "queued"}))
			queue.unit_trained.connect(func(role: int): report.queues.append({"at": GameManager.game_time, "owner": owner, "role": role, "action": "trained"}))

func _roster_ready(owner: int) -> bool:
	var policy: AIController = human if owner == 0 else main.ai_controller
	for role: int in ROSTER:
		var count: int = 0
		for unit: UnitBase in units:
			if _alive(unit) and unit.player_owner == owner and unit.unit_type == role: count += 1
		if count != int(ROSTER[role]) or policy._count_queued_unit(role) > 0: return false
	return GameManager.get_player_age(owner) == 2

func _staged() -> bool:
	for unit: UnitBase in units:
		if not _alive(unit) or unit.current_state == UnitBase.State.MOVING: return false
		var goal: Vector2 = center + Vector2(-352.0 if unit.player_owner == 0 else 352.0, 0)
		if unit.global_position.distance_to(goal) > 150.0: return false
	return true

func _issue(owner: int, destination: Vector2, attack: bool) -> void:
	var group: Array[UnitBase] = []
	for unit: UnitBase in units:
		if _alive(unit) and unit.player_owner == owner: group.append(unit)
	var started: int = Time.get_ticks_usec()
	var orders: Array[Dictionary] = PLANNER.plan(game_map, group, game_map.world_to_tile(destination), group, owner)
	for order: Dictionary in orders:
		var unit: UnitBase = order.unit
		var route: PackedVector2Array = order.path
		if attack:
			unit.command_attack_move_path(route) if not route.is_empty() else unit.command_attack_move(order.destination)
		else:
			unit.command_move_path(route) if not route.is_empty() else unit.command_move(order.destination)
	report.commands.append({"game_time": GameManager.game_time, "phase": phase, "owner": owner, "units": group.size(), "orders": orders.size(), "attack_move": attack, "destination": _xy(destination), "dispatch_ms": float(Time.get_ticks_usec() - started) / 1000.0})

func _damage(unit: UnitBase, amount: float) -> void:
	last_hit_us = Time.get_ticks_usec()
	if first_hit_us == 0: first_hit_us = last_hit_us
	report.damage_events.append({"at_us": last_hit_us, "game_time": GameManager.game_time, "owner": unit.player_owner, "role": unit.unit_type, "damage": amount})

func _bank(owner: int, resource: String, amount: int) -> void:
	var previous: int = int(banks[owner][resource])
	banks[owner][resource] = amount
	report.bank_ledger.append({"game_time": GameManager.game_time, "owner": owner, "resource": resource, "delta": amount - previous})

func _alive(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit is UnitBase and not unit.is_queued_for_deletion() and unit.current_state != UnitBase.State.DEAD

func _unit_snapshot() -> Array:
	var snapshot: Array = []
	for unit: UnitBase in units:
		if _alive(unit): snapshot.append({"owner": unit.player_owner, "role": unit.unit_type, "hp": unit.hp, "max_hp": unit.max_hp, "position": _xy(unit.global_position), "state": unit.current_state})
	return snapshot

func _worker_counts() -> Array:
	var counts: Array = [0, 0]
	for owner: int in 2:
		for unit: UnitBase in main._player_units[owner]:
			if _alive(unit) and unit.unit_type == UnitData.UnitType.VILLAGER: counts[owner] += 1
	return counts

func _xy(value: Vector2) -> Array:
	return [value.x, value.y]

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_directory.path_join(filename))

func _finish() -> void:
	report.phase = phase
	report.sample_started_us = sample_started_us
	report.sample_ended_us = sample_ended_us
	report.first_hit_us = first_hit_us
	report.last_hit_us = last_hit_us
	report.frame_columns = ["wall_seconds", "frame_ms", "process_ms", "physics_ms", "draw_calls", "visible_military_cached_2Hz", "attacking_cached_2Hz", "damage_within_1s"]
	report.frames = frame_rows
	report.observer = {"presence_total_us": observer_total_us, "presence_peak_us": observer_peak_us, "presence_interval_seconds": 0.5, "frame_callback": "constant append of eight values; no added fixture I/O or screenshots during sampling; ordinary runtime diagnostics persistence retained"}
	report.navigation_failures = nav_failures
	report.final_banks = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	FileAccess.open(output_directory.path_join("raw.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[DENSE_PAID_NATIVE] ", JSON.stringify({"phase": phase, "frames": frame_rows.size(), "failures": report.failures, "output": output_directory}))
	get_tree().quit(0 if report.failures.is_empty() else 1)


func _check_focus_only() -> void:
	get_window().grab_focus()
	var deadline: int = Time.get_ticks_msec() + 3000
	while not get_window().has_focus() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var result: Dictionary = {"focused": get_window().has_focus(), "display": DisplayServer.get_name(), "window_visible": get_window().visible, "launch": "macOS LaunchServices open -n -W -a", "pid": OS.get_process_id(), "user_data": OS.get_user_data_dir(), "probe_sha256": FileAccess.get_file_as_string("res://tools/probe_dense_paid_native.gd").sha256_text()}
	FileAccess.open(output_directory.path_join("focus.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("[NATIVE_FOCUS] ", JSON.stringify(result))
	get_tree().quit(0 if result.focused and result.display != "headless" else 1)
