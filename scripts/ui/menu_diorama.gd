extends Control
## A quiet illustrated village, shared with the web welcome screen.
## Static artwork needs no per-frame redraw or terrain generation in the menu.

const HERO_PNG := "res://assets/ui/kingdom_company_v2.png"
const FALLBACK_SVG := "res://assets/ui/kingdom_preview.svg"
var _texture: Texture2D
var _region := Rect2()


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
	queue_redraw()


func _draw() -> void:
	if _texture == null or size.x < 1.0 or size.y < 1.0:
		return
	var factor: float = minf(size.x / _region.size.x, size.y / _region.size.y)
	var art_size: Vector2 = _region.size * factor
	# Fit the whole company and kingdom; no portrait crop hides the illustration.
	var target := Rect2((size - art_size) * Vector2(0.5, 1.0), art_size)
	draw_texture_rect_region(_texture, target, _region)


func get_web_svg_source() -> String:
	# The SVG exporter keeps a coherent vector fallback. The web shell uses HERO_PNG.
	return FileAccess.get_file_as_string(FALLBACK_SVG) if FileAccess.file_exists(FALLBACK_SVG) else ""
