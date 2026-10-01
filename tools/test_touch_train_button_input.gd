extends Node
## Regression for touchscreen activation of dynamic building-command buttons
## in the horizontally scrollable mobile command shelf.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PHONE_SIZE := Vector2i(844, 390)

var _failures: Array[String] = []
var _emitted_unit_type: int = -1
var _cancelled_queue_index: int = -1
var _emitted_research_id: String = ""
var _clear_button_survived_signal: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var viewport := SubViewport.new()
	viewport.size = PHONE_SIZE
	viewport.handle_input_locally = true
	add_child(viewport)
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	viewport.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var town_center := BuildingBase.new()
	town_center.building_type = BuildingData.BuildingType.TOWN_CENTER
	town_center.player_owner = 0
	town_center.state = BuildingBase.State.ACTIVE
	viewport.add_child(town_center)
	var queue_items: Array = [
		{"unit_type": UnitData.UnitType.VILLAGER, "name": "Villager", "is_training": true, "progress": 0.25},
		{"unit_type": UnitData.UnitType.VILLAGER, "name": "Villager", "is_training": false},
		{"unit_type": UnitData.UnitType.SCOUT, "name": "Scout", "is_training": false},
	]
	hud.train_unit_requested.connect(func(_building: Node2D, unit_type: int) -> void:
		_emitted_unit_type = unit_type
	)
	hud.cancel_queue_requested.connect(func(_building: Node2D, queue_index: int) -> void:
		_cancelled_queue_index = queue_index
	)
	hud.research_requested.connect(func(_building: Node2D, research_id: String) -> void:
		_emitted_research_id = research_id
	)
	hud.call(
		"show_building_selection",
		"Town Center",
		5000,
		5000,
		queue_items,
		[UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT],
		town_center
	)
	hud.call("apply_mobile_layout", Vector2(PHONE_SIZE), Rect2(Vector2.ZERO, Vector2(PHONE_SIZE)))
	await get_tree().process_frame
	await get_tree().process_frame

	# Rebuild the controls through the same pause/resume route used by the MCP
	# phone gate. Recruiting stays at the start of the shelf ahead of the queue.
	hud.call("set_ui_modal_state", 2)
	await get_tree().process_frame
	hud.call("set_ui_modal_state", 0)
	await get_tree().process_frame
	await get_tree().process_frame

	var command_scroll: ScrollContainer = hud.get("command_scroll") as ScrollContainer
	command_scroll.scroll_horizontal = 0
	await get_tree().process_frame
	hud.call("_refresh_touch_target_diagnostics")

	var train_container: HBoxContainer = hud.get("_train_buttons_container") as HBoxContainer
	var button_name := "TrainButton_%s" % str(UnitData.UnitType.SCOUT)
	var scout_button: Button = train_container.get_node_or_null(button_name) as Button
	_expect(scout_button != null, "Scout train button is missing after pause/resume rebuild")
	if scout_button != null:
		_expect(not scout_button.disabled, "Scout train button remains disabled after resume")
		_expect(scout_button.is_visible_in_tree(), "Scout train button remains hidden after resume")
		var button_diag: Dictionary = _find_button_diag(hud.get("touch_target_diagnostics"), button_name)
		_expect(not button_diag.is_empty(), "Scout train button diagnostics are missing")
		if not button_diag.is_empty():
			var reported_rect := Rect2(
				Vector2(float(button_diag.get("x", -1.0)), float(button_diag.get("y", -1.0))),
				Vector2(float(button_diag.get("width", 0.0)), float(button_diag.get("height", 0.0)))
			)
			var actual_rect: Rect2 = scout_button.get_global_rect()
			_expect(
				reported_rect.position.distance_to(actual_rect.position) <= 0.5,
				"reported train-button origin %s does not match scrolled global origin %s" % [reported_rect.position, actual_rect.position]
			)
			await _tap(viewport, reported_rect.get_center(), func() -> void:
				# The match refreshes selected-building progress every 0.5 s. A
				# refresh between press and release must not replace the button that
				# owns this active pointer gesture.
				hud.call(
					"show_building_selection",
					"Town Center",
					5000,
					5000,
					queue_items,
					[UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT],
					town_center
				)
			)
			_expect_eq(_emitted_unit_type, UnitData.UnitType.SCOUT, "touch at reported train-button center")

	# A grouped queue button survives the same mid-gesture refresh. Reorder the
	# underlying queue while held to ensure its release resolves the new index,
	# rather than an index captured when the Button was first constructed.
	var queue_container: HBoxContainer = hud.get("queue_container") as HBoxContainer
	hud.call("show_building_selection", "Town Center", 5000, 5000, queue_items, [], town_center)
	await get_tree().process_frame
	await get_tree().process_frame
	var queue_button_name := "QueueUnit_%s" % str(UnitData.UnitType.SCOUT)
	var queue_button: Button = queue_container.get_node_or_null(queue_button_name) as Button
	_expect(queue_button != null, "grouped Scout queue button is missing")
	if queue_button != null:
		command_scroll.ensure_control_visible(queue_button)
		await get_tree().process_frame
		var queue_button_id: int = queue_button.get_instance_id()
		var reordered_queue_items: Array = [
			{"unit_type": UnitData.UnitType.VILLAGER, "name": "Villager", "is_training": true, "progress": 0.3},
			{"unit_type": UnitData.UnitType.SCOUT, "name": "Scout", "is_training": false},
			{"unit_type": UnitData.UnitType.VILLAGER, "name": "Villager", "is_training": false},
		]
		await _tap(viewport, queue_button.get_global_rect().get_center(), func() -> void:
			hud.call(
				"show_building_selection",
				"Town Center",
				5000,
				5000,
				reordered_queue_items,
				[],
				town_center
			)
		)
		var refreshed_queue_button: Button = queue_container.get_node_or_null(queue_button_name) as Button
		_expect(
			refreshed_queue_button != null and refreshed_queue_button.get_instance_id() == queue_button_id,
			"grouped Scout queue button instance changed during refresh"
		)
		_expect_eq(_cancelled_queue_index, 1, "grouped queue touch resolves the current Scout index")

	# Reconcile empty and populated states in one frame. The retired instance must
	# vacate the canonical name without leaving the tree, and the replacement must
	# be uniquely addressable before end-of-frame deletion.
	var retiring_scout_button: Button = queue_container.get_node_or_null(queue_button_name) as Button
	hud.call("show_building_selection", "Town Center", 5000, 5000, [], [], town_center)
	_expect(retiring_scout_button != null and retiring_scout_button.is_inside_tree(), "retired queue control detached synchronously")
	_expect(
		retiring_scout_button != null and String(retiring_scout_button.name).begins_with("RetiredControl_"),
		"retired queue control kept its canonical name"
	)
	hud.call("show_building_selection", "Town Center", 5000, 5000, queue_items, [], town_center)
	var replacement_scout_button: Button = queue_container.get_node_or_null(queue_button_name) as Button
	_expect(replacement_scout_button != null, "same-frame reconciliation did not create a canonical replacement")
	_expect(
		replacement_scout_button != null and retiring_scout_button != null
		and replacement_scout_button.get_instance_id() != retiring_scout_button.get_instance_id(),
		"same-frame reconciliation reused a queued control"
	)
	var canonical_name_count: int = 0
	for child: Node in queue_container.get_children():
		if String(child.name) == queue_button_name:
			canonical_name_count += 1
	_expect_eq(canonical_name_count, 1, "same-frame canonical queue control count")
	await get_tree().process_frame

	# Clearing the queue synchronously refreshes the HUD in the real match. The
	# pressed Button must stay in the tree until BaseButton finishes dispatching
	# the release event, then it may be freed at the end of the frame.
	hud.call("show_building_selection", "Town Center", 5000, 5000, queue_items, [], town_center)
	await get_tree().process_frame
	var clear_button: Button = queue_container.get_node_or_null("QueueClearAllButton") as Button
	_expect(clear_button != null, "Clear queue button is missing")
	if clear_button != null:
		command_scroll.ensure_control_visible(clear_button)
		await get_tree().process_frame
		hud.cancel_queue_requested.connect(func(_building: Node2D, _queue_index: int) -> void:
			hud.call("show_building_selection", "Town Center", 5000, 5000, [], [], town_center)
			_clear_button_survived_signal = clear_button.is_inside_tree()
		, CONNECT_ONE_SHOT)
		await _tap(viewport, clear_button.get_global_rect().get_center())
		_expect(_clear_button_survived_signal, "Clear queue button left the SceneTree during its pressed signal")
		_expect(not is_instance_valid(clear_button), "retired Clear queue button was not freed after input dispatch")

	# Research buttons use the same stable lifecycle while their DONE/disabled
	# presentation remains refreshable.
	var blacksmith := BuildingBase.new()
	blacksmith.building_type = BuildingData.BuildingType.BLACKSMITH
	blacksmith.player_owner = 0
	blacksmith.state = BuildingBase.State.ACTIVE
	viewport.add_child(blacksmith)
	hud.call("show_building_selection", "Blacksmith", 1200, 1200, [], [], blacksmith)
	await get_tree().process_frame
	await get_tree().process_frame
	var research_container: HBoxContainer = hud.get("_research_container") as HBoxContainer
	var forging_button: Button = research_container.get_node_or_null("ResearchButton_forging") as Button
	_expect(forging_button != null, "Forging research button is missing")
	if forging_button != null:
		command_scroll.ensure_control_visible(forging_button)
		await get_tree().process_frame
		var forging_button_id: int = forging_button.get_instance_id()
		await _tap(viewport, forging_button.get_global_rect().get_center(), func() -> void:
			hud.call("show_building_selection", "Blacksmith", 1200, 1200, [], [], blacksmith)
		)
		var refreshed_forging_button: Button = research_container.get_node_or_null("ResearchButton_forging") as Button
		_expect(
			refreshed_forging_button != null and refreshed_forging_button.get_instance_id() == forging_button_id,
			"Forging research button instance changed during refresh"
		)
		_expect_eq(_emitted_research_id, "forging", "research touch after mid-gesture refresh")

	viewport.free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[PASS] touch_train_button_input: train, queue, clear, and research controls survive synchronous HUD refresh")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] touch_train_button_input: %s" % failure)
	get_tree().quit(1)


func _find_button_diag(touch_diag: Dictionary, button_name: String) -> Dictionary:
	for entry: Variant in touch_diag.get("train_buttons", []):
		if entry is Dictionary and String((entry as Dictionary).get("name", "")) == button_name:
			return (entry as Dictionary).duplicate(true)
	return {}


func _tap(viewport: SubViewport, position: Vector2, during_press: Callable = Callable()) -> void:
	# Input.parse_input_event (used by the MCP bridge) performs touch-to-mouse
	# emulation before routing. Push the equivalent local primary-pointer events
	# here so the headless SubViewport exercises the same Control path.
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.position = position
	down.global_position = position
	down.pressed = true
	viewport.push_input(down, true)
	await get_tree().process_frame
	if during_press.is_valid():
		during_press.call()
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.button_mask = 0
	up.position = position
	up.global_position = position
	up.pressed = false
	viewport.push_input(up, true)
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
