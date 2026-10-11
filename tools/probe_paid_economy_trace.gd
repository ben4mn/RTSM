extends "res://tools/probe_ai_compact_paid_match.gd"
## Observation only. Accepted queue events and newly registered foundations are
## receipts; bank debits include every transaction but do not infer its cause.
## All-stock counts are audit-only and never feed either controller's decisions.

var _trace_started: bool = false
var _trace_buildings: Dictionary = {}
var _trace_queues: Dictionary = {}
var _trace_bank: Array[Dictionary] = [{}, {}]
var _trace_last_sample: float = -1.0
var _trace_last_time: float = 0.0
var _trace_gate_seconds: Array[Dictionary] = [{}, {}]
var _trace_gates: Array[String] = ["", ""]
var _trace_pending: Array[String] = ["", ""]


func _register_human_entities() -> void:
	super._register_human_entities()
	if not _trace_started:
		_trace_started = true
		stats["accepted_economy_purchases"] = []
		stats["economy_bank_debits"] = []
		stats["economy_gate_changes"] = []
		stats["economy_pending_changes"] = []
		stats["economy_trace_samples"] = []
		stats["siege_gate_seconds"] = _trace_gate_seconds
		stats["economy_trace_scope"] = "Observation-only paid match. Foundations are observed within one process frame, queues through accepted unit_queued events. First failed gate sampled once per game second; seconds are sample estimates and may mask simultaneous blockers. Foundation bank_after is observed within one frame, not instant preflight. Accepted costs exclude subsequent refunds/cancellations. All natural stock is audit-only, current-visible stock is separately reported. No decisions or resources changed."
		stats["economy_trace_sha256"] = (load("res://tools/probe_paid_economy_trace.gd") as Script).get_source_code().sha256_text()
		for pid: int in [0, 1]:
			_trace_bank[pid] = ResourceManager.get_all_resources(pid).duplicate()
		ResourceManager.resources_changed.connect(_observe_bank)
		GameManager.age_advanced.connect(_observe_age)
		GameManager.research_completed.connect(_observe_research)
	for pid: int in [0, 1]:
		for building: BuildingBase in match_scene._player_buildings[pid]:
			if not is_instance_valid(building):
				continue
			var key: int = building.get_instance_id()
			if not _trace_buildings.has(key):
				_trace_buildings[key] = true
				if building.state == BuildingBase.State.CONSTRUCTING:
					stats["accepted_economy_purchases"].append({"time": GameManager.game_time, "player": pid, "kind": "foundation", "type": building.building_type, "name": building.building_name, "cost": BuildingData.get_building_cost(building.building_type), "bank_after": ResourceManager.get_all_resources(pid).duplicate()})
			var queue: Node = building.get_production_queue()
			if queue != null and not _trace_queues.has(key):
				_trace_queues[key] = true
				queue.unit_queued.connect(_observe_queue.bind(pid))


func _observe_bank(pid: int, _type: String, _amount: int) -> void:
	var current: Dictionary = ResourceManager.get_all_resources(pid).duplicate()
	var debits: Dictionary = {}
	for resource_type: String in ["food", "wood", "gold"]:
		var difference: int = int(_trace_bank[pid].get(resource_type, 0)) - int(current.get(resource_type, 0))
		if difference > 0:
			debits[resource_type] = difference
	if not debits.is_empty():
		stats["economy_bank_debits"].append({"time": GameManager.game_time, "player": pid, "debits": debits, "bank_after": current})
	_trace_bank[pid] = current


func _observe_queue(unit_type: int, pid: int) -> void:
	stats["accepted_economy_purchases"].append({"time": GameManager.game_time, "player": pid, "kind": "unit_queue", "type": unit_type, "name": UnitData.get_unit_name(unit_type), "cost": UnitData.get_unit_cost(unit_type), "bank_after": ResourceManager.get_all_resources(pid).duplicate()})


func _observe_age(pid: int, age: int) -> void:
	stats["accepted_economy_purchases"].append({"time": GameManager.game_time, "player": pid, "kind": "age", "type": age, "cost": SkirmishData.get_age_up_cost(age, GameManager.get_player_population_limit(pid)), "bank_after": ResourceManager.get_all_resources(pid).duplicate()})


func _observe_research(pid: int, tech: String) -> void:
	stats["accepted_economy_purchases"].append({"time": GameManager.game_time, "player": pid, "kind": "research", "name": tech, "bank_after": ResourceManager.get_all_resources(pid).duplicate()})


func _measure() -> void:
	super._measure()
	if GameManager.game_time - _trace_last_sample < 1.0:
		return
	_trace_last_sample = GameManager.game_time
	var elapsed: float = maxf(0.0, GameManager.game_time - _trace_last_time)
	_trace_last_time = GameManager.game_time
	for pid: int in [0, 1]:
		var controller: AIController = human_bot if pid == 0 else match_scene.ai_controller
		var gate: String = _siege_gate(controller, pid)
		_trace_gate_seconds[pid][gate] = float(_trace_gate_seconds[pid].get(gate, 0.0)) + elapsed
		if gate != _trace_gates[pid]:
			_trace_gates[pid] = gate
			stats["economy_gate_changes"].append({"time": GameManager.game_time, "player": pid, "gate": gate, "bank": ResourceManager.get_all_resources(pid).duplicate()})
		var pending: String = str(controller.get("_pending_economy_rebalance_type"))
		if pending != _trace_pending[pid]:
			stats["economy_pending_changes"].append({"time": GameManager.game_time, "player": pid, "before": _trace_pending[pid], "after": pending, "deadline": controller.get("_pending_economy_rebalance_deadline"), "note": "clear may be fulfilled or expired; compare assignments/deadline"})
			_trace_pending[pid] = pending
	if stats["economy_trace_samples"].is_empty() or GameManager.game_time - float(stats["economy_trace_samples"].back()["time"]) >= 20.0:
		var sample: Dictionary = {"time": GameManager.game_time, "players": []}
		for pid: int in [0, 1]:
			var controller: AIController = human_bot if pid == 0 else match_scene.ai_controller
			var all_stock: Dictionary = {"food": 0, "wood": 0, "gold": 0}
			var visible_stock: Dictionary = all_stock.duplicate()
			for node: Node2D in match_scene.game_map.resource_nodes.values():
				if not is_instance_valid(node):
					continue
				var resource_type: String = str(node.get_resource_type())
				all_stock[resource_type] += int(node.get("remaining"))
				if match_scene.game_map.is_resource_target_visible_to_player(node, pid):
					visible_stock[resource_type] += int(node.get("remaining"))
			var bank: Dictionary = ResourceManager.get_all_resources(pid).duplicate()
			var workers: Array = controller.call("_get_villagers")
			sample["players"].append({"bank": bank, "workers": workers.size(), "assignment_counts": controller.call("_get_economy_work_counts"), "worker_targets": controller.call("_get_economy_worker_targets", workers.size(), bank), "all_natural_stock_audit_only": all_stock, "current_visible_natural_stock": visible_stock, "siege_gate": _trace_gates[pid], "siege_intent": controller.call("_needs_compact_siege_purchase"), "workshop_count": controller.get("_siege_workshop_count"), "pressure": controller.get("_is_under_pressure"), "pending_rebalance": _trace_pending[pid], "last_action": controller.get("_last_economy_action")})
		stats["economy_trace_samples"].append(sample)


func _siege_gate(controller: AIController, pid: int) -> String:
	if GameManager.get_player_age(pid) < 3:
		return "before_castle"
	if bool(controller.get("_is_under_pressure")):
		return "home_pressure"
	if bool(controller.call("_needs_compact_worker_recovery")):
		return "worker_recovery"
	if int(controller.call("_get_compact_missing_role_building")) >= 0:
		return "missing_core_producer"
	if (controller.call("_get_fighting_units") as Array).size() < int(controller.call("_get_attack_threshold")):
		return "escorts_below_threshold"
	if int(controller.call("_count_queued_unit", UnitData.UnitType.SIEGE)) > 0:
		return "siege_queued"
	for unit: UnitBase in controller.call("_get_fighting_units"):
		if unit.unit_type == UnitData.UnitType.SIEGE:
			return "siege_alive"
	if int(controller.get("_siege_workshop_count")) == 0:
		return "workshop_affordable" if ResourceManager.can_afford(pid, BuildingData.get_building_cost(BuildingData.BuildingType.SIEGE_WORKSHOP)) else "saving_workshop"
	if controller.call("_find_trainable_building_of_type", BuildingData.BuildingType.SIEGE_WORKSHOP) == null:
		return "workshop_unavailable"
	if not GameManager.can_reserve_population(pid, 3):
		return "three_pop_unavailable"
	return "engine_affordable" if ResourceManager.can_afford(pid, UnitData.get_unit_cost(UnitData.UnitType.SIEGE)) else "saving_engine"
