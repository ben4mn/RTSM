class_name TilesetBuilder
extends RefCounted
## Creates procedural TileSet resources at runtime using colored isometric
## diamond images. Call build_terrain_tileset() / build_fog_tileset() and
## assign the result to a TileMapLayer.tile_set.

## Build the terrain tileset with one tile per MapData.TileType.
static func build_terrain_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(MapData.TILE_WIDTH, MapData.TILE_HEIGHT)
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN

	# Create an atlas source from a procedural texture.
	var tile_count := MapData.TileType.size()
	var atlas_image := _create_terrain_atlas(tile_count)
	var atlas_texture := ImageTexture.create_from_image(atlas_image)

	var source := TileSetAtlasSource.new()
	source.texture = atlas_texture
	source.texture_region_size = Vector2i(MapData.TILE_WIDTH, MapData.TILE_HEIGHT)

	# Create one tile per type.
	for i in range(tile_count):
		source.create_tile(Vector2i(i, 0))

	ts.add_source(source, 0)
	return ts


## Build the fog-of-war tileset with 2 tiles: unexplored (black) and explored (grey).
static func build_fog_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(MapData.TILE_WIDTH, MapData.TILE_HEIGHT)
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN

	var atlas_image := _create_fog_atlas()
	var atlas_texture := ImageTexture.create_from_image(atlas_image)

	var source := TileSetAtlasSource.new()
	source.texture = atlas_texture
	source.texture_region_size = Vector2i(MapData.TILE_WIDTH, MapData.TILE_HEIGHT)

	# Tile 0,0 = unexplored (black), Tile 1,0 = explored (grey/dim)
	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))

	ts.add_source(source, 0)
	return ts


## Create a horizontal strip atlas image for terrain tiles.
## Each tile is a filled isometric diamond of the corresponding color.
static func _create_terrain_atlas(tile_count: int) -> Image:
	var w := MapData.TILE_WIDTH * tile_count
	var h := MapData.TILE_HEIGHT
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for i in range(tile_count):
		var tile_type: MapData.TileType = i as MapData.TileType
		var color: Color = MapData.TILE_COLORS.get(tile_type, Color.MAGENTA)
		var offset_x := i * MapData.TILE_WIDTH
		_draw_iso_diamond(img, offset_x, 0, MapData.TILE_WIDTH, MapData.TILE_HEIGHT, color)

	return img


## Create a 2-tile atlas for fog states.
static func _create_fog_atlas() -> Image:
	var w := MapData.TILE_WIDTH * 2
	var h := MapData.TILE_HEIGHT
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Unexplored = dark but not completely opaque so you can faintly see terrain shape.
	_draw_iso_diamond(img, 0, 0, MapData.TILE_WIDTH, MapData.TILE_HEIGHT, Color(0, 0, 0, 0.85))
	# Explored = light dim so previously-seen terrain is clearly visible.
	_draw_iso_diamond(img, MapData.TILE_WIDTH, 0, MapData.TILE_WIDTH, MapData.TILE_HEIGHT, Color(0, 0, 0, 0.35))

	return img


## Draw a filled isometric diamond on an image.
static func _draw_iso_diamond(img: Image, ox: int, oy: int, tw: int, th: int, color: Color) -> void:
	@warning_ignore("integer_division")
	var cx := ox + tw / 2
	@warning_ignore("integer_division")
	var cy := oy + th / 2
	var half_w := tw / 2.0
	var half_h := th / 2.0

	for py in range(oy, oy + th):
		for px in range(ox, ox + tw):
			# Check if point is inside the isometric diamond.
			var dx := absf(float(px - cx)) / half_w
			var dy := absf(float(py - cy)) / half_h
			if dx + dy <= 1.0:
				img.set_pixel(px, py, color)
