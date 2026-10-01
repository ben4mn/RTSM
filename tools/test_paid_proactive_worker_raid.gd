extends "res://tools/test_paid_worker_recovery.gd"
## Paid A/B diagnostic. Baseline suppresses only the new proactive scan via its
## timer; damage, paid training, travel, harvest, retreat and deposit are real.
## Raiders withdraw on the first recovery event, so this measures warning lead
## and preserved HP/cargo/job rather than survival against an uninterrupted raid.

func _run() -> void:
	AudioManager.set_all_enabled(false)
	var results: Array[Dictionary] = []
	for seed: int in [202, 404]:
		_probe_seed = seed
		for resource: String in ["food", "wood"]:
			for count: int in [1, 3]:
				for damage_only: bool in [true, false]:
					await _start()
					await _raid(damage_only, resource, count)
					results.append(_last_raid_result.duplicate(true))
					_main.free()
					_workers.clear()
					GameManager.set_state(GameManager.GameState.MENU)
					await get_tree().process_frame
	Engine.time_scale = 1.0
	print("PAID_PROACTIVE_AB_MATRIX ", JSON.stringify(results))
	if _failures.is_empty():
		print("[PASS] paid_proactive_worker_raid: 16 paid A/B raids, seeds202/404, Food/Wood,1/3Warriors, current25HP zero-hit warning, baseline natural8HP hit, exact job/cargo resume")
	else:
		for failure: String in _failures:
			push_error("[FAIL] paid_proactive_worker_raid: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
