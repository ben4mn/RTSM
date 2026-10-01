extends Node
## Regression coverage for selection entries that become unusable without input.

var _failures: Array[String] = []
var _selection_change_count := 0
var _selection_manager: SelectionManager
var _game_map: Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	_game_map = Node2D.new()
	_game_map.name = "FakeGameMap"
	add_child(_game_map)

	_selection_manager = SelectionManager.new()
	_selection_manager.name = "SelectionManager"
	_selection_manager.touch_context_enabled = false
	_selection_manager.game_map = _game_map
	_game_map.add_child(_selection_manager)
	_selection_manager.selection_changed.connect(_on_selection_changed)

	await get_tree().process_frame
	_test_freed_node_cleanup()
	_test_dead_unit_cleanup()
	_test_destroyed_building_cleanup()
	_test_depleted_resource_cleanup()

	_game_map.free()
	if _failures.is_empty():
		print("[PASS] selection_lifecycle_cleanup: stale selections prune once and later clear/tap paths stay safe")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] selection_lifecycle_cleanup: %s" % failure)
	get_tree().quit(1)


func _test_freed_node_cleanup() -> void:
	var node := Node2D.new()
	node.name = "FreedSelection"
	_game_map.add_child(node)
	_selection_manager.select_single(node)
	_selection_change_count = 0
	node.free()
	_assert_cleanup_once("freed node")


func _test_dead_unit_cleanup() -> void:
	var scene: PackedScene = load("res://scenes/units/scout.tscn")
	var unit := scene.instantiate() as UnitBase
	unit.name = "DeadSelection"
	_game_map.add_child(unit)
	_selection_manager.select_single(unit)
	_selection_change_count = 0
	unit.current_state = UnitBase.State.DEAD
	_assert_cleanup_once("dead unit")
	_expect(not unit.is_selected, "dead unit is visually deselected during cleanup")


func _test_destroyed_building_cleanup() -> void:
	var scene: PackedScene = load("res://scenes/buildings/house.tscn")
	var building := scene.instantiate() as BuildingBase
	building.name = "DestroyedSelection"
	_game_map.add_child(building)
	_selection_manager.select_single(building)
	_selection_change_count = 0
	building.state = BuildingBase.State.DESTROYED
	_assert_cleanup_once("destroyed building")
	_expect(not building.is_selected, "destroyed building is visually deselected during cleanup")


func _test_depleted_resource_cleanup() -> void:
	var scene: PackedScene = load("res://scenes/map/resource_node.tscn")
	var resource := scene.instantiate() as ResourceNode
	resource.name = "DepletedSelection"
	resource.total_amount = 10
	_game_map.add_child(resource)
	# _ready initializes remaining synchronously when add_child enters the tree.
	_selection_manager.select_single(resource)
	_selection_change_count = 0
	resource.remaining = 0
	_assert_cleanup_once("depleted resource")
	_expect(not resource.is_selected, "depleted resource is visually deselected during cleanup")


func _assert_cleanup_once(label: String) -> void:
	var changed: bool = bool(_selection_manager.call("_prune_stale_selection"))
	_expect(changed, "%s is recognized as stale" % label)
	_expect(_selection_manager.selected.is_empty(), "%s is removed from selected" % label)
	_expect_eq(_selection_change_count, 1, "%s cleanup emits selection_changed exactly once" % label)

	# Repeated maintenance, an explicit clear, and an empty-ground desktop tap
	# must remain no-ops after the stale Object has left the array.
	_selection_manager.call("_prune_stale_selection")
	_selection_manager.deselect_all()
	_selection_manager.set("_last_tap_time", 0.0)
	_selection_manager.call("_handle_tap", Vector2(10000.0, 10000.0), false)
	_expect(_selection_manager.selected.is_empty(), "%s stays cleared after later input" % label)
	_expect_eq(_selection_change_count, 1, "%s later clear/tap paths do not emit again" % label)


func _on_selection_changed(_nodes: Array[Node2D]) -> void:
	_selection_change_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
