extends "res://tools/probe_ai_compact_paid_match.gd"
## Same ordinary-cost policy match, with owner civilization choices and explicit
## economic-investment receipts. No state, resources or outcomes are injected.

var civilization_choices: Array[int] = [0, 0]
var _investment_last_sample: float = -20.0
var _research_seen: Array[Dictionary] = [{}, {}]
var _camp_seen: Array[Dictionary] = [{}, {}]
var _research_events: Array[Dictionary] = []
var _camp_events: Array[Dictionary] = []
var _haul_samples: Array[Dictionary] = []
var _observer_cost: Dictionary = {}
var _observer_started_usec: int = 0


func _run() -> void:
	_observer_started_usec = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--civilization="):
			civilization_choices[0] = int(argument.trim_prefix("--civilization="))
		elif argument.begins_with("--opponent-civilization="):
			civilization_choices[1] = int(argument.trim_prefix("--opponent-civilization="))
	# Keep the observer usable on the frozen pre-civilization baseline too.
	for property: Dictionary in GameManager.get_property_list():
		if property.name == "selected_civilization":
			GameManager.set("selected_civilization", civilization_choices[0])
		elif property.name == "selected_opponent_civilization":
			GameManager.set("selected_opponent_civilization", civilization_choices[1])
	stats["civilization_choices"] = civilization_choices.duplicate()
	stats["economic_investments"] = {"research_events": _research_events, "camp_events": _camp_events, "haul_samples": _haul_samples}
	stats["observer_cost"] = _observer_cost
	await super._run()


func _measure() -> void:
	var started: int = Time.get_ticks_usec()
	super._measure()
	_record_observer_cost("base_measure", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	_measure_investments()
	_record_observer_cost("investment_measure", Time.get_ticks_usec() - started)
	_observer_cost["wall_elapsed_seconds"] = float(Time.get_ticks_usec() - _observer_started_usec) / 1000000.0
	_observer_cost["game_seconds"] = GameManager.game_time


func _register_human_entities() -> void:
	var started: int = Time.get_ticks_usec()
	super._register_human_entities()
	_record_observer_cost("human_registration", Time.get_ticks_usec() - started)


func _register_combat_observers() -> void:
	var started: int = Time.get_ticks_usec()
	super._register_combat_observers()
	_record_observer_cost("combat_registration", Time.get_ticks_usec() - started)


func _record_observer_cost(section: String, elapsed_usec: int) -> void:
	var receipt: Dictionary = _observer_cost.get(section, {"calls": 0, "total_usec": 0, "max_usec": 0})
	receipt.calls += 1
	receipt.total_usec += elapsed_usec
	receipt.max_usec = maxi(receipt.max_usec, elapsed_usec)
	_observer_cost[section] = receipt


func _measure_investments() -> void:
	if not stats.has("actual_civilizations"):
		stats["actual_civilizations"] = [int(GameManager.call("get_player_civilization", 0)), int(GameManager.call("get_player_civilization", 1))] if GameManager.has_method("get_player_civilization") else [0, 0]
	for owner: int in [0, 1]:
		for research_id: String in GameManager.researched_upgrades.get(owner, []):
			if not _research_seen[owner].has(research_id):
				_research_seen[owner][research_id] = true
				_research_events.append({"owner": owner, "research": research_id, "time": GameManager.game_time})
				print("[INVESTMENT_RESEARCH] ", JSON.stringify(_research_events.back()))
		for building: BuildingBase in match_scene._player_buildings[owner]:
			if not is_instance_valid(building) or building.building_type != BuildingData.BuildingType.RESOURCE_CAMP or _camp_seen[owner].has(building.get_instance_id()):
				continue
			_camp_seen[owner][building.get_instance_id()] = true
			_camp_events.append({"owner": owner, "time": GameManager.game_time, "position": [building.position.x, building.position.y], "paid_camp_number": _camp_seen[owner].size()})
			print("[INVESTMENT_CAMP] ", JSON.stringify(_camp_events.back()))
	if GameManager.game_time - _investment_last_sample < 20.0:
		return
	_investment_last_sample = GameManager.game_time
	for owner: int in [0, 1]:
		var distances: Array[float] = []
		for worker: UnitBase in match_scene._player_units[owner]:
			if not is_instance_valid(worker) or not (worker is Villager):
				continue
			if not (worker as Villager).has_active_gather_order():
				continue
			var source: Node2D = (worker as Villager).gather_target
			if not is_instance_valid(source) or not (source is ResourceNode):
				continue
			var distance: float = INF
			for building: BuildingBase in match_scene._player_buildings[owner]:
				if is_instance_valid(building) and building.state == BuildingBase.State.ACTIVE and building.is_drop_off_point((source as ResourceNode).resource_type):
					distance = minf(distance, source.global_position.distance_to(building.global_position))
			if not is_inf(distance):
				distances.append(distance)
		var remote_workers: int = 0
		var sum: float = 0.0
		for distance: float in distances:
			sum += distance
			if distance >= 300.0:
				remote_workers += 1
		_haul_samples.append({"owner": owner, "time": GameManager.game_time, "natural_resource_workers": distances.size(), "remote_workers": remote_workers, "mean_haul_world_distance": sum / maxf(1.0, float(distances.size()))})


func _get_runtime_source_hashes() -> Dictionary:
	var hashes: Dictionary = super._get_runtime_source_hashes()
	hashes["tools/probe_civilization_paid_match.gd"] = get_script().get_source_code().sha256_text()
	return hashes
