extends Node
## Synthetic rule/policy proof with real paid-role actors; not match pacing evidence.

const SITE := preload("res://scenes/map/sacred_site.tscn")
const AI := preload("res://scripts/ai/ai_controller.gd")
var failures: Array[String] = []
var checks: int = 0

class FixtureMap extends Node2D:
	var sacred_site: Node2D
	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2((tile.x - tile.y) * 32.0, (tile.x + tile.y) * 16.0)
	func world_to_tile(point: Vector2) -> Vector2i:
		return Vector2i(roundi((point.x / 32.0 + point.y / 16.0) * 0.5), roundi((point.y / 16.0 - point.x / 32.0) * 0.5))
	func is_tile_walkable(_tile: Vector2i) -> bool:
		return true
	func is_entity_visible_to_player(entity: Node2D, _owner: int) -> bool:
		return bool(entity.get_meta("fixture_visible", true))
	func get_navigation_world_path(_start: Vector2, finish: Vector2, _radius: float = 4.0, _goal: int = 8) -> PackedVector2Array:
		return PackedVector2Array([finish])

func _ready() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_population_limit = 30
	GameManager.initialize_game(2)
	ResourceManager.reset()
	for owner in 2:
		ResourceManager.initialize_player(owner, {"food": 0, "wood": 0, "gold": 0})
	_test_rules()
	for difficulty in 3:
		_test_policy(difficulty)
	if failures.is_empty():
		print("[PASS] armed_sacred_garrison: ", checks, " rule and bounded AI assertions")
	get_tree().quit(0 if failures.is_empty() else 1)

func _actor(kind: String, owner: int, position_world: Vector2, parent_node: Node = null) -> UnitBase:
	if parent_node == null:
		parent_node = self
	var actor := load("res://scenes/units/" + kind + ".tscn").instantiate() as UnitBase
	actor.player_owner = owner
	actor.position = position_world
	parent_node.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	return actor

func _site(parent_node: Node = null) -> Node2D:
	if parent_node == null:
		parent_node = self
	var site := SITE.instantiate() as Node2D
	parent_node.add_child(site)
	site.set_process(false)
	site.configure_match_mode(SkirmishData.MatchMode.STANDARD)
	site.victory_wake_time = 0.0  # The 8:00 opening has its own test (test_sacred_wake).
	site.state = 2
	site.owning_player = 0
	site.capture_progress = 1.0
	return site

func _step(site: Node, seconds: float) -> void:
	site.call("_process", seconds)

func _test_rules() -> void:
	var site: Node2D = _site()
	var ticks: Array[float] = []
	var statuses: Array = []
	site.victory_timer_tick.connect(func(_owner: int, remaining: float, _total: float) -> void: ticks.append(remaining))
	site.status_changed.connect(func() -> void: statuses.append(site.get_status()))
	_step(site, 5.0)
	_expect(site.victory_timer == 0.0 and site.garrison_paused and not site.clock_ticking, "empty Standard pauses")
	_expect(ResourceManager.get_resource(0, "gold") == 10 and site.owning_player == 0 and site.capture_progress == 1.0, "empty ownership/income preserved")
	_expect(site.get_status().phase == "unguarded", "public phase explains empty guard")
	var scout: UnitBase = _actor("scout", 0, Vector2.ZERO)
	var worker: UnitBase = _actor("villager", 0, Vector2(4, 0))
	_step(site, 1.0)
	_expect(site.victory_timer == 0.0 and ticks.is_empty(), "Scout and armed worker do not score")
	site.state = 0
	site.owning_player = -1
	site.capture_progress = 0.0
	_step(site, 0.1)
	_step(site, 30.0)
	_step(site, 1.0)
	_expect(site.state == 2 and site.owning_player == 0 and site.garrison_paused, "Scout/worker still capture completely")
	var fighter: UnitBase = _actor("infantry", 0, Vector2(10, 0))
	var before_status: int = statuses.size()
	_step(site, 0.01)
	_expect(site.clock_ticking and not site.garrison_paused and is_equal_approx(site.victory_timer, 0.01), "real fighter starts clock")
	_expect(statuses.size() > before_status, "resume publishes before remaining-second boundary")
	fighter.position = Vector2(193, 0)
	before_status = statuses.size()
	_step(site, 0.01)
	_expect(is_equal_approx(site.victory_timer, 0.01) and site.garrison_paused, "outside192 pauses without reset")
	_expect(statuses.size() > before_status, "departure publishes immediately")
	fighter.position = Vector2(192, 0)
	_step(site, 1.0)
	_expect(is_equal_approx(site.victory_timer, 1.01), "exact boundary fighter resumes retained time")
	var almost_complete: float = site.victory_hold_time - 0.01
	site.victory_timer = almost_complete
	fighter.hp = 0.0
	_step(site, 1.0)
	_expect(is_equal_approx(site.victory_timer, almost_complete), "zero-HP actor cannot score before its death-state transition")
	fighter.set_state(UnitBase.State.DEAD)
	var before_ticks: int = ticks.size()
	_step(site, 1.0)
	_expect(is_equal_approx(site.victory_timer, almost_complete) and ticks.size() == before_ticks, "dead fade cannot cross victory boundary")
	fighter.free()
	var replacement: UnitBase = _actor("infantry", 0, Vector2.ZERO)
	_step(site, 0.01)
	_expect(ticks.size() == before_ticks + 1 and is_zero_approx(ticks.back()), "returning live fighter reaches the existing natural victory signal")
	replacement.free()
	site.victory_timer = almost_complete
	var enemy: UnitBase = _actor("scout", 1, Vector2.ZERO)
	_step(site, 1.0)
	_expect(site.state == 3 and not site.clock_ticking, "unarmed enemy still contests")
	scout.free()
	worker.free()
	_step(site, 30.0)
	_step(site, 30.0)
	_step(site, 1.0)
	_expect(site.owning_player == 1 and site.victory_timer == 0.0 and site.garrison_paused, "enemy takeover resets and enemy Scout cannot score")
	var siege: UnitBase = _actor("siege", 1, Vector2.ZERO)
	_step(site, 1.0)
	_expect(is_equal_approx(site.victory_timer, 1.0) and site.clock_ticking, "Siege is an armed guard for opposing owner")
	siege.free()
	enemy.free()
	site.configure_match_mode(SkirmishData.MatchMode.QUICK_CONTROL)
	site.victory_wake_time = 0.0  # The 8:00 opening has its own test (test_sacred_wake).
	site.state = 2
	site.owning_player = 0
	site.capture_progress = 1.0
	_step(site, 3.0)
	_expect(site.clock_ticking and not site.garrison_paused and is_equal_approx(site.control_banks[0], 3.0), "empty Control race still scores ownership")
	site.free()

func _test_policy(difficulty: int) -> void:
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.initialize_game(2)
	GameManager.players[1].population_cap = 30
	var map := FixtureMap.new()
	add_child(map)
	var site: Node2D = _site(map)
	site.position = Vector2(900, 300)
	site.owning_player = 1
	map.sacred_site = site
	var ai := AI.new()
	add_child(ai)
	ai.difficulty = difficulty
	ai.game_map = map
	ai.start_ai(Vector2i.ZERO, Vector2.ZERO)
	ai._decision_timer.stop()
	ai.set_process(false)
	ai._game_time = 500.0
	var scout: UnitBase = _actor("scout", 1, site.position, map)
	ai.register_unit(scout)
	var fighters: Array = []
	for index in 3:
		var fighter: UnitBase = _actor("infantry", 1, site.position + Vector2(20 + index * 40, 0), map)
		ai.register_unit(fighter)
		fighters.append(fighter)
	ai._objective_units = [scout]
	ai._check_sacred_site_strategy()
	_expect(ai._objective_units.size() == 1 and ai._objective_units[0] != scout and ai._objective_units[0].damage > 0, "d%d replaces favored Scout with one armed guard" % difficulty)
	if ai._objective_units.is_empty():
		ai.free()
		map.free()
		return
	var guard: UnitBase = ai._objective_units[0]
	var original_generation: int = guard._command_generation
	ai._check_sacred_site_strategy()
	_expect(ai._objective_units == [guard] and guard._command_generation == original_generation, "d%d repeated safe decision keeps guard without order churn" % difficulty)
	for fighter: UnitBase in fighters:
		fighter.hp = fighter.max_hp * 0.3
	ai._check_sacred_site_strategy()
	guard = ai._objective_units[0]
	original_generation = guard._command_generation
	ai._micro_damaged_units()
	_expect(ai._sacred_armed_guard == guard and guard._command_generation == original_generation, "d%d wounded fallback is not canceled by safe-hold micro" % difficulty)
	# No spare and a full population: transfer exactly one nearest raider.
	for fighter: UnitBase in fighters:
		fighter.hp = fighter.max_hp
	ai._objective_units = [scout]
	ai._attack_wave_units = fighters.duplicate()
	ai._attack_in_progress = true
	GameManager.players[1].population = 4
	ai._check_sacred_site_strategy()
	_expect(ai._objective_units == [scout] and ai._attack_wave_units.size() == 3, "d%d does not recall a raider before population blocks replacement" % difficulty)
	GameManager.players[1].population = 30
	ai._check_sacred_site_strategy()
	_expect(ai._objective_units == [fighters[0]] and ai._attack_wave_units.size() == 2 and fighters[0] not in ai._attack_wave_units, "d%d full-pop fallback transfers nearest one from raid tracking" % difficulty)
	if difficulty == 0:
		_expect(ai._attack_wave_units.size() + ai._count_easy_objective_fighters() <= SkirmishData.get_easy_pressure_squad_size(500.0), "Easy guard and raid share original pressure budget")
	# Explicit reserve is never stolen even by a full-pop fallback.
	ai._objective_mode = AI.ObjectiveMode.DEFEND
	ai._attack_wave_units = [fighters[0]]
	var selected: Array = ai._ensure_standard_sacred_guard([scout], [scout, fighters[0]], [fighters[0]], site, 1)
	_expect(selected == [scout], "d%d does not steal home reserve" % difficulty)
	# Actual defense-first seam preempts the guard under visible home pressure.
	var threat: UnitBase = _actor("infantry", 0, Vector2(20, 0), map)
	ai._check_attack_or_defend()
	_expect(ai._objective_units.is_empty() and ai._sacred_armed_guard == null and ai._last_strategy_decision == "base_defense", "d%d real home defense overrides garrison" % difficulty)
	threat.free()
	ai._last_defense_threat_time = -INF
	ai._attack_wave_units.clear()
	ai._attack_in_progress = false
	ai._objective_units = [scout]
	GameManager.selected_match_mode = SkirmishData.MatchMode.QUICK_CONTROL
	GameManager.initialize_game(2)
	ai._has_launched_field_attack = true
	ai._check_sacred_site_strategy()
	_expect(ai._objective_units == [scout] and ai._sacred_armed_guard == null, "d%d Control race Scout preference unchanged" % difficulty)
	ai.free()
	map.free()

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("[FAIL] armed_sacred_garrison: " + label)
