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

	# An unseen footprint containing a hidden blocker must fail generically, and
	# the hidden tile must never be queried for terrain/occupancy information.
	world.blocked_tiles[TEST_ORIGIN + Vector2i(1, 1)] = true
	var preview_valid: bool = bool(placement.call("_check_validity"))
	_expect(not preview_valid, "unseen footprint was accepted by the preview")
	_expect_eq(placement.get_invalid_reason(), BuildingPlacement.GENERIC_INVALID_REASON, "unseen preview leaked a specific invalid reason")
	_expect(world.walkability_queries.is_empty(), "unseen preview queried hidden walkability")

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
	_expect_eq(placement.get_invalid_reason(), BuildingPlacement.GENERIC_INVALID_REASON, "stale preview rejection leaked hidden state")
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
	_expect_eq(_last_transaction_invalid_reason, BuildingPlacement.GENERIC_INVALID_REASON, "transaction guard leaked hidden state")

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
		print("[PASS] building_placement_fog: unseen footprints are generic; preview and transaction races are blocked")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] building_placement_fog: %s" % failure)
	get_tree().quit(1)


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
