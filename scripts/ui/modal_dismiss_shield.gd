extends Control
## Outside dismissal retains the entire contact after the sheet disappears.

signal dismiss_requested()

var active: bool = false
var protected_rects: Array[Rect2] = []
var _contacts: Dictionary = {}
var _mouse_owned: bool = false
static var _owning_shields: Dictionary = {}


static func has_owned_contact() -> bool:
	return not _owning_shields.is_empty()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func set_active(enabled: bool) -> void:
	active = enabled
	visible = active or not _contacts.is_empty() or _mouse_owned
	if not _contacts.is_empty() or _mouse_owned:
		_owning_shields[get_instance_id()] = true
	else:
		_owning_shields.erase(get_instance_id())


func _exit_tree() -> void:
	_owning_shields.erase(get_instance_id())


func _has_point(point: Vector2) -> bool:
	if not _contacts.is_empty() or _mouse_owned:
		return true
	for rect: Rect2 in protected_rects:
		if rect.has_point(point + global_position):
			return false
	return Rect2(Vector2.ZERO, size).has_point(point)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and not touch.canceled:
			_contacts[touch.index] = true
			set_active(active)
			accept_event()
			if active:
				dismiss_requested.emit()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if mouse.device == InputEvent.DEVICE_ID_EMULATION:
				return
			if mouse.pressed:
				_mouse_owned = true
				set_active(active)
				if active:
					dismiss_requested.emit()
			else:
				_mouse_owned = false
				set_active(active)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not _contacts.is_empty():
			# A new finger during dismissal cannot start an unrelated action.
			if touch.pressed and not touch.canceled:
				_contacts[touch.index] = true
			elif _contacts.has(touch.index):
				_contacts.erase(touch.index)
			get_viewport().set_input_as_handled()
			set_active(active)
	elif event is InputEventScreenDrag:
		if _contacts.has((event as InputEventScreenDrag).index):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and _mouse_owned:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if not mouse.pressed:
				_mouse_owned = false
				set_active(active)
	elif event is InputEventMouseMotion and _mouse_owned:
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_contacts.clear()
		_mouse_owned = false
		set_active(active)
