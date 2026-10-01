extends SceneTree
## Real seeded match probe, using production gathering/building/queue/AI code.
## The human side keeps its normal opening economy but gives no commands.
## --attrition applies two explicit combat losses after the first attack to
## verify real paid replacements; it never grants resources or population.

var _limit: int = 30
var _difficulty: int = 1
var _seed: int = 101
var _duration: float = 600.0
var _attrition: bool = false
var _loss_time: float = -1.0
var _loss_count: int = 0
var _army_trained_at_loss: int = 0
var _main: Node
var _samples: Array[Dictionary] = []
var _last_sample_time: float = -10.0
var _winner: int = -1


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--limit="):
			_limit = int(argument.trim_prefix("--limit="))
		elif argument.begins_with("--difficulty="):
			_difficulty = int(argument.trim_prefix("--difficulty="))
		elif argument.begins_with("--seed="):
			_seed = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--duration="):
			_duration = float(argument.trim_prefix("--duration="))
		elif argument == "--attrition":
			_attrition = true
	call_deferred("_run")


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.set("selected_population_limit", _limit)
	gm.set("selected_difficulty", _difficulty)
	gm.set("selected_map_seed", _seed)
	gm.set("guided_opening_enabled", false)
	gm.set("audio_enabled", false)
	root.get_node("AudioManager").call("set_all_enabled", false)
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	gm.game_over.connect(func(winner_id: int) -> void: _winner = winner_id)
	for _frame in range(900):
		if int(gm.get("current_state")) == 2:
			break
		await process_frame
	if int(gm.get("current_state")) != 2:
		push_error("compact_ai_match: failed to reach PLAYING")
		quit(1)
		return
	var initial_resources: Array[Dictionary] = []
	for player_id in [0, 1]:
		initial_resources.append(root.get_node("ResourceManager").call("get_all_resources", player_id).duplicate())
	var initial_limits: Array[int] = [gm.call("get_player_population_limit", 0), gm.call("get_player_population_limit", 1)]
	for _frame in range(ceili((_duration + 5.0) * 60.0)):
		var elapsed: float = float(gm.get("game_time"))
		if elapsed - _last_sample_time >= 10.0:
			_record_sample()
			_last_sample_time = elapsed
		if _attrition and _loss_time < 0.0:
			var first_attack: float = float(_main.get("balance_ai_first_attack_time"))
			if first_attack >= 0.0 and elapsed >= first_attack + 15.0:
				_apply_attrition()
		if elapsed >= _duration or int(gm.get("current_state")) == 4:
			break
		await process_frame
	_record_sample()
	var stats: Array = _main.get("_stats")
	var summary: Dictionary = {
		"population_limit": _limit, "difficulty": _difficulty, "seed": _seed,
		"elapsed": float(gm.get("game_time")), "game_over": int(gm.get("current_state")) == 4,
		"winner": _winner, "victory_reason": str(_main.get("_victory_reason")), "human_policy": "normal opening gathering; no commands",
		"initial_population_limits": initial_limits, "initial_resources": initial_resources,
		"first_attack": _main.get("balance_ai_first_attack_time"),
		"attack_count": _main.get("balance_ai_attack_count"),
		"feudal_time": _main.get("balance_ai_feudal_time"),
		"castle_time": _main.get("balance_ai_castle_time"),
		"peak_villagers": _main.get("balance_ai_peak_villagers"),
		"peak_military": _main.get("balance_ai_peak_military"),
		"ai_stats": stats[1].duplicate(),
		"attrition_loss_time": _loss_time, "attrition_loss_count": _loss_count,
		"army_produced_after_attrition": int(stats[1]["army_trained"]) - _army_trained_at_loss if _loss_time >= 0.0 else 0,
		"economic_bonus_active": _main.get("balance_ai_economic_bonus_active"),
		"samples": _samples,
	}
	var output_path: String = OS.get_environment("AOEM_PROBE_OUTPUT")
	if output_path != "":
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(summary, "\t"))
	var compact_summary: Dictionary = summary.duplicate()
	compact_summary.erase("samples")
	print("[COMPACT_AI_MATCH] %s" % JSON.stringify(compact_summary))
	paused = false
	_main.free()
	current_scene = null
	await process_frame
	quit(0 if initial_limits == [_limit, _limit] and not bool(summary["economic_bonus_active"]) else 1)


func _record_sample() -> void:
	_main.call("_update_balance_snapshot")
	var army_types: Dictionary = {}
	var units: Array = _main.get("_player_units")
	for unit in units[1]:
		if not is_instance_valid(unit) or int(unit.get("current_state")) == 5:
			continue
		var unit_type: int = int(unit.get("unit_type"))
		if unit_type != 0:
			army_types[str(unit_type)] = int(army_types.get(str(unit_type), 0)) + 1
	_samples.append({
		"time": _main.get("balance_elapsed_seconds"), "age": _main.get("balance_ai_age"),
		"villagers": _main.get("balance_ai_villagers"), "military": _main.get("balance_ai_military"),
		"population": _main.get("balance_ai_population"), "cap": _main.get("balance_ai_population_cap"),
		"resources": {"food": _main.get("balance_ai_food"), "wood": _main.get("balance_ai_wood"), "gold": _main.get("balance_ai_gold")},
		"army_types": army_types, "strategy": _main.get("ai_controller").call("get_strategy_snapshot"),
	})


func _apply_attrition() -> void:
	var units: Array = _main.get("_player_units")
	var candidates: Array = units[1].duplicate()
	for unit in candidates:
		if not is_instance_valid(unit) or int(unit.get("unit_type")) in [0, 4] or int(unit.get("current_state")) == 5:
			continue
		unit.call("take_damage", float(unit.get("hp")) + 100.0)
		_loss_count += 1
		if _loss_count >= 2:
			break
	if _loss_count > 0:
		_loss_time = float(root.get_node("GameManager").get("game_time"))
		var stats: Array = _main.get("_stats")
		_army_trained_at_loss = int(stats[1]["army_trained"])
