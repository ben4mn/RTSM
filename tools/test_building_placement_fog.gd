extends Node
## Regression for fog-safe build preview and confirm-time transaction checks.

const TEST_ORIGIN := Vector2i(10, 10)
const HOUSE_FOOTPRINT := Vector2i(2, 2)
const HOUSE_WOOD_COST := 50

var _failures: Array[String] = []
var _confirmation_requests: int = 0
var _transaction_rejections: int = 0
var _resource_wood: int = 200
var _spawn_count: int = 0
var _hide_during_confirmation: bool = false
var _race_tile: Vector2i = Vector2i.ZERO
var _last_transaction_invalid_reason: String = ""


class FakeGameMap extends Node2D:
	var visible_tiles: Dictionary = {}
	var blocked_tiles: Dictionary = {}
	var non_buildable_tiles: Dictionary = {}
	var walkability_queries: Array[Vector2i] = []

	func is_tile_visible_to_player(tile_pos: Vector2i, _viewer_player_id: int = 0) -> bool:
		return bool(visible_tiles.get(tile_pos, false))

	func is_tile_walkable(tile_pos: Vector2i) -> bool:
		walkability_queries.append(tile_pos)
		return not blocked_tiles.has(tile_pos)

	func is_tile_buildable(tile_pos: Vector2i) -> bool:
		return is_tile_walkable(tile_pos) and not non_buildable_tiles.has(tile_pos)

	func set_tile_visible(tile_pos: Vector2i, is_visible: bool) -> void:
		if is_visible:
			visible_tiles[tile_pos] = true
		else:
			visible_tiles.erase(tile_pos)


class FallbackMap extends Node2D:
	var hidden_tile := Vector2i(-1, -1)
	var walkability_queries: Array[Vector2i] = []

	func is_tile_visible_to_player(tile_pos: Vector2i, _owner: int = 0) -> bool:
		return tile_pos != hidden_tile

	func is_tile_walkable(tile_pos: Vector2i) -> bool:
		walkability_queries.append(tile_pos)
		return true


class PlacementProbe extends BuildingPlacement:
	var occupancy_queries: Array[Vector2i] = []
	var occupied_tiles: Dictionary = {}

	func _has_building_at_tile(tile_pos: Vector2i) -> bool:
		occupancy_queries.append(tile_pos)
		return occupied_tiles.has(tile_pos)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var world := FakeGameMap.new()
	world.name = "FakeGameMap"
	add_child(world)
	var placement := BuildingPlacement.new()
	placement.name = "BuildingPlacement"
	world.add_child(placement)
	placement.placement_confirmed.connect(_on_confirmation_requested.bind(placement, world))
	await get_tree().process_frame

	var world_pos := _tile_to_world(TEST_ORIGIN)
	placement.start_placement(BuildingData.BuildingType.HOUSE, 0)
	placement.ghost_position = world_pos

	# An unseen footprint explains the visibility requirement, and
	# the hidden tile must never be queried for terrain/occupancy information.
	world.blocked_tiles[TEST_ORIGIN + Vector2i(1, 1)] = true
	var preview_valid: bool = bool(placement.call("_check_validity"))
	_expect(not preview_valid, "unseen footprint was accepted by the preview")
	_expect_eq(placement.get_invalid_reason(), BuildingPlacement.FOG_INVALID_REASON, "unseen preview leaked a specific invalid reason")
	_expect(world.walkability_queries.is_empty(), "unseen preview queried hidden walkability")

	_check_range_fog_feedback()

	# Once visible, ordinary legal terrain is accepted. A visible blocker may use
	# detailed feedback because it is no longer hidden information.
	_set_footprint_visibility(world, TEST_ORIGIN, true)
	preview_valid = bool(placement.call("_check_validity"))
	_expect(not preview_valid, "visible blocked footprint was accepted")
	_expect_eq(placement.get_invalid_reason(), "Blocked terrain", "visible blocker did not report terrain feedback")
	world.blocked_tiles.clear()
	world.walkability_queries.clear()
	preview_valid = bool(placement.call("_check_validity"))
	_expect(preview_valid, "fully visible legal footprint was rejected")
	_expect_eq(world.walkability_queries.size(), 4, "visible footprint did not validate every tile")

	# Movement-walkable resource/non-grass terrain is still not valid foundation
	# terrain once visible, and may provide specific feedback at that point.
	world.non_buildable_tiles[TEST_ORIGIN + Vector2i(0, 1)] = true
	world.walkability_queries.clear()
	preview_valid = bool(placement.call("_check_validity"))
	_expect(not preview_valid, "visible non-grass/resource terrain accepted a foundation")
	_expect_eq(placement.get_invalid_reason(), "Blocked terrain", "visible non-buildable terrain did not report terrain feedback")
	world.non_buildable_tiles.clear()

	# A stale green preview must be rejected if fog changes before the input is
	# processed; no confirmation request may escape the placement component.
	world.set_tile_visible(TEST_ORIGIN + Vector2i(1, 0), false)
	world.non_buildable_tiles[TEST_ORIGIN + Vector2i(1, 0)] = true
	placement.is_valid_placement = true
	world.walkability_queries.clear()
	placement.call("_confirm_placement")
	_expect_eq(_confirmation_requests, 0, "stale green preview emitted a confirmation request")
	_expect(placement.active, "stale preview rejection closed placement instead of allowing retry")
	_expect_eq(_resource_wood, 200, "stale preview rejection spent resources")
	_expect_eq(_spawn_count, 0, "stale preview rejection spawned a building")
	_expect_eq(placement.get_invalid_reason(), BuildingPlacement.FOG_INVALID_REASON, "stale preview rejection leaked hidden state")
	_expect(world.walkability_queries.is_empty(), "stale preview rejection queried hidden walkability")
	world.non_buildable_tiles.clear()

	# Simulate fog changing synchronously after the placement-level check but
	# before the gameplay coordinator spends. Its final revalidation must reject
	# the transaction without a spend or spawn.
	_set_footprint_visibility(world, TEST_ORIGIN, true)
	placement.is_valid_placement = bool(placement.call("_check_validity"))
	_hide_during_confirmation = true
	_race_tile = TEST_ORIGIN + Vector2i(0, 1)
	placement.call("_confirm_placement")
	_expect_eq(_confirmation_requests, 1, "confirm-time race did not reach the transaction guard")
	_expect_eq(_transaction_rejections, 1, "confirm-time fog race was not rejected")
	_expect_eq(_resource_wood, 200, "confirm-time fog race spent resources")
	_expect_eq(_spawn_count, 0, "confirm-time fog race spawned a building")
	_expect_eq(_last_transaction_invalid_reason, BuildingPlacement.FOG_INVALID_REASON, "transaction guard leaked hidden state")

	# The same two-stage path must still allow a fully visible legal footprint.
	_set_footprint_visibility(world, TEST_ORIGIN, true)
	placement.start_placement(BuildingData.BuildingType.HOUSE, 0)
	placement.ghost_position = world_pos
	placement.is_valid_placement = bool(placement.call("_check_validity"))
	_hide_during_confirmation = false
	placement.call("_confirm_placement")
	_expect_eq(_confirmation_requests, 2, "visible legal confirmation was not requested")
	_expect_eq(_transaction_rejections, 1, "visible legal confirmation was rejected")
	_expect_eq(_resource_wood, 150, "visible legal confirmation did not spend exactly once")
	_expect_eq(_spawn_count, 1, "visible legal confirmation did not spawn exactly once")

	placement.free()
	world.free()
	if _failures.is_empty():
		print("[PASS] building_placement_fog: full-footprint sight feedback, no hidden queries/uniform cells, generic missing API; preview and transaction races are blocked")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] building_placement_fog: %s" % failure)
	get_tree().quit(1)


func _check_range_fog_feedback() -> void:
	var world := FakeGameMap.new()
	add_child(world)
	var placement := PlacementProbe.new()
	world.add_child(placement)
	var footprint := Vector2i(3, 3)
	var expected_cells: Array[Vector2i] = []
	for dx: int in footprint.x:
		for dy: int in footprint.y:
			var tile := TEST_ORIGIN + Vector2i(dx, dy)
			expected_cells.append(tile)
			world.set_tile_visible(tile, true)
	var hidden := TEST_ORIGIN + Vector2i(2, 2)
	world.set_tile_visible(hidden, false)
	placement.start_placement(BuildingData.BuildingType.ARCHERY_RANGE, 0)
	placement.ghost_position = _tile_to_world(TEST_ORIGIN)
	# Known visibility may be explained; the hidden terrain, resources and
	# occupancy must not change either text or the all-invalid footprint.
	for hidden_state: int in 4:
		world.blocked_tiles.clear()
		world.non_buildable_tiles.clear()
		placement.occupied_tiles.clear()
		if hidden_state == 1:
			world.blocked_tiles[hidden] = true
		elif hidden_state == 2:
			world.non_buildable_tiles[hidden] = true
		elif hidden_state == 3:
			placement.occupied_tiles[hidden] = true
		world.walkability_queries.clear()
		placement.occupancy_queries.clear()
		_expect(not bool(placement.call("_check_validity")), "partially unseen Range accepted state%d" % hidden_state)
		_expect_eq(placement.get_invalid_reason(), "Move all tiles into sight", "Range lacks actionable full-visibility feedback")
		_expect_eq(placement.get("_invalid_tiles"), expected_cells, "hidden state changed uniform invalid Range cells")
		_expect(world.walkability_queries.is_empty(), "partial Range queried terrain under fog")
		_expect(placement.occupancy_queries.is_empty(), "partial Range queried occupancy under fog")
	world.blocked_tiles.clear()
	world.non_buildable_tiles.clear()
	placement.occupied_tiles.clear()
	world.set_tile_visible(hidden, true)
	world.walkability_queries.clear()
	placement.occupancy_queries.clear()
	_expect(bool(placement.call("_check_validity")), "revealed clear Range did not become legal")
	_expect_eq(world.walkability_queries.size(), 9, "revealed Range did not validate all terrain cells")
	_expect(placement.occupancy_queries.is_empty(), "canonical buildability unexpectedly used occupancy fallback")
	placement.free()
	world.free()
	# A map without the canonical buildable API uses the actual occupancy
	# fallback. Prove that visibility blocks those reads too, then reveal the
	# same actor so the witness cannot pass because that branch was unreachable.
	var fallback_world := FallbackMap.new()
	add_child(fallback_world)
	var fallback := PlacementProbe.new()
	fallback_world.add_child(fallback)
	fallback_world.hidden_tile = hidden
	fallback.start_placement(BuildingData.BuildingType.ARCHERY_RANGE, 0)
	fallback.ghost_position = _tile_to_world(TEST_ORIGIN)
	fallback.occupied_tiles[hidden] = true
	fallback_world.walkability_queries.clear()
	fallback.occupancy_queries.clear()
	_expect(not bool(fallback.call("_check_validity")), "hidden fallback occupancy accepted Range")
	_expect_eq(fallback.get_invalid_reason(), "Move all tiles into sight", "fallback exposed hidden occupancy reason")
	_expect_eq(fallback.get("_invalid_tiles"), expected_cells, "fallback exposed hidden occupancy cell")
	_expect(fallback_world.walkability_queries.is_empty() and fallback.occupancy_queries.is_empty(), "fallback queried hidden terrain/occupancy")
	fallback_world.hidden_tile = Vector2i(-1, -1)
	_expect(not bool(fallback.call("_check_validity")), "revealed occupied fallback Range accepted")
	_expect_eq(fallback.get_invalid_reason(), "Overlaps building", "revealed fallback did not reach real occupancy branch")
	_expect_eq(fallback.occupancy_queries.size(), 9, "revealed fallback did not query whole Range")
	fallback.free()
	fallback_world.free()
	# Missing visibility support is not evidence that a player can fix fog.
	var unavailable := Node2D.new()
	add_child(unavailable)
	var unknown := PlacementProbe.new()
	unavailable.add_child(unknown)
	unknown.start_placement(BuildingData.BuildingType.ARCHERY_RANGE, 0)
	unknown.ghost_position = _tile_to_world(TEST_ORIGIN)
	_expect(not bool(unknown.call("_check_validity")), "missing visibility API accepted Range")
	_expect_eq(unknown.get_invalid_reason(), BuildingPlacement.GENERIC_INVALID_REASON, "missing API misreported known fog")
	_expect(unknown.occupancy_queries.is_empty(), "missing visibility API queried occupancy")
	unknown.free()
	unavailable.free()


func _on_confirmation_requested(
	building_type: int,
	world_pos: Vector2,
	placement: BuildingPlacement,
	world: FakeGameMap
) -> void:
	_confirmation_requests += 1
	if _hide_during_confirmation:
		world.set_tile_visible(_race_tile, false)
	if not placement.revalidate_confirmation(building_type, world_pos, 0):
		_transaction_rejections += 1
		_last_transaction_invalid_reason = placement.get_invalid_reason()
		return
	_resource_wood -= HOUSE_WOOD_COST
	_spawn_count += 1


func _set_footprint_visibility(world: FakeGameMap, origin: Vector2i, is_visible: bool) -> void:
	for dx in HOUSE_FOOTPRINT.x:
		for dy in HOUSE_FOOTPRINT.y:
			world.set_tile_visible(origin + Vector2i(dx, dy), is_visible)


func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	var half_w := float(MapData.TILE_WIDTH) * 0.5
	var half_h := float(MapData.TILE_HEIGHT) * 0.5
	return Vector2((tile_pos.x - tile_pos.y) * half_w, (tile_pos.x + tile_pos.y) * half_h)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])
