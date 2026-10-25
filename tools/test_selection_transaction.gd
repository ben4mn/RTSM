extends "res://tools/test_occlusion_touch_orders.gd"
## Integrated selection transactions and real destination contacts through death.
## Armies are synthetic; no balance/timing or physical-device claim.
var _signals: int = 0
var _last_cleanup: bool = false
var _last_replacement: bool = false
var _last_signal_size: int = 0

func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_population_limit = 100
	GameManager.selected_map_seed = 101
	GameManager.ui_scale = 1.0
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	GameManager.set_state(GameManager.GameState.MENU)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null: break
		await get_tree().process_frame
	_main.set_process(false)
	_main.ai_controller.set_process(false)
	_main.ai_controller.get("_decision_timer").stop()
	_main.get_node("StrategyController").set_process(false)
	_map = _main.game_map
	_map.fog_of_war.set_process(false)
	_map.fog_of_war.reveal_all()
	_selection = _map.selection_mgr
	GameManager.grant_population_cap(0, 987654, 100)
	for unit: Node in get_tree().get_nodes_in_group("units"): unit.set_process(false)
	var origin: Vector2 = _map.tile_to_world(Vector2i(36, 34))
	var army: Array[Node2D] = []
	for index: int in 69:
		var unit: UnitBase = _main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, origin + Vector2((index % 14 - 7) * 24, (index / 14 - 2) * 28))
		unit.set_process(false)
		army.append(unit)
	_map.note_camera_interaction()
	_map.set("_user_zoom_override", true)
	_map.camera.zoom = Vector2.ONE
	await _center(origin)
	_selection.selection_changed.connect(_observe)
	var before_ms: Array[float] = []
	var after_ms: Array[float] = []
	for repeat: int in 3:
		_selection.deselect_all()
		_signals = 0
		var started: int = Time.get_ticks_usec()
		# Replay the previous public bulk implementation against the same HUD.
		for unit: Node2D in army: _selection._add_to_selection(unit)
		before_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		_expect(_signals == 69, "baseline callback count")
		_signals = 0
		started = Time.get_ticks_usec()
		_selection.select_many(army)
		after_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		_expect(_signals == 1 and _last_signal_size == 69 and _last_replacement and not _last_cleanup, "one completed replacement callback")
		_expect(_selection.selected == army, "same final unit order")
		_expect(army.all(func(unit: Node2D) -> bool: return unit.is_selected), "all visual selection marks retained")
	print("[SELECTION COST] before_ms=%s after_ms=%s;69 callbacks ->1" % [before_ms, after_ms])
	_main.set("_move_command_armed", true)
	_main.call("_sync_selection_command_mode")
	_selection.select_many(army)
	_expect(not _main.get("_move_command_armed") and not _selection.unit_command_armed, "explicit replacement retains command reset")
	_signals = 0
	_selection.select_all_own_units()
	_expect(_signals == 1 and _selection.selected.size() == 74, "select all emits once including own workers/scout")
	_signals = 0
	_selection._handle_double_tap(_selection._world_to_screen(army[0].global_position), false)
	_expect(_signals == 1 and _selection.selected.size() == 69, "double tap emits once for same type on screen")
	_signals = 0
	_selection.set("_drag_start", Vector2(120, 80))
	_selection.set("_drag_end", Vector2(1150, 510))
	_selection._finish_drag_select()
	_expect(_signals == 1 and _selection.selected.size() == 69, "drag emits once for final army")
	var survivor: UnitBase = army[0]
	for unit: Node2D in army:
		if unit != survivor: unit.global_position += Vector2(800, 0)
	survivor.global_position = _find_walkable_near(origin)
	await _center(survivor.global_position)
	for mode: String in ["move", "attack_move", "attack"]:
		await _death_during_destination(survivor, mode)
	_main.free()
	for failure: String in _failures: push_error("[FAIL] selection_transaction: " + failure)
	if _failures.is_empty(): print("[PASS] selection_transaction: %d checks;69-unit transaction, final HUD/order/flags, real ScreenTouch Move/Attack-move/directAttack through ordinary selected death" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _observe(nodes: Array[Node2D]) -> void:
	_signals += 1
	_last_signal_size = nodes.size()
	_last_cleanup = _selection.is_selection_cleanup()
	_last_replacement = _selection.is_selection_replacement()

func _death_during_destination(survivor: UnitBase, mode: String) -> void:
	survivor.command_stop()
	var casualty: UnitBase = _main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, survivor.global_position + Vector2(30, 0))
	casualty.set_process(false)
	var targets: Array[Node2D] = [survivor, casualty]
	_selection.select_many(targets)
	await _frames(3)
	var destination: Vector2 = _empty_ground(survivor)
	var enemy: UnitBase = null
	if mode == "attack":
		enemy = _main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 1, _selection._screen_to_world(destination))
		enemy.set_process(false)
		destination = _selection._world_to_screen(_opaque_point(enemy.get("_sprite"), Vector2(0.3, 0.6)))
	else:
		var button: Button = _main.hud.get("_unit_move_button" if mode == "move" else "_unit_attack_move_button")
		await _tap(button.get_global_rect().get_center())
		_expect(_selection.unit_command_armed, mode + " armed")
	_contact_id += 1
	var press := InputEventScreenTouch.new()
	press.index = _contact_id
	press.position = get_viewport().get_final_transform() * destination
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(1)
	casualty.take_damage(casualty.hp + 100.0)
	await _frames(2)
	_expect(_selection.selected == [survivor], mode + " automatically prunes only casualty")
	_expect(_last_cleanup, mode + " cleanup marker reaches observer")
	if mode != "attack": _expect(_selection.unit_command_armed, mode + " survives selected death")
	var release := InputEventScreenTouch.new()
	release.index = _contact_id
	release.position = get_viewport().get_final_transform() * destination
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(3)
	if mode == "move": _expect(survivor.current_state == UnitBase.State.MOVING and survivor.get("_force_move_active"), "surviving army accepts held Move")
	elif mode == "attack_move": _expect(survivor.attack_move, "surviving army accepts held Attack-move")
	else: _expect(survivor.attack_target == enemy, "surviving army accepts held directAttack")
	if enemy != null: enemy.take_damage(enemy.hp + 100.0)
