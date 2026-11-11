extends SceneTree
## Old builds meet this server: a protocol-17 (0.3.0-beta.33) client asking for
## a quick match, a private lobby or a seat is refused with the "reload" reason
## its own code shows, and never matched. A forged resume is refused. And this
## client, meeting an older server's room/match reply, asks the player to reload.
var sockets: Array[WebSocketPeer] = []
var replies: Array[Array] = []
var sent: Array[bool] = []
var elapsed: float = 0.0
var failures: Array[String] = []
var checks: int = 0
var requests: Array[Dictionary] = []

func _initialize() -> void:
	var constants: Dictionary = load("res://scripts/network/network_session.gd").get_script_constant_map()
	var old_protocol: int = int(constants["PROTOCOL"]) - 1
	var catalog: int = int(constants["MAP_CATALOG_VERSION"])
	requests = [
		{"op": "search", "protocol": old_protocol, "map_catalog": catalog, "civilization": 0},
		{"op": "host", "protocol": old_protocol, "map_catalog": catalog, "map_archetype": 0, "civilization": 0},
		{"op": "join", "protocol": old_protocol, "map_catalog": catalog, "code": "ABCDEF", "civilization": 0},
		{"op": "search", "protocol": int(constants["PROTOCOL"]), "map_catalog": catalog - 1, "civilization": 0},
		{"op": "resume", "protocol": int(constants["PROTOCOL"]), "match": 1, "slot": 0, "token": "not-a-real-seat"},
	]
	for request: Dictionary in requests:
		var socket := WebSocketPeer.new()
		socket.connect_to_url(OS.get_environment("AOEM_MATCH_URL"))
		sockets.append(socket)
		replies.append([])
		sent.append(false)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _process(delta: float) -> bool:
	elapsed += delta
	var complete: bool = true
	for index: int in sockets.size():
		var socket: WebSocketPeer = sockets[index]
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not sent[index]:
			socket.send_text(JSON.stringify(requests[index]))
			sent[index] = true
		while socket.get_available_packet_count() > 0:
			var packet: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if packet is Dictionary:
				replies[index].append(packet)
		if not replies[index].any(func(packet: Dictionary) -> bool: return packet.get("op") == "error"):
			complete = false
	if (complete or elapsed > 8.0) and not finished:
		finished = true
		_finish()
	return false

var finished: bool = false

func _finish() -> void:
	for index: int in requests.size():
		var ops: Array = replies[index].map(func(packet: Dictionary) -> String: return str(packet.get("op")))
		var reasons: Array = replies[index].filter(func(packet: Dictionary) -> bool: return packet.get("op") == "error").map(func(packet: Dictionary) -> String: return str(packet.get("reason", "")))
		var label: String = "%s protocol=%s" % [requests[index].op, requests[index].protocol]
		_expect(not "matched" in ops and not "room" in ops and not "queued" in ops and not "resumed" in ops, label + " is never admitted (" + str(ops) + ")")
		if requests[index].op == "resume":
			_expect(reasons.size() == 1 and str(reasons[0]).contains("can no longer be resumed"), "a forged resume is refused: " + str(reasons))
		else:
			_expect(reasons.size() == 1 and str(reasons[0]).to_lower().contains("reload"), label + " is told to reload: " + str(reasons))
		sockets[index].close()
	# This client against an older server's replies.
	var session: Node = root.get_node("NetworkSession")
	for packet: Dictionary in [
		{"op": "room", "protocol": 17, "code": "ABCDEF", "host": true, "players": 1, "map_archetype": 0, "civilizations": [0, 0]},
		{"op": "matched", "protocol": 17, "slot": 0, "seed": 5, "match": 1, "map_archetype": 0, "civilizations": [0, 0]},
	]:
		session.state = "searching"
		session._client_packet(packet)
		_expect(session.state == "error" and str(session.last_error).contains("Reload") and not session.online, "an old server's %s asks this player to reload (%s)" % [packet.op, session.last_error])
	print("ONLINE_PROTOCOL_GATE checks=%d failures=%s" % [checks, failures])
	for failure: String in failures:
		push_error("[FAIL] online_protocol_gate: " + failure)
	quit(0 if failures.is_empty() else 1)
