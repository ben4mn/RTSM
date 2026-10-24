extends Node
## Paused presentation fixture in production Main. Models roster, damage and
## researched bonuses; real selection signals and native pointer/touch Info.
## Not a paid match, battle/performance benchmark or physical-device test.

var _checks: int = 0
var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _output: String = ""
var _baseline: bool = false
var _profile: String = ""
var _hud: CanvasLayer
var _safe: Rect2


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument == "--baseline":
			_baseline = true
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
	for profile: Dictionary in [
		{"size": Vector2i(1280, 800), "scale": 1.0, "insets": false},
		{"size": Vector2i(844, 390), "scale": 1.0, "insets": false},
		{"size": Vector2i(844, 390), "scale": 1.15, "insets": true},
	]:
		await _profile_cases(profile)
	if not _output.is_empty():
		var file := FileAccess.open(_output + "/receipt.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"scope": "Paused real Main with modeled units/health/upgrades. Production selection signals, actual GUI touch/mouse Info and wheel overflow. Synthetic browser clearance at maximum scale. Baseline records known omitted content/overflow; candidate asserts fixes. No paid-match, network, phone-device or performance claim.", "baseline": _baseline, "checks": _checks, "failures": _failures, "states": _records}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] army_selection_readability: " + failure)
	if _failures.is_empty():
		print("[PASS] army_selection_readability: %d checks; %d states; baseline=%s" % [_checks, _records.size(), _baseline])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile_cases(profile: Dictionary) -> void:
	_profile = "%dx%d-%d-%s" % [profile.size.x, profile.size.y, roundi(float(profile.scale) * 100), "clearance" if profile.insets else "ordinary"]
	get_window().size = profile.size
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = profile.scale
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 50
	GameManager.set_state(GameManager.GameState.MENU)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_expect(main.get("_building_placement") != null, "production Main initializes")
	_hud = main.get_node("HUD")
	var map: Node2D = main.get_node("GameMap")
	var selection: Node = map.get("selection_mgr")
	var tc: BuildingBase = main.get("_player_buildings")[0][0]
	get_tree().paused = true
	GameManager.players[0]["population_cap"] = 50
	GameManager.players[1]["population_cap"] = 50
	GameManager.apply_attack_upgrade(0, 2)
	GameManager.apply_armor_upgrade(0, 1)
	var roster: Array[Node2D] = []
	for unit_type: int in [UnitData.UnitType.INFANTRY, UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY, UnitData.UnitType.SCOUT, UnitData.UnitType.SIEGE, UnitData.UnitType.VILLAGER]:
		var offset := Vector2(100 + (roster.size() % 4) * 45, 30 + floori(roster.size() / 4.0) * 50)
		var unit: UnitBase = main.call("_spawn_unit", unit_type, 0, tc.position + offset)
		_expect(unit != null, "modeled unit available")
		roster.append(unit)
	var camera: Camera2D = map.get("camera")
	camera.position = tc.position + Vector2(140, 70)
	camera.reset_smoothing()
	camera.force_update_scroll()
	main.call("_update_fog_of_war")
	main.call("_update_minimap")
	var logical: Vector2 = get_viewport().get_visible_rect().size
	_safe = Rect2(Vector2.ZERO, logical)
	if profile.insets:
		_safe = Rect2(Vector2(44.0 / profile.scale, 0), logical - Vector2(88.0 / profile.scale, 18.0 / profile.scale + 60.0))
	_hud.call("set_early_game_ui_state", false)
	_hud.call("set_progression_hint", "")
	_hud.set("_movement_controls_hint_shown", true)
	var archer: UnitBase = roster[2]
	archer.hp = 21
	archer.current_state = UnitBase.State.ATTACKING
	archer.stance = UnitBase.Stance.STAND_GROUND
	selection.call("select_single", archer)
	await _state("archer", ["Ranged infantry", "Attack 9", "Armor 1", "Range 5 tiles", "Stance: Stand Ground", "Current order: Attacking", "damage bonus against Warriors"], true)
	var pair: Array[Node2D] = [roster[0], roster[1]]
	(roster[0] as UnitBase).hp = 30
	selection.call("select_many", pair)
	await _state("warrior-pair", ["Combined health 90 / 120 across 2 selected units", "Attack 10", "First unit order:"], false)
	var two_types: Array[Node2D] = [roster[0], roster[1], roster[2], roster[3]]
	selection.call("select_many", two_types)
	await _state("two-types", ["Warrior ×2", "Archer ×2", "Selection composition"], true)
	var first_summary: String = (_hud.get("selection_details") as Label).text
	two_types.reverse()
	selection.call("select_many", two_types)
	if not _baseline:
		_expect((_hud.get("selection_details") as Label).text == first_summary, "reordered selection retains stable roster order")
	selection.call("select_many", roster)
	await _state("six-types", ["Warrior ×2", "Archer ×2", "Horseman ×1", "Scout ×1", "Siege Engine ×1", "Villager ×1", "Scouts cannot attack"], true)
	var mixed_info: String = str((_hud.call("_selection_information") as Dictionary).body)
	if not _baseline:
		_expect(not mixed_info.contains("Attack 10") and not mixed_info.contains("Armor 3"), "mixed selection never adopts first-unit attack or armor")
	var command_ids: Array[int] = []
	for control: Node in (_hud.get("_unit_command_container") as Node).get_children():
		command_ids.append(control.get_instance_id())
	_hud.call("configure_unit_commands", true, true, "Mixed", "attack_move")
	await _state("attack-armed", ["Selection composition"], false)
	_expect((_hud.get("selection_details") as Label).text.begins_with("Tap attack-move"), "armed order prompt retains priority")
	_expect((_hud.get("_unit_attack_move_button") as Button).button_pressed, "armed icon remains highlighted")
	_hud.call("show_unit_selection", "Army", 170, 200, "Mixed (4 units)", 4, {"role_counts": {UnitData.UnitType.ARCHER: 2, UnitData.UnitType.INFANTRY: 2}})
	var refreshed_ids: Array[int] = []
	for control: Node in (_hud.get("_unit_command_container") as Node).get_children():
		refreshed_ids.append(control.get_instance_id())
	_expect(command_ids == refreshed_ids, "status refresh retains command node identity")
	NetworkSession.online = true
	_hud.call("show_unit_selection", "Army", 170, 200, "Mixed (4 units)", 4, {"role_counts": {UnitData.UnitType.ARCHER: 2, UnitData.UnitType.INFANTRY: 2}})
	if not _baseline:
		var replica_info: String = str((_hud.call("_selection_information") as Dictionary).body)
		_expect(replica_info.contains("Archer ×2") and not replica_info.contains("Attack 9"), "online composition uses only supplied roster, no inferred live stats")
	NetworkSession.online = false
	selection.call("select_single", roster[5])
	await _state("scout", ["Reconnaissance · unarmed", "Attack 0", "cannot fight back"], false)
	# Stress the minimum-width text column without spawning a fake large battle.
	_hud.call("show_unit_selection", "Army", 8450, 10000, "Mixed (36 units)", 36, {"role_counts": {UnitData.UnitType.INFANTRY: 30, UnitData.UnitType.ARCHER: 2, UnitData.UnitType.CAVALRY: 1, UnitData.UnitType.SCOUT: 1, UnitData.UnitType.SIEGE: 1, UnitData.UnitType.VILLAGER: 1}})
	_hud.call("configure_unit_commands", true, true, "Mixed", "smart")
	await _state("large-counts", ["Combined health 8450 / 10000 across 36 selected units", "Warrior ×30"], false)
	if not _baseline:
		_expect((_hud.get("selection_details") as Label).text == "Warrior ×30\n+5 other types", "large count and remaining type count are explicit")
	selection.call("select_single", roster[7])
	if not _baseline:
		var worker_info: String = str((_hud.call("_selection_information") as Dictionary).body)
		_expect(not worker_info.contains("Selection composition") and not worker_info.contains("Attack 9"), "selection change clears former roster/stats")
	var enemy: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 1, tc.position + Vector2(230, 150))
	GameManager.apply_attack_upgrade(1, 5)
	GameManager.apply_armor_upgrade(1, 3)
	selection.call("select_single", enemy)
	_expect(not bool(_hud.get("_unit_commands_authorized")), "enemy remains inspection-only")
	await _state("enemy-local", ["Attack 13", "Armor 5"], false)
	# Feed the real client replica adapter, with only own upgrades disclosed by
	# the snapshot. Deliberately retain stale enemy bonuses from the offline case
	# to prove Main does not turn unavailable online research into claimed stats.
	NetworkSession.online = true
	var adapter: Node = load("res://scripts/network/network_match.gd").new()
	main.add_child(adapter)
	adapter.call("setup", main)
	adapter.set_process(false)
	for slot: int in [0, 1]:
		NetworkSession.player_slot = slot
		var own_id: int = 9001 + slot * 10
		var enemy_id: int = own_id + 1
		adapter.call("apply_snapshot", {"upgrades": {"attack_bonus": 2, "armor_bonus": 1}, "actors": [
			{"id": own_id, "kind": "unit", "type": UnitData.UnitType.ARCHER, "owner": slot, "x": tc.position.x + 200, "y": tc.position.y + 60, "hp": 21.0, "max_hp": 35.0, "state": UnitBase.State.ATTACKING, "stance": UnitBase.Stance.STAND_GROUND},
			{"id": enemy_id, "kind": "unit", "type": UnitData.UnitType.INFANTRY, "owner": 1 - slot, "x": tc.position.x + 240, "y": tc.position.y + 100, "hp": 40.0, "max_hp": 60.0, "state": UnitBase.State.MOVING, "stance": UnitBase.Stance.AGGRESSIVE},
		]})
		var own_replica: UnitBase = adapter.get("entities")[own_id]
		var enemy_replica: UnitBase = adapter.get("entities")[enemy_id]
		_expect(own_replica.player_owner == 0 and enemy_replica.player_owner == 1, "snapshot remaps own/enemy for slot%d" % slot)
		_expect(own_replica.process_mode == Node.PROCESS_MODE_DISABLED and enemy_replica.process_mode == Node.PROCESS_MODE_DISABLED, "snapshot replicas remain inert")
		selection.call("select_single", own_replica)
		if not _baseline:
			var own_info: String = str((_hud.call("_selection_information") as Dictionary).body)
			_expect(own_info.contains("Attack 9") and own_info.contains("Armor 1") and not own_info.contains("Base attack"), "online own researched stats retained for slot%d" % slot)
		selection.call("select_single", enemy_replica)
		await _state("enemy-online-slot%d" % slot, ["Base attack 8", "Base armor 2", "Enemy research is not shown online."], slot == 1)
		_expect(not bool(_hud.get("_unit_commands_authorized")), "online enemy remains inspection-only")
		if not _baseline:
			var enemy_info: String = str((_hud.call("_selection_information") as Dictionary).body)
			_expect(not enemy_info.contains("Attack 13") and not enemy_info.contains("Armor 5"), "stale enemy research never leaks into observed online values")
	NetworkSession.online = false
	NetworkSession.player_slot = 0
	get_tree().paused = false
	main.free()
	await get_tree().process_frame


func _state(state: String, required: Array[String], capture_info: bool) -> void:
	await _settle()
	var panel: Control = _hud.get("selection_panel")
	var details: Label = _hud.get("selection_details")
	var info: Dictionary = _hud.call("_selection_information")
	var complete_lines: bool = true
	for label: Label in [details, (_hud.get("selection_hp_bar") as Node).get_node("SelectionMeterValue")]:
		for line: String in label.text.split("\n"):
			var width: float = label.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			complete_lines = complete_lines and width <= label.size.x + 0.5
			if not _baseline:
				var budget: float = minf(96.0, label.size.x)
				_expect(width <= budget + 0.5, state + " complete line at96px minimum: " + line + " width=" + str(width) + " available=" + str(budget))
	_expect(panel.size.y <= 80.5, state + " dock remains at most80px")
	_expect(_safe.grow(1.0).encloses(panel.get_global_rect()), state + " dock respects safe area")
	if not _baseline:
		for phrase: String in required:
			_expect(str(info.body).contains(phrase), state + " inspection includes " + phrase)
	_records.append({"profile": _profile, "state": state, "details": details.text, "info": info, "complete_lines": complete_lines, "dock": str(panel.get_global_rect()), "safe": str(_safe), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	await _capture(state)
	await _tap(_hud.get("_selection_info_button"))
	_expect(_hud.call("get_secondary_surface_name") == "info", state + " actual touch opens Info")
	var info_panel: Control = _hud.get("_info_panel")
	_expect(_safe.grow(1.0).encloses(info_panel.get_global_rect()), state + " Info inside safe area")
	_expect((_hud.get("_info_body") as Label).text == str(info.body), state + " touch card displays current inspection")
	if capture_info:
		await _capture(state + "-info")
		var scroll: ScrollContainer = info_panel.find_child("InfoScroll", true, false)
		if scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page:
			var scroll_point: Vector2 = scroll.get_global_rect().get_center()
			for step: int in 20:
				for pressed: bool in [true, false]:
					var wheel := InputEventMouseButton.new()
					wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
					wheel.position = get_viewport().get_final_transform() * scroll_point
					wheel.pressed = pressed
					Input.parse_input_event(wheel)
					Input.flush_buffered_events()
				await _frame()
				if state == "six-types":
					await _capture(state + "-info-page-%02d" % step)
				if scroll.scroll_vertical >= scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page:
					break
			_expect(scroll.scroll_vertical > 0, state + " ordinary wheel reaches overflow")
			await _capture(state + "-info-scroll")
	await _tap(info_panel.find_child("InfoCloseButton", true, false))
	_expect(_hud.call("get_secondary_surface_name") == "none", state + " actual touch closes Info")


func _settle() -> void:
	for frame: int in 6:
		await _frame()


func _frame() -> void:
	await get_tree().process_frame
	# Real DisplayServer does not know the modeled notch/browser clearance.
	# Restore it after deferred layout work, including opening an Info card.
	_hud.call("apply_mobile_layout", get_viewport().get_visible_rect().size, _safe)


func _tap(button: Button) -> void:
	var point: Vector2 = get_viewport().get_final_transform() * button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 7
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		for frame: int in 3:
			await _frame()


func _capture(state: String) -> void:
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_output + "/" + _profile + "-" + state + ".png")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(_profile + ": " + description)
