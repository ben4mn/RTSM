extends Node
## Native rendered inventory. Touch drives the real menu-to-match journey.
## Results are a staged presentation; no physical-device or paid-match claim.

var output: String = "res://output/menu-inventory"
var records: Array[Dictionary] = []
var failures: Array[String] = []
var contact: int = 0
var tag: String = ""

class InsetMenu:
	extends "res://scripts/ui/main_menu.gd"
	func _refresh_responsive_layout() -> void:
		if not is_node_ready():
			return
		var logical: Vector2 = get_viewport().get_visible_rect().size
		apply_mobile_layout(logical, Rect2(Vector2(44.0 / 1.15, 0), logical - Vector2(88.0 / 1.15, 18.0 / 1.15)), 60)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_window().gui_embed_subwindows = true
	Input.emulate_mouse_from_touch = true
	AudioManager.set_all_enabled(false)
	GameManager.audio_enabled = false
	GameManager.reduced_motion = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_difficulty = 0
	GameManager.selected_map_seed = 101
	for profile: Dictionary in [
		{"size": Vector2i(1280, 720), "scale": 1.0, "name": "desktop"},
		{"size": Vector2i(844, 390), "scale": 1.0, "name": "phone"},
		{"size": Vector2i(932, 430), "scale": 1.15, "name": "phone-large-ui"},
	]:
		await _profile(profile)
	await _edge_profile()
	var report := {"scope": "Windows native rendered viewport inventory with ScreenTouch navigation, embedded option popups and real menu-to-match transition. Result panels are staged UI presentations. No public-browser, physical-device, natural-win or performance claim.", "records": records, "failures": failures}
	FileAccess.open(output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MENU_INVENTORY views=%d failures=%s" % [records.size(), failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _profile(profile: Dictionary) -> void:
	tag = profile.name
	get_tree().paused = false
	NetworkSession.leave_match()
	get_window().size = profile.size
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = profile.scale
	GameManager.ui_scale = profile.scale
	GameManager.selected_population_limit = 100
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	var menu: Control = preload("res://scenes/ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames(10)
	await _capture("01-home", menu)
	await _tap(menu._new_game_button)
	_expect(menu._screen == "setup", "Solo opens setup")
	await _capture("02-setup", menu)
	await _tap(menu._civilization_button)
	var picker: Control = menu._civilization_picker
	_expect(is_instance_valid(picker), "kingdom picker opens")
	if is_instance_valid(picker):
		for id in 3:
			await _tap(picker._cards[id])
			await _capture("03-kingdom-%d" % id, picker)
		await _tap(picker._cards[0 if tag == "desktop" else (1 if tag == "phone" else 2)])
		await _tap(picker._confirm)
	await _tap(menu._rules_option)
	await _capture("04-rules-popup", menu, menu._rules_option.get_popup())
	menu._rules_option.get_popup().hide()
	await _tap(menu._advanced_button)
	await _capture("05-match-options", menu)
	var match_options_scroll := menu.find_child("MatchOptionsScroll", true, false) as ScrollContainer
	if match_options_scroll != null:
		match_options_scroll.ensure_control_visible(menu.guided_opening_toggle)
		await _capture("05-match-options-lower", menu)
	menu._toggle_advanced_options()
	await _frames(3)
	await _tap(menu.settings_button)
	var settings: Control = menu._shared_settings
	for section in 4:
		await _tap(settings._tabs[section])
		if section == 3:
			await _tap(settings._body.get_child(1).get_node("LearnButton"))
		await _capture("06-settings-%d" % section, settings)
		if section == 1:
			var choice := settings.find_child("CameraSpeedScaleOption", true, false) as OptionButton
			await _tap(choice)
			await _capture("07-preference-popup", settings, choice.get_popup())
			choice.get_popup().hide()
	await _tap(settings.find_child("SettingsDoneButton", true, false))
	await _tap(menu._back_button)
	await _tap(menu._online_button)
	await _capture("08-online", menu)
	menu._on_network_status_changed("error", "You're offline. Choose Solo to play the saved game; Online 1v1 needs a connection.")
	await _capture("08-online-error", menu)
	menu._on_network_status_changed("idle", "")
	await _tap(menu._back_button)
	await _tap(menu._new_game_button)
	await _tap(menu.start_button)
	for frame in 900:
		var scene: Node = get_tree().current_scene
		if scene != null and scene.scene_file_path == "res://scenes/main/main.tscn" and scene.get("_building_placement") != null:
			break
		await get_tree().process_frame
	var main: Node = get_tree().current_scene
	if main == null or main.scene_file_path != "res://scenes/main/main.tscn":
		failures.append(tag + " Begin did not reach Main")
		return
	await _frames(10)
	var hud: Node = main.hud
	var strategy: Control = hud._strategy_overview
	await _tap(strategy._economy_button)
	await _capture("09-economy", strategy.panel)
	await _tap(strategy._info_button)
	await _capture("09-economy-info", strategy.panel)
	await _tap(strategy._info_button)
	await _tap(strategy._production_tab)
	await _capture("10-production", strategy.panel)
	await _tap(strategy._army_button)
	await _capture("11-army-recruit", strategy.panel)
	await _tap(strategy._groups_tab)
	await _capture("12-army-groups", strategy.panel)
	await _tap(strategy._info_button)
	await _capture("12-army-notes", strategy.panel)
	hud.close_secondary_surface()
	await _tap(hud.build_menu_button)
	await _capture("13-build", hud.get_node("BuildMenu"))
	var build_menu: Control = hud.get_node("BuildMenu")
	for category: String in ["Army", "Defence"]:
		await _tap(build_menu._category_buttons[category])
		await _capture("13-build-" + category.to_lower(), build_menu)
	await _tap(build_menu._category_buttons["Economy"])
	await _tap(build_menu._info_button)
	await _tap(build_menu._button_map[BuildingData.BuildingType.HOUSE])
	await _capture("13-build-info", hud._info_panel)
	hud.close_secondary_surface()
	hud.get_node("BuildMenu").close_requested.emit()
	await _frames(3)
	await _tap(hud._pause_button)
	await _capture("14-pause", hud._pause_overlay)
	await _tap(hud._pause_overlay.get_node("PauseMenu/UtilityRow/ReportProblemButton"))
	var report_dialog := hud.get_node_or_null("PlaytestReportDialog") as AcceptDialog
	if report_dialog != null:
		await _capture("14-report-confirmation", main)
		_expect(report_dialog.get_ok_button().size.x >= 104 and report_dialog.get_ok_button().size.y >= 48, "report confirmation has a comfortable OK target")
		report_dialog.hide()
		report_dialog.confirmed.emit()
	await _tap(hud._pause_overlay.get_node("PauseMenu/UtilityRow/FieldGuideButton"))
	await _capture("15-field-guide", hud._hotkey_panel)
	hud.close_secondary_surface()
	await _tap(hud._match_learning_button)
	await _capture("16-battle-lessons", hud._pause_overlay)
	# Result presentation only; retain actual short-session counters, mark its reason.
	main._victory_reason = "Presentation fixture"
	main._show_game_over()
	await _frames(6)
	await _capture("17-results-defeat", main)
	var result: Node = main.get_node("GameOverScreen")
	var victory_stats: Dictionary = result.summary_diagnostics.duplicate(true)
	victory_stats["is_victory"] = true
	victory_stats["winner_id"] = 0
	result.show_victory(victory_stats)
	await _capture("18-results-victory", result)
	get_tree().paused = false
	get_tree().current_scene = null
	main.free()
	await _frames(4)

func _edge_profile() -> void:
	tag = "phone-inset-large-ui"
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.15
	GameManager.ui_scale = 1.15
	var menu := InsetMenu.new()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames(10)
	await _tap(menu._new_game_button)
	await _capture("02-setup", menu)
	await _tap(menu._advanced_button)
	await _capture("05-match-options", menu)
	menu._toggle_advanced_options()
	await _tap(menu.settings_button)
	var settings: Control = menu._shared_settings
	await _tap(settings._tabs[1])
	await _capture("06-settings-controls", settings)
	await _tap(settings.find_child("SettingsDoneButton", true, false))
	get_tree().current_scene = null
	menu.free()
	await _frames(3)

func _tap(control: Control) -> void:
	if not is_instance_valid(control):
		failures.append(tag + " missing touch target")
		return
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await _frames(3)
	contact += 1
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = contact
		event.position = get_viewport().get_final_transform() * control.get_global_rect().get_center()
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)
	await _frames(3)

func _capture(name_text: String, surface: Node, popup: PopupMenu = null) -> void:
	await _frames(6)
	var path: String = output.path_join(tag + "-" + name_text + ".png")
	var row: Dictionary = {"name": tag + "-" + name_text, "viewport": str(get_viewport().get_visible_rect()), "window_pixels": str(get_window().size), "path": path}
	if surface is Control:
		row["surface_rect"] = str((surface as Control).get_global_rect())
	if popup != null:
		row["popup_rect"] = str(Rect2(popup.position, popup.size))
		row["popup_visible"] = popup.visible
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
	records.append(row)

func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame

func _expect(ok: bool, label_text: String) -> void:
	if not ok:
		failures.append(tag + ": " + label_text)
