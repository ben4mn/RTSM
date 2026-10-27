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

	# A resource tap and nearby ground tap are distinct intents even when
	# their discovery-ring boundary is within the double-tap pixel radius.
	selection_manager.set_unit_command_armed(false)
	selection_manager.select_single(villager)
	var resource_edge: Vector2 = screen_position
	var nearby_ground: Vector2 = Vector2.ZERO
	for offset: int in range(2, 122, 2):
		var candidate: Vector2 = screen_position + Vector2(offset, 0)
		var world: Vector2 = selection_manager.call("_screen_to_world", candidate)
		if selection_manager.call("_get_resource_at", world, true) == resource:
			resource_edge = candidate
		else:
			nearby_ground = candidate
			break
	_expect(nearby_ground != Vector2.ZERO and resource_edge.distance_to(nearby_ground) < 30.0, "resource discovery boundary provides adjacent gather/ground taps")
	_move_count = 0
	_gather_count = 0
	selection_manager.call("_handle_tap", resource_edge, true)
	selection_manager.call("_handle_tap", nearby_ground, true)
	_expect_eq(_gather_count, 1, "unarmed edge tap gathers the resource")
	_expect_eq(_move_count, 1, "ground tap after Gather moves instead of clearing")
	_expect(selection_manager.selected == [villager], "Gather then nearby ground accidentally clears selection")
	selection_manager.call("_handle_tap", nearby_ground, true)
	_expect(selection_manager.selected == [villager] and _move_count == 2, "repeated ground tap remains a destination order")
	selection_manager.select_single(villager)
	selection_manager.call("_handle_tap", nearby_ground, true)
	_expect(selection_manager.selected == [villager] and _move_count == 3, "HUD/programmatic selection preserves subsequent ground orders")

	# A worker standing over a resource must not steal another worker's order.
	var overlap: Villager = villager_scene.instantiate() as Villager
	overlap.global_position = resource.global_position
	game_map.add_child(overlap)
	overlap.set_process(false)
	await get_tree().process_frame
	selection_manager.select_single(villager)
	selection_manager.set("_last_tap_time", 0.0)
	_gather_count = 0
	selection_manager.call("_handle_tap", screen_position, true, overlap)
	selection_manager.call("_handle_tap", screen_position, true, overlap)
	_expect_eq(_gather_count, 2, "worker over resource routes repeated taps to gathering")
	_expect(selection_manager.selected == [villager], "resource order preserves original workers instead of stealing selection")
	var context: Array = selection_manager.call("_build_touch_context_actions", overlap, resource)
	var has_select: bool = false
	var has_gather: bool = false
	for action: Dictionary in context:
		has_select = has_select or action.label == "Select worker"
		has_gather = has_gather or action.label == "Gather"
	_expect(has_select and has_gather, "hold explicitly offers Select worker and Gather for an overlap")
	selection_manager.set_unit_command_armed(true)
	_gather_count = 0
	selection_manager.call("_handle_tap", screen_position, true, overlap)
	_expect(_gather_count == 0 and selection_manager.selected == [villager], "armed Move still wins over worker/resource overlap")
	selection_manager.set_unit_command_armed(false)
	overlap.position = Vector2(300, 0)
	selection_manager.set("_last_tap_time", 0.0)
	selection_manager.call("_handle_tap", selection_manager.call("_world_to_screen", overlap.position), true)
	_expect(selection_manager.selected == [overlap], "worker on plain ground still selects directly")

	game_map.free()
	if _failures.is_empty():
		print("[PASS] touch_military_resource_routing: Scout/armed routing; Gather/ground boundary; worker/resource overlap and explicit hold selection; repeat destination orders")
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
