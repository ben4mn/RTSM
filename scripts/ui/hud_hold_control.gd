class_name HUDHoldControl
extends Node
## Optional GUI hold inspection/chooser. Native BaseButton short clicks remain
## intact; a consumed/canceled contact is intercepted through its final release.
## Attach under a persistent CanvasLayer/GUI owner, not under the target Button.

signal surface_opened(kind: String)
signal surface_closed()
signal choice_selected(action_id: Variant)
signal ownership_started(contact_id: int)
signal ownership_finished(contact_id: int)

const HOLD_MSEC: int = 450
const MOVE_TOLERANCE: float = 12.0
const MOUSE_CONTACT: int = -2
const NO_CONTACT: int = -999999
const EMULATED_MOUSE_DEVICE: int = -1
const THEME_SCRIPT := preload("res://scripts/ui/kingdom_theme.gd")
const DISMISS_SHIELD := preload("res://scripts/ui/modal_dismiss_shield.gd")
const INFO_FOOTER: String = "Release to close · Tap Info for all details"

# Paid finite repetition opts in; world holds keep their existing meaning.
var repeat_action: Callable = Callable()
var repeat_interval_msec: int = 240
var _next_repeat_msec: int = 0
var _repeat_count: int = 0
var hold_enabled: bool = true
var hold_msec: int = HOLD_MSEC
var move_tolerance: float = MOVE_TOLERANCE
var admission_provider: Callable = Callable()
var _button: Button
var _info_provider: Callable
var _context_provider: Callable
var _safe_area_provider: Callable
var _choices_provider: Callable
var _contact: int = NO_CONTACT
var _started_msec: int = 0
var _press_position: Vector2 = Vector2.ZERO
var _current_position: Vector2 = Vector2.ZERO
var _max_displacement: float = 0.0
var _context: Variant = null
var _consumed: bool = false
var _canceled: bool = false
var _native_mouse_seen: bool = false
var _awaiting_native_release: bool = false
var _native_release_allowed: bool = false
var _native_mouse_released: bool = false
var _provisional_touch: bool = false
var _popup: Control
var _preview: Label
var _progress: ProgressBar
var _choices: Array[Dictionary] = []
var _choice_rects: Array[Rect2] = []
var _choice_controls: Array[Button] = []
var _choice_index: int = -1
var _neutral_rect: Rect2 = Rect2()
var _frozen_safe_rect: Rect2 = Rect2()
var _info: Dictionary = {}
var _blocked_contacts: Dictionary = {}
var _retire_when_released: bool = false
var _surface_visible: bool = false
var _tooltip_saved: bool = false
var _tooltip_text: String = ""
var _scroll_parent: ScrollContainer
var _scroll_origin: Vector2 = Vector2.ZERO
var _scrolling: bool = false
static var _active_owner: WeakRef
static var _orphaned_touch_contacts: Dictionary = {}
static var _orphaned_mouse_release: bool = false


static func attach_to(button: Button, popup_parent: Node, info_provider: Callable, context_provider: Callable = Callable(), safe_area_provider: Callable = Callable(), choices_provider: Callable = Callable()) -> HUDHoldControl:
	var control := HUDHoldControl.new()
	control._button = button
	control._info_provider = info_provider
	control._context_provider = context_provider
	control._safe_area_provider = safe_area_provider
	control._choices_provider = choices_provider
	control.name = "Hold_%s" % button.name
	control.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_parent.add_child(control)
	button.set_meta("hud_hold_control", control)
	return control


func _ready() -> void:
	get_viewport().size_changed.connect(_on_resize)
	get_window().focus_exited.connect(_on_focus_lost)
	set_process_input(true)


func get_info() -> Dictionary:
	var restoring: bool = _tooltip_saved and is_instance_valid(_button) and _button.tooltip_text.is_empty()
	if restoring:
		_button.tooltip_text = _tooltip_text
	var result: Dictionary = {}
	if _info_provider.is_valid():
		var value: Variant = _info_provider.call()
		if value is Dictionary:
			result = value.duplicate(true)
	if restoring:
		_suppress_tooltip()
	return result


func get_visible_bounds() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if is_instance_valid(_popup) and _popup.is_visible_in_tree():
		result.append(_popup.get_global_rect())
	if is_instance_valid(_preview) and _preview.is_visible_in_tree():
		result.append(_preview.get_global_rect())
	if is_instance_valid(_progress) and _progress.is_visible_in_tree():
		result.append(_progress.get_global_rect())
	return result


func is_gesture_active() -> bool:
	return _contact != NO_CONTACT or _awaiting_native_release or not _blocked_contacts.is_empty()


func get_choice_rects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(_choice_rects.size()):
		result.append({"id": _choices[index].get("id"), "rect": _choice_rects[index], "enabled": _choices[index].get("enabled", true)})
	return result


func cancel_gesture(_reason: String = "external") -> void:
	if _contact != NO_CONTACT and not _canceled:
		_playtest_event("gui_contact_cancel", {"reason": _reason})
	_scrolling = false
	if _contact == NO_CONTACT:
		_hide_surface()
		return
	_canceled = true
	_consumed = true
	_reset_native_button()
	_suppress_tooltip()
	_hide_surface()
	_hide_progress()


func detach() -> void:
	_clear_button_registration()
	cancel_gesture("detached")
	if is_gesture_active():
		_retire_when_released = true
	else:
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_focus_lost()


func _exit_tree() -> void:
	_clear_button_registration()
	_orphan_contact()


func _on_resize() -> void:
	cancel_gesture("resize")


func _on_focus_lost() -> void:
	cancel_gesture("focus")
	# Backgrounding can drop the final OS release. Keep orphan releases GUI-owned
	# while permitting a fresh press after focus returns.
	_orphan_contact()


func _process(_delta: float) -> void:
	if _contact == NO_CONTACT:
		return
	_suppress_tooltip()
	if not _context_valid() or not _target_visible():
		cancel_gesture("invalid_context")
		return
	if _canceled:
		return
	if _consumed and repeat_action.is_valid():
		if Time.get_ticks_msec() >= _next_repeat_msec:
			_repeat_once()
		return
	var elapsed: int = Time.get_ticks_msec() - _started_msec
	if not _consumed:
		if is_instance_valid(_progress):
			_progress.value = clampf(float(elapsed) / maxf(1.0, float(hold_msec)), 0.0, 1.0)
		if elapsed >= hold_msec and _holds_allowed():
			_activate_hold()


func _input(event: InputEvent) -> void:
	var owner: HUDHoldControl = _active_owner.get_ref() as HUDHoldControl if _active_owner != null else null
	if owner != null and owner != self:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _orphaned_touch_contacts.has(drag.index) or _blocked_contacts.has(drag.index) or (_orphaned_mouse_release and drag.device == EMULATED_MOUSE_DEVICE):
			get_viewport().set_input_as_handled()
		elif _contact == drag.index or (_contact == MOUSE_CONTACT and drag.device == EMULATED_MOUSE_DEVICE):
			_handle_motion(_to_logical(drag.position))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orphaned_mouse_release or not _blocked_contacts.is_empty():
			get_viewport().set_input_as_handled()
		if _contact != NO_CONTACT:
			if _contact == MOUSE_CONTACT or motion.device == EMULATED_MOUSE_DEVICE:
				_handle_motion(_to_logical(motion.position))
			if _consumed or _canceled:
				get_viewport().set_input_as_handled()


func _handle_touch(event: InputEventScreenTouch) -> void:
	# Once the initiating finger ends, all additional contacts still belong
	# to its canceled gesture until they drain. A third finger cannot rearm it.
	if _contact == NO_CONTACT and not _blocked_contacts.is_empty():
		var guarded_id: int = MOUSE_CONTACT if event.device == EMULATED_MOUSE_DEVICE else event.index
		if event.pressed:
			_blocked_contacts[guarded_id] = true
		elif _blocked_contacts.has(guarded_id):
			_blocked_contacts.erase(guarded_id)
			if guarded_id == MOUSE_CONTACT:
				_awaiting_native_release = true
				_native_release_allowed = false
		get_viewport().set_input_as_handled()
		_finish_if_drained()
		return
	# Desktop projects can also emulate touch from a physical mouse. Godot
	# dispatches that synthetic touch before the original native mouse event.
	# Own it as one mouse contact; never emit a second fallback pressed signal.
	if event.device == EMULATED_MOUSE_DEVICE:
		if not event.pressed and _blocked_contacts.has(MOUSE_CONTACT):
			_blocked_contacts.erase(MOUSE_CONTACT)
			get_viewport().set_input_as_handled()
			_finish_if_drained()
			return
		if event.pressed:
			_orphaned_mouse_release = false
		if not event.pressed and _orphaned_mouse_release:
			get_viewport().set_input_as_handled()
			return
		if event.pressed and _contact == NO_CONTACT and _can_admit(_to_logical(event.position)):
			_begin_contact(MOUSE_CONTACT, _to_logical(event.position))
			_native_mouse_seen = true
		elif _contact == MOUSE_CONTACT:
			if event.canceled:
				cancel_gesture("os_cancel")
			if not event.pressed:
				_prepare_release(_to_logical(event.position))
		elif _contact != NO_CONTACT:
			if event.pressed:
				_blocked_contacts[MOUSE_CONTACT] = true
			cancel_gesture("second_mouse_contact")
		if _contact != NO_CONTACT:
			get_viewport().set_input_as_handled()
		return
	if event.pressed:
		_orphaned_touch_contacts.erase(event.index)
	elif _orphaned_touch_contacts.has(event.index):
		_orphaned_touch_contacts.erase(event.index)
		get_viewport().set_input_as_handled()
		return
	if _blocked_contacts.has(event.index):
		get_viewport().set_input_as_handled()
		if not event.pressed:
			_blocked_contacts.erase(event.index)
			_finish_if_drained()
		return
	if event.pressed:
		# Input emits touch-derived mouse down before ScreenTouch. Adopt that
		# provisional press rather than interpreting the real finger as finger2.
		if _provisional_touch and _contact == MOUSE_CONTACT:
			_provisional_touch = false
			_contact = event.index
			ownership_started.emit(event.index)
			get_viewport().set_input_as_handled()
			return
		if _contact != NO_CONTACT:
			if event.index != _contact:
				_blocked_contacts[event.index] = true
				cancel_gesture("second_contact")
			get_viewport().set_input_as_handled()
			return
		if _can_admit(_to_logical(event.position)):
			_begin_contact(event.index, _to_logical(event.position))
			get_viewport().set_input_as_handled()
	elif _contact == event.index:
		get_viewport().set_input_as_handled()
		if event.canceled:
			cancel_gesture("os_cancel")
		_release_contact(_to_logical(event.position), true)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var emulated: bool = event.device == EMULATED_MOUSE_DEVICE
	var position: Vector2 = _to_logical(event.position)
	if _contact == NO_CONTACT and not event.pressed and _awaiting_native_release:
		_awaiting_native_release = false
		if not _native_release_allowed:
			get_viewport().set_input_as_handled()
		_finish_if_drained()
		return
	if _contact == NO_CONTACT and not _blocked_contacts.is_empty():
		get_viewport().set_input_as_handled()
		return
	if event.pressed:
		_orphaned_mouse_release = false
	elif _orphaned_mouse_release:
		_orphaned_mouse_release = false
		get_viewport().set_input_as_handled()
		return
	if not emulated and _contact >= 0:
		if event.pressed:
			cancel_gesture("second_mouse_contact")
		get_viewport().set_input_as_handled()
		return
	if emulated:
		if _contact == NO_CONTACT and event.pressed:
			if _can_admit(position):
				_begin_contact(MOUSE_CONTACT, position, true)
				_native_mouse_seen = true
			return
		if _contact != NO_CONTACT and _contact != MOUSE_CONTACT:
			_native_mouse_seen = true
			if event.canceled:
				cancel_gesture("os_cancel")
			_handle_motion(position)
			if not event.pressed:
				# Validate BEFORE native BaseButton release can run a paid action.
				_prepare_release(position)
				_native_mouse_released = true
			if _consumed or _canceled or not _target_visible():
				get_viewport().set_input_as_handled()
			return
	if event.pressed and _contact == NO_CONTACT:
		if _can_admit(position):
			_begin_contact(MOUSE_CONTACT, position)
			_native_mouse_seen = true
	elif not event.pressed and _contact == MOUSE_CONTACT:
		if event.canceled:
			cancel_gesture("os_cancel")
		_prepare_release(position)
		var consume_release: bool = _consumed or _canceled
		_release_contact(position, false)
		if consume_release:
			get_viewport().set_input_as_handled()


func _begin_contact(contact: int, position: Vector2, provisional: bool = false) -> void:
	_contact = contact
	_started_msec = Time.get_ticks_msec()
	_press_position = position
	_current_position = position
	_max_displacement = 0.0
	_context = _context_provider.call() if _context_provider.is_valid() else null
	_consumed = false
	_canceled = false
	_native_mouse_seen = false
	_awaiting_native_release = false
	_native_release_allowed = false
	_native_mouse_released = false
	_provisional_touch = provisional
	_choice_index = -1
	_tooltip_saved = false
	_tooltip_text = ""
	_suppress_tooltip()
	_active_owner = weakref(self)
	if not provisional:
		ownership_started.emit(contact)
	_scroll_parent = _find_scroll_parent()
	_scroll_origin = Vector2(_scroll_parent.scroll_horizontal, _scroll_parent.scroll_vertical) if is_instance_valid(_scroll_parent) else Vector2.ZERO
	_scrolling = false
	_playtest_event("gui_contact_begin", {"provisional_mouse": provisional})
	_show_progress()


func _handle_motion(position: Vector2) -> void:
	_current_position = position
	_max_displacement = maxf(_max_displacement, position.distance_to(_press_position))
	if _scrolling:
		if is_instance_valid(_scroll_parent) and _scroll_parent.is_visible_in_tree():
			_scroll_from_origin(position)
		else:
			cancel_gesture("scroll_parent_removed")
		return
	if _canceled:
		return
	if _consumed and not _choices.is_empty():
		_preview_choice(position)
	elif _max_displacement > move_tolerance:
		var can_scroll: bool = not _consumed and is_instance_valid(_scroll_parent) and _scroll_parent.is_visible_in_tree()
		cancel_gesture("movement")
		if can_scroll:
			_scrolling = true
			_playtest_event("gui_scroll_begin", {"scroll_origin": [_scroll_origin.x, _scroll_origin.y]})
			_scroll_from_origin(position)


func _find_scroll_parent() -> ScrollContainer:
	var ancestor: Node = _button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor as ScrollContainer
		ancestor = ancestor.get_parent()
	return null


func _scroll_from_origin(position: Vector2) -> void:
	# Mouse emulation and ScreenDrag may both report the same pose. Deriving
	# from the immutable press offset prevents adding displacement twice.
	var desired: Vector2 = _scroll_origin + _press_position - position
	if _scroll_parent.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		var horizontal: HScrollBar = _scroll_parent.get_h_scroll_bar()
		_scroll_parent.scroll_horizontal = int(clampf(desired.x, horizontal.min_value, maxf(horizontal.min_value, horizontal.max_value - horizontal.page)))
	if _scroll_parent.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		var vertical: VScrollBar = _scroll_parent.get_v_scroll_bar()
		_scroll_parent.scroll_vertical = int(clampf(desired.y, vertical.min_value, maxf(vertical.min_value, vertical.max_value - vertical.page)))


func _prepare_release(position: Vector2) -> void:
	_current_position = position
	_max_displacement = maxf(_max_displacement, position.distance_to(_press_position))
	if not _context_valid() or not _target_visible():
		cancel_gesture("invalid_release_context")
	if not _consumed and _max_displacement > move_tolerance:
		cancel_gesture("release_movement")
	if not _consumed and not _canceled and Time.get_ticks_msec() - _started_msec >= hold_msec and _holds_allowed():
		_activate_hold()


func _release_contact(position: Vector2, touch: bool) -> void:
	_prepare_release(position)
	var action: Variant = null
	if _consumed and not _canceled and not _choices.is_empty():
		_preview_choice(position)
		if _choice_index >= 0 and bool(_choices[_choice_index].get("enabled", true)):
			action = _choices[_choice_index].get("id")
	var short_tap: bool = not _consumed and not _canceled and _target_visible() and _button.get_global_rect().has_point(position) and not _button.disabled
	_playtest_event("gui_contact_release", {
		"outcome": "scroll" if _scrolling else ("choice" if action != null else ("tap" if short_tap else ("canceled" if _canceled else "inspect"))),
		"choice": action,
	})
	_native_release_allowed = short_tap
	_awaiting_native_release = touch and _native_mouse_seen and not _native_mouse_released
	_scrolling = false
	_restore_tooltip()
	_hide_surface()
	_hide_progress()
	var ended_contact: int = _contact
	_contact = NO_CONTACT
	_provisional_touch = false
	ownership_finished.emit(ended_contact)
	_finish_if_drained()
	if short_tap and touch and not _native_mouse_seen and is_instance_valid(_button):
		# Without mouse emulation BaseButton has no native touch-click. Preserve
		# its existing pressed listeners and toggled state as the fallback.
		if _button.toggle_mode:
			_button.button_pressed = not _button.button_pressed
		_button.pressed.emit()
	if action != null:
		choice_selected.emit(action)


func _activate_hold() -> void:
	if _canceled or _consumed or not _context_valid():
		return
	_playtest_event("gui_hold_activated")
	_consumed = true
	_reset_native_button()
	_hide_progress()
	if repeat_action.is_valid():
		_repeat_count = 0
		_repeat_once()
		return
	_info = get_info()
	_choices.clear()
	if _choices_provider.is_valid():
		var result: Variant = _choices_provider.call()
		if result is Array:
			for choice: Variant in result:
				if choice is Dictionary and _choices.size() < 4:
					_choices.append(choice.duplicate(true))
	_frozen_safe_rect = _get_safe_rect()
	_surface_visible = true
	surface_opened.emit("chooser" if not _choices.is_empty() else "info")
	if _canceled:
		return
	if _choices.is_empty():
		_show_info()
	else:
		_show_chooser()


func _repeat_once() -> void:
	_next_repeat_msec = Time.get_ticks_msec() + repeat_interval_msec
	if not _holds_allowed() or _button.disabled or not _context_valid() or not _button.get_global_rect().has_point(_current_position) or not bool(repeat_action.call()):
		cancel_gesture("repeat_limit")
		return
	_repeat_count += 1
	if not is_instance_valid(_progress):
		_show_progress()
	if is_instance_valid(_progress):
		_progress.value = 1.0
	if not is_instance_valid(_preview):
		_preview = Label.new()
		_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview.add_theme_font_size_override("font_size", 12)
		_preview.z_index = 200
		_preview.position = _button.get_global_rect().position - Vector2(0, 24)
		add_child(_preview)
	_preview.text = "+%d queued · release to stop" % _repeat_count


func _context_valid() -> bool:
	if not is_instance_valid(_button) or not _button.is_inside_tree():
		return false
	return not _context_provider.is_valid() or _context_provider.call() == _context


func _target_visible() -> bool:
	return is_instance_valid(_button) and _button.is_inside_tree() and _button.is_visible_in_tree()


func _can_admit(position: Vector2) -> bool:
	if DISMISS_SHIELD.has_owned_contact() or _retire_when_released or not _target_visible():
		return false
	if admission_provider.is_valid() and not bool(admission_provider.call()):
		return false
	if not _button.get_global_rect().has_point(position):
		return false
	var ancestor: Node = _button.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents and not (ancestor as Control).get_global_rect().has_point(position):
			return false
		ancestor = ancestor.get_parent()
	return true


func _holds_allowed() -> bool:
	var preference: Variant = GameManager.get("hold_shortcuts_enabled")
	return hold_enabled and (preference == null or bool(preference))


func _orphan_contact() -> void:
	_scrolling = false
	_restore_tooltip()
	if _contact >= 0:
		_orphaned_touch_contacts[_contact] = true
	for id: Variant in _blocked_contacts:
		if int(id) == MOUSE_CONTACT:
			_orphaned_mouse_release = true
		else:
			_orphaned_touch_contacts[id] = true
	if _native_mouse_seen and not _native_mouse_released:
		_orphaned_mouse_release = true
	var ended_contact: int = _contact
	_contact = NO_CONTACT
	_awaiting_native_release = false
	_provisional_touch = false
	_blocked_contacts.clear()
	if ended_contact != NO_CONTACT:
		ownership_finished.emit(ended_contact)
	_finish_if_drained()


func _clear_button_registration() -> void:
	if is_instance_valid(_button) and _button.has_meta("hud_hold_control") and _button.get_meta("hud_hold_control") == self:
		_button.remove_meta("hud_hold_control")


func _suppress_tooltip() -> void:
	if is_instance_valid(_button) and not _button.tooltip_text.is_empty():
		_tooltip_text = _button.tooltip_text
		_tooltip_saved = true
		_button.tooltip_text = ""


func _restore_tooltip() -> void:
	if _tooltip_saved and is_instance_valid(_button) and _button.tooltip_text.is_empty():
		_button.tooltip_text = _tooltip_text
	_tooltip_saved = false
	_tooltip_text = ""


func _to_logical(position: Vector2) -> Vector2:
	# Viewport transforms OS/parse_input_event positions before Node._input.
	# The incoming position is already in viewport logical coordinates.
	return position


func _playtest_event(kind: String, extra: Dictionary = {}) -> void:
	if not is_inside_tree():
		return
	var recorder: Node = get_node_or_null("/root/PlaytestDiagnostics")
	if recorder == null:
		return
	var fields: Dictionary = {
		"control": str(_button.name) if is_instance_valid(_button) else "detached",
		"contact_id": _contact,
		"position": [_current_position.x, _current_position.y],
		"start": [_press_position.x, _press_position.y],
		"duration_ms": maxi(0, Time.get_ticks_msec() - _started_msec),
		"maximum_movement": _max_displacement,
		"move_tolerance": move_tolerance,
		"hold_msec": hold_msec,
	}
	fields.merge(extra)
	recorder.call("record_event", kind, fields)


func _get_safe_rect() -> Rect2:
	var view: Rect2 = get_viewport().get_visible_rect()
	if _safe_area_provider.is_valid():
		var value: Variant = _safe_area_provider.call()
		if value is Rect2 and value.has_area():
			return value.intersection(view)
	return view


func _reset_native_button() -> void:
	if is_instance_valid(_button):
		# Godot's BaseButton focus-exit notification clears press_attempt and
		# button_down state without toggling/spending or mutating affordability.
		_button.notification(Control.NOTIFICATION_FOCUS_EXIT)


func _show_progress() -> void:
	if not _holds_allowed():
		return
	_progress = ProgressBar.new()
	_progress.name = "HoldProgress"
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.size = Vector2(maxf(16.0, _button.size.x - 12.0), 3.0)
	_progress.position = _button.get_global_rect().position + Vector2(6.0, _button.size.y - 5.0)
	_progress.theme = THEME_SCRIPT.create_theme()
	_progress.z_index = 200
	add_child(_progress)


func _show_info() -> void:
	var maximum_width: float = minf(440.0, maxf(48.0, _frozen_safe_rect.size.x - 16.0))
	var width: float = minf(320.0, maximum_width)
	var maximum_height: float = maxf(48.0, _frozen_safe_rect.size.y - 16.0)
	var title: String = str(_info.get("title", _button.text))
	var body: String = str(_info.get("body", "Hold to inspect. Release to close."))
	var natural_height: float = _info_height(title, body, width)
	while natural_height > maximum_height and width < maximum_width:
		width = minf(maximum_width, width + 32.0)
		natural_height = _info_height(title, body, width)
	var height: float = minf(maximum_height, maxf(72.0, natural_height))
	# A plain bounded panel prevents a long Label minimum from growing the
	# presentation outside safe bounds. Held bodies are clipped previews;
	# the pinned footer points to the scrollable persistent tap Info alternative.
	var panel := Panel.new()
	panel.name = "HoldInfo"
	panel.theme = THEME_SCRIPT.create_theme()
	panel.add_theme_stylebox_override("panel", THEME_SCRIPT.panel_style(THEME_SCRIPT.INK_PANEL, THEME_SCRIPT.TEAL, 10))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.clip_contents = true
	panel.size = Vector2(width, height)
	panel.position = _clamp_position(Vector2(_press_position.x - width * 0.5, _press_position.y - height - 24.0), panel.size)
	panel.z_index = 200
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)
	var heading := Label.new()
	heading.name = "HoldInfoTitle"
	heading.text = title
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", THEME_SCRIPT.AMBER)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.name = "HoldInfoBodyClip"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var description := Label.new()
	description.name = "HoldInfoBody"
	description.text = body
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("font_size", 15)
	scroll.add_child(description)
	var footer := Label.new()
	footer.name = "HoldInfoFooter"
	footer.text = INFO_FOOTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", THEME_SCRIPT.AMBER)
	box.add_child(footer)
	_popup = panel


func _info_height(title: String, body: String, width: float) -> float:
	var content_width: float = maxf(16.0, width - 28.0)
	return _wrapped_text_height(body, 15, content_width) + _wrapped_text_height(title, 16, content_width) + _wrapped_text_height(INFO_FOOTER, 12, content_width) + 38.0


func _wrapped_text_height(value: String, font_size: int, width: float) -> float:
	# Measure actual Label wrapping/line spacing, including the footer budget,
	# before widening a long preview to fit the available reading area.
	var measure := Label.new()
	measure.theme = THEME_SCRIPT.create_theme()
	measure.text = value
	measure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	measure.add_theme_font_size_override("font_size", font_size)
	measure.size = Vector2(width, 0.0)
	measure.hide()
	add_child(measure)
	var height: float = measure.get_minimum_size().y
	measure.free()
	return height


func _show_chooser() -> void:
	var count: int = _choices.size()
	var choice_width: float = 108.0
	var gap: float = 6.0
	var width: float = count * choice_width + (count - 1) * gap + 16.0
	var height: float = 98.0
	var panel := Panel.new()
	panel.name = "HoldChooser"
	panel.theme = THEME_SCRIPT.create_theme()
	panel.add_theme_stylebox_override("panel", THEME_SCRIPT.panel_style(THEME_SCRIPT.INK_PANEL, THEME_SCRIPT.TEAL, 12))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size = Vector2(width, height)
	panel.position = _clamp_position(Vector2(_press_position.x - width * 0.5, _press_position.y - height - 42.0), panel.size)
	panel.z_index = 200
	add_child(panel)
	_popup = panel
	_choice_rects.clear()
	_choice_controls.clear()
	for index: int in range(count):
		var choice := Button.new()
		choice.text = str(_choices[index].get("label", "Command"))
		choice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		choice.focus_mode = Control.FOCUS_NONE
		choice.size = Vector2(choice_width, 56.0)
		choice.position = Vector2(8.0 + index * (choice_width + gap), 25.0 if index == 0 or index == count - 1 else 8.0)
		choice.add_theme_font_size_override("font_size", 14)
		choice.disabled = not bool(_choices[index].get("enabled", true))
		panel.add_child(choice)
		_choice_controls.append(choice)
		_choice_rects.append(choice.get_global_rect())
	_preview = Label.new()
	_preview.name = "HoldPreview"
	_preview.text = "Slide to choose · release outside to cancel"
	_preview.theme = THEME_SCRIPT.create_theme()
	_preview.add_theme_font_size_override("font_size", 14)
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.size = Vector2(width, 24.0)
	_preview.position = _clamp_position(panel.position - Vector2(0.0, 28.0), _preview.size)
	_preview.z_index = 201
	add_child(_preview)
	_neutral_rect = Rect2(_press_position - Vector2(24.0, 24.0), Vector2(48.0, 48.0))
	_preview_choice(_current_position)


func _preview_choice(position: Vector2) -> void:
	_choice_index = -1
	if not _neutral_rect.has_point(position):
		for index: int in range(_choice_rects.size()):
			if _choice_rects[index].has_point(position):
				_choice_index = index
				break
	for index: int in range(_choice_controls.size()):
		var control: Button = _choice_controls[index]
		if index == _choice_index:
			THEME_SCRIPT.apply_primary(control)
		else:
			THEME_SCRIPT.apply_secondary(control)
	if is_instance_valid(_preview):
		_preview.text = str(_choices[_choice_index].get("description", _choices[_choice_index].get("label", "Command"))) if _choice_index >= 0 else "Return to start or release outside to cancel"


func _clamp_position(desired: Vector2, dimensions: Vector2) -> Vector2:
	var safe: Rect2 = _frozen_safe_rect.grow(-8.0)
	return Vector2(clampf(desired.x, safe.position.x, maxf(safe.position.x, safe.end.x - dimensions.x)), clampf(desired.y, safe.position.y, maxf(safe.position.y, safe.end.y - dimensions.y)))


func _hide_surface() -> void:
	if is_instance_valid(_popup):
		_popup.queue_free()
		_popup.hide()
	_popup = null
	if is_instance_valid(_preview):
		_preview.queue_free()
		_preview.hide()
	_preview = null
	_choice_rects.clear()
	_choice_controls.clear()
	_choices.clear()
	_choice_index = -1
	if _surface_visible:
		_surface_visible = false
		surface_closed.emit()


func _hide_progress() -> void:
	if is_instance_valid(_progress):
		_progress.queue_free()
		_progress.hide()
	_progress = null


func _finish_if_drained() -> void:
	if _contact != NO_CONTACT or _awaiting_native_release or not _blocked_contacts.is_empty():
		return
	var owner: HUDHoldControl = _active_owner.get_ref() as HUDHoldControl if _active_owner != null else null
	if owner == self:
		_active_owner = null
	if _retire_when_released:
		queue_free()
