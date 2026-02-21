class_name SelectionManager
extends Node2D
## Handles unit and building selection via tap, drag-box, and double-tap.
## Issues move/attack commands based on what is tapped while units are selected.

## Emitted when the selection set changes.
signal selection_changed(selected_units: Array[Node2D])
## Emitted when a move command is issued to a tile.
signal move_command(target_tile: Vector2i)
## Emitted when an attack command is issued against a target.
signal attack_command(target: Node2D)
## Emitted when a gather command is issued on a resource node.
signal gather_command(resource_node: Node2D)
## Emitted when a build command is issued on a construction site.
signal build_command(building: Node2D)

## Currently selected units/buildings.
var selected: Array[Node2D] = []

## Reference to the game_map node (set externally by GameMap).
var game_map: Node2D = null

## --- Drag-box state ---
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_end := Vector2.ZERO
var _drag_threshold := 10.0  # Minimum pixels to count as a drag, not a tap.

## --- Double-tap detection ---
var _last_tap_time := 0.0
var _last_tap_position := Vector2.ZERO
var _double_tap_interval := 0.35  # seconds
var _double_tap_radius := 30.0  # pixels

## Visual drag-box rectangle.
var _drag_rect: Rect2 = Rect2()

## --- Touch long-press context ---
enum TouchContextAction { MOVE = 100, ATTACK = 101, GATHER = 102, BUILD = 103, SELECT = 104, CLEAR = 105 }
var _touch_hold_active := false
var _touch_hold_elapsed := 0.0
@export var touch_context_enabled: bool = true
@export var long_press_threshold: float = 0.35
@export var touch_pan_threshold: float = 18.0
var _long_press_move_tolerance := 16.0  # pixels
var _touch_pan_gesture := false
var _touch_context_open := false
var _touch_context_menu: PopupMenu = null
var _context_world_pos := Vector2.ZERO
var _context_target: Node2D = null
var _context_resource: Node2D = null
var _active_touch_indices: Dictionary = {}


func _ready() -> void:
	set_process_unhandled_input(true)
	set_process(true)
	if touch_context_enabled:
		_ensure_touch_context_menu()


func _process(delta: float) -> void:
	if not touch_context_enabled or not _touch_hold_active:
		return
	if _drag_start.distance_to(_drag_end) > _long_press_move_tolerance:
		_touch_hold_active = false
		return
	_touch_hold_elapsed += delta
	if _touch_hold_elapsed >= long_press_threshold:
		_touch_hold_active = false
		_is_dragging = false
		queue_redraw()
		_open_touch_context(_drag_end)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _is_dragging:
		_handle_mouse_motion(event as InputEventMouseMotion)


## --- Touch input (mobile) ---

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_active_touch_indices[event.index] = true
		if _active_touch_indices.size() > 1:
			_touch_pan_gesture = true
			_touch_hold_active = false
			_is_dragging = false
		if event.index != 0:
			return
		_hide_touch_context()
		_drag_start = event.position
		_drag_end = event.position
		_touch_pan_gesture = false
		_touch_hold_active = touch_context_enabled
		_touch_hold_elapsed = 0.0
	else:
		_active_touch_indices.erase(event.index)
		if event.index != 0:
			return
		_touch_hold_active = false
		if _touch_context_open:
			_is_dragging = false
			queue_redraw()
			return
		var drag_distance := _drag_start.distance_to(event.position)
		if _active_touch_indices.is_empty() and not _touch_pan_gesture and drag_distance < _drag_threshold:
			_handle_tap(event.position, true)
		_touch_pan_gesture = false
		queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if _touch_context_open:
		return
	if event.index != 0:
		_touch_pan_gesture = true
		_touch_hold_active = false
		return
	_drag_end = event.position
	if _active_touch_indices.size() > 1:
		_touch_pan_gesture = true
		_touch_hold_active = false
		queue_redraw()
		return
	var drag_distance := _drag_start.distance_to(_drag_end)
	if drag_distance > touch_pan_threshold:
		_touch_pan_gesture = true
	if _touch_hold_active and drag_distance > _long_press_move_tolerance:
		_touch_hold_active = false
	queue_redraw()


## --- Mouse input (desktop / testing) ---

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if not event.pressed and selected.size() > 0:
			_handle_right_click(event.position)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_hide_touch_context()
		_drag_start = event.position
		_drag_end = event.position
		_is_dragging = true
	else:
		_is_dragging = false
		var drag_distance := _drag_start.distance_to(event.position)
		if drag_distance < _drag_threshold:
			_handle_tap(event.position, false)
		else:
			_drag_end = event.position
			_finish_drag_select()
		queue_redraw()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_drag_end = event.position
	queue_redraw()


## --- Tap / click logic ---

func _handle_tap(screen_pos: Vector2, is_touch_input: bool) -> void:
	var consumed: bool = false
	# Check double-tap.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_tap_time < _double_tap_interval \
			and screen_pos.distance_to(_last_tap_position) < _double_tap_radius:
		_handle_double_tap(screen_pos)
		_last_tap_time = 0.0
		if is_touch_input:
			get_viewport().set_input_as_handled()
		return
	_last_tap_time = now
	_last_tap_position = screen_pos

	var world_pos := _screen_to_world(screen_pos)

	# Check if we tapped on a unit or building.
	var tapped_node: Node2D = _get_node_at(world_pos)
	var resource_node: Node2D = _get_resource_at(world_pos)

	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)

	if tapped_node != null:
		if selected.size() > 0 and _is_enemy(tapped_node):
			# Attack command.
			attack_command.emit(tapped_node)
			consumed = true
		elif _has_selected_villagers() and _is_under_construction(tapped_node):
			# Send selected villagers to build.
			build_command.emit(tapped_node)
			consumed = true
		elif shift_held and not _is_enemy(tapped_node):
			# Shift+click: add/remove from selection
			if tapped_node in selected:
				_remove_from_selection(tapped_node)
			else:
				_add_to_selection(tapped_node)
			consumed = true
		else:
			# Select the tapped unit/building.
			_clear_selection()
			_add_to_selection(tapped_node)
			consumed = true
		if consumed and is_touch_input:
			get_viewport().set_input_as_handled()
		return

	if resource_node != null:
		if _has_selected_villagers():
			# Touch parity: villagers can gather by tapping a resource target.
			gather_command.emit(resource_node)
			consumed = true
		elif selected.is_empty():
			_clear_selection()
			_add_to_selection(resource_node)
			consumed = true
		if consumed and is_touch_input:
			get_viewport().set_input_as_handled()
		return

	if is_touch_input and selected.size() > 0:
		# Touch parity: tapping empty ground while selected issues a move command.
		var tile_pos := _world_to_tile(world_pos)
		move_command.emit(tile_pos)
		consumed = true
	elif not shift_held:
		# Desktop left click keeps deselect behavior.
		if not is_touch_input:
			_clear_selection()
			consumed = true
	if consumed and is_touch_input:
		get_viewport().set_input_as_handled()


func _handle_double_tap(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	var tapped_node: Node2D = _get_node_at(world_pos)
	if tapped_node == null:
		return

	# Select all own units of the same type that are visible on screen.
	var unit_type: String = ""
	if tapped_node.has_method("get_unit_type"):
		unit_type = tapped_node.get_unit_type()
	elif tapped_node.has_meta("unit_type"):
		unit_type = tapped_node.get_meta("unit_type")
	else:
		return

	_clear_selection()

	for node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		if _is_enemy(node as Node2D):
			continue
		var n_type := ""
		if node.has_method("get_unit_type"):
			n_type = node.get_unit_type()
		elif node.has_meta("unit_type"):
			n_type = node.get_meta("unit_type")
		if n_type == unit_type and _is_on_screen(node as Node2D):
			_add_to_selection(node as Node2D)


## --- Drag-box selection ---

func _finish_drag_select() -> void:
	_drag_rect = Rect2(_drag_start, _drag_end - _drag_start).abs()
	_clear_selection()

	for node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var screen_pos := _world_to_screen((node as Node2D).global_position)
		if _drag_rect.has_point(screen_pos):
			# Only select own units during drag.
			if not _is_enemy(node as Node2D):
				_add_to_selection(node as Node2D)
	_drag_rect = Rect2()


## --- Selection management ---

func _clear_selection() -> void:
	for node in selected:
		if node.has_method("deselect"):
			node.deselect()
	selected.clear()
	selection_changed.emit(selected)


func _add_to_selection(node: Node2D) -> void:
	if node not in selected:
		selected.append(node)
		if node.has_method("select"):
			node.select()
	selection_changed.emit(selected)


func _remove_from_selection(node: Node2D) -> void:
	if node in selected:
		selected.erase(node)
		if node.has_method("deselect"):
			node.deselect()
		selection_changed.emit(selected)


func select_all_own_units() -> void:
	_clear_selection()
	for node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		if not _is_enemy(node as Node2D):
			_add_to_selection(node as Node2D)


func deselect_all() -> void:
	_clear_selection()


## --- Coordinate helpers ---

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos


func _world_to_screen(world_pos: Vector2) -> Vector2:
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	return canvas_transform * world_pos


func _world_to_tile(world_pos: Vector2) -> Vector2i:
	if game_map != null and game_map.has_method("world_to_tile"):
		return game_map.world_to_tile(world_pos)
	# Convert world position to isometric tile coordinates.
	# Standard isometric formula: tile_x = (world_x / (TILE_WIDTH/2) + world_y / (TILE_HEIGHT/2)) / 2
	var half_w := float(MapData.TILE_WIDTH) / 2.0
	var half_h := float(MapData.TILE_HEIGHT) / 2.0
	var tile_x := int((world_pos.x / half_w + world_pos.y / half_h) / 2.0)
	var tile_y := int((world_pos.y / half_h - world_pos.x / half_w) / 2.0)
	return Vector2i(tile_x, tile_y)


## Find a node2D at a world position (checks units first with tighter radius, then buildings).
func _get_node_at(world_pos: Vector2) -> Node2D:
	# Check units first with a tight radius so clicking near units registers ground clicks.
	var best_unit: Node2D = null
	var best_unit_dist := 20.0
	for node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var dist := (node as Node2D).global_position.distance_to(world_pos)
		if dist < best_unit_dist:
			best_unit_dist = dist
			best_unit = node as Node2D
	if best_unit != null:
		return best_unit

	# Then check buildings with a wider radius.
	var best_building: Node2D = null
	var best_building_dist := 36.0
	for node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var dist := (node as Node2D).global_position.distance_to(world_pos)
		if dist < best_building_dist:
			best_building_dist = dist
			best_building = node as Node2D
	return best_building


## Find a resource node at a world position (checks "resources" group).
func _get_resource_at(world_pos: Vector2) -> Node2D:
	var best_node: Node2D = null
	var best_dist := 28.0  # Max click distance for resources.
	for node in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var dist := (node as Node2D).global_position.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best_node = node as Node2D
	return best_node


## Check if a unit belongs to the enemy (not our player).
func _is_enemy(node: Node2D) -> bool:
	if node.has_method("get_player_id"):
		return node.get_player_id() != 0  # Assume local player = 0.
	if node.has_meta("player_id"):
		return node.get_meta("player_id") != 0
	return false


## Check if a node2D is visible on the current screen.
func _is_on_screen(node: Node2D) -> bool:
	var screen_pos := _world_to_screen(node.global_position)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return screen_pos.x >= 0 and screen_pos.x <= viewport_size.x \
		and screen_pos.y >= 0 and screen_pos.y <= viewport_size.y


## --- Right-click command ---

func _handle_right_click(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)

	# Check for enemy target → attack
	var tapped_node: Node2D = _get_node_at(world_pos)
	if tapped_node != null and _is_enemy(tapped_node):
		attack_command.emit(tapped_node)
		return

	# Check for construction site + villagers → build command
	if tapped_node != null and _has_selected_villagers() and _is_under_construction(tapped_node):
		build_command.emit(tapped_node)
		return

	# Check for resource node → gather command
	var resource_node: Node2D = _get_resource_at(world_pos)
	if resource_node != null:
		gather_command.emit(resource_node)
		return

	# Empty ground → move command
	var tile_pos := _world_to_tile(world_pos)
	move_command.emit(tile_pos)


## --- Selection helpers ---

func _has_selected_villagers() -> bool:
	for node in selected:
		if node is Villager:
			return true
	return false


func _is_under_construction(node: Node2D) -> bool:
	if node is BuildingBase:
		var b := node as BuildingBase
		return b.state == BuildingBase.State.CONSTRUCTING and not _is_enemy(node)
	return false


## --- Touch context menu ---

func _ensure_touch_context_menu() -> void:
	if _touch_context_menu != null:
		return
	_touch_context_menu = PopupMenu.new()
	_touch_context_menu.name = "TouchContextMenu"
	_touch_context_menu.hide_on_item_selection = true
	_touch_context_menu.id_pressed.connect(_on_touch_context_pressed)
	_touch_context_menu.popup_hide.connect(_on_touch_context_hidden)
	add_child(_touch_context_menu)


func _open_touch_context(screen_pos: Vector2) -> void:
	_ensure_touch_context_menu()
	var world_pos := _screen_to_world(screen_pos)
	var tapped_node: Node2D = _get_node_at(world_pos)
	var resource_node: Node2D = _get_resource_at(world_pos)
	var actions := _build_touch_context_actions(tapped_node, resource_node)
	if actions.size() <= 1:
		if actions.size() == 1:
			_context_world_pos = world_pos
			_context_target = tapped_node
			_context_resource = resource_node
			_execute_touch_context_action(actions[0]["id"])
		return

	_touch_context_menu.clear()
	for action in actions:
		_touch_context_menu.add_item(action["label"], action["id"])

	_context_world_pos = world_pos
	_context_target = tapped_node
	_context_resource = resource_node

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var popup_pos := screen_pos + Vector2(12, 8)
	popup_pos.x = clampf(popup_pos.x, 8.0, maxf(8.0, viewport_size.x - 180.0))
	popup_pos.y = clampf(popup_pos.y, 8.0, maxf(8.0, viewport_size.y - 160.0))

	_touch_context_menu.popup(Rect2i(Vector2i(popup_pos), Vector2i(180, 1)))
	_touch_context_open = true


func _build_touch_context_actions(tapped_node: Node2D, resource_node: Node2D) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var has_selection: bool = selected.size() > 0

	if has_selection:
		if tapped_node != null and _is_enemy(tapped_node):
			actions.append({"id": TouchContextAction.ATTACK, "label": "Attack"})
		if resource_node != null and _has_selected_villagers():
			actions.append({"id": TouchContextAction.GATHER, "label": "Gather"})
		if tapped_node != null and _has_selected_villagers() and _is_under_construction(tapped_node):
			actions.append({"id": TouchContextAction.BUILD, "label": "Build"})
		if tapped_node == null:
			actions.append({"id": TouchContextAction.MOVE, "label": "Move"})
		elif not _is_enemy(tapped_node):
			actions.append({"id": TouchContextAction.SELECT, "label": "Select"})
		return actions

	if tapped_node != null or resource_node != null:
		actions.append({"id": TouchContextAction.SELECT, "label": "Select"})
	else:
		actions.append({"id": TouchContextAction.CLEAR, "label": "Clear Selection"})
	return actions


func _on_touch_context_pressed(action_id: int) -> void:
	_touch_context_open = false
	_execute_touch_context_action(action_id)


func _on_touch_context_hidden() -> void:
	_touch_context_open = false


func _execute_touch_context_action(action_id: int) -> void:
	match action_id:
		TouchContextAction.ATTACK:
			if _context_target != null and _is_enemy(_context_target):
				attack_command.emit(_context_target)
		TouchContextAction.GATHER:
			if _context_resource != null and _has_selected_villagers():
				gather_command.emit(_context_resource)
		TouchContextAction.BUILD:
			if _context_target != null and _has_selected_villagers() and _is_under_construction(_context_target):
				build_command.emit(_context_target)
		TouchContextAction.MOVE:
			var tile_pos := _world_to_tile(_context_world_pos)
			move_command.emit(tile_pos)
		TouchContextAction.SELECT:
			if _context_target != null:
				_clear_selection()
				_add_to_selection(_context_target)
			elif _context_resource != null:
				_clear_selection()
				_add_to_selection(_context_resource)
		TouchContextAction.CLEAR:
			_clear_selection()
	get_viewport().set_input_as_handled()


func _hide_touch_context() -> void:
	if _touch_context_menu != null and _touch_context_menu.visible:
		_touch_context_menu.hide()
	_touch_context_open = false


## --- Draw drag-box ---

func _draw() -> void:
	if _is_dragging:
		var rect := Rect2(_drag_start, _drag_end - _drag_start).abs()
		# Convert screen rect to local coords for drawing.
		var canvas_inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
		var local_start := canvas_inv * rect.position
		var local_end := canvas_inv * rect.end
		var local_rect := Rect2(local_start, local_end - local_start)
		draw_rect(local_rect, Color(0.3, 0.7, 1.0, 0.25), true)
		draw_rect(local_rect, Color(0.3, 0.7, 1.0, 0.8), false, 1.5)
