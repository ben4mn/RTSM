extends SceneTree
## Controlled regression for workers that cannot leave their current tile.
## Movement, gathering and depositing use real Villagers; visibility and route
## rejection are explicit fixture setup, not ordinary-match balance evidence.

var failures: Array[String] = []

class SearchMap extends Node2D:
	var blocked_position := Vector2.ZERO
	var block_routes: bool = true
	var visible_tiles: Dictionary = {}
	var resource: Node2D
	var route_checks: int = 0
	var hidden_guards: int = 0

	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2(float(tile.x - tile.y) * 32.0, float(tile.x + tile.y) * 16.0)

	func world_to_tile(position: Vector2) -> Vector2i:
		return Vector2i(roundi((position.x / 32.0 + position.y / 16.0) * 0.5), roundi((position.y / 16.0 - position.x / 32.0) * 0.5))

	func is_tile_visible_to_player(tile: Vector2i, _owner: int = 0) -> bool:
		return visible_tiles.has(tile)

	func is_entity_visible_to_player(entity: Node2D, owner: int = 0) -> bool:
		return entity.get("player_owner") == owner or is_tile_visible_to_player(world_to_tile(entity.global_position), owner)

	func get_navigation_world_path(from: Vector2, target: Vector2, _radius: float = 4.0, _goal_radius: int = 6) -> PackedVector2Array:
		route_checks += 1
		return PackedVector2Array() if block_routes and from.distance_to(blocked_position) < 2.0 else PackedVector2Array([from, target])

	func get_nearest_resource_node(kind: String, from: Vector2, owner: int = -1) -> Node2D:
		return get_nearest_reachable_resource_node(kind, from, owner)

	func get_nearest_reachable_resource_node(kind: String, from: Vector2, owner: int = -1, excluded: Dictionary = {}) -> Node2D:
		# The fixture knows the resource location, but exposes no resource property
		# or stock to AI/Villager until the location has current vision.
		if resource == null or not is_tile_visible_to_player(world_to_tile(resource.global_position), owner):
			hidden_guards += 1
			return null
		if block_routes and from.distance_to(blocked_position) < 2.0:
			return null
		if excluded.has(resource.get_instance_id()) or resource.get_resource_type() != kind or not resource.is_harvestable_by(owner):
			return null
		return resource

class Dropoff extends Node2D:
	var player_owner: int = 1
	var wood_deposited: int = 0

	func get_player_owner() -> int:
		return player_owner

	func is_drop_off_point(_kind: String) -> bool:
		return true

	func deposit_resource(kind: String, amount: int) -> void:
		if kind == "wood":
			wood_deposited += amount
		get_tree().root.get_node("ResourceManager").add_resource(player_owner, kind, amount)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("AudioManager").set_all_enabled(false)
	var manager: Node = root.get_node("GameManager")
	manager.selected_population_limit = 20
	manager.initialize_game(2)
	manager.players[1]["age"] = 2
	root.get_node("ResourceManager").initialize_player(1, {"food": 500, "wood": 0, "gold": 500})
	var map := SearchMap.new()
	root.add_child(map)
	var base_tile := Vector2i(64, 5)
	map.blocked_position = map.tile_to_world(base_tile)
	var ai: Node = load("res://scripts/ai/ai_controller.gd").new()
	root.add_child(ai)
	ai.game_map = map
	ai.start_ai(base_tile, map.blocked_position)
	ai.get("_decision_timer").stop()
	ai.set_process(false)
	var trapped: Node = _worker(map, map.blocked_position)
	ai.register_unit(trapped)
	var total: int = int(ai.get_strategy_snapshot()["economy_exploration_waypoint_count"])
	var incidental_position: Vector2 = (ai.get("_economy_exploration_waypoints") as Array[Vector2])[-1]
	map.visible_tiles[map.world_to_tile(incidental_position)] = true
	ai.call("_refresh_economy_exploration")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_waypoints_remaining"]) == total, "incidental military vision cannot retire destinations before economy search examines them")
	map.visible_tiles.clear()
	# Many decisions across two complete old-style sweeps cannot exhaust points
	# that no worker has reached. Same-tick retries are also bounded by cooldown.
	for tick: int in range(total * 2):
		ai.set("_game_time", float(tick) * 1.5)
		trapped.command_stop()
		ai.call("_assign_idle_villagers")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_waypoints_remaining"]) == total, "trapped worker cannot globally retire unrevealed destinations")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_orders"]) == 0, "failed path preflights issue no exploration moves")
	var checks_before: int = map.route_checks
	for _retry: int in range(20):
		trapped.command_stop()
		ai.call("_assign_idle_villagers")
	_expect(map.route_checks == checks_before, "same-time decisions perform no additional failed route checks")
	_expect(map.route_checks <= ceili(float(total * 2) / 10.0) * 2, "failed search costs at most two path checks per fifteen seconds")
	var mobile: Node = _worker(map, map.blocked_position + Vector2(48.0, 0.0))
	ai.register_unit(mobile)
	ai.call("_assign_idle_villagers")
	_expect(mobile.current_state == 1, "another worker still receives a legal expansion trip")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_waypoints_remaining"]) == total, "issuing an accepted route does not mark its destination revealed")
	var first_target: Vector2 = mobile.move_target
	mobile.command_move(first_target + Vector2(8.0, 0.0))
	ai.call("_refresh_economy_exploration")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_active_workers"]) == 0, "a replacement Move releases the precise previous destination reservation")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_waypoints_remaining"]) == total, "interrupted travel preserves the unseen destination")
	ai.set("_game_time", float(ai.get("_game_time")) + 16.0)
	mobile.command_stop()
	ai.call("_assign_idle_villagers")
	var destination: Vector2 = mobile.move_target
	var wood: Node2D = load("res://scenes/map/resource_node.tscn").instantiate()
	wood.resource_type = "wood"
	wood.tile_position = map.world_to_tile(destination)
	wood.position = destination
	map.add_child(wood)
	wood.set_process(false)
	map.resource = wood
	var dropoff := Dropoff.new()
	dropoff.position = destination + Vector2(75.0, 0.0)
	map.add_child(dropoff)
	dropoff.add_to_group("dropoff_buildings")
	var revealed_before: bool = false
	for frame: int in range(60 * 120):
		# Only a worker's physical arrival creates vision in this fixture.
		if mobile.global_position.distance_to(destination) < 32.0:
			map.visible_tiles[wood.tile_position] = true
			revealed_before = true
		mobile.call("_process", 1.0 / 60.0)
		if frame % 90 == 0:
			ai.set("_game_time", float(ai.get("_game_time")) + 1.5)
			ai.call("_assign_idle_villagers")
		if dropoff.wood_deposited > 0:
			break
	_expect(revealed_before, "unblocked worker physically reaches an expansion destination")
	_expect(dropoff.wood_deposited == 10, "revealed expansion wood completes a real ten-wood gather and drop-off cycle")
	_expect(int(root.get_node("ResourceManager").get_resource(1, "wood")) == 10, "expansion deposit credits the bank through the ordinary resource transaction")
	_expect(int(ai.get_strategy_snapshot()["economy_exploration_waypoints_remaining"]) == total - 1, "only the currently revealed destination completes exploration")
	_expect(map.hidden_guards > 0, "hidden resource queries stop at the visibility guard")
	var report := {"failures": failures, "waypoint_count": total, "blocked_route_checks": checks_before, "expansion_wood_deposited": dropoff.wood_deposited, "strategy": ai.get_strategy_snapshot()}
	print("[", "PASS" if failures.is_empty() else "FAIL", "] ai_exploration_recovery ", JSON.stringify(report))
	ai.free()
	map.free()
	quit(0 if failures.is_empty() else 1)

func _worker(map: Node2D, position: Vector2) -> Node:
	var worker: Node = load("res://scenes/units/villager.tscn").instantiate()
	worker.player_owner = 1
	worker.position = position
	map.add_child(worker)
	worker.set_process(false)
	return worker

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
