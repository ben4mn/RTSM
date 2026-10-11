extends Node
## Real main-scene opening workers, normal bank and finite source deposits.
## AI policy is disabled after load so map/autoassignment can be compared
## without later recruitment, construction, scouting or combat decisions.

var _seed: int = 13
var _cap: int = 30
var _duration: float = 75.0
var _output: String = "res://output/evolution/map-opening-deposits.json"
var _main: Node
var _deposits: Array[Dictionary] = [{"food": 0, "wood": 0, "gold": 0}, {"food": 0, "wood": 0, "gold": 0}]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--pop="):
			_cap = int(argument.trim_prefix("--pop="))
		elif argument.begins_with("--duration="):
			_duration = float(argument.trim_prefix("--duration="))
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	AudioManager.set_all_enabled(false)
	GameManager.selected_map_seed = _seed
	GameManager.selected_population_limit = _cap
	GameManager.guided_opening_enabled = false
	_main = preload("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for _frame: int in range(900):
		if GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	if GameManager.current_state != GameManager.GameState.PLAYING:
		push_error("Opening deposit probe failed to start a real match")
		get_tree().quit(1)
		return
	_main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node.has_signal("resource_deposited"):
			node.connect("resource_deposited", _on_deposit.bind(int(node.get("player_owner"))))
	await get_tree().process_frame
	await get_tree().process_frame
	var report: Dictionary = {
		"evidence_kind": "fixed-FPS real main-scene opening simulation; ordinary starting bank and workers, AI decisions disabled after load",
		"seed": _seed, "population_cap": _cap, "duration_seconds": _duration,
		"source_sha256": _source_hashes(), "initial": _snapshot(),
	}
	while GameManager.game_time < _duration and GameManager.current_state == GameManager.GameState.PLAYING:
		await get_tree().process_frame
	report["final"] = _snapshot()
	report["deposits_by_resource"] = _deposits
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output).get_base_dir())
	var file := FileAccess.open(_output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	get_tree().quit(0)


func _on_deposit(resource_type: String, amount: int, player_id: int) -> void:
	_deposits[player_id][resource_type] += amount


func _snapshot() -> Dictionary:
	var workers: Array[Array] = [[], []]
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not node is Villager:
			continue
		var worker := node as Villager
		workers[worker.player_owner].append({"state": worker.current_state, "task": worker.get_economy_task(), "work_status": worker.get_work_status(), "position": [worker.global_position.x, worker.global_position.y], "gather_type": worker.gather_type, "target_valid": worker.gather_target != null and is_instance_valid(worker.gather_target), "carried": worker.carried_amount})
	return {"time": GameManager.game_time, "workers": workers, "banks": [ResourceManager.get_all_resources(0).duplicate(), ResourceManager.get_all_resources(1).duplicate()]}


func _source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in ["scripts/map/map_generator.gd", "scripts/map/map_data.gd", "scripts/map/pathfinding.gd", "scripts/map/game_map.gd", "scripts/data/unit_data.gd", "scripts/data/building_data.gd", "scripts/units/villager.gd", "scripts/units/unit_base.gd", "scripts/managers/fog_manager.gd", "scripts/main/main.gd", "tools/probe_map_opening_deposits.gd"]:
		result[path] = (load("res://" + path) as Script).source_code.sha256_text()
	return result
