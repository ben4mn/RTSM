extends SceneTree
## Real local WebSockets, intentionally >32 snapshots before the terminal packet.
## No rendered map needed: a witness records the expensive adapter boundary.
class SnapshotWitness extends Node:
	var applied: Array[int] = []
	var finish_time: int = -1
	var feedback_time: int = -1
	func apply_snapshot(packet: Dictionary) -> void: applied.append(int(packet.time))
	func finish_match(_winner: int, _reason: String) -> void: finish_time = applied.back() if not applied.is_empty() else -1
	func show_feedback(_reason: String) -> void: feedback_time = applied.back() if not applied.is_empty() else -1
var failures: Array[String] = []
var receipts: Array[Dictionary] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var session: Node = root.get_node("NetworkSession")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--session-script="):
			session = load(argument.trim_prefix("--session-script=")).new()
			root.add_child(session)
	session.set_process(false)
	for close_after_send: bool in [false, true]:
		await _scenario(session, close_after_send)
	print(JSON.stringify({"test": "online_snapshot_backlog", "failures": failures, "receipts": receipts}))
	quit(0 if failures.is_empty() else 1)
func _scenario(session: Node, close_after_send: bool) -> void:
	session.leave_match()
	var server := TCPServer.new()
	var port: int = 49150
	while port < 49200 and server.listen(port, "127.0.0.1") != OK: port += 1
	if port >= 49200:
		failures.append("no fixture port available")
		return
	var client: WebSocketPeer = session._new_socket()
	client.connect_to_url("ws://127.0.0.1:%d" % port)
	var peer := WebSocketPeer.new()
	peer.max_queued_packets = 64
	var accepted: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		client.poll()
		if not accepted and server.is_connection_available():
			accepted = peer.accept_stream(server.take_connection()) == OK
		if accepted: peer.poll()
		if client.get_ready_state() == WebSocketPeer.STATE_OPEN and peer.get_ready_state() == WebSocketPeer.STATE_OPEN: break
		await process_frame
	if client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		failures.append("fixture handshake failed")
		server.stop()
		return
	var witness := SnapshotWitness.new()
	root.add_child(witness)
	session._socket = client
	session.adapter = witness
	session.match_id = 91
	session.online = true
	session.state = "playing"
	for value: int in range(1, 61):
		peer.send_text(JSON.stringify({"op": "snapshot", "match": 91, "time": value}))
		if value == 30: peer.send_text(JSON.stringify({"op": "rejected", "match": 91, "reason": "fixture order barrier"}))
	peer.send_text(JSON.stringify({"op": "ended", "match": 91, "winner": 0, "reason": "fixture terminal"}))
	peer.poll()
	# Receive the complete batch before allowing application processing.
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and client.get_available_packet_count() < 62:
		client.poll()
		peer.poll()
		await process_frame
	var queued_before: int = client.get_available_packet_count()
	if close_after_send:
		peer.close(1000, "fixture close after terminal")
		peer.poll()
	var acknowledgements: int = 0
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		session._process(0.016)
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var packet: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if packet is Dictionary and packet.get("op") == "result_ack": acknowledgements += 1
		if session.state == "ended" and (close_after_send or acknowledgements > 0): break
		await process_frame
	if queued_before <= 32: failures.append("fixture did not establish a packet backlog")
	if session.state != "ended" or witness.finish_time != 60: failures.append("latest state and terminal result lost")
	if witness.feedback_time != 30: failures.append("control packet crossed its preceding snapshot")
	if witness.applied.size() >= 60: failures.append("superseded snapshots were not coalesced")
	if not close_after_send and acknowledgements != 1: failures.append("result receipt acknowledgement missing or duplicated")
	receipts.append({"closed_after_send": close_after_send, "queued": queued_before, "applied": witness.applied, "finish_time": witness.finish_time, "feedback_time": witness.feedback_time, "acks": acknowledgements, "state": session.state})
	session.leave_match()
	peer.close()
	server.stop()
	witness.queue_free()
	await process_frame
