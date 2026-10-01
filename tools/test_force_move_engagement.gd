extends Node
## Focused regression for the semantic difference between Move and A-Move.
## Run through: Godot --headless --path . tools/test_force_move_engagement.tscn

const INFANTRY_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")

var _failures: Array[String] = []


class FakeNavigationMap extends Node2D:
	func get_navigation_world_path(
		from_world: Vector2,
		target_world: Vector2,
		_arrival_radius_world: float = 4.0,
		_max_goal_radius_tiles: int = 6
	) -> PackedVector2Array:
		return PackedVector2Array([from_world, target_world])

	func world_to_tile(world_position: Vector2) -> Vector2i:
		return Vector2i(roundi(world_position.x / 16.0), roundi(world_position.y / 16.0))

	func is_tile_walkable(_tile: Vector2i) -> bool:
		return true

	func is_entity_visible_to_player(_entity: Node2D, _viewer_player_id: int = 0) -> bool:
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var navigation_map := FakeNavigationMap.new()
	add_child(navigation_map)
	var container := Node2D.new()
	navigation_map.add_child(container)

	var mover := _spawn_infantry(container, 0, Vector2.ZERO)
	var enemy := _spawn_infantry(container, 1, Vector2(48.0, 0.0))
	mover.stance = UnitBase.Stance.AGGRESSIVE

	# The enemy is inside the mover's vision and directly on its route. Explicit
	# Move must keep going without acquiring or retaliating.
	mover.command_move(Vector2(192.0, 0.0))
	_expect(bool(mover.get("_force_move_active")), "Move records no-engagement intent")
	_expect(not mover.can_auto_retaliate(), "Move suppresses automatic retaliation en route")
	mover._process_moving(0.1)
	_expect_eq(mover.current_state, UnitBase.State.MOVING, "Move continues past a visible enemy")
	_expect(mover.attack_target == null, "Move does not auto-acquire a visible enemy")

	# A-Move over the same route must clear no-engagement intent and acquire.
	mover.command_attack_move(Vector2(192.0, 0.0))
	_expect(not bool(mover.get("_force_move_active")), "A-Move clears no-engagement intent")
	_expect(mover.can_auto_retaliate(), "A-Move restores automatic retaliation")
	mover._process_moving(0.1)
	_expect_eq(mover.current_state, UnitBase.State.ATTACKING, "A-Move engages a visible enemy")
	_expect(mover.attack_target == enemy, "A-Move acquires the enemy on its route")

	_test_intent_cleanup(mover, enemy)
	navigation_map.free()
	_finish()


func _test_intent_cleanup(mover: UnitBase, enemy: UnitBase) -> void:
	var destination := Vector2(240.0, 0.0)
	mover.command_move_path(PackedVector2Array([mover.global_position, destination]))
	_expect(bool(mover.get("_force_move_active")), "Move Path records no-engagement intent")
	mover.command_attack(enemy)
	_expect(not bool(mover.get("_force_move_active")), "explicit Attack clears no-engagement intent")

	mover.command_move(destination)
	mover.command_patrol(destination + Vector2(0.0, 96.0))
	_expect(not bool(mover.get("_force_move_active")), "Patrol clears no-engagement intent")

	mover.command_move(destination)
	mover.command_attack_move_path(PackedVector2Array([mover.global_position, destination]))
	_expect(not bool(mover.get("_force_move_active")), "A-Move Path clears no-engagement intent")

	mover.command_move(destination)
	mover.command_stop()
	_expect(not bool(mover.get("_force_move_active")), "Stop clears no-engagement intent")

	mover.command_move(mover.global_position)
	mover._process_moving(0.1)
	_expect_eq(mover.current_state, UnitBase.State.IDLE, "Move arrival returns the unit to idle")
	_expect(not bool(mover.get("_force_move_active")), "arrival clears no-engagement intent")

	mover.command_move(destination)
	mover.set_state(UnitBase.State.BUILDING)
	_expect(not bool(mover.get("_force_move_active")), "a new non-movement task clears no-engagement intent")


func _spawn_infantry(container: Node2D, owner: int, spawn_position: Vector2) -> UnitBase:
	var unit := INFANTRY_SCENE.instantiate() as UnitBase
	unit.player_owner = owner
	unit.global_position = spawn_position
	unit.set_process(false)
	container.add_child(unit)
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] force_move_engagement: Move bypasses enemies; A-Move engages; intent cleanup is bounded")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] force_move_engagement: %s" % failure)
	get_tree().quit(1)
