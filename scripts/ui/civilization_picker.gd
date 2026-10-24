extends ColorRect
## Compare a kingdom's actual tradeoffs before committing the match draft.

signal chosen(civilization: int)
signal closed()

const THEME := preload("res://scripts/ui/kingdom_theme.gd")
const WEB := preload("res://scripts/ui/web_shell_bridge.gd")
const INK := Color("10282b")
const PANEL := Color("19383b")
const IVORY := Color("f4eddd")
const GOLD := Color("e7ba67")
const BORDER := Color("3d5d60")
var selected: int = 0
var heading: String = "Choose your kingdom"
var _panel: PanelContainer
var _cards: Array[Button] = []
var _title: Label
var _tagline: Label
var _detail: Label
var _portrait: TextureRect
var _confirm: Button
var _scroll: ScrollContainer
var _closing: bool = false


static func open(parent: Node, civilization: int, title: String = "Choose your kingdom") -> Control:
	var picker: Control = load("res://scripts/ui/civilization_picker.gd").new()
	picker.name = "CivilizationPicker"
	picker.set("selected", CivilizationData.normalize(civilization))
	picker.set("heading", title)
	parent.add_child(picker)
	return picker


func _ready() -> void:
	WEB.set_update_safe(false)
	WEB.set_controls_visible(false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	color = Color(INK, 0.97)
	theme = THEME.create_theme()
	theme.set_color("font_color", "Label", IVORY)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var button_style: StyleBoxFlat = THEME.button_style("secondary", "pressed" if state == "hover_pressed" else state)
		button_style.set_corner_radius_all(10)
		button_style.border_width_bottom = 1
		button_style.bg_color = GOLD if state in ["pressed", "hover_pressed"] else PANEL
		button_style.border_color = GOLD if state in ["pressed", "hover_pressed", "hover"] else BORDER
		if state == "focus":
			button_style.bg_color = Color.TRANSPARENT
			button_style.border_color = IVORY
		theme.set_stylebox(state, "Button", button_style)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.name = "KingdomComparison"
	var style: StyleBoxFlat = THEME.panel_style(PANEL, BORDER, 16)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	_title = _label(heading, 22)
	_title.add_theme_font_override("font", THEME.FONT_MEDIUM)
	column.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for id: int in CivilizationData.ORDERED_IDS:
		var definition: Dictionary = CivilizationData.get_definition(id)
		var card := Button.new()
		card.name = "Civilization%d" % id
		card.text = str(definition.name)
		card.tooltip_text = "%s · %s" % [definition.name, definition.tagline]
		card.accessibility_name = "Compare " + str(definition.name)
		card.icon = load(str(definition.icon_path))
		# Crests are colored illustrations, unlike monochrome command glyphs.
		card.add_theme_color_override("icon_pressed_color", Color.WHITE)
		card.add_theme_color_override("icon_hover_pressed_color", Color.WHITE)
		card.expand_icon = true
		card.add_theme_constant_override("icon_max_width", 36)
		card.add_theme_font_size_override("font_size", 15)
		card.custom_minimum_size = Vector2(0, 64)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.clip_text = true
		card.toggle_mode = true
		card.pressed.connect(select_civilization.bind(id))
		row.add_child(card)
		_cards.append(card)
	_scroll = ScrollContainer.new()
	_scroll.name = "KingdomDetailsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var comparison := HBoxContainer.new()
	comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comparison.add_theme_constant_override("separation", 14)
	_scroll.add_child(comparison)
	var identity := VBoxContainer.new()
	identity.custom_minimum_size.x = 116
	comparison.add_child(identity)
	_portrait = TextureRect.new()
	_portrait.name = "SignaturePortrait"
	_portrait.custom_minimum_size = Vector2(116, 116)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(_portrait)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 10)
	comparison.add_child(details)
	_tagline = _label("", 20)
	_tagline.name = "KingdomTagline"
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tagline.add_theme_font_override("font", THEME.FONT_MEDIUM)
	details.add_child(_tagline)
	_detail = _label("", 16)
	_detail.name = "KingdomTradeoffs"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(_detail)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	var cancel := Button.new()
	cancel.name = "CancelKingdomButton"
	cancel.text = "Back"
	cancel.custom_minimum_size = Vector2(96, 48)
	cancel.pressed.connect(close)
	footer.add_child(cancel)
	_confirm = Button.new()
	_confirm.name = "ChooseKingdomButton"
	_confirm.custom_minimum_size.y = 48
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	THEME.apply_primary(_confirm)
	for state: String in ["normal", "hover", "pressed"]:
		var confirm_style: StyleBoxFlat = THEME.button_style("primary", state)
		confirm_style.bg_color = Color("f0cb86") if state == "hover" else GOLD
		confirm_style.border_color = GOLD
		confirm_style.set_corner_radius_all(10)
		confirm_style.border_width_bottom = 1
		_confirm.add_theme_stylebox_override(state, confirm_style)
	_confirm.pressed.connect(_choose)
	footer.add_child(_confirm)
	var focus_order: Array[Control] = []
	for card: Button in _cards:
		focus_order.append(card)
	focus_order.append(cancel)
	focus_order.append(_confirm)
	for index: int in focus_order.size():
		var control: Control = focus_order[index]
		control.focus_next = control.get_path_to(focus_order[(index + 1) % focus_order.size()])
		control.focus_previous = control.get_path_to(focus_order[posmod(index - 1, focus_order.size())])
	select_civilization(selected)
	get_viewport().size_changed.connect(_layout)
	WEB.watch_safe_area(self, _layout)
	_layout()
	for card: Button in _cards:
		if card.button_pressed:
			card.grab_focus()
			break


func _label(text: String, size_value: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size_value)
	return label


func select_civilization(id: int) -> void:
	if _closing:
		return
	selected = CivilizationData.normalize(id)
	var definition: Dictionary = CivilizationData.get_definition(selected)
	for index: int in _cards.size():
		_cards[index].set_pressed_no_signal(CivilizationData.ORDERED_IDS[index] == selected)
	var strengths: Variant = definition.get("strengths", "")
	var strength_text: String = " · ".join(strengths) if strengths is Array or strengths is PackedStringArray else str(strengths)
	_tagline.text = str(definition.tagline)
	_detail.text = "%s\n\nStrengths: %s\nTradeoff: %s\n\nSignature: %s" % [definition.description, strength_text, definition.weakness, definition.signature]
	# Identity uses the same three crests as match setup, not old-theme portraits.
	_portrait.texture = load(str(definition.icon_path))
	_confirm.text = "Confirm kingdom"
	_confirm.accessibility_name = "Confirm " + str(definition.name)
	_scroll.scroll_vertical = 0


func apply_mobile_layout(viewport_size: Vector2, safe_area: Rect2) -> void:
	var safe: Rect2 = safe_area.intersection(Rect2(Vector2.ZERO, viewport_size))
	if not safe.has_area():
		safe = Rect2(Vector2.ZERO, viewport_size)
	var available: Rect2 = safe.grow(-10)
	var width_value: float = minf(900, available.size.x)
	var height_value: float = minf(470, available.size.y)
	_panel.position = available.get_center() - Vector2(width_value, height_value) * 0.5
	_panel.size = Vector2(width_value, height_value)
	var compact: bool = height_value < 400 or width_value < 700
	var panel_style: StyleBoxFlat = _panel.get_theme_stylebox("panel")
	panel_style.set_content_margin_all(12 if compact else 20)
	_title.add_theme_font_size_override("font_size", 18 if compact else 24)
	_tagline.add_theme_font_size_override("font_size", 17 if compact else 21)
	_detail.add_theme_font_size_override("font_size", 14 if compact else 16)
	for card: Button in _cards:
		card.custom_minimum_size.y = 58 if compact else 80
		card.add_theme_font_size_override("font_size", 13 if width_value < 700 else 15)
		card.add_theme_constant_override("icon_max_width", 26 if width_value < 700 else 36)


func _layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, WEB.get_safe_area_rect(viewport_size))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		close()


func _choose() -> void:
	_dismiss(true)


func close() -> void:
	_dismiss(false)


func _dismiss(confirm: bool) -> void:
	if _closing:
		return
	_closing = true
	# Hide before the owner clears its reference. Rapid reopen/confirm cannot
	# leave a second visible modal or commit this queued-for-deletion instance.
	hide()
	set_process_input(false)
	if confirm:
		chosen.emit(selected)
	closed.emit()
	queue_free()
