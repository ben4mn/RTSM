extends Node
## Real authority commands and paid production for both owners; no socket claim.
const NETWORK = preload("res://scripts/network/network_match.gd")
var failures: Array[String] = []
var checks: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	GameManager.selected_population_limit = 30
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var map: Node = main.game_map
	var server: Node = NETWORK.new()
	main.add_child(server)
	server.main = main
	server.game_map = map
	server.set_process(false)
	server._register_server_entities()
	NetworkSession.online = true
	NetworkSession.server_mode = true
	for owner: int in 2:
		var tc: BuildingBase = main._player_buildings[owner][0]
		var source: ResourceNode
		for candidate: Node in get_tree().get_nodes_in_group("resources"):
			if candidate is ResourceNode and map.is_resource_target_visible_to_player(candidate, owner):
				source = candidate
				break
		_expect(source != null, "owner%d has a visible starting resource" % owner)
		if source == null: continue
		var packet: Dictionary = {"command": "rally", "target": NetworkSession.entity_id(tc), "position": [source.global_position.x, source.global_position.y]}
		_expect(not server.execute_command(1 - owner, packet).is_empty(), "foreign owner cannot set producer rally")
		_expect(server.execute_command(owner, packet).is_empty(), "owner resource rally accepted")
		_expect(tc.rally_resource_instance_id == source.get_instance_id(), "server resolves only observed resource identity")
		var bank: int = ResourceManager.get_resource(owner, "food")
		var count: int = main._player_units[owner].size()
		_expect(server.execute_command(owner, {"command": "train", "target": NetworkSession.entity_id(tc), "type": UnitData.UnitType.VILLAGER}).is_empty(), "normal authoritative paid recruit accepted")
		var queue: ProductionQueue = tc.get_production_queue()
		queue.advance(queue.current_train_time + 0.01)
		_expect(main._player_units[owner].size() == count + 1, "one paid birth")
		_expect(ResourceManager.get_resource(owner, "food") == bank - 100, "one exact100F debit")
		var worker: Villager = main._player_units[owner].back()
		_expect(worker.current_state == UnitBase.State.GATHERING and worker.gather_target == source, "server-born worker inherits resource job")
		var snapshot: Dictionary = server._snapshot_for(owner)
		var actors: Array = snapshot.actors.filter(func(actor: Dictionary) -> bool: return int(actor.id) == NetworkSession.entity_id(tc))
		_expect(actors.size() == 1 and actors[0].custom_rally and Vector2(actors[0].rally[0], actors[0].rally[1]) == source.global_position, "recipient snapshot agrees on rally position")
	for operation: String in ["speed", "set_speed", "game_speed"]:
		_expect(server.execute_command(0, {"command": operation, "speed": 3.0}) == "Unknown order", "authority rejects speed injection")
	Engine.time_scale = 3.0
	GameManager.game_speed = 3.0
	NetworkSession._physics_process(0.01)
	_expect(Engine.time_scale == 1.0 and GameManager.game_speed == 1.0, "online speed remains1x")
	NetworkSession.online = false
	NetworkSession.server_mode = false
	main.free()
	for failure: String in failures: push_error(failure)
	print(JSON.stringify({"test": "network_resource_rally", "checks": checks, "failures": failures, "scope": "both owners; actual commands, paid production and snapshots; no sockets"}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
