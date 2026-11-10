extends Node2D
## Presentation-only dressing for a finished map: painted ground, batched
## ground props, the soft fog veil and ambient life.
##
## Everything is derived from the generated grid with a private tile hash. The
## generator's random stream, the simulation, saves and the network protocol
## are never read for decisions or written. A dedicated server never creates it.

const AMBIENT_MOTION := preload("res://scripts/map/ambient_motion.gd")
const FOG_VEIL := preload("res://scripts/map/fog_veil.gd")
const AMBIENT_LIFE := preload("res://scripts/map/ambient_life.gd")
const PROPS_SHADER: Shader = preload("res://assets/terrain/ground_props.gdshader")
const PROPS_TEXTURE: Texture2D = preload("res://assets/terrain/ground_props.svg")

const NOISE_SIZE: int = 256
const PROP_QUAD: float = 44.0
const SETTINGS_POLL_SECONDS: float = 0.5

## Atlas cells in assets/terrain/ground_props.svg (tools/make_ground_props.py).
enum Prop {
	TUFT_A, TUFT_B, TUFT_TALL, TUFT_DRY, DAISY, BUTTERCUP, POPPY, CORNFLOWER,
	CLOVER, FERN, PEBBLES_A, PEBBLES_B, BOULDER, LOG, REEDS, CATTAIL,
	MUSHROOM, TWIGS, STUMP, LILY, BUTTERFLY_PALE, BUTTERFLY_AMBER, DRY_TALL, BLOSSOM_BUSH,
}

## Wind sway at the top of the quad, in mesh pixels, per atlas cell.
const PROP_SWAY: PackedFloat32Array = [
	4.0, 3.6, 4.6, 4.0, 3.4, 3.4, 3.4, 3.4,
	0.0, 1.2, 0.0, 0.0, 0.0, 0.0, 4.2, 3.4,
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 4.6, 1.0,
]

## Weighted picks: [cell, weight, cell, weight, ...].
const LUSH_TABLE: PackedInt32Array = [Prop.TUFT_A, 20, Prop.TUFT_B, 18, Prop.TUFT_TALL, 12, Prop.CLOVER, 16, Prop.DAISY, 9, Prop.CORNFLOWER, 6, Prop.BUTTERCUP, 6, Prop.FERN, 4, Prop.BLOSSOM_BUSH, 3, Prop.BOULDER, 2]
const MEADOW_TABLE: PackedInt32Array = [Prop.TUFT_A, 24, Prop.TUFT_B, 22, Prop.TUFT_TALL, 8, Prop.CLOVER, 8, Prop.BUTTERCUP, 8, Prop.POPPY, 6, Prop.DAISY, 6, Prop.PEBBLES_A, 6, Prop.PEBBLES_B, 4, Prop.LOG, 2, Prop.BOULDER, 2]
const DRY_TABLE: PackedInt32Array = [Prop.TUFT_DRY, 34, Prop.DRY_TALL, 18, Prop.PEBBLES_A, 9, Prop.PEBBLES_B, 8, Prop.BOULDER, 3, Prop.POPPY, 7, Prop.TUFT_B, 9, Prop.LOG, 2]
const BLOOM_TABLE: PackedInt32Array = [Prop.DAISY, 26, Prop.BUTTERCUP, 22, Prop.POPPY, 18, Prop.CORNFLOWER, 20, Prop.CLOVER, 8, Prop.TUFT_A, 6]
const WOODSIDE_TABLE: PackedInt32Array = [Prop.FERN, 28, Prop.MUSHROOM, 20, Prop.TWIGS, 22, Prop.STUMP, 7, Prop.TUFT_TALL, 14, Prop.LOG, 5, Prop.BLOSSOM_BUSH, 4]
const SHORE_TABLE: PackedInt32Array = [Prop.REEDS, 44, Prop.CATTAIL, 34, Prop.PEBBLES_A, 10, Prop.PEBBLES_B, 8, Prop.TUFT_TALL, 4]
const WORN_TABLE: PackedInt32Array = [Prop.PEBBLES_A, 40, Prop.PEBBLES_B, 40, Prop.TUFT_DRY, 20]

var game_map: Node2D
var fog_veil: Polygon2D = null
var ambient_life: Node2D = null

var _width: int = MapData.MAP_WIDTH
var _height: int = MapData.MAP_HEIGHT
var _origin: Vector2 = Vector2.ZERO
var _axis_x: Vector2 = Vector2(32.0, 16.0)
var _axis_y: Vector2 = Vector2(-32.0, 16.0)
var _inverse: Vector4 = Vector4(1.0, 0.0, 0.0, 1.0)

var _noise_bytes: PackedByteArray = PackedByteArray()
var _noise_texture: ImageTexture = null
var _water: PackedByteArray = PackedByteArray()
var _forest: PackedByteArray = PackedByteArray()
var _worn: PackedFloat32Array = PackedFloat32Array()
var _data_image: Image = null
var _data_texture: ImageTexture = null
var _data_dirty: bool = false
var _ground_materials: Array[ShaderMaterial] = []

var _props: MultiMesh = null
var _props_material: ShaderMaterial = null
var _prop_transforms: Array[Transform2D] = []
var _prop_tiles: Dictionary = {}  # Vector2i -> PackedInt32Array of instance ids
var _covered: Dictionary = {}  # Vector2i -> number of footprints over the tile
var _tracked_buildings: Dictionary = {}  # instance id -> {tile, footprint, shown, node}
var _unseen_buildings: Array[int] = []
var _poll_timer: float = 0.0


func setup(map: Node2D) -> void:
	game_map = map
	z_index = -9
	var generator: MapGenerator = map.map_generator
	_origin = map.tile_to_world(Vector2i.ZERO)
	_axis_x = map.tile_to_world(Vector2i(1, 0)) - _origin
	_axis_y = map.tile_to_world(Vector2i(0, 1)) - _origin
	var determinant: float = _axis_x.x * _axis_y.y - _axis_y.x * _axis_x.y
	_inverse = Vector4(_axis_y.y, -_axis_y.x, -_axis_x.y, _axis_x.x) / determinant
	_build_noise(int(generator._rng.seed))
	_build_ground_data(generator)
	_bind_ground_materials()
	_build_props(generator)
	_build_veil()
	ambient_life = AMBIENT_LIFE.new()
	ambient_life.name = "AmbientLife"
	ambient_life.game_map = map
	map.add_child(ambient_life)
	var buildings: Node = map.get_node_or_null("BuildingsContainer")
	if buildings != null:
		buildings.child_entered_tree.connect(_on_building_entered)
		buildings.child_exiting_tree.connect(_on_building_exiting)
	_apply_motion_setting()


func _exit_tree() -> void:
	for material: ShaderMaterial in _ground_materials:
		AMBIENT_MOTION.unregister(material)
	AMBIENT_MOTION.unregister(_props_material)
	if fog_veil != null and is_instance_valid(fog_veil):
		AMBIENT_MOTION.unregister(fog_veil.material as ShaderMaterial)


func _process(delta: float) -> void:
	if _data_dirty:
		_data_dirty = false
		_data_texture.update(_data_image)
	_poll_timer -= delta / maxf(0.001, Engine.time_scale)
	if _poll_timer > 0.0:
		return
	_poll_timer = SETTINGS_POLL_SECONDS
	_apply_motion_setting()
	if _unseen_buildings.is_empty():
		return
	for index: int in range(_unseen_buildings.size() - 1, -1, -1):
		var id: int = _unseen_buildings[index]
		var record: Dictionary = _tracked_buildings.get(id, {})
		var node: Node2D = record.get("node", null) as Node2D
		if record.is_empty() or not is_instance_valid(node):
			_unseen_buildings.remove_at(index)
		elif game_map.is_entity_visible_to_player(node, 0):
			_unseen_buildings.remove_at(index)
			_show_building_ground(record)


func _apply_motion_setting() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	var reduced: bool = game_manager != null and bool(game_manager.get("reduced_motion"))
	AMBIENT_MOTION.set_scale(0.0 if reduced else 1.0)


# --- Shared noise -----------------------------------------------------------

func _build_noise(map_seed: int) -> void:
	# One tileable texture, two channels: red is broad, green carries the same
	# kind of noise at a finer pitch. Shaders get two scales from each lookup.
	var broad: PackedByteArray = _noise_layer(map_seed % 100003, 0.018)
	var fine: PackedByteArray = _noise_layer(map_seed % 100003 + 71, 0.047)
	var count: int = NOISE_SIZE * NOISE_SIZE
	_noise_bytes.resize(count * 2)
	for index: int in count:
		_noise_bytes[index * 2] = broad[index]
		_noise_bytes[index * 2 + 1] = fine[index]
	_noise_texture = ImageTexture.create_from_image(Image.create_from_data(NOISE_SIZE, NOISE_SIZE, false, Image.FORMAT_RG8, _noise_bytes))


func _noise_layer(layer_seed: int, frequency: float) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = layer_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.52
	var image: Image = noise.get_seamless_image(NOISE_SIZE, NOISE_SIZE, false, false, 0.25)
	if image == null:
		image = Image.create(NOISE_SIZE, NOISE_SIZE, false, Image.FORMAT_L8)
		image.fill(Color(0.5, 0.5, 0.5))
	image.convert(Image.FORMAT_L8)
	return image.get_data()


## The same lookup the ground shader makes, so props agree with painted patches.
func _noise_at(world: Vector2, span: float, offset: Vector2, channel: int = 0) -> float:
	var u: float = world.x / span + offset.x
	var v: float = world.y * 2.0 / span + offset.y
	var x: int = posmod(int(floor(u * NOISE_SIZE)), NOISE_SIZE)
	var y: int = posmod(int(floor(v * NOISE_SIZE)), NOISE_SIZE)
	return float(_noise_bytes[(y * NOISE_SIZE + x) * 2 + channel]) / 255.0


func _climate_at(world: Vector2) -> float:
	return _noise_at(world, 3100.0, Vector2.ZERO, 0) * 0.62 + _noise_at(world, 3100.0, Vector2.ZERO, 1) * 0.38


# --- Painted ground ---------------------------------------------------------

func _build_ground_data(generator: MapGenerator) -> void:
	var count: int = _width * _height
	_water.resize(count)
	_forest.resize(count)
	_worn.resize(count)
	_worn.fill(0.0)
	for y: int in _height:
		var row: Array = generator.grid[y]
		for x: int in _width:
			var type: int = row[x]
			var index: int = y * _width + x
			_water[index] = 1 if type == MapData.TileType.WATER else 0
			_forest[index] = 1 if type == MapData.TileType.FOREST else 0
			if type in [MapData.TileType.GOLD_MINE, MapData.TileType.BERRY_BUSH, MapData.TileType.STONE]:
				_stamp_worn(Vector2(x, y), 2.1, 0.62)
			elif type == MapData.TileType.SACRED_SITE:
				_stamp_worn(Vector2(x, y), 2.4, 1.0)
	# Faint tracks along the public tactical routes, then the homesteads.
	for route: Dictionary in generator.get_tactical_routes():
		var points: Array = route["waypoints"]
		for index: int in range(1, points.size()):
			var from: Vector2 = Vector2(points[index - 1])
			var to: Vector2 = Vector2(points[index])
			var steps: int = maxi(1, int(from.distance_to(to) * 1.5))
			for step: int in steps + 1:
				_stamp_worn(from.lerp(to, float(step) / float(steps)), 1.9, 0.46)
	for spawn: Vector2i in generator.spawn_positions:
		_stamp_worn(Vector2(spawn) + Vector2(1.0, 1.0), 6.5, 1.0)
	for shrine: Vector2i in generator.get_shrine_tiles():
		_stamp_worn(Vector2(shrine), 3.0, 0.8)
	@warning_ignore("integer_division")
	_stamp_worn(Vector2(_width / 2, _height / 2), 4.5, 0.9)

	_data_image = Image.create(_width, _height, false, Image.FORMAT_RGBA8)
	for y: int in _height:
		for x: int in _width:
			_write_data_pixel(x, y)
	_data_texture = ImageTexture.create_from_image(_data_image)


func _stamp_worn(center: Vector2, radius: float, strength: float) -> void:
	var reach: int = int(ceil(radius))
	var cx: int = int(round(center.x))
	var cy: int = int(round(center.y))
	for y: int in range(maxi(0, cy - reach), mini(_height, cy + reach + 1)):
		for x: int in range(maxi(0, cx - reach), mini(_width, cx + reach + 1)):
			var distance: float = Vector2(x, y).distance_to(center)
			var value: float = strength * clampf(1.5 * (1.0 - distance / radius), 0.0, 1.0)
			var index: int = y * _width + x
			if value > _worn[index]:
				_worn[index] = value


func _write_data_pixel(x: int, y: int) -> void:
	var forest: float = 0.0
	var depth: float = 0.0
	for dy: int in range(-1, 2):
		var ny: int = y + dy
		for dx: int in range(-1, 2):
			var nx: int = x + dx
			var weight: float = 0.36 if dx == 0 and dy == 0 else (0.11 if dx == 0 or dy == 0 else 0.05)
			if nx < 0 or ny < 0 or nx >= _width or ny >= _height:
				continue
			var index: int = ny * _width + nx
			forest += weight * float(_forest[index])
			depth += float(_water[index]) / 9.0
	var here: int = y * _width + x
	_data_image.set_pixel(x, y, Color(float(_water[here]), forest, _worn[here], depth))


func _bind_ground_materials() -> void:
	var tile_set: TileSet = game_map.terrain_layer.tile_set
	if tile_set == null or tile_set.get_source_count() == 0:
		return
	var source := tile_set.get_source(0) as TileSetAtlasSource
	for column: int in [MapData.TileType.GRASS, MapData.TileType.WATER]:
		var material := source.get_tile_data(Vector2i(column, 0), 0).material as ShaderMaterial
		if material == null or _ground_materials.has(material):
			continue
		material.set_shader_parameter("ground_data", _data_texture)
		material.set_shader_parameter("ground_noise", _noise_texture)
		material.set_shader_parameter("map_origin", _origin)
		material.set_shader_parameter("map_inverse", _inverse)
		material.set_shader_parameter("map_tiles", float(_width))
		material.set_shader_parameter("dressed", true)
		_ground_materials.append(material)
		AMBIENT_MOTION.register(material)


## A felled or mined-out tile the player has now seen: lift the canopy shade.
func clear_forest_tile(tile: Vector2i) -> void:
	if tile.x < 0 or tile.y < 0 or tile.x >= _width or tile.y >= _height or _data_image == null:
		return
	var index: int = tile.y * _width + tile.x
	if _forest[index] == 0:
		return
	_forest[index] = 0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var x: int = tile.x + dx
			var y: int = tile.y + dy
			if x >= 0 and y >= 0 and x < _width and y < _height:
				_write_data_pixel(x, y)
	_data_dirty = true


# --- Ground props -----------------------------------------------------------

static func _tile_hash(x: int, y: int, salt: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 16)) * 668265263) & 0x7fffffff
	return h ^ (h >> 15)


static func _unit(x: int, y: int, salt: int) -> float:
	return float(_tile_hash(x, y, salt) % 100003) / 100003.0


static func _pick(table: PackedInt32Array, roll: float) -> int:
	var total: int = 0
	for index: int in range(1, table.size(), 2):
		total += table[index]
	var target: float = roll * float(total)
	for index: int in range(0, table.size(), 2):
		target -= float(table[index + 1])
		if target <= 0.0:
			return table[index]
	return table[table.size() - 2]


func _is_type(generator: MapGenerator, x: int, y: int, type: int) -> bool:
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return false
	return generator.grid[y][x] == type


func _build_props(generator: MapGenerator) -> void:
	var salt: int = int(generator._rng.seed) % 9973 + 17
	var transforms: Array[Transform2D] = []
	var customs: PackedColorArray = PackedColorArray()
	var tints: PackedColorArray = PackedColorArray()
	var owners: Array[Vector2i] = []
	@warning_ignore("integer_division")
	var center := Vector2i(_width / 2, _height / 2)
	var quiet_tiles: Array[Vector2i] = [center]
	quiet_tiles.append_array(generator.get_shrine_tiles())

	for y: int in _height:
		var row: Array = generator.grid[y]
		for x: int in _width:
			var type: int = row[x]
			var tile := Vector2i(x, y)
			var world: Vector2 = _origin + _axis_x * float(x) + _axis_y * float(y)
			var roll: float = _unit(x, y, salt)
			if type == MapData.TileType.WATER:
				# Lily pads idle in sheltered water beside a bank.
				if roll < 0.085 and _water_ring(x, y) == 4 and _land_within(x, y, 2):
					_add_prop(transforms, customs, tints, owners, tile, world, Prop.LILY, salt, 0)
				continue
			if not MapData.is_grass(type as MapData.TileType):
				continue
			var quiet: bool = false
			for spot: Vector2i in quiet_tiles:
				if absi(spot.x - x) <= 2 and absi(spot.y - y) <= 2:
					quiet = true
			if quiet:
				continue
			var here: int = y * _width + x
			var shore: bool = _water_touch(x, y)
			var woods: int = _forest_touch(generator, x, y)
			var pick_roll: float = _unit(x, y, salt + 101)
			if shore:
				if roll < 0.72:
					var toward: Vector2 = _water_direction(x, y)
					var cell: int = _pick(SHORE_TABLE, pick_roll)
					_add_prop(transforms, customs, tints, owners, tile, world + toward * 0.30, cell, salt, 0)
					if cell in [Prop.REEDS, Prop.CATTAIL] and _unit(x, y, salt + 7) < 0.6:
						_add_prop(transforms, customs, tints, owners, tile, world + toward * 0.12, Prop.REEDS, salt, 1)
			elif _worn[here] > 0.55:
				if roll < 0.10:
					_add_prop(transforms, customs, tints, owners, tile, world, _pick(WORN_TABLE, pick_roll), salt, 0)
			elif woods > 0:
				if roll < 0.52:
					_add_prop(transforms, customs, tints, owners, tile, world, _pick(WOODSIDE_TABLE, pick_roll), salt, 0)
			else:
				var climate: float = _climate_at(world)
				var bloom: float = _noise_at(world, 760.0, Vector2(0.19, 0.83))
				var faded: float = 1.0 - clampf(_worn[here] * 1.6, 0.0, 0.8)
				if bloom > 0.66 and climate < 0.60:
					# Drifts of wildflowers, thick enough to read as a meadow.
					if roll < 0.78 * faded:
						var cell: int = _pick(BLOOM_TABLE, pick_roll)
						_add_prop(transforms, customs, tints, owners, tile, world, cell, salt, 0)
						if _unit(x, y, salt + 7) < 0.55:
							_add_prop(transforms, customs, tints, owners, tile, world, _pick(BLOOM_TABLE, _unit(x, y, salt + 9)), salt, 1)
						if _unit(x, y, salt + 11) < 0.10:
							_add_prop(transforms, customs, tints, owners, tile, world, Prop.BUTTERFLY_PALE if roll < 0.4 else Prop.BUTTERFLY_AMBER, salt, 2)
				else:
					var table: PackedInt32Array = MEADOW_TABLE
					var density: float = 0.34
					if climate < 0.42:
						table = LUSH_TABLE
						density = 0.46
					elif climate > 0.60:
						table = DRY_TABLE
						density = 0.27
					if roll < density * faded:
						var cell: int = _pick(table, pick_roll)
						_add_prop(transforms, customs, tints, owners, tile, world, cell, salt, 0)
						if cell <= Prop.TUFT_DRY and _unit(x, y, salt + 7) < 0.45:
							_add_prop(transforms, customs, tints, owners, tile, world, cell, salt, 1)

	_prop_transforms = transforms
	_props = MultiMesh.new()
	_props.transform_format = MultiMesh.TRANSFORM_2D
	_props.use_colors = true
	_props.use_custom_data = true
	_props.mesh = _make_prop_mesh()
	_props.instance_count = transforms.size()
	for index: int in transforms.size():
		_props.set_instance_transform_2d(index, transforms[index])
		_props.set_instance_color(index, tints[index])
		_props.set_instance_custom_data(index, customs[index])
	for index: int in owners.size():
		var list: PackedInt32Array = _prop_tiles.get(owners[index], PackedInt32Array())
		list.append(index)
		_prop_tiles[owners[index]] = list

	var image: Image = PROPS_TEXTURE.get_image()
	var texture: Texture2D = PROPS_TEXTURE
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		# Premultiplied colour keeps minified edges from picking up dark fringes.
		image.convert(Image.FORMAT_RGBA8)
		image.clear_mipmaps()
		image.premultiply_alpha()
		image.generate_mipmaps()
		texture = ImageTexture.create_from_image(image)
	_props_material = ShaderMaterial.new()
	_props_material.shader = PROPS_SHADER
	AMBIENT_MOTION.register(_props_material)
	var instance := MultiMeshInstance2D.new()
	instance.name = "GroundProps"
	instance.multimesh = _props
	instance.texture = texture
	instance.material = _props_material
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(instance)


func _add_prop(transforms: Array[Transform2D], customs: PackedColorArray, tints: PackedColorArray, owners: Array[Vector2i],
		tile: Vector2i, world: Vector2, cell: int, salt: int, slot: int) -> void:
	var s: int = salt + 31 * (slot + 1)
	var jitter: Vector2 = _axis_x * (_unit(tile.x, tile.y, s + 1) - 0.5) * 0.62 + _axis_y * (_unit(tile.x, tile.y, s + 2) - 0.5) * 0.62
	var size: float = 0.86 + 0.34 * _unit(tile.x, tile.y, s + 3)
	if cell in [Prop.BOULDER, Prop.LOG, Prop.BLOSSOM_BUSH, Prop.FERN]:
		size *= 1.12
	var flip: float = -1.0 if _unit(tile.x, tile.y, s + 4) < 0.5 else 1.0
	var position: Vector2 = (world + jitter).round()
	transforms.append(Transform2D(Vector2(size * flip, 0.0), Vector2(0.0, size), position))
	var shade: float = 0.93 + 0.10 * _unit(tile.x, tile.y, s + 5)
	tints.append(Color(shade, shade, shade, 1.0))
	var butterfly: bool = cell == Prop.BUTTERFLY_PALE or cell == Prop.BUTTERFLY_AMBER
	customs.append(Color(float(cell), PROP_SWAY[cell], _unit(tile.x, tile.y, s + 6) * TAU, 1.0 if butterfly else 0.0))
	owners.append(tile)


func _make_prop_mesh() -> ArrayMesh:
	var half: float = PROP_QUAD * 0.5
	var top: float = -PROP_QUAD * 0.875
	var bottom: float = PROP_QUAD * 0.125
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-half, top), Vector2(half, top), Vector2(half, bottom), Vector2(-half, bottom)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _is_water(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < _width and y < _height and _water[y * _width + x] == 1


## Number of the four edge neighbours that are water.
func _water_ring(x: int, y: int) -> int:
	return int(_is_water(x - 1, y)) + int(_is_water(x + 1, y)) + int(_is_water(x, y - 1)) + int(_is_water(x, y + 1))


func _water_touch(x: int, y: int) -> bool:
	return _water_ring(x, y) > 0


func _land_within(x: int, y: int, reach: int) -> bool:
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and ny >= 0 and nx < _width and ny < _height and _water[ny * _width + nx] == 0:
				return true
	return false


func _water_direction(x: int, y: int) -> Vector2:
	var direction := Vector2.ZERO
	if _is_water(x - 1, y): direction -= _axis_x
	if _is_water(x + 1, y): direction += _axis_x
	if _is_water(x, y - 1): direction -= _axis_y
	if _is_water(x, y + 1): direction += _axis_y
	return direction


func _forest_touch(generator: MapGenerator, x: int, y: int) -> int:
	var count: int = 0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if (dx != 0 or dy != 0) and _is_type(generator, x + dx, y + dy, MapData.TileType.FOREST):
				count += 1
	return count


# --- Buildings press the ground flat ---------------------------------------

func _on_building_entered(node: Node) -> void:
	_track_building.call_deferred(node)


func _track_building(node: Node) -> void:
	if not is_instance_valid(node) or not node is BuildingBase or not node.is_inside_tree():
		return
	var building := node as BuildingBase
	var record: Dictionary = {
		"node": building,
		"tile": game_map.world_to_tile(building.global_position),
		"footprint": building.footprint,
		"shown": false,
	}
	_tracked_buildings[building.get_instance_id()] = record
	# Rival work is only pressed into the ground once the player has seen it,
	# so remembered terrain never gives away a hidden building.
	if building.player_owner == 0:
		_show_building_ground(record)
	else:
		_unseen_buildings.append(building.get_instance_id())


func _on_building_exiting(node: Node) -> void:
	var id: int = node.get_instance_id()
	if not _tracked_buildings.has(id):
		return
	var record: Dictionary = _tracked_buildings[id]
	_tracked_buildings.erase(id)
	if not bool(record.shown):
		return
	var origin: Vector2i = record.tile
	var footprint: Vector2i = record.footprint
	for dy: int in footprint.y:
		for dx: int in footprint.x:
			var tile: Vector2i = origin + Vector2i(dx, dy)
			var count: int = int(_covered.get(tile, 0)) - 1
			if count > 0:
				_covered[tile] = count
				continue
			_covered.erase(tile)
			for index: int in _prop_tiles.get(tile, PackedInt32Array()):
				_props.set_instance_transform_2d(index, _prop_transforms[index])


func _show_building_ground(record: Dictionary) -> void:
	record.shown = true
	var origin: Vector2i = record.tile
	var footprint: Vector2i = record.footprint
	for dy: int in footprint.y:
		for dx: int in footprint.x:
			var tile: Vector2i = origin + Vector2i(dx, dy)
			_covered[tile] = int(_covered.get(tile, 0)) + 1
			for index: int in _prop_tiles.get(tile, PackedInt32Array()):
				_props.set_instance_transform_2d(index, Transform2D(Vector2.ZERO, Vector2.ZERO, _prop_transforms[index].origin))
	# People wear the grass down around anything they build.
	var middle: Vector2 = Vector2(origin) + (Vector2(footprint) - Vector2.ONE) * 0.5
	var radius: float = maxf(footprint.x, footprint.y) * 0.5 + 1.7
	_stamp_worn(middle, radius, 0.95)
	var reach: int = int(ceil(radius)) + 1
	for y: int in range(maxi(0, int(middle.y) - reach), mini(_height, int(middle.y) + reach + 1)):
		for x: int in range(maxi(0, int(middle.x) - reach), mini(_width, int(middle.x) + reach + 1)):
			_write_data_pixel(x, y)
	_data_dirty = true


# --- Fog veil ---------------------------------------------------------------

func _build_veil() -> void:
	var host: Node = game_map.get_node_or_null("FogLayer")
	if host == null:
		return
	fog_veil = FOG_VEIL.new()
	fog_veil.name = "FogVeil"
	host.add_child(fog_veil)
	fog_veil.setup(game_map, _noise_texture, _origin, _inverse)
