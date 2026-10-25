extends Node
## Actual TileMap projection and real building/ghost art. No economy mutation.

var _checks: int = 0
var _failures: Array[String] = []
var _world: ProjectionWorld
var _placement: BuildingPlacement

class ProjectionWorld extends Node2D:
	var terrain := TileMapLayer.new()
	var sight_hidden := false
	var blocked: Dictionary = {}
	var terrain_queries: int = 0
	func _ready() -> void:
		terrain.name = "TerrainLayer"
		terrain.tile_set = TilesetBuilder.build_terrain_tileset()
		add_child(terrain)
	func tile_to_world(tile: Vector2i) -> Vector2:
		return terrain.map_to_local(tile)
	func world_to_tile(point: Vector2) -> Vector2i:
		return terrain.local_to_map(point)
	func is_tile_visible_to_player(_tile: Vector2i, _owner: int = 0) -> bool:
		return not sight_hidden
	func is_tile_buildable(tile: Vector2i) -> bool:
		terrain_queries += 1
		return not blocked.has(tile)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous_civilization: int = GameManager.selected_civilization
	GameManager.set_state(GameManager.GameState.MENU)
	AudioManager.set_all_enabled(false)
	_world = ProjectionWorld.new()
	add_child(_world)
	_placement = BuildingPlacement.new()
	_world.add_child(_placement)
	await get_tree().process_frame
	_expect(_placement.z_index == 8 and not _placement.z_as_relative, "preview stays above world objects and below fog layer10")
	for civilization: int in CivilizationData.ORDERED_IDS:
		GameManager.selected_civilization = civilization
		for type: int in KingdomArt.BUILDING_NAMES:
			_placement.start_placement(type)
			_placement.update_preview_at_world(_world.tile_to_world(Vector2i(30, 30)))
			var size: Vector2i = BuildingData.get_building_stats(type).footprint
			_check_polygon(Vector2i(30, 30), size)
			var finished := BuildingBase.new()
			finished.building_type = type
			finished.player_owner = 0
			finished.position = _world.tile_to_world(Vector2i(30, 30))
			_world.add_child(finished)
			var ghost: Sprite2D = _placement.get("_ghost_sprite")
			var built: Sprite2D = finished.get_node("BuildingSprite")
			_expect(ghost.texture.resource_path == built.texture.resource_path, "civilization%d type%d uses the final building illustration" % [civilization, type])
			_expect(ghost.global_transform.is_equal_approx(built.global_transform) and ghost.offset.is_equal_approx(built.offset), "civilization%d type%d preview matches completed ground anchor, scale and offset" % [civilization, type])
			finished.free()
			_placement.cancel_placement()
	# A rectangular fixture catches the old single width/height diamond formula,
	# even though all current authored building footprints happen to be square.
	_check_polygon(Vector2i(20, 20), Vector2i(2, 3))
	_check_polygon(Vector2i(20, 20), Vector2i(4, 1))
	_check_clearance_categories()
	_world.free()
	GameManager.selected_civilization = previous_civilization
	for failure: String in _failures:
		push_error("[FAIL] placement_preview_geometry: " + failure)
	if _failures.is_empty():
		print("[PASS] placement_preview_geometry: %d checks; actual TileMap cell hulls, all30 civilization/building art anchors, clearance versus occupied marks, fog-safe categories and overlay layer" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_polygon(origin: Vector2i, size: Vector2i) -> void:
	var polygon: PackedVector2Array = _placement.call("_footprint_world_polygon", origin, size)
	var corners := PackedVector2Array()
	for x: int in size.x:
		for y: int in size.y:
			var center: Vector2 = _world.terrain.map_to_local(origin + Vector2i(x, y))
			for offset: Vector2 in [Vector2(-32, 0), Vector2(0, -16), Vector2(32, 0), Vector2(0, 16)]:
				corners.append(center + offset)
	var hull: PackedVector2Array = Geometry2D.convex_hull(corners)
	_expect(polygon.size() == 4 and hull.size() == 5, "actual reserved-cell hull has four outer corners")
	for point: Vector2 in polygon:
		_expect(point in hull, "preview outer boundary exactly matches the union of actual terrain cells")
	var area: float = 0.0
	for i: int in polygon.size():
		area += polygon[i].cross(polygon[(i + 1) % polygon.size()]) * 0.5
	_expect(is_equal_approx(absf(area), size.x * size.y * 1024.0), "preview reserves exactly the declared number of64×32diamond cells")
	for point: Vector2 in corners:
		var contained: bool = Geometry2D.is_point_in_polygon(point, polygon)
		for i: int in polygon.size():
			contained = contained or Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()]).distance_to(point) < 0.01
		_expect(contained, "no actual footprint corner lies outside the shown boundary")


func _check_clearance_categories() -> void:
	var anchor := Vector2i(20, 20)
	var existing := BuildingBase.new()
	existing.building_type = BuildingData.BuildingType.HOUSE
	existing.player_owner = 0
	existing.position = _world.tile_to_world(anchor)
	_world.add_child(existing)
	for x: int in 2:
		for y: int in 2:
			_world.blocked[anchor + Vector2i(x, y)] = true
	_placement.start_placement(BuildingData.BuildingType.HOUSE)
	_placement.update_preview_at_world(_world.tile_to_world(anchor + Vector2i(2, 0)))
	_expect(not _placement.is_valid_placement and (_placement.get("_invalid_tiles") as Array).size() == 2, "unchanged path rule rejects exactly the adjacent two candidate cells")
	_expect((_placement.get("_clearance_tiles") as Array).size() == 2 and _placement.get_preview_state_label() == "Keep a path gap", "reserved path cells use dashed/double-bar category with an explicit label")
	_expect((_placement.get("_clearance_areas") as Array) == [Rect2i(anchor - Vector2i.ONE, Vector2i(4, 4))], "dashed context is the existing House's actual one-tile protection ring")
	_placement.update_preview_at_world(_world.tile_to_world(anchor))
	_expect(not _placement.is_valid_placement and (_placement.get("_clearance_tiles") as Array).is_empty() and _placement.get_preview_state_label() == "Blocked", "occupied terrain remains X-marked, never mislabeled as spare path ground")
	_placement.update_preview_at_world(_world.tile_to_world(anchor + Vector2i(3, 0)))
	_expect(_placement.is_valid_placement and _placement.get_preview_state_label() == "Fits", "one complete path tile remains legal; clear placement has a text/check cue")
	_world.sight_hidden = true
	_world.terrain_queries = 0
	_placement.update_preview_at_world(_world.tile_to_world(anchor + Vector2i(2, 0)))
	_expect(_world.terrain_queries == 0 and (_placement.get("_clearance_tiles") as Array).is_empty() and (_placement.get("_clearance_areas") as Array).is_empty(), "lost vision clears detailed categories before any terrain/occupancy query")
	_expect(_placement.get_preview_state_label() == "Needs sight", "fog state has its own plain-language cue")
	_placement.cancel_placement()
	existing.free()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
