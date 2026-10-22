class_name TilesetBuilder
extends RefCounted
## Quiet ground surfaces keep the harvestable sprites and units legible.
## Call build_terrain_tileset() / build_fog_tileset() and assign the result
## to a TileMapLayer.tile_set.

## Sprite texture paths for each tile type, mapped from Kenney Medieval RTS pack.
const TILE_TEXTURES: Dictionary = {
	MapData.TileType.GRASS: "res://assets/terrain/tile_grass_flowers.png",
	MapData.TileType.WATER: "",  # Water stays procedural (blue diamond)
	MapData.TileType.FOREST: "res://assets/terrain/tile_grass_tree.png",
	MapData.TileType.GOLD_MINE: "res://assets/terrain/tile_dirt.png",
	MapData.TileType.BERRY_BUSH: "res://assets/terrain/tile_farmland.png",
	MapData.TileType.STONE: "res://assets/terrain/tile_sand.png",
	MapData.TileType.SACRED_SITE: "res://assets/terrain/tile_farmland2.png",
	MapData.TileType.GRASS_ALT: "res://assets/terrain/tile_grass_alt.png",
	MapData.TileType.GRASS_DARK: "res://assets/terrain/tile_grass_dark.png",
}

## Base columns remain the TileType values. Only water gains presentation
## variants: bits follow grid -X, -Y, +X, +Y (NW, NE, SE, SW on screen).
const SHORE_VARIANT_START: int = MapData.TileType.GRASS_DARK + 1
const SHORE_VARIANT_COUNT: int = 15


static func get_terrain_atlas_coords(tile_type: int, shore_mask: int = 0) -> Vector2i:
	if tile_type == MapData.TileType.WATER and shore_mask > 0:
		return Vector2i(SHORE_VARIANT_START + clampi(shore_mask, 1, 15) - 1, 0)
	return Vector2i(tile_type, 0)


## One shared atlas; shoreline variants add no scene nodes or frame updates.
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

	for i in range(tile_count + SHORE_VARIANT_COUNT):
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
	var w := tw * (tile_count + SHORE_VARIANT_COUNT)
	var h := th
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for i in range(tile_count):
		var tile_type: MapData.TileType = i as MapData.TileType
		var offset_x := i * tw
		# The pack's terrain images contain vegetation, not just ground. Drawing
		# those beneath real trees made every open tile look like a forest.
		_fill_iso_diamond(img, offset_x, 0, tw, th, tile_type, null)

	var water: Image = img.get_region(Rect2i(MapData.TileType.WATER * tw, 0, tw, th))
	for shore_mask: int in range(1, SHORE_VARIANT_COUNT + 1):
		var offset_x: int = (SHORE_VARIANT_START + shore_mask - 1) * tw
		img.blit_rect(water, Rect2i(0, 0, tw, th), Vector2i(offset_x, 0))
		_paint_shore_edges(img, offset_x, tw, th, shore_mask)

	return img


static func _paint_shore_edges(img: Image, ox: int, tw: int, th: int, shore_mask: int) -> void:
	# Paint strictly within the unchanged water alpha. A warm narrow bank and
	# shallow mineral tint identify land edges; interior water seams stay quiet.
	for y: int in th:
		for x: int in tw:
			var base: Color = img.get_pixel(ox + x, y)
			if base.a <= 0.0:
				continue
			var nx: float = (float(x) - tw * 0.5) / (tw * 0.5)
			var ny: float = (float(y) - th * 0.5) / (th * 0.5)
			var distances: Array[float] = [1.0 + nx + ny, 1.0 - nx + ny, 1.0 - nx - ny, 1.0 + nx - ny]
			var nearest: float = INF
			for edge: int in 4:
				if shore_mask & (1 << edge):
					nearest = minf(nearest, distances[edge])
			if nearest < 0.055:
				img.set_pixel(ox + x, y, Color("aaa990"))
			elif nearest < 0.28:
				img.set_pixel(ox + x, y, base.lerp(Color("9aafa0"), 0.7 * (1.0 - nearest / 0.28)))


## Fill an isometric diamond on the atlas image.
## Uses source_img texture if available, otherwise falls back to flat color.
static func _fill_iso_diamond(img: Image, ox: int, oy: int, tw: int, th: int, tile_type: MapData.TileType, source_img: Image) -> void:
	@warning_ignore("integer_division")
	var cx := ox + tw / 2
	@warning_ignore("integer_division")
	var cy := oy + th / 2
	var half_w := tw / 2.0
	var half_h := th / 2.0
	var surface_colors: Dictionary = {
		MapData.TileType.GRASS: Color("9ba58a"),
		MapData.TileType.GRASS_ALT: Color("9da68c"),
		MapData.TileType.GRASS_DARK: Color("99a389"),
		MapData.TileType.FOREST: Color("89977d"),
		MapData.TileType.WATER: Color("668f93"),
		MapData.TileType.GOLD_MINE: Color("aaa488"),
		MapData.TileType.BERRY_BUSH: Color("98a28a"),
		MapData.TileType.STONE: Color("a5a895"),
		MapData.TileType.SACRED_SITE: Color("bbb59e"),
	}
	var fallback_color: Color = surface_colors.get(tile_type, Color.MAGENTA)

	for py in range(oy, oy + th):
		for px in range(ox, ox + tw):
			var dx := absf(float(px - cx)) / half_w
			var dy := absf(float(py - cy)) / half_h
			if dx + dy <= 1.06:
				if source_img != null:
					# Sample from the source texture
					var src_x := px - ox
					var src_y := py - oy
					var color := source_img.get_pixel(src_x, src_y)
					# Ensure full opacity for the diamond
					color.a = 1.0
					img.set_pixel(px, py, color)
				else:
					# Subpixel grain gives the meadow texture without a tile grid.
					var grain_strength: float = 0.0007 if MapData.is_grass(tile_type) else 0.0014
					var grain: float = float(posmod((px - ox) * 17 + py * 31, 7) - 3) * grain_strength
					var color := Color(fallback_color.r + grain, fallback_color.g + grain, fallback_color.b + grain)
					if tile_type == MapData.TileType.WATER and posmod(py * 3 + px, 23) < 2:
						color = color.lightened(0.045)
					img.set_pixel(px, py, color)


## Create a 2-tile atlas for fog states.
static func _create_fog_atlas() -> Image:
	var w := MapData.TILE_WIDTH * 2
	var h := MapData.TILE_HEIGHT
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	_draw_iso_diamond(img, 0, 0, MapData.TILE_WIDTH, MapData.TILE_HEIGHT, Color("182a30"))
	_draw_iso_diamond(img, MapData.TILE_WIDTH, 0, MapData.TILE_WIDTH, MapData.TILE_HEIGHT, Color(0.06, 0.12, 0.16, 0.64))

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
