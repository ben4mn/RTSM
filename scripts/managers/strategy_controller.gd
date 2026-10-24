extends Node
## Bridges the selection-independent overview to existing paid, fog-legal orders.

const ECONOMY_ASSESSMENT = preload("res://scripts/managers/economy_assessment.gd")

var _main: Node
var _hud: CanvasLayer
var _map: Node2D
var _overview: StrategyOverview
var _elapsed: float = 0.0
var _food_gap_started: float = -1.0
const FOOD_ALERT_STARTUP_GRACE := 12.0
const FOOD_ALERT_GAP_GRACE := 6.0


func setup(main: Node, hud: CanvasLayer, map: Node2D) -> void:
	_main = main
	_hud = hud
	_map = map
	_overview = hud.call("setup_strategy_overview") as StrategyOverview
	_overview.allocation_requested.connect(_allocate_worker)
	_overview.repeat_requested.connect(_set_repeat)
	_overview.rally_requested.connect(_rally_to_army)
	_overview.sacred_rally_requested.connect(_rally_to_sacred)
	_overview.farm_requested.connect(_plan_farm)
	_overview.barracks_requested.connect(_plan_barracks)
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


func _own_workers(owner: int = 0) -> Array[Villager]:
	var workers: Array[Villager] = []
	for entry: Variant in (_main.get("_player_units") as Array)[owner]:
		if is_instance_valid(entry) and entry is Villager and entry.player_owner == owner and entry.current_state != UnitBase.State.DEAD:
			workers.append(entry as Villager)
	return workers


func _worker_source(worker: Villager) -> String:
	if bool(worker.get_meta("network_recovering", worker.is_auto_recovering())):
		return "recovering"
	if bool(worker.get_meta("network_building", worker.has_active_build_order())):
		return "build"
	var task: String = worker.get_economy_task()
	if task in ["food", "wood", "gold"]:
		return task
	return "idle" if worker.current_state == UnitBase.State.IDLE else "moving"


func _can_plan_with_worker(worker: Villager) -> bool:
	# Match the states Main can automatically assign when placement is paid.
	# An explicitly fighting villager must not be presented as a free builder.
	return _worker_source(worker) not in ["recovering", "build"] and worker.current_state in [UnitBase.State.IDLE, UnitBase.State.GATHERING, UnitBase.State.MOVING]


func _refresh() -> void:
	if not is_instance_valid(_main) or not is_instance_valid(_overview):
		return
	var workers: Dictionary = {"food": 0, "wood": 0, "gold": 0, "idle": 0, "recovering": 0, "build": 0, "moving": 0}
	var own_workers: Array[Villager] = _own_workers()
	var available_builders: int = 0
	for worker: Villager in own_workers:
		var source: String = _worker_source(worker)
		workers[source] = int(workers.get(source, 0)) + 1
		if _can_plan_with_worker(worker):
			available_builders += 1
	var military: int = 0
	var fighters: int = 0
	for entry: Variant in (_main.get("_player_units") as Array)[0]:
		if is_instance_valid(entry) and entry is UnitBase and not entry is Villager and entry.player_owner == 0 and entry.current_state != UnitBase.State.DEAD:
			military += 1
			if entry.damage > 0.0:
				fighters += 1
	var producers: Array[Dictionary] = []
	var idle_producers: int = 0
	var queued_workers: int = 0
	var refund_food: int = 0
	var active_worker_producer: bool = false
	for entry: Variant in (_main.get("_player_buildings") as Array)[0]:
		if not is_instance_valid(entry) or not entry is BuildingBase or entry.player_owner != 0 or entry.state == BuildingBase.State.DESTROYED:
			continue
		var building := entry as BuildingBase
		var queue := building.get_production_queue() as ProductionQueue
		if queue == null or building.trainable_units.is_empty():
			continue
		var paid: Array[String] = []
		for unit_type: int in queue.queue:
			paid.append(UnitData.get_unit_name(unit_type, 0))
			refund_food += int(UnitData.get_unit_cost(unit_type).get("food", 0))
			if unit_type == UnitData.UnitType.VILLAGER and building.state == BuildingBase.State.ACTIVE:
				queued_workers += 1
		if UnitData.UnitType.VILLAGER in building.trainable_units and building.state == BuildingBase.State.ACTIVE:
			active_worker_producer = true
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
			status += " · %s %d%%" % [UnitData.get_unit_name(queue.queue[0], 0), roundi(queue.get_current_progress() * 100.0)]
		var unit_status: Dictionary = {}
		var military_producer: bool = false
		for unit_type: int in building.trainable_units:
			unit_status[unit_type] = _training_blocker(building, unit_type)
			if unit_type != UnitData.UnitType.VILLAGER and float(UnitData.get_unit_stats(unit_type, 0).get("damage", 0.0)) > 0.0:
				military_producer = true
		producers.append({"building": building, "military": military_producer, "status": status, "active": building.state == BuildingBase.State.ACTIVE, "queue": paid, "trainable": building.trainable_units.duplicate(), "repeat_type": queue.auto_queue_unit_type, "repeat_enabled": queue.auto_queue_enabled, "unit_status": unit_status, "rally_status": _rally_status(building), "sacred_available": is_instance_valid(_map.get("sacred_site"))})
	var data: Dictionary = GameManager.players.get(0, {})
	var committed: int = GameManager.get_committed_population(0)
	var cap: int = int(data.get("population_cap", 5))
	var pop: int = int(data.get("population", 0))
	var population_text: String = "Population %d/%d + %d paid slots · %d idle producers" % [pop, cap, maxi(0, committed - pop), idle_producers]
	if committed >= cap:
		var can_add_housing: bool = cap < GameManager.get_player_population_limit(0) and pop < GameManager.get_player_population_limit(0) and not own_workers.is_empty()
		if pop < cap:
			population_text += "\nPopulation blocked — refund paid slots" + (" or build a House." if can_add_housing else ".")
		elif can_add_housing:
			population_text += "\nLiving units fill available housing — build a House. Refunds alone cannot open a slot."
		else:
			population_text += "\nLiving units fill available population; a slot must open before training."
	var groups: Dictionary = {}
	var group_has_buildings: Dictionary = {}
	for index: int in [1, 2]:
		groups[index] = 0
		group_has_buildings[index] = false
		for entry: Variant in (_main.get("_control_groups") as Array)[index]:
			if _valid_group_entry(entry):
				groups[index] += 1
				if entry is BuildingBase:
					group_has_buildings[index] = true
	var selection_count: int = 0
	var selected_military: int = 0
	for entry: Variant in _map.selection_mgr.selected:
		if _valid_group_entry(entry):
			selection_count += 1
			if entry is UnitBase and not entry is Villager:
				selected_military += 1
	var economy_facts: Dictionary = _observed_food_stock(own_workers)
	economy_facts.merge({"workers": own_workers.size(), "recovering": int(workers.recovering), "food_workers": int(workers.food), "queued_workers": queued_workers, "refund_food": refund_food, "active_worker_producer": active_worker_producer, "food": ResourceManager.get_resource(0, "food"), "free_population": maxi(0, cap - committed), "reserved_population": maxi(0, committed - pop), "population_room_after_refunds": maxi(0, cap - pop)}, true)
	var farm_missing: Dictionary = ResourceManager.get_missing_resources(0, BuildingData.get_building_cost(BuildingData.BuildingType.FARM))
	var farm_blocker: String = "Needs a free worker; builders and recovering workers keep their orders." if available_builders == 0 else ("Need %d more wood to build a Farm." % int(farm_missing.get("wood", 0)) if not farm_missing.is_empty() else "Builder starts farming when finished. One worker per Farm.")
	var barracks_missing: Dictionary = ResourceManager.get_missing_resources(0, BuildingData.get_building_cost(BuildingData.BuildingType.BARRACKS))
	var barracks_blocker: String = "Needs a free worker. Builders and recovering workers keep their orders." if available_builders == 0 else ("Need %d more wood to build a Barracks." % int(barracks_missing.get("wood", 0)) if not barracks_missing.is_empty() else "Choose a location, then confirm to pay. Train Warriors when construction finishes.")
	_overview.update_snapshot({"workers": workers, "military": military, "fighters": fighters, "producers": producers, "population_text": population_text, "groups": groups, "group_has_buildings": group_has_buildings, "selection_count": selection_count, "selected_military": selected_military, "economy": ECONOMY_ASSESSMENT.describe(economy_facts), "economy_facts": economy_facts, "food_attention_ready": _update_food_attention(own_workers.size(), int(workers.food), int(workers.recovering)), "can_plan_farm": available_builders > 0 and farm_missing.is_empty(), "farm_blocker": farm_blocker, "can_plan_barracks": available_builders > 0 and barracks_missing.is_empty(), "barracks_blocker": barracks_blocker})


func _update_food_attention(workers: int, food_workers: int, recovering: int) -> bool:
	# Gameplay time excludes pause/loading. Brief travel, startup auto-allocation,
	# and sheltering workers must not flash an urgent income warning.
	if not _playing() or workers <= 0 or food_workers > 0 or recovering > 0:
		_food_gap_started = -1.0
		return false
	if _food_gap_started < 0.0 or GameManager.game_time < _food_gap_started:
		_food_gap_started = GameManager.game_time
	return GameManager.game_time >= FOOD_ALERT_STARTUP_GRACE and GameManager.game_time - _food_gap_started >= FOOD_ALERT_GAP_GRACE


func _observed_food_stock(workers: Array[Villager]) -> Dictionary:
	# Check visibility before inspecting a neutral node's stock or type. Own
	# fields are known through the ownership registry; enemy fields are excluded.
	var berries: int = 0
	var farms: int = 0
	var permanent_worked: bool = false
	var known: Dictionary = {}
	for entry: Variant in (_map.get("resource_nodes") as Dictionary).values():
		if not is_instance_valid(entry) or not entry is ResourceNode:
			continue
		var node := entry as ResourceNode
		if not _map.is_resource_target_visible_to_player(node, 0):
			continue
		if not _map.is_resource_target_valid(node, "food", 0):
			continue
		berries += node.remaining
		known[node.get_instance_id()] = node.remaining
	for entry: Variant in (_main.get("_player_buildings") as Array)[0]:
		if not is_instance_valid(entry) or not entry is BuildingBase:
			continue
		var building := entry as BuildingBase
		if building.player_owner == 0 and building.provides_food and building.is_harvestable_by(0):
			farms += 1
			known[building.get_instance_id()] = -1
	var worked_ids: Dictionary = {}
	var worked: int = 0
	for worker: Villager in workers:
		if _worker_source(worker) != "food" or not is_instance_valid(worker.gather_target):
			continue
		var id: int = worker.gather_target.get_instance_id()
		if known.has(id) and not worked_ids.has(id):
			if int(known[id]) < 0:
				permanent_worked = true
			else:
				worked += int(known[id])
			worked_ids[id] = true
	return {"berry_food": berries, "permanent_farms": farms, "visible_food": berries + farms, "worked_food": worked, "permanent_food_worked": permanent_worked}


func _rally_status(building: BuildingBase) -> String:
	if not building.has_custom_rally_point():
		return "Rally: beside this building."
	var tile: Vector2i = _map.world_to_tile(building.rally_point)
	var destination: String = "a fixed map location"
	var site: Node2D = _map.get("sacred_site") as Node2D
	if is_instance_valid(site) and tile == _map.world_to_tile(site.global_position):
		destination = "Sacred Site"
	if building.rally_resource_instance_id > 0:
		destination = "gather %s at %s" % [building.rally_resource_type, destination]
	return "Rally: %s · fixed until changed.%s" % [destination, " Includes new Villagers." if UnitData.UnitType.VILLAGER in building.trainable_units else ""]


func _valid_group_entry(entry: Variant) -> bool:
	if not is_instance_valid(entry) or not entry is Node2D:
		return false
	if entry is UnitBase:
		return entry.player_owner == 0 and entry.current_state != UnitBase.State.DEAD
	if entry is BuildingBase:
		return entry.player_owner == 0 and entry.state != BuildingBase.State.DESTROYED
	return false


func _training_blocker(building: BuildingBase, unit_type: int) -> String:
	if building.state != BuildingBase.State.ACTIVE:
		return "under construction"
	if unit_type < 0 or unit_type not in building.trainable_units:
		return "train a unit first"
	var queue := building.get_production_queue() as ProductionQueue
	if queue != null and queue.get_queue_size() >= ProductionQueue.MAX_QUEUE_SIZE:
		return "queue full (%d/%d) — wait or undo" % [queue.get_queue_size(), ProductionQueue.MAX_QUEUE_SIZE]
	var pop_cost: int = int(UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1))
	var cap: int = int(GameManager.players.get(0, {}).get("population_cap", 5))
	if GameManager.get_committed_population(0) + pop_cost > cap:
		var population: int = int(GameManager.players.get(0, {}).get("population", 0))
		if population + pop_cost <= cap:
			return "population blocked — refund paid slots"
		if cap < GameManager.get_player_population_limit(0) and population + pop_cost <= GameManager.get_player_population_limit(0) and not _own_workers().is_empty():
			return "population blocked — build a House; refunds alone cannot help"
		return "population blocked — living units must free a slot"
	var missing: Dictionary = ResourceManager.get_missing_resources(0, UnitData.get_unit_cost(unit_type))
	var parts: PackedStringArray = []
	for resource: String in ["food", "wood", "gold"]:
		if int(missing.get(resource, 0)) > 0:
			parts.append("%d %s" % [int(missing[resource]), resource])
	return "need " + ", ".join(parts) if not parts.is_empty() else "ready"


func _plan_farm() -> void:
	_plan_building(BuildingData.BuildingType.FARM)


func _plan_barracks() -> void:
	_plan_building(BuildingData.BuildingType.BARRACKS)


func _plan_building(building_type: int) -> void:
	if not _playing():
		return
	var available: bool = false
	for worker: Villager in _own_workers():
		if _can_plan_with_worker(worker):
			available = true
			break
	if not available or not ResourceManager.can_afford(0, BuildingData.get_building_cost(building_type)):
		_overview.show_feedback("A %s needs %d wood and a free worker. Builders and recovering workers keep their orders." % [BuildingData.get_building_name(building_type), int(BuildingData.get_building_cost(building_type).get("wood", 0))], false)
		_refresh()
		return
	# Enter the same placement flow as the Build palette. Planning spends
	# nothing: Main's confirmation still validates terrain, workers and payment.
	_hud.call("close_secondary_surface")
	var menu: Node = _main.get("_build_menu") as Node
	if is_instance_valid(menu):
		menu.emit_signal("building_selected", building_type)


func _allocate_worker(source: String, destination: String) -> void:
	if not _playing() or source not in StrategyOverview.SOURCES or destination not in StrategyOverview.RESOURCES or source == destination:
		return
	if NetworkSession.is_client():
		var sent: bool = NetworkSession.send_command("allocate", {"source": source, "destination": destination})
		_overview.show_feedback("Requested one worker: %s to %s." % [source, destination] if sent else "Connection unavailable. Try again.", sent)
		return
	var result: Dictionary = try_allocate_worker(0, source, destination)
	if result.has("worker"):
		var worker: Villager = result.worker
		_overview.show_feedback("Moved one worker from %s to %s.%s" % [source, destination, " Cargo kept." if worker.carried_amount > 0 and worker.carried_resource_type != destination else ""])
		var diagnostics: Node = get_node_or_null("/root/PlaytestDiagnostics")
		if diagnostics:
			diagnostics.call("record_event", "economy_reallocation", {"source": source, "destination": destination, "worker": str(worker.get_path()), "cargo": worker.carried_amount})
		_refresh()
	else:
		_overview.show_feedback(str(result.error), false)


func try_allocate_worker(owner: int, source: String, destination: String) -> Dictionary:
	# Resolve the job and eligible worker on the simulation authority. Replica
	# snapshots can be stale and must never steal a builder or recovering worker.
	if not _playing() or owner not in [0, 1] or source not in StrategyOverview.SOURCES or destination not in StrategyOverview.RESOURCES or source == destination:
		return {"error": "Invalid worker assignment"}
	var candidates: Array[Villager] = []
	for worker: Villager in _own_workers(owner):
		if _worker_source(worker) == source:
			candidates.append(worker)
	# Stable least-cargo choice minimizes interruption without stealing builders
	# or recovering workers. Destination discovery is visible and path-aware.
	candidates.sort_custom(func(a: Villager, b: Villager) -> bool:
		return a.get_instance_id() < b.get_instance_id() if a.carried_amount == b.carried_amount else a.carried_amount < b.carried_amount)
	for worker: Villager in candidates:
		var target: Node2D = _map.get_nearest_reachable_resource_node(destination, worker.global_position, owner, {}, worker)
		if target != null and worker.command_gather(target):
			return {"worker": worker}
	return {"error": "No %s worker is available." % source if candidates.is_empty() else "No visible, reachable %s work is available. Scout a deposit%s." % [destination, " or build another Farm" if destination == "food" else ""]}


func _owned_producer(building: Node2D) -> ProductionQueue:
	if not _playing() or not is_instance_valid(building) or not building is BuildingBase or building.player_owner != 0 or building.state != BuildingBase.State.ACTIVE:
		return null
	return building.get_production_queue() as ProductionQueue


func _train(building: Node2D, unit_type: int) -> void:
	if _owned_producer(building) == null:
		return
	_hud.emit_signal("train_unit_requested", building, unit_type)
	if NetworkSession.is_client():
		_overview.show_feedback(str(_main.get("_last_train_feedback")), str(_main.get("_last_train_request_result")) == "requested")
		return
	var queued: bool = str(_main.get("_last_train_request_result")) == "queued"
	_overview.show_feedback("Paid training: " + UnitData.get_unit_name(unit_type, 0) if queued else str(_main.get("_last_train_feedback")), queued)
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
	if NetworkSession.is_client():
		var sent: bool = NetworkSession.send_command("repeat", {"target": NetworkSession.entity_id(building), "enabled": enabled})
		_overview.show_feedback("Repeat %s requested." % ("ON" if enabled else "OFF") if sent else "Connection unavailable. Try again.", sent)
		_refresh()
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
	_refresh()


func _rally_to_sacred(building: Node2D) -> void:
	if _owned_producer(building) == null:
		return
	var site: Node2D = _map.get("sacred_site") as Node2D
	if not is_instance_valid(site):
		return
	# Sacred's public location is known even through fog. The canonical setter
	# handles bounds and visible blockers without inspecting hidden terrain.
	var accepted: bool = bool(_main.call("_set_production_rally", building, _map.world_to_tile(site.global_position)))
	_overview.show_feedback("Future recruits rally to Sacred. Existing units keep their orders; the destination stays fixed." if accepted else "Sacred rally is blocked. Choose another rally point on the map.", accepted)
	_refresh()
