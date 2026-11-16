extends Node
## Actual command -> authority simulation -> per-slot snapshot -> inert recipient.
## Runs both recipient slots sequentially; this fixture does not claim sockets.
const NETWORK := preload("res://scripts/network/network_match.gd")
var failures: Array[String] = []
var checks: int = 0
var main: Node
var server: Node
var captures: Array[Dictionary] = []
var durations: Array[float] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	NetworkSession.online = false
	NetworkSession.set_process(false)
	NetworkSession.set_physics_process(false)
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.selected_population_limit = 100
	GameManager.guided_opening_enabled = false
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	GameManager.set_process(false)
	GameManager.current_state = GameManager.GameState.PLAYING
	var map: Node = main.game_map
	server = NETWORK.new()
	main.add_child(server)
	server.main = main
	server.game_map = map
	server.set_process(false)
	var traders: Array[Trader] = []
	var posts: Array[BuildingBase] = []
	var centers: Array[Vector2i] = map.map_generator.get_expansion_pocket_centers()
	for slot: int in 2:
		var post: BuildingBase = main._spawn_building(BuildingData.BuildingType.TRADE_POST, slot, centers[slot])
		post.complete_instantly()
		posts.append(post)
		var trader: Trader = main._spawn_unit(UnitData.UnitType.TRADER, slot, map.tile_to_world(centers[slot] + Vector2i(-1, 1)))
		trader.command_stop()
		traders.append(trader)
	server._register_server_entities()
	NetworkSession.online = true
	NetworkSession.server_mode = true
	for slot: int in 2:
		var trader: Trader = traders[slot]
		var id: int = NetworkSession.entity_id(trader)
		var target: int = NetworkSession.entity_id(posts[slot])
		var own_command: Dictionary = {"command": "trade", "ids": [id], "target": target}
		_expect(not server.execute_command(1 - slot, own_command).is_empty() and not trader.trade_route_active, "foreign player cannot command trader/post slot%d" % slot)
		var foreign_trader: Dictionary = {"command": "trade", "ids": [NetworkSession.entity_id(traders[1 - slot])], "target": target}
		_expect(not server.execute_command(slot, foreign_trader).is_empty() and not traders[1 - slot].trade_route_active, "owned post cannot authorize foreign trader slot%d" % slot)
		var foreign_post: Dictionary = {"command": "trade", "ids": [id], "target": NetworkSession.entity_id(posts[1 - slot])}
		_expect(not server.execute_command(slot, foreign_post).is_empty() and not trader.trade_route_active, "owned trader cannot use enemy post slot%d" % slot)
		_expect(server.execute_command(slot, own_command).is_empty() and trader.trade_route_active, "actual authoritative trade command accepted slot%d" % slot)
		var before: int = ResourceManager.get_resource(slot, "gold")
		var other_before: int = ResourceManager.get_resource(1 - slot, "gold")
		var packets: Array[Dictionary] = [_packet(slot, id)]
		var loaded: bool = false
		var elapsed: float = 0.0
		for tick: int in 4800:
			trader._process(0.05)
			elapsed += 0.05
			if trader.carried_gold > 0 and not loaded:
				loaded = true
				packets.append(_packet(slot, id))
				_expect(ResourceManager.get_resource(slot, "gold") == before, "cargo is unpaid until return slot%d" % slot)
			if trader.delivered_gold > 0: break
		_expect(loaded and trader.delivered_gold == trader.get_trip_income() and trader.delivered_gold > 0, "one completed round trip pays advertised income slot%d" % slot)
		_expect(ResourceManager.get_resource(slot, "gold") == before + trader.delivered_gold and ResourceManager.get_resource(1 - slot, "gold") == other_before, "authority pays owning bank exactly once slot%d" % slot)
		packets.append(_packet(slot, id))
		captures.append({"slot": slot, "id": id, "packets": packets})
		durations.append(elapsed)
		trader.command_stop()
		for tick: int in 100: trader._process(0.05)
		_expect(ResourceManager.get_resource(slot, "gold") == before + trader.delivered_gold, "stop after delivery pays no extra income slot%d" % slot)
	for op: String in ["speed", "set_speed", "game_speed"]:
		_expect(server.execute_command(0, {"command": op, "speed": 4.0}) == "Unknown order", "authority rejects speed command " + op)
	Engine.time_scale = 4.0
	GameManager.game_speed = 4.0
	NetworkSession._physics_process(0.016)
	_expect(Engine.time_scale == 1.0 and GameManager.game_speed == 1.0, "server physics enforces fixed speed independent of UI")
	NetworkSession.server_mode = false
	for capture: Dictionary in captures:
		NetworkSession.player_slot = capture.slot
		var client: Node = NETWORK.new()
		main.add_child(client)
		client.main = main
		client.game_map = map
		client.set_process(false)
		for packet: Dictionary in capture.packets:
			client.apply_snapshot(packet)
			var replica: Trader = client.entities.get(capture.id) as Trader
			var actor: Dictionary = packet.actors[0]
			_expect(replica != null and replica.player_owner == 0 and replica.process_mode == Node.PROCESS_MODE_DISABLED, "slot%d receives inert local Trader class" % capture.slot)
			if replica == null: continue
			_expect(replica.carried_gold == actor.trade_cargo and replica.get_trip_income() == actor.trade_income and replica.get_trade_status() == actor.trade_status, "slot%d trade cargo/income/status round trip" % capture.slot)
			var gold: int = ResourceManager.get_resource(0, "gold")
			for tick: int in 100:
				replica._process(1.0)
				client._process(0.1)
			client.apply_snapshot(packet)
			client.apply_snapshot(packet)
			_expect(ResourceManager.get_resource(0, "gold") == gold and gold == int(packet.bank.gold) and replica.delivered_gold == 0, "slot%d replayed snapshot and local ticks cannot duplicate income" % capture.slot)
			_expect(client.entities.size() == 1, "duplicate snapshots reuse one Trader replica")
		Engine.time_scale = 3.0
		GameManager.game_speed = 3.0
		NetworkSession._physics_process(0.016)
		_expect(Engine.time_scale == 1.0 and GameManager.game_speed == 1.0, "client fixed speed survives direct tamper slot%d" % capture.slot)
		for id: int in client.entities.keys(): client._remove_replica(id)
		client.free()
	NetworkSession.online = false
	NetworkSession.server_mode = false
	NetworkSession.player_slot = 0
	main.queue_free()
	await get_tree().process_frame
	for failure: String in failures: push_error("[FAIL] network_trade_authority: " + failure)
	print(JSON.stringify({"test": "network_trade_authority", "checks": checks, "failures": failures, "scope": "actual authority command and simulation; sequential recipient snapshots; no sockets", "simulated_first_delivery_seconds": durations}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _packet(slot: int, id: int) -> Dictionary:
	var packet: Dictionary = server._snapshot_for(slot).duplicate(true)
	# Retain actual authority economics/status, isolating the Trader recipient.
	packet.actors = packet.actors.filter(func(actor: Dictionary) -> bool: return int(actor.id) == id)
	_expect(packet.actors.size() == 1 and packet.actors[0].type == UnitData.UnitType.TRADER, "snapshot includes own Trader slot%d" % slot)
	return packet

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
