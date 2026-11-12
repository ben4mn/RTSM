class_name BuildingPlacement
extends Node2D
## Ghost preview system for building placement.
##
## L2 — one placement language on a phone:
## - Picking a building shows the ghost already on a valid spot in view.
## - Tapping the ghost itself (or the Build button attached to it) builds.
## - Tapping anywhere else moves the ghost there (centred under the finger);
##   it never builds. Dragging that starts on the ghost carries it; a drag
##   that starts elsewhere pans the map; two fingers pinch.
## Mouse keeps the desktop idiom: the ghost follows the cursor, left click
## builds there, Shift+click builds and keeps placing, right click cancels.

signal placement_confirmed(building_type: int, position: Vector2)
signal placement_cancelled()
signal placement_invalid(reason: String)
signal preview_changed(valid: bool, reason: String)
signal input_mode_changed(uses_touch: bool)
signal assisted_preview_changed(active: bool)

var active: bool = false
var current_building_type: int = -1
var current_footprint: Vector2i = Vector2i(2, 2)
var current_color: Color = Color.WHITE
var ghost_position: Vector2 = Vector2.ZERO
var is_valid_placement: bool = false
var _invalid_reason: String = ""
var _invalid_tiles: Array[Vector2i] = []
var _clearance_tiles: Array[Vector2i] = []
var _clearance_areas: Array[Rect2i] = []
var _player_owner: int = 0
var _ghost_sprite: Sprite2D = null
var _ghost_art_rect: Rect2 = Rect2()
var _terrain_layer: TileMapLayer = null
var _last_invalid_feedback_msec: int = -10000
var _suspended_world_inputs: Array[Dictionary] = []
var _touch_points: Dictionary = {}
var _released_touch_inputs: Dictionary = {}
var _touch_camera_gesture: bool = false
## Where each placement finger first touched. A finger that lifts close to
## where it landed is a tap.
var _touch_starts: Dictionary = {}
## L2: fingers that landed on the ghost (index -> world offset from the
## finger to the ghost anchor). They carry the ghost instead of the camera.
var _ghost_grabs: Dictionary = {}
var _ghost_dragging: Dictionary = {}
## Same as the camera pan deadzone and the selection tap slop (12 px): a
## finger that pans the map is never also a tap.
const TAP_TO_PLACE_SLOP_PX: float = 12.0
const GHOST_DRAG_SLOP_PX: float = 6.0
## Extra screen pixels around the drawn ghost that still count as "on it".
const GHOST_HIT_MARGIN_PX: float = 8.0
## Ignore a confirm this soon after another one (a nervous double tap).
const CONFIRM_DEBOUNCE_MSEC: int = 350
var _last_confirm_msec: int = -100000
var _uses_touch_input: bool = false
var _assisted_preview_active: bool = false
var _preview_refresh_elapsed: float = 0.0
var _placement_grid: PlacementGrid = null
var _grid_canvas_transform: Transform2D = Transform2D.IDENTITY
var _grid_world_transform: Transform2D = Transform2D.IDENTITY
var _grid_view_rect: Rect2 = Rect2()
var _grid_tile_bounds: Rect2i = Rect2i()
var _grid_cache_valid: bool = false
var _grid_preview_tile := Vector2i(-1000, -1000)
var _trade_preview: Dictionary = {}

const TRADE_PREVIEW = preload("res://scripts/units/trade_preview.gd")
const HAPTICS = preload("res://scripts/ui/haptics.gd")

const FIND_SPACE_RADIUS: int = 12
const FIND_SPACE_MAX_CANDIDATES: int = 625
const FIND_SPACE_SCREEN_MARGIN: float = 6.0
## K: Find's last resort walks outward from your Town Centers this far, with
## this many full placement checks at most (fogged ground fails on its first
## lookup, so most rings cost very little).
const FIND_OWNED_SPACE_RADIUS: int = 18
const FIND_OWNED_SPACE_MAX_CHECKS: int = 1500
const GENERIC_INVALID_REASON := "Invalid placement"
const FOG_INVALID_REASON := "Move all tiles into sight"
const SHORE_INVALID_REASON := "Too close to the shore"
const PLACEMENT_GRID_COLOR := Color(0.90, 0.92, 0.83, 0.18)
const PLACEMENT_GRID_WIDTH_PX := 0.9
const PLACEMENT_GRID_MARGIN_TILES: int = 1
const FOOTPRINT_INK := Color("f4eddd")
const FOOTPRINT_GOLD := Color("e8bf77")
const FOOTPRINT_BLOCKED := Color("df947f")
## L2: valid ground reads green at a glance (red stays "no").
const FOOTPRINT_VALID := Color("b4dc8c")
const PREVIEW_VALID_TINT := Color(1.0, 1.0, 1.0, 0.78)
const PREVIEW_INVALID_TINT := Color(1.0, 0.80, 0.75, 0.72)
const PREVIEW_LAYER: int = 8


class PlacementGrid extends Node2D:
	var segments := PackedVector2Array()
	var line_width: float = 1.0

	func _draw() -> void:
		if not segments.is_empty():
			draw_multiline(segments, PLACEMENT_GRID_COLOR, line_width, true)


func _ready() -> void:
	# A preview is a planning overlay, not a world actor. Canopies must not hide
	# its reserved cells or blocked marks; the actual fog layer remains above it.
	z_as_relative = false
	z_index = PREVIEW_LAYER
	set_process(false)
	# Observe real input before GUI routing, including the Build card that
	# starts placement. Viewport size does not identify the active input device.
	_uses_touch_input = DisplayServer.is_touchscreen_available()
	set_process_input(true)
	set_process_unhandled_input(false)
	visible = false
	_try_find_terrain_layer()


func _try_find_terrain_layer() -> void:
	if _terrain_layer != null:
		return
	var parent := get_parent()
	if parent and parent.has_node("TerrainLayer"):
		_terrain_layer = parent.get_node("TerrainLayer") as TileMapLayer


## I2: a real (not emulated) touch or mouse press has been observed.
var _real_pointer_seen: bool = false


func start_placement(building_type: int, player_owner: int = 0) -> void:
	_try_find_terrain_layer()
	var stats: Dictionary = BuildingData.get_building_stats(building_type)
	if stats.is_empty():
		return
	current_building_type = building_type
	current_footprint = stats.get("footprint", Vector2i(2, 2))
	current_color = stats.get("color", Color(0.5, 0.5, 0.5))
	_player_owner = player_owner
	# H: start in the device's own language (a phone speaks touch from the
	# first tap) so the hint and the Place button never flip mid-placement.
	# I2: only before any real pointer was seen. Desktops report a touchscreen
	# too (mouse-to-touch emulation); a mouse user's last click already set
	# _uses_touch_input = false and must not get the touch UI flashed at them.
	if DisplayServer.is_touchscreen_available() and not _uses_touch_input and not _real_pointer_seen:
		_uses_touch_input = true
		input_mode_changed.emit(true)
	active = true
	visible = true
	set_process(true)
	_suspend_conflicting_world_input()
	set_process_input(true)
	set_process_unhandled_input(true)
	_ensure_placement_grid()
	_setup_ghost_sprite()
	cancel_touch_gesture()
	_preview_refresh_elapsed = 0.0
	# Always enter placement with a visible, validated preview in the current
	# view, instead of a stale ghost from the previous building or world origin.
	var view_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var center_world: Vector2 = get_canvas_transform().affine_inverse() * view_center
	update_preview_at_world(_find_initial_preview_position(center_world))


func _ensure_placement_grid() -> void:
	if _placement_grid == null:
		_placement_grid = PlacementGrid.new()
		_placement_grid.name = "PlacementGrid"
		# Terrain is -10. World objects use 0 and fog uses 10, so neither the
		# grid nor its color can reveal hidden resources/building occupancy.
		_placement_grid.z_as_relative = false
		_placement_grid.z_index = -5
		add_child(_placement_grid)
	_placement_grid.visible = true
	_grid_cache_valid = false


func _hide_placement_grid() -> void:
	if _placement_grid != null:
		_placement_grid.visible = false
		_placement_grid.segments.clear()
		_placement_grid.queue_redraw()
	_grid_tile_bounds = Rect2i()
	_grid_cache_valid = false


func _refresh_placement_grid(force: bool = false) -> void:
	if not active or _placement_grid == null:
		return
	var canvas: Transform2D = get_canvas_transform()
	var world_transform: Transform2D = _placement_grid.global_transform
	var view_rect: Rect2 = get_viewport().get_visible_rect()
	var preview_tile: Vector2i = _get_ghost_tile()
	if not force and _grid_cache_valid and canvas == _grid_canvas_transform and world_transform == _grid_world_transform and view_rect == _grid_view_rect and preview_tile == _grid_preview_tile:
		return
	_grid_preview_tile = preview_tile
	_grid_canvas_transform = canvas
	_grid_world_transform = world_transform
	_grid_view_rect = view_rect
	_grid_cache_valid = true
	_placement_grid.line_width = PLACEMENT_GRID_WIDTH_PX / maxf(0.01, canvas.x.length())
	var minimum := Vector2i(MapData.MAP_WIDTH, MapData.MAP_HEIGHT)
	var maximum := Vector2i(-1, -1)
	var inverse_canvas: Transform2D = canvas.affine_inverse()
	for corner: Vector2 in [view_rect.position, view_rect.position + Vector2(view_rect.size.x, 0.0), view_rect.end, view_rect.position + Vector2(0.0, view_rect.size.y)]:
		var tile: Vector2i = _world_to_tile(inverse_canvas * corner)
		minimum = minimum.min(tile - Vector2i.ONE)
		maximum = maximum.max(tile + Vector2i.ONE)
	# Keep only a one-tile placement guide around the candidate. The rest of
	# the battlefield remains unobscured at every screen size and zoom.
	minimum = minimum.max(preview_tile - Vector2i.ONE * PLACEMENT_GRID_MARGIN_TILES).max(Vector2i.ZERO)
	maximum = maximum.min(preview_tile + current_footprint - Vector2i.ONE + Vector2i.ONE * PLACEMENT_GRID_MARGIN_TILES).min(Vector2i(MapData.MAP_WIDTH - 1, MapData.MAP_HEIGHT - 1))
	var segments := PackedVector2Array()
	_grid_tile_bounds = Rect2i()
	if minimum.x <= maximum.x and minimum.y <= maximum.y:
		_grid_tile_bounds = Rect2i(minimum, maximum - minimum + Vector2i.ONE)
		# Half-cell corners come from the actual terrain projection. No
		# terrain/resource queries are needed for this uniform geometric grid.
		var origin: Vector2 = _tile_to_world(Vector2i.ZERO)
		var half_x: Vector2 = (_tile_to_world(Vector2i(1, 0)) - origin) * 0.5
		var half_y: Vector2 = (_tile_to_world(Vector2i(0, 1)) - origin) * 0.5
		var end: Vector2i = maximum + Vector2i.ONE
		for x: int in range(minimum.x, end.x + 1):
			segments.append(_placement_grid.to_local(_tile_to_world(Vector2i(x, minimum.y)) - half_x - half_y))
			segments.append(_placement_grid.to_local(_tile_to_world(Vector2i(x, end.y)) - half_x - half_y))
		for y: int in range(minimum.y, end.y + 1):
			segments.append(_placement_grid.to_local(_tile_to_world(Vector2i(minimum.x, y)) - half_x - half_y))
			segments.append(_placement_grid.to_local(_tile_to_world(Vector2i(end.x, y)) - half_x - half_y))
	_placement_grid.segments = segments
	_placement_grid.queue_redraw()


func _setup_ghost_sprite() -> void:
	# Remove old ghost sprite if any
	if _ghost_sprite != null:
		_ghost_sprite.queue_free()
		_ghost_sprite = null

	_ghost_sprite = Sprite2D.new()
	var tex_path: String = BuildingBase.get_sprite_texture_path(current_building_type, _player_owner)
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_ghost_sprite.texture = load(tex_path)
	BuildingBase.configure_art_sprite(_ghost_sprite, current_building_type, current_footprint)
	_ghost_sprite.position = BuildingBase.get_footprint_center_offset(current_footprint, get_parent())
	_ghost_art_rect = _ghost_sprite.get_rect()
	if _ghost_sprite.texture != null:
		var ink: Rect2 = KingdomArt.ink_rect(_ghost_sprite.texture)
		_ghost_art_rect = Rect2(_ghost_sprite.get_rect().position + Vector2(ink.position), Vector2(ink.size))
	_ghost_sprite.modulate = PREVIEW_VALID_TINT
	# Keep the exact cell edges and blocked marks readable over the translucent art.
	_ghost_sprite.show_behind_parent = true
	add_child(_ghost_sprite)


func has_assisted_preview() -> bool:
	return _assisted_preview_active


func _set_assisted_preview(value: bool) -> void:
	if _assisted_preview_active == value:
		return
	_assisted_preview_active = value
	assisted_preview_changed.emit(value)


## Explicit assistance changes only the preview. The normal confirmation path
## still revalidates current vision, terrain, clearance and available payment.
func find_visible_space(safe_rect: Rect2, occlusions: Array[Rect2]) -> bool:
	if not active or not safe_rect.has_area() or not safe_rect.position.is_finite() or not safe_rect.size.is_finite():
		return false
	var canvas: Transform2D = get_canvas_transform()
	var screen_anchor: Vector2 = canvas * ghost_position
	if not screen_anchor.is_finite():
		return false
	# An old preview can be outside a newly panned view. Search near the closest
	# current view point, never pan the camera or inspect the whole map.
	screen_anchor = screen_anchor.clamp(safe_rect.position, safe_rect.end)
	var world_anchor: Vector2 = canvas.affine_inverse() * screen_anchor
	var center: Vector2i = _world_to_tile(world_anchor)
	var candidates: Array[Dictionary] = []
	for dx: int in range(-FIND_SPACE_RADIUS, FIND_SPACE_RADIUS + 1):
		for dy: int in range(-FIND_SPACE_RADIUS, FIND_SPACE_RADIUS + 1):
			var tile: Vector2i = center + Vector2i(dx, dy)
			candidates.append({"tile": tile, "distance": (canvas * _tile_to_world(tile)).distance_squared_to(screen_anchor)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance: float = float(a["distance"])
		var b_distance: float = float(b["distance"])
		if a_distance != b_distance:
			return a_distance < b_distance
		var a_tile: Vector2i = a["tile"]
		var b_tile: Vector2i = b["tile"]
		return a_tile.x < b_tile.x if a_tile.x != b_tile.x else a_tile.y < b_tile.y
	)
	var previous_reason: String = _invalid_reason
	var previous_tiles: Array[Vector2i] = _invalid_tiles.duplicate()
	var previous_clearance_tiles: Array[Vector2i] = _clearance_tiles.duplicate()
	var previous_clearance_areas: Array[Rect2i] = _clearance_areas.duplicate()
	# H (G1 "No nearby space" over open ground): the first pass wants the whole
	# drawn building on screen and clear of every HUD panel; on a phone a
	# Barracks' art is taller than the free band. The second pass only needs
	# the footprint itself visible and its centre clear of the HUD.
	# One candidate budget covers both passes; the relaxed pass only visits
	# tiles the strict pass skipped.
	var examined: int = 0
	var strict_fit: Dictionary = {}
	var grazed: Variant = null
	for strict: bool in [true, false]:
		for candidate: Dictionary in candidates:
			var tile: Vector2i = candidate["tile"]
			if examined >= FIND_SPACE_MAX_CANDIDATES:
				break
			if not strict and strict_fit.has(tile):
				continue
			if not _find_space_fits_screen(tile, safe_rect, occlusions, strict):
				continue
			if strict:
				strict_fit[tile] = true
			examined += 1
			# This existing validator checks the WHOLE footprint's current visibility
			# before querying any terrain/occupancy. Do not prefilter hidden terrain.
			if not _check_footprint_validity(tile, current_footprint, _player_owner):
				continue
			# K: a sheep or deer grazing at the edge walks in a moment later and
			# Place then refuses ("Animal in the way"). Prefer quiet ground; a
			# spot beside animals is still better than none.
			if _wildlife_near_footprint(tile, current_footprint, 1):
				if grazed == null:
					grazed = tile
				continue
			return show_found_space(tile)
	if grazed != null and show_found_space(grazed as Vector2i):
		return true
	# A failed search must not replace the user's selected footprint or its
	# ordinary invalid-cell explanation with the last rejected candidate.
	_invalid_reason = previous_reason
	_invalid_tiles = previous_tiles
	_clearance_tiles = previous_clearance_tiles
	_clearance_areas = previous_clearance_areas
	return false


## K: shows a spot found away from the current view (Find's fallback beside
## your own buildings) exactly like an on-screen Find result: it must pass the
## same check Place uses, and it is held as an assisted preview so a mouse
## travelling to Place cannot drag it away. Returns false, leaving the current
## preview and its explanation, when the spot does not pass.
func show_found_space(tile: Vector2i) -> bool:
	if not active:
		return false
	if not _check_footprint_validity(tile, current_footprint, _player_owner):
		_refresh_preview_state(true)
		return false
	_set_assisted_preview(true)
	ghost_position = _tile_to_world(tile)
	global_position = ghost_position
	_refresh_preview_state(true)
	return is_valid_placement


## K: nearest spot Place accepts, ring by ring around your active Town
## Centers (then any of your buildings), for when nothing fits on screen and
## the tidy search beside same-kind buildings found nothing. Quiet ground
## (no animal within a tile) is preferred. Returns a tile or null.
func find_owned_space() -> Variant:
	if not active or not is_inside_tree():
		return null
	var found: Variant = _search_owned_space()
	if found == null:
		# The search leaves the last rejected candidate's explanation behind.
		_refresh_preview_state(true)
	return found


func _search_owned_space() -> Variant:
	var anchors: Array[Vector2i] = []
	var fallback_anchors: Array[Vector2i] = []
	for node: Node in get_tree().get_nodes_in_group("player_%d_buildings" % _player_owner):
		if not (node is BuildingBase) or (node as BuildingBase).state == BuildingBase.State.DESTROYED:
			continue
		var building := node as BuildingBase
		var center: Vector2i = _world_to_tile(building.global_position) + building.footprint / 2 - current_footprint / 2
		if building.building_type == BuildingData.BuildingType.TOWN_CENTER and building.state == BuildingBase.State.ACTIVE:
			anchors.append(center)
		elif fallback_anchors.is_empty():
			fallback_anchors.append(center)
	if anchors.is_empty():
		anchors = fallback_anchors
	var seen: Dictionary = {}
	var checks: int = 0
	var grazed: Variant = null
	for radius: int in range(FIND_OWNED_SPACE_RADIUS + 1):
		for anchor: Vector2i in anchors:
			for dx: int in range(-radius, radius + 1):
				for dy: int in range(-radius, radius + 1):
					if maxi(absi(dx), absi(dy)) != radius:
						continue
					var tile: Vector2i = anchor + Vector2i(dx, dy)
					if seen.has(tile):
						continue
					seen[tile] = true
					checks += 1
					if checks > FIND_OWNED_SPACE_MAX_CHECKS:
						return grazed
					if not _check_footprint_validity(tile, current_footprint, _player_owner):
						continue
					if _wildlife_near_footprint(tile, current_footprint, 1):
						if grazed == null:
							grazed = tile
						continue
					return tile
	return grazed


func _wildlife_near_footprint(origin: Vector2i, footprint: Vector2i, margin: int) -> bool:
	var game_map: Node = get_parent()
	if game_map == null or not game_map.has_method("get_wildlife_nodes"):
		return false
	var area := Rect2i(origin, footprint).grow(margin)
	var can_see: bool = game_map.has_method("is_tile_visible_to_player")
	for animal: Node2D in game_map.call("get_wildlife_nodes", ""):
		if not is_instance_valid(animal):
			continue
		var tile: Vector2i = _world_to_tile(animal.global_position)
		# Only animals the player can see may steer the choice (no fog oracle).
		if area.has_point(tile) and (not can_see or bool(game_map.call("is_tile_visible_to_player", tile, _player_owner))):
			return true
	return false


func _find_space_fits_screen(tile: Vector2i, safe_rect: Rect2, occlusions: Array[Rect2], strict: bool) -> bool:
	if strict:
		var bounds: Rect2 = _find_space_preview_screen_rect(tile)
		if not bounds.has_area() or not safe_rect.encloses(bounds):
			return false
		for obstacle: Rect2 in occlusions:
			if obstacle.has_area() and bounds.intersects(obstacle, true):
				return false
		return true
	var canvas: Transform2D = get_canvas_transform()
	var polygon: PackedVector2Array = _footprint_world_polygon(tile, current_footprint)
	var center := Vector2.ZERO
	for point: Vector2 in polygon:
		var screen: Vector2 = canvas * point
		if not screen.is_finite() or not safe_rect.has_point(screen):
			return false
		center += screen
	center /= float(maxi(1, polygon.size()))
	for obstacle: Rect2 in occlusions:
		if obstacle.has_area() and obstacle.has_point(center):
			return false
	return true


func _find_space_preview_screen_rect(tile: Vector2i) -> Rect2:
	var canvas: Transform2D = get_canvas_transform()
	var origin: Vector2 = _tile_to_world(tile)
	var points: Array[Vector2] = []
	points.assign(_footprint_world_polygon(tile, current_footprint))
	if _ghost_sprite != null and _ghost_sprite.texture != null:
		var art: Rect2 = _ghost_art_rect
		for corner: Vector2 in [art.position, art.position + Vector2(art.size.x, 0.0), art.end, art.position + Vector2(0.0, art.size.y)]:
			points.append(origin + _ghost_sprite.transform * corner)
	var minimum: Vector2 = canvas * points[0]
	var maximum: Vector2 = minimum
	for point: Vector2 in points:
		var screen: Vector2 = canvas * point
		if not screen.is_finite():
			return Rect2()
		minimum = minimum.min(screen)
		maximum = maximum.max(screen)
	# The short name and state badge belong to the preview too. Assistance must
	# not tuck them beneath HUD controls while the artwork itself happens to fit.
	minimum.y -= 24.0
	maximum.y += 28.0
	return Rect2(minimum, maximum - minimum).grow(FIND_SPACE_SCREEN_MARGIN)


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
		var art: Rect2 = _ghost_art_rect
		for corner: Vector2 in [art.position, art.position + Vector2(art.size.x, 0.0), art.end, art.position + Vector2(0.0, art.size.y)]:
			if not world_area.has_point(canvas * (world_pos + _ghost_sprite.transform * corner)):
				return false
	for point: Vector2 in _footprint_world_polygon(tile, current_footprint):
		if not world_area.has_point(canvas * point):
			return false
	return true


func cancel_placement() -> void:
	keep_placing_requested = false
	_set_assisted_preview(false)
	active = false
	_hide_placement_grid()
	visible = false
	current_building_type = -1
	set_process(false)
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
	_touch_starts.clear()
	_ghost_grabs.clear()
	_ghost_dragging.clear()
	_touch_camera_gesture = false


func _input(event: InputEvent) -> void:
	_observe_input_mode(event)
	# A world finger can lift over a HUD Control, which owns the release before
	# unhandled input. Only clear ownership here: never move or confirm a ghost.
	if active and event is InputEventScreenTouch and event.device != InputEvent.DEVICE_ID_EMULATION:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			if _touch_points.has(touch.index):
				_released_touch_inputs[touch.index] = _touch_camera_gesture
				# This record belongs only to this input dispatch. A GUI-consumed
				# release must not accumulate stale increasing browser touch IDs.
				call_deferred("_clear_released_touch_inputs")
			_touch_points.erase(touch.index)
			if _touch_points.is_empty():
				_touch_camera_gesture = false


func uses_touch_input() -> bool:
	return _uses_touch_input


func _observe_input_mode(event: InputEvent) -> void:
	# Both touch-to-mouse and mouse-to-touch emulation are enabled. Synthesized
	# events must never change the instructions or confirmation workflow.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var uses_touch: bool = _uses_touch_input
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		uses_touch = true
		_real_pointer_seen = true
	elif event is InputEventMouseButton and event.pressed:
		uses_touch = false
		_real_pointer_seen = true
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative != Vector2.ZERO:
		uses_touch = false
	if uses_touch == _uses_touch_input:
		return
	_uses_touch_input = uses_touch
	queue_redraw()
	input_mode_changed.emit(uses_touch)


func _clear_released_touch_inputs() -> void:
	_released_touch_inputs.clear()
	# A finger whose release a HUD Control consumed leaves no other trace.
	for index: Variant in _touch_starts.keys():
		if not _touch_points.has(index):
			_touch_starts.erase(index)
			_ghost_grabs.erase(index)
			_ghost_dragging.erase(index)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	_observe_input_mode(event)

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
			# A mouse builds where it clicks; the ghost already follows it there.
			update_preview_centered_at_screen(mb.position)
			# AoE2 idiom: Shift+click builds and keeps the same building in hand.
			keep_placing_requested = mb.shift_pressed
			confirm_preview()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_released_touch_inputs.erase(touch.index)
			_touch_points[touch.index] = touch.position
			_touch_starts[touch.index] = touch.position
			if _touch_points.size() > 1:
				_touch_camera_gesture = true
				_ghost_grabs.clear()
				_ghost_dragging.clear()
			elif is_screen_point_on_ghost(touch.position):
				# The finger landed on the ghost: it may carry it or tap it.
				var finger_world: Vector2 = get_canvas_transform().affine_inverse() * touch.position
				_ghost_grabs[touch.index] = ghost_position - finger_world
		else:
			var owned_press: bool = _touch_points.has(touch.index) or _released_touch_inputs.has(touch.index)
			var was_camera_gesture: bool = bool(_released_touch_inputs.get(touch.index, _touch_camera_gesture))
			var start: Vector2 = _touch_starts.get(touch.index, Vector2(INF, INF))
			var grabbed: bool = _ghost_grabs.has(touch.index)
			var dragged_ghost: bool = bool(_ghost_dragging.get(touch.index, false))
			_touch_starts.erase(touch.index)
			_released_touch_inputs.erase(touch.index)
			_touch_points.erase(touch.index)
			_ghost_grabs.erase(touch.index)
			_ghost_dragging.erase(touch.index)
			if _touch_points.is_empty():
				_touch_camera_gesture = false
			var is_tap: bool = start.distance_to(touch.position) < TAP_TO_PLACE_SLOP_PX
			if not touch.canceled and not was_camera_gesture and owned_press and not dragged_ghost and is_tap and _touch_points.is_empty():
				if grabbed:
					# Tap on the ghost: build it exactly where it is drawn.
					confirm_preview()
				else:
					# Tap elsewhere: the ghost moves there. It never builds.
					update_preview_centered_at_screen(touch.position)
			# The camera must still see this release, or it keeps a stuck finger.
		# Camera needs touch presses/releases to recognize the second finger.
		# Selection is suspended, so these events cannot issue unit commands.
		return

	if event is InputEventScreenDrag:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var drag := event as InputEventScreenDrag
		# A finger that began on GUI belongs to GUI until it lifts. Receiving a
		# drag outside that Control does not grant placement or camera ownership.
		if not _touch_points.has(drag.index):
			return
		_touch_points[drag.index] = drag.position
		if _touch_points.size() > 1:
			_touch_camera_gesture = true
			_ghost_grabs.clear()
			_ghost_dragging.clear()
			# GameMap owns midpoint pan and anchored pinch as one gesture.
			return
		if _touch_camera_gesture or not _ghost_grabs.has(drag.index):
			# A drag that did not start on the ghost pans the map (GameMap).
			return
		var start: Vector2 = _touch_starts.get(drag.index, drag.position)
		if not bool(_ghost_dragging.get(drag.index, false)) and start.distance_to(drag.position) < GHOST_DRAG_SLOP_PX:
			get_viewport().set_input_as_handled()
			return
		_ghost_dragging[drag.index] = true
		var finger_world: Vector2 = get_canvas_transform().affine_inverse() * drag.position
		update_preview_at_world(finger_world + (_ghost_grabs[drag.index] as Vector2))
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var motion := event as InputEventMouseMotion
		# L2: no Place button waits at the bottom any more, so a found spot is
		# not held: the ghost always follows a real mouse.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			return
		update_preview_centered_at_screen(motion.position)
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
	_refresh_placement_grid()
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


## L2: the footprint's centre goes under the finger or cursor (the anchor
## tile is the footprint's top corner, which sat visibly off to one side).
func update_preview_centered_at_screen(screen_pos: Vector2) -> void:
	if not active:
		return
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	update_preview_at_world(world_pos - _footprint_center_offset())


func _footprint_center_offset() -> Vector2:
	var origin: Vector2 = _tile_to_world(Vector2i.ZERO)
	var axis_x: Vector2 = _tile_to_world(Vector2i(1, 0)) - origin
	var axis_y: Vector2 = _tile_to_world(Vector2i(0, 1)) - origin
	return (axis_x * float(current_footprint.x - 1) + axis_y * float(current_footprint.y - 1)) * 0.5


## Screen rectangle of everything drawn for the ghost: the footprint and the
## building art. Empty when no ghost is shown.
func get_ghost_screen_rect() -> Rect2:
	if not active:
		return Rect2()
	return _screen_rect_for(_get_ghost_tile(), ghost_position)


## Same rectangle for a footprint at `tile` (the art of the current type).
func _screen_rect_for(tile: Vector2i, anchor_world: Vector2) -> Rect2:
	var canvas: Transform2D = get_canvas_transform()
	var points: Array[Vector2] = []
	points.assign(_footprint_world_polygon(tile, current_footprint))
	if _ghost_sprite != null and _ghost_sprite.texture != null:
		var art: Rect2 = _ghost_art_rect
		for corner: Vector2 in [art.position, art.position + Vector2(art.size.x, 0.0), art.end, art.position + Vector2(0.0, art.size.y)]:
			points.append(anchor_world + _ghost_sprite.transform * corner)
	var minimum: Vector2 = canvas * points[0]
	var maximum: Vector2 = minimum
	for point: Vector2 in points:
		var screen: Vector2 = canvas * point
		if not screen.is_finite():
			return Rect2()
		minimum = minimum.min(screen)
		maximum = maximum.max(screen)
	return Rect2(minimum, maximum - minimum)


## Screen bounds of the footprint diamond alone (the ground it will take).
func get_ghost_footprint_screen_rect() -> Rect2:
	if not active:
		return Rect2()
	var canvas: Transform2D = get_canvas_transform()
	var polygon: PackedVector2Array = _footprint_world_polygon(_get_ghost_tile(), current_footprint)
	var rect := Rect2(canvas * polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		rect = rect.expand(canvas * point)
	return rect


## True when a screen point lands on the drawn ghost (art or footprint).
func is_screen_point_on_ghost(screen_pos: Vector2) -> bool:
	if not active:
		return false
	var canvas: Transform2D = get_canvas_transform()
	# The drawn walls (their inked bounds, not the transparent texture)...
	if _ghost_sprite != null and _ghost_sprite.texture != null:
		var art: Rect2 = _ghost_art_rect
		var first: Vector2 = canvas * (ghost_position + _ghost_sprite.transform * art.position)
		var art_rect := Rect2(first, Vector2.ZERO).expand(canvas * (ghost_position + _ghost_sprite.transform * art.end))
		if art_rect.grow(GHOST_HIT_MARGIN_PX).has_point(screen_pos):
			return true
	# ...or the ground diamond it will take.
	var polygon := PackedVector2Array()
	var center := Vector2.ZERO
	for point: Vector2 in _footprint_world_polygon(_get_ghost_tile(), current_footprint):
		polygon.append(canvas * point)
		center += canvas * point
	center /= float(maxi(1, polygon.size()))
	for index: int in polygon.size():
		# Grow the diamond a little so its tips stay easy to hit.
		var away: Vector2 = polygon[index] - center
		polygon[index] += away.normalized() * GHOST_HIT_MARGIN_PX
	return Geometry2D.is_point_in_polygon(screen_pos, polygon)


## Shift+click asked to keep the same building in hand after this one.
var keep_placing_requested: bool = false


func consume_keep_placing() -> bool:
	var value: bool = keep_placing_requested
	keep_placing_requested = false
	return value


func update_preview_at_world(world_pos: Vector2) -> void:
	_set_assisted_preview(false)
	if not active:
		return
	# Snap to tile grid
	ghost_position = _snap_to_grid(world_pos)
	global_position = ghost_position
	_refresh_preview_state(true)


func _update_ghost_position(screen_pos: Vector2) -> void:
	update_preview_at_screen(screen_pos)


func _refresh_preview_state(force_signal: bool = false) -> void:
	_refresh_placement_grid()
	var was_valid: bool = is_valid_placement
	var previous_hint: String = get_preview_hint()
	is_valid_placement = _check_validity()
	_trade_preview.clear()
	if is_valid_placement and current_building_type == BuildingData.BuildingType.TRADE_POST:
		var towns: Array = []
		for node: Node in get_tree().get_nodes_in_group("buildings"):
			if node is BuildingBase and get_parent().is_ancestor_of(node) and node.building_type == BuildingData.BuildingType.TOWN_CENTER and node.player_owner == _player_owner:
				towns.append({"position": node.global_position, "owner": node.player_owner, "active": node.state == BuildingBase.State.ACTIVE})
		# Geometry only. Looking for a path here could disclose unseen blockades.
		_trade_preview = TRADE_PREVIEW.candidate(ghost_position, _player_owner, towns)

	# Update ghost sprite tint
	if _ghost_sprite != null:
		if is_valid_placement:
			_ghost_sprite.modulate = PREVIEW_VALID_TINT
		else:
			_ghost_sprite.modulate = PREVIEW_INVALID_TINT

	queue_redraw()
	if force_signal or was_valid != is_valid_placement or previous_hint != get_preview_hint():
		preview_changed.emit(is_valid_placement, get_preview_hint())


func get_preview_hint() -> String:
	if not is_valid_placement:
		return get_invalid_reason()
	if current_building_type != BuildingData.BuildingType.TRADE_POST:
		return ""
	if not _trade_preview.get("has_town_center", false):
		return "Needs a Town Center"
	if not _trade_preview.get("usable_distance", false):
		return "Move farther from town"
	return "Up to %d gold / trip · clear road needed" % int(_trade_preview.get("payout", 0))


## Called by the explicit touch Place action. Always revalidates the footprint.
func confirm_preview() -> bool:
	if not active:
		return false
	# A second confirm right after a placement (a double tap that reached a new
	# ghost) must not buy another building.
	if _uses_touch_input and Time.get_ticks_msec() - _last_confirm_msec < CONFIRM_DEBOUNCE_MSEC:
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
		_clearance_tiles.clear()
		_clearance_areas.clear()
		return false
	# Round 2 E: a kingdom holds a limited number of some buildings (three
	# Town Centers). Foundations count; ruins do not.
	var max_count: int = BuildingData.get_max_count(building_type)
	if max_count > 0:
		var owned: int = 0
		for building: Node in get_tree().get_nodes_in_group("player_%d_buildings" % player_owner):
			if building is BuildingBase and (building as BuildingBase).building_type == building_type and (building as BuildingBase).state != BuildingBase.State.DESTROYED:
				owned += 1
		if owned >= max_count:
			_invalid_reason = "Limit reached: %d %ss" % [max_count, str(stats.get("name", "building"))]
			_invalid_tiles.clear()
			_clearance_tiles.clear()
			_clearance_areas.clear()
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
	_clearance_tiles.clear()
	_clearance_areas.clear()
	var has_buildable_check: bool = false
	var has_walkable_check: bool = false
	var game_map := get_parent()
	if game_map:
		has_buildable_check = game_map.has_method("is_tile_buildable")
		has_walkable_check = game_map.has_method("is_tile_walkable")

	# Bounds and visibility are checked in separate passes before terrain or
	# occupancy. If any part of the footprint is outside current vision, return a
	# single visibility-only result and never query hidden walkability/buildings. This
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
	# L2 (after L1's coast rim): the sandy bank is drawn over the outermost
	# tile ring, so a building there would sit half in the sea. The map edge
	# is public, so this reads nothing hidden.
	for dx in footprint.x:
		for dy in footprint.y:
			var edge_tile := tile_origin + Vector2i(dx, dy)
			if edge_tile.x == 0 or edge_tile.y == 0 or edge_tile.x == MapData.MAP_WIDTH - 1 or edge_tile.y == MapData.MAP_HEIGHT - 1:
				if _invalid_reason == "":
					_invalid_reason = SHORE_INVALID_REASON
				_invalid_tiles.append(edge_tile)
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
			_invalid_reason = FOG_INVALID_REASON
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

	_mark_wildlife_conflicts(tile_origin, footprint)
	_mark_owned_clearance_conflicts(tile_origin, footprint, player_owner)
	return _invalid_tiles.is_empty()


## G1: a footprint over an animal or carcass with food left would bury it (and
## any villager working it) inside the walls. The footprint is fully visible
## here, so this reads nothing hidden.
func _mark_wildlife_conflicts(origin: Vector2i, footprint: Vector2i) -> void:
	var game_map: Node = get_parent()
	if game_map == null or not game_map.has_method("get_wildlife_nodes"):
		return
	var area := Rect2i(origin, footprint)
	for animal: Node2D in game_map.call("get_wildlife_nodes", ""):
		if not is_instance_valid(animal):
			continue
		var tile: Vector2i = _world_to_tile(animal.global_position)
		if not area.has_point(tile):
			continue
		if _invalid_reason == "":
			_invalid_reason = "Animal in the way"
		if tile not in _invalid_tiles:
			_invalid_tiles.append(tile)


func _mark_owned_clearance_conflicts(origin: Vector2i, footprint: Vector2i, owner: int) -> void:
	var map_node: Node = get_parent()
	if map_node == null or not is_inside_tree():
		return
	var candidate := Rect2i(origin, footprint)
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is BuildingBase) or not map_node.is_ancestor_of(node):
			continue
		var building := node as BuildingBase
		if building.player_owner != owner or building.state == BuildingBase.State.DESTROYED:
			continue
		# Owned locations are already known. No enemy or hidden terrain is read.
		var occupied := Rect2i(_world_to_tile(building.global_position), building.footprint)
		var protected_ground := occupied.grow(BuildingData.BUILDING_CLEARANCE_TILES)
		if not candidate.intersects(protected_ground):
			continue
		_clearance_areas.append(protected_ground)
		if _invalid_reason == "":
			_invalid_reason = "Leave 1 tile between buildings for a path"
		for dx: int in footprint.x:
			for dy: int in footprint.y:
				var tile: Vector2i = origin + Vector2i(dx, dy)
				if protected_ground.has_point(tile) and tile not in _invalid_tiles:
					_invalid_tiles.append(tile)
					if not occupied.has_point(tile):
						_clearance_tiles.append(tile)


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
	HAPTICS.refuse()
	AudioManager.play_sfx("building_invalid")


func _confirm_placement() -> void:
	if not active:
		return
	# Input may arrive a frame after the green preview was calculated. Recheck
	# fog, terrain, and occupancy before emitting any gameplay-side request.
	is_valid_placement = _check_validity()
	if not is_valid_placement:
		if _ghost_sprite != null:
			_ghost_sprite.modulate = PREVIEW_INVALID_TINT
		queue_redraw()
		preview_changed.emit(false, get_invalid_reason())
		_emit_invalid_feedback()
		return
	var pos := ghost_position
	_last_confirm_msec = Time.get_ticks_msec()
	_set_assisted_preview(false)
	active = false
	_hide_placement_grid()
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	cancel_touch_gesture()
	_restore_conflicting_world_input()
	if _ghost_sprite != null:
		_ghost_sprite.queue_free()
		_ghost_sprite = null
	HAPTICS.tap()
	placement_confirmed.emit(current_building_type, pos)
	AudioManager.play_sfx("building_place")
	current_building_type = -1
	queue_redraw()


func _footprint_world_polygon(origin: Vector2i, footprint: Vector2i) -> PackedVector2Array:
	# Derive all corners from the terrain's real basis, including its layout and
	# half-cell origin. The same polygon serves drawing and assisted-placement bounds.
	var center: Vector2 = _tile_to_world(origin)
	var axis_x: Vector2 = _tile_to_world(origin + Vector2i(1, 0)) - center
	var axis_y: Vector2 = _tile_to_world(origin + Vector2i(0, 1)) - center
	var first: Vector2 = center - (axis_x + axis_y) * 0.5
	return PackedVector2Array([first, first + axis_x * footprint.x, first + axis_x * footprint.x + axis_y * footprint.y, first + axis_y * footprint.y])


func _footprint_local_polygon(origin: Vector2i, footprint: Vector2i) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in _footprint_world_polygon(origin, footprint):
		points.append(to_local(point))
	return points


func get_preview_state_label() -> String:
	if is_valid_placement:
		if current_building_type == BuildingData.BuildingType.TRADE_POST:
			if not _trade_preview.get("has_town_center", false):
				return "Needs town"
			if not _trade_preview.get("usable_distance", false):
				return "Too near town"
			return "Up to %d gold" % int(_trade_preview.get("payout", 0))
		return "Fits"
	if _invalid_reason == FOG_INVALID_REASON:
		return "Needs sight"
	if not _clearance_tiles.is_empty() and _clearance_tiles.size() == _invalid_tiles.size():
		return "Keep a path gap"
	return "Blocked"


func _draw_polygon_edges(points: PackedVector2Array, color: Color, width: float, dashed: bool = false) -> void:
	for i: int in points.size():
		if dashed:
			draw_dashed_line(points[i], points[(i + 1) % points.size()], color, width, width * 3.0)
		else:
			draw_line(points[i], points[(i + 1) % points.size()], color, width, true)


func _draw() -> void:
	if not active:
		return
	var origin_tile: Vector2i = _get_ghost_tile()
	var pixel: float = 1.0 / maxf(0.01, get_global_transform_with_canvas().x.length())
	# Mark collision cells within the proposed footprint only. Drawing entire
	# neighboring clearance rings made the candidate boundary ambiguous.
	for dx: int in current_footprint.x:
		for dy: int in current_footprint.y:
			var tile: Vector2i = origin_tile + Vector2i(dx, dy)
			var points: PackedVector2Array = _footprint_local_polygon(tile, Vector2i.ONE)
			var invalid: bool = tile in _invalid_tiles
			var clearance: bool = tile in _clearance_tiles
			var color: Color = FOOTPRINT_VALID if not invalid else (FOOTPRINT_GOLD if clearance else FOOTPRINT_BLOCKED)
			draw_colored_polygon(points, Color(color, 0.18 if invalid else (0.20 if is_valid_placement else 0.08)))
			_draw_polygon_edges(points, Color(color, 0.88 if invalid else 0.50), (1.4 if invalid else 0.75) * pixel, clearance)
			if invalid:
				var center: Vector2 = to_local(_tile_to_world(tile))
				# A double bar means reserved path spacing; an X means blocked
				# ground. Both remain readable without interpreting tint alone.
				if clearance:
					for y: float in [-2.5, 2.5]:
						draw_line(center + Vector2(-5.0, y) * pixel, center + Vector2(5.0, y) * pixel, FOOTPRINT_INK, 2.0 * pixel, true)
				else:
					draw_line(center + Vector2(-5, -5) * pixel, center + Vector2(5, 5) * pixel, FOOTPRINT_INK, 2.0 * pixel, true)
					draw_line(center + Vector2(-5, 5) * pixel, center + Vector2(5, -5) * pixel, FOOTPRINT_INK, 2.0 * pixel, true)
	var boundary: PackedVector2Array = _footprint_local_polygon(origin_tile, current_footprint)
	_draw_polygon_edges(boundary, FOOTPRINT_VALID if is_valid_placement else FOOTPRINT_BLOCKED, 2.2 * pixel)
	var bounds := Rect2(boundary[0], Vector2.ZERO)
	for point: Vector2 in boundary:
		bounds = bounds.expand(point)
	var center: Vector2 = bounds.get_center()
	var font: Font = KingdomTheme.FONT_MEDIUM
	var font_size: int = maxi(1, roundi(14.0 * pixel))
	var name_text: String = BuildingData.get_building_name(current_building_type)
	var label_y: float = bounds.position.y - 10.0 * pixel
	if _ghost_sprite != null:
		label_y = minf(label_y, (_ghost_sprite.transform * _ghost_art_rect).position.y - 10.0 * pixel)
	_draw_preview_label(font, font_size, name_text, Vector2(center.x, label_y), FOOTPRINT_INK, pixel)
	if _uses_touch_input:
		# L2: on touch the Build button attached under the ghost carries the
		# state ("Build" or the reason), so the ground stays uncluttered.
		return
	var trade_warning: bool = is_valid_placement and current_building_type == BuildingData.BuildingType.TRADE_POST and not _trade_preview.get("usable_distance", false)
	_draw_preview_label(font, font_size, get_preview_state_label(), Vector2(center.x, bounds.end.y + 20.0 * pixel), FOOTPRINT_GOLD if trade_warning else FOOTPRINT_INK, pixel)
	if is_valid_placement and current_building_type != BuildingData.BuildingType.TRADE_POST:
		var tick_center := Vector2(center.x - 24.0 * pixel, bounds.end.y + 15.0 * pixel)
		draw_line(tick_center + Vector2(-4, 0) * pixel, tick_center + Vector2(-1, 3) * pixel, FOOTPRINT_INK, 2.2 * pixel, true)
		draw_line(tick_center + Vector2(-1, 3) * pixel, tick_center + Vector2(5, -4) * pixel, FOOTPRINT_INK, 2.2 * pixel, true)


func _draw_preview_label(font: Font, font_size: int, text: String, anchor: Vector2, color: Color, pixel: float) -> void:
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var position: Vector2 = anchor - Vector2(text_size.x * 0.5, 0.0)
	draw_string_outline(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(1, roundi(3.0 * pixel)), Color("1d302c"))
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
