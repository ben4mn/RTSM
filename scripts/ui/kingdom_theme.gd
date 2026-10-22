class_name KingdomTheme
extends RefCounted
## Field-atlas typography and restrained, high-contrast touch controls.

const INK := Color("171c1d")
const INK_PANEL := Color("202729")
const INK_LIGHT := Color("293235")
const PARCHMENT := Color("e8e5db")
const MUTED := Color("a6afad")
const RUST := Color("d69477")
const AMBER := RUST # Compatibility name for existing notices and accents.
const TEAL := Color("88b7ad")
const BORDER := Color("465150")
const FONT_BODY := preload("res://assets/fonts/Barlow-Regular.ttf")
const FONT_MEDIUM := preload("res://assets/fonts/Barlow-Medium.ttf")
const FONT_HEADING := preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")


static func panel_style(background: Color = INK_PANEL, border: Color = BORDER, radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(4.0)
	return style


static func button_style(kind: String = "secondary", state: String = "normal") -> StyleBoxTexture:
	var family: String = kind if kind in ["primary", "secondary"] else "secondary"
	var variant: String = state if state in ["normal", "hover", "pressed", "disabled", "focus"] else "normal"
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/ui/plates/%s_%s.svg" % [family, variant]) as Texture2D
	for side: int in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_texture_margin(side, 12.0)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


static func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = FONT_BODY
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PARCHMENT)
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	var normal: StyleBoxTexture = button_style()
	var hover: StyleBoxTexture = button_style("secondary", "hover")
	var pressed: StyleBoxTexture = button_style("secondary", "pressed")
	var disabled: StyleBoxTexture = button_style("secondary", "disabled")
	var focus: StyleBoxTexture = button_style("secondary", "focus")
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
