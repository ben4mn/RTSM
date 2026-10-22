extends SceneTree
## Uses raw WebSocket clients to exercise the actual listening service.
var clients: Array[WebSocketPeer] = []
var states: Array[Dictionary] = []
var elapsed := 0.0
var phase := 0
var phase_started := 0.0
var heartbeat := 0.0
var endpoint: String
var failures: Array[String] = []

func _initialize() -> void:
	endpoint = OS.get_environment("AOEM_MATCH_URL")
	if endpoint.is_empty():
		endpoint = "ws://127.0.0.1:19080"
	_add_client()

func _add_client() -> void:
	var socket := WebSocketPeer.new()
	socket.inbound_buffer_size = 262144
	socket.outbound_buffer_size = 32768
	socket.connect_to_url(endpoint)
	clients.append(socket)
	states.append({"search": false, "queued": false, "matched": false, "started": false, "ended": false, "rejections": 0, "snapshot": {}})

func _send(index: int, data: Dictionary) -> void:
	clients[index].send_text(JSON.stringify(data))

func _process(delta: float) -> bool:
	elapsed += delta
	heartbeat += delta
	for i: int in clients.size():
		var socket: WebSocketPeer = clients[i]
		socket.poll()
		if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		if heartbeat > 4.0:
			_send(i, {"op": "ping"})
		if not states[i].search:
			_send(i, {"op": "search", "protocol": 1})
			states[i].search = true
		while socket.get_available_packet_count() > 0:
			var packet: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if not packet is Dictionary:
				continue
			var op: String = str(packet.get("op", ""))
			if op in ["queued", "matched", "started", "ended"]:
				states[i][op] = true
			if op == "rejected":
				states[i].rejections += 1
			if op == "matched":
				states[i].match_id = int(packet.match)
				states[i].slot = int(packet.slot)
				_send(i, {"op": "ready", "match": packet.match})
			if op == "snapshot":
				states[i].snapshot = packet
			if op == "ended":
				states[i].result = packet
	if heartbeat > 4.0:
		heartbeat = 0.0
	match phase:
		0:
			if states[0].queued:
				_send(0, {"op": "leave"})
				clients[0].close()
				phase = 1
				phase_started = elapsed
		1:
			if elapsed - phase_started > 0.3:
				_add_client()
				phase = 2
				phase_started = elapsed
		2:
			if states[1].queued and elapsed - phase_started > 0.7:
				if states[1].matched:
					failures.append("Cancelled player was matched")
				_add_client()
				phase = 3
		3:
			if states[1].started and states[2].started and not states[1].snapshot.is_empty():
				var data: Dictionary = states[1].snapshot
				var enemy_ids: Array = []
				var town_center_id: int = 0
				for actor: Dictionary in data.actors:
					if int(actor.owner) != int(states[1].slot):
						enemy_ids.append(actor.id)
					elif actor.kind == "building" and int(actor.type) == BuildingData.BuildingType.TOWN_CENTER:
						town_center_id = int(actor.id)
				if not enemy_ids.is_empty():
					failures.append("Hidden enemy entities leaked into snapshot")
				if town_center_id == 0:
					failures.append("Missing own Town Center for Repeat validation")
				_send(1, {"op": "command", "match": states[1].match_id, "sequence": 1, "command": "train", "target": 99999, "type": 0})
				_send(1, {"op": "command", "match": {}, "sequence": [], "command": "move"})
				_send(1, {"op": "command", "match": states[1].match_id, "sequence": 2, "command": "move", "position": [0, {}]})
				_send(1, {"op": "command", "match": states[1].match_id, "sequence": 3, "command": "repeat", "target": town_center_id, "enabled": []})
				_send(1, {"op": "command", "match": states[1].match_id, "sequence": 4, "command": "repeat", "target": town_center_id, "enabled": {}})
				_send(1, {"op": "command", "match": states[1].match_id, "sequence": 5, "command": "allocate", "source": {}, "destination": "wood"})
				_send(1, {"op": "command", "match": states[1].match_id, "sequence": 6, "command": "allocate", "source": "build", "destination": "wood"})
				phase = 4
		4:
			if int(states[1].rejections) >= 6:
				clients[2].close()
				phase = 5
		5:
			if states[1].ended:
				if int(states[1].result.winner) != int(states[1].slot):
					failures.append("Disconnect winner wrong")
				print("ONLINE_LIFECYCLE_VERIFIED cancel=true malformed=true malformed_repeat=true authority=true fog=true disconnect=true failures=%s" % [failures])
				quit(0 if failures.is_empty() else 1)
	if elapsed > 40.0:
		push_error("Lifecycle timed out phase=%d" % phase)
		quit(1)
	return false
