extends SceneTree
## Paid, real-match regression for shared research and supported progression.

var _failures: Array[String] = []
var _main: Node
var _gm: Node
var _rm: Node
var _research_events: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_gm = root.get_node("GameManager")
	_rm = root.get_node("ResourceManager")
	_gm.connect("research_completed", func(player_id: int, research_id: String) -> void: _research_events.append("%d:%s" % [player_id, research_id]))
	root.get_node("AudioManager").call("set_all_enabled", false)
	_gm.set("guided_opening_enabled", false)
	_gm.set("selected_map_seed", 42)
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	var initialized := false
	for _frame in range(900):
		await process_frame
		var workers: Array = _main.get("_player_units")
		if workers.size() == 2 and workers[1].size() >= 4:
			initialized = true
			break
	_expect(initialized, "real match initializes both players")
	if not initialized:
		_finish()
		return
	_main.set_process(false)
	var ai: Node = _main.get("ai_controller")
	(ai.get("_decision_timer") as Timer).stop()
	ai.set_process(false)
	for candidate: Node in get_nodes_in_group("units"):
		candidate.set_process(false)
		if candidate.has_method("command_stop"):
			candidate.call("command_stop")
	for candidate: Node in get_nodes_in_group("buildings"):
		candidate.set_process(false)
	for player_id: int in [0, 1]:
		_rm.call("initialize_player", player_id, {"food": 2000, "wood": 2000, "gold": 2000})
		_gm.call("advance_age", player_id)
	ai.set("_saving_for_age_up", false)
	var human_forge: Node2D = _paid_blacksmith(0, ai)
	var ai_forge: Node2D = _paid_blacksmith(1, ai)
	_expect(human_forge != null and ai_forge != null, "paid foundations exist")
	if human_forge == null or ai_forge == null:
		_finish()
		return
	var human_before: Dictionary = _rm.call("get_all_resources", 0)
	var ai_before: Dictionary = _rm.call("get_all_resources", 1)
	_main.call("_on_research_requested", human_forge, "forging")
	ai.call("_update_building_counts")
	ai.call("_check_research")
	print("Foundation research: human=%s AI=%s; resources human=%s AI=%s" % [
		_gm.call("has_research", 0, "forging"), _gm.call("has_research", 1, "forging"),
		_rm.call("get_all_resources", 0), _rm.call("get_all_resources", 1)])
	_expect(not _gm.call("has_research", 0, "forging"), "human foundation cannot research")
	_expect(not _gm.call("has_research", 1, "forging"), "AI foundation cannot research")
	_expect(_rm.call("get_all_resources", 0) == human_before, "human foundation spends no research resources")
	_expect(_rm.call("get_all_resources", 1) == ai_before, "AI foundation spends no research resources")
	for player_id: int in [0, 1]:
		var forge: Node2D = human_forge if player_id == 0 else ai_forge
		var units: Array = _main.get("_player_units")
		var worker: Node2D = units[player_id][0] as Node2D
		worker.global_position = forge.global_position + Vector2(28.0, 0.0)
		worker.call("command_build", forge)
		worker.call("_process_building", float(forge.get("build_time")) * 0.5)
		_expect(int(forge.get("state")) == 1 and is_equal_approx(float(forge.get("build_progress")), 0.5), "player %d forge stays incomplete after half paid labor" % player_id)
		worker.call("_process_building", float(forge.get("build_time")) * 0.5)
		_expect(int(forge.get("state")) == 2, "player %d actual worker completes forge" % player_id)
		print("Paid forge %d: construction=%ss state=%s" % [player_id, worker.get("build_timer"), forge.get("state")])
	var reentry_results: Array[bool] = []
	var reentry := func(player_id: int, _resource: String, _amount: int) -> void:
		if player_id == 0:
			reentry_results.append(bool(_gm.call("try_research", 0, human_forge, "scale_mail")))
			reentry_results.append(bool(_gm.call("try_advance_age", 0)))
	_rm.connect("resources_changed", reentry)
	_main.call("_on_research_requested", human_forge, "forging")
	_rm.disconnect("resources_changed", reentry)
	_expect(not reentry_results.is_empty() and not reentry_results.has(true), "spending signals cannot interleave another research or age purchase")
	ai.call("_check_research")
	for player_id: int in [0, 1]:
		_expect(_gm.call("has_research", player_id, "forging"), "player %d completed forge can research" % player_id)
		_expect(int(_gm.call("get_attack_bonus", player_id)) == 2, "player %d forging applies +2 exactly once" % player_id)
		var expected: Dictionary = human_before.duplicate() if player_id == 0 else ai_before.duplicate()
		expected["food"] -= 100
		expected["gold"] -= 50
		_expect(_rm.call("get_all_resources", player_id) == expected, "player %d forging spends exactly 100F/50G" % player_id)
	var duplicate_before: Dictionary = _snapshot(0)
	_main.call("_on_research_requested", human_forge, "forging")
	_expect(_snapshot(0) == duplicate_before, "duplicate human request is free of any mutation")
	_expect(not bool(_gm.call("try_research", 1, human_forge, "scale_mail")), "AI cannot buy from human forge")
	_expect(not bool(_gm.call("try_research", 0, ai_forge, "scale_mail")), "human cannot buy from AI forge")
	_expect(not bool(_gm.call("try_research", 0, human_forge, "invented_upgrade")), "unknown technology is rejected")
	var buildings: Array = _main.get("_player_buildings")
	_expect(not bool(_gm.call("try_research", 0, buildings[0][0], "scale_mail")), "Town Center cannot research Blacksmith upgrades")
	var resource_before: Dictionary = _rm.call("get_all_resources", 0)
	_rm.call("initialize_player", 0, {"food": 99, "gold": 50, "wood": 0})
	var unaffordable_before: Dictionary = _snapshot(0)
	_main.call("_on_research_requested", human_forge, "scale_mail")
	_expect(_snapshot(0) == unaffordable_before, "unaffordable research spends nothing and adds no effect")
	_rm.call("initialize_player", 0, resource_before)
	_main.call("_on_research_requested", human_forge, "scale_mail")
	ai.call("_check_research")
	for player_id: int in [0, 1]:
		_expect(int(_gm.call("get_armor_bonus", player_id)) == 1, "player %d scale mail applies same +1 armor" % player_id)
	await _exercise_villager_upgrades(human_forge)
	_expect(_research_events.size() == 6, "six accepted human/AI research purchases emit exactly six completion events")
	for event_id: String in ["0:forging", "1:forging", "0:scale_mail", "1:scale_mail", "0:wheelbarrow", "0:loom"]:
		_expect(_research_events.count(event_id) == 1, "research event %s emits exactly once" % event_id)
	_exercise_interrupted_purchase(ai_forge)
	_exercise_paid_age_transactions()
	for player_id: int in [0, 1]:
		var unsupported_cost: Dictionary = _gm.call("get_age_up_cost", player_id, 4)
		var advanced: bool = _gm.call("advance_age", player_id)
		print("Castle boundary player %d: next cost=%s advancement=%s resulting age=%s" % [player_id, unsupported_cost, advanced, _gm.call("get_player_age", player_id)])
		_expect(not advanced, "unsupported advancement is rejected for player %d" % player_id)
		_expect(int(_gm.call("get_player_age", player_id)) == 3, "supported endgame remains Castle for player %d" % player_id)
	_finish()


func _exercise_villager_upgrades(forge: Node2D) -> void:
	var units: Array = _main.get("_player_units")
	var worker: Node = units[0][0]
	var previous_gather: float = float(worker.get("gather_rate"))
	var previous_hp: int = int(worker.get("max_hp"))
	_main.call("_on_research_requested", forge, "wheelbarrow")
	_main.call("_on_research_requested", forge, "loom")
	_expect(is_equal_approx(float(worker.get("gather_rate")), previous_gather + UnitData.WHEELBARROW_GATHER_BONUS), "existing worker receives Wheelbarrow once")
	_expect(int(worker.get("max_hp")) == previous_hp + 15, "existing worker receives Loom once")
	# A paid replacement is produced through the real queue, not debug spawned.
	_gm.call("increase_population_cap", 0, 10)
	var buildings: Array = _main.get("_player_buildings")
	var town_center: Node = buildings[0][0]
	var queue: Node = town_center.call("get_production_queue")
	queue.set("auto_queue_enabled", false)
	queue.call("cancel_all")
	var before_count: int = units[0].size()
	_expect(bool(queue.call("enqueue_unit", UnitData.UnitType.VILLAGER)), "replacement worker uses paid production")
	queue.call("advance", float(queue.get("current_train_time")) + 0.1)
	await process_frame
	units = _main.get("_player_units")
	_expect(units[0].size() == before_count + 1, "paid replacement worker is actually spawned")
	if units[0].size() == before_count + 1:
		var replacement: Node = units[0][-1]
		replacement.set_process(false)
		_expect(is_equal_approx(float(replacement.get("gather_rate")), float(worker.get("gather_rate"))), "paid replacement inherits same gathering upgrade")
		_expect(int(replacement.get("max_hp")) == int(worker.get("max_hp")), "paid replacement inherits same HP upgrade")
	var before: Dictionary = _snapshot(0)
	_main.call("_on_research_requested", forge, "wheelbarrow")
	_main.call("_on_research_requested", forge, "loom")
	_expect(_snapshot(0) == before, "economic research duplicates neither spend nor stack bonuses")
	print("Research effects: attack=2 armor=1; worker gather=%s HP=%s; paid replacement=%s" % [worker.get("gather_rate"), worker.get("max_hp"), units[0].size() - before_count])


func _exercise_paid_age_transactions() -> void:
	for player_id: int in [0, 1]:
		var cost: Dictionary = _gm.call("get_age_up_cost", player_id, 3)
		_rm.call("initialize_player", player_id, {"food": int(cost["food"]) - 1, "gold": int(cost["gold"]), "wood": 0})
		var before: Dictionary = _snapshot(player_id)
		_expect(not bool(_gm.call("try_advance_age", player_id)), "player %d cannot advance below paid costs" % player_id)
		_expect(_snapshot(player_id) == before, "player %d failed age purchase changes nothing" % player_id)
		_rm.call("add_resource", player_id, "food", 1)
		var reentry_results: Array[bool] = []
		var reentry := func(changed_player: int, _resource: String, _amount: int) -> void:
			if changed_player == player_id:
				reentry_results.append(bool(_gm.call("try_advance_age", player_id)))
		_rm.connect("resources_changed", reentry)
		_expect(bool(_gm.call("try_advance_age", player_id)), "player %d exact-cost Castle purchase succeeds" % player_id)
		_rm.disconnect("resources_changed", reentry)
		_expect(not reentry_results.is_empty() and not reentry_results.has(true), "player %d resource notification cannot buy twice" % player_id)
		_expect(int(_gm.call("get_player_age", player_id)) == 3, "player %d paid purchase reaches Castle" % player_id)
		_expect((_rm.call("get_all_resources", player_id) as Dictionary) == {"food": 0, "wood": 0, "gold": 0}, "player %d Castle payment is exact" % player_id)
		var castle_before: Dictionary = _snapshot(player_id)
		_expect(not bool(_gm.call("try_advance_age", player_id)), "player %d cannot purchase unsupported tier" % player_id)
		_expect(_snapshot(player_id) == castle_before, "player %d final-age request changes nothing" % player_id)
		print("Paid Castle player %d: cost=%s remaining=%s" % [player_id, cost, _rm.call("get_all_resources", player_id)])


func _exercise_interrupted_purchase(forge: Node2D) -> void:
	var before: Dictionary = _snapshot(1)
	var interruption := func(player_id: int, _resource: String, _amount: int) -> void:
		if player_id == 1:
			_gm.call("set_state", 3)
	_rm.connect("resources_changed", interruption)
	_expect(not bool(_gm.call("try_research", 1, forge, "wheelbarrow")), "research cancelled by synchronous pause is rejected")
	_rm.disconnect("resources_changed", interruption)
	_expect(_snapshot(1) == before, "interrupted research refunds every resource and applies no effect")
	_gm.call("set_state", 2)
	_expect(_research_events.size() == 6, "interrupted research emits no completion")
	forge.set("hp", 0)
	_expect(not bool(_gm.call("try_research", 1, forge, "wheelbarrow")), "zero-HP building cannot research")
	forge.set("hp", forge.get("max_hp"))
	forge.set("state", 3)
	_expect(not bool(_gm.call("try_research", 1, forge, "wheelbarrow")), "destroyed building cannot research")
	forge.set("state", 2)
	_expect(_snapshot(1) == before, "dead-building requests leave all player values unchanged")


func _snapshot(player_id: int) -> Dictionary:
	return {
		"bank": _rm.call("get_all_resources", player_id), "age": _gm.call("get_player_age", player_id),
		"bonuses": (_gm.get("player_upgrades") as Dictionary)[player_id].duplicate(true),
		"research": (_gm.get("researched_upgrades") as Dictionary)[player_id].duplicate(),
	}


func _paid_blacksmith(player_id: int, ai: Node) -> Node2D:
	# Explicit funding is a synthetic fixture; both construction and research
	# still use their actual costs, nodes and request paths.
	var tile: Vector2i = ai.call("_find_build_location", BuildingData.BuildingType.BLACKSMITH)
	if tile == Vector2i(-1, -1):
		return null
	if not bool(_rm.call("try_spend", player_id, BuildingData.get_building_cost(BuildingData.BuildingType.BLACKSMITH))):
		return null
	var forge: Node2D = _main.call("_spawn_building", BuildingData.BuildingType.BLACKSMITH, player_id, tile) as Node2D
	forge.start_construction()
	forge.set_process(false)
	return forge


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[FAIL] shared_technology_rules: " + message)


func _finish() -> void:
	paused = false
	if is_instance_valid(_main):
		_main.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] shared_technology_rules: paid real-worker completion, shared research costs/effects, ownership/duplicates/reentrancy, upgraded paid replacement and Castle purchases")
		quit(0)
	else:
		quit(1)
