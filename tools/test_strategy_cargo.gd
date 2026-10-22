extends "res://tools/test_paid_worker_recovery.gd"
## Overview reallocation must preserve naturally harvested cargo and skip safety
## recovery. Uses real visibility, navigation, resource nodes and TC drop-off.

func _run() -> void:
	AudioManager.set_all_enabled(false)
	await _start()
	var worker: Villager = _workers[0]
	worker.set_process(true)
	_track(worker)
	var wood: ResourceNode = _map.get_nearest_reachable_resource_node("wood", worker.global_position, 0) as ResourceNode
	_expect(wood != null and worker.command_gather(wood), "natural wood gather is required")
	var stock: int = wood.remaining
	var bank: int = ResourceManager.get_resource(0, "wood")
	await _until(func() -> bool: return worker.carried_amount >= 4, 60.0)
	var cargo: int = worker.carried_amount
	_expect(cargo > 0 and worker.carried_resource_type == "wood", "reallocation starts with natural wood cargo")
	var controller: Node = _main.get_node("StrategyController")
	var gold: Node2D = _map.get_nearest_reachable_resource_node("gold", worker.global_position, 0)
	_expect(gold != null, "visible gold destination is required")
	controller.call("_allocate_worker", "wood", "gold")
	_expect(worker.carried_amount == cargo and worker.get_carried_resources() == {"wood": cargo} and worker.get_economy_task() == "gold", "overview must immediately retask while preserving original cargo accounting")
	await _until(func() -> bool: return int(_deposits.wood) == cargo, 80.0)
	_expect(ResourceManager.get_resource(0, "wood") == bank + cargo and stock - wood.remaining == cargo, "old resource bank must receive exactly its natural harvest")
	await _until(func() -> bool: return int(_deposits.gold) > 0, 100.0)
	_expect(int(_deposits.wood) == cargo and int(_deposits.gold) > 0, "gold retask must deliver new gold without retyping or duplicating wood")
	var recovering: Villager = _workers[1]
	recovering.take_damage(1.0)
	_expect(recovering.is_auto_recovering(), "recovery fixture did not enter protection")
	controller.call("_allocate_worker", "idle", "food")
	_expect(recovering.is_auto_recovering(), "overview stole a recovering worker")
	var assigned: int = 0
	for candidate: Villager in [_workers[2], _workers[3]]:
		if candidate.get_economy_task() == "food":
			assigned += 1
	_expect(assigned == 1, "explicit idle allocation must retask exactly one available worker")
	_main.free()
	_workers.clear()
	Engine.time_scale = 1.0
	GameManager.set_state(GameManager.GameState.MENU)
	for failure: String in _failures:
		push_error("[FAIL] strategy_cargo: " + failure)
	if _failures.is_empty():
		print("[PASS] strategy_cargo: natural wood harvest survives explicit Gold retask and deposits exactly once alongside new gold; recovering worker protected and exactly one idle worker retasked")
	get_tree().quit(0 if _failures.is_empty() else 1)
