extends "res://tools/probe_polish_skirmishes.gd"
## Bounded real-menu navigation diagnostic using the exact observer click helper.

func _run() -> void:
	output_directory = "res://output/polish-2026-10-22/navigation-click"
	var pixels := Vector2i(932, 430)
	var ui_scale: float = 1.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_directory = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--width="): pixels.x = int(argument.trim_prefix("--width="))
		elif argument.begins_with("--height="): pixels.y = int(argument.trim_prefix("--height="))
		elif argument.begins_with("--ui-scale="): ui_scale = float(argument.trim_prefix("--ui-scale="))
	_native = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(output_directory)
	_had_preferences = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_preferences: _preferences_before = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	GameManager.audio_enabled = false
	GameManager.guided_opening_enabled = false
	GameManager.ui_scale = ui_scale
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.WOODLAND_FLANKS
	AudioManager.set_all_enabled(false)
	get_window().size = pixels
	GameManager.apply_preferences()
	if _native: get_window().grab_focus()
	get_tree().current_scene = null
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _settle(6)
	current = {"name": "navigation-click", "screenshots": [], "failures": []}
	phase = "home"
	await _click(menu.get("_new_game_button"))
	await _settle(3)
	var button: Button = menu.get("start_button")
	var events: Dictionary = {"pressed_signals": 0, "gui_events": []}
	button.pressed.connect(func() -> void: events.pressed_signals += 1)
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouse:
			events.gui_events.append({"type": event.get_class(), "position": _xy(event.position), "pressed": event.pressed if event is InputEventMouseButton else false})
	)
	phase = "menu"
	await _capture("before")
	report["before"] = {"window": _xy(get_window().size), "viewport": _xy(get_viewport().get_visible_rect().size), "content_scale_factor": get_window().content_scale_factor, "final_transform": str(get_viewport().get_final_transform()), "button_rect": str(button.get_global_rect()), "button_viewport_center": _xy(button.get_global_transform_with_canvas() * (button.size * 0.5)), "hovered": button.is_hovered()}
	if "--interrupted-legacy" in OS.get_cmdline_user_args():
		await _interrupted_legacy_click(button)
	else:
		await _click(button)
	var ready: bool = false
	for frame: int in 300:
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/main/main.tscn" and get_tree().current_scene.get("_building_placement") != null:
			ready = true
			break
		await get_tree().process_frame
	report["actual_main_ready"] = ready
	report["events"] = events
	report["source_sha256"] = {"observer": FileAccess.get_sha256("res://tools/probe_polish_skirmishes.gd"), "fixture": FileAccess.get_sha256("res://tools/test_polish_navigation_click.gd")}
	phase = "ready" if ready else "menu-not-activated"
	await _capture("after")
	if not ready: _fail("Real Play solo did not enter actual Main")
	_finish()


func _interrupted_legacy_click(button: Button) -> void:
	# Model an unrelated native move arriving during the old one-frame hold.
	# This is a lifecycle regression, not proof of the original OS event order.
	var point: Vector2 = button.get_global_rect().get_center()
	var hover := InputEventMouseMotion.new()
	hover.position = point
	hover.global_position = point
	get_viewport().push_input(hover, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame
		if pressed:
			var outside := InputEventMouseMotion.new()
			outside.position = Vector2.ONE
			outside.global_position = outside.position
			outside.button_mask = MOUSE_BUTTON_MASK_LEFT
			get_viewport().push_input(outside, true)
