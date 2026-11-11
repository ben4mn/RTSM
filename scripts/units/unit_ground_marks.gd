class_name UnitGroundMarks
extends RefCounted
## Baked unit ground art (contact shadow and ownership marker) in one small
## shared texture, so every unit's marks are plain sprites that the canvas
## renderer batches into a single draw call per frame. They sit one z layer
## below the y-sorted world (above terrain at -10), exactly where the old
## per-unit polygons visually were: beneath the feet. Presentation only.

## Texture pixels per world unit for the marker cells.
const MARKER_DENSITY: float = 4.0
## Shadow cell: outer ellipse fills it exactly (rx = 32 px, ry = 16 px).
const SHADOW_RECT := Rect2(0, 0, 64, 32)
const MARKER_BAR_RECT := Rect2(64, 0, 48, 24)
const MARKER_CHEVRON_RECT := Rect2(112, 0, 48, 24)
const INK := Color("293235")
const OWN_LIGHT := Color("88b7ad")
const RIVAL_LIGHT := Color("d69477")
const SHADOW_RGB := Color(0.09, 0.13, 0.13)

static var _texture: ImageTexture = null


static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(_bake())
	return _texture


## Sprite transform for the shadow of a unit with ring radius `size`: the old
## ground ring (rx = size + 1, ry = 0.48 size, centred 3 below the feet) and
## its darker contact core.
static func shadow_scale(size: float) -> Vector2:
	return Vector2((size + 1.0) / 32.0, size * 0.48 / 16.0)


static func shadow_offset() -> Vector2:
	return Vector2(0.0, 3.0)


static func _coverage(image_size: Vector2i, sample: Callable) -> PackedFloat32Array:
	# 3x3 supersampling gives the soft one-pixel edge the old polygons lacked
	# only on the diagonal; it reads the same, without the stair steps.
	var values := PackedFloat32Array()
	values.resize(image_size.x * image_size.y)
	for y: int in image_size.y:
		for x: int in image_size.x:
			var total: float = 0.0
			for sy: int in 3:
				for sx: int in 3:
					total += float(sample.call(Vector2(x + (sx + 0.5) / 3.0, y + (sy + 0.5) / 3.0)))
			values[y * image_size.x + x] = total / 9.0
	return values


static func _bake() -> Image:
	var image := Image.create(160, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	# Shadow: outer ring at 0.14 and the contact core (0.72 x 0.58 of it, one
	# world unit higher) layered at 0.20, as the two old polygons composited.
	var outer := _coverage(Vector2i(64, 32), func(p: Vector2) -> float:
		var d := (p - Vector2(32, 16)) / Vector2(32, 16)
		return 1.0 if d.length_squared() <= 1.0 else 0.0)
	var core := _coverage(Vector2i(64, 32), func(p: Vector2) -> float:
		var d := (p - Vector2(32, 14)) / Vector2(32 * 0.72, 16 * 0.58)
		return 1.0 if d.length_squared() <= 1.0 else 0.0)
	for y: int in 32:
		for x: int in 64:
			var a: float = 1.0 - (1.0 - 0.14 * outer[y * 64 + x]) * (1.0 - 0.20 * core[y * 64 + x])
			image.set_pixel(x, y, Color(SHADOW_RGB, a))
	_bake_marker(image, MARKER_BAR_RECT, [Vector2(-3, 0), Vector2(3, 0)], OWN_LIGHT)
	_bake_marker(image, MARKER_CHEVRON_RECT, [Vector2(-3, -1.5), Vector2(0, 1.5), Vector2(3, -1.5)], RIVAL_LIGHT)
	return image


## A dark 3-unit stroke under a light 1.5-unit stroke along `points` (world
## units at zoom 1, centred in the cell), like the old pair of lines.
static func _bake_marker(image: Image, cell: Rect2, points: Array, light: Color) -> void:
	var centre := cell.size * 0.5
	var distance := func(p: Vector2) -> float:
		var world := (p - centre) / MARKER_DENSITY
		var best: float = 1e9
		for i: int in points.size() - 1:
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var t: float = clampf((world - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			# Flat ends like the old lines: only the joint is round.
			var along: float = (world - a).dot((b - a).normalized())
			if (i == 0 and along < 0.0) or (i == points.size() - 2 and along > (b - a).length()):
				continue
			best = minf(best, world.distance_to(a + (b - a) * t))
		return best
	var dark := _coverage(Vector2i(cell.size), func(p: Vector2) -> float: return 1.0 if float(distance.call(p)) <= 1.5 else 0.0)
	var lit := _coverage(Vector2i(cell.size), func(p: Vector2) -> float: return 1.0 if float(distance.call(p)) <= 0.75 else 0.0)
	for y: int in int(cell.size.y):
		for x: int in int(cell.size.x):
			var i: int = y * int(cell.size.x) + x
			var a_dark: float = dark[i]
			var a_lit: float = lit[i]
			var alpha: float = a_lit + a_dark * (1.0 - a_lit)
			if alpha <= 0.0:
				continue
			var rgb: Color = INK.lerp(light, a_lit / alpha)
			image.set_pixel(int(cell.position.x) + x, int(cell.position.y) + y, Color(rgb, alpha))
