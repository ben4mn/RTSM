extends RefCounted
## Two quick taps on a panel's own background (padding, gaps, labels) tuck the
## panel away. Buttons accept their own contacts, so they never reach this.
## One gesture may watch several controls of the same panel: a contact that
## propagates from a child container to its panel is counted once.

const WINDOW_MSEC: int = 360
const SLOP: float = 36.0

var _on_double: Callable
var _on_single: Callable
var _last_msec: int = -100000
var _last_position: Vector2 = Vector2.INF
var _last_frame: int = -1


static func attach(targets: Array, on_double: Callable, on_single: Callable = Callable()) -> RefCounted:
	var gesture: RefCounted = (load("res://scripts/ui/double_tap_gesture.gd") as GDScript).new()
	gesture.set("_on_double", on_double)
	gesture.set("_on_single", on_single)
	for target: Control in targets:
		if target == null:
			continue
		target.set_meta("double_tap_gesture", gesture)
		target.gui_input.connect(Callable(gesture, "_on_gui_input").bind(target))
	return gesture


func reset() -> void:
	_last_msec = -100000
	_last_position = Vector2.INF


func _on_gui_input(event: InputEvent, target: Control) -> void:
	# Godot repeats a touch as an emulated pointer; count the contact once.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed and not event.canceled) or (
		event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	)
	if not pressed:
		return
	var frame: int = Engine.get_process_frames()
	if frame == _last_frame:
		return
	_last_frame = frame
	var now: int = Time.get_ticks_msec()
	# Contacts arrive in the receiving control's space; compare in canvas space.
	var global_position: Vector2 = target.get_global_transform() * (event as InputEventFromWindow).position
	if now - _last_msec <= WINDOW_MSEC and global_position.distance_to(_last_position) <= SLOP:
		reset()
		if _on_double.is_valid():
			_on_double.call()
		return
	_last_msec = now
	_last_position = global_position
	if _on_single.is_valid():
		_on_single.call()
