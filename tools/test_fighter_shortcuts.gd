extends "res://tools/test_strategy_overview.gd"
## Synthetic roster, real navigation and native ScreenTouch controls. Tests
## selection/camera only; not an ordinary paid match or a physical-phone test.

var _fighter_checks: int = 0


func _apply_profile_layout() -> void:
	if _synthetic_notch:
		super._apply_profile_layout()


func _expect(condition: bool, message: String) -> void:
	_fighter_checks += 1
	super._expect(condition, message)


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for large: bool in [false, true]:
			await _fighter_journey(phone, 1.15 if large else 1.0, large)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("fighter-shortcuts.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Synthetic roster in real Main, normal navigation, native ScreenTouch selection/Find/Move/group controls, actual local replica adapter. No paid gameplay, live socket, pacing or physical phone claim.", "checks": _fighter_checks, "failures": _failures, "profiles": _receipts}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] fighter_shortcuts: " + failure)
	if _failures.is_empty():
		print("[PASS] fighter_shortcuts: %d checks;4 phone/notch profiles; accepted Scout route survives fighter selection/Find, deliberate Scout group/Move remains, empty/0damage/foreign/dead filtering, remapped inert replicas" % _fighter_checks)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _fighter_journey(phone: Vector2i, scale: float, notched: bool) -> void:
	_profile = "%dx%d-%d-%s" % [phone.x, phone.y, roundi(scale * 100.0), "notched" if notched else "ordinary"]
	_synthetic_notch = notched
	_hud = null
	NetworkSession.online = false
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = scale
	GameManager.ui_scale = scale
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.selected_opponent_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.guided_opening_enabled = false
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_map = _main.get_node("GameMap")
	_hud = _main.get_node("HUD")
	_selection = _map.selection_mgr
	_main.set_process(false)
	_main.get_node("AIController").set_process(false)
	_main.get_node("AIController").get("_decision_timer").stop()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var controller: Node = _main.get_node("StrategyController")
	controller.set_process(false)
	await _frames(6)
	_hud.call("set_early_game_ui_state", false)
	_hud.call("set_progression_hint", "")
	_hud.set("_movement_controls_hint_shown", true)
	var scout: UnitBase = _spawn_frozen(UnitData.UnitType.SCOUT, 0, _walkable_near(Vector2i(20, 20)))
	var first: UnitBase = _spawn_frozen(UnitData.UnitType.INFANTRY, 0, _walkable_near(Vector2i(42, 42)))
	var second: UnitBase = _spawn_frozen(UnitData.UnitType.CAVALRY, 0, _walkable_near(Vector2i(43, 42)))
	var foe: UnitBase = _spawn_frozen(UnitData.UnitType.INFANTRY, 1, _walkable_near(Vector2i(55, 55)))
	_expect(not bool(_main.call("_is_live_owned_fighter", scout)) and not bool(_main.call("_is_live_owned_fighter", foe)), "Scout and foreign armed unit are never bulk fighters")
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	_main.call("_update_fog_of_war")
	var camera: Camera2D = _map.camera
	_map.note_camera_interaction()
	camera.position = scout.global_position
	_map._clamp_camera()
	camera.reset_smoothing()
	camera.force_update_scroll()
	_selection.deselect_all()
	await _frames(3)
	# Use actual world touch to deliberately select the unarmed Scout.
	await _tap(get_viewport().get_canvas_transform() * scout.global_position)
	_expect(_selection.selected == [scout], "native world touch still selects the Scout deliberately")
	await _button(_hud.get("_unit_move_button"))
	var destination: Vector2 = _empty_ground(scout)
	_expect(destination != Vector2.ZERO, "visible legal Scout route is available")
	await _tap(destination)
	_expect(scout.current_state == UnitBase.State.MOVING and not scout.path.is_empty(), "native Move plus ground accepts a real recon route")
	var recon: Dictionary = _intent(scout)
	_main.call("_update_idle_villager_count")
	controller.call("_refresh")
	var overview: StrategyOverview = _hud.get("_strategy_overview")
	var army_button: Button = overview.rail.get_node("ArmyButton")
	_expect(army_button.get_node("CommandIconBadge").text == "2" and army_button.accessibility_name.contains("2 fighters"), "rail badge and accessibility count armed fighters only")
	_expect(int(_hud.get("_last_military_count")) == 2, "legacy HUD count matches fighter roster")
	await _button(army_button)
	if bool(overview.get("_army_recruit_page")):
		await _button(overview.get("_groups_tab"))
	var select_button: Button = overview.get("_select_army_button")
	_check_caption_fit(select_button)
	_expect(select_button.text == "Select fighters", "bulk action names the units it will select")
	await _overview_button(overview, overview.get("_group_rows")[1].save)
	_expect(_main.get("_control_groups")[1] == [scout], "explicit group save can still contain a Scout")
	await _overview_button(overview, select_button)
	_expect(_selection.selected.size() == 2 and first in _selection.selected and second in _selection.selected and scout not in _selection.selected, "real fighter shortcut selects only the compact armed pair")
	_expect(_intent(scout) == recon and ResourceManager.get_all_resources(0) == bank, "fighter selection leaves accepted Scout intent and bank untouched")
	var fighter_center: Vector2 = (first.global_position + second.global_position) / 2.0
	_expect(scout.global_position.distance_to(fighter_center) > 500.0, "Scout is far enough away to expose incorrect averaging")
	await _button(army_button)
	await _overview_button(overview, overview.get("_focus_army_button"))
	_expect(camera.position.distance_to(fighter_center) < 1.0, "native Find army frames the fighters instead of the separated Scout")
	_expect(_intent(scout) == recon and _selection.selected.size() == 2, "Find changes camera only, preserving orders and selection")
	await _capture("fighters-found-scout-preserved")
	await _button(army_button)
	await _overview_button(overview, overview.get("_group_rows")[1].recall)
	_expect(_selection.selected == [scout] and _intent(scout) == recon, "explicit group recall restores the Scout without changing its route")
	# Explicit Scout control remains available after battle navigation.
	await _button(_hud.get("_camera_view_button"))
	await _button(_hud.get("_camera_center_button"))
	await _button(_hud.get("_camera_view_button"))
	# Modeled final Guide stage: the same explicit Scout touch must still finish it.
	_main.set("_guided_opening_active", true)
	_main.set("_guided_stage", 3) # GuidedOpeningStage.MOVE_MILITARY
	_main.set("_opening_military_move_complete", false)
	await _button(_hud.get("_unit_move_button"))
	destination = _empty_ground(scout)
	await _tap(destination)
	_expect(scout.current_state == UnitBase.State.MOVING and not scout.path.is_empty(), "deliberate Scout Move still works after recall/Center")
	_expect(bool(_main.get("_opening_military_move_complete")) and not bool(_main.get("_guided_opening_active")), "accepted direct Scout touch still completes the final Guide stage")
	recon = _intent(scout)
	# Pending/incomplete zero-damage setup must not enable battle shortcuts.
	var first_damage: float = first.damage
	var second_damage: float = second.damage
	first.damage = 0.0
	second.damage = 0.0
	controller.call("_refresh")
	_main.call("_update_idle_villager_count")
	_expect(not bool(_main.call("_is_live_owned_fighter", first)) and int(_hud.get("_last_military_count")) == 0, "zero-damage actor setup is not combat-ready")
	await _button(army_button)
	_expect(select_button.disabled and (overview.get("_focus_army_button") as Button).disabled and army_button.get_node("CommandIconBadge").text == "0", "Scout-only combat roster honestly disables selection and Find")
	_hud.call("close_secondary_surface")
	var empty_camera: Vector2 = camera.position
	await _action("select_all_military")
	await _action("find_army")
	_expect(_selection.selected == [scout] and camera.position.is_equal_approx(empty_camera) and _intent(scout) == recon, "empty keyboard shortcuts preserve explicit Scout selection, view and orders")
	first.damage = first_damage
	second.damage = second_damage
	first.set_state(UnitBase.State.DEAD)
	second.set_state(UnitBase.State.DEAD)
	controller.call("_refresh")
	_expect(int(overview.get("_snapshot").fighters) == 0, "dead fighters stay excluded even with positive base damage")
	await _check_replica_fighters(controller, overview, bank)
	_receipts.append({"profile": _profile, "scout_route": recon, "fighter_center": str(fighter_center), "separation": scout.global_position.distance_to(fighter_center), "bank_unchanged_before_replica_fixture": ResourceManager.get_all_resources(0) == bank})
	NetworkSession.online = false
	NetworkSession.player_slot = 0
	_main.free()
	_main = null
	_hud = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)


func _spawn_frozen(type: int, owner: int, point: Vector2) -> UnitBase:
	var unit: UnitBase = _main.call("_spawn_unit", type, owner, point)
	unit.set_process(false)
	return unit


func _walkable_near(tile: Vector2i) -> Vector2:
	for radius: int in range(0, 5):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				var candidate := tile + Vector2i(x, y)
				if _map.is_tile_walkable(candidate):
					return _map.tile_to_world(candidate)
	return _map.tile_to_world(tile)


func _intent(unit: UnitBase) -> Dictionary:
	return {"state": unit.current_state, "target": unit.move_target, "path": unit.path.duplicate(), "attack_move": unit.attack_move, "force_move": unit.get("_force_move_active")}


func _check_replica_fighters(controller: Node, overview: StrategyOverview, bank: Dictionary) -> void:
	NetworkSession.online = true
	NetworkSession.player_slot = 1
	var adapter: Node = load("res://scripts/network/network_match.gd").new()
	_main.add_child(adapter)
	adapter.main = _main
	adapter.game_map = _map
	adapter.set_process(false)
	var point: Vector2 = _walkable_near(Vector2i(36, 36))
	var actors: Array = []
	for data: Array in [[9901, 1, UnitData.UnitType.CAVALRY], [9902, 1, UnitData.UnitType.SCOUT], [9903, 0, UnitData.UnitType.INFANTRY]]:
		actors.append({"id": data[0], "kind": "unit", "type": data[2], "owner": data[1], "x": point.x + actors.size() * 36.0, "y": point.y, "hp": 30.0, "max_hp": 30.0, "state": UnitBase.State.MOVING, "stance": UnitBase.Stance.AGGRESSIVE})
	adapter.apply_snapshot({"actors": actors, "bank": bank, "civilizations": [0, 0]})
	var fighter: UnitBase = adapter.entities[9901]
	var scout: UnitBase = adapter.entities[9902]
	var enemy: UnitBase = adapter.entities[9903]
	_expect(fighter.player_owner == 0 and fighter.process_mode == Node.PROCESS_MODE_DISABLED and bool(_main.call("_is_live_owned_fighter", fighter)), "remapped inert own armed replica remains selectable as a fighter")
	_expect(not bool(_main.call("_is_live_owned_fighter", scout)) and not bool(_main.call("_is_live_owned_fighter", enemy)), "replica Scout and enemy never enter own fighter shortcut")
	controller.call("_refresh")
	_main.call("_update_idle_villager_count")
	_expect(int(overview.get("_snapshot").fighters) == 1 and int(_hud.get("_last_military_count")) == 1, "replica controller and HUD counts agree")
	await _button(overview.rail.get_node("ArmyButton"))
	await _overview_button(overview, overview.get("_select_army_button"))
	_expect(_selection.selected == [fighter], "actual touch fighter shortcut selects own inert replica only")
	await _button(overview.rail.get_node("ArmyButton"))
	await _overview_button(overview, overview.get("_focus_army_button"))
	_expect((_map.camera as Camera2D).position.distance_to(fighter.global_position) < 1.0, "actual touch Find frames only own inert fighter")
