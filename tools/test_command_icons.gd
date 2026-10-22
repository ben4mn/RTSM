extends Node
## The shared icon decorator must never change action state or enlarge targets.

var _failures: Array[String] = []


func _ready() -> void:
	for key: String in CommandIcons.ICON_KEYS:
		var texture: Texture2D = CommandIcons.get_icon(key)
		_expect(texture != null and texture.get_size() == Vector2(32, 32), "%s glyph missing or wrong source size" % key)
		_expect(texture == CommandIcons.get_icon(key), "%s texture was not cached" % key)
	_expect(CommandIcons.get_icon("unknown") == null, "unknown key should have no glyph")
	_check_pre_tree_theme(false)
	_check_pre_tree_theme(true)
	var button := Button.new()
	button.theme = KingdomTheme.create_theme()
	button.custom_minimum_size = Vector2(48, 48)
	button.toggle_mode = true
	button.set_pressed_no_signal(true)
	button.disabled = true
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(button)
	CommandIcons.apply(button, "build", "Build a structure")
	_expect(button.disabled and button.toggle_mode and button.button_pressed, "decoration changed action state")
	_expect(button.vertical_icon_alignment == VERTICAL_ALIGNMENT_TOP, "decoration changed caller's vertical alignment")
	_expect(button.text.is_empty() and button.accessibility_name == "Build a structure" and button.tooltip_text == button.accessibility_name, "icon-only action lost its accessible label")
	_expect(button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER and not button.expand_icon and button.get_theme_constant("icon_max_width") == 24, "icon-only geometry changed")
	CommandIcons.apply(button, "build", "Build a structure", "Build")
	_expect(button.icon_alignment == HORIZONTAL_ALIGNMENT_LEFT, "caption and glyph overlap")
	_expect(button.get_theme_color("icon_pressed_color") == button.get_theme_color("font_pressed_color"), "pressed icon contrast differs from text")
	var minimum_before: Vector2 = button.get_combined_minimum_size()
	for count: int in 200:
		CommandIcons.set_badge(button, str(count) if count % 2 == 0 else "", count % 3 == 0)
	_expect(button.get_child_count() == 1, "repeated badge updates accumulated nodes")
	_expect(button.get_combined_minimum_size() == minimum_before, "badge inflated button minimum size")
	var badge: Label = button.get_node(CommandIcons.BADGE_NODE_NAME)
	_expect(badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "badge intercepts action input")
	CommandIcons.set_badge(button, "4", true)
	_expect(badge.visible and badge.text == "4", "badge count failed to refresh")
	CommandIcons.set_badge(button, "")
	_expect(not badge.visible, "empty badge remains visible")
	button.free()
	if _failures.is_empty():
		print("[PASS] command_icons: all 38 cached glyphs, accessible actions, pre-tree theme/override preservation, preserved state and stable nonblocking badges")
	else:
		for failure: String in _failures:
			push_error("[FAIL] command_icons: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_pre_tree_theme(primary: bool) -> void:
	var button := Button.new()
	button.theme = KingdomTheme.create_theme()
	if primary:
		KingdomTheme.apply_primary(button)
	else:
		KingdomTheme.apply_secondary(button)
	var expected_normal: StyleBoxTexture = button.get_theme_stylebox("normal") as StyleBoxTexture
	var expected_selected: StyleBoxTexture = button.theme.get_stylebox("hover_pressed", "Button") as StyleBoxTexture
	var normal_ink: Color = KingdomTheme.INK if primary else KingdomTheme.PARCHMENT
	CommandIcons.apply(button, "economy", "Economy")
	_expect(not button.is_inside_tree(), "theme regression fixture must decorate before tree entry")
	var hovered: StyleBox = button.get_theme_stylebox("hover_pressed")
	_expect(hovered is StyleBoxTexture and expected_selected != null and (hovered as StyleBoxTexture).texture == expected_selected.texture, "pre-tree decoration froze the engine fallback instead of the selected plate")
	_expect(button.get_theme_color("icon_hover_pressed_color").is_equal_approx(KingdomTheme.INK), "pre-tree decoration froze fallback selected icon contrast")
	var normal: StyleBoxTexture = button.get_theme_stylebox("normal") as StyleBoxTexture
	_expect(normal != null and expected_normal != null and normal.texture == expected_normal.texture and button.get_theme_color("icon_normal_color").is_equal_approx(normal_ink), "explicit primary/secondary plate or icon contrast was replaced by the pending theme")
	if normal != null and expected_normal != null:
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_expect(is_equal_approx(normal.get_texture_margin(side), expected_normal.get_texture_margin(side)), "decoration changed the nine-slice plate border")
	add_child(button)
	_expect(button.get_theme_stylebox("hover_pressed") == hovered and button.get_theme_color("font_hover_pressed_color").is_equal_approx(button.get_theme_color("icon_hover_pressed_color")), "tree entry changes the captured style or exposes mismatched selected contrast")
	button.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
