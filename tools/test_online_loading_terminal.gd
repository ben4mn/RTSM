extends SceneTree
## Reproduce a terminal event before deferred Main creation and map readiness.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var session: Node = root.get_node("NetworkSession")
	var manager: Node = root.get_node("GameManager")
	var connection_failure: bool = "--connection-failure" in OS.get_cmdline_user_args()
	var reason: String = "Connection lost during loading" if connection_failure else "Opponent disconnected during loading"
	session._client_packet({"op": "matched", "slot": 0, "seed": 101, "match": 41, "civilizations": [0, 0]})
	session._client_packet({"op": "snapshot", "match": 41, "time": 7.5, "player": {"is_defeated": false}, "actors": []})
	if connection_failure:
		session._fail(reason)
	else:
		session._client_packet({"op": "ended", "winner": 0, "reason": reason})
	_check(not is_instance_valid(session.adapter), "Terminal event must arrive before match attachment")
	for frame: int in range(600):
		await process_frame
		if is_instance_valid(session.adapter):
			break
	_check(is_instance_valid(session.adapter), "Match scene never attached")
	if is_instance_valid(session.adapter):
		_check(manager.current_state == manager.GameState.GAME_OVER, "Late attachment resumed ended match")
		_check(session.adapter.main._game_over_shown, "Result screen missing after late attachment")
		_check(session.adapter.main._victory_reason == reason, "Terminal reason was lost")
		_check(is_equal_approx(manager.game_time, 7.5), "Pending snapshot was lost before terminal result")
		_check(manager.players[1].is_defeated, "Opponent defeat missing")
		_check(bool(manager.players[0].is_defeated) == connection_failure, "Wrong winner for delayed terminal event")
		_check(session._pending_terminal.is_empty(), "Terminal result was not consumed")
		_check(not session.send_command("age"), "Ended match accepted gameplay command")
		var result: CanvasLayer = session.adapter.main.get_node("GameOverScreen")
		_check(result.result_label.text == ("MATCH ENDED" if connection_failure else "VICTORY"), "Result misrepresents unknown winner")
		# Results return to the shared New Game flow introduced with private rooms.
		_check(result.play_again_button.text == "New game", "Online replay action is unclear")
		_check(not result.score_bar.visible and not result.panel.get_node("Margin/VBox/StatsHeader/Right").visible, "Online result fabricated opponent comparisons")
	_check(session.state == ("error" if connection_failure else "ended"), "Wrong terminal transport state")
	# A late start frame must never reactivate the terminal transport.
	session._client_packet({"op": "started"})
	_check(session.state == ("error" if connection_failure else "ended"), "Late start reopened terminal match")
	print("ONLINE_LOADING_TERMINAL_VERIFIED failure=%s failures=%s" % [connection_failure, failures])
	quit(0 if failures.is_empty() else 1)
