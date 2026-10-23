extends Node
## Real Main dispatch: unarmed scouts explain rejected attacks without losing
## their move order, while mixed armed groups and explicit movement still work.

var _failures: Array[String] = []
var _main: Node
var _map: Node2D
var _hud: CanvasLayer
var _selection: SelectionManager
var _viewport: SubViewport
var _captures: Array[String] = []
var _geometry: Array[Dictionary] = []
var _had_preferences: bool = false
var _preferences_before: PackedByteArray

const PHONE_SIZE := Vector2i(844, 390)
const CAPTURE_OUTPUT := "res://output/polish-2026-10-22/scout-orders"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_had_preferences = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_preferences:
		_preferences_before = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	AudioManager.set_all_enabled(false)
	GameManager.audio_enabled = false
	GameManager.ui_scale = 1.0
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 30
	_viewport = SubViewport.new()
	_viewport.size = PHONE_SIZE
	_viewport.handle_input_locally = true
	if DisplayServer.get_name() != "headless":
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_main = load("res://scenes/main/main.tscn").instantiate()
	_viewport.add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_expect(_main.get("_building_placement") != null, "Main initializes the real match")
	if _main.get("_building_placement") == null:
		_finish()
		return
	_main.set_process(false)
	(_main.get_node("AIController") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	_main.get_node("AIController").get("_decision_timer").stop()
	_main.get_node("StrategyController").set_process(false)
	_map = _main.get_node("GameMap") as Node2D
	_map.set_process(false)
	_hud = _main.get_node("HUD") as CanvasLayer
	_selection = _map.get("selection_mgr") as SelectionManager
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var fog: FogManager = _map.get("fog_of_war") as FogManager
	for y: int in MapData.MAP_HEIGHT:
		for x: int in MapData.MAP_WIDTH:
			fog.fog_grid[y][x] = MapData.FogState.VISIBLE
	# This is a synthetic UI fixture, not ordinary-resource gameplay evidence.
	# Match the pre-existing visible target setup in the native capture too.
	fog.set("_initial_apply_done", false)
	fog.call("_apply_fog_delta")
	var scout: UnitBase = _unit("scout", 0, Vector2i(20, 20))
	var second: UnitBase = _unit("scout", 0, Vector2i(20, 21))
	var warrior: UnitBase = _unit("infantry", 0, Vector2i(21, 20))
	var enemy: UnitBase = _unit("infantry", 1, Vector2i(23, 20))
	var building: BuildingBase = load("res://scenes/buildings/house.tscn").instantiate()
	building.player_owner = 1
	building.state = BuildingBase.State.ACTIVE
	building.position = _map.tile_to_world(Vector2i(23, 21))
	_map.get_node("BuildingsContainer").add_child(building)
	building.set_process(false)
	var destination: Vector2 = _map.tile_to_world(Vector2i(20, 24))
	scout.command_move(destination)
	_selection.select_single(scout)
	await _settle_phone()
	_main.call("_center_camera_on_selection")
	_expect((_hud.get("_unit_attack_move_button") as Button).tooltip_text.contains("armed units"), "Scout attack-move tooltip qualifies which units fight")
	_expect(str(_hud.call("_selection_information")).contains("Scouts are unarmed"), "Scout selection Info explains its inability to attack")
	for target: Node2D in [enemy, building]:
		_clear_notices()
		_main.call("_on_attack_command", target)
		_expect(_notices().contains("Scouts are unarmed"), "direct Scout attack on %s explains the rejection" % target.name)
		_expect(scout.current_state == UnitBase.State.MOVING and scout.move_target == destination and scout.attack_target == null and scout.attack_building_target == null, "rejected attack preserves the Scout's existing move order")
		await _check_phone_rejection("unit" if target is UnitBase else "building")
	await _check_phone_info()
	_selection.select_many([scout, second])
	_clear_notices()
	_main.call("_on_attack_command", enemy)
	_expect(_notices().contains("Scouts are unarmed"), "all-Scout groups receive the same useful rejection")
	_expect(str(_hud.call("_selection_information")).contains("Scouts are unarmed"), "same-role Scout group Info retains the unarmed explanation")
	await _check_phone_rejection("all-scouts")
	_selection.select_many([scout, warrior])
	_clear_notices()
	_main.call("_on_attack_command", enemy)
	_expect(warrior.current_state == UnitBase.State.ATTACKING and warrior.attack_target == enemy, "mixed armed group still accepts a unit attack")
	_expect(not _notices().contains("Scouts are unarmed") and scout.attack_target == null, "mixed group does not reject armed units or make Scouts fight")
	_main.call("_on_attack_command", building)
	_expect(warrior.current_state == UnitBase.State.ATTACKING and warrior.attack_building_target == building, "mixed armed group still accepts a building attack")
	_selection.select_single(scout)
	_clear_notices()
	_main.call("_arm_move_command")
	_main.call("_on_attack_command", enemy)
	_expect(scout.current_state == UnitBase.State.MOVING and scout.move_target != destination, "explicit Move to a target routes to movement before unarmed-attack rejection")
	_expect(not _notices().contains("Scouts are unarmed"), "explicit movement is not mislabeled as an attack")
	_finish()


func _settle_phone() -> void:
	var size := Vector2(PHONE_SIZE)
	_hud.call("apply_mobile_layout", size, Rect2(Vector2.ZERO, size))
	for frame: int in 4:
		await get_tree().process_frame


func _check_phone_rejection(context: String) -> void:
	await _settle_phone()
	var safe := Rect2(Vector2.ZERO, Vector2(PHONE_SIZE))
	var feed := _hud.get("_notification_container") as Control
	var found := false
	for child: Node in feed.get_children():
		if child.is_queued_for_deletion() or child.get_child_count() == 0 or not child.get_child(0) is Label:
			continue
		var label := child.get_child(0) as Label
		if not label.text.contains("Scouts are unarmed"):
			continue
		found = true
		var toast := child as Control
		_expect(toast.is_visible_in_tree(), context + " rejection toast is visible")
		_expect(safe.encloses(toast.get_global_rect()), context + " rejection toast remains inside 844x390")
		_expect(label.get_line_count() == label.get_visible_line_count(), context + " rejection toast shows every wrapped line")
		_expect(label.get_minimum_size().y <= label.size.y + 0.5, context + " rejection text does not clip vertically")
		for key: String in ["_camera_controls", "selection_panel", "_pause_button"]:
			var control := _hud.get(key) as Control
			if is_instance_valid(control) and control.is_visible_in_tree():
				_expect(not toast.get_global_rect().intersects(control.get_global_rect()), context + " rejection toast avoids " + key)
		_geometry.append({"context": context, "toast": str(toast.get_global_rect()), "text": label.text, "lines": label.get_line_count(), "visible_lines": label.get_visible_line_count(), "attack_move_tooltip": (_hud.get("_unit_attack_move_button") as Button).tooltip_text})
	_expect(found, context + " rejection text exists for geometry inspection")
	await _capture("rejected-attack-%s-844x390.png" % context)


func _check_phone_info() -> void:
	var info := _hud.get("_selection_info_button") as Button
	_expect(info.is_visible_in_tree() and info.size.x >= 48.0 and info.size.y >= 48.0, "Scout Info has a visible 48px tap target")
	await _tap(info.get_global_rect().get_center())
	await _settle_phone()
	var panel := _hud.get("_info_panel") as Control
	var body := _hud.get("_info_body") as Label
	var scroll := panel.find_child("InfoScroll", true, false) as ScrollContainer
	var close := panel.find_child("InfoCloseButton", true, false) as Button
	_expect(_hud.call("get_secondary_surface_name") == "info" and panel.is_visible_in_tree(), "actual tap opens Scout selection Info")
	_expect((_hud.call("get_hold_safe_rect") as Rect2).encloses(panel.get_global_rect()), "Scout Info stays within the rail-reserved reading area")
	_expect(body.text.contains("Scouts are unarmed") and body.text.contains("cannot fight back"), "visible Scout Info explains its combat limit")
	_expect(close.size.x >= 48.0 and close.size.y >= 48.0 and panel.get_global_rect().encloses(close.get_global_rect()), "Scout Info Close remains a safe 48px target")
	_expect(not (_hud.get("_notification_container") as Control).is_visible_in_tree(), "opening Info hides the prior rejection toast instead of overlapping it")
	_geometry.append({"context": "info-top", "panel": str(panel.get_global_rect()), "scroll": str(scroll.get_global_rect()), "body": body.text, "body_height": body.size.y, "scroll_max": scroll.get_v_scroll_bar().max_value, "scroll_page": scroll.get_v_scroll_bar().page})
	await _capture("selection-info-top-844x390.png")
	# Check real wheel input can reach the end of the long explanation, then
	# close via the button. A bounded card must not silently truncate its body.
	for step: int in 24:
		await _pointer_button(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	await _settle_phone()
	var last_scroll: float = maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
	_expect(float(scroll.scroll_vertical) >= last_scroll - 1.0, "Scout Info can scroll to its final explanation by real pointer input")
	_geometry.append({"context": "info-bottom", "scroll_vertical": scroll.scroll_vertical, "last_scroll": last_scroll})
	await _capture("selection-info-bottom-844x390.png")
	await _tap(close.get_global_rect().get_center())
	await _settle_phone()
	_expect(_hud.call("get_secondary_surface_name") == "none" and _selection.selected.size() == 1, "Info Close preserves the selected Scout")


func _tap(position: Vector2) -> void:
	await _pointer_button(position, MOUSE_BUTTON_LEFT)


func _pointer_button(position: Vector2, button_index: MouseButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button_index
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button_index == MOUSE_BUTTON_LEFT else 0
		event.position = position
		event.global_position = position
		event.pressed = pressed
		_viewport.push_input(event, true)
		await get_tree().process_frame


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_OUTPUT))
	await RenderingServer.frame_post_draw
	var error: Error = _viewport.get_texture().get_image().save_png(CAPTURE_OUTPUT.path_join(filename))
	_expect(error == OK, "native Scout feedback capture saves " + filename)
	if error == OK:
		_captures.append(filename)


func _unit(scene_name: String, owner: int, tile: Vector2i) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % scene_name).instantiate()
	unit.player_owner = owner
	unit.position = _map.tile_to_world(tile)
	_map.get_node("UnitsContainer").add_child(unit)
	unit.set_process(false)
	return unit


func _clear_notices() -> void:
	for child: Node in (_hud.get("_notification_container") as Control).get_children():
		child.free()


func _notices() -> String:
	var text := ""
	for child: Node in (_hud.get("_notification_container") as Control).get_children():
		if child.get_child_count() > 0 and child.get_child(0) is Label:
			text += (child.get_child(0) as Label).text + "\n"
	return text


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_OUTPUT))
	var report := FileAccess.open(CAPTURE_OUTPUT.path_join("evidence.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"captures": _captures, "geometry": _geometry, "failures": _failures, "scope": "Synthetic real-Main dispatch/UI fixture at fixed 844x390; units created by fixture, fog revealed and simulation disabled. Native images only when not headless. No paid-match, combat-balance, device or performance claim."}, "\t") + "\n")
	else:
		_expect(false, "Scout evidence report opens for writing")
	if _had_preferences:
		FileAccess.open(GameManager.PREFERENCES_PATH, FileAccess.WRITE).store_buffer(_preferences_before)
	else:
		DirAccess.remove_absolute(GameManager.PREFERENCES_PATH)
	_viewport.free()
	if _failures.is_empty():
		print("[PASS] scout_order_feedback: single/group Scout rejection; movement preserved; mixed attacks; 844x390 rejection/Info geometry; actual Info tap/scroll/close; %d native captures" % _captures.size())
	else:
		for failure: String in _failures:
			push_error("[FAIL] scout_order_feedback: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
