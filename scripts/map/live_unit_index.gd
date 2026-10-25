extends RefCounted
## Broad-phase only. Callers retain exact distance, ownership, death and fog rules.
## Local transform notifications update immediately, including paused teleports.
const CELL_SIZE: float = 64.0
const VISION_CELL_TILES: float = 4.0
var _map: Node2D
var _entries: Dictionary = {}
var _cells: Dictionary = {}
var _vision_cells: Dictionary = {}
var _parents: Dictionary = {}
var _unit_vision_cache: Dictionary = {}

func _init(map: Node2D) -> void:
	_map = map

func update(unit: UnitBase) -> void:
	if not is_instance_valid(unit) or not unit.is_inside_tree(): return
	var id: int = unit.get_instance_id()
	var cell := Vector2i((unit.global_position / CELL_SIZE).floor())
	var tile: Vector2i = _map.world_to_tile(unit.global_position)
	var radius: int = maxi(0, int(round(MapData.world_to_range_tiles(unit.vision_radius))))
	var first := Vector2i((Vector2(tile - Vector2i(radius, radius)) / VISION_CELL_TILES).floor())
	var last := Vector2i((Vector2(tile + Vector2i(radius, radius)) / VISION_CELL_TILES).floor())
	if not _entries.has(id):
		_entries[id] = {"unit": unit, "cell": cell, "first": first, "last": last, "tile": tile, "radius": radius, "parent": unit.get_parent()}
		invalidate_vision()
		_insert(_cells, cell, unit)
		_vision_change(unit, first, last, true)
	else:
		var entry: Dictionary = _entries[id]
		if entry.tile != tile or entry.radius != radius:
			invalidate_vision()
			entry.tile = tile
			entry.radius = radius
		if entry.cell != cell:
			_remove(_cells, entry.cell, unit)
			_insert(_cells, cell, unit)
			entry.cell = cell
		if entry.first != first or entry.last != last:
			_vision_change(unit, entry.first, entry.last, false)
			_vision_change(unit, first, last, true)
			entry.first = first
			entry.last = last
		entry.parent = unit.get_parent()
	var parent: Node2D = unit.get_parent() as Node2D
	if parent != null and not _parents.has(parent.get_instance_id()):
		_parents[parent.get_instance_id()] = {"node": parent, "transform": parent.global_transform}

func remove(unit: UnitBase) -> void:
	var id: int = unit.get_instance_id()
	if not _entries.has(id): return
	var entry: Dictionary = _entries[id]
	_remove(_cells, entry.cell, unit)
	_vision_change(unit, entry.first, entry.last, false)
	_entries.erase(id)
	invalidate_vision()

func invalidate_vision() -> void:
	_unit_vision_cache.clear()

func units_reveal(tile: Vector2i, owner: int) -> bool:
	_refresh_parent_transforms()
	var key := Vector3i(tile.x, tile.y, owner)
	if _unit_vision_cache.has(key): return _unit_vision_cache[key]
	var visible: bool = false
	for unit: UnitBase in _vision_cells.get(Vector2i((Vector2(tile) / VISION_CELL_TILES).floor()), []):
		if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.player_owner != owner or unit.current_state == UnitBase.State.DEAD: continue
		var entry: Dictionary = _entries[unit.get_instance_id()]
		var offset: Vector2i = tile - entry.tile
		if offset.x * offset.x + offset.y * offset.y <= entry.radius * entry.radius:
			visible = true
			break
	_unit_vision_cache[key] = visible
	return visible

func near(position: Vector2, radius: float) -> Array[UnitBase]:
	_refresh_parent_transforms()
	var result: Array[UnitBase] = []
	var first := Vector2i(((position - Vector2.ONE * radius) / CELL_SIZE).floor())
	var last := Vector2i(((position + Vector2.ONE * radius) / CELL_SIZE).floor())
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			for unit: UnitBase in _cells.get(Vector2i(x, y), []):
				if is_instance_valid(unit) and unit.is_inside_tree() and unit.current_state != UnitBase.State.DEAD and unit.global_position.distance_to(position) <= radius:
					result.append(unit)
	# Match SceneTree group order, preserving equal-distance targets and sums.
	result.sort_custom(func(a: UnitBase, b: UnitBase) -> bool: return b.is_greater_than(a))
	return result

func _refresh_parent_transforms() -> void:
	for id: int in _parents.keys():
		if not is_instance_valid(_parents[id].node):
			_parents.erase(id)
			continue
		var parent: Node2D = _parents[id].node
		if parent.global_transform != _parents[id].transform:
			_parents[id].transform = parent.global_transform
			for entry: Dictionary in _entries.values():
				if is_instance_valid(entry.unit) and entry.unit.get_parent() == parent: update(entry.unit)

func _vision_change(unit: UnitBase, first: Vector2i, last: Vector2i, insert: bool) -> void:
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			if insert: _insert(_vision_cells, Vector2i(x, y), unit)
			else: _remove(_vision_cells, Vector2i(x, y), unit)

func _insert(cells: Dictionary, cell: Vector2i, unit: UnitBase) -> void:
	if not cells.has(cell): cells[cell] = []
	cells[cell].append(unit)

func _remove(cells: Dictionary, cell: Vector2i, unit: UnitBase) -> void:
	if not cells.has(cell): return
	cells[cell].erase(unit)
	if cells[cell].is_empty(): cells.erase(cell)
