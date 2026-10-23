extends Node
## Authoritative online transport. WebSocket works in native mobile and Web exports.
## Only JSON primitives cross the wire; never deserialize Godot Objects.

signal status_changed(state: String, message: String)
signal match_found()
signal snapshot_received(snapshot: Dictionary)
signal match_ended(winner: int, reason: String)

const PROTOCOL := 1
# Version 2 places River/Woodland resources after carving their routes.
# A different catalog must use unchanged Open Plains on either server version.
const MAP_CATALOG_VERSION := 2
const DEFAULT_ENDPOINT := "wss://game.4mn.org/match"
const MAX_CLIENT_PACKET := 8192
const MAX_SERVER_PACKET := 262144
const MAX_CONNECTIONS := 34
const SNAPSHOT_INTERVAL := 0.1
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
	process_mode = Node.PROCESS_MODE_ALWAYS
	server_mode = "--aoem-server" in OS.get_cmdline_user_args()
	if server_mode:
		GameManager.guided_opening_enabled = false
		call_deferred("_start_server")

func is_client() -> bool:
	return online and not server_mode

func is_network_match() -> bool:
	return online

func find_match(endpoint: String = "") -> void:
	leave_match()
	if endpoint.is_empty():
		endpoint = OS.get_environment("AOEM_MATCH_URL")
	if endpoint.is_empty():
		endpoint = DEFAULT_ENDPOINT
	_socket = _new_socket()
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

func entity_id(node: Node) -> int:
	return int(node.get_meta("network_id", 0)) if is_instance_valid(node) else 0

func selection_ids(selected: Array) -> Array:
	var result: Array = []
	for node: Node in selected:
		if is_instance_valid(node) and node.get("player_owner") == 0 and entity_id(node) > 0:
			result.append(entity_id(node))
	return result

func target_payload(node: Node2D) -> Dictionary:
	if not is_instance_valid(node):
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
	peer.heartbeat_interval = 5.0
	return peer

func _send(peer: WebSocketPeer, packet: Dictionary) -> bool:
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	if peer.get_current_outbound_buffered_amount() > MAX_SERVER_PACKET:
		peer.close(1008, "Connection too slow")
		return false
	return peer.send_text(JSON.stringify(packet)) == OK

func _process(delta: float) -> void:
	_elapsed += delta
	if server_mode:
		_poll_server(delta)
	else:
		_poll_client(delta)

func _poll_client(delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if state == "connecting":
			_send(_socket, {"op": "search", "protocol": PROTOCOL, "map_catalog": MAP_CATALOG_VERSION})
			_set_status("searching", "Searching for an opponent…")
		_heartbeat += delta
		if _heartbeat > 4.0:
			_heartbeat = 0.0
			_send(_socket, {"op": "ping"})
	# A terminal message may share a poll with the close frame. Drain it before
	# interpreting CLOSED, including through a TLS reverse proxy.
	var budget := 32
	while _socket != null and _socket.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var data: PackedByteArray = _socket.get_packet()
		if data.size() > MAX_SERVER_PACKET:
			_fail("Invalid server response.")
			return
		var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
		if parsed is Dictionary:
			_last_receive = _elapsed
			_client_packet(parsed)
	if _socket == null:
		return
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if state == "ended":
			_socket = null
			return
		_fail("Connection lost. Return to the menu to search again.")
		return
	var timeout: float = CONNECTION_TIMEOUT if state == "connecting" else SILENCE_TIMEOUT
	if _elapsed - _last_receive > timeout and state != "ended":
		_fail("Connection timed out. Try again.")

func _client_packet(packet: Dictionary) -> void:
	match str(packet.get("op", "")):
		"queued":
			_set_status("searching", "Waiting for an arena…" if bool(packet.get("busy", false)) else "Searching for an opponent…")
		"matched":
			_pending_snapshot.clear()
			_pending_terminal.clear()
			online = true
			player_slot = int(packet["slot"])
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
		if socket.get_ready_state() in [WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED] or _elapsed - float(record.last) > SILENCE_TIMEOUT or (record.has("finished_at") and _elapsed - float(record.finished_at) > 2.0):
			_drop_peer(id)
			continue
		var budget := 16
		while socket.get_available_packet_count() > 0 and budget > 0 and _peers.has(id):
			budget -= 1
			var data: PackedByteArray = socket.get_packet()
			if data.size() > MAX_CLIENT_PACKET or float(record.tokens) < 1.0:
				socket.close(1008, "Packet limit")
				_drop_peer(id)
				break
			record.tokens = float(record.tokens) - 1.0
			var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
			if parsed is Dictionary:
				record.last = _elapsed
				_server_packet(id, parsed)
	if _players.is_empty() and _queue.size() >= 2 and not _finishing:
		_start_match()
	if not _players.is_empty() and state == "loading":
		if _ready_peers.size() == 2 and is_instance_valid(adapter):
			get_tree().paused = false
			_set_status("playing", "")
			_broadcast({"op": "started"})
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
	for key: String in ["protocol", "sequence", "match", "map_catalog"]:
		if packet.has(key) and typeof(packet[key]) not in [TYPE_INT, TYPE_FLOAT]:
			return
	match str(packet.get("op", "")):
		"ping":
			_send_peer(id, {"op": "pong"})
		"search":
			if int(packet.get("protocol", -1)) != PROTOCOL:
				_send_peer(id, {"op": "error", "reason": "Game version changed. Reload to play online."})
				return
			if id not in _queue and id not in _players:
				_peers[id]["map_catalog"] = MAP_CATALOG_VERSION if float(packet.get("map_catalog", 0)) == float(MAP_CATALOG_VERSION) else 0
				_queue.append(id)
			_send_peer(id, {"op": "queued", "busy": not _players.is_empty()})
		"leave":
			_drop_peer(id)
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
				_send_peer(id, {"op": "rejected", "reason": reason})

func _start_match() -> void:
	_players = [_queue.pop_front(), _queue.pop_front()]
	_ready_peers.clear()
	match_id += 1
	match_seed = int(randi() % 2147483646) + 1
	match_map_archetype = _choose_match_archetype(_players, match_seed)
	online = true
	_match_loading_at = _elapsed
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_population_limit = SkirmishData.DEFAULT_POPULATION_LIMIT
	_set_status("loading", "")
	for slot: int in 2:
		_send_peer(_players[slot], {"op": "matched", "slot": slot, "seed": match_seed, "map_archetype": match_map_archetype, "match": match_id})
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main/main.tscn")


func _choose_match_archetype(peers: Array[int], seed_value: int) -> int:
	# Older clients generate terrain locally and ignore unknown packet fields.
	# Keep mixed-version pairs on their byte-identical original generator.
	for id: int in peers:
		if int(_peers.get(id, {}).get("map_catalog", 0)) != MAP_CATALOG_VERSION:
			return MapData.MapArchetype.OPEN_PLAINS
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

func _drop_peer(id: int) -> void:
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
	_broadcast({"op": "ended", "winner": winner, "reason": reason})
	var completed_peers: Array[int] = _players.duplicate()
	_players.clear()
	for id: int in completed_peers:
		if _peers.has(id):
			_peers[id]["finished_at"] = _elapsed
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
