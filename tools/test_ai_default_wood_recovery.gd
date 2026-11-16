extends "res://tools/test_ai_resource_deficit_search.gd"
## Same bounded real Villager search policy at compact and default population.
## Food-heavy banks and controlled visibility are fixture setup, not match income.
var _checks: int = 0
var _cases: Array[Dictionary] = []

func _run() -> void:
	AudioManager.set_all_enabled(false)
	for limit: int in [20, 100]:
		_case(limit)
	print(JSON.stringify({"test": "ai_default_wood_recovery", "checks": _checks, "failures": _failures, "cases": _cases, "scope": "controlled visibility, explicit bank and existing real worker search/assignment; no full-match or income claim"}))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	_expect(ok, label)

func _case(limit: int) -> void:
	GameManager.selected_population_limit = limit
	GameManager.initialize_game(2)
	GameManager.players[1].age = 2
	ResourceManager.initialize_player(1, {"food": 826, "wood": 12, "gold": 540})
	var map := SearchMap.new()
	add_child(map)
	var base_tile := Vector2i(33, 6)
	var ai := AIController.new()
	ai.player_id = 1
	ai.game_map = map
	add_child(ai)
	ai.start_ai(base_tile, map.tile_to_world(base_tile))
	ai._decision_timer.stop()
	ai.set_process(false)
	ai._archery_range_count = 1
	ai._stable_count = 1
	var food: ResourceNode = _resource(map, "food", base_tile + Vector2i(3, 0))
	var workers: Array[Villager] = []
	for index: int in 5:
		var worker := preload("res://scenes/units/villager.tscn").instantiate() as Villager
		worker.player_owner = 1
		worker.position = map.tile_to_world(base_tile) + Vector2(index * 10.0, 0)
		map.add_child(worker)
		worker.set_process(false)
		ai.register_unit(worker)
		workers.append(worker)
		if index < 3: worker.command_gather(food)
	var bank: Dictionary = ResourceManager.get_all_resources(1)
	var targets: Dictionary = ai._get_economy_worker_targets(5, bank)
	_check(int(targets.wood) > 0, "%d: real policy requests wood labor" % limit)
	ai._assign_idle_villagers()
	var moving: int = 0
	var food_jobs: int = 0
	for worker: Villager in workers:
		moving += int(worker.current_state == UnitBase.State.MOVING)
		food_jobs += int(worker.gather_target == food)
	_check(moving == 1 and food_jobs == 4, "%d: one idle worker searches for missing wood before all-food fallback" % limit)
	_check(ai._economy_wood_search_orders_issued == 1 and ai._get_active_wood_search_worker() == workers[3], "%d: exactly one targeted search is owned" % limit)
	_check(ResourceManager.get_all_resources(1) == bank, "%d: search has no bank mutation" % limit)
	var before_orders: int = ai._economy_exploration_orders_issued
	ai._assign_idle_villagers()
	_check(ai._economy_exploration_orders_issued == before_orders, "%d: later idle pass does not duplicate the search" % limit)
	_cases.append({"limit": limit, "targets": targets, "searching": moving, "food_jobs": food_jobs, "bank": bank})
	# Actual visible supply takes priority over exploring as soon as it appears.
	workers[3].command_stop()
	var wood: ResourceNode = _resource(map, "wood", base_tile + Vector2i(2, 1))
	ai._assign_idle_villagers()
	_check(workers[3].gather_target == wood, "%d: revealed wood takes a real gather assignment" % limit)
	workers[3].command_stop()
	map.resources.erase(wood)
	# A loaded or retreating idle worker must keep the existing safety contract.
	workers[3].carried_resource_type = "food"
	workers[3].carried_amount = 7
	before_orders = ai._economy_exploration_orders_issued
	ai._assign_idle_villagers()
	_check(workers[3].carried_amount == 7 and ai._economy_exploration_orders_issued == before_orders, "%d: loaded worker retains cargo and is never sent exploring" % limit)
	workers[3].carried_amount = 0
	workers[3].command_stop()
	workers[3].set("_auto_recovering", true)
	ai._assign_idle_villagers()
	_check(workers[3].current_state == UnitBase.State.IDLE and ai._economy_exploration_orders_issued == before_orders, "%d: retreat ownership blocks exploration" % limit)
	workers[3].set("_auto_recovering", false)
	# Hidden wood is never read by the map's guarded resource lookup; failed
	# normal movement paths must not turn the search into a fabricated job.
	map.resource_visible = false
	map.fail_routes = true
	ai._reset_economy_recovery()
	ai._assign_idle_villagers()
	_check(map.visibility_guard_returns > 0 and ai._economy_exploration_orders_issued == 0, "%d: hidden lookup guard and route rejection remain intact" % limit)
	_check(ai._economy_exploration_route_checks <= AIController.ECONOMY_EXPLORATION_ROUTE_CHECKS_PER_WORKER, "%d: failed search keeps its existing bounded route budget" % limit)
	_check(ResourceManager.get_all_resources(1) == bank, "%d: all recovery branches preserve bank" % limit)
	ai.free()
	map.free()
