class_name CommandRow
extends RefCounted
## A production building's command row, planned for a thumb.
##
## Order: unit cards, pinned one-tap actions (the town bell), the rally flag,
## then every other context action (research, toggles). When all of it fits
## the phone, it is one row. When it does not, the row becomes pages of one
## width: "Train" (units, bell, rally and a Tech button saying what waits
## behind it) and "Tech" (a back button, the bell again, and the remaining
## tiles). Nothing ever sits half under the age button, the bell is one tap
## from a selected Town Center on every page, and so is training a villager.
##
## On a very narrow row (a small phone at Extra Large UI) the Train page gives
## ground in this order rather than clip: the rally flag moves to Tech, the
## unit cards slim down, then the last unit cards move to Tech.
##
## The HUD owns the buttons; this file only decides, styles and guards.

## Context actions that stay beside the unit cards on every page layout.
const PINNED_ACTION_IDS: PackedStringArray = ["garrison:bell"]
## Instant actions that stay on the Train page of a paged row while they fit
## ("Out" after a raid should not hide behind Tech on a wide phone).
const URGENT_ACTION_IDS: PackedStringArray = ["garrison:release"]
## Everything in the selection panel that is not the row itself: collapse
## chevron, portrait, separators, panel padding and the queue pager's slot
## (reserved even while no queue exists, so queueing never re-pages the row).
const CHROME_WIDTH: float = 188.0
const RALLY_KEY: String = "rally"
const MIN_UNIT_WIDTH: float = 64.0
const MIN_TILE_WIDTH: float = 60.0
const PINNED_SIZE := Vector2(48, 54)
const TILE_SIZE := Vector2(66, 54)
const MORE_SIZE := Vector2(52, 54)
const BACK_SIZE := Vector2(48, 48)
const NEXT_SIZE := Vector2(48, 48)
const MORE_BUTTON_NAME: String = "RowTechButton"
const BACK_BUTTON_NAME: String = "RowTrainButton"
const NEXT_BUTTON_NAME: String = "RowNextButton"
## A running research is cancelled by two separate taps: the first arms the
## tile ("Cancel?"), the second confirms. A double tap cannot do both.
const CANCEL_ARM_MSEC: int = 2600
const COMPACT_TILE := preload("res://scripts/ui/compact_action_tile.gd")
const CANCEL_MIN_GAP_MSEC: int = 380

static var _armed_key: String = ""
static var _armed_at_msec: int = 0


static func is_pinned(action_id: String) -> bool:
	return action_id in PINNED_ACTION_IDS


static func is_urgent(action_id: String) -> bool:
	return action_id in URGENT_ACTION_IDS


static func is_optional(action_id: String) -> bool:
	## The running age-up card repeats the age button's meter; it is the first
	## thing to leave a crowded row (it can still be cancelled from Research).
	return action_id.begins_with(BuildingBase.RESEARCH_ACTION_PREFIX + TechData.AGE_RESEARCH_PREFIX)


static func unit_key(index: int) -> String:
	return "unit:%d" % index


static func _span(widths: Array, gap: float) -> float:
	var total: float = 0.0
	for width: float in widths:
		total += width
	return total + gap * float(maxi(0, widths.size() - 1))


static func _train_span(units: int, unit_width: float, pinned_widths: Array, rally_width: float, gap: float) -> float:
	## Width of the Train page: units, pinned tiles, rally flag (0 = moved), Tech.
	var widths: Array = []
	for index: int in units:
		widths.append(unit_width)
	widths.append_array(pinned_widths)
	if rally_width > 0.0:
		widths.append(rally_width)
	widths.append(MORE_SIZE.x)
	return _span(widths, gap)


## Plans the row. `unit_widths` are the unit cards in order, `pinned` and
## `tail` are {"id", "width"} for the pinned tiles and for every other tile in
## display order, `rally_width` is 0 without a rally flag.
##
## Returns item keys (unit_key(i), RALLY_KEY or an action id):
##   "paged": bool
##   "train": keys on the first page (the whole row when not paged)
##   "pages": Array of key arrays, one per Tech page (empty when not paged);
##            the pinned tiles lead every Tech page and are not repeated here
##   "hidden": action ids left out (only the optional age card)
##   "pinned_on_tech": whether the pinned tiles lead the Tech pages (false
##            only when a page could not then hold a single tile)
##   "unit_width", "tile_width": widths to give unit cards and tail tiles
##   "width": the widest page, so every page can share it
static func plan(unit_widths: Array, pinned: Array, rally_width: float, tail: Array, capacity: float, gap: float) -> Dictionary:
	var unit_count: int = unit_widths.size()
	var unit_width: float = float(unit_widths[0]) if unit_count > 0 else 0.0
	var required: Array[Dictionary] = []
	var optional: Array[Dictionary] = []
	for tile: Dictionary in tail:
		if is_optional(str(tile.id)):
			optional.append(tile)
		else:
			required.append(tile)
	var hidden: Array[String] = []
	var row_keys: Array[String] = []
	var row_widths: Array = []
	for index: int in unit_count:
		row_keys.append(unit_key(index))
		row_widths.append(unit_width)
	var pinned_widths: Array = []
	for tile: Dictionary in pinned:
		row_keys.append(str(tile.id))
		row_widths.append(float(tile.width))
		pinned_widths.append(float(tile.width))
	if rally_width > 0.0:
		row_keys.append(RALLY_KEY)
		row_widths.append(rally_width)
	for tile: Dictionary in required:
		row_keys.append(str(tile.id))
		row_widths.append(float(tile.width))
	if _span(row_widths, gap) <= capacity or required.is_empty():
		for tile: Dictionary in optional:
			if _span(row_widths + [float(tile.width)], gap) <= capacity:
				row_keys.append(str(tile.id))
				row_widths.append(float(tile.width))
			else:
				hidden.append(str(tile.id))
		return {"paged": false, "train": row_keys, "pages": [], "hidden": hidden, "pinned_on_tech": true, "unit_width": unit_width, "tile_width": TILE_SIZE.x, "width": _span(row_widths, gap)}

	# --- Train page: units, pinned, rally, urgent tiles that fit, Tech. ---
	var train_units: int = unit_count
	var rally_on_train: bool = rally_width > 0.0
	var moved: Array[Dictionary] = []  # What the Train page gave up, in row order.
	if _train_span(train_units, unit_width, pinned_widths, rally_width, gap) > capacity and rally_on_train:
		rally_on_train = false
	var train_rally: float = rally_width if rally_on_train else 0.0
	var excess: float = _train_span(train_units, unit_width, pinned_widths, train_rally, gap) - capacity
	if excess > 0.0 and train_units > 0:
		unit_width = maxf(MIN_UNIT_WIDTH, unit_width - ceilf(excess / float(train_units)))
	while _train_span(train_units, unit_width, pinned_widths, train_rally, gap) > capacity and train_units > 1:
		train_units -= 1
	for index: int in range(train_units, unit_count):
		moved.append({"id": unit_key(index), "width": unit_width})
	if rally_width > 0.0 and not rally_on_train:
		moved.append({"id": RALLY_KEY, "width": rally_width})
	var train_keys: Array[String] = []
	for index: int in train_units:
		train_keys.append(unit_key(index))
	for tile: Dictionary in pinned:
		train_keys.append(str(tile.id))
	if rally_on_train:
		train_keys.append(RALLY_KEY)
	var train_width: float = _train_span(train_units, unit_width, pinned_widths, train_rally, gap)
	var paged_tiles: Array[Dictionary] = []
	for tile: Dictionary in required:
		if is_urgent(str(tile.id)) and train_width + gap + float(tile.width) <= capacity:
			train_keys.append(str(tile.id))
			train_width += gap + float(tile.width)
		else:
			paged_tiles.append(tile)

	# --- Tech pages: Back, the pinned tiles, then as many items as fit. ---
	var lead: float = BACK_SIZE.x
	for width: float in pinned_widths:
		lead += gap + width
	# Too narrow for Back, the bell, one tile and Next: the bell stays on the
	# Train page only (still one tap from Back).
	var pinned_on_tech: bool = lead + gap + TILE_SIZE.x + gap + NEXT_SIZE.x <= capacity
	if not pinned_on_tech:
		lead = BACK_SIZE.x
	# A near miss is solved by slimmer tiles instead of a page holding one tile.
	var tile_width: float = TILE_SIZE.x
	var single: float = lead
	for item: Dictionary in moved:
		single += gap + float(item.width)
	for tile: Dictionary in paged_tiles:
		single += gap + float(tile.width)
	if single > capacity and not paged_tiles.is_empty():
		var slimmer: float = floorf(TILE_SIZE.x - (single - capacity) / float(paged_tiles.size()))
		if slimmer >= MIN_TILE_WIDTH:
			tile_width = slimmer
	var items: Array[Dictionary] = moved.duplicate()
	for tile: Dictionary in paged_tiles:
		items.append({"id": str(tile.id), "width": minf(float(tile.width), tile_width)})
	var pages: Array = []
	var widths: Array[float] = []
	var current: Array[String] = []
	var current_width: float = lead
	for index: int in items.size():
		var item: Dictionary = items[index]
		var remaining_after: float = 0.0
		for later: int in range(index + 1, items.size()):
			remaining_after += float(items[later].width) + gap
		var needed: float = current_width + gap + float(item.width)
		# Keep room for Next unless everything left fits on this page.
		var fits_all: bool = needed + remaining_after <= capacity
		var fits_with_next: bool = needed + gap + NEXT_SIZE.x <= capacity
		if not current.is_empty() and not fits_all and not fits_with_next:
			pages.append(current)
			widths.append(current_width + gap + NEXT_SIZE.x)
			current = []
			current_width = lead
			needed = current_width + gap + float(item.width)
		current.append(str(item.id))
		current_width = needed
	for tile: Dictionary in optional:
		if current_width + gap + minf(float(tile.width), tile_width) <= capacity:
			current.append(str(tile.id))
			current_width += gap + minf(float(tile.width), tile_width)
		else:
			hidden.append(str(tile.id))
	pages.append(current)
	widths.append(current_width)
	var widest: float = train_width
	for width: float in widths:
		widest = maxf(widest, width)
	return {"paged": true, "train": train_keys, "pages": pages, "hidden": hidden, "pinned_on_tech": pinned_on_tech, "unit_width": unit_width, "tile_width": tile_width, "width": widest}


## Counts for the Tech button: {"ready": startable now, "progress": -1 or 0..1}.
static func summarize_tail(actions: Array) -> Dictionary:
	var ready: int = 0
	var progress: float = -1.0
	for action: Dictionary in actions:
		var id: String = str(action.get("id", ""))
		if is_pinned(id):
			continue
		var running: float = float(action.get("progress", -1.0))
		if running >= 0.0:
			progress = maxf(progress, running)
		elif id.begins_with(BuildingBase.RESEARCH_ACTION_PREFIX) and not bool(action.get("done", false)) and str(action.get("disabled_reason", "")).is_empty():
			ready += 1
	return {"ready": ready, "progress": progress}


static func style_more_button(button: Button, summary: Dictionary) -> void:
	## A tile like its neighbours: name, glyph, and one line saying what waits
	## behind it ("2 ready") or how far the running research is ("40%").
	var ready: int = int(summary.get("ready", 0))
	var progress: float = float(summary.get("progress", -1.0))
	var label: String = "Research and building actions"
	var note: String = ""
	if progress >= 0.0:
		note = "%d%%" % int(clampf(progress, 0.0, 1.0) * 100.0)
		label += ": researching, %s" % note
	elif ready > 0:
		note = "%d ready" % ready
		label += ": %s" % note
	COMPACT_TILE.apply(button, CommandIcons.get_icon("research"), {}, MORE_SIZE, "Tech")
	set_note(button, note, KingdomTheme.GOLD)
	button.tooltip_text = label
	button.accessibility_name = label
	FieldStyle.production_meter(button, progress)


## One quiet line where a tile's costs would be (a toggle's state, a count).
## Blocked reasons keep ACTION_TILE.set_status and its rust voice.
static func set_note(button: Button, note: String, color: Color = KingdomTheme.MUTED) -> void:
	COMPACT_TILE.set_status(button, note)
	var label := button.get_node_or_null("TileStatus") as Label
	if label != null:
		label.add_theme_color_override("font_color", color if not note.is_empty() else KingdomTheme.RUST.lightened(0.25))


static func style_back_button(button: Button) -> void:
	CommandIcons.apply(button, "back", "Back to training")
	button.custom_minimum_size = BACK_SIZE


static func style_next_button(button: Button) -> void:
	CommandIcons.apply(button, "more", "More actions")
	button.custom_minimum_size = NEXT_SIZE


## An icon-only tile: the glyph is centred instead of leaving a cost line.
static func center_tile_icon(button: Button, active: bool) -> void:
	var art := button.get_node_or_null("TilePortrait") as Control
	if art != null:
		art.offset_left = 10
		art.offset_right = -10
		art.offset_top = 11
		art.offset_bottom = -11
	for state: String in ["normal", "hover"]:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		if style == null:
			continue
		style = style.duplicate() as StyleBoxFlat
		# A ringing bell reads as "on": gold rim, lighter cloth.
		style.border_color = KingdomTheme.GOLD if active or state == "hover" else KingdomTheme.BORDER
		style.set_border_width_all(2 if active else 1)
		style.border_width_bottom = 2
		if active:
			style.bg_color = KingdomTheme.INK_LIGHT
		button.add_theme_stylebox_override(state, style)


# --- Deliberate cancel -------------------------------------------------------

static func cancel_key(building: Object, research_id: String) -> String:
	return "%d:%s" % [building.get_instance_id() if is_instance_valid(building) else 0, research_id]


static func is_cancel_armed(key: String) -> bool:
	return key == _armed_key and Time.get_ticks_msec() - _armed_at_msec <= CANCEL_ARM_MSEC


## Returns true when this tap confirms the cancel; otherwise arms it.
static func tap_cancel(key: String) -> bool:
	var now: int = Time.get_ticks_msec()
	if key == _armed_key and now - _armed_at_msec <= CANCEL_ARM_MSEC:
		if now - _armed_at_msec < CANCEL_MIN_GAP_MSEC:
			return false  # The second half of a double tap: still only armed.
		_armed_key = ""
		return true
	_armed_key = key
	_armed_at_msec = now
	return false


static func disarm_cancel() -> void:
	_armed_key = ""
