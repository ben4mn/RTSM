extends Node
## Authoritative online transport. WebSocket works in native mobile and Web exports.
## Only JSON primitives cross the wire; never deserialize Godot Objects.

signal status_changed(state: String, message: String)
signal match_found()
signal room_changed()
signal snapshot_received(snapshot: Dictionary)
signal match_ended(winner: int, reason: String)

## Protocol11/catalog7 agrees on pacing and axis-safe stock. Terrain geometry stays
## generator5 so existing solo saves can restore their original stock and clock.
## Old clients reload before joining so simulation data stays identical.
const PROTOCOL := 12
const MAP_CATALOG_VERSION := 7
const DEFAULT_ENDPOINT := "wss://game.4mn.org/match"
const MAX_CLIENT_PACKET := 8192
const MAX_SERVER_PACKET := 262144
const MAX_CONNECTIONS := 34
const SNAPSHOT_INTERVAL := 0.1
const CLIENT_POLL_PACKET_BUDGET := 256
const CLIENT_POLL_PARSE_BUDGET_USEC := 4000
const CONNECTION_TIMEOUT := 12.0
const SILENCE_TIMEOUT := 20.0

var state: String = "idle"
var status_text: String = ""
var last_error: String = ""
var server_mode: bool = false
var online: bool = false
var player_slot: int = 0
var match_seed: int = 1
var match_map_archetype: int = MapData.MapArchetype.OPEN_PLAINS
var match_id: int = 0
var room_code: String = ""
var room_host: bool = false
var room_players: int = 0
var room_civilizations: Array[int] = [0, 0]
var match_civilizations: Array[int] = [0, 0]  # authoritative server slot order
var _connection_request: Dictionary = {}
var _request_sent_at: float = 0.0
var _rooms: Dictionary = {}
var adapter: Node = null
var _socket: WebSocketPeer = null
var _server: TCPServer = null
var _peers: Dictionary = {}
var _queue: Array[int] = []
var _players: Array[int] = []
var _next_peer: int = 1
var _elapsed: float = 0.0
var _last_receive: float = 0.0
var _heartbeat: float = 0.0
var _snapshot_elapsed: float = 0.0
var _ready_peers: Dictionary = {}
var _sequence: int = 0
var _match_loading_at: float = 0.0
var _pending_snapshot: Dictionary = {}
var _pending_terminal: Dictionary = {}
var _finishing: bool = false

func _ready() -> void:
	_elapsed = float(Time.get_ticks_msec()) / 1000.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	process_physics_priority = -1000
	server_mode = "--aoem-server" in OS.get_cmdline_user_args()
	if server_mode:
		GameManager.guided_opening_enabled = false
		call_deferred("_start_server")

func is_client() -> bool:
	return online and not server_mode

func is_network_match() -> bool:
	return online

func find_match(endpoint: String = "") -> void:
	_connect_with_request({"op": "search", "protocol": PROTOCOL, "map_catalog": MAP_CATALOG_VERSION, "civilization": CivilizationData.normalize(GameManager.selected_civilization)}, endpoint)

func host_game(map_archetype: int, endpoint: String = "") -> void:
	if not MapData.MAP_ARCHETYPES.has(map_archetype):
		return
	_connect_with_request({"op": "host", "protocol": PROTOCOL, "map_catalog": MAP_CATALOG_VERSION, "map_archetype": map_archetype, "civilization": CivilizationData.normalize(GameManager.selected_civilization)}, endpoint)

func join_game(code: String, endpoint: String = "") -> void:
	_connect_with_request({"op": "join", "protocol": PROTOCOL, "map_catalog": MAP_CATALOG_VERSION, "code": code.strip_edges().to_upper(), "civilization": CivilizationData.normalize(GameManager.selected_civilization)}, endpoint)

func set_room_civilization(civilization: int) -> bool:
	if state != "lobby" or not CivilizationData.is_valid(civilization):
		return false
	return _send(_socket, {"op": "room_civilization", "civilization": civilization})

func get_local_civilizations() -> Array[int]:
	if server_mode:
		return match_civilizations.duplicate()
	return [match_civilizations[player_slot], match_civilizations[1 - player_slot]]

func set_hosted_map(map_archetype: int) -> bool:
	if state != "lobby" or not room_host or not MapData.MAP_ARCHETYPES.has(map_archetype):
		return false
	return _send(_socket, {"op": "room_map", "map_archetype": map_archetype})

func start_hosted_match() -> bool:
	if state != "lobby" or not room_host or room_players != 2:
		return false
	return _send(_socket, {"op": "room_start"})

func _connect_with_request(request: Dictionary, endpoint: String) -> void:
	leave_match()
	# A cached Solo game remains playable without a network. Avoid making an
	# explicitly offline browser wait for a socket timeout to explain that.
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("navigator.onLine === false")):
		_fail("You're offline. Choose Solo to play the saved game; Online 1v1 needs a connection.")
		return
	_connection_request = request
	_heartbeat = 0.0
	last_error = ""
	if endpoint.is_empty():
		endpoint = OS.get_environment("AOEM_MATCH_URL")
	if endpoint.is_empty():
		endpoint = DEFAULT_ENDPOINT
	_socket = _new_socket()
	_elapsed = float(Time.get_ticks_msec()) / 1000.0
	_last_receive = _elapsed
	_set_status("connecting", "Connecting…")
	if _socket.connect_to_url(endpoint) != OK:
		_fail("Cannot connect. Check your connection and try again.")

func cancel_search() -> void:
	leave_match()

func leave_match() -> void:
	if _socket != null:
		if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_send(_socket, {"op": "leave"})
		_socket.close()
	_socket = null
	online = false
	adapter = null
	_pending_snapshot.clear()
	_pending_terminal.clear()
	_connection_request.clear()
	room_code = ""
	room_host = false
	room_players = 0
	room_civilizations.assign([0, 0])
	match_civilizations.assign([0, 0])
	room_changed.emit()
	_set_status("idle", "")

func send_command(operation: String, payload: Dictionary = {}) -> bool:
	if not is_client() or state != "playing" or _socket == null:
		return false
	_sequence += 1
	var packet: Dictionary = payload.duplicate()
	packet["op"] = "command"
	packet["command"] = operation
	packet["sequence"] = _sequence
	packet["match"] = match_id
	return _send(_socket, packet)

func entity_id(node: Variant) -> int:
	# An input callback may still hold a replica removed by the last snapshot.
	# Validate before a typed argument/iterator can reject a freed Object.
	if not is_instance_valid(node) or not node is Node or node.is_queued_for_deletion():
		return 0
	return int(node.get_meta("network_id", 0))

func selection_ids(selected: Array) -> Array:
	var result: Array = []
	for entry: Variant in selected:
		var id: int = entity_id(entry)
		if id > 0 and entry.get("player_owner") == 0:
			result.append(id)
	return result

func target_payload(node: Variant) -> Dictionary:
	if not is_instance_valid(node) or not node is Node2D or node.is_queued_for_deletion():
		return {}
	return {"target": entity_id(node), "position": [node.global_position.x, node.global_position.y]}

func attach_match(main: Node) -> void:
	if not online:
		return
	adapter = load("res://scripts/network/network_match.gd").new()
	adapter.name = "NetworkMatch"
	main.add_child(adapter)
	adapter.setup(main)
	if is_client():
		if not _pending_snapshot.is_empty():
			adapter.apply_snapshot(_pending_snapshot)
			_pending_snapshot.clear()
		if not _pending_terminal.is_empty():
			adapter.finish_match(int(_pending_terminal.winner), str(_pending_terminal.reason))
			_pending_terminal.clear()
		if state in ["ended", "error"]:
			return
		_send(_socket, {"op": "ready", "match": match_id})
	else:
		get_tree().paused = true # Both clients must finish map loading first.

func _set_status(value: String, message: String) -> void:
	state = value
	status_text = message
	if value == "error":
		last_error = message
	status_changed.emit(value, message)

func _new_socket() -> WebSocketPeer:
	var peer := WebSocketPeer.new()
	peer.inbound_buffer_size = MAX_SERVER_PACKET
	peer.outbound_buffer_size = MAX_SERVER_PACKET
	peer.max_queued_packets = 64
	# Godot's native heartbeat expires before reading an already queued Pong
	# after a slow scene/render frame. The application ping below is shared by
	# native and Web and checks liveness only after draining received packets.
	peer.heartbeat_interval = 0.0
	return peer

func _send(peer: WebSocketPeer, packet: Dictionary) -> bool:
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	if peer.get_current_outbound_buffered_amount() > MAX_SERVER_PACKET:
		peer.close(1008, "Connection too slow")
		return false
	return peer.send_text(JSON.stringify(packet)) == OK

func enforce_match_speed() -> void:
	if online or server_mode:
		Engine.time_scale = 1.0
		GameManager.game_speed = 1.0

func _physics_process(_delta: float) -> void:
	enforce_match_speed()

func _process(_delta: float) -> void:
	enforce_match_speed()
	# Engine delta can be capped during stalls or scaled for simulation. Socket
	# deadlines and rate limits belong to elapsed wall time, including loading.
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var transport_delta: float = maxf(0.0, now - _elapsed)
	_elapsed = now
	if server_mode:
		_poll_server(transport_delta)
	else:
		_poll_client(transport_delta)

func _poll_client(delta: float) -> void:
	if _socket == null:
		return
	# Godot can clear its received-message queue while processing a close frame.
	# Consume messages already handed to us before advancing transport state.
	if _socket.get_available_packet_count() == 0:
		_socket.poll()
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if state == "connecting":
			_send(_socket, _connection_request)
			_request_sent_at = _elapsed
			var operation: String = str(_connection_request.get("op", "search"))
			_set_status("searching" if operation == "search" else "joining", "Searching for an opponent…" if operation == "search" else "Opening lobby…")
		_heartbeat += delta
		if _heartbeat > 4.0:
			_heartbeat = 0.0
			_send(_socket, {"op": "ping"})
	# A terminal message may share a poll with the close frame. Drain it before
	# interpreting CLOSED, including through a TLS reverse proxy.
	var budget: int = CLIENT_POLL_PACKET_BUDGET
	var started_usec: int = Time.get_ticks_usec()
	var latest_snapshot: Dictionary = {}
	while _socket != null and _socket.get_available_packet_count() > 0 and budget > 0:
		if budget < CLIENT_POLL_PACKET_BUDGET and Time.get_ticks_usec() - started_usec >= CLIENT_POLL_PARSE_BUDGET_USEC:
			break
		budget -= 1
		var data: PackedByteArray = _socket.get_packet()
		if data.size() > MAX_SERVER_PACKET:
			_fail("Invalid server response.")
			return
		var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
		if parsed is Dictionary:
			_last_receive = _elapsed
			# Snapshots replace state. Applying every obsolete frame can create a
			# permanent backlog on a busy phone. Controls are ordering barriers:
			# apply the last preceding state before results, feedback or a new match.
			if parsed.get("op") == "snapshot" and _whole_number(parsed.get("match")) and int(parsed.match) == match_id:
				latest_snapshot = parsed
			else:
				if not latest_snapshot.is_empty():
					_client_packet(latest_snapshot)
					latest_snapshot = {}
				if _socket == null: return
				_client_packet(parsed)
	if _socket != null and not latest_snapshot.is_empty():
		_client_packet(latest_snapshot)
	if _socket == null:
		return
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		# A terminal frame can remain behind this poll's bounded batch. Keep
		# draining received data before interpreting the transport close.
		if _socket.get_available_packet_count() > 0: return
		if state == "ended":
			_socket = null
			return
		_fail("Connection lost. Return to the menu to search again.")
		return
	# Old servers reply to pings but do not understand private room requests.
	# Those replies must not leave the new lobby flow waiting forever.
	if state == "joining" and _elapsed - _request_sent_at > CONNECTION_TIMEOUT:
		_fail("This server has not enabled private lobbies yet. Use Quick match or connect to an updated server.")
		return
	var timeout: float = CONNECTION_TIMEOUT if state == "connecting" else SILENCE_TIMEOUT
	if _elapsed - _last_receive > timeout and state != "ended":
		_fail("Connection timed out. Try again.")

func _client_packet(packet: Dictionary) -> void:
	if not packet.get("op", "") is String:
		_fail("Invalid server response.")
		return
	if packet.has("match") and (not _whole_number(packet.match) or (str(packet.op) != "matched" and int(packet.match) != match_id)):
		return
	if str(packet.get("op", "")) in ["room", "matched"] and (not _whole_number(packet.get("protocol")) or int(packet.protocol) != PROTOCOL):
		_fail("Game version changed. Reload to play online.")
		return
	match str(packet.get("op", "")):
		"queued":
			_set_status("searching", "Waiting for an arena…" if bool(packet.get("busy", false)) else "Searching for an opponent…")
		"room":
			if not packet.get("code", "") is String or not packet.get("host", false) is bool or not _whole_number(packet.get("players")) or not _valid_map(packet.get("map_archetype")) or not _valid_civilizations(packet.get("civilizations")):
				_fail("Invalid lobby from server.")
				return
			room_code = packet.code
			room_host = packet.host
			room_players = int(packet.players)
			room_civilizations.assign([int(packet.civilizations[0]), int(packet.civilizations[1])])
			match_map_archetype = int(packet.map_archetype)
			_set_status("lobby", "Both players joined · host can start" if room_players == 2 else "Waiting for your opponent…")
			room_changed.emit()
		"room_waiting":
			_set_status("lobby", "Waiting for an arena…")
		"matched":
			if not _whole_number(packet.get("slot")) or int(packet.slot) not in [0, 1] or not _whole_number(packet.get("seed")) or not _whole_number(packet.get("match")):
				_fail("Invalid match from server.")
				return
			if not _valid_civilizations(packet.get("civilizations")):
				_fail("Game version changed. Reload to play online with kingdoms.")
				return
			room_code = ""
			room_players = 0
			room_host = false
			_pending_snapshot.clear()
			_pending_terminal.clear()
			online = true
			player_slot = int(packet["slot"])
			match_civilizations.assign([int(packet.civilizations[0]), int(packet.civilizations[1])])
			match_seed = int(packet["seed"])
			# Previous servers omit this field and always generate Open Plains.
			var received_archetype: Variant = packet.get("map_archetype", MapData.MapArchetype.OPEN_PLAINS)
			if typeof(received_archetype) not in [TYPE_INT, TYPE_FLOAT]:
				_fail("Invalid map from server. Return to the menu and try again.")
				return
			if not is_finite(float(received_archetype)) or float(received_archetype) != float(int(received_archetype)) or not MapData.MAP_ARCHETYPES.has(int(received_archetype)):
				_fail("Map version changed. Reload to play online.")
				return
			match_map_archetype = int(received_archetype)
			match_id = int(packet["match"])
			_sequence = 0
			GameManager.selected_population_limit = SkirmishData.DEFAULT_POPULATION_LIMIT
			GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
			_set_status("loading", "Opponent found · loading…")
			match_found.emit()
			get_tree().call_deferred("change_scene_to_file", "res://scenes/main/main.tscn")
		"started":
			if state not in ["ended", "error"]:
				_set_status("playing", "Online match")
		"snapshot":
			if int(packet.get("match", -1)) != match_id:
				return
			if is_instance_valid(adapter):
				adapter.apply_snapshot(packet)
			else:
				_pending_snapshot = packet
			snapshot_received.emit(packet)
		"rejected":
			if is_instance_valid(adapter):
				adapter.show_feedback(str(packet.get("reason", "Order unavailable")))
		"ended":
			# Confirm receipt before result UI work; the authority retains the
			# connection until this acknowledgement or the bounded legacy timeout.
			_send(_socket, {"op": "result_ack", "match": match_id})
			var winner: int = int(packet.get("winner", -1))
			var reason: String = str(packet.get("reason", "Match ended"))
			_set_status("ended", reason)
			_finish_or_defer(winner, reason)
			match_ended.emit(winner, reason)
		"error":
			_fail(str(packet.get("reason", "Match unavailable. Try again.")))

func _fail(message: String) -> void:
	var in_match: bool = online
	if _socket != null:
		_socket.close()
	_socket = null
	_set_status("error", message)
	if in_match:
		_finish_or_defer(-1, message)

func _finish_or_defer(winner: int, reason: String) -> void:
	# A result or transport failure can arrive while the map scene is loading.
	# Keep it until attach_match has applied the last snapshot and built the HUD.
	if is_instance_valid(adapter):
		adapter.finish_match(winner, reason)
	else:
		_pending_terminal = {"winner": winner, "reason": reason}

func _start_server() -> void:
	_server = TCPServer.new()
	var port := 9080
	var port_text := OS.get_environment("AOEM_MATCH_PORT")
	if port_text.is_valid_int():
		port = int(port_text)
	var error: Error = _server.listen(port, "0.0.0.0")
	if error != OK:
		push_error("Match server failed to listen: %s" % error)
		get_tree().quit(1)
		return
	print("AOEM_MATCH_SERVER_READY port=%d protocol=%d" % [port, PROTOCOL])

func _poll_server(delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var stream: StreamPeerTCP = _server.take_connection()
		if _peers.size() >= MAX_CONNECTIONS:
			stream.disconnect_from_host()
			continue
		var socket := _new_socket()
		socket.inbound_buffer_size = MAX_CLIENT_PACKET * 2
		if socket.accept_stream(stream) == OK:
			_peers[_next_peer] = {"socket": socket, "last": _elapsed, "tokens": 40.0, "seq": 0, "map_catalog": 0}
			_next_peer += 1
	for id: int in _peers.keys():
		if not _peers.has(id):
			continue
		var record: Dictionary = _peers[id]
		var socket: WebSocketPeer = record.socket
		record.tokens = minf(40.0, float(record.tokens) + delta * 20.0)
		socket.poll()
		if socket.get_ready_state() in [WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED]:
			_drop_peer(id, "socket_closed code=%d reason=%s" % [socket.get_close_code(), socket.get_close_reason()])
			continue
		var budget := 16
		while socket.get_available_packet_count() > 0 and budget > 0 and _peers.has(id):
			budget -= 1
			var data: PackedByteArray = socket.get_packet()
			if data.size() > MAX_CLIENT_PACKET or float(record.tokens) < 1.0:
				socket.close(1008, "Packet limit")
				_drop_peer(id, "packet_limit")
				break
			record.tokens = float(record.tokens) - 1.0
			var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
			if parsed is Dictionary:
				record.last = _elapsed
				_server_packet(id, parsed)
		# Drain replies first: a delayed server frame must not turn an already
		# received heartbeat/result acknowledgement into a false timeout.
		if _peers.has(id):
			if record.has("finished_at") and _elapsed - float(record.finished_at) > SILENCE_TIMEOUT:
				_drop_peer(id, "result_receipt_timeout")
			elif _elapsed - float(record.last) > SILENCE_TIMEOUT:
				_drop_peer(id, "silence_timeout")
	if _players.is_empty() and not _finishing:
		var ready_room: String = _ready_room()
		if not ready_room.is_empty():
			var room: Dictionary = _rooms[ready_room]
			var peers: Array[int] = [int(room.host), int(room.guest)]
			_rooms.erase(ready_room)
			_begin_match(peers, int(room.map))
		elif _queue.size() >= 2:
			_start_match()
	if not _players.is_empty() and state == "loading":
		if _ready_peers.size() == 2 and is_instance_valid(adapter):
			get_tree().paused = false
			_set_status("playing", "")
			_broadcast({"op": "started", "match": match_id})
		elif _elapsed - _match_loading_at > 30.0:
			end_match(-1, "Opponent could not load the match.")
	if state == "playing" and is_instance_valid(adapter):
		_snapshot_elapsed += delta
		if _snapshot_elapsed >= SNAPSHOT_INTERVAL:
			_snapshot_elapsed = 0.0
			adapter.broadcast_snapshots()
		if GameManager.game_time > 1800.0:
			end_match(-1, "Time limit reached · draw")

func _server_packet(id: int, packet: Dictionary) -> void:
	if not packet.get("op", "") is String:
		return
	for key: String in ["protocol", "sequence", "match", "map_catalog", "map_archetype", "civilization"]:
		if packet.has(key) and not _whole_number(packet[key]):
			return
	match str(packet.get("op", "")):
		"ping":
			_send_peer(id, {"op": "pong"})
		"host", "join":
			_room_request(id, packet)
		"room_map", "room_start", "room_civilization":
			_room_action(id, packet)
		"search":
			if not _peer_room(id).is_empty():
				return
			if int(packet.get("protocol", -1)) != PROTOCOL or int(packet.get("map_catalog", -1)) != MAP_CATALOG_VERSION:
				_send_peer(id, {"op": "error", "reason": "Game version changed. Reload to play online."})
				return
			if not _valid_civilization(packet.get("civilization", 0)):
				_send_peer(id, {"op": "error", "reason": "Choose a supported kingdom."})
				return
			if id not in _queue and id not in _players:
				_peers[id]["map_catalog"] = MAP_CATALOG_VERSION
				_peers[id]["civilization"] = int(packet.get("civilization", 0))
				_queue.append(id)
			_send_peer(id, {"op": "queued", "busy": not _players.is_empty()})
		"result_ack":
			if _peers[id].has("finished_match") and int(packet.get("match", -1)) == int(_peers[id].finished_match):
				_drop_peer(id, "result_acknowledged")
		"leave":
			_drop_peer(id, "client_leave")
		"ready":
			if id in _players and int(packet.get("match", -1)) == match_id:
				_ready_peers[id] = true
		"command":
			if state != "playing" or id not in _players or int(packet.get("match", -1)) != match_id or not is_instance_valid(adapter):
				return
			var sequence: int = int(packet.get("sequence", 0))
			if sequence <= int(_peers[id].seq):
				return
			_peers[id].seq = sequence
			var reason: String = adapter.execute_command(_players.find(id), packet)
			if not reason.is_empty():
				_send_peer(id, {"op": "rejected", "match": match_id, "reason": reason})

func _start_match() -> void:
	var peers: Array[int] = [_queue.pop_front(), _queue.pop_front()]
	_begin_match(peers)

func _begin_match(peers: Array[int], selected_map: int = -1) -> void:
	_players = peers
	match_civilizations.assign([int(_peers[peers[0]].get("civilization", 0)), int(_peers[peers[1]].get("civilization", 0))])
	_ready_peers.clear()
	match_id += 1
	match_seed = int(randi() % 2147483646) + 1
	match_map_archetype = selected_map if selected_map >= 0 else _choose_match_archetype(_players, match_seed)
	_snapshot_elapsed = 0.0
	online = true
	_match_loading_at = _elapsed
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_population_limit = SkirmishData.DEFAULT_POPULATION_LIMIT
	_set_status("loading", "")
	for slot: int in 2:
		_send_peer(_players[slot], {"op": "matched", "protocol": PROTOCOL, "slot": slot, "seed": match_seed, "map_archetype": match_map_archetype, "civilizations": match_civilizations, "match": match_id})
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main/main.tscn")


func _choose_match_archetype(_peers_for_match: Array[int], seed_value: int) -> int:
	# Queue admission requires the current terrain catalog. Every admitted pair
	# can use the complete seeded rotation; no map supports mixed generators.
	var choices: Array = MapData.MAP_ARCHETYPES.keys()
	return int(choices[posmod(seed_value, choices.size())])

func send_snapshot(slot: int, snapshot: Dictionary) -> void:
	if slot < _players.size():
		snapshot["op"] = "snapshot"
		snapshot["match"] = match_id
		_send_peer(_players[slot], snapshot)

func _send_peer(id: int, packet: Dictionary) -> void:
	if _peers.has(id):
		_send(_peers[id].socket, packet)

func _broadcast(packet: Dictionary) -> void:
	for id: int in _players:
		_send_peer(id, packet)

func _drop_peer(id: int, cause: String = "connection_closed") -> void:
	if _peers.has(id):
		print("AOEM_PEER_DISCONNECTED match=%d slot=%d state=%s silence=%.2f cause=%s" % [match_id, _players.find(id), state, _elapsed - float(_peers[id].last), cause])
	_remove_from_room(id)
	_queue.erase(id)
	var slot: int = _players.find(id)
	if _peers.has(id):
		(_peers[id].socket as WebSocketPeer).close()
		_peers.erase(id)
	if slot >= 0 and not _finishing:
		end_match(1 - slot, "Opponent disconnected")

func end_match(winner: int, reason: String) -> void:
	if _finishing or _players.is_empty():
		return
	_finishing = true
	print("AOEM_MATCH_ENDED match=%d winner=%d seconds=%.1f fps=%.1f reason=%s" % [match_id, winner, GameManager.game_time, Engine.get_frames_per_second(), reason])
	if is_instance_valid(adapter):
		adapter.broadcast_snapshots()
	_broadcast({"op": "ended", "match": match_id, "winner": winner, "reason": reason})
	var completed_peers: Array[int] = _players.duplicate()
	_players.clear()
	for id: int in completed_peers:
		if _peers.has(id):
			_peers[id]["finished_at"] = _elapsed
			_peers[id]["finished_match"] = match_id
	_ready_peers.clear()
	online = false
	adapter = null
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.MENU)
	_set_status("idle", "")
	call_deferred("_reset_arena")

func _reset_arena() -> void:
	get_tree().change_scene_to_file("res://scenes/network/server_lobby.tscn")
	_finishing = false


func _whole_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and absf(float(value)) <= 9007199254740991.0 and float(value) == float(int(value))

func _valid_map(value: Variant) -> bool:
	return _whole_number(value) and MapData.MAP_ARCHETYPES.has(int(value))

func _peer_room(id: int) -> String:
	for code: String in _rooms:
		var room: Dictionary = _rooms[code]
		if int(room.host) == id or int(room.guest) == id:
			return code
	return ""

func _room_request(id: int, packet: Dictionary) -> void:
	if id in _players or id in _queue or not _peer_room(id).is_empty():
		return
	if not _valid_civilization(packet.get("civilization", 0)):
		_send_peer(id, {"op": "error", "reason": "Choose a supported kingdom."})
		return
	if int(packet.get("protocol", -1)) != PROTOCOL or int(packet.get("map_catalog", -1)) != MAP_CATALOG_VERSION:
		_send_peer(id, {"op": "error", "reason": "Game version changed. Both players must reload to use a private lobby."})
		return
	if str(packet.op) == "host":
		if not _valid_map(packet.get("map_archetype")):
			_send_peer(id, {"op": "error", "reason": "Choose a supported map."})
			return
		var code: String = ""
		while code.is_empty() or _rooms.has(code):
			code = ""
			for character: int in 6:
				code += "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[randi() % 32]
		_rooms[code] = {"host": id, "guest": 0, "map": int(packet.map_archetype), "start": false}
		_peers[id]["civilization"] = int(packet.get("civilization", 0))
		_publish_room(code)
	else:
		if not packet.get("code", "") is String:
			return
		var code: String = str(packet.code).strip_edges().to_upper()
		if not _rooms.has(code):
			_send_peer(id, {"op": "error", "reason": "Lobby not found. Check the code with the host."})
			return
		if int(_rooms[code].guest) != 0:
			_send_peer(id, {"op": "error", "reason": "That lobby already has two players."})
			return
		_rooms[code].guest = id
		_peers[id]["civilization"] = int(packet.get("civilization", 0))
		_publish_room(code)

func _room_action(id: int, packet: Dictionary) -> void:
	var code: String = _peer_room(id)
	if code.is_empty():
		return
	var room: Dictionary = _rooms[code]
	if str(packet.op) == "room_civilization":
		# Only the sending peer's own identity can change, before host Start.
		if bool(room.start) or not _valid_civilization(packet.get("civilization")):
			return
		_peers[id]["civilization"] = int(packet.civilization)
		_publish_room(code)
		return
	if int(room.host) != id:
		return
	if str(packet.op) == "room_map":
		if not _valid_map(packet.get("map_archetype")) or bool(room.start):
			return
		room.map = int(packet.map_archetype)
		_publish_room(code)
	elif int(room.guest) != 0:
		room.start = true
		if not _players.is_empty() or _finishing:
			for peer_id: int in [int(room.host), int(room.guest)]:
				_send_peer(peer_id, {"op": "room_waiting"})

func _publish_room(code: String) -> void:
	var room: Dictionary = _rooms[code]
	var civilizations: Array[int] = [int(_peers.get(int(room.host), {}).get("civilization", 0)), int(_peers.get(int(room.guest), {}).get("civilization", 0))]
	for id: int in [int(room.host), int(room.guest)]:
		if id > 0:
			_send_peer(id, {"op": "room", "protocol": PROTOCOL, "code": code, "host": id == int(room.host), "players": 2 if int(room.guest) > 0 else 1, "map_archetype": int(room.map), "civilizations": civilizations})

func _valid_civilization(value: Variant) -> bool:
	return _whole_number(value) and CivilizationData.is_valid(int(value))

func _valid_civilizations(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _valid_civilization(value[0]) and _valid_civilization(value[1])

func _ready_room() -> String:
	for code: String in _rooms:
		if bool(_rooms[code].start) and int(_rooms[code].guest) > 0:
			return code
	return ""

func _remove_from_room(id: int) -> void:
	var code: String = _peer_room(id)
	if code.is_empty():
		return
	var room: Dictionary = _rooms[code]
	if int(room.host) == id:
		_send_peer(int(room.guest), {"op": "error", "reason": "The host closed the lobby. Join a new game."})
		_rooms.erase(code)
	else:
		room.guest = 0
		room.start = false
		_publish_room(code)
