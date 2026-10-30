extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var button := Button.new()
	button.theme = KingdomTheme.create_theme()
	root.add_child(button)
	CommandIcons.apply_labeled(button, "army", "Army", "Army")
	var states := ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]
	var styles: Array[StyleBox] = []
	for state: String in states: styles.append(button.get_theme_stylebox(state))
	for count: int in 100:
		CommandIcons.apply_labeled(button, "army", "%d fighters" % count, "Army")
		for index: int in states.size():
			assert(button.get_theme_stylebox(states[index]) == styles[index], "Count refresh replaced a style")
	assert(button.accessibility_name == "99 fighters")
	assert(button.get_theme_constant("icon_max_width") == 20)
	assert(styles[0].get_content_margin(SIDE_LEFT) == 3.0)
	CommandIcons.apply_labeled(button, "pause", "Pause", "Pause")
	assert((button.get_theme_stylebox("normal") as StyleBoxFlat).corner_radius_top_left == 24)
	KingdomTheme.apply_primary(button)
	CommandIcons.apply_labeled(button, "army", "Army", "Army")
	assert(button.get_theme_color("icon_normal_color") == KingdomTheme.INK)
	# Beta 25 softened every tile: the shared tile radius is now 16 (was 10).
	assert((button.get_theme_stylebox("normal") as StyleBoxFlat).corner_radius_top_left == CommandIcons.CORNER_RADIUS)
	CommandIcons.apply(button, "attack", "Attack")
	assert(button.get_theme_constant("icon_max_width") == CommandIcons.GLYPH_SIZE)
	assert(button.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT) == 6.0)
	assert(button.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER)
	button.free()
	print("[PASS] command_icon_reuse:600 stable style identities; live count, shape, theme and labeled/plain transitions")
	quit()
