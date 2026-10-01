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
## Main mirrors its one-shot Move/A-Move/Patrol state here so a world tap cannot
## be reinterpreted as gather, construction, attack, or building reselection.
var unit_command_armed: bool = false

## Reference to the game_map node (set externally by GameMap).
var game_map: Node2D = null

## --- Drag-box state ---
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_end := Vector2.ZERO
var _mouse_drag_threshold := 10.0  # Desktop mouse threshold.

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
var _touch_hold_started_at_msec: int = 0
var _touch_long_press_consumed := false
@export var touch_context_enabled: bool = true
@export var long_press_threshold: float = 0.35
@export var touch_tap_slop_px: float = 12.0
@export var touch_pan_threshold: float = 16.0
@export var touch_unit_hit_radius_px: float = 24.0
## A deliberate tap on a friendly unit switches selection even while another
## unit is selected. The outer discovery ring remains available for movement.
@export var touch_unit_reselect_radius_px: float = 18.0
@export var touch_building_hit_radius_px: float = 34.0
## Friendly buildings use a deliberately tighter center hit while units are
## selected. This makes direct production-building reselection reliable without
## turning nearby ground taps into accidental selection changes.
@export var touch_building_reselect_radius_px: float = 26.0
@export var touch_resource_hit_radius_px: float = 28.0
@export var touch_context_diagnostics: Dictionary = {}
@export var touch_input_diagnostics: Dictionary = {}
@export var touch_target_diagnostics: Dictionary = {}
var _long_press_move_tolerance := 12.0  # pixels
var _touch_pan_gesture := false
var _touch_context_open := false
var _touch_context_menu: PopupMenu = null
var _context_world_pos := Vector2.ZERO
var _context_target: Node2D = null
var _context_resource: Node2D = null
var _active_touch_indices: Dictionary = {}
var _released_world_touch_indices: Dictionary = {}
## Browser contact identifiers need not start at zero or be reused. The first
## unhandled world press owns this gesture until every admitted contact lifts.
var _primary_touch_index: int = -1
var _last_touch_input_msec: int = 0
var _last_tap_target_id: int = 0
var _next_touch_target_refresh_msec: int = 0
var _last_touch_context_action: String = ""
var _last_touch_context_action_id: int = -1
var _last_touch_context_timestamp_ms: int = 0
var _touch_context_execution_count: int = 0
var _building_facade_art_bounds: Dictionary = {}  # texture instance id -> opaque art bounds

const DESKTOP_UNIT_HIT_RADIUS_WORLD := 20.0
const DESKTOP_BUILDING_HIT_RADIUS_WORLD := 36.0
const DESKTOP_RESOURCE_HIT_RADIUS_WORLD := 28.0
const MIN_TOUCH_HIT_RADIUS_WORLD := 8.0
const MOUSE_AFTER_TOUCH_IGNORE_MS: int = 1500


func set_unit_command_armed(armed: bool) -> void:
	unit_command_armed = armed
	if armed:
		# The destination tap starts a new one-shot gesture; it must not combine
		# with the selection tap that preceded the HUD button press.
		_last_tap_time = 0.0


## A modal world interaction owns any fingers already down. Cancel its prior
## gesture so a delayed long press cannot issue an order during placement.
func cancel_touch_gesture() -> void:
	_touch_hold_active = false
	_touch_hold_elapsed = 0.0
	_touch_hold_started_at_msec = 0
	_touch_long_press_consumed = false
	_touch_pan_gesture = false
	_active_touch_indices.clear()
	_released_world_touch_indices.clear()
	_primary_touch_index = -1
	_is_dragging = false
	_last_tap_time = 0.0
	_hide_touch_context()
	queue_redraw()


func _ready() -> void:
	set_process_unhandled_input(true)
	set_process(true)
	touch_tap_slop_px = maxf(4.0, touch_tap_slop_px)
	touch_pan_threshold = maxf(touch_pan_threshold, touch_tap_slop_px + 2.0)
	_long_press_move_tolerance = minf(_long_press_move_tolerance, touch_pan_threshold - 1.0)
	_long_press_move_tolerance = maxf(4.0, _long_press_move_tolerance)
	if touch_context_enabled:
		_ensure_touch_context_menu()
	_refresh_touch_context_diagnostics()


func _process(delta: float) -> void:
	# Selected world objects can disappear independently of input (death,
	# destruction, depletion, or queue_free). Prune them before any per-frame
	# selection consumer can observe a stale Object reference.
	_prune_stale_selection()
	var now_msec: int = Time.get_ticks_msec()
	if not OS.has_feature("production") and now_msec >= _next_touch_target_refresh_msec:
		_next_touch_target_refresh_msec = now_msec + 250
		_refresh_touch_target_diagnostics()
	if not touch_context_enabled or not _touch_hold_active:
		return
	if _drag_start.distance_to(_drag_end) > _long_press_move_tolerance:
		_touch_hold_active = false
		return
	_touch_hold_elapsed += delta
	if _touch_hold_elapsed >= long_press_threshold:
		_touch_hold_active = false
		_touch_hold_started_at_msec = 0
		_touch_long_press_consumed = true
		_is_dragging = false
		queue_redraw()
		_open_touch_context(_drag_end)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# HUD controls can consume a finger release before unhandled input. Keep
	# only gesture bookkeeping here so that release never selects the world,
	# leaves a stale pinch finger, or triggers a delayed long press.
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		var touch := event as InputEventScreenTouch
		if _active_touch_indices.has(touch.index):
			_released_world_touch_indices[touch.index] = true
		else:
			_released_world_touch_indices.erase(touch.index)
		_active_touch_indices.erase(touch.index)
		_last_touch_input_msec = Time.get_ticks_msec()
		if touch.index == _primary_touch_index:
			_touch_hold_active = false
		# GUI may consume this release before _unhandled_input. Defer cleanup
		# until that dispatch ends so world ownership remains available there.
		call_deferred("_finish_released_touch", touch.index)


func _finish_released_touch(index: int) -> void:
	# A synchronous input producer may already have reused this identity for
	# a new press before the deferred callback. Never cancel that new contact.
	if _active_touch_indices.has(index):
		return
	_released_world_touch_indices.erase(index)
	if _active_touch_indices.is_empty():
		_primary_touch_index = -1
		_touch_hold_active = false
		_touch_hold_elapsed = 0.0
		_touch_hold_started_at_msec = 0
		_touch_long_press_consumed = false
		_touch_pan_gesture = false
		_is_dragging = false


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
	_last_touch_input_msec = Time.get_ticks_msec()
	if event.pressed:
		_released_world_touch_indices.erase(event.index)
		if _active_touch_indices.is_empty():
			_primary_touch_index = event.index
			_touch_pan_gesture = false
		_active_touch_indices[event.index] = true
		if _active_touch_indices.size() > 1:
			_touch_pan_gesture = true
			_touch_hold_active = false
			_is_dragging = false
		if event.index != _primary_touch_index:
			return
		_hide_touch_context()
		_drag_start = event.position
		_drag_end = event.position
		# Once a second contact arrives, camera ownership stays latched even
		# if one finger lifts or its release is consumed by a GUI control.
		_touch_pan_gesture = _touch_pan_gesture or _active_touch_indices.size() > 1
		_touch_hold_active = touch_context_enabled and not _touch_pan_gesture
		_touch_hold_elapsed = 0.0
		_touch_hold_started_at_msec = Time.get_ticks_msec()
		_touch_long_press_consumed = false
	else:
		# A GUI-owned press or an OS-canceled contact is never a world tap.
		# _input may already have removed the contact before GUI routing.
		var owned_world_press: bool = _active_touch_indices.has(event.index) or bool(_released_world_touch_indices.get(event.index, false))
		_released_world_touch_indices.erase(event.index)
		_active_touch_indices.erase(event.index)
		if event.canceled or not owned_world_press:
			if event.index == _primary_touch_index:
				_touch_hold_active = false
				_touch_hold_started_at_msec = 0
				_touch_long_press_consumed = false
			if _active_touch_indices.is_empty():
				_finish_released_touch(event.index)
			return
		if event.index != _primary_touch_index:
			if _active_touch_indices.is_empty():
				_finish_released_touch(event.index)
			return
		_touch_hold_active = false
		if _touch_context_open:
			_touch_hold_started_at_msec = 0
			_touch_long_press_consumed = false
			_is_dragging = false
			queue_redraw()
			_finish_released_touch(event.index)
			return
		if _touch_long_press_consumed:
			# The threshold callback already opened the context action. A
			# single-action menu executes immediately, so its release must not
			# run the long-press fallback (or the normal tap path) a second time.
			_touch_hold_started_at_msec = 0
			_touch_long_press_consumed = false
			_is_dragging = false
			queue_redraw()
			get_viewport().set_input_as_handled()
			_finish_released_touch(event.index)
			return
		var drag_distance := _drag_start.distance_to(event.position)
		var held_long_enough: bool = false
		if _touch_hold_started_at_msec > 0:
			held_long_enough = (Time.get_ticks_msec() - _touch_hold_started_at_msec) >= int(round(long_press_threshold * 1000.0))
		_touch_hold_started_at_msec = 0
		if _active_touch_indices.is_empty() and not _touch_pan_gesture and drag_distance < touch_tap_slop_px and held_long_enough and touch_context_enabled:
			_touch_long_press_consumed = true
			_open_touch_context(event.position)
			_touch_long_press_consumed = false
			queue_redraw()
			get_viewport().set_input_as_handled()
			_finish_released_touch(event.index)
			return
		if _active_touch_indices.is_empty() and not _touch_pan_gesture and drag_distance < touch_tap_slop_px:
			_handle_tap(event.position, true)
		if _active_touch_indices.is_empty():
			_finish_released_touch(event.index)
		queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	_last_touch_input_msec = Time.get_ticks_msec()
	if not _active_touch_indices.has(event.index):
		# A GUI-owned or unknown contact cannot enter a world gesture by dragging.
		return
	if _touch_context_open:
		return
	if event.index != _primary_touch_index:
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
	# Mouse→touch emulation stamps the touch timer on a physical left click.
	# A subsequent physical right click is a distinct desktop command, while
	# synthesized mouse events must not duplicate the touch interaction.
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
	elif _should_ignore_mouse_input():
		return
	_prune_stale_selection()
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
		if drag_distance < _mouse_drag_threshold:
			_handle_tap(event.position, false)
		else:
			_drag_end = event.position
			_finish_drag_select()
		queue_redraw()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _should_ignore_mouse_input():
		return
	_drag_end = event.position
	queue_redraw()


## --- Tap / click logic ---

func _handle_tap(screen_pos: Vector2, is_touch_input: bool) -> void:
	_prune_stale_selection()
	var consumed: bool = false
	var world_pos := _screen_to_world(screen_pos)
	var tapped_node: Node2D = _get_node_at(world_pos, is_touch_input)
	var resource_node: Node2D = _get_resource_at(world_pos, is_touch_input)
	var tap_target_id: int = tapped_node.get_instance_id() if tapped_node != null else 0
	# Check double-tap.
	var now := Time.get_ticks_msec() / 1000.0
	if not unit_command_armed and tap_target_id != 0 and tap_target_id == _last_tap_target_id \
			and _last_tap_time > 0.0 \
			and now - _last_tap_time < _double_tap_interval \
			and screen_pos.distance_to(_last_tap_position) < _double_tap_radius:
		_handle_double_tap(screen_pos, is_touch_input)
		_last_tap_time = 0.0
		if is_touch_input:
			get_viewport().set_input_as_handled()
		return
	_last_tap_time = now
	_last_tap_position = screen_pos
	_last_tap_target_id = tap_target_id

	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)
	var has_selected_villagers: bool = _has_selected_villagers()
	var has_selected_units: bool = _has_selected_units()
	_record_touch_input(screen_pos, world_pos, "pending", tapped_node, resource_node)

	if unit_command_armed and has_selected_units:
		# An explicit command mode owns the next world tap regardless of what is
		# underneath it. Main applies the armed Move/A-Move/Patrol semantics after
		# receiving this common destination signal.
		var armed_tile_pos := _world_to_tile(world_pos)
		_record_touch_input(
			screen_pos,
			world_pos,
			"armed_command",
			tapped_node,
			resource_node,
			armed_tile_pos
		)
		# This completes an explicit one-shot gesture. A quick following tap
		# may select a production building rather than double-select a unit type.
		_last_tap_time = 0.0
		move_command.emit(armed_tile_pos)
		if is_touch_input:
			get_viewport().set_input_as_handled()
		return

	if is_touch_input and has_selected_units and _is_direct_friendly_unit_reselection(tapped_node, screen_pos):
		_clear_selection()
		_add_to_selection(tapped_node)
		_record_touch_input(screen_pos, world_pos, "select_unit", tapped_node, resource_node)
		get_viewport().set_input_as_handled()
		return

	if is_touch_input and has_selected_units \
			and _is_direct_friendly_building_reselection(tapped_node, screen_pos) \
			and _is_touch_on_building_facade(tapped_node, world_pos) \
			and tapped_node != resource_node:
		# A visible wall is deliberate production/construction intent, even
		# when an adjacent resource has a generous overview discovery ring.
		# A Farm that is itself the resource keeps its normal gather meaning.
		if has_selected_villagers and _is_under_construction(tapped_node):
			_record_touch_input(screen_pos, world_pos, "build", tapped_node, resource_node)
			build_command.emit(tapped_node)
		else:
			_clear_selection()
			_add_to_selection(tapped_node)
			_record_touch_input(screen_pos, world_pos, "select_building", tapped_node, resource_node)
		get_viewport().set_input_as_handled()
		return

	if is_touch_input and has_selected_villagers and resource_node != null \
			and (tapped_node == null or not _is_enemy(tapped_node)):
		# On touch, resource intent should win over nearby friendly-unit hitboxes.
		_record_touch_input(screen_pos, world_pos, "gather", tapped_node, resource_node)
		gather_command.emit(resource_node)
		get_viewport().set_input_as_handled()
		return

	if tapped_node != null:
		if selected.size() > 0 and _is_enemy(tapped_node):
			# Attack command.
			_record_touch_input(screen_pos, world_pos, "attack", tapped_node, resource_node)
			attack_command.emit(tapped_node)
			consumed = true
		elif has_selected_villagers and _is_under_construction(tapped_node):
			# Send selected villagers to build.
			_record_touch_input(screen_pos, world_pos, "build", tapped_node, resource_node)
			build_command.emit(tapped_node)
			consumed = true
		elif is_touch_input and has_selected_units and _is_direct_friendly_building_reselection(tapped_node, screen_pos):
			# A deliberate tap near the center of an owned building changes context
			# immediately. The tighter radius is important: the broader discovery
			# radius still treats near-building taps as ground commands.
			_clear_selection()
			_add_to_selection(tapped_node)
			_record_touch_input(screen_pos, world_pos, "select_building", tapped_node, resource_node)
			consumed = true
		elif is_touch_input and has_selected_units:
			# The outer hit ring around a friendly target still counts as a ground
			# destination; selection requires a deliberate tap on its center.
			var touched_tile_pos := _world_to_tile(world_pos)
			_record_touch_input(screen_pos, world_pos, "move", tapped_node, resource_node, touched_tile_pos)
			move_command.emit(touched_tile_pos)
			consumed = true
		elif shift_held and not _is_enemy(tapped_node):
			# Shift+click: add/remove from selection
			if tapped_node in selected:
				_remove_from_selection(tapped_node)
			else:
				_add_to_selection(tapped_node)
			_record_touch_input(screen_pos, world_pos, "multi_select", tapped_node, resource_node)
			consumed = true
		else:
			# Select the tapped unit/building.
			_clear_selection()
			_add_to_selection(tapped_node)
			_record_touch_input(screen_pos, world_pos, "select", tapped_node, resource_node)
			consumed = true
		if consumed and is_touch_input:
			get_viewport().set_input_as_handled()
		return

	if resource_node != null:
		if has_selected_villagers:
			# Touch parity: villagers can gather by tapping a resource target.
			_record_touch_input(screen_pos, world_pos, "gather", tapped_node, resource_node)
			gather_command.emit(resource_node)
			consumed = true
		elif is_touch_input and has_selected_units:
			# When units are already selected, a touch on a resource should still issue
			# a ground command instead of becoming a no-op.
			var resource_tile_pos := _world_to_tile(world_pos)
			_record_touch_input(screen_pos, world_pos, "move", tapped_node, resource_node, resource_tile_pos)
			move_command.emit(resource_tile_pos)
			consumed = true
		elif selected.is_empty():
			_clear_selection()
			_add_to_selection(resource_node)
			_record_touch_input(screen_pos, world_pos, "select_resource", tapped_node, resource_node)
			consumed = true
		if consumed and is_touch_input:
			get_viewport().set_input_as_handled()
		return

	if is_touch_input and selected.size() > 0:
		# Touch parity: tapping empty ground while selected issues a move command.
		var tile_pos := _world_to_tile(world_pos)
		_record_touch_input(screen_pos, world_pos, "move", tapped_node, resource_node, tile_pos)
		move_command.emit(tile_pos)
		consumed = true
	elif not shift_held:
		# Desktop left click keeps deselect behavior.
		if not is_touch_input:
			_record_touch_input(screen_pos, world_pos, "clear", tapped_node, resource_node)
			_clear_selection()
			consumed = true
	if not consumed:
		_record_touch_input(screen_pos, world_pos, "ignored", tapped_node, resource_node)
	if consumed and is_touch_input:
		get_viewport().set_input_as_handled()


func _handle_double_tap(screen_pos: Vector2, is_touch_input: bool) -> void:
	var world_pos := _screen_to_world(screen_pos)
	var tapped_node: Node2D = _get_node_at(world_pos, is_touch_input)
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
		if not _is_current_selection_entry(node):
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
		if not _is_current_selection_entry(node):
			continue
		var screen_pos := _world_to_screen((node as Node2D).global_position)
		if _drag_rect.has_point(screen_pos):
			# Only select own units during drag.
			if not _is_enemy(node as Node2D):
				_add_to_selection(node as Node2D)
	_drag_rect = Rect2()


## --- Selection management ---

func _clear_selection() -> void:
	var changed := not selected.is_empty()
	# A typed Object array may retain a Variant that points to an already-freed
	# instance. Iterate by index in reverse and validate before dereferencing.
	for index in range(selected.size() - 1, -1, -1):
		var entry: Variant = selected[index]
		_deselect_entry_if_valid(entry)
		selected.remove_at(index)
	if changed:
		selection_changed.emit(selected)
		_refresh_touch_context_diagnostics()


func _add_to_selection(node: Node2D) -> void:
	_prune_stale_selection()
	if not _is_current_selection_entry(node):
		return
	if node not in selected:
		selected.append(node)
		if node.has_method("select"):
			node.select()
	selection_changed.emit(selected)


func _remove_from_selection(node: Node2D) -> void:
	_prune_stale_selection()
	if node == null or not is_instance_valid(node):
		return
	if node in selected:
		selected.erase(node)
		if node.has_method("deselect"):
			node.deselect()
		selection_changed.emit(selected)


func select_all_own_units() -> void:
	_clear_selection()
	for node in get_tree().get_nodes_in_group("units"):
		if not _is_current_selection_entry(node):
			continue
		if not _is_enemy(node as Node2D):
			_add_to_selection(node as Node2D)


func select_single(node: Node2D) -> void:
	if not _is_current_selection_entry(node):
		return
	_clear_selection()
	_add_to_selection(node)


func select_many(nodes: Array[Node2D]) -> void:
	_clear_selection()
	for node in nodes:
		if not _is_current_selection_entry(node):
			continue
		_add_to_selection(node)


func deselect_all() -> void:
	_clear_selection()


## Remove selected objects that are no longer actionable. All stale entries are
## removed as one transaction so one cleanup pass emits selection_changed once.
func _prune_stale_selection() -> bool:
	var changed := false
	for index in range(selected.size() - 1, -1, -1):
		var entry: Variant = selected[index]
		if _is_current_selection_entry(entry):
			continue
		_deselect_entry_if_valid(entry)
		selected.remove_at(index)
		changed = true
	if changed:
		selection_changed.emit(selected)
		_refresh_touch_context_diagnostics()
	return changed


## Variant-safe validity check for entries retained by the typed selection array.
func _is_current_selection_entry(entry: Variant) -> bool:
	if not is_instance_valid(entry) or not entry is Node2D:
		return false
	var node := entry as Node2D
	var is_neutral_resource: bool = node is ResourceNode
	var is_enemy_object: bool = _is_enemy_owner_unchecked(node)
	# Visibility precedes every mutable live-state read for neutral resources and
	# enemies. Hidden deletion, health/state, and remaining stock are never used
	# to decide a player-facing selection result.
	if (is_neutral_resource or is_enemy_object) and not _is_visible_to_local_player(node):
		return false
	if node.is_queued_for_deletion():
		return false
	if node is UnitBase and (node as UnitBase).current_state == UnitBase.State.DEAD:
		return false
	if node is BuildingBase and (node as BuildingBase).state == BuildingBase.State.DESTROYED:
		return false
	if node is ResourceNode:
		if (node as ResourceNode).remaining <= 0:
			return false
	# Enemy objects cease to be selectable, clickable, or commandable on the
	# same fog update that hides them. Friendly objects remain actionable.
	return true


func _deselect_entry_if_valid(entry: Variant) -> void:
	if not is_instance_valid(entry) or not entry is Node2D:
		return
	var node := entry as Node2D
	if node.has_method("deselect"):
		node.call("deselect")


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


## Prefer deliberate hits on people and building facades over discovery rings.
func _get_node_at(world_pos: Vector2, use_touch_radius: bool = false) -> Node2D:
	# Check units first with a tight radius so clicking near units registers ground clicks.
	var best_unit: Node2D = null
	var best_unit_dist := DESKTOP_UNIT_HIT_RADIUS_WORLD
	var best_body_hit: Node2D = null
	var best_body_distance: float = INF
	if use_touch_radius:
		best_unit_dist = _screen_px_to_world_radius(touch_unit_hit_radius_px)
	for node in get_tree().get_nodes_in_group("units"):
		if not _is_current_selection_entry(node):
			continue
		var dist := (node as Node2D).global_position.distance_to(world_pos)
		if _is_touch_on_unit_body(node as Node2D, world_pos):
			# A visible body wins over another unit's broad feet discovery ring.
			# This matters in compact armies at overview zoom: tapping a head
			# must not select the soldier standing just above that person.
			var sprite: Sprite2D = (node as Node2D).get_node("UnitSprite") as Sprite2D
			var body_center: Vector2 = sprite.to_global(_unit_touch_body_rect(sprite).get_center())
			var body_distance: float = body_center.distance_to(world_pos)
			if body_distance < best_body_distance:
				best_body_distance = body_distance
				best_body_hit = node as Node2D
		if dist < best_unit_dist:
			best_unit_dist = dist
			best_unit = node as Node2D
	# The exact ground marker belongs to its unit even when a taller neighbor's
	# body overlaps it. Keep this deliberate disk much tighter than discovery.
	if best_unit != null and best_unit_dist <= 6.0:
		return best_unit
	if best_body_hit != null:
		return best_body_hit

	# The central visible wall is a deliberate building target. A nearby unit's
	# broad feet ring must not steal production buildings from the player.
	var best_building: Node2D = null
	var best_building_dist := DESKTOP_BUILDING_HIT_RADIUS_WORLD
	var best_facade_hit: Node2D = null
	var best_facade_distance: float = INF
	if use_touch_radius:
		best_building_dist = _screen_px_to_world_radius(touch_building_hit_radius_px)
	for node in get_tree().get_nodes_in_group("buildings"):
		if not _is_current_selection_entry(node):
			continue
		if _is_touch_on_building_facade(node as Node2D, world_pos):
			var sprite: Sprite2D = (node as Node2D).get_node("BuildingSprite") as Sprite2D
			var facade_center: Vector2 = sprite.to_global(_building_touch_facade_rect(sprite).get_center())
			var facade_distance: float = facade_center.distance_to(world_pos)
			if facade_distance < best_facade_distance:
				best_facade_distance = facade_distance
				best_facade_hit = node as Node2D
		var dist := (node as Node2D).global_position.distance_to(world_pos)
		if dist < best_building_dist:
			best_building_dist = dist
			best_building = node as Node2D
	if best_facade_hit != null:
		return best_facade_hit
	if best_unit != null:
		return best_unit
	return best_building


## Find a resource node at a world position (checks "resources" group).
func _get_resource_at(world_pos: Vector2, use_touch_radius: bool = false) -> Node2D:
	var best_node: Node2D = null
	var body_node: Node2D = null
	var body_distance: float = INF
	var best_dist := DESKTOP_RESOURCE_HIT_RADIUS_WORLD
	if use_touch_radius:
		best_dist = _screen_px_to_world_radius(touch_resource_hit_radius_px)
	for node in get_tree().get_nodes_in_group("resources"):
		if not _is_current_selection_entry(node):
			continue
		if not _is_resource_target_valid_for_local_player(node as Node2D):
			continue
		var dist := (node as Node2D).global_position.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best_node = node as Node2D
		elif dist < body_distance and node.has_method("is_sprite_body_hit") and bool(node.call("is_sprite_body_hit", world_pos)):
			body_distance = dist
			body_node = node as Node2D
	# Direct ground/resource taps retain priority when artwork overlaps them.
	return best_node if best_node != null else body_node


func _is_resource_target_valid_for_local_player(entry: Variant) -> bool:
	if not _is_current_selection_entry(entry):
		return false
	var node := entry as Node2D
	if game_map != null and game_map.has_method("is_resource_target_valid"):
		return bool(game_map.call("is_resource_target_valid", node, "", 0))
	if node.has_method("is_harvestable_by"):
		return bool(node.call("is_harvestable_by", 0))
	return node.has_method("get_resource_type") and node.has_method("harvest")


## Check if a unit belongs to the enemy (not our player).
func _is_enemy(entry: Variant) -> bool:
	if not _is_current_selection_entry(entry):
		return false
	var node := entry as Node2D
	return _is_enemy_owner_unchecked(node)


func _is_enemy_owner_unchecked(node: Node2D) -> bool:
	if node.has_method("get_player_id"):
		return int(node.call("get_player_id")) != 0  # Local player = 0.
	if node.has_method("get_player_owner"):
		return int(node.call("get_player_owner")) != 0
	if node.has_meta("player_id"):
		return int(node.get_meta("player_id")) != 0
	return false


func _is_visible_to_local_player(node: Node2D) -> bool:
	if game_map != null and game_map.has_method("is_entity_visible_to_player"):
		return bool(game_map.call("is_entity_visible_to_player", node, 0))
	return node.visible


## Check if a node2D is visible on the current screen.
func _is_on_screen(node: Node2D) -> bool:
	var screen_pos := _world_to_screen(node.global_position)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return screen_pos.x >= 0 and screen_pos.x <= viewport_size.x \
		and screen_pos.y >= 0 and screen_pos.y <= viewport_size.y


## --- Right-click command ---

func _handle_right_click(screen_pos: Vector2) -> void:
	_prune_stale_selection()
	if selected.is_empty():
		return
	var world_pos := _screen_to_world(screen_pos)

	# Check for enemy target → attack
	var tapped_node: Node2D = _get_node_at(world_pos, false)
	if tapped_node != null and _is_enemy(tapped_node):
		attack_command.emit(tapped_node)
		return

	# Check for construction site + villagers → build command
	if tapped_node != null and _has_selected_villagers() and _is_under_construction(tapped_node):
		build_command.emit(tapped_node)
		return

	# Check for resource node → gather command
	var resource_node: Node2D = _get_resource_at(world_pos, false)
	if resource_node != null:
		gather_command.emit(resource_node)
		return

	# Empty ground → move command
	var tile_pos := _world_to_tile(world_pos)
	move_command.emit(tile_pos)


## --- Selection helpers ---

func _has_selected_villagers() -> bool:
	for index in range(selected.size() - 1, -1, -1):
		var entry: Variant = selected[index]
		if _is_current_selection_entry(entry) and entry is Villager:
			return true
	return false


func _has_selected_units() -> bool:
	for index in range(selected.size() - 1, -1, -1):
		var entry: Variant = selected[index]
		if _is_current_selection_entry(entry) and entry is UnitBase:
			return true
	return false


func _is_under_construction(entry: Variant) -> bool:
	if _is_current_selection_entry(entry) and entry is BuildingBase:
		var building := entry as BuildingBase
		return building.state == BuildingBase.State.CONSTRUCTING and not _is_enemy(building)
	return false


func _is_direct_friendly_building_reselection(entry: Variant, screen_pos: Vector2) -> bool:
	if not _is_current_selection_entry(entry) or not entry is BuildingBase:
		return false
	var building := entry as BuildingBase
	if _is_enemy(building) or building.state == BuildingBase.State.DESTROYED:
		return false
	var building_screen_pos: Vector2 = _world_to_screen(building.global_position)
	return (
		building_screen_pos.distance_to(screen_pos) <= maxf(12.0, touch_building_reselect_radius_px)
		or _is_touch_on_building_facade(building, _screen_to_world(screen_pos))
	)


func _is_touch_on_building_facade(building: Node2D, world_pos: Vector2) -> bool:
	var sprite: Sprite2D = building.get_node_or_null("BuildingSprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return false
	return _building_touch_facade_rect(sprite).has_point(sprite.to_local(world_pos))


func _building_touch_facade_rect(sprite: Sprite2D) -> Rect2:
	var texture_id: int = sprite.texture.get_instance_id()
	if not _building_facade_art_bounds.has(texture_id):
		var art_bounds: Rect2 = Rect2(Vector2.ZERO, sprite.texture.get_size())
		var texture_image: Image = sprite.texture.get_image()
		if texture_image != null:
			var opaque_bounds: Rect2i = texture_image.get_used_rect()
			if opaque_bounds.has_area():
				art_bounds = Rect2(opaque_bounds)
		_building_facade_art_bounds[texture_id] = art_bounds
	var art_rect: Rect2 = _building_facade_art_bounds[texture_id]
	art_rect.position += sprite.get_rect().position
	# Asset margins differ greatly (the Town Center art occupies its lower
	# half). A narrow central/lower wall column excludes those margins and
	# leaves nearby terrain available as a movement destination.
	var facade_rect := Rect2(
		art_rect.position + art_rect.size * Vector2(0.28, 0.30),
		art_rect.size * Vector2(0.44, 0.60)
	)
	return facade_rect


func _is_direct_friendly_unit_reselection(entry: Variant, screen_pos: Vector2) -> bool:
	if not _is_current_selection_entry(entry) or not entry is UnitBase:
		return false
	var unit := entry as UnitBase
	if _is_enemy(unit):
		return false
	return (
		_world_to_screen(unit.global_position).distance_to(screen_pos) <= maxf(12.0, touch_unit_reselect_radius_px)
		or _is_touch_on_unit_body(unit, _screen_to_world(screen_pos))
	)


func _is_touch_on_unit_body(unit: Node2D, world_pos: Vector2) -> bool:
	var sprite: Sprite2D = unit.get_node_or_null("UnitSprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return false
	return _unit_touch_body_rect(sprite).has_point(sprite.to_local(world_pos))


func _unit_touch_body_rect(sprite: Sprite2D) -> Rect2:
	# Ignore the transparent margin around the art: the central body column is
	# a deliberate target, while nearby terrain retains its movement meaning.
	var body_rect: Rect2 = sprite.get_rect()
	body_rect.position += body_rect.size * Vector2(0.26, 0.12)
	body_rect.size *= Vector2(0.48, 0.64)
	return body_rect


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
	_prune_stale_selection()
	_ensure_touch_context_menu()
	var world_pos := _screen_to_world(screen_pos)
	var tapped_node: Node2D = _get_node_at(world_pos, true)
	var resource_node: Node2D = _get_resource_at(world_pos, true)
	var actions := _build_touch_context_actions(tapped_node, resource_node)
	if actions.size() <= 1:
		_refresh_touch_context_diagnostics(actions, false, screen_pos)
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
	_refresh_touch_context_diagnostics(actions, true, popup_pos)


func _build_touch_context_actions(tapped_node: Node2D, resource_node: Node2D) -> Array[Dictionary]:
	_prune_stale_selection()
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
	_refresh_touch_context_diagnostics()


func _execute_touch_context_action(action_id: int) -> void:
	_prune_stale_selection()
	var executed_action: String = ""
	match action_id:
		TouchContextAction.ATTACK:
			if _is_current_selection_entry(_context_target) and _is_enemy(_context_target):
				attack_command.emit(_context_target)
				executed_action = "Attack"
		TouchContextAction.GATHER:
			if (
				_context_resource != null
				and _has_selected_villagers()
				and _is_resource_target_valid_for_local_player(_context_resource)
			):
				gather_command.emit(_context_resource)
				executed_action = "Gather"
		TouchContextAction.BUILD:
			if _is_current_selection_entry(_context_target) and _has_selected_villagers() and _is_under_construction(_context_target):
				build_command.emit(_context_target)
				executed_action = "Build"
		TouchContextAction.MOVE:
			if not selected.is_empty():
				var tile_pos := _world_to_tile(_context_world_pos)
				move_command.emit(tile_pos)
				executed_action = "Move"
		TouchContextAction.SELECT:
			if _is_current_selection_entry(_context_target):
				_clear_selection()
				_add_to_selection(_context_target)
				executed_action = "Select"
			elif _is_resource_target_valid_for_local_player(_context_resource):
				_clear_selection()
				_add_to_selection(_context_resource)
				executed_action = "Select"
		TouchContextAction.CLEAR:
			_clear_selection()
			executed_action = "Clear Selection"
	if not executed_action.is_empty():
		_last_touch_context_action = executed_action
		_last_touch_context_action_id = action_id
		_last_touch_context_timestamp_ms = Time.get_ticks_msec()
		_touch_context_execution_count += 1
	get_viewport().set_input_as_handled()
	_refresh_touch_context_diagnostics()


func _hide_touch_context() -> void:
	if _touch_context_menu != null and _touch_context_menu.visible:
		_touch_context_menu.hide()
	_touch_context_open = false
	_refresh_touch_context_diagnostics()


func _refresh_touch_context_diagnostics(actions: Array[Dictionary] = [], visible_override: bool = false, popup_pos: Vector2 = Vector2.ZERO) -> void:
	if OS.has_feature("production"):
		return
	var labels: PackedStringArray = PackedStringArray()
	var ids: Array[int] = []
	for action in actions:
		labels.append(String(action.get("label", "")))
		ids.append(int(action.get("id", -1)))
	touch_context_diagnostics = {
		"visible": visible_override,
		"actions": labels,
		"action_ids": ids,
		"selection_count": selected.size(),
		"popup_x": popup_pos.x,
		"popup_y": popup_pos.y,
		"last_executed_action": _last_touch_context_action,
		"last_executed_action_id": _last_touch_context_action_id,
		"last_executed_timestamp_ms": _last_touch_context_timestamp_ms,
		"execution_count": _touch_context_execution_count,
	}


func _record_touch_input(
	screen_pos: Vector2,
	world_pos: Vector2,
	action: String,
	tapped_node: Node2D,
	resource_node: Node2D,
	target_tile: Vector2i = Vector2i.ZERO,
) -> void:
	if OS.has_feature("production"):
		return
	var tapped_node_distance: float = -1.0
	if tapped_node != null:
		tapped_node_distance = tapped_node.global_position.distance_to(world_pos)
	var resource_node_distance: float = -1.0
	if resource_node != null:
		resource_node_distance = resource_node.global_position.distance_to(world_pos)
	var camera_zoom: float = _get_camera_zoom_scalar()
	touch_input_diagnostics = {
		"timestamp_ms": Time.get_ticks_msec(),
		"action": action,
		"screen_x": screen_pos.x,
		"screen_y": screen_pos.y,
		"world_x": world_pos.x,
		"world_y": world_pos.y,
		"selected_count": selected.size(),
		"has_selected_units": _has_selected_units(),
		"has_selected_villagers": _has_selected_villagers(),
		"tapped_node_path": str(tapped_node.get_path()) if tapped_node != null else "",
		"tapped_node_distance_world": tapped_node_distance,
		"resource_node_path": str(resource_node.get_path()) if resource_node != null else "",
		"resource_node_distance_world": resource_node_distance,
		"unit_hit_radius_world": _screen_px_to_world_radius(touch_unit_hit_radius_px),
		"building_hit_radius_world": _screen_px_to_world_radius(touch_building_hit_radius_px),
		"resource_hit_radius_world": _screen_px_to_world_radius(touch_resource_hit_radius_px),
		"camera_zoom": camera_zoom,
		"target_tile_x": target_tile.x,
		"target_tile_y": target_tile.y,
	}


func _refresh_touch_target_diagnostics() -> void:
	if OS.has_feature("production"):
		return
	touch_target_diagnostics = {
		"units": _collect_touch_targets("units"),
		"buildings": _collect_touch_targets("buildings"),
		"resources": _collect_touch_targets("resources"),
	}


func _collect_touch_targets(group_name: String) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	for node in get_tree().get_nodes_in_group(group_name):
		if not _is_current_selection_entry(node):
			continue
		var node_2d: Node2D = node as Node2D
		if group_name == "resources" and not _is_resource_target_valid_for_local_player(node_2d):
			continue
		var screen_pos: Vector2 = _world_to_screen(node_2d.global_position)
		if screen_pos.x < -64.0 or screen_pos.x > viewport_size.x + 64.0:
			continue
		if screen_pos.y < -64.0 or screen_pos.y > viewport_size.y + 64.0:
			continue
		var target: Dictionary = {
			"path": str(node_2d.get_path()),
			"screen_x": screen_pos.x,
			"screen_y": screen_pos.y,
			"world_x": node_2d.global_position.x,
			"world_y": node_2d.global_position.y,
		}
		if node_2d is UnitBase:
			var unit: UnitBase = node_2d as UnitBase
			target["player_owner"] = unit.player_owner
			target["unit_type"] = unit.unit_type
		elif node_2d is BuildingBase:
			var building: BuildingBase = node_2d as BuildingBase
			target["player_owner"] = building.player_owner
		elif node_2d is ResourceNode:
			var resource: ResourceNode = node_2d as ResourceNode
			target["resource_type"] = resource.resource_type
		targets.append(target)
	return targets


func _screen_px_to_world_radius(radius_px: float) -> float:
	var zoom: float = _get_camera_zoom_scalar()
	return maxf(MIN_TOUCH_HIT_RADIUS_WORLD, radius_px / zoom)


func _should_ignore_mouse_input() -> bool:
	if _last_touch_input_msec <= 0:
		return false
	return (Time.get_ticks_msec() - _last_touch_input_msec) <= MOUSE_AFTER_TOUCH_IGNORE_MS


func _get_camera_zoom_scalar() -> float:
	if game_map != null:
		var camera_node: Node = game_map.get_node_or_null("Camera2D")
		if camera_node is Camera2D:
			return maxf(0.25, (camera_node as Camera2D).zoom.x)
	return 1.0


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
