extends SceneTree
## The first food objective must not advance when the player orders lumbering.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	root.get_node("AudioManager").call("set_all_enabled", false)
	gm.set("guided_opening_enabled", true)
	var match_scene: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(match_scene)
	current_scene = match_scene
	for _frame in range(900):
		if int(gm.get("current_state")) == 2 and not match_scene.get("_player_units")[0].is_empty():
			break
		await process_frame
	if match_scene.get("_player_units")[0].is_empty():
		_expect(false, "match did not become playable")
		_finish(match_scene)
		return

	var map: Node2D = match_scene.get_node("GameMap") as Node2D
	var villager: Node2D = match_scene.get("_player_units")[0][0] as Node2D
	map.get("selection_mgr").call("select_single", villager)
	match_scene.set("_opening_gather_complete", false)
	for resource_type: String in ["wood", "gold", "food"]:
		var fixture: Node2D = load("res://scenes/map/resource_node.tscn").instantiate() as Node2D
		fixture.set("resource_type", resource_type)
		fixture.set("tile_position", map.call("world_to_tile", villager.global_position))
		fixture.global_position = villager.global_position
		map.get_node("ResourcesContainer").add_child(fixture)
		match_scene.call("_on_gather_command", fixture)
		_expect(villager.get("gather_target") == fixture, "%s order did not reach the selected villager" % resource_type)
		_expect(bool(match_scene.get("_opening_gather_complete")) == (resource_type == "food"), "%s order incorrectly changed food-objective completion" % resource_type)
		villager.call("command_stop")
		fixture.free()

	_finish(match_scene)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[FAIL] guided_food_objective: %s" % message)


func _finish(match_scene: Node) -> void:
	match_scene.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] guided_food_objective: wood/gold orders retain food step; accepted food order advances")
		quit(0)
	else:
		quit(1)
