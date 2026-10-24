extends SceneTree
## The actual authority ends a match while the visual client cannot poll.
## A terminal result must survive the peer's render/event-loop delay.
var session: Node
var partner: WebSocketPeer
var partner_search: bool = false
var started: bool = false
var result_received: bool = false
var failures: Array[String] = []
var elapsed: float = 0.0

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	session = root.get_node("NetworkSession")
	root.get_node("AudioManager").set_all_enabled(false)
	session.match_ended.connect(func(winner: int, reason: String) -> void:
		result_received = winner == session.player_slot and reason == "Surrender"
	)
	session.find_match()
	partner = WebSocketPeer.new()
	partner.inbound_buffer_size = 262144
	partner.connect_to_url(OS.get_environment("AOEM_MATCH_URL"))

func _process(delta: float) -> bool:
	elapsed += delta
	if partner != null:
		partner.poll()
		if partner.get_ready_state() == WebSocketPeer.STATE_OPEN and not partner_search:
			partner_search = true
			partner.send_text(JSON.stringify({"op": "search", "protocol": int(load("res://scripts/network/network_session.gd").get_script_constant_map()["PROTOCOL"]), "map_catalog": 2}))
		while partner.get_available_packet_count() > 0:
			var packet: Dictionary = JSON.parse_string(partner.get_packet().get_string_from_utf8())
			if packet.get("op", "") == "matched":
				partner.send_text(JSON.stringify({"op": "ready", "match": packet.match}))
	if session != null and session.state == "playing" and not started and is_instance_valid(session.adapter):
		started = true
		call_deferred("_delay_result")
	if elapsed > 20.0:
		push_error("delayed_result did not start")
		quit(1)
	return false

func _delay_result() -> void:
	session.set_process(false)
	partner.send_text(JSON.stringify({"op": "command", "command": "surrender", "sequence": 1, "match": session.match_id}))
	partner.poll()
	var started_at: int = Time.get_ticks_msec()
	OS.delay_msec(4200)
	session._process(0.016)
	if not result_received or session.state != "ended":
		failures.append("authoritative result discarded while client event loop was delayed")
	print("ONLINE_DELAYED_RESULT delay=%.2f state=%s received=%s failures=%s" % [float(Time.get_ticks_msec() - started_at) / 1000.0, session.state, result_received, failures])
	for failure: String in failures:
		push_error("[FAIL] online_delayed_result: " + failure)
	session.leave_match()
	partner.close()
	quit(0 if failures.is_empty() else 1)
