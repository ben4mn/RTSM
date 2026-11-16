class_name KingdomTheme
extends RefCounted
## Shared illustrated-world palette: forest cloth, warm paper and honey actions.

const INK := Color("1d302c")
const INK_PANEL := Color("2b4239")
const INK_LIGHT := Color("3b5548")
const PARCHMENT := Color("f4eddd")
const MUTED := Color("bec9b8")
const RUST := Color("df947f")
const GOLD := Color("e8bf77")
const AMBER := GOLD
const TEAL := Color("b1ceb4")
const BORDER := Color("617467")
const PAPER := Color("e7dfc9")
const PAPER_INK := Color("354638")
const FONT_BODY := preload("res://assets/fonts/Barlow-Regular.ttf")
const FONT_MEDIUM := preload("res://assets/fonts/Barlow-Medium.ttf")
const FONT_HEADING := preload("res://assets/fonts/Cinzel.ttf")
## Soft, pebble-like corners: a 48px control reads as a rounded pill, never a box.
const BUTTON_RADIUS := 18
const PANEL_RADIUS := 18
const PILL_RADIUS := 24


## Maps an older tight radius onto the softer scale (10 -> 16, 12 -> 18, 24 -> 24).
static func soft_radius(radius: int) -> int:
	return clampi(radius + 6, 16, PILL_RADIUS) if radius > 0 else 0


static func panel_style(background: Color = INK_PANEL, border: Color = BORDER, radius: int = PANEL_RADIUS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.corner_detail = 10
	style.set_content_margin_all(4.0)
	return style


static func button_style(kind: String = "secondary", state: String = "normal") -> StyleBoxFlat:
	var primary: bool = kind == "primary"
	var background: Color = AMBER if primary else INK_LIGHT
	var border: Color = AMBER if primary else BORDER
	match state:
		"hover":
			background = Color("f0cb86") if primary else Color("4a6553")
			border = PARCHMENT if primary else AMBER
		"pressed":
			background = Color("b99554") if primary else AMBER
			border = PARCHMENT
		"disabled":
			background = Color("263a32")
			border = Color("4f6358")
		"focus":
			background = Color.TRANSPARENT
			border = PARCHMENT
	var style: StyleBoxFlat = panel_style(background, border, BUTTON_RADIUS)
	style.border_width_bottom = 2
	if state == "focus":
		style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func apply_heading(label: Label, size: int = 24) -> void:
	label.add_theme_font_override("font", FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", PARCHMENT)


static func apply_eyebrow(label: Label) -> void:
	label.add_theme_font_override("font", FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", AMBER)


static func inset_panel() -> StyleBoxFlat:
	var style: StyleBoxFlat = panel_style(INK, BORDER)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


static func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = FONT_BODY
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PARCHMENT)
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "AcceptDialog", inset_panel())
	theme.set_constant("buttons_min_width", "AcceptDialog", 104)
	theme.set_constant("buttons_min_height", "AcceptDialog", 48)
	var window_frame := panel_style(INK_PANEL, BORDER, 12)
	window_frame.content_margin_top = 32
	theme.set_stylebox("embedded_border", "Window", window_frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", window_frame)
	theme.set_color("title_color", "Window", PARCHMENT)
	theme.set_font("title_font", "Window", FONT_MEDIUM)
	var normal: StyleBoxFlat = button_style()
	var hover: StyleBoxFlat = button_style("secondary", "hover")
	var pressed: StyleBoxFlat = button_style("secondary", "pressed")
	var disabled: StyleBoxFlat = button_style("secondary", "disabled")
	var focus: StyleBoxFlat = button_style("secondary", "focus")
	for control_type: String in ["Button", "OptionButton", "CheckButton"]:
		theme.set_font("font", control_type, FONT_MEDIUM)
		theme.set_stylebox("normal", control_type, normal)
		theme.set_stylebox("hover", control_type, hover)
		theme.set_stylebox("pressed", control_type, pressed)
		theme.set_stylebox("hover_pressed", control_type, pressed)
		theme.set_stylebox("disabled", control_type, disabled)
		theme.set_stylebox("focus", control_type, focus)
		theme.set_color("font_color", control_type, PARCHMENT)
		theme.set_color("font_hover_color", control_type, Color.WHITE)
		theme.set_color("font_focus_color", control_type, PARCHMENT)
		theme.set_color("font_pressed_color", control_type, INK)
		theme.set_color("font_hover_pressed_color", control_type, INK)
		theme.set_color("font_disabled_color", control_type, Color("9cae9f"))
		theme.set_color("icon_normal_color", control_type, Color.WHITE)
		theme.set_color("icon_hover_color", control_type, Color.WHITE)
		theme.set_color("icon_pressed_color", control_type, INK)
		theme.set_color("icon_hover_pressed_color", control_type, INK)
		theme.set_color("icon_disabled_color", control_type, Color("9cae9f"))
	# Preferences read as a quiet row, with the switch carrying its state.
	var preference: StyleBoxFlat = panel_style(Color.TRANSPARENT, Color.TRANSPARENT, 0)
	theme.set_stylebox("normal", "CheckButton", preference)
	theme.set_stylebox("hover", "CheckButton", preference)
	theme.set_stylebox("pressed", "CheckButton", preference)
	theme.set_stylebox("hover_pressed", "CheckButton", preference)
	theme.set_color("font_pressed_color", "CheckButton", PARCHMENT)
	theme.set_color("font_hover_pressed_color", "CheckButton", PARCHMENT)
	theme.set_icon("checked", "CheckButton", preload("res://assets/ui/atlas_toggle_on.svg"))
	theme.set_icon("unchecked", "CheckButton", preload("res://assets/ui/atlas_toggle_off.svg"))
	for state: String in ["normal", "focus", "read_only"]:
		var input_style: StyleBoxFlat = panel_style(INK, TEAL if state == "focus" else BORDER, 8)
		input_style.content_margin_left = 12
		input_style.content_margin_right = 12
		theme.set_stylebox(state, "LineEdit", input_style)
	theme.set_color("font_color", "LineEdit", PARCHMENT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", TEAL)
	theme.set_stylebox("panel", "PopupMenu", panel_style())
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_color("font_color", "PopupMenu", PARCHMENT)
	theme.set_color("font_hover_color", "PopupMenu", PARCHMENT)
	theme.set_color("font_disabled_color", "PopupMenu", MUTED)
	theme.set_color("font_accelerator_color", "PopupMenu", MUTED)
	theme.set_font("font", "PopupMenu", FONT_MEDIUM)
	theme.set_font_size("font_size", "PopupMenu", 18)
	theme.set_constant("v_separation", "PopupMenu", 26)
	theme.set_constant("h_separation", "PopupMenu", 12)
	var scroll_track := panel_style(INK, Color.TRANSPARENT, 5)
	var scroll_grab := panel_style(BORDER, Color.TRANSPARENT, 5)
	for kind: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", kind, scroll_track)
		theme.set_stylebox("grabber", kind, scroll_grab)
		theme.set_stylebox("grabber_highlight", kind, panel_style(TEAL, Color.TRANSPARENT, 5))
		theme.set_stylebox("grabber_pressed", kind, panel_style(GOLD, Color.TRANSPARENT, 5))
	var slider_track: StyleBoxFlat = panel_style(BORDER, BORDER, 2)
	slider_track.content_margin_top = 2.0
	slider_track.content_margin_bottom = 2.0
	var slider_fill: StyleBoxFlat = slider_track.duplicate()
	slider_fill.bg_color = TEAL
	slider_fill.border_color = TEAL
	theme.set_stylebox("slider", "HSlider", slider_track)
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	theme.set_icon("grabber", "HSlider", preload("res://assets/ui/atlas_slider_grabber.svg"))
	theme.set_icon("grabber_highlight", "HSlider", preload("res://assets/ui/atlas_slider_grabber_active.svg"))
	theme.set_icon("grabber_disabled", "HSlider", preload("res://assets/ui/atlas_slider_grabber.svg"))
	theme.set_stylebox("background", "ProgressBar", panel_style(INK, INK, 2))
	theme.set_stylebox("fill", "ProgressBar", panel_style(TEAL, TEAL, 2))
	return theme


static func apply_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", button_style("primary"))
	button.add_theme_stylebox_override("hover", button_style("primary", "hover"))
	button.add_theme_stylebox_override("pressed", button_style("primary", "pressed"))
	button.add_theme_font_override("font", FONT_MEDIUM)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)


static func apply_secondary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", button_style())
	button.add_theme_stylebox_override("hover", button_style("secondary", "hover"))
	button.add_theme_stylebox_override("pressed", button_style("secondary", "pressed"))
	button.add_theme_color_override("font_color", PARCHMENT)
	button.add_theme_color_override("font_pressed_color", INK)


# ---------------------------------------------------------------------------
# Menu family: the one source for out-of-match screens and modal cards.
#
#   Title          Cinzel, parchment          apply_title()
#   Section label  Barlow Medium caps, gold   apply_section_label()
#   Note           Barlow, muted              apply_note()
#   Primary        gold hex plaque, ONE per screen      apply_menu_primary()
#   Secondary      dark cloth pill            apply_menu_secondary()
#   Tertiary       quiet text pill            apply_tertiary()
#   Icon           48px round cloth button    apply_icon_button()
#   Choice         soft segment; gold rim when selected   apply_choice()
#   Field          soft rect (dropdown, disclosure row)   apply_field()
#   Card           cloth surface              card_style() / apply_card_button()
#   Modal          raised card over a scrim   modal_style(), SCRIM
#   Header bar     back pill + title + utilities         make_header_bar()
# The older helpers above stay unchanged for the HUD.
# ---------------------------------------------------------------------------

const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 12
const SPACE_L := 16
const SPACE_XL := 24
const CONTROL_HEIGHT := 48
const TITLE_SIZE := 24
const TITLE_SIZE_COMPACT := 19
const SECTION_SIZE := 12
const NOTE_SIZE := 13
const MODAL_RADIUS := 22
const CLOTH_HOVER := Color("4a6553")
const SCRIM := Color(0.114, 0.188, 0.173, 0.94)
const FLAT_STATES: Array[String] = ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]

static var _section_font: FontVariation


static func apply_title(label: Label, size: int = TITLE_SIZE, color: Color = PARCHMENT) -> void:
	label.add_theme_font_override("font", FONT_HEADING)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


static func section_font() -> FontVariation:
	if _section_font == null:
		_section_font = FontVariation.new()
		_section_font.base_font = FONT_MEDIUM
		_section_font.spacing_glyph = 1
	return _section_font


static func apply_section_label(label: Label, size: int = SECTION_SIZE) -> void:
	label.text = label.text.to_upper()
	label.add_theme_font_override("font", section_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", GOLD)


static func apply_note(label: Label, size: int = NOTE_SIZE) -> void:
	label.add_theme_font_override("font", FONT_BODY)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", MUTED)


## The gold hex plaque. Focus reuses the hover plate so the shape never changes.
static func plaque_style(state: String = "normal") -> StyleBoxTexture:
	var plate: String = state
	if state == "focus":
		plate = "hover"
	elif state == "hover_pressed":
		plate = "pressed"
	var plaque := StyleBoxTexture.new()
	plaque.texture = load("res://assets/ui/plates/primary_%s.svg" % plate)
	plaque.texture_margin_left = 20
	plaque.texture_margin_right = 20
	plaque.texture_margin_top = 12
	plaque.texture_margin_bottom = 12
	plaque.content_margin_left = 24
	plaque.content_margin_right = 24
	plaque.content_margin_top = 10
	plaque.content_margin_bottom = 12
	return plaque


static func apply_menu_primary(button: Button) -> void:
	for state: String in FLAT_STATES:
		button.add_theme_stylebox_override(state, plaque_style(state))
	button.add_theme_font_override("font", FONT_MEDIUM)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, CONTROL_HEIGHT)


static func pill_style(state: String = "normal", radius: int = PILL_RADIUS) -> StyleBoxFlat:
	var background: Color = INK_PANEL
	var border: Color = BORDER
	match state:
		"hover":
			background = CLOTH_HOVER
			border = GOLD
		"pressed", "hover_pressed":
			background = INK_LIGHT
			border = GOLD
		"disabled":
			background = Color(INK_PANEL, 0.55)
			border = Color("4f6358")
		"focus":
			background = Color.TRANSPARENT
			border = PARCHMENT
	var style: StyleBoxFlat = panel_style(background, border, radius)
	style.set_border_width_all(2 if state == "focus" else 1)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func _apply_flat_states(button: Button, styles: Dictionary, text: Color, pressed_text: Color) -> void:
	for state: String in styles:
		button.add_theme_stylebox_override(state, styles[state])
	button.add_theme_font_override("font", FONT_MEDIUM)
	for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(state, text)
	button.add_theme_color_override("font_pressed_color", pressed_text)
	button.add_theme_color_override("font_hover_pressed_color", pressed_text)
	button.add_theme_color_override("font_disabled_color", Color("9cae9f"))
	# Crests and glyphs keep their own colour in every state.
	for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)


static func apply_menu_secondary(button: Button) -> void:
	var styles: Dictionary = {}
	for state: String in FLAT_STATES:
		styles[state] = pill_style(state)
	_apply_flat_states(button, styles, PARCHMENT, PARCHMENT)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, CONTROL_HEIGHT)


static func apply_tertiary(button: Button) -> void:
	var styles: Dictionary = {}
	for state: String in FLAT_STATES:
		var style: StyleBoxFlat = pill_style(state)
		if state in ["normal", "disabled"]:
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color.TRANSPARENT
		elif state != "focus":
			style.border_color = Color.TRANSPARENT
		styles[state] = style
	_apply_flat_states(button, styles, TEAL, PARCHMENT)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, CONTROL_HEIGHT)


static func apply_icon_button(button: Button, icon: Texture2D = null, label_text: String = "") -> void:
	var styles: Dictionary = {}
	for state: String in FLAT_STATES:
		var style: StyleBoxFlat = pill_style(state)
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		styles[state] = style
	_apply_flat_states(button, styles, PARCHMENT, PARCHMENT)
	if icon != null:
		button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 22)
	button.custom_minimum_size = Vector2(maxf(button.custom_minimum_size.x, CONTROL_HEIGHT), maxf(button.custom_minimum_size.y, CONTROL_HEIGHT))
	if not label_text.is_empty():
		button.tooltip_text = label_text
		button.accessibility_name = label_text


## Selectable segment (tabs, difficulty, population, kingdom cards).
static func choice_style(state: String = "normal") -> StyleBoxFlat:
	var style: StyleBoxFlat = pill_style(state, BUTTON_RADIUS)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	match state:
		"pressed", "hover_pressed":
			style.bg_color = INK_LIGHT
			style.border_color = GOLD
			style.set_border_width_all(2)
		"hover":
			style.border_color = Color(GOLD, 0.7)
	return style


static func apply_choice(button: Button) -> void:
	var styles: Dictionary = {}
	for state: String in FLAT_STATES:
		styles[state] = choice_style(state)
	_apply_flat_states(button, styles, PARCHMENT, GOLD)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, CONTROL_HEIGHT)


## Dropdowns, disclosure rows and text inputs share one soft field shape.
static func field_style(state: String = "normal") -> StyleBoxFlat:
	var style: StyleBoxFlat = choice_style("hover" if state in ["pressed", "hover_pressed"] else state)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	if state == "normal":
		style.bg_color = INK_LIGHT
	return style


static func apply_field(button: Button) -> void:
	var styles: Dictionary = {}
	for state: String in FLAT_STATES:
		styles[state] = field_style(state)
	_apply_flat_states(button, styles, PARCHMENT, PARCHMENT)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, CONTROL_HEIGHT)


static func card_style(selected: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = panel_style(INK_LIGHT if selected else INK_PANEL, GOLD if selected else BORDER, PANEL_RADIUS)
	if selected:
		style.set_border_width_all(2)
	style.content_margin_left = SPACE_M
	style.content_margin_right = SPACE_M
	style.content_margin_top = SPACE_M
	style.content_margin_bottom = SPACE_M
	return style


## A whole tappable card (map style, kingdom summary). Selected = gold rim.
static func apply_card_button(button: Button) -> void:
	var hover: StyleBoxFlat = card_style()
	hover.bg_color = CLOTH_HOVER
	hover.border_color = Color(GOLD, 0.7)
	var styles: Dictionary = {
		"normal": card_style(), "hover": hover, "pressed": card_style(true), "hover_pressed": card_style(true),
		"disabled": card_style(), "focus": pill_style("focus", PANEL_RADIUS),
	}
	_apply_flat_states(button, styles, PARCHMENT, PARCHMENT)


static func modal_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = panel_style(INK_PANEL, Color("6f8574"), MODAL_RADIUS)
	style.border_width_top = 2
	style.shadow_color = Color(0.02, 0.05, 0.04, 0.45)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 4)
	style.set_content_margin_all(SPACE_L)
	return style


## Header bar: optional back pill, title, then trailing utilities (icon buttons
## or reserved space). Callers keep their own references to the children.
static func make_header_bar(title: Label, back: Button = null, trailing: Array = []) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "HeaderBar"
	bar.add_theme_constant_override("separation", SPACE_L)
	if back != null:
		apply_menu_secondary(back)
		bar.add_child(back)
	apply_title(title)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(title)
	for control: Variant in trailing:
		if control is Control:
			bar.add_child(control as Control)
	return bar


## Footer: quiet action(s) on the left, the one primary on the right.
static func make_footer(leading: Array = [], primary: Button = null) -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", SPACE_S)
	for control: Variant in leading:
		if control is Control:
			footer.add_child(control as Control)
	var spacer := Control.new()
	spacer.name = "FooterSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)
	if primary != null:
		apply_menu_primary(primary)
		primary.custom_minimum_size.x = maxf(primary.custom_minimum_size.x, 150)
		footer.add_child(primary)
	return footer


## Theme for a menu surface: create_theme() with pills as the default Button,
## soft fields for dropdowns and inputs, and cloth popups.
static func create_menu_theme() -> Theme:
	var result: Theme = create_theme()
	for state: String in FLAT_STATES:
		result.set_stylebox(state, "Button", pill_style(state))
		result.set_stylebox(state, "OptionButton", field_style(state))
	for control_type: String in ["Button", "OptionButton"]:
		for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			result.set_color(state, control_type, PARCHMENT)
	for state: String in ["normal", "focus", "read_only"]:
		var input: StyleBoxFlat = field_style("focus" if state == "focus" else "normal")
		input.bg_color = INK
		input.border_color = TEAL if state == "focus" else BORDER
		input.set_border_width_all(1)
		result.set_stylebox(state, "LineEdit", input)
	result.set_stylebox("panel", "PopupMenu", panel_style(INK_PANEL, BORDER, 14))
	return result
