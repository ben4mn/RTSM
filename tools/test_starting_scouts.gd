extends Node
## Actual Main initialization and authoritative snapshot/replica paths. No sockets.
## Starts must remain symmetric without charging or consuming a production queue.

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	NetworkSession.set_process(false)
	for map_type: int in MapData.MAP_ARCHETYPES:
		for civilization: int in CivilizationData.ORDERED_IDS:
			for mode: int in [SkirmishData.MatchMode.STANDARD, SkirmishData.MatchMode.QUICK_CONTROL]:
				_configure(civilization, map_type, mode, false)
				var main: Node = await _open_match()
				var context := "solo map=%d civ=%d mode=%d" % [map_type, civilization, mode]
				_check_start(main, context)
				main.set("_guided_opening_active", true)
				main.set("_guided_stage", main.GuidedOpeningStage.BUILD_HOUSE)
				main.set("_opening_house_complete", true)
				main.call("_refresh_guided_opening_stage")
				_expect(main.get("_guided_stage") == main.GuidedOpeningStage.MOVE_MILITARY, context + " guide uses the available Scout")
				for unit: UnitBase in (main.get("_player_units")[0] as Array).duplicate():
					if unit.unit_type == UnitData.UnitType.SCOUT:
						unit.die()
				main.call("_refresh_guided_opening_stage")
				_expect(main.get("_guided_stage") == main.GuidedOpeningStage.TRAIN_SCOUT, context + " guide offers replacement after starter is lost")
				_close_match(main)
				await get_tree().process_frame
	# The map generator guarantees broad spawn clearings. Probe distant seeds
	# as well as the full rules/civilization matrix above to catch blocked exits.
	for seed_value: int in [1, 42, 424242, 2147483647]:
		for map_type: int in MapData.MAP_ARCHETYPES:
			_configure(seed_value % 3, map_type, SkirmishData.MatchMode.STANDARD, false)
			GameManager.selected_map_seed = seed_value
			var main: Node = await _open_match()
			_check_start(main, "seed=%d map=%d" % [seed_value, map_type])
			_close_match(main)
			await get_tree().process_frame
	# Every civilization occupies both server slots over these three pairings.
	for civilization: int in CivilizationData.ORDERED_IDS:
		_configure(civilization, civilization, SkirmishData.MatchMode.STANDARD, true)
		var authority: Node = await _open_match()
		_check_start(authority, "authority civ=%d" % civilization)
		var adapter: Node = NetworkSession.adapter
		adapter.call("_register_server_entities")
		var snapshots: Array[Dictionary] = []
		for slot: int in 2:
			var snapshot: Dictionary = adapter.call("_snapshot_for", slot)
			snapshots.append(snapshot)
			var scouts: Array = (snapshot.actors as Array).filter(func(actor: Dictionary) -> bool: return actor.owner == slot and actor.kind == "unit" and actor.type == UnitData.UnitType.SCOUT)
			_expect(scouts.size() == 1 and int(snapshot.player.population) == 5, "authority sends exactly one Scout and five population to slot %d" % slot)
		_close_match(authority)
		await get_tree().process_frame
		for slot: int in 2:
			NetworkSession.server_mode = false
			NetworkSession.player_slot = slot
			var client: Node = await _open_match()
			_expect((client.get("_player_units")[0] as Array).is_empty(), "client does not create its own starting actors")
			NetworkSession.adapter.call("apply_snapshot", snapshots[slot])
			NetworkSession.adapter.call("apply_snapshot", snapshots[slot])
			var scouts: Array = (client.get("_player_units")[0] as Array).filter(func(unit: UnitBase) -> bool: return unit.unit_type == UnitData.UnitType.SCOUT)
			_expect(scouts.size() == 1, "repeated snapshot creates one own Scout for slot %d civ %d" % [slot, civilization])
			_expect(int(GameManager.players[0].population) == 5, "replica keeps authoritative five population")
			if scouts.size() == 1:
				_expect(not scouts[0].can_process() and scouts[0].player_owner == 0, "replica Scout stays inert and maps to local owner")
				_expect(scouts[0].get("_sprite").texture.resource_path == KingdomArt.unit_path(GameManager.get_player_civilization(0), UnitData.UnitType.SCOUT), "replica Scout uses its civilization art")
			_close_match(client)
			await get_tree().process_frame
	NetworkSession.online = false
	NetworkSession.server_mode = false
	NetworkSession.player_slot = 0
	for failure: String in _failures:
		push_error("[FAIL] starting_scouts: " + failure)
	if _failures.is_empty():
		print("[PASS] starting_scouts: %d checks; 18 solo starts (3 maps x 3 civs x 2 modes), 12 extra map/seed probes, both owners, 3 authority starts and 6 slot-remapped client replicas, bank/cap/queue/egress and guided opening/loss" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _configure(civilization: int, map_type: int, mode: int, authority: bool) -> void:
	NetworkSession.online = authority
	NetworkSession.server_mode = authority
	NetworkSession.state = "idle"
	NetworkSession.match_seed = 101
	NetworkSession.match_map_archetype = map_type
	NetworkSession.match_civilizations = [civilization, (civilization + 1) % 3]
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = map_type
	GameManager.selected_civilization = civilization
	GameManager.selected_opponent_civilization = (civilization + 1) % 3
	GameManager.selected_population_limit = SkirmishData.POPULATION_OPTIONS[civilization]
	GameManager.selected_match_mode = mode
	GameManager.guided_opening_enabled = false
	if GameManager.has_meta("auto_solo_opponent"):
		GameManager.remove_meta("auto_solo_opponent")


func _open_match() -> Node:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 120:
		await get_tree().process_frame
		if main.get("_building_placement") != null:
			break
	_expect(main.get("_building_placement") != null, "match initialized")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	return main


func _check_start(main: Node, context: String) -> void:
	var map: Node = main.get_node("GameMap")
	for owner: int in 2:
		var units: Array = main.get("_player_units")[owner]
		var scouts: Array = units.filter(func(unit: UnitBase) -> bool: return unit.unit_type == UnitData.UnitType.SCOUT)
		var workers: Array = units.filter(func(unit: UnitBase) -> bool: return unit is Villager)
		_expect(scouts.size() == 1 and workers.size() == 4 and units.size() == 5, context + " four workers plus one Scout for owner %d" % owner)
		_expect(int(GameManager.players[owner].population) == 5 and int(GameManager.players[owner].population_reserved) == 0, context + " exact used population without queue reservation")
		_expect(int(GameManager.players[owner].population_cap) == 15 and GameManager.can_reserve_population(owner, 1), context + " unchanged TC housing leaves recruitment room")
		_expect(ResourceManager.get_all_resources(owner) == SkirmishData.STARTING_RESOURCES, context + " starting bank unchanged")
		_expect(int(main.get("_stats")[owner].units_trained) == 0, context + " initial Scout is not a paid recruitment statistic")
		var tc: BuildingBase = main.get("_player_buildings")[owner][0]
		_expect(tc.get_production_queue().get_queue_size() == 0, context + " no training queue consumed")
		if scouts.size() == 1:
			var scout: UnitBase = scouts[0]
			_expect(map.is_tile_walkable(map.world_to_tile(scout.global_position)), context + " Scout starts on walkable egress")
			var center_route: PackedVector2Array = map.get_navigation_world_path(scout.global_position, map.sacred_site.global_position, 40.0)
			_expect(not center_route.is_empty(), context + " Scout has a route into the battlefield")
			for worker: UnitBase in workers:
				_expect(scout.global_position.distance_to(worker.global_position) > 20.0, context + " Scout does not overlap a starting worker")
			_expect(scout.damage == 0.0, context + " starting Scout stays unarmed")


func _close_match(main: Node) -> void:
	NetworkSession.adapter = null
	main.free()
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.MENU)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
