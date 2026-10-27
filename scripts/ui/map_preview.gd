extends Control
## Representative map-style illustration. Never depicts a generated match seed.
## Existing Kingdom buildings and resource artwork keep the menu's visual language.
const HOUSE := preload("res://assets/kingdoms/crownlands/building_house.tres")
const TOWN := preload("res://assets/kingdoms/crownlands/building_town_center.tres")
const FARM := preload("res://assets/kingdoms/crownlands/building_farm.tres")
const OAK := preload("res://assets/resources/company_oak.svg")
const PINE := preload("res://assets/resources/company_pine.svg")
const GOLD := preload("res://assets/resources/company_gold.svg")
const CHART_SIZE := Vector2(320, 190)
var archetype: int = 0
# Retained for callers of refresh(archetype, seed); seed has no visual effect.
var preview_seed: int = 101

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)
	refresh(archetype)

func refresh(map_archetype: int, _seed_value: int = 101) -> void:
	archetype = MapData.normalize_archetype(map_archetype)
	tooltip_text = MapData.get_archetype_name(archetype) + " style illustration. A fresh battlefield is generated each match."
	queue_redraw()

func _draw() -> void:
	if size.x < 1 or size.y < 1: return
	var factor: float = minf(size.x / CHART_SIZE.x, size.y / CHART_SIZE.y)
	draw_set_transform((size - CHART_SIZE * factor) * 0.5, 0, Vector2.ONE * factor)
	_oval(Vector2(160, 144), Vector2(142, 34), Color("a9aa8f"))
	var ground := PackedVector2Array([Vector2(18, 97), Vector2(60, 62), Vector2(151, 43), Vector2(243, 62), Vector2(302, 99), Vector2(268, 143), Vector2(173, 174), Vector2(73, 149)])
	var shelf := ground.duplicate()
	for i: int in shelf.size(): shelf[i].y += 9
	draw_colored_polygon(shelf, Color("7e9070"))
	draw_colored_polygon(ground, Color("afbd8b") if archetype != 4 else Color("c2bd87"))
	_oval(Vector2(163, 112), Vector2(98, 36), Color("b9c595") if archetype != 4 else Color("d3ca99"))
	match archetype:
		MapData.MapArchetype.OPEN_PLAINS:
			_road([Vector2(52, 133), Vector2(141, 113), Vector2(240, 83)])
			_stamp(OAK, Vector2(70, 96), 58)
			_stamp(TOWN, Vector2(221, 101), 68)
			_stamp(FARM, Vector2(172, 142), 34)
			_stamp(HOUSE, Vector2(99, 143), 49)
			_stamp(OAK, Vector2(259, 135), 42)
		MapData.MapArchetype.RIVER_CROSSINGS:
			_ribbon([Vector2(107, 57), Vector2(129, 82), Vector2(158, 107), Vector2(176, 135), Vector2(203, 162)], Color("779faa"), 29)
			_ribbon([Vector2(107, 57), Vector2(129, 82), Vector2(158, 107), Vector2(176, 135), Vector2(203, 162)], Color("99bec1"), 19)
			_road([Vector2(61, 132), Vector2(156, 109), Vector2(252, 86)])
			_bridge(Vector2(157, 108))
			_bridge(Vector2(126, 78))
			_bridge(Vector2(180, 140))
			_stamp(OAK, Vector2(78, 96), 51)
			_stamp(HOUSE, Vector2(235, 104), 54)
			_stamp(OAK, Vector2(97, 157), 48)
		MapData.MapArchetype.WOODLAND_FLANKS:
			_road([Vector2(53, 127), Vector2(103, 111), Vector2(170, 122), Vector2(252, 91)])
			for p: Vector2 in [Vector2(75, 89), Vector2(104, 73), Vector2(143, 77), Vector2(198, 77), Vector2(239, 86), Vector2(268, 109)]: _stamp(PINE, p, 55)
			_stamp(HOUSE, Vector2(160, 121), 47)
			for p: Vector2 in [Vector2(71, 139), Vector2(97, 157), Vector2(223, 148), Vector2(252, 137)]: _stamp(OAK, p, 56)
		MapData.MapArchetype.TWIN_LAKES:
			_lake(Vector2(104, 103), Vector2(48, 24))
			_lake(Vector2(231, 110), Vector2(43, 24))
			_road([Vector2(157, 62), Vector2(165, 107), Vector2(153, 162)])
			_stamp(HOUSE, Vector2(168, 82), 43)
			_stamp(OAK, Vector2(69, 132), 49)
			_stamp(OAK, Vector2(262, 91), 51)
			_stamp(OAK, Vector2(226, 158), 43)
		MapData.MapArchetype.GOLDEN_BASIN:
			for p: Vector2 in [Vector2(71, 94), Vector2(113, 71), Vector2(209, 74), Vector2(255, 98)]: _stamp(PINE, p, 51)
			_road([Vector2(57, 130), Vector2(156, 110), Vector2(257, 137)])
			for p: Vector2 in [Vector2(154, 100), Vector2(179, 110), Vector2(141, 120)]: _stamp(GOLD, p, 35)
			_stamp(HOUSE, Vector2(215, 151), 44)
			_stamp(OAK, Vector2(88, 147), 53)
	draw_set_transform(Vector2.ZERO)

func _stamp(texture: Texture2D, foot: Vector2, height: float) -> void:
	var ink: Rect2 = KingdomArt.ink_rect(texture)
	if not ink.has_area(): return
	var dimensions: Vector2 = ink.size * (height / ink.size.y)
	draw_texture_rect_region(texture, Rect2(foot - Vector2(dimensions.x * 0.5, dimensions.y), dimensions), ink)

func _oval(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i: int in 40: points.append(center + Vector2.from_angle(TAU * i / 40.0) * radius)
	draw_colored_polygon(points, color)

func _lake(center: Vector2, radius: Vector2) -> void:
	_oval(center, radius + Vector2(3, 3), Color("779c8e"))
	_oval(center, radius, Color("87adb7"))
	_oval(center + Vector2(-3, -3), radius * 0.82, Color("a1c5c6"))
	draw_line(center + Vector2(-18, 1), center + Vector2(9, 1), Color("d5e3d8"), 2, true)
	draw_line(center + Vector2(-5, 7), center + Vector2(17, 7), Color("d5e3d8"), 2, true)

func _road(points: Array, width: float = 9.0) -> void:
	_ribbon(points, Color("d8cb9d"), width)

func _ribbon(points: Array, color: Color, width: float) -> void:
	draw_polyline(PackedVector2Array(points), color, width, true)
	for point: Vector2 in points: draw_circle(point, width * 0.5, color)

func _bridge(center: Vector2) -> void:
	draw_line(center + Vector2(-20, 7), center + Vector2(20, -7), Color("786c4d"), 12, true)
	draw_line(center + Vector2(-20, 5), center + Vector2(20, -9), Color("d9bc83"), 8, true)
	for i: int in 5:
		var p: Vector2 = center + Vector2(-16 + i * 8, 5 - i * 2.8)
		draw_line(p + Vector2(-2, -5), p + Vector2(2, 3), Color("9c835d"), 1.4, true)

# Kept for existing coordinate utility callers; illustration rendering does not
# use battlefield coordinates, generated resources, starts, or a seed.
static func project_tile_to_preview(tile: Vector2, rect: Rect2) -> Vector2:
	return rect.position + tile / Vector2(MapData.MAP_WIDTH, MapData.MAP_HEIGHT) * rect.size
