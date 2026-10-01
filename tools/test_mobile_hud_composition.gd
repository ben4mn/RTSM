extends Node
## Real-control regression for the battlefield-first mobile HUD composition.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PHONE_SIZES: Array[Vector2i] = [Vector2i(844, 390), Vector2i(932, 430)]
const MIN_TOUCH_TARGET := 48.0
const MOBILE_NOTIFICATION_TEST_MAX_WIDTH := 224.5
const UI_SCALES: Array[float] = [1.0, 1.15]
const MIN_PHYSICAL_GAP := 8.0

var _failures: Array[String] = []
var _selection_action_profiles_checked: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	for phone_size: Vector2i in PHONE_SIZES:
		await _exercise_phone_size(phone_size)
		for ui_scale: float in UI_SCALES:
			await _exercise_scaled_corridor(phone_size, ui_scale, false)
			await _exercise_scaled_corridor(phone_size, ui_scale, true)

	if _failures.is_empty():
		print(
			"[PASS] mobile_hud_composition: phone states, safe areas, and 1.0/1.15 UI scales remain collision-free; "
			+ "%d real queue/train/research action profiles meet 48px and 4:1 limits" % _selection_action_profiles_checked
		)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] mobile_hud_composition: %s" % failure)
	get_tree().quit(1)


func _exercise_phone_size(phone_size: Vector2i) -> void:
	var phone_viewport := SubViewport.new()
	phone_viewport.size = phone_size
	add_child(phone_viewport)
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	phone_viewport.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var viewport_size := Vector2(phone_size)
	var full_safe_area := Rect2(Vector2.ZERO, viewport_size)
	hud.call("update_idle_villager_count", 0)
	hud.call("update_military_count", 0)
	hud.call("apply_mobile_layout", viewport_size, full_safe_area)
	await get_tree().process_frame

	var metrics: Dictionary = hud.get("mobile_layout_diagnostics")
	var top_bar: PanelContainer = hud.get_node("Root/TopBar") as PanelContainer
	var minimap: ColorRect = hud.get_node("Root/MinimapBG") as ColorRect
	var bottom_right: VBoxContainer = hud.get_node("Root/BottomRight") as VBoxContainer
	var selection: PanelContainer = hud.get_node("Root/SelectionPanel") as PanelContainer
	var action_panel: PanelContainer = hud.get_node("Root/MobileActionPanel") as PanelContainer
	var game_controls: Control = hud.get_node("Root/GameControlButtons") as Control
	var age_button: Button = hud.get("age_up_button") as Button
	var build_button: Button = hud.get("build_menu_button") as Button
	var score_label: Label = hud.get("_score_label") as Label
	var camera_controls: HBoxContainer = hud.get("_camera_controls") as HBoxContainer

	var prefix := "%dx%d" % [phone_size.x, phone_size.y]
	_expect(camera_controls.visible, "%s visible zoom controls are missing" % prefix)
	for button: Button in camera_controls.get_children():
		if button.visible:
			_expect(button.size.x >= MIN_TOUCH_TARGET and button.size.y >= MIN_TOUCH_TARGET, "%s visible view/zoom button is under48px" % prefix)
	_expect((hud.get("_camera_view_button") as Button).visible and not (hud.get("_camera_zoom_in_button") as Button).visible, "%s camera controls did not start collapsed" % prefix)
	_expect(not camera_controls.get_global_rect().intersects(minimap.get_global_rect(), true), "%s zoom controls overlap minimap" % prefix)
	hud.call("update_camera_zoom", 0.62, 0.62, 2.2)
	_expect((hud.get("_camera_zoom_out_button") as Button).disabled, "%s minus remains active at minimum zoom" % prefix)
	hud.call("update_camera_zoom", 2.2, 0.62, 2.2)
	_expect((hud.get("_camera_zoom_in_button") as Button).disabled, "%s plus remains active at maximum zoom" % prefix)
	hud.call("update_camera_zoom", 1.0, 0.62, 2.2)
	hud.call("set_match_population_limit", 30)
	_expect((hud.get("_match_population_label") as Label).text == "Max 30", "%s match maximum is missing beside housing capacity" % prefix)
	_expect(top_bar.size.y <= 40.5, "%s top rail exceeds 40px" % prefix)
	_expect(minimap.size.x <= 120.5 and minimap.size.y <= 120.5, "%s minimap exceeds 120px" % prefix)
	_expect(age_button.size.y >= MIN_TOUCH_TARGET and build_button.size.y >= MIN_TOUCH_TARGET, "%s thumb buttons are shorter than 48px" % prefix)
	_expect(not selection.visible, "%s selection shelf is visible without a selection" % prefix)
	_expect(action_panel.visible, "%s persistent Home shortcut is missing" % prefix)
	_expect((hud.get("_town_center_button") as Button).visible, "%s Home is hidden" % prefix)
	_expect(bool(metrics.get("layout_pass", false)), "%s layout diagnostics report overlap" % prefix)
	_expect(float(metrics.get("central_world_width", 0.0)) >= 560.0, "%s central world is narrower than 560px" % prefix)
	_expect(float(metrics.get("central_world_height", 0.0)) >= 230.0, "%s central world is shorter than 230px" % prefix)
	var default_coverage: float = (
		viewport_size.x * top_bar.size.y
		+ minimap.size.x * minimap.size.y
		+ bottom_right.size.x * bottom_right.size.y
	) / (viewport_size.x * viewport_size.y)
	_expect(default_coverage <= 0.22, "%s default chrome covers %.1f%% of the screen" % [prefix, default_coverage * 100.0])

	# Guidance, transient messages, and the sacred-site clock each have a bounded
	# lane instead of painting unbounded text across one another.
	hud.call("set_progression_hint", "Gather Food to train a Scout, then move onto the map.", false)
	hud.call("show_notification", "A deliberately long mobile notification must wrap or trim inside its compact lane.", Color.WHITE)
	hud.call("update_sacred_site_timer", 1, 172.0, 180.0)
	await get_tree().process_frame
	var guidance: PanelContainer = hud.get("_progression_hint_panel") as PanelContainer
	var notifications: VBoxContainer = hud.get("_notification_container") as VBoxContainer
	var sacred_chip: PanelContainer = hud.get("_sacred_site_panel") as PanelContainer
	_expect(guidance.get_global_rect().position.y - top_bar.get_global_rect().end.y >= MIN_PHYSICAL_GAP - 0.5, "%s top-to-guidance gap is under 8px" % prefix)
	_expect(notifications.get_global_rect().position.y - top_bar.get_global_rect().end.y >= MIN_PHYSICAL_GAP - 0.5, "%s top-to-notification gap is under 8px" % prefix)
	_expect(sacred_chip.get_global_rect().position.y - guidance.get_global_rect().end.y >= MIN_PHYSICAL_GAP - 0.5, "%s guidance-to-sacred gap is under 8px" % prefix)
	_expect(not notifications.get_global_rect().intersects(guidance.get_global_rect(), true), "%s notifications overlap guidance" % prefix)
	_expect(not sacred_chip.get_global_rect().intersects(top_bar.get_global_rect(), true), "%s sacred chip overlaps top rail" % prefix)
	_expect(
		not sacred_chip.get_global_rect().intersects(guidance.get_global_rect(), true),
		"%s sacred chip %s overlaps guidance %s" % [prefix, sacred_chip.get_global_rect(), guidance.get_global_rect()]
	)
	_expect(notifications.size.x <= MOBILE_NOTIFICATION_TEST_MAX_WIDTH, "%s notification lane exceeds 224px" % prefix)
	var toast_panel: PanelContainer = notifications.get_child(0) as PanelContainer
	var toast_label: Label = toast_panel.get_child(0) as Label
	_expect(toast_label.autowrap_mode != TextServer.AUTOWRAP_OFF and toast_label.size.y >= toast_label.get_theme_font("font").get_height(toast_label.get_theme_font_size("font_size")), "%s notification text collapses" % prefix)
	_expect(toast_label.get_visible_line_count() == toast_label.get_line_count(), "%s notification hides message lines" % prefix)

	# A selected unit gets a short information shelf, not a large modal card.
	hud.call("show_unit_selection", "Villager", 25, 25, "Idle", 1, {"damage": 3, "armor": 0})
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(selection.visible, "%s unit selection did not show its context shelf" % prefix)
	_expect(selection.size.y <= 72.5, "%s unit context shelf exceeds 72px (%.1f)" % [prefix, selection.size.y])
	_expect(selection.size.x <= 320.5, "%s unit context shelf is wider than 320px" % prefix)
	_expect(not selection.get_global_rect().intersects(minimap.get_global_rect(), true), "%s selection shelf overlaps minimap" % prefix)
	_expect(not selection.get_global_rect().intersects(bottom_right.get_global_rect(), true), "%s selection shelf overlaps thumb rail" % prefix)

	# Commands expand horizontally inside the same 72px shelf and scroll rather
	# than growing upward into the battlefield.
	var queue_container: HBoxContainer = hud.get("queue_container") as HBoxContainer
	var mock_command := Button.new()
	mock_command.text = "Train"
	mock_command.custom_minimum_size = Vector2(108, 48)
	queue_container.add_child(mock_command)
	queue_container.visible = true
	hud.call("apply_mobile_layout", viewport_size, full_safe_area)
	await get_tree().process_frame
	_expect(selection.size.y <= 72.5, "%s command shelf grew above 72px (%.1f)" % [prefix, selection.size.y])
	_expect(selection.size.x <= 520.5, "%s command shelf is wider than 520px" % prefix)
	_expect(not selection.get_global_rect().intersects(minimap.get_global_rect(), true), "%s command shelf overlaps minimap" % prefix)
	_expect(not selection.get_global_rect().intersects(bottom_right.get_global_rect(), true), "%s command shelf overlaps thumb rail" % prefix)

	# The build sheet owns the lower screen while open; underlying HUD chrome is
	# hidden so there are no stacked or competing touch surfaces.
	hud.call("set_ui_modal_state", 1)
	await get_tree().process_frame
	_expect(not selection.visible, "%s selection shelf remained behind the build sheet" % prefix)
	_expect(not minimap.visible, "%s minimap remained behind the build sheet" % prefix)
	_expect(not bottom_right.visible, "%s thumb rail remained behind the build sheet" % prefix)
	_expect(not action_panel.visible, "%s utility rail remained behind the build sheet" % prefix)
	_expect(not camera_controls.visible, "%s zoom controls remained behind the build sheet" % prefix)
	hud.call("set_ui_modal_state", 0)
	await get_tree().process_frame
	_expect(selection.visible and minimap.visible and bottom_right.visible, "%s field chrome did not return after closing the build sheet" % prefix)

	# Free play can expose Age, Idle, Military, and Find at once. Worker task
	# micro-stats stay off the phone rail so the two vertical stacks never meet.
	hud.call("set_early_game_ui_state", false)
	hud.call("configure_unit_commands", true, false, "Aggressive", "smart")
	hud.call("set_guided_military_shortcuts_visible", true)
	hud.call("update_villager_tasks", 2, 1, 1, 0)
	hud.call("update_idle_villager_count", 1)
	hud.call("update_military_count", 2)
	hud.call("apply_mobile_layout", viewport_size, full_safe_area)
	await get_tree().process_frame
	var task_row: HBoxContainer = hud.get("_villager_task_hbox") as HBoxContainer
	_expect(task_row.visible and task_row.get_parent() == hud.get_node("Root"), "%s worker distribution is not a compact context caption" % prefix)
	_expect(not score_label.visible, "%s free-play score overlaps the compact top-rail clock" % prefix)
	_expect(not age_button.visible and build_button.visible, "%s worker context did not hide Age while preserving Build" % prefix)
	_expect(not (hud.get("_town_center_button") as Button).visible and not (hud.get("_select_military_button") as Button).visible, "%s worker context retained irrelevant kingdom rail" % prefix)
	_expect(action_panel.visible, "%s free-play utility rail is missing" % prefix)
	_expect(not action_panel.get_global_rect().intersects(bottom_right.get_global_rect(), true), "%s utility rail overlaps Age/Build rail" % prefix)
	_expect(not action_panel.get_global_rect().intersects(selection.get_global_rect(), true), "%s utility rail overlaps command shelf" % prefix)

	# Placement is intentionally sparse, then restores the selected context when
	# the user cancels or completes the ghost placement.
	hud.call("set_placement_mode", true, "House")
	await get_tree().process_frame
	metrics = hud.get("mobile_layout_diagnostics")
	_expect(not selection.visible, "%s selection shelf remained during placement" % prefix)
	_expect(not minimap.visible, "%s minimap remained during placement" % prefix)
	_expect(not bottom_right.visible, "%s thumb rail remained during placement" % prefix)
	_expect(action_panel.visible, "%s placement Cancel is missing" % prefix)
	_expect_eq(int(metrics.get("action_rows", 0)), 1, "%s placement has more than one action" % prefix)
	_expect(action_panel.size.x <= 324.0, "%s placement buttons became a full-width bar" % prefix)
	var place_button: Button = hud.get("_placement_confirm_button") as Button
	_expect(place_button.visible and place_button.disabled, "%s invalid placement must expose a disabled Place button" % prefix)
	hud.call("update_placement_preview", true, "")
	_expect(not place_button.disabled, "%s valid preview does not enable Place" % prefix)
	hud.call("update_placement_preview", false, "Blocked ground")
	_expect(place_button.disabled, "%s blocked preview leaves Place enabled" % prefix)

	hud.call("set_placement_mode", false)
	await get_tree().process_frame
	_expect(selection.visible, "%s selection shelf was not restored after placement" % prefix)
	_expect(minimap.visible and bottom_right.visible, "%s standard HUD did not return after placement" % prefix)

	phone_viewport.free()
	await get_tree().process_frame


func _exercise_scaled_corridor(phone_size: Vector2i, ui_scale: float, notched: bool) -> void:
	# Window.content_scale_factor reduces the logical layout surface as UI grows.
	# Exercise that effective surface with real Controls, then convert gaps and
	# target sizes back to physical pixels for the acceptance checks.
	var logical_size := Vector2(
		floorf(float(phone_size.x) / ui_scale),
		floorf(float(phone_size.y) / ui_scale)
	)
	var phone_viewport := SubViewport.new()
	phone_viewport.size = Vector2i(logical_size)
	add_child(phone_viewport)
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	phone_viewport.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var safe_area := Rect2(Vector2.ZERO, logical_size)
	if notched:
		var side_inset: float = 44.0 / ui_scale
		var bottom_inset: float = 18.0 / ui_scale
		safe_area = Rect2(
			Vector2(side_inset, 0.0),
			Vector2(logical_size.x - side_inset * 2.0, logical_size.y - bottom_inset)
		)

	# Exercise the actual selection-action constructors.  Queue cancellation and
	# training coexist on production buildings; research replaces them on an
	# active Blacksmith.  This catches regressions that a same-sized placeholder
	# cannot, such as long labels, grouped queue buttons, and disabled research.
	var queue_items: Array = [
		{"unit_type": UnitData.UnitType.VILLAGER, "name": "Villager", "is_training": true, "progress": 0.42},
		{"unit_type": UnitData.UnitType.VILLAGER, "name": "Villager", "is_training": false},
		{"unit_type": UnitData.UnitType.SCOUT, "name": "Scout", "is_training": false},
	]
	var town_center := BuildingBase.new()
	town_center.building_type = BuildingData.BuildingType.TOWN_CENTER
	town_center.player_owner = 0
	town_center.state = BuildingBase.State.ACTIVE
	var production_queue := ProductionQueue.new()
	production_queue.auto_queue_unit_type = UnitData.UnitType.SCOUT
	town_center.add_child(production_queue)
	town_center.set_production_queue(production_queue)
	hud.call(
		"show_building_selection",
		"Town Center",
		5000,
		5000,
		queue_items,
		[UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT],
		town_center
	)
	hud.call("set_early_game_ui_state", false)
	hud.call("set_guided_military_shortcuts_visible", true)
	hud.call("update_villager_tasks", 2, 1, 1, 1)
	hud.call("update_idle_villager_count", 1)
	hud.call("update_military_count", 2)
	hud.call("apply_mobile_layout", logical_size, safe_area)
	await get_tree().process_frame
	await get_tree().process_frame
	hud.call("set_progression_hint", "Gather Food to train a Scout, then move onto the map.", false)
	hud.call("show_notification", "Population capped. Build a House before training another unit.", Color.WHITE)
	hud.call("update_sacred_site_timer", 1, 172.0, 180.0)
	await get_tree().process_frame
	await get_tree().process_frame
	# Deferred relayouts intentionally use the platform safe area. Reapply the
	# synthetic notch after those settle so this fixture audits the requested
	# profile rather than the headless display fallback.
	hud.call("apply_mobile_layout", logical_size, safe_area)
	await get_tree().process_frame
	hud.call("_refresh_touch_target_diagnostics")

	var minimap: ColorRect = hud.get_node("Root/MinimapBG") as ColorRect
	var selection: PanelContainer = hud.get_node("Root/SelectionPanel") as PanelContainer
	var bottom_right: VBoxContainer = hud.get_node("Root/BottomRight") as VBoxContainer
	var action_panel: PanelContainer = hud.get_node("Root/MobileActionPanel") as PanelContainer
	var game_controls: Control = hud.get_node("Root/GameControlButtons") as Control
	var age_button: Button = hud.get("age_up_button") as Button
	var build_button: Button = hud.get("build_menu_button") as Button
	var camera_controls: HBoxContainer = hud.get("_camera_controls") as HBoxContainer
	var metrics: Dictionary = hud.get("mobile_layout_diagnostics")
	var guidance: PanelContainer = hud.get("_progression_hint_panel") as PanelContainer
	var notifications: VBoxContainer = hud.get("_notification_container") as VBoxContainer
	var sacred_chip: PanelContainer = hud.get("_sacred_site_panel") as PanelContainer
	var top_bar: PanelContainer = hud.get_node("Root/TopBar") as PanelContainer
	var suffix := "%dx%d scale %.2f%s" % [phone_size.x, phone_size.y, ui_scale, " notched" if notched else ""]
	var touch_diagnostics: Dictionary = hud.get("touch_target_diagnostics")
	_assert_touch_target_group(
		touch_diagnostics.get("queue_cancel_buttons", []),
		4,
		ui_scale,
		"%s queue-cancel" % suffix
	)
	_assert_touch_target_group(
		touch_diagnostics.get("train_buttons", []),
		3,
		ui_scale,
		"%s train" % suffix
	)
	var command_scroll: ScrollContainer = hud.get("command_scroll") as ScrollContainer
	var train_row: HBoxContainer = hud.get("_train_buttons_container") as HBoxContainer
	_expect(command_scroll.scroll_horizontal == 0, "%s Town Center did not start at scroll0" % suffix)
	for button: Button in train_row.get_children():
		_expect(command_scroll.get_global_rect().encloses(button.get_global_rect()), "%s %s is clipped at initial scroll0: %s inside %s" % [suffix, button.name, button.get_global_rect(), command_scroll.get_global_rect()])
	_expect(bool(metrics.get("layout_pass", false)), "%s production-action layout reports overlap" % suffix)

	var blacksmith := BuildingBase.new()
	blacksmith.building_type = BuildingData.BuildingType.BLACKSMITH
	blacksmith.player_owner = 0
	blacksmith.state = BuildingBase.State.ACTIVE
	hud.call("show_building_selection", "Blacksmith", 1200, 1200, [], [], blacksmith)
	await get_tree().process_frame
	await get_tree().process_frame
	hud.call("apply_mobile_layout", logical_size, safe_area)
	await get_tree().process_frame
	hud.call("_refresh_touch_target_diagnostics")
	touch_diagnostics = hud.get("touch_target_diagnostics")
	metrics = hud.get("mobile_layout_diagnostics")
	_assert_touch_target_group(
		touch_diagnostics.get("research_buttons", []),
		4,
		ui_scale,
		"%s research" % suffix
	)
	_expect(bool(metrics.get("layout_pass", false)), "%s research-action layout reports overlap" % suffix)
	_selection_action_profiles_checked += 1
	blacksmith.free()
	town_center.free()

	_expect(bool(metrics.get("layout_pass", false)), "%s calculated layout reports overlap" % suffix)
	_expect(camera_controls.get_global_rect().position.x >= safe_area.position.x and camera_controls.get_global_rect().end.x <= safe_area.end.x, "%s camera controls leave safe area" % suffix)
	for button: Button in camera_controls.get_children():
		if button.visible:
			_expect(button.size.x * ui_scale >= MIN_TOUCH_TARGET and button.size.y * ui_scale >= MIN_TOUCH_TARGET, "%s visible view/zoom button is under48 physical px" % suffix)
	for other: Control in [minimap, selection, guidance, notifications, bottom_right, action_panel, sacred_chip]:
		_expect(not camera_controls.get_global_rect().intersects(other.get_global_rect(), true), "%s zoom controls overlap %s" % [suffix, other.name])
	_expect(not notifications.get_global_rect().intersects(guidance.get_global_rect(), true), "%s notification lane overlaps guidance" % suffix)
	_expect(
		(guidance.get_global_rect().position.x - notifications.get_global_rect().end.x) * ui_scale >= MIN_PHYSICAL_GAP - 0.5,
		"%s notification-to-guidance gap is under 8 physical px" % suffix
	)
	_expect((guidance.get_global_rect().position.y - top_bar.get_global_rect().end.y) * ui_scale >= MIN_PHYSICAL_GAP - 0.5, "%s top-to-guidance gap is under 8 physical px" % suffix)
	_expect((notifications.get_global_rect().position.y - top_bar.get_global_rect().end.y) * ui_scale >= MIN_PHYSICAL_GAP - 0.5, "%s top-to-notification gap is under 8 physical px" % suffix)
	_expect((sacred_chip.get_global_rect().position.y - guidance.get_global_rect().end.y) * ui_scale >= MIN_PHYSICAL_GAP - 0.5, "%s guidance-to-sacred gap is under 8 physical px" % suffix)
	_expect(not minimap.get_global_rect().intersects(selection.get_global_rect(), true), "%s minimap overlaps command shelf" % suffix)
	_expect(not selection.get_global_rect().intersects(bottom_right.get_global_rect(), true), "%s command shelf overlaps thumb rail" % suffix)
	_expect(not action_panel.get_global_rect().intersects(bottom_right.get_global_rect(), true), "%s utility rail overlaps thumb rail" % suffix)
	_expect(not action_panel.get_global_rect().intersects(selection.get_global_rect(), true), "%s utility rail overlaps command shelf" % suffix)
	_expect(not action_panel.get_global_rect().intersects(game_controls.get_global_rect(), true), "%s utility cluster overlaps pause/speed controls" % suffix)
	_expect(not action_panel.get_global_rect().intersects(guidance.get_global_rect(), true), "%s utility cluster overlaps guidance" % suffix)
	_expect(not action_panel.get_global_rect().intersects(sacred_chip.get_global_rect(), true), "%s utility cluster overlaps sacred timer" % suffix)
	_expect(
		(action_panel.get_global_rect().position.y - game_controls.get_global_rect().end.y) * ui_scale >= MIN_PHYSICAL_GAP - 0.5,
		"%s pause/speed-to-utility gap is under 8 physical px" % suffix
	)
	_expect(
		(action_panel.get_global_rect().position.y - guidance.get_global_rect().end.y) * ui_scale >= MIN_PHYSICAL_GAP - 0.5,
		"%s guidance-to-utility gap is under 8 physical px" % suffix
	)
	_expect(
		(action_panel.get_global_rect().position.y - sacred_chip.get_global_rect().end.y) * ui_scale >= MIN_PHYSICAL_GAP - 0.5,
		"%s sacred-timer-to-utility gap is under 8 physical px" % suffix
	)
	_expect(
		(selection.position.x - minimap.get_global_rect().end.x) * ui_scale >= MIN_PHYSICAL_GAP - 0.5,
		"%s minimap-to-shelf gap is under 8 physical px" % suffix
	)
	_expect(
		(bottom_right.position.x - selection.get_global_rect().end.x) * ui_scale >= MIN_PHYSICAL_GAP - 0.5,
		"%s shelf-to-thumb gap is under 8 physical px" % suffix
	)
	_expect(
		(bottom_right.position.y - action_panel.get_global_rect().end.y) * ui_scale >= MIN_PHYSICAL_GAP - 1.0,
		"%s utility-to-thumb gap is under 8 physical px" % suffix
	)
	_expect(age_button.size.y * ui_scale >= MIN_TOUCH_TARGET, "%s Age target is under 48 physical px" % suffix)
	_expect(build_button.size.y * ui_scale >= MIN_TOUCH_TARGET, "%s Build target is under 48 physical px" % suffix)
	for child: Node in hud.get("_mobile_action_strip").get_children():
		if child is Button and child.visible:
			_expect((child as Button).size.y * ui_scale >= MIN_TOUCH_TARGET, "%s utility target is under 48 physical px" % suffix)

	# Pause is a modal phone state too. Its content must center inside the safe
	# rectangle instead of inheriting a fixed desktop-sized center offset.
	hud.call("set_ui_modal_state", 2)
	await get_tree().process_frame
	await get_tree().process_frame
	hud.call("_layout_pause_menu", logical_size, safe_area)
	await get_tree().process_frame
	var pause_menu: VBoxContainer = hud.get("_pause_overlay").get_node("PauseMenu") as VBoxContainer
	var pause_rect: Rect2 = pause_menu.get_global_rect()
	_expect(pause_rect.position.x >= safe_area.position.x - 0.5, "%s pause menu enters the left safe inset" % suffix)
	_expect(pause_rect.position.y >= safe_area.position.y - 0.5, "%s pause menu enters the top safe inset" % suffix)
	_expect(pause_rect.end.x <= safe_area.end.x + 0.5, "%s pause menu enters the right safe inset" % suffix)
	_expect(pause_rect.end.y <= safe_area.end.y + 0.5, "%s pause menu %s enters bottom safe bound %.1f" % [suffix, pause_rect, safe_area.end.y])
	for button_name: String in ["ResumeButton", "SoundToggleButton", "QuitButton"]:
		var pause_button: Button = pause_menu.get_node(button_name) as Button
		_expect(pause_button.size.y * ui_scale >= MIN_TOUCH_TARGET, "%s %s is under 48 physical px" % [suffix, button_name])
		_expect(pause_button.size.x / maxf(1.0, pause_button.size.y) <= 4.0, "%s %s exceeds 4:1 touch aspect" % [suffix, button_name])
	hud.call("set_ui_modal_state", 0)

	phone_viewport.free()
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_touch_target_group(entries: Array, expected_count: int, ui_scale: float, label: String) -> void:
	_expect(entries.size() == expected_count, "%s controls missing (expected %d, got %d)" % [label, expected_count, entries.size()])
	for entry_variant: Variant in entries:
		if not (entry_variant is Dictionary):
			_expect(false, "%s diagnostics contain a non-dictionary entry" % label)
			continue
		var entry: Dictionary = entry_variant
		var target_name: String = String(entry.get("name", "unnamed"))
		_expect(bool(entry.get("visible", false)), "%s %s is not visible" % [label, target_name])
		_expect(
			float(entry.get("width", 0.0)) * ui_scale >= MIN_TOUCH_TARGET - 0.5,
			"%s %s is under 48 physical px wide" % [label, target_name]
		)
		_expect(
			float(entry.get("height", 0.0)) * ui_scale >= MIN_TOUCH_TARGET - 0.5,
			"%s %s is under 48 physical px tall" % [label, target_name]
		)
		_expect(
			float(entry.get("aspect_ratio", INF)) <= 4.0,
			"%s %s exceeds 4:1 touch aspect" % [label, target_name]
		)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
