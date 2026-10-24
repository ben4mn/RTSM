extends Node
## Real container layout and game-creation contracts, not a network transport test.

const MAP_PREVIEW := preload("res://scripts/ui/map_preview.gd")
var _failures: Array[String] = []
var _checks: int = 0
const PROFILES: Array[Dictionary] = [
	{"size": Vector2(1280, 720), "scale": 1.0, "notch": false},
	{"size": Vector2(844, 390), "scale": 1.0, "notch": false},
	{"size": Vector2(844, 390), "scale": 1.15, "notch": true},
	{"size": Vector2(932, 430), "scale": 1.15, "notch": true},
	{"size": Vector2(844, 390), "scale": 1.15, "notch": true, "clearance": 60.0, "scroll_map": true},
	{"size": Vector2(932, 430), "scale": 1.15, "notch": true, "clearance": 60.0, "scroll_map": true},
	# 1280x800 Web stretches to 844x527. Shell controls consume more height.
	{"size": Vector2(844, 527), "scale": 1.0, "notch": false, "clearance": 45.0},
	{"size": Vector2(844, 501), "scale": 1.0, "notch": false},
	{"size": Vector2(844, 560), "scale": 1.0, "notch": false},
	{"size": Vector2(844, 600), "scale": 1.0, "notch": true},
	{"size": Vector2(844, 623), "scale": 1.0, "notch": false, "compact": true},
	{"size": Vector2(844, 624), "scale": 1.0, "notch": false, "compact": false},
	{"size": Vector2(844, 624), "scale": 1.0, "notch": false, "clearance": 45.0, "compact": true},
	{"size": Vector2(844, 637), "scale": 1.0, "notch": false, "clearance": 45.0, "compact": false},
	{"size": Vector2(844, 660), "scale": 1.0, "notch": true, "clearance": 45.0},
]
var _shell_clearance: float = 0.0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	_check_preview_projection()
	for profile: Dictionary in PROFILES:
		await _exercise(profile)
	if _failures.is_empty():
		print("[PASS] phone_menu_layout: %d checks; home, New Game, 3 maps, solo setup, host/guest lobby presentation, preference-only Settings at desktop/phone/max-scale safe areas" % _checks)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] phone_menu_layout: " + failure)
		get_tree().quit(1)


func _check_preview_projection() -> void:
	var rect := Rect2(Vector2(7, 11), Vector2(176, 88))
	var dimensions := Vector2(MapData.MAP_WIDTH, MapData.MAP_HEIGHT)
	_expect(MAP_PREVIEW.project_tile_to_preview(Vector2.ZERO, rect).is_equal_approx(rect.position), "preview origin matches terrain origin")
	_expect(MAP_PREVIEW.project_tile_to_preview(dimensions, rect).is_equal_approx(rect.end), "preview far edge matches current map dimensions")
	_expect(MAP_PREVIEW.project_tile_to_preview(dimensions * 0.5, rect).is_equal_approx(rect.get_center()), "preview Sacred Site stays centered")
	for archetype: int in MapData.MAP_ARCHETYPES:
		var generator := MapGenerator.new(101, archetype)
		generator.generate()
		for spawn: Vector2i in generator.spawn_positions:
			var marker: Vector2 = MAP_PREVIEW.project_tile_to_preview(Vector2(spawn) + Vector2(2, 2), rect)
			_expect(rect.has_point(marker), "current map %d Town Center marker stays inside terrain" % archetype)


func _exercise(profile: Dictionary) -> void:
	var logical: Vector2 = (profile.size / profile.scale).floor()
	_shell_clearance = float(profile.get("clearance", 0.0))
	var safe := Rect2(Vector2.ZERO, logical)
	if profile.notch:
		var inset: float = 44.0 / float(profile.scale)
		safe = Rect2(Vector2(inset, 0), logical - Vector2(inset * 2, 18.0 / float(profile.scale)))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(logical)
	add_child(viewport)
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	menu.size = logical
	viewport.add_child(menu)
	await _settle(menu, logical, safe)
	var context: String = "%s scale=%s shell=%s" % [profile.size, profile.scale, _shell_clearance]
	if profile.has("compact"):
		_expect(menu.get("_compact_layout") == profile.compact, context + " usable-height breakpoint")
	_expect(menu.get("_screen") == "home", context + " starts at home")
	_bounds(menu.get("_root_margin"), safe, context + " home frame")
	_touch(menu.get("_new_game_button"), safe, context + " New Game")
	_touch(menu.get("_online_button"), safe, context + " Join friend")
	_touch(menu.get("settings_button"), safe, context + " Settings")
	(menu.get("_new_game_button") as Button).pressed.emit()
	await _settle(menu, logical, safe)
	_expect(menu.get("_screen") == "setup", context + " New Game opens setup")
	_bounds(menu.get("_root_margin"), safe, context + " setup frame")
	_touch(menu.get("start_button"), safe, context + " Start")
	_footer_bounds(menu, safe, context + " solo")
	_touch(menu.get("_back_button"), safe, context + " Back")
	for button: Button in menu.get("_map_buttons"):
		_touch(button, safe, context + " " + button.name)
		_bounds(button, (menu.get("_map_scroll") as Control).get_global_rect(), context + " map target initially visible")
	if bool(profile.get("scroll_map", false)):
		var map_scroll: ScrollContainer = menu.get("_map_scroll")
		map_scroll.scroll_vertical = 10000
		await get_tree().process_frame
		_bounds(menu.get("map_summary_label"), map_scroll.get_global_rect(), context + " map details reachable by scroll")
		map_scroll.scroll_vertical = 0
	for archetype: int in MapData.MAP_ARCHETYPES:
		(menu.get("_map_buttons") as Array)[archetype].pressed.emit()
		_expect(GameManager.selected_map_archetype == archetype, context + " selected map is game draft")
		_expect((menu.get("_selection_summary") as Label).text.contains(MapData.get_archetype_name(archetype)), context + " footer names selected map")
		_expect((menu.get("map_summary_label") as Label).text == MapData.get_archetype_description(archetype), context + " selected map tactics")
		var selected: int = 0
		for button: Button in menu.get("_map_buttons"):
			selected += int(button.button_pressed)
		_expect(selected == 1, context + " exactly one selected map")
	(menu.get("_difficulty_buttons") as Array)[2].pressed.emit()
	_expect(GameManager.selected_difficulty == 2, context + " difficulty applied")
	(menu.get("_population_buttons") as Array)[0].pressed.emit()
	_expect(GameManager.selected_population_limit == 20, context + " population applied")
	var scroll: ScrollContainer = menu.get("_options_scroll")
	_expect(scroll.size.y >= (96.0 if bool(profile.get("scroll_map", false)) else 120.0), context + " useful options scroll viewport")
	scroll.scroll_vertical = 10000
	await get_tree().process_frame
	_bounds(menu.get("seed_input"), safe, context + " seed reachable by scroll")
	menu.call("_set_mode", "multiplayer")
	await _settle(menu, logical, safe)
	_touch(menu.get("_host_button"), safe, context + " create room")
	_expect(not (menu.get("_solo_options") as Control).visible, context + " solo settings hidden online")
	var session: Node = get_node("/root/NetworkSession")
	# Model shared room states independently of transport; actual socket coverage
	# lives in test_network_room_lobby, so these assertions exercise the UI contract.
	session.set("state", "lobby")
	session.set("room_code", "TEST23")
	session.set("room_host", false)
	session.set("room_players", 2)
	session.set("match_map_archetype", 1)
	menu.call("_on_room_changed")
	await _settle(menu, logical, safe)
	_expect((menu.get("start_button") as Button).disabled, context + " guest cannot start")
	_footer_bounds(menu, safe, context + " guest")
	_expect((menu.get("_room_map") as Label).text.contains("River Crossings"), context + " guest sees host map")
	for button: Button in menu.get("_map_buttons"):
		_expect(button.disabled, context + " guest cannot edit host map")
	session.set("room_host", true)
	session.set("room_players", 1)
	menu.call("_on_room_changed")
	_expect((menu.get("start_button") as Button).disabled, context + " host cannot start alone")
	session.set("room_players", 2)
	menu.call("_on_room_changed")
	await _settle(menu, logical, safe)
	_expect(not (menu.get("start_button") as Button).disabled, context + " host can start two-player room")
	_footer_bounds(menu, safe, context + " host")
	_touch(menu.get("_leave_button"), safe, context + " leave room")
	menu.call("_on_network_status_changed", "lobby", "Waiting for an arena…")
	_expect((menu.get("start_button") as Button).disabled, context + " queued host cannot repeat start")
	for button: Button in menu.get("_map_buttons"):
		_expect(button.disabled, context + " queued room map remains locked")
	session.set("room_code", "")
	session.set("room_players", 0)
	session.set("room_host", false)
	session.set("state", "idle")
	menu.call("_on_network_status_changed", "idle", "")
	menu.call("_on_settings_pressed")
	await _settle(menu, logical, safe)
	var settings: Control = menu.get("_shared_settings")
	var tabs: Array = settings.get("_tabs")
	_expect(tabs.size() == 3, context + " settings has only application preference tabs")
	_expect(settings.find_child("MapTab", true, false) == null and settings.find_child("MatchTab", true, false) == null, context + " map and match removed from Settings")
	for i: int in 3:
		settings.call("_show_section", i)
		await get_tree().process_frame
		await get_tree().process_frame
		_bounds(settings.get("_panel"), safe, context + " settings card")
		for button: BaseButton in settings.find_children("*", "BaseButton", true, false):
			if button.is_visible_in_tree():
				_expect(button.size.y >= 47.5, context + " preference touch height")
	menu.free()
	viewport.free()
	await get_tree().process_frame


func _settle(menu: Control, logical: Vector2, safe: Rect2) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	menu.call("apply_mobile_layout", logical, safe, _shell_clearance)
	await get_tree().process_frame
	await get_tree().process_frame


func _footer_bounds(menu: Control, safe: Rect2, context: String) -> void:
	var frame: Control = menu.get("_root_margin")
	_bounds(frame, safe, context + " frame")
	_expect(frame.position.y >= _shell_clearance, context + " below browser controls")
	for control: Control in [menu.get("_footer"), menu.get("start_button")]:
		_bounds(control, frame.get_global_rect(), context + " footer within frame")
	_touch(menu.get("start_button"), safe, context + " footer Start")
	if (menu.get("_leave_button") as Control).is_visible_in_tree():
		_touch(menu.get("_leave_button"), frame.get_global_rect(), context + " footer Leave")
	_expect((menu.get("_columns") as Control).get_global_rect().end.y <= (menu.get("_footer") as Control).get_global_rect().position.y, context + " content does not overlap footer")


func _touch(control: Control, safe: Rect2, label: String) -> void:
	_bounds(control, safe, label)
	_expect(control.size.y >= 47.5 and control.size.x >= 47.5, label + " 48px target")


func _bounds(control: Control, safe: Rect2, label: String) -> void:
	_expect(control.is_visible_in_tree(), label + " visible")
	_expect(safe.grow(0.5).encloses(control.get_global_rect()), label + " safe bounds: " + str(control.get_global_rect()))


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
