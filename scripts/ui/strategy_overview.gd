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
signal sacred_rally_requested(building: Node2D)
signal farm_requested()
signal save_group_requested(index: int)
signal recall_group_requested(index: int)

const SOURCES: PackedStringArray = ["idle", "food", "wood", "gold"]
const RESOURCES: PackedStringArray = ["food", "wood", "gold"]
const RAIL_BUTTON_SIZE := CommandIcons.TARGET_SIZE
const RAIL_GAP := CommandIcons.GAP
const RAIL_WIDTH := RAIL_BUTTON_SIZE * 3.0 + RAIL_GAP * 2.0
const JOB_CHIP_WIDTH := 96.0
const JOB_CHIP_MIN_WIDTH := 80.0
const TRAIN_CARD_WIDTH := 156.0
const SHEET_MAX_WIDTH := 480.0
var rail: HBoxContainer
var panel: PanelContainer
var _title: Label
var _scroll: ScrollContainer
var _economy: VBoxContainer
var _army: VBoxContainer
var _summary: Label
var _economy_health: Label
var _food_stock: Label
var _farm_blocker: Label
var _farm_button: Button
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
var _sheet_width: float = SHEET_MAX_WIDTH


func _ready() -> void:
	theme = KingdomTheme.create_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail = HBoxContainer.new()
	rail.name = "StrategyRail"
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_theme_constant_override("separation", int(RAIL_GAP))
	add_child(rail)
	var base := _icon_button("base", "Base: select and view your Town Center", "BaseButton", RAIL_BUTTON_SIZE)
	base.custom_minimum_size.y = RAIL_BUTTON_SIZE
	base.pressed.connect(func() -> void: base_requested.emit())
	rail.add_child(base)
	_economy_button = _icon_button("economy", "Economy: manage workers and paid production", "EconomyButton", RAIL_BUTTON_SIZE)
	_economy_button.custom_minimum_size.y = RAIL_BUTTON_SIZE
	_economy_button.toggle_mode = true
	_economy_button.pressed.connect(func() -> void: surface_requested.emit("" if _surface == "economy" else "economy"))
	rail.add_child(_economy_button)
	_army_button = _icon_button("army", "Army: select units and manage two groups", "ArmyButton", RAIL_BUTTON_SIZE)
	_army_button.custom_minimum_size.y = RAIL_BUTTON_SIZE
	_army_button.toggle_mode = true
	_army_button.pressed.connect(func() -> void: surface_requested.emit("" if _surface == "army" else "army"))
	rail.add_child(_army_button)
	panel = PanelContainer.new()
	panel.name = "StrategyPanel"
	panel.z_index = 60
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Header, padding and exhausted scroll gestures belong to the sheet.
	panel.mouse_force_pass_scroll_events = false
	panel.add_theme_stylebox_override("panel", KingdomTheme.panel_style(KingdomTheme.INK_PANEL, KingdomTheme.BORDER, 8))
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
	var close := _icon_button("close", "Close management panel", "CloseStrategyButton", 48)
	close.pressed.connect(func() -> void: surface_requested.emit(""))
	header.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.name = "StrategyScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	_scroll.gui_input.connect(_on_gui_contact)
	body.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_economy = VBoxContainer.new()
	_economy.add_theme_constant_override("separation", int(CommandIcons.GAP))
	content.add_child(_economy)
	_build_economy()
	_army = VBoxContainer.new()
	_army.add_theme_constant_override("separation", int(CommandIcons.GAP))
	content.add_child(_army)
	_build_army()
	set_surface("")


func _button(text: String, control_name: String, width: float = 96.0) -> Button:
	var button := Button.new()
	# Icon decoration captures styles before this button joins the scene tree.
	button.theme = theme
	button.name = control_name
	button.text = text
	button.custom_minimum_size = Vector2(width, CommandIcons.TARGET_SIZE)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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


func _icon_button(key: String, label: String, control_name: String, width: float = 88.0, caption: String = "") -> Button:
	var button := _button(caption, control_name, width)
	CommandIcons.apply(button, key, label, caption)
	return button


func _build_economy() -> void:
	_summary = _label("Workers: Food 0 · Wood 0 · Gold 0")
	_economy.add_child(_summary)
	_economy_health = _label("", 13)
	_economy_health.name = "EconomyHealth"
	_economy.add_child(_economy_health)
	_food_stock = _label("", 12)
	_food_stock.name = "FoodStock"
	_economy.add_child(_food_stock)
	_economy.add_child(_label("Move one worker: choose a current job, then a destination."))
	var sources := HBoxContainer.new()
	sources.add_theme_constant_override("separation", 6)
	_economy.add_child(sources)
	for resource: String in SOURCES:
		var button := _icon_button(resource, "Workers currently on " + resource, "Source_" + resource, JOB_CHIP_WIDTH, resource.capitalize())
		button.toggle_mode = true
		button.pressed.connect(_choose_source.bind(resource))
		_source_buttons[resource] = button
		sources.add_child(button)
	var destinations := HBoxContainer.new()
	destinations.add_theme_constant_override("separation", 6)
	_economy.add_child(destinations)
	for resource: String in RESOURCES:
		var button := _icon_button(resource, "Move one worker to " + resource, "Assign_" + resource, JOB_CHIP_WIDTH, "To\n" + resource.capitalize())
		button.pressed.connect(func() -> void: allocation_requested.emit(_source, resource))
		_destination_buttons[resource] = button
		destinations.add_child(button)
	_idle_button = _icon_button("idle", "Select the next idle worker", "FindIdleButton", JOB_CHIP_WIDTH, "Find\nidle")
	_idle_button.pressed.connect(func() -> void: idle_requested.emit())
	destinations.add_child(_idle_button)
	_feedback = _label("Cargo first; builders and recovering workers keep their orders.", 12)
	_feedback.add_theme_color_override("font_color", KingdomTheme.MUTED)
	_economy.add_child(_feedback)
	var farm_row := HBoxContainer.new()
	farm_row.add_theme_constant_override("separation", int(CommandIcons.GAP))
	_economy.add_child(farm_row)
	_farm_button = _icon_button("farm", "Plan a paid Farm with finite food", "PlanFarm", TRAIN_CARD_WIDTH, "Farm · 75W\n300 finite food")
	_farm_button.pressed.connect(func() -> void: farm_requested.emit())
	farm_row.add_child(_farm_button)
	_farm_blocker = _label("", 12)
	_farm_blocker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	farm_row.add_child(_farm_blocker)
	_population = _label("")
	_economy.add_child(_population)
	_economy.add_child(_label("Paid production", 15))
	_producer_list = VBoxContainer.new()
	_producer_list.add_theme_constant_override("separation", 8)
	_economy.add_child(_producer_list)


func _build_army() -> void:
	_army.add_child(_label("Save your selection. Recall selects it again."))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(CommandIcons.GAP))
	_army.add_child(actions)
	_select_army_button = _icon_button("army", "Select every military unit", "SelectAllArmy", 120, "Select all")
	_select_army_button.pressed.connect(func() -> void: army_requested.emit())
	actions.add_child(_select_army_button)
	_focus_army_button = _icon_button("find", "Find and view your army", "FindArmy", 120, "Find army")
	_focus_army_button.pressed.connect(func() -> void: army_focus_requested.emit())
	actions.add_child(_focus_army_button)
	for index: int in [1, 2]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(CommandIcons.GAP))
		_army.add_child(row)
		var label := _label("Group %d · empty" % index)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var save := _icon_button("group_save", "Save current selection to group %d" % index, "SaveGroup%d" % index, 104, "Save")
		save.pressed.connect(func() -> void: save_group_requested.emit(index))
		row.add_child(save)
		var recall := _icon_button("group_recall", "Recall group %d. Then open Camera and choose Center to view the group." % index, "RecallGroup%d" % index, 104, "Recall")
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
			warnings.append("No " + resource + " workers")
	var idle: int = int(workers.get("idle", 0))
	var military: int = int(snapshot.get("military", 0))
	var economy: Dictionary = snapshot.get("economy", {})
	var attention: String = str(economy.get("attention", ""))
	var economy_description := "Economy: manage workers and paid production"
	if not warnings.is_empty():
		economy_description += "\n" + "; ".join(warnings)
	if not attention.is_empty():
		economy_description += "\n" + attention
	if int(economy.get("severity", 0)) > 0:
		economy_description += "\n%s\n%s" % [str(economy.get("title", "")), str(economy.get("detail", ""))]
	CommandIcons.apply(_economy_button, "economy", economy_description)
	CommandIcons.set_badge(_economy_button, "!" if not warnings.is_empty() or not attention.is_empty() else "", true)
	CommandIcons.apply(_army_button, "army", "Army: %d military units. Select units and manage two groups." % military)
	CommandIcons.set_badge(_army_button, str(military))
	var worker_count: int = 0
	for amount: Variant in workers.values():
		worker_count += int(amount)
	_summary.text = "%d workers · %d building · %d recovering" % [worker_count, int(workers.get("build", 0)), int(workers.get("recovering", 0))]
	_summary.add_theme_color_override("font_color", KingdomTheme.PARCHMENT if warnings.is_empty() else KingdomTheme.AMBER)
	_economy_health.text = ""
	if int(economy.get("severity", 0)) > 0:
		_economy_health.text = "%s\n%s" % [str(economy.get("title", "")), str(economy.get("detail", ""))]
	if not warnings.is_empty():
		_economy_health.text += ("\n" if not _economy_health.text.is_empty() else "") + " · ".join(warnings)
	_economy_health.visible = not _economy_health.text.is_empty()
	_economy_health.add_theme_color_override("font_color", KingdomTheme.AMBER if int(economy.get("severity", 0)) > 0 else KingdomTheme.PARCHMENT)
	_food_stock.text = str(economy.get("stock", ""))
	_farm_blocker.text = str(snapshot.get("farm_blocker", ""))
	var farm_wood: int = int(BuildingData.get_building_cost(BuildingData.BuildingType.FARM).get("wood", 75))
	CommandIcons.apply(_farm_button, "farm", "Plan a Farm: costs %d wood and provides %d finite food. Rebuild when exhausted. %s" % [farm_wood, BuildingData.FARM_FOOD_AMOUNT, _farm_blocker.text], "Farm · %dW\n%d finite food" % [farm_wood, BuildingData.FARM_FOOD_AMOUNT])
	_farm_button.disabled = not bool(snapshot.get("can_plan_farm", false))
	_population.text = str(snapshot.get("population_text", ""))
	CommandIcons.apply(_idle_button, "idle", "Find the next of %d idle workers" % idle, "Find\nidle")
	_idle_button.disabled = idle <= 0
	_select_army_button.disabled = military <= 0
	_focus_army_button.disabled = military <= 0
	_refresh_allocation_buttons()
	_refresh_producers(snapshot.get("producers", []))
	_fit_economy_rows(_sheet_width)
	var counts: Dictionary = snapshot.get("groups", {})
	for index: int in [1, 2]:
		var row: Dictionary = _group_rows[index]
		var count: int = int(counts.get(index, 0))
		var member_name: String = "members" if bool((snapshot.get("group_has_buildings", {}) as Dictionary).get(index, false)) else "units"
		(row.label as Label).text = "Group %d · %s" % [index, "%d %s" % [count, member_name] if count > 0 else "empty"]
		(row.save as Button).disabled = int(snapshot.get("selection_count", 0)) <= 0
		(row.recall as Button).disabled = count <= 0


func _refresh_allocation_buttons() -> void:
	var workers: Dictionary = _snapshot.get("workers", {})
	for resource: String in SOURCES:
		var button: Button = _source_buttons[resource]
		var count: int = int(workers.get(resource, 0))
		button.set_pressed_no_signal(resource == _source)
		if resource == _source:
			KingdomTheme.apply_primary(button)
		else:
			KingdomTheme.apply_secondary(button)
		CommandIcons.apply(button, resource, "%s: %d workers. Choose this current job before assigning one worker." % [resource.capitalize(), count], "%s\n%d" % [resource.capitalize(), count])
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
		apply_repeat_caption(repeat_button, repeat_type, bool(producer.get("repeat_enabled", false)))
		repeat_button.set_pressed_no_signal(bool(producer.get("repeat_enabled", false)))
		repeat_button.disabled = repeat_type < 0 or not bool(producer.get("active", false))
		(row.undo as Button).disabled = queue.is_empty()
		(row.clear as Button).disabled = queue.is_empty() and not bool(producer.get("repeat_enabled", false))
		(row.rally as Button).disabled = int(_snapshot.get("selected_military", 0)) <= 0 or not bool(producer.get("active", false))
		(row.sacred as Button).disabled = not bool(producer.get("sacred_available", false)) or not bool(producer.get("active", false))
		(row.rally_status as Label).text = str(producer.get("rally_status", ""))
		row["queue_size"] = queue.size()
		for unit_type: int in row.train:
			var button: Button = row.train[unit_type]
			button.disabled = not bool(producer.get("active", false))
			var blocker: String = str((producer.get("unit_status", {}) as Dictionary).get(unit_type, ""))
			button.tooltip_text = "%s\n%s" % [button.text, blocker.capitalize()]
			var status_label: Label = row.train_status[unit_type]
			var role: String = "Gather & build" if unit_type == UnitData.UnitType.VILLAGER else UnitData.get_unit_counter_description(unit_type)
			status_label.text = role if blocker == "ready" else blocker.capitalize()
			status_label.add_theme_color_override("font_color", KingdomTheme.MUTED if blocker == "ready" else KingdomTheme.AMBER)
	for id: int in _producer_rows.keys():
		if id not in live_ids:
			var card: Control = _producer_rows[id].card
			card.visible = false
			card.queue_free()
			_producer_rows.erase(id)


static func apply_repeat_caption(button: Button, unit_type: int, enabled: bool) -> void:
	var state: String = "ON" if enabled else "OFF"
	var full_name: String = UnitData.get_unit_name(unit_type) if unit_type >= 0 else "Train first"
	# The recruitment card and accessible action retain the full unit name.
	var caption: String = "Siege" if unit_type == UnitData.UnitType.SIEGE else full_name
	CommandIcons.apply(button, "repeat", "Repeat %s: %s. Each training order is paid." % [full_name, state], "%s\n%s" % [caption, state])


func _create_producer(producer: Dictionary) -> void:
	var building: Node2D = producer.building
	var id: int = building.get_instance_id()
	var card := PanelContainer.new()
	card.name = "Producer_%d" % id
	card.add_theme_stylebox_override("panel", KingdomTheme.panel_style(KingdomTheme.INK, KingdomTheme.BORDER, 8))
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
	var train_status: Dictionary = {}
	for unit_type: int in producer.get("trainable", []):
		var cost: Dictionary = UnitData.get_unit_cost(unit_type)
		var costs: PackedStringArray = []
		for resource: String in RESOURCES:
			if int(cost.get(resource, 0)) > 0:
				costs.append("%d%s" % [int(cost[resource]), resource.left(1).to_upper()])
		var unit_card := VBoxContainer.new()
		unit_card.custom_minimum_size.x = TRAIN_CARD_WIDTH
		unit_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		training.add_child(unit_card)
		var button := _button("%s\n%s" % [UnitData.get_unit_name(unit_type), " ".join(costs)], "Train_%d" % unit_type, TRAIN_CARD_WIDTH)
		button.add_theme_font_size_override("font_size", 12)
		var portrait_path: String = UnitData.get_unit_icon_path(unit_type)
		if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
			button.icon = load(portrait_path)
			button.add_theme_constant_override("icon_max_width", int(CommandIcons.GLYPH_SIZE))
			button.expand_icon = false
		button.pressed.connect(func() -> void:
			if is_instance_valid(building):
				training_requested.emit(building, unit_type))
		unit_card.add_child(button)
		train_buttons[unit_type] = button
		var unit_status := _label("", 12)
		unit_status.name = "TrainingStatus_%d" % unit_type
		unit_card.add_child(unit_status)
		train_status[unit_type] = unit_status
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	content.add_child(actions)
	var repeat_button := _icon_button("repeat", "Repeat paid training while resources and population room allow", "Repeat", 120, "Repeat\nOFF")
	repeat_button.toggle_mode = true
	repeat_button.toggled.connect(func(enabled: bool) -> void:
		if is_instance_valid(building):
			repeat_requested.emit(building, enabled))
	actions.add_child(repeat_button)
	var undo := _icon_button("undo", "Refund the last paid unit", "UndoLast", 120, "Undo\nlast")
	undo.tooltip_text = "Refund the last paid unit and its population reservation. Repeat keeps its current setting."
	undo.pressed.connect(func() -> void:
		if is_instance_valid(building) and _producer_rows.has(id):
			cancellation_requested.emit(building, int(_producer_rows[id].queue_size) - 1))
	actions.add_child(undo)
	var clear := _icon_button("clear", "Stop Repeat and refund all queued units", "ClearAndStop", 120, "Clear\n& stop")
	clear.tooltip_text = "Stop Repeat and refund every paid unit and reserved population slot."
	clear.pressed.connect(func() -> void:
		if is_instance_valid(building):
			cancellation_requested.emit(building, ProductionQueue.CANCEL_ALL_INDEX))
	actions.add_child(clear)
	var rally_status := _label("", 12)
	rally_status.name = "RallyStatus"
	content.add_child(rally_status)
	var rallies := HBoxContainer.new()
	rallies.add_theme_constant_override("separation", 6)
	content.add_child(rallies)
	var rally := _icon_button("rally", "Rally future recruits to the selected army", "RallyToArmy", TRAIN_CARD_WIDTH, "Rally to army")
	rally.tooltip_text = "Send future trained units to the selected army’s current location. Existing units keep their orders."
	rally.pressed.connect(func() -> void:
		if is_instance_valid(building):
			rally_requested.emit(building))
	rallies.add_child(rally)
	var sacred := _icon_button("sacred", "Rally future recruits to the Sacred Site", "RallyToSacred", TRAIN_CARD_WIDTH, "Rally to Sacred")
	sacred.tooltip_text = "All future recruits go to the public Sacred location. Existing units keep their orders."
	sacred.pressed.connect(func() -> void:
		if is_instance_valid(building):
			sacred_rally_requested.emit(building))
	rallies.add_child(sacred)
	_producer_rows[id] = {"card": card, "status": status, "paid": paid, "repeat": repeat_button, "undo": undo, "clear": clear, "rally": rally, "sacred": sacred, "rally_status": rally_status, "train": train_buttons, "train_status": train_status, "queue_size": 0}


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
	_economy_button.set_pressed_no_signal(surface == "economy")
	_army_button.set_pressed_no_signal(surface == "army")
	if changed:
		_scroll.scroll_vertical = 0


func apply_layout(safe: Rect2, field_visible: bool, card_area: Rect2, dock_height: float = 72.0) -> void:
	rail.visible = field_visible
	var rail_bottom: float = safe.end.y - dock_height - 16.0
	rail.position = Vector2(safe.end.x - RAIL_WIDTH - 8.0, rail_bottom - RAIL_BUTTON_SIZE)
	rail.size = Vector2(RAIL_WIDTH, RAIL_BUTTON_SIZE)
	# The sheet leaves its launchers reachable for switching and tap-to-collapse.
	var card_left: float = card_area.position.x + 8.0
	var card_right: float = minf(card_area.end.x - 8.0, rail.position.x - 8.0)
	_sheet_width = minf(SHEET_MAX_WIDTH, card_right - card_left)
	_fit_economy_rows(_sheet_width)
	var card_height: float = minf(310.0, card_area.size.y - 16.0)
	if _surface == "army":
		# Three action rows and their short instruction determine the Army height;
		# safe-area constraints can still scroll the contents on a narrow profile.
		# Two pixels absorb container rounding at fractional interface scales.
		var content_height: float = _army.get_combined_minimum_size().y
		card_height = minf(card_height, content_height + CommandIcons.TARGET_SIZE + 14.0)
	var card_size := Vector2(_sheet_width, card_height)
	var centered: Vector2 = card_area.position + (card_area.size - card_size) * 0.5
	panel.position = Vector2(clampf(centered.x, card_left, card_right - card_size.x), centered.y)
	panel.size = card_size
	panel.visible = field_visible and _surface in ["economy", "army"]


func _fit_economy_rows(sheet_width: float) -> void:
	# Reserve the real scroll bar even before it becomes visible. Reflow widths
	# before sizing the panel, so a stale child minimum cannot enlarge the sheet.
	var panel_padding: float = panel.get_theme_stylebox("panel").get_minimum_size().x
	var scroll_width: float = _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var content_width: float = sheet_width - panel_padding - scroll_width
	var chip_width: float = clampf(floorf((content_width - CommandIcons.GAP * 3.0) / 4.0), JOB_CHIP_MIN_WIDTH, JOB_CHIP_WIDTH)
	for button: Button in _source_buttons.values():
		button.custom_minimum_size.x = chip_width
	for button: Button in _destination_buttons.values():
		button.custom_minimum_size.x = chip_width
	_idle_button.custom_minimum_size.x = chip_width
	for row: Dictionary in _producer_rows.values():
		var producer: PanelContainer = row.card
		var inner_padding: float = producer.get_theme_stylebox("panel").get_minimum_size().x
		var action_width: float = minf(120.0, floorf((content_width - inner_padding - CommandIcons.GAP * 2.0) / 3.0))
		for button: Button in [row.repeat, row.undo, row.clear]:
			button.custom_minimum_size.x = maxf(CommandIcons.TARGET_SIZE, action_width)


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
