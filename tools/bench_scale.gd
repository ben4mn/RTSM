extends Node
## Scale stress benchmark (workstream F). Boots a real solo match with both AIs
## alive, tops each side up to `bodies` living units (villagers on the economy,
## a field army fighting at the map centre, an idle garrison at home, two
## towers), keeps that count for `seconds` of simulation and reports the
## wall/game ratio plus PerfProbe's per-system breakdown.
##   godot --headless --fixed-fps 60 res://tools/bench_scale.tscn -- --bodies=120 --seconds=30 --net=1
## `--net=1` also builds and JSON-encodes both authority snapshots at 10 Hz.
## `--select=N` keeps N own units selected so the HUD refresh path is exercised.

const DEV_HOOKS := preload("res://scripts/managers/dev_hooks.gd")
const NETWORK_MATCH := preload("res://scripts/network/network_match.gd")
const WARMUP_SECONDS: float = 4.0
const TOP_UP_SECONDS: float = 1.0
## Share of each side's bodies: economy, field army, home garrison.
const VILLAGER_SHARE: float = 0.4
const FIELD_SHARE: float = 0.4
const ARMY_MIX: Array[int] = [UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.INFANTRY, UnitData.UnitType.CAVALRY, UnitData.UnitType.ARCHER]

var options: Dictionary = {"bodies": "60", "seconds": "30", "seed": "100", "net": "1", "select": "0", "output": "", "label": ""}
var match_scene: Node
var game_map: Node2D
var bot: AIController
var adapter: Node
var registered: Dictionary = {}
var field_ids: Dictionary = {}
var _spawn_serial: int = 0
var _field_seeded: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2 and options.has(parts[0]):
			options[parts[0]] = parts[1]
	var bodies: int = maxi(4, int(options["bodies"]))
	var seconds: float = float(options["seconds"])
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_civilization = CivilizationData.normalize(0)
	GameManager.selected_opponent_civilization = CivilizationData.normalize(1)
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_difficulty = 1
	GameManager.selected_population_limit = SkirmishData.normalize_population_limit(100)
	GameManager.selected_map_seed = int(options["seed"])
	GameManager.selected_map_archetype = MapData.normalize_archetype(0)
	match_scene = load("res://scenes/main/main.tscn").instantiate()
	add_child(match_scene)
	for frame: int in range(900):
		if match_scene.get("_building_placement") != null:
			break
		await get_tree().process_frame
	game_map = match_scene.game_map
	bot = AIController.new()
	bot.player_id = 0
	bot.enemy_id = 1
	bot.difficulty = 1
	bot.game_map = game_map
	bot.map_generator = game_map.map_generator
	bot.pathfinding = game_map.pathfinding
	match_scene.add_child(bot)
	bot.ai_wants_to_build.connect(func(building_type: int, tile: Vector2i, _rebuild: bool) -> void:
		match_scene._on_placement_confirmed(building_type, game_map.tile_to_world(tile)))
	bot.ai_wants_to_train.connect(func(building: Node, unit_type: int) -> void: match_scene._on_train_unit_requested(building, unit_type))
	bot.ai_wants_to_age_up.connect(func() -> void: match_scene._on_age_up_requested())
	var spawn: Vector2i = game_map.map_generator.spawn_positions[0]
	_register_bot_entities()
	bot.start_ai(spawn, game_map.tile_to_world(spawn))
	for player_id: int in 2:
		# The shipped limit is 100 slots (50 bodies); the benchmark measures beyond it.
		GameManager.players[player_id]["max_population"] = 100000
		ResourceManager.add_resource(player_id, "food", 4000)
		ResourceManager.add_resource(player_id, "wood", 4000)
		ResourceManager.add_resource(player_id, "gold", 2000)
		_spawn_towers(player_id)
	_top_up(bodies)
	if int(options["net"]) > 0:
		adapter = NETWORK_MATCH.new()
		add_child(adapter)
		adapter.setup(match_scene)
		# setup() parks the opponent AI for real online play; this is a solo sim.
		match_scene.ai_controller.process_mode = Node.PROCESS_MODE_INHERIT
	var warm_until: float = GameManager.game_time + WARMUP_SECONDS
	var next_top_up: float = GameManager.game_time + TOP_UP_SECONDS
	while GameManager.game_time < warm_until and GameManager.current_state == GameManager.GameState.PLAYING:
		_register_bot_entities()
		if GameManager.game_time >= next_top_up:
			next_top_up += TOP_UP_SECONDS
			_top_up(bodies)
		await get_tree().process_frame
	PerfProbe.reset()
	PerfProbe.on = true
	var started_game: float = GameManager.game_time
	var started_usec: int = Time.get_ticks_usec()
	var started_cpu: float = _process_cpu_seconds()
	var frame_usec := PackedInt32Array()
	var last_usec: int = started_usec
	var next_snapshot: float = started_game
	var snapshot_bytes: int = 0
	var snapshots: int = 0
	var body_samples: int = 0
	var body_total: int = 0
	var fighting_total: int = 0
	var harness_usec: int = 0
	while GameManager.current_state == GameManager.GameState.PLAYING and GameManager.game_time - started_game < seconds:
		var harness_started: int = Time.get_ticks_usec()
		_register_bot_entities()
		if GameManager.game_time >= next_top_up:
			next_top_up += TOP_UP_SECONDS
			_top_up(bodies)
			_keep_selection(int(options["select"]))
			body_samples += 1
			for player_id: int in 2:
				for unit: UnitBase in match_scene._player_units[player_id]:
					if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
						body_total += 1
						if unit.current_state == UnitBase.State.ATTACKING:
							fighting_total += 1
		harness_usec += Time.get_ticks_usec() - harness_started
		if adapter != null and GameManager.game_time >= next_snapshot:
			next_snapshot += NetworkSession.SNAPSHOT_INTERVAL
			var probe: int = Time.get_ticks_usec()
			adapter._register_server_entities()
			adapter._snapshot_number += 1
			var packets: Array = [adapter._snapshot_for(0), adapter._snapshot_for(1)]
			probe = PerfProbe.add(&"net.snapshot", probe)
			for packet: Dictionary in packets:
				snapshot_bytes += JSON.stringify(packet).length()
				snapshots += 1
			PerfProbe.add(&"net.json", probe)
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		frame_usec.append(now - last_usec)
		last_usec = now
	PerfProbe.on = false
	var cpu_seconds: float = _process_cpu_seconds() - started_cpu
	# Outcome fingerprint: equal before/after a change means the simulation ran
	# the same way (positions to 0.01 px, HP, state, banked resources).
	var fingerprint: Array = []
	for player_id: int in 2:
		fingerprint.append(ResourceManager.get_all_resources(player_id))
		for unit: UnitBase in match_scene._player_units[player_id]:
			if is_instance_valid(unit):
				fingerprint.append([unit.unit_type, roundi(unit.global_position.x * 100.0), roundi(unit.global_position.y * 100.0), roundi(unit.hp * 10.0), unit.current_state])
		for building: BuildingBase in match_scene._player_buildings[player_id]:
			if is_instance_valid(building):
				fingerprint.append([building.building_type, building.hp, building.state])
	var wall_usec: int = Time.get_ticks_usec() - started_usec - harness_usec
	var game_seconds: float = GameManager.game_time - started_game
	frame_usec.sort()
	var systems: Dictionary = {}
	var keys: Array = PerfProbe.usec.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return int(PerfProbe.usec[a]) > int(PerfProbe.usec[b]))
	var top_level_usec: int = 0
	for key: StringName in keys:
		var total: int = int(PerfProbe.usec[key])
		systems[str(key)] = {"ms_per_game_second": snappedf(float(total) / 1000.0 / maxf(0.001, game_seconds), 0.01), "share": snappedf(float(total) / float(maxi(1, wall_usec)), 0.001), "calls": int(PerfProbe.calls[key])}
		if not "." in str(key) or str(key).get_slice(".", 0) in ["main", "net", "path", "building", "site", "ai", "fog", "villager"]:
			if str(key).count(".") <= 1 and not str(key).begins_with("unit.state."):
				top_level_usec += total
	var frames: int = frame_usec.size()
	var report: Dictionary = {
		"label": str(options["label"]), "bodies_per_side": bodies, "net": adapter != null, "selected": int(options["select"]),
		"game_seconds": snappedf(game_seconds, 0.01), "wall_seconds": snappedf(float(wall_usec) / 1000000.0, 0.01),
		"realtime_ratio": snappedf(game_seconds / maxf(0.000001, float(wall_usec) / 1000000.0), 0.01),
		# Process CPU time (Linux only, -1 elsewhere) is insensitive to other jobs on
		# a shared box; the simulation is single-threaded, so this is the ratio an
		# idle core would give.
		"cpu_seconds": snappedf(cpu_seconds, 0.01),
		"cpu_realtime_ratio": snappedf(game_seconds / cpu_seconds, 0.01) if cpu_seconds > 0.0 else -1.0,
		"frames": frames,
		"frame_ms": {"mean": snappedf(float(wall_usec) / 1000.0 / maxf(1.0, float(frames)), 0.01),
			"p50": snappedf(float(frame_usec[frames / 2]) / 1000.0, 0.01) if frames > 0 else 0.0,
			"p95": snappedf(float(frame_usec[int(float(frames) * 0.95)]) / 1000.0, 0.01) if frames > 0 else 0.0,
			"max": snappedf(float(frame_usec[frames - 1]) / 1000.0, 0.01) if frames > 0 else 0.0},
		"average_living_bodies": snappedf(float(body_total) / maxf(1.0, float(body_samples)), 0.1),
		"average_attacking": snappedf(float(fighting_total) / maxf(1.0, float(body_samples)), 0.1),
		"buildings": get_tree().get_nodes_in_group("buildings").size(),
		"snapshot_bytes_mean": int(float(snapshot_bytes) / maxf(1.0, float(snapshots))),
		"state_hash": JSON.stringify(fingerprint).md5_text().substr(0, 12),
		"unattributed_share": snappedf(1.0 - float(top_level_usec) / float(maxi(1, wall_usec)), 0.001),
		"systems": systems,
	}
	if str(options["output"]) != "":
		var file: FileAccess = FileAccess.open(str(options["output"]), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
			file.close()
	print("BENCH_SCALE ", JSON.stringify(report))
	match_scene.free()
	get_tree().quit()


## utime + stime of this process from /proc (clock ticks are 1/100 s on Linux).
func _process_cpu_seconds() -> float:
	var output: Array = []
	if OS.get_name() != "Linux" or OS.execute("cat", ["/proc/%d/stat" % OS.get_process_id()], output) != 0 or output.is_empty():
		return -1.0
	var text: String = str(output[0])
	var fields: PackedStringArray = text.substr(text.rfind(")") + 2).split(" ")
	return (float(fields[11]) + float(fields[12])) / 100.0 if fields.size() > 12 else -1.0


func _register_bot_entities() -> void:
	for unit: Node in match_scene._player_units[0]:
		if is_instance_valid(unit) and not registered.has(unit.get_instance_id()):
			registered[unit.get_instance_id()] = true
			bot.register_unit(unit)
	for building: Node in match_scene._player_buildings[0]:
		if is_instance_valid(building) and not registered.has(building.get_instance_id()):
			registered[building.get_instance_id()] = true
			bot.register_building(building)


func _spawn_towers(player_id: int) -> void:
	var home: Vector2i = game_map.map_generator.spawn_positions[player_id]
	var placed: int = 0
	for offset: Vector2i in [Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6), Vector2i(6, 6), Vector2i(-6, -6)]:
		if placed >= 2:
			break
		var tile: Vector2i = home + offset
		if not game_map.is_tile_buildable(tile):
			continue
		var tower: BuildingBase = match_scene._spawn_building(BuildingData.BuildingType.WATCH_TOWER, player_id, tile)
		if tower != null:
			tower.complete_instantly()
			placed += 1


## Replace losses so the measured population stays at `bodies` per side.
func _top_up(bodies: int) -> void:
	var centre: Vector2 = game_map.sacred_site.global_position if game_map.sacred_site != null else game_map.tile_to_world(Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2))
	var villager_target: int = int(round(float(bodies) * VILLAGER_SHARE))
	var field_target: int = int(round(float(bodies) * FIELD_SHARE))
	for player_id: int in 2:
		var villagers: int = 0
		var field: int = 0
		var living: int = 0
		for unit: UnitBase in match_scene._player_units[player_id]:
			if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
				continue
			living += 1
			if unit.unit_type == UnitData.UnitType.VILLAGER:
				villagers += 1
			elif field_ids.has(unit.get_instance_id()):
				field += 1
		var home: Vector2i = game_map.map_generator.spawn_positions[player_id]
		while living < bodies:
			var unit_type: int = UnitData.UnitType.VILLAGER
			var to_field: bool = false
			if villagers >= villager_target:
				unit_type = ARMY_MIX[_spawn_serial % ARMY_MIX.size()]
				to_field = field < field_target
			_spawn_serial += 1
			# The opening field armies start either side of the centre so the fight
			# is on from the first measured second; replacements walk in from home.
			var origin: Vector2i = home
			if to_field and not _field_seeded:
				origin = game_map.world_to_tile(centre) + (Vector2i(-4, 0) if player_id == 0 else Vector2i(4, 0))
			var unit: UnitBase = _spawn(unit_type, player_id, origin)
			if unit == null:
				break
			living += 1
			if unit_type == UnitData.UnitType.VILLAGER:
				villagers += 1
			elif to_field:
				field += 1
				field_ids[unit.get_instance_id()] = true
				unit.command_attack_move(centre + Vector2(float((_spawn_serial * 37) % 160) - 80.0, float((_spawn_serial * 53) % 120) - 60.0))
	_field_seeded = true


func _spawn(unit_type: int, player_id: int, near: Vector2i) -> UnitBase:
	var pop_cost: int = int(UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1))
	if not GameManager.can_reserve_population(player_id, pop_cost):
		GameManager.increase_population_cap(player_id, pop_cost)
	var tiles: Array[Vector2i] = game_map.pathfinding.get_walkable_tiles_near(near, 7, 96)
	if tiles.is_empty():
		return null
	return match_scene._spawn_unit(unit_type, player_id, game_map.tile_to_world(tiles[(_spawn_serial * 7) % tiles.size()]))


func _keep_selection(count: int) -> void:
	if count <= 0:
		return
	var selection: Node = game_map.selection_mgr
	if selection.selected.size() >= count:
		return
	var chosen: Array[Node2D] = []
	for unit: UnitBase in match_scene._player_units[0]:
		if chosen.size() >= count:
			break
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD and unit.unit_type != UnitData.UnitType.VILLAGER:
			chosen.append(unit)
	selection.select_many(chosen)
