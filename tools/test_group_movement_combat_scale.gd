extends Node
## Bounded regression for movement/combat command fan-out at representative army sizes.
## Run through: Godot --headless --path . tools/test_group_movement_combat_scale.tscn

const INFANTRY_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")

var _failures: Array[String] = []


class FakeNavigationMap extends Node2D:
	var path_requests: int = 0

	func get_navigation_world_path(
		from_world: Vector2,
		target_world: Vector2,
		_arrival_radius_world: float = 4.0,
		_max_goal_radius_tiles: int = 6
	) -> PackedVector2Array:
		path_requests += 1
		return PackedVector2Array([
			from_world,
			from_world + Vector2(0.0, 48.0),
			target_world,
		])

	func world_to_tile(world_position: Vector2) -> Vector2i:
		return Vector2i(roundi(world_position.x / 16.0), roundi(world_position.y / 16.0))

	func is_tile_walkable(_tile: Vector2i) -> bool:
		return true

	func is_entity_visible_to_player(_entity: Node2D, _viewer_player_id: int = 0) -> bool:
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager != null:
		audio_manager.call("set_all_enabled", false)
	var game_manager: Node = get_node("/root/GameManager")
	game_manager.call("initialize_game", 2)
	var players: Dictionary = game_manager.get("players") as Dictionary
	var population_cap: int = int((players[0] as Dictionary).get("max_population", 200))
	for group_size: int in [1, 8, 20, population_cap]:
		_test_group_size(group_size)
	_test_population_cap_rejects_overflow(game_manager, population_cap)
	_finish()


func _test_group_size(group_size: int) -> void:
	var navigation_map := FakeNavigationMap.new()
	add_child(navigation_map)
	var container := Node2D.new()
	navigation_map.add_child(container)
	var enemy: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	enemy.player_owner = 1
	enemy.global_position = Vector2(5000.0, 5000.0)
	container.add_child(enemy)
	var units: Array[UnitBase] = []
	for index: int in range(group_size):
		var unit: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
		unit.player_owner = 0
		unit.stance = UnitBase.Stance.STAND_GROUND
		unit.global_position = Vector2(float(index % 20) * 40.0, float(index / 20) * 40.0)
		container.add_child(unit)
		units.append(unit)

	for unit: UnitBase in units:
		var before: Vector2 = unit.global_position
		unit.command_move(Vector2(4000.0, 1000.0))
		unit._process_moving(0.1)
		_expect(unit.global_position.distance_to(before) > 0.0, "%d-unit move advances every unit" % group_size)
	_expect_eq(navigation_map.path_requests, group_size, "%d-unit move requests one bounded route per unit" % group_size)

	for unit: UnitBase in units:
		var before: Vector2 = unit.global_position
		unit.command_attack(enemy)
		unit._process_attacking(0.1)
		_expect(unit.global_position.distance_to(before) > 0.0, "%d-unit combat chase advances every unit" % group_size)
		_expect(unit.attack_target == enemy, "%d-unit combat chase retains its visible target" % group_size)
	_expect_eq(navigation_map.path_requests, group_size * 2, "%d-unit move plus chase keeps route work linear" % group_size)
	navigation_map.free()


func _test_population_cap_rejects_overflow(game_manager: Node, population_cap: int) -> void:
	var players: Dictionary = game_manager.get("players") as Dictionary
	var current_cap: int = int((players[0] as Dictionary).get("population_cap", 0))
	game_manager.call("increase_population_cap", 0, population_cap - current_cap)
	_expect(bool(game_manager.call("add_population", 0, population_cap)), "population-cap group can fill all available slots")
	_expect(not bool(game_manager.call("add_population", 0, 1)), "population-cap group rejects one additional unit")
	game_manager.call("remove_population", 0, population_cap)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] group_movement_combat_scale: 1, 8, 20, and population-cap groups")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] group_movement_combat_scale: %s" % failure)
	get_tree().quit(1)
