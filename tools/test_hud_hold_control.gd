extends Node
## Real engine GUI dispatch fixture; controls are stand-ins, no paid match.

const HOLD_SCRIPT := preload("res://scripts/ui/hud_hold_control.gd")
var _failures: Array[String] = []
var _presses: int = 0
var _choices: Array[String] = []
var _world_events: int = 0
var _opened: int = 0
var _revision: int = 1
var _button: Button
var _disabled: Button
var _more: Button
var _hold: Node
var _disabled_hold: Node
var _more_hold: Node
var _safe: Rect2 = Rect2(Vector2(44, 0), Vector2(756, 372))
var _records: Array[Dictionary] = []
var _scroll_actions: int = 0
var _scroll_records: Array[Dictionary] = []
var _ordinary_presses: int = 0
var _ordinary: Button
var _layer: CanvasLayer
var _info_override: Dictionary = {}
var _info_layout_records: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.hold_shortcuts_enabled = true
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	Input.emulate_mouse_from_touch = true
	_layer = CanvasLayer.new()
	add_child(_layer)
	_button = _make_button("Paid action", Vector2(370, 306))
	_disabled = _make_button("Locked", Vector2(70, 306))
	_disabled.disabled = true
	_more = _make_button("More", Vector2(600, 306))
	_ordinary = _make_button("Unwrapped", Vector2(230, 306))
	_ordinary.pressed.connect(func() -> void: _ordinary_presses += 1)
	_button.pressed.connect(func() -> void: _presses += 1)
	_disabled.pressed.connect(func() -> void: _presses += 100)
	_more.pressed.connect(func() -> void: _presses += 10)
	_hold = HOLD_SCRIPT.attach_to(_button, _layer, _info, func() -> int: return _revision, func() -> Rect2: return _safe)
	_disabled_hold = HOLD_SCRIPT.attach_to(_disabled, _layer, _info, func() -> int: return _revision, func() -> Rect2: return _safe)
	_more_hold = HOLD_SCRIPT.attach_to(_more, _layer, _info, func() -> int: return _revision, func() -> Rect2: return _safe, _choice_data)
	for component: Node in [_hold, _disabled_hold, _more_hold]:
		component.surface_opened.connect(func(_kind: String) -> void: _opened += 1)
	_more_hold.choice_selected.connect(func(action: Variant) -> void: _choices.append(str(action)))
	await _frames(3)
	var center: Vector2 = _button.get_global_rect().get_center()
	await _touch(31, center, true)
	await _touch(31, center, false)
	_expect(_presses == 1, "ordinary native emulated tap must execute once")
	await _touch(77, center, true)
	await _real_wait(0.48)
	_expect(_opened == 1 and not _hold.get_visible_bounds().is_empty(), "hold must open inspection at450ms")
	_expect(_presses == 1, "inspection spent before release")
	await _touch(77, center, false)
	_expect(_presses == 1 and _hold.get_visible_bounds().is_empty(), "consumed hold executed native release")
	for speed: float in [1.0, 1.5, 2.0, 3.0]:
		Engine.time_scale = speed
		var opened_before: int = _opened
		var started: int = Time.get_ticks_msec()
		await _touch(80, center, true)
		await _real_wait(0.40)
		_expect(_opened == opened_before, "game speed%.1f fired hold before real threshold" % speed)
		await _real_wait(0.09)
		_expect(_opened == opened_before + 1, "game speed%.1f missed real threshold" % speed)
		_records.append({"speed": speed, "actual_elapsed_msec": Time.get_ticks_msec() - started})
		await _touch(80, center, false)
	Engine.time_scale = 1.0
	var before: int = _presses
	await _touch(99, center, true)
	await _drag(99, center + Vector2(30, 0))
	await _drag(99, center)
	await _real_wait(0.48)
	await _touch(99, center, false)
	_expect(_presses == before and _hold.get_visible_bounds().is_empty(), "out-and-back requalified canceled tap/hold")
	await _touch(123, center, true)
	_revision += 1
	await _frames(3)
	await _touch(123, center, false)
	_expect(_presses == before, "changed context ran original paid action")
	await _touch(124, center, true)
	await _touch(888, Vector2(250, 200), true)
	await _touch(124, center, false)
	await _touch(888, Vector2(250, 200), false)
	_expect(_presses == before, "second contact ran original action")
	await _touch(221, center, true)
	await _touch(222, Vector2(250, 200), true)
	await _touch(221, center, false)
	await _touch(223, center, true)
	await _real_wait(0.48)
	await _touch(223, center, false)
	await _touch(222, Vector2(250, 200), false)
	_expect(_presses == before and not _hold.is_gesture_active(), "third finger rearmed canceled gesture before second drained")
	await _touch(224, center, true)
	await _mouse(center, true)
	await _touch(224, center, false)
	await _mouse(Vector2(250, 200), false)
	_expect(_presses == before and not _hold.is_gesture_active(), "secondary physical mouse rearmed canceled touch or leaked release")
	await _touch(125, center, true)
	await _touch(125, center, false, true)
	_expect(_presses == before, "OS canceled contact ran action")
	await _touch(126, center, true)
	_hold.cancel_gesture("modal")
	await _touch(126, Vector2(250, 200), false)
	_expect(_presses == before, "modal cancellation leaked action")
	await _touch(127, center, true)
	_button.hide()
	await _frames(2)
	await _touch(127, Vector2(250, 200), false)
	_button.show()
	_expect(_presses == before, "hidden panel release leaked action")
	await _touch(128, center, true)
	_hold.call("_on_focus_lost")
	await _touch(128, center, false)
	_expect(_presses == before, "focus loss ran action")
	await _touch(129, center, true)
	get_window().size = Vector2i(932, 430)
	await _frames(3)
	await _touch(129, center, false)
	_expect(_presses == before, "resize ran action")
	get_window().size = Vector2i(844, 390)
	await _frames(3)
	await _touch(130, _disabled.get_global_rect().get_center(), true)
	await _real_wait(0.48)
	_expect(not _disabled_hold.get_visible_bounds().is_empty(), "disabled action not inspectable")
	await _touch(130, _disabled.get_global_rect().get_center(), false)
	_expect(_presses == before, "disabled inspection executed action")
	var more_center: Vector2 = _more.get_global_rect().get_center()
	await _touch(131, more_center, true)
	await _real_wait(0.48)
	var rects: Array[Dictionary] = _more_hold.get_choice_rects()
	_expect(rects.size() == 4, "chooser missing fixed4actions")
	for row: Dictionary in rects:
		var rect: Rect2 = row.rect
		_expect(rect.size.x >= 48.0 and rect.size.y >= 48.0 and _safe.encloses(rect), "chooserchoice escapedsafearea/48px")
	var chosen: Vector2 = rects[1].rect.get_center() if rects.size() == 4 else more_center
	await _drag(131, chosen)
	_expect(_choices.is_empty(), "chooser preview ran action before release")
	await _touch(131, chosen, false)
	_expect(_choices == ["patrol"], "chooser valid release missing/duplicated choice")
	await _touch(132, more_center, true)
	await _real_wait(0.48)
	await _drag(132, more_center)
	await _touch(132, more_center, false)
	_expect(_choices.size() == 1 and _presses == before, "center cancel ran chooser/native action")
	await _touch(133, more_center, true)
	await _real_wait(0.48)
	await _touch(133, Vector2(230, 160), false)
	_expect(_choices.size() == 1 and _presses == before, "outside cancel ran chooser/native action")
	Input.emulate_mouse_from_touch = false
	await _touch(141, center, true)
	await _touch(141, center, false)
	_expect(_presses == before + 1, "touch with emulationoff missing/duplicated short pressed")
	Input.emulate_mouse_from_touch = true
	await _touch(141, center, true)
	await _touch(141, center, false)
	_expect(_presses == before + 2, "reusedID shorttap missing/duplicated action")
	# Consecutive real dispatch with no frame between gestures must not lose a
	# fresh wrapped/unwrapped press after a consumed hold or ordinary release.
	var quick_before: int = _presses
	await _touch(201, center, true)
	await _real_wait(0.48)
	_inject_touch(201, center, false)
	_inject_touch(202, center, true)
	_inject_touch(202, center, false)
	_inject_touch(203, center, true)
	_inject_touch(203, center, false)
	_inject_touch(204, _ordinary.get_global_rect().get_center(), true)
	_inject_touch(204, _ordinary.get_global_rect().get_center(), false)
	await _frames(3)
	_expect(_presses == quick_before + 2 and _ordinary_presses == 1, "rapid heldrelease/wrapped/wrapped/unwrapped taps lost/duplicated action")
	_expect(not _hold.is_gesture_active(), "rapid ordinary taps left stale owner")
	# Focus can drop a release entirely; a new arbitrary/reused ID must work,
	# while an eventual orphan release over the world remains UI-owned.
	quick_before = _presses
	await _touch(205, center, true)
	_hold.call("_on_focus_lost")
	await _touch(206, center, true)
	await _touch(206, center, false)
	await _touch(205, Vector2(250, 200), false)
	await _touch(205, center, true)
	await _touch(205, center, false)
	_expect(_presses == quick_before + 2 and not _hold.is_gesture_active(), "focus with missing release locked new/reused contacts")
	# Disabled hold preference keeps the existing short/native button path.
	_hold.hold_enabled = false
	quick_before = _presses
	var opened_before: int = _opened
	await _touch(207, center, true)
	await _real_wait(0.48)
	await _touch(207, center, false)
	_expect(_presses == quick_before + 1 and _opened == opened_before, "disabled hold shortcut changed ordinary action")
	_hold.hold_enabled = true
	GameManager.hold_shortcuts_enabled = false
	quick_before = _presses
	opened_before = _opened
	await _touch(214, center, true)
	await _real_wait(0.48)
	await _touch(214, center, false)
	_expect(_presses == quick_before + 1 and _opened == opened_before, "GameManager disabled hold preference changed ordinary action")
	GameManager.hold_shortcuts_enabled = true
	# Actual mouse dispatch, with native Button listeners and no ScreenTouch.
	quick_before = _presses
	await _mouse(center, true)
	await _mouse(center, false)
	_expect(_presses == quick_before + 1, "native mouse short click missing/duplicated action")
	await _mouse(center, true)
	await _real_wait(0.48)
	await _mouse(center, false)
	_expect(_presses == quick_before + 1, "native mouse held release executed action")
	quick_before = _presses
	await _mouse(center, true)
	_hold.call("_on_focus_lost")
	await _mouse(Vector2(250, 200), false)
	await _mouse(center, true)
	await _mouse(center, false)
	_expect(_presses == quick_before + 1, "physical mouse orphan release/focus recovery spent or locked")
	quick_before = _presses
	_button.tooltip_text = "Original hint"
	await _touch(213, center, true)
	_expect(_button.tooltip_text.is_empty(), "contact retained overlapping native tooltip")
	_button.tooltip_text = "Refreshed hint"
	await _frames(2)
	_expect(_button.tooltip_text.is_empty(), "live tooltip refresh escaped contact suppression")
	await _touch(213, center, false)
	_expect(_button.tooltip_text == "Refreshed hint" and _presses == quick_before + 1, "tooltip restoration stale or changed ordinary click")
	# Removing the target does not transfer or leak its owning contact.
	quick_before = _presses
	await _touch(208, center, true)
	_hold.detach()
	_expect(not _button.has_meta("hud_hold_control"), "detached helper left stale target registration")
	_button.queue_free()
	await _frames(3)
	await _touch(208, Vector2(250, 200), false)
	_expect(_presses == quick_before, "detached target spent/leaked on release")
	_expect(not is_instance_valid(_hold), "detached helper did not retire after release")
	_button = _make_button("Replacement", Vector2(370, 306))
	_button.pressed.connect(func() -> void: _presses += 1)
	_hold = HOLD_SCRIPT.attach_to(_button, _layer, _info, func() -> int: return _revision, func() -> Rect2: return _safe)
	await _touch(209, center, true)
	await _touch(209, center, false)
	_expect(_presses == quick_before + 1, "replacement helper inherited stale global owner")
	# Recreate a full owning CanvasLayer while its OS contact is outstanding.
	await _touch(210, center, true)
	_layer.queue_free()
	await _frames(3)
	_layer = CanvasLayer.new()
	add_child(_layer)
	_button = _make_button("Fresh HUD", Vector2(370, 306))
	_button.pressed.connect(func() -> void: _presses += 1)
	_hold = HOLD_SCRIPT.attach_to(_button, _layer, _info, func() -> int: return _revision, func() -> Rect2: return _safe)
	await _touch(211, center, true)
	await _touch(211, center, false)
	await _touch(210, Vector2(250, 200), false)
	await _touch(212, center, true)
	await _touch(212, center, false)
	_expect(_presses == quick_before + 3 and not _hold.is_gesture_active(), "freshHUD/contact reuse retained stale global owner")
	# Coordinate admission and tolerance must use viewport logical pixels at
	# both phone resolutions and all three shipped interface scales.
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for ui_scale: float in [1.0, 1.075, 1.15]:
			get_window().size = phone
			get_window().content_scale_factor = ui_scale
			await _frames(3)
			var logical_size: Vector2 = get_viewport().get_visible_rect().size
			_safe = Rect2(Vector2(40, 0), logical_size - Vector2(80, 18))
			_button.position = Vector2(logical_size.x * 0.5 - 54, logical_size.y - 72)
			center = _button.get_global_rect().get_center()
			quick_before = _presses
			await _touch(301, center, true)
			await _real_wait(0.48)
			var visible: Array[Rect2] = _hold.get_visible_bounds()
			_expect(not visible.is_empty(), "scaled logical touch failed inspection at %sx%s %.3f" % [phone.x, phone.y, ui_scale])
			for rect: Rect2 in visible:
				_expect(_safe.encloses(rect), "info popup escaped actual safe area at scale %.3f" % ui_scale)
			await _touch(301, center, false)
			_expect(_presses == quick_before, "scaled inspection executed paid stand-in action")
			await _touch(302, center, true)
			await _drag(302, center + Vector2(11.9, 0))
			await _touch(302, center + Vector2(11.9, 0), false)
			_expect(_presses == quick_before + 1, "logical movement inside 12px tolerance failed native tap")
			await _touch(303, center, true)
			await _drag(303, center + Vector2(12.1, 0))
			await _drag(303, center)
			await _touch(303, center, false)
			_expect(_presses == quick_before + 1, "logical movement outside 12px tolerance requalified tap")
	await _held_info_layout_tests()
	await _scrolling_tests()
	_expect(_world_events == 0, "GUI contacts leaked %s world events" % _world_events)
	var folder: String = OS.get_environment("AOEM_HOLD_EVIDENCE_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder.path_join("component-receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope":"Real Input.parse_input_event engine dispatch over standalone GUI controls. No paid match or physicaldevice evidence.", "clock_samples": _records, "presses": _presses, "ordinary_unwrapped_presses": _ordinary_presses, "scroll_cases": _scroll_records, "scroll_actions": _scroll_actions, "chooser_actions": _choices, "held_info_layouts": _info_layout_records, "world_events": _world_events, "failures": _failures}, "\t"))
	for failure: String in _failures:
		push_error("[FAIL] hud_hold_control: " + failure)
	if _failures.is_empty():
		print("[PASS] hud_hold_control: native shorttaps, realclock450ms across4speeds, inspection/disabled zeroactions, latchedmotion/context/second/third-contact drain/OScancel/focus/resize/hidden/modal cancellation, fixedchooserpreview/commit/cancel, emulationoff/reusedIDs, fast wrapped/unwrapped taps, missing-release focus recovery, disabled component/global shortcut settings, native mouse, target detach/full HUD recreation, six scaled viewport profiles, logical tolerance boundaries, native tooltip suppression/live restoration, pending card-origin horizontal/vertical pan with emulation on/off, consumed/canceled pan exclusion, bounded held body with pinned reading footer/no inert scrollbar at two Large notched phones and zero GUI world leakage")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _held_info_layout_tests() -> void:
	var villager_core: String = "Cost: 50 food\nPopulation: 1 · Training: 16s\nHP 25 · Attack 3 · Armor 0\nRequires an active producer, enough resources and free committed population."
	var stable_core: String = "Train Horsemen\nCost: 150 wood\nRequires Feudal Age\nHP 1200 · Build 30s\nTrains: Horseman"
	var samples: Array[Dictionary] = [
		{"title":"Villager", "critical":villager_core, "body":villager_core + "\nTap to train one. Holding only inspects."},
		{"title":"Stable", "critical":stable_core, "body":stable_core + "\nTap to preview. Place spends the cost; Cancel spends nothing."},
		{"title":"Oversized details", "critical":"Cost: 50 food\nRequires an active producer.", "body":"Cost: 50 food\nRequires an active producer.\n" + "Additional explanation remains available through tap Info.\n".repeat(80)},
	]
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		get_window().size = phone
		get_window().content_scale_factor = 1.15
		await _frames(3)
		var logical_size: Vector2 = get_viewport().get_visible_rect().size
		# Reserve the top resource rail and the notched left/right/bottom edges.
		_safe = Rect2(Vector2(40, 64), logical_size - Vector2(80, 82))
		_button.position = Vector2(logical_size.x * 0.5 - 54, logical_size.y - 72)
		var origin: Vector2 = _button.get_global_rect().get_center()
		for sample: Dictionary in samples:
			_info_override = sample
			var presses_before: int = _presses
			await _touch(350, origin, true)
			await _real_wait(0.48)
			await _frames(3)
			var popup: Control = _hold.find_child("HoldInfo", true, false) as Control
			var footer: Label = _hold.find_child("HoldInfoFooter", true, false) as Label
			var heading: Label = _hold.find_child("HoldInfoTitle", true, false) as Label
			var clip: ScrollContainer = _hold.find_child("HoldInfoBodyClip", true, false) as ScrollContainer
			var body: Label = _hold.find_child("HoldInfoBody", true, false) as Label
			_expect(popup != null and footer != null and clip != null and body != null and heading != null, "held information lost title/body/pinned footer")
			if popup != null and footer != null and clip != null and body != null and heading != null:
				_expect(_safe.encloses(popup.get_global_rect()) and popup.get_global_rect().encloses(footer.get_global_rect()) and _safe.encloses(footer.get_global_rect()), "pinned information footer escaped panel/safe bounds")
				_expect(footer.text == "Release to close · Tap Info for all details" and footer.get_line_count() == 1 and footer.get_global_rect().position.y >= clip.get_global_rect().end.y, "reading footer wrapped or entered clipped body")
				_expect(not clip.get_v_scroll_bar().is_visible_in_tree() and not clip.get_h_scroll_bar().is_visible_in_tree(), "held preview retained an inert scrollbar")
				_expect(popup.get_global_rect().encloses(heading.get_global_rect()) and body.text == str(sample.body), "title escaped or held body lost original full details")
				var critical := Label.new()
				critical.theme = popup.theme
				critical.text = str(sample.critical)
				critical.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				critical.add_theme_font_size_override("font_size", 15)
				critical.size = Vector2(body.size.x, 0)
				critical.hide()
				_layer.add_child(critical)
				var critical_height: float = critical.get_minimum_size().y
				_expect(critical_height <= clip.size.y + 0.5, "critical held cost/requirements truncated at %sx%s for %s" % [phone.x, phone.y, sample.title])
				_info_layout_records.append({"phone":str(phone), "scale":1.15, "title":sample.title, "panel":str(popup.get_global_rect()), "footer":str(footer.get_global_rect()), "critical_height":critical_height, "body_viewport_height":clip.size.y, "inert_scrollbar_visible":clip.get_v_scroll_bar().is_visible_in_tree()})
				critical.free()
			await _touch(350, origin, false)
			_expect(_presses == presses_before and _hold.get_visible_bounds().is_empty(), "held layout release executed action or left presentation open")
	_info_override = {}


func _scrolling_tests() -> void:
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	await _frames(3)
	var horizontal: Dictionary = _make_scroll_board(false)
	var vertical: Dictionary = _make_scroll_board(true)
	await _frames(4)
	var row: ScrollContainer = horizontal.scroll
	var card: Button = horizontal.card
	var component: Node = card.get_meta("hud_hold_control")
	for emulation: bool in [true, false]:
		Input.emulate_mouse_from_touch = emulation
		row.scroll_horizontal = 40
		await _frames(2)
		var origin: Vector2 = card.get_global_rect().get_center()
		await _touch(401, origin, true)
		await _drag(401, origin - Vector2(70, 0))
		_expect(absi(row.scroll_horizontal - 110) <= 1, "card-origin horizontal pan missing or double-applied with emulation %s" % emulation)
		await _real_wait(0.48)
		_expect(component.get_visible_bounds().is_empty(), "pending card pan activated hold")
		await _touch(401, origin - Vector2(70, 0), false)
		_expect(_scroll_actions == 0 and not component.is_gesture_active(), "card pan executed action or retained contact")
		_scroll_records.append({"axis":"horizontal", "emulation":emulation, "initial_offset":40, "logical_displacement":70, "final_offset":row.scroll_horizontal})
		var column: ScrollContainer = vertical.scroll
		var vertical_card: Button = vertical.card
		column.scroll_vertical = 10
		await _frames(2)
		origin = vertical_card.get_global_rect().get_center()
		await _touch(402, origin, true)
		await _drag(402, origin - Vector2(0, 70))
		_expect(absi(column.scroll_vertical - 80) <= 1, "card-origin vertical pan missing or double-applied with emulation %s" % emulation)
		await _touch(402, origin - Vector2(0, 70), false)
		_expect(_scroll_actions == 0, "vertical card pan executed action")
		_scroll_records.append({"axis":"vertical", "emulation":emulation, "initial_offset":10, "logical_displacement":70, "final_offset":column.scroll_vertical})
	Input.emulate_mouse_from_touch = true
	row.scroll_horizontal = 0
	await _frames(2)
	var origin: Vector2 = card.get_global_rect().get_center()
	await _touch(403, origin, true)
	await _real_wait(0.48)
	_expect(not component.get_visible_bounds().is_empty(), "scroll card info hold missing")
	await _drag(403, origin - Vector2(70, 0))
	await _touch(403, origin - Vector2(70, 0), false)
	_expect(row.scroll_horizontal == 0 and _scroll_actions == 0, "consumed info hold became a scroll/action")
	var chooser_card: Button = horizontal.chooser
	var chooser: Node = chooser_card.get_meta("hud_hold_control")
	origin = chooser_card.get_global_rect().get_center()
	await _touch(404, origin, true)
	await _real_wait(0.48)
	_expect(chooser.get_choice_rects().size() == 4, "scroll card chooser hold missing")
	await _drag(404, origin - Vector2(70, 0))
	await _touch(404, origin, false)
	_expect(row.scroll_horizontal == 0 and _scroll_actions == 0, "consumed chooser became a scroll/action")
	origin = card.get_global_rect().get_center()
	await _touch(405, origin, true)
	await _drag(405, origin - Vector2(70, 0))
	await _touch(499, Vector2(560, 80), true)
	await _drag(405, origin - Vector2(140, 0))
	await _touch(405, origin - Vector2(140, 0), false)
	await _touch(499, Vector2(560, 80), false)
	_expect(row.scroll_horizontal == 70 and _scroll_actions == 0 and not component.is_gesture_active(), "second finger did not cancel/drain pending card pan")
	row.scroll_horizontal = 0
	await _frames(2)
	origin = card.get_global_rect().get_center()
	await _touch(406, origin, true)
	await _drag(406, origin - Vector2(70, 0))
	component.call("_on_focus_lost")
	await _drag(406, origin - Vector2(140, 0))
	await _touch(406, origin - Vector2(140, 0), false)
	_expect(row.scroll_horizontal == 70 and _scroll_actions == 0 and not component.is_gesture_active(), "focus loss did not cancel/drain pending card pan")
	row.scroll_horizontal = 0
	await _frames(2)
	origin = card.get_global_rect().get_center()
	await _touch(407, origin, true)
	await _touch(407, origin, false)
	_expect(_scroll_actions == 1, "ordinary card tap failed after pans/cancellations")


func _make_scroll_board(vertical: bool) -> Dictionary:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(620, 100) if vertical else Vector2(60, 100)
	scroll.size = Vector2(150, 180) if vertical else Vector2(480, 105)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if vertical else ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if vertical else ScrollContainer.SCROLL_MODE_DISABLED
	_layer.add_child(scroll)
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	var cards: Array[Button] = []
	for index: int in range(8):
		var card := Button.new()
		card.text = "Build %d" % index
		card.custom_minimum_size = Vector2(120, 64)
		card.focus_mode = Control.FOCUS_NONE
		card.pressed.connect(func() -> void: _scroll_actions += 1)
		box.add_child(card)
		cards.append(card)
		var choices: Callable = _choice_data if index == 1 else Callable()
		HOLD_SCRIPT.attach_to(card, _layer, _info, func() -> int: return _revision, func() -> Rect2: return _safe, choices)
	return {"scroll":scroll, "card":cards[0], "chooser":cards[1]}


func _make_button(text: String, position: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position
	button.size = Vector2(108, 64)
	button.focus_mode = Control.FOCUS_NONE
	_layer.add_child(button)
	return button


func _info() -> Dictionary:
	if not _info_override.is_empty():
		return _info_override
	return {"title":"Villager", "body":"Gather resources and construct buildings.\nCost:50Food.\nInspecting never purchases or cancels production."}


func _choice_data() -> Array[Dictionary]:
	return [{"id":"stop", "label":"Stop", "description":"Stop current orders"}, {"id":"patrol", "label":"Patrol", "description":"Arm Patrol; tap a destination"}, {"id":"stance", "label":"Stance", "description":"Change combat stance"}, {"id":"idle", "label":"Idle workers", "description":"Find idle workers"}]


func _touch(id: int, logical: Vector2, pressed: bool, canceled: bool = false) -> void:
	_inject_touch(id, logical, pressed, canceled)
	await _frames(2)


func _inject_touch(id: int, logical: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = get_viewport().get_final_transform() * logical
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)


func _mouse(logical: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = get_viewport().get_final_transform() * logical
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(2)


func _drag(id: int, logical: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = id
	event.position = get_viewport().get_final_transform() * logical
	Input.parse_input_event(event)
	await _frames(2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton:
		_world_events += 1
		print("[WORLD_LEAK] ", event.as_text(), " device=", event.device)


func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func _real_wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
