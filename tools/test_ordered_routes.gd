extends Node
## Routes preview for units the player ordered without selecting them
## (rally births, workers panel), just like a selected unit's route.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	(main.get("ai_controller") as Node).set_process(false)
	var map: Node2D = main.get("game_map")
	var selection: SelectionManager = map.get("selection_mgr")
	var overlay: Node = map.get_node("CommandPaths")
	var tc: Node2D = main.get("_player_town_center")
	var villagers: Array[Villager] = []
	for unit: Node in main.get("_player_units")[0]:
		if unit is Villager:
			villagers.append(unit as Villager)
	selection.call("_clear_selection")
	await get_tree().process_frame
	_expect(overlay.call("get_display_routes").is_empty(), "no routes before any order")
	# A rally birth: not selected, walking to the Town Center's rally point.
	var destination: Vector2 = map.tile_to_world(map.world_to_tile(tc.global_position) + Vector2i(7, -5))
	main.call("_issue_production_rally", villagers[0], destination, null)
	for frame: int in 3:
		await get_tree().process_frame
	_expect(overlay.call("get_display_routes").size() >= 1, "an unselected rally birth previews its route")
	# A workers-panel style order goes through the worker Undo record.
	villagers[1].command_move(map.tile_to_world(map.world_to_tile(tc.global_position) + Vector2i(-6, 6)))
	main.get("_worker_order_undo").call("supersede", 0, [villagers[1]])
	await get_tree().process_frame
	_expect(overlay.call("get_display_routes").size() >= 2, "an unselected worker order previews its route too")
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 2400:
		await get_tree().process_frame
	_expect(overlay.call("get_display_routes").is_empty(), "previews fade after about two seconds")
	main.free()
	if _failures.is_empty():
		print("[PASS] ordered_routes: rally births and unselected worker orders preview their routes, then fade")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] ordered_routes: %s" % failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
