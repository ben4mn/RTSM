extends SceneTree
## Regression for exactly-once single-action touch context gestures.

const SELECTION_MANAGER_SCRIPT_PATH := "res://scripts/managers/selection_manager.gd"
const INFANTRY_SCENE_PATH := "res://scenes/units/infantry.tscn"
const MOVE_ACTION_ID: int = 100

var _failures: Array[String] = []


class FakeGameMap extends Node2D:
	func world_to_tile(world_pos: Vector2) -> Vector2i:
		return Vector2i(roundi(world_pos.x / 16.0), roundi(world_pos.y / 16.0))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("AudioManager").call("set_all_enabled", false)
	var game_map := FakeGameMap.new()
	root.add_child(game_map)

	var selection_script: Script = load(SELECTION_MANAGER_SCRIPT_PATH)
	var selection_manager: Node = selection_script.new()
	selection_manager.set("game_map", game_map)
	selection_manager.set("long_press_threshold", 0.35)
	game_map.add_child(selection_manager)

	var infantry_scene: PackedScene = load(INFANTRY_SCENE_PATH)
	var selected_unit: Node2D = infantry_scene.instantiate() as Node2D
	selected_unit.set("player_owner", 0)
	selected_unit.global_position = Vector2.ZERO
	game_map.add_child(selected_unit)
	selection_manager.call("select_single", selected_unit)
	await process_frame

	var move_tiles: Array[Vector2i] = []
	selection_manager.connect("move_command", func(tile: Vector2i) -> void:
		move_tiles.append(tile)
	)

	var before: Dictionary = selection_manager.get("touch_context_diagnostics") as Dictionary
	var before_count: int = int(before.get("execution_count", 0))
	var empty_ground := Vector2(400.0, 200.0)
	selection_manager.call("_handle_touch", _touch_event(empty_ground, true))
	selection_manager.call("_process", 0.36)

	var after_threshold: Dictionary = selection_manager.get("touch_context_diagnostics") as Dictionary
	_expect_eq(move_tiles.size(), 1, "threshold crossing executes the single Move action once")
	_expect_eq(String(after_threshold.get("last_executed_action", "")), "Move", "diagnostics identify the executed context action")
	_expect_eq(int(after_threshold.get("last_executed_action_id", -1)), MOVE_ACTION_ID, "diagnostics retain the Move action id")
	_expect_eq(int(after_threshold.get("execution_count", -1)), before_count + 1, "diagnostics count one threshold execution")
	var first_timestamp: int = int(after_threshold.get("last_executed_timestamp_ms", 0))
	_expect(first_timestamp > 0, "diagnostics include a fresh execution timestamp")

	selection_manager.call("_handle_touch", _touch_event(empty_ground, false))
	var after_release: Dictionary = selection_manager.get("touch_context_diagnostics") as Dictionary
	_expect_eq(move_tiles.size(), 1, "release does not execute Move again after threshold dispatch")
	_expect_eq(int(after_release.get("execution_count", -1)), before_count + 1, "release does not increment context execution count")
	_expect_eq(int(after_release.get("last_executed_timestamp_ms", -1)), first_timestamp, "release preserves the original execution timestamp")

	selection_manager.call("_refresh_touch_context_diagnostics")
	var after_refresh: Dictionary = selection_manager.get("touch_context_diagnostics") as Dictionary
	_expect_eq(String(after_refresh.get("last_executed_action", "")), "Move", "diagnostic refresh retains the last executed action")
	_expect_eq(int(after_refresh.get("last_executed_timestamp_ms", -1)), first_timestamp, "diagnostic refresh retains the last execution timestamp")

	# Sparse frames can miss the process threshold. The release-time fallback
	# still executes exactly once and updates the durable evidence.
	var fallback_ground := Vector2(480.0, 240.0)
	selection_manager.set("long_press_threshold", 0.005)
	selection_manager.call("_handle_touch", _touch_event(fallback_ground, true))
	selection_manager.set("_touch_hold_started_at_msec", maxi(1, Time.get_ticks_msec() - 20))
	selection_manager.call("_handle_touch", _touch_event(fallback_ground, false))
	var after_fallback: Dictionary = selection_manager.get("touch_context_diagnostics") as Dictionary
	_expect_eq(move_tiles.size(), 2, "release fallback executes one Move action")
	_expect_eq(int(after_fallback.get("execution_count", -1)), before_count + 2, "fallback adds exactly one context execution")
	_expect_eq(String(after_fallback.get("last_executed_action", "")), "Move", "fallback records fresh Move evidence")
	_expect(int(after_fallback.get("last_executed_timestamp_ms", 0)) >= first_timestamp, "fallback timestamp is not stale")

	game_map.free()
	_finish()


func _touch_event(position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	return event


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] touch_long_press_context: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_expect(false, "%s (expected %s, got %s)" % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] touch_long_press_context: single dispatch, release fallback, durable runtime evidence")
		quit(0)
	else:
		quit(1)
