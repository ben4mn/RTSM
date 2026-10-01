extends SceneTree
## Focused headless regression for queued-population accounting.

const TOWN_CENTER_SCENE_PATH := "res://scenes/buildings/town_center.tscn"
const BARRACKS_SCENE_PATH := "res://scenes/buildings/barracks.tscn"
const STABLE_SCENE_PATH := "res://scenes/buildings/stable.tscn"
const SIEGE_WORKSHOP_SCENE_PATH := "res://scenes/buildings/siege_workshop.tscn"
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const PLAYER_ID: int = 0
const STARTING_RESOURCE_AMOUNT: int = 5000
const UNIT_VILLAGER: int = 0
const UNIT_INFANTRY: int = 1
const UNIT_CAVALRY: int = 3
const UNIT_SCOUT: int = 4
const UNIT_SIEGE: int = 5
const READY_FRAME_LIMIT: int = 900

var _failures: Array[String] = []
var _trained_units: Array[int] = []
var _game_manager: Node
var _resource_manager: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game_manager = root.get_node("GameManager")
	_resource_manager = root.get_node("ResourceManager")
	_test_overflow_and_cross_building_reservations()
	_test_multi_slot_reservations()
	_test_cancellation_releases_exact_reservations()
	_test_completion_consumes_once()
	_test_building_and_queue_destruction_release_reservations()
	_test_stale_queue_cannot_release_a_new_match_reservation()
	_test_direct_spawn_and_unclaimed_completion()
	await _test_real_main_training_transaction()
	_finish()


func _test_overflow_and_cross_building_reservations() -> void:
	var villager_pop: int = _pop_cost(UNIT_VILLAGER)
	_reset_state(5 - villager_pop, 5)
	var fixture: Dictionary = _make_fixture(TOWN_CENTER_SCENE_PATH)
	var building: Node = fixture["building"]
	var production_queue: Node = fixture["queue"]
	var bank_before: Dictionary = _resource_bank()

	_expect(bool(production_queue.call("enqueue_unit", UNIT_VILLAGER)), "first unit should reserve the final population slot")
	for attempt in 4:
		_expect(not bool(production_queue.call("enqueue_unit", UNIT_VILLAGER)), "overflow enqueue %d should be rejected" % (attempt + 1))
	_expect_eq(production_queue.call("get_queue_size"), 1, "overflow leaves exactly one queued unit")
	_expect_eq(_population(), 5 - villager_pop, "enqueue does not create live population")
	_expect_eq(_reserved(), villager_pop, "enqueue reserves the unit's exact slot cost")
	_expect_eq(_game_manager.call("get_committed_population", PLAYER_ID), 5, "live plus reserved population reaches cap")
	_expect_spending(bank_before, UNIT_VILLAGER, 1, "rejected enqueues do not spend resources")
	_expect(not bool(_game_manager.call("add_population", PLAYER_ID, 1)), "direct spawns cannot steal a queued reservation")
	building.free()
	_expect_eq(_reserved(), 0, "freeing a queued building releases its reservation")

	var horseman_pop: int = _pop_cost(UNIT_CAVALRY)
	_reset_state(5 - horseman_pop, 5)
	var stable_fixture: Dictionary = _make_fixture(STABLE_SCENE_PATH)
	var barracks_fixture: Dictionary = _make_fixture(BARRACKS_SCENE_PATH)
	var stable_queue: Node = stable_fixture["queue"]
	var barracks_queue: Node = barracks_fixture["queue"]
	var shared_bank_before: Dictionary = _resource_bank()
	_expect(bool(stable_queue.call("enqueue_unit", UNIT_CAVALRY)), "Horseman reserves all remaining population slots")
	_expect(not bool(barracks_queue.call("enqueue_unit", UNIT_INFANTRY)), "a second building must see reservations from the first")
	_expect_eq(_reserved(), horseman_pop, "cross-building reservation total is authoritative")
	_expect_spending(shared_bank_before, UNIT_CAVALRY, 1, "cross-building rejection preserves every resource")
	(stable_fixture["building"] as Node).free()
	(barracks_fixture["building"] as Node).free()


func _test_multi_slot_reservations() -> void:
	# Siege remains a legacy three-slot unit even though the compact production
	# roster omits it. Retain coverage that reservations count slots, not bodies.
	var siege_pop: int = _pop_cost(UNIT_SIEGE)
	_expect(siege_pop > 1, "legacy Siege provides a meaningful multi-slot reservation case")
	_reset_state(5 - siege_pop, 5)
	var siege_fixture: Dictionary = _make_fixture(SIEGE_WORKSHOP_SCENE_PATH)
	var barracks_fixture: Dictionary = _make_fixture(BARRACKS_SCENE_PATH)
	var siege_queue: Node = siege_fixture["queue"]
	var bank_before: Dictionary = _resource_bank()
	_expect(bool(siege_queue.call("enqueue_unit", UNIT_SIEGE)), "multi-slot unit reserves the full remaining capacity")
	_expect_eq(_reserved(), siege_pop, "one queued Siege body reserves its data-defined multiple slots")
	_expect(not bool((barracks_fixture["queue"] as Node).call("enqueue_unit", UNIT_INFANTRY)), "another queue cannot steal one slot from a multi-slot reservation")
	_expect_spending(bank_before, UNIT_SIEGE, 1, "rejected overflow preserves Siege's single paid cost")
	_expect(bool(siege_queue.call("cancel_unit", 0)), "multi-slot cancellation succeeds")
	_expect_eq(_reserved(), 0, "multi-slot cancellation releases every reserved slot")
	_expect_spending(bank_before, UNIT_SIEGE, 0, "multi-slot cancellation refunds food, wood and gold exactly once")
	(siege_fixture["building"] as Node).free()
	(barracks_fixture["building"] as Node).free()


func _test_cancellation_releases_exact_reservations() -> void:
	_reset_state(2, 5)
	var fixture: Dictionary = _make_fixture(BARRACKS_SCENE_PATH)
	var building: Node = fixture["building"]
	var production_queue: Node = fixture["queue"]
	var bank_before: Dictionary = _resource_bank()

	for index in 3:
		_expect(bool(production_queue.call("enqueue_unit", UNIT_INFANTRY)), "cancellation setup enqueue %d succeeds" % index)
	_expect_eq(_reserved(), 3, "three queued infantry reserve three slots")
	_expect_spending(bank_before, UNIT_INFANTRY, 3, "three queued Warriors each spend their cost once")
	production_queue.set("current_progress", 5.0)
	_expect(bool(production_queue.call("cancel_unit", 1)), "cancelling a non-head entry succeeds")
	_expect_eq(_reserved(), 2, "non-head cancellation releases one slot")
	_expect_spending(bank_before, UNIT_INFANTRY, 2, "non-head cancellation refunds exactly its own cost")
	_expect_eq(production_queue.get("current_progress"), 5.0, "non-head cancellation preserves head progress")
	_expect(bool(production_queue.call("cancel_unit", 0)), "cancelling the head entry succeeds")
	_expect_eq(_reserved(), 1, "head cancellation releases only its slot")
	_expect_spending(bank_before, UNIT_INFANTRY, 1, "head cancellation refunds exactly its own cost")
	_expect_eq(production_queue.get("current_progress"), 0.0, "new head restarts at zero progress")
	_expect(bool(production_queue.call("cancel_unit", 0)), "cancelling the final entry succeeds")
	_expect_eq(_reserved(), 0, "all cancellations release all reservations")
	_expect_eq(_population(), 2, "cancellation never changes live population")
	_expect_spending(bank_before, UNIT_INFANTRY, 0, "all cancellations refund every resource exactly once")
	_expect(not bool(production_queue.call("cancel_unit", 0)), "repeated cancellation of an empty queue is rejected")
	_expect_eq(_reserved(), 0, "invalid cancellation cannot underflow reservations")
	building.free()


func _test_completion_consumes_once() -> void:
	var horseman_pop: int = _pop_cost(UNIT_CAVALRY)
	var population_before: int = 5 - horseman_pop
	_reset_state(population_before, 5)
	_trained_units.clear()
	var fixture: Dictionary = _make_fixture(STABLE_SCENE_PATH)
	var building: Node = fixture["building"]
	var production_queue: Node = fixture["queue"]
	production_queue.connect("unit_trained", Callable(self, "_record_trained_unit").bind(production_queue))
	production_queue.set("auto_queue_enabled", true)
	var bank_before: Dictionary = _resource_bank()

	_expect(bool(production_queue.call("enqueue_unit", UNIT_CAVALRY)), "completion setup reserves a Horseman at the population limit")
	_expect_eq(_population(), population_before, "training does not change live population before completion")
	_expect_eq(_reserved(), horseman_pop, "training holds the exact data-defined slot reservation")
	production_queue.call("_complete_current_unit")
	_expect_eq(_population(), 5, "completion converts the reservation to live population")
	_expect_eq(_reserved(), 0, "completion consumes the reservation")
	_expect_eq(production_queue.call("get_queue_size"), 0, "auto-queue is rejected when committed population is capped")
	_expect_eq(_trained_units, [UNIT_CAVALRY], "completion emits exactly one trained unit")
	_expect_spending(bank_before, UNIT_CAVALRY, 1, "failed capped repeat production does not spend food, wood or gold")
	production_queue.call("_complete_current_unit")
	_expect_eq(_population(), 5, "repeated completion cannot double-add population")
	_expect_eq(_trained_units.size(), 1, "repeated completion cannot emit another unit")
	_expect_spending(bank_before, UNIT_CAVALRY, 1, "repeated completion cannot spend a second unit cost")
	_game_manager.call("remove_population", PLAYER_ID, horseman_pop)
	_expect_eq(_population(), population_before, "unit death removes its exact live slot cost after reservation consumption")
	_expect_eq(_reserved(), 0, "unit death does not affect reservations")
	building.free()


func _test_building_and_queue_destruction_release_reservations() -> void:
	_reset_state(2, 5)
	var fixture: Dictionary = _make_fixture(BARRACKS_SCENE_PATH)
	var building: Node = fixture["building"]
	var production_queue: Node = fixture["queue"]
	for index in 3:
		_expect(bool(production_queue.call("enqueue_unit", UNIT_INFANTRY)), "destruction setup enqueue %d succeeds" % index)
	building.call("take_damage", int(building.get("max_hp")) + 1)
	_expect_eq(_reserved(), 0, "building_destroyed releases reservations immediately")
	_expect_eq(production_queue.call("get_queue_size"), 0, "building_destroyed clears the queue")
	_expect_eq(_population(), 2, "building destruction does not change live population")
	building.free()
	_expect_eq(_reserved(), 0, "later tree exit cannot double-release destroyed-building reservations")

	var replacement_fixture: Dictionary = _make_fixture(BARRACKS_SCENE_PATH)
	var replacement_building: Node = replacement_fixture["building"]
	var replacement_queue: Node = replacement_fixture["queue"]
	for index in 3:
		_expect(bool(replacement_queue.call("enqueue_unit", UNIT_INFANTRY)), "replacement queue reuses released slot %d" % index)
	_expect_eq(_reserved(), 3, "replacement queue owns all available reservations")
	replacement_queue.free()
	_expect_eq(_reserved(), 0, "freeing only the queue releases all of its reservations")
	replacement_building.free()


func _test_stale_queue_cannot_release_a_new_match_reservation() -> void:
	_reset_state(3, 5)
	var stale_fixture: Dictionary = _make_fixture(BARRACKS_SCENE_PATH)
	var stale_building: Node = stale_fixture["building"]
	var stale_queue: Node = stale_fixture["queue"]
	_expect(bool(stale_queue.call("enqueue_unit", UNIT_INFANTRY)), "stale queue setup reserves one slot")

	_reset_state(3, 5)
	var fresh_fixture: Dictionary = _make_fixture(BARRACKS_SCENE_PATH)
	var fresh_building: Node = fresh_fixture["building"]
	var fresh_queue: Node = fresh_fixture["queue"]
	_expect(bool(fresh_queue.call("enqueue_unit", UNIT_INFANTRY)), "new match queue reserves one slot")
	stale_building.free()
	_expect_eq(_reserved(), 1, "stale queue cleanup cannot release a new match reservation")
	fresh_building.free()
	_expect_eq(_reserved(), 0, "fresh queue releases its own reservation")


func _test_direct_spawn_and_unclaimed_completion() -> void:
	_reset_state(4, 5)
	var fixture: Dictionary = _make_fixture(TOWN_CENTER_SCENE_PATH)
	var building: Node = fixture["building"]
	var production_queue: Node = fixture["queue"]
	var bank_before: Dictionary = _resource_bank()
	_expect(bool(production_queue.call("enqueue_unit", UNIT_VILLAGER)), "spawn-failure setup reserves the final slot")
	var main_scene: PackedScene = load(MAIN_SCENE_PATH)
	var detached_main: Node = main_scene.instantiate()
	var blocked_spawn: Variant = detached_main.call("_spawn_unit", UNIT_VILLAGER, PLAYER_ID, Vector2.ZERO)
	_expect(blocked_spawn == null, "direct spawn is rejected while the final slot is reserved")
	_expect_eq(_population(), 4, "rejected direct spawn leaves live population unchanged")
	_expect_eq(_reserved(), 1, "rejected direct spawn leaves the queue reservation intact")

	production_queue.call("_complete_current_unit")
	_expect_eq(_population(), 4, "an unclaimed completion never commits live population")
	_expect_eq(_reserved(), 0, "an unclaimed completion releases its reservation")
	_expect_spending(bank_before, UNIT_VILLAGER, 0, "an unclaimed completion refunds its cost and preserves unrelated resources")
	building.free()
	detached_main.free()


func _test_real_main_training_transaction() -> void:
	var audio_manager: Node = root.get_node("AudioManager")
	audio_manager.call("set_all_enabled", false)
	var main_scene: PackedScene = load(MAIN_SCENE_PATH)
	var match_scene: Node = main_scene.instantiate()
	root.add_child(match_scene)
	current_scene = match_scene
	if not await _wait_for(func() -> bool:
		var players: Dictionary = _game_manager.get("players") as Dictionary
		var buildings_by_player: Array = match_scene.get("_player_buildings") as Array
		return (
			int(_game_manager.get("current_state")) == 2
			and players.has(PLAYER_ID)
			and not (buildings_by_player[PLAYER_ID] as Array).is_empty()
		)
	):
		_expect(false, "real main scene did not reach PLAYING")
		return

	var player_units: Array = (match_scene.get("_player_units") as Array)[PLAYER_ID]
	var player_buildings: Array = (match_scene.get("_player_buildings") as Array)[PLAYER_ID]
	var town_center: Node = null
	for building in player_buildings:
		if int(building.get("building_type")) == 0:
			town_center = building
			break
	if town_center == null:
		_expect(false, "real main scene has no player Town Center")
		match_scene.free()
		current_scene = null
		return

	var production_queue: Node = town_center.call("get_production_queue")
	var hud: Node = match_scene.get_node("HUD")
	var units_before: int = player_units.size()
	var population_before: int = _population()
	var stats_before: int = int(((match_scene.get("_stats") as Array)[PLAYER_ID] as Dictionary).get("units_trained", 0))
	var bank_before: Dictionary = _resource_bank()
	_expect_eq(int(hud.get("_population_current")), population_before, "HUD starts from live population when no slots are reserved")
	_expect(bool(production_queue.call("enqueue_unit", UNIT_SCOUT)), "real main Town Center queues a Scout")
	_expect_eq(_population(), population_before, "real queue keeps population inactive during training")
	_expect_eq(_reserved(), 1, "real queue reserves the Scout slot")
	_expect_eq(int(hud.get("_population_current")), population_before + 1, "HUD includes the queued Scout reservation")
	production_queue.call("_complete_current_unit")
	_expect_eq(_population(), population_before + 1, "real spawn consumes its reservation into live population")
	_expect_eq(_reserved(), 0, "real spawn leaves no reservation")
	_expect_eq(int(hud.get("_population_current")), population_before + 1, "HUD stays stable as the reservation becomes a live unit")
	_expect_eq(player_units.size(), units_before + 1, "real spawn adds exactly one tracked unit")
	_expect_spending(bank_before, UNIT_SCOUT, 1, "real successful spawn spends exactly one data-defined Scout cost")
	var stats_after: int = int(((match_scene.get("_stats") as Array)[PLAYER_ID] as Dictionary).get("units_trained", 0))
	_expect_eq(stats_after, stats_before + 1, "real spawn increments trained-unit stats once")

	var unit_scenes: Dictionary = match_scene.get("_unit_scenes") as Dictionary
	var scout_scene: PackedScene = unit_scenes[UNIT_SCOUT]
	unit_scenes.erase(UNIT_SCOUT)
	var units_before_failure: int = player_units.size()
	var population_before_failure: int = _population()
	var bank_before_failure: Dictionary = _resource_bank()
	var stats_before_failure: int = int(((match_scene.get("_stats") as Array)[PLAYER_ID] as Dictionary).get("units_trained", 0))
	_expect(bool(production_queue.call("enqueue_unit", UNIT_SCOUT)), "real spawn-failure setup reserves another Scout slot")
	_expect_eq(_reserved(), 1, "real spawn-failure setup owns one reservation")
	_expect_eq(int(hud.get("_population_current")), population_before_failure + 1, "HUD includes a reservation before a failed spawn")
	production_queue.call("_complete_current_unit")
	_expect_eq(_population(), population_before_failure, "real spawn failure never commits live population")
	_expect_eq(_reserved(), 0, "real spawn failure releases its reservation")
	_expect_eq(int(hud.get("_population_current")), population_before_failure, "HUD rolls back a reservation after spawn failure")
	_expect_eq(player_units.size(), units_before_failure, "real spawn failure adds no tracked unit")
	_expect_spending(bank_before_failure, UNIT_SCOUT, 0, "real spawn failure refunds every unit-cost resource exactly once")
	var stats_after_failure: int = int(((match_scene.get("_stats") as Array)[PLAYER_ID] as Dictionary).get("units_trained", 0))
	_expect_eq(stats_after_failure, stats_before_failure, "real spawn failure does not increment trained-unit stats")
	unit_scenes[UNIT_SCOUT] = scout_scene
	match_scene.free()
	current_scene = null


func _make_fixture(scene_path: String) -> Dictionary:
	var scene: PackedScene = load(scene_path)
	var building: Node = scene.instantiate()
	building.set("player_owner", PLAYER_ID)
	root.add_child(building)
	building.call("complete_instantly")
	var production_queue: Node = building.get_node("ProductionQueue")
	return {
		"building": building,
		"queue": production_queue,
	}


func _reset_state(active_population: int, population_cap: int) -> void:
	_game_manager.call("initialize_game", 1)
	_resource_manager.call("reset")
	_resource_manager.call("initialize_player", PLAYER_ID, {
		"food": STARTING_RESOURCE_AMOUNT,
		"wood": STARTING_RESOURCE_AMOUNT,
		"gold": STARTING_RESOURCE_AMOUNT,
	})
	var players: Dictionary = _game_manager.get("players") as Dictionary
	var base_cap: int = int(players[PLAYER_ID].get("population_cap", 5))
	if population_cap > base_cap:
		_game_manager.call("increase_population_cap", PLAYER_ID, population_cap - base_cap)
	_expect(bool(_game_manager.call("add_population", PLAYER_ID, active_population)), "test setup can add %d active population" % active_population)


func _record_trained_unit(unit_type: int, production_queue: Node) -> void:
	if bool(production_queue.call("consume_completed_population_reservation")):
		_trained_units.append(unit_type)
	else:
		_expect(false, "successful spawn callback could not consume its reservation")


func _wait_for(predicate: Callable) -> bool:
	for _frame in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await process_frame
	return false


func _population() -> int:
	var players: Dictionary = _game_manager.get("players") as Dictionary
	return int(players[PLAYER_ID].get("population", 0))


func _reserved() -> int:
	return int(_game_manager.call("get_reserved_population", PLAYER_ID))


func _pop_cost(unit_type: int) -> int:
	return int(UnitData.UNITS[unit_type]["pop_cost"])


func _resource_bank() -> Dictionary:
	var bank: Dictionary = {}
	for resource: String in ["food", "wood", "gold"]:
		bank[resource] = int(_resource_manager.call("get_resource", PLAYER_ID, resource))
	return bank


func _expect_spending(bank_before: Dictionary, unit_type: int, paid_units: int, message: String) -> void:
	var cost: Dictionary = UnitData.get_unit_cost(unit_type)
	for resource: String in ["food", "wood", "gold"]:
		_expect_eq(int(_resource_manager.call("get_resource", PLAYER_ID, resource)), int(bank_before[resource]) - int(cost.get(resource, 0)) * paid_units, "%s (%s)" % [message, resource])


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] population_reservations: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_expect(false, "%s (expected %s, got %s)" % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] population_reservations: overflow, cancellation, completion, destruction, restart isolation, spawn failure, and real main spawn")
		quit(0)
	else:
		quit(1)
