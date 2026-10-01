extends Node
## Direct friendly reselection preserves nearby ground commands and explicit
## Move / Attack-move destinations on touch.

var _failures: Array[String] = []
var _move_count: int = 0


class FakeGameMap extends Node2D:
	func world_to_tile(world_pos: Vector2) -> Vector2i:
		return Vector2i(roundi(world_pos.x), roundi(world_pos.y))

	func is_resource_target_valid(_node: Node2D, _resource_type: String = "", _player_id: int = -1) -> bool:
		return false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var game_map := FakeGameMap.new()
	add_child(game_map)
	var camera := Camera2D.new()
	game_map.add_child(camera)

	var selection_manager := SelectionManager.new()
	selection_manager.touch_context_enabled = false
	selection_manager.game_map = game_map
	game_map.add_child(selection_manager)
	selection_manager.move_command.connect(func(_tile: Vector2i) -> void: _move_count += 1)

	var scout_scene: PackedScene = load("res://scenes/units/scout.tscn")
	var scout: UnitBase = scout_scene.instantiate() as UnitBase
	scout.player_owner = 0
	scout.global_position = Vector2(-100.0, 0.0)
	game_map.add_child(scout)

	var building := BuildingBase.new()
	building.building_type = BuildingData.BuildingType.TOWN_CENTER
	building.player_owner = 0
	building.state = BuildingBase.State.ACTIVE
	building.global_position = Vector2.ZERO
	game_map.add_child(building)
	await get_tree().process_frame

	selection_manager.select_single(scout)
	var building_screen_position: Vector2 = selection_manager.call("_world_to_screen", building.global_position)
	selection_manager.call("_handle_tap", building_screen_position, true)
	_expect(selection_manager.selected.size() == 1 and selection_manager.selected[0] == building, "center tap directly selects the owned building")
	_expect_eq(_move_count, 0, "center tap does not emit a ground move")
	_expect_eq(String(selection_manager.touch_input_diagnostics.get("action", "")), "select_building", "diagnostics identify direct reselection: %s" % selection_manager.touch_input_diagnostics)

	selection_manager.select_single(scout)
	# Wait past the double-tap interval so this remains an independent ground tap.
	await get_tree().create_timer(0.36).timeout
	selection_manager.call("_handle_tap", building_screen_position + Vector2(31.0, 0.0), true)
	_expect(selection_manager.selected.size() == 1 and selection_manager.selected[0] == scout, "nearby ground tap retains the unit selection")
	_expect_eq(_move_count, 1, "nearby ground tap emits exactly one move")
	_expect_eq(String(selection_manager.touch_input_diagnostics.get("action", "")), "move", "nearby tap remains a move command")

	var second_scout: UnitBase = scout_scene.instantiate() as UnitBase
	second_scout.player_owner = 0
	second_scout.global_position = Vector2(140.0, 0.0)
	game_map.add_child(second_scout)
	var unit_screen_position: Vector2 = selection_manager.call("_world_to_screen", second_scout.global_position)
	selection_manager.select_single(scout)
	selection_manager.call("_handle_tap", unit_screen_position, true)
	_expect(selection_manager.selected.size() == 1 and selection_manager.selected[0] == second_scout, "center tap switches directly to a friendly unit")
	_expect_eq(_move_count, 1, "friendly unit center tap does not move the previous selection")
	_expect_eq(String(selection_manager.touch_input_diagnostics.get("action", "")), "select_unit", "unit reselection has clear diagnostics")

	selection_manager.select_single(scout)
	selection_manager.set("_last_tap_time", 0.0)
	var upper_body_screen: Vector2 = selection_manager.call("_world_to_screen", second_scout.global_position + Vector2(0.0, -25.0))
	selection_manager.call("_handle_tap", upper_body_screen, true)
	_expect(selection_manager.selected.size() == 1 and selection_manager.selected[0] == second_scout, "tap on the enlarged visible body selects above the feet hit radius")
	_expect_eq(_move_count, 1, "body tap does not send the old unit to its feet")

	# Reset the first tap to its marker before checking neighboring targets.
	selection_manager.set("_last_tap_time", 0.0)
	selection_manager.call("_handle_tap", unit_screen_position, true)
	# This tap is close enough to the previous tap to look like a double tap,
	# but targets a different unit. It must switch, not select the whole type.
	scout.global_position = second_scout.global_position + Vector2(27.0, 0.0)
	selection_manager.call("_handle_tap", selection_manager.call("_world_to_screen", scout.global_position), true)
	_expect(selection_manager.selected.size() == 1 and selection_manager.selected[0] == scout, "rapid tap on a different nearby unit remains direct selection")

	scout.global_position = Vector2(-100.0, 0.0)
	selection_manager.select_single(scout)
	selection_manager.set("_last_tap_time", 0.0)
	selection_manager.call("_handle_tap", unit_screen_position + Vector2(21.0, 0.0), true)
	_expect(selection_manager.selected.size() == 1 and selection_manager.selected[0] == scout, "outer unit hit ring retains selected units")
	_expect_eq(_move_count, 2, "outer unit hit ring emits a ground move")

	selection_manager.select_single(scout)
	selection_manager.set_unit_command_armed(true)
	selection_manager.call("_handle_tap", unit_screen_position, true)
	_expect(selection_manager.selected.size() == 1 and selection_manager.selected[0] == scout, "armed destination on a friendly unit keeps the previous selection")
	_expect_eq(_move_count, 3, "armed destination on a friendly unit still emits a move")
	_expect_eq(String(selection_manager.touch_input_diagnostics.get("action", "")), "armed_command", "armed mode wins over reselection")

	game_map.free()
	if _failures.is_empty():
		print("[PASS] touch_building_reselection: direct unit/building switches; ground and armed commands retained")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] touch_building_reselection: %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
