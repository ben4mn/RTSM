extends Node
## Native rendered visual fixture, not balance/playthrough evidence. Capture the
## real Main HUD, fogged objective and two owned attack locations at phone sizes.

var _failures: Array[String] = []
var _profiles: Array[Dictionary] = []
var _output_dir := "res://output/evolution/mobile-rts-pass-20261012-input/battlefield"
var _fixture_hud: CanvasLayer
var _fixture_safe: Rect2


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var requested_output: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not requested_output.is_empty():
		_output_dir = requested_output
	DirAccess.make_dir_recursive_absolute(_output_dir)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale_factor: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _scenario(phone, scale_factor, notched)
	var file := FileAccess.open(_output_dir.path_join("profiles.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "Native rendering and settled bounds in synthetic real-Main fixture. Fog unchanged; two public owned-hit locations; not a paid match or physical phone.", "profiles": _profiles, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] battlefield_feedback_phone: " + failure)
	if _failures.is_empty():
		print("[PASS] battlefield_feedback_phone: 12 native phone profiles, fogged objective, two raid cards survive ordinary toast and remain outside Economy/Army, safe 48px targets")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _scenario(phone: Vector2i, scale_factor: float, notched: bool) -> void:
	var profile := "%dx%d-scale%.3f-%s" % [phone.x, phone.y, scale_factor, "notch" if notched else "ordinary"]
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = scale_factor
	GameManager.ui_scale = scale_factor
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	GameManager.set_state(GameManager.GameState.MENU)
	var main: Node2D = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	var map: Node2D = main.get("game_map")
	var hud: CanvasLayer = main.get("hud")
	var selection: SelectionManager = map.get("selection_mgr")
	var camera: Camera2D = map.get("camera")
	var feedback: Control = main.get("_battlefield_feedback")
	var site: Node2D = map.get("sacred_site")
	main.get("ai_controller").set_process(false)
	main.get("ai_controller").get("_decision_timer").stop()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var worker: Villager = main.get("_player_units")[0][0]
	selection.select_single(worker)
	main.call("_show_under_attack_alert", "Town Center", worker.global_position)
	main.call("_show_under_attack_alert", "Villager", worker.global_position + Vector2(800, 0))
	hud.call("show_notification", "Warrior trained · Reinforcements ready")
	map.call("note_camera_interaction")
	camera.position = site.global_position
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _settle()
	var view: Vector2 = get_viewport().get_visible_rect().size
	var safe := Rect2(Vector2.ZERO, view)
	if notched:
		safe = Rect2(Vector2(44.0 / scale_factor, 0), view - Vector2(88.0 / scale_factor, 18.0 / scale_factor))
	_fixture_hud = hud
	_fixture_safe = safe
	hud.call("apply_mobile_layout", view, safe)
	await _settle()
	var bounds: Array[Rect2] = feedback.call("get_visible_bounds")
	_expect(bounds.size() == 2, profile + " lost an attack front")
	_expect(not (hud.get("_notification_container") as Control).is_visible_in_tree(), profile + " ordinary toast replaced raid priority")
	_expect(not bool(map.call("is_tile_visible_to_player", site.get("tile_position"), 0)), profile + " site fixture is not fogged")
	var siblings: Array[Dictionary] = []
	for property: String in ["_progression_hint_panel", "_sacred_site_panel", "_camera_controls", "_command_dock", "_navigation_controls"]:
		var control: Control = hud.get(property) as Control
		if is_instance_valid(control) and control.is_visible_in_tree():
			siblings.append({"name": property, "rect": control.get_global_rect()})
	var overview: Node = hud.get("_strategy_overview")
	if overview != null:
		for rectangle: Rect2 in overview.call("get_visible_bounds"):
			siblings.append({"name": "strategy", "rect": rectangle})
	for rectangle: Rect2 in bounds:
		_expect(rectangle.size.y >= 48 and rectangle.size.x >= 48, profile + " undersized raid control " + str(rectangle))
		_expect(safe.encloses(rectangle), profile + " raid control outside safe area " + str(rectangle))
		for sibling: Dictionary in siblings:
			_expect(not rectangle.intersects(sibling["rect"]), profile + " raid overlaps " + sibling["name"] + " " + str(sibling["rect"]))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var result: Error = get_viewport().get_texture().get_image().save_png(_output_dir.path_join(profile + ".png"))
		_expect(result == OK, profile + " capture failed")
	_profiles.append({"profile": profile, "logical_viewport": str(view), "safe_rect": str(safe), "raid_bounds": str(bounds), "hud_bounds": str(siblings), "site_fogged": not bool(map.call("is_tile_visible_to_player", site.get("tile_position"), 0))})
	for surface: String in ["economy", "army"]:
		hud.call("_set_secondary_surface", hud.SecondarySurface.ECONOMY if surface == "economy" else hud.SecondarySurface.ARMY)
		hud.call("apply_mobile_layout", view, safe)
		await _settle()
		# Queued layout may use native display bounds; restore this fixture's
		# explicit cutout rectangle once its real container sizes have settled.
		hud.call("apply_mobile_layout", view, safe)
		await _settle()
		var management_bounds: Array[Rect2] = feedback.call("get_visible_bounds")
		_expect(management_bounds.size() == 2, profile + " " + surface + " lost an attack front")
		var panel: Control = overview.get("panel")
		var rail: Control = overview.get("rail")
		for rectangle: Rect2 in management_bounds:
			_expect(safe.encloses(rectangle), profile + " " + surface + " raid outside safe bounds")
			_expect(rectangle.size.x >= 48.0 and rectangle.size.y >= 48.0, profile + " " + surface + " small raid target")
			_expect(not rectangle.intersects(panel.get_global_rect()) and not rectangle.intersects(rail.get_global_rect()), profile + " " + surface + " hides a raid target")
		for button: Button in feedback.get("_buttons"):
			var font: Font = button.get_theme_font("font")
			var text_size: Vector2 = font.get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size"))
			var padding: Vector2 = button.get_theme_stylebox("normal").get_minimum_size()
			_expect(text_size.x + padding.x <= button.size.x + 0.5 and text_size.y + padding.y <= button.size.y + 0.5, profile + " " + surface + " clips raid text")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_output_dir.path_join(profile + "-" + surface + ".png"))
		_profiles.append({"profile": profile, "surface": surface, "raid_bounds": str(management_bounds), "panel": str(panel.get_global_rect()), "rail": str(rail.get_global_rect())})
	main.free()
	_fixture_hud = null
	await _settle()


func _settle() -> void:
	for frame: int in 5:
		await get_tree().process_frame
		# This desktop-only geometry fixture supplies synthetic cutouts. Keep
		# those bounds through deferred container layout; native DisplayServer
		# correctly knows nothing about this test's imaginary phone notch.
		if is_instance_valid(_fixture_hud):
			_fixture_hud.call("apply_mobile_layout", get_viewport().get_visible_rect().size, _fixture_safe)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
