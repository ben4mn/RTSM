extends Node
## Bridges the selection-independent overview to existing paid, fog-legal orders.

var _main: Node
var _hud: CanvasLayer
var _map: Node2D
var _overview: StrategyOverview
var _elapsed: float = 0.0


func setup(main: Node, hud: CanvasLayer, map: Node2D) -> void:
	_main = main
	_hud = hud
	_map = map
	_overview = hud.call("setup_strategy_overview") as StrategyOverview
	_overview.allocation_requested.connect(_allocate_worker)
	_overview.repeat_requested.connect(_set_repeat)
	_overview.rally_requested.connect(_rally_to_army)
	_overview.save_group_requested.connect(_save_group)
	_overview.recall_group_requested.connect(_recall_group)
	_overview.training_requested.connect(_train)
	_overview.cancellation_requested.connect(_cancel)
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.35:
		_elapsed = 0.0
		_refresh()


func _playing() -> bool:
	return is_instance_valid(_main) and GameManager.current_state == GameManager.GameState.PLAYING


func _own_workers() -> Array[Villager]:
	var workers: Array[Villager] = []
	for entry: Variant in (_main.get("_player_units") as Array)[0]:
		if is_instance_valid(entry) and entry is Villager and entry.player_owner == 0 and entry.current_state != UnitBase.State.DEAD:
			workers.append(entry as Villager)
	return workers


func _worker_source(worker: Villager) -> String:
	if worker.is_auto_recovering():
		return "recovering"
	if worker.has_active_build_order():
		return "build"
	var task: String = worker.get_economy_task()
	if task in ["food", "wood", "gold"]:
		return task
	return "idle" if worker.current_state == UnitBase.State.IDLE else "moving"


func _refresh() -> void:
	if not is_instance_valid(_main) or not is_instance_valid(_overview):
		return
	var workers: Dictionary = {"food": 0, "wood": 0, "gold": 0, "idle": 0, "recovering": 0, "build": 0, "moving": 0}
	for worker: Villager in _own_workers():
		var source: String = _worker_source(worker)
		workers[source] = int(workers.get(source, 0)) + 1
	var military: int = 0
	for entry: Variant in (_main.get("_player_units") as Array)[0]:
		if is_instance_valid(entry) and entry is UnitBase and not entry is Villager and entry.player_owner == 0 and entry.current_state != UnitBase.State.DEAD:
			military += 1
	var producers: Array[Dictionary] = []
	var idle_producers: int = 0
	for entry: Variant in (_main.get("_player_buildings") as Array)[0]:
		if not is_instance_valid(entry) or not entry is BuildingBase or entry.player_owner != 0 or entry.state == BuildingBase.State.DESTROYED:
			continue
		var building := entry as BuildingBase
		var queue := building.get_production_queue() as ProductionQueue
		if queue == null or building.trainable_units.is_empty():
			continue
		var paid: Array[String] = []
		for unit_type: int in queue.queue:
			paid.append(UnitData.get_unit_name(unit_type))
		var status: String = building.building_name
		if building.state != BuildingBase.State.ACTIVE:
			status += " · under construction"
		elif queue.queue.is_empty():
			if queue.auto_queue_enabled:
				status += " · repeat waiting: " + _training_blocker(building, queue.auto_queue_unit_type)
			else:
				status += " · IDLE"
				idle_producers += 1
		else:
			status += " · %s %d%%" % [UnitData.get_unit_name(queue.queue[0]), roundi(queue.get_current_progress() * 100.0)]
		var unit_status: Dictionary = {}
		for unit_type: int in building.trainable_units:
			unit_status[unit_type] = _training_blocker(building, unit_type)
		producers.append({"building": building, "status": status, "active": building.state == BuildingBase.State.ACTIVE, "queue": paid, "trainable": building.trainable_units.duplicate(), "repeat_type": queue.auto_queue_unit_type, "repeat_enabled": queue.auto_queue_enabled, "unit_status": unit_status})
	var data: Dictionary = GameManager.players.get(0, {})
	var committed: int = GameManager.get_committed_population(0)
	var cap: int = int(data.get("population_cap", 5))
	var pop: int = int(data.get("population", 0))
	var population_text: String = "Population %d/%d + %d paid slots · %d idle producers" % [pop, cap, maxi(0, committed - pop), idle_producers]
	if committed >= cap:
		population_text += "\nPopulation blocked — build a House." if cap < GameManager.get_player_population_limit(0) else "\nMatch population limit reached."
	var groups: Dictionary = {}
	for index: int in [1, 2]:
		groups[index] = 0
		for entry: Variant in (_main.get("_control_groups") as Array)[index]:
			if _valid_group_entry(entry):
				groups[index] += 1
	var selection_count: int = 0
	var selected_military: int = 0
	for entry: Variant in _map.selection_mgr.selected:
		if _valid_group_entry(entry):
			selection_count += 1
			if entry is UnitBase and not entry is Villager:
				selected_military += 1
	_overview.update_snapshot({"workers": workers, "military": military, "producers": producers, "population_text": population_text, "groups": groups, "selection_count": selection_count, "selected_military": selected_military})


func _valid_group_entry(entry: Variant) -> bool:
	if not is_instance_valid(entry) or not entry is Node2D:
		return false
	if entry is UnitBase:
		return entry.player_owner == 0 and entry.current_state != UnitBase.State.DEAD
	if entry is BuildingBase:
		return entry.player_owner == 0 and entry.state != BuildingBase.State.DESTROYED
	return false


func _training_blocker(building: BuildingBase, unit_type: int) -> String:
	if unit_type < 0 or unit_type not in building.trainable_units:
		return "train a unit first"
	var pop_cost: int = int(UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1))
	var cap: int = int(GameManager.players.get(0, {}).get("population_cap", 5))
	if GameManager.get_committed_population(0) + pop_cost > cap:
		return "population full"
	var missing: Dictionary = ResourceManager.get_missing_resources(0, UnitData.get_unit_cost(unit_type))
	var parts: PackedStringArray = []
	for resource: String in ["food", "wood", "gold"]:
		if int(missing.get(resource, 0)) > 0:
			parts.append("%d %s" % [int(missing[resource]), resource])
	return "need " + ", ".join(parts) if not parts.is_empty() else "ready"


func _allocate_worker(source: String, destination: String) -> void:
	if not _playing() or source not in StrategyOverview.SOURCES or destination not in StrategyOverview.RESOURCES or source == destination:
		return
	var candidates: Array[Villager] = []
	for worker: Villager in _own_workers():
		if _worker_source(worker) == source:
			candidates.append(worker)
	# Stable least-cargo choice minimizes interruption without stealing builders
	# or recovering workers. Destination discovery is visible and path-aware.
	candidates.sort_custom(func(a: Villager, b: Villager) -> bool:
		return a.get_instance_id() < b.get_instance_id() if a.carried_amount == b.carried_amount else a.carried_amount < b.carried_amount)
	for worker: Villager in candidates:
		var target: Node2D = _map.get_nearest_reachable_resource_node(destination, worker.global_position, 0)
		if target != null and worker.command_gather(target):
			_overview.show_feedback("Moved one worker from %s to %s.%s" % [source, destination, " Current cargo will be delivered first." if worker.carried_amount > 0 and worker.carried_resource_type != destination else ""])
			var diagnostics: Node = get_node_or_null("/root/PlaytestDiagnostics")
			if diagnostics:
				diagnostics.call("record_event", "economy_reallocation", {"source": source, "destination": destination, "worker": str(worker.get_path()), "cargo": worker.carried_amount})
			_refresh()
			return
	_overview.show_feedback("No %s worker is available." % source if candidates.is_empty() else "No visible reachable %s. Scout a deposit%s." % [destination, " or build a Farm" if destination == "food" else ""], false)


func _owned_producer(building: Node2D) -> ProductionQueue:
	if not _playing() or not is_instance_valid(building) or not building is BuildingBase or building.player_owner != 0 or building.state != BuildingBase.State.ACTIVE:
		return null
	return building.get_production_queue() as ProductionQueue


func _train(building: Node2D, unit_type: int) -> void:
	if _owned_producer(building) == null:
		return
	_hud.emit_signal("train_unit_requested", building, unit_type)
	var queued: bool = str(_main.get("_last_train_request_result")) == "queued"
	_overview.show_feedback("Paid training: " + UnitData.get_unit_name(unit_type) if queued else str(_main.get("_last_train_feedback")), queued)
	_refresh()


func _cancel(building: Node2D, index: int) -> void:
	var queue: ProductionQueue = _owned_producer(building)
	if queue == null:
		return
	# Resolve Undo against the current queue, not a stale rendered snapshot.
	var current_index: int = ProductionQueue.CANCEL_ALL_INDEX if index == ProductionQueue.CANCEL_ALL_INDEX else queue.queue.size() - 1
	if current_index == ProductionQueue.CANCEL_ALL_INDEX and index != ProductionQueue.CANCEL_ALL_INDEX:
		return
	_hud.emit_signal("cancel_queue_requested", building, current_index)
	_refresh()


func _set_repeat(building: Node2D, enabled: bool) -> void:
	var queue: ProductionQueue = _owned_producer(building)
	if queue == null or queue.auto_queue_unit_type < 0:
		return
	queue.auto_queue_enabled = enabled
	_refresh()


func _save_group(index: int) -> void:
	if _playing() and index in [1, 2]:
		_main.call("_save_control_group", index)
		_refresh()


func _recall_group(index: int) -> void:
	if _playing() and index in [1, 2]:
		_main.call("_recall_control_group", index)
		_hud.call("close_secondary_surface")
		_refresh()


func _rally_to_army(building: Node2D) -> void:
	if _owned_producer(building) == null:
		return
	var center := Vector2.ZERO
	var count: int = 0
	for entry: Variant in _map.selection_mgr.selected:
		if _valid_group_entry(entry) and entry is UnitBase and not entry is Villager:
			center += entry.global_position
			count += 1
	if count <= 0:
		return
	var target: Vector2i = _map.world_to_tile(center / float(count))
	var accepted: bool = bool(_main.call("_set_production_rally", building, target))
	_overview.show_feedback("Future recruits will join this army location. Rally stays here until changed." if accepted else "Army center is blocked. Move the group onto clear ground and try again.", accepted)
