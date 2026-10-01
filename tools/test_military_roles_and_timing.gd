extends Node
## Gameplay regression for the compact counter roles and legible attack timing.

const UNIT_SCENES: Dictionary = {
	UnitData.UnitType.INFANTRY: preload("res://scenes/units/infantry.tscn"),
	UnitData.UnitType.ARCHER: preload("res://scenes/units/archer.tscn"),
	UnitData.UnitType.CAVALRY: preload("res://scenes/units/cavalry.tscn"),
	UnitData.UnitType.SCOUT: preload("res://scenes/units/scout.tscn"),
}
var _failures: Array[String] = []


class VisibleArena extends Node2D:
	var targets_visible: bool = true

	func get_navigation_world_path(from_world: Vector2, target_world: Vector2, _radius: float = 4.0) -> PackedVector2Array:
		return PackedVector2Array([from_world, target_world])

	func world_to_tile(world_position: Vector2) -> Vector2i:
		return Vector2i(roundi(world_position.x / 16.0), roundi(world_position.y / 16.0))

	func is_tile_walkable(_tile: Vector2i) -> bool:
		return true

	func is_entity_visible_to_player(_entity: Node2D, _owner: int = 0) -> bool:
		return targets_visible


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	get_tree().current_scene = null
	_test_shared_role_data()
	_test_windup_and_projectile_impact()
	_test_coincident_melee_hits()
	_test_retreat_and_stop_cancel_unreleased_attacks()
	_test_fog_and_post_kill_acquisition()
	_test_scout_reconnaissance()
	if _failures.is_empty():
		print("[PASS] military_roles_and_timing: counter roles, shared intervals, windup, arrow arrival, retreat, Stop, fog, retarget and recon")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] military_roles_and_timing: %s" % failure)
		get_tree().quit(1)


func _test_shared_role_data() -> void:
	for role: int in [UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY]:
		var arena := VisibleArena.new()
		add_child(arena)
		var unit: UnitBase = _spawn(arena, role, 0, Vector2.ZERO)
		_expect(int(UnitData.UNITS[role]["pop_cost"]) == 1, "compact military role takes one population")
		_expect(is_equal_approx(unit.attack_speed, 1.0 / float(UnitData.UNITS[role]["attack_interval"])), "runtime cadence reads shared role data")
		_expect(not UnitData.get_unit_counter_description(role).is_empty(), "military role exposes its counter explanation")
		arena.free()
	_expect(UnitData.get_unit_name(UnitData.UnitType.INFANTRY) == "Warrior", "spear infantry display name is Warrior")
	_expect(UnitData.get_unit_name(UnitData.UnitType.CAVALRY) == "Horseman", "battle cavalry display name is Horseman")
	_expect(Combat.get_counter_bonus(UnitData.UnitType.INFANTRY, UnitData.UnitType.CAVALRY) > 1.0, "Warrior counters Horseman")
	_expect(Combat.get_counter_bonus(UnitData.UnitType.CAVALRY, UnitData.UnitType.ARCHER) > 1.0, "Horseman counters Archer")
	_expect(Combat.get_counter_bonus(UnitData.UnitType.ARCHER, UnitData.UnitType.INFANTRY) > 1.0, "Archer counters Warrior")


func _test_windup_and_projectile_impact() -> void:
	var arena := VisibleArena.new()
	add_child(arena)
	var archer: UnitBase = _spawn(arena, UnitData.UnitType.ARCHER, 0, Vector2(-70.0, 0.0))
	var target: UnitBase = _spawn(arena, UnitData.UnitType.INFANTRY, 1, Vector2.ZERO)
	archer.command_attack(target)
	archer._process(0.01)
	_expect(is_equal_approx(target.hp, 60.0), "bow windup does not apply damage")
	archer._process(0.19)
	var projectile: Node = _find_projectile(arena)
	_expect(projectile != null, "bow release creates a moving projectile")
	_expect(is_equal_approx(target.hp, 60.0), "arrow release does not pre-apply HP loss")
	if projectile != null:
		arena.targets_visible = false
		projectile.call("advance_projectile", 0.05)
		_expect(is_equal_approx(target.hp, 60.0), "arrow in flight does not apply HP loss")
		_expect(not bool(projectile.get("visible")), "arrow rendering cannot reveal a flight into hidden fog")
		# A shot already released survives the archer's removal.
		archer.free()
		projectile.call("advance_projectile", 0.4)
		_expect(is_equal_approx(target.hp, 48.0), "arrow arrival applies exactly one twelve-point counter hit")
		projectile.call("advance_projectile", 0.4)
		_expect(is_equal_approx(target.hp, 48.0), "completed projectile cannot apply damage twice")
	arena.free()


func _test_coincident_melee_hits() -> void:
	var arena := VisibleArena.new()
	add_child(arena)
	var first: UnitBase = _spawn(arena, UnitData.UnitType.INFANTRY, 0, Vector2.ZERO)
	var second: UnitBase = _spawn(arena, UnitData.UnitType.INFANTRY, 1, Vector2(20.0, 0.0))
	first.hp = 6.0
	second.hp = 6.0
	first.command_attack(second)
	second.command_attack(first)
	first._process(0.01)
	second._process(0.01)
	first._process(0.2)
	second._process(0.2)
	_expect(first.hp == 6.0 and second.hp == 6.0, "coincident blows wait for all unit windups to release")
	for child: Node in arena.get_children():
		if child.has_method("advance_committed_hit"):
			child.call("advance_committed_hit")
	_expect(first.current_state == UnitBase.State.DEAD and second.current_state == UnitBase.State.DEAD, "coincident mirror blows trade without faction processing-order advantage")
	arena.free()


func _test_retreat_and_stop_cancel_unreleased_attacks() -> void:
	for command: String in ["retreat", "stop"]:
		var arena := VisibleArena.new()
		add_child(arena)
		var warrior: UnitBase = _spawn(arena, UnitData.UnitType.INFANTRY, 0, Vector2(20.0, 0.0))
		var target: UnitBase = _spawn(arena, UnitData.UnitType.CAVALRY, 1, Vector2.ZERO)
		warrior.command_attack(target)
		warrior._process(0.01)
		if command == "retreat":
			warrior.command_move(Vector2(200.0, 0.0))
		else:
			warrior.command_stop()
		warrior._process(0.2)
		_expect(is_equal_approx(target.hp, 80.0), "%s cancels spear windup before impact" % command)
		_expect(warrior.attack_target == null, "%s immediately clears the combat target" % command)
		if command == "retreat":
			_expect(warrior.global_position.x > 20.0 and not warrior.can_auto_retaliate(), "retreat moves away without auto retaliation")
		else:
			_expect(warrior.current_state == UnitBase.State.IDLE, "Stop visibly settles before passive stance scanning")
		arena.free()


func _test_fog_and_post_kill_acquisition() -> void:
	var arena := VisibleArena.new()
	add_child(arena)
	var warrior: UnitBase = _spawn(arena, UnitData.UnitType.INFANTRY, 0, Vector2.ZERO)
	var target: UnitBase = _spawn(arena, UnitData.UnitType.CAVALRY, 1, Vector2(20.0, 0.0))
	var second: UnitBase = _spawn(arena, UnitData.UnitType.ARCHER, 1, Vector2(30.0, 0.0))
	arena.targets_visible = false
	warrior._try_auto_attack()
	warrior.command_attack(target)
	_expect(warrior.attack_target == null, "hidden targets cannot be acquired by idle scan or explicit attack")
	arena.targets_visible = true
	warrior.command_attack(target)
	warrior._process(0.01)
	arena.targets_visible = false
	warrior._process(0.2)
	_expect(is_equal_approx(target.hp, 80.0), "unreleased spear attack cancels after loss of vision")
	arena.targets_visible = true
	warrior.command_attack(target)
	target.die()
	warrior._process(0.35)
	warrior._process(0.02)
	_expect(warrior.attack_target == second, "unit acquires the next visible opponent after a kill")
	arena.free()


func _test_scout_reconnaissance() -> void:
	var arena := VisibleArena.new()
	add_child(arena)
	var scout: UnitBase = _spawn(arena, UnitData.UnitType.SCOUT, 0, Vector2.ZERO)
	var target: UnitBase = _spawn(arena, UnitData.UnitType.ARCHER, 1, Vector2(20.0, 0.0))
	scout._try_auto_attack()
	scout.command_attack(target)
	_expect(is_zero_approx(scout.damage) and scout.attack_target == null and not scout.can_auto_retaliate(), "Scout remains reconnaissance rather than battle cavalry")
	_expect(scout.vision_radius > target.vision_radius, "Scout retains wider vision than a battle Archer")
	arena.free()


func _spawn(arena: Node2D, role: int, owner: int, spawn_position: Vector2) -> UnitBase:
	var unit: UnitBase = (UNIT_SCENES[role] as PackedScene).instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = spawn_position
	unit.set_process(false)
	arena.add_child(unit)
	return unit


func _find_projectile(arena: Node2D) -> Node:
	for child: Node in arena.get_children():
		if child.has_method("advance_projectile"):
			return child
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
