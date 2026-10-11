extends Node
## Real Main scene, ordinary bank/workers/vision/navigation/deposits. The labeled
## intervention depletes only currently visible Wood without crediting a bank;
## all other AI decisions are disabled to isolate resource-search ownership.

var _output: String = "res://output/evolution/resource-search-20261010/paid.json"
var _duration: float = 240.0
var _seed: int = 424242
var _observe_only: bool = false
var _deposits: Dictionary = {"food": 0, "wood": 0, "gold": 0}
var _first_wood_deposit: float = -1.0
var _first_new_visible_wood: float = -1.0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--duration="):
			_duration = float(argument.trim_prefix("--duration="))
		elif argument.begins_with("--seed="):
			_seed = int(argument.trim_prefix("--seed="))
		elif argument == "--observe-only":
			_observe_only = true
	AudioManager.set_all_enabled(false)
	GameManager.selected_map_seed = _seed
	GameManager.selected_population_limit = 20
	GameManager.guided_opening_enabled = false
	var main := preload("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for _frame: int in range(900):
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	var map: Node2D = main.get("game_map")
	var ai: AIController = main.get("ai_controller")
	ai.process_mode = Node.PROCESS_MODE_DISABLED
	var workers: Array[Villager] = []
	for unit: Node in main.get("_player_units")[0]:
		if unit is Villager:
			(unit as Villager).command_stop()
	for unit: Node in main.get("_player_units")[1]:
		if unit is Villager:
			var worker := unit as Villager
			worker.command_stop()
			workers.append(worker)
			worker.resource_deposited.connect(_on_deposit)
	var bank_before: Dictionary = ResourceManager.get_all_resources(1)
	var removed_tiles: Array[Vector2i] = []
	var removed_stock: int = 0
	for tile: Vector2i in (map.get("resource_nodes") as Dictionary).keys():
		if not map.call("is_tile_visible_to_player", tile, 1):
			continue
		var resource: ResourceNode = map.call("get_resource_node_at", tile) as ResourceNode
		if resource != null and resource.resource_type == "wood":
			removed_stock += resource.remaining
			removed_tiles.append(tile)
			resource.harvest(resource.remaining)
	await get_tree().process_frame
	for index: int in range(3):
		var food: Node2D = map.call("get_nearest_reachable_resource_node", "food", workers[index].global_position, 1)
		if food != null:
			workers[index].command_gather(food)
	ai.call("_reset_economy_recovery")
	var gold: Node2D = map.call("get_nearest_reachable_resource_node", "gold", workers[3].global_position, 1)
	var report: Dictionary = {
		"evidence_kind": "real Main paid economy/navigation fixture; visible Wood deliberately depleted without bank credit; other AI decisions disabled; fixed60; not an ordinary untouched match",
		"seed": _seed, "population_cap": 20, "duration": _duration,
		"source_sha256": _source_hashes(), "starting_bank": bank_before,
		"removed_visible_wood_tiles": removed_tiles, "removed_visible_wood_stock_without_credit": removed_stock,
		"reachable_visible_gold_exists": gold != null,
		"wood_lookup_before": map.call("get_nearest_reachable_resource_node", "wood", workers[3].global_position, 1) != null,
	}
	ai.call("_assign_idle_villagers")
	report["initial_task_after_assignment"] = workers[3].get_economy_task()
	report["initial_search_snapshot"] = ai.get_strategy_snapshot()
	var next_decision: float = GameManager.game_time + 1.5
	var samples: Array[Dictionary] = []
	var next_sample: float = GameManager.game_time + 20.0
	while GameManager.game_time < _duration and GameManager.current_state == GameManager.GameState.PLAYING:
		if GameManager.game_time >= next_decision:
			next_decision += 1.5
			ai.call("_assign_idle_villagers")
		if _first_new_visible_wood < 0.0 and map.call("get_nearest_reachable_resource_node", "wood", workers[3].global_position, 1) != null:
			_first_new_visible_wood = GameManager.game_time
		if GameManager.game_time >= next_sample:
			next_sample += 20.0
			samples.append({"time": GameManager.game_time, "worker_task": workers[3].get_economy_task(), "worker_state": workers[3].current_state, "position": workers[3].global_position, "deposits": _deposits.duplicate(), "strategy": ai.get_strategy_snapshot()})
		await get_tree().process_frame
	report["deposits"] = _deposits
	report["first_new_visible_reachable_wood_seconds"] = _first_new_visible_wood
	report["first_real_wood_deposit_seconds"] = _first_wood_deposit
	report["final_bank"] = ResourceManager.get_all_resources(1)
	report["samples"] = samples
	report["final_strategy"] = ai.get_strategy_snapshot()
	var conservation: bool = true
	for kind: String in ["food", "wood", "gold"]:
		conservation = conservation and int(report["final_bank"][kind]) == int(bank_before[kind]) + int(_deposits[kind])
	report["criteria"] = {"visible_wood_initially_absent": not bool(report["wood_lookup_before"]), "surplus_gold_reachable": gold != null, "new_wood_revealed_by_live_worker_vision": _first_new_visible_wood >= 0.0, "real_wood_deposit": int(_deposits["wood"]) > 0, "bank_equals_start_plus_real_deposits": conservation}
	var passed: bool = true
	for value: Variant in (report["criteria"] as Dictionary).values():
		passed = passed and bool(value)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output).get_base_dir())
	var file := FileAccess.open(_output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[", "OBSERVED" if _observe_only else ("PASS" if passed else "FAIL"), "] ai_resource_search_paid ", JSON.stringify({"criteria": report["criteria"], "deposits": _deposits, "first_wood_deposit": _first_wood_deposit, "final_strategy": report["final_strategy"]}))
	get_tree().quit(0 if _observe_only or passed else 1)


func _on_deposit(kind: String, amount: int) -> void:
	_deposits[kind] = int(_deposits.get(kind, 0)) + amount
	if kind == "wood" and _first_wood_deposit < 0.0:
		_first_wood_deposit = GameManager.game_time


func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in ["scripts/ai/ai_controller.gd", "scripts/units/unit_base.gd", "scripts/units/villager.gd", "scripts/main/main.gd", "scripts/map/game_map.gd", "scripts/map/map_generator.gd", "scripts/managers/resource_manager.gd", "scripts/managers/game_manager.gd", "tools/probe_ai_resource_search_paid.gd"]:
		hashes[path] = (load("res://" + path) as Script).source_code.sha256_text()
	return hashes
