extends Control
## Public objective annotation and two independent, recent owned attack fronts.
## Never changes fog or reads enemies. Ordinary toasts cannot retire these cards.

signal interaction_bounds_changed()

const FRONT_RADIUS: float = 320.0
const FRONT_LIFETIME: float = 20.0
const FRONT_SOUND_COOLDOWN: float = 8.0
var fronts: Array[Dictionary] = []
var _hud: CanvasLayer
var _map: Node2D
var _focus: Callable
var _lane: VBoxContainer
var _buttons: Array[Button] = []
var _site: Node2D
var _last_interaction_bounds: Array[Rect2] = []


func setup(hud: CanvasLayer, map: Node2D, focus: Callable) -> void:
	_hud = hud
	_map = map
	_focus = focus
	interaction_bounds_changed.connect(Callable(hud, "_refresh_dismissal_shield"))
	_site = map.get("sacred_site") as Node2D
	name = "BattlefieldFeedback"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lane = VBoxContainer.new()
	_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lane.add_theme_constant_override("separation", 4)
	add_child(_lane)
	for index: int in 2:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 48)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_stylebox_override("normal", KingdomTheme.button_style())
		button.add_theme_color_override("font_color", KingdomTheme.RUST)
		button.pressed.connect(_view_front.bind(index))
		button.button_down.connect(func() -> void:
			if _hud.has_signal("world_gesture_cancel_requested"):
				_hud.emit_signal("world_gesture_cancel_requested")
		)
		_lane.add_child(button)
		_buttons.append(button)
	_refresh()


func report_attack(target_name: String, world_position: Vector2) -> bool:
	var now: float = GameManager.game_time
	for front: Dictionary in fronts:
		if (front["position"] as Vector2).distance_to(world_position) <= FRONT_RADIUS:
			front["position"] = world_position
			front["target"] = target_name
			front["last_hit"] = now
			var sound_due: bool = now - float(front["last_sound"]) >= FRONT_SOUND_COOLDOWN
			if sound_due:
				front["last_sound"] = now
			_refresh()
			return sound_due
	# Retain the two most recently hit distinct locations. A busy front does not
	# throttle a new raid elsewhere, and production never enters this collection.
	if fronts.size() >= 2:
		fronts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["last_hit"]) < float(b["last_hit"]))
		fronts.pop_front()
	fronts.append({"position": world_position, "target": target_name, "last_hit": now, "last_sound": now})
	_refresh()
	return true


func _process(_delta: float) -> void:
	for index: int in range(fronts.size() - 1, -1, -1):
		if GameManager.game_time - float(fronts[index]["last_hit"]) > FRONT_LIFETIME:
			fronts.remove_at(index)
	_refresh()
	queue_redraw()


func report_loss(target_name: String, world_position: Vector2) -> void:
	report_attack(target_name, world_position)
	for front: Dictionary in fronts:
		if (front["position"] as Vector2).distance_to(world_position) <= FRONT_RADIUS:
			front["losses"] = int(front.get("losses", 0)) + 1
			front["last_loss"] = target_name
			break
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_hud) or _lane == null:
		return
	var field: bool = GameManager.current_state == GameManager.GameState.PLAYING
	visible = field
	var safe: Rect2 = _hud.call("get_hold_safe_rect")
	_lane.position = safe.position + Vector2(8, 0)
	# At Extra Large UI with a notch, only 96px remain above map navigation.
	# Preserve both 48px targets by using the top rail's four-pixel inset.
	var compact: bool = safe.size.y < 280.0
	_lane.add_theme_constant_override("separation", 0 if compact else 4)
	if compact:
		_lane.position.y -= 4.0
	var width: float = minf(224.0, safe.size.x * 0.34)
	var guidance: Control = _hud.get("_progression_hint_panel") as Control
	if is_instance_valid(guidance) and guidance.is_visible_in_tree():
		width = minf(width, guidance.get_global_rect().position.x - _lane.position.x - 8.0)
	var overview: Control = _hud.get("_strategy_overview") as Control
	if is_instance_valid(overview) and overview.get("panel").is_visible_in_tree():
		# Management leaves its right-hand launchers exposed. Keep attacks in
		# that same lane so the card never covers an urgent response target.
		var rail: Control = overview.get("rail")
		_lane.position.x = rail.get_global_rect().position.x
		width = rail.size.x
	_lane.size = Vector2(maxf(120.0, width), 100)
	for index: int in _buttons.size():
		var button: Button = _buttons[index]
		button.visible = index < fronts.size()
		if button.visible:
			var front: Dictionary = fronts[index]
			var age: int = maxi(0, int(GameManager.game_time - float(front["last_hit"])))
			var detail: String = "Under attack" if age < 3 else "%ds ago" % age
			if int(front.get("losses", 0)) > 0:
				detail = "Lost %d · %s" % [int(front["losses"]), str(front.get("last_loss", "unit"))]
			button.text = "RAID %d · %s\n%s · view" % [index + 1, str(front["target"]), detail]
			button.tooltip_text = "Recent attack on your %s. View location without changing selection." % str(front["target"])
	var feed: Control = _hud.get("_notification_container") as Control
	if is_instance_valid(feed):
		feed.visible = fronts.is_empty()
	var bounds: Array[Rect2] = get_visible_bounds()
	if bounds != _last_interaction_bounds:
		_last_interaction_bounds = bounds
		interaction_bounds_changed.emit()


func _view_front(index: int) -> void:
	if index < fronts.size() and GameManager.current_state == GameManager.GameState.PLAYING:
		_hud.call("close_secondary_surface")
		_focus.call(fronts[index]["position"])


func get_visible_bounds() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for button: Button in _buttons:
		if button.is_visible_in_tree():
			result.append(button.get_global_rect())
	return result


func _draw() -> void:
	if not is_instance_valid(_site) or not is_instance_valid(_map) or not visible:
		return
	# Render a map annotation above fog. Only this known location and its public
	# objective state are used; terrain, units and capture participants stay hidden.
	var center: Vector2 = _site.get_global_transform_with_canvas().origin
	var safe: Rect2 = _hud.call("get_world_safe_rect")
	if not safe.has_point(center):
		return
	var status: Dictionary = _site.call("get_status")
	var owner: int = int(status.get("owner", -1))
	var phase: String = str(status.get("phase", "neutral"))
	var color := KingdomTheme.PARCHMENT
	if owner == 0:
		color = KingdomTheme.TEAL
	elif owner == 1:
		color = KingdomTheme.RUST
	if phase in ["contested", "neutralizing"]:
		color = Color("c6b486")
	var camera: Camera2D = _map.get("camera") as Camera2D
	var radius: float = float(_site.call("get_capture_radius_world")) * camera.zoom.x
	draw_arc(center, radius, 0, TAU, 96, Color(color, 0.5), 2.0, true)
	draw_circle(center, 23, Color(KingdomTheme.INK, 0.95))
	draw_arc(center, 23, 0, TAU, 32, color, 2.5, true)
	draw_line(center + Vector2(-5, 12), center + Vector2(-5, -13), color, 3, true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-4,-13),center + Vector2(13,-7),center + Vector2(-4,0)]), color)
	var title: String = "SACRED SITE · enter ring"
	if phase == "contested" or phase == "neutralizing":
		title = "SACRED SITE · clock paused"
	elif phase == "holding":
		title = "SACRED SITE · " + ("defend" if owner == 0 else "enter to contest")
	var font: Font = KingdomTheme.FONT_MEDIUM
	var text_size: Vector2 = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var label_rect := Rect2(center + Vector2(-text_size.x * 0.5 - 6, 27), text_size + Vector2(12, 8))
	label_rect.position.x = clampf(label_rect.position.x, safe.position.x, maxf(safe.position.x, safe.end.x - label_rect.size.x))
	draw_style_box(KingdomTheme.panel_style(Color(KingdomTheme.INK, 0.95), color, 4), label_rect)
	draw_string(font, label_rect.position + Vector2(6, 17), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
