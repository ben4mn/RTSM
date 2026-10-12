extends Node
## Controlled visibility/route fixture. Banks and route failures are explicit
## setup, not ordinary-match income or balance evidence.

var _failures: Array[String] = []
var _report: Dictionary = {}
var _output: String = "res://output/evolution/resource-search-20261010/focused.json"
var _observe_only: bool = false


class SearchMap extends Node2D:
	var resources: Array[ResourceNode] = []
	var visible_enemies: Array[Node2D] = []
	var resource_visible: bool = true
	var fail_routes: bool = false
	var visibility_guard_returns: int = 0

	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2(float(tile.x - tile.y) * 32.0, float(tile.x + tile.y) * 16.0)

	func world_to_tile(position: Vector2) -> Vector2i:
		return Vector2i(roundi((position.x / 32.0 + position.y / 16.0) * 0.5), roundi((position.y / 16.0 - position.x / 32.0) * 0.5))

	func is_tile_visible_to_player(tile: Vector2i, _owner: int = 0) -> bool:
		if not resource_visible:
			return false
		for resource: ResourceNode in resources:
			if tile == resource.tile_position:
				return true
		return false

	func is_entity_visible_to_player(entity: Node2D, owner: int = 0) -> bool:
		return entity.get("player_owner") == owner or entity in visible_enemies or (resource_visible and entity in resources)

	func get_navigation_world_path(from: Vector2, target: Vector2, _radius: float = 4.0, _goal_radius: int = 6) -> PackedVector2Array:
		return PackedVector2Array() if fail_routes else PackedVector2Array([from, target])

	func get_nearest_reachable_resource_node(kind: String, from: Vector2, owner: int = -1, excluded: Dictionary = {}) -> Node2D:
		# Visibility precedes every resource property/validity read.
		if not resource_visible:
			visibility_guard_returns += 1
			return null
		var best: ResourceNode = null
		for resource: ResourceNode in resources:
			if excluded.has(resource.get_instance_id()) or resource.resource_type != kind or not resource.is_harvestable_by(owner):
				continue
			if best == null or from.distance_squared_to(resource.global_position) < from.distance_squared_to(best.global_position):
				best = resource
		return best


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--observe-only":
			_observe_only = true
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	AudioManager.set_all_enabled(false)
	GameManager.selected_population_limit = 20
	GameManager.initialize_game(2)
	GameManager.players[1]["age"] = 2
	ResourceManager.initialize_player(1, {"food": 500, "wood": 0, "gold": 500})
	var map := SearchMap.new()
	add_child(map)
	var base_tile := Vector2i(33, 6)
	var ai := AIController.new()
	ai.player_id = 1
	ai.game_map = map
	add_child(ai)
	ai.start_ai(base_tile, map.tile_to_world(base_tile))
	(ai.get("_decision_timer") as Timer).stop()
	ai.set_process(false)
	ai.set("_archery_range_count", 1)
	ai.set("_stable_count", 1)
	var food := _resource(map, "food", base_tile + Vector2i(3, 0))
	var gold := _resource(map, "gold", base_tile + Vector2i(4, 0))
	var workers: Array[Villager] = []
	for index: int in range(5):
		var worker := preload("res://scenes/units/villager.tscn").instantiate() as Villager
		worker.player_owner = 1
		worker.position = map.tile_to_world(base_tile) + Vector2(float(index) * 10.0, 0.0)
		map.add_child(worker)
		worker.set_process(false)
		ai.register_unit(worker)
		workers.append(worker)
		if index < 3:
			worker.command_gather(food)
	var bank_before: Dictionary = ResourceManager.get_all_resources(1)
	# Food workers retain their earlier legal jobs; only surplus Gold is exposed
	# through the current-visible query in this controlled snapshot.
	map.resources.erase(food)
	var targets: Dictionary = ai.call("_get_economy_worker_targets", 5, bank_before)
	ai.call("_assign_idle_villagers")
	var search_count: int = 0
	var gold_count: int = 0
	for index: int in [3, 4]:
		if workers[index].current_state == UnitBase.State.MOVING:
			search_count += 1
		if workers[index].gather_target == gold:
			gold_count += 1
	_report["wood_deficit_surplus_gold"] = {"targets": targets, "before_labor": {"food": 3, "wood": 0, "gold": 0}, "searching_workers": search_count, "gold_assigned_workers": gold_count, "snapshot": ai.get_strategy_snapshot()}
	_expect(search_count == 1, "one empty worker searches for missing Wood while another remains productive")
	_expect(gold_count == 1, "one active deficit search leaves the second worker on safe visible fallback")
	_expect(ResourceManager.get_all_resources(1) == bank_before, "search policy never grants or spends resources")
	var search_reference: WeakRef = ai.get("_economy_wood_search_worker") as WeakRef
	workers[3].command_stop()
	for _sample: int in range(5):
		ai.get_strategy_snapshot()
	_expect(ai.get("_economy_wood_search_worker") == search_reference, "strategy snapshots do not mutate inactive search ownership")
	# No lead remains after a completed sweep. The policy boundary must clear the
	# inactive reference before its normal go-home fallback creates another Move.
	var search_waypoints: Array[Vector2] = (ai.get("_economy_exploration_waypoints") as Array[Vector2]).duplicate()
	var remembered_leads: Dictionary = (ai.get("_resource_memory") as Dictionary).duplicate(true)
	ai.set("_economy_exploration_waypoints", [] as Array[Vector2])
	ai.set("_resource_memory", {"food": [], "wood": [], "gold": []})
	map.resource_visible = false
	ai.call("_assign_idle_villagers")
	_expect(ai.get("_economy_wood_search_worker") == null and workers[3].move_target.distance_to(map.tile_to_world(base_tile)) < 0.01, "idle policy releases old search ownership before a go-home Move")
	ai.set("_economy_exploration_waypoints", search_waypoints)
	ai.set("_resource_memory", remembered_leads)
	map.resource_visible = true

	# The currently hidden lead was recorded during a legal sighting. Every route
	# now fails through the real UnitBase navigation result, leaving the worker
	# empty and IDLE. Thirty decision retries must not target that lead thirty times.
	workers[4].command_gather(food)
	workers[3].command_stop()
	map.resource_visible = false
	map.fail_routes = true
	ai.call("_reset_economy_recovery")
	var stale_tile := Vector2i(15, 15)
	var stale_position: Vector2 = map.tile_to_world(stale_tile)
	ai.call("_remember_resource_sighting", "wood", stale_position)
	var failed_memory_orders: int = 0
	for _tick: int in range(30):
		var issued_before: int = int(ai.get_strategy_snapshot()["economy_memory_revisit_orders"])
		ai.call("_assign_idle_villagers")
		if int(ai.get_strategy_snapshot()["economy_memory_revisit_orders"]) > issued_before and workers[3].move_target.distance_to(stale_position) < 0.01:
			failed_memory_orders += 1
		for _frame: int in range(120):
			workers[3].call("_process", 1.0 / 60.0)
			if workers[3].current_state == UnitBase.State.IDLE:
				break
	_report["stale_hidden_memory"] = {"failed_route_ticks": 30, "orders_to_same_lead": failed_memory_orders, "snapshot": ai.get_strategy_snapshot(), "worker_state": workers[3].current_state}
	_expect(failed_memory_orders == 1, "a stale hidden memory gets one attempt until another legal sighting")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_route_checks"]) > 0, "failed memory tests a bounded geometry route")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_orders"]) == 0, "unreachable geometry never counts an untraveled order as exploration")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_waypoints_remaining"]) == int(ai.get_strategy_snapshot()["economy_exploration_waypoint_count"]), "failed routes leave all unrevealed destinations available to other workers")

	# Re-observe a real resource through the current-visible lookup and accepted
	# gather order, then hide it again. This fresh sighting permits one new attempt.
	workers[3].command_stop()
	map.resource_visible = true
	map.fail_routes = false
	var fresh_wood := _resource(map, "wood", stale_tile)
	ai.call("_assign_idle_villagers")
	_expect(workers[3].gather_target == fresh_wood, "fresh currently visible Wood is gathered directly")
	var position_only: bool = true
	for memory: Dictionary in (ai.get("_resource_memory") as Dictionary)["wood"]:
		for value: Variant in memory.values():
			position_only = position_only and typeof(value) != TYPE_OBJECT
	_expect(position_only, "resource memory retains plain position data without live node references")
	workers[3].command_stop()
	map.resource_visible = false
	map.fail_routes = true
	var memory_orders_before: int = int(ai.get_strategy_snapshot()["economy_memory_revisit_orders"])
	ai.call("_assign_idle_villagers")
	_expect(int(ai.get_strategy_snapshot()["economy_memory_revisit_orders"]) == memory_orders_before + 1, "fresh legal sighting re-enables one memory attempt")
	workers[3].command_stop()
	workers[3].set("_auto_recovering", true)
	var orders_before_retreat: int = int(ai.get_strategy_snapshot()["economy_exploration_orders"])
	ai.call("_assign_idle_villagers")
	_expect(workers[3].current_state == UnitBase.State.IDLE and int(ai.get_strategy_snapshot()["economy_exploration_orders"]) == orders_before_retreat, "retreat ownership blocks resource search")
	workers[3].set("_auto_recovering", false)
	workers[3].carried_resource_type = "wood"
	workers[3].carried_amount = 7
	ai.call("_assign_idle_villagers")
	_expect(workers[3].carried_amount == 7 and workers[3].current_state != UnitBase.State.MOVING, "loaded worker preserves cargo and attempts Return instead of search")
	_expect(map.visibility_guard_returns > 0, "current-resource queries exit through the fixture visibility guard")
	workers[3].carried_amount = 0
	workers[3].command_stop()
	ai.call("_reset_economy_recovery")
	map.fail_routes = false
	ai.call("_remember_resource_sighting", "wood", stale_position)
	var enemy := preload("res://scenes/units/infantry.tscn").instantiate() as UnitBase
	enemy.player_owner = 0
	enemy.position = stale_position
	map.add_child(enemy)
	enemy.set_process(false)
	map.visible_enemies.append(enemy)
	ai.call("_assign_idle_villagers")
	var avoided_visible_threat: bool = not bool(ai.call("_is_worker_position_exposed", workers[3].move_target, [enemy]))
	_expect(avoided_visible_threat and int(ai.get_strategy_snapshot()["economy_memory_revisit_orders"]) == 0, "visible danger at a remembered lead selects a safe geometry destination")
	_expect(int(ai.get_strategy_snapshot()["resource_memory_count"]) == 1, "unattempted unsafe lead is retained without hidden revalidation")
	map.visible_enemies.clear()
	workers[3].command_stop()
	ai.call("_assign_idle_villagers")
	_expect(workers[3].move_target.distance_to(stale_position) < 0.01, "hidden enemy cannot veto an otherwise legal remembered-position attempt")
	_report["visible_threat_search_avoided"] = avoided_visible_threat
	_report["evidence_kind"] = "controlled visibility/failed-route fixture, explicit bank setup; not ordinary gameplay"
	_report["source_sha256"] = _source_hashes()
	_report["criteria_failures"] = _failures
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output).get_base_dir())
	var file := FileAccess.open(_output, FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	for failure: String in _failures:
		print("CRITERION_FAILURE ", failure)
	print("[", "OBSERVED" if _observe_only else ("PASS" if _failures.is_empty() else "FAIL"), "] ai_resource_deficit_search ", JSON.stringify(_report))
	get_tree().quit(0 if _observe_only or _failures.is_empty() else 1)


func _resource(map: SearchMap, kind: String, tile: Vector2i) -> ResourceNode:
	var resource := preload("res://scenes/map/resource_node.tscn").instantiate() as ResourceNode
	resource.resource_type = kind
	resource.tile_position = tile
	resource.position = map.tile_to_world(tile)
	map.add_child(resource)
	resource.set_process(false)
	map.resources.append(resource)
	return resource


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in ["scripts/ai/ai_controller.gd", "scripts/units/unit_base.gd", "scripts/units/villager.gd", "scripts/managers/resource_manager.gd", "scripts/managers/game_manager.gd", "tools/test_ai_resource_deficit_search.gd"]:
		hashes[path] = (load("res://" + path) as Script).source_code.sha256_text()
	return hashes
