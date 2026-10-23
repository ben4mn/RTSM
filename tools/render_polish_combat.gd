extends Node
## Interactive synthetic combat fixture using the actual Main input and HUD.
## Free rosters/capacity and revealed fog; ordinary unit stats, no balance claim.

var main: Node2D
var game_map: Node2D
var roster: Array[UnitBase] = []
var enemies: Array[UnitBase] = []
var objective: BuildingBase
var phase: String = "runner"
var phase_seconds: float = 0.0
var automatic: bool = true
var busy: bool = false
var output: String = "res://output/polish-combat-rendered-2026-10-22"
var width: int = 844
var height: int = 390
var center: Vector2
var label: Label
var events: Dictionary = {}
var report: Dictionary = {"scope": "Synthetic free tactical roster and capacity; revealed fog; actual Main controls/GameMap/A*/HUD and normal unit stats. Scripted commands, optional human control. Not paid-play, balance or physical-device evidence.", "phases": [], "commands": [], "hits": [], "navigation_failures": 0, "captures": []}
var frames: Array[float] = []
var previous_frame: int = 0
var repeat_remaining: float = 0.0
var screenshot_busy: bool = false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
		elif argument.begins_with("--width="): width = int(argument.trim_prefix("--width="))
		elif argument.begins_with("--height="): height = int(argument.trim_prefix("--height="))
		elif argument == "--manual": automatic = false
	DirAccess.make_dir_recursive_absolute(output)
	report.environment = {"display": DisplayServer.get_name(), "width": width, "height": height, "fixed_fps": "--fixed-fps" in OS.get_cmdline_args(), "engine": Engine.get_version_info()}
	report.source_hashes = {}
	for source: String in ["scripts/units/unit_base.gd", "scripts/main/main.gd", "scripts/ui/hud.gd", "tools/render_polish_combat.gd", "tools/fixtures/polish_revealed_fog.gd"]:
		report.source_hashes[source] = FileAccess.get_file_as_string("res://" + source).sha256_text()
	get_window().size = Vector2i(width, height)
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	var overlay := CanvasLayer.new()
	overlay.layer = 110
	add_child(overlay)
	label = Label.new()
	label.position = Vector2(172, 49)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(label)
	call_deferred("jump_to_phase", phase)


func jump_to_phase(next_phase: String) -> void:
	if busy: return
	busy = true
	if is_instance_valid(main):
		_save_phase()
		main.free()
		await get_tree().process_frame
	phase = next_phase if next_phase in ["runner", "crowd", "building"] else "runner"
	phase_seconds = 0.0
	repeat_remaining = 0.0
	events.clear()
	roster.clear()
	enemies.clear()
	objective = null
	frames.clear()
	previous_frame = 0
	GameManager.guided_opening_enabled = false
	GameManager.ui_scale = 1.0
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_population_limit = 100
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.set_state(GameManager.GameState.MENU)
	main = load("res://scenes/main/main.tscn").instantiate() as Node2D
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	game_map = main.get("game_map") as Node2D
	var ai: Node = main.get("ai_controller")
	ai.process_mode = Node.PROCESS_MODE_DISABLED
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	for owner: int in 2:
		GameManager.increase_population_cap(owner, 80)
	var fog := game_map.get_node("FogOfWar") as FogManager
	# Main refreshes fog itself even when the FogManager process is stopped.
	# Keep that API intact with an explicitly fixture-only reveal implementation.
	fog.set_script(load("res://tools/fixtures/polish_revealed_fog.gd"))
	fog.fog_layer = game_map.get_node("FogLayer") as TileMapLayer
	fog.set_process(false)
	fog.refresh_visibility_now()
	game_map.get_node("FogLayer").hide()
	if game_map.get("sacred_site") != null:
		game_map.get("sacred_site").set_process(false)
		game_map.get("sacred_site").hide()
	var field_feedback: Control = main.get("_battlefield_feedback") as Control
	field_feedback.set("_site", null)
	field_feedback.queue_redraw()
	center = game_map.tile_to_world(Vector2i(36, 35))
	if phase == "runner":
		_spawn(UnitData.UnitType.CAVALRY, 0, center + Vector2(-180, 0))
		_spawn(UnitData.UnitType.INFANTRY, 1, center + Vector2(-20, 0))
	elif phase == "crowd":
		for owner: int in 2:
			for index: int in 8:
				var kind: int = UnitData.UnitType.INFANTRY if index < 4 else (UnitData.UnitType.ARCHER if index < 7 else UnitData.UnitType.CAVALRY)
				_spawn(kind, owner, center + Vector2((-180.0 if owner == 0 else 180.0) + (index / 4) * (-36.0 if owner == 0 else 36.0), (index % 4 - 1.5) * 34.0))
	else:
		for tile: Vector2i in [Vector2i(35, 33), Vector2i(35, 36)]:
			var wall: BuildingBase = main.call("_spawn_building", BuildingData.BuildingType.HOUSE, 0, tile)
			wall.complete_instantly()
		objective = main.call("_spawn_building", BuildingData.BuildingType.HOUSE, 1, Vector2i(39, 35))
		objective.complete_instantly()
		for index: int in 6:
			_spawn(UnitData.UnitType.INFANTRY if index < 4 else UnitData.UnitType.ARCHER, 0, game_map.tile_to_world(Vector2i(31 + index / 3, 34 + index % 3)))
		_spawn(UnitData.UnitType.INFANTRY, 1, game_map.tile_to_world(Vector2i(38, 35)))
		_spawn(UnitData.UnitType.ARCHER, 1, game_map.tile_to_world(Vector2i(40, 37)))
	main.call("_update_fog_entity_visibility")
	_select_roster()
	game_map.call("note_camera_interaction")
	game_map.set("_user_zoom_override", true)
	var camera: Camera2D = game_map.get("camera")
	camera.position = center
	camera.zoom = Vector2.ONE * 0.90
	camera.reset_smoothing()
	camera.force_update_scroll()
	for frame: int in 6: await get_tree().process_frame
	for unit: UnitBase in roster + enemies:
		assert(unit.is_visible_in_tree() and unit._sprite.is_visible_in_tree(), "Rendered fixture troop must be visible after Main fog refresh")
	assert(not game_map.get_node("FogLayer").is_visible_in_tree(), "Rendered fixture fog layer must remain hidden")
	busy = false
	await capture("before")
	if automatic: _start_orders()
	print("[READY] render_polish_combat phase=", phase, " automatic=", automatic)


func _spawn(kind: int, owner: int, position: Vector2) -> void:
	var unit: UnitBase = main.call("_spawn_unit", kind, owner, position)
	if unit == null: return
	if owner == 0: roster.append(unit)
	else: enemies.append(unit)
	unit.attack_landed.connect(func(attacker: UnitBase, defender: UnitBase, loss: float, _bonus: float):
		report.hits.append({"phase": phase, "seconds": phase_seconds, "owner": attacker.player_owner, "role": attacker.unit_type, "target_role": defender.unit_type, "damage": loss}))
	unit.navigation_failed.connect(func(_unit: UnitBase, _target: Vector2): report.navigation_failures += 1)


func _select_roster() -> void:
	var living: Array[Node2D] = []
	for unit: UnitBase in roster:
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD: living.append(unit)
	(game_map.get("selection_mgr") as SelectionManager).select_many(living)


func _start_orders() -> void:
	_select_roster()
	if phase == "runner":
		enemies[0].command_move(center + Vector2(420, 0))
		main.call("_on_attack_command", enemies[0])
	elif phase == "crowd":
		main.call("_on_touch_attack_move_command", game_map.world_to_tile(center + Vector2(100, 0)))
		for unit: UnitBase in enemies: unit.command_attack_move(center + Vector2(-100, 0))
	else:
		main.call("_on_move_command", Vector2i(38, 35))
	report.commands.append({"phase": phase, "seconds": phase_seconds, "action": "start"})


func take_control() -> void:
	automatic = false
	report.commands.append({"phase": phase, "seconds": phase_seconds, "action": "human_control"})


func _process(delta: float) -> void:
	if busy or not is_instance_valid(main): return
	var now: int = Time.get_ticks_usec()
	if previous_frame > 0 and frames.size() < 20000:
		frames.append(float(now - previous_frame) / 1000.0)
	previous_frame = now
	label.text = "SYNTHETIC · %s · %.1fs · %s\nF6 take control   F7 next   F8 capture   F9 replay" % [phase, phase_seconds, "scripted" if automatic else "manual"]
	if get_tree().paused: return
	phase_seconds += delta
	if not automatic: return
	if phase == "runner" and phase_seconds < 9.0:
		repeat_remaining -= delta
		if repeat_remaining <= 0.0:
			repeat_remaining = 0.3
			if is_instance_valid(enemies[0]) and enemies[0].current_state != UnitBase.State.DEAD:
				main.call("_on_attack_command", enemies[0])
	if _event("mid", 5.0): capture("mid")
	if phase == "building" and _event("building_attack", 4.0):
		main.call("_on_attack_command", objective)
	if phase == "building" and _event("switch", 9.0):
		for enemy: UnitBase in enemies:
			if is_instance_valid(enemy) and enemy.current_state != UnitBase.State.DEAD:
				main.call("_on_attack_command", enemy)
				break
	if _event("stop", 10.0): main.call("_stop_selected_units")
	if _event("retreat", 11.0): main.call("_on_move_command", game_map.world_to_tile(center + Vector2(-230, -90)))
	if _event("reengage", 14.0) and phase != "runner":
		main.call("_on_touch_attack_move_command", game_map.world_to_tile(center + Vector2(180, 0)))
	if _event("after", 17.0): capture("after")
	if _event("finish", 20.0):
		if phase == "building": finish()
		else: jump_to_phase("crowd" if phase == "runner" else "building")


func _event(key: String, at: float) -> bool:
	if phase_seconds < at or events.has(key): return false
	events[key] = true
	report.commands.append({"phase": phase, "seconds": phase_seconds, "action": key})
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F6: take_control()
		KEY_F7: jump_to_phase("crowd" if phase == "runner" else ("building" if phase == "crowd" else "runner"))
		KEY_F8: capture("manual-%d" % Time.get_ticks_msec())
		KEY_F9: jump_to_phase(phase)


func capture(name: String) -> void:
	if screenshot_busy or DisplayServer.get_name() == "headless": return
	screenshot_busy = true
	await RenderingServer.frame_post_draw
	var filename: String = "%s-%s.png" % [phase, name]
	var status: Error = get_viewport().get_texture().get_image().save_png(output.path_join(filename))
	report.captures.append({"phase": phase, "seconds": phase_seconds, "path": filename, "error": status})
	screenshot_busy = false


func _save_phase() -> void:
	var sorted: Array[float] = frames.duplicate()
	sorted.sort()
	var survivors: Array[int] = [0, 0]
	for unit: UnitBase in roster + enemies:
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD: survivors[unit.player_owner] += 1
	report.phases.append({"phase": phase, "seconds": phase_seconds, "survivors": survivors, "frame_samples": sorted.size(), "process_interval_p95_ms": sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0, "process_interval_max_ms": sorted[-1] if not sorted.is_empty() else 0.0, "timing_scope": "Wall intervals between _process callbacks, including screenshots; not isolated GPU/display FPS."})
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))


func finish() -> void:
	busy = true
	_save_phase()
	print("[PASS] render_polish_combat completed; report=", output.path_join("report.json"))
	get_tree().quit()
