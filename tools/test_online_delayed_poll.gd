extends SceneTree
## Real socket and production keepalive settings: delay a poll while a reply is
## already in flight. Native automatic heartbeat must not discard that reply.
var session: Node
var started: int = 0
var checked: bool = false
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("NetworkSession")
	session.find_match()
	started = Time.get_ticks_msec()
	for frame: int in 1200:
		await process_frame
		if session.state == "searching" and session._socket != null and session._socket.get_available_packet_count() == 0:
			break
	if session.state != "searching":
		push_error("Failed to enter actual server queue")
		quit(1)
		return
	session.set_process(false)
	# Godot's native heartbeat is measured from process start. Avoid receiving
	# its first Pong until after the next five-second interval has elapsed.
	while Time.get_ticks_msec() < 5200:
		await process_frame
	session._socket.poll()
	# Also queue an application reply. The server keeps processing throughout.
	session._send(session._socket, {"op": "ping"})
	var delay_at: int = Time.get_ticks_msec()
	OS.delay_msec(5600)
	session._process(0.016)
	var delay: float = float(Time.get_ticks_msec() - delay_at) / 1000.0
	if session.state != "searching" or session._socket == null or session._socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		failures.append("queued live server response discarded after delayed polling")
	for failure: String in failures:
		push_error("[FAIL] online_delayed_poll: " + failure)
	print("ONLINE_DELAYED_POLL delay=%.2f state=%s failures=%s" % [delay, session.state, failures])
	session.leave_match()
	quit(0 if failures.is_empty() else 1)
