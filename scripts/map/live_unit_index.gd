extends RefCounted
## Broad-phase only. Callers retain exact distance, ownership, death and fog rules.
## Local transform notifications update immediately, including paused teleports.
## Broad-phase only, so the size changes cost, never results: 64 px keeps a
## separation query to ~9 cells and an acquisition query to ~100.
const CELL_SIZE: float = 64.0
var _map: Node2D
var _entries: Dictionary = {}
var _cells: Dictionary = {}
var _parents: Dictionary = {}
## How many living units of an owner see each map tile: one int per tile,
## row-major, one map-sized block per owner slot. Kept exact by update(),
## remove() and invalidate_vision(unit), so a visibility probe is one array
## read instead of a scan of nearby units.
var _vision_counts := PackedInt32Array()
var _vision_slots: Dictionary = {}
var vision_revision: int = 0
var _movement_by_owner: Dictionary = {}
var order_revision: int = 0
var _order_dirty: bool = true
var _ordered_units: Array[UnitBase] = []

func _init(map: Node2D) -> void:
	_map = map

func update(unit: UnitBase) -> void:
	if not is_instance_valid(unit) or not unit.is_inside_tree(): return
	var cell := Vector2i((unit.global_position / CELL_SIZE).floor())
	var tile: Vector2i = _map.world_to_tile(unit.global_position)
	# Almost every call is a step inside the same tile and cell with the same
	# sight: only the recorded position moves. (`_index_listed` is cleared by
	# remove(), `_index_vision` is the sight radius the stamp was made with.)
	if unit._index_listed and tile == unit._index_tile and cell == unit._index_cell and unit.vision_radius == unit._index_vision:
		unit._index_position = unit.global_position
		return
	var id: int = unit.get_instance_id()
	var radius: int = maxi(0, int(round(MapData.world_to_range_tiles(unit.vision_radius))))
	unit._index_listed = true
	unit._index_tile = tile
	unit._index_cell = cell
	unit._index_vision = unit.vision_radius
	if not _entries.has(id):
		invalidate_order()
		unit._index_position = unit.global_position
		_entries[id] = {"unit": unit, "position": unit.global_position, "cell": cell, "tile": tile, "radius": radius, "parent": unit.get_parent(), "stamped": false, "stamp_owner": 0, "presence_owner": unit.player_owner}
		vision_revision += 1
		_insert(_cells, cell, unit)
		_count_presence(unit.player_owner, cell, 1)
		_restamp(_entries[id], unit)
	else:
		var entry: Dictionary = _entries[id]
		entry.position = unit.global_position
		unit._index_position = unit.global_position
		if entry.tile != tile or entry.radius != radius:
			vision_revision += 1
			_movement_by_owner[unit.player_owner] = int(_movement_by_owner.get(unit.player_owner, 0)) + 1
			_unstamp(entry)
			entry.tile = tile
			entry.radius = radius
			_restamp(entry, unit)
		if entry.cell != cell:
			_remove(_cells, entry.cell, unit)
			_insert(_cells, cell, unit)
			_count_presence(entry.presence_owner, entry.cell, -1)
			_count_presence(entry.presence_owner, cell, 1)
			entry.cell = cell
		entry.parent = unit.get_parent()
	var parent: Node2D = unit.get_parent() as Node2D
	if parent != null and not _parents.has(parent.get_instance_id()):
		_parents[parent.get_instance_id()] = {"node": parent, "transform": parent.global_transform}

func remove(unit: UnitBase) -> void:
	var id: int = unit.get_instance_id()
	unit._index_listed = false
	if not _entries.has(id): return
	var entry: Dictionary = _entries[id]
	_remove(_cells, entry.cell, unit)
	_count_presence(entry.presence_owner, entry.cell, -1)
	_unstamp(entry)
	_entries.erase(id)
	invalidate_order()
	vision_revision += 1

## A unit's owner or living/dead status changed (called after the new value is
## stored): move its contribution to the right owner's count grid.
func invalidate_vision(unit: UnitBase = null) -> void:
	vision_revision += 1
	if unit != null and _entries.has(unit.get_instance_id()):
		var entry: Dictionary = _entries[unit.get_instance_id()]
		_restamp(entry, unit)
		if entry.presence_owner != unit.player_owner:
			_count_presence(entry.presence_owner, entry.cell, -1)
			entry.presence_owner = unit.player_owner
			_count_presence(entry.presence_owner, entry.cell, 1)

## How many indexed units (living or dying) each owner has in each block of
## 8x8 cells. near() can only return another owner's unit from a block that
## holds one, so an empty neighbourhood is answered without walking cells.
var _presence: Dictionary = {}

func _count_presence(owner: int, cell: Vector2i, change: int) -> void:
	if not _presence.has(owner): _presence[owner] = {}
	var blocks: Dictionary = _presence[owner]
	var block := Vector2i(cell.x >> 3, cell.y >> 3)
	var count: int = int(blocks.get(block, 0)) + change
	if count > 0: blocks[block] = count
	else: blocks.erase(block)

## False only when near(position, radius) holds no unit of another owner.
func other_owner_near(position: Vector2, radius: float, owner: int) -> bool:
	_refresh_parent_transforms()
	var first := Vector2i(((position - Vector2.ONE * radius) / CELL_SIZE).floor())
	var last := Vector2i(((position + Vector2.ONE * radius) / CELL_SIZE).floor())
	for other: int in _presence:
		if other == owner: continue
		var blocks: Dictionary = _presence[other]
		if blocks.is_empty(): continue
		for y: int in range(first.y >> 3, (last.y >> 3) + 1):
			for x: int in range(first.x >> 3, (last.x >> 3) + 1):
				if blocks.has(Vector2i(x, y)): return true
	return false

func enemy_position_revision(viewer: int) -> int:
	# A local FogManager owns source visibility. Moving its own workers does
	# not change which enemy positions land in that already-published grid.
	return vision_revision - int(_movement_by_owner.get(viewer, 0))

## Moves whenever `owner`'s own sight sources may have changed: every revision
## step except another owner's unit crossing a tile.
func own_vision_revision(owner: int) -> int:
	var foreign_moves: int = 0
	for other: int in _movement_by_owner:
		if other != owner: foreign_moves += int(_movement_by_owner[other])
	return vision_revision - foreign_moves

func units_reveal(tile: Vector2i, owner: int) -> bool:
	_refresh_parent_transforms()
	if tile.x >= 0 and tile.y >= 0 and tile.x < MapData.MAP_WIDTH and tile.y < MapData.MAP_HEIGHT:
		var slot: int = _vision_slots.get(owner, -1)
		return slot >= 0 and _vision_counts[slot + tile.y * MapData.MAP_WIDTH + tile.x] > 0
	# Off-map probes (transient poses) are rare; keep the exact per-unit rule.
	for entry: Dictionary in _entries.values():
		var unit: UnitBase = entry.unit
		if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.player_owner != owner or unit.current_state == UnitBase.State.DEAD: continue
		var offset: Vector2i = tile - entry.tile
		if offset.x * offset.x + offset.y * offset.y <= entry.radius * entry.radius:
			return true
	return false

func _restamp(entry: Dictionary, unit: UnitBase) -> void:
	_unstamp(entry)
	if unit.current_state == UnitBase.State.DEAD: return
	entry.stamped = true
	entry.stamp_owner = unit.player_owner
	_stamp(entry.stamp_owner, entry.tile, entry.radius, 1)

func _unstamp(entry: Dictionary) -> void:
	if not entry.stamped: return
	entry.stamped = false
	_stamp(entry.stamp_owner, entry.tile, entry.radius, -1)

## Same tile circle as the per-unit rule: dx*dx + dy*dy <= radius*radius.
func _stamp(owner: int, tile: Vector2i, radius: int, amount: int) -> void:
	var width: int = MapData.MAP_WIDTH
	if not _vision_slots.has(owner):
		_vision_slots[owner] = _vision_counts.size()
		_vision_counts.resize(_vision_counts.size() + width * MapData.MAP_HEIGHT)
	var base: int = _vision_slots[owner]
	var radius_squared: int = radius * radius
	for y: int in range(maxi(0, tile.y - radius), mini(MapData.MAP_HEIGHT - 1, tile.y + radius) + 1):
		var dy: int = y - tile.y
		var half: int = int(sqrt(float(radius_squared - dy * dy)))
		var row: int = base + y * width
		for x: int in range(maxi(0, tile.x - half), mini(width - 1, tile.x + half) + 1):
			_vision_counts[row + x] += amount

func near(position: Vector2, radius: float) -> Array[UnitBase]:
	_refresh_parent_transforms()
	_refresh_order()
	var ranks := PackedInt32Array()
	var result: Array[UnitBase] = []
	var first := Vector2i(((position - Vector2.ONE * radius) / CELL_SIZE).floor())
	var last := Vector2i(((position + Vector2.ONE * radius) / CELL_SIZE).floor())
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var cell: Variant = _cells.get(Vector2i(x, y))
			if cell == null: continue
			for unit: UnitBase in cell:
				# Membership is removed synchronously on tree exit; positions are
				# refreshed by local notifications and the parent check above.
				# The unit carries its own index record (position as of its last
				# transform notification, tree rank) to avoid a lookup per candidate.
				if unit.current_state != UnitBase.State.DEAD and unit._index_position.distance_to(position) <= radius:
					ranks.append(unit._index_rank)
	# Native integer sorting preserves exact SceneTree order without a script
	# callback for every comparison in every unit neighborhood query.
	ranks.sort()
	for rank: int in ranks: result.append(_ordered_units[rank])
	return result

## Enemy units `viewer` currently sees, in tree order, appended to `into`.
## Per unit this is GameMap.is_entity_visible_to_player: the local FogManager
## grid when `fog` is given, otherwise living-unit sight counts or the building
## vision grid; off-map poses go through the map's exact query.
func collect_visible_enemies(viewer: int, fog: FogManager, building_grid: PackedByteArray, into: Array[UnitBase]) -> void:
	_refresh_order()
	var slot: int = _vision_slots.get(viewer, -1)
	var width: int = MapData.MAP_WIDTH
	for unit: UnitBase in _ordered_units:
		if unit.player_owner == viewer or unit.current_state == UnitBase.State.DEAD: continue
		var tile: Vector2i = _entries[unit.get_instance_id()].tile
		var seen: bool = false
		if fog != null:
			seen = fog.is_tile_visible(tile)
		elif tile.x >= 0 and tile.y >= 0 and tile.x < width and tile.y < MapData.MAP_HEIGHT:
			var index: int = tile.y * width + tile.x
			seen = (slot >= 0 and _vision_counts[slot + index] > 0) or building_grid[index] != 0
		else:
			seen = _map.is_entity_visible_to_player(unit, viewer)
		if seen: into.append(unit)

func size() -> int:
	return _entries.size()

## Living and dying units of this map in SceneTree order. Borrowed: do not mutate.
func ordered_units() -> Array[UnitBase]:
	_refresh_order()
	return _ordered_units

func invalidate_order() -> void:
	order_revision += 1
	_order_dirty = true

func _refresh_order() -> void:
	if not _order_dirty: return
	_order_dirty = false
	_ordered_units.clear()
	for node: Node in _map.get_tree().get_nodes_in_group("units"):
		if node is UnitBase and _entries.has(node.get_instance_id()):
			_entries[node.get_instance_id()].rank = _ordered_units.size()
			(node as UnitBase)._index_rank = _ordered_units.size()
			_ordered_units.append(node)

func _refresh_parent_transforms() -> void:
	# Called on every visibility probe: no key-array copy in the usual case
	# (one live container that has not moved).
	var settled: bool = true
	for id: int in _parents:
		var record: Dictionary = _parents[id]
		if not is_instance_valid(record.node) or (record.node as Node2D).global_transform != record.transform:
			settled = false
			break
	if settled: return
	var stale: Array = []
	var moved: Array = []
	for id: int in _parents:
		var record: Dictionary = _parents[id]
		if not is_instance_valid(record.node):
			stale.append(id)
		elif (record.node as Node2D).global_transform != record.transform:
			moved.append(id)
	for id: int in stale:
		_parents.erase(id)
	for id: int in moved:
		var parent: Node2D = _parents[id].node
		_parents[id].transform = parent.global_transform
		for entry: Dictionary in _entries.values():
			if is_instance_valid(entry.unit) and entry.unit.get_parent() == parent: update(entry.unit)

func _insert(cells: Dictionary, cell: Vector2i, unit: UnitBase) -> void:
	if not cells.has(cell): cells[cell] = []
	cells[cell].append(unit)

func _remove(cells: Dictionary, cell: Vector2i, unit: UnitBase) -> void:
	if not cells.has(cell): return
	cells[cell].erase(unit)
	if cells[cell].is_empty(): cells.erase(cell)
