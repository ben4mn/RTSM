extends Control
## A small, live kingdom built from the same art used in the match.

const TOWN := preload("res://assets/buildings/town_center_alt.png")
const HOUSE := preload("res://assets/buildings/house.png")
const TOWER := preload("res://assets/buildings/tower.png")
const TREE := preload("res://assets/resources/tree_large.png")
const GOLD := preload("res://assets/resources/gold_rocks.png")
const VILLAGER := preload("res://assets/units/unit_01.png")
const SOLDIER := preload("res://assets/units/unit_05.png")

var _elapsed: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()


func _tile_position(tile: Vector2) -> Vector2:
	return Vector2((tile.x - tile.y) * 24.0, (tile.x + tile.y) * 12.0)


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	var scale_factor: float = minf(size.x / 370.0, size.y / 232.0)
	var origin := Vector2(size.x * 0.5, size.y * 0.12)
	draw_set_transform(origin, 0.0, Vector2.ONE * scale_factor)
	# Floating terrain edges give this little kingdom its own silhouette.
	var perimeter := PackedVector2Array([Vector2(0, -12), Vector2(192, 84), Vector2(0, 180), Vector2(-192, 84)])
	var shadow_points := PackedVector2Array()
	for point: Vector2 in perimeter:
		shadow_points.append(point + Vector2(0, 18))
	draw_colored_polygon(shadow_points, Color(0.025, 0.05, 0.07, 0.38))
	draw_colored_polygon(PackedVector2Array([Vector2(-192, 84), Vector2(0, 180), Vector2(0, 192), Vector2(-192, 96)]), Color("546c54"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 180), Vector2(192, 84), Vector2(192, 96), Vector2(0, 192)]), Color("394f43"))
	for y: int in range(8):
		for x: int in range(8):
			var center: Vector2 = _tile_position(Vector2(x, y))
			var tile := PackedVector2Array([center + Vector2(0, -12), center + Vector2(24, 0), center + Vector2(0, 12), center + Vector2(-24, 0)])
			var base := Color("899b69") if (x + y) % 3 == 0 else Color("829765")
			if x == 4 or (y == 4 and x > 2):
				base = Color("b8a77b")
			draw_colored_polygon(tile, base)
			draw_polyline(PackedVector2Array([tile[0], tile[1], tile[2]]), Color(0.96, 0.91, 0.72, 0.07), 1.0)
	# Paint objects back to front, as the match does.
	for tile: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 2), Vector2(0, 3), Vector2(7, 1), Vector2(7, 2)]:
		_draw_sprite(TREE, _tile_position(tile) + Vector2(0, -20), 48.0)
	_draw_sprite(TOWER, _tile_position(Vector2(4, 0)) + Vector2(0, -28), 55.0)
	_draw_sprite(HOUSE, _tile_position(Vector2(1, 4)) + Vector2(0, -15), 58.0)
	_draw_sprite(TOWN, _tile_position(Vector2(3, 2)) + Vector2(0, -34), 118.0)
	_draw_sprite(HOUSE, _tile_position(Vector2(6, 3)) + Vector2(0, -15), 58.0)
	_draw_sprite(GOLD, _tile_position(Vector2(1, 6)) + Vector2(0, -10), 45.0)
	var worker_offset: float = sin(_elapsed * 0.6) * 11.0
	_draw_person(VILLAGER, _tile_position(Vector2(4, 5)) + Vector2(worker_offset, worker_offset * 0.5), 41.0)
	_draw_person(VILLAGER, _tile_position(Vector2(2, 6)) + Vector2(-worker_offset * 0.5, worker_offset * 0.25), 41.0)
	_draw_person(SOLDIER, _tile_position(Vector2(6, 5)), 44.0)
	_draw_person(SOLDIER, _tile_position(Vector2(5, 6)), 44.0)
	# A little teal standard ties the preview to the player's army.
	var flag_base: Vector2 = _tile_position(Vector2(5, 3))
	draw_line(flag_base, flag_base + Vector2(0, -43), Color("efe8d4"), 2.0)
	var flutter: float = sin(_elapsed * 2.0) * 2.0
	draw_colored_polygon(PackedVector2Array([flag_base + Vector2(0, -43), flag_base + Vector2(20, -39 + flutter), flag_base + Vector2(0, -30)]), Color("73c4bb"))
	draw_set_transform(Vector2.ZERO)


func _draw_sprite(texture: Texture2D, center: Vector2, width: float) -> void:
	draw_texture_rect(texture, Rect2(center - Vector2.ONE * width * 0.5, Vector2.ONE * width), false)


func _draw_person(texture: Texture2D, center: Vector2, width: float) -> void:
	draw_circle(center + Vector2(0, 6), 6.0, Color(0.05, 0.13, 0.13, 0.30))
	draw_arc(center + Vector2(0, 6), 7.0, 0, TAU, 16, Color("74c5bf"), 2.0)
	_draw_sprite(texture, center, width)
