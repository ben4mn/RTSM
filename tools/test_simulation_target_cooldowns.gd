extends Node
## Scripted unit-clock fixture: production exclusion methods and auto-target
## selection, manual simulation deltas, then a real paused SceneTree wall wait.

const INFANTRY: PackedScene = preload("res://scenes/units/infantry.tscn")
const VILLAGER: PackedScene = preload("res://scenes/units/villager.tscn")
const AUTO_TARGETING: Script = preload("res://scripts/units/auto_targeting.gd")

var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _observe_only: bool = false
var _output: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--observe-only":
			_observe_only = true
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	_test_simulation_boundaries(0.25)
	_test_simulation_boundaries(1.0 / 60.0)
	await _test_pause_and_lifecycle()
	var receipt: Dictionary = {
		"scope": "Scripted real-unit exclusion/auto-acquisition fixture, manually stepped simulation; actual paused SceneTree wall wait. Cargo is a declared seven-Wood fixture load, not paid production or natural harvest.",
		"source": {
			"unit_base": FileAccess.get_file_as_string("res://scripts/units/unit_base.gd").sha256_text(),
			"villager": FileAccess.get_file_as_string("res://scripts/units/villager.gd").sha256_text(),
			"auto_targeting": FileAccess.get_file_as_string("res://scripts/units/auto_targeting.gd").sha256_text(),
			"fixture": FileAccess.get_file_as_string("res://tools/test_simulation_target_cooldowns.gd").sha256_text(),
		},
		"cases": _records,
		"failures": _failures,
	}
	if _output != "":
		var file := FileAccess.open(_output, FileAccess.WRITE)
		file.store_string(JSON.stringify(receipt, "\t"))
	print("[SIMULATION_TARGET_COOLDOWNS] ", JSON.stringify(receipt))
	get_tree().quit(0 if _failures.is_empty() or _observe_only else 1)

func _make_units() -> Dictionary:
	var fighter := INFANTRY.instantiate() as UnitBase
	add_child(fighter)
	fighter.set_process(false)
	# Keep manual clock steps free of autonomous combat side effects.
	fighter.set("_auto_attack_timer", 10000.0)
	var enemy := INFANTRY.instantiate() as UnitBase
	enemy.player_owner = 1
	enemy.position = Vector2(48.0, 0.0)
	add_child(enemy)
	enemy.set_process(false)
	var worker := VILLAGER.instantiate() as Villager
	add_child(worker)
	worker.set_process(false)
	worker.carried_resource_type = "wood"
	worker.carried_amount = 7
	var resource := Node2D.new()
	add_child(resource)
	var dropoff := Node2D.new()
	add_child(dropoff)
	return {"fighter": fighter, "enemy": enemy, "worker": worker, "resource": resource, "dropoff": dropoff}

func _remember(fixture: Dictionary) -> void:
	var fighter := fixture["fighter"] as UnitBase
	var worker := fixture["worker"] as Villager
	fighter._temporarily_ignore_auto_target(fixture["enemy"] as Node2D)
	worker._remember_unreachable_target(fixture["resource"] as Node2D, worker.get("_unreachable_resource_ids_until") as Dictionary)
	worker._remember_unreachable_target(fixture["dropoff"] as Node2D, worker.get("_unreachable_dropoff_ids_until") as Dictionary)

func _sample(fixture: Dictionary) -> Dictionary:
	var fighter := fixture["fighter"] as UnitBase
	var worker := fixture["worker"] as Villager
	var resources: Dictionary = worker.get("_unreachable_resource_ids_until") as Dictionary
	var dropoffs: Dictionary = worker.get("_unreachable_dropoff_ids_until") as Dictionary
	worker._prune_expired_unreachable_targets(resources)
	worker._prune_expired_unreachable_targets(dropoffs)
	return {
		"auto_ignored": fighter._is_auto_target_temporarily_ignored(fixture["enemy"] as Node2D),
		"resource_ignored": resources.has((fixture["resource"] as Node2D).get_instance_id()),
		"dropoff_ignored": dropoffs.has((fixture["dropoff"] as Node2D).get_instance_id()),
		"cargo_amount": worker.carried_amount,
		"cargo_type": worker.carried_resource_type,
	}

func _step(fixture: Dictionary, delta: float) -> void:
	(fixture["fighter"] as UnitBase)._process(delta)
	(fixture["worker"] as Villager)._process(delta)

func _test_simulation_boundaries(delta: float) -> void:
	var fixture: Dictionary = _make_units()
	_remember(fixture)
	var fighter := fixture["fighter"] as UnitBase
	var enemy := fixture["enemy"] as UnitBase
	_expect(AUTO_TARGETING.find_target(fighter, 96.0, 96.0, false) == null, "Ignored unreachable enemy stays out of automatic acquisition")
	var wall_started: int = Time.get_ticks_msec()
	var elapsed: float = 0.0
	while elapsed < 3.0 - delta * 0.5:
		_step(fixture, delta)
		elapsed += delta
		if elapsed < 3.0 - 0.00000001:
			_expect(fighter._is_auto_target_temporarily_ignored(enemy), "Automatic exclusion cannot expire before three simulation seconds")
	var at_three: Dictionary = _sample(fixture)
	# A float accumulator may cross a deadline on the next simulation frame.
	if bool(at_three["auto_ignored"]):
		_step(fixture, delta)
		elapsed += delta
		at_three = _sample(fixture)
	_expect(not bool(at_three["auto_ignored"]), "Automatic target exclusion expires after three simulation seconds at step %s" % delta)
	_expect(bool(at_three["resource_ignored"]) and bool(at_three["dropoff_ignored"]), "Worker exclusions remain active at three simulation seconds")
	_expect(AUTO_TARGETING.find_target(fighter, 96.0, 96.0, false) == enemy, "Simulation expiry makes the visible enemy eligible for automatic acquisition")
	while elapsed < 5.0 - delta * 0.5:
		_step(fixture, delta)
		elapsed += delta
		if elapsed < 5.0 - 0.00000001:
			_expect(((fixture["worker"] as Villager).get("_unreachable_resource_ids_until") as Dictionary).has((fixture["resource"] as Node2D).get_instance_id()), "Worker exclusion cannot expire before five simulation seconds")
	var at_five: Dictionary = _sample(fixture)
	if bool(at_five["resource_ignored"]) or bool(at_five["dropoff_ignored"]):
		_step(fixture, delta)
		elapsed += delta
		at_five = _sample(fixture)
	_expect(not bool(at_five["resource_ignored"]) and not bool(at_five["dropoff_ignored"]), "Resource and drop-off exclusions expire after five simulation seconds at step %s" % delta)
	_remember(fixture)
	for _tick: int in range(21):
		_step(fixture, 0.25)
	var worker := fixture["worker"] as Villager
	_expect((worker.get("_unreachable_resource_ids_until") as Dictionary).is_empty() and (worker.get("_unreachable_dropoff_ids_until") as Dictionary).is_empty(), "Idle processing expires cache keys before AI's ordinary exclusion read, without a gather retry")
	_expect(int(at_five["cargo_amount"]) == 7 and str(at_five["cargo_type"]) == "wood", "Clock advancement conserves declared worker cargo")
	_records.append({"kind": "simulation", "step_seconds": delta, "advanced_seconds": elapsed, "wall_elapsed_ms": Time.get_ticks_msec() - wall_started, "at_three": at_three, "at_five": at_five})
	_free_fixture(fixture)

func _test_pause_and_lifecycle() -> void:
	var fixture: Dictionary = _make_units()
	_remember(fixture)
	var fighter := fixture["fighter"] as UnitBase
	var enemy := fixture["enemy"] as UnitBase
	var worker := fixture["worker"] as Villager
	var clock_before: Variant = fighter.get("_simulation_elapsed_seconds")
	GameManager.set_state(GameManager.GameState.PAUSED)
	var wall_started: int = Time.get_ticks_msec()
	await get_tree().create_timer(5.20, true).timeout
	var after_wall_wait: Dictionary = _sample(fixture)
	_expect(bool(after_wall_wait["auto_ignored"]) and bool(after_wall_wait["resource_ignored"]) and bool(after_wall_wait["dropoff_ignored"]), "A five-second wall wait while paused does not expire gameplay exclusions")
	_step(fixture, 10.0)
	var after_paused_manual_step: Dictionary = _sample(fixture)
	_expect(bool(after_paused_manual_step["auto_ignored"]) and bool(after_paused_manual_step["resource_ignored"]), "Paused manual processing cannot advance the unit exclusion clock")
	GameManager.set_state(GameManager.GameState.PLAYING)
	# Explicit orders retain authority independently of automatic exclusions.
	fighter.command_attack(enemy)
	_expect(fighter.attack_target == enemy and fighter.current_state == UnitBase.State.ATTACKING, "An explicit attack still accepts an automatically excluded visible target")
	worker.command_move(Vector2(128.0, 0.0))
	_expect(worker.current_state == UnitBase.State.MOVING and worker.carried_amount == 7 and worker.carried_resource_type == "wood", "Explicit Move preserves worker cargo during exclusion")
	fighter.current_state = UnitBase.State.DEAD
	var dead_clock_before: Variant = fighter.get("_simulation_elapsed_seconds")
	fighter._process(6.0)
	_expect(fighter.get("_simulation_elapsed_seconds") == dead_clock_before, "Dead units do not advance their local simulation clock")
	_records.append({"kind": "pause_lifecycle", "wall_elapsed_ms": Time.get_ticks_msec() - wall_started, "clock_before": clock_before, "after_wall_wait": after_wall_wait, "after_paused_manual_step": after_paused_manual_step, "cargo_after_move": worker.carried_amount})
	_free_fixture(fixture)

func _free_fixture(fixture: Dictionary) -> void:
	for value: Variant in fixture.values():
		(value as Node).free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		print("[FAIL] ", message)
