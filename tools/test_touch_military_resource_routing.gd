extends Node
## Verifies a selected military unit moves, rather than gathers, when a resource is tapped.

var _failures: Array[String] = []
var _move_count: int = 0
var _gather_count: int = 0


class FakeGameMap extends Node2D:
	func world_to_tile(_world_pos: Vector2) -> Vector2i:
		return Vector2i(7, 9)

	func is_resource_target_valid(_node: Node2D, _resource_type: String = "", _player_id: int = -1) -> bool:
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var game_map := FakeGameMap.new()
	game_map.name = "FakeGameMap"
	add_child(game_map)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	game_map.add_child(camera)

	var selection_manager := SelectionManager.new()
	selection_manager.touch_context_enabled = false
	selection_manager.game_map = game_map
	game_map.add_child(selection_manager)
	selection_manager.move_command.connect(func(_tile: Vector2i) -> void: _move_count += 1)
	selection_manager.gather_command.connect(func(_resource: Node2D) -> void: _gather_count += 1)

	var scout_scene: PackedScene = load("res://scenes/units/scout.tscn")
	var scout: UnitBase = scout_scene.instantiate() as UnitBase
	scout.global_position = Vector2(-200.0, 0.0)
	game_map.add_child(scout)
	var resource_scene: PackedScene = load("res://scenes/map/resource_node.tscn")
	var resource: ResourceNode = resource_scene.instantiate() as ResourceNode
	resource.global_position = Vector2.ZERO
	game_map.add_child(resource)

	await get_tree().process_frame
	selection_manager.select_single(scout)
	var screen_position: Vector2 = selection_manager.call("_world_to_screen", resource.global_position)
	selection_manager.call("_handle_tap", screen_position, true)
	var diagnostics: Dictionary = selection_manager.touch_input_diagnostics

	_expect_eq(_move_count, 1, "resource tap emits one ground move for a Scout")
	_expect_eq(_gather_count, 0, "resource tap never emits gather for a Scout")
	_expect_eq(String(diagnostics.get("action", "")), "move", "diagnostics record the military move")
	_expect(int(diagnostics.get("timestamp_ms", -1)) >= 0, "touch diagnostics include a fresh timestamp")

	# When Main has armed an explicit unit command, the common selection layer
	# must not reinterpret a Villager tap as contextual gathering.
	var villager_scene: PackedScene = load("res://scenes/units/villager.tscn")
	var villager: UnitBase = villager_scene.instantiate() as UnitBase
	villager.global_position = Vector2(-240.0, 0.0)
	game_map.add_child(villager)
	await get_tree().process_frame
	selection_manager.select_single(villager)
	selection_manager.set_unit_command_armed(true)
	_move_count = 0
	_gather_count = 0
	selection_manager.call("_handle_tap", screen_position, true)
	diagnostics = selection_manager.touch_input_diagnostics
	_expect_eq(_move_count, 1, "armed Villager resource tap emits the common destination command")
	_expect_eq(_gather_count, 0, "armed Villager resource tap cannot emit gather")
	_expect_eq(String(diagnostics.get("action", "")), "armed_command", "diagnostics preserve explicit command precedence")

	game_map.free()
	if _failures.is_empty():
		print("[PASS] touch_military_resource_routing: smart Scout and armed Villager resource taps route correctly")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] touch_military_resource_routing: %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
