extends SceneTree
## Budget contracts for actual 20/30/40 skirmishes. Full gathering/pressure
## behavior is measured separately by probe_compact_ai_match.gd.

var _failures: Array[String] = []
var _fixtures: Array[Node] = []


class VisibilityMap extends Node2D:
	var entities_visible: bool = true
	var sacred_site: Node2D

	func is_entity_visible_to_player(_entity: Node2D, _viewer_player_id: int = 0) -> bool:
		return entities_visible

	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2(float(tile.x - tile.y) * 32.0, float(tile.x + tile.y) * 16.0)

	func world_to_tile(position: Vector2) -> Vector2i:
		return Vector2i(roundi((position.x / 32.0 + position.y / 16.0) / 2.0), roundi((position.y / 16.0 - position.x / 32.0) / 2.0))


class ContestSite extends Node2D:
	var state: int = 2
	var owning_player: int = 0
	var capture_radius: int = 3
	var victory_hold_time: float = 600.0
	var victory_timer: float = 200.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	root.get_node("AudioManager").call("set_all_enabled", false)
	for limit in [20, 30, 40]:
		gm.set("selected_population_limit", limit)
		gm.call("initialize_game", 2)
		_expect(int(gm.call("get_player_population_limit", 0)) == limit and int(gm.call("get_player_population_limit", 1)) == limit, "both players receive selected budget %d" % limit)
		for difficulty in [0, 1, 2]:
			var expected_mature: int = int({20: 8, 30: 12, 40: 16}[limit]) if difficulty == 0 else int(limit / 2)
			var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
			ai.set("difficulty", difficulty)
			root.add_child(ai)
			_fixtures.append(ai)
			(ai.get("_decision_timer") as Timer).stop()
			for age in [1, 2, 3]:
				gm.players[1]["age"] = age
				var target: int = int(ai.call("_get_target_villager_count"))
				_expect(target <= limit / 2, "%d/%d Age%d reserves at least half the budget for troops" % [limit, difficulty, age])
				if age >= 2:
					ai.set("_has_launched_field_attack", true)
					target = int(ai.call("_get_target_villager_count"))
					_expect(target == expected_mature, "%d/%d mature workforce uses its difficulty profile target" % [limit, difficulty])
				var next_age: int = age + 1
				if next_age <= 3:
					var worker_gate: int = int(ai.call("_get_min_villagers_for_age_up", next_age))
					var army_gate: int = int(ai.call("_get_min_military_for_age_up", next_age))
					_expect(worker_gate + army_gate * 2 <= limit, "%d/%d Age%d gates fit even with two-pop troops" % [limit, difficulty, next_age])
			gm.players[1]["population_cap"] = limit
			gm.players[1]["population"] = limit
			var houses: Array[int] = []
			ai.connect("ai_wants_to_build", func(building_type: int, _tile: Vector2i, _rebuild: bool) -> void: houses.append(building_type))
			ai.call("_check_house_need")
			_expect(houses.is_empty(), "%d/%d does not buy housing beyond the match cap" % [limit, difficulty])
			var buildings: Dictionary = ai.call("_get_target_building_counts", 3)
			for kind in [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.STABLE, BuildingData.BuildingType.ARCHERY_RANGE]:
				_expect(int(buildings[kind]) <= 1, "%d/%d skips surplus small-match production" % [limit, difficulty])
			var threshold: int = int(ai.call("_get_attack_threshold"))
			_expect(threshold >= 3 and threshold <= 6 and threshold + 2 <= limit / 2, "%d/%d has a feasible three-to-six unit attack packet" % [limit, difficulty])
			ai.free()
	_test_army_mix(gm)
	_test_second_role_reserve(gm)
	await _test_safe_worker_cargo(gm)
	_test_worker_recovery_and_three_roles(gm)
	_test_wounded_full_population_contest(gm)
	_test_easy_opening_pacing(gm)
	_test_easy_paid_fighter_caps(gm)
	for fixture in _fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	if _failures.is_empty():
		print("[PASS] compact_ai_policy: equal budgets, reachable ages, army space, housing limits and fair counter mix")
		quit(0)
	else:
		for failure in _failures:
			push_error("[FAIL] compact_ai_policy: %s" % failure)
		quit(1)


func _test_army_mix(gm: Node) -> void:
	gm.set("selected_population_limit", 20)
	gm.call("initialize_game", 2)
	var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
	root.add_child(ai)
	_fixtures.append(ai)
	(ai.get("_decision_timer") as Timer).stop()
	var visibility_map := VisibilityMap.new()
	root.add_child(visibility_map)
	_fixtures.append(visibility_map)
	ai.set("game_map", visibility_map)
	var infantry: Node = (load("res://scenes/units/infantry.tscn") as PackedScene).instantiate()
	infantry.set("player_owner", 1)
	root.add_child(infantry)
	_fixtures.append(infantry)
	ai.call("register_unit", infantry)
	var plan: Array = ai.call("_rank_compact_military_plan", [1, 2, 3])
	_expect(int(plan[0]) == 2, "a paid Infantry does not monopolize every compact army queue")
	var enemy_archer: Node = (load("res://scenes/units/archer.tscn") as PackedScene).instantiate()
	enemy_archer.set("player_owner", 0)
	root.add_child(enemy_archer)
	_fixtures.append(enemy_archer)
	plan = ai.call("_rank_compact_military_plan", [1, 2, 3])
	_expect(int(plan[0]) == 3, "visible hostile Archers favor the existing Cavalry counter")
	visibility_map.entities_visible = false
	plan = ai.call("_rank_compact_military_plan", [1, 2, 3])
	_expect(int(plan[0]) == 2, "hidden enemy composition does not influence compact counter production")


func _test_second_role_reserve(gm: Node) -> void:
	gm.set("selected_population_limit", 20)
	gm.call("initialize_game", 2)
	gm.players[1]["age"] = 2
	root.get_node("ResourceManager").call("initialize_player", 1, {"food": 500, "wood": 100, "gold": 500})
	var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
	root.add_child(ai)
	_fixtures.append(ai)
	(ai.get("_decision_timer") as Timer).stop()
	ai.set("_farm_count", 1)
	ai.set("_barracks_count", 1)
	ai.set("_lumber_camp_count", 1)
	ai.set("_mill_count", 1)
	var requests: Array[int] = []
	ai.connect("ai_wants_to_build", func(building_type: int, _tile: Vector2i, _rebuild: bool) -> void: requests.append(building_type))
	ai.call("_check_building_construction")
	_expect(requests.is_empty(), "active food cannot spend the second troop-role unlock bank on optional buildings")
	ai.set("_game_time", 1000.0)
	_expect(not bool(ai.call("_is_sacred_timing_ready")), "uncontested Sacred timing waits for a real field attack")
	ai.set("_has_launched_field_attack", true)
	_expect(bool(ai.call("_is_sacred_timing_ready")), "a field attack releases the compact objective opening")
	ai.set("_archery_range_count", 1)
	requests.clear()
	ai.call("_check_building_construction")
	_expect(requests.is_empty(), "active food also preserves the third troop-role Stable bank")
	_expect(bool(ai.call("_is_essential_building_while_saving", BuildingData.BuildingType.STABLE)), "age saving cannot suppress the first Stable")
	_expect(int(ai.call("_get_target_building_counts", 3)[BuildingData.BuildingType.SIEGE_WORKSHOP]) == 0, "compact matches keep Siege outside this iteration")


func _test_safe_worker_cargo(gm: Node) -> void:
	gm.set("selected_population_limit", 30)
	gm.call("initialize_game", 2)
	var rm: Node = root.get_node("ResourceManager")
	rm.call("initialize_player", 1, {"food": 0, "wood": 0, "gold": 0})
	var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
	root.add_child(ai)
	_fixtures.append(ai)
	(ai.get("_decision_timer") as Timer).stop()
	var visibility_map := VisibilityMap.new()
	root.add_child(visibility_map)
	_fixtures.append(visibility_map)
	ai.set("game_map", visibility_map)
	var base_position := Vector2(0.0, 320.0)
	ai.set("_base_position", base_position)
	var tc: Node = (load("res://scenes/buildings/town_center.tscn") as PackedScene).instantiate()
	tc.set("player_owner", 1)
	tc.set("position", base_position)
	root.add_child(tc)
	_fixtures.append(tc)
	tc.call("complete_instantly")
	ai.call("register_building", tc)
	var worker: Node = (load("res://scenes/units/villager.tscn") as PackedScene).instantiate()
	worker.set("player_owner", 1)
	worker.set("position", base_position + Vector2(-96.0, 0.0))
	root.add_child(worker)
	_fixtures.append(worker)
	worker.set("carried_resource_type", "food")
	worker.set("carried_amount", 10)
	ai.call("register_unit", worker)
	var enemy: Node = (load("res://scenes/units/infantry.tscn") as PackedScene).instantiate()
	enemy.set("player_owner", 0)
	enemy.set("position", base_position + Vector2(100.0, 0.0))
	root.add_child(enemy)
	_fixtures.append(enemy)
	enemy.set_process(false)
	worker.call("command_return_resources")
	var deposit_destination: Vector2 = worker.get("move_target")
	for _decision in range(8):
		ai.call("_rally_defense", [enemy])
		for _movement in range(12):
			worker.call("_process", 0.1)
	_expect(worker.get("move_target") == deposit_destination, "safe cargo return is not repeatedly replaced by blanket evacuation")
	_expect(int(worker.get("carried_amount")) == 0 and int(rm.call("get_resource", 1, "food")) == 10, "safe worker deposits exact food during a continuing nearby melee threat")
	worker.set("position", enemy.get("position") + Vector2(24.0, 0.0))
	ai.call("_rally_defense", [enemy])
	_expect((worker.get("move_target") as Vector2).distance_to(enemy.get("position")) > 80.0, "actually exposed worker receives an escape outside melee range")
	for fixture in [ai, tc, worker, enemy, visibility_map]:
		fixture.free()


func _test_worker_recovery_and_three_roles(gm: Node) -> void:
	gm.set("selected_population_limit", 30)
	gm.call("initialize_game", 2)
	gm.players[1]["age"] = 2
	var rm: Node = root.get_node("ResourceManager")
	rm.call("initialize_player", 1, {"food": 25, "wood": 200, "gold": 0})
	var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
	root.add_child(ai)
	_fixtures.append(ai)
	(ai.get("_decision_timer") as Timer).stop()
	ai.set("_game_time", 400.0)
	ai.set("_ai_state", 1)
	ai.set("_has_launched_field_attack", true)
	var tc: Node = (load("res://scenes/buildings/town_center.tscn") as PackedScene).instantiate()
	tc.set("player_owner", 1)
	root.add_child(tc)
	_fixtures.append(tc)
	tc.call("complete_instantly")
	ai.call("register_building", tc)
	var requests: Array[int] = []
	ai.connect("ai_wants_to_train", func(_building: Node, unit_type: int) -> void: requests.append(unit_type))
	ai.call("_check_military_production")
	_expect(requests.is_empty(), "worker recovery banks scarce food instead of repeatedly buying a cheaper troop")
	ai.set("_saving_for_age_up", true)
	ai.call("_update_age_up_reserve")
	_expect(not bool(ai.get("_saving_for_age_up")), "worker attrition releases optional age saving")
	var labor: Dictionary = ai.call("_get_economy_worker_targets", 3, {"food": 25, "wood": 200, "gold": 0})
	_expect(int(labor["food"]) >= 2 and int(labor["gold"]) == 0, "three surviving workers can earn replacement food without gold labor")
	var horse_cost: Dictionary = UnitData.get_unit_cost(UnitData.UnitType.CAVALRY)
	var plan: Array = ai.call("_get_military_training_plan", horse_cost)
	_expect(UnitData.UnitType.CAVALRY in plan, "Horseman production uses its real cost with no obsolete gold gate")
	# Actual paid queues prove the cheapest role cannot consume every wood deposit
	# while the underrepresented, already unlocked Archer is waiting for 45 wood.
	ai.set("_game_time", 0.0)
	var mix_fixtures: Array[Node] = []
	for scene_path in ["res://scenes/buildings/barracks.tscn", "res://scenes/buildings/archery_range.tscn", "res://scenes/buildings/stable.tscn"]:
		var building: Node = (load(scene_path) as PackedScene).instantiate()
		building.set("player_owner", 1)
		root.add_child(building)
		_fixtures.append(building)
		mix_fixtures.append(building)
		building.call("complete_instantly")
		ai.call("register_building", building)
	for _index in range(2):
		var warrior: Node = (load("res://scenes/units/infantry.tscn") as PackedScene).instantiate()
		warrior.set("player_owner", 1)
		root.add_child(warrior)
		_fixtures.append(warrior)
		mix_fixtures.append(warrior)
		ai.call("register_unit", warrior)
	ai.connect("ai_wants_to_train", func(building: Node, unit_type: int) -> void: building.call("get_production_queue").call("enqueue_unit", unit_type))
	rm.call("initialize_player", 1, {"food": 500, "wood": 30, "gold": 0})
	requests.clear()
	ai.call("_check_military_production")
	_expect(requests.is_empty() and int(rm.call("get_resource", 1, "wood")) == 30, "compact army banks an unlocked Archer cost instead of falling back to a cheap Warrior")
	rm.call("add_resource", 1, "wood", 15)
	ai.call("_check_military_production")
	_expect(requests == [UnitData.UnitType.ARCHER] and int(rm.call("get_resource", 1, "food")) == 475 and int(rm.call("get_resource", 1, "wood")) == 0, "the bank resumes as an exact paid Archer queue when its real cost is earned")
	for fixture in mix_fixtures:
		fixture.free()
	ai.free()
	tc.free()


func _test_wounded_full_population_contest(gm: Node) -> void:
	gm.set("selected_population_limit", 30)
	gm.call("initialize_game", 2)
	gm.players[1]["age"] = 2
	gm.players[1]["population_cap"] = 30
	gm.players[1]["population"] = 30
	var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
	root.add_child(ai)
	_fixtures.append(ai)
	(ai.get("_decision_timer") as Timer).stop()
	var visibility_map := VisibilityMap.new()
	root.add_child(visibility_map)
	_fixtures.append(visibility_map)
	var site := ContestSite.new()
	site.position = Vector2(300.0, 1000.0)
	root.add_child(site)
	_fixtures.append(site)
	visibility_map.sacred_site = site
	ai.set("game_map", visibility_map)
	ai.set("_base_position", Vector2(0.0, 1000.0))
	var town_center: Node = (load("res://scenes/buildings/town_center.tscn") as PackedScene).instantiate()
	town_center.set("player_owner", 1)
	town_center.set("position", Vector2(0.0, 1000.0))
	root.add_child(town_center)
	_fixtures.append(town_center)
	town_center.call("complete_instantly")
	ai.call("register_building", town_center)
	var army: Array[Node] = []
	var workers: Array[Node] = []
	for index in range(15):
		var warrior: Node = (load("res://scenes/units/infantry.tscn") as PackedScene).instantiate()
		warrior.set("player_owner", 1)
		warrior.set("position", Vector2(100.0 + float(index) * 8.0, 1020.0))
		root.add_child(warrior)
		_fixtures.append(warrior)
		warrior.set("hp", float(warrior.get("max_hp")) * 0.25)
		ai.call("register_unit", warrior)
		army.append(warrior)
		var worker: Node = (load("res://scenes/units/villager.tscn") as PackedScene).instantiate()
		worker.set("player_owner", 1)
		worker.set("position", Vector2(-80.0, 1000.0))
		root.add_child(worker)
		_fixtures.append(worker)
		ai.call("register_unit", worker)
		workers.append(worker)
	ai.call("_check_sacred_site_strategy")
	var committed: Array = ai.get("_objective_units")
	_expect(committed.size() == 12, "urgent contest commits three quarters of a mature wounded army at full population")
	ai.call("_micro_damaged_units")
	for unit in committed:
		_expect((unit.get("move_target") as Vector2).distance_to(site.position) < 112.0, "wounded urgent orders survive retreat micro instead of idling forever")
	site.victory_timer = 510.0
	ai.call("_check_sacred_site_strategy")
	_expect((ai.get("_objective_units") as Array).size() == 15, "late hostile hold commits the full wounded force before the timer ends")
	var home_enemy: Node = (load("res://scenes/units/infantry.tscn") as PackedScene).instantiate()
	home_enemy.set("player_owner", 0)
	home_enemy.set("position", Vector2(32.0, 1000.0))
	root.add_child(home_enemy)
	_fixtures.append(home_enemy)
	ai.call("_check_attack_or_defend")
	_expect((ai.get("_objective_units") as Array).is_empty(), "actual visible base pressure still overrides a full urgent contest")
	for unit in army:
		_expect(unit.get("attack_target") == home_enemy, "wounded fighters still defend the base against its current visible threat")
	for fixture in army + workers + [ai, town_center, visibility_map, site, home_enemy]:
		fixture.free()


func _test_easy_opening_pacing(gm: Node) -> void:
	gm.set("selected_population_limit", 30)
	gm.call("initialize_game", 2)
	var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
	ai.set("difficulty", 0)
	root.add_child(ai)
	_fixtures.append(ai)
	(ai.get("_decision_timer") as Timer).stop()
	var visibility_map := VisibilityMap.new()
	root.add_child(visibility_map)
	_fixtures.append(visibility_map)
	ai.set("game_map", visibility_map)
	ai.set("_base_position", Vector2(0.0, 1000.0))
	ai.set("_staging_point", Vector2(100.0, 1000.0))
	var town_center: Node = (load("res://scenes/buildings/town_center.tscn") as PackedScene).instantiate()
	town_center.set("player_owner", 1)
	town_center.set("position", Vector2(0.0, 1000.0))
	root.add_child(town_center)
	_fixtures.append(town_center)
	town_center.call("complete_instantly")
	ai.call("register_building", town_center)
	var army: Array[Node] = []
	for index in range(3):
		var warrior: Node = (load("res://scenes/units/infantry.tscn") as PackedScene).instantiate()
		warrior.set("player_owner", 1)
		warrior.set("position", Vector2(100.0 + float(index) * 8.0, 1000.0))
		root.add_child(warrior)
		_fixtures.append(warrior)
		ai.call("register_unit", warrior)
		army.append(warrior)
	var enemy: Node = (load("res://scenes/units/infantry.tscn") as PackedScene).instantiate()
	enemy.set("player_owner", 0)
	enemy.set("position", Vector2(2000.0, 1000.0))
	root.add_child(enemy)
	_fixtures.append(enemy)
	var launches: Array[int] = []
	ai.connect("ai_attack_launched", func(units: Array, _target: Vector2) -> void: launches.append(units.size()))
	ai.set("_game_time", 299.0)
	ai.call("_check_attack_or_defend")
	_expect(launches.is_empty() and not bool(ai.get("_attack_in_progress")), "ready Easy fighters neither raid nor harass at 299 seconds")
	_expect(str(ai.get("_last_strategy_decision")) == "opening_staging", "Easy opening staging remains observable")
	ai.set("_game_time", 301.0)
	ai.call("_check_attack_or_defend")
	_expect(launches.size() == 1 and launches[0] == 3, "the same ready Easy fighting force launches after 300 seconds")
	ai.call("_clear_attack_wave")
	ai.set("_game_time", 299.0)
	enemy.set("position", Vector2(32.0, 1000.0))
	ai.call("_check_attack_or_defend")
	_expect(str(ai.get("_last_strategy_decision")) == "base_defense", "visible home pressure overrides the Easy opening delay")
	for warrior in army:
		_expect(warrior.get("attack_target") == enemy, "every opening fighter receives the current visible home threat")
	enemy.set("position", Vector2(2000.0, 1000.0))
	ai.set("_last_defense_threat_time", -INF)
	var site := ContestSite.new()
	site.position = Vector2(500.0, 1000.0)
	root.add_child(site)
	_fixtures.append(site)
	visibility_map.sacred_site = site
	ai.call("_check_attack_or_defend")
	_expect(str(ai.get("_last_strategy_decision")) == "contest_sacred_site" and (ai.get("_objective_units") as Array).size() == 3, "a hostile Sacred claim receives all three opening fighters before 300 seconds")
	visibility_map.sacred_site = null
	ai.call("_release_objective_units")
	ai.set("difficulty", 1)
	ai.call("_check_attack_or_defend")
	_expect(launches.size() == 2 and bool(ai.get("_attack_in_progress")), "Medium retains its existing pre-five-minute attack policy")
	for fixture in army + [ai, town_center, visibility_map, site, enemy]:
		fixture.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _test_easy_paid_fighter_caps(gm: Node) -> void:
	var rm: Node = root.get_node("ResourceManager")
	for limit: int in [20, 30, 40]:
		gm.set("selected_population_limit", limit)
		gm.call("initialize_game", 2)
		gm.players[1]["age"] = 2
		gm.players[1]["population_cap"] = limit
		rm.call("initialize_player", 1, {"food": 1000, "wood": 1000, "gold": 1000})
		var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
		ai.set("difficulty", 0)
		root.add_child(ai)
		(ai.get("_decision_timer") as Timer).stop()
		ai.set("_game_time", 0.0)
		ai.set("_has_launched_field_attack", true)
		ai.set("_is_under_pressure", true)
		var fixtures: Array[Node] = [ai]
		var buildings: Array[Node] = []
		for path: String in ["res://scenes/buildings/town_center.tscn", "res://scenes/buildings/barracks.tscn", "res://scenes/buildings/archery_range.tscn", "res://scenes/buildings/stable.tscn"]:
			var building: Node = (load(path) as PackedScene).instantiate()
			building.set("player_owner", 1)
			root.add_child(building)
			building.call("complete_instantly")
			ai.call("register_building", building)
			fixtures.append(building)
			buildings.append(building)
		var fighter_cap: int = int({20: 6, 30: 9, 40: 12}[limit])
		var soldiers: Array[Node] = []
		for index: int in range(fighter_cap - 2):
			var warrior: Node = (load("res://scenes/units/infantry.tscn") as PackedScene).instantiate()
			warrior.set("player_owner", 1)
			root.add_child(warrior)
			ai.call("register_unit", warrior)
			soldiers.append(warrior)
			fixtures.append(warrior)
		_expect(bool(buildings[2].call("get_production_queue").call("enqueue_unit", UnitData.UnitType.ARCHER)), "%d paid Archer queue is accepted" % limit)
		_expect(bool(buildings[3].call("get_production_queue").call("enqueue_unit", UnitData.UnitType.CAVALRY)), "%d paid Horseman queue is accepted" % limit)
		var accepted_requests: Array[int] = []
		ai.connect("ai_wants_to_train", func(building: Node, unit_type: int) -> void:
			if bool(building.call("get_production_queue").call("enqueue_unit", unit_type)):
				accepted_requests.append(unit_type)
		)
		_expect(not bool(ai.call("_has_easy_compact_fighter_room")), "%d living plus paid pending fighters close the Easy cap" % limit)
		ai.call("_check_military_production")
		_expect(accepted_requests == [UnitData.UnitType.SCOUT], "%d full fighter budget still purchases its separate Scout" % limit)
		accepted_requests.clear()
		var full_bank: Dictionary = rm.call("get_all_resources", 1)
		ai.call("_check_military_production")
		_expect(accepted_requests.is_empty() and rm.call("get_all_resources", 1) == full_bank, "%d full pending fighter budget cannot spend on overflow troops" % limit)
		_expect(not bool(ai.call("_try_train_from_building", BuildingData.BuildingType.BARRACKS, UnitData.UnitType.INFANTRY)), "%d direct training path also enforces queued fighter cap" % limit)
		soldiers[0].call("take_damage", 1000.0)
		_expect(bool(ai.call("_has_easy_compact_fighter_room")), "%d paid casualty reopens a replacement slot" % limit)
		ai.call("_check_military_production")
		_expect(accepted_requests.size() == 1 and not bool(ai.call("_has_easy_compact_fighter_room")), "%d pressured two-train decision purchases exactly one available replacement" % limit)
		if accepted_requests.size() == 1:
			var cost: Dictionary = UnitData.get_unit_cost(accepted_requests[0])
			for kind: String in ["food", "wood", "gold"]:
				_expect(int(rm.call("get_resource", 1, kind)) == int(full_bank[kind]) - int(cost.get(kind, 0)), "%d replacement deducts the real %s cost once" % [limit, kind])
		ai.set("difficulty", 1)
		_expect(bool(ai.call("_has_easy_compact_fighter_room")), "%d Medium bypasses Easy fighter ceiling" % limit)
		ai.set("difficulty", 2)
		_expect(bool(ai.call("_has_easy_compact_fighter_room")), "%d Hard bypasses Easy fighter ceiling" % limit)
		for fixture: Node in fixtures:
			if is_instance_valid(fixture):
				fixture.free()
