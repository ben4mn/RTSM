extends Node
## One headless AI-vs-AI skirmish for tools/joy_match_report.py.
## Player 0 is a second AIController paying through the human build/train/age
## transactions (same mechanism as probe_ai_compact_paid_match.gd). Nothing is
## granted or injected; observation reuses scripts/managers/dev_hooks.gd.

const DEV_HOOKS := preload("res://scripts/managers/dev_hooks.gd")
const SAMPLE_SECONDS: float = 60.0
const FLOAT_SAMPLE_SECONDS: float = 5.0

var options: Dictionary = {"seed": "100", "difficulty": "1", "civ": "0", "opp": "1", "map": "0", "pop": "100", "max-seconds": "1800", "output": ""}
var match_scene: Node
var bot: AIController
var hooks: Node
var registered: Dictionary = {}
var timeline: Array[Dictionary] = []
var float_sum: Array[Dictionary] = [{}, {}]
var float_peak: Array[int] = [0, 0]
var float_samples: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2 and options.has(parts[0]):
			options[parts[0]] = parts[1]
	var difficulty: int = clampi(int(options["difficulty"]), 0, 2)
	var max_seconds: float = float(options["max-seconds"])
	# Pin every match preference so saved player settings cannot leak in.
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_civilization = CivilizationData.normalize(int(options["civ"]))
	GameManager.selected_opponent_civilization = CivilizationData.normalize(int(options["opp"]))
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_difficulty = difficulty
	GameManager.selected_population_limit = SkirmishData.normalize_population_limit(int(options["pop"]))
	GameManager.selected_map_seed = int(options["seed"])
	GameManager.selected_map_archetype = MapData.normalize_archetype(int(options["map"]))
	match_scene = load("res://scenes/main/main.tscn").instantiate()
	add_child(match_scene)
	for frame: int in range(900):
		if match_scene.get("_building_placement") != null:
			break
		await get_tree().process_frame
	var game_map: Node2D = match_scene.game_map
	bot = AIController.new()
	bot.player_id = 0
	bot.enemy_id = 1
	bot.difficulty = difficulty
	bot.game_map = game_map
	bot.map_generator = game_map.map_generator
	bot.pathfinding = game_map.pathfinding
	match_scene.add_child(bot)
	bot.ai_wants_to_build.connect(func(building_type: int, tile: Vector2i, _rebuild: bool) -> void:
		match_scene._on_placement_confirmed(building_type, game_map.tile_to_world(tile)))
	bot.ai_wants_to_train.connect(func(building: Node, unit_type: int) -> void: match_scene._on_train_unit_requested(building, unit_type))
	bot.ai_wants_to_age_up.connect(func() -> void: match_scene._on_age_up_requested())
	hooks = DEV_HOOKS.new()
	match_scene.add_child(hooks)
	hooks.bind(match_scene)
	hooks.watch_ai(bot, 0)
	_register_bot_entities()
	var spawn: Vector2i = game_map.map_generator.spawn_positions[0]
	bot.start_ai(spawn, game_map.tile_to_world(spawn))
	var started_usec: int = Time.get_ticks_usec()
	var next_sample: float = SAMPLE_SECONDS
	var next_float: float = FLOAT_SAMPLE_SECONDS
	while GameManager.current_state == GameManager.GameState.PLAYING and GameManager.game_time < max_seconds:
		_register_bot_entities()
		if GameManager.game_time >= next_float:
			next_float += FLOAT_SAMPLE_SECONDS
			_sample_float()
		if GameManager.game_time >= next_sample:
			next_sample += SAMPLE_SECONDS
			timeline.append(_sample())
		await get_tree().process_frame
	var wall_seconds: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var final: Dictionary = hooks.snapshot()
	var finished: bool = GameManager.current_state == GameManager.GameState.GAME_OVER
	var players: Array[Dictionary] = []
	for player_id: int in [0, 1]:
		var player: Dictionary = final.players[player_id]
		var average: Dictionary = {}
		for resource: String in float_sum[player_id]:
			average[resource] = snappedf(float(float_sum[player_id][resource]) / maxf(1.0, float(float_samples)), 0.1)
		players.append({"civ": player.civ, "age": player.age, "age_times": player.age_times, "final_resources": player.resources,
			"final_units": player.units, "final_buildings": player.buildings, "units_lost": player.units_lost, "units_killed": player.units_killed,
			"buildings_lost": player.buildings_lost, "resources_gathered": player.resources_gathered,
			"average_float": average, "peak_float": float_peak[player_id], "totals": player.totals})
	var sacred_events: Array = hooks.events.filter(func(event: Dictionary) -> bool: return str(event.type).begins_with("sacred_"))
	var report: Dictionary = {
		"seed": final.seed, "map": final.map, "difficulty": difficulty, "population_limit": final.population_limit,
		"winner": hooks.winner if finished else -1,
		"win_reason": str(match_scene.get("_victory_reason")) if finished else "unresolved at %ds" % int(max_seconds),
		"length_seconds": snappedf(GameManager.game_time, 0.1), "wall_seconds": snappedf(wall_seconds, 0.1),
		"speedup": snappedf(GameManager.game_time / maxf(0.001, wall_seconds), 0.1),
		"first_combat_time": final.first_combat_time, "first_building_lost_time": final.first_building_lost_time,
		"players": players, "timeline": timeline, "sacred_events": sacred_events, "sacred_final": final.get("sacred_site", {}),
		"events": hooks.events,
	}
	var file: FileAccess = FileAccess.open(str(options["output"]), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report))
		file.close()
	print("[JOY_MATCH] seed=%s winner=%d reason=%s length=%.0fs wall=%.0fs" % [str(final.seed), int(report.winner), report.win_reason, GameManager.game_time, wall_seconds])
	Engine.time_scale = 1.0
	match_scene.free()
	get_tree().quit()


func _register_bot_entities() -> void:
	for unit: Node in match_scene._player_units[0]:
		if is_instance_valid(unit) and not registered.has(unit.get_instance_id()):
			registered[unit.get_instance_id()] = true
			bot.register_unit(unit)
	for building: Node in match_scene._player_buildings[0]:
		if is_instance_valid(building) and not registered.has(building.get_instance_id()):
			registered[building.get_instance_id()] = true
			bot.register_building(building)


func _sample_float() -> void:
	float_samples += 1
	for player_id: int in [0, 1]:
		var banked: Dictionary = ResourceManager.get_all_resources(player_id)
		var total: int = 0
		for resource: String in banked:
			total += int(banked[resource])
			float_sum[player_id][resource] = int(float_sum[player_id].get(resource, 0)) + int(banked[resource])
		float_sum[player_id]["total"] = int(float_sum[player_id].get("total", 0)) + total
		float_peak[player_id] = maxi(float_peak[player_id], total)


func _sample() -> Dictionary:
	var state: Dictionary = hooks.snapshot()
	var site: Dictionary = state.get("sacred_site", {})
	var sample: Dictionary = {"t": int(round(GameManager.game_time)), "players": [],
		"sacred": {"phase": site.get("phase", ""), "owner": site.get("owner", -1), "remaining": snappedf(float(site.get("remaining", 0.0)), 0.1)}}
	for player: Dictionary in state.players:
		var army: Dictionary = (player.units as Dictionary).duplicate()
		army.erase("villager")
		sample.players.append({"villagers": player.villagers, "idle_villagers": player.idle_villagers, "military": army, "age": player.age,
			"pop": player.pop, "pop_cap": player.pop_cap, "resources": player.resources, "gathered": (player.totals.gathered as Dictionary).duplicate(),
			"buildings": player.buildings})
	return sample
