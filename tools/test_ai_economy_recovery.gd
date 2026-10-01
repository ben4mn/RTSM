extends SceneTree
## Regression for fair AI economy recovery when current vision contains no
## resource. The fixture exposes resources only through the same visibility-
## gated lookup used in production and records any attempted hidden lookup.

const AI_CONTROLLER_SCRIPT_PATH := "res://scripts/ai/ai_controller.gd"
const VILLAGER_SCENE_PATH := "res://scenes/units/villager.tscn"
const RESOURCE_SCENE_PATH := "res://scenes/map/resource_node.tscn"
const BARRACKS_SCENE_PATH := "res://scenes/buildings/barracks.tscn"
const FARM_SCENE_PATH := "res://scenes/buildings/farm.tscn"
const SCOUT_SCENE_PATH := "res://scenes/units/scout.tscn"
const PLAYER_HUMAN: int = 0
const PLAYER_AI: int = 1
const STATE_IDLE: int = 0
const STATE_MOVING: int = 1
const STATE_GATHERING: int = 3

var _failures: Array[String] = []
var _fixtures: Array = []


class RecoveryMap extends Node2D:
	var sacred_site: Node2D = null
	var visible_resource: Node2D = null
	var resource_visible: bool = false
	var visible_empty_tiles: Dictionary = {}
	var lookup_types: Array[String] = []
	var hidden_lookup_count: int = 0
	var reachable_resource_override: Node2D = null
	var last_reachable_exclusions: Dictionary = {}
	var registered_harvestables: Array[Node2D] = []
	var buildability_queries: int = 0
	var hidden_buildability_queries: int = 0

	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2(float(tile.x - tile.y) * 32.0, float(tile.x + tile.y) * 16.0)

	func world_to_tile(world_position: Vector2) -> Vector2i:
		var tile_x: int = roundi((world_position.x / 32.0 + world_position.y / 16.0) * 0.5)
		var tile_y: int = roundi((world_position.y / 16.0 - world_position.x / 32.0) * 0.5)
		return Vector2i(tile_x, tile_y)

	func is_tile_visible_to_player(tile: Vector2i, _viewer_player_id: int = 0) -> bool:
		if visible_empty_tiles.has(tile):
			return true
		if resource_visible:
			for candidate: Node2D in _resource_candidates():
				if tile == world_to_tile(candidate.global_position):
					return true
		return false

	func is_entity_visible_to_player(entity: Node2D, viewer_player_id: int = 0) -> bool:
		if entity.get("player_owner") != null and int(entity.get("player_owner")) == viewer_player_id:
			return true
		return resource_visible and entity in _resource_candidates()

	func is_tile_buildable(tile: Vector2i) -> bool:
		buildability_queries += 1
		if not is_tile_visible_to_player(tile, PLAYER_AI):
			hidden_buildability_queries += 1
			return false
		return true

	func get_navigation_world_path(
		from_world: Vector2,
		target_world: Vector2,
		_arrival_radius_world: float = 4.0,
		_max_goal_radius_tiles: int = 6
	) -> PackedVector2Array:
		return PackedVector2Array([from_world, target_world])

	func register_harvestable(resource: Node2D) -> void:
		if resource not in registered_harvestables:
			registered_harvestables.append(resource)
		visible_resource = resource

	func get_nearest_resource_node(
		resource_type: String,
		from_position: Vector2,
		_viewer_player_id: int = -1
	) -> Node2D:
		lookup_types.append(resource_type)
		# This guard intentionally precedes every resource property/validity read.
		if not resource_visible:
			hidden_lookup_count += 1
			return null
		var best_resource: Node2D = null
		var best_distance: float = INF
		for candidate: Node2D in _resource_candidates():
			if str(candidate.call("get_resource_type")) != resource_type:
				continue
			if not bool(candidate.call("is_harvestable_by", _viewer_player_id)):
				continue
			var distance: float = from_position.distance_squared_to(candidate.global_position)
			if distance < best_distance:
				best_distance = distance
				best_resource = candidate
		return best_resource

	func get_nearest_reachable_resource_node(
		resource_type: String,
		from_position: Vector2,
		viewer_player_id: int = -1,
		excluded_instance_ids: Dictionary = {}
	) -> Node2D:
		last_reachable_exclusions = excluded_instance_ids.duplicate()
		if not resource_visible:
			hidden_lookup_count += 1
			return null
		var candidates: Array[Node2D] = _resource_candidates()
		candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
			return from_position.distance_squared_to(a.global_position) < from_position.distance_squared_to(b.global_position)
		)
		for candidate: Node2D in candidates:
			if excluded_instance_ids.has(candidate.get_instance_id()):
				continue
			if str(candidate.call("get_resource_type")) != resource_type:
				continue
			if not bool(candidate.call("is_harvestable_by", viewer_player_id)):
				continue
			return candidate
		return null

	func _resource_candidates() -> Array[Node2D]:
		var candidates: Array[Node2D] = []
		for candidate in [visible_resource, reachable_resource_override]:
			if candidate == null or not is_instance_valid(candidate) or candidate in candidates:
				continue
			candidates.append(candidate as Node2D)
		return candidates


class CargoDropoff extends Node2D:
	var player_owner: int = PLAYER_AI
	var deposits: Dictionary = {"food": 0, "wood": 0, "gold": 0}

	func get_player_owner() -> int:
		return player_owner

	func is_drop_off_point(_resource_type: String) -> bool:
		return true

	func deposit_resource(resource_type: String, amount: int) -> void:
		deposits[resource_type] = int(deposits.get(resource_type, 0)) + amount


class SacredFixture extends Node2D:
	var owning_player: int = PLAYER_AI


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio_manager: Node = root.get_node("AudioManager")
	var game_manager: Node = root.get_node("GameManager")
	var resource_manager: Node = root.get_node("ResourceManager")
	audio_manager.call("set_all_enabled", false)
	game_manager.call("initialize_game", 2)
	# These fixtures preserve the established large-match policy contract.
	# Compact 20/30/40 skirmishes have separate population-policy coverage.
	for player_data in game_manager.players.values():
		player_data["max_population"] = 200
	resource_manager.call("reset")
	resource_manager.call("initialize_player", PLAYER_HUMAN, {"food": 0, "wood": 0, "gold": 0})
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 0, "wood": 100, "gold": 100})

	var recovery_map := RecoveryMap.new()
	root.add_child(recovery_map)
	_fixtures.append(recovery_map)
	var base_tile := Vector2i(33, 6)
	var base_position: Vector2 = recovery_map.tile_to_world(base_tile)

	var ai: Node = load(AI_CONTROLLER_SCRIPT_PATH).new()
	root.add_child(ai)
	_fixtures.append(ai)
	ai.set("game_map", recovery_map)
	ai.call("start_ai", base_tile, base_position)
	(ai.get("_decision_timer") as Timer).stop()

	var villager: Node = _spawn_fixture(VILLAGER_SCENE_PATH, PLAYER_AI, base_position)
	recovery_map.add_child(villager)
	ai.call("register_unit", villager)

	# No target is visible: the old behavior repeatedly moved to base. The new
	# policy must issue a geometry-only exploration order inside map bounds.
	ai.call("_assign_idle_villagers")
	_expect_eq(int(villager.get("current_state")), STATE_MOVING, "no-visible-resource recovery issues a real movement order")
	var first_move_target: Vector2 = villager.get("move_target") as Vector2
	_expect(first_move_target.distance_to(base_position) > 1.0, "no-visible-resource recovery does not loop at the Town Center")
	var first_exploration_tile: Vector2i = recovery_map.world_to_tile(first_move_target)
	_expect(_is_in_bounds(first_exploration_tile), "geometry-only exploration target remains inside public map bounds")
	var snapshot: Dictionary = ai.call("get_strategy_snapshot")
	_expect_eq(int(snapshot.get("economy_exploration_orders", 0)), 1, "exploration order is exposed in strategy telemetry")
	_expect_eq(str(snapshot.get("last_economy_action", "")), "explore", "strategy telemetry identifies economy exploration")

	# Repeat the setup independently to prove waypoint choice is deterministic.
	var second_ai: Node = load(AI_CONTROLLER_SCRIPT_PATH).new()
	root.add_child(second_ai)
	_fixtures.append(second_ai)
	second_ai.set("game_map", recovery_map)
	second_ai.call("start_ai", base_tile, base_position)
	(second_ai.get("_decision_timer") as Timer).stop()
	var deterministic_target: Dictionary = second_ai.call("_take_next_economy_exploration_target")
	_expect_vector_approx(
		deterministic_target.get("position", Vector2.ZERO) as Vector2,
		first_move_target,
		"identical base state produces an identical first exploration destination"
	)

	# A resource becomes visible through normal exploration. Assignment is legal,
	# and memory captures plain position data only after command acceptance.
	var resource: Node2D = _spawn_fixture(RESOURCE_SCENE_PATH, -1, recovery_map.tile_to_world(Vector2i(27, 12))) as Node2D
	resource.set("resource_type", "food")
	recovery_map.add_child(resource)
	recovery_map.visible_resource = resource
	recovery_map.resource_visible = true
	villager.call("set_state", STATE_IDLE)
	ai.call("_assign_idle_villagers")
	_expect_eq(int(villager.get("current_state")), STATE_GATHERING, "newly visible food resumes real gathering")
	_expect(villager.get("gather_target") == resource, "visible lookup result becomes the gather target")
	seed(1)
	_expect(bool(villager.call("command_gather", resource)), "visible resource accepts a deterministic-offset gather order")
	var deterministic_offset: Vector2 = villager.get("_gather_offset") as Vector2
	seed(999)
	_expect(bool(villager.call("command_gather", resource)), "same visible resource accepts a repeated gather order")
	_expect_vector_approx(
		villager.get("_gather_offset") as Vector2,
		deterministic_offset,
		"gather approach offset is independent of global RNG consumption"
	)
	seed(202)
	snapshot = ai.call("get_strategy_snapshot")
	_expect_eq(int(snapshot.get("resource_memory_count", 0)), 1, "legal sighting creates one position-only memory")
	_expect_eq(int(snapshot.get("economy_resource_assignments", 0)), 1, "successful gather assignment is exposed in telemetry")
	_expect(_resource_memory_is_position_only(ai), "resource memory contains no live node or weak reference")

	# AI assignment must honor the same unreachable cache used by Villager's
	# autonomous retargeting instead of immediately restoring the closest target.
	var farther_resource: Node2D = _spawn_fixture(
		RESOURCE_SCENE_PATH,
		-1,
		recovery_map.tile_to_world(Vector2i(25, 14))
	) as Node2D
	farther_resource.set("resource_type", "food")
	recovery_map.add_child(farther_resource)
	recovery_map.reachable_resource_override = farther_resource
	var unreachable_until: Dictionary = villager.get("_unreachable_resource_ids_until") as Dictionary
	unreachable_until[resource.get_instance_id()] = Time.get_ticks_msec() + 5000
	var reachable_choice: Node2D = ai.call("_find_resource_for_villager", "food", villager) as Node2D
	_expect(reachable_choice == farther_resource, "AI chooses the farther reachable resource over a cached unreachable nearest target")
	_expect(
		recovery_map.last_reachable_exclusions.has(resource.get_instance_id()),
		"AI forwards the villager's unreachable-target exclusion cache"
	)
	recovery_map.reachable_resource_override = null
	recovery_map.remove_child(farther_resource)
	farther_resource.free()
	unreachable_until.clear()

	# A different-resource command with cargo is accepted as a two-step order.
	# It must deliver the exact original type before resolving the new target from
	# current vision; the pending intent itself is position/type metadata only.
	var cargo_dropoff := CargoDropoff.new()
	cargo_dropoff.global_position = base_position
	recovery_map.add_child(cargo_dropoff)
	cargo_dropoff.add_to_group("dropoff_buildings")
	_fixtures.append(cargo_dropoff)
	var closer_food: Node2D = _spawn_fixture(
		RESOURCE_SCENE_PATH,
		-1,
		recovery_map.tile_to_world(base_tile + Vector2i(-1, 1))
	) as Node2D
	closer_food.set("resource_type", "food")
	recovery_map.add_child(closer_food)
	recovery_map.reachable_resource_override = closer_food
	var cross_type_worker: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position
	)
	recovery_map.add_child(cross_type_worker)
	cross_type_worker.set("carried_resource_type", "wood")
	cross_type_worker.set("carried_amount", 7)
	cross_type_worker.call("set_state", STATE_IDLE)
	_expect(
		bool(cross_type_worker.call("command_gather", resource)),
		"loaded cross-resource gather order is accepted"
	)
	_expect_eq(str(cross_type_worker.get("carried_resource_type")), "wood", "accepted retarget keeps the in-hand cargo typed as wood")
	_expect_eq(int(cross_type_worker.get("carried_amount")), 7, "accepted retarget keeps the exact in-hand cargo amount")
	_expect_eq(str(cross_type_worker.get("_pending_gather_resource_type")), "food", "new food intent waits behind the wood delivery")
	_expect_eq(int(cross_type_worker.get("current_state")), STATE_MOVING, "loaded retarget routes to a real drop-off first")
	cross_type_worker.call("_on_arrived_for_dropoff", cross_type_worker)
	_expect_eq(int(cargo_dropoff.deposits.get("wood", 0)), 7, "drop-off receives exactly seven wood from the loaded retarget")
	_expect_eq(int(cargo_dropoff.deposits.get("food", 0)), 0, "loaded retarget cannot transmute wood into food")
	_expect_eq(int(cross_type_worker.get("carried_amount")), 0, "original cargo clears only after the real delivery")
	_expect_eq(str(cross_type_worker.get("carried_resource_type")), "food", "food accounting activates only after wood delivery")
	_expect(cross_type_worker.get("gather_target") == resource, "post-delivery retarget preserves the farther explicitly selected food source")
	_expect(cross_type_worker.get("gather_target") != closer_food, "nearer food at the drop-off cannot replace the explicit target")
	cross_type_worker.free()

	# If fog closes during delivery, activation must not retain or inspect the
	# original node. It approaches the accepted position and re-resolves only
	# after that tile becomes currently visible again.
	var hidden_pending_worker: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position
	)
	recovery_map.add_child(hidden_pending_worker)
	hidden_pending_worker.set("carried_resource_type", "wood")
	hidden_pending_worker.set("carried_amount", 7)
	hidden_pending_worker.call("set_state", STATE_IDLE)
	_expect(bool(hidden_pending_worker.call("command_gather", resource)), "visible target accepts the second loaded retarget")
	recovery_map.resource_visible = false
	var hidden_lookups_before_delivery: int = recovery_map.hidden_lookup_count
	hidden_pending_worker.call("_on_arrived_for_dropoff", hidden_pending_worker)
	_expect_eq(recovery_map.hidden_lookup_count, hidden_lookups_before_delivery, "delivery activation performs no resource lookup while its accepted tile is hidden")
	_expect(hidden_pending_worker.get("gather_target") == null, "hidden pending order retains no live resource reference")
	_expect_vector_approx(
		hidden_pending_worker.get("_gather_last_known_position") as Vector2,
		resource.global_position,
		"hidden pending order retains only the legally observed target position"
	)
	_expect_eq(str(hidden_pending_worker.get("carried_resource_type")), "food", "post-delivery hidden approach carries the requested accounting type with zero cargo")
	_expect_eq(int(hidden_pending_worker.get("carried_amount")), 0, "hidden approach begins only after original cargo is delivered")
	recovery_map.resource_visible = true
	hidden_pending_worker.call("_process_gathering", 0.0)
	_expect(hidden_pending_worker.get("gather_target") == resource, "revealing the pending tile re-resolves a current-visible reachable food source")
	_expect_eq(int(cargo_dropoff.deposits.get("wood", 0)), 14, "hidden transition still deposits the exact original wood load")
	hidden_pending_worker.free()

	# If the accepted target is removed while hidden, even a registered same-type
	# replacement at the identical position has a different observed identity.
	# Reveal permits validation but not a silent substitution or redirect.
	var removed_food: Node2D = _spawn_fixture(
		RESOURCE_SCENE_PATH,
		-1,
		recovery_map.tile_to_world(Vector2i(24, 15))
	) as Node2D
	removed_food.set("resource_type", "food")
	recovery_map.add_child(removed_food)
	recovery_map.visible_resource = removed_food
	var removed_position: Vector2 = removed_food.global_position
	var removed_id: int = removed_food.get_instance_id()
	var depleted_pending_worker: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position
	)
	recovery_map.add_child(depleted_pending_worker)
	depleted_pending_worker.set("carried_resource_type", "wood")
	depleted_pending_worker.set("carried_amount", 7)
	depleted_pending_worker.call("set_state", STATE_IDLE)
	_expect(bool(depleted_pending_worker.call("command_gather", removed_food)), "visible soon-depleted target accepts a loaded retarget")
	_expect_eq(int(depleted_pending_worker.get("_pending_gather_last_known_instance_id")), removed_id, "pending order stores only the observed scalar identity")
	recovery_map.resource_visible = false
	recovery_map.remove_child(removed_food)
	removed_food.free()
	depleted_pending_worker.call("_on_arrived_for_dropoff", depleted_pending_worker)
	_expect(depleted_pending_worker.get("gather_target") == null, "hidden removal cannot redirect the pending gather order")
	var replacement_food: Node2D = _spawn_fixture(
		RESOURCE_SCENE_PATH,
		-1,
		removed_position
	) as Node2D
	replacement_food.set("resource_type", "food")
	recovery_map.add_child(replacement_food)
	recovery_map.visible_resource = replacement_food
	recovery_map.resource_visible = true
	depleted_pending_worker.call("_process_gathering", 0.0)
	_expect_eq(int(depleted_pending_worker.get("current_state")), STATE_IDLE, "revealed depleted target ends the explicit pending order")
	_expect(depleted_pending_worker.get("gather_target") == null, "same-tile replacement with a different identity is rejected")
	_expect(depleted_pending_worker.get("gather_target") != closer_food, "revealed depletion does not silently redirect to nearer food")
	_expect_eq(int(cargo_dropoff.deposits.get("wood", 0)), 21, "depleted transition still deposits the exact original wood load")
	depleted_pending_worker.free()
	recovery_map.remove_child(replacement_food)
	replacement_food.free()
	recovery_map.visible_resource = resource
	recovery_map.reachable_resource_override = null
	recovery_map.remove_child(closer_food)
	closer_food.free()

	# AI generic idle recovery also gives loaded workers an explicit return order;
	# it never sends them toward a new resource, memory point, or search waypoint.
	var loaded_recovery_worker: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position
	)
	recovery_map.add_child(loaded_recovery_worker)
	loaded_recovery_worker.set("carried_resource_type", "wood")
	loaded_recovery_worker.set("carried_amount", 7)
	loaded_recovery_worker.call("set_state", STATE_IDLE)
	ai.call("register_unit", loaded_recovery_worker)
	ai.call("_assign_idle_villagers")
	_expect_eq(int(loaded_recovery_worker.get("current_state")), STATE_MOVING, "AI loaded-IDLE recovery routes cargo to a drop-off")
	_expect_eq(str(loaded_recovery_worker.get("carried_resource_type")), "wood", "AI idle recovery preserves cargo type in transit")
	_expect_eq(int(loaded_recovery_worker.get("carried_amount")), 7, "AI idle recovery preserves cargo amount in transit")
	_expect(loaded_recovery_worker.get("dropoff_target") == cargo_dropoff, "AI idle recovery selects the owned reachable drop-off")
	_expect_eq(str(loaded_recovery_worker.get("_pending_gather_resource_type")), "", "AI cargo return does not invent a cross-resource pending order")
	loaded_recovery_worker.call("_on_arrived_for_dropoff", loaded_recovery_worker)
	_expect_eq(int(cargo_dropoff.deposits.get("wood", 0)), 28, "AI recovery deposits the fourth exact seven-wood load")
	loaded_recovery_worker.free()
	ai.call("_cleanup_references")

	# The Feudal timing boundary activates saving even below the old completion
	# ratio latch. The pre-Feudal gates match the declared Medium liveness floors,
	# so reserve mode cannot itself cap the policy below 12 villagers/3 military.
	ai.set("_game_time", 54.9)
	ai.call("_update_age_up_reserve")
	_expect(not bool(ai.get("_timed_age_up_reserve_active")), "Medium Feudal reserve remains off before its t55 boundary")
	ai.set("_game_time", 55.0)
	ai.call("_update_age_up_reserve")
	_expect(bool(ai.get("_timed_age_up_reserve_active")), "Medium Feudal reserve activates at t55 to fund paid infrastructure")
	_expect(bool(ai.get("_saving_for_age_up")), "timed reserve activates before the completion-ratio latch")
	_expect(
		bool(ai.call("_should_pause_villager_production_for_age_up", 12, 0)),
		"timed Feudal reserve pauses villager spending at the Medium pre-age gate"
	)
	_expect(
		not bool(ai.call("_should_pause_villager_production_for_age_up", 11, 0)),
		"timed Feudal reserve still permits reaching the Medium pre-age gate"
	)
	ai.set("_is_under_pressure", true)
	_expect(
		not bool(ai.call("_should_pause_villager_production_for_age_up", 12, 0)),
		"pressure reserve keeps producing through the extra age-up survivor gate"
	)
	_expect(
		bool(ai.call("_should_pause_villager_production_for_age_up", 13, 0)),
		"pressure reserve pauses only after its age-up villager predicate is met"
	)
	ai.set("_is_under_pressure", false)
	_expect_eq(int(ai.call("_get_min_villagers_for_age_up", 2)), 12, "Medium Feudal villager gate cannot cap below the policy floor")
	_expect_eq(int(ai.call("_get_min_military_for_age_up", 2)), 3, "Medium Feudal military gate cannot cap below the policy floor")
	ai.set("difficulty", 0)
	game_manager.players[PLAYER_AI]["age"] = 2
	ai.set("_is_under_pressure", false)
	_expect_eq(int(ai.call("_get_target_villager_count")), 18, "Easy Castle progression target cannot stop below its 18-villager gate")
	ai.set("_is_under_pressure", true)
	_expect_eq(int(ai.call("_get_target_villager_count")), 19, "pressure keeps one survivor above the Easy Castle villager gate")
	ai.set("difficulty", 1)
	game_manager.players[PLAYER_AI]["age"] = 1
	ai.set("_is_under_pressure", false)
	var overshoot_targets: Dictionary = ai.call(
		"_get_economy_worker_targets",
		9,
		{"food": 360, "wood": 75, "gold": 598}
	) as Dictionary
	_expect_eq(int(overshoot_targets.get("food", 0)), 4, "fulfilled gold allocates every non-wood reserve worker to missing food")
	_expect_eq(int(overshoot_targets.get("wood", 0)), 5, "Feudal reserve temporarily commits half the workforce to paid infrastructure")
	_expect_eq(int(overshoot_targets.get("gold", -1)), 0, "gold target drops to zero after the 200-gold cost is met")
	var farm_funding_priority: Array = ai.call(
		"_get_economy_resource_priority",
		{"food": 0, "wood": 55, "gold": 406}
	) as Array
	_expect_eq(str(farm_funding_priority[0]), "wood", "timed no-food recovery makes visible wood the feasible first priority")
	ai.set("_farm_count", 3)
	ai.set("_feudal_paid_farm_foundations", 3)
	ai.set("_barracks_count", 0)
	var barracks_funding_targets: Dictionary = ai.call(
		"_get_economy_worker_targets",
		9,
		{"food": 360, "wood": 75, "gold": 598}
	) as Dictionary
	_expect_eq(int(barracks_funding_targets.get("wood", 0)), 5, "wood floor persists after Farm 3 until the first Barracks is funded")
	ai.set("_barracks_count", 1)
	var completed_opening_targets: Dictionary = ai.call(
		"_get_economy_worker_targets",
		9,
		{"food": 360, "wood": 75, "gold": 598}
	) as Dictionary
	_expect_eq(int(completed_opening_targets.get("wood", 0)), 1, "wood floor releases after three Farms and Barracks are registered")

	# Timed reserve converges one transaction-safe donor per decision instead of
	# waiting 20 seconds between every ramp/unwind step. The ordinary cadence stays
	# unchanged outside this bounded opening window. A loaded unwind donor also
	# proves its pending destination is counted before the next correction.
	var saved_ai_units: Array = (ai.get("_my_units") as Array).duplicate()
	ai.set("_my_units", [])
	var convergence_workers: Array[Node] = []
	resource.set("resource_type", "wood")
	recovery_map.visible_resource = resource
	recovery_map.resource_visible = true
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 0, "wood": 0, "gold": 200})
	ai.set("_farm_count", 0)
	ai.set("_feudal_paid_farm_foundations", 0)
	ai.set("_barracks_count", 0)
	ai.set("_saving_for_age_up", true)
	ai.set("_timed_age_up_reserve_active", true)
	ai.set("_is_under_pressure", false)
	for index in range(6):
		var convergence_worker: Node = _spawn_fixture(
			VILLAGER_SCENE_PATH,
			PLAYER_AI,
			base_position + Vector2(float(index) * 10.0, 24.0)
		)
		recovery_map.add_child(convergence_worker)
		convergence_worker.set("carried_resource_type", "wood" if index == 0 else "food")
		convergence_worker.set("carried_amount", 0)
		convergence_worker.call("set_state", STATE_GATHERING)
		ai.call("register_unit", convergence_worker)
		convergence_workers.append(convergence_worker)
	var convergence_orders_before: int = int(
		(ai.call("get_strategy_snapshot") as Dictionary).get("economy_rebalance_orders", 0)
	)
	ai.set("_next_economy_rebalance_time", INF)
	ai.call("_rebalance_gathering_villagers")
	ai.call("_rebalance_gathering_villagers")
	var ramped_wood_workers: int = 0
	for convergence_worker: Node in convergence_workers:
		if str(convergence_worker.get("carried_resource_type")) == "wood":
			ramped_wood_workers += 1
	_expect_eq(ramped_wood_workers, 3, "timed reserve ramps from one to three wood workers in two bounded decisions")
	_expect_eq(
		int((ai.call("get_strategy_snapshot") as Dictionary).get("economy_rebalance_orders", 0)),
		convergence_orders_before + 2,
		"rapid ramp still changes only one donor per decision"
	)

	# Two of the three wood workers carry real cargo. Unwind first takes the empty
	# worker, then accepts exactly one loaded deposit-then-food transaction.
	var ramped_workers: Array[Node] = []
	for convergence_worker: Node in convergence_workers:
		if str(convergence_worker.get("carried_resource_type")) == "wood":
			ramped_workers.append(convergence_worker)
	(ramped_workers[0] as Node).set("carried_amount", 0)
	(ramped_workers[1] as Node).set("carried_amount", 7)
	(ramped_workers[2] as Node).set("carried_amount", 7)
	resource.set("resource_type", "food")
	ai.set("_farm_count", 3)
	ai.set("_feudal_paid_farm_foundations", 3)
	ai.set("_barracks_count", 1)
	ai.call("_rebalance_gathering_villagers")
	ai.call("_rebalance_gathering_villagers")
	var pending_food_workers: int = 0
	var remaining_wood_workers: int = 0
	for convergence_worker: Node in convergence_workers:
		if str(convergence_worker.get("_pending_gather_resource_type")) == "food":
			pending_food_workers += 1
		if (
			str(convergence_worker.get("carried_resource_type")) == "wood"
			and str(convergence_worker.get("_pending_gather_resource_type")) == ""
		):
			remaining_wood_workers += 1
	_expect_eq(pending_food_workers, 1, "rapid unwind accepts one loaded wood-to-food transaction")
	_expect_eq(remaining_wood_workers, 1, "rapid unwind preserves the single post-opening wood worker")
	var orders_after_unwind: int = int(
		(ai.call("get_strategy_snapshot") as Dictionary).get("economy_rebalance_orders", 0)
	)
	ai.call("_rebalance_gathering_villagers")
	_expect_eq(
		int((ai.call("get_strategy_snapshot") as Dictionary).get("economy_rebalance_orders", 0)),
		orders_after_unwind,
		"loaded pending food assignment is counted and prevents unwind over-correction"
	)

	# Recreate a normal-cadence deficit and place its clock in the future. Outside
	# timed reserve no donor may move early.
	for convergence_worker: Node in convergence_workers:
		convergence_worker.call("_clear_pending_gather_order")
		convergence_worker.set("carried_amount", 0)
		convergence_worker.set("carried_resource_type", "food")
		convergence_worker.call("set_state", STATE_GATHERING)
	(convergence_workers[0] as Node).set("carried_resource_type", "wood")
	(convergence_workers[1] as Node).set("carried_resource_type", "gold")
	ai.set("_timed_age_up_reserve_active", false)
	ai.set("_next_economy_rebalance_time", float(ai.get("_game_time")) + 1000.0)
	var orders_before_normal_gate: int = int(
		(ai.call("get_strategy_snapshot") as Dictionary).get("economy_rebalance_orders", 0)
	)
	ai.call("_rebalance_gathering_villagers")
	_expect_eq(
		int((ai.call("get_strategy_snapshot") as Dictionary).get("economy_rebalance_orders", 0)),
		orders_before_normal_gate,
		"normal workforce rebalance retains its configured cadence"
	)
	for convergence_worker: Node in convergence_workers:
		convergence_worker.free()
	ai.set("_my_units", saved_ai_units)
	ai.set("_timed_age_up_reserve_active", true)
	resource.set("resource_type", "food")
	(ai.get("_resource_memory") as Dictionary)["wood"] = []

	# Periodic workforce rebalance changes at most one gatherer, preferring the
	# zero-cargo donor over a loaded gatherer. Builders and dropoff movers remain
	# ineligible. Model the farm transactions as funded so this isolates selection
	# from wood preservation; the bank also proves the zero-gold target moves one.
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 360, "wood": 75, "gold": 598})
	ai.set("_farm_count", 3)
	ai.set("_feudal_paid_farm_foundations", 3)
	ai.set("_barracks_count", 1)
	var donor_villagers: Array[Node] = []
	for index in range(3):
		var donor: Node = _spawn_fixture(
			VILLAGER_SCENE_PATH,
			PLAYER_AI,
			base_position + Vector2(float(index + 1) * 12.0, 0.0)
		)
		recovery_map.add_child(donor)
		donor.set("carried_resource_type", "gold")
		donor.set("carried_amount", 7 if index == 0 else 0)
		donor.call("set_state", STATE_GATHERING if index < 2 else 4)
		ai.call("register_unit", donor)
		donor_villagers.append(donor)
	var dropoff_mover: Node = donor_villagers[1]
	dropoff_mover.set("carried_amount", 7)
	dropoff_mover.call("set_state", STATE_MOVING)
	var safe_zero_carry_donor: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position + Vector2(48.0, 0.0)
	)
	recovery_map.add_child(safe_zero_carry_donor)
	safe_zero_carry_donor.set("carried_resource_type", "gold")
	safe_zero_carry_donor.set("carried_amount", 0)
	safe_zero_carry_donor.call("set_state", STATE_GATHERING)
	ai.call("register_unit", safe_zero_carry_donor)
	donor_villagers.append(safe_zero_carry_donor)
	var periodic_rebalance_orders_before: int = int(
		(ai.call("get_strategy_snapshot") as Dictionary).get("economy_rebalance_orders", 0)
	)
	ai.set("_timed_age_up_reserve_active", false)
	ai.set("_next_economy_rebalance_time", 0.0)
	ai.call("_rebalance_gathering_villagers")
	_expect_eq(str(safe_zero_carry_donor.get("carried_resource_type")), "food", "rebalance retasks one safe zero-carry donor toward the age-up shortage")
	_expect_eq(int(donor_villagers[0].get("carried_amount")), 7, "rebalance preserves a loaded gatherer's cargo")
	_expect_eq(int(donor_villagers[0].get("current_state")), STATE_GATHERING, "rebalance does not interrupt a loaded gatherer")
	_expect_eq(int(dropoff_mover.get("current_state")), STATE_MOVING, "rebalance does not interrupt a dropoff mover")
	_expect_eq(int(donor_villagers[2].get("current_state")), 4, "rebalance does not interrupt a builder")
	snapshot = ai.call("get_strategy_snapshot")
	_expect_eq(int(snapshot.get("economy_rebalance_orders", 0)), periodic_rebalance_orders_before + 1, "bounded workforce rebalance emits exactly one order")
	ai.set("_timed_age_up_reserve_active", true)
	for donor: Node in donor_villagers:
		donor.free()
	ai.call("_cleanup_references")

	# If every eligible donor is loaded, a direct currently-visible/reachable
	# target uses the Villager transaction instead of waiting for a short zero-load
	# polling window. The old cargo is unchanged until its exact real deposit.
	var loaded_direct_donor: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position
	)
	recovery_map.add_child(loaded_direct_donor)
	loaded_direct_donor.set("carried_resource_type", "gold")
	loaded_direct_donor.set("carried_amount", 7)
	loaded_direct_donor.call("set_state", STATE_GATHERING)
	ai.call("register_unit", loaded_direct_donor)
	ai.set("_pending_economy_rebalance_type", "food")
	ai.set("_pending_economy_rebalance_from_type", "gold")
	ai.set("_pending_economy_rebalance_deadline", float(ai.get("_game_time")) + 18.0)
	var rebalance_orders_before_loaded: int = int(
		(ai.call("get_strategy_snapshot") as Dictionary).get("economy_rebalance_orders", 0)
	)
	ai.call("_service_pending_economy_rebalance")
	_expect_eq(int(loaded_direct_donor.get("current_state")), STATE_MOVING, "loaded donor begins an exact drop-off before cross-resource rebalance")
	_expect_eq(str(loaded_direct_donor.get("carried_resource_type")), "gold", "loaded rebalance preserves old cargo type in transit")
	_expect_eq(int(loaded_direct_donor.get("carried_amount")), 7, "loaded rebalance preserves old cargo amount in transit")
	_expect_eq(str(loaded_direct_donor.get("_pending_gather_resource_type")), "food", "loaded donor records the direct food target behind delivery")
	_expect_eq(str(ai.get("_pending_economy_rebalance_type")), "", "accepted loaded transaction clears the AI rebalance request")
	loaded_direct_donor.call("_on_arrived_for_dropoff", loaded_direct_donor)
	_expect_eq(int(cargo_dropoff.deposits.get("gold", 0)), 7, "loaded donor deposits exactly seven gold before switching")
	_expect_eq(int(cargo_dropoff.deposits.get("food", 0)), 0, "loaded donor rebalance cannot transmute gold into food")
	_expect_eq(str(loaded_direct_donor.get("carried_resource_type")), "food", "loaded donor activates food only after gold delivery")
	_expect(loaded_direct_donor.get("gather_target") == resource, "loaded donor activates the direct visible food target")
	snapshot = ai.call("get_strategy_snapshot")
	_expect_eq(int(snapshot.get("economy_rebalance_orders", 0)), rebalance_orders_before_loaded + 1, "loaded direct rebalance emits exactly one order")
	loaded_direct_donor.free()
	ai.call("_cleanup_references")

	# With no direct legal target, the loaded donor and its cargo remain untouched;
	# memory and geometry exploration are not substitutes for a safe transaction.
	var hidden_loaded_donor: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position
	)
	recovery_map.add_child(hidden_loaded_donor)
	hidden_loaded_donor.set("carried_resource_type", "gold")
	hidden_loaded_donor.set("carried_amount", 5)
	hidden_loaded_donor.call("set_state", STATE_GATHERING)
	ai.call("register_unit", hidden_loaded_donor)
	recovery_map.resource_visible = false
	ai.set("_pending_economy_rebalance_type", "food")
	ai.set("_pending_economy_rebalance_from_type", "gold")
	ai.set("_pending_economy_rebalance_deadline", float(ai.get("_game_time")) + 1.0)
	var memory_orders_before_hidden_donor: int = int(ai.get("_economy_memory_revisit_orders_issued"))
	var exploration_orders_before_hidden_donor: int = int(ai.get("_economy_exploration_orders_issued"))
	ai.call("_service_pending_economy_rebalance")
	_expect_eq(int(hidden_loaded_donor.get("current_state")), STATE_GATHERING, "no-direct-target rebalance leaves loaded donor gathering")
	_expect_eq(str(hidden_loaded_donor.get("carried_resource_type")), "gold", "no-direct-target rebalance preserves donor type")
	_expect_eq(int(hidden_loaded_donor.get("carried_amount")), 5, "no-direct-target rebalance preserves donor amount")
	_expect_eq(str(ai.get("_pending_economy_rebalance_type")), "food", "no-direct-target request remains pending until its deadline")
	_expect_eq(int(ai.get("_economy_memory_revisit_orders_issued")), memory_orders_before_hidden_donor, "loaded donor never receives a memory move")
	_expect_eq(int(ai.get("_economy_exploration_orders_issued")), exploration_orders_before_hidden_donor, "loaded donor never receives an exploration move")
	ai.set("_game_time", float(ai.get("_pending_economy_rebalance_deadline")) + 0.01)
	ai.call("_service_pending_economy_rebalance")
	_expect_eq(str(ai.get("_pending_economy_rebalance_type")), "", "unserviceable direct request expires at its bounded deadline")
	recovery_map.resource_visible = true
	hidden_loaded_donor.free()
	ai.call("_cleanup_references")

	# A donor carrying cargo cannot be interrupted by the periodic poll. Its real
	# deposit signal schedules one deferred retry; after Villager clears cargo and
	# resumes gathering, the pending request is fulfilled without cargo mutation.
	var depositing_donor: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position + Vector2(60.0, 0.0)
	)
	recovery_map.add_child(depositing_donor)
	depositing_donor.set("carried_resource_type", "gold")
	depositing_donor.set("carried_amount", 7)
	depositing_donor.call("set_state", STATE_MOVING)
	ai.call("register_unit", depositing_donor)
	ai.set("_pending_economy_rebalance_type", "food")
	ai.set("_pending_economy_rebalance_from_type", "gold")
	ai.set("_pending_economy_rebalance_deadline", float(ai.get("_game_time")) + 18.0)
	var rebalance_orders_before_deposit: int = int(
		(ai.call("get_strategy_snapshot") as Dictionary).get("economy_rebalance_orders", 0)
	)
	depositing_donor.emit_signal("resource_deposited", "gold", 7)
	_expect(bool(ai.get("_economy_rebalance_deferred_scheduled")), "matching deposit schedules one deferred pending-rebalance service")
	# Mirrors Villager._deposit_resources() and its caller after the synchronous
	# signal returns: cargo clears, then the prior gather order resumes.
	depositing_donor.set("carried_amount", 0)
	depositing_donor.call("set_state", STATE_GATHERING)
	await process_frame
	_expect_eq(str(depositing_donor.get("carried_resource_type")), "food", "post-deposit deferred service reassigns the pending donor")
	_expect(depositing_donor.get("gather_target") == resource, "post-deposit rebalance uses only the currently visible food target")
	_expect_eq(int(depositing_donor.get("carried_amount")), 0, "post-deposit rebalance preserves the completed zero-cargo transaction")
	snapshot = ai.call("get_strategy_snapshot")
	_expect_eq(
		int(snapshot.get("economy_rebalance_orders", 0)),
		rebalance_orders_before_deposit + 1,
		"deposit callback services exactly one pending rebalance order"
	)
	_expect_eq(str(snapshot.get("economy_rebalance_pending", "unexpected")), "", "deposit callback clears the fulfilled pending request")
	depositing_donor.free()
	ai.call("_cleanup_references")

	# Remove the resource while hidden. Recovery may revisit only its last known
	# position; it must neither validate the freed object nor redirect from hidden
	# state. The mock itself also proves hidden lookup guards run first.
	var remembered_position: Vector2 = resource.global_position
	recovery_map.resource_visible = false
	recovery_map.visible_resource = null
	villager.call("_clear_gather_target_knowledge")
	villager.call("set_state", STATE_IDLE)
	recovery_map.remove_child(resource)
	resource.free()
	ai.call("_assign_idle_villagers")
	_expect_eq(int(villager.get("current_state")), STATE_MOVING, "hidden removal preserves a position-only recovery order")
	_expect_vector_approx(villager.get("move_target") as Vector2, remembered_position, "hidden removal revisits only the last legal sighting")
	snapshot = ai.call("get_strategy_snapshot")
	_expect_eq(int(snapshot.get("economy_memory_revisit_orders", 0)), 1, "memory revisit is exposed in strategy telemetry")
	_expect_eq(str(snapshot.get("last_economy_action", "")), "revisit_food", "telemetry identifies the remembered resource type")
	_expect(recovery_map.hidden_lookup_count > 0, "hidden resource lookup exits through the visibility guard")

	# Reaching/revealing the empty remembered tile invalidates memory from fog
	# state alone, then the finite sweep continues to a new destination.
	var remembered_tile: Vector2i = recovery_map.world_to_tile(remembered_position)
	recovery_map.visible_empty_tiles[remembered_tile] = true
	villager.call("set_state", STATE_IDLE)
	ai.call("_assign_idle_villagers")
	snapshot = ai.call("get_strategy_snapshot")
	_expect_eq(int(snapshot.get("resource_memory_count", -1)), 0, "visible empty tile retires stale resource memory")
	_expect_eq(str(snapshot.get("last_economy_action", "")), "explore", "empty remembered site resumes the deterministic sweep")
	_expect((villager.get("move_target") as Vector2).distance_to(remembered_position) > 1.0, "stale memory cannot trap workers at a depleted site")

	# The search plan itself is finite and all entries are geometry-derived.
	var waypoint_count: int = int(snapshot.get("economy_exploration_waypoint_count", 0))
	var waypoint_bound: int = ceili(float(MapData.MAP_WIDTH - 4) / 5.0) * ceili(float(MapData.MAP_HEIGHT - 4) / 5.0)
	_expect(waypoint_count > 0 and waypoint_count <= waypoint_bound, "economy exploration has a finite map-covering bound")
	for world_position_variant: Variant in ai.get("_economy_exploration_waypoints"):
		var world_position: Vector2 = world_position_variant as Vector2
		_expect(_is_in_bounds(recovery_map.world_to_tile(world_position)), "every economy waypoint stays in bounds")

	# Farm recovery uses ordinary construction transactions on fully visible
	# terrain. No natural food is visible when the intents are chosen: the
	# starting TC already supplies cap, so Farm precedes Barracks and all support
	# camps. Once the
	# owned farm is registered and active, its completion callback assigns one
	# safe worker through the same visibility-gated reachable lookup.
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 0, "wood": 200, "gold": 406})
	game_manager.players[PLAYER_AI]["population"] = 4
	game_manager.players[PLAYER_AI]["population_cap"] = 10
	ai.set("_saving_for_age_up", false)
	ai.set("_timed_age_up_reserve_active", false)
	ai.set("_farm_count", 0)
	ai.set("_feudal_paid_farm_foundations", 0)
	(ai.get("_feudal_paid_farm_foundation_ids") as Dictionary).clear()
	ai.set("_barracks_count", 0)
	for y in range(base_tile.y - 4, base_tile.y + 5):
		for x in range(base_tile.x - 4, base_tile.x + 5):
			recovery_map.visible_empty_tiles[Vector2i(x, y)] = true
	recovery_map.resource_visible = false
	recovery_map.visible_resource = null
	villager.call("_clear_gather_target_knowledge")
	villager.set("carried_amount", 0)
	villager.set("carried_resource_type", "")
	villager.call("set_state", STATE_IDLE)
	var loaded_idle: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position + Vector2(24.0, 0.0)
	)
	recovery_map.add_child(loaded_idle)
	loaded_idle.set("carried_amount", 7)
	loaded_idle.set("carried_resource_type", "wood")
	loaded_idle.call("set_state", STATE_IDLE)
	ai.call("register_unit", loaded_idle)
	var opening_scout: Node = _spawn_fixture(
		SCOUT_SCENE_PATH,
		PLAYER_AI,
		base_position + Vector2(32.0, 0.0)
	)
	recovery_map.add_child(opening_scout)
	ai.call("register_unit", opening_scout)
	# Main provisionally registers a foundation before its second builder preflight.
	# Its cancellation path unregisters and refunds; that failed transaction must
	# not satisfy cumulative paid Farm capacity.
	var cancelled_farm: Node = _spawn_fixture(
		FARM_SCENE_PATH,
		PLAYER_AI,
		base_position + Vector2(64.0, 0.0)
	)
	recovery_map.add_child(cancelled_farm)
	var farm_cost: Dictionary = BuildingData.get_building_cost(BuildingData.BuildingType.FARM)
	_expect(bool(resource_manager.call("try_spend", PLAYER_AI, farm_cost)), "cancel fixture provisionally spends the ordinary Farm cost")
	ai.call("register_building", cancelled_farm)
	_expect_eq(int(ai.get("_feudal_paid_farm_foundations")), 1, "provisionally registered Farm is tracked once")
	ai.call("unregister_building", cancelled_farm)
	resource_manager.call("refund", PLAYER_AI, farm_cost)
	_expect_eq(int(ai.get("_feudal_paid_farm_foundations")), 0, "cancelled/refunded Farm removes its provisional paid-capacity credit")
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), 200, "cancelled Farm restores the exact paid wood")
	cancelled_farm.free()
	# A synchronous Main builder-route rejection leaves the first tile buildable.
	# Consecutive proposals must therefore rotate to a deterministic alternative
	# instead of retrying the rejected site forever.
	var rejected_builder_sites: Dictionary = {}
	for attempt_index in range(12):
		var candidate_site: Vector2i = ai.call(
			"_find_build_location",
			BuildingData.BuildingType.FARM
		) as Vector2i
		_expect(candidate_site != Vector2i(-1, -1), "builder-rejection fixture finds visible candidate %d" % [attempt_index + 1])
		_expect(not rejected_builder_sites.has(candidate_site), "build-site cursor reaches candidate %d without cycling through its old prefix" % [attempt_index + 1])
		rejected_builder_sites[candidate_site] = true
	_expect_eq(rejected_builder_sites.size(), 12, "build-site cursor advances beyond the former eight-site retry limit")
	_expect_eq((ai.get("_build_site_search_cursors") as Dictionary).size(), 1, "build-site retry stores only one bounded scalar cursor per type")
	(ai.get("_build_site_search_cursors") as Dictionary).clear()
	# Watch Tower placement has an objective prefix followed by ordinary base
	# candidates. The same scalar cursor must cross that boundary without skipping
	# the beginning of the base domain.
	for visible_y in range(MapData.MAP_HEIGHT):
		for visible_x in range(MapData.MAP_WIDTH):
			recovery_map.visible_empty_tiles[Vector2i(visible_x, visible_y)] = true
	var sacred_fixture := SacredFixture.new()
	sacred_fixture.global_position = recovery_map.tile_to_world(Vector2i(20, 20))
	recovery_map.add_child(sacred_fixture)
	recovery_map.sacred_site = sacred_fixture
	var tower_footprint: Vector2i = BuildingData.get_building_stats(
		BuildingData.BuildingType.WATCH_TOWER
	).get("footprint", Vector2i(2, 2)) as Vector2i
	var sacred_candidates: Array = ai.call(
		"_collect_build_locations_near_tile",
		Vector2i(20, 20),
		tower_footprint,
		3,
		7
	) as Array
	var base_candidates: Array = ai.call(
		"_collect_build_locations_near_tile",
		base_tile,
		tower_footprint,
		3,
		15
	) as Array
	var expected_first_base_candidate: Vector2i = Vector2i(-1, -1)
	for base_candidate_variant: Variant in base_candidates:
		var base_candidate: Vector2i = base_candidate_variant as Vector2i
		if base_candidate not in sacred_candidates:
			expected_first_base_candidate = base_candidate
			break
	var boundary_candidate: Vector2i = ai.call(
		"_find_build_location_candidate",
		BuildingData.BuildingType.WATCH_TOWER,
		tower_footprint,
		sacred_candidates.size()
	) as Vector2i
	_expect(expected_first_base_candidate != Vector2i(-1, -1), "watch-tower fixture has a base candidate beyond the sacred prefix")
	_expect_eq(boundary_candidate, expected_first_base_candidate, "watch-tower cursor crosses from sacred candidates to the first deduplicated base site")
	recovery_map.sacred_site = null
	sacred_fixture.free()
	recovery_map.visible_empty_tiles.clear()
	for visible_y in range(base_tile.y - 4, base_tile.y + 5):
		for visible_x in range(base_tile.x - 4, base_tile.x + 5):
			recovery_map.visible_empty_tiles[Vector2i(visible_x, visible_y)] = true
	var hidden_lookups_before_farm: int = recovery_map.hidden_lookup_count
	var build_observation: Dictionary = {"intents": [], "farm": null}
	ai.connect("ai_wants_to_build", func(building_type: int, tile_pos: Vector2i, _is_rebuild: bool) -> void:
		var intents: Array = build_observation.get("intents", []) as Array
		intents.append(building_type)
		var cost: Dictionary = BuildingData.get_building_cost(building_type)
		if not bool(resource_manager.call("try_spend", PLAYER_AI, cost)):
			return
		if building_type != BuildingData.BuildingType.FARM:
			return
		var farm: Node2D = _spawn_fixture(
			FARM_SCENE_PATH,
			PLAYER_AI,
			recovery_map.tile_to_world(tile_pos)
		) as Node2D
		recovery_map.add_child(farm)
		recovery_map.call("register_harvestable", farm)
		recovery_map.resource_visible = true
		ai.call("register_building", farm)
		farm.call("start_construction")
		farm.call("complete_instantly")
		build_observation["farm"] = farm
	)
	var normal_age_one_order: Array = ai.call("_get_build_order", 1) as Array
	_expect_eq(int(normal_age_one_order[1]), BuildingData.BuildingType.FARM, "normal Age-I build order puts Farm immediately after demand-driven House")
	ai.set("_is_under_pressure", true)
	var pressured_age_one_order: Array = ai.call("_get_build_order", 1) as Array
	_expect_eq(int(pressured_age_one_order[1]), BuildingData.BuildingType.FARM, "pressure Age-I build order still preserves the food opening")
	ai.set("_is_under_pressure", false)
	ai.call("_check_house_need")
	ai.call("_check_building_construction")
	await process_frame
	var build_intents: Array = build_observation.get("intents", []) as Array
	_expect_eq(build_intents.size(), 1, "starting TC population room avoids an unnecessary opening House")
	if not build_intents.is_empty():
		_expect_eq(int(build_intents[0]), BuildingData.BuildingType.FARM, "first real Age-I intent is the food-producing Farm")
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), 125, "opening Farm spends its normal 75 wood cost")
	var built_farm: Node = build_observation.get("farm") as Node
	_expect(built_farm != null and is_instance_valid(built_farm), "no-visible-natural-food path creates a real Farm")
	_expect_eq(int(ai.get("_feudal_paid_farm_foundations")), 1, "accepted paid Farm foundation advances cumulative Feudal capacity once")
	if built_farm != null and is_instance_valid(built_farm):
		_expect(recovery_map.registered_harvestables.has(built_farm), "Farm enters the normal harvestable registry")
		_expect(bool(built_farm.call("is_harvestable_by", PLAYER_AI)), "active Farm is harvestable by its owner")
		_expect(not bool(built_farm.call("is_harvestable_by", PLAYER_HUMAN)), "active Farm cannot leak food to the opponent")
		_expect(villager.get("gather_target") == built_farm, "Farm completion assigns a safe worker to the registered food source")
	_expect_eq(int(villager.get("current_state")), STATE_GATHERING, "Farm completion resumes real food gathering")
	_expect_eq(int(loaded_idle.get("carried_amount")), 7, "Farm completion never retasks an idle worker holding cargo")
	_expect_eq(str(loaded_idle.get("carried_resource_type")), "wood", "Farm completion cannot convert interrupted cargo into food")
	# A completed paid Farm must retain its exact assignment identity. A nearer
	# natural food node cannot absorb the recovery worker; loaded gatherers deliver
	# their old cargo first through the normal transaction-safe command path.
	var nearer_natural_food: Node2D = _spawn_fixture(
		RESOURCE_SCENE_PATH,
		-1,
		base_position + Vector2(8.0, 0.0)
	) as Node2D
	nearer_natural_food.set("resource_type", "food")
	recovery_map.add_child(nearer_natural_food)
	recovery_map.reachable_resource_override = nearer_natural_food
	var loaded_farm_worker: Node = _spawn_fixture(
		VILLAGER_SCENE_PATH,
		PLAYER_AI,
		base_position
	)
	recovery_map.add_child(loaded_farm_worker)
	loaded_farm_worker.set("carried_resource_type", "gold")
	loaded_farm_worker.set("carried_amount", 7)
	loaded_farm_worker.call("set_state", STATE_GATHERING)
	ai.call("register_unit", loaded_farm_worker)
	var farm_recovery_gold_before: int = int(cargo_dropoff.deposits.get("gold", 0))
	if built_farm != null and is_instance_valid(built_farm):
		ai.call("_assign_safe_worker_to_completed_farm", built_farm)
		_expect_eq(
			int(loaded_farm_worker.get("_pending_gather_last_known_instance_id")),
			built_farm.get_instance_id(),
			"loaded recovery worker commits to the exact completed Farm, not nearer natural food"
		)
		loaded_farm_worker.call("_on_arrived_for_dropoff", loaded_farm_worker)
		_expect(loaded_farm_worker.get("gather_target") == built_farm, "completed Farm becomes the gather target after exact old-cargo delivery")
		_expect(loaded_farm_worker.get("gather_target") != nearer_natural_food, "nearer natural food cannot replace the completed Farm assignment")
		_expect_eq(
			int(cargo_dropoff.deposits.get("gold", 0)),
			farm_recovery_gold_before + 7,
			"Farm recovery deposits the loaded worker's exact old gold cargo"
		)
	loaded_farm_worker.free()
	ai.call("_cleanup_references")
	recovery_map.remove_child(nearer_natural_food)
	nearer_natural_food.free()
	recovery_map.reachable_resource_override = null
	# The paid Scout is one of three required policy-floor military units, so Farm
	# 1 preserves the remaining wood for Barracks. Once that foundation exists,
	# paid Farms 2 and 3 follow; no support building can intervene.
	ai.set("_saving_for_age_up", true)
	ai.set("_timed_age_up_reserve_active", true)
	# House 1 provides cap 15, exactly covering 12 villagers + 3 military. While
	# paid Barracks/Farms still need wood, the ordinary two-slot buffer must not
	# spend 50 wood at pop 13; a truly insufficient cap remains actionable.
	game_manager.players[PLAYER_AI]["population"] = 13
	game_manager.players[PLAYER_AI]["population_cap"] = 15
	build_intents.clear()
	ai.call("_check_house_need")
	_expect_eq(build_intents.size(), 0, "timed reserve suppresses proactive House 2 when cap covers both liveness floors")
	game_manager.players[PLAYER_AI]["population_cap"] = 14
	ai.call("_check_house_need")
	_expect_eq(build_intents.size(), 1, "timed reserve still requests a House when cap cannot fit both liveness floors")
	if not build_intents.is_empty():
		_expect_eq(int(build_intents[0]), BuildingData.BuildingType.HOUSE, "capacity safety request remains a real House intent")
	game_manager.players[PLAYER_AI]["population"] = 4
	game_manager.players[PLAYER_AI]["population_cap"] = 10
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 0, "wood": 125, "gold": 406})
	build_intents.clear()
	ai.call("_check_building_construction")
	_expect_eq(build_intents.size(), 0, "125 wood is preserved for Barracks while the force floor is unmet")
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), 125, "unmet force floor spends no support or extra-Farm wood")
	resource_manager.call("add_resource", PLAYER_AI, "wood", 25)
	ai.call("_check_building_construction")
	_expect_eq(build_intents.size(), 1, "opening resumes construction when the Barracks cost is earned")
	if not build_intents.is_empty():
		_expect_eq(int(build_intents[0]), BuildingData.BuildingType.BARRACKS, "first Barracks precedes Farm 2 for the three-unit floor")
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), 0, "Barracks spends its normal 150 wood cost")
	ai.set("_barracks_count", 1)
	build_intents.clear()
	ai.call("_check_building_construction")
	_expect_eq(build_intents.size(), 0, "zero wood after Barracks cannot issue Farm 2 or support")
	resource_manager.call("add_resource", PLAYER_AI, "wood", 75)
	ai.call("_check_building_construction")
	_expect_eq(build_intents.size(), 1, "opening issues Farm 2 when its exact cost is earned")
	if not build_intents.is_empty():
		_expect_eq(int(build_intents[0]), BuildingData.BuildingType.FARM, "Farm 2 follows the registered Barracks foundation")
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), 0, "two Farms and Barracks spend exactly their normal 300 wood total")
	# The fixture does not spawn a Barracks node; retain the already-observed
	# foundation count after Farm registration recomputes real fixture counts.
	ai.set("_barracks_count", 1)
	build_intents.clear()
	resource_manager.call("add_resource", PLAYER_AI, "wood", 75)
	ai.call("_check_building_construction")
	_expect_eq(build_intents.size(), 1, "opening issues Farm 3 when its exact cost is earned")
	if not build_intents.is_empty():
		_expect_eq(int(build_intents[0]), BuildingData.BuildingType.FARM, "Farm 3 completes the paid Feudal food capacity")
	_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, "wood")), 0, "three Farms and Barracks spend exactly their normal 375 wood total")
	build_intents.clear()
	ai.call("_check_building_construction")
	_expect_eq(build_intents.size(), 0, "pre-age opening never requests Farm 4")
	var timed_build_targets: Dictionary = ai.call("_get_target_building_counts", 1) as Dictionary
	_expect_eq(int(timed_build_targets.get(BuildingData.BuildingType.FARM, 0)), 3, "timed Feudal reserve funds three finite Farms")
	snapshot = ai.call("get_strategy_snapshot")
	_expect_eq(int(snapshot.get("farm_count", 0)), 3, "strategy telemetry counts all registered Farm foundations")
	_expect_eq(int(snapshot.get("feudal_paid_farm_foundations", 0)), 3, "strategy telemetry retains all paid pre-Feudal Farm foundations")
	_expect_eq(int(snapshot.get("feudal_paid_farm_foundations_remaining", -1)), 0, "paid-capacity telemetry proves the temporary wood latch can release")
	_expect_eq(int(snapshot.get("feudal_farm_capacity_target", 0)), 3, "strategy telemetry exposes the paid Farm capacity for the Feudal budget")
	_expect_eq(str(snapshot.get("last_economy_action", "")), "farm_recovery_food", "strategy telemetry identifies Farm-based food recovery")
	_expect_eq(recovery_map.hidden_buildability_queries, 0, "buildability is never queried before the full footprint is visible")
	_expect(recovery_map.buildability_queries > 0, "visible footprint uses the normal buildability API")
	_expect_eq(recovery_map.hidden_lookup_count, hidden_lookups_before_farm, "Farm opening does not query a hidden natural resource")
	if built_farm != null and is_instance_valid(built_farm):
		ai.call("_on_ai_building_destroyed", built_farm)
		_expect_eq(int(ai.get("_feudal_paid_farm_foundations")), 3, "accepted Farm capacity remains cumulative after finite depletion/destruction")
	opening_scout.free()
	ai.call("_cleanup_references")

	# Repeated decision ticks use a real production queue. The committed
	# living-plus-queued gate must stop exactly at the Medium three-unit pre-age
	# floor, rather than filling the queue and spending food reserved for Feudal.
	resource_manager.call("initialize_player", PLAYER_AI, {"food": 1000, "wood": 1000, "gold": 1000})
	game_manager.players[PLAYER_AI]["population"] = 0
	var barracks: Node = _spawn_fixture(BARRACKS_SCENE_PATH, PLAYER_AI, base_position + Vector2(96.0, 0.0))
	root.add_child(barracks)
	barracks.call("complete_instantly")
	ai.call("register_building", barracks)
	ai.connect("ai_wants_to_train", func(building: Node, unit_type: int) -> void:
		var production_queue: Node = building.call("get_production_queue") as Node
		if production_queue != null:
			production_queue.call("enqueue_unit", unit_type)
	)
	for _decision_tick in range(8):
		ai.call("_check_military_production")
	var barracks_queue: Node = barracks.call("get_production_queue") as Node
	_expect_eq(int(barracks_queue.call("get_queue_size")), 3, "repeated reserve ticks stop at the Medium pre-age force floor")
	_expect_eq(int(ai.call("_count_queued_military_units")), 3, "committed-military accounting includes all three queued Infantry")
	var warrior_cost: Dictionary = UnitData.get_unit_cost(UnitData.UnitType.INFANTRY)
	for resource_type in ["food", "wood", "gold"]:
		_expect_eq(int(resource_manager.call("get_resource", PLAYER_AI, resource_type)), 1000 - 3 * int(warrior_cost.get(resource_type, 0)), "queue gate spends exactly three Warrior %s costs" % resource_type)

	resource_manager.call("reset")
	_finish()


func _spawn_fixture(scene_path: String, owner: int, position: Vector2) -> Node:
	var fixture: Node = (load(scene_path) as PackedScene).instantiate()
	if fixture.get("player_owner") != null:
		fixture.set("player_owner", owner)
	fixture.set("global_position", position)
	_fixtures.append(fixture)
	return fixture


func _resource_memory_is_position_only(ai: Node) -> bool:
	var resource_memory: Dictionary = ai.get("_resource_memory") as Dictionary
	for memories_variant: Variant in resource_memory.values():
		for memory_variant: Variant in memories_variant as Array:
			var memory: Dictionary = memory_variant as Dictionary
			for value: Variant in memory.values():
				if typeof(value) == TYPE_OBJECT:
					return false
	return true


func _is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < MapData.MAP_WIDTH and tile.y >= 0 and tile.y < MapData.MAP_HEIGHT


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] ai_economy_recovery: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_vector_approx(actual: Vector2, expected: Vector2, message: String) -> void:
	_expect(actual.distance_to(expected) <= 0.01, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	for fixture: Variant in _fixtures:
		if typeof(fixture) == TYPE_OBJECT and is_instance_valid(fixture):
			(fixture as Node).free()
	if _failures.is_empty():
		print("[PASS] ai_economy_recovery: fog-safe recovery, transaction-safe cargo, and paid build order")
		quit(0)
	else:
		quit(1)
