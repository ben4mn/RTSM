extends Node
## Full-match GUI input: Home, guidance and training must work through the
## viewport's hit testing, including the world selection/camera handlers.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_window().size = Vector2i(844, 390)
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.guided_opening_enabled = true
	var match_scene: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(match_scene)
	for frame in 900:
		if match_scene.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	var hud: CanvasLayer = match_scene.get_node("HUD") as CanvasLayer
	for frame in 8:
		await get_tree().process_frame
	var map: Node = match_scene.get_node("GameMap")
	var zoom_before: float = float(map.call("get_zoom_state")["zoom"])
	_expect(not (hud.get("_camera_zoom_in_button") as Button).is_visible_in_tree(), "phone zoom buttons start expanded")
	await _click((hud.get("_camera_view_button") as Button).get_global_rect().get_center())
	_expect((hud.get("_camera_zoom_in_button") as Button).is_visible_in_tree(), "View did not reveal zoom controls")
	await _click((hud.get("_camera_zoom_in_button") as Button).get_global_rect().get_center())
	_expect(float(map.call("get_zoom_state")["zoom"]) > zoom_before, "Zoom + pointer click did not zoom in")
	await _click((hud.get("_camera_zoom_out_button") as Button).get_global_rect().get_center())
	_expect(absf(float(map.call("get_zoom_state")["zoom"]) - zoom_before) < 0.001, "Zoom - does not reverse the + step")
	await _click((hud.get("_camera_zoom_in_button") as Button).get_global_rect().get_center())
	await _click((hud.get("_camera_zoom_reset_button") as Button).get_global_rect().get_center())
	_expect(absf(float(map.call("get_zoom_state")["zoom"]) - float(map.call("get_zoom_state")["default"])) < 0.001, "Reset pointer click does not restore default zoom")
	await _click((hud.get("_camera_view_button") as Button).get_global_rect().get_center())
	_expect(not (hud.get("_camera_zoom_in_button") as Button).is_visible_in_tree(), "View did not collapse zoom controls")
	var home_button: Button = hud.get("_town_center_button") as Button
	await _click(home_button.get_global_rect().get_center())
	var selected_building: Node2D = hud.get("_selected_building_ref") as Node2D
	_expect(selected_building != null, "Home pointer click did not select the Town Center")
	var guidance_label: Label = hud.get("_progression_hint_label") as Label
	_expect(guidance_label.visible and guidance_label.text != "", "opening guidance has no visible text")
	_expect(guidance_label.size.x >= 220.0 and guidance_label.size.y >= 34.0, "opening guidance text is clipped by its layout: %s" % guidance_label.size)
	_expect(guidance_label.get_theme_color("font_color").r > 0.8, "opening guidance is dark on navy")
	var train_row: HBoxContainer = hud.get("_train_buttons_container") as HBoxContainer
	var villager_button: Button = train_row.get_node("TrainButton_%d" % UnitData.UnitType.VILLAGER) as Button
	var scout_button: Button = train_row.get_node("TrainButton_%d" % UnitData.UnitType.SCOUT) as Button
	var scroll: ScrollContainer = hud.get("command_scroll") as ScrollContainer
	var repeat_button: Button = hud.get("_auto_queue_button") as Button
	_assert_initial_training_row(scroll, [villager_button, scout_button, repeat_button])
	await _capture("tc-initial-844x390")
	_expect(scout_button.text.contains("food") and scout_button.text.contains("gold"), "Scout training cost does not spell out both resources: %s" % scout_button.text)
	var before_food: int = int(ResourceManager.get_all_resources(0).get("food", 0))
	var position: Vector2 = villager_button.get_global_rect().get_center()
	await _hover(position)
	var hovered: Control = get_viewport().gui_get_hovered_control()
	_expect(hovered == villager_button, "train button hit resolves to %s instead of Villager at %s" % [hovered.get_path() if hovered != null else "nothing", position])
	await _click(position)
	var after_food: int = int(ResourceManager.get_all_resources(0).get("food", 0))
	_expect(after_food <= before_food - int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).get("food", 0)), "Villager pointer click did not spend food")
	_expect(String(match_scene.get("_last_train_request_result")) == "queued", "Villager pointer click did not queue a unit: %s" % String(match_scene.get("_last_train_request_result")))
	# Queue updates can insert controls; deliberately use the current card
	# location after the live refresh, then ensure the visible Scout can train.
	await get_tree().process_frame
	await get_tree().process_frame
	before_food = int(ResourceManager.get_all_resources(0).get("food", 0))
	await _click(scout_button.get_global_rect().get_center())
	after_food = int(ResourceManager.get_all_resources(0).get("food", 0))
	_expect(after_food <= before_food - int(UnitData.get_unit_cost(UnitData.UnitType.SCOUT).get("food", 0)), "Scout pointer click did not spend food")
	# Both recruiting cards and the named repeat state must remain completely
	# visible at the initial scroll position, including after queue refreshes.
	var queue: Node = selected_building.call("get_production_queue")
	_expect(repeat_button.text == "Scout\nRepeat · OFF", "repeat button does not name the most recently queued Scout: %s" % repeat_button.text)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_initial_training_row(scroll, [villager_button, scout_button, repeat_button])
	await _capture("tc-repeat-off-844x390")
	_expect(repeat_button.size.x >= 48.0 and repeat_button.size.y >= 48.0, "repeat toggle is under48px")
	await _click(repeat_button.get_global_rect().get_center())
	_expect(bool(queue.get("auto_queue_enabled")) and repeat_button.button_pressed, "repeat pointer click did not turn repetition ON")
	_expect(repeat_button.text == "Scout\nRepeat · ON", "repeat active state is not visible")
	var active_style: StyleBoxFlat = repeat_button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(active_style.bg_color.is_equal_approx(KingdomTheme.AMBER), "repeat active state is not amber")
	_assert_initial_training_row(scroll, [villager_button, scout_button, repeat_button])
	await _capture("tc-repeat-on-844x390")
	await get_tree().process_frame
	await _click(villager_button.get_global_rect().get_center())
	_expect(repeat_button.text == "Villager\nRepeat · ON", "repeat unit name did not change after queuing a Villager")
	await get_tree().process_frame
	await _click(repeat_button.get_global_rect().get_center())
	_expect(not bool(queue.get("auto_queue_enabled")) and repeat_button.text == "Villager\nRepeat · OFF", "repeat pointer click did not turn repetition OFF")
	Engine.time_scale = 1.0
	match_scene.free()
	if _failures.is_empty():
		print("[PASS] match_hud_pointer_input: Zoom +/−/Reset, Home, readable guidance, training and visible repeat toggle work through full-match GUI hit testing")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] match_hud_pointer_input: %s" % failure)
	get_tree().quit(1)


func _hover(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	await get_tree().process_frame


func _assert_initial_training_row(scroll: ScrollContainer, buttons: Array[Button]) -> void:
	_expect(scroll.scroll_horizontal == 0, "Town Center training row moved away from initial scroll0")
	for button: Button in buttons:
		_expect(scroll.get_global_rect().encloses(button.get_global_rect()), "%s is clipped at scroll0: button %s, shelf %s" % [button.name, button.get_global_rect(), scroll.get_global_rect()])


func _capture(name: String) -> void:
	var directory: String = OS.get_environment("AOEM_CAPTURE_HUD_DIR")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png"))
	_expect(result == OK, "could not save rendered HUD screenshot %s" % name)


func _click(position: Vector2) -> void:
	await _hover(position)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = position
	press.global_position = position
	press.pressed = true
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = position
	release.global_position = position
	release.pressed = false
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
