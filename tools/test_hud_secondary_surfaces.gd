extends Node
## HUD lifecycle and actual GUI outside-contact routing, independent of Main's
## world dispatcher. The paid full-match journey covers command/economy effects.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
var _failures: Array[String] = []
var _profile_hud: CanvasLayer
var _profile_size: Vector2
var _profile_safe: Rect2

class WorldProbe extends Node:
	var contacts: int = 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			contacts += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	ResourceManager.initialize_player(0, {"food": 2000, "wood": 2000, "gold": 2000})
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _exercise(phone, scale, notched)
	for failure: String in _failures:
		push_error("[FAIL] hud_secondary_surfaces: " + failure)
	if _failures.is_empty():
		print("[PASS] hud_secondary_surfaces: 12 profiles, exclusive View/More/Queue/Info/Help/world popup, refresh/revision/modal lifecycle and retained outside contacts")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _exercise(phone: Vector2i, scale: float, notched: bool) -> void:
	var size := Vector2i(floori(phone.x / scale), floori(phone.y / scale))
	var view := SubViewport.new()
	view.size = size
	view.handle_input_locally = true
	add_child(view)
	var probe := WorldProbe.new()
	view.add_child(probe)
	var hud: CanvasLayer = HUD_SCENE.instantiate()
	view.add_child(hud)
	hud.connect("pause_requested", func() -> void:
		GameManager.set_paused(true)
		hud.call("set_ui_modal_state", 2))
	await _frames()
	var safe := Rect2(Vector2.ZERO, Vector2(size))
	if notched:
		var side: float = 44.0 / scale
		safe = Rect2(Vector2(side, 0), Vector2(size.x - side * 2, size.y - 18.0 / scale))
	_profile_hud = hud
	_profile_size = Vector2(size)
	_profile_safe = safe
	var tag := "%s %.3f notch=%s" % [phone, scale, notched]
	hud.call("set_selection_context_revision", 1)
	hud.call("show_unit_selection", "Scout", 110, 110, "Idle", 2, {"unit_type": UnitData.UnitType.SCOUT})
	hud.call("configure_unit_commands", true, true)
	hud.call("apply_mobile_layout", Vector2(size), safe)
	await _frames()
	await _click(view, hud.get("_camera_view_button") as Button)
	_expect(hud.call("get_secondary_surface_name") == "view", tag + " View did not open")
	await _click(view, hud.get("_camera_zoom_in_button") as Button)
	_expect(hud.call("get_secondary_surface_name") == "view", tag + " zoom collapsed View")
	await _click(view, hud.get("_camera_zoom_reset_button") as Button)
	_expect(hud.call("get_secondary_surface_name") == "none", tag + " Reset left View open")
	await _click(view, hud.get("_unit_more_button") as Button)
	_expect(hud.call("get_secondary_surface_name") == "more", tag + " normal More tap did not open")
	hud.call("show_unit_selection", "Scout", 100, 110, "Moving", 2, {"unit_type": UnitData.UnitType.SCOUT})
	hud.call("configure_unit_commands", true, true)
	hud.call("set_selection_context_revision", 1)
	_expect(hud.call("get_secondary_surface_name") == "more", tag + " routine unit refresh collapsed More")
	hud.call("set_selection_context_revision", 2)
	_expect(hud.call("get_secondary_surface_name") == "none", tag + " changed unit membership retained More")
	await _click(view, hud.get("_camera_view_button") as Button)
	await _click(view, hud.get("_unit_more_button") as Button)
	_expect(not bool(hud.get("_camera_controls_expanded")), tag + " More coexisted with View")
	hud.call("notify_world_gesture_started")
	_expect(hud.call("get_secondary_surface_name") == "none" and bool(hud.get("_selection_context_active")), tag + " world collapse lost selection")
	await _frames()
	await _click(view, hud.get("_selection_info_button") as Button)
	_expect(hud.call("get_secondary_surface_name") == "info", tag + " tap Info did not open")
	var info_panel: Control = hud.get("_info_panel") as Control
	_expect(safe.encloses(info_panel.get_global_rect()), tag + " Info escaped safe area")
	var card_area: Rect2 = hud.call("get_hold_safe_rect")
	_expect(card_area.encloses(info_panel.get_global_rect()) and info_panel.get_global_rect().position.y >= (hud.get("top_bar") as Control).get_global_rect().end.y + 8.0, tag + " Info obscures resource/objective rail")
	_expect((hud.call("get_world_occlusion_rects") as Array).has(info_panel.get_global_rect()), tag + " Info absent from camera obstacles")
	var before: int = probe.contacts
	var outside := Vector2(safe.position.x + 8, 90)
	await _touch(view, 41, outside, true)
	_expect(hud.call("get_secondary_surface_name") == "none", tag + " outside press did not close Info")
	await _drag(view, 41, outside + Vector2(30, 10))
	await _touch(view, 79, outside + Vector2(40, 0), true)
	await _touch(view, 41, outside + Vector2(30, 10), false)
	await _touch(view, 79, outside + Vector2(40, 0), false)
	_expect(probe.contacts == before, tag + " blocking dismissal leaked a press/drag/release into world")
	hud.call("_toggle_hotkey_panel")
	await _frames()
	var help: Control = hud.get("_hotkey_panel") as Control
	_expect(safe.encloses(help.get_global_rect()), tag + " Help escaped safe area")
	_expect(card_area.encloses(help.get_global_rect()), tag + " Help obscures resource/objective rail")
	_expect(hud.call("close_secondary_surface") == true, tag + " Escape API did not close Help")
	_expect(hud.call("close_secondary_surface") == false, tag + " collapsed state still consumed Escape")
	hud.call("begin_world_context")
	hud.call("set_world_context_rect", Rect2(Vector2(220, 80), Vector2(180, 100)))
	_expect(hud.call("get_secondary_surface_name") == "world_context", tag + " world popup did not register")
	hud.call("set_ui_modal_state", 2)
	_expect(hud.call("get_secondary_surface_name") == "none", tag + " Pause retained world popup")
	_expect(not bool(hud.call("begin_world_context")), tag + " popup overrode Pause")
	hud.call("set_ui_modal_state", 0)
	_expect(hud.call("get_secondary_surface_name") == "none", tag + " resume restored transient popup")
	var producer := BuildingBase.new()
	producer.building_type = BuildingData.BuildingType.TOWN_CENTER
	producer.player_owner = 0
	producer.state = BuildingBase.State.ACTIVE
	view.add_child(producer)
	var production := ProductionQueue.new()
	producer.add_child(production)
	var items: Array = [{"unit_type": UnitData.UnitType.VILLAGER, "name": "Villager", "is_training": true, "progress": 0.2}, {"unit_type": UnitData.UnitType.SCOUT, "name": "Scout", "is_training": false}]
	hud.call("show_building_selection", "Town Center", 5000, 5000, items, [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT], producer)
	hud.call("apply_mobile_layout", Vector2(size), safe)
	await _frames()
	await _click(view, hud.get("_camera_view_button") as Button)
	await _click(view, hud.get("_queue_navigation_button") as Button)
	_expect(hud.call("get_secondary_surface_name") == "queue" and not bool(hud.get("_camera_controls_expanded")), tag + " Queue coexisted with View")
	hud.call("show_building_selection", "Town Center", 4990, 5000, items, [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT], producer)
	await _frames()
	_expect(hud.call("get_secondary_surface_name") == "queue", tag + " producer refresh collapsed Queue")
	GameManager.hold_shortcuts_enabled = false
	await _click(view, hud.get("_selection_info_button") as Button)
	var body: String = (hud.get("_info_body") as Label).text
	var train: Button = (hud.get("_train_buttons_container") as Control).get_node("TrainButton_0")
	var train_info: Dictionary = (train.get_meta("hud_hold_control") as Node).call("get_info")
	var repeat_info: Dictionary = hud.call("_repeat_information")
	_expect(body.contains(str(train_info.body)), tag + " tap Info omitted full Train inspection")
	_expect(body.contains(str(repeat_info.body)), tag + " tap Info omitted Repeat cost/wait inspection")
	_expect(body.contains("Refunds the full paid resource cost and releases reserved population."), tag + " tap Info omitted refund inspection")
	_expect(safe.encloses(info_panel.get_global_rect()), tag + " long producer Info escaped safe area")
	hud.call("close_secondary_surface")
	# Add a later modal sibling to exercise native GUI order, rather than merely
	# checking draw z-order. Both Info Close and outside shield must win its hit.
	var palette_probe := Button.new()
	palette_probe.size = Vector2(size)
	var palette_presses: Array[int] = [0]
	palette_probe.pressed.connect(func() -> void: palette_presses[0] += 1)
	hud.add_child(palette_probe)
	hud.call("set_ui_modal_state", 1)
	var card_info := {"title": "Locked building", "body": "Cost: 150 wood\nProvides cavalry production.\nRequires Feudal Age."}
	hud.call("show_card_information", card_info)
	await _frames()
	_expect(hud.call("get_secondary_surface_name") == "info" and int(hud.get("_ui_modal_state")) == 1, tag + " Build tap Info closed/rejected Build modal")
	_expect((hud.get("_info_body") as Label).text == card_info.body, tag + " Build tap Info omitted cost/effect/requirements")
	var info_close: Button = info_panel.find_child("InfoCloseButton", true, false) as Button
	_expect(info_close.size.x >= 48 and info_close.size.y >= 48 and safe.encloses(info_close.get_global_rect()), tag + " Info Close lost48px/reachability")
	await _click(view, info_close)
	_expect(hud.call("get_secondary_surface_name") == "none" and int(hud.get("_ui_modal_state")) == 1 and palette_presses[0] == 0, tag + " Info Close hit underlying Build modal")
	hud.call("show_card_information", card_info)
	before = probe.contacts
	await _touch(view, 51, outside, true)
	await _drag(view, 51, outside + Vector2(30, 10))
	await _touch(view, 51, outside + Vector2(30, 10), false)
	_expect(hud.call("get_secondary_surface_name") == "none" and int(hud.get("_ui_modal_state")) == 1 and palette_presses[0] == 0 and probe.contacts == before, tag + " Build Info outside dismissal leaked/closed Build")
	palette_probe.hide()
	hud.call("show_card_information", card_info)
	await _frames()
	before = probe.contacts
	await _native_touch_tap(view, hud.get("_pause_button") as Button, 52)
	_expect(GameManager.current_state == GameManager.GameState.PAUSED and int(hud.get("_ui_modal_state")) == 2 and hud.call("get_secondary_surface_name") == "none", tag + " Pause did not supersede Build Info on first tap")
	_expect(probe.contacts == before and palette_presses[0] == 0, tag + " Pause from Build Info leaked world/modal action")
	GameManager.set_paused(false)
	palette_probe.queue_free()
	hud.call("set_ui_modal_state", 0)
	GameManager.hold_shortcuts_enabled = true
	await _click(view, hud.get("_queue_navigation_button") as Button)
	hud.call("notify_world_gesture_started")
	_expect(hud.call("get_secondary_surface_name") == "none" and (hud.get("command_scroll") as ScrollContainer).scroll_horizontal == 0, tag + " world admission did not return Queue to Train")
	# Drain the existing deferred queue-restoration/layout work before destroying
	# the isolated viewport; normal Main retains this HUD during field play.
	for drain: int in 3:
		await _frames()
	_profile_hud = null
	view.free()
	await _frames()


func _click(view: SubViewport, button: Button) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		view.push_input(event, true)
		await _frames()


func _touch(view: SubViewport, index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	view.push_input(event, true)
	await _frames()


func _native_touch_tap(view: SubViewport, button: Button, index: int) -> void:
	# push_input does not synthesize the root Input API's emulated mouse pair;
	# dispatch both native halves to verify shield ScreenTouch and Button routing.
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.position = point
		touch.pressed = pressed
		view.push_input(touch, true)
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.position = point
		mouse.pressed = pressed
		view.push_input(mouse, true)
		await _frames()


func _drag(view: SubViewport, index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	event.relative = Vector2(30, 10)
	view.push_input(event, true)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# DisplayServer cannot report a synthetic SubViewport notch. Reapply the
	# fixture's device bounds after deferred refreshes, as the full journey does.
	if is_instance_valid(_profile_hud):
		_profile_hud.call("apply_mobile_layout", _profile_size, _profile_safe)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
