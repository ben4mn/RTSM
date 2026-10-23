extends Node
## Three real scene-navigation journeys with an ordinary paid learner policy.
## This observer survives scene changes; production runtime is not modified.

const LEARNER: Script = preload("res://tools/fixtures/beginner_paid_policy.gd")
const CASES: Array[Dictionary] = [
	{"name": "plains-desktop", "map": MapData.MapArchetype.OPEN_PLAINS, "seed": 101, "pixels": Vector2i(1280, 720)},
	{"name": "river-phone", "map": MapData.MapArchetype.RIVER_CROSSINGS, "seed": 101, "pixels": Vector2i(844, 390)},
	{"name": "woodland-phone", "map": MapData.MapArchetype.WOODLAND_FLANKS, "seed": 101, "pixels": Vector2i(932, 430)},
]
const RUNTIME_PATHS: PackedStringArray = [
	"scripts/main/main.gd", "scripts/ui/main_menu.gd", "scripts/ui/hud.gd", "scripts/ui/game_over_screen.gd",
	"scripts/ui/build_menu.gd", "scripts/ai/ai_controller.gd", "scripts/units/unit_base.gd", "scripts/units/villager.gd",
	"scripts/units/combat.gd", "scripts/map/map_generator.gd", "scripts/map/game_map.gd", "scripts/map/pathfinding.gd",
	"scripts/map/sacred_site.gd", "scripts/managers/game_manager.gd", "scripts/managers/resource_manager.gd",
	"scripts/data/unit_data.gd", "scripts/data/building_data.gd", "scripts/data/skirmish_data.gd",
	"scripts/buildings/building_base.gd", "scripts/buildings/building_placement.gd", "scripts/map/resource_node.gd", "scripts/data/tech_data.gd",
	"tools/fixtures/beginner_paid_policy.gd", "tools/probe_polish_skirmishes.gd",
]

@export var probe_diagnostics: Dictionary = {}
var phase: String = "boot"
var output_directory: String = "res://output/polish-skirmishes-20261022"
var duration_limit: float = 900.0
var only_case: int = -1
var main: Node
var human: AIController
var report: Dictionary = {"cases": [], "failures": [], "focus_events": []}
var current: Dictionary = {}
var seen_units: Dictionary = {}
var seen_buildings: Dictionary = {}
var bank_previous: Array[Dictionary] = []
var frame_times: Array[float] = []
var process_times: Array[float] = []
var combat_frame_times: Array[float] = []
var last_frame_us: int = 0
var match_started_us: int = 0
var last_damage_us: int = 0
var previous_snapshot: float = -30.0
var previous_follow: float = -5.0
var capture_queue: Array[String] = []
var captured: Dictionary = {}
var winner: int = -1
var _had_preferences: bool = false
var _preferences_before: PackedByteArray
var _native: bool = false
var _fixed_fps: bool = false
var _collecting: bool = false
var _manual: bool = false
var _manual_captures: int = 0
const CROWD_SAMPLE_SECONDS: float = 0.5
const LONG_OBSERVATION_SECONDS: float = 8.0
const MAX_CROWD_RECORDS: int = 80
var _crowd_last_sample: float = -1.0
var _crowd_last_gaps: float = -5.0
var _crowd_units: Dictionary = {}
var _crowd_contacts: Dictionary = {}
var _crowd_stalls: Dictionary = {}
var _crowd_gaps: Array[Dictionary] = []
var _crowd_gap_visits: Dictionary = {}
var _crowd_capture_targets: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--manual": _manual = true
		if argument.begins_with("--output-dir="):
			output_directory = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--duration="):
			duration_limit = clampf(float(argument.trim_prefix("--duration=")), 60.0, 1200.0)
		elif argument.begins_with("--case="):
			only_case = clampi(int(argument.trim_prefix("--case=")), 0, CASES.size() - 1)
	_native = DisplayServer.get_name() != "headless"
	_fixed_fps = "--fixed-fps" in OS.get_cmdline_args()
	DirAccess.make_dir_recursive_absolute(output_directory)
	_had_preferences = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_preferences:
		_preferences_before = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	report["scope"] = "Automated slower learner versus untouched Easy AI. Ordinary starting banks, workers, paid buildings/queues/ages, fog, damage and objective rules. Real viewport mouse events enter and leave matches. Camera framing is observer controlled. Native screenshots are rendered observations, not human play or physical-phone testing."
	if _manual:
		report["scope"] = "Human commands and camera versus untouched Easy AI; observer captures ordinary paid play. Harness enters match and returns result to menu with real viewport events; no automated human policy or economic grants. F8 saves an observation. Native desktop, not physical-device evidence."
	report["congestion_scope"] = "Read-only 0.5 simulation-second samples of both owners, including offscreen actors. Close contact means overlapping configured unit circles; it is not a collision or path failure. Low displacement means a live travel route advanced less than 4 world units from its episode anchor for 8 simulation seconds; settled workers without active navigation and in-range unit attackers are excluded. Discrete gap traversal requires observed entry and opposite-side exit of a walkable 1–3 tile passage between actual building footprints. Sampling can miss short contacts, cargo gains and fast crossings. No commands, grants, teleports, path queries, hidden-policy information or delayed victory are introduced."
	report["performance_scope"] = "Native process callback wall intervals and CPU process monitor at the recorded gameplay speed, excluding the first two wall seconds of each match. Combat intervals are within two wall seconds of actual HP loss. No fixed-FPS/headless timing is treated as performance. These are not display FPS, GPU timings, physical-device performance or a controlled baseline comparison. Observer and other desktop workloads contribute."
	report["native"] = _native
	report["fixed_fps"] = _fixed_fps
	report["engine"] = Engine.get_version_info()
	report["user_data_dir"] = OS.get_user_data_dir()
	report["started_unix"] = Time.get_unix_time_from_system()
	get_window().focus_exited.connect(func() -> void: report.focus_events.append({"at_us": Time.get_ticks_usec(), "phase": phase, "focused": false}))
	get_window().focus_entered.connect(func() -> void: report.focus_events.append({"at_us": Time.get_ticks_usec(), "phase": phase, "focused": true}))
	ResourceManager.resources_changed.connect(_on_resource_changed)
	GameManager.game_over.connect(_on_game_over)
	# Changing current_scene frees the menu/Main, while this root observer stays.
	get_tree().current_scene = null
	for case_index: int in CASES.size():
		if only_case >= 0 and case_index != only_case:
			continue
		if not await _run_case(case_index):
			break
	_finish()


func _run_case(case_index: int) -> bool:
	var scenario: Dictionary = CASES[case_index]
	Engine.time_scale = 1.0
	GameManager.audio_enabled = false
	GameManager.guided_opening_enabled = false
	GameManager.ui_scale = 1.0
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_difficulty = AIController.Difficulty.EASY
	GameManager.selected_population_limit = 30
	GameManager.selected_map_seed = int(scenario.seed)
	GameManager.selected_map_archetype = int(scenario.map)
	AudioManager.set_all_enabled(false)
	get_window().size = scenario.pixels
	GameManager.apply_preferences()
	if _native:
		get_window().grab_focus()
	current = {"name": scenario.name, "map": scenario.map, "seed": scenario.seed, "requested_pixels": _xy(scenario.pixels), "difficulty": 0, "population_limit": 30, "events": [], "screenshots": [], "snapshots": [], "transactions": [], "bank_ledger": [], "failures": [], "deposits": [{"food": 0, "wood": 0, "gold": 0}, {"food": 0, "wood": 0, "gold": 0}], "paid_units": [{}, {}], "completed_buildings": [{}, {}], "damage_events": [0, 0], "hp_lost": [0.0, 0.0], "attack_hits": [0, 0], "field_attack_orders": [0, 0], "first_contact": -1.0, "navigation_failures": [0, 0]}
	current["congestion"] = {"sample_period_game_seconds": CROWD_SAMPLE_SECONDS, "long_episode_game_seconds": LONG_OBSERVATION_SECONDS, "samples": 0, "long_contacts": 0, "long_travel_stalls": 0, "long_near_goal_stalls": 0, "max_contact_seconds": 0.0, "max_travel_stall_seconds": 0.0, "contact_records": [], "stall_records": [], "gap_traversals": [], "gap_candidates_seen": {}, "dropped_records": 0}
	current["coverage"] = {"required_for_scripted_case": not _manual, "failures": [], "paid_farms_completed": [0, 0], "farm_cargo_gain_samples": [0, 0], "farm_associated_food_deposits": [0, 0], "delivery_workers": [{}, {}], "farm_delivery_workers": [{}, {}], "dropoff_workers": [{}, {}], "gap_traversals": 0, "max_simultaneous_deliverers": [0, 0]}
	_crowd_last_sample = -1.0
	_crowd_last_gaps = -5.0
	_crowd_units.clear()
	_crowd_contacts.clear()
	_crowd_stalls.clear()
	_crowd_gaps.clear()
	_crowd_gap_visits.clear()
	_crowd_capture_targets.clear()
	seen_units.clear()
	seen_buildings.clear()
	frame_times.clear()
	process_times.clear()
	combat_frame_times.clear()
	capture_queue.clear()
	captured.clear()
	bank_previous.clear()
	winner = -1
	previous_snapshot = -30.0
	previous_follow = -5.0
	last_frame_us = 0
	last_damage_us = 0
	if get_tree().current_scene == null:
		var initial_menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
		get_tree().root.add_child(initial_menu)
		get_tree().current_scene = initial_menu
	var menu: Node = get_tree().current_scene
	if menu.scene_file_path != "res://scenes/ui/main_menu.tscn":
		return _fail("Expected a real main menu before starting " + str(scenario.name))
	menu.call("_on_shared_settings_closed")
	_set_phase("menu")
	await _settle(6)
	await _capture("01-menu")
	await _click(menu.get("start_button") as Button)
	if not await _wait_for(func() -> bool:
		return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/main/main.tscn" and get_tree().current_scene.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING
	):
		return _fail("Menu Start did not produce a ready match")
	main = get_tree().current_scene
	current["initial_banks"] = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	current["actual_map"] = int(main.game_map.map_generator.archetype)
	current["actual_guided_opening"] = bool(main.get("_guided_opening_active"))
	current["economic_bonus_active"] = bool(main.get("balance_ai_economic_bonus_active"))
	current["source_sha256"] = _source_hashes()
	current["actual_viewport"] = _xy(get_viewport().get_visible_rect().size)
	current["actual_window_size"] = _xy(get_window().size)
	current["grid_sha256"] = JSON.stringify(main.game_map.map_generator.grid).sha256_text()
	bank_previous = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	if current.initial_banks != [SkirmishData.STARTING_RESOURCES, SkirmishData.STARTING_RESOURCES] or current.actual_guided_opening or current.economic_bonus_active or current.actual_map != scenario.map:
		return _fail("Match did not begin with the requested ordinary rules")
	if not _manual:
		human = LEARNER.new()
		human.name = "PolishPaidLearner"
		human.player_id = 0
		human.enemy_id = 1
		human.difficulty = AIController.Difficulty.MEDIUM
		human.game_map = main.game_map
		human.map_generator = main.game_map.map_generator
		human.pathfinding = main.game_map.pathfinding
		main.add_child(human)
		human.ai_wants_to_build.connect(_human_build)
		human.ai_wants_to_train.connect(_human_train)
		human.ai_wants_to_age_up.connect(_human_age)
		human.ai_attack_launched.connect(_on_attack_order.bind(0))
	main.ai_controller.ai_attack_launched.connect(_on_attack_order.bind(1))
	main.game_map.sacred_site.captured.connect(func(owner: int) -> void: _event("sacred_captured", {"owner": owner}); _queue_capture("sacred-captured"))
	main.game_map.sacred_site.contested.connect(func() -> void: _event("sacred_contested"); _queue_capture("sacred-contested"))
	main.game_map.sacred_site.neutralized.connect(func() -> void: _event("sacred_neutralized"))
	_register_entities()
	if not _manual:
		var spawn: Vector2i = main.game_map.map_generator.spawn_positions[0]
		human.start_ai(spawn, main.game_map.tile_to_world(spawn))
		# Use the same speed controls available to players.
		await _key(KEY_EQUAL)
		await _key(KEY_EQUAL)
	current["simulation_speed"] = Engine.time_scale
	if not is_equal_approx(Engine.time_scale, 1.0 if _manual else 3.0):
		return _fail("Requested normal gameplay speed was not selected")
	match_started_us = Time.get_ticks_usec()
	_collecting = true
	_set_phase("opening")
	await _capture("02-opening")
	while GameManager.current_state in [GameManager.GameState.PLAYING, GameManager.GameState.PAUSED] and GameManager.game_time < duration_limit:
		_register_entities()
		_update_observation()
		if not capture_queue.is_empty():
			var capture_label: String = capture_queue.pop_front()
			_frame_crowd_capture(capture_label)
			await _capture(capture_label)
		await get_tree().process_frame
	_collecting = false
	current["game_seconds"] = GameManager.game_time
	current["wall_seconds"] = float(Time.get_ticks_usec() - match_started_us) / 1000000.0
	current["winner"] = winner
	current["ending"] = str(main.get("_victory_reason")) if winner >= 0 else "unresolved at time limit"
	current["live_stats"] = main.get("_stats").duplicate(true)
	current["learner"] = {"manual_human": true} if _manual else human.call("get_learner_receipt")
	current["summary"] = main.get("match_summary_diagnostics").duplicate(true)
	current["final_banks"] = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	current["performance"] = _performance_summary()
	_finalize_crowd_coverage()
	if winner < 0:
		_fail("Match reached its cap without a natural result")
		_write_case()
		return false
	_set_phase("result")
	await _settle(35)
	await _capture("90-result")
	var result: Node = main.get_node_or_null("GameOverScreen")
	if result == null or not bool(result.get("visible")):
		return _fail("Natural ending did not show the real game-over screen")
	_validate_case()
	await _click(result.get("main_menu_button") as Button)
	if not await _wait_for(func() -> bool:
		return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/ui/main_menu.tscn" and GameManager.current_state == GameManager.GameState.MENU and not get_tree().paused
	):
		return _fail("Result Menu button did not return to an unpaused menu")
	main = null
	human = null
	_set_phase("returned-menu")
	await _settle(6)
	await _capture("99-returned-menu")
	current["menu_return_verified"] = true
	_write_case()
	return current.failures.is_empty()


func _unhandled_key_input(event: InputEvent) -> void:
	if _manual and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_manual_captures += 1
		_queue_capture("manual-%02d" % _manual_captures)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _collecting or not _native or _fixed_fps or GameManager.current_state != GameManager.GameState.PLAYING:
		last_frame_us = 0
		return
	var now: int = Time.get_ticks_usec()
	if last_frame_us > 0 and now - match_started_us >= 2000000:
		var interval_ms: float = float(now - last_frame_us) / 1000.0
		frame_times.append(interval_ms)
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if last_damage_us > 0 and now - last_damage_us <= 2000000:
			combat_frame_times.append(interval_ms)
	last_frame_us = now


func _register_entities() -> void:
	for owner: int in [0, 1]:
		for unit: UnitBase in main._player_units[owner]:
			if not is_instance_valid(unit) or seen_units.has(unit.get_instance_id()):
				continue
			seen_units[unit.get_instance_id()] = true
			if owner == 0 and human != null:
				human.register_unit(unit)
			unit.damage_received.connect(_on_damage.bind(owner))
			unit.attack_landed.connect(_on_hit.bind(owner))
			unit.navigation_failed.connect(_on_navigation_failed.bind(owner))
			if unit is Villager:
				unit.resource_deposited.connect(_on_deposit.bind(owner, unit))
		for building: BuildingBase in main._player_buildings[owner]:
			if not is_instance_valid(building) or seen_buildings.has(building.get_instance_id()):
				continue
			seen_buildings[building.get_instance_id()] = true
			if owner == 0 and human != null:
				human.register_building(building)
			building.damage_received.connect(_on_damage.bind(owner))
			building.construction_complete.connect(_on_constructed.bind(owner))
			var queue: Node = building.get_production_queue()
			if queue != null:
				queue.unit_queued.connect(_on_queued.bind(owner))
				queue.unit_trained.connect(_on_trained.bind(owner))


func _human_build(kind: int, tile: Vector2i, _rebuild: bool) -> void:
	if human.call("accept_build_input", kind):
		main.call("_on_placement_confirmed", kind, main.game_map.tile_to_world(tile))
		_event("human_build_input", {"kind": kind, "tile": _xy(tile)})


func _human_train(building: Node, kind: int) -> void:
	if human.call("accept_train_input", building):
		main.call("_on_train_unit_requested", building, kind)
		_event("human_train_input", {"kind": kind, "result": main.get("_last_train_request_result")})


func _human_age() -> void:
	if human.call("accept_age_input"):
		main.call("_on_age_up_requested")
		_event("human_age_input", {"age": GameManager.get_player_age(0)})


func _on_queued(kind: int, owner: int) -> void:
	current.transactions.append({"at": GameManager.game_time, "action": "queued", "owner": owner, "kind": kind, "cost": UnitData.get_unit_cost(kind)})


func _on_trained(kind: int, owner: int) -> void:
	var counts: Dictionary = current.paid_units[owner]
	counts[str(kind)] = int(counts.get(str(kind), 0)) + 1
	current.transactions.append({"at": GameManager.game_time, "action": "trained", "owner": owner, "kind": kind})


func _on_constructed(building: BuildingBase, owner: int) -> void:
	var counts: Dictionary = current.completed_buildings[owner]
	var kind: String = str(building.building_type)
	counts[kind] = int(counts.get(kind, 0)) + 1
	_event("construction_complete", {"owner": owner, "kind": building.building_type, "id": building.get_instance_id(), "tile": _xy(main.game_map.world_to_tile(building.global_position))})
	if building.building_type == BuildingData.BuildingType.FARM:
		current.coverage.paid_farms_completed[owner] += 1
	if owner == 0:
		_queue_capture("03-construction")


func _on_deposit(resource: String, amount: int, owner: int, worker: Villager) -> void:
	current.deposits[owner][resource] = int(current.deposits[owner].get(resource, 0)) + amount
	var worker_id: String = str(worker.get_instance_id())
	current.coverage.delivery_workers[owner][worker_id] = true
	var dropoff: BuildingBase = worker.dropoff_target as BuildingBase
	if is_instance_valid(dropoff):
		var dropoff_id: String = str(dropoff.get_instance_id())
		if not current.coverage.dropoff_workers[owner].has(dropoff_id):
			current.coverage.dropoff_workers[owner][dropoff_id] = {"kind": dropoff.building_type, "workers": {}, "amount": 0}
		var delivery: Dictionary = current.coverage.dropoff_workers[owner][dropoff_id]
		delivery.workers[worker_id] = true
		delivery.amount += amount
		if owner == 0 and delivery.workers.size() >= 2:
			_queue_crowd_capture("08-shared-dropoff", dropoff.global_position, {"dropoff_id": dropoff_id, "distinct_delivering_workers": delivery.workers.keys(), "trigger": "actual deposit"})
	if resource == "food" and is_instance_valid(worker.gather_target) and worker.gather_target is BuildingBase and worker.gather_target.provides_food:
		# This attributes the active farm assignment, not each unit of mixed cargo.
		current.coverage.farm_associated_food_deposits[owner] += amount
		current.coverage.farm_delivery_workers[owner][worker_id] = true


func _on_damage(_victim: Node2D, loss: float, owner: int) -> void:
	if loss <= 0.0:
		return
	current.damage_events[owner] += 1
	current.hp_lost[owner] += loss
	last_damage_us = Time.get_ticks_usec()
	if float(current.first_contact) < 0.0:
		current.first_contact = GameManager.game_time
		_event("first_damage")
		_queue_capture("04-first-combat")


func _on_hit(_attacker: UnitBase, _defender: UnitBase, hp_loss: float, _counter: float, owner: int) -> void:
	if hp_loss > 0.0:
		current.attack_hits[owner] += 1


func _on_navigation_failed(unit: UnitBase, target: Vector2, owner: int) -> void:
	current.navigation_failures[owner] += 1
	var tile: Vector2i = main.game_map.world_to_tile(unit.global_position)
	var blocked: Array[Dictionary] = []
	var nearby_buildings: Array[Dictionary] = []
	for dy: int in range(-4, 5):
		for dx: int in range(-4, 5):
			var neighbor: Vector2i = tile + Vector2i(dx, dy)
			if not main.game_map.is_tile_walkable(neighbor):
				blocked.append(_xy(neighbor))
	for building: Node in get_tree().get_nodes_in_group("buildings"):
		if building is BuildingBase and building.global_position.distance_to(unit.global_position) < 320.0:
			nearby_buildings.append({"kind": building.building_type, "owner": building.player_owner, "tile": _xy(main.game_map.world_to_tile(building.global_position)), "footprint": _xy(building.footprint), "state": building.state})
	_event("navigation_failed", {"owner": owner, "unit_type": unit.unit_type, "unit_id": unit.get_instance_id(), "position": _xy(unit.global_position), "tile": _xy(tile), "target": _xy(target), "state": unit.current_state, "attack_move": unit.attack_move, "blocked_nearby": blocked, "buildings_nearby": nearby_buildings})


func _on_attack_order(units: Array, _target: Vector2, owner: int) -> void:
	current.field_attack_orders[owner] += 1
	_event("field_attack_order", {"owner": owner, "units": units.size()})


func _on_resource_changed(owner: int, resource: String, value: int) -> void:
	if not _collecting or owner < 0 or owner >= bank_previous.size():
		return
	var previous: int = int(bank_previous[owner].get(resource, 0))
	current.bank_ledger.append({"at": GameManager.game_time, "owner": owner, "resource": resource, "delta": value - previous})
	bank_previous[owner][resource] = value


func _on_game_over(owner: int) -> void:
	winner = owner
	_event("natural_game_over", {"winner": owner})


func _update_observation() -> void:
	var seconds: float = GameManager.game_time
	if GameManager.current_state == GameManager.GameState.PLAYING and seconds - _crowd_last_sample >= CROWD_SAMPLE_SECONDS:
		_sample_congestion(seconds)
	var site: Node = main.game_map.sacred_site
	var desired_phase: String = "combat" if float(current.first_contact) >= 0.0 else ("economy-building" if seconds >= 60.0 else "opening")
	if site.owning_player >= 0 and float(site.victory_timer) > 60.0:
		desired_phase = "sacred-hold"
	if phase != desired_phase:
		_set_phase(desired_phase)
	if not _manual and seconds - previous_follow >= 5.0:
		previous_follow = seconds
		_follow_visible_action()
	if seconds - previous_snapshot >= 30.0:
		previous_snapshot = seconds
		current.snapshots.append({"at": seconds, "bank": [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)], "population": [GameManager.get_committed_population(0), GameManager.get_committed_population(1)], "ages": [GameManager.get_player_age(0), GameManager.get_player_age(1)], "site": {"owner": site.owning_player, "state": site.state, "held": site.victory_timer}, "units": seen_units.size(), "buildings": seen_buildings.size()})
		_refresh_diagnostics()
		print("[POLISH_PROGRESS] ", JSON.stringify(probe_diagnostics))
		_write_json(output_directory.path_join("progress.json"), probe_diagnostics)
	if seconds >= 180.0:
		_queue_capture("05-economy-developed")
	if seconds >= 360.0:
		_queue_capture("06-battlefield")
	if site.owning_player >= 0 and float(site.victory_timer) >= float(site.victory_hold_time) - 30.0:
		_queue_capture("07-final-sacred-hold")


func _sample_congestion(seconds: float) -> void:
	_crowd_last_sample = seconds
	current.congestion.samples += 1
	if seconds - _crowd_last_gaps >= 5.0:
		_crowd_last_gaps = seconds
		_discover_base_gaps()
	var live: Array[UnitBase] = []
	var active_ids: Dictionary = {}
	var deliverers: Array[int] = [0, 0]
	for owner: int in [0, 1]:
		for unit: UnitBase in main._player_units[owner]:
			if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
				continue
			live.append(unit)
			var key: String = str(unit.get_instance_id())
			active_ids[key] = true
			var previous: Dictionary = _crowd_units.get(key, {})
			var sample: Dictionary = _crowd_unit_sample(unit)
			if unit is Villager:
				var worker := unit as Villager
				if worker.is_returning_resources():
					deliverers[owner] += 1
				if is_instance_valid(worker.gather_target) and worker.gather_target is BuildingBase and worker.gather_target.provides_food:
					var farm: BuildingBase = worker.gather_target
					if not previous.is_empty() and int(previous.get("farm_id", 0)) == farm.get_instance_id() and worker.carried_amount > int(previous.get("cargo", 0)):
						current.coverage.farm_cargo_gain_samples[owner] += 1
						if owner == 0 and int(current.coverage.paid_farms_completed[0]) >= 2:
							_queue_crowd_capture("09-active-paid-farms", farm.global_position, {"farm_id": farm.get_instance_id(), "worker_id": key, "trigger": "sampled cargo increase while assigned to a completed paid Farm"})
			var route: PackedVector2Array = unit.get_remaining_navigation_path()
			var attempting_travel: bool = unit._navigation_active and route.size() >= 2 and unit.global_position.distance_to(route[-1]) > 6.0
			if attempting_travel:
				var stall: Dictionary = _crowd_stalls.get(key, {})
				var endpoint: Vector2 = route[-1]
				if stall.is_empty() or unit.global_position.distance_to(stall.anchor) >= 4.0 or endpoint.distance_to(stall.goal) > 16.0 or int(stall.state) != unit.current_state:
					stall = {"start": seconds, "anchor": unit.global_position, "goal": endpoint, "state": unit.current_state, "reported": false}
				var elapsed: float = seconds - float(stall.start)
				current.congestion.max_travel_stall_seconds = maxf(float(current.congestion.max_travel_stall_seconds), elapsed)
				if elapsed >= LONG_OBSERVATION_SECONDS and not bool(stall.reported):
					stall.reported = true
					var near_goal: bool = unit.global_position.distance_to(endpoint) <= 48.0
					current.congestion.long_travel_stalls += 1
					if near_goal: current.congestion.long_near_goal_stalls += 1
					_crowd_record("stall_records", {"at": seconds, "duration_at_threshold": elapsed, "near_route_endpoint_48px": near_goal, "unit": sample, "route_endpoint": _xy(endpoint), "route_points": route.size()})
					if owner == 0:
						_queue_crowd_capture("11-long-travel-observation", unit.global_position, {"unit": sample, "duration": elapsed, "near_route_endpoint_48px": near_goal})
				_crowd_stalls[key] = stall
			else:
				_crowd_stalls.erase(key)
			_observe_gap_travel(unit, previous, seconds)
			_crowd_units[key] = sample
	for owner: int in [0, 1]:
		current.coverage.max_simultaneous_deliverers[owner] = maxi(int(current.coverage.max_simultaneous_deliverers[owner]), deliverers[owner])
	for key: String in _crowd_units.keys():
		if not active_ids.has(key):
			_crowd_units.erase(key)
			_crowd_stalls.erase(key)
	var close_pairs: Dictionary = {}
	for first: int in live.size():
		var a: UnitBase = live[first]
		for second: int in range(first + 1, live.size()):
			var b: UnitBase = live[second]
			var radius: float = float(UnitBase.UNIT_SIZES.get(a.unit_type, 10.0)) + float(UnitBase.UNIT_SIZES.get(b.unit_type, 10.0))
			var distance: float = a.global_position.distance_to(b.global_position)
			if distance >= radius:
				continue
			var pair_key: String = "%d:%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]
			close_pairs[pair_key] = true
			var contact: Dictionary = _crowd_contacts.get(pair_key, {"start": seconds, "reported": false})
			var elapsed: float = seconds - float(contact.start)
			current.congestion.max_contact_seconds = maxf(float(current.congestion.max_contact_seconds), elapsed)
			if elapsed >= LONG_OBSERVATION_SECONDS and not bool(contact.reported):
				contact.reported = true
				current.congestion.long_contacts += 1
				_crowd_record("contact_records", {"at": seconds, "duration_at_threshold": elapsed, "distance": distance, "circle_sum_radius": radius, "units": [_crowd_unit_sample(a), _crowd_unit_sample(b)]})
				if a.player_owner == 0 and b.player_owner == 0:
					_queue_crowd_capture("10-long-contact-observation", (a.global_position + b.global_position) * 0.5, {"unit_ids": [a.get_instance_id(), b.get_instance_id()], "duration": elapsed, "distance": distance})
			_crowd_contacts[pair_key] = contact
	for pair_key: String in _crowd_contacts.keys():
		if not close_pairs.has(pair_key): _crowd_contacts.erase(pair_key)


func _crowd_unit_sample(unit: UnitBase) -> Dictionary:
	var sample := {"id": unit.get_instance_id(), "owner": unit.player_owner, "type": unit.unit_type, "state": unit.current_state, "position": _xy(unit.global_position), "tile": _xy(main.game_map.world_to_tile(unit.global_position)), "at": GameManager.game_time}
	if unit is Villager:
		var worker := unit as Villager
		sample["work"] = worker.get_work_status()
		sample["cargo"] = worker.carried_amount
		sample["cargo_resources"] = worker._cargo.duplicate()
		sample["dropoff_id"] = worker.dropoff_target.get_instance_id() if is_instance_valid(worker.dropoff_target) else 0
		sample["farm_id"] = worker.gather_target.get_instance_id() if is_instance_valid(worker.gather_target) and worker.gather_target is BuildingBase and worker.gather_target.provides_food else 0
	return sample


func _discover_base_gaps() -> void:
	_crowd_gaps.clear()
	for owner: int in [0, 1]:
		var buildings: Array = main._player_buildings[owner]
		for first: int in buildings.size():
			var a: BuildingBase = buildings[first]
			if not is_instance_valid(a) or a.state == BuildingBase.State.DESTROYED: continue
			var a_rect := Rect2i(main.game_map.world_to_tile(a.global_position), a.footprint)
			for second: int in range(first + 1, buildings.size()):
				var b: BuildingBase = buildings[second]
				if not is_instance_valid(b) or b.state == BuildingBase.State.DESTROYED: continue
				var b_rect := Rect2i(main.game_map.world_to_tile(b.global_position), b.footprint)
				for across: int in [0, 1]:
					var along: int = 1 - across
					var left: Rect2i = a_rect if a_rect.position[across] < b_rect.position[across] else b_rect
					var right: Rect2i = b_rect if left == a_rect else a_rect
					var width: int = right.position[across] - left.end[across]
					var start: int = maxi(left.position[along], right.position[along])
					var finish: int = mini(left.end[along], right.end[along])
					if width < 1 or width > 3 or finish <= start: continue
					var origin := Vector2i.ZERO
					var size := Vector2i.ZERO
					origin[across] = left.end[across]
					origin[along] = start
					size[across] = width
					size[along] = finish - start
					var cells := Rect2i(origin, size)
					var walkable: bool = true
					for y: int in range(cells.position.y, cells.end.y):
						for x: int in range(cells.position.x, cells.end.x):
							walkable = walkable and main.game_map.is_tile_walkable(Vector2i(x, y))
					if not walkable: continue
					var key: String = "%d:%d:%d" % [a.get_instance_id(), b.get_instance_id(), across]
					var gap := {"id": key, "owner": owner, "rect": cells, "along": along, "width_tiles": width, "building_ids": [a.get_instance_id(), b.get_instance_id()]}
					_crowd_gaps.append(gap)
					current.congestion.gap_candidates_seen[key] = {"owner": owner, "tile": _xy(origin), "size": _xy(size), "along_axis": along, "width_tiles": width, "building_ids": gap.building_ids}


func _observe_gap_travel(unit: UnitBase, previous: Dictionary, seconds: float) -> void:
	if previous.is_empty(): return
	var tile: Vector2i = main.game_map.world_to_tile(unit.global_position)
	var previous_tile := Vector2i(int(previous.tile.x), int(previous.tile.y))
	for gap: Dictionary in _crowd_gaps:
		if int(gap.owner) != unit.player_owner: continue
		var cells: Rect2i = gap.rect
		var along: int = int(gap.along)
		var across: int = 1 - along
		var key: String = "%d:%s" % [unit.get_instance_id(), gap.id]
		if cells.has_point(tile):
			if not _crowd_gap_visits.has(key):
				var side: int = -1 if previous_tile[along] < cells.position[along] else (1 if previous_tile[along] >= cells.end[along] else 0)
				if side != 0 and previous_tile[across] >= cells.position[across] and previous_tile[across] < cells.end[across]:
					_crowd_gap_visits[key] = {"at": seconds, "side": side, "entry_tile": _xy(previous_tile)}
		elif _crowd_gap_visits.has(key):
			var visit: Dictionary = _crowd_gap_visits[key]
			var exit_side: int = -1 if tile[along] < cells.position[along] else (1 if tile[along] >= cells.end[along] else 0)
			if exit_side == -int(visit.side) and tile[across] >= cells.position[across] and tile[across] < cells.end[across] and seconds - float(visit.at) <= 20.0:
				current.coverage.gap_traversals += 1
				var record := {"at": seconds, "entered_at": visit.at, "unit": _crowd_unit_sample(unit), "gap_id": gap.id, "width_tiles": gap.width_tiles, "entry_tile": visit.entry_tile, "exit_tile": _xy(tile)}
				_crowd_record("gap_traversals", record)
				if unit.player_owner == 0:
					_queue_crowd_capture("12-base-gap-traversal", unit.global_position, record)
			_crowd_gap_visits.erase(key)
	# Expired visits cannot accumulate after death or topology changes.
	for key: String in _crowd_gap_visits.keys():
		if seconds - float(_crowd_gap_visits[key].at) > 20.0: _crowd_gap_visits.erase(key)


func _crowd_record(collection: String, record: Dictionary) -> void:
	if current.congestion[collection].size() < MAX_CROWD_RECORDS:
		current.congestion[collection].append(record)
	else:
		current.congestion.dropped_records += 1


func _queue_crowd_capture(label: String, position: Vector2, context: Dictionary) -> void:
	if _manual or captured.has(label) or _crowd_capture_targets.has(label): return
	_crowd_capture_targets[label] = {"position": _xy(position), "at": GameManager.game_time, "detail": context}
	_queue_capture(label)


func _frame_crowd_capture(label: String) -> void:
	if _manual or not _crowd_capture_targets.has(label): return
	var target: Dictionary = _crowd_capture_targets[label]
	main.game_map.camera.position = Vector2(float(target.position.x), float(target.position.y))
	main.game_map.camera.reset_smoothing()
	main.game_map.camera.force_update_scroll()
	previous_follow = GameManager.game_time


func _finalize_crowd_coverage() -> void:
	var failures: Array[String] = []
	for owner: int in [0, 1]:
		if int(current.coverage.paid_farms_completed[owner]) < 2:
			failures.append("Owner %d: fewer than 2 ordinary paid Farm completions" % owner)
		if current.coverage.delivery_workers[owner].size() < 2:
			failures.append("Owner %d: fewer than 2 distinct depositing workers" % owner)
		if int(current.coverage.farm_cargo_gain_samples[owner]) <= 0 or int(current.coverage.farm_associated_food_deposits[owner]) <= 0:
			failures.append("Owner %d: no observed Farm cargo gain plus Farm-associated food deposit" % owner)
		var shared: bool = false
		for delivery: Dictionary in current.coverage.dropoff_workers[owner].values():
			shared = shared or delivery.workers.size() >= 2
		if not shared: failures.append("Owner %d: no dropoff used by 2 distinct depositing workers" % owner)
	if int(current.coverage.gap_traversals) <= 0:
		failures.append("No sampled entry-and-opposite-exit traversal through a 1–3 tile building passage")
	current.coverage.failures = failures
	current.coverage["passed"] = failures.is_empty()
	# Coverage is independent of the actual match result and navigation failures.
	# Never stop a game early or hold victory to manufacture these observations.
	if not _manual and not failures.is_empty():
		if not report.has("coverage_failures"): report["coverage_failures"] = []
		report.coverage_failures.append({"case": current.name, "missing": failures})


func _follow_visible_action() -> void:
	for unit: UnitBase in main._player_units[0]:
		if is_instance_valid(unit) and unit.current_state == UnitBase.State.ATTACKING and is_instance_valid(unit.attack_target):
			main.game_map.selection_mgr.select_single(unit)
			main.game_map.camera.position = (unit.global_position + unit.attack_target.global_position) * 0.5
			return
	if GameManager.game_time >= 240.0:
		main.call("_on_sacred_site_pressed")
	else:
		main.call("_select_town_center")


func _queue_capture(label: String) -> void:
	if not captured.has(label) and label not in capture_queue:
		capture_queue.append(label)


func _capture(label: String) -> void:
	captured[label] = true
	if not _native:
		return
	await RenderingServer.frame_post_draw
	var filename: String = "%s-%s.png" % [current.name, label]
	var path: String = output_directory.path_join(filename)
	var result: Error = get_viewport().get_texture().get_image().save_png(path)
	if result != OK:
		_fail("Screenshot could not be saved: " + path)
	else:
		current.screenshots.append({"file": path, "game_seconds": GameManager.game_time, "phase": phase, "congestion_context": _crowd_capture_targets.get(label, {})})


func _click(button: Button) -> void:
	if button == null or not button.is_visible_in_tree() or button.disabled:
		_fail("Navigation button is unavailable")
		return
	var viewport: Viewport = button.get_viewport()
	# push_input(..., true) takes logical viewport coordinates. Include the
	# control's canvas transform, but do not apply the final window stretch.
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	var receipt := {"phase": phase, "button": str(button.get_path()), "point": _xy(point), "canvas_rect_center": _xy(button.get_global_rect().get_center()), "viewport": _xy(viewport.get_visible_rect().size), "window": _xy(get_window().size), "final_transform": str(viewport.get_final_transform()), "content_scale_factor": get_window().content_scale_factor, "pressed_signals": 0, "gui_mouse_buttons": 0}
	var on_pressed: Callable = func() -> void: receipt.pressed_signals += 1
	var on_input: Callable = func(event: InputEvent) -> void:
		if event is InputEventMouseButton: receipt.gui_mouse_buttons += 1
	button.pressed.connect(on_pressed)
	button.gui_input.connect(on_input)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	receipt["hovered_after_motion"] = button.is_hovered()
	# Keep the synthetic gesture in one dispatch turn. Yielding while pressed
	# lets an unrelated native pointer/focus event cancel the Button attempt.
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
	if is_instance_valid(button):
		button.pressed.disconnect(on_pressed)
		button.gui_input.disconnect(on_input)
	if not report.has("navigation_clicks"): report["navigation_clicks"] = []
	report.navigation_clicks.append(receipt)
	_write_json(output_directory.path_join("navigation-clicks.json"), {"clicks": report.navigation_clicks})
	await get_tree().process_frame


func _key(keycode: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame


func _wait_for(predicate: Callable) -> bool:
	for frame: int in 900:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _settle(frames: int) -> void:
	for frame: int in frames:
		await get_tree().process_frame


func _validate_case() -> void:
	for owner: int in [0, 1]:
		if int(current.paid_units[owner].get(str(UnitData.UnitType.VILLAGER), 0)) <= 0:
			_fail("Owner %d did not complete paid worker training" % owner)
		if current.completed_buildings[owner].is_empty():
			_fail("Owner %d did not finish construction" % owner)
		if int(current.deposits[owner].food) <= 0 or int(current.deposits[owner].wood) <= 0:
			_fail("Owner %d did not deposit ordinary food and wood" % owner)
		if int(current.attack_hits[owner]) <= 0:
			_fail("Owner %d landed no observed combat hit" % owner)
		for resource: String in ["food", "wood", "gold"]:
			var expected: int = int(current.initial_banks[owner][resource])
			for entry: Dictionary in current.bank_ledger:
				if entry.owner == owner and entry.resource == resource:
					expected += int(entry.delta)
			if expected != int(current.final_banks[owner][resource]):
				_fail("Resource ledger mismatch for owner %d %s" % [owner, resource])


func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in RUNTIME_PATHS:
		var script: Script = load("res://" + path)
		hashes[path] = script.get_source_code().sha256_text()
	return hashes


func _performance_summary() -> Dictionary:
	return {"eligible_native_timing": _native and not _fixed_fps, "process_frame_ms": _distribution(frame_times), "cpu_process_ms": _distribution(process_times), "combat_process_frame_ms": _distribution(combat_frame_times), "simulation_speed": current.get("simulation_speed", 1.0)}


func _distribution(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"count": 0}
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var over_33: int = 0
	for value: float in sorted:
		if value > 33.333:
			over_33 += 1
	return {"count": sorted.size(), "p50": sorted[int((sorted.size() - 1) * 0.5)], "p95": sorted[int((sorted.size() - 1) * 0.95)], "p99": sorted[int((sorted.size() - 1) * 0.99)], "max": sorted[-1], "over_33_33ms": over_33}


func _event(kind: String, detail: Dictionary = {}) -> void:
	if not current.is_empty():
		current.events.append({"at": GameManager.game_time, "kind": kind, "detail": detail})


func _set_phase(value: String) -> void:
	phase = value
	_refresh_diagnostics()
	print("[POLISH_PHASE] ", JSON.stringify(probe_diagnostics))


func _refresh_diagnostics() -> void:
	probe_diagnostics = {"phase": phase, "case": current.get("name", ""), "game_seconds": GameManager.game_time, "winner": winner, "output_directory": ProjectSettings.globalize_path(output_directory), "completed_cases": report.cases.size(), "failures": report.failures.duplicate(), "congestion": {"samples": current.get("congestion", {}).get("samples", 0), "long_contacts": current.get("congestion", {}).get("long_contacts", 0), "long_travel_stalls": current.get("congestion", {}).get("long_travel_stalls", 0), "gap_traversals": current.get("coverage", {}).get("gap_traversals", 0)}}


func _fail(message: String) -> bool:
	report.failures.append(message)
	if not current.is_empty():
		current.failures.append(message)
	push_error("[POLISH_FAIL] " + message)
	return false


func _write_case() -> void:
	report.cases.append(current.duplicate(true))
	_write_json(output_directory.path_join(str(current.name) + ".json"), current)
	_write_json(output_directory.path_join("report.json"), report)
	print("[POLISH_CASE] ", JSON.stringify({"name": current.name, "winner": current.winner, "ending": current.ending, "game_seconds": current.game_seconds, "wall_seconds": current.wall_seconds, "failures": current.failures}))


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))


func _xy(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _finish() -> void:
	_collecting = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	if _had_preferences:
		var preferences := FileAccess.open(GameManager.PREFERENCES_PATH, FileAccess.WRITE)
		preferences.store_buffer(_preferences_before)
	else:
		DirAccess.remove_absolute(GameManager.PREFERENCES_PATH)
	report["finished_unix"] = Time.get_unix_time_from_system()
	_set_phase("failed" if not report.failures.is_empty() else ("coverage-incomplete" if not report.get("coverage_failures", []).is_empty() else "complete"))
	_write_json(output_directory.path_join("report.json"), report)
	print("[POLISH_DONE] ", JSON.stringify(probe_diagnostics))
	get_tree().quit(0 if report.failures.is_empty() and report.get("coverage_failures", []).is_empty() else 1)
