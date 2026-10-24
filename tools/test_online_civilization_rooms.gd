extends SceneTree
## Real sockets: stale-version rejection, own-slot lobby changes, invalid input,
## start latching, authoritative HP and common result. Separate clients exercise
## replica creation and paid signature recruitment after this protocol check.

var sockets: Array[WebSocketPeer] = []
var states: Array[Dictionary] = []
var phase: int = 0
var phase_at: float = 0.0
var elapsed: float = 0.0
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	for index: int in 3:
		var socket := WebSocketPeer.new()
		socket.inbound_buffer_size = 262144
		socket.connect_to_url(OS.get_environment("AOEM_MATCH_URL"))
		sockets.append(socket)
		states.append({"error": "", "room": {}, "matched": {}, "snapshot": {}, "ended": {}, "started": false})

func _send(index: int, packet: Dictionary) -> void:
	sockets[index].send_text(JSON.stringify(packet))

func _next(value: int) -> void:
	phase = value
	phase_at = elapsed

func _process(delta: float) -> bool:
	elapsed += delta
	for index: int in sockets.size():
		var socket: WebSocketPeer = sockets[index]
		socket.poll()
		while socket.get_available_packet_count() > 0:
			var packet: Dictionary = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			var operation: String = str(packet.get("op", ""))
			if operation in ["room", "matched", "snapshot", "ended"]:
				states[index][operation] = packet
			elif operation == "error":
				states[index].error = str(packet.get("reason", ""))
			elif operation == "started":
				states[index].started = true
			if operation == "matched":
				_send(index, {"op": "ready", "match": int(packet.match)})
	match phase:
		0:
			if sockets.all(func(socket: WebSocketPeer) -> bool: return socket.get_ready_state() == WebSocketPeer.STATE_OPEN):
				_send(0, {"op": "search", "protocol": 1})
				_send(1, {"op": "host", "protocol": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["PROTOCOL"]), "map_catalog": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["MAP_CATALOG_VERSION"]), "map_archetype": 0, "civilization": 1})
				_next(1)
		1:
			if not str(states[0].error).is_empty() and not states[1].room.is_empty():
				_expect(str(states[0].error).contains("Reload"), "old clients receive explicit refresh instruction")
				_expect(_same_civilizations(states[1].room.civilizations, [1, 0]), "host identity enters lobby")
				_send(2, {"op": "join", "protocol": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["PROTOCOL"]), "map_catalog": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["MAP_CATALOG_VERSION"]), "code": states[1].room.code, "civilization": 2})
				_next(2)
		2:
			if not states[2].room.is_empty() and int(states[1].room.players) == 2:
				_expect(_same_civilizations(states[1].room.civilizations, [1, 2]) and _same_civilizations(states[2].room.civilizations, [1, 2]), "both peers see both identities in server slot order")
				_send(1, {"op": "room_civilization", "civilization": 2, "slot": 1})
				_send(2, {"op": "room_civilization", "civilization": 0, "slot": 0})
				_next(3)
		3:
			if _same_civilizations(states[1].room.civilizations, [2, 0]) and _same_civilizations(states[2].room.civilizations, [2, 0]):
				_expect(true, "either peer changes only their own identity, spoofed slot ignored")
				for value: Variant in [99, -1, 1.5, true, "1", [], {}]:
					_send(2, {"op": "room_civilization", "civilization": value})
				_send(2, {"op": "room_map", "map_archetype": 1})
				_send(2, {"op": "room_start"})
				_next(4)
		4:
			if elapsed - phase_at > 0.4:
				_expect(_same_civilizations(states[1].room.civilizations, [2, 0]) and _same_civilizations(states[2].room.civilizations, [2, 0]), "malformed and unknown kingdoms cannot change lobby")
				_expect(states[1].matched.is_empty() and int(states[1].room.map_archetype) == 0, "guest cannot start or change map")
				_send(1, {"op": "room_start"})
				_send(1, {"op": "room_civilization", "civilization": 1})
				_send(2, {"op": "room_civilization", "civilization": 1})
				_next(5)
		5:
			if states[1].started and states[2].started and not states[1].snapshot.is_empty() and not states[2].snapshot.is_empty():
				for index: int in [1, 2]:
					_expect(_same_civilizations(states[index].matched.civilizations, [2, 0]), "Start latches choices before late lobby edits")
					_expect(_same_civilizations(states[index].snapshot.civilizations, [2, 0]), "authority snapshots retain public identities")
					var slot: int = int(states[index].matched.slot)
					_expect(int(states[index].snapshot.player.civilization) == [2, 0][slot], "own player snapshot identity matches server slot")
					for actor: Dictionary in states[index].snapshot.actors:
						if str(actor.kind) == "building" and int(actor.type) == 0 and int(actor.owner) == slot:
							_expect(int(actor.max_hp) == (4000 if slot == 0 else 5000), "actual starting Town Center uses authority civilization HP")
				_send(2, {"op": "command", "command": "surrender", "sequence": 1, "match": int(states[2].matched.match)})
				_next(6)
		6:
			if not states[1].ended.is_empty() and not states[2].ended.is_empty():
				_expect(int(states[1].ended.winner) == 0 and int(states[2].ended.winner) == 0, "both clients receive same winner")
				_expect(str(states[1].ended.reason) == str(states[2].ended.reason), "both clients receive same result reason")
				for index: int in [1, 2]:
					_send(index, {"op": "result_ack", "match": int(states[index].matched.match)})
				for socket: WebSocketPeer in sockets:
					socket.close()
				print("ONLINE_CIV_LOBBY_RESULT checks=%d failures=%s" % [checks, failures])
				for failure: String in failures:
					push_error("[FAIL] online_civilization_rooms: " + failure)
				quit(0 if failures.is_empty() else 1)
	if elapsed > 45.0:
		push_error("online_civilization_rooms timeout phase=%d states=%s" % [phase, states])
		quit(1)
	return false

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _same_civilizations(actual: Array, expected: Array) -> bool:
	return actual.size() == 2 and int(actual[0]) == int(expected[0]) and int(actual[1]) == int(expected[1])
