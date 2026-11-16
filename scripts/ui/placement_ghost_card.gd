class_name PlacementGhostCard
extends Control
## L2: the building placement controls live on the ghost itself.
##
## While placing (touch): a big "Build" button with the cost sits right under
## the ghost's footprint, and a small x beside it cancels. When the ground does
## not fit, the same button names the reason instead (tapping it explains).
## After a House or Farm is placed: a "+1 House" button appears on the new
## foundation for a few seconds, so a row of them is Build, +1, Build, +1 ...
## with the thumb in one place, and never a silent repeat.
##
## The card follows the ghost every frame and keeps clear of HUD panels and
## the screen edge (below the footprint, else above the art, else beside it).

signal confirm_requested()
signal cancel_requested()
signal repeat_requested(building_type: int, anchor: Node2D)

const BUTTON_HEIGHT: float = 48.0
const CANCEL_SIZE: float = 48.0
## Cancel sits beside Build, so keep a clear thumb gap between them.
const GAP: float = 16.0
const GHOST_GAP: float = 10.0
const EDGE_MARGIN: float = 8.0
const REPEAT_SECONDS: float = 6.0
## Buildings people usually place several of in a row.
const REPEATABLE: Array[int] = [BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.FARM, BuildingData.BuildingType.WATCH_TOWER]

var _hud: Node = null
var _placement: BuildingPlacement = null
var _row: HBoxContainer = null
var build_button: Button = null
var cancel_button: Button = null
var _uses_touch: bool = true
var _valid: bool = false
var _reason: String = ""
var _building_type: int = -1
## Post-placement "+1" state.
var _repeat_type: int = -1
var _repeat_anchor: WeakRef = null
var _repeat_until_msec: int = 0
var _repeat_rect := Rect2()


func _init(hud: Node = null) -> void:
	_hud = hud


func _ready() -> void:
	name = "PlacementGhostCard"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", int(GAP))
	add_child(_row)
	build_button = Button.new()
	build_button.name = "GhostBuildButton"
	build_button.focus_mode = Control.FOCUS_NONE
	build_button.custom_minimum_size = Vector2(112.0, BUTTON_HEIGHT)
	build_button.add_theme_font_size_override("font_size", 16)
	build_button.pressed.connect(_on_build_pressed)
	_row.add_child(build_button)
	cancel_button = Button.new()
	cancel_button.name = "GhostCancelButton"
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.custom_minimum_size = Vector2(CANCEL_SIZE, CANCEL_SIZE)
	cancel_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	KingdomTheme.apply_secondary(cancel_button)
	CommandIcons.apply(cancel_button, "close", "Cancel placement [Esc]")
	cancel_button.pressed.connect(_on_cancel_pressed)
	_row.add_child(cancel_button)
	_row.visible = false
	set_process(true)


func set_placement_source(placement: BuildingPlacement) -> void:
	_placement = placement


## Placement started or ended. `building_type` < 0 ends it.
func set_placement(building_type: int) -> void:
	_building_type = building_type
	if building_type >= 0:
		_clear_repeat()
	_refresh_build_button()
	_update_layout()


func set_input_mode(uses_touch: bool) -> void:
	_uses_touch = uses_touch
	_update_layout()


func set_preview(valid: bool, reason: String) -> void:
	if valid == _valid and reason == _reason:
		return
	_valid = valid
	_reason = reason
	_refresh_build_button()


func is_build_visible() -> bool:
	return _row != null and _row.visible and _building_type >= 0


func is_cancel_visible() -> bool:
	return is_build_visible() and cancel_button.visible


func is_repeat_visible() -> bool:
	return _row != null and _row.visible and _repeat_type >= 0


## Offer "+1 <building>" on a foundation the player just placed.
func offer_repeat(building_type: int, anchor: Node2D) -> void:
	if building_type not in REPEATABLE or not is_instance_valid(anchor):
		return
	_repeat_type = building_type
	_repeat_anchor = weakref(anchor)
	_repeat_until_msec = Time.get_ticks_msec() + int(REPEAT_SECONDS * 1000.0)
	_refresh_build_button()
	_update_layout()


func dismiss_repeat() -> void:
	if _repeat_type < 0:
		return
	_clear_repeat()
	_refresh_build_button()
	_update_layout()


func _clear_repeat() -> void:
	_repeat_type = -1
	_repeat_anchor = null
	_repeat_rect = Rect2()


func _refresh_build_button() -> void:
	if build_button == null:
		return
	if _building_type >= 0:
		var cost: Dictionary = BuildingData.get_building_cost(_building_type, 0)
		var name_text: String = BuildingData.get_building_name(_building_type)
		if _valid:
			_style(true)
			CommandIcons.apply(build_button, "check", "Build %s here (%s)" % [name_text, _cost_text(cost)], "Build  %s" % _cost_text(cost))
		else:
			_style(false)
			var why: String = _reason if not _reason.is_empty() else "Choose clear ground"
			CommandIcons.apply(build_button, "", "%s cannot go here: %s. Drag it or tap clear ground." % [name_text, why], _short_reason(why))
		cancel_button.visible = true
		cancel_button.tooltip_text = "Cancel %s" % name_text
		cancel_button.accessibility_name = cancel_button.tooltip_text
	elif _repeat_type >= 0:
		var repeat_name: String = BuildingData.get_building_name(_repeat_type)
		var affordable: bool = ResourceManager.can_afford(0, BuildingData.get_building_cost(_repeat_type, 0))
		_style(false)
		CommandIcons.apply(build_button, "repeat", "Place another %s next to this one" % repeat_name, "+1 %s" % repeat_name)
		build_button.disabled = not affordable
		cancel_button.visible = false
		return
	build_button.disabled = false


func _style(primary: bool) -> void:
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		build_button.remove_theme_color_override(state)
	if primary:
		KingdomTheme.apply_primary(build_button)
	else:
		KingdomTheme.apply_secondary(build_button)


func _cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in ["food", "wood", "gold"]:
		var amount: int = int(cost.get(key, 0))
		if amount > 0:
			parts.append("%d%s" % [amount, key.substr(0, 1).to_upper()])
	return " ".join(parts)


func _short_reason(reason: String) -> String:
	# The button is a thumb target, not a paragraph.
	match reason:
		"Leave 1 tile between buildings for a path":
			return "Keep a gap"
		"Move all tiles into sight":
			return "Not in sight"
		"Overlaps building":
			return "Blocked"
		"Blocked terrain":
			return "Blocked"
	return reason if reason.length() <= 18 else reason.substr(0, 17) + "…"


func _on_build_pressed() -> void:
	if _building_type >= 0:
		confirm_requested.emit()
		return
	if _repeat_type >= 0:
		var anchor: Node2D = _repeat_anchor.get_ref() as Node2D if _repeat_anchor != null else null
		var building_type: int = _repeat_type
		_clear_repeat()
		_row.visible = false
		repeat_requested.emit(building_type, anchor)


func _on_cancel_pressed() -> void:
	cancel_requested.emit()


func _process(_delta: float) -> void:
	# The ghost is the source of truth; the card only mirrors it.
	var placing: bool = _placement != null and is_instance_valid(_placement) and _placement.active
	var building_type: int = _placement.current_building_type if placing else -1
	if building_type != _building_type:
		set_placement(building_type)
	if placing:
		_uses_touch = _placement.uses_touch_input()
		set_preview(_placement.is_valid_placement, _placement.get_preview_hint())
	if _repeat_type >= 0:
		var anchor: Node2D = _repeat_anchor.get_ref() as Node2D if _repeat_anchor != null else null
		if Time.get_ticks_msec() > _repeat_until_msec or anchor == null or not anchor.is_inside_tree():
			dismiss_repeat()
			return
		var affordable: bool = ResourceManager.can_afford(0, BuildingData.get_building_cost(_repeat_type, 0))
		if build_button.disabled == affordable:
			build_button.disabled = not affordable
	_update_layout()


func _update_layout() -> void:
	if _row == null:
		return
	var anchor_rect := Rect2()
	var footprint_rect := Rect2()
	if _building_type >= 0 and _uses_touch and _placement != null and _placement.active:
		footprint_rect = _placement.get_ghost_footprint_screen_rect()
		anchor_rect = _placement.get_ghost_screen_rect()
		if anchor_rect.has_area():
			# Remember the ghost's look for a later "+1" over its foundation.
			_repeat_rect = anchor_rect
	elif _repeat_type >= 0:
		var anchor: Node2D = _repeat_anchor.get_ref() as Node2D if _repeat_anchor != null else null
		if anchor != null:
			footprint_rect = _foundation_screen_rect(anchor)
			# The walls rise about two footprint-heights above the ground.
			anchor_rect = Rect2(footprint_rect.position - Vector2(0.0, footprint_rect.size.y * 2.0), footprint_rect.size + Vector2(0.0, footprint_rect.size.y * 2.0))
	if not footprint_rect.has_area():
		_row.visible = false
		return
	_row.visible = true
	_row.reset_size()
	var row_size: Vector2 = _row.get_combined_minimum_size()
	_row.size = row_size
	_row.position = _choose_position(footprint_rect, anchor_rect, row_size)


func _foundation_screen_rect(anchor: Node2D) -> Rect2:
	var building := anchor as BuildingBase
	var map: Node = _placement.get_parent() if _placement != null and is_instance_valid(_placement) else null
	if building == null or map == null or not map.has_method("tile_to_world"):
		return Rect2()
	var canvas: Transform2D = anchor.get_canvas_transform()
	var origin: Vector2i = map.call("world_to_tile", anchor.global_position)
	var center: Vector2 = map.call("tile_to_world", origin)
	var axis_x: Vector2 = (map.call("tile_to_world", origin + Vector2i(1, 0)) as Vector2) - center
	var axis_y: Vector2 = (map.call("tile_to_world", origin + Vector2i(0, 1)) as Vector2) - center
	var first: Vector2 = center - (axis_x + axis_y) * 0.5
	var rect := Rect2(canvas * first, Vector2.ZERO)
	for point: Vector2 in [first + axis_x * building.footprint.x, first + axis_x * building.footprint.x + axis_y * building.footprint.y, first + axis_y * building.footprint.y]:
		rect = rect.expand(canvas * point)
	return rect


func _choose_position(footprint_rect: Rect2, art_rect: Rect2, row_size: Vector2) -> Vector2:
	var safe: Rect2 = get_viewport_rect()
	var obstacles: Array[Rect2] = []
	if _hud != null:
		if _hud.has_method("get_hold_safe_rect"):
			safe = _hud.call("get_hold_safe_rect")
		if _hud.has_method("get_world_occlusion_rects"):
			for rect: Rect2 in _hud.call("get_world_occlusion_rects"):
				obstacles.append(rect)
	safe = safe.grow(-EDGE_MARGIN)
	var center_x: float = footprint_rect.get_center().x - row_size.x * 0.5
	var candidates: Array[Vector2] = [
		Vector2(center_x, footprint_rect.end.y + GHOST_GAP),
		Vector2(center_x, art_rect.position.y - GHOST_GAP - row_size.y - 18.0),
		Vector2(art_rect.end.x + GHOST_GAP, footprint_rect.get_center().y - row_size.y * 0.5),
		Vector2(art_rect.position.x - GHOST_GAP - row_size.x, footprint_rect.get_center().y - row_size.y * 0.5),
	]
	for candidate: Vector2 in candidates:
		var rect := Rect2(candidate, row_size)
		if not safe.encloses(rect):
			continue
		var clear: bool = true
		for obstacle: Rect2 in obstacles:
			if obstacle.has_area() and obstacle.intersects(rect.grow(2.0)):
				clear = false
				break
		if clear:
			return candidate
	# Nothing is fully clear: stay just under the ghost, inside the screen.
	var fallback: Vector2 = candidates[0]
	fallback.x = clampf(fallback.x, safe.position.x, maxf(safe.position.x, safe.end.x - row_size.x))
	fallback.y = clampf(fallback.y, safe.position.y, maxf(safe.position.y, safe.end.y - row_size.y))
	return fallback


func get_build_button_rect() -> Rect2:
	return build_button.get_global_rect() if build_button != null and _row.visible else Rect2()


func get_cancel_button_rect() -> Rect2:
	return cancel_button.get_global_rect() if cancel_button != null and _row.visible and cancel_button.visible else Rect2()
