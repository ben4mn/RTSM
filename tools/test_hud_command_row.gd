extends Node
## HUD pass: the production row planner (one row when it fits, Train | Tech
## pages when it does not), the deliberate two-tap research cancel, and the
## toast lane's two-pill priority policy. Pure logic; no match is started.

const GAP: float = 2.0
const BELL: String = "garrison:bell"
const RELEASE: String = "garrison:release"
const AGE: String = "research:age_2"

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("[FAIL] hud_command_row: " + message)


func _tiles(ids: Array) -> Array:
	var tiles: Array = []
	for id: String in ids:
		tiles.append({"id": id, "width": CommandRow.TILE_SIZE.x})
	return tiles


func _all_keys(layout: Dictionary) -> Array:
	var keys: Array = (layout.train as Array).duplicate()
	for page: Array in layout.pages:
		keys.append_array(page)
	return keys


func _page_width(layout: Dictionary, page: Array, widths: Dictionary) -> float:
	## Back, the bell, this page's items and (when more pages follow) Next.
	var width: float = CommandRow.BACK_SIZE.x + (GAP + CommandRow.PINNED_SIZE.x if bool(layout.pinned_on_tech) else 0.0)
	for key: String in page:
		width += GAP + float(widths.get(key, layout.tile_width))
	if (layout.pages as Array).size() > 1 and page != (layout.pages as Array).back():
		width += GAP + CommandRow.NEXT_SIZE.x
	return width


func _run() -> void:
	# Town Center: Villager 76, Scout 76, bell 48, rally 48.
	var units: Array = [76.0, 76.0]
	var pinned: Array = [{"id": BELL, "width": CommandRow.PINNED_SIZE.x}]
	var rally: float = 48.0
	var u0: String = CommandRow.unit_key(0)
	var u1: String = CommandRow.unit_key(1)
	var fixed: Array = [u0, u1, BELL, CommandRow.RALLY_KEY]
	var tech: Array = ["research:loom", "research:wheelbarrow", "wildlife:walk_home"]
	_expect(CommandRow.is_pinned(BELL) and not CommandRow.is_pinned(RELEASE) and CommandRow.is_urgent(RELEASE) and CommandRow.is_optional(AGE), "bell is pinned, Out is urgent, the running age card is optional")

	# 844x390 (464px of row): everything in one row, in order.
	var wide: Dictionary = CommandRow.plan(units, pinned, rally, _tiles(tech), 464.0, GAP)
	_expect(not bool(wide.paged) and wide.train == fixed + tech and (wide.pages as Array).is_empty() and float(wide.width) <= 464.0 and (wide.hidden as Array).is_empty(), "a wide phone shows the whole Town Center row at once: " + str(wide))
	_expect(is_equal_approx(float(wide.unit_width), 76.0) and is_equal_approx(float(wide.tile_width), CommandRow.TILE_SIZE.x), "nothing is slimmed when the row fits")
	# The running age card joins only while it fits; it never forces paging.
	var with_age: Dictionary = CommandRow.plan(units, pinned, rally, _tiles([AGE] + tech), 464.0, GAP)
	_expect(not bool(with_age.paged) and with_age.hidden == [AGE] and with_age.train == fixed + tech, "a crowded row drops the age card first, not into pages: " + str(with_age))
	var roomy: Dictionary = CommandRow.plan(units, pinned, rally, _tiles([AGE] + tech), 560.0, GAP)
	_expect(not bool(roomy.paged) and (roomy.hidden as Array).is_empty() and (roomy.train as Array).has(AGE), "with room the age card is part of the row")

	# A small phone (667x375: about 356px of row): Train | Tech, bell on both.
	var phone: Dictionary = CommandRow.plan(units, pinned, rally, _tiles(tech), 356.0, GAP)
	_expect(bool(phone.paged) and phone.train == fixed and phone.pages == [tech], "a small phone pages the row: " + str(phone))
	_expect(float(phone.width) <= 356.0 and is_equal_approx(float(phone.unit_width), 76.0), "both pages fit the row at full size: " + str(phone))
	# Out arrives: four tiles miss the page by a few pixels, so they slim down
	# rather than leave one tile alone on a second Tech page.
	var phone_out: Dictionary = CommandRow.plan(units, pinned, rally, _tiles(tech + [RELEASE]), 356.0, GAP)
	_expect(bool(phone_out.paged) and phone_out.train == fixed and phone_out.pages == [tech + [RELEASE]], "on a small phone Out joins the single Tech page: " + str(phone_out))
	_expect(float(phone_out.tile_width) >= CommandRow.MIN_TILE_WIDTH and float(phone_out.tile_width) < CommandRow.TILE_SIZE.x and float(phone_out.width) <= 356.0, "the four tiles slim to fit: " + str(phone_out))

	# Soldiers inside on a wide phone: Out stays on the Train page.
	var garrisoned: Dictionary = CommandRow.plan(units, pinned, rally, _tiles(tech + [RELEASE]), 464.0, GAP)
	_expect(bool(garrisoned.paged) and garrisoned.train == fixed + [RELEASE] and garrisoned.pages == [tech] and float(garrisoned.width) <= 464.0, "Out stays one tap away on a wide phone: " + str(garrisoned))

	# Very narrow rows (Extra Large UI on small phones) give ground instead of
	# clipping: rally to Tech, slimmer unit cards, then the last unit to Tech.
	for capacity: float in [252.0, 200.0]:
		var narrow: Dictionary = CommandRow.plan(units, pinned, rally, _tiles(tech + [RELEASE]), capacity, GAP)
		var widths: Dictionary = {u0: narrow.unit_width, u1: narrow.unit_width, CommandRow.RALLY_KEY: rally, BELL: CommandRow.PINNED_SIZE.x}
		var train_width: float = CommandRow.MORE_SIZE.x
		for key: String in narrow.train:
			train_width += GAP + float(widths.get(key, narrow.tile_width))
		_expect(bool(narrow.paged) and (narrow.train as Array).has(u0) and (narrow.train as Array).has(BELL) and train_width <= capacity, "%.0fpx: Villager, the bell and Tech always fit the Train page: %s (%.0f)" % [capacity, str(narrow.train), train_width])
		_expect(float(narrow.unit_width) >= CommandRow.MIN_UNIT_WIDTH, "%.0fpx: unit cards keep a usable width" % capacity)
		var keys: Array = _all_keys(narrow)
		for key: String in fixed + tech + [RELEASE]:
			_expect(keys.count(key) == 1, "%.0fpx: %s appears exactly once: %s" % [capacity, key, str(keys)])
		for page: Array in narrow.pages:
			_expect(not page.is_empty() and _page_width(narrow, page, widths) <= capacity, "%.0fpx: a Tech page never overflows: %s (%.0f)" % [capacity, str(page), _page_width(narrow, page, widths)])
		_expect(float(narrow.width) <= capacity, "%.0fpx: the shared page width fits" % capacity)
	var at_252: Dictionary = CommandRow.plan(units, pinned, rally, _tiles(tech), 252.0, GAP)
	_expect(at_252.train == [u0, u1, BELL] and float(at_252.unit_width) < 76.0, "at 252px both unit cards stay (slimmer) and the rally flag moves to Tech: " + str(at_252))
	var at_200: Dictionary = CommandRow.plan(units, pinned, rally, _tiles(tech), 200.0, GAP)
	_expect(at_200.train == [u0, BELL] and (at_200.pages[0] as Array).front() == u1 and not bool(at_200.pinned_on_tech), "at 200px the Scout card leads the Tech page and the bell stays on Train only: " + str(at_200))
	_expect(bool(at_252.pinned_on_tech) and bool(phone.pinned_on_tech), "wider rows keep the bell on every page")

	# A building with nothing but units and a rally flag is never paged.
	var plain: Dictionary = CommandRow.plan([76.0, 76.0, 76.0], [], rally, [], 200.0, GAP)
	_expect(not bool(plain.paged) and (plain.pages as Array).is_empty() and (plain.train as Array).size() == 4, "no context tiles, no pages")

	# Tech button summary.
	var summary: Dictionary = CommandRow.summarize_tail([
		{"id": BELL, "progress": -1.0, "disabled_reason": ""},
		{"id": "research:loom", "progress": -1.0, "disabled_reason": ""},
		{"id": "research:wheelbarrow", "progress": -1.0, "disabled_reason": "Need Feudal Age"},
		{"id": "research:hand_cart", "progress": 0.4, "disabled_reason": ""},
		{"id": "wildlife:walk_home", "progress": -1.0, "disabled_reason": ""},
	])
	_expect(int(summary.ready) == 1 and is_equal_approx(float(summary.progress), 0.4), "Tech counts startable research and carries the running meter: " + str(summary))

	# Deliberate cancel: arm, then a separate tap.
	CommandRow.disarm_cancel()
	var key: String = CommandRow.cancel_key(self, "loom")
	_expect(not CommandRow.is_cancel_armed(key) and not CommandRow.tap_cancel(key) and CommandRow.is_cancel_armed(key), "the first tap only arms the cancel")
	_expect(not CommandRow.tap_cancel(key) and CommandRow.is_cancel_armed(key), "the second half of a double tap does not cancel")
	await get_tree().create_timer(float(CommandRow.CANCEL_MIN_GAP_MSEC + 60) / 1000.0).timeout
	_expect(not CommandRow.tap_cancel(CommandRow.cancel_key(self, "wheelbarrow")) and not CommandRow.is_cancel_armed(key), "arming another research disarms the first")
	_expect(not CommandRow.tap_cancel(key), "re-arming starts over")
	await get_tree().create_timer(float(CommandRow.CANCEL_MIN_GAP_MSEC + 60) / 1000.0).timeout
	_expect(CommandRow.tap_cancel(key) and not CommandRow.is_cancel_armed(key), "a separate second tap confirms the cancel")

	await _toast_lane()
	if _failures.is_empty():
		print("[PASS] hud_command_row: %d checks; one row / Train|Tech pages / split Tech pages, pinned bell, urgent Out, deliberate cancel, two-pill toast priority and placement" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _texts(lane: ToastLane) -> Array:
	var texts: Array = []
	for child: Node in lane.get_children():
		if child is PanelContainer and (child as Control).visible and not child.is_queued_for_deletion():
			texts.append(((child as PanelContainer).get_child(0) as Label).text)
	return texts


func _toast_lane() -> void:
	var lane := ToastLane.new()
	add_child(lane)
	lane.push("Queued: Villager")
	lane.push("Unit trained: Scout")
	_expect(_texts(lane) == ["Queued: Villager", "Unit trained: Scout"], "two ordinary toasts show together: " + str(_texts(lane)))
	lane.push("Queued: Villager")
	_expect(_texts(lane).size() == 2, "a repeated message does not stack")
	lane.push("Waypoint added")
	_expect(_texts(lane) == ["Unit trained: Scout", "Waypoint added"], "a third ordinary toast replaces the oldest; never three: " + str(_texts(lane)))
	lane.push("Town bell — villagers take shelter", KingdomTheme.GOLD, 3.5, Callable(), ToastLane.Priority.HIGH)
	lane.push("Boar is dangerous — lure it to your Town Center", KingdomTheme.RUST, 5.0)
	_expect(_texts(lane) == ["Town bell — villagers take shelter", "Boar is dangerous — lure it to your Town Center"], "important toasts take both slots: " + str(_texts(lane)))
	lane.push("Unit trained: Villager")
	_expect(_texts(lane) == ["Town bell — villagers take shelter", "Boar is dangerous — lure it to your Town Center"], "chatter never bumps an important toast")
	lane.push("All clear", KingdomTheme.TEAL, 3.5, Callable(), ToastLane.Priority.HIGH)
	_expect(_texts(lane) == ["Boar is dangerous — lure it to your Town Center", "All clear"], "a new important toast replaces the oldest important one: " + str(_texts(lane)))
	lane.dismiss("All clear")
	_expect(_texts(lane) == ["Boar is dangerous — lure it to your Town Center", "Unit trained: Villager"], "the waiting chatter takes a freed slot: " + str(_texts(lane)))
	_expect(lane.visible_count() == 2, "the lane never shows more than two")
	# Placement: beside the alert column on a small phone, centred on a wide one,
	# under the guidance card while it is up; always inside the safe area.
	var small := Rect2(0, 0, 667, 375)
	lane.place(small, 56.0, 240.0, Rect2())
	_expect(lane.position.x >= 240.0 and lane.position.x + lane.size.x <= small.end.x - 8.0 and is_equal_approx(lane.position.y, 56.0), "small phone: the lane starts right of the alert column: " + str(lane.position))
	var wide := Rect2(0, 0, 844, 390)
	lane.place(wide, 56.0, 240.0, Rect2())
	_expect(is_equal_approx(lane.position.x + lane.size.x * 0.5, 422.0), "wide phone: the lane is centred: " + str(lane.position))
	var guidance := Rect2(476, 56, 360, 54)
	lane.place(wide, 56.0, 240.0, guidance)
	_expect(lane.position.y >= guidance.end.y and not Rect2(lane.position, Vector2(lane.size.x, 100)).intersects(guidance), "the lane drops below the guidance card")
	var notched := Rect2(44, 0, 696, 345)
	lane.place(notched, 52.0, notched.position.x + 240.0, Rect2())
	_expect(lane.position.x >= notched.position.x + 8.0 and lane.position.x + lane.size.x <= notched.end.x - 8.0, "the lane stays inside a notched safe area")
	await get_tree().process_frame
	for child: Node in lane.get_children():
		if child is Control and (child as Control).visible and not child.is_queued_for_deletion():
			_expect((child as Control).size.x <= lane.size.x + 0.5, "a pill never exceeds the lane width")
	lane.clear()
	_expect(lane.visible_count() == 0, "clear empties the lane")
	lane.queue_free()
