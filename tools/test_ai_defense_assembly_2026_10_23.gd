extends "res://tools/test_ai_assembly_2026_10_23.gd"
## Reuse canonical Main/AI fixtures and movement guards; synthetic mixed roster.

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.RIVER_CROSSINGS
	GameManager.selected_difficulty = AIController.Difficulty.EASY
	GameManager.selected_population_limit = 30
	match_scene = load("res://scenes/main/main.tscn").instantiate()
	add_child(match_scene)
	for frame: int in 900:
		if GameManager.current_state == GameManager.GameState.PLAYING and match_scene.get("_building_placement") != null: break
		await get_tree().process_frame
	map = match_scene.get("game_map")
	ai = match_scene.get("ai_controller")
	ai._decision_timer.stop()
	match_scene.process_mode = Node.PROCESS_MODE_DISABLED
	var soldiers: Array[UnitBase] = []
	for index: int in 5:
		soldiers.append(_unit("infantry" if index < 3 else "archer", Vector2i(59 + index, 14)))
	var anchor: Vector2 = map.tile_to_world(Vector2i(56, 12))
	ai._last_defense_threat_position = anchor
	ai._game_time = 100.0
	ai._last_defense_threat_time = 100.0
	for unit: UnitBase in soldiers: unit.command_attack_move(anchor)
	soldiers[0].command_move(anchor)
	ai._check_attack_or_defend()
	_expect(ai._last_strategy_decision == "search_last_base_threat", "normal decision reaches the remembered-defense branch")
	var goals: Dictionary = _positions(soldiers, true)
	_expect(goals.minimum_pair >= 28.0, "remembered defense replaces inherited shared attack-move endpoints")
	for unit: UnitBase in soldiers:
		_expect(unit.attack_move and not unit._force_move_active and unit.stance == UnitBase.Stance.AGGRESSIVE, "investigation retains attack-move and Easy defense stance")
		_expect(unit.move_target.distance_to(anchor) <= 64.0, "investigation remains local to the remembered threat")
	for step: int in 10:
		for unit: UnitBase in soldiers: unit._process(1.0 / 60.0)
	_assert_no_churn(soldiers, "investigation_in_flight", func() -> void: ai._rally_defense([]))
	var arrived: Dictionary = _drive(soldiers, 30.0)
	_expect(arrived.arrived == 5 and arrived.minimum_pair >= 20.0, "five mixed defenders settle separately at the actual River tile")
	_assert_no_churn(soldiers, "investigation_arrived", func() -> void: ai._rally_defense([]))
	records.append({"case": "remembered_river_threat", "anchor": str(anchor), "destinations": goals, "arrival": arrived})
	# Returning a visible enemy still uses actual attack targets and preserves
	# an attack already winding up when the memory-only policy is revisited.
	var enemy: UnitBase = load("res://scenes/units/infantry.tscn").instantiate()
	enemy.player_owner = 0
	enemy.position = soldiers[0].position + Vector2(12.0, 0.0)
	map.get_node("UnitsContainer").add_child(enemy)
	ai._rally_defense([enemy])
	for unit: UnitBase in soldiers: _expect(unit.attack_target == enemy and unit.current_state == UnitBase.State.ATTACKING, "visible defense target assignment remains intact")
	soldiers[0]._process(0.01)
	var windup: float = soldiers[0]._attack_windup_remaining
	ai._rally_defense([])
	_expect(soldiers[0].attack_target == enemy and soldiers[0]._attack_windup_remaining == windup, "memory investigation cannot replace an ongoing fight or windup")
	enemy.free()
	for unit: UnitBase in soldiers: unit._process(0.3)
	ai._rally_defense([])
	var returned: Dictionary = _drive(soldiers, 30.0)
	_expect(returned.arrived == 5 and returned.minimum_pair >= 20.0, "target removal returns defenders to spaced investigation")
	# A new obstacle forces only affected slots to be planned again.
	var blocked_tile: Vector2i = map.world_to_tile(soldiers[0].position)
	map.pathfinding.update_tile(blocked_tile, MapData.TileType.WATER)
	ai._rally_defense([])
	var reopened: Dictionary = _drive(soldiers, 30.0)
	for unit: UnitBase in soldiers: _expect(map.is_tile_walkable(map.world_to_tile(unit.position)), "new obstruction cannot remain an investigation endpoint")
	_expect(reopened.minimum_pair >= 20.0, "obstructed investigation remains spaced")
	map.pathfinding.update_tile(blocked_tile, MapData.TileType.GRASS)
	ai._game_time = 112.01
	_expect(not ai._has_recent_defense_threat(), "existing twelve-second defense memory is unchanged")
	ai._check_attack_or_defend()
	_expect(ai._last_strategy_decision != "search_last_base_threat", "expired defense memory yields to the existing strategy")
	_remove_units(soldiers)
	var output: String = "res://output/polish-ai-defense-assembly-2026-10-23"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output.path_join("defense.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Private headless actual Main/GameMap River101; five synthetic mixed soldiers, no paid/full-match/performance claim.", "checks": checks, "failures": failures, "records": records, "ai_sha256": FileAccess.get_sha256("res://scripts/ai/ai_controller.gd"), "fixture_sha256": FileAccess.get_sha256("res://tools/test_ai_defense_assembly_2026_10_23.gd")}, "  ") + "\n")
	match_scene.free()
	for failure: String in failures: push_error("[FAIL] ai_defense_assembly: " + failure)
	if failures.is_empty(): print("[PASS] ai_defense_assembly: ", checks, " checks; remembered threat spacing, attack-move intent, stable orders, visible combat, target loss, blocked slot and memory expiry")
	get_tree().quit(0 if failures.is_empty() else 1)
