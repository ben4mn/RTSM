extends SceneTree
## Menu/controller coverage only; actual browser worker activation has separate tests.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const PREFERENCES_PATH := "user://preferences.cfg"

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var had_preferences: bool = FileAccess.file_exists(PREFERENCES_PATH)
	var preferences_before: PackedByteArray = FileAccess.get_file_as_bytes(PREFERENCES_PATH) if had_preferences else PackedByteArray()
	var session: Node = root.get_node("NetworkSession")
	var game_manager: Node = root.get_node("GameManager")
	game_manager.set("audio_enabled", false)
	root.get_node("AudioManager").call("set_all_enabled", false)
	# No sockets or maps are created. Exercise the real menu and Settings signals
	# with the same state values NetworkSession publishes before status_changed.
	for initial_state: String in ["idle", "lobby", "loading"]:
		session.set("state", initial_state)
		var menu: Control = load(MENU_SCENE).instantiate()
		root.add_child(menu)
		await process_frame
		_expect(menu.get("_web_update_safe") == (initial_state == "idle"), "ready respects " + initial_state)
		for state: String in ["idle", "error", "connecting", "hosting", "joining", "searching", "lobby", "loading", "playing", "ended"]:
			_set_status(session, state)
			_expect(menu.get("_web_update_safe") == (state in ["idle", "error"]), initial_state + ": status " + state)
		_set_status(session, "lobby", "Waiting for an arena…")
		_expect(not bool(menu.get("_web_update_safe")), initial_state + ": queued room stays protected")
		menu.call("_on_settings_pressed")
		var settings: Control = menu.get("_shared_settings")
		_expect(not bool(menu.get("_web_update_safe")), initial_state + ": Settings protects room")
		_set_status(session, "idle")
		_expect(not bool(menu.get("_web_update_safe")), initial_state + ": idle notification cannot override Settings")
		_set_status(session, "lobby")
		settings.call("close")
		_expect(menu.get("_shared_settings") == null, initial_state + ": Settings close releases menu reference")
		_expect(not bool(menu.get("_web_update_safe")), initial_state + ": Settings close keeps room protected")
		await process_frame
		_set_status(session, "idle")
		_expect(bool(menu.get("_web_update_safe")), initial_state + ": idle home permits updates")
		menu.call("_on_settings_pressed")
		settings = menu.get("_shared_settings")
		_expect(not bool(menu.get("_web_update_safe")), initial_state + ": idle Settings blocks updates")
		settings.call("close")
		_expect(bool(menu.get("_web_update_safe")), initial_state + ": closing idle Settings restores updates")
		await process_frame
		menu.call("_open_new_game")
		menu.call("_toggle_advanced_options")
		_expect(not bool(menu.get("_web_update_safe")), initial_state + ": match options block reload")
		for backward: bool in [false, true]:
			for step: int in 12:
				for pressed: bool in [true, false]:
					var tab := InputEventKey.new()
					tab.keycode = KEY_TAB
					tab.shift_pressed = backward
					tab.pressed = pressed
					root.push_input(tab)
					await process_frame
				var focused: Control = root.gui_get_focus_owner()
				_expect(focused != null and (menu.get("_advanced_overlay") as Control).is_ancestor_of(focused), initial_state + ": keyboard traversal remains inside options")
		menu.call("_on_settings_pressed")
		menu.call("_open_civilization_picker")
		menu.call("_set_mode", "multiplayer")
		menu.call("_on_start_pressed")
		_expect(menu.get("_shared_settings") == null and menu.get("_civilization_picker") == null, initial_state + ": options cannot stack modal surfaces")
		_expect(menu.get("_mode") == "solo" and is_instance_valid(menu), initial_state + ": covered launch and mode controls stay blocked")
		_set_status(session, "idle")
		_expect(not bool(menu.get("_web_update_safe")), initial_state + ": idle status cannot override options")
		menu.call("_on_back_pressed")
		_expect(menu.get("_screen") == "setup" and not (menu.get("_advanced_overlay") as Control).visible, initial_state + ": Back closes options without discarding setup")
		_expect(bool(menu.get("_web_update_safe")), initial_state + ": closing options restores idle safety")
		_expect(root.gui_get_focus_owner() == menu.get("_advanced_button"), initial_state + ": options restore launch-page focus")
		menu.free()
		await process_frame

	session.set("state", "idle")
	session.set("status_text", "")
	if had_preferences:
		var preferences := FileAccess.open(PREFERENCES_PATH, FileAccess.WRITE)
		if preferences != null:
			preferences.store_buffer(preferences_before)
			preferences.close()
		else:
			_failures.append("could not restore test-owned preferences")
	elif FileAccess.file_exists(PREFERENCES_PATH):
		_expect(DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES_PATH)) == OK, "remove test-owned preferences")
	if _failures.is_empty():
		print("[PASS] menu_update_safety: %d checks; initial state, live/pending lobbies, transport transitions and Settings close" % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] menu_update_safety: " + failure)
		quit(1)


func _set_status(session: Node, state: String, message: String = "") -> void:
	session.set("state", state)
	session.set("status_text", message)
	session.emit_signal("status_changed", state, message)


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
