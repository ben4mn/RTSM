extends Node2D
## Main map controller. Generates the map, builds the tilemap, sets up
## pathfinding, fog of war, camera, and selection manager.

## Emitted when map generation is complete.
signal map_ready(map_gen: MapGenerator)

## The map generator instance with the generated grid.
var map_generator: MapGenerator
## Pathfinding helper.
var pathfinding: Pathfinding

## Child node references (assigned in _ready).
@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var fog_of_war: FogManager = $FogOfWar
@onready var selection_mgr: SelectionManager = $SelectionManager
@onready var camera: Camera2D = $Camera2D

## Seed for deterministic map generation (-1 = random).
@export var map_seed: int = -1

## Camera drag/zoom state.
var _camera_drag_active := false
var _camera_drag_start := Vector2.ZERO
var _camera_origin := Vector2.ZERO
var _touch_points: Dictionary = {}  # index -> position

## Camera zoom limits.
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const ZOOM_SPEED := 0.1


## Preloaded sacred site scene.
var _sacred_site_scene: PackedScene = preload("res://scenes/map/sacred_site.tscn")

## Reference to the spawned sacred site instance.
var sacred_site: Node2D = null


func _ready() -> void:
	# Generate map.
	map_generator = MapGenerator.new(map_seed)
	map_generator.generate()

	# Create and assign procedural tilesets.
	terrain_layer.tile_set = TilesetBuilder.build_terrain_tileset()
	$FogLayer.tile_set = TilesetBuilder.build_fog_tileset()

	# Build visual tilemap.
	_build_terrain()

	# Set up pathfinding.
	pathfinding = Pathfinding.new(map_generator)

	# Configure fog of war.
	fog_of_war.fog_layer = $FogLayer
	fog_of_war.owning_player = 0

	# Configure selection manager.
	selection_mgr.game_map = self

	# Spawn sacred site at map center.
	_spawn_sacred_site()

	# Set up camera bounds.
	_configure_camera()

	# Notify others.
	map_ready.emit(map_generator)


## Build the terrain TileMapLayer from the generated grid.
func _build_terrain() -> void:
	if terrain_layer == null:
		return

	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			var tile_type: MapData.TileType = map_generator.grid[y][x] as MapData.TileType
			var atlas_coords := _tile_type_to_atlas(tile_type)
			terrain_layer.set_cell(Vector2i(x, y), 0, atlas_coords)


## Map tile type to atlas coordinate in our procedural tileset.
## Each tile type occupies a column in a 7x1 atlas.
func _tile_type_to_atlas(tile_type: MapData.TileType) -> Vector2i:
	return Vector2i(tile_type, 0)


## Configure camera with reasonable limits for a 32x32 isometric map.
func _configure_camera() -> void:
	if camera == null:
		return
	# Isometric map pixel bounds (approximate).
	var map_pixel_width := (MapData.MAP_WIDTH + MapData.MAP_HEIGHT) * MapData.TILE_WIDTH / 2
	var map_pixel_height := (MapData.MAP_WIDTH + MapData.MAP_HEIGHT) * MapData.TILE_HEIGHT / 2
	camera.limit_left = -map_pixel_width / 2 - 100
	camera.limit_right = map_pixel_width / 2 + 100
	camera.limit_top = -100
	camera.limit_bottom = map_pixel_height + 100
	# Start camera at center.
	camera.position = Vector2(0, map_pixel_height / 2)


## Handle camera pan and pinch-zoom.
func _unhandled_input(event: InputEvent) -> void:
	# --- Multi-touch pinch zoom (mobile) ---
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_points[touch.index] = touch.position
		else:
			_touch_points.erase(touch.index)
			if _touch_points.size() < 2:
				_camera_drag_active = false

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var old_pos: Vector2 = _touch_points.get(drag.index, drag.position)
		_touch_points[drag.index] = drag.position

		if _touch_points.size() == 2:
			# Pinch zoom.
			var keys := _touch_points.keys()
			var p0_new: Vector2 = _touch_points[keys[0]]
			var p1_new: Vector2 = _touch_points[keys[1]]
			var new_dist := p0_new.distance_to(p1_new)

			# Compute old distance using previous position for the moved finger.
			var p0_old: Vector2 = p0_new if drag.index != keys[0] else old_pos
			var p1_old: Vector2 = p1_new if drag.index != keys[1] else old_pos
			var old_dist := p0_old.distance_to(p1_old)

			if old_dist > 10.0:
				var zoom_factor := new_dist / old_dist
				_apply_zoom(zoom_factor)
		elif _touch_points.size() == 1:
			# Single-finger pan — only if selection manager isn't handling it.
			camera.position -= drag.relative / camera.zoom

	# --- Mouse wheel zoom (desktop) ---
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(1.0 + ZOOM_SPEED)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(1.0 - ZOOM_SPEED)
		# Middle-mouse drag for pan.
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_camera_drag_active = mb.pressed
			_camera_drag_start = mb.position
			_camera_origin = camera.position

	elif event is InputEventMouseMotion and _camera_drag_active:
		var motion := event as InputEventMouseMotion
		camera.position -= motion.relative / camera.zoom


func _apply_zoom(factor: float) -> void:
	var new_zoom := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(new_zoom, new_zoom)


## --- Public API ---

## Convert a tile coordinate to world (pixel) position.
func tile_to_world(tile_pos: Vector2i) -> Vector2:
	if terrain_layer:
		return terrain_layer.map_to_local(tile_pos)
	# Fallback isometric formula.
	var wx := (tile_pos.x - tile_pos.y) * MapData.TILE_WIDTH / 2
	var wy := (tile_pos.x + tile_pos.y) * MapData.TILE_HEIGHT / 2
	return Vector2(wx, wy)


## Convert a world (pixel) position to the nearest tile coordinate.
func world_to_tile(world_pos: Vector2) -> Vector2i:
	if terrain_layer:
		return terrain_layer.local_to_map(world_pos)
	# Fallback isometric formula.
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	var tile_x := int((world_pos.x / half_w + world_pos.y / half_h) / 2.0)
	var tile_y := int((world_pos.y / half_h - world_pos.x / half_w) / 2.0)
	return Vector2i(tile_x, tile_y)


## Get the tile type at a world position.
func get_tile_at_world(world_pos: Vector2) -> MapData.TileType:
	var tile_pos := world_to_tile(world_pos)
	return map_generator.get_tile(tile_pos)


## Get a movement path between two tile positions.
func get_movement_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return pathfinding.get_tile_path(from, to)


## Check if a tile is walkable.
func is_tile_walkable(tile_pos: Vector2i) -> bool:
	return pathfinding.is_walkable(tile_pos)


## Mark a building footprint as solid in pathfinding.
func place_building_obstacle(origin: Vector2i, size: Vector2i) -> void:
	pathfinding.set_area_solid(origin, size, true)


## Remove a building footprint from pathfinding.
func remove_building_obstacle(origin: Vector2i, size: Vector2i) -> void:
	pathfinding.set_area_solid(origin, size, false)


## Spawn the sacred site at the center of the map.
func _spawn_sacred_site() -> void:
	sacred_site = _sacred_site_scene.instantiate()
	var center := Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2)
	sacred_site.tile_position = center
	sacred_site.global_position = tile_to_world(center)
	$SacredSiteContainer.add_child(sacred_site)
