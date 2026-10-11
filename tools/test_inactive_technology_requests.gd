extends SceneTree
## Delayed match requests cannot spend after pause or game-over.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	var rm: Node = root.get_node("ResourceManager")
	root.get_node("AudioManager").call("set_all_enabled", false)
	gm.set("guided_opening_enabled", false)
	gm.set("selected_map_seed", 42)
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var initialized := false
	for _frame in range(900):
		await process_frame
		var units: Array = main.get("_player_units")
		if units.size() == 2 and units[1].size() >= 4:
			initialized = true
			break
	_expect(initialized, "real match initializes")
	if not initialized:
		main.free()
		quit(1)
		return
	main.set_process(false)
	var ai: Node = main.get("ai_controller")
	(ai.get("_decision_timer") as Timer).stop()
	ai.set_process(false)
	for unit: Node in get_nodes_in_group("units"):
		unit.set_process(false)
		if unit.has_method("command_stop"):
			unit.call("command_stop")
	for player_id: int in [0, 1]:
		rm.call("initialize_player", player_id, {"food": 10000, "wood": 10000, "gold": 10000})
	var tile: Vector2i = ai.call("_find_build_location", BuildingData.BuildingType.BLACKSMITH)
	_expect(tile != Vector2i(-1, -1), "fixture finds legal forge position")
	_expect(rm.call("try_spend", 0, BuildingData.get_building_cost(BuildingData.BuildingType.BLACKSMITH)), "forge is paid")
	var forge: Node2D = main.call("_spawn_building", BuildingData.BuildingType.BLACKSMITH, 0, tile) as Node2D
	forge.call("start_construction")
	var units: Array = main.get("_player_units")
	var builder: Node2D = units[0][0] as Node2D
	builder.global_position = forge.global_position + Vector2(28.0, 0.0)
	builder.call("command_build", forge)
	builder.call("_process_building", float(forge.get("build_time")))
	_expect(int(forge.get("state")) == 2, "real worker completes paid forge")
	forge.set_process(false)
	for inactive_state: int in [3, 4]:
		gm.call("set_state", inactive_state)
		var before: Dictionary = _snapshot(gm, rm)
		main.call("_on_research_requested", forge, "forging" if inactive_state == 3 else "scale_mail")
		main.call("_on_age_up_requested")
		main.call("_on_ai_wants_to_age_up")
		var after: Dictionary = _snapshot(gm, rm)
		print("Inactive state %d: before=%s after=%s" % [inactive_state, before, after])
		_expect(before == after, "delayed human research and both age requests preserve state %d" % inactive_state)
		gm.call("set_state", 2)
	paused = false
	main.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] inactive_technology_requests: paid completed forge and both age request paths reject pause/game-over without spending or upgrades")
		quit(0)
	else:
		quit(1)


func _snapshot(gm: Node, rm: Node) -> Dictionary:
	return {
		"resources0": rm.call("get_all_resources", 0), "resources1": rm.call("get_all_resources", 1),
		"age0": gm.call("get_player_age", 0), "age1": gm.call("get_player_age", 1),
		"upgrades": (gm.get("player_upgrades") as Dictionary).duplicate(true),
		"research": (gm.get("researched_upgrades") as Dictionary).duplicate(true),
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[FAIL] inactive_technology_requests: " + message)
