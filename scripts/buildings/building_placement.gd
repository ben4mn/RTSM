class_name BuildingPlacement
extends Node2D
## Ghost preview system for building placement.
## Shows a transparent building following the pointer/finger.
## Green = valid, Red = invalid. Tap/click to confirm.

signal placement_confirmed(building_type: int, position: Vector2)
signal placement_cancelled()

var active: bool = false
var current_building_type: int = -1
var current_footprint: Vector2i = Vector2i(2, 2)
var current_color: Color = Color.WHITE
var ghost_position: Vector2 = Vector2.ZERO
var is_valid_placement: bool = false
var _player_owner: int = 0


func _ready() -> void:
	set_process(false)
	set_process_input(false)
	visible = false


func start_placement(building_type: int, player_owner: int = 0) -> void:
	var stats := BuildingData.get_building_stats(building_type)
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


func cancel_placement() -> void:
	active = false
	visible = false
	current_building_type = -1
	set_process(false)
	set_process_input(false)
	placement_cancelled.emit()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var touch := event as InputEventScreenTouch
		var pressed: bool = false
		if mb:
			pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif touch:
			pressed = touch.pressed

		if pressed:
			if is_valid_placement:
				_confirm_placement()
			# Don't cancel on invalid tap -- let user reposition

	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		var pos: Vector2
		if event is InputEventScreenDrag:
			pos = (event as InputEventScreenDrag).position
		else:
			pos = (event as InputEventMouseMotion).position
		_update_ghost_position(pos)


func _update_ghost_position(screen_pos: Vector2) -> void:
	# Convert screen position to world position via the camera/canvas
	var canvas_transform := get_canvas_transform()
	var world_pos := canvas_transform.affine_inverse() * screen_pos

	# Snap to tile grid
	ghost_position = _snap_to_grid(world_pos)
	global_position = ghost_position
	is_valid_placement = _check_validity()
	queue_redraw()


func _snap_to_grid(world_pos: Vector2) -> Vector2:
	# Snap to isometric grid based on tile size
	var tile_x := roundi(world_pos.x / MapData.TILE_WIDTH) * MapData.TILE_WIDTH
	var tile_y := roundi(world_pos.y / MapData.TILE_HEIGHT) * MapData.TILE_HEIGHT
	return Vector2(tile_x, tile_y)


func _check_validity() -> bool:
	# Check tile bounds
	var tile_col := roundi(ghost_position.x / MapData.TILE_WIDTH)
	var tile_row := roundi(ghost_position.y / MapData.TILE_HEIGHT)

	for dx in current_footprint.x:
		for dy in current_footprint.y:
			var cx := tile_col + dx
			var cy := tile_row + dy
			# Out of map bounds
			if cx < 0 or cx >= MapData.MAP_WIDTH or cy < 0 or cy >= MapData.MAP_HEIGHT:
				return false

	# Check for overlapping buildings using physics
	var space := get_world_2d().direct_space_state
	if space:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = ghost_position
		query.collide_with_areas = true
		query.collision_mask = 0xFFFFFFFF
		var results := space.intersect_point(query, 8)
		for result in results:
			var collider := result.get("collider")
			if collider is BuildingBase and collider != self:
				return false

	return true


func _confirm_placement() -> void:
	var pos := ghost_position
	active = false
	visible = false
	set_process(false)
	set_process_input(false)
	placement_confirmed.emit(current_building_type, pos)
	current_building_type = -1
	queue_redraw()


func _draw() -> void:
	if not active:
		return

	var pixel_w: float = current_footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = current_footprint.y * MapData.TILE_HEIGHT

	# Draw isometric diamond ghost
	var points := PackedVector2Array([
		Vector2(0, -pixel_h * 0.5),
		Vector2(pixel_w * 0.5, 0),
		Vector2(0, pixel_h * 0.5),
		Vector2(-pixel_w * 0.5, 0),
	])

	var ghost_col: Color
	if is_valid_placement:
		ghost_col = Color(0.2, 0.8, 0.2, 0.45)
	else:
		ghost_col = Color(0.8, 0.2, 0.2, 0.45)

	draw_colored_polygon(points, ghost_col)

	# Outline
	var outline := Color(1, 1, 1, 0.7) if is_valid_placement else Color(1, 0.3, 0.3, 0.7)
	for i in points.size():
		var next_i := (i + 1) % points.size()
		draw_line(points[i], points[next_i], outline, 2.0)

	# Building name label
	var bname := BuildingData.get_building_name(current_building_type)
	if bname != "Unknown":
		var font := ThemeDB.fallback_font
		var fsize := ThemeDB.fallback_font_size
		if font:
			var text_pos := Vector2(-pixel_w * 0.25, -pixel_h * 0.5 - 12)
			draw_string(font, text_pos, bname, HORIZONTAL_ALIGNMENT_CENTER, pixel_w, fsize, Color.WHITE)
