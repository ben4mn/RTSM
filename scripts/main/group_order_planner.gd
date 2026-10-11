extends RefCounted
## Bounded endpoint allocation for a human group order. The intended marker
## stays with Main; these are the actual legal slots its units can occupy.

const MAX_SLOT_RADIUS_TILES: int = 6
const MAX_SLOT_CANDIDATES: int = 128
const MAX_PATH_CHECKS_PER_UNIT: int = 16
const FRIENDLY_CLEARANCE_WORLD: float = 28.0
const SETTLED_SLOT_RADIUS_WORLD: float = 5.0

static func plan(
	game_map: Node2D,
	units: Array[UnitBase],
	target_tile: Vector2i,
	friendly_units: Array = []
) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	var selected_ids: Dictionary = {}
	var pending: Array[UnitBase] = []
	for unit: UnitBase in units:
		if not is_instance_valid(unit) or unit.is_queued_for_deletion() or unit.player_owner != 0 or unit.current_state == UnitBase.State.DEAD:
			continue
		selected_ids[unit.get_instance_id()] = true
		pending.append(unit)
	if pending.is_empty():
		return orders
	# Project the requested center once. Clamping each member independently
	# collapses a corner formation onto the same endpoint.
	var center_tile := Vector2i(
		clampi(target_tile.x, 0, MapData.MAP_WIDTH - 1),
		clampi(target_tile.y, 0, MapData.MAP_HEIGHT - 1)
	)
	var target_world: Vector2 = game_map.tile_to_world(center_tile)
	var candidates: Array[Vector2i] = []
	for dy: int in range(-MAX_SLOT_RADIUS_TILES, MAX_SLOT_RADIUS_TILES + 1):
		for dx: int in range(-MAX_SLOT_RADIUS_TILES, MAX_SLOT_RADIUS_TILES + 1):
			var candidate := center_tile + Vector2i(dx, dy)
			if not game_map.is_tile_walkable(candidate):
				continue
			var destination: Vector2 = game_map.tile_to_world(candidate)
			if _is_occupied_by_other_friendly(destination, friendly_units, selected_ids):
				continue
			candidates.append(candidate)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance: float = game_map.tile_to_world(a).distance_squared_to(target_world)
		var b_distance: float = game_map.tile_to_world(b).distance_squared_to(target_world)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	if candidates.size() > MAX_SLOT_CANDIDATES:
		candidates.resize(MAX_SLOT_CANDIDATES)
	# Nearby members take nearby slots first, regardless of the selection's
	# iteration order.
	pending.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		var a_distance: float = a.global_position.distance_squared_to(target_world)
		var b_distance: float = b.global_position.distance_squared_to(target_world)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		return a.get_instance_id() < b.get_instance_id()
	)
	# Keep arrived members on legal occupied slots in the compact destination
	# area. Equal-distance ring members would otherwise swap destinations on an
	# identical repeat, turning a harmless tap into unnecessary crossing travel.
	var settled_slots: Dictionary = {}
	var reserved_slots: Dictionary = {}
	var component_ids: Dictionary = {}
	var components: Array[Dictionary] = []
	var compact_slot_count: int = mini(pending.size(), candidates.size())
	for unit: UnitBase in pending:
		for index: int in compact_slot_count:
			var candidate: Vector2i = candidates[index]
			if reserved_slots.has(candidate):
				continue
			if unit.global_position.distance_to(game_map.tile_to_world(candidate)) <= SETTLED_SLOT_RADIUS_WORLD:
				settled_slots[unit.get_instance_id()] = candidate
				reserved_slots[candidate] = unit.get_instance_id()
				break
	for unit: UnitBase in pending:
		var available: Array[Vector2i] = []
		var unit_id: int = unit.get_instance_id()
		var settled_candidate: Vector2i = settled_slots.get(unit_id, Vector2i(-1, -1))
		if settled_slots.has(unit_id):
			available.append(settled_candidate)
		for candidate: Vector2i in candidates:
			if reserved_slots.has(candidate) and int(reserved_slots[candidate]) != unit_id:
				continue
			if candidate != settled_candidate:
				available.append(candidate)
		var from_tile: Vector2i = game_map.world_to_tile(unit.global_position)
		if pending.size() > 1 and game_map.is_tile_walkable(from_tile):
			# Reuse connectivity only within this synchronous order. A sealed goal
			# otherwise floods the same region up to16 times for every member.
			# Actual routes still come from canonical A*. Four-neighbor connectivity
			# matches its diagonal policy (both orthogonal neighbors must be open).
			if not component_ids.has(from_tile):
				var connected: Dictionary = _collect_connected_tiles(game_map, from_tile)
				var component_id: int = components.size()
				components.append(connected)
				for tile: Vector2i in connected:
					component_ids[tile] = component_id
			var connected: Dictionary = components[int(component_ids[from_tile])]
			var reachable: Array[Vector2i] = []
			for candidate: Vector2i in available:
				if connected.has(candidate):
					reachable.append(candidate)
			available = reachable
		var tile_path: Array[Vector2i] = game_map.pathfinding.get_tile_path_to_any(
			from_tile, available, MAX_PATH_CHECKS_PER_UNIT
		)
		if tile_path.is_empty():
			# Blind ground commands remain accepted. UnitBase retains responsibility
			# for ordinary navigation recovery/unreachable handling, with no private
			# blocker details exposed through new feedback.
			orders.append({"unit": unit, "destination": target_world, "path": PackedVector2Array()})
			continue
		var destination_tile: Vector2i = tile_path[tile_path.size() - 1]
		var destination: Vector2 = game_map.tile_to_world(destination_tile)
		var world_path := PackedVector2Array()
		for tile: Vector2i in tile_path:
			world_path.append(game_map.tile_to_world(tile))
		orders.append({"unit": unit, "destination": destination, "path": world_path})
		candidates.erase(destination_tile)
	return orders

static func _collect_connected_tiles(game_map: Node2D, origin: Vector2i) -> Dictionary:
	var connected: Dictionary = {origin: true}
	var frontier: Array[Vector2i] = [origin]
	var next: int = 0
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	while next < frontier.size() and next < MapData.MAP_WIDTH * MapData.MAP_HEIGHT:
		var tile: Vector2i = frontier[next]
		next += 1
		for direction: Vector2i in directions:
			var neighbor: Vector2i = tile + direction
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= MapData.MAP_WIDTH or neighbor.y >= MapData.MAP_HEIGHT:
				continue
			if connected.has(neighbor) or not game_map.is_tile_walkable(neighbor):
				continue
			connected[neighbor] = true
			frontier.append(neighbor)
	return connected

static func _is_occupied_by_other_friendly(destination: Vector2, friendly_units: Array, selected_ids: Dictionary) -> bool:
	for entry: Variant in friendly_units:
		if not is_instance_valid(entry) or not entry is UnitBase:
			continue
		var unit := entry as UnitBase
		if unit.player_owner != 0 or unit.is_queued_for_deletion() or selected_ids.has(unit.get_instance_id()) or unit.current_state == UnitBase.State.DEAD:
			continue
		if unit.global_position.distance_to(destination) < FRIENDLY_CLEARANCE_WORLD:
			return true
		if unit.current_state == UnitBase.State.MOVING and unit.move_target.distance_to(destination) < FRIENDLY_CLEARANCE_WORLD:
			return true
	return false
