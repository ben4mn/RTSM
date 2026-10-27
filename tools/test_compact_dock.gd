extends Node
## Actual HUD targets and ScreenTouch production. Optional native render states.
var failures: Array[String] = []
var checks: int = 0
var main: Node
var hud: CanvasLayer
var output: String = ""
var rallies: int = 0
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.hold_shortcuts_enabled = true
	GameManager.selected_map_seed = 424242
	GameManager.selected_population_limit = 100
	get_window().size = Vector2i(844,390)
	get_window().content_scale_size = Vector2i(844,390)
	get_window().content_scale_factor = 1.0
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	await _frames(4)
	main.set_process(false)
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("StrategyController").set_process(false)
	main.game_map.set_process(false)
	for unit: Node in get_tree().get_nodes_in_group("units"): unit.set_process(false)
	for building: Node in get_tree().get_nodes_in_group("buildings"): building.set_process(false)
	hud = main.hud
	var tc: BuildingBase = main._player_town_center
	var queue: ProductionQueue = tc.get_production_queue()
	queue.set_process(false)
	ResourceManager._player_resources[0] = {"food": 10000, "wood": 10000, "gold": 10000}
	GameManager.increase_population_cap(0, 80)
	main.game_map.selection_mgr.select_single(tc)
	await _frames(5)
	var train: Button = hud._train_buttons_container.get_node("TrainButton_%s" % UnitData.UnitType.VILLAGER)
	_expect(train.text.is_empty() and train.has_node("TilePortrait") and train.has_node("TileCosts"), "recruitment uses portrait and persistent numeric resource chips")
	_expect(hud.selection_details.is_visible_in_tree() == false and not hud.selection_name.is_visible_in_tree(), "name and task paragraphs live behind portrait Info")
	_expect(hud.command_scroll.get_global_rect().grow(0.5).encloses(hud._building_rally_button.get_global_rect()), "phone rally flag is fully exposed, not clipped by Queue")
	var expanded: float = hud.selection_panel.size.x
	await _tap(hud._dock_toggle_button)
	_expect(hud._dock_collapsed and not hud.command_scroll.visible and hud.selection_panel.size.x < expanded, "touch chevron collapses commands into portrait dock")
	await _capture("collapsed")
	await _tap(hud._dock_toggle_button)
	_expect(not hud._dock_collapsed and hud.command_scroll.visible, "touch chevron restores actions")
	await _tap(hud._selection_info_button)
	_expect(hud.get_secondary_surface_name() == "info" and not hud._info_body.text.is_empty(), "portrait tap exposes full name and requirements")
	hud.close_secondary_surface()
	await _frames(3)
	hud.building_rally_requested.connect(func(building: Node2D) -> void:
		if building == tc: rallies += 1)
	await _tap(hud._building_rally_button)
	_expect(rallies == 1, "direct touch flag emits selected production building")
	hud.set_rally_armed(true)
	_expect(hud._building_rally_button.button_pressed, "armed rally is visibly selected")
	hud.set_rally_armed(false)
	if main.game_map.selection_mgr.has_method("cancel_building_rally"): main.game_map.selection_mgr.cancel_building_rally()
	Input.emulate_touch_from_mouse = false
	Input.emulate_mouse_from_touch = true
	var before: int = ResourceManager.get_resource(0, "food")
	var point: Vector2 = train.get_global_rect().get_center()
	await _touch(50, point, true)
	await get_tree().create_timer(1.8, true, false, true).timeout
	var bought: int = queue.queue.size()
	await _touch(50, point, false)
	await _frames(3)
	_expect(bought == ProductionQueue.MAX_QUEUE_SIZE and queue.queue.size() == bought, "actual compact tile hold fills finite queue without release extra buy")
	_expect(ResourceManager.get_resource(0,"food") == before - bought * int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).food), "compact hold pays exactly once per queued unit")
	await _capture("production")
	for surface: String in ["economy", "army"]:
		hud._strategy_overview.set_surface(surface)
		hud._queue_mobile_layout_refresh()
		await _frames(5)
		_expect(hud._strategy_overview.panel.get_global_rect().end.x <= 844.5 and hud._strategy_overview.panel.get_global_rect().end.y <= 390.5, "icon sheet stays inside phone: " + surface)
		await _capture(surface)
		hud._strategy_overview.set_surface("")
	await _check_trade_placement_strip()
	get_window().size = Vector2i(1280,720)
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().content_scale_factor = 1.0
	await _frames(5)
	hud.apply_mobile_layout(Vector2(1280,720), Rect2(0,0,1280,720))
	await _frames(5)
	_expect(hud.command_scroll.get_global_rect().grow(0.5).encloses(hud._building_rally_button.get_global_rect()), "desktop rally flag is fully exposed, not clipped by Queue")
	await _capture("production")
	await _check_trade_placement_strip()
	var worker: UnitBase = main._player_units[0][0]
	main.game_map.selection_mgr.select_single(worker)
	await _frames(5)
	for child: Node in hud._unit_command_container.get_children():
		if child is Button and child.visible: _expect(hud.command_scroll.get_global_rect().grow(0.5).encloses(child.get_global_rect()), "desktop unit action fully exposed: " + child.name)
	await _capture("worker")
	get_window().size = Vector2i(844,390)
	get_window().content_scale_size = Vector2i(844,390)
	get_window().content_scale_factor = 1.0
	await _frames(5)
	hud.set_save_status({"state":"saved"})
	hud.set_pause_display(true)
	await _frames(4)
	_expect(hud._pause_overlay.get_node_or_null("PauseMenu/SaveAndExitButton") != null and hud._save_status_label.text == "Saved", "solo pause offers save-and-exit and saved status")
	_expect(hud._pause_overlay.get_node_or_null("PauseMenu/DepartureRow/QuitButton") == null, "solo exit has one save-first action")
	hud.set_save_status({"state":"saving"})
	_expect(hud._save_exit_button.disabled, "pending save prevents duplicate save-exit requests")
	var storage_error := "Could not save. Storage may be full or blocked, or this save changed in another window. Keep the game open and retry; the previous save is kept."
	hud.set_save_status({"state":"failed", "error":storage_error})
	await _frames(6)
	_expect(not hud._save_exit_button.disabled and hud._save_status_label.text == storage_error, "failed save is visibly explained and remains retryable")
	_expect(hud._save_status_label.size.x <= 320.5 and hud._save_status_label.get_line_count() >= 2, "long failure wraps within 320px")
	_expect(hud._save_status_label.get_visible_line_count() == hud._save_status_label.get_line_count(), "every failure line is visible")
	var screen := get_viewport().get_visible_rect()
	_expect(screen.encloses(hud._pause_overlay.get_node("PauseFrame").get_global_rect()), "phone pause failure frame stays on screen")
	_expect(screen.encloses(hud._pause_overlay.get_node("PauseMenu/DepartureRow").get_global_rect()), "phone pause failure keeps last action on screen")
	await _capture("pause-save")
	hud._pause_overlay.free()
	hud._pause_overlay = null
	NetworkSession.online = true
	hud._create_pause_overlay()
	await _frames(4)
	var leave: Button = hud._pause_overlay.get_node_or_null("PauseMenu/DepartureRow/QuitButton")
	_expect(leave != null and leave.text == "Leave match", "online pause retains Leave match")
	_expect(hud._pause_overlay.get_node_or_null("PauseMenu/SaveAndExitButton") == null, "online pause does not offer solo save")
	await _capture("pause-online")
	NetworkSession.online = false
	get_tree().paused = false
	main.queue_free()
	await _frames(1)
	for failure: String in failures: push_error("[FAIL] compact_dock: " + failure)
	print(JSON.stringify({"test":"compact_dock", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_trade_placement_strip() -> void:
	hud.set_placement_input_mode(true)
	hud.set_placement_mode(true, "Trade Post")
	var hint := "Up to 60 gold / trip · clear road needed"
	hud.update_placement_preview(true, hint)
	await _frames(5)
	var label: Label = hud._placement_status_label
	var text_width: float = label.get_theme_font("font").get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	_expect(label.text == hint and text_width <= label.size.x, "complete trade estimate fits existing status strip without ellipsis")
	_expect(get_viewport().get_visible_rect().encloses(hud._placement_status_panel.get_global_rect()), "trade status strip stays inside viewport")
	await _capture("trade-preview")
	hud.update_placement_preview(true, "Move farther from town")
	_expect(not hud._placement_confirm_button.disabled and label.text == "Move farther from town", "near-town warning stays advisory and does not prohibit legal placement")
	hud.update_placement_preview(false, "Move all tiles into sight")
	_expect(hud._placement_confirm_button.disabled and label.text.contains("Move all tiles into sight"), "fog warning replaces estimate and blocks confirmation")
	hud.set_placement_mode(false)
	hud.set_placement_input_mode(false)
	await _frames(3)

func _touch(id: int, point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = get_viewport().get_final_transform() * point
	event.pressed = down
	Input.parse_input_event(event)
	await _frames(2)
func _tap(button: Button) -> void:
	Input.emulate_mouse_from_touch = true
	await _touch(42, button.get_global_rect().get_center(), true)
	await _touch(42, button.get_global_rect().get_center(), false)
	await _frames(4)
func _frames(count: int) -> void:
	for frame: int in count: await get_tree().process_frame
func _capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(output)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("%dx%d-%s.png" % [get_window().size.x, get_window().size.y, label]))
func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
