class_name BuildingPlacement
extends Node2D
## Ghost preview system for building placement.
## Shows a transparent building sprite following the pointer/finger.
## Green tint = valid, Red tint = invalid. Tap/click to confirm.

signal placement_confirmed(building_type: int, position: Vector2)
signal placement_cancelled()
signal placement_invalid(reason: String)

var active: bool = false
var current_building_type: int = -1
var current_footprint: Vector2i = Vector2i(2, 2)
var current_color: Color = Color.WHITE
var ghost_position: Vector2 = Vector2.ZERO
var is_valid_placement: bool = false
var _invalid_reason: String = ""
var _invalid_tiles: Array[Vector2i] = []
var _player_owner: int = 0
var _ghost_sprite: Sprite2D = null
var _terrain_layer: TileMapLayer = null
var _last_invalid_feedback_msec: int = -10000


func _ready() -> void:
	set_process(false)
	set_process_input(false)
	visible = false
	_try_find_terrain_layer()


func _try_find_terrain_layer() -> void:
	if _terrain_layer != null:
		return
	var parent := get_parent()
	if parent and parent.has_node("TerrainLayer"):
		_terrain_layer = parent.get_node("TerrainLayer") as TileMapLayer


func start_placement(building_type: int, player_owner: int = 0) -> void:
	_try_find_terrain_layer()
	var stats: Dictionary = BuildingData.get_building_stats(building_type)
	if stats.is_empty():
		return
	current_building_type = building_type
	current_footprint = stats.get("footprint", Vector2i(2, 2))
	current_color = stats.get("color", Color(0.5, 0.5, 0.5))
	_player_owner = player_owner
	active = true
	visible = true
	set_process(true)
	set_process_input(true)
	_setup_ghost_sprite()


func _setup_ghost_sprite() -> void:
	# Remove old ghost sprite if any
	if _ghost_sprite != null:
		_ghost_sprite.queue_free()
		_ghost_sprite = null

	_ghost_sprite = Sprite2D.new()
	var tex_path: String = BuildingBase.BUILDING_SPRITES.get(current_building_type, "")
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_ghost_sprite.texture = load(tex_path)
	_ghost_sprite.scale = BuildingBase.BUILDING_SCALES.get(current_building_type, Vector2(0.4, 0.4))
	var sprite_y_offset := -current_footprint.y * MapData.TILE_HEIGHT * 0.3
	_ghost_sprite.offset = Vector2(0, sprite_y_offset)
	_ghost_sprite.modulate = Color(0.4, 1.0, 0.4, 0.6)
	add_child(_ghost_sprite)


func cancel_placement() -> void:
	active = false
	visible = false
	current_building_type = -1
	set_process(false)
	set_process_input(false)
	if _ghost_sprite != null:
		_ghost_sprite.queue_free()
		_ghost_sprite = null
	placement_cancelled.emit()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Right-click cancels placement
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel_placement()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if is_valid_placement:
				_confirm_placement()
			else:
				_emit_invalid_feedback()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_update_ghost_position(touch.position)
			if is_valid_placement:
				_confirm_placement()
			else:
				_emit_invalid_feedback()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		var pos: Vector2
		if event is InputEventScreenDrag:
			pos = (event as InputEventScreenDrag).position
		else:
			pos = (event as InputEventMouseMotion).position
		_update_ghost_position(pos)
		get_viewport().set_input_as_handled()


func _update_ghost_position(screen_pos: Vector2) -> void:
	# Convert screen position to world position via the camera/canvas
	var canvas_transform: Transform2D = get_canvas_transform()
	var world_pos := canvas_transform.affine_inverse() * screen_pos

	# Snap to tile grid
	ghost_position = _snap_to_grid(world_pos)
	global_position = ghost_position
	is_valid_placement = _check_validity()

	# Update ghost sprite tint
	if _ghost_sprite != null:
		if is_valid_placement:
			_ghost_sprite.modulate = Color(0.4, 1.0, 0.4, 0.6)
		else:
			_ghost_sprite.modulate = Color(1.0, 0.3, 0.3, 0.6)

	queue_redraw()


func _snap_to_grid(world_pos: Vector2) -> Vector2:
	# Use TileMapLayer's isometric conversion for correct snapping
	if _terrain_layer:
		var tile_coords := _terrain_layer.local_to_map(world_pos)
		return _terrain_layer.map_to_local(tile_coords)
	# Fallback: isometric formula
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	var tile_x := roundi((world_pos.x / half_w + world_pos.y / half_h) / 2.0)
	var tile_y := roundi((world_pos.y / half_h - world_pos.x / half_w) / 2.0)
	return Vector2((tile_x - tile_y) * half_w, (tile_x + tile_y) * half_h)


func _get_ghost_tile() -> Vector2i:
	if _terrain_layer:
		return _terrain_layer.local_to_map(ghost_position)
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	var tx := int((ghost_position.x / half_w + ghost_position.y / half_h) / 2.0)
	var ty := int((ghost_position.y / half_h - ghost_position.x / half_w) / 2.0)
	return Vector2i(tx, ty)


func _check_validity() -> bool:
	_invalid_reason = ""
	_invalid_tiles.clear()
	var tile_origin := _get_ghost_tile()
	var has_walkable_check: bool = false
	var game_map := get_parent()
	if game_map and game_map.has_method("is_tile_walkable"):
		has_walkable_check = true

	# Check tile bounds for entire footprint
	for dx in current_footprint.x:
		for dy in current_footprint.y:
			var cx := tile_origin.x + dx
			var cy := tile_origin.y + dy
			var check_tile := Vector2i(cx, cy)
			var tile_invalid := false
			if cx < 0 or cx >= MapData.MAP_WIDTH or cy < 0 or cy >= MapData.MAP_HEIGHT:
				if _invalid_reason == "":
					_invalid_reason = "Out of bounds"
				tile_invalid = true
			elif has_walkable_check and not game_map.is_tile_walkable(check_tile):
				if _invalid_reason == "":
					_invalid_reason = "Blocked terrain"
				tile_invalid = true
			elif _has_building_at_tile(check_tile):
				if _invalid_reason == "":
					_invalid_reason = "Overlaps building"
				tile_invalid = true
			if tile_invalid:
				_invalid_tiles.append(check_tile)

	return _invalid_tiles.is_empty()


func _has_building_at_tile(tile_pos: Vector2i) -> bool:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return false
	var query := PhysicsPointQueryParameters2D.new()
	query.position = _tile_to_world(tile_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 0xFFFFFFFF
	var results: Array[Dictionary] = space.intersect_point(query, 8)
	for result in results:
		var collider: Variant = result.get("collider")
		if collider is BuildingBase and collider != self:
			return true
	return false


func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	if _terrain_layer:
		return _terrain_layer.map_to_local(tile_pos)
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	return Vector2((tile_pos.x - tile_pos.y) * half_w, (tile_pos.x + tile_pos.y) * half_h)


func _emit_invalid_feedback() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_invalid_feedback_msec < 300:
		return
	_last_invalid_feedback_msec = now
	var reason: String = _invalid_reason if _invalid_reason != "" else "Invalid placement"
	placement_invalid.emit(reason)


func _confirm_placement() -> void:
	var pos := ghost_position
	active = false
	visible = false
	set_process(false)
	set_process_input(false)
	if _ghost_sprite != null:
		_ghost_sprite.queue_free()
		_ghost_sprite = null
	placement_confirmed.emit(current_building_type, pos)
	current_building_type = -1
	queue_redraw()


func _draw() -> void:
	if not active:
		return

	var origin_tile := _get_ghost_tile()
	var half_w: float = float(MapData.TILE_WIDTH) * 0.5
	var half_h: float = float(MapData.TILE_HEIGHT) * 0.5

	# Per-tile footprint overlay makes blocked cells clear on touch devices.
	for dx in current_footprint.x:
		for dy in current_footprint.y:
			var tile_pos := origin_tile + Vector2i(dx, dy)
			var local_center := to_local(_tile_to_world(tile_pos))
			var tile_points := PackedVector2Array([
				local_center + Vector2(0, -half_h),
				local_center + Vector2(half_w, 0),
				local_center + Vector2(0, half_h),
				local_center + Vector2(-half_w, 0),
			])
			var tile_invalid: bool = tile_pos in _invalid_tiles
			var fill := Color(0.30, 0.85, 0.45, 0.14)
			var stroke := Color(0.45, 1.0, 0.65, 0.45)
			if tile_invalid:
				fill = Color(1.0, 0.20, 0.20, 0.24)
				stroke = Color(1.0, 0.45, 0.35, 0.85)
			draw_colored_polygon(tile_points, fill)
			for i in tile_points.size():
				var next_i := (i + 1) % tile_points.size()
				draw_line(tile_points[i], tile_points[next_i], stroke, 1.2)

	var pixel_w: float = current_footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = current_footprint.y * MapData.TILE_HEIGHT

	# Draw isometric diamond outline for footprint
	var points := PackedVector2Array([
		Vector2(0, -pixel_h * 0.5),
		Vector2(pixel_w * 0.5, 0),
		Vector2(0, pixel_h * 0.5),
		Vector2(-pixel_w * 0.5, 0),
	])

	var outline := Color(1, 1, 1, 0.5) if is_valid_placement else Color(1, 0.3, 0.3, 0.5)
	for i in points.size():
		var next_i := (i + 1) % points.size()
		draw_line(points[i], points[next_i], outline, 1.5)

	# Building name label
	var bname := BuildingData.get_building_name(current_building_type)
	var font := ThemeDB.fallback_font
	var fsize := ThemeDB.fallback_font_size
	if font:
		if bname != "Unknown":
			var text_pos := Vector2(-pixel_w * 0.25, -pixel_h * 0.5 - 20)
			draw_string(font, text_pos, bname, HORIZONTAL_ALIGNMENT_CENTER, pixel_w, fsize, Color.WHITE)
		# Show reason when placement is invalid
		if not is_valid_placement and _invalid_reason != "":
			var reason_pos := Vector2(-pixel_w * 0.25, pixel_h * 0.5 + 14)
			draw_string(font, reason_pos, _invalid_reason, HORIZONTAL_ALIGNMENT_CENTER, pixel_w, fsize, Color(1.0, 0.4, 0.3))
