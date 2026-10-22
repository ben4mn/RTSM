extends Node
## Deterministic real-unit boundary checks; no paid-economy or performance claim.

const ARCHER: PackedScene = preload("res://scenes/units/archer.tscn")
const INFANTRY: PackedScene = preload("res://scenes/units/infantry.tscn")
const HOUSE: PackedScene = preload("res://scenes/buildings/house.tscn")
const STEP: float = 1.0 / 60.0
var _failures: Array[String] = []
var _metrics: Array[Dictionary] = []
var _checks: int = 0

class Arena extends Node2D:
	var hidden_entities: Array[Node2D] = []
	func get_navigation_world_path(from: Vector2, to: Vector2, _radius: float = 4.0) -> PackedVector2Array:
		return PackedVector2Array([from, to])
	func world_to_tile(at: Vector2) -> Vector2i:
		return Vector2i(at / 16.0)
	func is_tile_walkable(_tile: Vector2i) -> bool:
		return true
	func is_entity_visible_to_player(entity: Node2D, _owner: int = 0) -> bool:
		return not hidden_entities.has(entity)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	get_tree().current_scene = null
	for owner: int in [0, 1]:
		for offset: float in [8.0, 9.0, 16.0]:
			_test_stationary_boundary(ARCHER, owner, offset)
			_test_stationary_boundary(INFANTRY, owner, offset)
		_test_moving_opponent(owner)
		_test_explicit_orders(owner)
		_test_passive_move_and_retaliation(owner)
		_test_fog(owner)
		_test_building_threat_boundary(owner)
		_test_aggressive_and_advancing_threats(owner)
	var report: Dictionary = {
		"passed": _failures.is_empty(), "failures": _failures, "metrics": _metrics,
		"checks": _checks,
		"unit_base_sha256": FileAccess.get_sha256("res://scripts/units/unit_base.gd"),
		"auto_targeting_sha256": FileAccess.get_sha256("res://scripts/units/auto_targeting.gd"),
		"user_data": OS.get_user_data_dir(), "step_seconds": STEP,
	}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var file := FileAccess.open(argument.trim_prefix("--output="), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(report, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] stand_ground_acquisition: " + failure)
	print("[METRIC] stand_ground_acquisition ", JSON.stringify(report))
	if _failures.is_empty():
		print("[PASS] stand_ground_acquisition: boundaries, moving targets, intent, retaliation, fog and building threat switches")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _arena() -> Arena:
	var arena := Arena.new()
	add_child(arena)
	return arena

func _unit(arena: Arena, scene: PackedScene, owner: int, at: Vector2) -> UnitBase:
	var unit := scene.instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = at
	arena.add_child(unit)
	unit.set_process(false)
	return unit

func _advance(arena: Arena, units: Array[UnitBase]) -> void:
	for unit: UnitBase in units:
		unit._process(STEP)
	for child: Node in arena.get_children():
		if child.has_method("advance_projectile"):
			child.call("advance_projectile", STEP)
			if bool(child.get("finished")):
				child.free()
		elif child.has_method("advance_committed_hit"):
			child.call("advance_committed_hit")
			child.free()

func _test_stationary_boundary(scene: PackedScene, owner: int, offset: float) -> void:
	var arena := _arena()
	var guard := _unit(arena, scene, owner, Vector2.ZERO)
	guard.stance = UnitBase.Stance.STAND_GROUND
	var distance: float = guard.attack_range + offset
	var enemy := _unit(arena, INFANTRY, 1 - owner, Vector2(distance, 0.0))
	var health: float = enemy.hp
	var acquisitions: int = 0
	var previous_target: UnitBase = null
	for tick: int in 180:
		_advance(arena, [guard])
		if guard.attack_target != null and previous_target == null:
			acquisitions += 1
		previous_target = guard.attack_target
	var label: String = "owner%d type%d distance%.0f" % [owner, guard.unit_type, distance]
	_expect(guard.position == Vector2.ZERO, label + " never moves autonomously")
	_expect(guard.attack_range == (80.0 if scene == ARCHER else 16.0), label + " keeps data-driven weapon range")
	if offset == 8.0:
		_expect(acquisitions == 1 and enemy.hp < health, label + " acquires at exact engagement boundary and lands real damage")
	else:
		_expect(acquisitions == 0, label + " never acquires an unreachable standing target")
		_expect(guard._ignored_auto_targets_until.is_empty(), label + " does not poison ignore cache with an out-of-range scan")
		_expect(enemy.hp == health, label + " does not extend weapon reach")
	_metrics.append({"case": "stationary", "owner": owner, "type": guard.unit_type, "distance": distance, "acquisitions": acquisitions, "damage": health - enemy.hp, "ignored_targets": guard._ignored_auto_targets_until.size(), "guard_distance": guard.position.length()})
	arena.free()

func _test_moving_opponent(owner: int) -> void:
	var arena := _arena()
	var guard := _unit(arena, ARCHER, owner, Vector2.ZERO)
	guard.stance = UnitBase.Stance.STAND_GROUND
	var enemy := _unit(arena, INFANTRY, 1 - owner, Vector2(96.0, 0.0))
	enemy.stance = UnitBase.Stance.STAND_GROUND
	enemy.command_move(Vector2(80.0, 0.0))
	var crossed_at: float = -1.0
	var acquired_at: float = -1.0
	var first_damage_at: float = -1.0
	var initial_hp: float = enemy.hp
	for tick: int in 240:
		# Guard scans first, so the baseline sees96 before the enemy moves inward.
		_advance(arena, [guard, enemy])
		var now: float = float(tick + 1) * STEP
		if crossed_at < 0.0 and enemy.position.length() <= 88.0:
			crossed_at = now
		if acquired_at < 0.0 and guard.attack_target == enemy and enemy.position.length() <= 88.0:
			acquired_at = now
		if first_damage_at < 0.0 and enemy.hp < initial_hp:
			first_damage_at = now
	_expect(crossed_at > 0.0 and acquired_at >= crossed_at and acquired_at - crossed_at <= 0.3 + STEP, "moving owner%d reacquires within one scan after crossing88" % owner)
	_expect(first_damage_at > crossed_at and first_damage_at - crossed_at < 1.0, "moving owner%d is not immune for the stale three-second ignore window" % owner)
	_expect(guard.position == Vector2.ZERO, "moving owner%d guard holds its exact position" % owner)
	enemy.command_move(Vector2(140.0, 0.0))
	for tick: int in 90:
		_advance(arena, [guard, enemy])
	_expect(guard.position == Vector2.ZERO and guard.attack_target == null, "moving owner%d guard releases the retreating target without chase" % owner)
	_metrics.append({"case": "moving", "owner": owner, "crossed_88_at": crossed_at, "acquired_in_range_at": acquired_at, "first_damage_at": first_damage_at, "guard_distance": guard.position.length(), "retreat_distance": enemy.position.length()})
	arena.free()

func _test_explicit_orders(owner: int) -> void:
	for distance: float in [89.0, 96.0]:
		var arena := _arena()
		var guard := _unit(arena, ARCHER, owner, Vector2.ZERO)
		guard.stance = UnitBase.Stance.STAND_GROUND
		var target := _unit(arena, INFANTRY, 1 - owner, Vector2(distance, 0.0))
		var distraction := _unit(arena, INFANTRY, 1 - owner, Vector2(0.0, 40.0))
		guard.command_attack(target)
		Combat.resolve_unit_hit(distraction, guard, 1.0, 1.0)
		_advance(arena, [guard])
		_expect(guard.attack_target == target and guard._forced_attack and guard.position.x > 0.0, "explicit owner%d at%.0f pursues chosen target despite retaliation" % [owner, distance])
		arena.free()
	for patrol: bool in [false, true]:
		var arena := _arena()
		var guard := _unit(arena, ARCHER, owner, Vector2.ZERO)
		guard.stance = UnitBase.Stance.STAND_GROUND
		var target := _unit(arena, INFANTRY, 1 - owner, Vector2(96.0, 0.0))
		var destination := Vector2(300.0, 0.0)
		if patrol:
			guard.command_patrol(destination)
		else:
			guard.command_attack_move(destination)
		guard._try_auto_attack()
		_expect(guard.attack_target == target, "advancing owner%d patrol%s retains original96 acquisition" % [owner, patrol])
		_advance(arena, [guard])
		_expect(guard.position.x > 0.0 and guard.attack_move and not guard._forced_attack, "advancing owner%d patrol%s retains permitted autonomous pursuit" % [owner, patrol])
		target.current_state = UnitBase.State.DEAD
		_advance(arena, [guard])
		_expect(guard.current_state == UnitBase.State.MOVING and guard.move_target == destination, "advancing owner%d patrol%s resumes its destination" % [owner, patrol])
		arena.free()

func _test_passive_move_and_retaliation(owner: int) -> void:
	var arena := _arena()
	var guard := _unit(arena, ARCHER, owner, Vector2.ZERO)
	guard.stance = UnitBase.Stance.STAND_GROUND
	var enemy := _unit(arena, INFANTRY, 1 - owner, Vector2(40.0, 0.0))
	guard.command_move(Vector2(110.0, 0.0))
	Combat.resolve_unit_hit(enemy, guard, 1.0, 1.0)
	var passive_violations: int = 0
	for tick: int in 180:
		_advance(arena, [guard])
		if guard.current_state != UnitBase.State.MOVING:
			break
		if guard.attack_target != null or not guard._force_move_active:
			passive_violations += 1
	_expect(passive_violations == 0 and guard.position.distance_to(Vector2(110.0, 0.0)) <= 4.0, "passive owner%d arrives without acquisition or retaliation" % owner)
	_advance(arena, [guard])
	_expect(guard.attack_target == enemy, "passive owner%d returns to standing acquisition after arrival" % owner)
	arena.free()
	for distance: float in [88.0, 89.0, 96.0]:
		arena = _arena()
		guard = _unit(arena, ARCHER, owner, Vector2.ZERO)
		guard.stance = UnitBase.Stance.STAND_GROUND
		enemy = _unit(arena, INFANTRY, 1 - owner, Vector2(distance, 0.0))
		Combat.resolve_unit_hit(enemy, guard, 1.0, 1.0)
		_expect((guard.attack_target == enemy) == (distance == 88.0), "retaliation owner%d respects88 boundary at%.0f" % [owner, distance])
		arena.free()

func _test_fog(owner: int) -> void:
	var arena := _arena()
	var guard := _unit(arena, ARCHER, owner, Vector2.ZERO)
	guard.stance = UnitBase.Stance.STAND_GROUND
	var enemy := _unit(arena, INFANTRY, 1 - owner, Vector2(88.0, 0.0))
	arena.hidden_entities.append(enemy)
	guard._try_auto_attack()
	guard.command_attack(enemy)
	_expect(guard.attack_target == null, "fog owner%d blocks both acquisition and explicit unseen targets" % owner)
	arena.hidden_entities.clear()
	guard._auto_attack_timer = 0.0
	guard._try_auto_attack()
	_expect(guard.attack_target == enemy, "fog owner%d permits currently visible boundary target" % owner)
	arena.hidden_entities.append(enemy)
	_advance(arena, [guard])
	_expect(guard.attack_target == null and guard.position == Vector2.ZERO, "fog owner%d invalidates an acquired target without movement" % owner)
	arena.free()

func _test_building_threat_boundary(owner: int) -> void:
	for scene: PackedScene in [ARCHER, INFANTRY]:
		for offset: float in [8.0, 9.0, 16.0]:
			var arena := _arena()
			var guard := _unit(arena, scene, owner, Vector2.ZERO)
			guard.stance = UnitBase.Stance.STAND_GROUND
			var distance: float = guard.attack_range + offset
			var building := HOUSE.instantiate() as BuildingBase
			building.player_owner = 1 - owner
			building.position = Vector2(0.0, guard.attack_range + 20.0)
			arena.add_child(building)
			building.set_process(false)
			building.complete_instantly()
			var threat := _unit(arena, INFANTRY, 1 - owner, Vector2(distance, 0.0))
			threat.command_attack(guard)
			guard.command_attack_building(building, false, false)
			_advance(arena, [guard])
			var label: String = "building threat owner%d type%d distance%.0f" % [owner, guard.unit_type, distance]
			_expect((guard.attack_target == threat) == (offset == 8.0), label + " only switches to an in-range threat")
			_expect(offset == 8.0 or guard.attack_building_target == building, label + " retains reachable building against out-of-range distraction")
			_expect(guard.position == Vector2.ZERO, label + " cannot provoke chase")
			_metrics.append({"case": "building_threat", "owner": owner, "type": guard.unit_type, "distance": distance, "retained_building": guard.attack_building_target == building, "acquired_threat": guard.attack_target == threat, "ignored_targets": guard._ignored_auto_targets_until.size()})
			guard.command_attack_building(building)
			guard._auto_attack_timer = 0.0
			_advance(arena, [guard])
			_expect(guard.attack_building_target == building and guard._forced_attack, label + " never replaces explicit building attack")
			arena.free()

func _test_aggressive_and_advancing_threats(owner: int) -> void:
	for scene: PackedScene in [ARCHER, INFANTRY]:
		var arena := _arena()
		var fighter := _unit(arena, scene, owner, Vector2.ZERO)
		var enemy := _unit(arena, INFANTRY, 1 - owner, Vector2(fighter.vision_radius, 0.0))
		fighter._try_auto_attack()
		_advance(arena, [fighter])
		_expect(fighter.attack_target == enemy and fighter.position.x > 0.0, "aggressive owner%d type%d retains vision-radius acquisition and pursuit" % [owner, fighter.unit_type])
		arena.free()
	var arena := _arena()
	var fighter := _unit(arena, ARCHER, owner, Vector2.ZERO)
	fighter.stance = UnitBase.Stance.STAND_GROUND
	var building := HOUSE.instantiate() as BuildingBase
	building.player_owner = 1 - owner
	building.position = Vector2(0.0, 100.0)
	arena.add_child(building)
	building.set_process(false)
	building.complete_instantly()
	var enemy := _unit(arena, INFANTRY, 1 - owner, Vector2(96.0, 0.0))
	enemy.command_attack(fighter)
	fighter.command_attack_move(Vector2(300.0, 0.0))
	fighter.command_attack_building(building, false, false)
	_advance(arena, [fighter])
	_expect(fighter.attack_target == enemy and fighter.attack_move and fighter.position.x > 0.0, "advancing owner%d still switches from building to beyond-reach threat and pursues" % owner)
	arena.free()

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and not _failures.has(message):
		_failures.append(message)
