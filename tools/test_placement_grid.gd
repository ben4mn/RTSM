extends Node
## Placement-only geometry: local candidate coverage, canonical tile edges, constant
## screen weight, map bounds, fog neutrality and complete input lifecycle.

var _failures: Array[String] = []
var _world: ProjectionWorld
var _placement: BuildingPlacement
var _camera: Camera2D

class ProjectionWorld extends Node2D:
	var projection: Node2D = load("res://scripts/map/game_map.gd").new()
	var visible_tiles: bool = true
	var blocked: bool = false
	var visibility_queries: int = 0
	var terrain_queries: int = 0

	func tile_to_world(tile: Vector2i) -> Vector2:
		return projection.call("tile_to_world", tile)

	func world_to_tile(point: Vector2) -> Vector2i:
		return projection.call("world_to_tile", point)

	func is_tile_visible_to_player(_tile: Vector2i, _owner: int = 0) -> bool:
		visibility_queries += 1
		return visible_tiles

	func is_tile_buildable(_tile: Vector2i) -> bool:
		terrain_queries += 1
		return not blocked

	func _exit_tree() -> void:
		projection.free()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	_world = ProjectionWorld.new()
	add_child(_world)
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position = _world.tile_to_world(Vector2i(24, 24))
	_world.add_child(_camera)
	_placement = BuildingPlacement.new()
	_world.add_child(_placement)
	await get_tree().process_frame
	_expect(_placement.get_node_or_null("PlacementGrid") == null, "normal play allocates no grid")
	_placement.start_placement(BuildingData.BuildingType.HOUSE)
	var grid: Node2D = _placement.get_node("PlacementGrid")
	_expect(grid.is_visible_in_tree(), "placement opens a visible ground grid")
	_expect(not grid.z_as_relative and grid.z_index > -10 and grid.z_index < 0, "grid is above terrain and below world objects and fog")
	_expect(BuildingPlacement.PLACEMENT_GRID_COLOR.a < 0.25, "surrounding grid is substantially softer than the footprint")
	for zoom: float in [0.42, 0.95, 2.2]:
		_camera.zoom = Vector2.ONE * zoom
		_camera.force_update_scroll()
		await get_tree().process_frame
		_placement.call("_refresh_placement_grid", true)
		var points := _world_segments()
		_expect(not points.is_empty(), "screen-visible tiles have grid lines at zoom %.2f" % zoom)
		_expect(points.size() <= 20, "House guide stays within one tile of its footprint, even at overview zoom")
		var pixels: float = float(grid.get("line_width")) * _placement.get_canvas_transform().x.length()
		_expect(is_equal_approx(pixels, 0.9), "grid stroke remains 0.9 screen pixels at zoom %.2f" % zoom)
		_check_map_bounds(points)
		_check_footprint_alignment(points)
	# The small guide follows the chosen footprint while remaining snapped to world tiles.
	var before_move := _world_segments()
	_placement.update_preview_at_world(_world.tile_to_world(Vector2i(26, 25)))
	_expect(not _points_match(before_move, _world_segments()), "moving the preview moves its small guide instead of covering the scene")
	_check_footprint_alignment(_world_segments())
	var old_bounds: Rect2i = _placement.get("_grid_tile_bounds")
	_camera.position = _world.tile_to_world(Vector2i(37, 32))
	_camera.force_update_scroll()
	await get_tree().process_frame
	_placement.call("_process", 0.01)
	_expect(_placement.get("_grid_tile_bounds") != old_bounds, "camera movement clips the local guide to the visible scene")
	# Grid geometry is deliberately ignorant of hidden content and visibility.
	var before_hidden := _world_segments()
	_world.visible_tiles = false
	_world.blocked = true
	_world.visibility_queries = 0
	_world.terrain_queries = 0
	_placement.call("_refresh_placement_grid", true)
	_expect(_points_match(before_hidden, _world_segments()), "hidden resources/buildings cannot alter grid geometry")
	_expect(_world.visibility_queries == 0 and _world.terrain_queries == 0, "grid queries no fog, terrain, occupancy or resources")
	# The camera can view map corners or empty space beyond the map.
	_placement.update_preview_at_world(_world.tile_to_world(Vector2i.ZERO))
	_camera.position = _world.tile_to_world(Vector2i.ZERO)
	_camera.force_update_scroll()
	await get_tree().process_frame
	_placement.call("_refresh_placement_grid", true)
	_check_map_bounds(_world_segments())
	var edge_bounds: Rect2i = _placement.get("_grid_tile_bounds")
	_expect(edge_bounds.position == Vector2i.ZERO, "map corner clamps the grid to actual tiles")
	_camera.position = Vector2(-50000, -50000)
	_camera.force_update_scroll()
	await get_tree().process_frame
	_placement.call("_refresh_placement_grid", true)
	_expect(_world_segments().is_empty(), "camera outside the map draws no invented tiles")
	_placement.update_preview_at_world(_world.tile_to_world(Vector2i(24, 24)))
	_camera.position = _world.tile_to_world(Vector2i(24, 24))
	_camera.zoom = Vector2.ONE
	_camera.force_update_scroll()
	await get_tree().process_frame
	_placement.call("_refresh_placement_grid", true)
	var phone_bounds: Rect2i = _placement.get("_grid_tile_bounds")
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	await get_tree().process_frame
	_placement.call("_process", 0.01)
	var desktop_bounds: Rect2i = _placement.get("_grid_tile_bounds")
	_expect(desktop_bounds == phone_bounds, "resizing to desktop does not spread guide lines across the battlefield")
	_placement.cancel_placement()
	_expect(not grid.is_visible_in_tree() and _world_segments().is_empty(), "Cancel removes the placement grid immediately")
	_world.visible_tiles = true
	_world.blocked = false
	_placement.start_placement(BuildingData.BuildingType.HOUSE)
	_expect(grid.is_visible_in_tree(), "a later placement reuses and restores the grid")
	_expect(_placement.confirm_preview(), "valid explicit Place still confirms")
	_expect(not grid.is_visible_in_tree() and _world_segments().is_empty(), "successful Place removes the grid immediately")
	_world.free()
	for failure: String in _failures:
		push_error("[FAIL] placement_grid: " + failure)
	if _failures.is_empty():
		print("[PASS] placement_grid: canonical footprint alignment, bounded local guide, zoom/pan/resize, map edges, fog-neutral geometry, layers, Cancel/Place lifecycle")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _world_segments() -> PackedVector2Array:
	var grid: Node2D = _placement.get_node("PlacementGrid")
	var result := PackedVector2Array()
	for point: Vector2 in grid.get("segments"):
		result.append(grid.to_global(point))
	return result

func _check_map_bounds(points: PackedVector2Array) -> void:
	var origin: Vector2 = _world.tile_to_world(Vector2i.ZERO)
	var axis_x: Vector2 = _world.tile_to_world(Vector2i(1, 0)) - origin
	var axis_y: Vector2 = _world.tile_to_world(Vector2i(0, 1)) - origin
	var inverse_projection: Transform2D = Transform2D(axis_x, axis_y, origin).affine_inverse()
	for point: Vector2 in points:
		var cell: Vector2 = inverse_projection * point
		_expect(cell.x >= -0.501 and cell.y >= -0.501 and cell.x <= MapData.MAP_WIDTH - 0.499 and cell.y <= MapData.MAP_HEIGHT - 0.499, "line endpoint stays within the map's outer tile edges")

func _check_footprint_alignment(points: PackedVector2Array) -> void:
	var tile: Vector2i = _world.world_to_tile(_placement.ghost_position)
	var half_w: float = MapData.TILE_WIDTH * 0.5
	var half_h: float = MapData.TILE_HEIGHT * 0.5
	for dx: int in _placement.current_footprint.x:
		for dy: int in _placement.current_footprint.y:
			var center: Vector2 = _world.tile_to_world(tile + Vector2i(dx, dy))
			for offset: Vector2 in [Vector2(0, -half_h), Vector2(half_w, 0), Vector2(0, half_h), Vector2(-half_w, 0)]:
				var corner: Vector2 = center + offset
				var distance: float = INF
				for index: int in range(0, points.size(), 2):
					distance = minf(distance, corner.distance_to(Geometry2D.get_closest_point_to_segment(corner, points[index], points[index + 1])))
				_expect(distance <= 0.01, "every selected footprint corner lies on the surrounding map grid")

func _points_match(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for index: int in a.size():
		if not a[index].is_equal_approx(b[index]):
			return false
	return true

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
