extends Node
## Synthetic assignment proof with real actors; not paid-match pacing evidence.

const AI := preload("res://scripts/ai/ai_controller.gd")
const SITE := preload("res://scenes/map/sacred_site.tscn")
const FIXTURES := preload("res://tools/test_armed_sacred_garrison.gd")
var checks: int = 0
var failures: Array[String] = []

func _ready() -> void:
	AudioManager.set_all_enabled(false)
	for mode in [SkirmishData.MatchMode.STANDARD, SkirmishData.MatchMode.QUICK_CONTROL]:
		for difficulty in [AI.Difficulty.MEDIUM, AI.Difficulty.HARD]:
			for fighters in [20, 40]:
				_test_split(mode, difficulty, fighters)
	for difficulty in [AI.Difficulty.MEDIUM, AI.Difficulty.HARD]:
		_test_fresh_surplus(difficulty)
		for fighters in [2, 3, 5, 8, 9]:
			_test_opening_commitment(difficulty, fighters)
	_test_preserved_policies()
	print("LARGE_ARMY_OBJECTIVES checks=%d failures=%s scope=synthetic-real-actors" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _fixture(limit: int, difficulty: int, count: int, mode: int) -> Dictionary:
	GameManager.selected_match_mode = mode
	GameManager.selected_population_limit = limit
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	ResourceManager.reset()
	for owner in 2:
		ResourceManager.initialize_player(owner, {"food": 0, "wood": 0, "gold": 0})
	var map := FIXTURES.FixtureMap.new()
	add_child(map)
	var site := SITE.instantiate() as Node2D
	map.add_child(site)
	site.set_process(false)
	site.configure_match_mode(mode)
	site.position = Vector2(1000, 300)
	site.state = 2
	site.owning_player = 0
	site.capture_progress = 1.0
	site.victory_timer = 30.0
	map.sacred_site = site
	var ai := AI.new()
	add_child(ai)
	ai.difficulty = difficulty
	ai.game_map = map
	ai.start_ai(Vector2i.ZERO, Vector2.ZERO)
	ai._decision_timer.stop()
	ai.set_process(false)
	ai._game_time = 500.0
	ai._town_center_count = 1
	var units: Array = []
	for index in count:
		var unit := _actor(1, Vector2(600 + (index % 8) * 40, 220 + (index / 8) * 40), map)
		ai.register_unit(unit)
		units.append(unit)
	return {"ai": ai, "map": map, "site": site, "units": units}

func _actor(owner: int, location: Vector2, parent_node: Node) -> UnitBase:
	var unit := preload("res://scenes/units/infantry.tscn").instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = location
	parent_node.add_child(unit)
	unit.set_process(false)
	unit.set_physics_process(false)
	return unit

func _test_split(mode: int, difficulty: int, count: int) -> void:
	var f := _fixture(100, difficulty, count, mode)
	var ai: Node = f.ai
	var units: Array = f.units
	var expected: int = ceili(count * 0.75)
	var prefix := "mode%d difficulty%d fighters%d " % [mode, difficulty, count]
	var reserve: Array = ai._get_base_reserve_units(units)
	var wave: Array = units.filter(func(unit: UnitBase) -> bool: return unit not in reserve)
	for unit: UnitBase in wave:
		unit.command_attack_move(Vector2(2400, 300))
	ai._begin_attack_wave(wave, Vector2(2400, 300))
	ai._attack_wave_last_progress_time = ai._game_time - 23.0
	var original_generations: Dictionary = {}
	for unit: UnitBase in units:
		original_generations[unit] = unit._command_generation
	var blocks: bool = ai._check_sacred_site_strategy()
	_expect(not blocks and ai._objective_units.size() == expected, prefix + "75 percent commits without blocking surplus")
	_expect(ai._attack_in_progress and ai._attack_wave_units.size() == count - reserve.size() - expected, prefix + "existing wave retains only surplus")
	_expect(ai._attack_wave_last_progress_time == ai._game_time and is_equal_approx(ai._attack_wave_best_distance, ai._get_closest_wave_distance(ai._attack_wave_units, Vector2(2400, 300))), prefix + "partial recall rebases survivor progress watchdog")
	_check_disjoint(ai, units, prefix)
	for unit: UnitBase in ai._attack_wave_units:
		_expect(unit._command_generation == original_generations[unit] and unit.move_target == Vector2(2400, 300), prefix + "surplus keeps its accepted order")
	var objective: Array = ai._objective_units.duplicate()
	var remaining_wave: Array = ai._attack_wave_units.duplicate()
	var progress_epoch: float = ai._attack_wave_last_progress_time
	var after_generations: Dictionary = {}
	for unit: UnitBase in units:
		after_generations[unit] = unit._command_generation
	ai._game_time += 1.0
	ai._check_sacred_site_strategy()
	_expect(ai._objective_units == objective and ai._attack_wave_units == remaining_wave, prefix + "repeated decision preserves membership")
	_expect(ai._attack_wave_last_progress_time == progress_epoch, prefix + "unchanged membership does not extend watchdog")
	for unit: UnitBase in units:
		_expect(unit._command_generation == after_generations[unit], prefix + "repeated decision has no command churn")
	# No healing exists: wounded center members must not be parked indefinitely.
	for unit: UnitBase in objective:
		unit.hp = unit.max_hp * 0.3
	ai._micro_damaged_units()
	ai._check_sacred_site_strategy()
	_expect(ai._objective_units.size() == expected, prefix + "wounded contest still commits proportionally")
	for unit: UnitBase in objective:
		_expect(unit._command_generation == after_generations[unit], prefix + "wounded micro preserves accepted center order")
	ai._game_time += 1.0
	for unit: UnitBase in remaining_wave:
		unit.position += Vector2(1, 0)
	_expect(ai._refresh_attack_wave_lifecycle() and ai._attack_wave_units == remaining_wave, prefix + "survivors advance beyond old timeout without false stall")
	# A paused contested clock retains its deadline and must recall the wave.
	f.site.state = 3
	f.site.victory_timer = 60.0
	blocks = ai._check_sacred_site_strategy()
	_expect(blocks and ai._objective_units.size() == count, prefix + "exact120 seconds remaining recalls every fighter")
	_expect(not ai._attack_in_progress and ai._attack_wave_units.is_empty(), prefix + "urgent recall releases wave tracking")
	_check_disjoint(ai, units, prefix)
	# Real home-defense detection must still preempt the objective entirely.
	var threat := _actor(0, Vector2(20, 0), f.map)
	ai._check_attack_or_defend()
	_expect(ai._objective_units.is_empty() and not ai._attack_in_progress and ai._last_strategy_decision == "base_defense", prefix + "home defense remains first")
	threat.free()
	ai.free()
	f.map.free()

func _check_disjoint(ai: Node, units: Array, prefix: String) -> void:
	var reserve: Array = ai._get_base_reserve_units(units)
	var field: Array = ai._get_field_military(reserve)
	for unit: UnitBase in ai._objective_units:
		_expect(unit not in ai._attack_wave_units and unit not in reserve and unit not in field, prefix + "objective has one owner")
	for unit: UnitBase in ai._attack_wave_units:
		_expect(unit not in reserve and unit in field, prefix + "wave remains genuine field surplus")

func _test_fresh_surplus(difficulty: int) -> void:
	var f := _fixture(100, difficulty, 40, SkirmishData.MatchMode.STANDARD)
	# The real target selector may use the public symmetric spawn when no enemy
	# is visible. No target override, bank grant or custom order seam is involved.
	f.ai.map_generator = MapGenerator.new(101)
	f.ai._check_attack_or_defend()
	_expect(f.ai._objective_units.size() == 30, "fresh large contest assigns30 of40 fighters")
	_expect(f.ai._attack_in_progress and f.ai._attack_wave_units.size() == 8 and f.ai._last_strategy_decision == "full_attack", "real field seam launches the eight unassigned fighters")
	_check_disjoint(f.ai, f.units, "fresh surplus ")
	f.ai.free()
	f.map.free()

func _test_preserved_policies() -> void:
	for profile in [{"limit": 100, "difficulty": AI.Difficulty.EASY, "expected": 3}, {"limit": 40, "difficulty": AI.Difficulty.MEDIUM, "expected": 15}, {"limit": 40, "difficulty": AI.Difficulty.HARD, "expected": 15}]:
		var f := _fixture(profile.limit, profile.difficulty, 20, SkirmishData.MatchMode.STANDARD)
		_expect(not f.ai._uses_large_army_objective_policy(), "preserved profile does not enter new policy")
		_expect(f.ai._check_sacred_site_strategy() and f.ai._objective_units.size() == profile.expected, "preserved profile retains commitment/offense block")
		f.ai.free()
		f.map.free()

func _test_opening_commitment(difficulty: int, count: int) -> void:
	var f := _fixture(100, difficulty, count, SkirmishData.MatchMode.STANDARD)
	var expected: int = mini(count, maxi(f.ai._get_attack_threshold(), ceili(count * 0.75)))
	f.ai._check_sacred_site_strategy()
	_expect(f.ai._objective_units.size() == expected, "opening%d difficulty%d can borrow reserve to fill its contest force" % [count, difficulty])
	_check_disjoint(f.ai, f.units, "opening commitment ")
	var generations: Dictionary = {}
	for unit: UnitBase in f.ai._objective_units:
		generations[unit] = unit._command_generation
		_expect(unit.current_state == UnitBase.State.MOVING and unit.move_target.distance_to(f.site.position) < 64.0, "opening committed fighter has an actual center order")
	f.ai._check_attack_or_defend()
	for unit: UnitBase in f.ai._objective_units:
		_expect(unit._command_generation == generations[unit], "opening repeat does not churn accepted center orders")
	var threat := _actor(0, Vector2(20, 0), f.map)
	f.ai._check_attack_or_defend()
	_expect(f.ai._objective_units.is_empty() and f.ai._last_strategy_decision == "base_defense", "borrowed opening reserve still responds to real home danger")
	threat.free()
	f.ai.free()
	f.map.free()

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("[FAIL] large_army_objectives: " + label)
