extends Node
## Beta 31: workers whose resource runs out with none in sight walk to the
## nearest one the player has explored (fog memory), fog-safely: position
## only, the hidden node is checked once its tile is back in sight.

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
	main.get_node("AIController").set_process(false)
	await get_tree().process_frame
	var map: Node = main.get_node("GameMap")
	var worker: Villager = null
	for unit: Variant in main.get("_player_units")[0]:
		if unit is Villager:
			worker = unit
			break
	var memory: Node = map.call("_ensure_fog_memory")
	# Pick the nearest hidden, unexplored tree with a reachable route.
	var target: ResourceNode = null
	var best: float = INF
	for tile: Vector2i in map.resource_nodes:
		var node: Variant = map.resource_nodes[tile]
		if not node is ResourceNode or (node as ResourceNode).resource_type != "wood":
			continue
		if map.is_tile_visible_to_player(tile, 0) or map.fog_of_war.is_explored(tile):
			continue
		var d: float = worker.global_position.distance_to((node as Node2D).global_position)
		if d < best and d > 400.0 and not map.get_navigation_world_path(worker.global_position, (node as Node2D).global_position, MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD).is_empty():
			best = d
			target = node
	_expect(target != null, "fixture needs a hidden tree")
	if target == null:
		_finish()
		return
	# Unexplored and unseen: nothing to remember, no fallback.
	_expect(memory.call("nearest_remembered_resource", "wood", worker.global_position, 0).get("id", 0) != target.get_instance_id(), "an unexplored tree is never remembered")
	# The player saw it once (scouted), then lost sight.
	map.fog_of_war.remember_explored(target.tile_position)
	memory.call("observe_resource", target)
	var seen: Dictionary = memory.call("nearest_remembered_resource", "wood", worker.global_position, 0)
	_expect(int(seen.get("id", 0)) == target.get_instance_id(), "the explored, out-of-sight tree is the nearest memory")
	# The AI never uses the player's memory.
	var enemy: Villager = null
	for unit: Variant in main.get("_player_units")[1]:
		if unit is Villager:
			enemy = unit
			break
	if enemy != null:
		_expect(not bool(enemy.call("_try_remembered_resource", map, "wood")), "AI workers never read the player's fog memory")
	_expect(bool(worker.call("_try_remembered_resource", map, "wood")), "worker accepts the remembered tree")
	_expect(worker.current_state == UnitBase.State.GATHERING and worker.gather_target == null and worker.get("_gather_last_known_instance_id") == target.get_instance_id(), "the order is position-only while the tree is hidden")
	var arrived: bool = false
	Engine.time_scale = 6.0
	for frame: int in 3600:
		await get_tree().physics_frame
		if worker.gather_target == target:
			arrived = true
			break
	Engine.time_scale = 1.0
	_expect(arrived, "the worker reaches the remembered tree and gathers that exact one (state %d)" % worker.current_state)
	_finish()


func _finish() -> void:
	for failure: String in _failures:
		push_error("[FAIL] remembered_resource: " + failure)
	if _failures.is_empty():
		print("[PASS] remembered_resource: explored out-of-sight trees are remembered fog-safely; workers walk to them; AI excluded")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
