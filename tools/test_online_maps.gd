extends SceneTree
## Nine real WebSocket pairs: incompatible catalogs are rejected before pairing;
## the current pair still receives a common map, startup and live snapshots.

var clients: Array[WebSocketPeer] = []
var states: Array[Dictionary] = []
var failures: Array[String] = []
var round_index: int = 0
var elapsed: float = 0.0
var next_round_at: float = 0.0
var rejection_ready_at: float = -1.0
var endpoint: String
var current_protocol: int = 0
var current_catalog: int = 0
var catalog_pairs: Array[Array] = []
var finished: bool = false


func _initialize() -> void:
	endpoint = OS.get_environment("AOEM_MATCH_URL")
	if endpoint.is_empty():
		endpoint = "ws://127.0.0.1:19080"
	var session: Node = load("res://scripts/network/network_session.gd").new()
	current_protocol = int(session.get_script().get_script_constant_map()["PROTOCOL"])
	current_catalog = int(session.get_script().get_script_constant_map()["MAP_CATALOG_VERSION"])
	var old_catalog: int = current_catalog - 1
	catalog_pairs = [[0, 0], [old_catalog, old_catalog], [old_catalog, current_catalog], [current_catalog, old_catalog], [0, current_catalog], [current_catalog, 0], [999, current_catalog], [current_catalog, 999], [current_catalog, current_catalog]]
	session.set("_peers", {1: {"map_catalog": current_catalog}, 2: {"map_catalog": current_catalog}})
	var peers: Array[int] = [1, 2]
	for seed_value: int in range(6):
		_expect(session.call("_choose_match_archetype", peers, seed_value) == seed_value % MapData.MAP_ARCHETYPES.size(), "all current map types participate")
	for invalid_map: Variant in [-1, 3, 1.5, "1", [], {}]:
		session.call("_client_packet", {"op": "matched", "protocol": current_protocol, "slot": 0, "seed": 101, "match": 41, "map_archetype": invalid_map, "civilizations": [0, 0]})
		_expect(session.get("state") == "error", "unsupported map is rejected before terrain loading")
	session.free()
	_begin_round()


func _begin_round() -> void:
	clients.clear()
	states.clear()
	rejection_ready_at = -1.0
	for index: int in 2:
		var socket := WebSocketPeer.new()
		socket.inbound_buffer_size = 262144
		socket.connect_to_url(endpoint)
		clients.append(socket)
		states.append({"searched": false, "queued": false, "matched": false, "started": false, "snapshot": false, "error": ""})
	print("ONLINE_MAP_PAIR_BEGIN round=%d catalogs=%s" % [round_index, catalog_pairs[round_index]])


func _process(delta: float) -> bool:
	if finished:
		return false
	elapsed += delta
	if clients.is_empty():
		if elapsed >= next_round_at:
			_begin_round()
		return false
	var current_pair: bool = catalog_pairs[round_index] == [current_catalog, current_catalog]
	for index: int in clients.size():
		var socket: WebSocketPeer = clients[index]
		socket.poll()
		if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		if not states[index].searched:
			var search: Dictionary = {"op": "search", "protocol": current_protocol, "civilization": index}
			var declared_catalog: int = int(catalog_pairs[round_index][index])
			if declared_catalog > 0:
				search["map_catalog"] = declared_catalog
			socket.send_text(JSON.stringify(search))
			states[index].searched = true
		while socket.get_available_packet_count() > 0:
			var packet: Dictionary = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			match str(packet.get("op", "")):
				"queued":
					states[index].queued = true
				"matched":
					states[index].matched = true
					states[index].seed = int(packet.seed)
					states[index].map = int(packet.get("map_archetype", -1))
					states[index].match_id = int(packet.match)
					if current_pair:
						socket.send_text(JSON.stringify({"op": "ready", "match": packet.match}))
				"started":
					states[index].started = true
				"snapshot":
					states[index].snapshot = true
				"error":
					states[index].error = str(packet.get("reason", ""))
	if not current_pair:
		var both_answered: bool = true
		for index: int in 2:
			var state: Dictionary = states[index]
			if state.matched or state.started or state.snapshot:
				failures.append("incompatible pair reached a match: " + str(catalog_pairs[round_index]))
				_finish()
				return false
			if int(catalog_pairs[round_index][index]) == current_catalog:
				if not str(state.error).is_empty():
					failures.append("current peer rejected in mixed pair: " + str(state.error))
					_finish()
					return false
				both_answered = both_answered and bool(state.queued)
			else:
				both_answered = both_answered and not str(state.error).is_empty()
		if both_answered:
			if rejection_ready_at < 0.0:
				rejection_ready_at = elapsed
			# Give the server a pairing tick before accepting rejection as complete.
			if elapsed - rejection_ready_at >= 0.15:
				for index: int in 2:
					if int(catalog_pairs[round_index][index]) != current_catalog:
						_expect(str(states[index].error).to_lower().contains("reload"), "incompatible peer receives a reload instruction")
						_expect(not states[index].queued, "incompatible peer never enters matchmaking")
				print("ONLINE_MAP_PAIR_REJECTED round=%d catalogs=%s" % [round_index, catalog_pairs[round_index]])
				_advance_round()
	else:
		for state: Dictionary in states:
			if not str(state.error).is_empty():
				failures.append("current pair rejected: " + str(state.error))
				_finish()
				return false
		if states[0].started and states[1].started and states[0].snapshot and states[1].snapshot:
			_expect(states[0].queued and states[1].queued and states[0].matched and states[1].matched, "current pair queues and matches")
			_expect(states[0].seed == states[1].seed and states[0].map == states[1].map, "paired clients share seed and map")
			_expect(states[0].match_id == states[1].match_id, "paired clients share match")
			var chosen: int = int(states[0].map)
			_expect(MapData.MAP_ARCHETYPES.has(chosen), "server publishes supported map")
			_expect(chosen == int(states[0].seed) % MapData.MAP_ARCHETYPES.size(), "current pair uses seeded catalog")
			print("ONLINE_MAP_PAIR_VERIFIED round=%d catalogs=%s seed=%d archetype=%d" % [round_index, catalog_pairs[round_index], states[0].seed, chosen])
			_advance_round()
	if not finished and elapsed > 35.0:
		failures.append("timed out round=%d catalogs=%s states=%s" % [round_index, catalog_pairs[round_index], states])
		_finish()
	return false


func _close_clients() -> void:
	for socket: WebSocketPeer in clients:
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			socket.send_text(JSON.stringify({"op": "leave"}))
		socket.close()
	clients.clear()


func _advance_round() -> void:
	_close_clients()
	round_index += 1
	next_round_at = elapsed + 0.5
	if round_index == catalog_pairs.size():
		_finish()


func _finish() -> void:
	finished = true
	_close_clients()
	for failure: String in failures:
		push_error("[FAIL] online_maps: " + failure)
	if failures.is_empty():
		print("[PASS] online_maps: nine real absent/old/mixed/unknown/current catalog rounds; incompatible peers rejected before queue or match, current pair matched/started/snapshotted")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
