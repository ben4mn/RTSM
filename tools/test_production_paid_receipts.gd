extends Node

const CODEC := preload("res://scripts/main/solo_match_state.gd")
const TC := preload("res://scenes/buildings/town_center.tscn")
var checks := 0
var failures: Array[String] = []
var codec = CODEC.new()
var building: BuildingBase
var queue: ProductionQueue

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _ready() -> void: call_deferred("_run")

func _reset() -> void:
	if is_instance_valid(building): building.free()
	GameManager.initialize_game(1)
	ResourceManager.initialize_player(0, {"food": 1000, "wood": 1000, "gold": 1000})
	building = TC.instantiate()
	add_child(building)
	building.complete_instantly()
	building.trainable_units.assign([UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY])
	queue = building.get_production_queue()
	codec._references.clear()

func _saved_entry(cost: Dictionary, legacy: bool = false, unit_type: int = UnitData.UnitType.ARCHER) -> Dictionary:
	check(ResourceManager.try_spend(0, cost), "fixture pays exact checkpoint receipt")
	var reservation: int = GameManager.reserve_population(0, 2)
	check(reservation >= 0, "fixture reserves paid population")
	var data := {"queue": [unit_type], "current_progress": 3.25, "current_train_time": 20.0,
		"is_training": true, "_population_reservation_ids": [reservation]}
	if not legacy: data.paid_costs = [cost.duplicate(true)]
	return data

func _run() -> void:
	AudioManager.set_all_enabled(false)
	_reset()
	check(queue.enqueue_unit(UnitData.UnitType.ARCHER), "ordinary purchase accepted")
	check(queue.paid_costs == [UnitData.get_unit_cost(UnitData.UnitType.ARCHER)], "ordinary purchase records current exact cost")
	queue.cancel_all()
	check(ResourceManager.get_all_resources(0) == {"food": 1000, "wood": 1000, "gold": 1000}, "ordinary cancel restores exact bank")
	for path: String in ["single", "all", "missing", "unclaimed", "rejected", "consumed", "consume_failed"]:
		_reset()
		var receipt := {"food": 17, "wood": 23, "gold": 5}
		var data: Dictionary = _saved_entry(receipt)
		# The generic save decoder remaps integer actor IDs. Cost quantities must
		# bypass it even when a quantity happens to equal a captured actor ID.
		codec._references[17] = building
		codec._restore_queue(queue, data)
		check(queue.current_progress == 3.25 and queue._population_reservation_ids == data._population_reservation_ids, path + " preserves progress and reservation")
		check(queue.paid_costs == [receipt], path + " preserves amounts without reference remapping")
		var captured: Dictionary = codec._capture_queue(queue)
		check(captured.paid_costs == [receipt], path + " serializes exact receipt")
		data.paid_costs[0].gold = 999
		check(queue.paid_costs[0].gold == 5, path + " restore owns a deep copy")
		if path == "single": queue.cancel_unit(0)
		elif path == "all": queue.cancel_all()
		else:
			if path == "missing":
				GameManager.release_population_reservation(queue._population_reservation_ids[0])
				queue._population_reservation_ids.clear()
			elif path == "rejected": queue.unit_trained.connect(func(_type: int) -> void: queue.reject_completed_unit())
			elif path == "consumed": queue.unit_trained.connect(func(_type: int) -> void: check(queue.consume_completed_population_reservation(), "successful spawn consumes reservation"))
			elif path == "consume_failed": queue.unit_trained.connect(func(_type: int) -> void:
				GameManager.release_population_reservation(queue._pending_completion_reservation_id)
				check(not queue.consume_completed_population_reservation(), "failed spawn consume retains receipt for rollback")
			)
			queue.advance(20.0)
		var expected := {"food": 983, "wood": 977, "gold": 995} if path == "consumed" else {"food": 1000, "wood": 1000, "gold": 1000}
		check(ResourceManager.get_all_resources(0) == expected, path + " uses receipt exactly once")
		check(queue.paid_costs.is_empty() and queue.queue.is_empty() and queue._pending_completion_paid_cost.is_empty(), path + " clears consumed receipt")
		queue.cancel_all()
		queue.reject_completed_unit()
		check(ResourceManager.get_all_resources(0) == expected, path + " repeated cleanup cannot mint resources")
	_reset()
	check(queue.enqueue_unit(UnitData.UnitType.ARCHER) and queue.enqueue_unit(UnitData.UnitType.CAVALRY), "mixed finite queue purchases accepted")
	var first_receipt: Dictionary = queue.paid_costs[0].duplicate(true)
	queue.cancel_last()
	check(queue.paid_costs == [first_receipt] and queue.queue == [UnitData.UnitType.ARCHER], "tail cancellation preserves receipt alignment")
	var cancel_on_refund: Callable = func(_owner: int, _resource: String, _amount: int) -> void: queue.cancel_all()
	ResourceManager.resources_changed.connect(cancel_on_refund, CONNECT_ONE_SHOT)
	queue.cancel_unit(0)
	check(ResourceManager.get_all_resources(0) == {"food": 1000, "wood": 1000, "gold": 1000}, "reentrant cancellation cannot refund the same receipt twice")
	for type: int in [UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY]:
		_reset()
		var legacy: Dictionary = CODEC.LEGACY_QUEUE_COSTS[type]
		codec._restore_queue(queue, _saved_entry(legacy, true, type))
		check(queue.paid_costs == [legacy] and queue.current_progress == 3.25, "old checkpoint migrates fixed beta16 price and retains progress")
		queue.cancel_all()
		check(ResourceManager.get_all_resources(0) == {"food": 1000, "wood": 1000, "gold": 1000}, "legacy refund returns old wood and creates no gold")
	var valid := {"queue": [UnitData.UnitType.ARCHER], "paid_costs": [{"food": 50, "wood": 70, "gold": 20}]}
	check(CODEC._valid_queue_receipts(valid), "future price is allowed as an exact saved receipt")
	for bad: Variant in [null, [], [{"food": 50, "wood": 90}], [{"food": -1, "wood": 0, "gold": 0}], [{"food": 50.0, "wood": 0, "gold": 0}], [{"food": 50, "wood": 0, "gold": 0, "extra": 1}]]:
		check(not CODEC._valid_queue_receipts({"queue": [2], "paid_costs": bad}), "malformed receipt rejected")
	building.free()
	print(JSON.stringify({"result": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
