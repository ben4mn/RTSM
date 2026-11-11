class_name ToastLane
extends VBoxContainer
## One-line HUD messages in one consistent, unobstructed place: a centred
## column just under the top rail (below the guidance card while that shows).
## It never shares the alert column on the left (RAID cards, Undo, the bell
## shortcut), the command dock or the minimap.
##
## At most MAX_VISIBLE pills show. A new message of equal or higher priority
## replaces the oldest of the least important pills at once; a less important
## one waits for a free slot (only the latest such message is kept, briefly).
## Repeating a visible message only restarts its timer.
##
## Children are PanelContainers whose first child is the message Label.

enum Priority { LOW, NORMAL, HIGH }

const MAX_VISIBLE: int = 2
const MAX_WIDTH: float = 340.0
const PENDING_LIFETIME_MSEC: int = 5000
const FADE_SECONDS: float = 0.4
const ACTION_HEIGHT: float = 48.0
const FONT_SIZE: int = 13

var _pending: Array[Dictionary] = []
var _lane_width: float = MAX_WIDTH


func _init() -> void:
	name = "ToastLane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 4)


## `priority` < 0 infers it: tappable or long-lived messages are HIGH.
func push(text: String, color: Color = Color.WHITE, duration: float = 3.5, action: Callable = Callable(), priority: int = -1) -> void:
	if text.is_empty():
		return
	if priority < 0:
		priority = Priority.HIGH if action.is_valid() or duration > 3.75 else Priority.NORMAL
	var entry: Dictionary = {"text": text, "color": color, "duration": maxf(0.05, duration), "action": action, "priority": priority, "queued_msec": Time.get_ticks_msec()}
	for pill: PanelContainer in _live_pills():
		if str(pill.get_meta("toast_text", "")) == text:
			_restart(pill, entry)
			return
	for waiting: Dictionary in _pending:
		if str(waiting.text) == text:
			return
	var live: Array[PanelContainer] = _live_pills()
	if live.size() < MAX_VISIBLE:
		_show(entry)
		return
	var victim: PanelContainer = _victim_for(live, priority)
	if victim != null:
		_retire(victim)
		_show(entry)
		return
	if priority == Priority.LOW:
		return
	# Less important than everything showing: keep only the newest such message.
	_pending.clear()
	_pending.append(entry)


func clear() -> void:
	_pending.clear()
	for pill: PanelContainer in _live_pills():
		_retire(pill)


func dismiss(text: String) -> void:
	for index: int in range(_pending.size() - 1, -1, -1):
		if str(_pending[index].text) == text:
			_pending.remove_at(index)
	for pill: PanelContainer in _live_pills():
		if str(pill.get_meta("toast_text", "")) == text:
			_expire(pill)


func visible_count() -> int:
	return _live_pills().size()


## Place the lane. `left_limit` is the right edge of the alert column,
## `guidance` the guidance card's rectangle (no area when hidden). Coordinates
## are the HUD root's.
func place(safe: Rect2, top: float, left_limit: float, guidance: Rect2) -> void:
	var width: float = minf(MAX_WIDTH, safe.size.x - 16.0)
	var left: float = safe.position.x + (safe.size.x - width) * 0.5
	var right_limit: float = safe.end.x - 8.0
	if left < left_limit and left_limit + width <= right_limit:
		left = left_limit
	left = clampf(left, safe.position.x + 8.0, maxf(safe.position.x + 8.0, right_limit - width))
	var lane_top: float = top
	if guidance.has_area() and guidance.intersects(Rect2(left, top, width, ACTION_HEIGHT * 2.0 + 4.0)):
		lane_top = guidance.end.y + 6.0
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(left, lane_top)
	size = Vector2(width, 0.0)
	if not is_equal_approx(width, _lane_width):
		_lane_width = width
		for pill: PanelContainer in _live_pills():
			_fit(pill)


func _live_pills() -> Array[PanelContainer]:
	var pills: Array[PanelContainer] = []
	for child: Node in get_children():
		if child is PanelContainer and not child.is_queued_for_deletion() and not bool(child.get_meta("toast_retired", false)):
			pills.append(child as PanelContainer)
	return pills


func _victim_for(live: Array[PanelContainer], priority: int) -> PanelContainer:
	## The oldest of the least important pills, if the newcomer matters as much.
	var victim: PanelContainer = null
	for pill: PanelContainer in live:
		if victim == null or int(pill.get_meta("toast_priority", 0)) < int(victim.get_meta("toast_priority", 0)):
			victim = pill
	if victim != null and int(victim.get_meta("toast_priority", 0)) <= priority:
		return victim
	return null


func _show(entry: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var action: Callable = entry.action
	if action.is_valid():
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.custom_minimum_size.y = ACTION_HEIGHT
		panel.gui_input.connect(func(event: InputEvent) -> void:
			# Godot may deliver the same contact again as an emulated pointer.
			if event.device == InputEvent.DEVICE_ID_EMULATION:
				panel.accept_event()
				return
			if (event is InputEventScreenTouch and event.pressed and not event.canceled) or (
				event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
			):
				panel.accept_event()
				if bool(panel.get_meta("toast_answered", false)):
					return
				# H: a tapped offer has been answered: it fades and leaves once
				# the finger has lifted (the pill keeps owning that release so it
				# cannot fall through to the map as a ground tap).
				panel.set_meta("toast_answered", true)
				panel.modulate.a = 0.45
				get_tree().create_timer(0.35, true, false, true).timeout.connect(func() -> void:
					if is_instance_valid(panel) and panel.get_parent() == self:
						_retire(panel))
				action.call()
			elif (event is InputEventScreenTouch or event is InputEventMouseButton) and not event.pressed:
				panel.accept_event()
		)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(KingdomTheme.INK, 0.94)
	style.border_color = entry.color
	style.border_width_left = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.04, 0.08, 0.07, 0.25)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 1)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = entry.text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.clip_text = false
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_font_override("font", KingdomTheme.FONT_BODY)
	label.add_theme_constant_override("line_spacing", 0)
	label.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	panel.set_meta("toast_text", entry.text)
	panel.set_meta("toast_priority", int(entry.priority))
	panel.set_meta("toast_shown_msec", Time.get_ticks_msec())
	panel.set_meta("toast_tappable", action.is_valid())
	add_child(panel)
	# H: tappable offers sit above plain messages, so an expiring note never
	# slides an offer up from under the finger that is about to tap it.
	if action.is_valid():
		var slot: int = 0
		for child: Node in get_children():
			if child != panel and bool(child.get_meta("toast_tappable", false)) and not bool(child.get_meta("toast_retired", false)):
				slot = maxi(slot, child.get_index() + 1)
		move_child(panel, mini(slot, get_child_count() - 1))
	_fit(panel)
	if not GameManager.reduced_motion:
		panel.modulate.a = 0.0
	_schedule(panel, float(entry.duration), not GameManager.reduced_motion)


func _restart(pill: PanelContainer, entry: Dictionary) -> void:
	pill.set_meta("toast_priority", maxi(int(pill.get_meta("toast_priority", 0)), int(entry.priority)))
	_schedule(pill, float(entry.duration), false)


func _schedule(pill: PanelContainer, duration: float, fade_in: bool) -> void:
	var previous: Variant = pill.get_meta("toast_tween") if pill.has_meta("toast_tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	var tween: Tween = pill.create_tween()
	if fade_in:
		tween.tween_property(pill, "modulate:a", 1.0, 0.12)
	else:
		pill.modulate.a = 1.0
	tween.tween_interval(duration)
	tween.tween_property(pill, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(_expire.bind(pill))
	pill.set_meta("toast_tween", tween)


func _expire(pill: PanelContainer) -> void:
	_retire(pill)
	var now: int = Time.get_ticks_msec()
	while not _pending.is_empty() and _live_pills().size() < MAX_VISIBLE:
		var entry: Dictionary = _pending.pop_front()
		if now - int(entry.queued_msec) <= PENDING_LIFETIME_MSEC:
			_show(entry)


func _retire(pill: PanelContainer) -> void:
	if not is_instance_valid(pill) or pill.is_queued_for_deletion():
		return
	# Stay in the tree until any input dispatch has unwound, out of the layout.
	pill.set_meta("toast_retired", true)
	pill.visible = false
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.name = "RetiredToast_%d" % pill.get_instance_id()
	pill.queue_free()


func _fit(pill: PanelContainer) -> void:
	## Short messages hug their words; long ones wrap at the lane width.
	var label := pill.get_child(0) as Label
	var style: StyleBox = pill.get_theme_stylebox("panel")
	var inner: float = maxf(40.0, _lane_width - style.get_minimum_size().x)
	var font: Font = label.get_theme_font("font")
	var natural: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	if natural <= inner and not label.text.contains("\n"):
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size = Vector2.ZERO
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var wrapped: Vector2 = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, inner, FONT_SIZE, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
		label.custom_minimum_size = Vector2(inner, ceilf(wrapped.y))
