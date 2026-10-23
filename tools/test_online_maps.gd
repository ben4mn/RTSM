extends SceneTree
## Real absent/old/mixed/current WebSocket pairs and deterministic catalog choice.
## AOEM_TEST_SERVER_MAP_CATALOG permits the same current-client probe against
## a frozen older server; only matching advertisements may use that catalog.

var clients: Array[WebSocketPeer] = []
var states: Array[Dictionary] = []
var failures: Array[String] = []
var round_index: int = 0
var elapsed: float = 0.0
var next_round_at: float = 0.0
var endpoint: String
var current_catalog: int = 0
var server_catalog: int = 0
var catalog_pairs: Array[Array] = []


func _initialize() -> void:
	endpoint = OS.get_environment("AOEM_MATCH_URL")
	if endpoint.is_empty():
		endpoint = "ws://127.0.0.1:19080"
	var session: Node = load("res://scripts/network/network_session.gd").new()
	current_catalog = int(session.get_script().get_script_constant_map()["MAP_CATALOG_VERSION"])
	server_catalog = int(OS.get_environment("AOEM_TEST_SERVER_MAP_CATALOG")) if not OS.get_environment("AOEM_TEST_SERVER_MAP_CATALOG").is_empty() else current_catalog
	catalog_pairs = [[0, 0], [1, 1], [1, current_catalog], [current_catalog, 1], [0, current_catalog], [current_catalog, 0], [999, current_catalog], [current_catalog, 999], [current_catalog, current_catalog]]
	session.set("_peers", {1: {"map_catalog": current_catalog}, 2: {"map_catalog": current_catalog}})
	var peers: Array[int] = [1, 2]
	for seed_value: int in range(6):
		_expect(session.call("_choose_match_archetype", peers, seed_value) == seed_value % 3, "all compatible map types participate")
	for pair: Array in catalog_pairs:
		if pair == [current_catalog, current_catalog]:
			continue
		session.set("_peers", {1: {"map_catalog": pair[0]}, 2: {"map_catalog": pair[1]}})
		_expect(session.call("_choose_match_archetype", peers, 1) == MapData.MapArchetype.OPEN_PLAINS, "old, absent or unknown peer catalog falls back safely: " + str(pair))
	for invalid_map: Variant in [-1, 3, 1.5, "1", [], {}]:
		session.call("_client_packet", {"op": "matched", "slot": 0, "seed": 101, "match": 41, "map_archetype": invalid_map})
		_expect(session.get("state") == "error", "unsupported map is rejected before terrain loading")
	session.free()
	_begin_round()


func _begin_round() -> void:
	clients.clear()
	states.clear()
	for index: int in 2:
		var socket := WebSocketPeer.new()
		socket.inbound_buffer_size = 262144
		socket.connect_to_url(endpoint)
		clients.append(socket)
		states.append({"searched": false, "matched": false, "started": false, "snapshot": false})
	print("ONLINE_MAP_PAIR_BEGIN round=%d catalogs=%s server_catalog=%d" % [round_index, catalog_pairs[round_index], server_catalog])


func _process(delta: float) -> bool:
	elapsed += delta
	if clients.is_empty():
		if elapsed >= next_round_at:
			_begin_round()
		return false
	for index: int in clients.size():
		var socket: WebSocketPeer = clients[index]
		socket.poll()
		if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		if not states[index].searched:
			var search: Dictionary = {"op": "search", "protocol": 1}
			var declared_catalog: int = int(catalog_pairs[round_index][index])
			if declared_catalog > 0:
				search["map_catalog"] = declared_catalog
			socket.send_text(JSON.stringify(search))
			states[index].searched = true
		while socket.get_available_packet_count() > 0:
			var packet: Dictionary = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			match str(packet.get("op", "")):
				"matched":
					states[index].matched = true
					states[index].seed = int(packet.seed)
					states[index].map = int(packet.get("map_archetype", -1))
					states[index].match_id = int(packet.match)
					socket.send_text(JSON.stringify({"op": "ready", "match": packet.match}))
				"started":
					states[index].started = true
				"snapshot":
					states[index].snapshot = true
				"error":
					failures.append("server error: " + str(packet.get("reason", "")))
	if states[0].started and states[1].started and states[0].snapshot and states[1].snapshot:
		_expect(states[0].seed == states[1].seed and states[0].map == states[1].map, "paired clients share seed and map")
		_expect(states[0].match_id == states[1].match_id, "paired clients share match")
		var chosen: int = int(states[0].map)
		_expect(MapData.MAP_ARCHETYPES.has(chosen), "server publishes supported map")
		var catalog_matches: bool = catalog_pairs[round_index] == [server_catalog, server_catalog]
		if catalog_matches:
			_expect(chosen == int(states[0].seed) % MapData.MAP_ARCHETYPES.size(), "current pair uses seeded catalog")
		else:
			_expect(chosen == MapData.MapArchetype.OPEN_PLAINS, "old, mixed or unknown catalogs use unchanged Plains: " + str(catalog_pairs[round_index]))
		print("ONLINE_MAP_PAIR_VERIFIED round=%d catalogs=%s server_catalog=%d seed=%d archetype=%d" % [round_index, catalog_pairs[round_index], server_catalog, states[0].seed, chosen])
		for socket: WebSocketPeer in clients:
			socket.send_text(JSON.stringify({"op": "leave"}))
			socket.close()
		clients.clear()
		round_index += 1
		next_round_at = elapsed + 0.5
		if round_index == catalog_pairs.size():
			for failure: String in failures:
				push_error("[FAIL] online_maps: " + failure)
			if failures.is_empty():
				print("[PASS] online_maps: nine real absent/legacy/mixed/unknown/current catalog pairs share terrain selection; only matching catalog uses new layouts; all catalog entries reachable")
			quit(0 if failures.is_empty() else 1)
	if elapsed > 35.0:
		push_error("[FAIL] online_maps timed out round=%d" % round_index)
		quit(1)
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
