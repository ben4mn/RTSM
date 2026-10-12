class_name StrategyOverview
extends Control
## Selection-independent, paid economy/production and two deliberate army groups.
## All mutations are requests: the controller revalidates current ownership/state.

signal surface_requested(surface: String)
signal world_gesture_cancel_requested()
signal base_requested()
signal army_requested()
signal army_focus_requested()
signal idle_requested()
signal allocation_requested(source: String, destination: String)
signal training_requested(building: Node2D, unit_type: int)
signal cancellation_requested(building: Node2D, index: int)
signal repeat_requested(building: Node2D, enabled: bool)
signal rally_requested(building: Node2D)
signal save_group_requested(index: int)
signal recall_group_requested(index: int)

const SOURCES: PackedStringArray = ["idle", "food", "wood", "gold"]
const RESOURCES: PackedStringArray = ["food", "wood", "gold"]
var rail: HBoxContainer
var panel: PanelContainer
var _title: Label
var _scroll: ScrollContainer
var _economy: VBoxContainer
var _army: VBoxContainer
var _summary: Label
var _population: Label
var _feedback: Label
var _source_buttons: Dictionary = {}
var _destination_buttons: Dictionary = {}
var _producer_list: VBoxContainer
var _producer_rows: Dictionary = {}
var _group_rows: Dictionary = {}
var _economy_button: Button
var _army_button: Button
var _idle_button: Button
var _select_army_button: Button
var _focus_army_button: Button
var _source: String = "idle"
var _surface: String = ""
var _snapshot: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail = HBoxContainer.new()
	rail.name = "StrategyRail"
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_theme_constant_override("separation", 6)
	add_child(rail)
	var base := _button("Base", "BaseButton", 64)
	base.tooltip_text = "Select and view your Town Center"
	base.pressed.connect(func() -> void: base_requested.emit())
	rail.add_child(base)
	_economy_button = _button("Economy", "EconomyButton", 88)
	_economy_button.tooltip_text = "Staff workers and train reinforcements without changing selection"
	_economy_button.pressed.connect(func() -> void: surface_requested.emit("" if _surface == "economy" else "economy"))
	rail.add_child(_economy_button)
	_army_button = _button("Army", "ArmyButton", 72)
	_army_button.tooltip_text = "Select your army or save and recall two groups"
	_army_button.pressed.connect(func() -> void: surface_requested.emit("" if _surface == "army" else "army"))
	rail.add_child(_army_button)
	panel = PanelContainer.new()
	panel.name = "StrategyPanel"
	panel.z_index = 60
	panel.visible = false
	panel.add_theme_stylebox_override("panel", KingdomTheme.panel_style())
	panel.gui_input.connect(_on_gui_contact)
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	_title = _label("Economy & production", 16)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := _button("Close", "CloseStrategyButton", 72)
	close.pressed.connect(func() -> void: surface_requested.emit(""))
	header.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.name = "StrategyScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.gui_input.connect(_on_gui_contact)
	body.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_economy = VBoxContainer.new()
	_economy.add_theme_constant_override("separation", 7)
	content.add_child(_economy)
	_build_economy()
	_army = VBoxContainer.new()
	_army.add_theme_constant_override("separation", 8)
	content.add_child(_army)
	_build_army()
	set_surface("")


func _button(text: String, control_name: String, width: float = 96.0) -> Button:
	var button := Button.new()
	button.name = control_name
	button.text = text
	button.custom_minimum_size = Vector2(width, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	KingdomTheme.apply_secondary(button)
	button.gui_input.connect(_on_gui_contact)
	return button


func _label(text: String, font_size: int = 13) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_economy() -> void:
	_summary = _label("Workers: Food 0 · Wood 0 · Gold 0")
	_economy.add_child(_summary)
	_population = _label("")
	_economy.add_child(_population)
	_economy.add_child(_label("Move one worker: choose their current job, then a destination."))
	var sources := HBoxContainer.new()
	sources.add_theme_constant_override("separation", 6)
	_economy.add_child(sources)
	for resource: String in SOURCES:
		var button := _button(resource.capitalize(), "Source_" + resource)
		button.toggle_mode = true
		button.pressed.connect(_choose_source.bind(resource))
		_source_buttons[resource] = button
		sources.add_child(button)
	var destinations := HBoxContainer.new()
	destinations.add_theme_constant_override("separation", 6)
	_economy.add_child(destinations)
	for resource: String in RESOURCES:
		var button := _button("To " + resource, "Assign_" + resource)
		button.pressed.connect(func() -> void: allocation_requested.emit(_source, resource))
		_destination_buttons[resource] = button
		destinations.add_child(button)
	_idle_button = _button("Find idle", "FindIdleButton", 104)
	_idle_button.pressed.connect(func() -> void: idle_requested.emit())
	destinations.add_child(_idle_button)
	_feedback = _label("Cargo is delivered before switching resources. Builders and recovering workers keep their orders.", 12)
	_feedback.add_theme_color_override("font_color", KingdomTheme.MUTED)
	_economy.add_child(_feedback)
	_economy.add_child(_label("Production · each training order is paid", 15))
	_producer_list = VBoxContainer.new()
	_producer_list.add_theme_constant_override("separation", 8)
	_economy.add_child(_producer_list)


func _build_army() -> void:
	_army.add_child(_label("Save your selection to a group, then recall it from anywhere. Use View, then Center after recalling to follow the group."))
	var actions := HBoxContainer.new()
	_army.add_child(actions)
	_select_army_button = _button("Select all army", "SelectAllArmy", 144)
	_select_army_button.pressed.connect(func() -> void: army_requested.emit())
	actions.add_child(_select_army_button)
	_focus_army_button = _button("Find army", "FindArmy", 112)
	_focus_army_button.pressed.connect(func() -> void: army_focus_requested.emit())
	actions.add_child(_focus_army_button)
	for index: int in [1, 2]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_army.add_child(row)
		var label := _label("Group %d · empty" % index)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var save := _button("Save selection", "SaveGroup%d" % index, 128)
		save.pressed.connect(func() -> void: save_group_requested.emit(index))
		row.add_child(save)
		var recall := _button("Recall", "RecallGroup%d" % index)
		recall.pressed.connect(func() -> void: recall_group_requested.emit(index))
		row.add_child(recall)
		_group_rows[index] = {"label": label, "save": save, "recall": recall}


func _choose_source(resource: String) -> void:
	_source = resource
	_refresh_allocation_buttons()


func update_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	var workers: Dictionary = snapshot.get("workers", {})
	var warnings: PackedStringArray = []
	for resource: String in RESOURCES:
		if int(workers.get(resource, 0)) == 0:
			warnings.append("No " + resource)
	var idle: int = int(workers.get("idle", 0))
	var military: int = int(snapshot.get("military", 0))
	_economy_button.text = "Economy\nF%d W%d G%d" % [int(workers.get("food", 0)), int(workers.get("wood", 0)), int(workers.get("gold", 0))] if warnings.is_empty() else "Economy\n" + warnings[0] + "!"
	_economy_button.tooltip_text = "; ".join(warnings) if not warnings.is_empty() else "Manage workers and paid production"
	if warnings.is_empty():
		KingdomTheme.apply_secondary(_economy_button)
	else:
		KingdomTheme.apply_primary(_economy_button)
	_army_button.text = "Army %d" % military
	_summary.text = "Food %d · Wood %d · Gold %d · Idle %d · Recovering %d · Building %d" % [int(workers.get("food", 0)), int(workers.get("wood", 0)), int(workers.get("gold", 0)), idle, int(workers.get("recovering", 0)), int(workers.get("build", 0))]
	if not warnings.is_empty():
		_summary.text += "\n" + " · ".join(warnings) + " workers — reassign below."
	_summary.add_theme_color_override("font_color", KingdomTheme.PARCHMENT if warnings.is_empty() else KingdomTheme.AMBER)
	_population.text = str(snapshot.get("population_text", ""))
	_idle_button.text = "Find idle %d" % idle
	_idle_button.disabled = idle <= 0
	_select_army_button.disabled = military <= 0
	_focus_army_button.disabled = military <= 0
	_refresh_allocation_buttons()
	_refresh_producers(snapshot.get("producers", []))
	var counts: Dictionary = snapshot.get("groups", {})
	for index: int in [1, 2]:
		var row: Dictionary = _group_rows[index]
		var count: int = int(counts.get(index, 0))
		(row.label as Label).text = "Group %d · %s" % [index, "%d selected members" % count if count > 0 else "empty"]
		(row.save as Button).disabled = int(snapshot.get("selection_count", 0)) <= 0
		(row.recall as Button).disabled = count <= 0


func _refresh_allocation_buttons() -> void:
	var workers: Dictionary = _snapshot.get("workers", {})
	for resource: String in SOURCES:
		var button: Button = _source_buttons[resource]
		button.text = "%s %d" % [resource.capitalize(), int(workers.get(resource, 0))]
		button.set_pressed_no_signal(resource == _source)
		if resource == _source:
			KingdomTheme.apply_primary(button)
		else:
			KingdomTheme.apply_secondary(button)
	for resource: String in RESOURCES:
		(_destination_buttons[resource] as Button).disabled = resource == _source or int(workers.get(_source, 0)) <= 0


func _refresh_producers(producers: Array) -> void:
	var live_ids: Array[int] = []
	for producer: Dictionary in producers:
		var building: Node2D = producer.get("building")
		if not is_instance_valid(building):
			continue
		var id: int = building.get_instance_id()
		live_ids.append(id)
		if not _producer_rows.has(id):
			_create_producer(producer)
		var row: Dictionary = _producer_rows[id]
		(row.status as Label).text = str(producer.get("status", ""))
		var queue: Array = producer.get("queue", [])
		(row.paid as Label).text = "Paid queue: " + (" / ".join(queue) if not queue.is_empty() else "empty")
		var repeat_type: int = int(producer.get("repeat_type", -1))
		var repeat_button: Button = row.repeat
		repeat_button.text = "Repeat %s\n%s" % ["ON" if bool(producer.get("repeat_enabled", false)) else "OFF", UnitData.get_unit_name(repeat_type) if repeat_type >= 0 else "Train first"]
		repeat_button.set_pressed_no_signal(bool(producer.get("repeat_enabled", false)))
		repeat_button.disabled = repeat_type < 0 or not bool(producer.get("active", false))
		(row.undo as Button).disabled = queue.is_empty()
		(row.clear as Button).disabled = queue.is_empty() and not bool(producer.get("repeat_enabled", false))
		(row.rally as Button).disabled = int(_snapshot.get("selected_military", 0)) <= 0 or not bool(producer.get("active", false))
		row["queue_size"] = queue.size()
		for unit_type: int in row.train:
			var button: Button = row.train[unit_type]
			button.disabled = not bool(producer.get("active", false))
			button.tooltip_text = str((producer.get("unit_status", {}) as Dictionary).get(unit_type, ""))
	for id: int in _producer_rows.keys():
		if id not in live_ids:
			var card: Control = _producer_rows[id].card
			card.visible = false
			card.queue_free()
			_producer_rows.erase(id)


func _create_producer(producer: Dictionary) -> void:
	var building: Node2D = producer.building
	var id: int = building.get_instance_id()
	var card := PanelContainer.new()
	card.name = "Producer_%d" % id
	card.add_theme_stylebox_override("panel", KingdomTheme.panel_style(KingdomTheme.INK))
	_producer_list.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	card.add_child(content)
	var status := _label("")
	content.add_child(status)
	var paid := _label("", 12)
	content.add_child(paid)
	var training := HBoxContainer.new()
	training.add_theme_constant_override("separation", 6)
	content.add_child(training)
	var train_buttons: Dictionary = {}
	for unit_type: int in producer.get("trainable", []):
		var cost: Dictionary = UnitData.get_unit_cost(unit_type)
		var costs: PackedStringArray = []
		for resource: String in RESOURCES:
			if int(cost.get(resource, 0)) > 0:
				costs.append("%d%s" % [int(cost[resource]), resource.left(1).to_upper()])
		var button := _button("+ %s\n%s" % [UnitData.get_unit_name(unit_type), " ".join(costs)], "Train_%d" % unit_type, 104)
		button.pressed.connect(func() -> void:
			if is_instance_valid(building):
				training_requested.emit(building, unit_type))
		training.add_child(button)
		train_buttons[unit_type] = button
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	content.add_child(actions)
	var repeat_button := _button("Repeat OFF", "Repeat", 120)
	repeat_button.toggle_mode = true
	repeat_button.toggled.connect(func(enabled: bool) -> void:
		if is_instance_valid(building):
			repeat_requested.emit(building, enabled))
	actions.add_child(repeat_button)
	var undo := _button("Undo last", "UndoLast", 104)
	undo.tooltip_text = "Refund the last paid unit and its population reservation. Repeat keeps its current setting."
	undo.pressed.connect(func() -> void:
		if is_instance_valid(building) and _producer_rows.has(id):
			cancellation_requested.emit(building, int(_producer_rows[id].queue_size) - 1))
	actions.add_child(undo)
	var clear := _button("Clear & stop", "ClearAndStop", 120)
	clear.tooltip_text = "Stop Repeat and refund every paid unit and reserved population slot."
	clear.pressed.connect(func() -> void:
		if is_instance_valid(building):
			cancellation_requested.emit(building, ProductionQueue.CANCEL_ALL_INDEX))
	actions.add_child(clear)
	var rally := _button("Rally to army", "RallyToArmy", 120)
	rally.tooltip_text = "Send future trained units to the selected army’s current location. Existing units keep their orders."
	rally.pressed.connect(func() -> void:
		if is_instance_valid(building):
			rally_requested.emit(building))
	actions.add_child(rally)
	_producer_rows[id] = {"card": card, "status": status, "paid": paid, "repeat": repeat_button, "undo": undo, "clear": clear, "rally": rally, "train": train_buttons, "queue_size": 0}


func show_feedback(message: String, success: bool = true) -> void:
	_feedback.text = message
	_feedback.add_theme_color_override("font_color", KingdomTheme.TEAL if success else KingdomTheme.AMBER)


func set_surface(surface: String) -> void:
	var changed: bool = _surface != surface
	_surface = surface
	panel.visible = surface in ["economy", "army"]
	_economy.visible = surface == "economy"
	_army.visible = surface == "army"
	_title.text = "Economy & production" if surface == "economy" else "Army & groups"
	if changed:
		_scroll.scroll_vertical = 0


func apply_layout(safe: Rect2, field_visible: bool, card_area: Rect2) -> void:
	rail.visible = field_visible
	rail.position = Vector2(safe.end.x - 244.0, safe.end.y - 136.0)
	rail.size = Vector2(236, 48)
	var card_size := Vector2(minf(560.0, card_area.size.x - 16.0), minf(310.0, card_area.size.y - 16.0))
	panel.position = card_area.position + (card_area.size - card_size) * 0.5
	panel.size = card_size
	panel.visible = field_visible and _surface in ["economy", "army"]


func get_visible_bounds() -> Array[Rect2]:
	var bounds: Array[Rect2] = []
	if rail.is_visible_in_tree():
		bounds.append(rail.get_global_rect())
	if panel.is_visible_in_tree():
		bounds.append(panel.get_global_rect())
	return bounds


func _on_gui_contact(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		world_gesture_cancel_requested.emit()


func set_attention(action: String, pulse: float) -> void:
	_economy_button.modulate = Color(1.0, pulse, 0.62) if action == "idle_button" else Color.WHITE
	_army_button.modulate = Color(1.0, pulse, 0.62) if action == "military_button" else Color.WHITE
