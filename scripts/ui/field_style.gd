class_name FieldStyle
extends RefCounted
## Quiet cloth surfaces and tactile silhouettes for the illustrated battlefield.
## Decoration only: hit rectangles, input ownership and game actions stay intact.

const CLOTH := KingdomTheme.INK_PANEL
const CLOTH_LIGHT := KingdomTheme.INK_LIGHT
const STITCH := KingdomTheme.BORDER


static func surface(radius: int = 14) -> StyleBoxFlat:
	var style := KingdomTheme.panel_style(CLOTH, STITCH, radius + 6)
	style.border_color = STITCH
	style.shadow_color = Color(0.04, 0.08, 0.07, 0.22)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style


static func soften(button: Button, radius: int = 12, cloth: bool = false) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var original: StyleBox = button.get_theme_stylebox(state)
		if not original is StyleBoxFlat:
			continue
		var style := original.duplicate() as StyleBoxFlat
		style.set_corner_radius_all(KingdomTheme.soft_radius(radius))
		if cloth and state in ["normal", "hover"]:
			style.bg_color = CLOTH_LIGHT if state == "hover" else CLOTH
			style.border_color = KingdomTheme.GOLD if state == "hover" else STITCH
		button.add_theme_stylebox_override(state, style)


static func production_meter(button: Button, progress: float) -> void:
	## A quiet inset seam shows active training beside its portrait. Queued count
	## remains separate; no progress is inferred for waiting or blocked units.
	var meter := button.get_node_or_null("ProductionSeam") as ProgressBar
	if meter == null:
		meter = ProgressBar.new()
		meter.name = "ProductionSeam"
		meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.show_percentage = false
		meter.max_value = 1.0
		meter.add_theme_stylebox_override("background", KingdomTheme.panel_style(KingdomTheme.INK, Color.TRANSPARENT, 3))
		meter.add_theme_stylebox_override("fill", KingdomTheme.panel_style(KingdomTheme.GOLD, Color.TRANSPARENT, 3))
		button.add_child(meter)
		meter.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		meter.offset_left = 10
		meter.offset_right = -10
		meter.offset_top = -6
		meter.offset_bottom = -2
		# Border/margins must not set a minimum larger than the three-pixel seam.
		for state: String in ["background", "fill"]:
			var style := meter.get_theme_stylebox(state) as StyleBoxFlat
			style.set_content_margin_all(0)
			style.set_border_width_all(0)
		meter.custom_minimum_size = Vector2.ZERO
	meter.visible = progress >= 0.0
	meter.value = clampf(progress, 0.0, 1.0)
	meter.accessibility_name = "Training %d percent" % int(meter.value * 100)
