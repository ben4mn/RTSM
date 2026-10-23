class_name KingdomTheme
extends RefCounted
## Illuminated command atlas: navy surfaces, parchment type, antique-gold actions.

const INK := Color("101c2c")
const INK_PANEL := Color("192a3c")
const INK_LIGHT := Color("24394c")
const PARCHMENT := Color("f2e6c9")
const MUTED := Color("aeb8c0")
const RUST := Color("df947f")
const GOLD := Color("d8b36b")
const AMBER := GOLD
const TEAL := Color("9fc7d0")
const BORDER := Color("455a6a")
const FONT_BODY := preload("res://assets/fonts/Barlow-Regular.ttf")
const FONT_MEDIUM := preload("res://assets/fonts/Barlow-Medium.ttf")
const FONT_HEADING := preload("res://assets/fonts/Cinzel.ttf")


static func panel_style(background: Color = INK_PANEL, border: Color = BORDER, radius: int = 2) -> StyleBoxFlat:
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
			background = Color("edcb85") if primary else Color("304b60")
			border = PARCHMENT if primary else AMBER
		"pressed":
			background = Color("b99554") if primary else AMBER
			border = PARCHMENT
		"disabled":
			background = Color("192636")
			border = Color("354656")
		"focus":
			background = Color.TRANSPARENT
			border = PARCHMENT
	var style: StyleBoxFlat = panel_style(background, border, 2)
	style.border_width_bottom = 2
	if state == "focus":
		style.set_border_width_all(2)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func apply_heading(label: Label, size: int = 24) -> void:
	label.add_theme_font_override("font", FONT_HEADING)
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
		theme.set_color("font_disabled_color", control_type, Color("747e7f"))
		theme.set_color("icon_normal_color", control_type, Color.WHITE)
		theme.set_color("icon_hover_color", control_type, Color.WHITE)
		theme.set_color("icon_pressed_color", control_type, INK)
		theme.set_color("icon_hover_pressed_color", control_type, INK)
		theme.set_color("icon_disabled_color", control_type, Color("747e7f"))
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
	theme.set_stylebox("normal", "LineEdit", panel_style(INK, BORDER, 3))
	theme.set_stylebox("focus", "LineEdit", panel_style(INK, TEAL, 3))
	theme.set_color("font_color", "LineEdit", PARCHMENT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", TEAL)
	theme.set_stylebox("panel", "PopupMenu", panel_style())
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_color("font_color", "PopupMenu", PARCHMENT)
	theme.set_font_size("font_size", "PopupMenu", 18)
	theme.set_constant("v_separation", "PopupMenu", 28)
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
