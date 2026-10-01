class_name BuildingPlacement
extends Node2D
## Ghost preview system for building placement.
## Shows a transparent building sprite following the pointer/finger.
## Touch positions a preview; an explicit Place action confirms it.
## Desktop left click still places immediately.

signal placement_confirmed(building_type: int, position: Vector2)
signal placement_cancelled()
signal placement_invalid(reason: String)
signal preview_changed(valid: bool, reason: String)

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
var _suspended_world_inputs: Array[Dictionary] = []
var _touch_points: Dictionary = {}
var _released_touch_inputs: Dictionary = {}
var _touch_camera_gesture: bool = false
var _last_touch_input_msec: int = -10000
var _preview_refresh_elapsed: float = 0.0

const GENERIC_INVALID_REASON := "Invalid placement"
const MOUSE_AFTER_TOUCH_IGNORE_MS := 1500


func _ready() -> void:
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
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
	_suspend_conflicting_world_input()
	set_process_input(true)
	set_process_unhandled_input(true)
	_setup_ghost_sprite()
	cancel_touch_gesture()
	_preview_refresh_elapsed = 0.0
	# Always enter placement with a visible, validated preview in the current
	# view, instead of a stale ghost from the previous building or world origin.
	var view_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var center_world: Vector2 = get_canvas_transform().affine_inverse() * view_center
	update_preview_at_world(_find_initial_preview_position(center_world))


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
	_ghost_sprite.offset = BuildingBase.get_sprite_offset(current_building_type, current_footprint)
	_ghost_sprite.modulate = Color(0.4, 1.0, 0.4, 0.6)
	add_child(_ghost_sprite)


func _find_initial_preview_position(center_world: Vector2) -> Vector2:
	var center_tile: Vector2i = _world_to_tile(center_world)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var top_clearance: float = 112.0
	var bottom_clearance: float = 104.0
	var visible_world_area := Rect2(Vector2(32.0, top_clearance), viewport_size - Vector2(64.0, top_clearance + bottom_clearance))
	# A small bounded search usually finds clear ground beside the selected
	# Town Center. Every candidate still obeys current vision and occupancy.
	for radius in range(7):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile: Vector2i = center_tile + Vector2i(dx, dy)
				var world_pos: Vector2 = _tile_to_world(tile)
				if not _initial_preview_fits_world_area(tile, world_pos, visible_world_area):
					continue
				if _check_footprint_validity(tile, current_footprint, _player_owner):
					return world_pos
	return center_world


func _initial_preview_fits_world_area(tile: Vector2i, world_pos: Vector2, world_area: Rect2) -> bool:
	var canvas: Transform2D = get_canvas_transform()
	if not world_area.has_point(canvas * world_pos):
		return false
	# Account for the whole sprite above its anchor, so a useful green preview
	# cannot open behind the guidance card or the bottom thumb actions.
	if _ghost_sprite != null and _ghost_sprite.texture != null:
		var art: Rect2 = _ghost_sprite.get_rect()
		for corner: Vector2 in [art.position, art.position + Vector2(art.size.x, 0.0), art.end, art.position + Vector2(0.0, art.size.y)]:
			if not world_area.has_point(canvas * (world_pos + _ghost_sprite.transform * corner)):
				return false
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(current_footprint.x, 0), current_footprint, Vector2i(0, current_footprint.y)]:
		if not world_area.has_point(canvas * _tile_to_world(tile + offset)):
			return false
	return true


func cancel_placement() -> void:
	active = false
	visible = false
	current_building_type = -1
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	cancel_touch_gesture()
	_restore_conflicting_world_input()
	if _ghost_sprite != null:
		_ghost_sprite.queue_free()
		_ghost_sprite = null
	placement_cancelled.emit()
	queue_redraw()


func cancel_touch_gesture() -> void:
	_touch_points.clear()
	_released_touch_inputs.clear()
	_touch_camera_gesture = false


func _input(event: InputEvent) -> void:
	# A world finger can lift over a HUD Control, which owns the release before
	# unhandled input. Only clear ownership here: never move or confirm a ghost.
	if active and event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			_last_touch_input_msec = Time.get_ticks_msec()
			if _touch_points.has(touch.index):
				_released_touch_inputs[touch.index] = _touch_camera_gesture
				# This record belongs only to this input dispatch. A GUI-consumed
				# release must not accumulate stale increasing browser touch IDs.
				call_deferred("_clear_released_touch_inputs")
			_touch_points.erase(touch.index)
			if _touch_points.is_empty():
				_touch_camera_gesture = false


func _clear_released_touch_inputs() -> void:
	_released_touch_inputs.clear()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventMouseButton:
		# Godot dispatches the mouse event synthesized from a touch before the
		# unhandled touch callback. It may be the first contact after a Build
		# card owned the preceding touch, so elapsed-time suppression is too late.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var mb := event as InputEventMouseButton
		# Right-click cancels placement
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel_placement()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			update_preview_at_screen(mb.position)
			confirm_preview()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_last_touch_input_msec = Time.get_ticks_msec()
		if touch.pressed:
			_released_touch_inputs.erase(touch.index)
			_touch_points[touch.index] = touch.position
			if _touch_points.size() > 1:
				_touch_camera_gesture = true
		else:
			var owned_press: bool = _touch_points.has(touch.index) or _released_touch_inputs.has(touch.index)
			var was_camera_gesture: bool = bool(_released_touch_inputs.get(touch.index, _touch_camera_gesture))
			if not touch.canceled and not was_camera_gesture and owned_press:
				update_preview_at_screen(touch.position)
			_released_touch_inputs.erase(touch.index)
			_touch_points.erase(touch.index)
			if _touch_points.is_empty():
				_touch_camera_gesture = false
		# Camera needs touch presses/releases to recognize the second finger.
		# Selection is suspended, so these events cannot issue unit commands.
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_last_touch_input_msec = Time.get_ticks_msec()
		# A finger that began on GUI belongs to GUI until it lifts. Receiving a
		# drag outside that Control does not grant placement or camera ownership.
		if not _touch_points.has(drag.index):
			return
		_touch_points[drag.index] = drag.position
		if _touch_points.size() > 1:
			_touch_camera_gesture = true
			# GameMap owns midpoint pan and anchored pinch as one gesture.
			return
		if _touch_camera_gesture:
			# Keep navigation ownership after one pinch finger lifts; a fresh
			# one-finger gesture may reposition only after every finger ends.
			return
		update_preview_at_screen(drag.position)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if Time.get_ticks_msec() - _last_touch_input_msec < MOUSE_AFTER_TOUCH_IGNORE_MS:
			return
		var motion := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			return
		update_preview_at_screen(motion.position)
		get_viewport().set_input_as_handled()


func _suspend_conflicting_world_input() -> void:
	if not _suspended_world_inputs.is_empty():
		return
	var game_map: Node = get_parent()
	if game_map == null:
		return
	var candidates: Array[Node] = []
	var selection_manager: Node = game_map.get_node_or_null("SelectionManager")
	if selection_manager != null:
		candidates.append(selection_manager)
	for candidate in candidates:
		if candidate == self:
			continue
		if candidate.has_method("cancel_touch_gesture"):
			candidate.call("cancel_touch_gesture")
		_suspended_world_inputs.append({
			"node": candidate,
			"was_processing_unhandled_input": candidate.is_processing_unhandled_input(),
		})
		candidate.set_process_unhandled_input(false)


func _restore_conflicting_world_input() -> void:
	for state in _suspended_world_inputs:
		var candidate: Variant = state.get("node")
		if candidate is Node and is_instance_valid(candidate):
			(candidate as Node).set_process_unhandled_input(
				bool(state.get("was_processing_unhandled_input", false))
			)
	_suspended_world_inputs.clear()


func _process(delta: float) -> void:
	if not active:
		return
	_preview_refresh_elapsed += delta
	if _preview_refresh_elapsed >= 0.12:
		_preview_refresh_elapsed = 0.0
		_refresh_preview_state()


func update_preview_at_screen(screen_pos: Vector2) -> void:
	if not active:
		return
	# Convert screen position to world position via the camera/canvas
	var canvas_transform: Transform2D = get_canvas_transform()
	var world_pos := canvas_transform.affine_inverse() * screen_pos
	update_preview_at_world(world_pos)


func update_preview_at_world(world_pos: Vector2) -> void:
	if not active:
		return
	# Snap to tile grid
	ghost_position = _snap_to_grid(world_pos)
	global_position = ghost_position
	_refresh_preview_state(true)


func _update_ghost_position(screen_pos: Vector2) -> void:
	update_preview_at_screen(screen_pos)


func _refresh_preview_state(force_signal: bool = false) -> void:
	var was_valid: bool = is_valid_placement
	var previous_reason: String = _invalid_reason
	is_valid_placement = _check_validity()

	# Update ghost sprite tint
	if _ghost_sprite != null:
		if is_valid_placement:
			_ghost_sprite.modulate = Color(0.4, 1.0, 0.4, 0.6)
		else:
			_ghost_sprite.modulate = Color(1.0, 0.3, 0.3, 0.6)

	queue_redraw()
	if force_signal or was_valid != is_valid_placement or previous_reason != _invalid_reason:
		preview_changed.emit(is_valid_placement, "" if is_valid_placement else get_invalid_reason())


## Called by the explicit touch Place action. Always revalidates the footprint.
func confirm_preview() -> bool:
	if not active:
		return false
	_refresh_preview_state()
	if not is_valid_placement:
		_emit_invalid_feedback()
		return false
	_confirm_placement()
	return not active


func _snap_to_grid(world_pos: Vector2) -> Vector2:
	var game_map := get_parent()
	if game_map != null and game_map.has_method("world_to_tile") and game_map.has_method("tile_to_world"):
		return game_map.call("tile_to_world", game_map.call("world_to_tile", world_pos))
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
	return _world_to_tile(ghost_position)


func _world_to_tile(world_pos: Vector2) -> Vector2i:
	var game_map := get_parent()
	if game_map != null and game_map.has_method("world_to_tile"):
		return game_map.call("world_to_tile", world_pos)
	if _terrain_layer:
		return _terrain_layer.local_to_map(world_pos)
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	var tx := int((world_pos.x / half_w + world_pos.y / half_h) / 2.0)
	var ty := int((world_pos.y / half_h - world_pos.x / half_w) / 2.0)
	return Vector2i(tx, ty)


func _check_validity() -> bool:
	return _check_footprint_validity(_get_ghost_tile(), current_footprint, _player_owner)


## Perform the final authoritative placement check. The gameplay coordinator
## calls this immediately before spending resources and spawning the building,
## closing the gap between a green preview and confirmation.
func revalidate_confirmation(building_type: int, world_pos: Vector2, player_owner: int = 0) -> bool:
	_try_find_terrain_layer()
	var stats: Dictionary = BuildingData.get_building_stats(building_type)
	if stats.is_empty():
		_invalid_reason = GENERIC_INVALID_REASON
		_invalid_tiles.clear()
		return false
	var footprint: Vector2i = stats.get("footprint", Vector2i(2, 2))
	return _check_footprint_validity(_world_to_tile(world_pos), footprint, player_owner)


func get_invalid_reason() -> String:
	return _invalid_reason if _invalid_reason != "" else GENERIC_INVALID_REASON


func _check_footprint_validity(
	tile_origin: Vector2i,
	footprint: Vector2i,
	player_owner: int
) -> bool:
	_invalid_reason = ""
	_invalid_tiles.clear()
	var has_buildable_check: bool = false
	var has_walkable_check: bool = false
	var game_map := get_parent()
	if game_map:
		has_buildable_check = game_map.has_method("is_tile_buildable")
		has_walkable_check = game_map.has_method("is_tile_walkable")

	# Bounds and visibility are checked in separate passes before terrain or
	# occupancy. If any part of the footprint is outside current vision, return a
	# single generic result and never query hidden walkability/buildings. This
	# prevents the preview or feedback text from becoming an information oracle.
	for dx in footprint.x:
		for dy in footprint.y:
			var cx := tile_origin.x + dx
			var cy := tile_origin.y + dy
			var check_tile := Vector2i(cx, cy)
			if cx < 0 or cx >= MapData.MAP_WIDTH or cy < 0 or cy >= MapData.MAP_HEIGHT:
				if _invalid_reason == "":
					_invalid_reason = "Out of bounds"
				_invalid_tiles.append(check_tile)
	if not _invalid_tiles.is_empty():
		return false

	var visibility_api_available: bool = game_map != null and game_map.has_method("is_tile_visible_to_player")
	if player_owner == 0 and not visibility_api_available:
		_invalid_reason = GENERIC_INVALID_REASON
		for dx in footprint.x:
			for dy in footprint.y:
				_invalid_tiles.append(tile_origin + Vector2i(dx, dy))
		return false
	if visibility_api_available:
		var has_hidden_tile := false
		for dx in footprint.x:
			for dy in footprint.y:
				var check_tile := tile_origin + Vector2i(dx, dy)
				if not bool(game_map.call("is_tile_visible_to_player", check_tile, player_owner)):
					has_hidden_tile = true
		if has_hidden_tile:
			_invalid_reason = GENERIC_INVALID_REASON
			for dx in footprint.x:
				for dy in footprint.y:
					_invalid_tiles.append(tile_origin + Vector2i(dx, dy))
			return false

	# The whole footprint is visible, so detailed terrain/occupancy feedback no
	# longer reveals hidden state.
	for dx in footprint.x:
		for dy in footprint.y:
			var check_tile := tile_origin + Vector2i(dx, dy)
			var tile_invalid := false
			if has_buildable_check:
				if not bool(game_map.call("is_tile_buildable", check_tile)):
					if _invalid_reason == "":
						_invalid_reason = "Blocked terrain"
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
	var game_map := get_parent()
	if game_map != null and game_map.has_method("tile_to_world"):
		return game_map.call("tile_to_world", tile_pos)
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
	var reason: String = get_invalid_reason()
	placement_invalid.emit(reason)
	AudioManager.play_sfx("building_invalid")


func _confirm_placement() -> void:
	if not active:
		return
	# Input may arrive a frame after the green preview was calculated. Recheck
	# fog, terrain, and occupancy before emitting any gameplay-side request.
	is_valid_placement = _check_validity()
	if not is_valid_placement:
		if _ghost_sprite != null:
			_ghost_sprite.modulate = Color(1.0, 0.3, 0.3, 0.6)
		queue_redraw()
		preview_changed.emit(false, get_invalid_reason())
		_emit_invalid_feedback()
		return
	var pos := ghost_position
	active = false
	visible = false
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	cancel_touch_gesture()
	_restore_conflicting_world_input()
	if _ghost_sprite != null:
		_ghost_sprite.queue_free()
		_ghost_sprite = null
	placement_confirmed.emit(current_building_type, pos)
	AudioManager.play_sfx("building_place")
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
			var fill := Color(0.30, 0.90, 0.45, 0.22)
			var stroke := Color(0.90, 1.0, 0.68, 0.92)
			if tile_invalid:
				fill = Color(1.0, 0.20, 0.20, 0.34)
				stroke = Color(1.0, 0.45, 0.35, 0.96)
			draw_colored_polygon(tile_points, fill)
			for i in tile_points.size():
				var next_i := (i + 1) % tile_points.size()
				draw_line(tile_points[i], tile_points[next_i], stroke, 2.0)

	var pixel_w: float = current_footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = current_footprint.y * MapData.TILE_HEIGHT

	# Draw isometric diamond outline for footprint
	var points := PackedVector2Array([
		Vector2(0, -pixel_h * 0.5),
		Vector2(pixel_w * 0.5, 0),
		Vector2(0, pixel_h * 0.5),
		Vector2(-pixel_w * 0.5, 0),
	])

	var outline := Color(1.0, 0.94, 0.70, 0.85) if is_valid_placement else Color(1.0, 0.3, 0.3, 0.75)
	for i in points.size():
		var next_i := (i + 1) % points.size()
		draw_line(points[i], points[next_i], outline, 2.2)

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
