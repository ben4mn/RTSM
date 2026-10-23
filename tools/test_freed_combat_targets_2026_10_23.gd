extends Node
## Genuine freed references must reach lifetime guards before typed use.
const INFANTRY: PackedScene = preload("res://scenes/units/infantry.tscn")
const ARCHER: PackedScene = preload("res://scenes/units/archer.tscn")
const HOUSE: PackedScene = preload("res://scenes/buildings/house.tscn")
var failures: Array[String] = []
var checks: int = 0
var records: Array[Dictionary] = []

class Arena extends Node2D:
	func get_navigation_world_path(from: Vector2, to: Vector2, _radius: float = 4.0) -> PackedVector2Array:
		return PackedVector2Array([from, from.lerp(to, 0.5), to])
	func world_to_tile(at: Vector2) -> Vector2i:
		return Vector2i(at / 16.0)
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
	for building: bool in [false, true]:
		for ranged: bool in [false, true]:
			for resume: bool in [false, true]:
				await _target_removed(building, ranged, resume, false)
				await _target_removed(building, ranged, resume, true)
	_retaliate_after_target_removed()
	var output: String = "res://output/polish-freed-combat-targets-2026-10-23"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output.path_join("lifetime.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Private headless synthetic arena; genuine queue_free during pursuit and windup, not merely DEAD state. No native/performance claim.", "checks": checks, "failures": failures, "records": records, "unit_base_sha256": FileAccess.get_sha256("res://scripts/units/unit_base.gd"), "fixture_sha256": FileAccess.get_sha256("res://tools/test_freed_combat_targets_2026_10_23.gd")}, "  ") + "\n")
	for failure: String in failures: push_error("[FAIL] freed_combat_targets: " + failure)
	if failures.is_empty(): print("[PASS] freed_combat_targets: ", checks, " checks; queued target deletion during pursuit/windup, explicit cleanup, attack-move resume and retaliation")
	get_tree().quit(0 if failures.is_empty() else 1)

func _target_removed(building: bool, ranged: bool, resume: bool, windup: bool) -> void:
	var arena := Arena.new()
	add_child(arena)
	var attacker: UnitBase = _unit(arena, ARCHER if ranged else INFANTRY, 0, Vector2.ZERO)
	var target: Node2D
	if building:
		var house := HOUSE.instantiate() as BuildingBase
		house.player_owner = 1
		house.position = Vector2(20.0 if windup else 110.0, 0.0)
		arena.add_child(house)
		house.complete_instantly()
		house.set_process(false)
		target = house
	else:
		target = _unit(arena, INFANTRY, 1, Vector2(20.0 if windup else 110.0, 0.0))
	if resume: attacker.command_attack_move(Vector2(900.0, 0.0))
	if building: attacker.command_attack_building(target, not resume, not resume)
	else: attacker.command_attack(target, not resume, not resume)
	attacker._process(0.01)
	_expect(attacker._attack_windup_remaining > 0.0 if windup else attacker._navigation_active, "fixture has pending strike or live pursuit before removal")
	var initial_cooldown: float = attacker.attack_cooldown
	# Keep an actual dangling Object handle across a deferred queue deletion.
	var removed: Variant = target
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not is_instance_valid(removed), "target is actually freed, not just marked dead")
	attacker._process(0.3)
	var after_state: int = attacker.current_state
	var route_after: int = attacker.get_remaining_navigation_path().size()
	_expect(after_state == (UnitBase.State.MOVING if resume else UnitBase.State.IDLE), "removed target releases attack state and restores only authorized movement")
	_expect(attacker.attack_target == null and attacker.attack_building_target == null, "removed target references are cleared")
	_expect(not attacker._navigation_active and attacker.path.is_empty() and route_after == 0, "obsolete chase and route feedback are cleared before a new movement step")
	_expect(attacker._attack_windup_remaining < 0.0, "freed target cannot retain an unreleased strike")
	_expect(attacker.attack_cooldown <= initial_cooldown, "cleanup cannot restart the attack cadence")
	_check_freed_validator(attacker, removed, building)
	if resume:
		var before: Vector2 = attacker.position
		attacker._process(0.1)
		_expect(attacker.position.distance_to(before) > 0.0 and attacker.move_target == Vector2(900.0, 0.0), "attack-move makes progress after target removal")
	records.append({"building": building, "ranged": ranged, "resume": resume, "windup": windup, "state_after": after_state, "route_after": route_after})
	arena.free()

func _check_freed_validator(attacker: UnitBase, removed: Variant, building: bool) -> void:
	# A baseline typed-argument error aborts this helper only; each arena still
	# cleans up so a failed case cannot contaminate later cases.
	if building: _expect(not attacker._is_valid_building_target(removed), "building validator accepts a freed handle and returns false")
	else: _expect(not attacker._is_valid_target(removed), "unit validator accepts a freed handle and returns false")

func _retaliate_after_target_removed() -> void:
	var arena := Arena.new()
	add_child(arena)
	var defender: UnitBase = _unit(arena, INFANTRY, 0, Vector2.ZERO)
	var original: UnitBase = _unit(arena, INFANTRY, 1, Vector2(200.0, 0.0))
	defender.command_attack(original, false, false)
	original.free()
	var replacement: UnitBase = _unit(arena, INFANTRY, 1, Vector2(20.0, 0.0))
	defender.respond_to_attacker(replacement)
	_expect(defender.attack_target == replacement, "retaliation replaces a genuinely freed autonomous target")
	_expect(not defender._is_valid_target(null) and not defender._is_valid_building_target(null), "null targets remain invalid")
	arena.free()

func _unit(arena: Node2D, scene: PackedScene, owner: int, at: Vector2) -> UnitBase:
	var unit := scene.instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = at
	arena.add_child(unit)
	unit.set_process(false)
	return unit

func _expect(condition: bool, detail: String) -> void:
	checks += 1
	if not condition: failures.append(detail)
