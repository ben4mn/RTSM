extends Node2D
## Main map controller. Generates the map, builds the tilemap, sets up
## pathfinding, fog of war, camera, and selection manager.

## Emitted when map generation is complete.
signal map_ready(map_gen: MapGenerator)
## HUD controls can track current zoom and enable only available directions.
signal zoom_changed(current: float, minimum: float, maximum: float)

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

## Mobile-first camera tuning.
@export var mobile_default_zoom: float = 1.02
@export var mobile_zoom_min: float = 0.62
@export var mobile_zoom_max: float = 2.2
@export var desktop_default_zoom: float = 1.35
@export var mobile_disable_camera_smoothing: bool = true

## Camera drag/zoom state.
var _camera_drag_active := false
var _camera_drag_start := Vector2.ZERO
var _camera_origin := Vector2.ZERO
var _touch_points: Dictionary = {}  # index -> position
var _touch_start_points: Dictionary = {}  # index -> initial press position
var _touch_pan_active: Dictionary = {}  # index -> bool
var _touch_input_detected: bool = false

## Camera zoom limits.
const DESKTOP_ZOOM_MIN := 0.5
const DESKTOP_ZOOM_MAX := 2.5
const ZOOM_STEP_FACTOR := 1.16
const NO_ZOOM_ANCHOR := Vector2(-1.0, -1.0)
const CAMERA_PAN_SPEED := 400.0
const EDGE_SCROLL_MARGIN := 8.0  # Pixels from screen edge to trigger scroll
const TOUCH_PAN_DEADZONE := 16.0  # Pixels before one-finger pan starts
const MOBILE_SHORT_SIDE_REFERENCE := 430.0
const MOBILE_SHORT_SIDE_MIN_SCALE := 0.90
const MOBILE_SHORT_SIDE_MAX_SCALE := 1.08
const MOBILE_SHORT_SIDE_PROFILE_MAX := 460.0  # Landscape phone short side cap.
const MOBILE_SHORT_SIDE_MIN := 360.0
const MOBILE_SHORT_SIDE_MAX := 520.0

var _camera_zoom_min: float = DESKTOP_ZOOM_MIN
var _camera_zoom_max: float = DESKTOP_ZOOM_MAX
var _camera_world_bounds: Rect2 = Rect2()
var _mobile_profile_active: bool = false
var _user_zoom_override: bool = false


## Preloaded scenes.
var _sacred_site_scene: PackedScene = preload("res://scenes/map/sacred_site.tscn")
var _resource_node_scene: PackedScene = preload("res://scenes/map/resource_node.tscn")

## Maps tile position (Vector2i) to the ResourceNode at that tile.
var resource_nodes: Dictionary = {}
## Player-built harvestables (currently farms), registered by match orchestration.
## Keeping these separate preserves tile-addressed natural-resource lookup.
var _additional_resource_nodes: Array[Node2D] = []
## Depleted terrain changes are simulation-live immediately, but their rendered
## tile and minimap terrain wait for current human vision so explored fog
## preserves honest memory. Values are the last-seen TileType.
var _pending_depleted_terrain_tiles: Dictionary = {}

## Reference to the spawned sacred site instance.
var sacred_site: Node2D = null

const NAVIGATION_ENDPOINT_MARGIN_WORLD := 8.0
const NAVIGATION_MAX_GOAL_RADIUS_TILES := 6
const NAVIGATION_MAX_GOAL_CANDIDATES := 32
const NAVIGATION_MAX_PATH_CHECKS := 32


func _ready() -> void:
	# Share depth sorting across all world entities so a person can walk
	# behind a building or tree rather than floating over its roof.
	y_sort_enabled = true
	terrain_layer.z_index = -10
	terrain_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for container_name: String in ["ResourcesContainer", "SacredSiteContainer", "UnitsContainer", "BuildingsContainer"]:
		var container: Node2D = get_node_or_null(NodePath(container_name)) as Node2D
		if container != null:
			container.y_sort_enabled = true
	# Generate map.
	var resolved_seed: int = map_seed
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.get("selected_map_seed") != null:
		resolved_seed = int(gm.get("selected_map_seed"))
	map_seed = resolved_seed
	map_generator = MapGenerator.new(resolved_seed)
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

	# Spawn harvestable resource nodes on resource tiles.
	_spawn_resource_nodes()

	# Set up camera bounds.
	_configure_camera()

	# Notify others (deferred so parent nodes have connected signals in _ready).
	call_deferred("_emit_map_ready")


func _emit_map_ready() -> void:
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
	var map_pixel_width: float = float(MapData.MAP_WIDTH + MapData.MAP_HEIGHT) * float(MapData.TILE_WIDTH) * 0.5
	var map_pixel_height: float = float(MapData.MAP_WIDTH + MapData.MAP_HEIGHT) * float(MapData.TILE_HEIGHT) * 0.5
	var left_bound: float = -map_pixel_width * 0.5
	var right_bound: float = map_pixel_width * 0.5
	var top_bound: float = 0.0
	var bottom_bound: float = map_pixel_height
	_camera_world_bounds = Rect2(
		Vector2(left_bound, top_bound),
		Vector2(right_bound - left_bound, bottom_bound - top_bound)
	)
	camera.limit_left = int(floor(left_bound))
	camera.limit_right = int(ceil(right_bound))
	camera.limit_top = int(floor(top_bound))
	camera.limit_bottom = int(ceil(bottom_bound))

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_apply_camera_profile(viewport_size, false)

	# Start camera at center.
	camera.position = Vector2(0.0, map_pixel_height * 0.5)
	_clamp_camera()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_SIZE_CHANGED:
		return
	if camera == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_apply_camera_profile(viewport_size, true)


func _is_mobile_camera_profile(viewport_size: Vector2) -> bool:
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		return true
	var short_side: float = minf(viewport_size.x, viewport_size.y)
	return short_side <= MOBILE_SHORT_SIDE_PROFILE_MAX


func _get_mobile_short_side_scale(viewport_size: Vector2) -> float:
	var short_side: float = maxf(1.0, minf(viewport_size.x, viewport_size.y))
	var normalized: float = clampf(inverse_lerp(MOBILE_SHORT_SIDE_MIN, MOBILE_SHORT_SIDE_MAX, short_side), 0.0, 1.0)
	var ratio: float = lerpf(MOBILE_SHORT_SIDE_MIN_SCALE, MOBILE_SHORT_SIDE_MAX_SCALE, normalized)
	ratio = minf(ratio, short_side / MOBILE_SHORT_SIDE_REFERENCE * 1.03)
	return clampf(ratio, MOBILE_SHORT_SIDE_MIN_SCALE, MOBILE_SHORT_SIDE_MAX_SCALE)


func _apply_camera_profile(viewport_size: Vector2, preserve_zoom_if_user_override: bool) -> void:
	_mobile_profile_active = _is_mobile_camera_profile(viewport_size)
	if _mobile_profile_active:
		_camera_zoom_min = maxf(0.1, mobile_zoom_min)
		_camera_zoom_max = maxf(_camera_zoom_min + 0.01, mobile_zoom_max)
		if mobile_disable_camera_smoothing:
			camera.position_smoothing_enabled = false
	else:
		_camera_zoom_min = DESKTOP_ZOOM_MIN
		_camera_zoom_max = DESKTOP_ZOOM_MAX
		camera.position_smoothing_enabled = true
	var desired_zoom: float = camera.zoom.x if preserve_zoom_if_user_override and _user_zoom_override else _get_default_zoom()
	_set_zoom_anchored(desired_zoom, NO_ZOOM_ANCHOR, NO_ZOOM_ANCHOR, false)


func _get_camera_half_view_world() -> Vector2:
	if camera == null:
		return Vector2.ZERO
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: float = maxf(0.001, camera.zoom.x)
	return Vector2(viewport_size.x * 0.5 / zoom, viewport_size.y * 0.5 / zoom)


func _process(delta: float) -> void:
	_update_camera_pan(delta)


func _update_camera_pan(delta: float) -> void:
	if camera == null:
		return
	var pan := Vector2.ZERO
	if Input.is_action_pressed("camera_up"):
		pan.y -= 1.0
	if Input.is_action_pressed("camera_down"):
		pan.y += 1.0
	if Input.is_action_pressed("camera_left"):
		pan.x -= 1.0
	if Input.is_action_pressed("camera_right"):
		pan.x += 1.0

	# Edge scrolling should only run on pointer-based desktop controls.
	if not DisplayServer.is_touchscreen_available() and not _touch_input_detected:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		if mouse_pos.x < EDGE_SCROLL_MARGIN:
			pan.x -= 1.0
		elif mouse_pos.x > viewport_size.x - EDGE_SCROLL_MARGIN:
			pan.x += 1.0
		if mouse_pos.y < EDGE_SCROLL_MARGIN:
			pan.y -= 1.0
		elif mouse_pos.y > viewport_size.y - EDGE_SCROLL_MARGIN:
			pan.y += 1.0

	if pan != Vector2.ZERO:
		var camera_speed_scale: float = 1.0
		var game_manager: Node = get_node_or_null("/root/GameManager")
		if game_manager != null:
			camera_speed_scale = clampf(float(game_manager.get("camera_speed_scale")), 0.75, 1.25)
		camera.position += pan.normalized() * CAMERA_PAN_SPEED * camera_speed_scale * delta / camera.zoom.x
		_clamp_camera()


func _clamp_camera() -> void:
	if camera == null:
		return
	var bounds_pos: Vector2 = _camera_world_bounds.position
	var bounds_end: Vector2 = _camera_world_bounds.position + _camera_world_bounds.size
	var half_view: Vector2 = _get_camera_half_view_world()

	var min_x: float = bounds_pos.x + half_view.x
	var max_x: float = bounds_end.x - half_view.x
	if min_x > max_x:
		camera.position.x = (bounds_pos.x + bounds_end.x) * 0.5
	else:
		camera.position.x = clampf(camera.position.x, min_x, max_x)

	var min_y: float = bounds_pos.y + half_view.y
	var max_y: float = bounds_end.y - half_view.y
	if min_y > max_y:
		camera.position.y = (bounds_pos.y + bounds_end.y) * 0.5
	else:
		camera.position.y = clampf(camera.position.y, min_y, max_y)


func _input(event: InputEvent) -> void:
	# A finger may end over a HUD button, which consumes its release before
	# unhandled input. Clean up without consuming the event or leaving a stale
	# second finger that would turn later drags into unexpected pinch gestures.
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		_release_camera_touch((event as InputEventScreenTouch).index)


func _release_camera_touch(index: int) -> void:
	if not _touch_points.has(index):
		return
	_touch_points.erase(index)
	_touch_start_points.erase(index)
	_touch_pan_active.erase(index)
	if _touch_points.size() < 2:
		_camera_drag_active = false
	if _touch_points.size() == 1:
		var remaining_index: int = int(_touch_points.keys()[0])
		_touch_start_points[remaining_index] = _touch_points[remaining_index]
		_touch_pan_active[remaining_index] = false


## A modal menu may receive the release of contacts that started in the world.
## Forget the old gesture so resuming cannot adopt those fingers or jump view.
func cancel_camera_touch_gesture() -> void:
	_touch_points.clear()
	_touch_start_points.clear()
	_touch_pan_active.clear()
	_camera_drag_active = false


## Handle camera pan and anchored pinch/wheel zoom.
func _unhandled_input(event: InputEvent) -> void:
	# --- Multi-touch pinch zoom (mobile) ---
	if event is InputEventScreenTouch:
		_touch_input_detected = true
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_points[touch.index] = touch.position
			_touch_start_points[touch.index] = touch.position
			_touch_pan_active[touch.index] = false
		else:
			_release_camera_touch(touch.index)

	elif event is InputEventScreenDrag:
		_touch_input_detected = true
		var drag := event as InputEventScreenDrag
		if not _touch_points.has(drag.index):
			# A finger that started on GUI belongs to GUI until it lifts.
			return
		var old_pos: Vector2 = _touch_points.get(drag.index, drag.position)
		_touch_points[drag.index] = drag.position

		if _touch_points.size() >= 2:
			# Pinch zoom.
			var keys: Array = _touch_points.keys()
			# Keep the first two world fingers in control if a third contact is
			# added. An extra finger must neither freeze nor shift their gesture.
			if drag.index != int(keys[0]) and drag.index != int(keys[1]):
				return
			var p0_new: Vector2 = _touch_points[keys[0]]
			var p1_new: Vector2 = _touch_points[keys[1]]
			var new_dist := p0_new.distance_to(p1_new)

			# Compute old distance using previous position for the moved finger.
			var p0_old: Vector2 = p0_new if drag.index != keys[0] else old_pos
			var p1_old: Vector2 = p1_new if drag.index != keys[1] else old_pos
			var old_dist := p0_old.distance_to(p1_old)

			if old_dist > 10.0 and new_dist > 10.0:
				var zoom_factor := new_dist / old_dist
				var old_midpoint: Vector2 = (p0_old + p1_old) * 0.5
				var new_midpoint: Vector2 = (p0_new + p1_new) * 0.5
				_set_zoom_anchored(camera.zoom.x * zoom_factor, old_midpoint, new_midpoint, true)
		elif _touch_points.size() == 1:
			# Single-finger pan starts only after crossing a drag deadzone.
			var start_pos: Vector2 = _touch_start_points.get(drag.index, drag.position)
			var moved_distance: float = start_pos.distance_to(drag.position)
			var pan_active: bool = _touch_pan_active.get(drag.index, false)
			if not pan_active and moved_distance >= TOUCH_PAN_DEADZONE:
				pan_active = true
				_touch_pan_active[drag.index] = true
			if pan_active:
				camera.position -= drag.relative / camera.zoom
				_clamp_camera()

	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_apply_zoom(magnify.factor, true, magnify.position)
		get_viewport().set_input_as_handled()

	# --- Mouse wheel zoom (desktop) ---
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in(mb.position)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out(mb.position)
			get_viewport().set_input_as_handled()
		# Middle-mouse drag for pan.
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_camera_drag_active = mb.pressed
			_camera_drag_start = mb.position
			_camera_origin = camera.position

	elif event is InputEventMouseMotion and _camera_drag_active:
		var motion := event as InputEventMouseMotion
		camera.position -= motion.relative / camera.zoom
		_clamp_camera()


func _apply_zoom(factor: float, from_user: bool = false, anchor_screen: Vector2 = NO_ZOOM_ANCHOR) -> void:
	if camera == null or factor <= 0.0 or not is_finite(factor):
		return
	_set_zoom_anchored(camera.zoom.x * factor, anchor_screen, anchor_screen, from_user)


func _set_zoom_anchored(level: float, previous_anchor: Vector2, next_anchor: Vector2, from_user: bool) -> void:
	if camera == null or not is_finite(level):
		return
	var viewport_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var before: Vector2 = viewport_center if previous_anchor == NO_ZOOM_ANCHOR else previous_anchor
	var after: Vector2 = viewport_center if next_anchor == NO_ZOOM_ANCHOR else next_anchor
	# Read the rendered view rather than the camera's smoothing target. This
	# makes zoom during a pan preserve the exact terrain under the pointer.
	var anchor_world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * before
	var next_zoom: float = clampf(level, _camera_zoom_min, _camera_zoom_max)
	camera.zoom = Vector2(next_zoom, next_zoom)
	camera.position = anchor_world + (viewport_center - after) / next_zoom
	if from_user:
		_user_zoom_override = true
	_clamp_camera()
	# A zoom is immediate; smoothing remains enabled for ordinary desktop pan.
	camera.reset_smoothing()
	camera.force_update_scroll()
	zoom_changed.emit(camera.zoom.x, _camera_zoom_min, _camera_zoom_max)


func _get_default_zoom() -> float:
	var default_level: float = desktop_default_zoom
	if _mobile_profile_active:
		default_level = mobile_default_zoom * _get_mobile_short_side_scale(get_viewport().get_visible_rect().size)
	return clampf(default_level, _camera_zoom_min, _camera_zoom_max)


func zoom_in(anchor_screen: Vector2 = NO_ZOOM_ANCHOR) -> void:
	_apply_zoom(ZOOM_STEP_FACTOR, true, anchor_screen)


func zoom_out(anchor_screen: Vector2 = NO_ZOOM_ANCHOR) -> void:
	_apply_zoom(1.0 / ZOOM_STEP_FACTOR, true, anchor_screen)


func reset_zoom(anchor_screen: Vector2 = NO_ZOOM_ANCHOR) -> void:
	_set_zoom_anchored(_get_default_zoom(), anchor_screen, anchor_screen, true)


func show_overview() -> void:
	_set_zoom_anchored(_camera_zoom_min, NO_ZOOM_ANCHOR, NO_ZOOM_ANCHOR, true)


func get_zoom_state() -> Dictionary:
	var current_zoom: float = camera.zoom.x if camera != null else _get_default_zoom()
	var default_zoom: float = _get_default_zoom()
	return {
		"zoom": current_zoom,
		"min": _camera_zoom_min,
		"max": _camera_zoom_max,
		"default": default_zoom,
		"ratio": current_zoom / maxf(0.001, default_zoom),
	}


## --- Public API ---

## Convert a tile coordinate to world (pixel) position.
func tile_to_world(tile_pos: Vector2i) -> Vector2:
	if terrain_layer:
		return terrain_layer.map_to_local(tile_pos)
	# Fallback isometric formula.
	@warning_ignore("integer_division")
	var wx := (tile_pos.x - tile_pos.y) * MapData.TILE_WIDTH / 2
	@warning_ignore("integer_division")
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


## Build a bounded world-space route toward a gameplay target. Candidate goal
## tiles are ordered by actual isometric world distance, then passed to the
## bounded A* helper. A small endpoint margin lets units stop on the nearest
## tile beside solid building footprints without walking through the building.
func get_navigation_world_path(
	from_world: Vector2,
	target_world: Vector2,
	arrival_radius_world: float = 4.0,
	max_goal_radius_tiles: int = NAVIGATION_MAX_GOAL_RADIUS_TILES
) -> PackedVector2Array:
	if pathfinding == null:
		return PackedVector2Array()
	var from_tile: Vector2i = world_to_tile(from_world)
	var target_tile: Vector2i = world_to_tile(target_world)
	var radius_from_range: int = int(ceil(
		(arrival_radius_world + NAVIGATION_ENDPOINT_MARGIN_WORLD) / maxf(1.0, float(MapData.TILE_HEIGHT))
	)) + 1
	var search_radius: int = clampi(
		maxi(1, radius_from_range),
		1,
		maxi(1, max_goal_radius_tiles)
	)
	var candidates: Array[Vector2i] = pathfinding.get_walkable_tiles_near(
		target_tile,
		search_radius,
		NAVIGATION_MAX_GOAL_CANDIDATES
	)
	# Prefer candidates that satisfy the requested interaction radius. Remaining
	# nearby candidates are still useful as a recoverable endpoint for ground
	# movement and as evidence that an interaction target is unreachable.
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_world: Vector2 = tile_to_world(a)
		var b_world: Vector2 = tile_to_world(b)
		var a_distance: float = a_world.distance_to(target_world)
		var b_distance: float = b_world.distance_to(target_world)
		var acceptable_distance: float = arrival_radius_world + NAVIGATION_ENDPOINT_MARGIN_WORLD
		var a_acceptable: bool = a_distance <= acceptable_distance
		var b_acceptable: bool = b_distance <= acceptable_distance
		if a_acceptable != b_acceptable:
			return a_acceptable
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		return a_world.distance_squared_to(from_world) < b_world.distance_squared_to(from_world)
	)
	var tile_path: Array[Vector2i] = pathfinding.get_tile_path_to_any(
		from_tile,
		candidates,
		NAVIGATION_MAX_PATH_CHECKS
	)
	var world_path := PackedVector2Array()
	for tile: Vector2i in tile_path:
		world_path.append(tile_to_world(tile))
	return world_path


## Building work uses the full footprint. The anchor is one corner of the
## obstacle, so its nearest edge may be sealed while another edge is reachable.
func get_building_work_distance(from_world: Vector2, anchor_world: Vector2, footprint: Vector2i) -> float:
	var origin: Vector2i = world_to_tile(anchor_world)
	var closest: float = INF
	for dy: int in range(maxi(1, footprint.y)):
		for dx: int in range(maxi(1, footprint.x)):
			closest = minf(closest, from_world.distance_to(tile_to_world(origin + Vector2i(dx, dy))))
	return closest


## Only real walkable perimeter tiles inside the work distance are goals.
## There is no out-of-range fallback endpoint for construction or harvesting.
func get_building_work_world_path(
	from_world: Vector2,
	anchor_world: Vector2,
	footprint: Vector2i,
	action_radius_world: float
) -> PackedVector2Array:
	if pathfinding == null:
		return PackedVector2Array()
	var origin: Vector2i = world_to_tile(anchor_world)
	var size := Vector2i(maxi(1, footprint.x), maxi(1, footprint.y))
	var candidates: Array[Vector2i] = []
	for dy: int in range(-1, size.y + 1):
		for dx: int in range(-1, size.x + 1):
			if dx >= 0 and dx < size.x and dy >= 0 and dy < size.y:
				continue
			var tile: Vector2i = origin + Vector2i(dx, dy)
			if not pathfinding.is_walkable(tile):
				continue
			if get_building_work_distance(tile_to_world(tile), anchor_world, size) <= action_radius_world:
				candidates.append(tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return from_world.distance_squared_to(tile_to_world(a)) < from_world.distance_squared_to(tile_to_world(b))
	)
	var tile_path: Array[Vector2i] = pathfinding.get_tile_path_to_any(
		world_to_tile(from_world), candidates, NAVIGATION_MAX_PATH_CHECKS
	)
	var world_path := PackedVector2Array()
	for tile: Vector2i in tile_path:
		world_path.append(tile_to_world(tile))
	return world_path


## Canonical current-visibility query for every simulated player. Player 0 uses
## the rendered FogManager grid; players without a FogManager derive the same
## tile-circle result from their live units and non-destroyed buildings.
func is_entity_visible_to_player(entity: Node2D, viewer_player_id: int = 0) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	var entity_owner: int = -1
	if entity.has_method("get_player_id"):
		entity_owner = int(entity.call("get_player_id"))
	elif entity.has_method("get_player_owner"):
		entity_owner = int(entity.call("get_player_owner"))
	if entity_owner == viewer_player_id:
		return true

	var origin_tile: Vector2i = world_to_tile(entity.global_position)
	var target_tiles: Array[Vector2i] = []
	if entity is BuildingBase:
		var building := entity as BuildingBase
		for dy in range(building.footprint.y):
			for dx in range(building.footprint.x):
				target_tiles.append(origin_tile + Vector2i(dx, dy))
	else:
		target_tiles.append(origin_tile)

	if fog_of_war != null and viewer_player_id == fog_of_war.owning_player:
		for tile: Vector2i in target_tiles:
			if fog_of_war.is_tile_visible(tile):
				return true
		return false
	return _are_tiles_visible_from_live_sources(target_tiles, viewer_player_id)


## Fog-aware tile visibility used by player-issued world interactions and by
## non-local simulation systems that need the same current-vision rule.
func is_tile_visible_to_player(tile_pos: Vector2i, viewer_player_id: int = 0) -> bool:
	if (
		tile_pos.x < 0
		or tile_pos.x >= MapData.MAP_WIDTH
		or tile_pos.y < 0
		or tile_pos.y >= MapData.MAP_HEIGHT
	):
		return false
	if fog_of_war != null and viewer_player_id == fog_of_war.owning_player:
		return fog_of_war.is_tile_visible(tile_pos)
	return _are_tiles_visible_from_live_sources([tile_pos], viewer_player_id)


func _are_tiles_visible_from_live_sources(
	target_tiles: Array[Vector2i],
	viewer_player_id: int
) -> bool:
	if target_tiles.is_empty() or not is_inside_tree():
		return false

	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not is_ancestor_of(node) or not (node is UnitBase):
			continue
		var unit := node as UnitBase
		if unit.player_owner != viewer_player_id or unit.current_state == UnitBase.State.DEAD:
			continue
		var unit_tile: Vector2i = world_to_tile(unit.global_position)
		var unit_vision: int = int(round(MapData.world_to_range_tiles(unit.vision_radius)))
		if _vision_circle_contains_any(unit_tile, unit_vision, target_tiles):
			return true

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not is_ancestor_of(node) or not (node is BuildingBase):
			continue
		var building := node as BuildingBase
		if (
			building.player_owner != viewer_player_id
			or building.state == BuildingBase.State.DESTROYED
		):
			continue
		var building_tile: Vector2i = world_to_tile(building.global_position)
		var stats: Dictionary = BuildingData.get_building_stats(building.building_type)
		var building_vision: int = int(stats.get("vision_radius", 3))
		if _vision_circle_contains_any(building_tile, building_vision, target_tiles):
			return true
	return false


func _vision_circle_contains_any(
	source_tile: Vector2i,
	radius: int,
	target_tiles: Array[Vector2i]
) -> bool:
	var radius_squared: int = maxi(0, radius) * maxi(0, radius)
	for target_tile: Vector2i in target_tiles:
		var delta: Vector2i = target_tile - source_tile
		if delta.x * delta.x + delta.y * delta.y <= radius_squared:
			return true
	return false


## Check if a tile is walkable.
func is_tile_walkable(tile_pos: Vector2i) -> bool:
	return pathfinding.is_walkable(tile_pos)


## Canonical structure-placement terrain contract. Movement permits forests and
## resource terrain, but foundations require open grass with no live natural
## resource occupying the tile.
func is_tile_buildable(tile_pos: Vector2i) -> bool:
	if (
		tile_pos.x < 0
		or tile_pos.x >= MapData.MAP_WIDTH
		or tile_pos.y < 0
		or tile_pos.y >= MapData.MAP_HEIGHT
		or map_generator == null
		or pathfinding == null
	):
		return false
	if not MapData.is_grass(map_generator.grid[tile_pos.y][tile_pos.x] as MapData.TileType):
		return false
	var natural_resource: Node2D = resource_nodes.get(tile_pos, null) as Node2D
	if natural_resource != null and is_instance_valid(natural_resource):
		return false
	return pathfinding.is_walkable(tile_pos)


## Mark a building footprint as solid in pathfinding.
func place_building_obstacle(origin: Vector2i, size: Vector2i) -> void:
	pathfinding.set_area_solid(origin, size, true)


## Remove a building footprint from pathfinding.
func remove_building_obstacle(origin: Vector2i, size: Vector2i) -> void:
	pathfinding.set_area_solid(origin, size, false)


## Spawn ResourceNode instances on every resource tile.
func _spawn_resource_nodes() -> void:
	var type_map: Dictionary = {
		MapData.TileType.BERRY_BUSH: { "type": "food", "amount": 200 },
		MapData.TileType.FOREST: { "type": "wood", "amount": 250 },
		MapData.TileType.GOLD_MINE: { "type": "gold", "amount": 400 },
		# Stone is intentionally excluded until a usable stone economy is implemented.
	}
	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			var tile_type: MapData.TileType = map_generator.grid[y][x] as MapData.TileType
			if not type_map.has(tile_type):
				continue
			var info: Dictionary = type_map[tile_type]
			var node = _resource_node_scene.instantiate()
			node.resource_type = info["type"]
			node.total_amount = info["amount"]
			var tile_pos := Vector2i(x, y)
			node.tile_position = tile_pos
			node.global_position = tile_to_world(tile_pos)
			$ResourcesContainer.add_child(node)
			resource_nodes[tile_pos] = node
			node.depleted.connect(_on_resource_depleted.bind(tile_pos))


func _on_resource_depleted(node: Node2D, tile_pos: Vector2i) -> void:
	if resource_nodes.get(tile_pos, null) == node:
		resource_nodes.erase(tile_pos)
	if (
		map_generator == null
		or pathfinding == null
		or tile_pos.x < 0
		or tile_pos.x >= MapData.MAP_WIDTH
		or tile_pos.y < 0
		or tile_pos.y >= MapData.MAP_HEIGHT
	):
		return
	var prior_type: MapData.TileType = map_generator.grid[tile_pos.y][tile_pos.x] as MapData.TileType
	if prior_type not in [
		MapData.TileType.FOREST,
		MapData.TileType.GOLD_MINE,
		MapData.TileType.BERRY_BUSH,
	]:
		return
	map_generator.grid[tile_pos.y][tile_pos.x] = MapData.TileType.GRASS
	pathfinding.update_tile(tile_pos, MapData.TileType.GRASS)
	_pending_depleted_terrain_tiles[tile_pos] = prior_type
	if is_tile_visible_to_player(tile_pos, 0):
		_apply_depleted_terrain_visual(tile_pos)


## Natural-resource visuals reveal only under current vision. Explored terrain
## retains terrain memory, never the live presence or depletion state of stock.
func update_resource_visibility_for_player(viewer_player_id: int = 0) -> void:
	for tile_pos: Vector2i in resource_nodes:
		var resource: Node2D = resource_nodes[tile_pos] as Node2D
		if resource == null or not is_instance_valid(resource):
			continue
		resource.visible = is_tile_visible_to_player(tile_pos, viewer_player_id)
	var revealed_depletions: Array[Vector2i] = []
	for tile_variant: Variant in _pending_depleted_terrain_tiles.keys():
		var tile_pos: Vector2i = tile_variant as Vector2i
		if is_tile_visible_to_player(tile_pos, viewer_player_id):
			revealed_depletions.append(tile_pos)
	for tile_pos: Vector2i in revealed_depletions:
		_apply_depleted_terrain_visual(tile_pos)


func _apply_depleted_terrain_visual(tile_pos: Vector2i) -> void:
	if terrain_layer != null:
		terrain_layer.set_cell(tile_pos, 0, _tile_type_to_atlas(MapData.TileType.GRASS))
	_pending_depleted_terrain_tiles.erase(tile_pos)


## Return a fog-honest terrain snapshot for the local minimap. Simulation and
## navigation use the current grid immediately, while explored-only tiles keep
## the terrain type last observed by the player until the tile is revealed.
func get_minimap_grid_for_player(viewer_player_id: int = 0) -> Array:
	if map_generator == null:
		return []
	var minimap_grid: Array = []
	for row: Array in map_generator.grid:
		minimap_grid.append(row.duplicate())
	for tile_variant: Variant in _pending_depleted_terrain_tiles.keys():
		var tile_pos: Vector2i = tile_variant as Vector2i
		if is_tile_visible_to_player(tile_pos, viewer_player_id):
			continue
		minimap_grid[tile_pos.y][tile_pos.x] = _pending_depleted_terrain_tiles[tile_pos]
	return minimap_grid


## Spawn the sacred site at the center of the map.
func _spawn_sacred_site() -> void:
	sacred_site = _sacred_site_scene.instantiate()
	@warning_ignore("integer_division")
	var center := Vector2i(MapData.MAP_WIDTH / 2, MapData.MAP_HEIGHT / 2)
	sacred_site.tile_position = center
	sacred_site.global_position = tile_to_world(center)
	$SacredSiteContainer.add_child(sacred_site)


## Get the resource node at a specific tile, or null.
func get_resource_node_at(tile: Vector2i) -> Node2D:
	return resource_nodes.get(tile, null)


## Register a player-built harvestable without changing natural tile lookup.
func register_harvestable(node: Node2D) -> void:
	if node != null and is_instance_valid(node) and node not in _additional_resource_nodes:
		_additional_resource_nodes.append(node)


func unregister_harvestable(node: Node2D) -> void:
	_additional_resource_nodes.erase(node)


## Shared validity contract used by nearest-resource lookup and player input.
## A negative player id means ownership is irrelevant (useful for neutral discovery).
func is_resource_target_valid(node: Node2D, type: String = "", player_id: int = -1) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not node.has_method("get_resource_type") or not node.has_method("harvest"):
		return false
	var node_type: String = String(node.call("get_resource_type"))
	if node_type == "" or (type != "" and node_type != type):
		return false
	if node.has_method("is_harvestable_by"):
		return bool(node.call("is_harvestable_by", player_id))
	return true


## Resource discovery is fog-aware whenever a concrete player is supplied.
## A negative player id remains the explicit omniscient/debug discovery mode.
func is_resource_target_visible_to_player(node: Node2D, player_id: int = -1) -> bool:
	if player_id < 0:
		return true
	return is_entity_visible_to_player(node, player_id)


## Find the nearest resource node of a given type ("food", "wood", "gold") from a world position.
## When player_id is supplied, candidates must be currently visible and enemy-owned farms are excluded.
func get_nearest_resource_node(type: String, from: Vector2, player_id: int = -1) -> Node2D:
	var best_node: Node2D = null
	var best_dist: float = INF
	var candidates: Array[Node2D] = []
	for tile_pos: Vector2i in resource_nodes:
		var natural_node: Node2D = resource_nodes[tile_pos] as Node2D
		if natural_node != null:
			candidates.append(natural_node)
	for additional_node: Node2D in _additional_resource_nodes:
		if additional_node != null and additional_node not in candidates:
			candidates.append(additional_node)
	for node: Node2D in candidates:
		if not is_resource_target_visible_to_player(node, player_id):
			continue
		if not is_resource_target_valid(node, type, player_id):
			continue
		var dist: float = from.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_node = node
	# Compact stale references opportunistically after lookup.
	for index in range(_additional_resource_nodes.size() - 1, -1, -1):
		var candidate: Node2D = _additional_resource_nodes[index]
		if candidate == null or not is_instance_valid(candidate):
			_additional_resource_nodes.remove_at(index)
	return best_node


## Path-aware resource recovery for autonomous villagers. At most twelve
## candidates are probed, and every route probe is itself bounded.
func get_nearest_reachable_resource_node(
	type: String,
	from: Vector2,
	player_id: int = -1,
	excluded_instance_ids: Dictionary = {}
) -> Node2D:
	var candidates: Array[Node2D] = []
	for tile_pos: Vector2i in resource_nodes:
		var natural_node: Node2D = resource_nodes[tile_pos] as Node2D
		if (
			natural_node != null
			and is_resource_target_visible_to_player(natural_node, player_id)
			and is_resource_target_valid(natural_node, type, player_id)
		):
			candidates.append(natural_node)
	for additional_node: Node2D in _additional_resource_nodes:
		if (
			additional_node != null
			and additional_node not in candidates
			and is_resource_target_visible_to_player(additional_node, player_id)
			and is_resource_target_valid(additional_node, type, player_id)
		):
			candidates.append(additional_node)
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return from.distance_squared_to(a.global_position) < from.distance_squared_to(b.global_position)
	)
	var checked: int = 0
	for candidate: Node2D in candidates:
		if checked >= 12:
			break
		if excluded_instance_ids.has(candidate.get_instance_id()):
			continue
		checked += 1
		var is_farm: bool = candidate is BuildingBase and (candidate as BuildingBase).provides_food
		var route: PackedVector2Array
		if is_farm:
			route = get_building_work_world_path(from, candidate.global_position, (candidate as BuildingBase).footprint, Villager.BUILD_APPROACH_DISTANCE)
		else:
			route = get_navigation_world_path(from, candidate.global_position, MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD)
		if route.is_empty():
			continue
		if is_farm:
			return candidate
		if (
			route[route.size() - 1].distance_to(candidate.global_position)
			<= MapData.RESOURCE_GATHER_INTERACTION_RADIUS_WORLD
		):
			return candidate
	return null
