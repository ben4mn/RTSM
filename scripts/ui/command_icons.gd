class_name CommandIcons
extends RefCounted
## Original, shared command glyphs. Button behavior belongs to the caller.

const ICON_KEYS: PackedStringArray = [
	"build", "base", "economy", "army", "food", "wood", "gold", "population",
	"pause", "resume", "view", "select_area", "clear", "more", "back",
	"zoom_in", "zoom_out", "reset", "center", "move", "attack", "stop",
	"patrol", "stance", "idle", "repeat", "queue", "age_up", "info", "close",
	"check", "group_save", "group_recall", "find", "undo", "rally", "sacred", "farm",
]
const BADGE_NODE_NAME := "CommandIconBadge"
static var _textures: Dictionary = {}


static func get_icon(key: String) -> Texture2D:
	if key not in ICON_KEYS:
		return null
	if not _textures.has(key):
		_textures[key] = load("res://assets/ui/icons/%s.svg" % key) as Texture2D
	return _textures[key] as Texture2D


static func apply(button: Button, key: String, accessible_label: String, caption: String = "") -> void:
	button.icon = get_icon(key)
	button.text = caption
	button.tooltip_text = accessible_label
	button.accessibility_name = accessible_label
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if caption.is_empty() else HORIZONTAL_ALIGNMENT_LEFT
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 26)
	button.add_theme_constant_override("h_separation", 6)
	# Before tree entry, Control lookups can still return the engine fallback
	# even when theme is assigned. Read that resource directly for entries the
	# caller has not overridden; otherwise decoration would freeze the fallback.
	var pending_theme: Theme = button.theme if not button.is_inside_tree() else null
	# Match the theme's pressed/disabled contrast, including amber primary actions.
	for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var font_key: String = "font_color" if state == "normal" else "font_%s_color" % state
		var font_color: Color = button.get_theme_color(font_key)
		if pending_theme != null and not button.has_theme_color_override(font_key) and pending_theme.has_color(font_key, "Button"):
			font_color = pending_theme.get_color(font_key, "Button")
		button.add_theme_color_override("icon_%s_color" % state, font_color)
		var style: StyleBox = button.get_theme_stylebox(state)
		if pending_theme != null and not button.has_theme_stylebox_override(state) and pending_theme.has_stylebox(state, "Button"):
			style = pending_theme.get_stylebox(state, "Button")
		if style.get_content_margin(SIDE_LEFT) == 6.0 and style.get_content_margin(SIDE_TOP) == 4.0:
			continue
		var compact: StyleBox = style.duplicate()
		compact.set_content_margin(SIDE_LEFT, 6.0)
		compact.set_content_margin(SIDE_RIGHT, 6.0)
		compact.set_content_margin(SIDE_TOP, 4.0)
		compact.set_content_margin(SIDE_BOTTOM, 4.0)
		button.add_theme_stylebox_override(state, compact)


static func set_badge(button: Button, text: String, attention: bool = false) -> void:
	var badge: Label = button.get_node_or_null(NodePath(BADGE_NODE_NAME)) as Label
	if badge == null:
		badge = Label.new()
		badge.name = BADGE_NODE_NAME
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 11)
		button.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -28.0
		badge.offset_right = -2.0
		badge.offset_top = 2.0
		badge.offset_bottom = 20.0
	badge.text = text
	badge.visible = not text.is_empty()
	if not badge.has_meta("attention") or bool(badge.get_meta("attention")) != attention:
		badge.set_meta("attention", attention)
		var style := StyleBoxFlat.new()
		style.bg_color = KingdomTheme.AMBER if attention else KingdomTheme.INK
		style.border_color = KingdomTheme.AMBER if attention else KingdomTheme.BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(7)
		style.set_content_margin_all(2)
		badge.add_theme_stylebox_override("normal", style)
		badge.add_theme_color_override("font_color", KingdomTheme.INK if attention else KingdomTheme.PARCHMENT)
