extends SceneTree
## Real new-client handshake against a frozen older authority plus strict
## reply parsing. Runner supplies an owned loopback endpoint; no public access.
var session: Node
var started: int = 0
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _run() -> void:
	session = root.get_node("NetworkSession")
	_expect(int(session.PROTOCOL) == 6, "actual client source declares Scout-vision protocol6")
	_expect(int(session.MAP_CATALOG_VERSION) == 3, "terrain catalog3 remains unchanged")
	for valid: Variant in [6, 6.0]:
		_expect(bool(session.call("_whole_number", valid)), "integral JSON6/6.0 accepted")
	for invalid: Variant in [6.5, "6", true, null, INF, NAN]:
		_expect(not bool(session.call("_whole_number", invalid)), "nonintegral/string/bool/nonfinite protocol rejected")
	for operation: String in ["room", "matched"]:
		for invalid: Variant in [null, 2, 3, 4, 5, 6.5, "6", true, INF, NAN]:
			session.leave_match()
			var packet := {"op": operation, "protocol": invalid}
			if invalid == null:
				packet.erase("protocol")
			session.call("_client_packet", packet)
			_expect(session.state == "error" and not session.online and str(session.last_error).to_lower().contains("reload"), "invalid/old reply cannot enter lobby/loading")
	session.leave_match()
	session.call("_client_packet", {"op": "room", "protocol": 6.0, "code": "ABCDEF", "host": true, "players": 1, "map_archetype": 0, "civilizations": [1, 2]})
	_expect(session.state == "lobby", "valid integral6.0 room reply enters lobby")
	session.leave_match()
	var endpoint := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--old-url="):
			endpoint = argument.trim_prefix("--old-url=")
	var endpoint_pattern := RegEx.create_from_string("^ws://127\\.0\\.0\\.1:[0-9]+/match$")
	_expect(endpoint_pattern.search(endpoint) != null, "fixture has exact owned loopback endpoint")
	if not failures.is_empty():
		_finish()
		return
	started = Time.get_ticks_msec()
	session.host_game(0, endpoint)
	_expect(int(session.get("_connection_request").protocol) == 6, "real host_game transmits current protocol6 request")

func _process(_delta: float) -> bool:
	if started <= 0:
		return false
	if session.state == "error":
		_expect(str(session.last_error).to_lower().contains("reload") and not session.online, "frozen older authority rejects actual new6 client explicitly")
		_finish()
	elif Time.get_ticks_msec() - started > 10000:
		_expect(false, "older/new6 actual socket rejection timed out")
		_finish()
	return false

func _finish() -> void:
	started = 0
	session.leave_match()
	for failure: String in failures:
		push_error("[FAIL] protocol3_client_compatibility: " + failure)
	print("PROTOCOL3_CLIENT_COMPATIBILITY checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
