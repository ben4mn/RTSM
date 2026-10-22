extends Node
## Rule/transaction regression; fixtures are distinct from paid policy matches.
const SITE := preload("res://scenes/map/sacred_site.tscn")
var failures: Array[String] = []

func _ready() -> void:
	AudioManager.set_all_enabled(false)
	_test_latched_costs()
	_test_control_bank()
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.initialize_game()
	for failure: String in failures:
		push_error(failure)
	print("[QUICK_RULES] ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, context: String) -> void:
	if not value:
		failures.append(context)

func _test_latched_costs() -> void:
	GameManager.selected_match_mode = SkirmishData.MatchMode.QUICK_CONTROL
	GameManager.selected_population_limit = 30
	GameManager.initialize_game()
	ResourceManager.reset()
	ResourceManager.initialize_player(0)
	ResourceManager.initialize_player(1)
	for pid: int in [0, 1]:
		_expect(ResourceManager.get_resource(pid, "wood") == 250, "mode keeps ordinary starting bank")
		_expect(GameManager.get_age_up_cost(pid, 2) == {"food": 250, "gold": 125}, "both sides pay quick age cost")
		var cost: Dictionary = BuildingData.get_building_cost(BuildingData.BuildingType.BARRACKS)
		_expect(cost["wood"] == 100 and ResourceManager.try_spend(pid, cost), "both sides pay quick barracks")
		_expect(ResourceManager.get_resource(pid, "wood") == 150, "quick building debits exact cost")
		ResourceManager.refund(pid, cost)
		_expect(ResourceManager.get_resource(pid, "wood") == 250, "refund preserves exact purchase")
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.set_state(GameManager.GameState.PAUSED)
	_expect(BuildingData.get_building_stats(BuildingData.BuildingType.ARCHERY_RANGE)["cost"]["wood"] == 100, "pause settings cannot change running displayed/spent costs")
	_expect(GameManager.get_age_up_cost(0, 2)["food"] == 250, "pause settings cannot change running age cost")
	GameManager.initialize_game()
	_expect(BuildingData.get_building_cost(BuildingData.BuildingType.BARRACKS)["wood"] == 120, "new standard match restores original costs")
	_expect(GameManager.get_age_up_cost(0, 2) == {"food": 250, "gold": 125}, "standard Feudal uses shared pacing costs")

func _site(mode: int) -> Node2D:
	var site: Node2D = SITE.instantiate()
	add_child(site)
	site.set_process(false)
	site.configure_match_mode(mode)
	site.owning_player = 0
	site.state = 2
	site.capture_progress = 1.0
	return site

func _test_control_bank() -> void:
	var site: Node2D = _site(SkirmishData.MatchMode.QUICK_CONTROL)
	site._handle_captured(2, 0, 100.0)
	_expect(is_equal_approx(site.victory_timer, 100.0), "exclusive control earns bank")
	var gold_before: int = ResourceManager.get_resource(0, "gold")
	site._handle_captured(2, 1, 30.0)
	_expect(is_equal_approx(site.victory_timer, 100.0), "contest pauses control mode")
	_expect(ResourceManager.get_resource(0, "gold") == gold_before, "contest grants no gold")
	site.state = 2
	site._handle_captured(0, 2, 40.0)
	_expect(site.owning_player == -1, "enemy clears captured site")
	site._handle_neutral(0, 1, 0.0)
	site._handle_capturing(0, 1, 31.0)
	site._handle_captured(0, 1, 50.0)
	_expect(is_equal_approx(site.victory_timer, 50.0), "new owner earns only own bank")
	site._handle_captured(2, 0, 40.0)
	site._handle_neutral(1, 0, 0.0)
	site._handle_capturing(1, 0, 31.0)
	_expect(is_equal_approx(site.victory_timer, 100.0), "recapture restores original side bank")
	var ticks: Array[float] = []
	site.victory_timer_tick.connect(func(_owner: int, remaining: float, _total: float) -> void: ticks.append(remaining))
	site._handle_captured(1, 0, SkirmishData.get_sacred_target(SkirmishData.MatchMode.QUICK_CONTROL) - 100.0)
	_expect(ticks.size() == 1 and is_zero_approx(ticks[0]), "natural bank boundary emits existing victory signal")
	site.free()
	var standard: Node2D = _site(SkirmishData.MatchMode.STANDARD)
	standard._handle_captured(1, 0, 100.0)
	standard._handle_captured(0, 2, 40.0)
	standard._handle_neutral(1, 0, 0.0)
	_expect(is_zero_approx(standard.victory_timer), "standard neutralization still resets hold")
	standard.free()
