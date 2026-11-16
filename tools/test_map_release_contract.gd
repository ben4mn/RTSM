extends Node
## Real protocol handlers and actual solo scene setup, without public sockets.

class Recorder extends "res://scripts/network/network_session.gd":
	var sent: Array[Dictionary] = []
	func _send_peer(_id: int, packet: Dictionary) -> void:
		sent.append(packet)

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	var server := Recorder.new()
	server.set("_peers", {1: {}})
	for operation: String in ["search", "host", "join"]:
		server.sent.clear()
		server.call("_server_packet", 1, {"op": operation, "protocol": 10, "map_catalog": 6, "map_archetype": 0, "civilization": 0, "code": "ABCDEF"})
		_expect(server.sent.size() == 1 and server.sent[0].op == "error" and str(server.sent[0].reason).to_lower().contains("reload"), "pre-axis-fix stock cannot enter " + operation)
		_expect((server.get("_queue") as Array).is_empty() and (server.get("_rooms") as Dictionary).is_empty(), "pre-axis-fix stock cannot reserve lobby or queue")
		server.sent.clear()
		server.call("_server_packet", 1, {"op": operation, "protocol": 9, "map_catalog": 5, "map_archetype": 0, "civilization": 0, "code": "ABCDEF"})
		_expect(server.sent.size() == 1 and server.sent[0].op == "error" and str(server.sent[0].reason).to_lower().contains("reload"), "beta14 pacing cannot enter " + operation)
		_expect((server.get("_queue") as Array).is_empty() and (server.get("_rooms") as Dictionary).is_empty(), "old stock cannot reserve lobby or queue")
		server.sent.clear()
		server.call("_server_packet", 1, {"op": operation, "protocol": 6, "map_catalog": 3, "map_archetype": 0, "civilization": 0, "code": "ABCDEF"})
		_expect(server.sent.size() == 1 and server.sent[0].op == "error" and str(server.sent[0].reason).to_lower().contains("reload"), "prior berry layout cannot enter " + operation)
		_expect((server.get("_queue") as Array).is_empty() and (server.get("_rooms") as Dictionary).is_empty(), "prior berry layout cannot reserve lobby or queue")
		server.sent.clear()
		server.call("_server_packet", 1, {"op": operation, "protocol": 4, "map_catalog": 3, "map_archetype": 0, "civilization": 0, "code": "ABCDEF"})
		_expect(server.sent.size() == 1 and server.sent[0].op == "error" and str(server.sent[0].reason).to_lower().contains("reload"), "30-pop protocol4 cannot enter " + operation)
		_expect((server.get("_queue") as Array).is_empty() and (server.get("_rooms") as Dictionary).is_empty(), "old population rules cannot reserve lobby or queue")
		server.sent.clear()
		server.call("_server_packet", 1, {"op": operation, "protocol": 3, "map_catalog": 2, "map_archetype": 0, "civilization": 0, "code": "ABCDEF"})
		_expect(server.sent.size() == 1 and server.sent[0].op == "error" and str(server.sent[0].reason).to_lower().contains("reload"), "old generator cannot enter " + operation)
		_expect((server.get("_queue") as Array).is_empty() and (server.get("_rooms") as Dictionary).is_empty(), "old version cannot reserve lobby or queue")
	for catalog: int in [-1, 2, 3, 5, 6, 99]:
		server.sent.clear()
		var packet := {"op": "search", "protocol": NetworkSession.PROTOCOL, "civilization": 0}
		if catalog >= 0:
			packet["map_catalog"] = catalog
		server.call("_server_packet", 1, packet)
		_expect(server.sent.size() == 1 and server.sent[0].op == "error", "current protocol still requires current terrain catalog")
		_expect((server.get("_queue") as Array).is_empty(), "incompatible catalog cannot enter queue")
	server.sent.clear()
	server.call("_server_packet", 1, {"op": "search", "protocol": NetworkSession.PROTOCOL, "map_catalog": NetworkSession.MAP_CATALOG_VERSION, "civilization": 1})
	_expect(server.sent.size() == 1 and server.sent[0].op == "queued", "current protocol queues normally")
	server.free()
	for operation: String in ["room", "matched"]:
		NetworkSession.leave_match()
		NetworkSession.call("_client_packet", {"op": operation, "protocol": 4})
		_expect(NetworkSession.state == "error" and not NetworkSession.online and NetworkSession.last_error.to_lower().contains("reload"), "protocol5 client rejects old30-pop authority before " + operation)
	NetworkSession.leave_match()
	for civilization: int in CivilizationData.ORDERED_IDS:
		var seen: Dictionary = {}
		for seed_value: int in 32:
			var rival := CivilizationData.choose_solo_opponent(civilization, seed_value)
			_expect(rival != civilization and CivilizationData.is_valid(rival), "automatic rival contrasts with player")
			_expect(rival == CivilizationData.choose_solo_opponent(civilization, seed_value), "automatic rival is reproducible")
			seen[rival] = true
		_expect(seen.size() == 2, "both alternate settlements appear")
	# Exercise the real map-ready/initialize-game path, preserving Random prefs.
	get_tree().current_scene = null
	NetworkSession.leave_match()
	GameManager.selected_map_seed = -1
	GameManager.selected_civilization = 1
	GameManager.set_meta("auto_solo_opponent", true)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 30:
		await get_tree().process_frame
		if main.get("_building_placement") != null:
			break
	var map: Node = main.get_node("GameMap")
	_expect(main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING, "actual match startup completed")
	_expect(GameManager.players.has(1) and int(GameManager.players.get(1, {}).get("civilization", -1)) == CivilizationData.choose_solo_opponent(1, map.map_seed), "initialized opponent uses resolved settlement")
	_expect(GameManager.selected_map_seed == -1, "Random preference survives actual generation")
	_expect(map.map_seed == map.map_generator._rng.seed, "actual generated seed retained")
	_expect(map.map_seed > 0, "random map uses a replayable positive seed")
	var replay := MapGenerator.new(map.map_seed, map.map_archetype)
	_expect(replay.generate() == map.map_generator.grid, "random startup map can be replayed exactly")
	_expect(GameManager.get_player_civilization(1) == CivilizationData.choose_solo_opponent(1, map.map_seed), "automatic rival latched before actors initialize")
	_expect(not GameManager.has_meta("auto_solo_opponent"), "one-shot automatic choice consumed")
	main.free()
	for failure: String in failures:
		push_error("[FAIL] map_release_contract: " + failure)
	if failures.is_empty():
		print("[PASS] map_release_contract: old generator rejection, current queue, deterministic contrasting rivals and actual random-seed startup")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
