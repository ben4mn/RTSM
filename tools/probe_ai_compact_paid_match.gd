extends Node
## Automated opponent for player 0 using the human transactions, not free units.
var match_scene: Node
var human_bot: AIController
var stats: Dictionary = {"attacks": [0, 0], "peak_workers": [0, 0], "peak_troops": [0, 0], "peak_population": [0, 0], "peak_committed_workers": [0, 0], "peak_committed_fighters": [0, 0], "kills": [0, 0], "first_attack": [-1.0, -1.0]}
var registered_units: Dictionary = {}
var registered_buildings: Dictionary = {}
var ending: String = "time limit"
var result_path: String
var first_loss_army_trained: Array[int] = [-1, -1]
var last_snapshot_time: float = -20.0
var duration_seconds: float = 1200.0
var worker_loss_at: float = -1.0
var worker_survivors: int = 3
var worker_loss_record: Dictionary = {}
var worker_loss_trained_before: int = -1
var workers_produced_after_loss: int = 0
var first_paid_worker_replacement_at: float = -1.0
var order_decisions: Array[Dictionary] = []
var last_decisions: Array[String] = ["", ""]
var registered_combat_units: Dictionary = {}
var landed_hits_by_role: Array[Dictionary] = [{}, {}]
var counter_hits_by_role: Array[Dictionary] = [{}, {}]
var first_landed_role_hit_at: Array[Dictionary] = [{}, {}]
var landed_hit_examples: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_difficulty = 1
	GameManager.selected_population_limit = 30
	GameManager.selected_map_seed = 424242
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--pop="):
			GameManager.selected_population_limit = int(argument.trim_prefix("--pop="))
		if argument.begins_with("--seed="):
			GameManager.selected_map_seed = int(argument.trim_prefix("--seed="))
		if argument.begins_with("--difficulty="):
			GameManager.selected_difficulty = int(argument.trim_prefix("--difficulty="))
	result_path = "res://output/aoe-mobile-rts/ai/paid-%d-%d-%d.json" % [GameManager.selected_population_limit, GameManager.selected_map_seed, GameManager.selected_difficulty]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--duration="):
			duration_seconds = float(argument.trim_prefix("--duration="))
		elif argument.begins_with("--worker-loss-at="):
			worker_loss_at = float(argument.trim_prefix("--worker-loss-at="))
		elif argument.begins_with("--worker-survivors="):
			worker_survivors = maxi(1, int(argument.trim_prefix("--worker-survivors=")))
		elif argument.begins_with("--output="):
			result_path = argument.trim_prefix("--output=")
	match_scene = load("res://scenes/main/main.tscn").instantiate()
	add_child(match_scene)
	stats["runtime_source_hashes"] = _get_runtime_source_hashes()
	for frame: int in range(900):
		if match_scene.get("_building_placement") != null:
			break
		await get_tree().process_frame
	human_bot = AIController.new()
	human_bot.player_id = 0
	human_bot.enemy_id = 1
	human_bot.difficulty = AIController.Difficulty.MEDIUM
	human_bot.game_map = match_scene.game_map
	human_bot.map_generator = match_scene.game_map.map_generator
	human_bot.pathfinding = match_scene.game_map.pathfinding
	match_scene.add_child(human_bot)
	human_bot.ai_wants_to_build.connect(func(building_type: int, tile_pos: Vector2i, _rebuild: bool): match_scene._on_placement_confirmed(building_type, match_scene.game_map.tile_to_world(tile_pos)))
	human_bot.ai_wants_to_train.connect(func(building: Node, unit_type: int): match_scene._on_train_unit_requested(building, unit_type))
	human_bot.ai_wants_to_age_up.connect(match_scene._on_age_up_requested)
	human_bot.ai_attack_launched.connect(_attack.bind(0))
	match_scene.ai_controller.ai_attack_launched.connect(_attack.bind(1))
	GameManager.game_over.connect(func(_winner: int): ending = "game over")
	stats["initial_population_limits"] = [GameManager.get_player_population_limit(0), GameManager.get_player_population_limit(1)]
	stats["initial_resources"] = [ResourceManager.get_all_resources(0).duplicate(), ResourceManager.get_all_resources(1).duplicate()]
	stats["first_contact"] = -1.0
	stats["first_loss"] = [-1.0, -1.0]
	stats["army_types_seen"] = [{}, {}]
	stats["first_role_time"] = [{}, {}]
	stats["peak_army_by_type"] = [{}, {}]
	stats["snapshots"] = []
	_register_human_entities()
	var spawn: Vector2i = match_scene.game_map.map_generator.spawn_positions[0]
	human_bot.start_ai(spawn, match_scene.game_map.tile_to_world(spawn))
	while GameManager.current_state == GameManager.GameState.PLAYING and GameManager.game_time < duration_seconds:
		_register_human_entities()
		_register_combat_observers()
		_measure()
		_apply_worker_losses()
		await get_tree().process_frame
	stats["time"] = GameManager.game_time
	stats["end"] = ending
	stats["population_limit"] = GameManager.get_match_population_limit()
	stats["seed"] = GameManager.selected_map_seed
	stats["ages"] = [GameManager.get_player_age(0), GameManager.get_player_age(1)]
	stats["age_times"] = match_scene.get("_age_reached_at").duplicate(true)
	stats["resources"] = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	stats["difficulty"] = GameManager.selected_difficulty
	stats["summary"] = match_scene.get("match_summary_diagnostics")
	stats["victory_reason"] = match_scene.get("_victory_reason") if ending == "game over" else "unresolved at %ds" % int(duration_seconds)
	stats["live_stats"] = match_scene.get("_stats").duplicate(true)
	stats["army_produced_after_first_loss"] = [0, 0]
	for player_id: int in [0, 1]:
		if first_loss_army_trained[player_id] >= 0:
			stats["army_produced_after_first_loss"][player_id] = int(stats["live_stats"][player_id]["army_trained"]) - first_loss_army_trained[player_id]
	stats["economic_bonus_active"] = match_scene.get("balance_ai_economic_bonus_active")
	stats["worker_attrition"] = worker_loss_record
	stats["paid_workers_after_explicit_loss"] = workers_produced_after_loss
	stats["first_paid_worker_replacement_at"] = first_paid_worker_replacement_at
	stats["decision_changes"] = order_decisions
	stats["landed_hits_by_role"] = landed_hits_by_role
	stats["counter_hits_by_role"] = counter_hits_by_role
	stats["first_landed_role_hit_at"] = first_landed_role_hit_at
	stats["landed_hit_examples"] = landed_hit_examples
	stats["human_policy"] = "Medium AI using normal human construction/training/age transactions; automated, not hands-on"
	stats["simulation"] = {"physics_ticks_per_second": Engine.physics_ticks_per_second, "time_scale": Engine.time_scale, "map_width": MapData.MAP_WIDTH, "map_height": MapData.MAP_HEIGHT}

	var file := FileAccess.open(result_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(stats, "\t"))
	var compact_summary: Dictionary = stats.duplicate()
	compact_summary.erase("snapshots")
	compact_summary.erase("decision_changes")
	print("[PAID_COMPACT_MATCH] ", JSON.stringify(compact_summary))
	Engine.time_scale = 1.0
	match_scene.free()
	get_tree().quit()

func _register_human_entities() -> void:
	for unit: Node in match_scene._player_units[0]:
		if is_instance_valid(unit) and not registered_units.has(unit.get_instance_id()):
			registered_units[unit.get_instance_id()] = true
			human_bot.register_unit(unit)
	for building: Node in match_scene._player_buildings[0]:
		if is_instance_valid(building) and not registered_buildings.has(building.get_instance_id()):
			registered_buildings[building.get_instance_id()] = true
			human_bot.register_building(building)


func _register_combat_observers() -> void:
	for pid: int in [0, 1]:
		for unit: UnitBase in match_scene._player_units[pid]:
			if not is_instance_valid(unit) or registered_combat_units.has(unit.get_instance_id()):
				continue
			registered_combat_units[unit.get_instance_id()] = true
			unit.attack_landed.connect(_on_attack_landed)


func _on_attack_landed(attacker: UnitBase, defender: UnitBase, hp_loss: float, counter_bonus: float) -> void:
	# Combat emits only after a resolved hit actually reduces HP. This records
	# paid cavalry's own hits rather than inferring them from presence or losses.
	if hp_loss <= 0.0:
		return
	var pid: int = attacker.player_owner
	var role: String = str(attacker.unit_type)
	landed_hits_by_role[pid][role] = int(landed_hits_by_role[pid].get(role, 0)) + 1
	if not first_landed_role_hit_at[pid].has(role):
		first_landed_role_hit_at[pid][role] = GameManager.game_time
	if counter_bonus > 1.0:
		counter_hits_by_role[pid][role] = int(counter_hits_by_role[pid].get(role, 0)) + 1
	if int(landed_hits_by_role[pid][role]) <= 2 or (counter_bonus > 1.0 and int(counter_hits_by_role[pid][role]) <= 3):
		landed_hit_examples.append({"time": GameManager.game_time, "player": pid, "role": attacker.unit_type, "target_role": defender.unit_type, "hp_loss": hp_loss, "counter_bonus": counter_bonus, "target_remaining_hp": maxf(0.0, defender.hp)})

func _measure() -> void:
	if GameManager.game_time - last_snapshot_time >= 20.0:
		last_snapshot_time = GameManager.game_time
		var sample: Dictionary = {"time": GameManager.game_time, "players": []}
		for pid: int in [0, 1]:
			var unit_states: Dictionary = {}
			var worker_resources: Dictionary = {}
			var worker_tasks: Dictionary = {}
			var army_types: Dictionary = {}
			var building_counts: Dictionary = {}
			var farm_stock: int = 0
			for unit in match_scene._player_units[pid]:
				if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
					continue
				if not (unit is Villager):
					army_types[str(unit.unit_type)] = int(army_types.get(str(unit.unit_type), 0)) + 1
					continue
				unit_states[str(unit.current_state)] = int(unit_states.get(str(unit.current_state), 0)) + 1
				worker_resources[str(unit.carried_resource_type)] = int(worker_resources.get(str(unit.carried_resource_type), 0)) + 1
				if unit.has_method("get_economy_task"):
					var task: String = str(unit.call("get_economy_task"))
					worker_tasks[task] = int(worker_tasks.get(task, 0)) + 1
			for building in match_scene._player_buildings[pid]:
				if not is_instance_valid(building):
					continue
				building_counts[str(building.building_type)] = int(building_counts.get(str(building.building_type), 0)) + 1
				if building.building_type == BuildingData.BuildingType.FARM:
					farm_stock += int(building.farm_remaining)
			var controller: AIController = human_bot if pid == 0 else match_scene.ai_controller
			sample["players"].append({"units_trained": match_scene.get("_stats")[pid]["units_trained"], "army_trained": match_scene.get("_stats")[pid]["army_trained"], "army_types": army_types, "resources": ResourceManager.get_all_resources(pid).duplicate(), "worker_states": unit_states, "worker_resources": worker_resources, "worker_tasks": worker_tasks, "building_counts": building_counts, "farm_stock": farm_stock, "strategy": controller.get_strategy_snapshot(), "age": GameManager.get_player_age(pid)})
		stats["snapshots"].append(sample)
	for player_id: int in [0, 1]:
		var controller: AIController = human_bot if player_id == 0 else match_scene.ai_controller
		var decision: String = str(controller.get("_last_strategy_decision"))
		if decision != last_decisions[player_id]:
			last_decisions[player_id] = decision
			order_decisions.append({"time": GameManager.game_time, "player": player_id, "decision": decision})
		var workers: int = 0
		var troops: int = 0
		var kills: int = 0
		var frame_army_types: Dictionary = {}
		for unit: UnitBase in match_scene._player_units[player_id]:
			if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
				workers += int(unit.unit_type == UnitData.UnitType.VILLAGER)
				troops += int(unit.unit_type != UnitData.UnitType.VILLAGER)
				kills += unit.kills
				if unit.unit_type != UnitData.UnitType.VILLAGER:
					var key: String = str(unit.unit_type)
					stats["army_types_seen"][player_id][key] = true
					if not stats["first_role_time"][player_id].has(key):
						stats["first_role_time"][player_id][key] = GameManager.game_time
					frame_army_types[key] = int(frame_army_types.get(key, 0)) + 1
				if stats["first_contact"] < 0.0 and unit.hp < unit.max_hp:
					stats["first_contact"] = GameManager.game_time
		var player_stats: Dictionary = match_scene.get("_stats")[player_id]
		if int(player_stats["units_lost"]) > 0 and stats["first_loss"][player_id] < 0.0:
			stats["first_loss"][player_id] = GameManager.game_time
			first_loss_army_trained[player_id] = int(player_stats["army_trained"])
		for key: String in frame_army_types:
			stats["peak_army_by_type"][player_id][key] = maxi(int(stats["peak_army_by_type"][player_id].get(key, 0)), int(frame_army_types[key]))
		stats.peak_workers[player_id] = maxi(stats.peak_workers[player_id], workers)
		stats.peak_troops[player_id] = maxi(stats.peak_troops[player_id], troops)
		var committed_workers: int = workers + int(controller.call("_count_queued_unit", UnitData.UnitType.VILLAGER))
		var committed_fighters: int = troops - int(frame_army_types.get(str(UnitData.UnitType.SCOUT), 0)) + int(controller.call("_count_queued_military_units")) - int(controller.call("_count_queued_unit", UnitData.UnitType.SCOUT))
		stats.peak_committed_workers[player_id] = maxi(stats.peak_committed_workers[player_id], committed_workers)
		stats.peak_committed_fighters[player_id] = maxi(stats.peak_committed_fighters[player_id], committed_fighters)
		stats.peak_population[player_id] = maxi(stats.peak_population[player_id], GameManager.get_committed_population(player_id))
		stats.kills[player_id] = maxi(stats.kills[player_id], kills)

func _attack(_units: Array, _target: Vector2, player_id: int) -> void:
	stats.attacks[player_id] += 1
	if stats.first_attack[player_id] < 0.0:
		stats.first_attack[player_id] = GameManager.game_time


func _apply_worker_losses() -> void:
	if worker_loss_at < 0.0:
		return
	var player_stats: Dictionary = match_scene.get("_stats")[1]
	if not worker_loss_record.is_empty():
		workers_produced_after_loss = int(player_stats["units_trained"]) - int(player_stats["army_trained"]) - worker_loss_trained_before
		if workers_produced_after_loss > 0 and first_paid_worker_replacement_at < 0.0:
			first_paid_worker_replacement_at = GameManager.game_time
		return
	if GameManager.game_time < worker_loss_at:
		return
	var workers: Array = []
	for unit in match_scene._player_units[1]:
		if is_instance_valid(unit) and unit is Villager and unit.current_state != UnitBase.State.DEAD:
			workers.append(unit)
	var loss_count: int = maxi(0, workers.size() - worker_survivors)
	worker_loss_record = {"time": GameManager.game_time, "workers_before": workers.size(), "explicit_worker_losses": loss_count, "survivors": workers.size() - loss_count, "queued_workers_before": match_scene.ai_controller.call("_count_queued_unit", UnitData.UnitType.VILLAGER), "resources_before": ResourceManager.get_all_resources(1).duplicate(), "resources_granted": 0, "method": "explicit take_damage on existing paid workers; recovery remains normal queues and gathering"}
	worker_loss_trained_before = int(player_stats["units_trained"]) - int(player_stats["army_trained"])
	for index: int in range(loss_count):
		workers[index].take_damage(workers[index].hp + 100.0)


func _get_runtime_source_hashes() -> Dictionary:
	# Cached Script resources expose the source actually loaded in this process,
	# even if another collaborator edits the file while the match is running.
	var hashes: Dictionary = {}
	for path: String in ["scripts/ai/ai_controller.gd", "scripts/data/unit_data.gd", "scripts/data/building_data.gd", "scripts/data/skirmish_data.gd", "scripts/buildings/building_base.gd", "scripts/units/unit_base.gd", "scripts/units/combat.gd", "scripts/units/villager.gd", "scripts/main/main.gd", "scripts/ui/hud.gd", "scripts/map/map_data.gd", "scripts/map/map_generator.gd", "scripts/map/game_map.gd", "scripts/map/resource_node.gd", "scripts/map/pathfinding.gd", "scripts/managers/fog_manager.gd", "scripts/managers/selection_manager.gd", "scripts/managers/game_manager.gd", "scripts/managers/resource_manager.gd", "tools/probe_ai_compact_paid_match.gd"]:
		var script: Script = load("res://" + path) as Script
		hashes[path] = script.get_source_code().sha256_text()
	return hashes
