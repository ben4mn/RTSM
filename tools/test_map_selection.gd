extends Node
## Real touch menu -> map choice -> paid skirmish, without test-side layout calls.

var _failures: Array[String] = []
var _original: Dictionary = {}
var _capture_dir: String = ""
var _contact_id: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().current_scene = null # Keep this observer across real menu transitions.
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for key: String in ["selected_map_seed", "selected_map_archetype", "ui_scale", "guided_opening_enabled"]:
		_original[key] = GameManager.get(key)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):
			_capture_dir = argument.trim_prefix("--captures=")
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale: float in [1.0, 1.15]:
			for launch_archetype: int in MapData.MAP_ARCHETYPES:
				await _exercise(phone, scale, launch_archetype)
	for key: String in _original:
		GameManager.set(key, _original[key])
	GameManager.save_preferences()
	GameManager.set_state(GameManager.GameState.MENU)
	for failure: String in _failures:
		push_error("[FAIL] map_selection: " + failure)
	if _failures.is_empty():
		print("[PASS] map_selection: all three map choices, real ScreenTouch, saved preferences and actual New Game-to-match terrain at two phone sizes/scales; map cards need no scrolling or manual layout")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _exercise(phone: Vector2i, scale: float, launch_archetype: int) -> void:
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	GameManager.ui_scale = scale
	get_window().content_scale_factor = scale
	GameManager.selected_map_seed = 101
	GameManager.guided_opening_enabled = false
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames(4)
	await _tap(menu.get("_new_game_button"))
	if not is_instance_valid(menu) or str(menu.get("_screen")) != "setup":
		_failures.append("touch New Game did not open setup")
		return
	for archetype: int in MapData.MAP_ARCHETYPES:
		var choice: Button = (menu.get("_map_buttons") as Array)[archetype]
		await _tap(choice)
		_expect(GameManager.selected_map_archetype == archetype and choice.button_pressed, "touch map choice applied " + choice.name)
		var tactics: Label = menu.get("map_summary_label")
		_expect(tactics.text == MapData.get_archetype_description(archetype), "tactical description follows choice")
		_expect(get_viewport().get_visible_rect().grow(1).encloses(choice.get_global_rect()), "map choice visible without scrolling at %s scale%s" % [phone, scale])
		_expect(choice.size.y >= 48.0, "map touch target at least48")
		if launch_archetype == 0 and not _capture_dir.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_capture_dir.path_join("map-%d-%dx%d-%s.png" % [archetype, phone.x, phone.y, scale]))
	# The real Start action persists the draft and uses that same map and seed.
	await _tap((menu.get("_map_buttons") as Array)[launch_archetype])
	await _tap(menu.get("start_button"))
	var main: Node = null
	for frame: int in range(900):
		main = get_tree().current_scene
		if is_instance_valid(main) and main.scene_file_path == "res://scenes/main/main.tscn" and main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_expect(is_instance_valid(main) and main.scene_file_path == "res://scenes/main/main.tscn", "touch Play loads match")
	if is_instance_valid(main) and main.has_node("GameMap"):
		var game_map: Node2D = main.get_node("GameMap")
		var config := ConfigFile.new()
		config.load(GameManager.PREFERENCES_PATH)
		_expect(int(config.get_value("skirmish", "map_archetype", -1)) == launch_archetype, "Start saves chosen map")
		_expect(game_map.map_archetype == launch_archetype, "selected archetype reaches actual match")
		var expected := MapGenerator.new(101, launch_archetype)
		_expect(game_map.map_generator.grid == expected.generate(), "actual terrain reproduces selected archetype and seed")
		_expect(GameManager.players[0]["population"] == 5, "map selection starts four workers and one Scout")
		main.free()
	get_tree().current_scene = null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(3)


func _tap(control: Control) -> void:
	if not is_instance_valid(control):
		_failures.append("missing touch control")
		return
	var center: Vector2 = control.get_global_rect().get_center()
	_contact_id += 1
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = _contact_id
		event.position = get_viewport().get_final_transform() * center
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)
	await _frames(3)


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
