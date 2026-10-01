extends SceneTree
## Focused headless regression for nominal population-cap provider ownership.
##
## Exercises the manager ledger plus real Town Center/House lifecycle callbacks,
## including late providers, partial visibility at max, revoke order, and over-cap.

const MAIN_SCENE: String = "res://scenes/main/main.tscn"
const PLAYER_ID: int = 0
const HOUSE_TYPE: int = 1
const READY_FRAME_LIMIT: int = 900
const GAME_STATE_PLAYING: int = 2

var _failures: Array[String] = []
var _match_scene: Node = null
var _game_manager: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game_manager = root.get_node("GameManager")
	var audio_manager: Node = root.get_node("AudioManager")
	audio_manager.call("set_all_enabled", false)

	var packed: PackedScene = load(MAIN_SCENE)
	_match_scene = packed.instantiate()
	root.add_child(_match_scene)
	current_scene = _match_scene
	if not await _wait_for_match_ready():
		_fail("match did not reach PLAYING with initialized players")
		_finish()
		return

	# This ledger regression deliberately exercises providers at 190/195/200.
	# Mobile 20/30/40 budgets are covered separately by skirmish_population.
	var players: Dictionary = _game_manager.get("players")
	players[PLAYER_ID]["max_population"] = 200
	_expect_eq(_population_cap(), 10, "starting active Town Center contributes its nominal five slots")
	_test_unfinished_house_changes_nothing()
	await process_frame
	_test_manager_provider_idempotence()
	await process_frame
	_test_late_provider_fills_headroom_in_both_revoke_orders()
	await process_frame
	_test_partial_provider_retains_nominal_capacity()
	await process_frame
	_test_destroyed_house_can_leave_player_over_cap()
	await process_frame
	_finish()


func _test_unfinished_house_changes_nothing() -> void:
	var initial_cap: int = _population_cap()
	var house: Node = _spawn_house(Vector2i(8, 8))
	_expect(house != null, "unfinished House can be spawned")
	if house == null:
		return
	house.call("start_construction")
	_expect_eq(_population_cap(), initial_cap, "placing an unfinished House does not grant capacity")
	house.call("take_damage", 1)
	_expect_eq(_population_cap(), initial_cap, "destroying an unfinished House removes no capacity")
	house.call("take_damage", 1)
	_expect_eq(_population_cap(), initial_cap, "repeated damage after unfinished destruction remains a no-op")


func _test_manager_provider_idempotence() -> void:
	_set_effective_cap_without_temporary_providers(10)
	var provider_id: int = 9000001
	_expect_eq(
		int(_game_manager.call("grant_population_cap", PLAYER_ID, provider_id, 10)),
		10,
		"first provider registration exposes its nominal capacity"
	)
	_expect_eq(_population_cap(), 20, "first provider registration updates effective cap")
	_expect_eq(
		int(_game_manager.call("grant_population_cap", PLAYER_ID, provider_id, 50)),
		0,
		"duplicate provider registration is ignored"
	)
	_expect_eq(_population_cap(), 20, "duplicate provider cannot add capacity twice")
	_expect_eq(
		int(_game_manager.call("revoke_population_cap", provider_id)),
		10,
		"first provider revocation reports the visible decrease"
	)
	_expect_eq(_population_cap(), 10, "first provider revocation restores baseline")
	_expect_eq(
		int(_game_manager.call("revoke_population_cap", provider_id)),
		0,
		"duplicate provider revocation is ignored"
	)
	_expect_eq(_population_cap(), 10, "duplicate revocation cannot remove capacity twice")


func _test_late_provider_fills_headroom_in_both_revoke_orders() -> void:
	_set_effective_cap_without_temporary_providers(190)
	var first_house: Node = _spawn_house(Vector2i(12, 8))
	var late_house: Node = _spawn_house(Vector2i(16, 8))
	_expect(first_house != null and late_house != null, "late-provider House fixtures can be spawned")
	if first_house == null or late_house == null:
		return
	first_house.call("complete_instantly")
	_expect_eq(_population_cap(), 200, "first House reaches max population")
	late_house.call("complete_instantly")
	_expect_eq(_population_cap(), 200, "House completed at cap remains clamped")
	late_house.call("complete_instantly")
	_expect_eq(_population_cap(), 200, "duplicate completion cannot register the late House twice")
	first_house.call("take_damage", int(first_house.get("max_hp")))
	_expect_eq(_population_cap(), 200, "late House fills headroom when the earlier House is destroyed")
	late_house.call("take_damage", int(late_house.get("max_hp")))
	_expect_eq(_population_cap(), 190, "removing the final House restores the pre-House cap")
	late_house.call("take_damage", 1)
	_expect_eq(_population_cap(), 190, "duplicate destruction cannot revoke a provider twice")

	# Repeat in the opposite revoke order to prove provider identity/order does
	# not determine the resulting capacity.
	var earlier_survivor: Node = _spawn_house(Vector2i(20, 8))
	var later_destroyed: Node = _spawn_house(Vector2i(24, 8))
	_expect(earlier_survivor != null and later_destroyed != null, "reverse-order House fixtures can be spawned")
	if earlier_survivor == null or later_destroyed == null:
		return
	earlier_survivor.call("complete_instantly")
	later_destroyed.call("complete_instantly")
	_expect_eq(_population_cap(), 200, "reverse-order fixtures remain clamped at max")
	later_destroyed.call("take_damage", int(later_destroyed.get("max_hp")))
	_expect_eq(_population_cap(), 200, "earlier House keeps full cap when late House is revoked first")
	earlier_survivor.call("take_damage", int(earlier_survivor.get("max_hp")))
	_expect_eq(_population_cap(), 190, "reverse revoke order also restores the same baseline")


func _test_partial_provider_retains_nominal_capacity() -> void:
	_set_effective_cap_without_temporary_providers(195)
	var partial_house: Node = _spawn_house(Vector2i(28, 8))
	var capped_house: Node = _spawn_house(Vector2i(32, 8))
	_expect(partial_house != null and capped_house != null, "partial-provider House fixtures can be spawned")
	if partial_house == null or capped_house == null:
		return
	partial_house.call("complete_instantly")
	_expect_eq(_population_cap(), 200, "partial House exposes the five slots available below max")
	capped_house.call("complete_instantly")
	_expect_eq(_population_cap(), 200, "second House registers nominal capacity while at max")

	# Remove ten unowned slots while both providers are active, then remove the
	# capped House. The partial House must still contribute its full nominal ten;
	# storing only its originally visible five would incorrectly leave cap 190.
	_game_manager.call("decrease_population_cap", PLAYER_ID, 10)
	_expect_eq(_population_cap(), 200, "hidden provider capacity absorbs a ten-slot base reduction")
	capped_house.call("take_damage", int(capped_house.get("max_hp")))
	_expect_eq(_population_cap(), 195, "partial House retains all ten nominal slots after rebalance")
	partial_house.call("take_damage", int(partial_house.get("max_hp")))
	_expect_eq(_population_cap(), 185, "removing the partial House removes its full nominal contribution")


func _test_destroyed_house_can_leave_player_over_cap() -> void:
	_set_effective_cap_without_temporary_providers(10)
	_set_live_population_for_test(0)
	var house: Node = _spawn_house(Vector2i(36, 8))
	_expect(house != null, "over-cap scenario House can be spawned")
	if house == null:
		return
	house.call("complete_instantly")
	_expect_eq(_population_cap(), 20, "completed House grants its normal ten slots above the active Town Center")
	_expect(bool(_game_manager.call("add_population", PLAYER_ID, 19)), "live population can fill nineteen House-supported slots")
	var existing_reservation: int = int(_game_manager.call("reserve_population", PLAYER_ID, 1))
	_expect(existing_reservation > 0, "the final supported slot can be reserved")
	_expect_eq(int(_game_manager.call("get_committed_population", PLAYER_ID)), 20, "live plus reserved population reaches the old cap")

	house.call("take_damage", int(house.get("max_hp")))
	_expect_eq(_population_cap(), 10, "House destruction removes its full ten-slot nominal contribution")
	_expect_eq(_live_population(), 19, "House destruction does not kill existing units")
	_expect_eq(int(_game_manager.call("get_reserved_population", PLAYER_ID)), 1, "House destruction does not cancel an existing reservation")
	_expect_eq(int(_game_manager.call("get_committed_population", PLAYER_ID)), 20, "committed population may remain above the reduced cap")
	_expect_eq(int(_game_manager.call("reserve_population", PLAYER_ID, 1)), -1, "new reservations are blocked while over cap")

	_expect(bool(_game_manager.call("consume_population_reservation", existing_reservation)), "an existing reservation can still finish while over cap")
	_expect_eq(_live_population(), 20, "reservation completion converts the slot to live population")
	_expect_eq(int(_game_manager.call("reserve_population", PLAYER_ID, 1)), -1, "new reservations remain blocked after completion while over cap")
	_game_manager.call("remove_population", PLAYER_ID, 11)
	var recovered_reservation: int = int(_game_manager.call("reserve_population", PLAYER_ID, 1))
	_expect(recovered_reservation > 0, "new production resumes once committed population fits the reduced cap")
	if recovered_reservation > 0:
		_game_manager.call("release_population_reservation", recovered_reservation)


func _spawn_house(tile_position: Vector2i) -> Node:
	return _match_scene.call("_spawn_building", HOUSE_TYPE, PLAYER_ID, tile_position)


func _set_effective_cap_without_temporary_providers(target_cap: int) -> void:
	var current_cap: int = _population_cap()
	if target_cap > current_cap:
		_game_manager.call("increase_population_cap", PLAYER_ID, target_cap - current_cap)
	elif target_cap < current_cap:
		_game_manager.call("decrease_population_cap", PLAYER_ID, current_cap - target_cap)
	_expect_eq(_population_cap(), target_cap, "test setup reaches effective cap %d" % target_cap)


func _set_live_population_for_test(live_population: int) -> void:
	var players: Dictionary = _game_manager.get("players")
	var player: Dictionary = players[PLAYER_ID]
	player["population"] = live_population
	player["population_reserved"] = 0


func _population_cap() -> int:
	var players: Dictionary = _game_manager.get("players")
	return int((players[PLAYER_ID] as Dictionary).get("population_cap", -1))


func _live_population() -> int:
	var players: Dictionary = _game_manager.get("players")
	return int((players[PLAYER_ID] as Dictionary).get("population", -1))


func _wait_for_match_ready() -> bool:
	for _frame in range(READY_FRAME_LIMIT):
		var players: Dictionary = _game_manager.get("players")
		if int(_game_manager.get("current_state")) == GAME_STATE_PLAYING and not players.is_empty():
			return true
		await process_frame
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)


func _expect_eq(actual: int, expected: int, message: String) -> void:
	if actual == expected:
		return
	_fail("%s (expected %d, got %d)" % [message, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[FAIL] population_cap_building_loss: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] population_cap_building_loss: nominal providers, revoke order, idempotence, and reservations")
		quit(0)
		return
	print("[FAIL] population_cap_building_loss: %d assertion(s) failed" % _failures.size())
	quit(1)
