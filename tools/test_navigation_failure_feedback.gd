extends Node
## Actual Main spawn/signal/HUD wiring for bounded path rejection feedback.
var failures: Array[String] = []
var main: Node
var hud: CanvasLayer

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_expect(main.get("_building_placement") != null, "actual Main initializes")
	if main.get("_building_placement") == null:
		_finish()
		return
	main.set_process(false)
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("AIController").get("_decision_timer").stop()
	main.get_node("StrategyController").set_process(false)
	var map: Node2D = main.get("game_map")
	map.set_process(false)
	hud = main.get("hud")
	for node: Node in get_tree().get_nodes_in_group("units"):
		node.set_process(false)
	var unit: UnitBase = main.get("_player_units")[0][0]
	var other: UnitBase = main.get("_player_units")[0][1]
	var enemy: UnitBase = main.get("_player_units")[1][0]
	var center := Vector2i(20, 20)
	var pathfinder: Pathfinding = map.get("pathfinding")
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			pathfinder.set_solid(center + Vector2i(x, y), x != 0 or y != 0)
	unit.position = map.tile_to_world(center)
	other.position = unit.position
	var target: Vector2 = map.tile_to_world(Vector2i(27, 20))
	var selection: SelectionManager = map.get("selection_mgr")
	selection.select_single(unit)
	_clear_notices()
	unit.command_move(target)
	for tick: int in 100:
		unit._process(0.05)
		if unit.current_state == UnitBase.State.IDLE:
			break
	_expect(unit.current_state == UnitBase.State.IDLE and unit.position == map.tile_to_world(center), "real unreachable order stops without passing through walls")
	_expect(_notices().size() == 1 and _notices()[0].begins_with("Route blocked."), "selected owned unit's real navigation signal reaches the HUD")
	var original_message: String = _notices()[0] if not _notices().is_empty() else ""
	_expect(not original_message.contains("20") and not original_message.contains("enemy"), "feedback contains no hidden coordinates or blocker identity")
	selection.select_many([unit, other])
	other.navigation_failed.emit(other, target)
	unit.navigation_failed.emit(unit, target)
	_expect(_notices().size() == 1, "group failure burst produces only one notice")
	_clear_notices()
	main.set("_navigation_feedback_available_msec", 0)
	other.navigation_failed.emit(other, target)
	_expect(_notices().size() == 1, "feedback can recur after the throttle expires")
	_clear_notices()
	selection.deselect_all()
	main.set("_navigation_feedback_available_msec", 0)
	unit.navigation_failed.emit(unit, target)
	_expect(_notices().is_empty(), "unselected autonomous failures remain quiet")
	selection.select_single(enemy)
	main.call("_on_player_unit_navigation_failed", enemy, target)
	_expect(_notices().is_empty(), "enemy inspection cannot produce owned-order feedback")
	selection.select_single(unit)
	for state: GameManager.GameState in [GameManager.GameState.PAUSED, GameManager.GameState.GAME_OVER, GameManager.GameState.MENU]:
		GameManager.current_state = state
		unit.navigation_failed.emit(unit, target)
	_expect(_notices().is_empty(), "pause, game over and menu suppress stale feedback")
	GameManager.current_state = GameManager.GameState.PLAYING
	unit.current_state = UnitBase.State.DEAD
	unit.navigation_failed.emit(unit, target)
	_expect(_notices().is_empty(), "dead units cannot emit stale feedback")
	unit.current_state = UnitBase.State.IDLE
	_finish()

func _clear_notices() -> void:
	for child: Node in (hud.get("_notification_container") as Control).get_children():
		child.free()

func _notices() -> Array[String]:
	var result: Array[String] = []
	for child: Node in (hud.get("_notification_container") as Control).get_children():
		if not child.is_queued_for_deletion() and child.get_child_count() > 0 and child.get_child(0) is Label:
			result.append((child.get_child(0) as Label).text)
	return result

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	main.free()
	for failure: String in failures:
		push_error("[FAIL] navigation_failure_feedback: " + failure)
	if failures.is_empty():
		print("[PASS] navigation_failure_feedback: actual unreachable signal/HUD, selected owner, group throttle and inactive/dead/context gates")
	get_tree().quit(0 if failures.is_empty() else 1)
