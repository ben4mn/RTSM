extends Node
## Exact-phone regression for the stable touch unit-command rail.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PHONE_SIZES: Array[Vector2i] = [Vector2i(844, 390), Vector2i(932, 430)]
const UI_SCALES: Array[float] = [1.0, 1.15]
const EXPECTED_ORDER: Array[String] = [
	"UnitMoveButton",
	"UnitStopButton",
	"UnitMoreButton",
	"UnitClearButton",
]


var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	for phone_size: Vector2i in PHONE_SIZES:
		for ui_scale: float in UI_SCALES:
			await _exercise_profile(phone_size, ui_scale, false)
			await _exercise_profile(phone_size, ui_scale, true)
	if _failures.is_empty():
		print("[PASS] mobile_unit_command_bar: 8 phone profiles expose 48px Move/Stop/More/Clear and expandable advanced commands")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] mobile_unit_command_bar: %s" % failure)
	get_tree().quit(1)


func _exercise_profile(phone_size: Vector2i, ui_scale: float, notched: bool) -> void:
	var logical_size := Vector2(
		floorf(float(phone_size.x) / ui_scale),
		floorf(float(phone_size.y) / ui_scale)
	)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(logical_size)
	add_child(viewport)
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	viewport.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var safe_area := Rect2(Vector2.ZERO, logical_size)
	if notched:
		var side: float = 44.0 / ui_scale
		var bottom: float = 18.0 / ui_scale
		safe_area = Rect2(Vector2(side, 0.0), Vector2(logical_size.x - side * 2.0, logical_size.y - bottom))
	hud.call("show_unit_selection", "Scout", 110, 110, "Idle", 8, {"damage": 5, "armor": 0, "stance": "Aggressive"})
	hud.call("configure_unit_commands", true, true, "Aggressive", "attack_move")
	hud.call("apply_mobile_layout", logical_size, safe_area)
	await get_tree().process_frame
	await get_tree().process_frame
	hud.call("apply_mobile_layout", logical_size, safe_area)
	await get_tree().process_frame
	await get_tree().process_frame
	hud.call("_refresh_touch_target_diagnostics")

	var suffix := "%dx%d %.2f%s" % [phone_size.x, phone_size.y, ui_scale, " notch" if notched else ""]
	var selection: PanelContainer = hud.get("selection_panel") as PanelContainer
	var minimap: Control = hud.get("minimap_bg") as Control
	var side_rail: Control = hud.get_node("Root/BottomRight") as Control
	var container: HBoxContainer = hud.get("_unit_command_container") as HBoxContainer
	var command_scroll: ScrollContainer = hud.get("command_scroll") as ScrollContainer
	_expect(container.visible, "%s command rail is hidden" % suffix)
	_expect(selection.size.y <= 72.5, "%s command rail grows above 72px: %s (min=%s)" % [suffix, selection.size, selection.get_combined_minimum_size()])
	_expect(selection.size.x <= 520.5, "%s command rail exceeds the field corridor" % suffix)
	_expect(not selection.get_global_rect().intersects(minimap.get_global_rect(), true), "%s command rail %s min=%s commands=%s scroll=%s overlaps minimap %s" % [suffix, selection.get_global_rect(), selection.get_combined_minimum_size(), container.get_combined_minimum_size(), command_scroll.get_combined_minimum_size(), minimap.get_global_rect()])
	_expect(not selection.get_global_rect().intersects(side_rail.get_global_rect(), true), "%s command rail %s overlaps thumb controls %s" % [suffix, selection.get_global_rect(), side_rail.get_global_rect()])
	_expect_eq(container.get_child_count(), EXPECTED_ORDER.size(), "%s command count" % suffix)
	for index in mini(container.get_child_count(), EXPECTED_ORDER.size()):
		var button := container.get_child(index) as Button
		_expect_eq(String(button.name), EXPECTED_ORDER[index], "%s command order %d" % [suffix, index])
		_expect(button.size.x * ui_scale >= 47.5 and button.size.y * ui_scale >= 47.5, "%s %s is below 48 physical pixels" % [suffix, button.name])
		_expect(button.size.x / maxf(1.0, button.size.y) <= 4.0, "%s %s exceeds 4:1 aspect" % [suffix, button.name])
	var advanced: HBoxContainer = hud.get("_advanced_command_container") as HBoxContainer
	var popup: PanelContainer = hud.get("_advanced_command_panel") as PanelContainer
	_expect(not popup.visible, "%s advanced commands start collapsed" % suffix)
	hud.call("_on_unit_more_pressed")
	await get_tree().process_frame
	hud.call("apply_mobile_layout", logical_size, safe_area)
	await get_tree().process_frame
	_expect(popup.visible, "%s More did not reveal advanced commands" % suffix)
	_expect_eq(advanced.get_child_count(), 3, "%s advanced command count" % suffix)
	_expect(not popup.get_global_rect().intersects(selection.get_global_rect(), true), "%s advanced commands overlap selection" % suffix)
	_expect(not popup.get_global_rect().intersects((hud.get("_camera_controls") as Control).get_global_rect(), true), "%s advanced commands overlap zoom controls" % suffix)
	_expect(popup.get_global_rect().position.x >= safe_area.position.x and popup.get_global_rect().end.x <= safe_area.end.x, "%s advanced commands leave safe area" % suffix)
	for child: Button in advanced.get_children():
		_expect(child.size.x * ui_scale >= 47.5 and child.size.y * ui_scale >= 47.5, "%s advanced %s is under48px" % [suffix, child.name])
	var attack_button := advanced.get_node("UnitAttackMoveButton") as Button
	_expect(attack_button.button_pressed, "%s armed A-Move state is not visible" % suffix)
	var patrol_button := advanced.get_node("UnitPatrolButton") as Button
	hud.call("configure_unit_commands", true, false, "Stand Ground", "smart")
	_expect(patrol_button.disabled, "%s Patrol remains active for villager-only selection" % suffix)
	var stance_button := advanced.get_node("UnitStanceButton") as Button
	_expect_eq(stance_button.text, "Stance", "%s stance action label remains stable" % suffix)
	_expect(stance_button.button_pressed, "%s Stand Ground state is not visible" % suffix)

	hud.call("show_unit_selection", "Army", 250, 400, "Moving", 6, {})
	_expect_eq((hud.get("selection_name") as Label).text, "Army · 6", "%s mixed army label" % suffix)
	hud.call("show_unit_selection", "Units", 150, 220, "Moving", 4, {})
	_expect_eq((hud.get("selection_name") as Label).text, "Units · 4", "%s mixed workers/troops label" % suffix)
	hud.call("set_ui_modal_state", 1)
	await get_tree().process_frame
	_expect(not selection.visible, "%s Build mode leaves the command rail competing with the sheet" % suffix)
	_expect(not popup.visible, "%s Build mode leaves advanced commands behind the sheet" % suffix)
	hud.call("set_ui_modal_state", 0)
	viewport.free()
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
