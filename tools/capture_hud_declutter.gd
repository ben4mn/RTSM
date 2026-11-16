extends Node
## Native 844x390 evidence for the HUD declutter pass: the opening crowd of
## advisories, the Town Center bar (fresh and re-selected), the field rail and
## the pause card. Run without --headless:
##   Godot --path . res://tools/capture_hud_declutter.tscn -- --output=/abs/dir --tag=before
## Layout evidence only: the match is the real main scene, frozen after the
## advisories are raised through their production entry points.

const PHONE := Vector2i(844, 390)
var _output: String = "/tmp/claude-501/aoem/hud"
var _tag: String = "after"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(_output)
	get_window().size = PHONE
	get_window().content_scale_size = PHONE
	get_window().content_scale_factor = 1.0
	await get_tree().process_frame
	GameManager.guided_opening_enabled = true
	GameManager.selected_map_seed = 101
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	# An unfocused capture window must not count as a backgrounded app.
	var guard: Node = main.get("_match_background_guard")
	guard.set_block_signals(true)
	for frame: int in 900:
		guard.set("backgrounded", false)
		if main.get("_building_placement") != null and GameManager.current_state != GameManager.GameState.MENU:
			break
		await get_tree().process_frame
	guard.set("backgrounded", false)
	if GameManager.current_state == GameManager.GameState.PAUSED:
		GameManager.set_state(GameManager.GameState.PLAYING)
	for frame: int in 30:
		guard.set("backgrounded", false)
		await get_tree().process_frame
	var map: Node2D = main.get_node("GameMap")
	var hud: CanvasLayer = main.get_node("HUD")
	var tc: BuildingBase = main.get("_player_buildings")[0][0]
	var selection: Node = map.get("selection_mgr")
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var safe := Rect2(Vector2.ZERO, logical)
	# The opening crowd, raised the way the match raises it.
	main.call("_update_timed_hints", 15.0)
	hud.call("show_notification", "Town Center idle · tap: +2 Villagers", KingdomTheme.GOLD, 8.0, func() -> void: pass, 2, func() -> bool: return true)
	await _shot(main, hud, safe, "1_opening_unselected")
	selection.call("select_single", tc)
	await _shot(main, hud, safe, "2_tc_selected")
	if hud.has_method("set_dock_collapsed"):
		hud.call("set_dock_collapsed", true)
	selection.call("deselect_all")
	await get_tree().process_frame
	selection.call("select_single", tc)
	await _shot(main, hud, safe, "3_tc_reselected")
	selection.call("deselect_all")
	hud.call("set_progression_hint", "")
	hud.call("set_early_game_ui_state", false)
	(hud.get("_notification_container") as Node).call("clear")
	hud.call("update_idle_villager_count", 2)
	hud.call("update_military_count", 6)
	# With the guide gone, the one contextual offer takes the channel.
	hud.call("show_notification", "Town Center idle · tap: +2 Villagers", KingdomTheme.GOLD, 8.0, func() -> void: pass, 2, func() -> bool: return true)
	await _shot(main, hud, safe, "4_field_rail")
	GameManager.set_state(GameManager.GameState.PAUSED)
	await get_tree().create_timer(0.4, true, false, true).timeout
	await _shot(main, hud, safe, "5_pause")
	var overlay: Node = hud.get("_pause_overlay")
	var settings: Node = overlay.find_child("SettingsButton", true, false) if overlay else null
	if settings is Button:
		(settings as Button).pressed.emit()
		await get_tree().create_timer(0.4, true, false, true).timeout
		await _shot(main, hud, safe, "6_pause_settings")
	print("[PASS] hud_declutter capture: ", _output)
	get_tree().quit()


func _shot(main: Node, hud: CanvasLayer, safe: Rect2, name: String) -> void:
	for frame: int in 4:
		hud.call("apply_mobile_layout", safe.size, safe)
		await get_tree().process_frame
	main.call("_update_minimap")
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/%s-%s.png" % [_output, _tag, name])
	print("Captured ", name)
