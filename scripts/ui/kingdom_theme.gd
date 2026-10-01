class_name KingdomTheme
extends RefCounted
## Shared visual language for the kingdom, its menus and thumb controls.

const INK := Color("101c2a")
const INK_PANEL := Color("182838")
const INK_LIGHT := Color("24394b")
const PARCHMENT := Color("f2ead8")
const MUTED := Color("a0b2b7")
const AMBER := Color("efbc63")
const TEAL := Color("77c3b8")
const BORDER := Color("38515d")


static func panel_style(background: Color = INK_PANEL, border: Color = BORDER, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(4.0)
	return style


static func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PARCHMENT)
	theme.set_color("font_color", "Button", PARCHMENT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("667b83"))
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	var normal: StyleBoxFlat = panel_style(INK_LIGHT, BORDER, 9)
	normal.set_content_margin(SIDE_LEFT, 12.0)
	normal.set_content_margin(SIDE_RIGHT, 12.0)
	var hover: StyleBoxFlat = panel_style(Color("30495a"), TEAL, 9)
	var pressed: StyleBoxFlat = panel_style(AMBER, AMBER, 9)
	var disabled: StyleBoxFlat = panel_style(Color("14212d"), Color("2a3c47"), 9)
	var focus: StyleBoxFlat = panel_style(Color(0, 0, 0, 0), AMBER, 9)
	focus.set_border_width_all(2)
	for control_type: String in ["Button", "OptionButton", "CheckButton"]:
		theme.set_stylebox("normal", control_type, normal)
		theme.set_stylebox("hover", control_type, hover)
		theme.set_stylebox("pressed", control_type, pressed)
		theme.set_stylebox("hover_pressed", control_type, pressed)
		theme.set_stylebox("disabled", control_type, disabled)
		theme.set_stylebox("focus", control_type, focus)
		theme.set_color("font_color", control_type, PARCHMENT)
		theme.set_color("font_pressed_color", control_type, INK)
		theme.set_color("font_hover_pressed_color", control_type, INK)
		theme.set_color("font_disabled_color", control_type, Color("667b83"))
	# A switched-on preference should stay quieter than the Play/Build action.
	theme.set_stylebox("pressed", "CheckButton", normal)
	theme.set_stylebox("hover_pressed", "CheckButton", hover)
	theme.set_color("font_pressed_color", "CheckButton", PARCHMENT)
	theme.set_color("font_hover_pressed_color", "CheckButton", PARCHMENT)
	theme.set_stylebox("normal", "LineEdit", panel_style(INK, BORDER, 8))
	theme.set_stylebox("focus", "LineEdit", panel_style(INK, TEAL, 8))
	theme.set_color("font_color", "LineEdit", PARCHMENT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", AMBER)
	theme.set_stylebox("panel", "PopupMenu", panel_style())
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_color("font_color", "PopupMenu", PARCHMENT)
	theme.set_stylebox("background", "ProgressBar", panel_style(INK, INK, 4))
	theme.set_stylebox("fill", "ProgressBar", panel_style(TEAL, TEAL, 4))
	return theme


static func apply_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", panel_style(AMBER, AMBER.lightened(0.10), 10))
	button.add_theme_stylebox_override("hover", panel_style(AMBER.lightened(0.12), PARCHMENT, 10))
	button.add_theme_stylebox_override("pressed", panel_style(AMBER.darkened(0.12), AMBER, 10))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)


static func apply_secondary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", panel_style(INK_LIGHT, BORDER, 9))
	button.add_theme_stylebox_override("hover", panel_style(Color("30495a"), TEAL, 9))
	button.add_theme_stylebox_override("pressed", panel_style(TEAL, TEAL, 9))
	button.add_theme_color_override("font_color", PARCHMENT)
	button.add_theme_color_override("font_pressed_color", INK)
