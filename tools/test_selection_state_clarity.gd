extends Node
## Real main-scene presentation states. Capture banks, health and construction
## progress are modeled; queue purchases and Farm claims use production methods.

var _failures: Array[String] = []
var _checks: int = 0
var _output: String = ""
var _records: Array[Dictionary] = []
var _hud: CanvasLayer
var _safe: Rect2
var _profile: String


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_output = argument.trim_prefix("--capture-dir=")
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
	for profile: Dictionary in [
		{"size": Vector2i(1100, 700), "scale": 1.0, "insets": false},
		{"size": Vector2i(844, 390), "scale": 1.0, "insets": false},
		{"size": Vector2i(844, 390), "scale": 1.15, "insets": true},
		{"size": Vector2i(932, 430), "scale": 1.15, "insets": true},
	]:
		await _check_profile(profile)
	if not _output.is_empty():
		var file := FileAccess.open(_output + "/manifest.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"scope": "Native production Main/HUD with modeled health, construction, banks and safe areas including 60 logical pixels of browser clearance. Production paid queue and Farm reservation APIs. No match, network, real browser or physical-device claim.", "checks": _checks, "failures": _failures, "states": _records}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] selection_state_clarity: " + failure)
	if _failures.is_empty():
		print("[PASS] selection_state_clarity: %d checks; four desktop/phone/max-scale profiles, meaningful meters, Farm capacity privacy, paid population reservations and touch Info" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_profile(profile: Dictionary) -> void:
	var physical: Vector2i = profile.size
	var scale_factor: float = profile.scale
	_profile = "%dx%d-scale%d-%s" % [physical.x, physical.y, roundi(scale_factor * 100), "clearance" if profile.insets else "ordinary"]
	get_window().size = physical
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = scale_factor
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 30
	GameManager.set_state(GameManager.GameState.MENU)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_expect(main.get("_building_placement") != null, "Main initializes")
	_hud = main.get_node("HUD")
	var map: Node2D = main.get_node("GameMap")
	var tc: BuildingBase = main.get("_player_buildings")[0][0]
	var worker: Villager = main.get("_player_units")[0][0]
	var camera: Camera2D = map.get("camera")
	camera.position = tc.global_position + Vector2(100, 0)
	camera.reset_smoothing()
	camera.force_update_scroll()
	main.call("_update_fog_of_war")
	main.call("_update_minimap")
	get_tree().paused = true
	var logical: Vector2 = get_viewport().get_visible_rect().size
	_safe = Rect2(Vector2.ZERO, logical)
	if profile.insets:
		_safe = Rect2(Vector2(44.0 / scale_factor, 0), logical - Vector2(88.0 / scale_factor, 18.0 / scale_factor + 60.0))
	_hud.call("set_early_game_ui_state", false)
	_hud.call("set_progression_hint", "")
	_hud.call("show_unit_selection", "Villager", 17, 25, "Returning Wood", 1, {"unit_type": UnitData.UnitType.VILLAGER, "cargo_amount": 15, "cargo_capacity": 15, "cargo_resource": "wood"})
	_hud.call("configure_unit_commands", true, false, "Aggressive", "smart")
	await _state("worker", "HP 17 / 25", "Health 17 / 25")
	_expect((_hud.get("selection_details") as Label).text.contains("Returning") and (_hud.get("selection_details") as Label).text.contains("Wood 15/15"), "worker order and cargo retained")
	_hud.call("show_resource_info", "Gold", 345, 500, 69)
	await _state("gold-stock", "Stock 69%", "Gold stock: 345 / 500")
	_expect(not str((_hud.call("_selection_information") as Dictionary).body).contains("HP "), "stock is not health")
	_hud.call("show_sacred_site_selection", {"phase": "capturing", "owner": 0, "capture_progress": 0.42, "remaining": 180.0, "total": 180.0})
	await _state("sacred-capture", "Capture 42%", "Capture progress: 42%")
	_expect(not str((_hud.call("_selection_information") as Dictionary).body).contains("HP "), "capture is not health")
	var farm: BuildingBase = load("res://scenes/buildings/farm.tscn").instantiate()
	farm.player_owner = 0
	farm.position = tc.position + Vector2(160, 80)
	map.add_child(farm)
	farm.state = BuildingBase.State.CONSTRUCTING
	farm.build_progress = 0.42
	_hud.call("show_building_selection", "Farm", 90, 400, [], [], farm)
	await _state("foundation", "Build 42%", "Construction 42%\nHealth 90 / 400")
	_expect((_hud.get("selection_hp_bar") as ProgressBar).value == 42.0, "foundation bar tracks completion separately from health")
	_expect((_hud.get("selection_details") as Label).text == "Needs builder", "stopped construction recovery remains visible")
	NetworkSession.online = true
	_hud.call("show_building_selection", "Farm", 90, 400, [], [], farm)
	_expect((_hud.get("selection_details") as Label).text == "Building 42%", "online foundation does not infer missing labor from absent replica links")
	NetworkSession.online = false
	farm.state = BuildingBase.State.ACTIVE
	farm.call("_update_sprite_appearance")
	farm.queue_redraw()
	_hud.call("show_building_selection", "Farm", 400, 400, [], [], farm)
	await _state("farm-available", "HP 400 / 400", "Available: assign one Villager")
	_expect((_hud.get("selection_details") as Label).text.contains("Needs 1 worker"), "available Farm visible without opening Info")
	_expect(farm.try_assign_worker(worker), "Farm production reservation succeeds")
	for work_state: Dictionary in [{"state": UnitBase.State.MOVING, "returning": false}, {"state": UnitBase.State.GATHERING, "returning": false}, {"state": UnitBase.State.MOVING, "returning": true}]:
		worker.current_state = work_state.state
		worker.set("_dropoff_route_active", work_state.returning)
		_hud.call("show_building_selection", "Farm", 400, 400, [], [], farm)
		_expect((_hud.get("selection_details") as Label).text.contains("Worker assigned"), "Farm reserved during travel, harvest and drop-off")
	await _state("farm-assigned", "HP 400 / 400", "Worker assigned (including travel and drop-off)")
	NetworkSession.online = true
	_hud.call("show_building_selection", "Farm", 400, 400, [], [], farm)
	_expect(not (_hud.get("selection_details") as Label).text.contains("assigned") and not (_hud.get("selection_details") as Label).text.contains("Needs"), "replica without claim data makes no occupancy promise")
	NetworkSession.online = false
	farm.player_owner = 1
	_hud.call("show_building_selection", "Farm", 400, 400, [], [], farm)
	_expect(not (_hud.get("selection_details") as Label).text.contains("assigned") and not (_hud.get("selection_details") as Label).text.contains("Needs"), "enemy occupancy remains private")
	farm.player_owner = 0
	farm.release_worker(worker)
	worker.current_state = UnitBase.State.IDLE
	worker.set("_dropoff_route_active", false)
	var queue: ProductionQueue = tc.get_production_queue()
	ResourceManager.initialize_player(0, {"food": 500, "wood": 500, "gold": 100})
	GameManager.players[0]["population"] = 4
	GameManager.players[0]["population_cap"] = 6
	_expect(queue.enqueue_unit(UnitData.UnitType.VILLAGER), "first Villager paid")
	_expect(queue.enqueue_unit(UnitData.UnitType.VILLAGER), "second Villager paid")
	_expect(ResourceManager.get_resource(0, "food") == 500 - queue.get_queue_size() * int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).get("food", 0)), "queue used exact normal cost (food left %d)" % ResourceManager.get_resource(0, "food"))
	_hud.call("update_population", GameManager.get_committed_population(0), 6)
	_hud.call("show_building_selection", "Town Center", tc.hp, tc.max_hp, queue.get_queue_info(), tc.trainable_units, tc)
	await _state("population-reserved", "HP %d / %d" % [tc.hp, tc.max_hp], "4 living · 2 paid in queues")
	_expect((_hud.get("pop_label") as Label).get_theme_color("font_color") == KingdomTheme.RUST, "full population has visible warning color")
	_expect(str((_hud.call("_selection_information") as Dictionary).body).contains("Cancel a paid unit"), "tap Info explains reserved population recovery")
	queue.cancel_all()
	_hud.call("update_population", GameManager.get_committed_population(0), 15)
	_expect((_hud.get("pop_label") as Label).get_theme_color("font_color") == KingdomTheme.PARCHMENT, "population warning clears with room")
	_expect((_hud.get("pop_label") as Label).tooltip_text.contains("0 paid in queues"), "refund clears reserved count")
	_hud.call("show_unit_selection", "Warrior", 1, 100, "IDLE", 1, {"unit_type": UnitData.UnitType.INFANTRY})
	await _state("injured-unit", "HP 1 / 100", "Health 1 / 100")
	var fill: StyleBoxFlat = (_hud.get("selection_hp_bar") as ProgressBar).get_theme_stylebox("fill")
	_expect(fill.bg_color == KingdomTheme.RUST.darkened(0.50), "health color resets after stock, progress and capture")
	get_tree().paused = false
	main.free()
	await get_tree().process_frame


func _state(state_name: String, caption: String, information: String) -> void:
	for frame: int in 3:
		await get_tree().process_frame
	_hud.call("apply_mobile_layout", get_viewport().get_visible_rect().size, _safe)
	for frame: int in 3:
		await get_tree().process_frame
	var meter: ProgressBar = _hud.get("selection_hp_bar")
	var label: Label = meter.get_node_or_null("SelectionMeterValue")
	if label != null:
		var fill_style: StyleBoxFlat = meter.get_theme_stylebox("fill")
		var text_color: Color = label.get_theme_color("font_color")
		var contrast: float = (_luminance(text_color) + 0.05) / (_luminance(fill_style.bg_color) + 0.05)
		_expect(contrast >= 4.5, state_name + " readable meter value contrast %.2f" % contrast)
	_expect(label != null and label.text == caption, state_name + " visible contextual meter")
	_expect(str((_hud.call("_selection_information") as Dictionary).body).contains(information), state_name + " correct Info semantics")
	var panel: Control = _hud.get("selection_panel")
	var column: Control = _hud.get("selection_info_column")
	_expect(_safe.grow(1.0).encloses(panel.get_global_rect()), state_name + " panel inside safe area")
	_expect(panel.size.y <= 80.5, state_name + " retains compact dock height: %s, column %s details %s" % [panel.size, column.size, (_hud.get("selection_details") as Label).size])
	_expect(panel.get_global_rect().grow(0.5).encloses(column.get_global_rect()), state_name + " identity inside dock")
	for text_label: Label in [_hud.get("selection_details"), label]:
		if text_label == null:
			continue
		for line: String in text_label.text.split("\n"):
			var width: float = text_label.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, text_label.get_theme_font_size("font_size")).x
			_expect(width <= text_label.size.x + 0.5, state_name + " complete text: " + line)
	var info_button: Button = _hud.get("_selection_info_button")
	var point: Vector2 = info_button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 7
		event.position = get_viewport().get_final_transform() * point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		for frame: int in 3:
			await get_tree().process_frame
	_expect(_hud.call("get_secondary_surface_name") == "info", state_name + " touch opens Info")
	_expect((_hud.get("_info_body") as Label).text.contains(information), state_name + " touch Info contains live value")
	if state_name == "population-reserved" and not _output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var info_filename: String = _profile + "-population-info.png"
		get_viewport().get_texture().get_image().save_png(_output + "/" + info_filename)
		_records.append({"profile": _profile, "state": "population-info", "image": info_filename})
	_hud.call("close_secondary_surface")
	await get_tree().process_frame
	_hud.call("apply_mobile_layout", get_viewport().get_visible_rect().size, _safe)
	if not _output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var filename: String = _profile + "-" + state_name + ".png"
		get_viewport().get_texture().get_image().save_png(_output + "/" + filename)
		_records.append({"profile": _profile, "state": state_name, "image": filename, "caption": label.text if label != null else "", "details": (_hud.get("selection_details") as Label).text, "panel": str(panel.get_global_rect()), "safe": str(_safe)})


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(_profile + ": " + description)


func _luminance(color: Color) -> float:
	var linear: Color = color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
