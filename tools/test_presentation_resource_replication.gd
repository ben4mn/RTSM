extends SceneTree
## Real resource harvest -> production serializer -> JSON -> client handler.
## Controlled visibility/harvest amounts; no socket or paid-match claim.

var map_scene: PackedScene
var failures: Array[String] = []
var cases: Array[Dictionary] = []
var session: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("AudioManager").set_all_enabled(false)
	# SceneTree scripts load before autoload identifiers are registered.
	map_scene = load("res://scenes/map/game_map.tscn")
	session = root.get_node("NetworkSession")
	session.set_process(false)
	for archetype: int in range(3):
		for slot: int in range(2):
			await _case(archetype, slot)
	session.leave_match()
	if current_scene != null:
		current_scene.free()
		current_scene = null
	var output: String = "res://output/presentation-integrity/resources.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	var hashes: Dictionary = {}
	for path: String in ["scripts/map/resource_node.gd", "scripts/map/game_map.gd", "scripts/network/network_match.gd", "scripts/network/network_session.gd", "tools/test_presentation_resource_replication.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"scope": "Controlled real harvest, production serializer, JSON round-trip and actual client snapshot handler; no socket or paid economy claim", "source_hashes": hashes, "cases": cases, "failures": failures, "user_data_dir": OS.get_user_data_dir()}, "  "))
	for failure: String in failures: push_error("[FAIL] presentation_resource_replication: " + failure)
	if failures.is_empty(): print("[PASS] presentation_resource_replication: three maps/both slots; stock, partial harvest, hidden omission, depletion, deferred fog/minimap reveal, idempotence and unchanged shorelines")
	quit(0 if failures.is_empty() else 1)

func _case(archetype: int, slot: int) -> void:
	session.leave_match()
	var match_id: int = 90 + archetype * 2 + slot
	session._client_packet({"op": "matched", "slot": slot, "seed": 101, "match": match_id, "map_archetype": archetype, "civilizations": [0, 0]})
	for frame: int in range(900):
		await process_frame
		if is_instance_valid(session.adapter): break
	_check(is_instance_valid(session.adapter), "client match attached")
	if not is_instance_valid(session.adapter): return
	var adapter: Node = session.adapter
	adapter.set_process(false)
	var main: Node = current_scene
	main.set_process(false)
	var client_map: Node2D = main.game_map
	client_map.fog_of_war.set_process(false)
	var source_map: Node2D = map_scene.instantiate()
	source_map.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(source_map)
	await process_frame
	source_map.fog_of_war.owning_player = slot
	_check(client_map.map_archetype == archetype and source_map.map_archetype == archetype, "paired generated archetype")
	_check(client_map.map_generator.grid == source_map.map_generator.grid, "same seed produces exact client/source grid")
	var selected: Array[Vector2i] = []
	var original_types: Dictionary = {}
	var initial: Array = []
	for kind: String in ["food", "wood", "gold"]:
		var best: ResourceNode = null
		var distance: float = INF
		for value: ResourceNode in source_map.resource_nodes.values():
			if value.resource_type != kind: continue
			var candidate: float = value.tile_position.distance_squared_to(source_map.map_generator.spawn_positions[slot])
			if candidate < distance:
				distance = candidate
				best = value
		_check(best != null, "generated " + kind + " stock exists")
		if best == null: continue
		var tile: Vector2i = best.tile_position
		selected.append(tile)
		original_types[tile] = source_map.map_generator.grid[tile.y][tile.x]
		initial.append([kind, tile.x, tile.y, best.remaining])
		source_map.fog_of_war.fog_grid[tile.y][tile.x] = MapData.FogState.VISIBLE
		client_map.fog_of_war.fog_grid[tile.y][tile.x] = MapData.FogState.VISIBLE
	_check(selected.size() == 3, "all natural economy families selected")
	var hidden := Vector2i(-1, -1)
	for tile: Vector2i in source_map.resource_nodes:
		if tile not in selected:
			hidden = tile
			break
	client_map.update_resource_visibility_for_player(0)
	var hidden_stock: int = client_map.get_resource_node_at(hidden).remaining
	_check(not client_map.get_resource_node_at(hidden).visible, "unexplored stock hidden")
	var water_before: String = _water_atlas(client_map)
	var whole: Dictionary = _snapshot(adapter, source_map, slot)
	_check(whole.resources.size() == 3, "serializer omits all hidden stock")
	_apply(whole, match_id)
	var partial: Array = []
	for index: int in range(selected.size()):
		var tile: Vector2i = selected[index]
		var resource: ResourceNode = source_map.get_resource_node_at(tile)
		var requested: int = 7 + index * 6
		_check(resource.harvest(requested) == requested, "real partial harvest matches request")
		partial.append(resource.remaining)
	var payload: Dictionary = _snapshot(adapter, source_map, slot)
	_apply(payload, match_id)
	for index: int in range(selected.size()):
		var tile: Vector2i = selected[index]
		_check(client_map.get_resource_node_at(tile).remaining == partial[index], "partial stock replicated exactly")
		client_map.fog_of_war.fog_grid[tile.y][tile.x] = MapData.FogState.EXPLORED
	client_map.update_resource_visibility_for_player(0)
	var old_atlas: Dictionary = {}
	for tile: Vector2i in selected:
		old_atlas[tile] = client_map.terrain_layer.get_cell_atlas_coords(tile)
		var resource: ResourceNode = source_map.get_resource_node_at(tile)
		var amount: int = resource.remaining
		_check(resource.harvest(amount + 9) == amount, "depletion cannot overdraw natural stock")
		_check(source_map.get_resource_node_at(tile) == null, "server registry retires exhausted source")
	payload = _snapshot(adapter, source_map, slot)
	_check(payload.resources.size() == 3, "depleted visible coordinates remain in snapshot")
	for item: Array in payload.resources: _check(int(item[2]) == 0, "exhausted stock serializes zero")
	_apply(payload, match_id)
	await process_frame
	for tile: Vector2i in selected:
		_check(client_map.get_resource_node_at(tile) == null, "client registry retires exhausted source")
		_check(client_map.map_generator.grid[tile.y][tile.x] == MapData.TileType.GRASS, "depletion updates live grid")
		_check(client_map.pathfinding.is_walkable(tile) and is_equal_approx(client_map.pathfinding._astar.get_point_weight_scale(tile), 1.0), "depletion resets live navigation weight")
		_check(client_map.terrain_layer.get_cell_atlas_coords(tile) == old_atlas[tile], "explored terrain preserves rendered memory")
		_check(client_map.get_minimap_grid_for_player(0)[tile.y][tile.x] == original_types[tile], "explored minimap preserves memory")
	_apply(payload, match_id)
	_check(client_map.get_resource_node_at(hidden).remaining == hidden_stock, "hidden resource remains unmodified by snapshot")
	for tile: Vector2i in selected: client_map.fog_of_war.fog_grid[tile.y][tile.x] = MapData.FogState.VISIBLE
	client_map.update_resource_visibility_for_player(0)
	for tile: Vector2i in selected:
		_check(client_map.terrain_layer.get_cell_atlas_coords(tile) == Vector2i(MapData.TileType.GRASS, 0), "reveal displays depleted ground")
		_check(client_map.get_minimap_grid_for_player(0)[tile.y][tile.x] == MapData.TileType.GRASS, "reveal updates minimap")
		_check(not client_map._pending_depleted_terrain_tiles.has(tile), "reveal clears pending memory")
	_check(client_map.map_generator.grid == source_map.map_generator.grid, "depleted client/source geometry matches")
	_check(_water_atlas(client_map) == water_before, "resource depletion does not alter shoreline assignment")
	cases.append({"map": archetype, "slot": slot, "initial_stock": initial, "partial_stock": partial, "hidden_stock_unchanged": hidden_stock, "depleted_grid_sha256": JSON.stringify(client_map.map_generator.grid).sha256_text(), "water_atlas_unchanged": true})
	source_map.free()

func _snapshot(adapter: Node, source_map: Node2D, slot: int) -> Dictionary:
	var saved: Node2D = adapter.game_map
	adapter.game_map = source_map
	var payload: Dictionary = adapter._snapshot_for(slot)
	adapter.game_map = saved
	return JSON.parse_string(JSON.stringify(payload)) as Dictionary

func _apply(payload: Dictionary, match_id: int) -> void:
	payload["op"] = "snapshot"
	payload["match"] = match_id
	session._client_packet(payload)

func _water_atlas(map: Node2D) -> String:
	var cells: Array = []
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			if map.map_generator.grid[y][x] == MapData.TileType.WATER:
				var coords: Vector2i = map.terrain_layer.get_cell_atlas_coords(Vector2i(x, y))
				cells.append([x, y, coords.x, coords.y])
	return JSON.stringify(cells).sha256_text()

func _check(condition: bool, message: String) -> void:
	if not condition and failures.size() < 100: failures.append(message)
