extends Node
## Native renders of every out-of-match menu surface at phone and desktop sizes,
## for side-by-side review of the shared KingdomTheme family. Presentation only:
## lobby and result states are staged; no network or match claim.
## Usage: Godot --path . res://tools/capture_menu_family.tscn -- --output=/abs/dir

var output: String = "res://output/menu-family"
var failures: Array[String] = []
var tag: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	AudioManager.set_all_enabled(false)
	GameManager.audio_enabled = false
	GameManager.reduced_motion = true
	GameManager.selected_map_seed = 101
	for profile: Dictionary in [
		{"size": Vector2i(844, 390), "name": "844x390"},
		{"size": Vector2i(667, 375), "name": "667x375"},
		{"size": Vector2i(1280, 720), "name": "1280x720"},
	]:
		await _profile(profile)
	for failure: String in failures:
		push_error("[FAIL] menu_family: " + failure)
	print("MENU_FAMILY failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func _profile(profile: Dictionary) -> void:
	tag = profile.name
	get_window().size = profile.size
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	GameManager.ui_scale = 1.0
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(10)
	await _capture("01-home")
	menu.call("_open_new_game", "solo")
	await _capture("02-solo-setup")
	menu.call("_set_map_picker_expanded", true)
	await _capture("03-map-picker")
	menu.call("_set_map_picker_expanded", false)
	menu.call("_toggle_advanced_options")
	await _capture("04-match-options")
	menu.call("_toggle_advanced_options")
	await _frames(3)
	menu.call("_open_civilization_picker")
	await _capture("05-kingdom-picker")
	var picker: Control = menu.get("_civilization_picker")
	if is_instance_valid(picker):
		picker.call("close")
	await _frames(3)
	menu.call("_on_settings_pressed")
	var settings: Control = menu.get("_shared_settings")
	if is_instance_valid(settings):
		for section: int in 4:
			settings.call("_show_section", section)
			await _capture("06-settings-%d" % section)
		settings.call("close")
	else:
		failures.append(tag + " settings did not open")
	await _frames(3)
	menu.call("_show_screen", "home")
	await _frames(2)
	menu.call("_open_new_game", "multiplayer")
	await _capture("07-online")
	var session: Node = get_node_or_null("/root/NetworkSession")
	if session != null:
		session.set("state", "lobby")
		session.set("room_code", "ATLAS7")
		session.set("room_players", 2)
		session.set("room_host", true)
		menu.call("_on_room_changed")
		await _capture("08-lobby-room")
		session.set("state", "idle")
		session.set("room_code", "")
		session.set("room_players", 0)
		menu.call("_on_room_changed")
	menu.queue_free()
	await _frames(3)
	await _results()
	await _age_moments()


func _results() -> void:
	var result: CanvasLayer = load("res://scenes/ui/game_over_screen.tscn").instantiate()
	add_child(result)
	await _frames(3)
	var stats := {"game_time": "18:42", "player_age": 2, "ai_age": 2, "player_feudal_seconds": 402.0, "ai_feudal_seconds": 455.0,
		"victory_reason": "Rival Town Center razed", "score": 1840, "ai_score": 1215, "army_trained": 24, "ai_army_trained": 19,
		"units_lost": 9, "ai_units_lost": 21, "buildings_lost": 1, "ai_buildings_lost": 6, "resources_gathered": 5210, "ai_resources_gathered": 4380,
		"sacred_control_seconds": 60, "ai_sacred_control_seconds": 0, "is_victory": true, "winner_id": 0}
	result.call("show_victory", stats)
	await _capture("09-results-victory")
	result.call("show_defeat", stats)
	await _capture("10-results-defeat")
	get_tree().paused = false
	result.queue_free()
	await _frames(2)


func _age_moments() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var backdrop := ColorRect.new()
	backdrop.color = Color("6f8a5a")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(backdrop)
	var dialog: Control = load("res://scenes/ui/age_up_dialog.tscn").instantiate()
	host.add_child(dialog)
	await _frames(2)
	dialog.call("show_dialog", 2)
	await _capture("11-age-up-dialog")
	dialog.hide()
	preload("res://scripts/ui/age_ceremony.gd").play(host, 2)
	await _frames(30)
	await _capture("12-age-ceremony")
	host.queue_free()
	await _frames(2)


func _capture(name_text: String) -> void:
	await _frames(6)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(tag + "-" + name_text + ".png"))


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame
