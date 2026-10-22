extends Control
## An original field company in front of the real seeded terrain atlas.
## Decorative route markers are not a battle simulation; Reduced Motion freezes them.

const ATLAS_SIZE := Vector2(420.0, 228.0)
const THEME := preload("res://scripts/ui/kingdom_theme.gd")
var _elapsed: float = 0.0
var _redraw_elapsed: float = 0.0
var _archetype: int = -1
var _seed: int = -2
var _atlas_texture: ImageTexture
var _company_texture: Texture2D
var _company_region: Rect2
var _company_is_png: bool = false
var _company_svg: String = ""
var _routes: Array[PackedVector2Array] = []
var _bases: Array[Vector2] = []
var _svg_source: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_load_company_art()
	_refresh_atlas()


func _load_company_art() -> void:
	const COMPANY_PNG := "res://assets/ui/field_company.png"
	const COMPANY_SVG := "res://assets/ui/field_company.svg"
	_company_is_png = ResourceLoader.exists(COMPANY_PNG)
	var source: String = COMPANY_PNG if _company_is_png else COMPANY_SVG
	if not ResourceLoader.exists(source):
		return
	_company_texture = load(source) as Texture2D
	if _company_texture == null:
		return
	_company_region = Rect2(_company_texture.get_image().get_used_rect())
	if not _company_region.has_area():
		_company_region = Rect2(Vector2.ZERO, _company_texture.get_size())
	# Raw SVG is only used by the local web-art exporter. Runtime rendering uses
	# imported textures so the illustration survives Godot's packed exports.
	if not _company_is_png and FileAccess.file_exists(COMPANY_SVG):
		_company_svg = FileAccess.get_file_as_string(COMPANY_SVG)


func _process(delta: float) -> void:
	var desired_seed: int = GameManager.selected_map_seed if GameManager.selected_map_seed >= 0 else 101
	if _archetype != GameManager.selected_map_archetype or _seed != desired_seed:
		_refresh_atlas()
	if GameManager.reduced_motion:
		return
	_elapsed += delta
	_redraw_elapsed += delta
	if _redraw_elapsed >= 1.0 / 30.0:
		_redraw_elapsed = 0.0
		queue_redraw()


static func _point(tile: Vector2) -> Vector2:
	# Presentation coordinates on this atlas, independent of world navigation.
	return Vector2(210.0 + (tile.x - tile.y) * 2.48, 15.0 + (tile.x + tile.y) * 1.22)


static func _svg_points(points: PackedVector2Array) -> String:
	var values := PackedStringArray()
	for point: Vector2 in points:
		values.append("%.2f,%.2f" % [point.x, point.y])
	return " ".join(values)


func _refresh_atlas() -> void:
	_archetype = GameManager.selected_map_archetype
	_seed = GameManager.selected_map_seed if GameManager.selected_map_seed >= 0 else 101
	var generator := MapGenerator.new(_seed, _archetype)
	generator.generate()
	_routes.clear()
	_bases.clear()
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="1260" height="684" viewBox="0 0 420 228">'
	# The map is a flat engraved field: no extrusion, shadows or toy props.
	var border := PackedVector2Array([_point(Vector2.ZERO), _point(Vector2(72, 0)), _point(Vector2(72, 72)), _point(Vector2(0, 72))])
	svg += '<polygon points="%s" fill="#303b3d" stroke="#768681" stroke-width="0.85"/>' % _svg_points(border)
	for y: int in MapData.MAP_HEIGHT:
		for x: int in MapData.MAP_WIDTH:
			var tile_type: int = generator.grid[y][x]
			if tile_type not in [MapData.TileType.WATER, MapData.TileType.FOREST]:
				continue
			var corners := PackedVector2Array([_point(Vector2(x, y)), _point(Vector2(x + 1, y)), _point(Vector2(x + 1, y + 1)), _point(Vector2(x, y + 1))])
			var color: String = "#192b31" if tile_type == MapData.TileType.WATER else "#495b51"
			svg += '<polygon points="%s" fill="%s"/>' % [_svg_points(corners), color]
			# Outline only region edges; the terrain never becomes a noisy tile grid.
			var neighbors: Array[Vector2i] = [Vector2i(x, y - 1), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x - 1, y)]
			for edge: int in 4:
				var neighbor: Vector2i = neighbors[edge]
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= 72 or neighbor.y >= 72 or int(generator.grid[neighbor.y][neighbor.x]) != tile_type:
					var end: Vector2 = corners[(edge + 1) % 4]
					svg += '<path d="M%.2f %.2f L%.2f %.2f" stroke="%s" stroke-width="0.55" fill="none"/>' % [corners[edge].x, corners[edge].y, end.x, end.y, "#88a5a1" if tile_type == MapData.TileType.WATER else "#899b87"]
	# Sparse survey lines establish scale while leaving the land legible.
	for axis: int in range(12, 72, 12):
		for pair: Array in [[Vector2(axis, 0), Vector2(axis, 72)], [Vector2(0, axis), Vector2(72, axis)]]:
			var a: Vector2 = _point(pair[0])
			var b: Vector2 = _point(pair[1])
			svg += '<path d="M%.2f %.2f L%.2f %.2f" stroke="#a6afad" stroke-opacity="0.12" stroke-width="0.55"/>' % [a.x, a.y, b.x, b.y]
	var route_colors: Array[String] = ["#e8e5db", "#88b7ad", "#d69477"]
	for route: Dictionary in generator.get_tactical_routes():
		var points := PackedVector2Array()
		for tile: Vector2i in route.waypoints:
			points.append(_point(Vector2(tile)))
		var index: int = _routes.size()
		_routes.append(points)
		svg += '<polyline points="%s" stroke="%s" stroke-width="1.4" stroke-opacity="0.82" fill="none" stroke-dasharray="%s"/>' % [_svg_points(points), route_colors[index], "2 4" if index != 0 else "none"]
	for spawn: Vector2i in generator.spawn_positions:
		_bases.append(_point(Vector2(spawn + Vector2i(2, 2))))
	# Central objective: a precise four-part lozenge, without a glowing marker.
	var center: Vector2 = _point(Vector2(36, 36))
	svg += '<path d="M%.1f %.1f l6 -4 6 4 -6 4 Z" stroke="#e8e5db" fill="#171c1d" stroke-width="1.1"/>' % [center.x - 6.0, center.y]
	for index: int in _bases.size():
		var base: Vector2 = _bases[index]
		var color: String = "#88b7ad" if index == 0 else "#d69477"
		svg += '<circle cx="%.1f" cy="%.1f" r="8" fill="#171c1d" stroke="%s" stroke-width="1"/><path d="M%.1f %.1f v-8 h6 v8 M%.1f %.1f v-5 h4 v5" fill="none" stroke="%s" stroke-width="1.4"/>' % [base.x, base.y, color, base.x - 4, base.y + 3, base.x - 6, base.y + 3, color]
	# Registration ticks and an understated scale, as on a working map sheet.
	for corner: Vector2 in border:
		svg += '<path d="M%.1f %.1f h8 M%.1f %.1f v8" stroke="#a6afad" stroke-width="0.6"/>' % [corner.x - 4, corner.y, corner.x, corner.y - 4]
	svg += '<path d="M176 214 h68 M176 211 v6 M210 211 v6 M244 211 v6" stroke="#687674" stroke-width="0.7"/></svg>'
	_svg_source = svg
	var image := Image.new()
	if image.load_svg_from_string(svg) == OK:
		_atlas_texture = ImageTexture.create_from_image(image)
	queue_redraw()


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0 or _atlas_texture == null:
		return
	var factor: float = minf(size.x / ATLAS_SIZE.x, size.y / ATLAS_SIZE.y)
	var offset: Vector2 = (size - ATLAS_SIZE * factor) * 0.5
	draw_set_transform(offset, 0.0, Vector2.ONE * factor)
	draw_texture_rect(_atlas_texture, Rect2(Vector2.ZERO, ATLAS_SIZE), false, Color(1.0, 1.0, 1.0, 0.38 if _company_texture != null else 1.0))
	for index: int in _routes.size():
		var points: PackedVector2Array = _routes[index]
		var phase: float = fmod(_elapsed * 0.035 + 0.12 + float(index) * 0.22, 1.0)
		# Two small formations use different routes: a quiet hint at split attacks.
		if index == 2:
			phase = 1.0 - phase
		var marker: Vector2 = _along_route(points, phase)
		var color: Color = THEME.TEAL if index != 2 else THEME.RUST
		color.a = 0.4 if _company_texture != null else 1.0
		for member: int in 3:
			var position: Vector2 = marker + Vector2(float(member - 1) * 5.4, float(abs(member - 1)) * 2.0)
			draw_rect(Rect2(position - Vector2(1.5, 3.2), Vector2(3.0, 6.4)), color)
	if _company_texture != null:
		var company_factor: float = minf(ATLAS_SIZE.x / _company_region.size.x, ATLAS_SIZE.y / _company_region.size.y)
		# Portrait framing brings faces forward; the Control clips the lower body
		# while keeping all three faces and the distinguishing tools visible.
		if _company_is_png:
			company_factor *= 1.16
		var company_size: Vector2 = _company_region.size * company_factor
		var company_rect := Rect2(Vector2((ATLAS_SIZE.x - company_size.x) * 0.5, ATLAS_SIZE.y - company_size.y), company_size)
		draw_texture_rect_region(_company_texture, company_rect, _company_region)
	draw_set_transform(Vector2.ZERO)


func _along_route(points: PackedVector2Array, fraction: float) -> Vector2:
	var first_length: float = points[0].distance_to(points[1])
	var second_length: float = points[1].distance_to(points[2])
	var distance: float = fraction * (first_length + second_length)
	if distance <= first_length:
		return points[0].lerp(points[1], distance / maxf(1.0, first_length))
	return points[1].lerp(points[2], (distance - first_length) / maxf(1.0, second_length))


func get_web_svg_source() -> String:
	# Static counterpart of the same formation phase shown with Reduced Motion.
	var marks: String = ""
	for index: int in _routes.size():
		var phase: float = 0.12 + float(index) * 0.22
		if index == 2:
			phase = 1.0 - phase
		var marker: Vector2 = _along_route(_routes[index], phase)
		for member: int in 3:
			var position: Vector2 = marker + Vector2(float(member - 1) * 5.4, float(abs(member - 1)) * 2.0)
			marks += '<rect x="%.2f" y="%.2f" width="3" height="6.4" fill="%s"/>' % [position.x - 1.5, position.y - 3.2, "#d69477" if index == 2 else "#88b7ad"]
	if _company_is_png or _company_svg.is_empty():
		return _svg_source.replace("</svg>", marks + "</svg>")
	var atlas_start: int = _svg_source.find(">") + 1
	var atlas_end: int = _svg_source.rfind("</svg>")
	var company_start: int = _company_svg.find("<svg")
	company_start = _company_svg.find(">", company_start) + 1
	var company_end: int = _company_svg.rfind("</svg>")
	return _svg_source.left(atlas_start) + '<g opacity="0.38">' + _svg_source.substr(atlas_start, atlas_end - atlas_start) + marks + '</g>' + _company_svg.substr(company_start, company_end - company_start) + "</svg>"
