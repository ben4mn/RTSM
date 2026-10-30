extends Node
## Actual-control acceptance for the integrated landscape command dock and rail.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PHONE_SIZES: Array[Vector2i] = [Vector2i(667, 375), Vector2i(844, 390), Vector2i(932, 430)]
const UI_SCALES: Array[float] = [1.0, 1.075, 1.15]
const MIN_TOUCH_TARGET := 48.0

var _failures: Array[String] = []
var _profiles_checked: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	# Recruitment now exposes live purchase blockers. Give the ready-layout
	# scenario real player state and a funded producer instead of orphan nodes.
	GameManager.initialize_game(1)
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 500, "wood": 500, "gold": 500})
	for phone: Vector2i in PHONE_SIZES:
		if "--tiny-only" in OS.get_cmdline_user_args() and phone.x != 667:
			continue
		for ui_scale: float in UI_SCALES:
			for notched: bool in [false, true]:
				if phone.x == 667 and (notched or is_equal_approx(ui_scale, 1.075)):
					continue
				await _exercise_profile(phone, ui_scale, notched)
	# Effective logical area of the small phone at its largest preference
	# after the screen-space target floor; distinct from a physical device.
	if "--tiny-only" not in OS.get_cmdline_user_args():
		await _exercise_profile(Vector2i(632, 356), 1.0, false)
	if _failures.is_empty():
		print("[PASS] mobile_hud_composition: %d phone/scale/notch profiles; integrated rail/dock, guidance/toast separation, contextual targets, paid production pages, placement and pause" % _profiles_checked)
	else:
		for failure: String in _failures:
			push_error("[FAIL] mobile_hud_composition: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _exercise_profile(phone: Vector2i, ui_scale: float, notched: bool) -> void:
	var logical := Vector2(floorf(float(phone.x) / ui_scale), floorf(float(phone.y) / ui_scale))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(logical)
	add_child(viewport)
	var hud: CanvasLayer = HUD_SCENE.instantiate()
	viewport.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var safe := Rect2(Vector2.ZERO, logical)
	if notched:
		safe = Rect2(Vector2(44.0 / ui_scale, 0), logical - Vector2(88.0 / ui_scale, 18.0 / ui_scale))
	var profile := "%s scale%.3f notch%s" % [phone, ui_scale, notched]
	hud.call("set_early_game_ui_state", false)
	hud.call("update_idle_villager_count", 2)
	hud.call("update_military_count", 6)
	hud.call("update_villager_tasks", 2, 1, 1, 1)
	await _settle(hud, logical, safe)
	var dock: Control = hud.get("_command_dock")
	var selection: Control = hud.get("selection_panel")
	var minimap: Control = hud.get("minimap_bg")
	var navigation: Control = hud.get("_navigation_controls")
	var top_rail: Control = hud.get("top_bar")
	_expect(not selection.visible, profile + " unselected context leaves an empty shelf")
	_expect(dock.visible, profile + " kingdom dock is missing")
	_expect((hud.get("_town_center_button") as Button).is_visible_in_tree(), profile + " Home is missing")
	_expect(not (hud.get("_select_area_button") as Button).is_visible_in_tree(), profile + " collapsed navigation exposes area selection")
	_expect(top_rail.size.y <= 56.5, profile + " top rail exceeds56")
	_expect(minimap.size.x <= 120.5, profile + " minimap exceeds120")
	for key: String in ["_town_center_button", "_idle_villager_button", "_select_military_button", "build_menu_button", "_camera_view_button", "_pause_button", "_speed_button"]:
		_target(hud.get(key), safe, profile)
	_assert_field(hud, safe, profile + " kingdom")

	# Objective is integrated into the resource rail, while readable teaching
	# and one transient message occupy separate bounded secondary lanes.
	hud.call("set_progression_hint", "Gather Food to train a Scout, then move onto the map.", false)
	hud.call("show_notification", "Population capped. Build a House before training another unit.", Color.WHITE)
	hud.call("update_sacred_site_timer", 1, 172.0, 180.0)
	await _settle(hud, logical, safe)
	var guidance: Control = hud.get("_progression_hint_panel")
	var objective: Control = hud.get("_sacred_site_panel")
	var feed: Control = hud.get("_notification_container")
	_expect(top_rail.get_global_rect().encloses(objective.get_global_rect()), profile + " objective leaves integrated rail")
	_target(hud.get("_sacred_site_button"), safe, profile)
	_label_fits(hud.get("_sacred_site_label"), profile + " objective")
	_expect(guidance.get_global_rect().position.y >= top_rail.get_global_rect().end.y + 7.5, profile + " guidance touches rail")
	_expect(not guidance.get_global_rect().intersects(feed.get_global_rect()), profile + " guidance/toast lanes overlap")
	for toast: Control in feed.get_children():
		if toast.visible and not toast.is_queued_for_deletion():
			var text: Label = toast.get_child(0)
			_expect(text.get_visible_line_count() == text.get_line_count(), profile + " toast hides message lines")
			_expect(safe.encloses(toast.get_global_rect()), profile + " toast leaves safe area")
	_assert_field(hud, safe, profile + " guidance")

	hud.call("show_unit_selection", "Villager", 25, 25, "Gathering Food", 4, {"unit_type": UnitData.UnitType.VILLAGER})
	hud.call("configure_unit_commands", true, false, "Aggressive", "move")
	await _settle(hud, logical, safe)
	var caption: Control = hud.get("_villager_task_hbox")
	_expect(not caption.visible, profile + " duplicate worker counts add a third field row")
	_expect((hud.get("_unit_move_button") as Button).button_pressed and (hud.get("_unit_move_button") as Button).icon != null and (hud.get("_unit_move_button") as Button).tooltip_text.contains("armed") and (hud.get("selection_details") as Label).text.contains("Tap to move"), profile + " Move lacks armed cue")
	_expect(not (hud.get("age_up_button") as Button).visible and (hud.get("build_menu_button") as Button).visible, profile + " worker context is wrong")
	_expect(not (hud.get("_mobile_action_panel") as Control).visible, profile + " worker leaves detached utility rail")
	_assert_field(hud, safe, profile + " workers")
	for mode: String in ["smart", "move", "attack_move"]:
		hud.call("configure_unit_commands", true, false, "Aggressive", mode)
		await _settle(hud, logical, safe)
		var initial_shelf: ScrollContainer = hud.get("command_scroll")
		_expect(initial_shelf.scroll_horizontal == 0, profile + " worker commands scroll when arming")
		for action: Button in (hud.get("_unit_command_container") as HBoxContainer).get_children():
			_expect(initial_shelf.get_global_rect().encloses(action.get_global_rect()), profile + " " + mode + " clips " + String(action.name))
			_target(action, safe, profile)
			_expect(action.size.is_equal_approx(Vector2(48, 48)), profile + " primary command is not square: " + String(action.name) + " " + str(action.size))
	_expect(selection.size.y <= 72.5, profile + " unit dock exceeds72")
	# The isolated HUD starts with its legacy shortcuts. Real matches attach
	# Strategy from main.gd; install it before testing the shared orders row.
	hud.call("setup_strategy_overview")
	hud.call("_on_unit_more_pressed")
	await _settle(hud, logical, safe)
	_target(hud.get("_worker_idle_button"), safe, profile)
	_expect((hud.get("_worker_idle_button") as Button).get_node("CommandIconBadge").text == "2", profile + " More loses idle count")
	var advanced: Control = hud.get("_advanced_command_panel")
	var strategy: Control = hud.get("_strategy_overview")
	var strategy_rail: Control = strategy.get("rail")
	_expect(advanced.get_global_rect().end.x <= strategy_rail.get_global_rect().position.x - 7.5, profile + " expanded orders overlap management rail")
	for action: Button in (hud.get("_advanced_command_container") as HBoxContainer).get_children():
		if action.visible:
			_expect(action.size.y <= 48.5, profile + " expanded order stretches vertically")
			_expect(absf(action.get_global_rect().get_center().y - strategy_rail.get_global_rect().get_center().y) <= 0.5, profile + " expanded orders create a separate third row: " + str(action.get_global_rect()) + " rail=" + str(strategy_rail.get_global_rect()))
	_assert_field(hud, safe, profile + " worker More")
	hud.call("_on_unit_more_pressed")

	hud.call("show_unit_selection", "Army", 300, 400, "Moving", 6, {"role_counts": {UnitData.UnitType.INFANTRY: 3, UnitData.UnitType.ARCHER: 3}})
	hud.call("configure_unit_commands", true, true, "Aggressive", "attack_move")
	await _settle(hud, logical, safe)
	_expect(not caption.visible and not (hud.get("build_menu_button") as Button).visible, profile + " army retains worker controls")
	_expect((hud.get("_unit_attack_move_button") as Button).button_pressed, profile + " Attack lacks armed state")
	_assert_field(hud, safe, profile + " army")

	var tc := BuildingBase.new()
	tc.building_type = BuildingData.BuildingType.TOWN_CENTER
	tc.player_owner = 0
	tc.state = BuildingBase.State.ACTIVE
	var pq := ProductionQueue.new()
	tc.add_child(pq)
	tc.set_production_queue(pq)
	viewport.add_child(tc)
	pq.auto_queue_unit_type = UnitData.UnitType.SCOUT
	var queue_items: Array = [
		{"unit_type": UnitData.UnitType.VILLAGER, "name": "Villager", "is_training": true, "progress": 0.42},
		{"unit_type": UnitData.UnitType.VILLAGER, "name": "Villager", "is_training": false},
		{"unit_type": UnitData.UnitType.SCOUT, "name": "Scout", "is_training": false},
	]
	hud.call("show_building_selection", "Town Center", 5000, 5000, queue_items, [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT], tc)
	await _settle(hud, logical, safe)
	var scroll: ScrollContainer = hud.get("command_scroll")
	_expect(scroll.scroll_horizontal == 0, profile + " production does not begin on Train page")
	for button: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
		_target(button, safe, profile)
		_expect(scroll.get_global_rect().encloses(button.get_global_rect()), profile + " initial Train/Repeat target is clipped: " + str(scroll.get_global_rect()) + " target " + str(button.get_global_rect()) + " info " + str((hud.get("selection_info_column") as Control).get_global_rect()))
	var scout: Button = (hud.get("_train_buttons_container") as HBoxContainer).get_node("TrainButton_%d" % UnitData.UnitType.SCOUT)
	var recruit_bounds: Dictionary = {}
	for recruit: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
		recruit_bounds[recruit.name] = recruit.get_global_rect()
	# A paid queue and changing blocker text must never move the recruit target
	# after the user has committed a finger to that spot.
	var saved_resources: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	hud.call("show_building_selection", "Town Center", 5000, 5000, [], [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT], tc)
	await _settle(hud, logical, safe)
	for recruit: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
		_expect(recruit.get_global_rect().is_equal_approx(recruit_bounds[recruit.name]), profile + " resource/empty queue refresh moved " + str(recruit.name))
	ResourceManager.initialize_player(0, saved_resources)
	hud.call("show_building_selection", "Town Center", 5000, 5000, queue_items, [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT], tc)
	await _settle(hud, logical, safe)
	for recruit: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
		_expect(recruit.get_global_rect().is_equal_approx(recruit_bounds[recruit.name]), profile + " paid queue refresh moved " + str(recruit.name))
	_expect((hud.get("selection_details") as Label).text.contains("2 waiting"), profile + " production summary omits pending count")
	for resource: String in ["food", "gold"]:
		_expect(scout.text.contains("%d%s" % [UnitData.get_unit_cost(UnitData.UnitType.SCOUT)[resource], resource.left(1).to_upper()]), profile + " Scout omits cost")
	_target(hud.get("_queue_navigation_button"), safe, profile)
	_assert_field(hud, safe, profile + " production")
	hud.call("_on_queue_navigation_pressed")
	await _settle(hud, logical, safe)
	for button: Control in (hud.get("queue_container") as Control).get_children():
		if button is Button and button.visible and not button.is_queued_for_deletion():
			_target(button, safe, profile)
			_expect(scroll.get_global_rect().encloses(button.get_global_rect()), profile + " queue cancellation target cannot be reached")
	_expect((hud.get("_queue_navigation_button") as Button).icon != null and (hud.get("_queue_navigation_button") as Button).accessibility_name.contains("recruitment"), profile + " queue loses return action")

	var smith := BuildingBase.new()
	smith.building_type = BuildingData.BuildingType.BLACKSMITH
	smith.player_owner = 0
	smith.state = BuildingBase.State.ACTIVE
	hud.call("show_building_selection", "Blacksmith", 1200, 1200, [], [], smith)
	await _settle(hud, logical, safe)
	for button: Button in (hud.get("_research_container") as HBoxContainer).get_children():
		if button.visible and not button.is_queued_for_deletion():
			_expect(button.size.x >= 48 and button.size.y >= 48, profile + " research target under48")
			_expect(scroll.get_global_rect().grow(0.5).encloses(button.get_global_rect()), profile + " research target clipped by fixed shelf: " + str(button.name))
	_assert_field(hud, safe, profile + " research")

	hud.call("set_ui_modal_state", 1)
	await _settle(hud, logical, safe)
	_expect(not dock.visible and not selection.visible and not minimap.visible and not navigation.visible, profile + " build sheet retains competing field chrome")
	hud.call("set_ui_modal_state", 0)
	hud.call("set_placement_input_mode", true)
	hud.call("set_placement_mode", true, "House")
	await _settle(hud, logical, safe)
	_expect(not dock.visible and not selection.visible and not minimap.visible and not navigation.visible, profile + " placement retains field chrome")
	var place: Button = hud.get("_placement_confirm_button")
	_target(place, safe, profile)
	_target(hud.get("_placement_cancel_button"), safe, profile)
	var find_space: Button = hud.get("_placement_find_space_button")
	_target(find_space, safe, profile)
	# Beta 25: placement actions are an icon plus one word (Place / Find / cross).
	_expect(find_space.text == "Find" and find_space.icon != null and not find_space.disabled, profile + " Find space action missing")
	_expect(place.disabled, profile + " invalid preview can be placed")
	hud.call("update_placement_preview", true, "")
	_expect(not place.disabled, profile + " valid preview cannot be placed")
	hud.call("update_placement_preview", false, "Blocked ground")
	_expect(place.disabled, profile + " blocked preview leaves Place enabled")
	# Long building names plus the observed-fog explanation remain readable
	# within the existing status lane; this does not widen field chrome.
	for building_name: String in ["Archery Range", "Siege Workshop", "Town Center"]:
		hud.call("set_placement_mode", true, building_name)
		hud.call("update_placement_preview", false, BuildingPlacement.FOG_INVALID_REASON)
		await _settle(hud, logical, safe)
		var status: Label = hud.get("_placement_status_label")
		_expect(status.text == building_name + " · Move all tiles into sight", profile + " fog explanation missing")
		_label_fits(status, profile + " full-footprint sight")
		_expect(safe.encloses((hud.get("_placement_status_panel") as Control).get_global_rect()), profile + " sight status leaves safe area")
		_expect(place.disabled, profile + " fog explanation enables Place")
		_target(place, safe, profile)
	# Mouse assistance has an explicit, readable purchase action without changing
	# direct world-click placement. Ordinary touch already had this action.
	hud.call("set_placement_input_mode", false)
	hud.call("set_placement_assisted_preview", false)
	await _settle(hud, logical, safe)
	_expect(not place.visible and find_space.visible, profile + " normal mouse placement contract changed")
	hud.call("set_placement_assisted_preview", true)
	hud.call("update_placement_preview", true, "")
	await _settle(hud, logical, safe)
	_target(place, safe, profile)
	_target(find_space, safe, profile)
	# Beta 25 copy: the assisted mouse hint is "House · click Place" (was "Click Place to build").
	_expect(not place.disabled and (hud.get("_placement_status_label") as Label).text.ends_with("click Place"), profile + " assisted mouse confirmation unavailable")
	_label_fits(hud.get("_placement_status_label"), profile + " assisted mouse status")
	var search_safe: Rect2 = hud.call("get_placement_search_safe_rect")
	_expect(safe.encloses(search_safe) and search_safe.end.y <= (hud.get("_mobile_action_panel") as Control).get_global_rect().position.y, profile + " search permits bottom action band")
	hud.call("set_ui_modal_state", 2)
	_expect(find_space.disabled and place.disabled, profile + " pause permits placement assistance")
	hud.call("set_ui_modal_state", 0)
	hud.call("set_placement_mode", false)
	await _settle(hud, logical, safe)
	_expect(not find_space.visible and not place.visible, profile + " placement actions survive cancel")
	_expect(dock.visible and selection.visible and minimap.visible, profile + " placement does not restore context")

	hud.call("set_ui_modal_state", 2)
	await _settle(hud, logical, safe)
	var pause_menu: Control = hud.get("_pause_overlay").get_node("PauseMenu")
	_expect(safe.encloses(pause_menu.get_global_rect()), profile + " pause leaves safe area")
	# Solo pause has no Quit (Save & exit replaced it) and, since beta 27,
	# Lessons is a round tool in UtilityRow instead of a row of its own.
	for name: String in ["ResumeButton", "UtilityRow/SettingsButton", "UtilityRow/ReportProblemButton", "UtilityRow/MatchLearningButton"]:
		_target(pause_menu.get_node(name), safe, profile)
	hud.call("set_ui_modal_state", 0)
	_profiles_checked += 1
	smith.free()
	tc.free()
	viewport.free()
	await get_tree().process_frame


func _settle(hud: Node, logical: Vector2, safe: Rect2) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	hud.call("apply_mobile_layout", logical, safe)
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_field(hud: Node, safe: Rect2, label: String) -> void:
	var controls: Array[Control] = []
	for key: String in ["minimap_bg", "selection_panel", "_navigation_controls", "_advanced_command_panel", "_progression_hint_panel"]:
		var control: Control = hud.get(key)
		if control.is_visible_in_tree():
			_expect(safe.encloses(control.get_global_rect()), label + " " + key + " leaves safe area")
			controls.append(control)
	var side: Control = hud.get_node("Root/BottomRight")
	if side.visible:
		controls.append(side)
	for index: int in controls.size():
		for other: int in range(index + 1, controls.size()):
			_expect(not controls[index].get_global_rect().intersects(controls[other].get_global_rect()), "%s %s overlaps %s" % [label, controls[index].name, controls[other].name])
	var dock: Control = hud.get("_command_dock")
	if dock.visible:
		_expect(safe.encloses(dock.get_global_rect()), label + " dock leaves safe area")
		var selection: Control = hud.get("selection_panel")
		if selection.visible:
			_expect(dock.get_global_rect().encloses(selection.get_global_rect()), "%s selection %s leaves integrated dock %s" % [label, selection.get_global_rect(), dock.get_global_rect()])
	var obstacles: Array = hud.call("get_world_occlusion_rects")
	_expect(not obstacles.is_empty(), label + " exposes no camera exclusions")
	for obstacle: Rect2 in obstacles:
		_expect(obstacle.size.x < safe.size.x + 90.0 and obstacle.size.y < safe.size.y, label + " exposes transparent full-screen obstacle")
	_expect(bool(hud.get("mobile_layout_diagnostics").get("layout_pass", false)), label + " metrics report overlap")


func _target(button: Button, safe: Rect2, label: String) -> void:
	_expect(button.is_visible_in_tree(), label + " target hidden: " + String(button.name))
	_expect(button.size.x >= MIN_TOUCH_TARGET - 0.5 and button.size.y >= MIN_TOUCH_TARGET - 0.5, label + " target under48: " + String(button.name))
	_expect(button.size.x / maxf(1.0, button.size.y) <= (6.5 if button.name == "ResumeButton" else 4.0), label + " target exceeds4:1: " + String(button.name))
	_expect(safe.encloses(button.get_global_rect()), label + " target outside safe: " + String(button.name))


func _label_fits(label: Label, profile: String) -> void:
	for line: String in label.text.split("\n"):
		var width: float = label.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		_expect(width <= label.size.x + 0.5, profile + " hides text: " + line)
	_expect(label.get_minimum_size().y <= label.size.y + 0.5, profile + " text height clips")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
