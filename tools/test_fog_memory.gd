extends Node
## Real map/resource/structure state and authoritative serializer/recipient.
## Controlled sight transitions; optional native screenshots, no socket claim.
const NETWORK := preload("res://scripts/network/network_match.gd")
var failures: Array[String] = []
var checks: int = 0
var main: Node
var map: Node2D
var output: String = ""
var cases: Array[Dictionary] = []

func _ready() -> void: call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	AudioManager.set_all_enabled(false)
	NetworkSession.online = false
	NetworkSession.set_process(false)
	NetworkSession.set_physics_process(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	GameManager.set_process(false)
	map = main.game_map
	map.camera.process_mode = Node.PROCESS_MODE_ALWAYS
	map.camera.make_current()
	map.get_node("FogLayer").process_mode = Node.PROCESS_MODE_ALWAYS
	map.terrain_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	await _solo()
	_network_sources()
	await _network_recipients()
	NetworkSession.online = false
	NetworkSession.player_slot = 0
	main.queue_free()
	await get_tree().process_frame
	for failure: String in failures: push_error("[FAIL] fog_memory: " + failure)
	print(JSON.stringify({"test": "fog_memory", "checks": checks, "failures": failures, "scope": "actual static fog rendering; controlled authority observations and JSON snapshots for both recipients, including skipped sightings"}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _solo() -> void:
	var tile := Vector2i(24, 18)
	var resource_tile := tile + Vector2i(4, 0)
	var resource: ResourceNode = _resource(resource_tile)
	var building: BuildingBase = main._spawn_building(BuildingData.BuildingType.BARRACKS, 1, tile)
	building.state = BuildingBase.State.CONSTRUCTING
	building.build_progress = 0.45
	building.hp = 330
	building._update_sprite_appearance()
	var enemy: UnitBase = main._spawn_unit(UnitData.UnitType.INFANTRY, 1, map.tile_to_world(tile + Vector2i(4, 2)))
	map.fog_of_war._init_fog_grid()
	map.fog_of_war._apply_fog_delta()
	main._update_fog_entity_visibility()
	var memory: Node2D = map.fog_memory
	var id: int = building.get_instance_id()
	_expect(not memory.buildings.has(id) and not memory.resources.has(resource_tile), "unseen objects create no memory")
	_patch(tile, 8, MapData.FogState.VISIBLE)
	main._update_fog_entity_visibility()
	_expect(memory.buildings.has(id) and memory.resources.has(resource_tile), "scouting records enemy building and natural resource")
	_expect(memory.buildings[id].visual == null and memory.resources[resource_tile].visual == null, "visible observations allocate no duplicate artwork")
	map.camera.position_smoothing_enabled = false
	map.camera.position = map.tile_to_world(tile + Vector2i(3, 1))
	map.camera.zoom = Vector2(1.5, 1.5)
	map.camera.reset_smoothing()
	map.camera.force_update_scroll()
	await _capture("01-scouted")
	_patch(tile, 8, MapData.FogState.EXPLORED)
	main._update_fog_entity_visibility()
	var art: Node2D = memory.buildings[id].visual
	var tree_art: Node2D = memory.resources[resource_tile].visual
	_expect(art.visible and tree_art.visible and not building.visible and not resource.visible and not enemy.visible, "explored region shows dark static memories but hides all live objects")
	_expect(art.modulate.r < 1.0 and tree_art.modulate.r < 1.0, "memory artwork is darkened")
	_expect(_inert(art) and _inert(tree_art), "memory has no collision, actor groups, targets or simulation")
	_expect(not map.is_resource_target_visible_to_player(resource, 0) and not map.selection_mgr._is_current_selection_entry(resource) and not map.selection_mgr._is_current_selection_entry(building), "hidden actual targets cannot expose live information through selection")
	var stock: int = resource.remaining
	resource.harvest(31)
	building.build_progress = 0.95
	building.hp = 800
	building._update_sprite_appearance()
	for frame: int in 40: main._update_fog_entity_visibility()
	_expect(memory.resources[resource_tile].remaining == stock and memory.buildings[id].progress == 0.45 and memory.buildings[id].hp == 330, "hidden harvest, HP and construction changes cannot update last sighting")
	_expect(memory.buildings[id].visual == art and memory.resources[resource_tile].visual == tree_art, "repeated refresh reuses memory nodes")
	var shader: ShaderMaterial = art.get_node("Artwork").material
	_expect(is_equal_approx(shader.get_shader_parameter("construction_progress"), 0.45), "construction memory material freezes observed progress")
	await _capture("02-remembered-hidden-changes")
	building.state = BuildingBase.State.DESTROYED
	building.queue_free()
	resource.harvest(resource.remaining)
	await get_tree().process_frame
	main._update_fog_entity_visibility()
	_expect(memory.buildings.has(id) and memory.resources.has(resource_tile) and art.visible and tree_art.visible, "hidden destruction/depletion retain frozen silhouettes")
	await _capture("03-remembered-hidden-destruction")
	_patch(tile, 8, MapData.FogState.VISIBLE)
	main._update_fog_entity_visibility()
	_expect(not memory.buildings.has(id) and not memory.resources.has(resource_tile), "rescouting empty ground retires both memories")
	_expect(map.get_resource_node_at(resource_tile) == null and map.pathfinding.is_walkable(resource_tile), "memory never restores live resources or navigation obstacles")
	await _capture("04-rescouted-empty")
	enemy.queue_free()

func _network_sources() -> void:
	var server: Node = NETWORK.new()
	main.add_child(server)
	server.main = main
	server.game_map = map
	server.set_process(false)
	for slot: int in 2:
		var tile := Vector2i(14 + slot * 22, 22)
		var resource_tile := tile + Vector2i(4, 0)
		var resource: ResourceNode = _resource(resource_tile)
		var building: BuildingBase = main._spawn_building(BuildingData.BuildingType.HOUSE, 1 - slot, tile)
		building.state = BuildingBase.State.CONSTRUCTING
		building.build_progress = 0.35
		building.hp = 123
		building._update_sprite_appearance()
		server._register_server_entities()
		var id: int = NetworkSession.entity_id(building)
		server._resource_tiles.assign([resource_tile])
		map.fog_of_war.owning_player = slot
		map.fog_of_war._init_fog_grid()
		var unseen: Dictionary = _snapshot(server, slot)
		_expect(not _has_memory(unseen, id) and unseen.memories.resources.is_empty(), "recipient%d has no unscouted memory" % slot)
		_patch(tile, 7, MapData.FogState.VISIBLE)
		var sight: Dictionary = _snapshot(server, slot)
		_expect(_has_memory(sight, id) and sight.memories.resources.size() == 1, "recipient%d authority records only observed objects" % slot)
		_patch(tile, 7, MapData.FogState.EXPLORED)
		resource.harvest(19)
		building.hp = 499
		building.build_progress = 0.99
		var hidden: Dictionary = _snapshot(server, slot)
		_expect(hidden.resources.is_empty() and not hidden.actors.any(func(actor: Dictionary) -> bool: return int(actor.id) == id), "hidden live actors and counts stay out of recipient%d snapshot" % slot)
		_expect(hidden.memories.buildings == sight.memories.buildings and hidden.memories.resources == sight.memories.resources and hidden.forgotten_buildings.is_empty(), "recipient%d memories freeze private hidden changes" % slot)
		building.state = BuildingBase.State.DESTROYED
		resource.harvest(resource.remaining)
		var destroyed_hidden: Dictionary = _snapshot(server, slot)
		_expect(_has_memory(destroyed_hidden, id) and destroyed_hidden.forgotten_buildings.is_empty(), "hidden destruction sends no tombstone recipient%d" % slot)
		_patch(tile, 7, MapData.FogState.VISIBLE)
		var empty: Dictionary = _snapshot(server, slot)
		_expect(empty.forgotten_buildings.any(func(value: Variant) -> bool: return int(value) == id) and int(empty.memories.resources[0][2]) == 0, "rescout reports known-empty ground recipient%d" % slot)
		_patch(tile, 7, MapData.FogState.EXPLORED)
		var final_packet: Dictionary = _snapshot(server, slot)
		_expect(final_packet.forgotten_buildings.any(func(value: Variant) -> bool: return int(value) == id) and int(final_packet.memories.resources[0][2]) == 0, "latest snapshot retains observed emptiness after vision ends recipient%d" % slot)
		# These scenarios isolate memories; no current actor replicas are needed.
		for packet: Dictionary in [hidden, destroyed_hidden, final_packet]: packet.actors = []
		cases.append({"slot": slot, "tile": tile, "resource_tile": resource_tile, "id": id, "hidden": hidden, "destroyed_hidden": destroyed_hidden, "final": final_packet})
		building.queue_free()
	server.free()

func _network_recipients() -> void:
	NetworkSession.online = true
	NetworkSession.server_mode = false
	for scenario: Dictionary in cases:
		NetworkSession.player_slot = scenario.slot
		map.fog_of_war.owning_player = 0
		map.fog_of_war._init_fog_grid()
		map.fog_memory.free()
		map.fog_memory = null
		# Deterministic client seed has the original resource before snapshots.
		var resource: ResourceNode = _resource(scenario.resource_tile)
		var client: Node = NETWORK.new()
		main.add_child(client)
		client.main = main
		client.game_map = map
		client.set_process(false)
		client.apply_snapshot(scenario.hidden)
		map.update_resource_visibility_for_player(0)
		var memory: Node2D = map.fog_memory
		_expect(memory.buildings.has(scenario.id) and memory.resources.has(scenario.resource_tile), "slot%d latest packet recovers entirely skipped initial sightings" % scenario.slot)
		_expect(memory.buildings[scenario.id].visual.visible and memory.resources[scenario.resource_tile].visual.visible and not map.is_tile_visible_to_player(scenario.tile, 0), "cumulative sighting grants dim explored memory, never live vision")
		_expect(client.entities.is_empty() and _inert(memory.buildings[scenario.id].visual), "remembered structure creates no targetable actor replica")
		var art: Node2D = memory.buildings[scenario.id].visual
		client.apply_snapshot(scenario.destroyed_hidden)
		map.update_resource_visibility_for_player(0)
		_expect(memory.buildings[scenario.id].visual == art and memory.buildings[scenario.id].hp == 123 and is_equal_approx(memory.buildings[scenario.id].progress, 0.35), "hidden destruction packet cannot alter frozen replica memory")
		_expect(not map.is_resource_target_visible_to_player(resource, 0), "remembered stock remains unqueryable/untargetable through live resource selection")
		# Deliberately skip the visible-empty packet and apply only later fog.
		client.apply_snapshot(scenario.final)
		map.update_resource_visibility_for_player(0)
		_expect(not memory.buildings.has(scenario.id) and not memory.resources.has(scenario.resource_tile) and map.get_resource_node_at(scenario.resource_tile) == null, "slot%d coalesced seen-empty then hidden removes known stale stock/structure" % scenario.slot)
		client.apply_snapshot(scenario.final)
		_expect(memory.buildings.is_empty() and memory.resources.is_empty(), "cumulative retirement is idempotent")
		client.free()
		await get_tree().process_frame

func _snapshot(server: Node, slot: int) -> Dictionary:
	return JSON.parse_string(JSON.stringify(server._snapshot_for(slot))) as Dictionary

func _has_memory(packet: Dictionary, id: int) -> bool:
	return packet.memories.buildings.any(func(record: Dictionary) -> bool: return int(record.id) == id)

func _resource(tile: Vector2i) -> ResourceNode:
	var prior: Node2D = map.get_resource_node_at(tile)
	if is_instance_valid(prior):
		map.resource_nodes.erase(tile)
		prior.queue_free()
	var resource: ResourceNode = load("res://scenes/map/resource_node.tscn").instantiate()
	resource.resource_type = "gold"
	resource.total_amount = 350
	resource.tile_position = tile
	resource.position = map.tile_to_world(tile)
	map.get_node("ResourcesContainer").add_child(resource)
	map.resource_nodes[tile] = resource
	resource.depleted.connect(map._on_resource_depleted.bind(tile))
	map.map_generator.grid[tile.y][tile.x] = MapData.TileType.GOLD_MINE
	map.pathfinding.update_tile(tile, MapData.TileType.GOLD_MINE)
	return resource

func _patch(center: Vector2i, radius: int, state: int) -> void:
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1): map.fog_of_war.set_debug_tile_state(Vector2i(x, y), state)
	map.fog_of_war._apply_fog_delta()

func _inert(node: Node) -> bool:
	if node is CollisionObject2D or node.is_in_group("units") or node.is_in_group("buildings") or node.is_in_group("resources"): return false
	for child: Node in node.get_children():
		if not _inert(child): return false
	return true

func _capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(output)
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1280, 720)]:
		DisplayServer.window_set_size(size)
		get_window().size = size
		get_window().content_scale_size = size
		get_window().content_scale_factor = 1.0
		main.hud.hide()
		map.note_camera_interaction()
		map._user_zoom_override = true
		map.camera.position = map.tile_to_world(Vector2i(27, 19))
		map.camera.zoom = Vector2(1.5, 1.5)
		map.camera.reset_smoothing()
		map.camera.force_update_scroll()
		for frame: int in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join("%dx%d-%s.png" % [size.x, size.y, label]))

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
