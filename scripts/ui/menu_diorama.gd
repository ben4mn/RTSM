extends Control
## A quiet illustrated village, shared with the web welcome screen.
## Static artwork; a slow breath and a twinkling star are the only motion, and
## both stop when the player asks for reduced motion.

const HERO_PNG := "res://assets/ui/kingdom_company_v2.png"
const FALLBACK_SVG := "res://assets/ui/kingdom_preview.svg"
const BREATH_SECONDS := 4.2
var _texture: Texture2D
var _region := Rect2()
var _phase: float = 0.0
var _animated: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var path: String = HERO_PNG if ResourceLoader.exists(HERO_PNG) else FALLBACK_SVG
	_texture = load(path) as Texture2D
	if _texture != null:
		_region = Rect2(_texture.get_image().get_used_rect())
		if not _region.has_area():
			_region = Rect2(Vector2.ZERO, _texture.get_size())
	resized.connect(queue_redraw)
	visibility_changed.connect(_refresh_motion)
	_refresh_motion()
	queue_redraw()


func _refresh_motion() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	var reduced: bool = game_manager != null and bool(game_manager.get("reduced_motion"))
	_animated = is_visible_in_tree() and not reduced and DisplayServer.get_name() != "headless"
	set_process(_animated)
	if not _animated:
		_phase = 0.0
		queue_redraw()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta / BREATH_SECONDS, 1.0)
	queue_redraw()


func _draw() -> void:
	if _texture == null or size.x < 1.0 or size.y < 1.0:
		return
	var center := Vector2(size.x * 0.5, size.y * 0.52)
	var radius: float = minf(size.x * 0.45, size.y * 0.48)
	draw_circle(center, radius, Color("324b3b"))
	draw_arc(center, radius + 7, 0, TAU, 96, Color("65704d"), 1.0, true)
	for index: int in 12:
		var direction := Vector2.from_angle(float(index) * TAU / 12.0)
		draw_line(center + direction * (radius + 11), center + direction * (radius + 15), Color("7b805b"), 1.0, true)
	var factor: float = minf(size.x / _region.size.x, size.y / _region.size.y)
	var art_size: Vector2 = _region.size * factor
	# The village rises and settles a few pixels, like a breath.
	var bob: float = -sin(_phase * TAU) * minf(3.0, size.y * 0.012) if _animated else 0.0
	# Fit the whole company and kingdom; no portrait crop hides the illustration.
	var target := Rect2((size - art_size) * Vector2(0.5, 1.0) + Vector2(0, bob), art_size)
	draw_texture_rect_region(_texture, target, _region)
	# A small gold star twinkles above the roofs, as on the web welcome.
	var glow: float = 0.55 + 0.45 * sin(_phase * TAU * 2.0) if _animated else 1.0
	var star_center := center + Vector2(radius * 0.72, -radius * 0.78)
	var arm: float = clampf(radius * 0.09, 5.0, 11.0) * (0.85 + 0.15 * glow)
	var star := PackedVector2Array()
	for point: int in 8:
		var reach: float = arm if point % 2 == 0 else arm * 0.28
		star.append(star_center + Vector2.from_angle(float(point) * TAU / 8.0 - PI * 0.5) * reach)
	draw_colored_polygon(star, Color(0.91, 0.75, 0.47, glow))


func get_web_svg_source() -> String:
	# The SVG exporter keeps a coherent vector fallback. The web shell uses HERO_PNG.
	return FileAccess.get_file_as_string(FALLBACK_SVG) if FileAccess.file_exists(FALLBACK_SVG) else ""
