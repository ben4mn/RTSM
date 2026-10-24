extends SceneTree
## Actual WebSocket lobby protocol, cancellation, explicit map choice and reuse.
var clients: Array[WebSocketPeer] = []
var states: Array[Dictionary] = []
var phase: int = 0
var round_index: int = 0
var elapsed: float = 0.0
var phase_at: float = 0.0
var failures: Array[String] = []
var checks: int = 0
var code: String = ""
var endpoint: String

func _initialize() -> void:
	endpoint = OS.get_environment("AOEM_MATCH_URL")
	_add_client()

func _add_client() -> void:
	var socket := WebSocketPeer.new()
	socket.inbound_buffer_size = 262144
	socket.connect_to_url(endpoint)
	clients.append(socket)
	states.append({"room": {}, "matched": {}, "snapshot": {}, "error": "", "started": false, "ended": {}})

func _send(index: int, packet: Dictionary) -> void:
	clients[index].send_text(JSON.stringify(packet))

func _ready_client(index: int) -> bool:
	return index < clients.size() and clients[index].get_ready_state() == WebSocketPeer.STATE_OPEN

func _next(next_phase: int) -> void:
	phase = next_phase
	phase_at = elapsed

func _process(delta: float) -> bool:
	elapsed += delta
	for i: int in clients.size():
		var socket: WebSocketPeer = clients[i]
		socket.poll()
		while socket.get_available_packet_count() > 0:
			var packet: Dictionary = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			var op: String = str(packet.get("op", ""))
			if op in ["room", "matched", "snapshot", "ended"]:
				states[i][op] = packet
			elif op == "started":
				states[i].started = true
			elif op == "error":
				states[i].error = str(packet.get("reason", ""))
			if op == "matched":
				_send(i, {"op": "ready", "match": int(packet.match)})
	match phase:
		0:
			if _ready_client(0):
				_send(0, {"op": "host", "protocol": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["PROTOCOL"]), "map_catalog": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["MAP_CATALOG_VERSION"]), "map_archetype": round_index})
				_next(1)
		1:
			if not states[0].room.is_empty():
				code = str(states[0].room.code)
				_expect(code.length() == 6 and bool(states[0].room.host) and int(states[0].room.players) == 1, "host gets code and one-player room")
				_add_client()
				_next(2)
		2:
			if _ready_client(1):
				_send(1, {"op": "join", "protocol": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["PROTOCOL"]), "map_catalog": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["MAP_CATALOG_VERSION"]), "code": code.to_lower()})
				_next(3)
		3:
			if not states[1].room.is_empty() and int(states[0].room.players) == 2:
				_expect(not bool(states[1].room.host), "guest never gets host authority")
				_expect(int(states[0].room.map_archetype) == round_index and int(states[1].room.map_archetype) == round_index, "both peers see host's selected map")
				_send(1, {"op": "room_map", "map_archetype": (round_index + 1) % 3})
				_send(1, {"op": "room_start"})
				_add_client()
				_next(4)
		4:
			if _ready_client(2):
				_send(2, {"op": "join", "protocol": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["PROTOCOL"]), "map_catalog": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["MAP_CATALOG_VERSION"]), "code": code})
				_next(5)
		5:
			if not str(states[2].error).is_empty() and elapsed - phase_at > 0.15:
				_expect(states[0].matched.is_empty(), "guest cannot start the match")
				_expect(int(states[0].room.map_archetype) == round_index, "guest cannot change the map")
				clients[2].close()
				_send(1, {"op": "leave"})
				_next(6)
		6:
			if int(states[0].room.players) == 1:
				_expect(states[0].matched.is_empty(), "guest departure leaves host in room")
				_send(0, {"op": "room_map", "map_archetype": (round_index + 1) % 3})
				_add_client()
				_next(7)
		7:
			if _ready_client(3) and int(states[0].room.map_archetype) == (round_index + 1) % 3:
				_send(3, {"op": "join", "protocol": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["PROTOCOL"]), "map_catalog": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["MAP_CATALOG_VERSION"]), "code": code})
				_next(8)
		8:
			if not states[3].room.is_empty() and int(states[0].room.players) == 2:
				_expect(int(states[3].room.map_archetype) == (round_index + 1) % 3, "replacement guest sees latest map")
				_send(0, {"op": "room_map", "map_archetype": round_index})
				_send(0, {"op": "room_start"})
				_next(9)
		9:
			if states[0].started and states[3].started and not states[0].snapshot.is_empty() and not states[3].snapshot.is_empty():
				_expect(int(states[0].matched.map_archetype) == round_index and int(states[3].matched.map_archetype) == round_index, "started match preserves final map")
				_expect(states[0].matched.seed == states[3].matched.seed and states[0].matched.match == states[3].matched.match, "clients share match and seed")
				_expect(int(states[0].matched.slot) == 0 and int(states[3].matched.slot) == 1, "host and guest receive opposite slots")
				clients[3].close()
				_next(10)
		10:
			if not states[0].ended.is_empty():
				_expect(int(states[0].ended.winner) == 0 and str(states[0].ended.reason) == "Opponent disconnected", "host receives honest disconnect result")
				print("ONLINE_ROOM_VERIFIED map=%d checks=%d" % [round_index, checks])
				for socket: WebSocketPeer in clients:
					socket.close()
				_next(11)
		11:
			if elapsed - phase_at > 0.3:
				clients.clear()
				states.clear()
				round_index += 1
				if round_index == 3:
					_add_client()
					_next(12)
				else:
					_add_client()
					_next(0)
		12:
			if _ready_client(0):
				_send(0, {"op": "host", "protocol": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["PROTOCOL"]), "map_catalog": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["MAP_CATALOG_VERSION"]), "map_archetype": 0})
				_next(13)
		13:
			if not states[0].room.is_empty():
				code = str(states[0].room.code)
				_add_client()
				_next(14)
		14:
			if _ready_client(1):
				_send(1, {"op": "join", "protocol": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["PROTOCOL"]), "map_catalog": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["MAP_CATALOG_VERSION"]), "code": code})
				_next(15)
		15:
			if not states[1].room.is_empty():
				clients[0].close()
				_next(16)
		16:
			if not str(states[1].error).is_empty():
				_expect(str(states[1].error).contains("host closed"), "host cancellation tells guest what happened")
				for failure: String in failures:
					push_error("[FAIL] online_rooms: " + failure)
				print("ONLINE_ROOMS_RESULT checks=%d failures=%s" % [checks, failures])
				quit(0 if failures.is_empty() else 1)
	if elapsed > 40.0:
		push_error("online_rooms timeout phase=%d map=%d" % [phase, round_index])
		quit(1)
	return false

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
