extends SceneTree
## Focused integration regression for fair, villager-driven AI construction.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const PLAYER_AI: int = 1
const HOUSE_TYPE: int = 1
const STATE_IDLE: int = 0
const STATE_MOVING: int = 1
const STATE_BUILDING: int = 4
const STATE_CONSTRUCTING: int = 1
const STATE_ACTIVE: int = 2
const EPSILON: float = 0.001

var _failures: Array[String] = []


class UnreachableMap extends Node2D:
	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2(2000.0 + tile.x * 64.0, 2000.0 + tile.y * 32.0)

	func get_navigation_world_path(
		_from_world: Vector2,
		_target_world: Vector2,
		_arrival_radius_world: float = 4.0,
		_max_goal_radius_tiles: int = 6
	) -> PackedVector2Array:
		return PackedVector2Array()

	func is_tile_visible_to_player(_tile: Vector2i, _viewer_player_id: int = 0) -> bool:
		return true

	func is_tile_buildable(_tile: Vector2i) -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("AudioManager").call("set_all_enabled", false)
	var main_scene: PackedScene = load(MAIN_SCENE_PATH)
	var match_scene: Node = main_scene.instantiate()
	root.add_child(match_scene)

	var initialized: bool = false
	for _frame in range(240):
		await process_frame
		var tracked_units: Array = match_scene.get("_player_units")
		if tracked_units.size() > PLAYER_AI and tracked_units[PLAYER_AI].size() >= 4:
			initialized = true
			break
	_expect(initialized, "main scene initializes four AI villagers")
	if not initialized:
		match_scene.free()
		_finish()
		return

	var ai: Node = match_scene.get("ai_controller")
	var resource_manager: Node = root.get_node("ResourceManager")
	var decision_timer: Timer = ai.get("_decision_timer") as Timer
	if decision_timer != null:
		decision_timer.stop()
	match_scene.set_process(false)

	var player_units: Array = match_scene.get("_player_units")
	var villagers: Array = []
	for unit in player_units[PLAYER_AI]:
		if unit.has_method("command_build"):
			unit.set_process(false)
			unit.call("command_stop")
			villagers.append(unit)
	_expect(villagers.size() >= 4, "construction fixture exposes enough real Villagers")
	if villagers.size() < 4:
		match_scene.free()
		_finish()
		return

	resource_manager.call("initialize_player", PLAYER_AI, {"food": 1000, "wood": 1000, "gold": 1000})
	var game_map: Node2D = match_scene.get("game_map") as Node2D

	# The first foundation must reserve and occupy one actual Villager.
	var first_tile: Vector2i = ai.call("_find_build_location", HOUSE_TYPE)
	_expect(first_tile != Vector2i(-1, -1), "fixture finds a valid first House location")
	var first_position: Vector2 = game_map.call("tile_to_world", first_tile)
	match_scene.call("_on_ai_wants_to_build", HOUSE_TYPE, first_tile, false)
	var jobs: Dictionary = match_scene.get("_ai_construction_jobs")
	_expect_eq(jobs.size(), 1, "first AI foundation creates one tracked construction job")
	if jobs.is_empty():
		match_scene.free()
		_finish()
		return
	var first_job: Dictionary = jobs.values()[0]
	var first_building: Node = _weak_node(first_job, "building_ref")
	var first_builder: Node = _weak_node(first_job, "builder_ref")
	_expect(first_building != null, "first construction job retains its live foundation")
	_expect(first_builder != null, "first construction job assigns a live Villager")
	if first_building == null or first_builder == null:
		match_scene.free()
		_finish()
		return
	_expect_eq(int(first_builder.get("current_state")), STATE_BUILDING, "assigned AI Villager is occupied building")
	_expect(first_builder.get("build_target") == first_building, "assigned AI Villager targets its foundation")
	var travel_fixture: Dictionary = _find_reachable_distant_origin(game_map, first_tile, first_position)
	_expect(bool(travel_fixture.get("found", false)), "fixture finds a distant route around the placed foundation")
	if bool(travel_fixture.get("found", false)):
		first_builder.set("global_position", travel_fixture.get("position"))
		first_builder.call("_process_building", 0.05)
		_expect(first_builder.get("path").size() > 0, "builder begins real navigation around the foundation obstacle")
		_expect_approx(float(first_building.get("build_progress")), 0.0, "travel time contributes no remote build progress")

	# A concurrent foundation must consume a different Villager; the first
	# builder cannot provide invisible parallel labor.
	var second_tile: Vector2i = ai.call("_find_build_location", HOUSE_TYPE)
	_expect(second_tile != Vector2i(-1, -1), "fixture finds a distinct second House location")
	var second_position: Vector2 = game_map.call("tile_to_world", second_tile)
	for villager in villagers:
		if villager != first_builder:
			villager.global_position = second_position + Vector2(28.0, 0.0)
			break
	match_scene.call("_on_ai_wants_to_build", HOUSE_TYPE, second_tile, false)
	jobs = match_scene.get("_ai_construction_jobs")
	_expect_eq(jobs.size(), 2, "two concurrent foundations create two construction jobs")
	var second_building: Node = null
	var second_builder: Node = null
	for job_value in jobs.values():
		var job: Dictionary = job_value
		var candidate_building: Node = _weak_node(job, "building_ref")
		if candidate_building != first_building:
			second_building = candidate_building
			second_builder = _weak_node(job, "builder_ref")
			break
	_expect(second_building != null and second_builder != null, "second job has a live foundation and builder")
	_expect(second_builder != first_builder, "concurrent foundations reserve distinct Villagers")
	if second_builder != null:
		_expect_eq(int(second_builder.get("current_state")), STATE_BUILDING, "second assigned Villager is also occupied")

	# Real Villager work contributes one builder-second per simulated second.
	# No Main-owned tween can advance the foundation in the background.
	first_builder.set("global_position", first_position + Vector2(28.0, 0.0))
	var half_time: float = float(first_building.get("build_time")) * 0.5
	first_builder.call("_process_building", half_time)
	_expect_approx(float(first_building.get("build_progress")), 0.5, "one Villager reaches half progress at half build time")
	_expect_eq(int(first_building.get("state")), STATE_CONSTRUCTING, "foundation is not active at half build time")
	_expect_approx(float(second_building.get("build_progress")), 0.0, "another paused builder's foundation receives no free progress")
	first_builder.call("_process_building", half_time - 0.01)
	_expect_eq(int(first_building.get("state")), STATE_CONSTRUCTING, "foundation remains constructing just before configured duration")
	first_builder.call("_process_building", 0.01)
	_expect_eq(int(first_building.get("state")), STATE_ACTIVE, "foundation activates at the full configured one-builder duration")

	# With every Villager already building or otherwise tasked, a third request
	# must not spend resources or leave a foundation behind.
	for villager in villagers:
		if villager != second_builder:
			villager.set_state(STATE_MOVING)
	var third_tile: Vector2i = ai.call("_find_build_location", HOUSE_TYPE)
	var wood_before_no_builder: int = int(resource_manager.call("get_resource", PLAYER_AI, "wood"))
	var buildings_by_player: Array = match_scene.get("_player_buildings")
	var building_count_before: int = buildings_by_player[PLAYER_AI].size()
	match_scene.call("_on_ai_wants_to_build", HOUSE_TYPE, third_tile, false)
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), wood_before_no_builder, "no-builder rejection spends no wood")
	buildings_by_player = match_scene.get("_player_buildings")
	_expect_eq(buildings_by_player[PLAYER_AI].size(), building_count_before, "no-builder rejection spawns no foundation")

	# A direct or stale AI signal cannot probe or build on a footprint outside
	# current AI vision, even when a Villager is nominally available.
	first_builder.call("set_state", STATE_IDLE)
	var hidden_tile: Vector2i = _find_hidden_walkable_footprint(game_map, ai, Vector2i(2, 2))
	_expect(hidden_tile != Vector2i(-1, -1), "fixture finds a hidden walkable footprint")
	if hidden_tile != Vector2i(-1, -1):
		var wood_before_hidden: int = int(resource_manager.call("get_resource", PLAYER_AI, "wood"))
		var count_before_hidden: int = (match_scene.get("_player_buildings") as Array)[PLAYER_AI].size()
		_expect(
			not bool(match_scene.call("_is_ai_build_site_currently_valid", HOUSE_TYPE, hidden_tile)),
			"transaction preflight rejects a hidden AI footprint"
		)
		match_scene.call("_on_ai_wants_to_build", HOUSE_TYPE, hidden_tile, false)
		_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), wood_before_hidden, "hidden-site rejection spends no wood")
		_expect_eq((match_scene.get("_player_buildings") as Array)[PLAYER_AI].size(), count_before_hidden, "hidden-site rejection spawns no foundation")

	# A nominally available Villager still cannot authorize spending when the
	# navigation preflight cannot reach the interaction radius.
	var unreachable_map := UnreachableMap.new()
	root.add_child(unreachable_map)
	match_scene.set("game_map", unreachable_map)
	first_builder.set("global_position", Vector2.ZERO)
	first_builder.call("set_state", STATE_IDLE)
	var wood_before_unreachable: int = int(resource_manager.call("get_resource", PLAYER_AI, "wood"))
	match_scene.call("_on_ai_wants_to_build", HOUSE_TYPE, Vector2i(20, 20), false)
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), wood_before_unreachable, "unreachable preflight spends no wood")
	buildings_by_player = match_scene.get("_player_buildings")
	_expect_eq(buildings_by_player[PLAYER_AI].size(), building_count_before, "unreachable preflight spawns no foundation")
	match_scene.set("game_map", game_map)
	unreachable_map.free()

	# If the active builder stops, recovery assigns another reachable, unreserved
	# Villager. Repeated failure with no replacements is bounded and refunds the
	# abandoned transaction instead of leaving paid ghost construction.
	var replacement_candidate: Node = null
	for villager in villagers:
		if villager != first_builder and villager != second_builder:
			replacement_candidate = villager
			break
	_expect(replacement_candidate != null, "fixture has a spare recovery Villager")
	if replacement_candidate != null and second_builder != null:
		replacement_candidate.set("global_position", second_building.get("global_position") + Vector2(28.0, 0.0))
		replacement_candidate.call("set_state", STATE_IDLE)
		second_builder.call("command_stop")
		match_scene.call("_process_ai_construction_recovery", 0.5)
		jobs = match_scene.get("_ai_construction_jobs")
		var recovered_job: Dictionary = jobs.get(second_building.get_instance_id(), {})
		var recovered_builder: Node = _weak_node(recovered_job, "builder_ref")
		_expect(recovered_builder == replacement_candidate, "stopped construction is reassigned to another reachable Villager")
		_expect(recovered_builder != second_builder, "recovery does not recycle the failed builder")

		if recovered_builder != null:
			recovered_builder.call("command_stop")
		for villager in villagers:
			villager.set_state(STATE_MOVING)
		var wood_before_cancel: int = int(resource_manager.call("get_resource", PLAYER_AI, "wood"))
		var count_before_cancel: int = (match_scene.get("_player_buildings") as Array)[PLAYER_AI].size()
		for _attempt in range(4):
			match_scene.call("_process_ai_construction_recovery", 0.5)
		jobs = match_scene.get("_ai_construction_jobs")
		_expect(not jobs.has(second_building.get_instance_id()), "recovery gives up after its bounded retry budget")
		_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), wood_before_cancel + 50, "abandoned foundation refunds its full House cost")
		buildings_by_player = match_scene.get("_player_buildings")
		_expect_eq(buildings_by_player[PLAYER_AI].size(), count_before_cancel - 1, "abandoned foundation is removed from tracked AI buildings")

	# Rebuild memory is consumed before dispatch and restored by the same
	# no-builder rejection, so recovery bookkeeping cannot silently disappear.
	for villager in villagers:
		villager.set_state(STATE_MOVING)
	var rebuild_requests: Dictionary = ai.get("_rebuild_requests")
	rebuild_requests[HOUSE_TYPE] = 1
	ai.set("_rebuild_requests", rebuild_requests)
	var wood_before_rebuild_rejection: int = int(resource_manager.call("get_resource", PLAYER_AI, "wood"))
	ai.call("_check_rebuilding")
	rebuild_requests = ai.get("_rebuild_requests")
	_expect_eq(int(rebuild_requests.get(HOUSE_TYPE, 0)), 1, "rejected rebuild request remains in strategic memory")
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), wood_before_rebuild_rejection, "rejected rebuild request spends no resources")

	# Full decision-order regression: temporarily expose no resource through the
	# real GameMap registries, while leaving current-visible construction terrain
	# and Main's transaction/preflight untouched. A funded rebuild must reserve a
	# real builder before generic recovery moves the remaining IDLE villagers.
	var saved_natural_resources: Dictionary = (
		game_map.get("resource_nodes") as Dictionary
	).duplicate()
	var saved_additional_resources: Array = (
		game_map.get("_additional_resource_nodes") as Array
	).duplicate()
	game_map.set("resource_nodes", {})
	game_map.set("_additional_resource_nodes", [])
	ai.call("_reset_economy_recovery")
	for villager_index in range(villagers.size()):
		var villager: Node = villagers[villager_index]
		if villager_index == 0:
			villager.call("command_stop")
		else:
			villager.call("set_state", STATE_MOVING)
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 1000, "wood": 1000, "gold": 1000})
	rebuild_requests = ai.get("_rebuild_requests")
	rebuild_requests.clear()
	rebuild_requests[HOUSE_TYPE] = 1
	ai.set("_rebuild_requests", rebuild_requests)
	_expect(
		game_map.call("get_nearest_resource_node", "food", villagers[0].global_position, PLAYER_AI) == null,
		"decision-order fixture exposes no current resource target"
	)
	var jobs_before_no_resource_tick: int = (match_scene.get("_ai_construction_jobs") as Dictionary).size()
	var wood_before_no_resource_tick: int = int(resource_manager.call("get_resource", PLAYER_AI, "wood"))
	var exploration_before_no_resource_tick: int = int(ai.get("_economy_exploration_orders_issued"))
	ai.call("_on_decision_tick")
	jobs = match_scene.get("_ai_construction_jobs")
	_expect_eq(jobs.size(), jobs_before_no_resource_tick + 1, "no-resource decision still creates one funded Main construction transaction")
	var ordered_job: Dictionary = {}
	for job_value: Variant in jobs.values():
		var candidate_job: Dictionary = job_value as Dictionary
		if bool(candidate_job.get("is_rebuild", false)):
			ordered_job = candidate_job
			break
	var ordered_builder: Node = _weak_node(ordered_job, "builder_ref")
	_expect(ordered_builder != null, "construction-first decision reserves a real builder")
	if ordered_builder != null:
		_expect_eq(int(ordered_builder.get("current_state")), STATE_BUILDING, "reserved builder remains building after idle exploration runs")
	_expect_eq(int(ai.get("_economy_exploration_orders_issued")), exploration_before_no_resource_tick, "exploration cannot steal the only eligible construction worker")
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), wood_before_no_resource_tick - 50, "successful no-resource rebuild spends the normal House cost exactly once")
	_expect_eq(int((ai.get("_rebuild_requests") as Dictionary).get(HOUSE_TYPE, 0)), 0, "successful no-resource rebuild consumes its ledger entry")
	game_map.set("resource_nodes", saved_natural_resources)
	game_map.set("_additional_resource_nodes", saved_additional_resources)

	match_scene.free()
	_finish()


func _weak_node(job: Dictionary, key: String) -> Node:
	var reference: WeakRef = job.get(key)
	return reference.get_ref() as Node if reference != null else null


func _find_reachable_distant_origin(game_map: Node2D, target_tile: Vector2i, target_position: Vector2) -> Dictionary:
	for ring in range(3, 11):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if abs(dx) != ring and abs(dy) != ring:
					continue
				var candidate_tile := target_tile + Vector2i(dx, dy)
				if not bool(game_map.call("is_tile_walkable", candidate_tile)):
					continue
				var candidate_position: Vector2 = game_map.call("tile_to_world", candidate_tile)
				if candidate_position.distance_to(target_position) <= 80.0:
					continue
				var route: PackedVector2Array = game_map.call(
					"get_navigation_world_path",
					candidate_position,
					target_position,
					40.0
				)
				if route.is_empty() or route[route.size() - 1].distance_to(target_position) > 40.5:
					continue
				return {"found": true, "position": candidate_position}
	return {"found": false}


func _find_hidden_walkable_footprint(
	game_map: Node2D,
	ai: Node,
	footprint: Vector2i
) -> Vector2i:
	for y in range(MapData.MAP_HEIGHT - footprint.y - 1, 0, -1):
		for x in range(MapData.MAP_WIDTH - footprint.x - 1, 0, -1):
			var origin := Vector2i(x, y)
			var clear := true
			var fully_visible := true
			for dy in range(footprint.y):
				for dx in range(footprint.x):
					var tile := origin + Vector2i(dx, dy)
					clear = clear and bool(game_map.call("is_tile_walkable", tile))
					fully_visible = fully_visible and bool(
						game_map.call("is_tile_visible_to_player", tile, int(ai.get("player_id")))
					)
			if clear and not fully_visible:
				return origin
	return Vector2i(-1, -1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] ai_construction_timing: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_expect(false, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_approx(actual: float, expected: float, message: String) -> void:
	if is_equal_approx(actual, expected) or absf(actual - expected) <= EPSILON:
		return
	_expect(false, "%s (expected %.3f, got %.3f)" % [message, expected, actual])


func _finish() -> void:
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("[PASS] ai_construction_timing: real builders, construction-first recovery, fair duration, and bounded refunds")
		quit(0)
	else:
		quit(1)
