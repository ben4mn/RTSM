extends SceneTree
## Regression for AI tracking arrays that retain freed Object placeholders.

const AI_CONTROLLER_SCRIPT_PATH := "res://scripts/ai/ai_controller.gd"
const INFANTRY_SCENE_PATH := "res://scenes/units/infantry.tscn"
const HOUSE_SCENE_PATH := "res://scenes/buildings/house.tscn"
const PLAYER_AI: int = 1

var _failures: Array[String] = []
var _fixtures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ai_script: Script = load(AI_CONTROLLER_SCRIPT_PATH)
	var ai: Node = ai_script.new()
	root.add_child(ai)
	_fixtures.append(ai)

	var live_unit: Node = _spawn_fixture(INFANTRY_SCENE_PATH)
	var freed_unit: Node = _spawn_fixture(INFANTRY_SCENE_PATH)
	var live_building: Node = _spawn_fixture(HOUSE_SCENE_PATH)
	var freed_building: Node = _spawn_fixture(HOUSE_SCENE_PATH)

	for unit in [live_unit, freed_unit]:
		unit.set("player_owner", PLAYER_AI)
		ai.call("register_unit", unit)
	for building in [live_building, freed_building]:
		building.set("player_owner", PLAYER_AI)
		ai.call("register_building", building)

	# Seed the third tracked-node array before freeing the fixture so all three
	# contain the same kind of invalid Object placeholder seen late in matches.
	ai.set("_attack_wave_units", [live_unit, freed_unit])
	freed_unit.free()
	freed_building.free()
	_expect(not is_instance_valid(freed_unit), "unit fixture is a freed Object placeholder")
	_expect(not is_instance_valid(freed_building), "building fixture is a freed Object placeholder")

	ai.call("_cleanup_references")
	_expect_single_live_reference(ai.get("_my_units"), live_unit, "unit cleanup")
	_expect_single_live_reference(ai.get("_my_buildings"), live_building, "building cleanup")
	_expect_single_live_reference(ai.get("_attack_wave_units"), live_unit, "attack-wave cleanup")
	_expect_eq(int(ai.get("_house_count")), 1, "building counts are recomputed from live references")

	# The attack-wave initializer previously had the same typed Array.filter
	# hazard, so exercise it independently with a newly freed unit reference.
	var freed_wave_unit: Node = _spawn_fixture(INFANTRY_SCENE_PATH)
	freed_wave_unit.set("player_owner", PLAYER_AI)
	var wave_candidates: Array = [live_unit, freed_wave_unit]
	freed_wave_unit.free()
	ai.call("_begin_attack_wave", wave_candidates, Vector2(128.0, 0.0), null)
	_expect_single_live_reference(ai.get("_attack_wave_units"), live_unit, "attack-wave initialization")

	_finish()


func _spawn_fixture(scene_path: String) -> Node:
	var packed: PackedScene = load(scene_path)
	var fixture: Node = packed.instantiate()
	root.add_child(fixture)
	_fixtures.append(fixture)
	return fixture


func _expect_single_live_reference(actual: Array, expected: Node, context: String) -> void:
	_expect_eq(actual.size(), 1, "%s removes invalid entries" % context)
	if actual.size() == 1:
		_expect(actual[0] == expected, "%s preserves the valid entry" % context)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] ai_freed_reference_cleanup: %s" % message)


func _expect_eq(actual: int, expected: int, message: String) -> void:
	_expect(actual == expected, "%s (expected %d, got %d)" % [message, expected, actual])


func _finish() -> void:
	for fixture in _fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	if _failures.is_empty():
		print("[PASS] ai_freed_reference_cleanup: freed unit/building/wave references are safely pruned")
		quit(0)
	else:
		quit(1)
