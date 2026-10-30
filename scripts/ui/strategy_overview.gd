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
signal trader_requested()
signal allocation_requested(source: String, destination: String)
signal training_requested(building: Node2D, unit_type: int)
signal cancellation_requested(building: Node2D, index: int)
signal repeat_requested(building: Node2D, enabled: bool)
signal rally_requested(building: Node2D)
signal sacred_rally_requested(building: Node2D)
signal farm_requested()
signal barracks_requested()
signal save_group_requested(index: int)
signal recall_group_requested(index: int)

const SOURCES: PackedStringArray = ["idle", "food", "wood", "gold"]
const RESOURCES: PackedStringArray = ["food", "wood", "gold"]
const RAIL_BUTTON_SIZE := CommandIcons.TARGET_SIZE
const RAIL_GAP := CommandIcons.GAP
const RAIL_WIDTH := RAIL_BUTTON_SIZE * 3.0 + RAIL_GAP * 2.0
const ACTION_TILE := preload("res://scripts/ui/compact_action_tile.gd")
const JOB_CHIP_WIDTH := 64.0
const JOB_CHIP_MIN_WIDTH := 54.0
const TRAIN_CARD_WIDTH := 84.0
const SHEET_MAX_WIDTH := 300.0
var rail: HBoxContainer
var panel: PanelContainer
var _title: Label
var _header: HBoxContainer
var _scroll: ScrollContainer
var _economy: VBoxContainer
var _army: VBoxContainer
var _army_notes: VBoxContainer
var _first_army_note_icon: TextureRect
var _first_army_note_title: Label
var _first_army_note_body: Label
var _summary: Label
var _economy_health: Label
var _food_stock: Label
var _farm_blocker: Label
var _farm_button: Button
var _trade_actions: HBoxContainer
var _trader_button: Button
var _population: Label
var _feedback: Label
var _feedback_until_msec: int = 0
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
var _production_page: bool = false
var _army_recruit_page: bool = true
var _army_page_initialized: bool = false
var _page_layout_signature: String = ""
var _producer_index: int = 0
var _army_producer_index: int = 0
var _economy_producer_id: int = 0
var _army_producer_id: int = 0
var _workers_tab: Button
var _production_tab: Button
var _recruit_tab: Button
var _groups_tab: Button
var _recruit_empty: VBoxContainer
var _barracks_button: Button
var _barracks_blocker: Label
var _previous_producer: Button
var _next_producer: Button
var _info_button: Button
var _details: VBoxContainer
var _detail_lines: Array[Label] = []
var _details_page: bool = false
var _last_panel_minimum := Vector2(-1.0, -1.0)


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
	CommandIcons.apply(base, "base", base.accessibility_name)
	_economy_button = _icon_button("economy", "Economy: manage workers and paid production", "EconomyButton", RAIL_BUTTON_SIZE)
	_economy_button.custom_minimum_size.y = RAIL_BUTTON_SIZE
	_economy_button.toggle_mode = true
	_economy_button.pressed.connect(func() -> void: surface_requested.emit("" if _surface == "economy" else "economy"))
	rail.add_child(_economy_button)
	CommandIcons.apply(_economy_button, "economy", _economy_button.accessibility_name)
	_army_button = _icon_button("army", "Army: recruit fighters and manage two groups", "ArmyButton", RAIL_BUTTON_SIZE)
	_army_button.custom_minimum_size.y = RAIL_BUTTON_SIZE
	_army_button.toggle_mode = true
	_army_button.pressed.connect(func() -> void: surface_requested.emit("" if _surface == "army" else "army"))
	rail.add_child(_army_button)
	CommandIcons.apply(_army_button, "army", _army_button.accessibility_name)
	panel = PanelContainer.new()
	panel.name = "StrategyPanel"
	panel.z_index = 60
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Header, padding and exhausted scroll gestures belong to the sheet.
	panel.mouse_force_pass_scroll_events = false
	panel.add_theme_stylebox_override("panel", FieldStyle.surface(16))
	panel.gui_input.connect(_on_gui_contact)
	add_child(panel)
	panel.minimum_size_changed.connect(_on_panel_minimum_changed)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	panel.add_child(body)
	var header := HBoxContainer.new()
	_header = header
	header.add_theme_constant_override("separation", 2)
	body.add_child(header)
	_title = _label("Economy & production", 16)
	KingdomTheme.apply_heading(_title, 16)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_workers_tab = _button("Workers", "WorkersTab", 76)
	_workers_tab.toggle_mode = true
	_workers_tab.pressed.connect(func() -> void: _set_production_page(false))
	header.add_child(_workers_tab)
	_production_tab = _button("Train", "ProductionTab", 58)
	_production_tab.toggle_mode = true
	_production_tab.pressed.connect(func() -> void: _set_production_page(true))
	header.add_child(_production_tab)
	_recruit_tab = _button("Recruit", "RecruitTab", 68)
	_recruit_tab.toggle_mode = true
	_recruit_tab.pressed.connect(func() -> void: _set_army_recruit_page(true))
	header.add_child(_recruit_tab)
	_groups_tab = _button("Groups", "GroupsTab", 66)
	_groups_tab.toggle_mode = true
	_groups_tab.pressed.connect(func() -> void: _set_army_recruit_page(false))
	header.add_child(_groups_tab)
	_previous_producer = _button("‹", "PreviousProducer", 48)
	_previous_producer.add_theme_font_size_override("font_size", 28)
	_previous_producer.tooltip_text = "Previous production building"
	_previous_producer.accessibility_name = _previous_producer.tooltip_text
	_previous_producer.pressed.connect(func() -> void: _step_producer(-1))
	header.add_child(_previous_producer)
	_next_producer = _button("›", "NextProducer", 48)
	_next_producer.add_theme_font_size_override("font_size", 28)
	_next_producer.tooltip_text = "Next production building"
	_next_producer.accessibility_name = _next_producer.tooltip_text
	_next_producer.pressed.connect(func() -> void: _step_producer(1))
	header.add_child(_next_producer)
	_info_button = _icon_button("info", "Show current worker or producer details", "StrategyInfo", 48)
	_info_button.toggle_mode = true
	_info_button.pressed.connect(func() -> void:
		_details_page = not _details_page
		_refresh_pages())
	header.add_child(_info_button)
	var close := _icon_button("close", "Close management panel", "CloseStrategyButton", 48)
	close.pressed.connect(func() -> void: surface_requested.emit(""))
	header.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.name = "StrategyScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	_trade_actions = HBoxContainer.new()
	_trade_actions.name = "TradeActions"
	header.add_child(_trade_actions)
	_trader_button = _icon_button("find", "Find your traders", "FindTrader", 48)
	_trader_button.icon = load(UnitData.get_unit_icon_path(UnitData.UnitType.TRADER, 0))
	_trader_button.add_theme_constant_override("icon_max_width", 36)
	_trader_button.pressed.connect(func() -> void: trader_requested.emit())
	_trade_actions.add_child(_trader_button)
	_recruit_empty = VBoxContainer.new()
	_recruit_empty.name = "RecruitEmpty"
	_recruit_empty.add_theme_constant_override("separation", 8)
	content.add_child(_recruit_empty)
	var recruit_heading: Label = _label("Build your first fighting force", 18)
	KingdomTheme.apply_heading(recruit_heading, 18)
	_recruit_empty.add_child(recruit_heading)
	_recruit_empty.add_child(_label("A Barracks trains Warriors. Scouts explore but cannot fight."))
	_barracks_button = _icon_button("build", "Plan a paid Barracks", "PlanBarracks", 200, "Build Barracks · 120W")
	_barracks_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_barracks_button.pressed.connect(func() -> void: barracks_requested.emit())
	_recruit_empty.add_child(_barracks_button)
	_barracks_blocker = _label("", 12)
	_barracks_blocker.add_theme_color_override("font_color", KingdomTheme.MUTED)
	_recruit_empty.add_child(_barracks_blocker)
	_army = VBoxContainer.new()
	_army.add_theme_constant_override("separation", int(CommandIcons.GAP))
	content.add_child(_army)
	_build_army()
	_army_notes = VBoxContainer.new()
	_army_notes.name = "ArmyFieldNotes"
	_army_notes.add_theme_constant_override("separation", 12)
	content.add_child(_army_notes)
	_build_army_notes()
	_details = VBoxContainer.new()
	_details.name = "StrategyDetails"
	_details.add_theme_constant_override("separation", 4)
	content.add_child(_details)
	for index: int in range(8):
		var line := _label("", 13)
		line.name = "Detail%d" % index
		_details.add_child(line)
		_detail_lines.append(line)
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
	for state: String in ["hover_pressed", "focus"]:
		button.add_theme_stylebox_override(state, theme.get_stylebox(state, "Button").duplicate())
	FieldStyle.soften(button, 10, true)
	button.gui_input.connect(_on_gui_contact)
	return button


func _attach_repeat(button: Button, action: Callable) -> void:
	var hold := HUDHoldControl.attach_to(button, self, func() -> Dictionary: return {}, func() -> Variant: return [_surface, _source])
	hold.repeat_action = action
	hold.admission_provider = func() -> bool: return panel.visible and GameManager.current_state == GameManager.GameState.PLAYING
	hold.ownership_started.connect(func(_contact: int) -> void: world_gesture_cancel_requested.emit())


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
	_summary.max_lines_visible = 1
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_economy.add_child(_summary)
	_economy_health = _label("", 13)
	_economy_health.name = "EconomyHealth"
	_economy.add_child(_economy_health)
	_food_stock = _label("", 12)
	_food_stock.name = "FoodStock"
	_economy.add_child(_food_stock)
	_summary.tooltip_text = "Choose a current job, then a destination to move one worker."
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
		var button := _icon_button(resource, "Move one worker to " + resource, "Assign_" + resource, JOB_CHIP_WIDTH, "+")
		button.pressed.connect(func() -> void: allocation_requested.emit(_source, resource))
		_destination_buttons[resource] = button
		destinations.add_child(button)
		_attach_repeat(button, func() -> bool:
			if button.disabled: return false
			allocation_requested.emit(_source, resource)
			return true)
	_idle_button = _icon_button("idle", "Select the next idle worker", "FindIdleButton", JOB_CHIP_WIDTH, "")
	_idle_button.pressed.connect(func() -> void: idle_requested.emit())
	destinations.add_child(_idle_button)
	_feedback = _label("", 12)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_OFF
	_feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_feedback.add_theme_color_override("font_color", KingdomTheme.MUTED)
	_economy.add_child(_feedback)
	var farm_row := HBoxContainer.new()
	farm_row.add_theme_constant_override("separation", int(CommandIcons.GAP))
	_economy.add_child(farm_row)
	_farm_button = _icon_button("farm", "Plan a paid permanent Farm", "PlanFarm", TRAIN_CARD_WIDTH, "75")
	_farm_button.pressed.connect(func() -> void: farm_requested.emit())
	_workers_tab.get_parent().add_child(_farm_button)
	_workers_tab.get_parent().move_child(_farm_button, 2)
	_farm_blocker = _label("", 12)
	_farm_blocker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	farm_row.add_child(_farm_blocker)
	_population = _label("")
	_economy.add_child(_population)

	_producer_list = VBoxContainer.new()
	_producer_list.add_theme_constant_override("separation", 8)
	_economy.add_child(_producer_list)


func _build_army() -> void:
	# Group buttons carry accessible names; keep three action rows visible.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(CommandIcons.GAP))
	_army.add_child(actions)
	_select_army_button = _icon_button("army", "Select all armed fighters. Scouts keep their own orders.", "SelectAllArmy", 120, "")
	_select_army_button.pressed.connect(func() -> void: army_requested.emit())
	actions.add_child(_select_army_button)
	_focus_army_button = _icon_button("find", "View your fighters. Scouts keep exploring independently.", "FindArmy", 120, "")
	_focus_army_button.pressed.connect(func() -> void: army_focus_requested.emit())
	actions.add_child(_focus_army_button)
	for index: int in [1, 2]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(CommandIcons.GAP))
		_army.add_child(row)
		var label := _label("Group %d · empty" % index)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var save := _icon_button("group_save", "Save current selection to group %d" % index, "SaveGroup%d" % index, 48, "")
		save.pressed.connect(func() -> void: save_group_requested.emit(index))
		row.add_child(save)
		var recall := _icon_button("group_recall", "Recall group %d. Then open Camera and choose Center to view the group." % index, "RecallGroup%d" % index, 48, "")
		recall.pressed.connect(func() -> void: recall_group_requested.emit(index))
		row.add_child(recall)
		_group_rows[index] = {"label": label, "save": save, "recall": recall}


func _build_army_notes() -> void:
	# A deliberate Info page: tactics stay available without another field banner.
	var notes: Array[Dictionary] = [
		{"icon": "move", "title": "01  Assemble", "body": "Tap ground to assemble. Let Warriors catch up with cavalry."},
		{"icon": "attack", "title": "02  Commit together", "body": "Tap the swords, then ground to attack-move. Hold ground to add a movement waypoint."},
		{"icon": "rally", "title": "03  Preserve your army", "body": "Tap safe ground to withdraw. Rally fresh recruits nearby."},
	]
	for note: Dictionary in notes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_army_notes.add_child(row)
		var icon := TextureRect.new()
		icon.texture = CommandIcons.get_icon(note.icon)
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.modulate = KingdomTheme.TEAL
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 2)
		row.add_child(copy)
		var heading: Label = _label(note.title, 18)
		heading.add_theme_font_override("font", KingdomTheme.FONT_MEDIUM)
		copy.add_child(heading)
		var body: Label = _label(note.body, 13)
		body.add_theme_color_override("font_color", KingdomTheme.MUTED)
		copy.add_child(body)
		if _first_army_note_body == null:
			_first_army_note_icon = icon
			_first_army_note_title = heading
			_first_army_note_body = body


func _choose_source(resource: String) -> void:
	if _source != resource:
		_clear_feedback()
	_source = resource
	_refresh_allocation_buttons()


func update_snapshot(snapshot: Dictionary) -> void:
	var traders: int = int(snapshot.get("traders", 0))
	var waiting: int = int(snapshot.get("waiting_traders", 0))
	_trader_button.disabled = traders == 0
	_trader_button.tooltip_text = "Find %d traders · %d paused or waiting. Tap to cycle; no orders changed." % [traders, waiting]
	_trader_button.accessibility_name = _trader_button.tooltip_text
	CommandIcons.set_badge(_trader_button, str(traders) if traders < 100 else "99+", waiting > 0)
	if _feedback_until_msec > 0 and Time.get_ticks_msec() >= _feedback_until_msec:
		_clear_feedback()
	_snapshot = snapshot
	var battle_lesson: Dictionary = snapshot.get("battle_lesson", {})
	var field_text: String = str(battle_lesson.get("field_text", ""))
	_first_army_note_icon.texture = CommandIcons.get_icon("army" if not field_text.is_empty() else "move")
	_first_army_note_title.text = "01  Learn from losses" if not field_text.is_empty() else "01  Assemble"
	_first_army_note_body.text = field_text if not field_text.is_empty() else "Tap ground to assemble. Let Warriors catch up with cavalry."
	var workers: Dictionary = snapshot.get("workers", {})
	var warnings: PackedStringArray = []
	for resource: String in RESOURCES:
		if int(workers.get(resource, 0)) == 0:
			warnings.append("No " + resource + " workers")
	var idle: int = int(workers.get("idle", 0))
	var fighters: int = maxi(0, int(snapshot.get("fighters", 0)))
	var economy: Dictionary = snapshot.get("economy", {})
	var attention: String = str(economy.get("attention", ""))
	var economy_description := "Economy: manage workers and paid production"
	if idle > 0:
		economy_description += "\n%d idle worker%s. Choose Idle, then a job." % [idle, "" if idle == 1 else "s"]
	if not warnings.is_empty():
		economy_description += "\n" + "; ".join(warnings)
	if not attention.is_empty():
		economy_description += "\n" + attention
	if int(economy.get("severity", 0)) > 0:
		economy_description += "\n%s\n%s" % [str(economy.get("title", "")), str(economy.get("detail", ""))]
	CommandIcons.apply(_economy_button, "economy", economy_description)
	# Keep unused workers visible even when another worker still staffs each job.
	# This is a count of observed idle workers, never an automatic assignment.
	var economy_badge: String = (str(idle) if idle < 100 else "99+") if idle > 0 else ("!" if not warnings.is_empty() or not attention.is_empty() else "")
	CommandIcons.set_badge(_economy_button, economy_badge, true)
	CommandIcons.apply(_army_button, "army", "Army: %d fighters. Recruit fighters and manage two groups. Scouts keep their own orders." % fighters)
	CommandIcons.set_badge(_army_button, str(fighters))
	var worker_count: int = 0
	for amount: Variant in workers.values():
		worker_count += int(amount)
	_summary.text = "%d workers · %d building · %d recovering" % [worker_count, int(workers.get("build", 0)), int(workers.get("recovering", 0))]
	if bool(snapshot.get("food_attention_ready", false)):
		_summary.text = "No food income · assign workers."
	elif bool(snapshot.get("food_low_attention_ready", false)):
		_summary.text = "Food low · scout or build a Farm."
	elif idle > 0:
		_summary.text = "%d idle · choose Idle, then a job." % idle
	_summary.add_theme_color_override("font_color", KingdomTheme.AMBER if idle > 0 or not warnings.is_empty() or bool(snapshot.get("food_low_attention_ready", false)) else KingdomTheme.PARCHMENT)
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
	CommandIcons.apply(_farm_button, "farm", "Plan a Farm: %d wood, permanent food. %s" % [farm_wood, _farm_blocker.text])
	ACTION_TILE.apply(_farm_button, CommandIcons.get_icon("farm"), {"wood": farm_wood}, Vector2(48,48))
	_farm_button.disabled = not bool(snapshot.get("can_plan_farm", false))
	_barracks_blocker.text = str(snapshot.get("barracks_blocker", ""))
	var barracks_wood: int = int(BuildingData.get_building_cost(BuildingData.BuildingType.BARRACKS).get("wood", 120))
	CommandIcons.apply(_barracks_button, "build", "Plan a Barracks: %d wood. %s" % [barracks_wood, _barracks_blocker.text])
	ACTION_TILE.apply(_barracks_button, load(BuildingBase.get_sprite_texture_path(BuildingData.BuildingType.BARRACKS, 0)), {"wood": barracks_wood}, Vector2(84,68))
	_barracks_button.disabled = not bool(snapshot.get("can_plan_barracks", false))
	_population.text = str(snapshot.get("population_text", ""))
	CommandIcons.apply(_idle_button, "idle", "Find the next of %d idle workers" % idle, "")
	_idle_button.disabled = idle <= 0
	_select_army_button.disabled = fighters <= 0
	_focus_army_button.disabled = fighters <= 0
	_refresh_allocation_buttons()
	_refresh_producers(snapshot.get("producers", []))
	_refresh_pages()
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
		CommandIcons.apply(button, resource, "%s: %d workers. Choose this current job before assigning one worker." % [resource.capitalize(), count], str(count))
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
		row["trade"] = building.building_type == BuildingData.BuildingType.TRADE_POST
		(row.rallies as Control).visible = not row.trade
		row["military"] = bool(producer.get("military", false))
		(row.status as Label).text = str(producer.get("status", ""))
		var queue: Array = producer.get("queue", [])
		(row.paid as Label).text = "%d queued · hold a unit to add" % queue.size()
		(row.paid as Label).tooltip_text = "Every queued unit is paid. Release to stop adding."
		(row.paid as Label).hide()
		(row.status as Label).hide()
		(row.rally_status as Label).hide()
		(row.repeat as Button).hide()
		(row.undo as Button).disabled = queue.is_empty()
		(row.clear as Button).disabled = queue.is_empty()
		var rally: Button = row.rally
		var active: bool = bool(producer.get("active", false))
		var army_selected: bool = int(_snapshot.get("selected_military", 0)) > 0
		rally.disabled = not army_selected or not active
		var rally_caption: String = "Rally to army" if army_selected else "Select army\nfirst"
		var rally_help: String = "Rally future recruits to the selected army's current location. Existing units keep their orders." if army_selected else "Select your own troops first, then rally future recruits to their current location."
		if not active:
			rally_caption = "Finish building\nfirst"
			rally_help = "Rally becomes available when this building is complete. Select your own troops to choose their location."
		CommandIcons.apply(rally, "rally", rally_help)
		(row.sacred as Button).disabled = not bool(producer.get("sacred_available", false)) or not bool(producer.get("active", false))
		(row.rally_status as Label).text = str(producer.get("rally_status", ""))
		row["queue_size"] = queue.size()
		CommandIcons.set_badge(row.queue_toggle, str(queue.size()) if not queue.is_empty() else "")
		(row.status as Label).tooltip_text = "%s\nQueue includes the unit currently training.\n%s\n%s" % [str(producer.get("status", "")), " / ".join(queue), str(producer.get("rally_status", ""))]
		for unit_type: int in row.train:
			var button: Button = row.train[unit_type]
			button.disabled = not bool(producer.get("active", false))
			var blocker: String = str((producer.get("unit_status", {}) as Dictionary).get(unit_type, ""))
			var status_label: Label = row.train_status[unit_type]
			var role: String = "Gather & build" if unit_type == UnitData.UnitType.VILLAGER else UnitData.get_unit_counter_description(unit_type, 0)
			button.tooltip_text = "%s\n%s\n%s" % [UnitData.get_unit_name(unit_type, 0), role, blocker.capitalize()]
			var paid_queue: ProductionQueue = building.get_production_queue()
			var count: int = paid_queue.queue.count(unit_type) if paid_queue != null else 0
			CommandIcons.set_badge(button, str(count) if count > 0 else "")
			FieldStyle.production_meter(button, paid_queue.get_current_progress() if paid_queue != null and not paid_queue.queue.is_empty() and paid_queue.queue[0] == unit_type else -1.0)
			button.get_node("TilePortrait").modulate = Color.WHITE if blocker == "ready" else Color(0.65, 0.65, 0.65)
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
	var full_name: String = UnitData.get_unit_name(unit_type, 0) if unit_type >= 0 else "Train first"
	# The recruitment card and accessible action retain the full unit name.
	var caption: String = "Siege" if unit_type == UnitData.UnitType.SIEGE else full_name
	CommandIcons.apply(button, "repeat", "Repeat %s: %s. Each training order is paid. Turning Repeat OFF leaves paid units queued; Clear & stop refunds them." % [full_name, state], "%s\n%s" % [caption, state])


func _create_producer(producer: Dictionary) -> void:
	var building: Node2D = producer.building
	var id: int = building.get_instance_id()
	var card := PanelContainer.new()
	card.name = "Producer_%d" % id
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_producer_list.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	card.add_child(content)
	var status := _label("")
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(status)
	var paid := _label("", 12)
	paid.autowrap_mode = TextServer.AUTOWRAP_OFF
	paid.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
		var button := _button("%s\n%s" % [UnitData.get_unit_name(unit_type, 0), " ".join(costs)], "Train_%d" % unit_type, TRAIN_CARD_WIDTH)
		button.add_theme_font_size_override("font_size", 12)
		var portrait_path: String = UnitData.get_unit_icon_path(unit_type, 0)
		if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
			button.icon = load(portrait_path)
			button.add_theme_constant_override("icon_max_width", int(CommandIcons.GLYPH_SIZE))
			button.expand_icon = false
		button.pressed.connect(func() -> void:
			if is_instance_valid(building):
				training_requested.emit(building, unit_type))
		unit_card.add_child(button)
		ACTION_TILE.apply(button, load(portrait_path) if not portrait_path.is_empty() else null, cost, Vector2(TRAIN_CARD_WIDTH, 64))
		_attach_repeat(button, func() -> bool:
			if not is_instance_valid(building) or button.disabled:
				return false
			training_requested.emit(building, unit_type)
			return true)
		train_buttons[unit_type] = button
		var unit_status := _label("", 12)
		unit_status.name = "TrainingStatus_%d" % unit_type
		unit_card.add_child(unit_status)
		unit_status.hide()
		train_status[unit_type] = unit_status
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	content.add_child(actions)
	actions.hide()
	var queue_toggle := _icon_button("queue", "Expand queue refunds", "QueueDisclosure", 48)
	content.add_child(queue_toggle)
	queue_toggle.pressed.connect(func() -> void:
		actions.visible = not actions.visible
		queue_toggle.set_pressed_no_signal(actions.visible))
	var repeat_button := _icon_button("repeat", "Repeat paid training while resources and population room allow", "Repeat", 120, "Repeat\nOFF")
	repeat_button.toggle_mode = true
	repeat_button.toggled.connect(func(enabled: bool) -> void:
		if is_instance_valid(building):
			repeat_requested.emit(building, enabled))
	actions.add_child(repeat_button)
	repeat_button.hide()
	var undo := _icon_button("undo", "Refund the last paid unit", "UndoLast", 120, "")
	undo.tooltip_text = "Refund the last paid unit and its population reservation."
	undo.pressed.connect(func() -> void:
		if is_instance_valid(building) and _producer_rows.has(id):
			cancellation_requested.emit(building, int(_producer_rows[id].queue_size) - 1))
	actions.add_child(undo)
	var clear := _icon_button("clear", "Refund all queued units", "ClearAndStop", 120, "")
	clear.tooltip_text = "Refund every queued unit and reserved population slot."
	clear.pressed.connect(func() -> void:
		if is_instance_valid(building):
			cancellation_requested.emit(building, ProductionQueue.CANCEL_ALL_INDEX))
	actions.add_child(clear)
	var rally_status := _label("", 12)
	rally_status.name = "RallyStatus"
	content.add_child(rally_status)
	rally_status.hide()
	var rallies := HBoxContainer.new()
	rallies.add_theme_constant_override("separation", 6)
	content.add_child(rallies)
	var rally := _icon_button("rally", "Rally future recruits to the selected army", "RallyToArmy", TRAIN_CARD_WIDTH, "Rally to army")
	rally.tooltip_text = "Send future trained units to the selected army’s current location. Existing units keep their orders."
	rally.pressed.connect(func() -> void:
		if is_instance_valid(building):
			rally_requested.emit(building))
	rallies.add_child(rally)
	var sacred := _icon_button("sacred", "Rally future recruits to the Sacred Site", "RallyToSacred", TRAIN_CARD_WIDTH, "")
	sacred.tooltip_text = "All future recruits go to the public Sacred location. Existing units keep their orders."
	sacred.pressed.connect(func() -> void:
		if is_instance_valid(building):
			sacred_rally_requested.emit(building))
	rallies.add_child(sacred)
	_producer_rows[id] = {"card": card, "training": training, "queue_toggle": queue_toggle, "status": status, "paid": paid, "repeat": repeat_button, "undo": undo, "clear": clear, "rally": rally, "sacred": sacred, "rallies": rallies, "rally_status": rally_status, "train": train_buttons, "train_status": train_status, "queue_size": 0}


func show_feedback(message: String, success: bool = true) -> void:
	_feedback_until_msec = Time.get_ticks_msec() + 6000
	_feedback.text = message
	_feedback.tooltip_text = message
	_feedback.add_theme_color_override("font_color", KingdomTheme.TEAL if success else KingdomTheme.AMBER)


func _clear_feedback() -> void:
	_feedback_until_msec = 0
	_feedback.text = ""
	_feedback.tooltip_text = ""
	_feedback.add_theme_color_override("font_color", KingdomTheme.MUTED)


func set_surface(surface: String) -> void:
	var changed: bool = _surface != surface
	_surface = surface
	if surface == "army" and not _army_page_initialized:
		# The opening Scout is unarmed: first-time players need recruitment.
		_army_recruit_page = int(_snapshot.get("fighters", 0)) == 0
		_army_page_initialized = true
	panel.visible = surface in ["economy", "army"]
	_economy.visible = surface == "economy"
	_army.visible = surface == "army"
	_title.text = "Economy" if surface == "economy" else "Army"
	_economy_button.set_pressed_no_signal(surface == "economy")
	_army_button.set_pressed_no_signal(surface == "army")
	if changed:
		_clear_feedback()
		_scroll.scroll_vertical = 0
		_details_page = false
	_refresh_pages()


func _set_production_page(enabled: bool) -> void:
	if _production_page != enabled:
		_clear_feedback()
	_production_page = enabled
	_details_page = false
	_scroll.scroll_vertical = 0
	_refresh_pages()


func _set_army_recruit_page(enabled: bool) -> void:
	if _army_recruit_page != enabled:
		_clear_feedback()
	_army_recruit_page = enabled
	_army_page_initialized = true
	_details_page = false
	_scroll.scroll_vertical = 0
	_refresh_pages()


func _showing_production() -> bool:
	return _army_recruit_page if _surface == "army" else _production_page


func _visible_producer_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _producer_rows:
		if _surface != "army" or bool(_producer_rows[id].get("military", false)):
			ids.append(id)
	return ids


func _selected_producer_id() -> int:
	var ids: Array[int] = _visible_producer_ids()
	if ids.is_empty():
		return 0
	var held_id: int = _army_producer_id if _surface == "army" else _economy_producer_id
	var index: int = _army_producer_index if _surface == "army" else _producer_index
	index = ids.find(held_id) if held_id in ids else clampi(index, 0, ids.size() - 1)
	if _surface == "army":
		_army_producer_index = index
		_army_producer_id = ids[index]
	else:
		_producer_index = index
		_economy_producer_id = ids[index]
	return ids[index]


func _step_producer(direction: int) -> void:
	var ids: Array[int] = _visible_producer_ids()
	if ids.is_empty():
		return
	var current: int = ids.find(_selected_producer_id())
	var next: int = posmod(current + direction, ids.size())
	if next != current:
		_clear_feedback()
	if _surface == "army":
		_army_producer_index = next
		_army_producer_id = ids[next]
	else:
		_producer_index = next
		_economy_producer_id = ids[next]
	_refresh_pages()


func _refresh_pages() -> void:
	var economy_open: bool = _surface == "economy"
	var army_open: bool = _surface == "army"
	var recruiting: bool = army_open and _army_recruit_page
	var production: bool = _showing_production()
	# Expanded finite queue controls must stay reachable in the bounded sheet.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var ids: Array[int] = _visible_producer_ids()
	var empty_recruit: bool = recruiting and ids.is_empty()
	var food_alert: bool = bool(_snapshot.get("food_attention_ready", false)) and not economy_open
	var food_low_alert: bool = bool(_snapshot.get("food_low_attention_ready", false)) and not economy_open
	var economy_caption: String = "No food" if food_alert else "Food low" if food_low_alert else "Economy"
	if _economy_button.text != economy_caption:
		CommandIcons.apply(_economy_button, "food" if food_alert or food_low_alert else "economy", _economy_button.accessibility_name)
	_economy.visible = (economy_open or recruiting) and not _details_page and not empty_recruit
	_details.visible = (economy_open or recruiting) and _details_page
	_army.visible = army_open and not _army_recruit_page and not _details_page
	_army_notes.visible = army_open and not _army_recruit_page and _details_page
	_recruit_empty.visible = empty_recruit and not _details_page
	for child: Node in _recruit_empty.get_children():
		if child is Label: child.hide()
	_farm_button.visible = economy_open and not production and not _details_page
	_info_button.visible = economy_open or army_open
	_info_button.set_pressed_no_signal(_details_page)
	var info_description: String = "Army field notes: assemble, attack-move and withdraw" if army_open and not recruiting else "Show current worker or producer details"
	if army_open and not recruiting and not (_snapshot.get("battle_lesson", {}) as Dictionary).is_empty():
		info_description = "Army field notes: observed losses, counters, attack-move and withdraw"
	CommandIcons.apply(_info_button, "back" if _details_page else "info", "Back to actions" if _details_page else info_description)
	if army_open:
		_title.text = "Army field notes" if _details_page else "Army & groups"
	_title.visible = false
	_workers_tab.visible = economy_open
	_production_tab.visible = economy_open
	_recruit_tab.visible = army_open
	_groups_tab.visible = army_open
	_recruit_tab.set_pressed_no_signal(_army_recruit_page)
	_groups_tab.set_pressed_no_signal(not _army_recruit_page)
	_previous_producer.visible = (economy_open or army_open) and production and ids.size() > 1
	_next_producer.visible = _previous_producer.visible
	_previous_producer.disabled = ids.size() <= 1
	_next_producer.disabled = ids.size() <= 1
	_workers_tab.set_pressed_no_signal(not _production_page)
	_production_tab.set_pressed_no_signal(_production_page)
	for child: Node in _economy.get_children():
		if child is Control:
			(child as Control).visible = (child == _producer_list) == production
	# Details have their own touch-accessible page, keeping actions unscrolled.
	_economy_health.hide()
	_food_stock.hide()
	_population.hide()
	_summary.hide()
	_farm_blocker.hide()
	_feedback.visible = Time.get_ticks_msec() < _feedback_until_msec
	for entry: Array in [[_workers_tab, "economy", "Assign workers"], [_production_tab, "base", "Train workers"], [_recruit_tab, "army", "Recruit fighters"], [_groups_tab, "group_recall", "Army groups"]]:
		CommandIcons.apply(entry[0], entry[1], entry[2])
		(entry[0] as Button).custom_minimum_size.x = 48
	var selected_id: int = _selected_producer_id()
	for id: int in _producer_rows:
		(_producer_rows[id].card as Control).visible = id == selected_id
	var trade_production: bool = production and bool(_producer_rows.get(selected_id, {}).get("trade", false))
	var trade_parent: HBoxContainer = _producer_rows[selected_id].training if economy_open and trade_production else _header
	if _trade_actions.get_parent() != trade_parent:
		_trade_actions.reparent(trade_parent, false)
	if trade_parent == _header:
		var before_info: int = _info_button.get_index() - (1 if _trade_actions.get_index() < _info_button.get_index() else 0)
		_header.move_child(_trade_actions, before_info)
	_trade_actions.visible = economy_open and not _details_page and bool(_snapshot.get("has_trade", false)) and (not production or trade_production)
	# Six 48px targets fit the worker header without widening the sheet. Trade
	# production uses spare room beside its sole unit card, never another row.
	_header.add_theme_constant_override("separation", 0 if _trade_actions.visible and trade_parent == _header else 2)
	_refresh_details()
	var signature: String = "%s:%s:%s:%s:%s" % [_surface, production, selected_id, ids.size(), _details_page]
	if signature != _page_layout_signature:
		_page_layout_signature = signature
		if panel.visible and get_parent().has_method("_queue_mobile_layout_refresh"):
			get_parent().call("_queue_mobile_layout_refresh")


func _refresh_details() -> void:
	var lines: PackedStringArray = []
	if not _showing_production():
		var economy: Dictionary = _snapshot.get("economy", {})
		var facts: Dictionary = _snapshot.get("economy_facts", {})
		var workers: Dictionary = _snapshot.get("workers", {})
		lines.append(_summary.text)
		lines.append("Food %d · Wood %d · Gold %d · Idle %d" % [int(workers.get("food", 0)), int(workers.get("wood", 0)), int(workers.get("gold", 0)), int(workers.get("idle", 0))])
		lines.append(str(economy.get("title", "Economy")))
		lines.append(_worker_recovery_hint(economy, facts))
		lines.append(str(_snapshot.get("population_text", "")).get_slice(" · ", 0).get_slice("\n", 0))
		lines.append("Visible berry food %d · %d permanent Farms" % [int(facts.get("berry_food", 0)), int(facts.get("permanent_farms", 0))])
		if bool(_snapshot.get("has_trade", false)):
			lines.append(_trade_summary())
			lines.append(_trade_help())
	else:
		var producers: Array = _snapshot.get("producers", [])
		if _visible_producer_ids().is_empty():
			lines.append("Build a Barracks to recruit Warriors.")
			lines.append(_barracks_button.tooltip_text)
			lines.append("Scouts explore but cannot fight. Use Groups to save selected fighters.")
		else:
			var selected_id: int = _selected_producer_id()
			for producer: Dictionary in producers:
				var building: Node2D = producer.get("building")
				if is_instance_valid(building) and building.get_instance_id() == selected_id:
					lines = _producer_details(producer)
					break
	for index: int in range(_detail_lines.size()):
		_detail_lines[index].text = lines[index] if index < lines.size() else ""
		_detail_lines[index].visible = not _detail_lines[index].text.is_empty()


func _worker_recovery_hint(economy: Dictionary, facts: Dictionary) -> String:
	var population_full: bool = int(facts.get("free_population", 1)) <= 0
	var living_full: bool = int(facts.get("population_room_after_refunds", 1)) <= 0
	var worker_food: int = int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).get("food", 50))
	var farm_wood: int = int(BuildingData.get_building_cost(BuildingData.BuildingType.FARM).get("wood", 75))
	match str(economy.get("title", "")):
		"Replacement already paid":
			return "Keep the paid Villager's producer safe."
		"Economy cannot restart":
			return "Army can still fight. Pause → Quit to Main Menu to restart."
		"Recover through a paid refund":
			return "Refund paid food; a living population slot must also open." if living_full else "Refund paid units, then train a %d-food Villager." % worker_food
		"Rebuild your workforce":
			if population_full:
				return "A living population slot must open before training." if living_full else "Refund reserved slots, then train a %d-food Villager." % worker_food
			return "Train a %d-food Villager and protect its work area." % worker_food
		"Workers sheltering from danger":
			return "Protect their work area; saved jobs resume when safe."
		"No workers on food":
			return "Assign a worker to food." if int(facts.get("visible_food", 0)) > 0 else "Scout berries or build a %d-wood Farm; assign a worker." % farm_wood
		"Nearby food is running low":
			return "%d food visible nearby. Scout berries or plan a %d-wood Farm." % [int(facts.get("nearby_food", facts.get("worked_food", 0))), farm_wood]
	return "Protect workers; keep food and wood staffed."


func _producer_details(producer: Dictionary) -> PackedStringArray:
	var status: String = str(producer.get("status", ""))
	if status.contains(" · repeat waiting:"):
		status = status.get_slice(" · repeat waiting:", 0) + " · Repeat waiting"
	var lines: PackedStringArray = [status]
	var blockers: PackedStringArray = []
	var named_blockers: PackedStringArray = []
	for unit_type: int in producer.get("trainable", []):
		var cost: Dictionary = UnitData.get_unit_cost(unit_type)
		var costs: PackedStringArray = []
		for resource: String in RESOURCES:
			if int(cost.get(resource, 0)) > 0:
				costs.append("%d%s" % [int(cost[resource]), resource.left(1).to_upper()])
		var role: String = "Gather & build" if unit_type == UnitData.UnitType.VILLAGER else UnitData.get_unit_role_description(unit_type, 0)
		if unit_type == UnitData.UnitType.SCOUT:
			role = UnitData.get_unit_counter_description(unit_type, 0)
		var counter: String = UnitData.get_unit_counter_name(unit_type, 0)
		if not counter.is_empty():
			role += "; beats " + counter
		lines.append("%s · %s · %s" % [UnitData.get_unit_name(unit_type, 0), " ".join(costs), role])
		var blocker: String = str((producer.get("unit_status", {}) as Dictionary).get(unit_type, "ready"))
		blocker = blocker.replace("population blocked — ", "Population: ").replace("; refunds alone cannot help", "").replace("living units must free a slot", "living slot must open")
		if blocker not in blockers:
			blockers.append(blocker)
		named_blockers.append(UnitData.get_unit_name(unit_type, 0) + ": " + blocker)
	lines.append("Training: " + "; ".join(blockers) if blockers.size() <= 1 else "; ".join(named_blockers))
	var queue: Array = producer.get("queue", [])
	var counts: Dictionary = {}
	for unit_name: String in queue:
		counts[unit_name] = int(counts.get(unit_name, 0)) + 1
	var paid: PackedStringArray = []
	for unit_name: String in counts:
		paid.append("%s ×%d" % [unit_name, counts[unit_name]])
	lines.append("Queue: %s" % [", ".join(paid) if not paid.is_empty() else "empty"])
	var building: BuildingBase = producer.get("building") as BuildingBase
	if is_instance_valid(building) and building.building_type == BuildingData.BuildingType.TRADE_POST:
		lines.append(_trade_summary())
		lines.append(_trade_help())
	else:
		lines.append(str(producer.get("rally_status", "")).replace(" · fixed until changed.", ".").replace(" Includes new Villagers.", " New Villagers too."))
	return lines


func _trade_summary() -> String:
	return "Traders %d · %d paused or waiting. Trader icon finds them." % [int(_snapshot.get("traders", 0)), int(_snapshot.get("waiting_traders", 0))]


func _trade_help() -> String:
	return "New traders use a distant reachable Town Center automatically. Gold pays on return. Move or Stop pauses trade; select the trader, then tap your Trade Post to resume."


func apply_layout(safe: Rect2, field_visible: bool, card_area: Rect2, dock_height: float = 72.0) -> void:
	rail.visible = field_visible
	var rail_bottom: float = safe.end.y - dock_height - 16.0
	rail.position = Vector2(safe.end.x - RAIL_WIDTH - 8.0, rail_bottom - RAIL_BUTTON_SIZE)
	rail.size = Vector2(RAIL_WIDTH, RAIL_BUTTON_SIZE)
	# The sheet leaves its launchers reachable for switching and tap-to-collapse.
	var card_left: float = card_area.position.x + 8.0
	var card_right: float = minf(card_area.end.x - 8.0, rail.position.x - 8.0)
	_sheet_width = minf(220.0 if _recruit_empty.visible else SHEET_MAX_WIDTH, card_right - card_left)
	_fit_economy_rows(_sheet_width)
	var sheet_slot_height: float = minf(310.0, card_area.size.y - 16.0)
	var content_height: float = (_scroll.get_child(0) as Control).get_combined_minimum_size().y
	var card_height: float = minf(sheet_slot_height, content_height + CommandIcons.TARGET_SIZE + 16.0)
	if (_surface == "economy" or _army_recruit_page) and _details_page:
		card_height = minf(card_height, 240.0)
	if _surface == "army":
		# Fit the current Army page so recruitment leaves more battlefield visible.
		# Two pixels absorb container rounding at fractional interface scales.
		var active_page: Control = _recruit_empty if _recruit_empty.visible else (_details if _details_page else _producer_list) if _army_recruit_page else (_army_notes if _details_page else _army)
		content_height = active_page.get_combined_minimum_size().y
		card_height = minf(card_height, content_height + CommandIcons.TARGET_SIZE + 14.0)
	_last_panel_minimum = panel.get_combined_minimum_size()
	card_height = maxf(card_height, _last_panel_minimum.y)
	var card_size := Vector2(_sheet_width, card_height)
	var centered: Vector2 = card_area.position + (card_area.size - card_size) * 0.5
	# Anchor all pages just below the resource bar. Page height and hidden labels'
	# unsettled wrapping must not move the tabs or the Info return control.
	# Compact pages still expose more battlefield below their shorter body.
	panel.position = Vector2(clampf(centered.x, card_left, card_right - card_size.x), maxf(safe.position.y, card_area.position.y))
	panel.size = card_size
	panel.visible = field_visible and _surface in ["economy", "army"]


func _on_panel_minimum_changed() -> void:
	if not panel.is_visible_in_tree():
		return
	var minimum: Vector2 = panel.get_combined_minimum_size()
	if minimum.is_equal_approx(_last_panel_minimum):
		return
	_last_panel_minimum = minimum
	# First opening sizes wrapped labels before their real width has settled.
	# Refit after that minimum changes, through the HUD's coalesced deferred
	# layout. Ordinary snapshot text updates with the same minimum do nothing.
	if get_parent().has_method("_queue_mobile_layout_refresh"):
		get_parent().call("_queue_mobile_layout_refresh")


func _fit_economy_rows(sheet_width: float) -> void:
	# Reserve the real scroll bar even before it becomes visible. Reflow widths
	# before sizing the panel, so a stale child minimum cannot enlarge the sheet.
	var panel_padding: float = panel.get_theme_stylebox("panel").get_minimum_size().x
	var scroll_width: float = 0.0
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
		var action_width: float = minf(120.0, floorf((content_width - inner_padding - CommandIcons.GAP) / 2.0))
		for button: Button in [row.undo, row.clear]:
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
	var economy_color: Color = KingdomTheme.AMBER if (bool(_snapshot.get("food_attention_ready", false)) or bool(_snapshot.get("food_low_attention_ready", false))) and _surface != "economy" else Color.WHITE
	_economy_button.modulate = Color(1.0, pulse, 0.62) if action == "idle_button" else economy_color
	_army_button.modulate = Color(1.0, pulse, 0.62) if action == "military_button" else Color.WHITE
