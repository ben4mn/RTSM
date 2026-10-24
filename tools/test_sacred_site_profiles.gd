extends "res://tools/test_sacred_site_mobile.gd"
## Reuses the live Standard state-machine fixture, then checks public status
## presentation in both modes and dispatches a real Sacred GUI contact per profile.
## Status dictionaries and notches below are explicit layout fixtures.

var _profile_hud: CanvasLayer
var _profile_name: String = ""
var _notched: bool = false
var _contact_index: int = 510
var _focus_events: int = 0
var _world_orders: int = 0
var _profile_receipts: Array[Dictionary] = []

func _run() -> void:
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.guided_opening_enabled = false
	Input.emulate_mouse_from_touch = true
	await super._run()

func _check_phone_status_layout() -> void:
	_profile_hud = _match_scene.get("hud") as CanvasLayer
	var map: Node2D = _match_scene.get("game_map") as Node2D
	var selection: SelectionManager = map.get("selection_mgr") as SelectionManager
	for unit: Node in _saved_units:
		unit.set_process(false)
	_profile_hud.sacred_site_pressed.connect(func() -> void: _focus_events += 1)
	selection.move_command.connect(func(_tile: Vector2i) -> void: _world_orders += 1)
	selection.attack_command.connect(func(_target: Node2D) -> void: _world_orders += 1)
	selection.gather_command.connect(func(_target: Node2D) -> void: _world_orders += 1)
	selection.build_command.connect(func(_target: Node2D) -> void: _world_orders += 1)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.075, 1.15]:
			for notch: bool in [false, true]:
				_notched = notch
				get_window().size = phone
				get_window().content_scale_size = Vector2i(844, 390)
				get_window().content_scale_factor = interface_scale
				GameManager.ui_scale = interface_scale
				await _profile_frames(4)
				for mode: int in [SkirmishData.MatchMode.STANDARD, SkirmishData.MatchMode.QUICK_CONTROL]:
					_profile_name = "%dx%d-scale%.3f-%s-%s" % [phone.x, phone.y, interface_scale, "notched" if notch else "ordinary", "standard" if mode == 0 else "control-race"]
					await _check_mode_profile(mode, selection, map)
	var folder: String = OS.get_environment("AOEM_CAPTURE_SACRED_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("sacred-profiles-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Two mode presentations across twelve engine phone/scale/safe profiles, synthetic public phase/bank status, actual ScreenTouch Sacred GUI contacts. Inherited live Standard state-machine checks. No physical device or acceptance-match claim.", "display_server": DisplayServer.get_name(), "profiles": _profile_receipts, "failures": _failures}, "  "))
	if _failures.is_empty():
		print("[PASS] sacred_site_profiles: Standard and Control race public titles, banks, phase inspectors, logical 48px targets and real Sacred contacts across twelve profiles; selection and fog retained, no world orders")

func _check_mode_profile(mode: int, selection: SelectionManager, map: Node2D) -> void:
	var failures_before: int = _failures.size()
	var button: Button = _profile_hud.get("_sacred_site_button") as Button
	var panel: Control = _profile_hud.get("_sacred_site_panel") as Control
	var label: Label = _profile_hud.get("_sacred_site_label") as Label
	var cases: int = 0
	for guided: bool in [false, true]:
		_profile_hud.call("set_progression_hint", "Guide · capture the site" if guided else "", false)
		var phases: Array[String] = ["neutral", "capturing", "holding", "contested", "neutralizing"]
		if mode == SkirmishData.MatchMode.STANDARD:
			phases.append("unguarded")
		for phase: String in phases:
			for owner: int in ([-1] if phase == "neutral" else [0, 1]):
				var status := {"match_mode": mode, "phase": phase, "owner": owner, "remaining": 532.1, "total": 600.0 if mode == 0 else 240.0, "capture_progress": 0.42, "control_banks": [93.99, 239.99], "clock_ticking": phase == "holding", "garrison_paused": phase == "unguarded"}
				_profile_hud.call("update_sacred_site_status", status)
				_profile_hud.call("show_sacred_site_selection", status)
				await _profile_frames(3)
				var context: String = "%s guided=%s owner=%d" % [phase, guided, owner]
				var expected: Array[String] = _expected_text(mode, phase, owner)
				_profile_expect(label.text == expected[0], context + " exact public objective text")
				var details: Label = _profile_hud.get("selection_details") as Label
				_profile_expect(details.text == expected[1], context + " exact inspector text")
				_check_label_fit(label, context + " objective")
				_check_label_fit(details, context + " inspector")
				_profile_expect(button.size.x >= 48.0 and button.size.y >= 48.0, context + " logical 48px Sacred target")
				_profile_expect(_profile_safe_area().encloses(panel.get_global_rect()), context + " safe Sacred bounds")
				_profile_expect(_profile_safe_area().encloses((_profile_hud.get("selection_panel") as Control).get_global_rect()), context + " safe inspector bounds")
				var notifications: Control = _profile_hud.get("_notification_container") as Control
				_profile_expect(not panel.get_global_rect().intersects(notifications.get_global_rect(), true), context + " avoids notification lane")
				cases += 1
	# Keep the real Main callback wired. Locating the public objective must not
	# select/reveal it or issue a world command, even behind unexplored fog.
	selection.call("_clear_selection")
	var worker: UnitBase = (_match_scene.get("_player_units") as Array)[0][0] as UnitBase
	selection.call("_add_to_selection", worker)
	var selected_before: Array[Node2D] = selection.selected.duplicate()
	var camera: Camera2D = map.get("camera") as Camera2D
	var site: Node2D = map.get("sacred_site") as Node2D
	var fog: FogManager = map.get("fog_of_war") as FogManager
	var tile: Vector2i = map.call("world_to_tile", site.global_position)
	fog.fog_grid[tile.y][tile.x] = MapData.FogState.UNEXPLORED
	var fog_before: Array = fog.fog_grid.duplicate(true)
	camera.position = worker.global_position
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _profile_frames(3)
	var focus_before: int = _focus_events
	var orders_before: int = _world_orders
	_profile_expect(button.is_visible_in_tree() and not button.disabled, "Sacred contact reachable")
	_contact_index += 1
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = _contact_index
		event.position = get_viewport().get_final_transform() * button.get_global_rect().get_center()
		event.pressed = pressed
		Input.parse_input_event(event)
		await _profile_frames(3)
	_profile_expect(_focus_events == focus_before + 1, "contact emits exactly one Sacred focus")
	_profile_expect(camera.position.distance_to(site.global_position) < 0.1, "contact focuses canonical site position")
	_profile_expect(selection.selected == selected_before, "contact retains unit selection")
	_profile_expect(fog.fog_grid == fog_before, "contact retains all fog cells")
	_profile_expect(_world_orders == orders_before, "contact emits no world orders")
	_profile_receipts.append({"profile": _profile_name, "status_cases": cases, "sacred_contacts": _focus_events - focus_before, "world_orders": _world_orders - orders_before, "passed": _failures.size() == failures_before})

func _expected_text(mode: int, phase: String, owner: int) -> Array[String]:
	var owner_name: String = "You" if owner == 0 else "Enemy"
	if mode != 0:
		var title_state: String = "bank control"
		if phase == "holding": title_state = owner_name + " scoring"
		elif phase == "capturing": title_state = "capturing"
		elif phase in ["contested", "neutralizing"]: title_state = "paused"
		return ["Sacred 4:00 · " + title_state + "\nYou 1:33 · Enemy 3:59", "You 1:33 · Enemy 3:59\nBank 4:00 · " + phase.capitalize()]
	match phase:
		"capturing": return ["Sacred Site · tap to view\n" + owner_name + " capturing · 42%", owner_name + " 42%\n" + ("Stay in ring" if owner == 0 else "Enter to contest")]
		"holding": return ["Sacred Site · tap to view\n" + owner_name + " win in 8:53", owner_name + " · 8:53\n" + ("Keep a fighter" if owner == 0 else "Enter to pause")]
		"unguarded": return [("Held · bring a fighter" if owner == 0 else "Enemy held · unguarded") + "\n" + owner_name + " 8:53 paused", owner_name + " 8:53 paused\n" + ("Bring a fighter" if owner == 0 else "No enemy fighter")]
		"contested": return ["Sacred Site · Contested\n" + owner_name + " 8:53 paused", "Contested\nClear enemies"]
		"neutralizing": return ["Sacred Site · Disrupted\n" + owner_name + " 8:53 paused", "Disrupted\nStay in ring"]
	return ["Sacred Site · tap to view\nNeutral · enter the ring", "Neutral\nEnter ring"]

func _check_label_fit(label: Label, context: String) -> void:
	_profile_expect(label.is_visible_in_tree(), context + " visible")
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	for line: String in label.text.split("\n"):
		var width: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_profile_expect(width <= label.size.x + 0.1, "%s line fits: '%s' %.1f <= %.1f" % [context, line, width, label.size.x])
	var height: float = font.get_height(font_size) * label.get_line_count() + label.get_theme_constant("line_spacing") * maxi(0, label.get_line_count() - 1)
	_profile_expect(height <= label.size.y + 0.1, "%s full text height %.1f <= %.1f" % [context, height, label.size.y])

func _profile_safe_area() -> Rect2:
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var inset: Vector2 = Vector2(44, 18) * logical / Vector2(get_window().size) if _notched else Vector2.ZERO
	return Rect2(Vector2(inset.x, 0), logical - Vector2(inset.x * 2, inset.y))

func _profile_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame
		if is_instance_valid(_profile_hud):
			_profile_hud.call("apply_mobile_layout", get_viewport().get_visible_rect().size, _profile_safe_area())

func _profile_expect(condition: bool, message: String) -> void:
	_expect(condition, _profile_name + ": " + message)
