extends Node
## Exercise actual action clocks and inert replica presentation, not combat mocks.
var failures: Array[String] = []
var checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameManager.players.clear()
	GameManager.current_state = 0
	GameManager.reduced_motion = false
	GameManager.reduced_flashes = true
	AudioManager.set_all_enabled(false)
	for civ: int in 3:
		GameManager.selected_civilization = civ
		for resource: String in ["wood", "food", "gold", "stone"]:
			_check_worker(resource)
		_check_farm()
		for role: int in 6:
			_check_attack(role)
	for failure: String in failures:
		push_error("[FAIL] unit_actions: " + failure)
	if failures.is_empty():
		print("[PASS] unit_actions: %d checks; all settlements, actual gather cadence, distinct role poses, release timing, bounded replica payloads, reduced motion, inert economy/combat" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)


func _worker() -> Villager:
	var worker: Villager = load("res://scenes/units/villager.tscn").instantiate()
	add_child(worker)
	worker.set_process(false)
	return worker


func _check_worker(resource: String) -> void:
	var worker: Villager = _worker()
	var target := ResourceNode.new()
	target.resource_type = resource
	target.position = Vector2(20, 0)
	add_child(target)
	target.set_process(false)
	_check(worker.command_gather(target), "Actual resource order accepted")
	var period: float = worker.gather_tick_time / float(UnitData.RESOURCE_GATHER_SPEEDS.get(resource, 1.0))
	worker._process_gathering(period * 0.55)
	var work: Vector3 = worker.get_work_presentation()
	var expected: int = {"wood": UnitActionPresentation.Action.CHOP, "food": UnitActionPresentation.Action.FORAGE, "gold": UnitActionPresentation.Action.MINE, "stone": UnitActionPresentation.Action.MINE}[resource]
	_check(int(work.x) == expected, "Actual work picks the correct tool")
	_check(is_equal_approx(work.y, 0.55), "Work phase uses authoritative gather timer")
	_check(worker.carried_amount == 0, "Anticipation earns no premature resource")
	worker._update_sprite_motion(0.0)
	_check_work_attachment(worker)
	var preparation: Transform2D = worker._sprite.transform
	var children: int = worker.get_child_count()
	worker._process_gathering(period * 0.45)
	worker._update_sprite_motion(0.0)
	_check_work_attachment(worker)
	_check(worker.carried_amount == 1, "Exactly one unchanged harvest at release")
	_check(not preparation.is_equal_approx(worker._sprite.transform), "Lift and contact poses visibly differ")
	var cargo: int = worker.carried_amount
	var remaining: int = target.remaining
	var timer: float = worker.gather_timer
	for frame: int in 120:
		worker._update_sprite_motion(1.0 / 60.0)
	_check(worker.carried_amount == cargo and target.remaining == remaining and worker.gather_timer == timer, "Presentation never advances economy")
	_check(worker.get_child_count() == children, "Work uses a persistent overlay without per-frame nodes")
	var replica: Villager = _worker()
	replica.process_mode = Node.PROCESS_MODE_DISABLED
	replica.current_state = UnitBase.State.GATHERING
	replica.apply_work_presentation([expected, 0.4, period])
	replica._update_sprite_motion(period * 0.1)
	_check(is_equal_approx(replica.get_work_presentation().y, 0.5), "Inert replica advances only visible work phase")
	_check(replica._action_presentation.action == expected and replica.carried_amount == 0, "Replica displays tool without harvest")
	for malformed: Variant in [[], [1, 0.5], [UnitActionPresentation.Action.MELEE, 0.5, 1.0], [1, NAN, 1.0], [1, 0.5, 0.0], ["wood", 0.5, 1.0], [1.2, 0.5, 1.0]]:
		replica.apply_work_presentation(malformed)
		_check(replica.get_work_presentation() == Vector3.ZERO, "Malformed work pose is cleared")
	GameManager.reduced_motion = true
	replica.apply_work_presentation([expected, 0.1, period])
	replica._update_sprite_motion(0.0)
	var quiet_pose: Transform2D = replica._sprite.transform
	replica._update_sprite_motion(period * 0.5)
	_check(replica._sprite.transform.is_equal_approx(quiet_pose), "Reduced motion holds a stable body pose")
	_check(replica._action_presentation.quiet_motion and replica._action_presentation.quiet_flashes, "Accessibility reaches equipment drawing")
	GameManager.reduced_motion = false
	replica.apply_work_presentation([])
	replica._update_sprite_motion(0.0)
	_check(not replica._action_presentation.visible, "Idle hides the tool overlay")
	replica.free()
	worker.free()
	target.free()


func _check_farm() -> void:
	var worker: Villager = _worker()
	var farm := BuildingBase.new()
	farm.building_type = BuildingData.BuildingType.FARM
	farm.state = BuildingBase.State.ACTIVE
	farm.position = Vector2(20, 0)
	add_child(farm)
	farm.set_process(false)
	_check(worker.command_gather(farm), "Actual Farm assigns the worker")
	var period: float = worker.gather_tick_time / float(UnitData.RESOURCE_GATHER_SPEEDS["food"])
	worker._process_gathering(period * 0.55)
	_check(int(worker.get_work_presentation().x) == UnitActionPresentation.Action.FARM, "Actual Farm uses a hoe, distinct from a food ResourceNode")
	worker._update_sprite_motion(0.0)
	_check_work_attachment(worker)
	_check(worker._action_presentation.action == UnitActionPresentation.Action.FARM, "Farm pose reaches renderer")
	# Mirroring the drawing must preserve its grip, not mirror the work target
	# or alter resource ownership. Check actual transformed sleeve coordinates.
	worker._sprite.flip_h = true
	worker._update_sprite_motion(0.0)
	_check_work_attachment(worker)
	worker._process_gathering(period * 0.45)
	_check(worker.carried_amount == 1, "Farm still yields only on the unchanged gather tick")
	worker.free()
	farm.free()


func _check_work_attachment(worker: Villager) -> void:
	_check(worker._sprite.position.is_zero_approx(), "Working feet stay planted at the unit origin")
	var facing: float = -1.0 if worker._sprite.flip_h else 1.0
	var sleeve := Vector2(0.0, -13.0)
	var body_sleeve: Vector2 = worker._sprite.to_global(sleeve * Vector2(facing, 1.0) / worker._sprite_rest_scale)
	var tool_sleeve: Vector2 = worker._action_presentation.to_global(sleeve)
	_check(body_sleeve.distance_to(tool_sleeve) < 0.01, "Tool sleeve follows body bend and mirrored facing")


func _check_attack(role: int) -> void:
	var unit: UnitBase = load("res://scenes/units/unit_base.tscn").instantiate()
	unit.unit_type = role
	add_child(unit)
	unit.set_process(false)
	var target := Node2D.new()
	target.position = Vector2(30, 0)
	add_child(target)
	unit.current_state = UnitBase.State.ATTACKING
	unit._begin_attack_windup(target, false)
	var windup: float = float(UnitData.UNITS[role].get("attack_windup", 0.12))
	_check(is_equal_approx(unit._attack_animation_duration, windup + 0.16), "Attack release/recovery timing unchanged")
	var hp_before: float = unit.hp
	var cooldown: float = unit.attack_cooldown
	unit._update_sprite_motion(windup * 0.5)
	var anticipation: Transform2D = unit._sprite.transform
	unit._update_sprite_motion(windup * 0.5)
	_check(not unit._sprite.transform.is_equal_approx(anticipation), "Anticipation differs from release for every role")
	_check(is_equal_approx(unit._action_presentation.phase, UnitActionPresentation.RELEASE), "Visual release coincides with existing windup")
	_check(unit._attack_windup_remaining == windup and unit.attack_cooldown == cooldown and unit.hp == hp_before, "Visual clock does not execute combat")
	unit._update_sprite_motion(0.17)
	_check(unit._sprite.position.is_zero_approx() and is_zero_approx(unit._sprite.rotation) and unit._sprite.scale == unit._sprite_rest_scale, "Attack settles to exact rest pose")
	unit.free()
	target.free()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
