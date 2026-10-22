extends SceneTree
## Two real clients activate Strategy controls and witness server snapshots.
var session: Node
var elapsed := 0.0
var phase := 0
var allocation_index := 0
var pairs: Array = [["food", "wood"], ["wood", "gold"], ["gold", "food"], ["idle", "wood"]]
var previous_jobs: Dictionary = {}
var previous_bank := 0
var previous_deposits := 0
var completed := false
var end_sent := false
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	session = root.get_node("NetworkSession")
	session.snapshot_received.connect(_snapshot)
	session.match_ended.connect(_ended)
	session.find_match()

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 40.0 or (session != null and session.state == "error"):
		push_error("ONLINE_STRATEGY_TIMEOUT phase=%d assignment=%d failures=%s" % [phase, allocation_index, failures])
		quit(1)
	return false

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _jobs(data: Dictionary) -> Dictionary:
	var jobs: Dictionary = {}
	for actor: Dictionary in data.actors:
		if int(actor.owner) == session.player_slot and actor.kind == "unit" and int(actor.type) == UnitData.UnitType.VILLAGER:
			jobs[int(actor.id)] = "idle" if int(actor.state) == 0 and str(actor.get("work", "")).is_empty() else str(actor.get("work", ""))
	return jobs

func _bank(data: Dictionary) -> int:
	var total := 0
	for value: Variant in data.bank.values():
		total += int(value)
	return total

func _request_assignment(overview: Node, data: Dictionary) -> void:
	previous_jobs = _jobs(data)
	var pair: Array = pairs[allocation_index]
	(overview._source_buttons[pair[0]] as Button).pressed.emit()
	_check(not (overview._destination_buttons[pair[1]] as Button).disabled, "Assignment button incorrectly disabled")
	(overview._destination_buttons[pair[1]] as Button).pressed.emit()
	# No client command may mutate an inert replica ahead of authority.
	for id: int in previous_jobs:
		var worker: Node = session.adapter.entities[id]
		var source: String = "idle" if worker.current_state == 0 and worker.get_economy_task().is_empty() else worker.get_economy_task()
		_check(source == previous_jobs[id], "Assignment mutated local replica")
	phase = 1

func _snapshot(data: Dictionary) -> void:
	if session.state != "playing" or not is_instance_valid(session.adapter):
		return
	var main: Node = session.adapter.main
	var controller: Node = main.get_node("StrategyController")
	controller._refresh()
	var overview: Node = controller._overview
	var producer: Dictionary = {}
	for actor: Dictionary in data.actors:
		if actor.kind == "building" and int(actor.owner) == session.player_slot and int(actor.type) == BuildingData.BuildingType.TOWN_CENTER:
			producer = actor
	if producer.is_empty():
		return
	var building: Node = session.adapter.entities[int(producer.id)]
	var row: Dictionary = overview._producer_rows.get(building.get_instance_id(), {})
	if row.is_empty():
		return
	var queue: Node = building.get_production_queue()
	match phase:
		0:
			if "food" in _jobs(data).values():
				_request_assignment(overview, data)
		1:
			var pair: Array = pairs[allocation_index]
			var changed := false
			var jobs: Dictionary = _jobs(data)
			for id: int in previous_jobs:
				if previous_jobs[id] == pair[0] and jobs.get(id) == pair[1]:
					changed = true
			if changed:
				allocation_index += 1
				if allocation_index < 3:
					_request_assignment(overview, data)
				elif allocation_index == 3:
					main.game_map.selection_mgr.select_single(session.adapter.entities[jobs.keys()[0]])
					(main.hud._unit_stop_button as Button).pressed.emit()
					phase = 2
				else:
					previous_bank = _bank(data)
					previous_deposits = int(data.stats.resources_gathered)
					(row.train[UnitData.UnitType.VILLAGER] as Button).pressed.emit()
					_check(queue.queue.is_empty(), "Training mutated replica queue")
					phase = 3
		2:
			if "idle" in _jobs(data).values():
				_request_assignment(overview, data)
		3:
			if producer.queue.items.size() == 1:
				var paid: int = int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).food)
				_check(_bank(data) + paid == previous_bank + int(data.stats.resources_gathered) - previous_deposits, "Training payment mismatch")
				_check(int(data.player.population_reserved) == 1, "Training reservation missing")
				(row.repeat as Button).toggled.emit(true)
				_check(not queue.auto_queue_enabled, "Repeat mutated replica queue")
				phase = 4
		4:
			if bool(producer.queue.repeat):
				(row.sacred as Button).pressed.emit()
				_check(not building.rally_point_is_custom, "Rally mutated replica")
				phase = 5
		5:
			if bool(producer.custom_rally):
				var location := Vector2(float(producer.rally[0]), float(producer.rally[1]))
				_check(main.game_map.world_to_tile(location) == main.game_map.world_to_tile(main.game_map.sacred_site.global_position), "Wrong Sacred rally")
				previous_bank = _bank(data)
				previous_deposits = int(data.stats.resources_gathered)
				(row.clear as Button).pressed.emit()
				_check(queue.queue.size() == 1 and queue.auto_queue_enabled, "Clear mutated replica queue")
				phase = 6
		6:
			if producer.queue.items.is_empty() and not bool(producer.queue.repeat):
				var refund: int = int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).food)
				_check(_bank(data) == previous_bank + refund + int(data.stats.resources_gathered) - previous_deposits, "Clear refund mismatch")
				_check(int(data.player.population_reserved) == 0, "Clear retained population reservation")
				completed = true
				phase = 7
				print("ONLINE_STRATEGY_VERIFIED slot=%d allocation_sources=food,wood,gold,idle paid_train=true repeat=true sacred_rally=true clear_refund=true failures=%s" % [session.player_slot, failures])
	if completed and session.player_slot == 1 and float(data.time) > 10.0 and not end_sent:
		end_sent = true
		session.send_command("surrender")

func _ended(winner: int, reason: String) -> void:
	print("ONLINE_STRATEGY_RESULT slot=%d winner=%d completed=%s failures=%s reason=%s" % [session.player_slot, winner, completed, failures, reason])
	quit(0 if completed and failures.is_empty() and winner == 0 else 1)
