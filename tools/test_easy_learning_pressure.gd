extends SceneTree
## Pressure contracts use real unit commands/death signals. Spending/cap
## transactions are separately covered by test_compact_ai_policy.+
var failures: Array[String] = []
var fixtures: Array[Node] = []

class TestMap extends Node2D:
	var sacred_site: Node2D
	var enemies_visible: bool = true
	func is_entity_visible_to_player(_entity: Node2D, _viewer: int = 0) -> bool:
		return enemies_visible
	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2(float(tile.x - tile.y) * 32.0, float(tile.x + tile.y) * 16.0)
	func world_to_tile(world: Vector2) -> Vector2i:
		return Vector2i(roundi((world.x / 32.0 + world.y / 16.0) / 2.0), roundi((world.y / 16.0 - world.x / 32.0) / 2.0))

class TestSite extends Node2D:
	var state: int = 2
	var owning_player: int = 0
	var capture_radius: int = 3
	var victory_hold_time: float = 180.0
	var victory_timer: float = 179.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("AudioManager").call("set_all_enabled", false)
	var gm: Node = root.get_node("GameManager")
	gm.set("selected_population_limit", 30)
	gm.call("initialize_game", 2)
	var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
	ai.set("difficulty", 0)
	root.add_child(ai)
	fixtures.append(ai)
	(ai.get("_decision_timer") as Timer).stop()
	ai.set("_base_position", Vector2(0, 1000))
	ai.set("_staging_point", Vector2(100, 1000))
	var map := TestMap.new()
	root.add_child(map)
	fixtures.append(map)
	ai.set("game_map", map)
	var tc: Node = load("res://scenes/buildings/town_center.tscn").instantiate()
	tc.set("player_owner", 1)
	tc.set("position", Vector2(0, 1000))
	root.add_child(tc)
	fixtures.append(tc)
	tc.call("complete_instantly")
	ai.call("register_building", tc)
	var soldiers: Array[Node] = []
	for index: int in range(6):
		var soldier: Node = _unit(1, Vector2(100 + index * 12, 1000))
		soldiers.append(soldier)
		ai.call("register_unit", soldier)
	var enemy: Node = _unit(0, Vector2(2000, 1000))
	for limit: int in [20, 30, 40, 60]:
		gm.players[1]["max_population"] = limit
		for moment: float in [301.0, 481.0]:
			ai.set("_game_time", moment)
			var threshold: int = int(ai.call("_get_attack_threshold"))
			_expect(threshold >= 3 and threshold <= SkirmishData.get_easy_pressure_squad_size(moment), "%d-pop Easy threshold fits its actual pressure squad at %.0fs" % [limit, moment])
			ai.set("_last_field_attack_time", -INF)
			ai.call("_check_attack_or_defend")
			_expect((ai.get("_attack_wave_units") as Array).size() == SkirmishData.get_easy_pressure_squad_size(moment), "%d-pop Easy actually issues one bounded field squad at %.0fs" % [limit, moment])
			ai.call("_clear_attack_wave")
	gm.players[1]["max_population"] = 30
	ai.set("_last_field_attack_time", -INF)
	_check_reactive_opening(ai, map, gm, enemy)
	var launches: Array[int] = []
	ai.connect("ai_attack_launched", func(units: Array, _target: Vector2) -> void: launches.append(units.size()))
	ai.set("_game_time", 299.0)
	ai.set("_staging_point", Vector2(500, 1000))
	enemy.set("position", Vector2(600, 1000))
	for soldier: Node in soldiers:
		soldier.call("command_stop")
		soldier.set("position", Vector2(500, 1000))
	# A stale investigation aimed at staging is still an attack-move, not a
	# passive return; Stand Ground alone must not preserve that acquisition.
	soldiers[0].call("command_attack_move", Vector2(500, 1000))
	ai.call("_check_attack_or_defend")
	_expect(launches.is_empty(), "Easy does not initiate a raid before five minutes")
	_expect(not bool(soldiers[0].get("attack_move")), "a stale attack-move toward staging is replaced with a passive return")
	for soldier: Node in soldiers:
		soldier.set("_auto_attack_timer", 0.0)
		soldier.call("_try_auto_attack")
		_expect(soldier.get("attack_target") == null, "idle staged fighters do not acquire a distant sighting during opening grace")
		soldier.set("position", Vector2(100, 1000))
	ai.set("_staging_point", Vector2(100, 1000))
	enemy.set("position", Vector2(2000, 1000))
	ai.set("_game_time", 301.0)
	ai.call("_check_attack_or_defend")
	var old_wave: Array = (ai.get("_attack_wave_units") as Array).duplicate()
	_expect(launches == [3] and old_wave.size() == 3, "six available fighters launch one coherent three-unit early squad")
	var site := TestSite.new()
	site.position = Vector2(800, 1000)
	root.add_child(site)
	fixtures.append(site)
	map.sacred_site = site
	# A field wave and a neutral objective must share one combat budget.
	site.state = 0
	site.owning_player = -1
	ai.set("_game_time", 390.0)
	ai.call("_check_sacred_site_strategy")
	_expect((ai.get("_objective_units") as Array).is_empty() and (ai.get("_attack_wave_units") as Array).size() == 3, "neutral-site guard cannot add a fourth fighter to an active early raid")
	site.state = 2
	site.owning_player = 1
	ai.call("_check_sacred_site_strategy")
	_expect((ai.get("_objective_units") as Array).is_empty(), "nonurgent owned-site defense also shares the existing wave's pressure budget")
	var scout: Node = load("res://scenes/units/scout.tscn").instantiate()
	scout.set("player_owner", 1)
	scout.set("position", site.position)
	root.add_child(scout)
	fixtures.append(scout)
	ai.call("register_unit", scout)
	ai.call("_check_sacred_site_strategy")
	_expect((ai.get("_objective_units") as Array) == [scout] and (ai.get("_attack_wave_units") as Array).size() == 3, "a zero-damage Scout can guard without consuming or expanding the three-fighter pressure budget")
	site.owning_player = 0
	ai.set("_game_time", 301.0)
	for soldier: Node in soldiers:
		soldier.set("position", Vector2(100, 1000) if soldier in old_wave else Vector2(790, 1000))
	ai.call("_check_attack_or_defend")
	var contest: Array = (ai.get("_objective_units") as Array).duplicate()
	_expect(contest.size() == 3 and (ai.get("_attack_wave_units") as Array).is_empty(), "one second left on the enemy clock still cannot create an all-army contest")
	for soldier: Node in old_wave:
		_expect(soldier not in contest and (soldier.get("move_target") as Vector2).distance_to(Vector2(100, 1000)) <= 64.0, "objective redirect recalls each old wave survivor instead of combining squads")
	contest[0].call("take_damage", 1000.0)
	var resume_at: float = float(ai.get("_easy_regroup_until"))
	_expect(is_equal_approx(resume_at, 346.0), "a real assigned-fighter death starts one 45-second regroup")
	ai.set("_game_time", 302.0)
	ai.call("_check_scouting")
	_expect(int(scout.get("current_state")) == 1 and (scout.get("move_target") as Vector2).distance_to(site.position) > 224.0, "an already capturing Scout receives an outbound move when regroup begins")
	for frame: int in range(240):
		scout.call("_process", 1.0 / 60.0)
	_expect((scout.get("global_position") as Vector2).distance_to(site.position) > 224.0, "real Scout movement clears capture and recon clearance during regroup")
	var reentry_route := PackedVector2Array([site.position + Vector2(300, 0), site.position - Vector2(300, 0)])
	_expect(not bool(ai.call("_is_outbound_sacred_recon_route", site.position, reentry_route, site)), "an outbound route that subsequently crosses back through capture is rejected")
	_expect(not bool(ai.call("_is_route_outside_sacred_capture", site.position, PackedVector2Array([site.position + Vector2(300, 0)]), site)), "normal outside-only recon validation still rejects an inside start")
	ai.call("_check_scouting")
	ai.call("_check_attack_or_defend")
	_expect(str(ai.get("_last_strategy_decision")) == "learning_regroup" and (ai.get("_objective_units") as Array).is_empty(), "Sacred urgency cannot bypass the recovery interval")
	contest[1].call("take_damage", 1000.0)
	_expect(is_equal_approx(float(ai.get("_easy_regroup_until")), resume_at), "a retreat casualty does not extend regroup indefinitely")
	enemy.set("position", Vector2(32, 1000))
	ai.call("_check_attack_or_defend")
	_expect(str(ai.get("_last_strategy_decision")) == "base_defense", "a visible home attack overrides regroup immediately")
	for soldier: Node in soldiers:
		if int(soldier.get("current_state")) != 5:
			_expect(soldier.get("attack_target") == enemy, "all surviving defenders can protect home without a pressure-squad cap")
	enemy.set("position", Vector2(2000, 1000))
	ai.set("_last_defense_threat_time", -INF)
	ai.set("_game_time", resume_at - 0.01)
	ai.call("_check_attack_or_defend")
	_expect(str(ai.get("_last_strategy_decision")) == "learning_regroup", "home defense does not erase remaining recovery time")
	ai.set("_game_time", resume_at)
	ai.call("_check_attack_or_defend")
	_expect((ai.get("_objective_units") as Array).size() == 3, "regroup expires and a paid surviving squad can contest again")
	ai.set("_game_time", 481.0)
	ai.call("_check_attack_or_defend")
	_expect((ai.get("_objective_units") as Array).size() == 4, "late Easy pressure grows to four, not its entire economic budget")
	ai.call("_release_objective_units")
	site.state = 0
	site.owning_player = -1
	ai.set("_game_time", 389.0)
	ai.call("_check_sacred_site_strategy")
	_expect((ai.get("_objective_units") as Array).is_empty(), "Easy does not start a neutral objective clock before 6:30")
	ai.set("_game_time", 390.0)
	ai.call("_check_sacred_site_strategy")
	_expect((ai.get("_objective_units") as Array).size() == 1, "Easy can deliberately claim an empty objective after its grace")
	site.state = 2
	site.owning_player = 0
	for difficulty: int in [1, 2]:
		ai.set("difficulty", difficulty)
		ai.set("_game_time", 100.0)
		ai.set("_easy_regroup_until", 999.0)
		ai.call("_check_attack_or_defend")
		_expect((ai.get("_objective_units") as Array).size() == 4 and str(ai.get("_last_strategy_decision")) == "contest_sacred_site", "Medium/Hard keep immediate full surviving-army urgency")
	for fixture: Node in fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	if failures.is_empty():
		print("[PASS] easy_learning_pressure: separate reactive/raid/neutral timing, visible threats, bounded redirects, real-loss regroup, home defense and Medium/Hard urgency")
	else:
		for failure: String in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check_reactive_opening(ai: Node, map: TestMap, gm: Node, enemy: Node) -> void:
	var site := TestSite.new()
	site.position = Vector2(800, 1000)
	root.add_child(site)
	fixtures.append(site)
	map.sacred_site = site
	for limit: int in [20, 30, 40]:
		gm.players[1]["max_population"] = limit
		for site_state: int in [1, 2, 3]:
			site.state = site_state
			site.owning_player = 0
			ai.call("_release_objective_units")
			ai.set("_game_time", 149.999)
			_expect(bool(ai.call("_should_hold_sacred_recon", site)), "%d-pop recon respects opening response grace for state%d" % [limit, site_state])
			_expect(not bool(ai.call("_check_sacred_site_strategy")) and (ai.get("_objective_units") as Array).is_empty(), "%d-pop fighters respect the same response grace for state%d" % [limit, site_state])
			ai.set("_game_time", 150.0)
			_expect(not bool(ai.call("_should_hold_sacred_recon", site)), "%d-pop recon permits a public hostile claim response at150 for state%d" % [limit, site_state])
			ai.call("_check_attack_or_defend")
			_expect(str(ai.get("_last_strategy_decision")) == "contest_sacred_site" and (ai.get("_objective_units") as Array).size() == 3 and (ai.get("_attack_wave_units") as Array).is_empty(), "%d-pop responds at150 with one three-fighter objective squad for state%d" % [limit, site_state])
	gm.players[1]["max_population"] = 30
	ai.call("_release_objective_units")
	site.state = 0
	site.owning_player = -1
	for moment: float in [150.0, 299.999, 389.999]:
		ai.set("_game_time", moment)
		_expect(bool(ai.call("_should_hold_sacred_recon", site)) and not bool(ai.call("_check_sacred_site_strategy")), "an empty neutral objective remains recon-only at%.3fs" % moment)
		if moment < 300.0:
			ai.call("_check_attack_or_defend")
			_expect((ai.get("_attack_wave_units") as Array).is_empty(), "reactive eligibility does not advance ordinary raids at%.3fs" % moment)
	# Public ownership can trigger a response without granting hidden-unit
	# knowledge. A hidden visitor alone cannot make a neutral site urgent.
	ai.set("_game_time", 150.0)
	enemy.set("position", site.position)
	map.enemies_visible = false
	_expect(bool(ai.call("_should_hold_sacred_recon", site)) and not bool(ai.call("_check_sacred_site_strategy")), "a hidden neutral-site visitor does not trigger early objective orders")
	site.state = 2
	site.owning_player = 0
	ai.call("_check_attack_or_defend")
	_expect((ai.get("_objective_units") as Array).size() == 3, "the public enemy-owned clock still permits a bounded response without enemy vision")
	for fighter: Node in ai.get("_objective_units"):
		_expect(fighter.get("attack_target") == null, "a public-clock response never directly targets the hidden visitor")
	ai.call("_release_objective_units")
	site.state = 0
	site.owning_player = -1
	map.enemies_visible = true
	ai.call("_check_attack_or_defend")
	_expect((ai.get("_objective_units") as Array).size() == 3, "a currently visible threat at the neutral objective permits the same bounded response")
	# Removing the threat restores the later neutral policy and passive staging.
	enemy.set("position", Vector2(2000, 1000))
	ai.call("_check_attack_or_defend")
	_expect((ai.get("_objective_units") as Array).is_empty() and (ai.get("_attack_wave_units") as Array).is_empty(), "a cleared objective does not become an early initiative or base raid")
	map.sacred_site = null
	ai.set("_last_field_attack_time", -INF)


func _unit(owner: int, at: Vector2) -> Node:
	var unit: Node = load("res://scenes/units/infantry.tscn").instantiate()
	unit.set("player_owner", owner)
	unit.set("position", at)
	root.add_child(unit)
	fixtures.append(unit)
	return unit

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
