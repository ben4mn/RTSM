extends "res://tools/probe_native_busy_front.gd"
## Exactly100 population/owner:30 working Villagers,1 Scout,69 fighters.
## Fixture-only free replacements maintain the load after ordinary combat deaths.
const Buckets = preload("res://tools/performance_buckets.gd")
var timeline: Array[Dictionary] = []
var replacements: int = 0
var replenish: bool = false
var start_usec: int = 0
var armies: Array[Array] = [[], []]
var seconds: float = 30.0
var leaders: Array[UnitBase] = [null, null]
var failures: Array[String] = []
var measured_wall_seconds: float = 0.0
var army_orders: Array[Dictionary] = []

func _ready() -> void:
	process_priority = 10000
	super._ready()

func _process(delta: float) -> void:
	var last: int = previous_usec
	super._process(delta)
	if active:
		timeline.append({"wall_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0, "frame_ms": float(previous_usec - last) / 1000.0, "cpu": Buckets.take_frame(), "population": [GameManager.players[0].population, GameManager.players[1].population]})
	else:
		Buckets.take_frame()

func _run() -> void:
	if OS.has_feature("web"):
		var start_layer := CanvasLayer.new()
		start_layer.layer = 100
		add_child(start_layer)
		var start_button := Button.new()
		start_button.text = "Start 100 vs 100 battle benchmark"
		start_button.position = Vector2(24, 24)
		start_button.custom_minimum_size = Vector2(400, 64)
		start_layer.add_child(start_button)
		await start_button.pressed
		start_layer.queue_free()
	output = OS.get_environment("AOEM_BUSY_OUTPUT")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	seconds = float(OS.get_environment("AOEM_BATTLE_SECONDS")) if not OS.get_environment("AOEM_BATTLE_SECONDS").is_empty() else 30.0
	AudioManager.set_all_enabled(OS.get_environment("AOEM_BATTLE_AUDIO") != "0")
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_population_limit = 100
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.ui_scale = 1.0
	Engine.time_scale = 1.0
	if not OS.has_feature("web"):
		get_window().size = Vector2i(1280, 720)
		get_window().content_scale_size = Vector2i(1280, 720)
	GameManager.set_state(GameManager.GameState.MENU)
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	var guard: Node = main.get("_match_background_guard")
	if is_instance_valid(guard):
		guard.background_changed.disconnect(main._on_match_background_changed)
		guard.queue_free()
		main.set("_match_background_guard", null)
	if GameManager.current_state == GameManager.GameState.PAUSED: main.call("_on_resume_requested")
	main.ai_controller.set_process(false)
	main.ai_controller.get("_decision_timer").stop()
	for owner: int in 2:
		GameManager.grant_population_cap(owner, 98000 + owner, 100)
		var base: BuildingBase = main.get("_player_buildings")[owner][0]
		var initial: Array = main.get("_player_units")[owner].duplicate()
		for unit: UnitBase in initial:
			if unit is Villager: _assign_worker(unit, owner, base.global_position)
		for index: int in 26:
			var worker: Villager = main.call("_spawn_unit", UnitData.UnitType.VILLAGER, owner, _walkable(main.game_map.world_to_tile(base.global_position) + Vector2i(index % 5 - 2, index / 5 + 4)))
			_assign_worker(worker, owner, base.global_position)
		for index: int in 69:
			_spawn_fighter(owner, index)
	replenish = true
	main.call("_update_fog_of_war")
	main.game_map.note_camera_interaction()
	main.game_map.set("_user_zoom_override", true)
	main.game_map.camera.zoom = Vector2(0.85, 0.85)
	main.game_map.camera.position = main.game_map.tile_to_world(Vector2i(41, 35))
	main.game_map.camera.reset_smoothing()
	main.game_map.camera.force_update_scroll()
	await get_tree().create_timer(3.0).timeout
	# Native offscreen fixture bypass only; Web audio is activated by the real
	# Start gesture. Keep the ordinary scheduler/voice limits during the battle.
	if not OS.has_feature("web"): AudioManager.set("_backgrounded", false)
	frames.clear()
	process_times.clear()
	physics_times.clear()
	render_objects.clear()
	responses.clear()
	Buckets.enabled = true
	active = true
	start_usec = Time.get_ticks_usec()
	var initial_sim: float = GameManager.game_time
	var scout: UnitBase = (main.get("_player_units")[0] as Array).filter(func(unit: UnitBase) -> bool: return unit.unit_type == UnitData.UnitType.SCOUT)[0]
	scout.global_position = _walkable(Vector2i(38, 29))
	for index: int in 4:
		var began: int = Time.get_ticks_msec()
		await _battle_response(scout, index)
		await get_tree().create_timer(maxf(0.0, seconds / 4.0 - float(Time.get_ticks_msec() - began) / 1000.0)).timeout
	measured_wall_seconds = float(Time.get_ticks_usec() - start_usec) / 1000000.0
	active = false
	Buckets.enabled = false
	# Freeze only after sampling, before waiting for a screenshot draw; otherwise
	# ordinary late combat deaths make the evidence image lose the stated load.
	main.process_mode = Node.PROCESS_MODE_DISABLED
	GameManager.set_state(GameManager.GameState.PAUSED)
	main.game_map.camera.position = main.game_map.tile_to_world(Vector2i(41, 35))
	main.game_map.camera.reset_smoothing()
	main.game_map.camera.force_update_scroll()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	replenish = false
	var living: Array[int] = [0, 0]
	var fighting: Array[int] = [0, 0]
	var workers: Array[int] = [0, 0]
	for owner: int in 2:
		for unit: UnitBase in main.get("_player_units")[owner]:
			if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
				living[owner] += 1
				if unit.current_state == UnitBase.State.ATTACKING: fighting[owner] += 1
				if unit is Villager and unit.current_state in [UnitBase.State.GATHERING, UnitBase.State.MOVING]: workers[owner] += 1
	for frame: Dictionary in timeline:
		if frame.population != [100, 100]:
			failures.append("Population dropped during sampling")
			break
	var report := {"scope": "Exactly100 population/owner;30 workers+1 Scout+69 fighters, including one isolated order-test fighter per owner. Synthetic instant reinforcements maintain load after normal damage/deaths. Real engine ScreenTouch/keyboard dispatch; not device touch latency. Background pause bypass fixture only. Instrumented runs are causal diagnostics only.", "platform": "web" if OS.has_feature("web") else "native", "source_revision": ProjectSettings.get_setting("application/config/playtest_revision", "working-tree"), "production_feature": OS.has_feature("production"), "viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y], "renderer": RenderingServer.get_video_adapter_name(), "sample_wall_seconds": measured_wall_seconds, "sim_seconds": GameManager.game_time - initial_sim, "replacements": replacements, "population": [GameManager.players[0].population, GameManager.players[1].population], "living": living, "fighting": fighting, "working": workers, "frames": _stats(frames), "input": responses, "failures": failures, "audio": AudioManager.get_audio_diagnostics(), "timeline": timeline}
	report["army_orders"] = army_orders
	if OS.has_feature("web"):
		report["browser_visibility"] = str(JavaScriptBridge.eval("document.visibilityState"))
		report["browser_has_focus"] = bool(JavaScriptBridge.eval("document.hasFocus()"))
	if not output.is_empty():
		FileAccess.open(output.path_join("population-battle.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join("population-battle.png"))
	report.erase("timeline")
	print("[POPULATION BATTLE] " + JSON.stringify(report))
	if OS.has_feature("web"):
		main.process_mode = Node.PROCESS_MODE_DISABLED
		set_process(false)
		var result_layer := CanvasLayer.new()
		result_layer.layer = 100
		add_child(result_layer)
		var result := Button.new()
		result.text = "100 / 100 population · p95 %.1f ms · %d input failures\nContinue battle" % [report.frames.p95, failures.size()]
		result.position = Vector2(24, 64)
		result.custom_minimum_size = Vector2(450, 70)
		result_layer.add_child(result)
		await result.pressed
		result_layer.queue_free()
		replenish = true
		main.process_mode = Node.PROCESS_MODE_INHERIT
		main.call("_on_resume_requested")
	else:
		main.free()
		get_tree().quit(0 if failures.is_empty() else 1)

func _assign_worker(worker: Villager, owner: int, origin: Vector2) -> void:
	var resource: String = ["food", "wood", "gold"][worker.get_index() % 3]
	var target: Node2D = main.game_map.get_nearest_resource_node(resource, origin, owner)
	if target != null: worker.command_gather(target)

func _spawn_fighter(owner: int, index: int) -> void:
	var type: int = UnitData.UnitType.INFANTRY if index < 35 else UnitData.UnitType.ARCHER if index < 59 else UnitData.UnitType.CAVALRY
	var tile := Vector2i(30 + owner * 18 + index % 8, 32 + index / 8)
	var unit: UnitBase = main.call("_spawn_unit", type, owner, _walkable(tile))
	armies[owner].append(unit)
	unit.unit_died.connect(_replace_fighter.bind(owner, index))
	if index == 0:
		leaders[owner] = unit
		unit.global_position = _walkable(Vector2i(37 + owner * 5, 30))
		unit.stance = UnitBase.Stance.STAND_GROUND
		unit.command_stop()
	else:
		unit.command_attack_move(_walkable(Vector2i(42, 36)))

func _replace_fighter(_unit: UnitBase, owner: int, index: int) -> void:
	if replenish:
		replacements += 1
		_spawn_fighter(owner, index)

func _battle_response(scout: UnitBase, index: int) -> void:
	var selection: SelectionManager = main.game_map.selection_mgr
	# Reset only the two disclosed order-test actors between samples. Their
	# health/stats stay ordinary; the other 136 fighters keep their live battle.
	for owner: int in 2:
		if is_instance_valid(leaders[owner]):
			leaders[owner].global_position = _walkable(Vector2i(37 + owner * 5, 25))
			leaders[owner].command_stop()
	main.game_map.camera.position = main.game_map.tile_to_world(Vector2i(40, 32))
	main.game_map.camera.reset_smoothing()
	main.game_map.camera.force_update_scroll()
	selection.deselect_all()
	await _tap("select Scout", _screen(scout), func() -> bool: return selection.selected == [scout])
	await _tap("Move arm", main.hud.get("_unit_move_button").get_global_rect().get_center(), func() -> bool: return bool(main.get("_move_command_armed")))
	var target: Vector2 = _walkable(Vector2i(37 + index % 2 * 3, 28))
	await _tap("Move accept", get_viewport().get_canvas_transform() * target, func() -> bool: return not bool(main.get("_move_command_armed")) and scout.current_state == UnitBase.State.MOVING)
	if not is_instance_valid(leaders[0]) or not is_instance_valid(leaders[1]):
		failures.append("Order-test fighter unavailable")
		return
	var fighter_id: int = leaders[0].get_instance_id()
	var enemy_id: int = leaders[1].get_instance_id()
	selection.deselect_all()
	await _tap("select fighter", _screen(leaders[0]), func() -> bool: return _selected_ids(selection.selected) == [fighter_id])
	await _tap("direct Attack", _screen(leaders[1]), func() -> bool: return _actor_attacks(fighter_id, enemy_id))
	await _tap("Attack-move arm", main.hud.get("_unit_attack_move_button").get_global_rect().get_center(), func() -> bool: return bool(main.get("_attack_move_command_armed")))
	target = _walkable(Vector2i(37 + index % 2 * 2, 27))
	await _tap("Attack-move accept", get_viewport().get_canvas_transform() * target, func() -> bool: return _actor_attack_moves(fighter_id) and not bool(main.get("_attack_move_command_armed")))
	selection.deselect_all()
	await _tap("select saved Scout", _screen(scout), func() -> bool: return selection.selected == [scout])
	main.get("_control_groups")[1] = []
	await _key("save group", KEY_1, true, func() -> bool: return main.get("_control_groups")[1] == [scout])
	var overview: StrategyOverview = main.hud.get("_strategy_overview")
	var tc: BuildingBase = main.get("_player_buildings")[0][0]
	await _tap("Base select", overview.rail.get_node("BaseButton").get_global_rect().get_center(), func() -> bool: return tc in selection.selected)
	await _key("recall group", KEY_1, false, func() -> bool: return selection.selected == [scout])
	for entry: Array in [["EconomyButton", "economy"], ["ArmyButton", "army"]]:
		var button: Button = overview.rail.get_node(entry[0])
		await _tap(entry[1] + " open", button.get_global_rect().get_center(), func() -> bool: return main.hud.call("get_secondary_surface_name") == entry[1])
		await _tap(entry[1] + " close", button.get_global_rect().get_center(), func() -> bool: return main.hud.call("get_secondary_surface_name") == "none")
	main.game_map.camera.position = main.game_map.tile_to_world(Vector2i(41, 35))
	main.game_map.camera.reset_smoothing()
	main.game_map.camera.force_update_scroll()
	await _key("select full army", KEY_M, false, func() -> bool: return selection.selected.size() >= 60)
	var cohort: Array = selection.selected.duplicate()
	await _tap("army Move arm", main.hud.get("_unit_move_button").get_global_rect().get_center(), func() -> bool: return bool(main.get("_move_command_armed")))
	target = _walkable(Vector2i(40 + index % 2 * 3, 34))
	await _tap("army Move accept", get_viewport().get_canvas_transform() * target, func() -> bool: return not bool(main.get("_move_command_armed")) and _army_command_count(cohort, "move") >= 40)
	army_orders.append({"kind": "move", "selected": cohort.size(), "accepted_units": _army_command_count(cohort, "move")})
	if is_instance_valid(leaders[1]):
		enemy_id = leaders[1].get_instance_id()
		await _tap("army direct Attack", _screen(leaders[1]), func() -> bool: return _army_command_count(cohort, "attack", enemy_id) >= 40)
		army_orders.append({"kind": "direct_attack", "selected": cohort.size(), "accepted_units": _army_command_count(cohort, "attack", enemy_id)})
	await _tap("army Attack-move arm", main.hud.get("_unit_attack_move_button").get_global_rect().get_center(), func() -> bool: return bool(main.get("_attack_move_command_armed")))
	target = _walkable(Vector2i(42, 36))
	await _tap("army Attack-move accept", get_viewport().get_canvas_transform() * target, func() -> bool: return not bool(main.get("_attack_move_command_armed")) and _army_command_count(cohort, "attack_move") >= 40)
	army_orders.append({"kind": "attack_move", "selected": cohort.size(), "accepted_units": _army_command_count(cohort, "attack_move")})

func _selected_ids(entries: Array) -> Array[int]:
	var result: Array[int] = []
	for entry: Variant in entries:
		if is_instance_valid(entry): result.append(entry.get_instance_id())
	return result

func _actor_attacks(actor_id: int, target_id: int) -> bool:
	if not is_instance_id_valid(actor_id): return false
	var actor: UnitBase = instance_from_id(actor_id) as UnitBase
	return actor != null and is_instance_valid(actor.attack_target) and actor.attack_target.get_instance_id() == target_id and actor.current_state == UnitBase.State.ATTACKING

func _actor_attack_moves(actor_id: int) -> bool:
	if not is_instance_id_valid(actor_id): return false
	var actor: UnitBase = instance_from_id(actor_id) as UnitBase
	return actor != null and actor.attack_move

func _army_command_count(cohort: Array, mode: String, target_id: int = 0) -> int:
	var count: int = 0
	for entry: Variant in cohort:
		if not is_instance_valid(entry) or entry.current_state == UnitBase.State.DEAD: continue
		if mode == "move" and bool(entry.get("_force_move_active")): count += 1
		elif mode == "attack_move" and entry.attack_move: count += 1
		elif mode == "attack" and is_instance_valid(entry.attack_target) and entry.attack_target.get_instance_id() == target_id: count += 1
	return count

func _screen(unit: Node2D) -> Vector2:
	return get_viewport().get_canvas_transform() * unit.global_position

func _tap(label: String, point: Vector2, accepted: Callable) -> void:
	contact += 1
	var event := InputEventScreenTouch.new()
	event.index = contact
	event.position = get_viewport().get_final_transform() * point
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	var start: int = Time.get_ticks_usec()
	Input.parse_input_event(event)
	await _measure_response(label, start, accepted)

func _key(label: String, key: Key, control: bool, accepted: Callable) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.ctrl_pressed = control
	event.pressed = true
	var start: int = Time.get_ticks_usec()
	Input.parse_input_event(event)
	await _measure_response(label, start, accepted)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func _measure_response(label: String, start: int, accepted: Callable) -> void:
	var count: int = 0
	while not accepted.call() and count < 12:
		await get_tree().process_frame
		count += 1
	var okay: bool = accepted.call()
	var accept_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	var rendered_ms: float = -1.0
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		rendered_ms = float(Time.get_ticks_usec() - start) / 1000.0
	responses.append({"action": label, "accepted": okay, "release_to_accept_ms": accept_ms, "release_to_render_ms": rendered_ms, "frames": count})
	if not okay: failures.append(label + " not accepted")
	for frame: int in 2: await get_tree().process_frame

func _stats(values: Array[float]) -> Dictionary:
	var result: Dictionary = super._stats(values)
	if values.is_empty(): return result
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	result["p99"] = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]
	result["over_50_ms"] = values.filter(func(value: float) -> bool: return value > 50.0).size()
	result["over_100_ms"] = values.filter(func(value: float) -> bool: return value > 100.0).size()
	return result
