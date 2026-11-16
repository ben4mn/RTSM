extends Control
## The ring around the top bar's age chip: how much of the next age's cost is
## banked, or how far the running age-up has come. Drawn under the chip's
## numeral; never takes input.

const TRACK_WIDTH: float = 3.0

var progress: float = 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if not is_equal_approx(value, progress):
			progress = value
			queue_redraw()
var color: Color = KingdomTheme.GOLD:
	set(value):
		if value != color:
			color = value
			queue_redraw()
var track_color: Color = Color(KingdomTheme.BORDER, 0.7):
	set(value):
		if value != track_color:
			track_color = value
			queue_redraw()
var fill: Color = Color(KingdomTheme.INK, 0.94):
	set(value):
		if value != fill:
			fill = value
			queue_redraw()


func _init() -> void:
	name = "AgeRing"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true


func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5 - TRACK_WIDTH * 0.5 - 1.0
	if radius <= 2.0:
		return
	var center: Vector2 = size * 0.5
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 48, track_color, TRACK_WIDTH, true)
	if progress > 0.0:
		var start: float = -PI * 0.5
		draw_arc(center, radius, start, start + TAU * progress, maxi(8, roundi(48.0 * progress)), color, TRACK_WIDTH, true)
