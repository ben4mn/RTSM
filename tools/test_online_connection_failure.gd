extends SceneTree
## An unavailable listener must return a user-facing error, never start solo AI.
var elapsed := 0.0
var session: Node

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	session = root.get_node("NetworkSession")
	session.status_changed.connect(_status)
	session.find_match("ws://127.0.0.1:1")

func _status(value: String, message: String) -> void:
	if value == "error":
		if message.is_empty() or session.is_network_match():
			quit(1)
		else:
			print("ONLINE_CONNECTION_FAILURE_VERIFIED explicit_error=true no_solo_fallback=true")
			quit(0)

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 15.0:
		push_error("Connection error was not reported")
		quit(1)
	return false
