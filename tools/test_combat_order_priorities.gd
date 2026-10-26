extends Node
## Real command and damage dispatch, stepped deterministically in a visible arena.

const INFANTRY: PackedScene = preload("res://scenes/units/infantry.tscn")
const HOUSE: PackedScene = preload("res://scenes/buildings/house.tscn")
var _failures: Array[String] = []

class Arena extends Node2D:
	func get_navigation_world_path(from: Vector2, to: Vector2, _radius: float = 4.0) -> PackedVector2Array:
		return PackedVector2Array([from, to])
	func world_to_tile(position: Vector2) -> Vector2i:
		return Vector2i(position / 16.0)
	func is_tile_walkable(_tile: Vector2i) -> bool:
		return true
	func is_entity_visible_to_player(_entity: Node2D, _owner: int = 0) -> bool:
		return true

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	get_tree().current_scene = null
	_test_retaliation_preserves_attack_move()
	_test_explicit_attack_priority()
	_test_move_survives_actual_damage()
	_test_stand_ground_building_and_retaliation()
	_test_bounded_autonomous_chase()
	_test_threat_priority_and_switching()
	_test_assault_retaliation_resume_and_cancel()
	_test_order_queue()
	for failure: String in _failures:
		push_error("[FAIL] combat_order_priorities: " + failure)
	if _failures.is_empty():
		print("[PASS] combat_order_priorities: retaliation, move/attack-move resume, explicit orders, stand ground, chase leash, nearby threats")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _arena() -> Arena:
	var arena := Arena.new()
	add_child(arena)
	return arena

func _unit(arena: Node2D, owner: int, at: Vector2) -> UnitBase:
	var unit := INFANTRY.instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = at
	unit.set_process(false)
	arena.add_child(unit)
	return unit

func _building(arena: Node2D, at: Vector2) -> BuildingBase:
	var building := HOUSE.instantiate() as BuildingBase
	building.player_owner = 1
	building.position = at
	building.set_process(false)
	arena.add_child(building)
	building.complete_instantly()
	return building

func _test_retaliation_preserves_attack_move() -> void:
	var arena := _arena()
	var mover := _unit(arena, 0, Vector2.ZERO)
	var enemy := _unit(arena, 1, Vector2(32, 0))
	var destination := Vector2(400, 0)
	mover.command_attack_move(destination)
	Combat.resolve_unit_hit(enemy, mover, 1.0, 1.0)
	_expect(mover.attack_move and mover.move_target == destination, "damage cannot discard attack-move destination")
	_expect(not bool(mover.get("_forced_attack")), "retaliation is autonomous, not a forced explicit attack")
	enemy.current_state = UnitBase.State.DEAD
	mover._process(0.05)
	_expect(mover.current_state == UnitBase.State.MOVING, "attack-move resumes after retaliated enemy dies")
	var before: Vector2 = mover.position
	mover._process(0.05)
	_expect(mover.position.x > before.x, "resumed attack-move makes forward progress")
	arena.free()

func _test_explicit_attack_priority() -> void:
	var arena := _arena()
	var fighter := _unit(arena, 0, Vector2.ZERO)
	var attacker := _unit(arena, 1, Vector2(32, 0))
	var original := _unit(arena, 1, Vector2(100, 0))
	fighter.command_attack(original)
	Combat.resolve_unit_hit(attacker, fighter, 1.0, 1.0)
	_expect(fighter.attack_target == original, "retaliation cannot overwrite explicit unit attack")
	var building := _building(arena, Vector2(100, 0))
	fighter.command_attack_building(building)
	Combat.resolve_unit_hit(attacker, fighter, 1.0, 1.0)
	_expect(fighter.attack_building_target == null and fighter.attack_target == attacker, "building assault temporarily fights its actual attacker")
	arena.free()

func _test_move_survives_actual_damage() -> void:
	var arena := _arena()
	var mover := _unit(arena, 0, Vector2.ZERO)
	var attacker := _unit(arena, 1, Vector2(32, 0))
	mover.command_move(Vector2(120, 0))
	Combat.resolve_unit_hit(attacker, mover, 1.0, 1.0)
	for step: int in 30:
		mover._process(0.1)
		if mover.current_state == UnitBase.State.IDLE:
			break
		_expect(mover.attack_target == null, "passive move never acquires or retaliates before arrival")
	_expect(mover.position.distance_to(Vector2(120, 0)) <= 4.0, "passive move arrives under enemy fire")
	arena.free()

func _test_stand_ground_building_and_retaliation() -> void:
	var arena := _arena()
	var defender := _unit(arena, 0, Vector2.ZERO)
	defender.stance = UnitBase.Stance.STAND_GROUND
	var enemy := _unit(arena, 1, Vector2(100, 0))
	Combat.resolve_unit_hit(enemy, defender, 1.0, 1.0)
	defender._process(0.1)
	_expect(defender.position == Vector2.ZERO, "stand-ground retaliation cannot chase an out-of-range attacker")
	enemy.free()
	var building := _building(arena, Vector2(100, 0))
	defender.command_attack_building(building, false, false)
	defender._process(0.1)
	_expect(defender.position == Vector2.ZERO, "stand ground cannot chase an autonomous building target")
	defender.command_attack_building(building)
	defender._process(0.1)
	_expect(defender.position.x > 0.0, "explicit building attack still overrides stand ground")
	arena.free()

func _test_bounded_autonomous_chase() -> void:
	var arena := _arena()
	var defender := _unit(arena, 0, Vector2.ZERO)
	var runner := _unit(arena, 1, Vector2(48, 0))
	defender._try_auto_attack()
	_expect(defender.attack_target == runner, "idle military acquires nearby enemy")
	for step: int in 120:
		runner.position.x = defender.position.x + 48.0
		defender._process(0.1)
	_expect(defender.position.x < 350.0, "idle defender cannot be dragged across the map by a faster enemy")
	_expect(not bool(defender.get("_forced_attack")), "autonomous pursuit never becomes forced")
	defender.command_attack_move(Vector2(0, 400))
	runner.position = defender.position + Vector2(48, 0)
	defender.set("_auto_attack_timer", 0.0)
	defender._try_auto_attack()
	runner.position = Vector2(1000, 0)
	defender._process(0.1)
	_expect(defender.current_state == UnitBase.State.MOVING and defender.attack_move and defender.move_target == Vector2(0, 400), "attack-move abandons excessive chase and resumes its saved destination")
	defender.command_attack(runner)
	defender._process(0.1)
	_expect(defender.attack_target == runner, "explicit attack is exempt from autonomous leash")
	arena.free()

func _test_threat_priority_and_switching() -> void:
	var arena := _arena()
	var fighter := _unit(arena, 0, Vector2.ZERO)
	var distraction := _unit(arena, 1, Vector2(20, 0))
	distraction.damage = 0.0
	var threat := _unit(arena, 1, Vector2(50, 0))
	threat.command_attack(fighter)
	fighter._try_auto_attack()
	_expect(fighter.attack_target == threat, "military prioritizes a nearby active attacker over an unarmed distraction")
	var building := _building(arena, Vector2(30, 0))
	fighter.command_attack_building(building, false, false)
	fighter.set("_auto_attack_timer", 0.0)
	fighter._process(0.1)
	_expect(fighter.attack_target == threat, "autonomous building attack yields to nearby military threat")
	fighter.command_attack_building(building)
	fighter.set("_auto_attack_timer", 0.0)
	fighter._process(0.1)
	_expect(fighter.attack_building_target == building, "explicit building attack survives periodic threat checks")
	arena.free()

func _test_assault_retaliation_resume_and_cancel() -> void:
	var arena := _arena()
	var fighter := _unit(arena, 0, Vector2.ZERO)
	var attacker := _unit(arena, 1, Vector2(32, 0))
	var building := _building(arena, Vector2(100, 0))
	fighter.command_attack_building(building)
	Combat.resolve_unit_hit(attacker, fighter, 1.0, 1.0)
	_expect(fighter.attack_target == attacker, "assault defends against actual damage")
	attacker.current_state = UnitBase.State.DEAD
	fighter._process(0.1)
	_expect(fighter.attack_building_target == building and bool(fighter.get("_forced_attack")), "retaliation resumes original explicit building assault")
	attacker.current_state = UnitBase.State.IDLE
	Combat.resolve_unit_hit(attacker, fighter, 1.0, 1.0)
	_expect(fighter.attack_building_target == building, "assault has hysteresis before another interruption")
	fighter.set("_retaliation_ready_at", 0.0)
	Combat.resolve_unit_hit(attacker, fighter, 1.0, 1.0)
	attacker.position = Vector2(5000, 0)
	fighter._process(0.1)
	_expect(fighter.attack_building_target == building, "retaliation leash returns to original assault")
	fighter.set("_retaliation_ready_at", 0.0)
	attacker.position = Vector2(32, 0)
	Combat.resolve_unit_hit(attacker, fighter, 1.0, 1.0)
	fighter.command_move(Vector2(0, 200))
	attacker.current_state = UnitBase.State.DEAD
	fighter._process(0.1)
	_expect(fighter.attack_building_target == null and fighter.current_state == UnitBase.State.MOVING and fighter.move_target == Vector2(0, 200), "fresh move cancels suspended assault")
	fighter.command_attack_building(building)
	fighter.set("_retaliation_ready_at", 0.0)
	attacker.current_state = UnitBase.State.IDLE
	Combat.resolve_unit_hit(attacker, fighter, 1.0, 1.0)
	building.free()
	attacker.current_state = UnitBase.State.DEAD
	fighter._process(0.1)
	_expect(fighter.attack_building_target == null and fighter.current_state == UnitBase.State.IDLE, "freed assault target is safely discarded")
	arena.free()


func _test_order_queue() -> void:
	var arena := _arena()
	var unit := _unit(arena, 0, Vector2.ZERO)
	unit.command_move(Vector2(60, 0))
	_expect(unit.enqueue_order({"kind": "move", "position": Vector2(120, 0)}), "append second waypoint")
	_expect(unit.enqueue_order({"kind": "move", "position": Vector2(180, 0)}), "append third waypoint")
	_expect(unit.move_target == Vector2(60, 0) and unit.queued_orders.size() == 2, "queue preserves active movement")
	for step: int in 60:
		unit._process(0.1)
		if unit.current_state == UnitBase.State.IDLE: break
	_expect(unit.position.distance_to(Vector2(180, 0)) <= 4.0 and unit.queued_orders.is_empty(), "queued waypoints complete in order")
	unit.command_move(Vector2(240, 0))
	unit.enqueue_order({"kind": "move", "position": Vector2(300, 0)})
	unit.command_stop()
	_expect(unit.queued_orders.is_empty() and unit.current_state == UnitBase.State.IDLE, "Stop cancels active movement and pending queue")
	unit.command_move(Vector2(240, 0))
	unit.enqueue_order({"kind": "move", "position": Vector2(300, 0)})
	unit.command_move(Vector2(0, 100))
	_expect(unit.queued_orders.is_empty() and unit.move_target == Vector2(0, 100), "fresh move replaces all queued intent")
	unit.enqueue_order({"kind": "move", "position": Vector2(360, 0)})
	unit._on_navigation_unreachable(unit.move_target)
	_expect(unit.move_target == Vector2(360, 0), "unreachable leg advances to next queued destination")
	_expect(not unit.enqueue_order({"kind": "move", "position": Vector2.INF}), "non-finite destination rejected")
	arena.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
