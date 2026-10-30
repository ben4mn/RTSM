extends Node
## Beta 31 regression: "queued 7 Warriors, some never trained". Warriors use
## two housing; the paid queue took four and the rest were refused with a
## transient toast while the tile only greyed out. Every accepted unit must
## train, and a blocked Barracks tile must say why where its costs were.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.selected_difficulty = 1
	GameManager.selected_map_seed = 101
	GameManager.guided_opening_enabled = false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	var map: Node = main.get_node("GameMap")
	var hud: Node = main.get_node("HUD")
	main.get_node("AIController").set_process(false)
	var placement: BuildingPlacement = main.get("_building_placement")
	var anchor: Vector2i = map.get("map_generator").spawn_positions[0]
	var spot := Vector2.ZERO
	for radius: int in range(5, 12):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if spot == Vector2.ZERO and maxi(absi(dx), absi(dy)) == radius:
					var point: Vector2 = map.tile_to_world(anchor + Vector2i(dx, dy))
					if placement.revalidate_confirmation(BuildingData.BuildingType.BARRACKS, point, 0):
						spot = point
	ResourceManager.initialize_player(0, {"food": 2000, "wood": 2000, "gold": 2000})
	main.call("_on_placement_confirmed", BuildingData.BuildingType.BARRACKS, spot)
	var barracks: BuildingBase = main.get("_player_buildings")[0].back()
	_expect(barracks.building_type == BuildingData.BuildingType.BARRACKS, "fixture Barracks placed")
	barracks.complete_instantly()
	var queue: ProductionQueue = barracks.get_production_queue()
	var room: int = (int(GameManager.players[0].population_cap) - GameManager.get_committed_population(0)) / 2
	var results: Array[String] = []
	for tap: int in 7:
		main.call("_on_train_unit_requested", barracks, UnitData.UnitType.INFANTRY)
		results.append(str(main.get("_last_train_request_result")))
	_expect(queue.queue.size() == room, "queue took %d of 7, housing allows %d" % [queue.queue.size(), room])
	_expect(results.count("population_blocked") == 7 - room, "taps past housing must be refused for population: %s" % [results])
	_expect(str(main.get("_last_train_feedback")).contains("House"), "refusal must name the fix: " + str(main.get("_last_train_feedback")))
	map.get("selection_mgr").select_single(barracks)
	await get_tree().process_frame
	await get_tree().process_frame
	var tile: Button = hud.get("_train_buttons_container").get_node_or_null("TrainButton_%d" % UnitData.UnitType.INFANTRY)
	_expect(tile != null, "Barracks dock shows the Warrior tile")
	if tile != null:
		var status: Label = tile.get_node_or_null("TileStatus")
		_expect(status != null and status.visible and status.text == "Need House", "blocked Warrior tile must say Need House, got %s" % (status.text if status != null else "nothing"))
		_expect(not (tile.get_node("TileCosts") as Control).visible, "blocked tile swaps costs for its reason")
	# Holding to queue at the cap reports the same reason instead of stopping silently.
	main.set("_last_train_request_result", "")
	_expect(not bool(hud.call("_repeat_train", UnitData.UnitType.INFANTRY)), "hold-repeat stops at the cap")
	_expect(str(main.get("_last_train_request_result")) == "population_blocked", "hold-repeat stop must report the population block")
	var before: int = _warriors(main)
	for step: int in 1200:
		main.call("_advance_production_queues", 0.1)
		if step % 20 == 0:
			await get_tree().process_frame
	_expect(_warriors(main) - before == room, "every paid Warrior trains: %d of %d" % [_warriors(main) - before, room])
	_expect(queue.queue.is_empty() and int(GameManager.players[0].population_reserved) == 0, "queue and reservations drain")
	# A House clears the block: the tile shows costs again.
	GameManager.increase_population_cap(0, 20)
	var reselect: Array[Node2D] = [barracks]
	main.call("_on_selection_changed", reselect)
	await get_tree().process_frame
	if tile != null and is_instance_valid(tile):
		var status_after: Label = tile.get_node_or_null("TileStatus")
		_expect(status_after == null or not status_after.visible, "ready tile hides its reason")
		_expect((tile.get_node("TileCosts") as Control).visible, "ready tile shows its costs")
	for failure: String in _failures:
		push_error("[FAIL] queue_block_reason: " + failure)
	if _failures.is_empty():
		print("[PASS] queue_block_reason: paid Warriors all train; housing block named on tile and on hold")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _warriors(main: Node) -> int:
	var count := 0
	for unit: Variant in main.get("_player_units")[0]:
		if is_instance_valid(unit) and (unit as UnitBase).unit_type == UnitData.UnitType.INFANTRY:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
