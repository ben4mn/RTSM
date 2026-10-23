extends SceneTree
## A real client observer: every gameplay action uses the production network API.
## No grants, teleports, direct authority mutations, or accelerated clock.
var session: Node
var manager: Node
var output := ""
var role := "host"
var map_choice := 0
var scenario := "match"
var room_mode := true
var start_us := 0
var match_us := 0
var last_policy := -10.0
var last_progress := -30.0
var last_army_order := -60.0
var last_build := -10.0
var started := false
var joined := false
var finishing := false
var capture_busy := false
var snapshots: FileAccess
var actions: FileAccess
var last_snapshot: Dictionary = {}
var coverage: Dictionary = {"snapshots": 0, "replica_checks": 0, "selected_replica_cycles": 0, "damage_observations": 0, "visible_enemies": 0, "max_age": 1, "demolition_sent": false, "research": [], "buildings": {}, "unit_types": {}}
var failures: Array[String] = []
var previous_hp: Dictionary = {}
var report: Dictionary = {}
var recruited := 0
var minimum_wall := 0.0
var duration_limit := 1100.0
var did_interrupt := false
var expected_scale := 1.0

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output = argument.trim_prefix("--output-dir=")
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--map="): map_choice = int(argument.trim_prefix("--map="))
		if argument.begins_with("--scenario="): scenario = argument.trim_prefix("--scenario=")
		if argument.begins_with("--minimum-wall="): minimum_wall = float(argument.trim_prefix("--minimum-wall="))
		if argument.begins_with("--timeout="): duration_limit = float(argument.trim_prefix("--timeout="))
		if argument == "--queue": room_mode = false
		if argument.begins_with("--expected-scale="): expected_scale = float(argument.trim_prefix("--expected-scale="))
	DirAccess.make_dir_recursive_absolute(output)
	start_us = Time.get_ticks_usec()
	session = root.get_node("NetworkSession")
	manager = root.get_node("GameManager")
	manager.guided_opening_enabled = false
	manager.master_volume = 0.0
	root.size = Vector2i(1100, 700) if role == "host" else Vector2i(844, 390)
	root.position = Vector2i(30, 40) if role == "host" else Vector2i(570, 450)
	root.title = "Company • multiplayer witness • " + role
	snapshots = FileAccess.open(output.path_join(role + "-snapshots.jsonl"), FileAccess.WRITE)
	actions = FileAccess.open(output.path_join(role + "-actions.jsonl"), FileAccess.WRITE)
	report = {"role": role, "pid": OS.get_process_id(), "scenario": scenario, "native": DisplayServer.get_name() != "headless", "fixed_fps": "--fixed-fps" in OS.get_cmdline_args(), "requested_scale": expected_scale, "status_events": [], "started_unix": Time.get_unix_time_from_system(), "user_data": OS.get_user_data_dir(), "engine": Engine.get_version_info(), "scope": "Independent real WebSocket Godot client with normal paid scripted commands; client viewport screenshots; no physical-device or hands-on claim."}
	root.close_requested.connect(func() -> void: _lifecycle("window_close_requested"))
	root.focus_entered.connect(func() -> void: _lifecycle("window_focus_entered"))
	root.focus_exited.connect(func() -> void: _lifecycle("window_focus_exited"))
	_lifecycle("started")
	session.snapshot_received.connect(_snapshot)
	session.match_ended.connect(_ended)
	session.status_changed.connect(_status)
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await process_frame
	await process_frame
	await _capture("00-menu")
	if room_mode:
		if role == "host": session.host_game(map_choice)
	else:
		session.find_match()

func _process(_delta: float) -> bool:
	if session == null or finishing:
		return false
	if _wall() > duration_limit:
		_fail("client_timeout")
		return false
	if room_mode and role == "guest" and not joined and FileAccess.file_exists(output.path_join("room-code.txt")):
		var code: String = FileAccess.get_file_as_string(output.path_join("room-code.txt")).strip_edges()
		if not code.is_empty():
			joined = true
			session.join_game(code)
	if room_mode and session.state == "lobby" and role == "host":
		if not FileAccess.file_exists(output.path_join("room-code.txt")):
			FileAccess.open(output.path_join("room-code.txt"), FileAccess.WRITE).store_string(session.room_code)
		if session.room_players == 2 and not started:
			started = session.start_hosted_match()
	return false

func _status(state: String, message: String) -> void:
	print("PAIR_STATUS ", role, " wall=", _wall(), " ", state, " ", message)
	if report.has("status_events"): report.status_events.append({"wall": _wall(), "state": state, "message": message})
	if state == "playing" and match_us == 0:
		match_us = Time.get_ticks_usec()
	if state == "error":
		if scenario == "interrupt" and did_interrupt:
			call_deferred("_interrupted_result", message)
		else:
			_fail("connection_error: " + message)

func _snapshot(data: Dictionary) -> void:
	if finishing or session.state != "playing": return
	last_snapshot = data.duplicate(true)
	var t: float = float(data.time)
	if not report.has("slot"):
		var game_map: Node = current_scene.get_node("GameMap")
		var expected := MapGenerator.new(session.match_seed, session.match_map_archetype)
		var expected_grid: Array = expected.generate()
		report.merge({"slot": session.player_slot, "match": session.match_id, "seed": session.match_seed, "map": session.match_map_archetype, "grid_hash": JSON.stringify(game_map.map_generator.grid).sha256_text(), "map_verified": game_map.map_generator.grid == expected_grid, "requested_map": map_choice})
		if not report.map_verified: failures.append("loaded_grid_mismatch")
		if room_mode and session.match_map_archetype != map_choice: failures.append("host_map_mismatch")
		call_deferred("_capture", "01-opening")
	coverage.snapshots += 1
	if not is_equal_approx(Engine.time_scale, expected_scale) and "clock_not_requested_scale" not in failures:
		failures.append("clock_not_requested_scale")
	_check_replicas(data)
	for actor: Dictionary in data.actors:
		var id: int = int(actor.id)
		if previous_hp.has(id) and float(actor.hp) < float(previous_hp[id]):
			coverage.damage_observations += 1
		previous_hp[id] = float(actor.hp)
		if int(actor.owner) != session.player_slot: coverage.visible_enemies += 1
		elif actor.kind == "building" and int(actor.state) == 2: coverage.buildings[str(int(actor.type))] = true
		elif actor.kind == "unit": coverage.unit_types[str(int(actor.type))] = true
	coverage.max_age = maxi(int(coverage.max_age), int(data.player.age))
	coverage.research = data.research
	if int(data.tick) % 10 == 0:
		snapshots.store_line(JSON.stringify({"wall": _match_wall(), "engine_scale": Engine.time_scale, "packet": data}))
		snapshots.flush()
	if t - last_policy >= 2.0:
		last_policy = t
		_policy(data)
	if t - last_progress >= 30.0:
		last_progress = t
		_write_progress()
		print("PAIR_PROGRESS ", JSON.stringify({"role": role, "time": t, "wall": _match_wall(), "bank": data.bank, "age": data.player.age, "stats": data.stats, "coverage": coverage, "failures": failures}))
		if int(t) % 180 < 31: call_deferred("_capture", "time-%04d" % int(t))
	if scenario == "interrupt" and role == "guest" and t >= 35.0 and not did_interrupt:
		did_interrupt = true
		# Abrupt transport closure, without the polite leave packet.
		session._socket.close(1001, "Witness interruption")

func _check_replicas(data: Dictionary) -> void:
	var adapter: Node = session.adapter
	var resource_manager: Node = root.get_node("ResourceManager")
	for resource: String in ["food", "wood", "gold"]:
		if int(resource_manager.get_all_resources(0).get(resource, -1)) != int(data.bank.get(resource, -2)):
			_record_failure("bank_replica_" + resource)
	if manager.get_player_age(0) != int(data.player.age): _record_failure("age_replica")
	for field: String in ["population", "population_reserved", "population_cap", "max_population", "is_defeated"]:
		if manager.players[0][field] != data.player[field]: _record_failure("player_replica_" + field)
	if manager.researched_upgrades[0] != data.research: _record_failure("research_replica")
	for item: Array in data.resources:
		var resource: Node2D = current_scene.get_node("GameMap").get_resource_node_at(Vector2i(int(item[0]), int(item[1])))
		if is_instance_valid(resource) and int(resource.remaining) != int(item[2]): _record_failure("resource_replica")
	for actor: Dictionary in data.actors:
		var replica: Node = adapter.entities.get(int(actor.id))
		if not is_instance_valid(replica):
			_record_failure("missing_replica")
			continue
		var expected_owner := 0 if int(actor.owner) == session.player_slot else 1
		if int(replica.player_owner) != expected_owner: _record_failure("ownership_replica")
		if not is_equal_approx(float(replica.hp), float(actor.hp)): _record_failure("hp_replica")
		if replica.process_mode != Node.PROCESS_MODE_DISABLED: _record_failure("replica_simulation_enabled")
		coverage.replica_checks += 1

func _policy(data: Dictionary) -> void:
	var own: int = session.player_slot
	var workers: Array[Dictionary] = []
	var army: Array[int] = []
	var buildings: Dictionary = {}
	var foundation_active := false
	for actor: Dictionary in data.actors:
		if int(actor.owner) != own: continue
		if actor.kind == "unit":
			if int(actor.type) == 0: workers.append(actor)
			else: army.append(int(actor.id))
		else:
			var type: int = int(actor.type)
			if int(actor.state) != 2: foundation_active = true
			if not buildings.has(type): buildings[type] = []
			buildings[type].append(actor)
	var bank: Dictionary = data.bank.duplicate()
	var t: float = float(data.time)
	var town: Dictionary = _active(buildings, 0)
	if not town.is_empty() and workers.size() < 12 and _queued(town) < 1 and _afford(bank, UnitData.get_unit_cost(0)):
		_send("train", {"target": int(town.id), "type": 0})
		_spend(bank, UnitData.get_unit_cost(0))
	var tasks := {"food": 0, "wood": 0, "gold": 0}
	for worker: Dictionary in workers:
		var work: String = str(worker.get("work", ""))
		if tasks.has(work): tasks[work] += 1
	for worker: Dictionary in workers:
		if str(worker.get("work", "")) != "" or bool(worker.get("recovering", false)): continue
		var job: String = "food"
		if int(tasks.wood) < 4: job = "wood"
		elif int(tasks.gold) < 3: job = "gold"
		_send("allocate", {"source": "idle", "destination": job})
		tasks[job] += 1
		break
	if not workers.is_empty() and not foundation_active and t - last_build >= 5.0:
		var build_type := -1
		if int(data.player.population_cap) < 30 and int(data.player.population) + int(data.player.get("population_reserved", 0)) >= int(data.player.population_cap) - 2: build_type = 1
		elif t > 260.0 and not coverage.demolition_sent and buildings.get(1, []).size() < 2: build_type = 1
		elif not buildings.has(2): build_type = 2
		elif not buildings.has(9) and t > 55: build_type = 9
		elif buildings.get(5, []).size() < (6 if t > 700 else 2) and t > 100: build_type = 5
		elif not buildings.has(3) and int(data.player.age) >= 2: build_type = 3
		elif not buildings.has(4) and int(data.player.age) >= 2: build_type = 4
		elif not buildings.has(8) and int(data.player.age) >= 3: build_type = 8
		if build_type >= 0 and _afford(bank, BuildingData.get_building_cost(build_type)):
			if _place(build_type, workers):
				last_build = t
				_spend(bank, BuildingData.get_building_cost(build_type))
	if int(data.player.age) < 3:
		var cost: Dictionary = manager.get_age_up_cost(0, int(data.player.age) + 1)
		if _afford(bank, cost):
			_send("age")
			_spend(bank, cost)
	var smith: Dictionary = _active(buildings, 9)
	if not smith.is_empty():
		for tech: Dictionary in TechData.RESEARCH_DEFS:
			if str(tech.id) not in data.research and _afford(bank, tech.cost):
				_send("research", {"target": int(smith.id), "research": str(tech.id)})
				_spend(bank, tech.cost)
				break
	# Repeated paid recruitment replaces actual casualties. Reserve late age-up food.
	var reserve := 0 if int(data.player.age) >= 3 or t < 180.0 else (260 if int(data.player.age) == 1 else 620)
	var emergency_minimum := 3 if t < 180.0 or int(data.player.age) >= 3 else 0
	if army.size() < 12 and (int(bank.food) > reserve or army.size() < emergency_minimum):
		for building_type: int in [2, 3, 4, 8]:
			var production: Dictionary = _active(buildings, building_type)
			var unit_type: int = {2: 1, 3: 2, 4: 3, 8: 5}[building_type]
			if production.is_empty() or _queued(production) >= 1: continue
			if _afford(bank, UnitData.get_unit_cost(unit_type)):
				_send("train", {"target": int(production.id), "type": unit_type})
				_spend(bank, UnitData.get_unit_cost(unit_type))
	if not army.is_empty() and t - last_army_order >= 24.0:
		last_army_order = t
		var map: Node = current_scene.get_node("GameMap")
		var selected: Array[Node2D] = []
		for id: int in army:
			var replica: Node2D = session.adapter.entities.get(id) as Node2D
			if is_instance_valid(replica): selected.append(replica)
		map.selection_mgr.select_many(selected)
		coverage.selected_replica_cycles += 1
		var target: Vector2 = _battle_position(map)
		# Short cases finish through ordinary objective capture once economy,
		# research, production, damage and losses have had time to occur.
		if scenario == "match" and t > 650.0:
			if role == "host": target = map.sacred_site.global_position
			else: target = map.tile_to_world(map.map_generator.spawn_positions[own])
		_send("attack_move", {"ids": army, "position": [target.x, target.y]})
		map.camera.position = target if t > 150.0 else map.tile_to_world(map.map_generator.spawn_positions[own])
		map._clamp_camera()
	# The normal Demolish command exercises live replica building deletion and
	# subsequent replacement, without killing a structure through fixture damage.
	if t > 300.0 and not coverage.demolition_sent and buildings.get(1, []).size() >= 2:
		var house: Dictionary = _active(buildings, 1)
		if not house.is_empty():
			var replica: Node2D = session.adapter.entities.get(int(house.id)) as Node2D
			if is_instance_valid(replica): current_scene.get_node("GameMap").selection_mgr.select_single(replica)
			_send("delete", {"target": int(house.id)})
			coverage.demolition_sent = true

func _battle_position(map: Node) -> Vector2:
	# Far enough from the objective to avoid ending the sustained run early.
	var origin: Vector2i = map.world_to_tile(map.sacred_site.global_position) + Vector2i(12, 12)
	for radius: int in range(0, 8):
		for x: int in range(-radius, radius + 1):
			for y: int in range(-radius, radius + 1):
				var tile: Vector2i = origin + Vector2i(x, y)
				if map.is_tile_walkable(tile): return map.tile_to_world(tile)
	return map.sacred_site.global_position + Vector2(0, 450)

func _place(type: int, workers: Array[Dictionary]) -> bool:
	var map: Node = current_scene.get_node("GameMap")
	var spawn: Vector2i = map.map_generator.spawn_positions[session.player_slot]
	for radius: int in range(4, 15):
		for dx: int in range(-radius, radius + 1):
			for dy: int in [-radius, radius]:
				var world: Vector2 = map.tile_to_world(spawn + Vector2i(dx, dy))
				if current_scene._building_placement.revalidate_confirmation(type, world, 0):
					_send("place", {"type": type, "ids": [int(workers[0].id)], "position": [world.x, world.y]})
					return true
	return false

func _active(buildings: Dictionary, type: int) -> Dictionary:
	for building: Dictionary in buildings.get(type, []):
		if int(building.state) == 2: return building
	return {}

func _queued(building: Dictionary) -> int:
	return building.get("queue", {}).get("items", []).size()

func _afford(bank: Dictionary, cost: Dictionary) -> bool:
	if cost.is_empty(): return false
	for resource: String in cost:
		if int(bank.get(resource, 0)) < int(cost[resource]): return false
	return true

func _spend(bank: Dictionary, cost: Dictionary) -> void:
	for resource: String in cost: bank[resource] = int(bank.get(resource, 0)) - int(cost[resource])

func _send(operation: String, payload: Dictionary = {}) -> void:
	var sent: bool = session.send_command(operation, payload)
	actions.store_line(JSON.stringify({"wall": _match_wall(), "time": last_snapshot.get("time", 0), "operation": operation, "payload": payload, "sent": sent}))
	actions.flush()

func _ended(winner: int, reason: String) -> void:
	if finishing: return
	finishing = true
	report.merge({"winner": winner, "reason": reason, "match_wall_seconds": _match_wall(), "total_wall_seconds": _wall(), "game_seconds": last_snapshot.get("time", 0)})
	if scenario == "sustained" and _match_wall() < minimum_wall: failures.append("sustained_wall_short")
	call_deferred("_finish")

func _interrupted_result(message: String) -> void:
	if finishing: return
	finishing = true
	report.merge({"winner": -1, "reason": message, "intentional_interruption": true, "match_wall_seconds": _match_wall(), "total_wall_seconds": _wall(), "game_seconds": last_snapshot.get("time", 0)})
	await _finish()

func _finish() -> void:
	await process_frame
	# The ordinary result panel fades in over 0.4 seconds, even while paused.
	await create_timer(0.5, true, false, true).timeout
	await _capture("90-result")
	var results: Node = current_scene.get_node_or_null("GameOverScreen")
	if results == null:
		for child: Node in current_scene.get_children():
			if child.has_signal("main_menu_requested"): results = child
	if results != null:
		report.result_visible = results.visible
		var button: Button = results.get("main_menu_button")
		if button != null:
			# Real viewport click through the visible ordinary result button.
			var event := InputEventMouseButton.new()
			event.position = button.get_global_rect().get_center()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			root.push_input(event, true)
			await process_frame
			event = event.duplicate()
			event.pressed = false
			root.push_input(event, true)
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	report.menu_return_verified = current_scene != null and current_scene.scene_file_path == "res://scenes/ui/main_menu.tscn" and not paused and session.state == "idle"
	if not bool(report.menu_return_verified): failures.append("result_menu_return")
	await _capture("99-returned-menu")
	_write_report()
	print("PAIR_CLIENT_COMPLETE ", JSON.stringify(report))
	_lifecycle("harness_quit_requested", "completed" if failures.is_empty() else "completed_with_failures")
	quit(0 if failures.is_empty() else 1)

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or capture_busy: return
	capture_busy = true
	await RenderingServer.frame_post_draw
	var texture: Texture2D = root.get_texture()
	if texture != null:
		texture.get_image().save_png(output.path_join(role + "-" + label + ".png"))
	capture_busy = false

func _record_failure(message: String) -> void:
	if message not in failures: failures.append(message)

func _fail(message: String) -> void:
	if finishing: return
	finishing = true
	_record_failure(message)
	_write_report()
	push_error("PAIR_CLIENT_FAILURE " + message)
	_lifecycle("harness_quit_requested", message)
	quit(1)

func _finalize() -> void:
	_lifecycle("scene_tree_finalize")

func _lifecycle(event: String, reason: String = "") -> void:
	if output.is_empty(): return
	var path := output.path_join(role + "-lifecycle.jsonl")
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null: return
	file.seek_end()
	file.store_line(JSON.stringify({"event": event, "reason": reason, "role": role, "pid": OS.get_process_id(), "unix": Time.get_unix_time_from_system(), "wall": _wall(), "match_wall": _match_wall(), "game_seconds": last_snapshot.get("time", 0), "network_state": session.state if is_instance_valid(session) else "unavailable", "finishing": finishing}))
	file.flush()

func _write_progress() -> void:
	var progress := {"role": role, "wall": _match_wall(), "time": last_snapshot.get("time", 0), "coverage": coverage, "stats": last_snapshot.get("stats", {}), "bank": last_snapshot.get("bank", {}), "failures": failures}
	FileAccess.open(output.path_join(role + "-progress.json"), FileAccess.WRITE).store_string(JSON.stringify(progress, "\t"))

func _write_report() -> void:
	report.total_wall_seconds = _wall()
	if not report.has("match_wall_seconds"): report.match_wall_seconds = _match_wall()
	report.coverage = coverage
	report.failures = failures
	report.final_snapshot = last_snapshot
	FileAccess.open(output.path_join(role + "-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))

func _wall() -> float:
	return float(Time.get_ticks_usec() - start_us) / 1000000.0

func _match_wall() -> float:
	return float(Time.get_ticks_usec() - match_us) / 1000000.0 if match_us > 0 else 0.0
