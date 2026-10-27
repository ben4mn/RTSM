extends Node
## Regression for shared melee approach slots remaining stacked after arrival.

const INFANTRY: PackedScene = preload("res://scenes/units/infantry.tscn")
var _failures: Array[String] = []


class Arena extends Node2D:
	var blocked_right: bool = false

	func get_navigation_world_path(from: Vector2, destination: Vector2, _radius: float = 4.0) -> PackedVector2Array:
		return PackedVector2Array([from, destination])

	func world_to_tile(position: Vector2) -> Vector2i:
		return Vector2i(floori(position.x / 10.0), floori(position.y / 10.0))

	func is_tile_walkable(tile: Vector2i) -> bool:
		return not blocked_right or tile.x < 1

	func is_entity_visible_to_player(_entity: Node2D, _owner: int) -> bool:
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	get_tree().current_scene = null
	_test_shared_target(false)
	_test_shared_target(true)
	_test_nearby_opponent_body()
	_test_stand_ground_holds_position()
	for failure: String in _failures:
		push_error("[FAIL] combat_spacing: " + failure)
	if _failures.is_empty():
		print("[PASS] combat_spacing: coincident melee allies separate without losing explicit target, attack cadence or legal terrain")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_shared_target(blocked: bool) -> void:
	var arena := Arena.new()
	arena.blocked_right = blocked
	add_child(arena)
	var defender: UnitBase = _spawn(arena, 1, Vector2.ZERO)
	defender.hp = 10000.0
	defender.max_hp = 10000.0
	defender.damage = 0.0
	defender.armor = 0.0
	var attackers: Array[UnitBase] = []
	for index: int in 4:
		var unit: UnitBase = _spawn(arena, 0, Vector2(-20.0, 0.0))
		# Cadence fixture deliberately isolates spacing from balance-data changes.
		unit.damage = 6.0
		unit.command_attack(defender)
		attackers.append(unit)
	for tick: int in 300:
		for attacker: UnitBase in attackers:
			attacker._process(1.0 / 60.0)
			_expect(arena.is_tile_walkable(arena.world_to_tile(attacker.position)), "spacing stays outside a blocked tile")
			_expect(attacker.position.distance_to(defender.position) <= attacker.attack_range + 8.01, "spacing remains inside the current attack circle")
			_expect(attacker.position.distance_to(defender.position) >= 15.99, "spacing does not push attackers through the target body")
		for child: Node in arena.get_children():
			if child.has_method("advance_committed_hit"):
				child.call("advance_committed_hit")
				child.free()
	var spacing: float = INF
	for i: int in attackers.size():
		_expect(attackers[i].attack_target == defender and attackers[i]._forced_attack, "spacing preserves explicit attack intent")
		for j: int in range(i + 1, attackers.size()):
			spacing = minf(spacing, attackers[i].position.distance_to(attackers[j].position))
	print("[METRIC] combat_spacing ", JSON.stringify({"blocked": blocked, "minimum_spacing": spacing, "damage": 10000.0 - defender.hp}))
	_expect(spacing >= 9.0, "exactly coincident melee allies visibly separate")
	_expect(10000.0 - defender.hp == 120.0, "five regular six-damage hits per attacker retain original cadence")
	arena.free()


func _test_nearby_opponent_body() -> void:
	var arena := Arena.new()
	add_child(arena)
	var target: UnitBase = _spawn(arena, 1, Vector2.ZERO)
	var neighbor: UnitBase = _spawn(arena, 1, Vector2(-20.0, 15.0))
	var attacker: UnitBase = _spawn(arena, 0, Vector2(-20.0, -2.0))
	_spawn(arena, 0, Vector2(-20.0, -6.0))
	attacker.command_attack(target)
	for tick: int in 120:
		attacker._separation_timer = 0.0
		attacker._relax_combat_spacing(1.0 / 60.0, target.position)
		_expect(attacker.position.distance_to(neighbor.position) >= 16.79, "friendly pressure cannot squeeze through a neighboring opponent")
	arena.free()


func _test_stand_ground_holds_position() -> void:
	var arena := Arena.new()
	add_child(arena)
	var target: UnitBase = _spawn(arena, 1, Vector2.ZERO)
	var guard: UnitBase = _spawn(arena, 0, Vector2(-20.0, 0.0))
	_spawn(arena, 0, Vector2(-20.0, -1.0))
	guard.stance = UnitBase.Stance.STAND_GROUND
	guard.command_attack(target, false)
	var start: Vector2 = guard.position
	guard._relax_combat_spacing(0.1, target.position)
	_expect(guard.position == start, "autonomous Stand Ground keeps its exact position under friendly pressure")
	guard.command_attack(target)
	guard._relax_combat_spacing(0.1, target.position)
	_expect(guard.position != start, "explicit attack retains its position-adjustment authority over stance")
	arena.free()


func _spawn(arena: Node2D, owner: int, position: Vector2) -> UnitBase:
	var unit: UnitBase = INFANTRY.instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = position
	arena.add_child(unit)
	unit.set_process(false)
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
