extends SceneTree
## Focused integration regressions for AI construction demand and combat scoring.

const AI_CONTROLLER_SCRIPT_PATH := "res://scripts/ai/ai_controller.gd"
const HOUSE_SCENE_PATH := "res://scenes/buildings/house.tscn"
const INFANTRY_SCENE_PATH := "res://scenes/units/infantry.tscn"
const PLAYER_HUMAN: int = 0
const PLAYER_AI: int = 1
const HOUSE_TYPE: int = 1
const EPSILON: float = 0.001

var _failures: Array[String] = []
var _fixtures: Array[Node] = []
var _ai: Node
var _pending_house: Node
var _house_request_count: int = 0


class AlwaysVisibleMap extends Node2D:
	func is_entity_visible_to_player(_entity: Node2D, _viewer_player_id: int = 0) -> bool:
		return true

	func is_tile_visible_to_player(_tile: Vector2i, _viewer_player_id: int = 0) -> bool:
		return true


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
	resource_manager.call("initialize_player", PLAYER_HUMAN, {"food": 1000, "wood": 1000, "gold": 1000})
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 1000, "wood": 1000, "gold": 1000})

	var ai_script: Script = load(AI_CONTROLLER_SCRIPT_PATH)
	_ai = ai_script.new()
	root.add_child(_ai)
	_fixtures.append(_ai)
	var visibility_map := AlwaysVisibleMap.new()
	root.add_child(visibility_map)
	_fixtures.append(visibility_map)
	_ai.set("game_map", visibility_map)
	_ai.set("_base_tile", Vector2i(20, 20))
	_ai.connect("ai_wants_to_build", _on_ai_wants_to_build)

	_test_pending_house_gate(game_manager)
	_test_dynamic_combat_strength(game_manager)
	_finish()


func _test_pending_house_gate(game_manager: Node) -> void:
	# Put the AI exactly at its normal "within two slots" trigger.
	game_manager.call("increase_population_cap", PLAYER_AI, 5)
	_expect(bool(game_manager.call("add_population", PLAYER_AI, 8)), "House test population setup succeeds")

	_ai.call("_check_house_need")
	_expect_eq(_house_request_count, 1, "first unmet cap need emits one House request")
	_expect(_pending_house != null, "first request creates a tracked constructing House fixture")
	if _pending_house == null:
		return
	_expect_eq(int(_pending_house.get("state")), 1, "requested House remains under construction")

	# Repeated decision ticks during the full construction time must not spend on
	# parallel Houses.
	for _decision in range(8):
		_ai.call("_check_house_need")
	_expect_eq(_house_request_count, 1, "pending House suppresses every repeated build request")

	# Model completion granting +10 cap, then fill to the new trigger. A later
	# House is valid once the first is ACTIVE and capacity is still needed.
	_pending_house.call("complete_instantly")
	game_manager.call("increase_population_cap", PLAYER_AI, 10)
	_expect(bool(game_manager.call("add_population", PLAYER_AI, 10)), "post-completion population setup succeeds")
	_ai.call("_check_house_need")
	_expect_eq(_house_request_count, 2, "a later House request is allowed after completion when still needed")


func _test_dynamic_combat_strength(game_manager: Node) -> void:
	# Reset upgrade state without replacing the AI node or its focused fixtures.
	game_manager.call("initialize_game", 2)
	# These fixtures preserve the established large-match policy contract.
	# Compact 20/30/40 skirmishes have separate population-policy coverage.
	for player_data in game_manager.players.values():
		player_data["max_population"] = 200
	var own_full: Node = _spawn_infantry(PLAYER_AI, Vector2.ZERO)
	var own_damaged: Node = _spawn_infantry(PLAYER_AI, Vector2(0.0, 8.0))
	own_damaged.set("hp", 50.0)
	var enemy: Node = _spawn_infantry(PLAYER_HUMAN, Vector2(10.0, 0.0))
	_ai.call("register_unit", own_full)
	_ai.call("register_unit", own_damaged)
	_ai.set("_base_position", Vector2.ZERO)

	_expect_float(float(_ai.call("_evaluate_army_strength")), 1100.0, "base own strength includes base attack and armor")
	_expect_float(float(_ai.call("_evaluate_enemy_visible_strength")), 600.0, "base visible-enemy strength uses the same formula")
	_ai.set("_pressure_memory", 0.0)
	_ai.set("_is_under_pressure", false)
	_ai.call("_update_pressure_state")
	_expect(not bool(_ai.get("_is_under_pressure")), "base enemy score stays below the pressure threshold")

	game_manager.call("apply_attack_upgrade", PLAYER_HUMAN, 2)
	game_manager.call("apply_armor_upgrade", PLAYER_HUMAN, 1)
	_expect_float(float(enemy.get("damage")), 8.0, "enemy base attack is not mutated by research")
	_expect_float(float(enemy.get("armor")), 2.0, "enemy base armor is not mutated by research")
	_expect_float(float(_ai.call("_evaluate_enemy_visible_strength")), 780.0, "enemy upgrades affect visible strength exactly once")
	_ai.set("_pressure_memory", 0.0)
	_ai.set("_is_under_pressure", false)
	_ai.call("_update_pressure_state")
	_expect(bool(_ai.get("_is_under_pressure")), "upgraded canonical enemy score crosses the pressure threshold")

	game_manager.call("apply_attack_upgrade", PLAYER_AI, 2)
	game_manager.call("apply_armor_upgrade", PLAYER_AI, 1)
	_expect_float(float(own_full.get("damage")), 8.0, "own base attack remains data-defined after research")
	_expect_float(float(own_full.get("armor")), 2.0, "own base armor remains data-defined after research")
	_expect_float(float(_ai.call("_evaluate_army_strength")), 1430.0, "own upgrades affect aggregate army strength exactly once")
	_expect_float(float(_ai.call("_evaluate_unit_combat_strength", own_full)), 780.0, "unit strength uses canonical effective attack and armor once")


func _on_ai_wants_to_build(building_type: int, _tile_position: Vector2i, _is_rebuild: bool) -> void:
	if building_type != HOUSE_TYPE:
		_fail("House-demand check requested unexpected building type %d" % building_type)
		return
	_house_request_count += 1
	if _house_request_count != 1:
		return
	var house_scene: PackedScene = load(HOUSE_SCENE_PATH)
	_pending_house = house_scene.instantiate()
	_pending_house.set("player_owner", PLAYER_AI)
	root.add_child(_pending_house)
	_fixtures.append(_pending_house)
	_pending_house.call("start_construction")
	_ai.call("register_building", _pending_house)


func _spawn_infantry(owner: int, position: Vector2) -> Node:
	var infantry_scene: PackedScene = load(INFANTRY_SCENE_PATH)
	var unit: Node = infantry_scene.instantiate()
	unit.set("player_owner", owner)
	unit.global_position = position
	root.add_child(unit)
	_fixtures.append(unit)
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _expect_eq(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		_fail("%s (expected %d, got %d)" % [message, expected, actual])


func _expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected) and absf(actual - expected) > EPSILON:
		_fail("%s (expected %.3f, got %.3f)" % [message, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[FAIL] ai_integration_regressions: %s" % message)


func _finish() -> void:
	for fixture in _fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	if _failures.is_empty():
		print("[PASS] ai_integration_regressions: pending House gate and canonical upgraded strength")
		quit(0)
	else:
		quit(1)
