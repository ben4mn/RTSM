extends Node
## Presentation only: revealed units retain their silhouette behind opaque art.
## Echoes inherit the real unit's visibility and sit below the existing fog layer.

const REFRESH_SECONDS: float = 0.10
const CELL_SIZE: float = 128.0
const ECHO_Z: int = 5 # World=0, fog=10. Never draw on top of fog.
const UNITS_PER_FRAME: int = 32
const OUTLINE := preload("res://assets/shaders/unit_occlusion.gdshader")
var _map: Node2D
var _elapsed: float = REFRESH_SECONDS
var _entries: Dictionary = {}
var _bins: Dictionary = {}
var _pending: Array[WeakRef] = []
var _scan_cursor: int = 0
var _sample_cache: Dictionary = {}
var last_candidate_checks: int = 0
var allow_headless_fixture: bool = false


func _ready() -> void:
	_map = get_parent() as Node2D
	process_priority = 90 # Observe this frame's simulation and fog updates.
	if DisplayServer.get_name() == "headless": set_process(false)


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless" and not allow_headless_fixture: return
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS and _scan_cursor >= _pending.size():
		_elapsed = 0.0
		_begin_scan()
	_scan_units(UNITS_PER_FRAME)
	for id: int in _entries.keys():
		var entry: Dictionary = _entries[id]
		var unit: UnitBase = entry.unit.get_ref() as UnitBase
		var echo: Sprite2D = entry.echo.get_ref() as Sprite2D
		if not is_instance_valid(unit) or not is_instance_valid(echo):
			_entries.erase(id)
			continue
		# Recheck vision every frame, independently of the bounded overlap scan.
		# Hidden ancestors and dead/remotely hidden actors can never leave an echo.
		echo.visible = bool(entry.occluded) and _unit_revealed(unit)
		if echo.visible:
			var source: Sprite2D = unit._sprite
			if echo.texture != source.texture: echo.texture = source.texture
			if echo.transform != source.transform: echo.transform = source.transform
			if echo.offset != source.offset: echo.offset = source.offset
			if echo.flip_h != source.flip_h: echo.flip_h = source.flip_h
			if echo.flip_v != source.flip_v: echo.flip_v = source.flip_v
			var edge: float = clampf(1.6 / maxf(0.05, absf(source.scale.x)), 3.0, 12.0)
			if not is_equal_approx(edge, float(entry.edge)):
				(echo.material as ShaderMaterial).set_shader_parameter("edge_pixels", edge)
				entry.edge = edge


func _unit_revealed(unit: UnitBase) -> bool:
	if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD or not unit.is_visible_in_tree(): return false
	var source: Sprite2D = unit._sprite
	return source != null and source.texture != null and source.is_visible_in_tree() and bool(_map.call("is_entity_visible_to_player", unit, 0))


func refresh_occlusion() -> void:
	# Synchronous entry point for rendering-contract fixtures.
	_begin_scan()
	_scan_units(_pending.size())


func _begin_scan() -> void:
	if not is_instance_valid(_map): return
	if DisplayServer.get_name() == "headless" and not allow_headless_fixture: return
	var viewport: Viewport = _map.get_viewport()
	var canvas: Transform2D = viewport.get_canvas_transform()
	var screen: Rect2 = viewport.get_visible_rect().grow(50.0)
	_bins.clear()
	last_candidate_checks = 0
	_pending.clear()
	_scan_cursor = 0
	var seen: Dictionary = {}
	for container_name: String in ["BuildingsContainer", "ResourcesContainer", "UnitsContainer"]:
		var container: Node = _map.get_node_or_null(NodePath(container_name))
		if container == null: continue
		for entity: Node in container.get_children():
			if not entity is Node2D or not entity.is_visible_in_tree(): continue
			if entity is UnitBase and not _unit_revealed(entity): continue
			if not bool(_map.call("is_entity_visible_to_player", entity, 0)): continue
			var source: Sprite2D = entity.get("_sprite") as Sprite2D
			if source == null or source.texture == null or not source.is_visible_in_tree(): continue
			var rect: Rect2 = source.global_transform * _ink_rect(source)
			if not screen.intersects(canvas * rect): continue
			# Buildings expose a y-sorted sprite at their footprint center; trees
			# and units sort at the entity's ground anchor in the existing world.
			var depth: float = source.global_position.y if entity is BuildingBase else entity.global_position.y
			var item := {"entity": entity, "sprite": source, "rect": rect, "depth": depth}
			for cell: Vector2i in _cells(rect):
				if not _bins.has(cell): _bins[cell] = []
				_bins[cell].append(item)
			if entity is UnitBase:
				_pending.append(weakref(entity))
				seen[entity.get_instance_id()] = true
	for id: int in _entries:
		if not seen.has(id): _entries[id].occluded = false


func _scan_units(budget: int) -> void:
	var end: int = mini(_pending.size(), _scan_cursor + budget)
	while _scan_cursor < end:
		var unit: UnitBase = _pending[_scan_cursor].get_ref() as UnitBase
		_scan_cursor += 1
		if not is_instance_valid(unit) or not _unit_revealed(unit): continue
		var source: Sprite2D = unit._sprite
		var rect: Rect2 = source.global_transform * _ink_rect(source)
		var body_points: PackedVector2Array = _body_points(source)
		var checked: Dictionary = {}
		var occluded: bool = false
		for cell: Vector2i in _cells(rect):
			if occluded: break
			for candidate: Dictionary in _bins.get(cell, []):
				if not is_instance_valid(candidate.entity): continue
				var other: Node2D = candidate.entity
				if not is_instance_valid(other) or not other.is_visible_in_tree(): continue
				if other == unit or checked.has(other.get_instance_id()): continue
				checked[other.get_instance_id()] = true
				if float(candidate.depth) < unit.global_position.y or not rect.intersects(candidate.rect): continue
				if not bool(_map.call("is_entity_visible_to_player", other, 0)): continue
				if not is_instance_valid(candidate.sprite): continue
				var foreground: Sprite2D = candidate.sprite
				if not is_instance_valid(foreground) or not foreground.is_visible_in_tree(): continue
				last_candidate_checks += 1
				if _points_covered(body_points, foreground):
					occluded = true
					break
		var id: int = unit.get_instance_id()
		if occluded and not _entries.has(id): _create_echo(unit)
		if _entries.has(id): _entries[id].occluded = occluded


func _create_echo(unit: UnitBase) -> void:
	var echo := Sprite2D.new()
	echo.name = "OccludedUnitEcho"
	echo.z_as_relative = false
	echo.z_index = ECHO_Z
	echo.visible = false
	var material := ShaderMaterial.new()
	material.shader = OUTLINE
	material.set_shader_parameter("body_color", Color("335b58") if unit.player_owner == 0 else Color("854f42"))
	echo.material = material
	unit.add_child(echo)
	_entries[unit.get_instance_id()] = {"unit": weakref(unit), "echo": weakref(echo), "occluded": true, "edge": 0.0}


func _ink_rect(sprite: Sprite2D) -> Rect2:
	var ink: Rect2 = KingdomArt.ink_rect(sprite.texture)
	var rect := Rect2(sprite.get_rect().position + ink.position, ink.size)
	if sprite.flip_h: rect.position.x = -rect.end.x
	if sprite.flip_v: rect.position.y = -rect.end.y
	return rect


func _opaque_overlap(source: Sprite2D, foreground: Sprite2D) -> bool:
	return _points_covered(_body_points(source), foreground)


func _body_points(source: Sprite2D) -> PackedVector2Array:
	var key: int = source.texture.get_instance_id()
	if not _sample_cache.has(key):
		var ink: Rect2 = KingdomArt.ink_rect(source.texture)
		var image: Image = source.texture.get_image()
		var points := PackedVector2Array()
		# Cache only actual opaque body pixels in texture coordinates. Shared
		# art, transparent padding and flipped actors need no per-candidate read.
		if image != null:
			for y: float in [0.18, 0.38, 0.58, 0.78, 0.90]:
				for x: float in [0.25, 0.50, 0.75]:
					var point: Vector2 = ink.position + ink.size * Vector2(x, y)
					if image.get_pixelv(Vector2i(point)).a > 0.1: points.append(point)
		_sample_cache[key] = points
	var result := PackedVector2Array()
	for point: Vector2 in _sample_cache[key]:
		var local: Vector2 = source.get_rect().position + point
		if source.flip_h: local.x = -local.x
		if source.flip_v: local.y = -local.y
		result.append(source.to_global(local))
	return result


func _points_covered(points: PackedVector2Array, foreground: Sprite2D) -> bool:
	var inverse: Transform2D = foreground.global_transform.affine_inverse()
	for point: Vector2 in points:
		if foreground.is_pixel_opaque(inverse * point): return true
	return false


func _cells(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var first := Vector2i((rect.position / CELL_SIZE).floor())
	var last := Vector2i((rect.end / CELL_SIZE).floor())
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1): result.append(Vector2i(x, y))
	return result


func _exit_tree() -> void:
	for id: int in _entries:
		var echo: Sprite2D = _entries[id].echo.get_ref() as Sprite2D
		if is_instance_valid(echo): echo.queue_free()
	_entries.clear()
