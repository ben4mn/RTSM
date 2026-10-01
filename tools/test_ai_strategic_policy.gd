extends SceneTree
## Focused contracts for fair difficulty scaling and deliberate AI strategy.

const AI_CONTROLLER_SCRIPT_PATH := "res://scripts/ai/ai_controller.gd"
const TOWN_CENTER_SCENE_PATH := "res://scenes/buildings/town_center.tscn"
const BARRACKS_SCENE_PATH := "res://scenes/buildings/barracks.tscn"
const SACRED_SITE_SCENE_PATH := "res://scenes/map/sacred_site.tscn"
const VILLAGER_SCENE_PATH := "res://scenes/units/villager.tscn"
const INFANTRY_SCENE_PATH := "res://scenes/units/infantry.tscn"
const SCOUT_SCENE_PATH := "res://scenes/units/scout.tscn"

const PLAYER_HUMAN: int = 0
const PLAYER_AI: int = 1
const DIFFICULTY_EASY: int = 0
const DIFFICULTY_MEDIUM: int = 1
const DIFFICULTY_HARD: int = 2
const SITE_NEUTRAL: int = 0
const SITE_CAPTURING: int = 1
const SITE_CAPTURED: int = 2
const SITE_CONTESTED: int = 3
const BARRACKS_TYPE: int = 2
const FARM_TYPE: int = 5
const EPSILON: float = 0.001

var _failures: Array[String] = []
var _fixtures: Array = []
var _ai: Node
var _strategy_map: StrategyMap
var _site: StrategySacredSite


class StrategySacredSite extends Node2D:
	var state: int = SITE_NEUTRAL
	var owning_player: int = -1
	var capture_radius: int = 3
	var victory_hold_time: float = 180.0
	var victory_timer: float = 0.0


class StrategyMap extends Node2D:
	var sacred_site: Node2D
	var use_navigation_route_override: bool = false
	var navigation_route_override := PackedVector2Array()

	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2(float(tile.x - tile.y) * 32.0, float(tile.x + tile.y) * 16.0)

	func world_to_tile(world_position: Vector2) -> Vector2i:
		var tile_x: int = roundi((world_position.x / 32.0 + world_position.y / 16.0) * 0.5)
		var tile_y: int = roundi((world_position.y / 16.0 - world_position.x / 32.0) * 0.5)
		return Vector2i(tile_x, tile_y)

	func is_tile_walkable(_tile_position: Vector2i) -> bool:
		return true

	func is_tile_visible_to_player(_tile_position: Vector2i, _viewer_player_id: int = 0) -> bool:
		# This policy fixture models an already scouted build area. Dedicated
		# resource-fog regressions exercise the production visibility boundary.
		return true

	func is_entity_visible_to_player(entity: Node2D, viewer_player_id: int = 0) -> bool:
		var entity_owner: int = int(entity.get("player_owner")) if entity.get("player_owner") != null else -1
		if entity_owner == viewer_player_id:
			return true
		for node: Node in get_tree().get_nodes_in_group("units"):
			if node.get("player_owner") == null or node.get("current_state") == null:
				continue
			if int(node.get("player_owner")) != viewer_player_id or int(node.get("current_state")) == 5:
				continue
			if node is Node2D and (node as Node2D).global_position.distance_to(entity.global_position) <= float(node.get("vision_radius")):
				return true
		for node: Node in get_tree().get_nodes_in_group("buildings"):
			if node.get("player_owner") == null or node.get("state") == null:
				continue
			if int(node.get("player_owner")) != viewer_player_id or int(node.get("state")) == 3:
				continue
			var stats: Dictionary = BuildingData.get_building_stats(int(node.get("building_type")))
			var vision_world: float = MapData.range_tiles_to_world(float(stats.get("vision_radius", 3)))
			if node is Node2D and (node as Node2D).global_position.distance_to(entity.global_position) <= vision_world:
				return true
		return false

	func get_navigation_world_path(
		_from_world: Vector2,
		target_world: Vector2,
		_arrival_radius_world: float = 4.0,
		_max_goal_radius_tiles: int = 8
	) -> PackedVector2Array:
		if use_navigation_route_override:
			return navigation_route_override.duplicate()
		# Real isometric navigation terminates at a nearby tile center rather than
		# the arbitrary requested world point.
		return PackedVector2Array([target_world + Vector2(0.0, 24.0)])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_manager: Node = root.get_node("GameManager")
	var resource_manager: Node = root.get_node("ResourceManager")
	root.get_node("AudioManager").call("set_all_enabled", false)
	game_manager.call("initialize_game", 2)
	# These fixtures preserve the established large-match policy contract.
	# Compact 20/30/40 skirmishes have separate population-policy coverage.
	for player_data in game_manager.players.values():
		player_data["max_population"] = 200
	resource_manager.call("reset")
	resource_manager.call("initialize_player", PLAYER_HUMAN, {"food": 5000, "wood": 5000, "gold": 5000})
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 5000, "wood": 5000, "gold": 5000})

	_strategy_map = StrategyMap.new()
	root.add_child(_strategy_map)
	_fixtures.append(_strategy_map)
	_site = StrategySacredSite.new()
	_site.global_position = Vector2(420.0, 180.0)
	_strategy_map.add_child(_site)
	_strategy_map.sacred_site = _site

	_test_fair_difficulty_profiles(resource_manager)
	_test_opening_military_liveness(resource_manager)
	_test_one_scout_capture_policy()
	_test_scout_recon_timing_boundary()
	_setup_hard_strategy_fixture()
	_test_sacred_site_policy()
	_test_base_defense_and_sighting_memory()
	_test_rebuild_memory()
	_finish()


func _test_fair_difficulty_profiles(resource_manager: Node) -> void:
	var expected_intervals: Array[float] = [2.0, 1.5, 1.0]
	for difficulty in [DIFFICULTY_EASY, DIFFICULTY_MEDIUM, DIFFICULTY_HARD]:
		resource_manager.call("initialize_player", PLAYER_AI, {"food": 777, "wood": 666, "gold": 555})
		var ai: Node = load(AI_CONTROLLER_SCRIPT_PATH).new()
		root.add_child(ai)
		_fixtures.append(ai)
		# Mirrors Main: difficulty is assigned after the scene node became ready.
		ai.set("difficulty", difficulty)
		ai.set("game_map", _strategy_map)
		ai.call("start_ai", Vector2i(10, 10), _strategy_map.tile_to_world(Vector2i(10, 10)))
		(ai.get("_decision_timer") as Timer).stop()
		var snapshot: Dictionary = ai.call("get_strategy_snapshot")
		_expect_float(float(snapshot.get("decision_interval", -1.0)), expected_intervals[difficulty], "difficulty %d reapplies its decision cadence at match start" % difficulty)
		var modifiers: Dictionary = snapshot.get("economic_modifiers", {})
		for modifier in modifiers.values():
			_expect_float(float(modifier), 0.0, "difficulty %d reports no hidden economic modifier" % difficulty)
		ai.call("_process", 60.0)
		_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "food")), 777, "difficulty %d grants no starting/passive food" % difficulty)
		_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), 666, "difficulty %d grants no starting/passive wood" % difficulty)
		_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "gold")), 555, "difficulty %d grants no starting/passive gold" % difficulty)


func _test_one_scout_capture_policy() -> void:
	var start_times: Array[float] = [270.0, 150.0, 90.0]
	for difficulty in [DIFFICULTY_EASY, DIFFICULTY_MEDIUM, DIFFICULTY_HARD]:
		_site.state = SITE_NEUTRAL
		_site.owning_player = -1
		var ai: Node = load(AI_CONTROLLER_SCRIPT_PATH).new()
		root.add_child(ai)
		_fixtures.append(ai)
		ai.set("difficulty", difficulty)
		ai.set("game_map", _strategy_map)
		var base_position: Vector2 = _strategy_map.tile_to_world(Vector2i(10, 10))
		ai.call("start_ai", Vector2i(10, 10), base_position)
		(ai.get("_decision_timer") as Timer).stop()
		var town_center: Node = _spawn_fixture(TOWN_CENTER_SCENE_PATH, PLAYER_AI, base_position)
		ai.call("register_building", town_center)
		var scout: Node = _spawn_fixture(SCOUT_SCENE_PATH, PLAYER_AI, base_position + Vector2(24.0, 0.0))
		ai.call("register_unit", scout)
		ai.set("_game_time", start_times[difficulty] + 1.0)

		var reserve: Array = ai.call("_get_base_reserve_units", [scout])
		_expect(reserve.is_empty(), "difficulty %d does not consume its only Scout as a passive base reserve" % difficulty)
		ai.call("_check_sacred_site_strategy")
		var snapshot: Dictionary = ai.call("get_strategy_snapshot")
		_expect_eq(str(snapshot.get("objective_mode", "")), "capture", "difficulty %d activates its timed capture policy" % difficulty)
		_expect_eq(int(snapshot.get("objective_unit_count", 0)), 1, "difficulty %d dispatches its lone Scout instead of reporting an empty capture" % difficulty)
		_expect_eq(int(scout.get("current_state")), 1, "difficulty %d gives the lone Scout a real movement order" % difficulty)
		_expect((scout.get("move_target") as Vector2).distance_to(_site.global_position) <= 48.0, "difficulty %d Scout heads inside the Sacred Site capture ring" % difficulty)

		var home_threat: Node = _spawn_fixture(INFANTRY_SCENE_PATH, PLAYER_HUMAN, base_position + Vector2(32.0, 0.0))
		ai.call("_check_attack_or_defend")
		snapshot = ai.call("get_strategy_snapshot")
		_expect_eq(int(snapshot.get("objective_unit_count", -1)), 0, "difficulty %d releases the Scout when the base is actually threatened" % difficulty)
		_expect(scout.get("attack_target") == null, "difficulty %d keeps the reconnaissance Scout out of combat" % difficulty)
		_expect_eq(int(scout.get("current_state")), 1, "difficulty %d evacuates an exposed reconnaissance Scout" % difficulty)
		_expect((scout.get("move_target") as Vector2).distance_to(home_threat.global_position) > 80.0, "difficulty %d gives the Scout a refuge outside melee exposure" % difficulty)

		ai.free()
		town_center.free()
		scout.free()
		home_threat.free()


func _test_opening_military_liveness(resource_manager: Node) -> void:
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 200, "wood": 200, "gold": 100})
	var ai: Node = load(AI_CONTROLLER_SCRIPT_PATH).new()
	root.add_child(ai)
	_fixtures.append(ai)
	ai.set("difficulty", DIFFICULTY_MEDIUM)
	ai.set("game_map", _strategy_map)
	var base_position: Vector2 = _strategy_map.tile_to_world(Vector2i(10, 10))
	ai.call("start_ai", Vector2i(10, 10), base_position)
	(ai.get("_decision_timer") as Timer).stop()
	var town_center: Node = _spawn_fixture(TOWN_CENTER_SCENE_PATH, PLAYER_AI, base_position)
	town_center.call("complete_instantly")
	ai.call("register_building", town_center)
	var villager: Node = _spawn_fixture(VILLAGER_SCENE_PATH, PLAYER_AI, base_position + Vector2(16.0, 16.0))
	ai.call("register_unit", villager)

	var requested_buildings: Array[int] = []
	ai.connect("ai_wants_to_build", func(building_type: int, _tile_position: Vector2i, _is_rebuild: bool) -> void:
		requested_buildings.append(building_type)
	)
	ai.call("_check_building_construction")
	_expect_eq(requested_buildings.size(), 1, "fair opening issues one affordable construction request")
	if not requested_buildings.is_empty():
		_expect_eq(requested_buildings[0], FARM_TYPE, "fair opening secures paid renewable food before its production unlock")

	ai.set("_saving_for_age_up", true)
	_expect(bool(ai.call("_is_essential_building_while_saving", BARRACKS_TYPE)), "age-up saving cannot suppress the first Barracks")

	resource_manager.call("try_spend", PLAYER_AI, BuildingData.get_building_cost(BARRACKS_TYPE))
	var barracks: Node = _spawn_fixture(BARRACKS_SCENE_PATH, PLAYER_AI, base_position + Vector2(96.0, 32.0))
	barracks.call("complete_instantly")
	ai.call("register_building", barracks)
	var scout: Node = _spawn_fixture(SCOUT_SCENE_PATH, PLAYER_AI, base_position + Vector2(24.0, 0.0))
	ai.call("register_unit", scout)
	var requested_units: Array[int] = []
	ai.connect("ai_wants_to_train", func(_building: Node, unit_type: int) -> void:
		requested_units.append(unit_type)
	)
	ai.call("_check_military_production")
	_expect_eq(requested_units.size(), 1, "unlocked Barracks produces from the remaining fair starting economy")
	if not requested_units.is_empty():
		_expect_eq(requested_units[0], UnitData.UnitType.INFANTRY, "one-Scout opening proceeds to a line combat unit")

	ai.free()
	town_center.free()
	villager.free()
	barracks.free()
	scout.free()
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 5000, "wood": 5000, "gold": 5000})


func _test_scout_recon_timing_boundary() -> void:
	var start_times: Array[float] = [270.0, 150.0, 90.0]
	for difficulty in [DIFFICULTY_EASY, DIFFICULTY_MEDIUM, DIFFICULTY_HARD]:
		var movement_map := StrategyMap.new()
		root.add_child(movement_map)
		var sacred_site: Node2D = load(SACRED_SITE_SCENE_PATH).instantiate()
		sacred_site.global_position = Vector2(640.0, 320.0)
		movement_map.add_child(sacred_site)
		movement_map.sacred_site = sacred_site
		var base_position: Vector2 = sacred_site.global_position + Vector2(-640.0, 0.0)
		var scout: Node = load(SCOUT_SCENE_PATH).instantiate()
		scout.set("player_owner", PLAYER_AI)
		scout.global_position = base_position
		movement_map.add_child(scout)
		var recon_scouts: Array = [scout]
		if difficulty == DIFFICULTY_HARD:
			var second_scout: Node = load(SCOUT_SCENE_PATH).instantiate()
			second_scout.set("player_owner", PLAYER_AI)
			second_scout.global_position = base_position + Vector2(0.0, 32.0)
			movement_map.add_child(second_scout)
			recon_scouts.append(second_scout)
		var ai: Node = load(AI_CONTROLLER_SCRIPT_PATH).new()
		root.add_child(ai)
		ai.set("difficulty", difficulty)
		ai.set("game_map", movement_map)
		ai.call("start_ai", Vector2i(5, 5), base_position)
		(ai.get("_decision_timer") as Timer).stop()
		for recon_scout in recon_scouts:
			ai.call("register_unit", recon_scout)
		ai.set("_game_time", start_times[difficulty] - 0.01)

		# Both injected waypoints are outside the capture disk, but the chord from
		# the Scout through the far-side waypoint crosses its center. Endpoint-only
		# validation would miss this exact live-match failure.
		var recon_position: Vector2 = (ai.get("_scout_waypoints") as Array)[0]
		movement_map.use_navigation_route_override = true
		movement_map.navigation_route_override = PackedVector2Array([
			sacred_site.global_position + Vector2(320.0, 0.0),
			recon_position,
		])
		ai.call("_check_scouting")
		_expect_eq(int(scout.get("current_state")), 0, "difficulty %d rejects a pre-policy route whose safe endpoints conceal a capture-ring crossing" % difficulty)

		movement_map.use_navigation_route_override = false
		ai.call("_check_scouting")
		_expect_eq(int(scout.get("current_state")), 1, "difficulty %d begins a validated outside-ring recon route" % difficulty)
		for step in 80:
			for recon_scout in recon_scouts:
				recon_scout.call("_process", 0.1)
			if step % 10 == 0:
				ai.call("_check_scouting")
			sacred_site.call("_process", 0.1)
		_expect_eq(int(sacred_site.get("state")), SITE_NEUTRAL, "difficulty %d remains neutral immediately below its configured policy boundary" % difficulty)
		_expect_eq(int(sacred_site.get("owning_player")), -1, "difficulty %d Scout never starts an early own claim while moving and holding" % difficulty)
		var capture_radius_world: float = float(sacred_site.get("capture_radius")) * float(MapData.TILE_WIDTH)
		_expect(scout.global_position.distance_to(sacred_site.global_position) > capture_radius_world, "difficulty %d Scout holds physically outside the capture ring" % difficulty)
		ai.call("_check_sacred_site_strategy")
		var snapshot: Dictionary = ai.call("get_strategy_snapshot")
		_expect_eq(str(snapshot.get("objective_mode", "")), "scout", "difficulty %d does not promote recon before the exact start time" % difficulty)
		_expect_eq(int(snapshot.get("objective_unit_count", -1)), recon_scouts.size(), "difficulty %d keeps every pre-policy Scout reserved from unrelated raids" % difficulty)

		# A genuine visible site threat still overrides the clock.
		var site_threat: Node = load(INFANTRY_SCENE_PATH).instantiate()
		site_threat.set("player_owner", PLAYER_HUMAN)
		site_threat.global_position = sacred_site.global_position + Vector2(-200.0, 0.0)
		movement_map.add_child(site_threat)
		ai.call("_check_sacred_site_strategy")
		snapshot = ai.call("get_strategy_snapshot")
		_expect_eq(str(snapshot.get("objective_mode", "")), "contest", "difficulty %d visible site threat preempts the policy timer" % difficulty)
		ai.call("_release_objective_units")
		for recon_scout in recon_scouts:
			recon_scout.call("command_stop")
		site_threat.free()

		# Ownership state is authoritative even when the claiming enemy is unseen.
		sacred_site.set("state", SITE_CAPTURING)
		sacred_site.set("owning_player", PLAYER_HUMAN)
		ai.call("_check_sacred_site_strategy")
		snapshot = ai.call("get_strategy_snapshot")
		_expect_eq(str(snapshot.get("objective_mode", "")), "contest", "difficulty %d enemy claim preempts the policy timer without hidden-unit tracking" % difficulty)
		ai.call("_release_objective_units")
		for recon_scout in recon_scouts:
			recon_scout.call("command_stop")
		sacred_site.set("state", SITE_NEUTRAL)
		sacred_site.set("owning_player", -1)
		sacred_site.set("capture_progress", 0.0)

		ai.set("_game_time", start_times[difficulty])
		ai.call("_check_sacred_site_strategy")
		snapshot = ai.call("get_strategy_snapshot")
		_expect_eq(str(snapshot.get("objective_mode", "")), "capture", "difficulty %d promotes recon at the configured start time" % difficulty)
		_expect_eq(int(snapshot.get("objective_unit_count", 0)), recon_scouts.size(), "difficulty %d assigns every available Scout at the configured boundary" % difficulty)
		for _step in 400:
			for recon_scout in recon_scouts:
				recon_scout.call("_process", 0.1)
			sacred_site.call("_process", 0.1)
			if int(sacred_site.get("state")) == SITE_CAPTURED:
				break
		_expect_eq(int(sacred_site.get("state")), SITE_CAPTURED, "difficulty %d Scout enters and completes capture after the boundary" % difficulty)
		_expect_eq(int(sacred_site.get("owning_player")), PLAYER_AI, "difficulty %d post-boundary capture belongs to the AI" % difficulty)

		ai.free()
		movement_map.free()


func _setup_hard_strategy_fixture() -> void:
	_ai = load(AI_CONTROLLER_SCRIPT_PATH).new()
	root.add_child(_ai)
	_fixtures.append(_ai)
	_ai.set("difficulty", DIFFICULTY_HARD)
	_ai.set("game_map", _strategy_map)
	_ai.call("start_ai", Vector2i(10, 10), _strategy_map.tile_to_world(Vector2i(10, 10)))
	(_ai.get("_decision_timer") as Timer).stop()

	var town_center: Node = _spawn_fixture(TOWN_CENTER_SCENE_PATH, PLAYER_AI, _strategy_map.tile_to_world(Vector2i(10, 10)))
	_ai.call("register_building", town_center)
	var villager: Node = _spawn_fixture(VILLAGER_SCENE_PATH, PLAYER_AI, Vector2(20.0, 20.0))
	_ai.call("register_unit", villager)
	var scout: Node = _spawn_fixture(SCOUT_SCENE_PATH, PLAYER_AI, Vector2(40.0, 20.0))
	_ai.call("register_unit", scout)
	for index in 8:
		var infantry: Node = _spawn_fixture(INFANTRY_SCENE_PATH, PLAYER_AI, Vector2(30.0, float(index) * 10.0))
		infantry.set("vision_radius", 2000.0)
		_ai.call("register_unit", infantry)


func _test_sacred_site_policy() -> void:
	_site.state = SITE_NEUTRAL
	_site.owning_player = -1
	_ai.set("_game_time", 100.0)
	var blocks_offense: bool = bool(_ai.call("_check_sacred_site_strategy"))
	var snapshot: Dictionary = _ai.call("get_strategy_snapshot")
	_expect(not blocks_offense, "neutral capture leaves surplus field forces available")
	_expect_eq(str(snapshot.get("objective_mode", "")), "capture", "Hard deliberately enters Sacred Site capture mode")
	_expect_eq(int(snapshot.get("objective_unit_count", -1)), 4, "Hard assigns its configured capture force")

	_site.state = SITE_CAPTURED
	_site.owning_player = PLAYER_AI
	_ai.call("_check_sacred_site_strategy")
	snapshot = _ai.call("get_strategy_snapshot")
	_expect_eq(str(snapshot.get("objective_mode", "")), "defend", "owned Sacred Site switches to defense")
	_expect_eq(int(snapshot.get("objective_unit_count", -1)), 3, "Hard retains a bounded Sacred Site garrison")

	_site.state = SITE_CAPTURED
	_site.owning_player = PLAYER_HUMAN
	_site.victory_timer = 130.0
	blocks_offense = bool(_ai.call("_check_sacred_site_strategy"))
	snapshot = _ai.call("get_strategy_snapshot")
	_expect(blocks_offense, "enemy Sacred Site hold suppresses unrelated offense")
	_expect_eq(str(snapshot.get("objective_mode", "")), "contest", "enemy-owned Sacred Site triggers contest mode")
	_expect(int(snapshot.get("objective_unit_count", 0)) >= 7, "late enemy hold recalls a full contest force")


func _test_base_defense_and_sighting_memory() -> void:
	var enemy: Node = _spawn_fixture(INFANTRY_SCENE_PATH, PLAYER_HUMAN, Vector2(20.0, 300.0))
	var remembered_position: Vector2 = enemy.global_position
	_ai.call("_update_pressure_state")
	_ai.call("_update_enemy_memory")
	_ai.call("_check_attack_or_defend")
	var snapshot: Dictionary = _ai.call("get_strategy_snapshot")
	_expect_eq(str(snapshot.get("last_decision", "")), "base_defense", "home threat overrides the Sacred Site contest")
	_expect_eq(int(snapshot.get("objective_unit_count", -1)), 0, "base defense releases the objective detachment")

	enemy.global_position = Vector2(6000.0, 6000.0)
	var memory_target: Dictionary = _ai.call("_find_enemy_target_selection")
	_expect_eq(str(memory_target.get("source", "")), "memory", "unseen enemy becomes a last-known-position target")
	_expect(memory_target.get("node") == null, "memory never keeps a hidden enemy as a live command target")
	_expect_vector_approx(memory_target.get("position", Vector2.ZERO), remembered_position, "memory preserves the last legal sighting")

	_ai.set("_game_time", 200.0)
	var expired_target: Dictionary = _ai.call("_find_enemy_target_selection")
	_expect(expired_target.is_empty(), "Hard sighting memory expires after its bounded lifetime")


func _test_rebuild_memory() -> void:
	var barracks: Node = _spawn_fixture(BARRACKS_SCENE_PATH, PLAYER_AI, Vector2(64.0, 64.0))
	_ai.call("register_building", barracks)
	_ai.call("_on_ai_building_destroyed", barracks)
	var snapshot: Dictionary = _ai.call("get_strategy_snapshot")
	var rebuild_requests: Dictionary = snapshot.get("rebuild_requests", {})
	_expect_eq(int(rebuild_requests.get(BARRACKS_TYPE, 0)), 1, "destroyed production building enters rebuild memory")

	var requested_types: Array[int] = []
	_ai.connect("ai_wants_to_build", func(building_type: int, _tile_position: Vector2i, _is_rebuild: bool) -> void:
		requested_types.append(building_type)
	)
	var requested: bool = bool(_ai.call("_check_rebuilding"))
	_expect(requested, "affordable remembered infrastructure requests a rebuild")
	_expect_eq(requested_types.size(), 1, "one rebuild is requested per decision")
	if not requested_types.is_empty():
		_expect_eq(requested_types[0], BARRACKS_TYPE, "rebuild restores the lost production type")
	snapshot = _ai.call("get_strategy_snapshot")
	rebuild_requests = snapshot.get("rebuild_requests", {})
	_expect_eq(int(rebuild_requests.get(BARRACKS_TYPE, 0)), 0, "issued replacement consumes one rebuild request")


func _spawn_fixture(scene_path: String, owner: int, position: Vector2) -> Node:
	var packed: PackedScene = load(scene_path)
	var fixture: Node = packed.instantiate()
	fixture.set("player_owner", owner)
	fixture.set("global_position", position)
	root.add_child(fixture)
	_fixtures.append(fixture)
	return fixture


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] ai_strategic_policy: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_float(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) <= EPSILON, "%s (expected %.3f, got %.3f)" % [message, expected, actual])


func _expect_vector_approx(actual: Vector2, expected: Vector2, message: String) -> void:
	_expect(actual.distance_to(expected) <= EPSILON, "%s (expected %s, got %s)" % [message, expected, actual])


func _finish() -> void:
	for fixture in _fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	if _failures.is_empty():
		print("[PASS] ai_strategic_policy: fair difficulty, objective policy, defense, memory, and rebuilding")
		quit(0)
	else:
		quit(1)
