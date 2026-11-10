extends RefCounted
## The on-screen age-up moment (Round 2 workstream B): a short banner with the
## new age's name over the upper third of the field. It never takes input, so
## play continues underneath, and it removes itself after a few seconds.

const NODE_NAME: String = "AgeCeremony"
const HOLD_SECONDS: float = 2.6
const UNLOCK_COPY: Dictionary = {
	2: "Archery Range, Stable, Watch Tower and new research unlocked",
	3: "Siege Workshop and the elite upgrades unlocked",
}


static func play(hud: Node, age: int) -> void:
	if hud == null or not hud.is_inside_tree():
		return
	var previous: Node = hud.get_node_or_null(NODE_NAME)
	if previous != null:
		previous.name = "RetiredAgeCeremony"
		previous.queue_free()
	var root := Control.new()
	root.name = NODE_NAME
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(root)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.anchor_right = 1.0
	center.anchor_top = 0.16
	center.anchor_bottom = 0.52
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = KingdomTheme.panel_style(Color(KingdomTheme.INK, 0.93), KingdomTheme.GOLD, 14)
	style.border_width_left = 0
	style.border_width_right = 0
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 22.0
	style.content_margin_right = 26.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 9.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var banner_path: String = str(BuildingBase.AGE_BANNER_TEXTURES.get(age, ""))
	if not banner_path.is_empty() and ResourceLoader.exists(banner_path):
		var banner := TextureRect.new()
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.texture = load(banner_path)
		banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		banner.custom_minimum_size = Vector2(36, 48)
		row.add_child(banner)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", -2)
	row.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "A NEW AGE"
	eyebrow.add_theme_font_override("font", KingdomTheme.FONT_MEDIUM)
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", KingdomTheme.GOLD)
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = GameManager.get_age_name(age)
	title.add_theme_font_override("font", KingdomTheme.FONT_HEADING)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
	column.add_child(title)
	var unlocks := Label.new()
	unlocks.text = str(UNLOCK_COPY.get(age, "New buildings, units and research unlocked"))
	unlocks.add_theme_font_override("font", KingdomTheme.FONT_BODY)
	unlocks.add_theme_font_size_override("font_size", 12)
	unlocks.add_theme_color_override("font_color", KingdomTheme.MUTED)
	column.add_child(unlocks)

	root.modulate.a = 0.0
	var tween: Tween = root.create_tween()
	if not GameManager.reduced_motion:
		# Settle in from slightly large; the pivot needs the laid-out size.
		panel.scale = Vector2(1.08, 1.08)
		panel.resized.connect(func() -> void: panel.pivot_offset = panel.size * 0.5)
		tween.set_parallel(true)
		tween.tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "modulate:a", 1.0, 0.3)
	tween.set_parallel(false)
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(root, "modulate:a", 0.0, 0.6)
	tween.tween_callback(root.queue_free)
