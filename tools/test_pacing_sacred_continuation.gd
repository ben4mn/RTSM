extends Node
## Test the counterfactual harness seam against actual Main victory wiring.
const ADAPTER = preload("res://tools/fixtures/pacing_sacred_continuation.gd")
var checks: int = 0
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 1
	GameManager.selected_population_limit = 100
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	check(main.get("_building_placement") != null, "actual Main initialized")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var adapter = ADAPTER.new()
	var site: Node = main.game_map.sacred_site
	var stock_before: Array = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	var hold_before: float = site.victory_hold_time
	check(adapter.attach(main), "adapter intercepts the real solo Sacred callback")
	check(not site.victory_timer_tick.is_connected(Callable(main, "_on_sacred_site_timer_tick")), "only original Sacred callback is disconnected")
	site.victory_timer_tick.emit(0, 100.0, hold_before)
	check(main._sacred_control_owner == 0 and main._sacred_last_remaining == 100.0, "positive tick retains Main telemetry")
	site.victory_timer_tick.emit(0, 0.0, hold_before)
	site.victory_timer_tick.emit(0, -0.25, hold_before)
	check(GameManager.current_state == GameManager.GameState.PLAYING and not main._game_over_shown, "Sacred threshold and later ticks do not conclude counterfactual")
	check(not GameManager.players[1].is_defeated, "suppressed Sacred win does not defeat the opponent")
	check(adapter.blocked_tick_count == 2 and adapter.windows.size() == 1 and adapter.windows[0].ticks == 2, "all blocked ticks retained in compact timestamp windows")
	check(is_equal_approx(main._sacred_control_seconds[0], 100.25), "suppressed branch preserves elapsed control telemetry")
	site.clock_ticking = false
	site.status_changed.emit()
	site.victory_timer_tick.emit(0, -0.5, hold_before)
	check(adapter.windows.size() == 2 and adapter.blocked_tick_count == 3, "resumed threshold attempts receive a new window")
	check(site.victory_hold_time == hold_before, "adapter does not change the actual Sacred timer")
	check([ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)] == stock_before, "adapter grants neither resources nor costs")
	var enemy_tc: BuildingBase
	for building: BuildingBase in main._player_buildings[1]:
		if building.building_type == BuildingData.BuildingType.TOWN_CENTER: enemy_tc = building
	check(enemy_tc != null, "ordinary opponent Town Center exists")
	if enemy_tc != null: enemy_tc.take_damage(enemy_tc.max_hp * 2)
	check(GameManager.current_state == GameManager.GameState.GAME_OVER and GameManager.players[1].is_defeated, "actual Town Center lethal damage still defeats its owner")
	check(main._game_over_shown and "destroyed" in main._victory_reason, "ordinary Main Town Center result remains connected")
	print(JSON.stringify({"test": "pacing_sacred_continuation", "checks": checks, "failures": failures}))
	main.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
