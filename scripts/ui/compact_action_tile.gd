extends RefCounted
## Shared icon-and-cost targets. Decorative children never own touch contacts.
static func apply(button: Button, portrait: Texture2D, cost: Dictionary, extent: Vector2 = Vector2(76, 60), caption: String = "") -> void:
	button.text = ""
	button.icon = null
	button.custom_minimum_size = extent
	var art: TextureRect = button.get_node_or_null("TilePortrait")
	if art == null:
		art = TextureRect.new()
		art.name = "TilePortrait"
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		button.add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.offset_left = 7
		art.offset_right = -7
		art.offset_top = 3
		art.offset_bottom = -19
	art.texture = portrait
	# An optional name line keeps look-alike buildings apart at a glance.
	var name_label: Label = button.get_node_or_null("TileName")
	if caption != "" and name_label == null:
		name_label = Label.new()
		name_label.name = "TileName"
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_child(name_label)
		name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		name_label.offset_top = 1
		name_label.offset_bottom = 14
	if name_label != null:
		name_label.visible = caption != ""
		name_label.text = caption
	art.offset_top = 15 if caption != "" else 3
	var costs: HBoxContainer = button.get_node_or_null("TileCosts")
	if costs == null:
		costs = HBoxContainer.new()
		costs.name = "TileCosts"
		costs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		costs.alignment = BoxContainer.ALIGNMENT_CENTER
		costs.add_theme_constant_override("separation", 3)
		button.add_child(costs)
		costs.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		costs.offset_top = -18
		costs.offset_bottom = -3
		for resource: String in ["food", "wood", "gold"]:
			var chip := HBoxContainer.new()
			chip.name = resource
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_theme_constant_override("separation", 1)
			costs.add_child(chip)
			var icon := TextureRect.new()
			icon.texture = CommandIcons.get_icon(resource)
			icon.custom_minimum_size = Vector2(10, 12)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(icon)
			var amount := Label.new()
			amount.name = "Amount"
			amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
			amount.add_theme_font_size_override("font_size", 10)
			chip.add_child(amount)
	for resource: String in ["food", "wood", "gold"]:
		var chip: Control = costs.get_node(resource)
		chip.visible = int(cost.get(resource, 0)) > 0
		chip.get_node("Amount").text = str(cost.get(resource, 0))
	FieldStyle.soften(button, 14, true)

static func chevron(collapsed: bool) -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#eadfbd" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>' % ("M6 15l6-6 6 6" if collapsed else "M6 9l6 6 6-6"))
	return ImageTexture.create_from_image(image)
