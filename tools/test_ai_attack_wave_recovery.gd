extends SceneTree
## Deterministic regression for bounded AI attack-wave lifecycle state.

const AI_CONTROLLER_SCRIPT_PATH := "res://scripts/ai/ai_controller.gd"
const INFANTRY_SCENE_PATH := "res://scenes/units/infantry.tscn"
const PLAYER_AI: int = 1
const PLAYER_HUMAN: int = 0
const DIFFICULTY_HARD: int = 2
const STATE_IDLE: int = 0
const STATE_DEAD: int = 5
const NO_PROGRESS_TEST_TIME: float = 60.0
const EPSILON: float = 0.001

var _failures: Array[String] = []
var _all_units: Array[Node] = []


class AlwaysVisibleMap extends Node2D:
	var hidden_ids: Dictionary = {}

	func set_entity_visible(entity: Node2D, is_visible: bool) -> void:
		if entity != null and is_instance_valid(entity):
			hidden_ids[entity.get_instance_id()] = not is_visible

	func is_entity_visible_to_player(entity: Node2D, _viewer_player_id: int = 0) -> bool:
		return entity != null and is_instance_valid(entity) and not hidden_ids.has(entity.get_instance_id())


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ai_script: Script = load(AI_CONTROLLER_SCRIPT_PATH)
	var ai: Node = ai_script.new()
	ai.set("difficulty", DIFFICULTY_HARD)
	root.add_child(ai)
	var visibility_map := AlwaysVisibleMap.new()
	root.add_child(visibility_map)
	ai.set("game_map", visibility_map)
	ai.set("_base_position", Vector2(-1000.0, 0.0))
	ai.set("_staging_point", Vector2.ZERO)

	var launched_targets: Array[Vector2] = []
	var launched_unit_counts: Array[int] = []
	ai.connect("ai_attack_launched", func(units: Array, target: Vector2) -> void:
		launched_targets.append(target)
		launched_unit_counts.append(units.size())
	)

	var first_army: Array[Node] = _spawn_army(ai, 5, Vector2.ZERO)
	var primary_target: Node = _spawn_infantry(PLAYER_HUMAN, Vector2(600.0, 0.0))
	var secondary_target: Node = _spawn_infantry(PLAYER_HUMAN, Vector2(700.0, 0.0))

	# First eligible army launches normally.
	ai.call("_check_attack_or_defend")
	_expect(bool(ai.get("_attack_in_progress")), "first eligible army starts a tracked attack wave")
	_expect_eq(launched_targets.size(), 1, "first attack emits one launch")
	_expect_eq(launched_unit_counts[0], 5, "first launch tracks the full eligible army")
	_expect_vector_approx(ai.get("_attack_wave_target_position"), primary_target.global_position, "highest-scoring target is tracked")

	# Idle survivors at the destination close the wave. The next decision may
	# launch them again, proving the old latch no longer blocks later attacks.
	for unit in first_army:
		unit.global_position = primary_target.global_position
		unit.set("current_state", STATE_IDLE)
	ai.call("_check_attack_or_defend")
	_expect(not bool(ai.get("_attack_in_progress")), "idle survivors at destination close the completed wave")
	_expect_eq(launched_targets.size(), 1, "wave completion does not relaunch in the same decision tick")
	_move_army(first_army, Vector2.ZERO)
	ai.call("_check_attack_or_defend")
	_expect(bool(ai.get("_attack_in_progress")), "eligible survivors can launch a second wave")
	_expect_eq(launched_targets.size(), 2, "second wave emits a distinct launch")

	# If a visibly tracked target dies, surviving wave units retarget without
	# counting that order refresh as a brand-new attack wave.
	primary_target.set("current_state", STATE_DEAD)
	ai.call("_check_attack_or_defend")
	_expect(bool(ai.get("_attack_in_progress")), "wave remains active when another target is available")
	_expect_vector_approx(ai.get("_attack_wave_target_position"), secondary_target.global_position, "destroyed target is replaced by another visible target")
	_expect_eq(launched_targets.size(), 2, "retargeting does not emit an extra wave launch")
	secondary_target.set("current_state", STATE_DEAD)
	ai.call("_check_attack_or_defend")
	_expect(not bool(ai.get("_attack_in_progress")), "wave clears when its target is gone and no replacement exists")

	# A fully destroyed launched force clears its lifecycle state, and a newly
	# produced eligible army can attack afterward.
	var replacement_target: Node = _spawn_infantry(PLAYER_HUMAN, Vector2(600.0, 0.0))
	ai.call("_check_attack_or_defend")
	_expect_eq(launched_targets.size(), 3, "army launches again after target-loss recovery")
	for unit in first_army:
		unit.set("current_state", STATE_DEAD)
		ai.call("_on_unit_died", unit)
	ai.call("_check_attack_or_defend")
	_expect(not bool(ai.get("_attack_in_progress")), "wave clears when every launched unit is gone")

	var second_army: Array[Node] = _spawn_army(ai, 5, Vector2.ZERO)
	ai.set("_game_time", 0.0)
	ai.call("_check_attack_or_defend")
	_expect(bool(ai.get("_attack_in_progress")), "replacement army starts a later wave")
	_expect_eq(launched_targets.size(), 4, "replacement army produces the fourth launch")

	# With no movement or target damage, the wave times out deterministically.
	ai.set("_game_time", NO_PROGRESS_TEST_TIME)
	ai.call("_check_attack_or_defend")
	_expect(not bool(ai.get("_attack_in_progress")), "no-progress timeout releases the attack latch")
	_expect_eq(launched_targets.size(), 4, "timeout does not relaunch during the recovery tick")
	ai.call("_check_attack_or_defend")
	_expect(bool(ai.get("_attack_in_progress")), "eligible army can launch after no-progress recovery")
	_expect_eq(launched_targets.size(), 5, "post-timeout decision launches a new wave")

	# Sight loss and queue_free can occur before the next lifecycle refresh. An
	# unresolved WeakRef must remain the same position-only order as a hidden live
	# target, even while another enemy is currently available for retargeting.
	var hidden_target_position: Vector2 = replacement_target.global_position
	var hidden_target_hp: float = float(ai.get("_attack_wave_best_target_hp"))
	var alternate_target: Node = _spawn_infantry(PLAYER_HUMAN, Vector2(720.0, 0.0))
	visibility_map.set_entity_visible(replacement_target as Node2D, false)
	replacement_target.queue_free()
	await process_frame
	ai.call("_check_attack_or_defend")
	_expect(bool(ai.get("_attack_in_progress")), "hidden queue_free preserves the position-only wave")
	_expect(ai.get("_attack_wave_target_ref") == null, "hidden queue_free clears the unresolved live reference")
	_expect_vector_approx(
		ai.get("_attack_wave_target_position"),
		hidden_target_position,
		"hidden queue_free preserves the last visible target position"
	)
	_expect(absf(float(ai.get("_attack_wave_best_target_hp")) - hidden_target_hp) <= EPSILON, "hidden queue_free preserves the last visible target HP")
	_expect_eq(launched_targets.size(), 5, "hidden queue_free does not redirect to a visible alternate target")

	if is_instance_valid(replacement_target):
		replacement_target.free()
	if is_instance_valid(alternate_target):
		alternate_target.free()
	for unit in _all_units:
		if is_instance_valid(unit):
			unit.free()
	if is_instance_valid(ai):
		ai.free()
	visibility_map.free()
	_finish()


func _spawn_army(ai: Node, count: int, origin: Vector2) -> Array[Node]:
	var army: Array[Node] = []
	for index in count:
		var unit: Node = _spawn_infantry(PLAYER_AI, origin + Vector2(0.0, float(index) * 8.0))
		ai.call("register_unit", unit)
		army.append(unit)
	return army


func _spawn_infantry(owner: int, position: Vector2) -> Node:
	var infantry_scene: PackedScene = load(INFANTRY_SCENE_PATH)
	var unit: Node = infantry_scene.instantiate()
	unit.set("player_owner", owner)
	unit.global_position = position
	root.add_child(unit)
	unit.set("vision_radius", 2000.0)
	_all_units.append(unit)
	return unit


func _move_army(army: Array[Node], origin: Vector2) -> void:
	for index in army.size():
		var unit: Node = army[index]
		unit.global_position = origin + Vector2(0.0, float(index) * 8.0)
		unit.set("current_state", STATE_IDLE)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] ai_attack_wave_recovery: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_expect(false, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_vector_approx(actual: Vector2, expected: Vector2, message: String) -> void:
	if actual.distance_to(expected) <= EPSILON:
		return
	_expect(false, "%s (expected %s, got %s)" % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] ai_attack_wave_recovery: arrival, force loss, retarget, timeout, and relaunch")
		quit(0)
	else:
		quit(1)
