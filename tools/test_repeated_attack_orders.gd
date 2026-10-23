extends Node
## Reconfirming an attack must not restart its route or cancel a paid windup.

const INFANTRY: PackedScene = preload("res://scenes/units/infantry.tscn")
const CAVALRY: PackedScene = preload("res://scenes/units/cavalry.tscn")
const ARCHER: PackedScene = preload("res://scenes/units/archer.tscn")
const HOUSE: PackedScene = preload("res://scenes/buildings/house.tscn")
const STEP: float = 1.0 / 60.0
var _failures: Array[String] = []


class Arena extends Node2D:
	var path_requests: int = 0

	func get_navigation_world_path(from: Vector2, to: Vector2, _radius: float = 4.0) -> PackedVector2Array:
		path_requests += 1
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
	for scenario: String in ["melee", "ranged", "building", "pursuit"]:
		var baseline: Dictionary = _run_engagement(scenario, 0)
		_expect(float(baseline["damage"]) > 0.0, "%s single-order fixture deals actual damage" % scenario)
		for repeat_ticks: int in [6, 18, 36]:
			var repeated: Dictionary = _run_engagement(scenario, repeat_ticks)
			_expect(is_equal_approx(float(baseline["damage"]), float(repeated["damage"])), "%s repeated at %.1fs retains single-order damage" % [scenario, repeat_ticks * STEP])
			_expect((baseline["position"] as Vector2).is_equal_approx(repeated["position"] as Vector2), "%s repetition preserves movement" % scenario)
			_expect(int(baseline["paths"]) == int(repeated["paths"]), "%s repetition does not request extra paths" % scenario)
			_expect(is_equal_approx(float(baseline["cooldown"]), float(repeated["cooldown"])), "%s repetition preserves attack cadence" % scenario)
		print("[METRIC] repeated_attack_orders ", JSON.stringify({"scenario": scenario, "single_order_damage": baseline["damage"], "path_requests": baseline["paths"], "repeat_intervals": [0.1, 0.3, 0.6]}))
	_test_autonomous_to_explicit(false)
	_test_autonomous_to_explicit(true)
	_test_replacement_cancels_windup()
	_test_autonomous_retarget_clears_old_route()
	for failure: String in _failures:
		push_error("[FAIL] repeated_attack_orders: " + failure)
	if _failures.is_empty():
		print("[PASS] repeated_attack_orders: melee, arrows, buildings, moving targets, order promotion and replacement")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _run_engagement(scenario: String, repeat_ticks: int) -> Dictionary:
	var arena := Arena.new()
	add_child(arena)
	var attacker_scene: PackedScene = CAVALRY if scenario == "pursuit" else (ARCHER if scenario == "ranged" else INFANTRY)
	var attacker: UnitBase = _unit(arena, attacker_scene, 0, Vector2.ZERO)
	var target: Node2D
	if scenario == "building":
		var building := HOUSE.instantiate() as BuildingBase
		building.player_owner = 1
		building.position = Vector2(140.0, 0.0)
		arena.add_child(building)
		building.set_process(false)
		building.complete_instantly()
		building.max_hp = 10000
		building.hp = 10000
		target = building
	else:
		var initial_distance: float = 160.0 if scenario == "pursuit" else (70.0 if scenario == "ranged" else 20.0)
		var enemy: UnitBase = _unit(arena, INFANTRY, 1, Vector2(initial_distance, 0.0))
		enemy.damage = 0.0
		enemy.max_hp = 10000.0
		enemy.hp = 10000.0
		if scenario == "pursuit":
			enemy.command_move(Vector2(800.0, 0.0))
		target = enemy
	var duration_ticks: int = 600 if scenario == "pursuit" else 300
	for tick: int in duration_ticks:
		if tick == 0 or (repeat_ticks > 0 and tick % repeat_ticks == 0):
			if target is BuildingBase:
				attacker.command_attack_building(target as BuildingBase)
			else:
				attacker.command_attack(target as UnitBase)
		if scenario == "pursuit":
			(target as UnitBase)._process(STEP)
		attacker._process(STEP)
		_advance_impacts(arena, STEP)
	var result: Dictionary = {
		"damage": 10000.0 - float(target.get("hp")),
		"position": attacker.position,
		"paths": arena.path_requests,
		"cooldown": attacker.attack_cooldown,
	}
	arena.free()
	return result


func _test_autonomous_to_explicit(building_target: bool) -> void:
	for patrol: bool in [false, true]:
		var arena := Arena.new()
		add_child(arena)
		var attacker: UnitBase = _unit(arena, INFANTRY, 0, Vector2.ZERO)
		var target: Node2D
		if building_target:
			var building := HOUSE.instantiate() as BuildingBase
			building.player_owner = 1
			building.position = Vector2(20.0, 0.0)
			arena.add_child(building)
			building.set_process(false)
			building.complete_instantly()
			target = building
		else:
			var enemy: UnitBase = _unit(arena, INFANTRY, 1, Vector2(20.0, 0.0))
			enemy.damage = 0.0
			target = enemy
		if patrol:
			attacker.command_patrol(Vector2(400.0, 0.0))
		else:
			attacker.command_attack_move(Vector2(400.0, 0.0))
		if building_target:
			attacker.command_attack_building(target as BuildingBase, false, false)
		else:
			attacker.command_attack(target as UnitBase, false, false)
		attacker._process(STEP)
		var windup: float = attacker._attack_windup_remaining
		var animation: float = attacker._attack_animation_remaining
		var cooldown: float = attacker.attack_cooldown
		_expect(windup > 0.0 and attacker.attack_move, "autonomous attack starts a windup while retaining travel intent")
		if building_target:
			attacker.command_attack_building(target as BuildingBase)
		else:
			attacker.command_attack(target as UnitBase)
		_expect(attacker._forced_attack and not attacker.attack_move and not attacker._patrol_active, "explicit same-target attack replaces autonomous travel intent")
		_expect(attacker._attack_windup_remaining == windup and attacker._attack_animation_remaining == animation and attacker.attack_cooldown == cooldown, "promoting same-target attack preserves windup, pose and cooldown")
		if building_target:
			(target as BuildingBase).state = BuildingBase.State.DESTROYED
		else:
			(target as UnitBase).current_state = UnitBase.State.DEAD
		attacker._process(0.3)
		_expect(attacker.current_state == UnitBase.State.IDLE, "explicit target death cannot resume old attack-move or patrol")
		arena.free()


func _test_replacement_cancels_windup() -> void:
	for replacement: String in ["unit", "building", "stop", "retreat"]:
		var arena := Arena.new()
		add_child(arena)
		var attacker: UnitBase = _unit(arena, INFANTRY, 0, Vector2.ZERO)
		var original: UnitBase = _unit(arena, INFANTRY, 1, Vector2(20.0, 0.0))
		original.damage = 0.0
		attacker.command_attack(original)
		attacker._process(STEP)
		_expect(attacker._attack_windup_remaining > 0.0, "original attack has an unreleased windup")
		match replacement:
			"unit":
				var other: UnitBase = _unit(arena, INFANTRY, 1, Vector2(-20.0, 0.0))
				other.damage = 0.0
				attacker.command_attack(other)
				_expect(attacker.attack_target == other, "different unit target takes effect immediately")
			"building":
				var building := HOUSE.instantiate() as BuildingBase
				building.player_owner = 1
				arena.add_child(building)
				building.set_process(false)
				building.complete_instantly()
				attacker.command_attack_building(building)
				_expect(attacker.attack_building_target == building, "different building target takes effect immediately")
			"stop":
				attacker.command_stop()
			"retreat":
				attacker.command_move(Vector2(-200.0, 0.0))
		_expect(attacker._attack_windup_remaining < 0.0 and attacker._attack_animation_remaining == 0.0, "%s still cancels old windup and pose" % replacement)
		attacker._process(0.2)
		_advance_impacts(arena, 0.2)
		_expect(original.hp == original.max_hp, "%s cannot release the canceled hit" % replacement)
		arena.free()


func _unit(arena: Node2D, scene: PackedScene, owner: int, at: Vector2) -> UnitBase:
	var unit := scene.instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = at
	arena.add_child(unit)
	unit.set_process(false)
	return unit


func _test_autonomous_retarget_clears_old_route() -> void:
	var arena := Arena.new()
	add_child(arena)
	var attacker: UnitBase = _unit(arena, INFANTRY, 0, Vector2.ZERO)
	var original: UnitBase = _unit(arena, INFANTRY, 1, Vector2(100.0, 0.0))
	original.damage = 0.0
	attacker.command_attack(original, false, false)
	attacker._process(STEP)
	_expect(attacker._navigation_active and not attacker.path.is_empty(), "autonomous pursuit has an accepted route before retargeting")
	var threat: UnitBase = _unit(arena, INFANTRY, 1, attacker.position + Vector2(-20.0, 0.0))
	threat.command_attack(attacker)
	attacker._auto_attack_timer = 0.0
	attacker._process(STEP)
	_expect(attacker.attack_target == threat and not attacker._forced_attack, "autonomous pursuit switches to the immediate nearby attacker")
	_expect(not attacker._navigation_active and attacker.path.is_empty(), "new nearby target cannot inherit the previous pursuit route")
	_expect(attacker.get_remaining_navigation_path().is_empty(), "nearby retarget cannot display the old chase endpoint")
	arena.free()


func _advance_impacts(arena: Node2D, delta: float) -> void:
	for child: Node in arena.get_children():
		if child.has_method("advance_committed_hit"):
			child.call("advance_committed_hit")
			child.free()
		elif child.has_method("advance_projectile"):
			child.call("advance_projectile", delta)
			if bool(child.get("finished")):
				child.free()


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
