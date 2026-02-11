class_name TilesetBuilder
extends RefCounted
## Creates TileSet resources using sprite-based terrain textures from asset packs.
## Falls back to procedural generation if textures are missing.
## Call build_terrain_tileset() / build_fog_tileset() and assign the result
## to a TileMapLayer.tile_set.

## Sprite texture paths for each tile type, mapped from Kenney Medieval RTS pack.
const TILE_TEXTURES: Dictionary = {
	MapData.TileType.GRASS: "res://assets/terrain/tile_grass_flowers.png",
	MapData.TileType.WATER: "",  # Water stays procedural (blue diamond)
	MapData.TileType.FOREST: "res://assets/terrain/tile_grass_dark.png",
	MapData.TileType.GOLD_MINE: "res://assets/terrain/tile_dirt.png",
	MapData.TileType.BERRY_BUSH: "res://assets/terrain/tile_grass_alt.png",
	MapData.TileType.STONE: "res://assets/terrain/tile_sand.png",
	MapData.TileType.SACRED_SITE: "res://assets/terrain/tile_farmland.png",
}


## Build the terrain tileset with one tile per MapData.TileType.
static func build_terrain_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(MapData.TILE_WIDTH, MapData.TILE_HEIGHT)
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN

	var tile_count := MapData.TileType.size()
	var atlas_image := _create_terrain_atlas(tile_count)
	var atlas_texture := ImageTexture.create_from_image(atlas_image)

	var source := TileSetAtlasSource.new()
	source.texture = atlas_texture
	source.texture_region_size = Vector2i(MapData.TILE_WIDTH, MapData.TILE_HEIGHT)

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

	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))

	ts.add_source(source, 0)
	return ts


## Create a horizontal strip atlas image for terrain tiles.
## Each tile samples from a sprite texture, masked to an isometric diamond.
static func _create_terrain_atlas(tile_count: int) -> Image:
	var tw := MapData.TILE_WIDTH
	var th := MapData.TILE_HEIGHT
	var w := tw * tile_count
	var h := th
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for i in range(tile_count):
		var tile_type: MapData.TileType = i as MapData.TileType
		var offset_x := i * tw
		var tex_path: String = TILE_TEXTURES.get(tile_type, "")

		# Try to load the sprite texture
		var source_img: Image = null
		if tex_path != "" and ResourceLoader.exists(tex_path):
			var tex: Texture2D = load(tex_path)
			if tex:
				source_img = tex.get_image()
				# Resize source to tile size if needed
				if source_img.get_width() != tw or source_img.get_height() != th:
					source_img.resize(tw, th, Image.INTERPOLATE_BILINEAR)

		# Fill the isometric diamond shape
		_fill_iso_diamond(img, offset_x, 0, tw, th, tile_type, source_img)

	return img


## Fill an isometric diamond on the atlas image.
## Uses source_img texture if available, otherwise falls back to flat color.
static func _fill_iso_diamond(img: Image, ox: int, oy: int, tw: int, th: int, tile_type: MapData.TileType, source_img: Image) -> void:
	@warning_ignore("integer_division")
	var cx := ox + tw / 2
	@warning_ignore("integer_division")
	var cy := oy + th / 2
	var half_w := tw / 2.0
	var half_h := th / 2.0
	var fallback_color: Color = MapData.TILE_COLORS.get(tile_type, Color.MAGENTA)

	for py in range(oy, oy + th):
		for px in range(ox, ox + tw):
			var dx := absf(float(px - cx)) / half_w
			var dy := absf(float(py - cy)) / half_h
			if dx + dy <= 1.0:
				if source_img != null:
					# Sample from the source texture
					var src_x := px - ox
					var src_y := py - oy
					var color := source_img.get_pixel(src_x, src_y)
					# Ensure full opacity for the diamond
					color.a = 1.0
					img.set_pixel(px, py, color)
				else:
					img.set_pixel(px, py, fallback_color)


## Create a 2-tile atlas for fog states.
static func _create_fog_atlas() -> Image:
	var w := MapData.TILE_WIDTH * 2
	var h := MapData.TILE_HEIGHT
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	_draw_iso_diamond(img, 0, 0, MapData.TILE_WIDTH, MapData.TILE_HEIGHT, Color(0, 0, 0, 0.85))
	_draw_iso_diamond(img, MapData.TILE_WIDTH, 0, MapData.TILE_WIDTH, MapData.TILE_HEIGHT, Color(0, 0, 0, 0.7))

	return img


## Draw a filled isometric diamond on an image (used for fog).
static func _draw_iso_diamond(img: Image, ox: int, oy: int, tw: int, th: int, color: Color) -> void:
	@warning_ignore("integer_division")
	var cx := ox + tw / 2
	@warning_ignore("integer_division")
	var cy := oy + th / 2
	var half_w := tw / 2.0
	var half_h := th / 2.0

	for py in range(oy, oy + th):
		for px in range(ox, ox + tw):
			var dx := absf(float(px - cx)) / half_w
			var dy := absf(float(py - cy)) / half_h
			if dx + dy <= 1.0:
				img.set_pixel(px, py, color)
