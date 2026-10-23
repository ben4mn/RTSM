extends SceneTree
## Run against a frozen legacy server that answers ping but ignores private rooms.
var session: Node
var start_msec: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	session = root.get_node("NetworkSession")
	start_msec = Time.get_ticks_msec()
	session.status_changed.connect(_status)
	session.host_game(1)

func _status(value: String, message: String) -> void:
	if value != "error":
		return
	var elapsed: float = float(Time.get_ticks_msec() - start_msec) / 1000.0
	if not message.contains("private lobbies") or session.online:
		failures.append("Legacy service must fail private lobbies explicitly without loading a match")
	if elapsed < 11.0 or elapsed > 15.0:
		failures.append("Lobby negotiation must time out even while legacy server answers pings")
	for failure: String in failures:
		push_error("[FAIL] online_lobby_compatibility: " + failure)
	print("ONLINE_LOBBY_COMPATIBILITY elapsed=%.2f failures=%s" % [elapsed, failures])
	quit(0 if failures.is_empty() else 1)

func _process(_delta: float) -> bool:
	if start_msec > 0 and Time.get_ticks_msec() - start_msec > 17000:
		push_error("Legacy server kept private lobby waiting forever")
		quit(1)
	return false
