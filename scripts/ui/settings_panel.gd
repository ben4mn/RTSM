extends ColorRect
## Shared preferences surface. A paused match remains paused beneath this panel.

signal closed()

const THEME := preload("res://scripts/ui/kingdom_theme.gd")
const SECTIONS: Array[String] = ["Audio", "Controls", "Display", "Guide"]
const SCALE_VALUES: Array[float] = [1.0, 1.075, 1.15]
const SENSITIVITY_VALUES: Array[float] = [0.75, 1.0, 1.25]
var from_match: bool = false
var _panel: PanelContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _tabs: Array[Button] = []
var _section: int = 0
var _status: Label
var _safe_area: Rect2
var _closing: bool = false


static func open(parent: Node, in_match: bool = false) -> Control:
	var existing: Control = parent.get_node_or_null("SettingsPanel") as Control
	if existing != null:
		return existing
	var panel: Control = load("res://scripts/ui/settings_panel.gd").new()
	panel.name = "SettingsPanel"
	panel.set("from_match", in_match)
	parent.add_child(panel)
	return panel


func _ready() -> void:
	preload("res://scripts/ui/web_shell_bridge.gd").set_update_safe(false)
	preload("res://scripts/ui/web_shell_bridge.gd").set_controls_visible(false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	color = Color(THEME.INK, 0.97)
	theme = THEME.create_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.name = "PreferencesCard"
	var panel_style: StyleBoxFlat = THEME.panel_style()
	panel_style.set_content_margin_all(2)
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_force_pass_scroll_events = false
	add_child(_panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10 if edge in ["left", "right"] else 4)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 5)
	column.add_child(tabs)
	var group := ButtonGroup.new()
	for i: int in SECTIONS.size():
		var button := Button.new()
		button.name = SECTIONS[i] + "Tab"
		button.text = SECTIONS[i]
		button.custom_minimum_size = Vector2(80, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.toggle_mode = true
		button.button_group = group
		var tab_normal: StyleBoxFlat = THEME.panel_style(THEME.INK_PANEL, THEME.INK_PANEL, 0)
		var tab_active: StyleBoxFlat = tab_normal.duplicate()
		tab_active.border_color = THEME.TEAL
		tab_active.set_border_width_all(0)
		tab_active.border_width_bottom = 2
		button.add_theme_stylebox_override("normal", tab_normal)
		button.add_theme_stylebox_override("pressed", tab_active)
		button.add_theme_stylebox_override("hover_pressed", tab_active)
		button.add_theme_color_override("font_pressed_color", THEME.PARCHMENT)
		button.add_theme_color_override("font_hover_pressed_color", THEME.PARCHMENT)
		button.pressed.connect(_show_section.bind(i))
		tabs.add_child(button)
		_tabs.append(button)
	_scroll = ScrollContainer.new()
	_scroll.name = "SettingsScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.mouse_force_pass_scroll_events = false
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "SectionBody"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	_scroll.add_child(_body)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	var reset := _button("Reset defaults", "ResetDefaultsButton", _reset_application_preferences)
	reset.pressed.connect(func() -> void:
		_show_section(_section)
		_status.text = "Defaults restored"
	)
	footer.add_child(reset)
	_status = Label.new()
	_status.text = "Changes save automatically"
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", THEME.MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(_status)
	var done := _button("Done", "SettingsDoneButton", close)
	done.custom_minimum_size.x = 90
	THEME.apply_primary(done)
	footer.add_child(done)
	get_viewport().size_changed.connect(_layout)
	preload("res://scripts/ui/web_shell_bridge.gd").watch_safe_area(self, _layout)
	_show_section(0)
	_layout()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closing:
		return
	_closing = true
	preload("res://scripts/ui/web_shell_bridge.gd").set_controls_visible(true)
	GameManager.save_preferences()
	# The owner restores its own update gate: a menu may still contain a live
	# multiplayer room, and an in-match panel must keep reloads blocked.
	closed.emit()
	queue_free()


func _layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var safe := Rect2(Vector2.ZERO, viewport_size)
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor.has_method("_get_safe_area_rect"):
			safe = ancestor.call("_get_safe_area_rect", viewport_size)
			break
		ancestor = ancestor.get_parent()
	apply_mobile_layout(viewport_size, safe)


func apply_mobile_layout(viewport_size: Vector2, safe: Rect2) -> void:
	_safe_area = safe.intersection(Rect2(Vector2.ZERO, viewport_size))
	if not _safe_area.has_area():
		_safe_area = Rect2(Vector2.ZERO, viewport_size)
	var card_size := Vector2(minf(660.0, _safe_area.size.x - 16.0), minf(550.0, _safe_area.size.y - 12.0))
	_panel.position = _safe_area.position + (_safe_area.size - card_size) * 0.5
	_panel.size = card_size


func _show_section(index: int) -> void:
	_section = index
	for i: int in _tabs.size():
		_tabs[i].set_pressed_no_signal(i == index)
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical = 0
	match index:
		0: _build_audio()
		1: _build_controls()
		2: _build_display()
		3: _build_guide()
	_status.text = "Tap an icon to learn" if index == 3 else "Changes save automatically"
	var reset: Button = find_child("ResetDefaultsButton", true, false) as Button
	if reset != null:
		reset.visible = index != 3


func _build_guide() -> void:
	_note("Tap any icon to learn its action. Tap again to fold it away.")
	for entry: Array in preload("res://scripts/ui/field_guide.gd").ENTRIES:
		var column := VBoxContainer.new()
		column.name = "Guide_" + str(entry[0])
		_body.add_child(column)
		var button := Button.new()
		button.name = "LearnButton"
		CommandIcons.apply(button, entry[0], "Learn: " + str(entry[1]), entry[1])
		button.toggle_mode = true
		button.custom_minimum_size.y = 48
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 15)
		column.add_child(button)
		var explanation := Label.new()
		explanation.name = "Explanation"
		explanation.text = entry[2]
		explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		explanation.add_theme_font_size_override("font_size", 14)
		explanation.add_theme_color_override("font_color", THEME.PARCHMENT)
		explanation.mouse_filter = Control.MOUSE_FILTER_IGNORE
		explanation.visible = false
		column.add_child(explanation)
		button.toggled.connect(func(expanded: bool) -> void:
			explanation.visible = expanded
			button.accessibility_name = ("Hide: " if expanded else "Learn: ") + str(entry[1])
		)



func _build_audio() -> void:
	_toggle("Sound enabled", "audio_enabled")
	var toggle: Control = _body.get_child(_body.get_child_count() - 1)
	var row := HBoxContainer.new()
	_body.add_child(row)
	toggle.reparent(row)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_button("Preview", "AudioPreviewButton", AudioManager.preview))
	_volume("Master", "master_volume")
	_volume("World effects", "sfx_volume")
	_volume("UI & alerts", "ui_alert_volume")


func _build_controls() -> void:
	_note("Tap ground: move · Hold ground: attack-move\nDrag: pan · Pinch: zoom")
	_choice("Pan sensitivity", "camera_speed_scale", ["Relaxed", "Standard", "Fast"], SENSITIVITY_VALUES)
	_choice("Zoom sensitivity", "zoom_sensitivity_scale", ["Relaxed", "Standard", "Fast"], SENSITIVITY_VALUES)
	_toggle("Optional hold shortcuts", "hold_shortcuts_enabled")



func _build_display() -> void:
	_choice("Interface size", "ui_scale", ["Standard", "Large", "Extra Large"], SCALE_VALUES)
	_toggle("Reduced motion", "reduced_motion")
	_toggle("Reduced flashes", "reduced_flashes")
	_toggle("Clear player markers", "clearer_player_markers")


func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48
	row.add_theme_constant_override("separation", 10)
	_body.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 154
	label.add_theme_font_size_override("font_size", 15)
	row.add_child(label)
	return row


func _toggle(label: String, property: String) -> void:
	var toggle := CheckButton.new()
	toggle.name = property.to_pascal_case() + "Toggle"
	toggle.text = label
	toggle.custom_minimum_size.y = 48
	toggle.add_theme_font_size_override("font_size", 15)
	toggle.set_pressed_no_signal(bool(GameManager.get(property)))
	toggle.toggled.connect(func(value: bool) -> void:
		GameManager.set(property, value)
		_save()
	)
	_body.add_child(toggle)


func _volume(label: String, property: String) -> void:
	var row := _row(label)
	var slider := HSlider.new()
	slider.name = property.to_pascal_case() + "Slider"
	slider.custom_minimum_size = Vector2(130, 48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.scrollable = false
	slider.value = float(GameManager.get(property)) * 100.0
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 44
	value.add_theme_font_size_override("font_size", 14)
	value.text = "%d%%" % slider.value
	row.add_child(value)
	slider.value_changed.connect(func(amount: float) -> void:
		GameManager.set(property, amount / 100.0)
		value.text = "%d%%" % amount
		GameManager.apply_preferences()
	)
	slider.drag_ended.connect(func(_changed: bool) -> void: _save())
	if property != "master_volume":
		var mute_property: String = "sfx_muted" if property == "sfx_volume" else "ui_alert_muted"
		var mute := CheckButton.new()
		mute.name = mute_property.to_pascal_case() + "Toggle"
		mute.text = "Mute"
		mute.custom_minimum_size = Vector2(96, 48)
		mute.add_theme_font_size_override("font_size", 13)
		mute.set_pressed_no_signal(bool(GameManager.get(mute_property)))
		mute.toggled.connect(func(enabled: bool) -> void:
			GameManager.set(mute_property, enabled)
			_save()
		)
		row.add_child(mute)


func _choice(label: String, property: String, labels: Array, values: Array) -> void:
	var row := _row(label)
	var choice := OptionButton.new()
	choice.name = property.to_pascal_case() + "Option"
	choice.custom_minimum_size = Vector2(190, 48)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.add_theme_font_size_override("font_size", 15)
	var current: float = float(GameManager.get(property))
	var nearest: int = 0
	for i: int in labels.size():
		choice.add_item(str(labels[i]))
		if absf(float(values[i]) - current) < absf(float(values[nearest]) - current):
			nearest = i
	choice.select(nearest)
	choice.item_selected.connect(func(i: int) -> void:
		GameManager.set(property, values[i])
		_save()
	)
	row.add_child(choice)


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", THEME.MUTED)
	_body.add_child(label)
	return label


func _button(text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(90, 48)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(callback)
	return button


func _save() -> void:
	GameManager.apply_preferences()
	_status.text = "Saved" if GameManager.save_preferences() else "Could not save preferences"


func _reset_application_preferences() -> void:
	# Reset application preferences without changing the draft game being created.
	var match_keys: Array[String] = ["selected_difficulty", "selected_population_limit", "selected_map_seed", "selected_map_archetype", "selected_match_mode", "guided_opening_enabled"]
	var draft: Dictionary = {}
	for key: String in match_keys:
		draft[key] = GameManager.get(key)
	GameManager.reset_preferences()
	for key: String in match_keys:
		GameManager.set(key, draft[key])
	GameManager.save_preferences()
