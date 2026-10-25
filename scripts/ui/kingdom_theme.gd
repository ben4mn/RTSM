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


static func panel_style(background: Color = INK_PANEL, border: Color = BORDER, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
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
	var style: StyleBoxFlat = panel_style(background, border, 10)
	style.border_width_bottom = 2
	if state == "focus":
		style.set_border_width_all(2)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
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
