extends Node
## Automatic growth preserves the shared owned-building movement lane.

var failures: Array[String] = []

class BuildMap extends Node2D:
	var permitted: Dictionary = {}
	var visible_tiles: bool = true
	var buildable_queries: int = 0

	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2((tile.x - tile.y) * 32.0, (tile.x + tile.y) * 16.0)

	func world_to_tile(point: Vector2) -> Vector2i:
		return Vector2i(roundi((point.x / 32.0 + point.y / 16.0) * 0.5), roundi((point.y / 16.0 - point.x / 32.0) * 0.5))

	func is_tile_visible_to_player(_tile: Vector2i, _owner: int = 0) -> bool:
		return visible_tiles

	func is_tile_buildable(tile: Vector2i) -> bool:
		buildable_queries += 1
		return permitted.has(tile)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var map := BuildMap.new()
	var ai := AIController.new()
	ai.player_id = 1
	ai.game_map = map
	ai._base_tile = Vector2i(6, 6)
	var tc := BuildingBase.new()
	tc.player_owner = 1
	tc.footprint = Vector2i(4, 4)
	tc.state = BuildingBase.State.ACTIVE
	tc.position = map.tile_to_world(Vector2i(6, 6))
	ai._my_buildings.append(tc)
	var near := Vector2i(4, 6)
	var farther := Vector2i(3, 3)
	_allow(map, near, Vector2i(2, 2))
	_expect(not ai._is_valid_build_spot(near, Vector2i(2, 2)), "automatic adjacency is rejected even on buildable visible terrain")
	var started: int = Time.get_ticks_usec()
	_expect(ai._find_build_location(BuildingData.BuildingType.HOUSE) == Vector2i(-1, -1), "cramped base returns bounded no-site instead of filling its only lane")
	_expect(Time.get_ticks_usec() - started < 1000000, "cramped-base scan remains bounded")
	_allow(map, farther, Vector2i(2, 2))
	var candidate: Vector2i = ai._find_build_location(BuildingData.BuildingType.HOUSE)
	_expect(candidate == farther, "allocator finds a spaced alternate within its existing search")
	ai._build_site_search_cursors[BuildingData.BuildingType.HOUSE] = 999
	_expect(ai._find_build_location(BuildingData.BuildingType.HOUSE) == farther, "exhausted cursor restarts without relaxing clearance")
	map.permitted.clear()
	tc.position = map.tile_to_world(Vector2i.ZERO)
	tc.footprint = Vector2i(2, 2)
	_allow(map, Vector2i(2, 0), Vector2i(2, 2))
	_allow(map, Vector2i(3, 0), Vector2i(2, 2))
	_expect(not ai._is_valid_build_spot(Vector2i(2, 0), Vector2i(2, 2)), "edge building adjacency is rejected")
	_expect(ai._is_valid_build_spot(Vector2i(3, 0), Vector2i(2, 2)), "one complete tile gap at the map edge is allowed")
	_expect(not ai._is_valid_build_spot(Vector2i(-1, 0), Vector2i(2, 2)), "clearance does not weaken map bounds")
	map.buildable_queries = 0
	map.visible_tiles = false
	_expect(not ai._is_valid_build_spot(Vector2i(3, 0), Vector2i(2, 2)) and map.buildable_queries == 0, "hidden footprint is rejected before terrain or clearance inspection")
	map.visible_tiles = true
	tc.state = BuildingBase.State.DESTROYED
	_expect(ai._is_valid_build_spot(Vector2i(2, 0), Vector2i(2, 2)), "destroyed structures no longer reserve clearance")
	tc.state = BuildingBase.State.ACTIVE
	tc.player_owner = 0
	_expect(ai._is_valid_build_spot(Vector2i(2, 0), Vector2i(2, 2)), "clearance consults only the acting owner's structures")
	tc.free()
	ai.free()
	map.free()
	for failure: String in failures:
		push_error("[FAIL] ai_building_clearance: " + failure)
	if failures.is_empty():
		print("[PASS] ai_building_clearance: one-tile spacing, map edge, alternate search, bounded cramped failure, cursor reset and ownership/vision")
	get_tree().quit(0 if failures.is_empty() else 1)

func _allow(map: BuildMap, origin: Vector2i, size: Vector2i) -> void:
	for y: int in size.y:
		for x: int in size.x:
			map.permitted[origin + Vector2i(x, y)] = true

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
