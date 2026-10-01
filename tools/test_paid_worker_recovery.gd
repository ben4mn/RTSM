extends Node
## Natural seeded Main scene: paid enemy Warriors walk into a real raid, with
## proactive and damage-only A/B recovery followed by explicit withdrawal. Two
## separate 75-wood Farms are funded, built, harvested and delivered normally.
## AI strategy and other worker processing are paused to isolate these orders.

var _failures: Array[String] = []
var _main: Node
var _map: Node2D
var _workers: Array[Villager] = []
var _deposits: Dictionary = {}
var _hits: int = 0
var _worker_at_hit: Dictionary = {}
var _probe_seed: int = 404
var _suppress_preemptive_for: Villager = null
var _paid_raiders: Array[UnitBase] = []
var _last_raid_result: Dictionary = {}

func _process(_delta: float) -> void:
	# A/B diagnostic: bypass only the new scan, preserving real damage/flee.
	if is_instance_valid(_suppress_preemptive_for):
		_suppress_preemptive_for.set("_economic_threat_check_timer", 1000000.0)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	for mode: String in ["raid", "raid_damage", "empty_farm", "loaded_farm"]:
		await _start()
		if mode.begins_with("raid"):
			await _raid(mode == "raid_damage")
		else:
			await _farm(mode == "loaded_farm")
		_main.free()
		_workers.clear()
		GameManager.set_state(GameManager.GameState.MENU)
		await get_tree().process_frame
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("[PASS] paid_worker_recovery: natural paid Warrior proactive/damage-only raid/withdrawal, exact worker job/cargo resume, paid empty/loaded Farm auto-work and real TC delivery")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] paid_worker_recovery: " + failure)
		get_tree().quit(1)

func _start() -> void:
	GameManager.set_state(GameManager.GameState.MENU)
	GameManager.selected_map_seed = _probe_seed
	GameManager.selected_population_limit = 30
	GameManager.selected_difficulty = AIController.Difficulty.EASY
	GameManager.guided_opening_enabled = false
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_map = _main.get("game_map") as Node2D
	var ai: Node = _main.get("ai_controller")
	ai.set_process(false)
	(ai.get("_decision_timer") as Timer).stop()
	Engine.time_scale = 4.0
	for unit: Node in _main.get("_player_units")[0]:
		if unit is Villager:
			var worker := unit as Villager
			worker.command_stop()
			worker.set_process(false)
			_workers.append(worker)
	_deposits = {"wood": 0, "food": 0, "gold": 0}
	_paid_raiders.clear()
	_suppress_preemptive_for = null
	_last_raid_result = {}

func _track(worker: Villager) -> void:
	worker.resource_deposited.connect(func(kind: String, amount: int) -> void:
		_deposits[kind] = int(_deposits[kind]) + amount
	)

func _raid(damage_only: bool = false, resource_type: String = "wood", raider_count: int = 1) -> void:
	var worker: Villager = _workers[0]
	worker.set_process(true)
	_track(worker)
	var wood: Node2D = _map.get_nearest_reachable_resource_node(resource_type, worker.global_position, 0)
	_expect(wood != null and worker.command_gather(wood), "raid needs accepted real " + resource_type + " job")
	if wood == null:
		return
	var stock_before: int = int(wood.get("remaining"))
	var bank_before: int = ResourceManager.get_resource(0, resource_type)
	_suppress_preemptive_for = worker if damage_only else null
	var attacker: UnitBase = await _train_paid_raider(raider_count)
	_expect(attacker != null, "raid needs a normally paid enemy Warrior")
	if attacker == null:
		return
	_hits = 0
	_worker_at_hit = {}
	var enemy_home: Vector2 = _map.tile_to_world(_map.map_generator.spawn_positions[1])
	for raider: UnitBase in _paid_raiders:
		raider.attack_landed.connect(func(_source: UnitBase, victim: UnitBase, loss: float, _counter: float) -> void:
			if victim != worker:
				return
			_hits += 1
			_worker_at_hit = {"time": GameManager.game_time, "hp_loss": loss, "hp":worker.hp, "cargo": worker.carried_amount, "type": worker.carried_resource_type, "recovering": worker.is_auto_recovering(), "job": worker.gather_target == wood, "deposits": _deposits.duplicate()}
			for withdrawing: UnitBase in _paid_raiders:
				if is_instance_valid(withdrawing):
					withdrawing.command_move(enemy_home)
		)
		raider.command_move(wood.global_position)
	var last_command: float = -1.0
	var last_work_status: String = worker.get_work_status()
	var deadline: float = GameManager.game_time + 180.0
	while is_instance_valid(attacker) and not worker.is_auto_recovering() and worker.current_state != UnitBase.State.DEAD and GameManager.game_time < deadline:
		if _map.is_entity_visible_to_player(worker, 1) and GameManager.game_time >= last_command + 0.5:
			for raider: UnitBase in _paid_raiders:
				if is_instance_valid(raider) and raider.attack_target != worker:
					raider.command_attack(worker)
			last_command = GameManager.game_time
		last_work_status = worker.get_work_status()
		await get_tree().process_frame
	_expect(worker.is_auto_recovering() and worker.hp > 0, "paid walking Warrior did not trigger live economic recovery")
	if not worker.is_auto_recovering():
		print("RAID_NO_RECOVERY ", JSON.stringify({"seed":_probe_seed,"resource":resource_type,"count":raider_count,"damage_only":damage_only,"time":GameManager.game_time,"worker_hp":worker.hp}))
		return
	if damage_only:
		_expect(_hits > 0 and _worker_at_hit.get("recovering", false), "damage-only A/B must include a natural Combat hit and recovery")
	else:
		_expect(_hits == 0 and worker.hp == worker.max_hp, "bounded visible proactive recovery must preserve the worker's initial HP")
	if _worker_at_hit.is_empty():
		_worker_at_hit = {"time":GameManager.game_time,"hp_loss":0,"hp":worker.hp,"cargo":worker.carried_amount,"type":worker.carried_resource_type,"recovering":true,"job":worker.gather_target==wood,"deposits":_deposits.duplicate()}
	_worker_at_hit["work_before"] = last_work_status
	var nearest_distance: float = INF
	for raider: UnitBase in _paid_raiders:
		if is_instance_valid(raider):
			nearest_distance = minf(nearest_distance, worker.global_position.distance_to(raider.global_position))
	_worker_at_hit["nearest_enemy"] = nearest_distance
	for raider: UnitBase in _paid_raiders:
		if is_instance_valid(raider):
			raider.command_move(enemy_home)
	var hit_time: float = float(_worker_at_hit["time"])
	await _until(func() -> bool: return not worker.is_auto_recovering() and worker.gather_target == wood and worker.current_state == UnitBase.State.GATHERING, 90.0)
	_expect(worker.hp > 0 and not worker.is_auto_recovering() and worker.gather_target == wood, "withdrawn raid did not return survivor to exact real wood job")
	var resumed_time: float = GameManager.game_time
	var deposited_at_hit: int = int((_worker_at_hit["deposits"] as Dictionary)[resource_type])
	var carried_at_hit: int = int(_worker_at_hit["cargo"])
	await _until(func() -> bool: return int(_deposits[resource_type]) > deposited_at_hit + carried_at_hit, 80.0)
	_expect(int(_deposits[resource_type]) > deposited_at_hit + carried_at_hit, "recovered worker never delivered newly harvested wood")
	var harvested: int = stock_before - int(wood.get("remaining"))
	_expect(harvested == int(_deposits[resource_type]) + worker.carried_amount, "natural raid harvest must exactly equal deposited plus owned cargo")
	_expect(ResourceManager.get_resource(0, resource_type) == bank_before + int(_deposits[resource_type]), "bank must credit only the exact natural deliveries")
	_last_raid_result = {"seed":_probe_seed,"resource":resource_type,"raider_count":raider_count,"damage_only":damage_only,"trigger":_worker_at_hit,"hits":_hits,"resumed_after_seconds":resumed_time-hit_time,"worker_hp":worker.hp,"deposits":_deposits.duplicate(),"bank":ResourceManager.get_resource(0,resource_type),"harvested":harvested,"cargo_now":worker.carried_amount,"stock_conserved":harvested==int(_deposits[resource_type])+worker.carried_amount}
	print("PAID_NATURAL_WORKER_RAID ", JSON.stringify(_last_raid_result))

func _train_paid_raider(raider_count: int = 1) -> UnitBase:
	var home: Vector2i = _map.map_generator.spawn_positions[1]
	var barracks: BuildingBase = null
	var wood_before: int = ResourceManager.get_resource(1, "wood")
	for radius: int in range(2, 10):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile: Vector2i = home + Vector2i(dx, dy)
				if not bool(_main.call("_is_ai_build_site_currently_valid", BuildingData.BuildingType.BARRACKS, tile)):
					continue
				var count: int = (_main.get("_player_buildings")[1] as Array).size()
				_main.call("_on_ai_wants_to_build", BuildingData.BuildingType.BARRACKS, tile, false)
				if (_main.get("_player_buildings")[1] as Array).size() > count:
					barracks = (_main.get("_player_buildings")[1] as Array).back() as BuildingBase
					break
			if barracks != null:
				break
		if barracks != null:
			break
	_expect(barracks != null and ResourceManager.get_resource(1, "wood") == wood_before - 150, "raid Barracks must be normally paid and staffed")
	if barracks == null:
		return null
	await _until(func() -> bool: return barracks.build_progress > 0.05, 30.0)
	var builder: Villager = null
	for unit: Node in _main.get("_player_units")[1]:
		if unit is Villager and (unit as Villager).build_target == barracks:
			builder = unit as Villager
	_expect(builder != null, "paid raid Barracks must have real builder progress")
	if builder != null:
		# Separate one-point diagnostic interruption verifies Main's paid job ledger
		# recognizes a temporarily retreating builder and does not refund/reassign it.
		builder.take_damage(1.0)
		var interruption_time: float = GameManager.game_time
		await _until(func() -> bool: return GameManager.game_time > interruption_time + 6.0, 10.0)
		var jobs: Dictionary = _main.get("_ai_construction_jobs")
		var job: Dictionary = jobs.get(barracks.get_instance_id(), {})
		_expect(not job.is_empty() and int(job.get("reassignments", -1)) == 0, "Main replaced/refunded a builder whose protected economic order was still recovering")
		_expect(builder.build_target == barracks and builder.is_auto_recovering(), "diagnostic AI builder lost its retained paid foundation order")
		print("PAID_AI_BUILDER_RETREAT ", JSON.stringify({"recovering":builder.is_auto_recovering(),"reassignments":job.get("reassignments",-1),"progress":barracks.build_progress,"elapsed":GameManager.game_time-interruption_time}))
	await _until(func() -> bool: return barracks.state == BuildingBase.State.ACTIVE, 80.0)
	var queue: ProductionQueue = barracks.get_production_queue() as ProductionQueue
	if raider_count > 1 and not ResourceManager.can_afford(1, {"food":50 * raider_count, "wood":20 * raider_count}):
		# Three Warriors plus the Barracks need210 Wood, exceeding the initial200.
		# With strategy paused, explicitly employ a free AI worker to fund the
		# remainder by ordinary visible-resource harvesting and actual delivery.
		var funding_worker: Villager = null
		for unit: Node in _main.get("_player_units")[1]:
			if not unit is Villager or (unit as Villager).has_active_build_order():
				continue
			var candidate: Villager = unit as Villager
			var funding_wood: Node2D = _map.get_nearest_reachable_resource_node("wood", candidate.global_position, 1)
			if funding_wood != null and candidate.command_gather(funding_wood):
				funding_worker = candidate
				break
		_expect(funding_worker != null, "three paid Warriors need a real visible Wood funding job")
		await _until(func() -> bool: return ResourceManager.can_afford(1, {"food":50 * raider_count, "wood":20 * raider_count}), 90.0)
	var food_before: int = ResourceManager.get_resource(1, "food")
	wood_before = ResourceManager.get_resource(1, "wood")
	for index: int in range(raider_count):
		_expect(queue.enqueue_unit(UnitData.UnitType.INFANTRY), "normal paid raid Warrior enqueue failed")
	_expect(ResourceManager.get_resource(1, "food") == food_before - 50 * raider_count and ResourceManager.get_resource(1, "wood") == wood_before - 20 * raider_count, "raid Warriors must spend normal 50food/20wood cost each")
	await _until(func() -> bool:
		var count: int = 0
		for unit: Node in _main.get("_player_units")[1]:
			if unit is UnitBase and (unit as UnitBase).unit_type == UnitData.UnitType.INFANTRY:
				count += 1
		return count >= raider_count
	, 60.0)
	for unit: Node in _main.get("_player_units")[1]:
		if unit is UnitBase and (unit as UnitBase).unit_type == UnitData.UnitType.INFANTRY:
			_paid_raiders.append(unit as UnitBase)
	_expect(_paid_raiders.size() == raider_count, "raid must wait for exactly the requested paid completed Warriors")
	return _paid_raiders[0] if not _paid_raiders.is_empty() else null

func _farm(loaded: bool) -> void:
	var target: Villager = _workers[0]
	if loaded:
		target.set_process(true)
		var wood: Node2D = _map.get_nearest_reachable_resource_node("wood", target.global_position, 0)
		_expect(wood != null and target.command_gather(wood), "loaded Farm needs real harvested wood")
		await _until(func() -> bool: return target.carried_amount >= 4, 45.0)
		target.command_stop()
		for worker: Villager in _workers:
			if worker != target:
				worker.command_move(_map.tile_to_world(_map.map_generator.spawn_positions[0] + Vector2i(7, 5)))
	var cargo_before: int = target.carried_amount
	var wood_before: int = ResourceManager.get_resource(0, "wood")
	var food_before: int = ResourceManager.get_resource(0, "food")
	var farm: BuildingBase = _place_farm()
	if farm == null:
		return
	var builder: Villager = null
	for worker: Villager in _workers:
		if worker.build_target == farm:
			builder = worker
	_expect(builder != null, "paid Farm must acquire one normal builder")
	if builder == null:
		return
	if loaded:
		_expect(builder == target and cargo_before > 0, "only free loaded builder did not receive the Farm")
	cargo_before = builder.carried_amount
	_track(builder)
	builder.set_process(true)
	await _until(func() -> bool: return farm.state == BuildingBase.State.ACTIVE, 60.0)
	_expect(farm.state == BuildingBase.State.ACTIVE, "75-wood Farm did not complete naturally")
	await _until(func() -> bool: return builder.gather_target == farm and builder.carried_resource_type == "food", 80.0)
	_expect(builder.gather_target == farm, "otherwise unassigned builder did not start its completed Farm")
	if loaded:
		_expect(int(_deposits["wood"]) == cargo_before and ResourceManager.get_resource(0, "wood") == wood_before - 75 + cargo_before, "loaded Farm retyped/lost/duplicated original wood cargo")
	await _until(func() -> bool: return int(_deposits["food"]) > 0, 80.0)
	_expect(int(_deposits["food"]) > 0 and ResourceManager.get_resource(0, "food") == food_before + int(_deposits["food"]), "new Farm did not deliver real harvested Food to TC")
	print("PAID_FARM_AUTO_WORK ", JSON.stringify({"loaded": loaded, "cost_wood": 75, "cargo_before": cargo_before, "wood_deposited": _deposits["wood"], "food_deposited": _deposits["food"], "farm_stock": farm.farm_remaining, "state": builder.current_state, "status": builder.get_work_status()}))

func _place_farm() -> BuildingBase:
	var placement: BuildingPlacement = _main.get("_building_placement")
	var anchor: Vector2i = _map.map_generator.spawn_positions[0]
	for radius: int in range(2, 10):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var point: Vector2 = _map.tile_to_world(anchor + Vector2i(dx, dy))
				if placement.revalidate_confirmation(BuildingData.BuildingType.FARM, point, 0):
					var before: int = ResourceManager.get_resource(0, "wood")
					_main.call("_on_placement_confirmed", BuildingData.BuildingType.FARM, point)
					_expect(ResourceManager.get_resource(0, "wood") == before - 75, "Farm placement was not paid")
					return (_main.get("_player_buildings")[0] as Array).back() as BuildingBase
	_expect(false, "no reachable paid Farm site")
	return null

func _until(predicate: Callable, seconds: float) -> bool:
	var deadline: float = GameManager.game_time + seconds
	var wall_deadline: int = Time.get_ticks_msec() + 30000
	while GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return bool(predicate.call())

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
