extends Node
## Native rendered UI review. Local synthetic room states are presentation-only.

const OUTPUT := "res://output/new-game-design-2026-10-23"
var _records: Array[Dictionary] = []
var _failures: Array[String] = []
var _contact_id: int = 0
var _notched: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.audio_enabled = false
	GameManager.reduced_motion = true
	Input.emulate_mouse_from_touch = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for profile: Dictionary in [
		{"size": Vector2i(1280, 720), "scale": 1.0, "tag": "desktop"},
		{"size": Vector2i(844, 390), "scale": 1.0, "tag": "phone"},
		{"size": Vector2i(844, 390), "scale": 1.15, "tag": "phone-max"},
		{"size": Vector2i(844, 390), "scale": 1.15, "tag": "phone-max-notched", "notched": true},
	]:
		await _profile(profile)
	var file := FileAccess.open(OUTPUT.path_join("receipt.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "Native macOS window renders at desktop and phone-sized resolutions. ScreenTouch selects New Game, maps, tabs and Settings. Lobby states are modeled UI presentations, not actual network coverage. No physical-device test.", "records": _records, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] new_game_capture: " + failure)
	print("[PASS] new_game_capture: %d native views, failures=%d" % [_records.size(), _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile(profile: Dictionary) -> void:
	_notched = bool(profile.get("notched", false))
	get_window().size = profile.size
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = profile.scale
	GameManager.ui_scale = profile.scale
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(10)
	_apply_safe(menu)
	await _frames(3)
	await _capture(menu, profile.tag + "-01-home")
	await _tap(menu.get("_new_game_button"))
	_expect(menu.get("_screen") == "setup", "New Game touch opens setup " + profile.tag)
	for archetype: int in MapData.MAP_ARCHETYPES:
		await _tap((menu.get("_map_buttons") as Array)[archetype])
		_expect(GameManager.selected_map_archetype == archetype, "map touch selects %d %s" % [archetype, profile.tag])
		await _capture(menu, profile.tag + "-02-solo-map%d" % archetype)
	await _tap(menu.get("_online_tab"))
	_expect(menu.get("_mode") == "multiplayer", "Multiplayer touch selects mode " + profile.tag)
	await _capture(menu, profile.tag + "-03-online")
	var session: Node = get_node("/root/NetworkSession")
	session.set("state", "lobby")
	session.set("room_code", "ATLAS7")
	session.set("room_players", 2)
	session.set("room_host", true)
	session.set("match_map_archetype", 1)
	menu.call("_on_room_changed")
	await _capture(menu, profile.tag + "-04-host-lobby")
	session.set("room_host", false)
	menu.call("_on_room_changed")
	await _capture(menu, profile.tag + "-05-guest-lobby")
	session.set("state", "idle")
	session.set("room_code", "")
	session.set("room_players", 0)
	session.set("room_host", false)
	menu.call("_on_network_status_changed", "idle", "")
	await _tap(menu.get("settings_button"))
	var settings: Control = menu.get("_shared_settings")
	_expect(settings != null, "Settings touch opens preferences " + profile.tag)
	if settings != null:
		for section: int in 3:
			await _tap((settings.get("_tabs") as Array)[section])
			_expect(int(settings.get("_section")) == section, "Settings tab touch " + profile.tag)
			await _capture(menu, profile.tag + "-06-settings%d" % section)
	menu.free()
	await _frames(3)


func _capture(menu: Control, name_text: String) -> void:
	await _frames(3)
	_apply_safe(menu)
	await _frames(6)
	menu.call("_refresh_main_menu_diagnostics")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(name_text + ".png"))
	_records.append({"name": name_text, "diagnostics": menu.get("main_menu_diagnostics")})


func _tap(control: Control) -> void:
	_contact_id += 1
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = _contact_id
		event.position = get_viewport().get_final_transform() * control.get_global_rect().get_center()
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)
	await _frames(3)


func _frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _apply_safe(menu: Control) -> void:
	if not _notched:
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var transform: Transform2D = get_viewport().get_final_transform()
	var factor := Vector2(transform.x.length(), transform.y.length())
	var safe := Rect2(Vector2(44.0 / factor.x, 0), logical - Vector2(88.0 / factor.x, 18.0 / factor.y))
	menu.call("apply_mobile_layout", logical, safe)
