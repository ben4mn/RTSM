extends Node
## Beta 33: one tap on Army selects the field army, a second tap or a hold
## opens its panel; the rail stays put (dimmed, inert) while placing so taps
## there never move or place the preview; icon buttons carry short labels;
## the Hold Build chooser shows building art with its hint inside the panel.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	get_window().size = Vector2i(844, 390)
	GameManager.selected_difficulty = 1
	GameManager.selected_map_seed = 101
	GameManager.guided_opening_enabled = false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	main.get_node("AIController").set_process(false)
	var map: Node = main.get_node("GameMap")
	var hud: Node = main.get_node("HUD")
	var controller: Node = main.get_node("StrategyController")
	var overview: StrategyOverview = hud.get("_strategy_overview")
	var selection: Node = map.get("selection_mgr")
	var tc: BuildingBase = main.get("_player_buildings")[0][0]
	var fighters: Array[UnitBase] = []
	for offset: Vector2 in [Vector2(-90, 70), Vector2(-60, 90)]:
		var unit: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, tc.global_position + offset)
		if unit != null:
			fighters.append(unit)
	_expect(fighters.size() == 2, "fixture fighters spawn")
	selection.call("select_single", tc)
	controller.call("_refresh")
	await _frames(3)
	var army: Button = overview.rail.get_node("ArmyButton")
	# 1. One tap selects every field fighter and leaves the panel shut.
	army.button_down.emit()
	army.button_up.emit()
	army.pressed.emit()
	await _frames(3)
	var picked: Array = selection.get("selected")
	_expect(picked.size() == 2 and fighters.all(func(f: UnitBase) -> bool: return f in picked), "one tap selects the field army (%d selected)" % picked.size())
	_expect(hud.call("get_secondary_surface_name") != "army" and not overview.panel.visible, "first tap keeps the Army panel shut")
	# 2. A second tap opens the panel.
	controller.call("_refresh")
	army.button_down.emit()
	army.button_up.emit()
	army.pressed.emit()
	await _frames(3)
	_expect(overview.panel.visible, "second tap opens the Army panel")
	army.button_down.emit()
	army.button_up.emit()
	army.pressed.emit()
	await _frames(3)
	_expect(not overview.panel.visible, "tapping Army with its panel open closes it")
	# 3. Holding opens the panel without changing the selection.
	selection.call("select_single", tc)
	controller.call("_refresh")
	overview.set("_army_selected_msec", -100000)
	army.button_down.emit()
	await get_tree().create_timer(0.7).timeout
	army.button_up.emit()
	army.pressed.emit()
	await _frames(3)
	_expect(overview.panel.visible, "holding Army opens its panel")
	_expect(selection.get("selected") == [tc], "holding Army keeps the selection")
	# 4. Panel labels.
	var select_all: Button = overview.get("_select_army_button")
	_expect(select_all.text == "Select fighters" and (overview.get("_focus_army_button") as Button).text == "Find", "Army panel icons carry short labels")
	var group: Dictionary = (overview.get("_group_rows") as Dictionary)[1]
	_expect((group.save as Button).text == "Save" and (group.recall as Button).text == "Recall", "group icons carry short labels")
	_expect((overview.get("_groups_tab") as Button).text == "Groups" and (overview.get("_recruit_tab") as Button).text == "Recruit", "Army page tabs carry short labels")
	hud.call("close_secondary_surface")
	await _frames(2)
	var plus: Button = (overview.get("_destination_buttons") as Dictionary)["wood"]
	_expect(plus.text == "+ Wood", "workers panel + says what it adds to, got '%s'" % plus.text)
	_expect((overview.get("_idle_button") as Button).text == "Find idle", "workers panel hourglass is labelled")
	# 5. Placement keeps the rail where it was, dimmed and inert.
	var menu: Node = main.get("_build_menu")
	menu.emit_signal("building_selected", BuildingData.BuildingType.HOUSE)
	await _frames(4)
	var placement: BuildingPlacement = main.get("_building_placement")
	_expect(placement.active, "House placement starts")
	_expect(overview.rail.is_visible_in_tree() and army.disabled and overview.rail.modulate.a < 0.5, "rail stays visible, dimmed and inert during placement")
	var ghost: Vector2 = placement.ghost_position
	# Control: the same tap on open ground does move the preview.
	var before_ground: int = (main.get("_player_buildings")[0] as Array).size()
	var open_ground: Vector2 = (overview.rail.get_node("BaseButton") as Control).get_global_rect().get_center() - Vector2(0, 90)
	await _touch(open_ground)
	_expect(placement.ghost_position != ghost or (main.get("_player_buildings")[0] as Array).size() > before_ground, "fixture: open-ground tap reaches placement")
	if not placement.active:
		menu.emit_signal("building_selected", BuildingData.BuildingType.HOUSE)
		await _frames(4)
	ghost = placement.ghost_position
	var buildings: int = (main.get("_player_buildings")[0] as Array).size()
	for name: String in ["BaseButton", "ArmyButton"]:
		var point: Vector2 = (overview.rail.get_node(name) as Control).get_global_rect().get_center()
		await _touch(point)
	_expect(placement.ghost_position == ghost, "taps on the dimmed rail never move the preview")
	_expect((main.get("_player_buildings")[0] as Array).size() == buildings, "taps on the dimmed rail never place a building")
	_expect(placement.active, "placement continues after a tap on the rail")
	# Build menu repeat button is labelled.
	var repeat: Button = menu.get("_repeat_button")
	if repeat != null:
		menu.call("_update_repeat_button")
		_expect(repeat.text == "Again", "build menu repeat is labelled Again, got '%s'" % repeat.text)
	placement.cancel_placement()
	await _frames(4)
	_expect(not army.disabled and is_equal_approx(overview.rail.modulate.a, 1.0), "rail is live again after placement")
	# 6. Hold Build chooser: building art on every choice.
	var choices: Array = hud.call("_quick_build_choices")
	_expect(choices.size() == 4 and choices.all(func(c: Dictionary) -> bool: return c.get("icon") is Texture2D), "Hold Build choices carry building art")
	_finish()


func _touch(canvas_point: Vector2) -> void:
	# Events arrive in window pixels; the HUD lays out in stretched canvas units.
	var point: Vector2 = get_viewport().get_final_transform() * canvas_point
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = point
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = point
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _finish() -> void:
	for failure: String in _failures:
		push_error("[FAIL] army_tap_and_labels: " + failure)
	if _failures.is_empty():
		print("[PASS] army_tap_and_labels: tap selects, tap again or hold opens; rail inert while placing; labels; chooser art")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
