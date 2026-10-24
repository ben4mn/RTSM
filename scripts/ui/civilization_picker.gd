extends ColorRect
## Compare a kingdom's actual tradeoffs before committing the match draft.

signal chosen(civilization: int)
signal closed()

const THEME := preload("res://scripts/ui/kingdom_theme.gd")
const WEB := preload("res://scripts/ui/web_shell_bridge.gd")
var selected: int = 0
var heading: String = "Choose your kingdom"
var _panel: PanelContainer
var _cards: Array[Button] = []
var _title: Label
var _detail: Label
var _portrait: TextureRect
var _signature: Label
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
	color = Color(THEME.INK, 0.97)
	theme = THEME.create_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.name = "KingdomComparison"
	var style: StyleBoxFlat = THEME.panel_style()
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	_title = _label(heading, 22)
	THEME.apply_heading(_title, 22)
	column.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for id: int in CivilizationData.ORDERED_IDS:
		var definition: Dictionary = CivilizationData.get_definition(id)
		var card := Button.new()
		card.name = "Civilization%d" % id
		card.text = str(definition.name)
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
	_signature = _label("", 13)
	_signature.name = "SignatureCaption"
	_signature.custom_minimum_size.x = 116
	_signature.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_signature.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_signature.add_theme_color_override("font_color", THEME.GOLD)
	identity.add_child(_signature)
	_detail = _label("", 16)
	_detail.name = "KingdomTradeoffs"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comparison.add_child(_detail)
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
	_confirm.pressed.connect(_choose)
	footer.add_child(_confirm)
	select_civilization(selected)
	get_viewport().size_changed.connect(_layout)
	WEB.watch_safe_area(self, _layout)
	_layout()


func _label(text: String, size_value: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size_value)
	return label


func select_civilization(id: int) -> void:
	selected = CivilizationData.normalize(id)
	var definition: Dictionary = CivilizationData.get_definition(selected)
	for index: int in _cards.size():
		_cards[index].set_pressed_no_signal(CivilizationData.ORDERED_IDS[index] == selected)
	var strengths: Variant = definition.get("strengths", "")
	var strength_text: String = " · ".join(strengths) if strengths is Array or strengths is PackedStringArray else str(strengths)
	_detail.text = "%s\n%s\n\nStrengths: %s\nTradeoff: %s" % [definition.tagline, definition.description, strength_text, definition.weakness]
	_portrait.texture = load(str(definition.get("preview_unit_icon", "res://assets/units/warrior.svg")))
	_signature.text = str(definition.signature)
	_confirm.text = "Choose " + str(definition.name)
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
	_title.add_theme_font_size_override("font_size", 18 if compact else 24)
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
	if _closing:
		return
	chosen.emit(selected)
	close()


func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
