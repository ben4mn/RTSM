extends Node
## Exercise normal menu signals. Settling must never force a layout pass.

class ShellMenu:
	extends "res://scripts/ui/main_menu.gd"
	var modeled_safe_area := Rect2()
	var modeled_clearance: float = 0.0
	func _refresh_responsive_layout() -> void:
		if is_node_ready():
			# Replace platform geometry only; production events still own timing.
			apply_mobile_layout(get_viewport().get_visible_rect().size, modeled_safe_area, modeled_clearance)

const PROFILES: Array[Dictionary] = [
	{"size": Vector2i(844, 527), "clearance": 45.0, "notch": false},
	{"size": Vector2i(844, 390), "clearance": 68.0, "notch": false},
	{"size": Vector2i(734, 339), "clearance": 60.0, "notch": true},
	{"size": Vector2i(1280, 720), "clearance": 0.0, "notch": false},
]
var _checks: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	for profile: Dictionary in PROFILES:
		for direct: bool in [true, false]:
			await _exercise(profile, direct)
	if _failures.is_empty():
		print("[PASS] menu_mode_reflow: %d checks; direct Join friend, Solo/Multiplayer tabs, map changes and Back/reopen without forced layout; four platform geometries" % _checks)
	else:
		for failure: String in _failures:
			push_error("[FAIL] menu_mode_reflow: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _exercise(profile: Dictionary, direct: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = profile.size
	add_child(viewport)
	var menu := ShellMenu.new()
	menu.modeled_safe_area = Rect2(Vector2.ZERO, Vector2(profile.size))
	if bool(profile.notch):
		menu.modeled_safe_area = Rect2(Vector2(44.0 / 1.15, 0), Vector2(profile.size) - Vector2(88.0 / 1.15, 18.0 / 1.15))
	menu.modeled_clearance = float(profile.clearance)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(menu)
	await _settle()
	var context: String = "%s shell=%s direct=%s" % [profile.size, profile.clearance, direct]
	if direct:
		(menu.get("_online_button") as Button).pressed.emit()
	else:
		(menu.get("_new_game_button") as Button).pressed.emit()
		await _settle()
		(menu.get("_online_tab") as Button).pressed.emit()
	await _settle()
	_check_online(menu, context + " initial online")
	(menu.get("_solo_tab") as Button).pressed.emit()
	await _settle()
	_bounds(menu.get("start_button"), menu.modeled_safe_area, context + " solo Start")
	(menu.get("_online_tab") as Button).pressed.emit()
	for button: Button in menu.get("_map_buttons"):
		button.pressed.emit()
		await _settle()
		_check_online(menu, context + " " + button.name)
	(menu.get("_back_button") as Button).pressed.emit()
	await _settle()
	(menu.get("_online_button") as Button).pressed.emit()
	await _settle()
	_check_online(menu, context + " Back/reopen")
	var settled_rect: Rect2 = (menu.get("_root_margin") as Control).get_global_rect()
	await _settle()
	_expect((menu.get("_root_margin") as Control).get_global_rect().is_equal_approx(settled_rect), context + " settled frame stays stable")
	viewport.free()
	await get_tree().process_frame


func _check_online(menu: ShellMenu, context: String) -> void:
	_expect(menu.get("_mode") == "multiplayer", context + " online mode")
	var frame: Control = menu.get("_root_margin")
	_bounds(frame, menu.modeled_safe_area, context + " frame")
	_expect(frame.position.y >= menu.modeled_clearance, context + " toolbar clearance")
	_bounds(menu.get("_footer"), frame.get_global_rect(), context + " footer")
	_bounds(menu.get("_selection_summary"), frame.get_global_rect(), context + " summary")
	var map_rect: Rect2 = (menu.get("_map_scroll") as Control).get_global_rect()
	for i: int in (menu.get("_map_buttons") as Array).size():
		var button: Button = (menu.get("_map_buttons") as Array)[i]
		_bounds(button, map_rect, context + " map button")
		_bounds((menu.get("_map_names") as Array)[i], map_rect, context + " full map name")
		_bounds((menu.get("_map_badges") as Array)[i], map_rect, context + " selected state")
		_expect(button.size.x >= 48.0 and button.size.y >= 48.0, context + " map touch target")
	_bounds(menu.get("_host_button"), (menu.get("_options_scroll") as Control).get_global_rect(), context + " Create room")
	_expect((menu.get("_host_button") as Button).size.y >= 48.0, context + " Create target")


func _settle() -> void:
	for frame: int in 12:
		await get_tree().process_frame


func _bounds(control: Control, rect: Rect2, message: String) -> void:
	_expect(control.is_visible_in_tree(), message + " visible")
	_expect(rect.grow(0.75).encloses(control.get_global_rect()), message + " inside " + str(rect) + ": " + str(control.get_global_rect()))


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
