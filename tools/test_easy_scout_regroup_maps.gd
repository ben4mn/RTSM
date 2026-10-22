extends Node
## Real maps and naturally purchased AI units; only relocation/time/death are
## injected to isolate the inside-Sacred regroup transition. Not match pacing.
var failures: Array[String] = []
var receipts: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	for archetype: int in [0, 1, 2]:
		GameManager.selected_map_archetype = archetype
		GameManager.selected_map_seed = 101
		GameManager.selected_difficulty = 0
		GameManager.selected_population_limit = 30
		GameManager.guided_opening_enabled = false
		var main: Node = load("res://scenes/main/main.tscn").instantiate()
		add_child(main)
		for frame: int in range(900):
			if main.get("_building_placement") != null:
				break
			await get_tree().process_frame
		var ai: AIController = main.ai_controller
		Engine.time_scale = 4.0
		while GameManager.game_time < 180.0 and (ai._get_scouts().is_empty() or ai._get_fighting_units().is_empty()):
			await get_tree().process_frame
		Engine.time_scale = 1.0
		_expect(not ai._get_scouts().is_empty() and not ai._get_fighting_units().is_empty(), "%d ordinary paid opening supplies Scout and fighter" % archetype)
		if ai._get_scouts().is_empty() or ai._get_fighting_units().is_empty():
			main.free()
			continue
		ai._decision_timer.stop()
		ai.set_process(false)
		main.set_process(false)
		for unit: Node in get_tree().get_nodes_in_group("units"):
			unit.set_process(false)
		for building: Node in get_tree().get_nodes_in_group("buildings"):
			building.set_process(false)
		var scout: UnitBase = ai._get_scouts()[0]
		var fighter: UnitBase = ai._get_fighting_units()[0]
		var site: Node2D = main.game_map.sacred_site
		scout.command_stop()
		scout.global_position = site.global_position
		ai._game_time = 302.0
		ai._attack_wave_units = [fighter]
		fighter.take_damage(fighter.hp + 100.0)
		ai._check_scouting()
		var route_points: int = scout.path.size()
		_expect(route_points > 0, "%d actual navigation supplies an outbound escape" % archetype)
		ai._check_attack_or_defend()
		var first_clear_at: float = -1.0
		var legal_route: bool = true
		for frame: int in range(480):
			ai._game_time += 1.0 / 60.0
			scout._process(1.0 / 60.0)
			legal_route = legal_route and main.game_map.is_tile_walkable(main.game_map.world_to_tile(scout.global_position))
			if first_clear_at < 0.0 and scout.global_position.distance_to(site.global_position) > 224.0:
				first_clear_at = float(frame + 1) / 60.0
			if frame % 120 == 119:
				ai._check_scouting()
				ai._check_attack_or_defend()
		_expect(first_clear_at >= 0.0 and first_clear_at < 8.0, "%d capturing Scout physically exits well before regroup ends" % archetype)
		_expect(legal_route, "%d withdrawal stays on actual walkable terrain" % archetype)
		_expect(ai._last_strategy_decision == "learning_regroup", "%d real Scout withdrawal preserves fighter regroup" % archetype)
		receipts.append({"archetype": archetype, "seed": 101, "paid_opening_seconds": GameManager.game_time, "initial_path_points": route_points, "seconds_to_clear_capture_and_buffer": first_clear_at, "final_distance": scout.global_position.distance_to(site.global_position), "legal_route": legal_route, "ai_source": ai.get_script().get_source_code().sha256_text()})
		main.free()
	print("[EASY_SCOUT_REGROUP_MAPS] ", JSON.stringify({"receipts": receipts, "failures": failures}))
	for failure: String in failures:
		push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
