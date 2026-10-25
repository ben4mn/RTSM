extends Node
## Staged real-world continuation regression. Ordinary Main order adapters and
## worker simulation perform restoration, reacquisition, construction and deposit.
## Positions, initial cargo and near-complete foundations are fixture setup only.

var _main: Node
var _map: Node2D
var _workers: Array[Node2D] = []
var _food: ResourceNode
var _wood: ResourceNode
var _checks: int = 0
var _failures: Array[String] = []
var _context: String
const STEP: float = 1.0 / 60.0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	for civilization: int in CivilizationData.ORDERED_IDS:
		_context = "civ%d" % civilization
		GameManager.selected_civilization = civilization
		GameManager.selected_opponent_civilization = civilization
		GameManager.set_state(GameManager.GameState.MENU)
		_main = load("res://scenes/main/main.tscn").instantiate()
		add_child(_main)
		for frame: int in 900:
			if _main.get("_building_placement") != null: break
			await get_tree().process_frame
		_expect(_main.get("_building_placement") != null, "Main initialized")
		_main.set_process(false)
		_main.ai_controller.set_process(false)
		_main.ai_controller.get("_decision_timer").stop()
		_main.get_node("StrategyController").set_process(false)
		_map = _main.game_map
		_map.fog_of_war.set_process(false)
		_map.fog_of_war.reveal_all()
		_workers.clear()
		for unit: UnitBase in get_tree().get_nodes_in_group("units"):
			unit.set_process(false)
			if unit is Villager and unit.player_owner == 0 and _workers.size() < 2:
				_workers.append(unit)
		_food = _nearest_resource("food")
		_wood = _nearest_resource("wood")
		_expect(_food != null and _wood != null and _workers.size() == 2, "two workers and both resource jobs exist")
		if _food != null and _wood != null and _workers.size() == 2:
			_remembered_gather()
			_return_only_delivery()
			_build_continuation(true)
			_build_continuation(false)
		_main.free()
		await get_tree().process_frame
	for failure: String in _failures:
		push_error("[FAIL] worker_undo_continuations: " + failure)
	print("[WORKER UNDO CONTINUATIONS] checks=%d failures=%d; three civilizations; actual remembered-target reacquisition, return-only deposit and post-build work; current cargo is conserved" % [_checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _reset() -> void:
	_map.fog_of_war.reveal_all()
	for worker: Villager in _workers:
		worker.command_stop()
		worker.call("_clear_gather_target_knowledge")
		worker.call("_clear_saved_gather_order")
		worker.gather_type = Villager.GatherType.NONE
		worker.carried_amount = 0
		worker.carried_resource_type = ""
		worker.set("_cargo", {})
	_main.game_map.selection_mgr.select_many(_workers)

func _remembered_gather() -> void:
	_reset()
	var tile: Vector2i = _map.world_to_tile(_food.global_position)
	_map.fog_of_war.fog_grid[tile.y][tile.x] = MapData.FogState.EXPLORED
	for worker: Villager in _workers:
		_expect(worker.command_gather_last_observed("food", _food.global_position, _food.get_instance_id(), false), "remembered gather accepted")
		_expect(worker.has_active_gather_order() and worker.gather_target == null, "real remembered job has no live target")
	_main._on_move_command(_free_destination())
	var id: int = _undo_id("remembered gathering workers are included")
	if id > 0: _main._on_worker_order_undo(id)
	for worker: Villager in _workers:
		_expect(worker.has_active_gather_order() and worker.gather_target == null, "Undo retains fog-safe approach before reveal")
	_map.fog_of_war.reveal_all()
	for frame: int in 6: _step()
	for worker: Villager in _workers:
		_expect(worker.has_active_gather_order() and worker.gather_target == _food, "ordinary gathering process reacquires the exact revealed resource")

func _return_only_delivery() -> void:
	_reset()
	for worker: Villager in _workers:
		_set_cargo(worker, {"food": 3, "wood": 2}, "food")
		_expect(worker.command_return_resources(), "return-only command accepted")
		_expect(worker.is_returning_resources() and not worker.has_active_gather_order(), "return-only delivery is distinct from gather and Move")
	_main._on_move_command(_free_destination())
	var id: int = _undo_id("return-only workers are included")
	# Simulate cargo earned before Undo; history must not roll this current bag back.
	for worker: Villager in _workers: _set_cargo(worker, {"food": 3, "wood": 2, "gold": 1}, "gold")
	var before: Dictionary = ResourceManager.get_all_resources(0).duplicate(true)
	if id > 0: _main._on_worker_order_undo(id)
	_expect(ResourceManager.get_all_resources(0) == before, "Undo itself never deposits or changes the bank")
	for worker: Villager in _workers:
		_expect(worker.is_returning_resources(), "Undo restores actual delivery semantics")
		_expect(worker.get_carried_resources() == {"food": 3, "wood": 2, "gold": 1}, "Undo preserves the current mixed bag")
	var frames: int = 0
	while _carried_total() > 0 and frames < 1800:
		_step()
		frames += 1
	_expect(_carried_total() == 0, "restored delivery actually reaches a drop-off and empties cargo")
	var after: Dictionary = ResourceManager.get_all_resources(0)
	_expect(int(after.food) - int(before.food) == 6 and int(after.wood) - int(before.wood) == 4 and int(after.gold) - int(before.gold) == 2, "actual bank receipt equals current cargo, with no duplication or relabeling")
	print("[CONTINUATION] %s return-only simulated_seconds=%.3f cargo_left=%d" % [_context, frames * STEP, _carried_total()])

func _build_continuation(has_prior_gather: bool) -> void:
	_reset()
	var label: String = "original wood job" if has_prior_gather else "original idle with cargo"
	var tile: Vector2i = _foundation_tile()
	_expect(tile.x >= 0, label + ": valid staged foundation location")
	if tile.x < 0: return
	var foundation: BuildingBase = _main._spawn_building(BuildingData.BuildingType.HOUSE, 0, tile)
	foundation.start_construction()
	foundation.build_progress = 0.98
	for worker: Villager in _workers:
		_set_cargo(worker, {"wood": 2}, "wood")
		if has_prior_gather: _expect(worker.command_gather(_wood), label + ": original work accepted")
		worker.command_build(foundation)
		_expect(worker.has_active_build_order(), label + ": original construction accepted")
	_main._on_gather_command(_food)
	var id: int = _undo_id(label + ": accidental group Gather can be undone")
	# Approach through the real map route, then perform ordinary harvest ticks.
	for worker: Villager in _workers:
		var route: PackedVector2Array = worker.call("_get_navigation_route", _food.global_position, worker.GATHER_APPROACH_DISTANCE)
		_expect(not route.is_empty(), label + ": food work position reachable")
		if not route.is_empty(): worker.global_position = route[-1]
	for frame: int in 360:
		var all_harvested: bool = true
		for worker: Villager in _workers:
			if int(worker.get_carried_resources().get("food", 0)) == 0:
				worker._process(STEP)
				all_harvested = false
		if all_harvested: break
	var bags: Array[Dictionary] = []
	for worker: Villager in _workers:
		var bag: Dictionary = worker.get_carried_resources()
		bags.append(bag.duplicate())
		_expect(int(bag.get("food", 0)) > 0 and int(bag.get("wood", 0)) == 2, label + ": interim food is really harvested into the existing wood bag")
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate(true)
	if id > 0: _main._on_worker_order_undo(id)
	_expect(is_equal_approx(foundation.build_progress, 0.98), label + ": Undo does not rewind or advance construction")
	for index: int in _workers.size():
		var worker: Villager = _workers[index]
		_expect(worker.has_active_build_order() and worker.build_target == foundation, label + ": restores the original foundation")
		_expect(worker.get_carried_resources() == bags[index], label + ": Undo keeps currently earned mixed cargo")
		var route: PackedVector2Array = _map.get_building_work_world_path(worker.global_position, foundation.global_position, foundation.footprint, worker.BUILD_APPROACH_DISTANCE)
		_expect(not route.is_empty(), label + ": construction edge is reachable")
		if not route.is_empty(): worker.global_position = route[-1]
	for frame: int in 180:
		_step()
		# Another builder can complete between these workers' ticks. Give both
		# state machines their next tick to run the ordinary completion branch.
		if foundation.state == BuildingBase.State.ACTIVE and _workers[0].current_state != UnitBase.State.BUILDING and _workers[1].current_state != UnitBase.State.BUILDING: break
	_expect(foundation.state == BuildingBase.State.ACTIVE, label + ": worker construction actually completes")
	for index: int in _workers.size():
		var worker: Villager = _workers[index]
		if has_prior_gather:
			_expect(worker.has_active_gather_order() and worker.gather_target == _wood, label + ": completion resumes original wood, not accidental food")
		_expect(worker.get_carried_resources() == bags[index], label + ": completion preserves each cargo type")
	_expect(ResourceManager.get_all_resources(0) == bank, label + ": restoration and completion do not change bank")
	for worker: Villager in _workers: worker.command_stop()
	foundation.free()

func _undo_id(message: String) -> int:
	var status: Dictionary = _main._worker_order_undo.status(0)
	_expect(int(status.get("count", 0)) == 2, message)
	return int(status.get("id", 0))

func _step() -> void:
	for worker: Villager in _workers: worker._process(STEP)

func _carried_total() -> int:
	var total: int = 0
	for worker: Villager in _workers: total += worker.carried_amount
	return total

func _set_cargo(worker: Villager, bag: Dictionary, current_type: String) -> void:
	worker.set("_cargo", bag.duplicate())
	worker.carried_amount = 0
	for amount: int in bag.values(): worker.carried_amount += amount
	worker.carried_resource_type = current_type

func _nearest_resource(kind: String) -> ResourceNode:
	var nearest: ResourceNode
	var distance: float = INF
	for resource: ResourceNode in _map.resource_nodes.values():
		if resource.resource_type == kind and resource.global_position.distance_to(_workers[0].global_position) < distance:
			nearest = resource
			distance = resource.global_position.distance_to(_workers[0].global_position)
	return nearest

func _free_destination() -> Vector2i:
	var origin: Vector2i = _map.world_to_tile(_workers[0].global_position)
	for radius: int in range(2, 8):
		for offset: Vector2i in [Vector2i(radius, 0), Vector2i(0, radius), Vector2i(-radius, 0), Vector2i(0, -radius)]:
			if _map.is_tile_walkable(origin + offset): return origin + offset
	return origin

func _foundation_tile() -> Vector2i:
	var tc: BuildingBase = _main.get("_player_buildings")[0][0]
	var origin: Vector2i = _map.world_to_tile(tc.global_position)
	for radius: int in range(6, 13):
		for y: int in range(-radius, radius + 1):
			var tile: Vector2i = origin + Vector2i(radius, y)
			if _main._building_placement.revalidate_confirmation(BuildingData.BuildingType.HOUSE, _map.tile_to_world(tile), 0): return tile
	return Vector2i(-1, -1)

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition: _failures.append(_context + " " + message)
