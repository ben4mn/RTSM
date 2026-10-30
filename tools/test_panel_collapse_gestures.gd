extends Node
## Double-tap a panel's background to tuck it away; tap the pill (or launcher)
## to bring it back. Real ScreenTouch contacts on an 844x390 phone.

var _failures: Array[String] = []
var main: Node
var hud: CanvasLayer


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	await _frames(6)
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	hud = main.get("hud")
	Input.emulate_mouse_from_touch = true
	ResourceManager._player_resources[0] = {"food": 10000, "wood": 10000, "gold": 10000}
	await _check_dock()
	await _check_strategy_sheet()
	await _check_build_sheet()
	main.free()
	if _failures.is_empty():
		print("[PASS] panel_collapse_gestures: dock, workers sheet and build sheet tuck on double tap and return on tap")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] panel_collapse_gestures: %s" % failure)
		get_tree().quit(1)


func _check_dock() -> void:
	var tc: Node = main.get("_player_town_center")
	main.game_map.selection_mgr.select_single(tc)
	await _frames(6)
	var panel: Control = hud.selection_panel
	var expanded_width: float = panel.size.x
	_expect(not hud.is_dock_collapsed() and hud.command_scroll.visible, "the dock starts expanded")
	var background := Vector2(panel.get_global_rect().position.x + 3.0, panel.get_global_rect().get_center().y)
	await _tap_at(background)
	await _wait_msec(450)
	_expect(not hud.is_dock_collapsed(), "one tap on the dock background does not collapse it")
	await _double_tap(background)
	_expect(hud.is_dock_collapsed() and not hud.command_scroll.visible, "double-tapping the dock background collapses it")
	await _frames(4)
	_expect(panel.size.x < expanded_width, "the collapsed dock is a smaller pill (%.0f < %.0f)" % [panel.size.x, expanded_width])
	_expect(panel.size.y >= 48.0, "the pill keeps a 48px touch target")
	await _wait_msec(450)
	background = Vector2(panel.get_global_rect().position.x + 3.0, panel.get_global_rect().get_center().y)
	await _tap_at(background)
	await _frames(4)
	_expect(not hud.is_dock_collapsed() and hud.command_scroll.visible, "tapping the pill brings the orders back")
	await _wait_msec(450)
	# Two quick taps on a recruitment button recruit twice; the dock stays.
	var train: Button = hud._train_buttons_container.get_node("TrainButton_%s" % UnitData.UnitType.VILLAGER)
	var queue: Node = tc.get_production_queue()
	var before: int = queue.queue.size()
	await _double_tap(train.get_global_rect().get_center())
	await _frames(4)
	_expect(not hud.is_dock_collapsed(), "double-tapping a button never collapses the dock")
	_expect(queue.queue.size() == before + 2, "both taps on the button still recruit (%d -> %d)" % [before, queue.queue.size()])
	main.game_map.selection_mgr.deselect_all()
	await _frames(4)


func _check_strategy_sheet() -> void:
	var overview: Node = hud.get("_strategy_overview")
	hud.call("_set_secondary_surface", hud.SecondarySurface.ECONOMY)
	await _frames(6)
	var panel: Control = overview.panel
	_expect(panel.is_visible_in_tree(), "the workers sheet opens")
	overview.call("_set_production_page", true)
	await _frames(4)
	var background: Vector2 = _background_point(panel)
	_expect(background.x >= 0.0, "the workers sheet has background to double-tap")
	await _double_tap(background)
	await _wait_msec(400)
	_expect(not panel.is_visible_in_tree() and hud.get_secondary_surface_name() != "economy", "double-tapping the workers sheet tucks it away")
	_expect(overview.rail.is_visible_in_tree(), "its launcher stays on screen to bring it back")
	var launcher: Button = overview.get("_economy_button")
	await _tap_at(launcher.get_global_rect().get_center())
	await _frames(6)
	_expect(panel.is_visible_in_tree() and bool(overview.get("_production_page")), "the launcher brings the sheet back on the same page")
	hud.close_secondary_surface()
	await _frames(4)


func _check_build_sheet() -> void:
	var menu: Control = main.get("_build_menu")
	hud.call("_on_build_menu_pressed")
	await _frames(6)
	_expect(hud.is_build_menu_open() and menu.is_visible_in_tree(), "the build sheet opens")
	menu.call("_on_category_pressed", "Army")
	await _frames(4)
	var background := Vector2(menu.get_global_rect().position.x + 3.0, menu.get_global_rect().get_center().y)
	await _double_tap(background)
	await _wait_msec(400)
	_expect(not hud.is_build_menu_open() and not menu.is_visible_in_tree(), "double-tapping the build sheet tucks it into Build")
	_expect(menu.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(menu.modulate.a, 1.0), "the tucked sheet is restored to full size for next time")
	await _tap_at(hud.build_menu_button.get_global_rect().get_center())
	await _frames(6)
	_expect(hud.is_build_menu_open() and menu.is_visible_in_tree(), "tapping Build brings the sheet back")
	_expect(str(menu.get("_active_category")) == "Army", "the sheet returns on the group it was tucked from")
	hud.close_build_menu()
	await _frames(4)


func _background_point(panel: Control) -> Vector2:
	# A spot on the sheet that no button, field or other tap-owning control covers.
	var owners: Array[Rect2] = []
	var pending: Array[Node] = panel.get_children()
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if control is BaseButton or control is LineEdit or (control.mouse_filter == Control.MOUSE_FILTER_STOP and not control is Container and not control.has_meta("double_tap_gesture")):
			owners.append(control.get_global_rect().grow(3.0))
	var area: Rect2 = panel.get_global_rect().grow(-2.0)
	var y: float = area.position.y
	while y < area.end.y:
		var x: float = area.position.x
		while x < area.end.x:
			var free: bool = true
			for owner: Rect2 in owners:
				if owner.has_point(Vector2(x, y)):
					free = false
					break
			if free:
				return Vector2(x, y)
			x += 3.0
		y += 3.0
	return Vector2(-1, -1)


func _double_tap(point: Vector2) -> void:
	await _tap_at(point)
	await _wait_msec(90)
	await _tap_at(point)
	await _frames(3)


func _tap_at(point: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 3
		event.position = get_viewport().get_final_transform() * point
		event.pressed = down
		Input.parse_input_event(event)
		await _frames(2)


func _wait_msec(msec: int) -> void:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < msec:
		await get_tree().process_frame


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
