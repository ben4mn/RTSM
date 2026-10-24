extends Node
## Real menu/compare modal at phone safe areas, plus draft and cancellation rules.

class SafeAreaMenu:
	extends "res://scripts/ui/main_menu.gd"
	var modeled_safe_area := Rect2()
	func _refresh_responsive_layout() -> void:
		if is_node_ready():
			# Model platform geometry on every production reflow, including modal
			# close. A one-off layout injection reverts to native desktop insets.
			apply_mobile_layout(get_viewport().get_visible_rect().size, modeled_safe_area, 60.0)

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var original_self: int = GameManager.selected_civilization
	var original_rival: int = GameManager.selected_opponent_civilization
	for pixels: Vector2 in [Vector2(844, 390), Vector2(932, 430), Vector2(1280, 720)]:
		for scale_value: float in [1.0, 1.15]:
			var size_value: Vector2 = (pixels / scale_value).floor()
			var inset: float = 44.0 / scale_value
			var safe := Rect2(Vector2(inset, 0), size_value - Vector2(inset * 2, 18.0 / scale_value))
			var viewport := SubViewport.new()
			viewport.size = Vector2i(size_value)
			add_child(viewport)
			var menu := SafeAreaMenu.new()
			menu.modeled_safe_area = safe
			menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			menu.size = size_value
			viewport.add_child(menu)
			menu.call("_open_new_game", "solo")
			await _settle()
			await _settle()
			var context: String = "%s scale %.2f" % [pixels, scale_value]
			_bounds(menu.get("_header"), safe, context + " setup header")
			_bounds(menu.get("settings_button"), safe, context + " settings beside setup choices")
			_kingdom_choice(menu.get("_civilization_button"), menu.get("_civilization_name"), GameManager.selected_civilization, safe, context + " player setup")
			_expect(menu.find_child("ChooseOpponentCivilizationButton", true, false) == null, context + " setup has no second kingdom selector")
			_bounds(menu.get("start_button"), safe, context + " Start remains reachable")
			for id: int in CivilizationData.ORDERED_IDS:
				(menu.get("_civilization_button") as Button).pressed.emit()
				var picker: Control = menu.get("_civilization_picker")
				(menu.get("_civilization_button") as Button).pressed.emit()
				_expect(menu.get("_civilization_picker") == picker and _visible_pickers(menu) == 1, context + " repeat press keeps one modal")
				menu.call("_on_settings_pressed")
				_expect(menu.get("_shared_settings") == null, context + " settings cannot stack over kingdom choice")
				await _settle()
				picker.call("apply_mobile_layout", size_value, safe)
				picker.call("select_civilization", id)
				await _settle()
				_bounds(picker.get("_panel"), safe, context + " comparison panel")
				for button: Button in picker.get("_cards"):
					_bounds(button, safe, context + " kingdom choice")
					_expect(button.size.y >= 48, context + " kingdom choice touch height")
				var detail: Label = picker.get("_detail")
				var definition: Dictionary = CivilizationData.get_definition(id)
				_expect(detail.text.contains(str(definition.weakness)), context + " weakness visible in details")
				_expect(detail.text.contains(str(definition.strengths)), context + " strengths visible in details")
				_expect(not bool(menu.get("_web_update_safe")), context + " modal blocks web reload")
				_bounds(picker.get("_confirm"), safe, context + " confirmation reachable")
				(picker.get("_confirm") as Button).pressed.emit()
				_expect(not picker.visible, context + " confirmed modal hides immediately")
				# A same-frame reopen must survive stale presses on the old dialog.
				(menu.get("_civilization_button") as Button).pressed.emit()
				var reopened: Control = menu.get("_civilization_picker")
				(picker.get("_confirm") as Button).pressed.emit()
				_expect(reopened != picker and menu.get("_civilization_picker") == reopened and _visible_pickers(menu) == 1, context + " rapid reopen keeps exactly one active picker")
				reopened.call("close")
				await _settle()
				_expect(GameManager.selected_civilization == id, context + " confirms player kingdom")
				_kingdom_choice(menu.get("_civilization_button"), menu.get("_civilization_name"), id, safe, context + " confirmed player setup")
				_expect(not (menu.get("_selection_summary") as Label).text.contains(str(definition.name)), context + " footer does not repeat the kingdom choice")
				_expect(bool(menu.get("_web_update_safe")), context + " closed modal restores menu update safety")
			_expect(GameManager.selected_opponent_civilization == original_rival, context + " setup leaves rival resolution until match seed exists")
			(menu.get("_civilization_button") as Button).pressed.emit()
			await _settle()
			var cancel_picker: Control = menu.get("_civilization_picker")
			cancel_picker.call("select_civilization", CivilizationData.Civilization.CROWNLANDS)
			cancel_picker.call("close")
			(cancel_picker.get("_confirm") as Button).pressed.emit()
			await _settle()
			_expect(GameManager.selected_civilization == CivilizationData.Civilization.SUNSTRIDE_CLANS, context + " cancellation preserves draft")
			if pixels == Vector2(1280, 720) and is_equal_approx(scale_value, 1.0):
				_test_room_and_loading_context(menu, context)
			menu.free()
			viewport.free()
	GameManager.selected_civilization = original_self
	GameManager.selected_opponent_civilization = original_rival
	if _failures.is_empty():
		print("[PASS] civilization_menu: %d checks, one setup choice, three kingdoms, rapid reopen/cancellation, phone safe areas and update safety" % _checks)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] civilization_menu: " + failure)
		get_tree().quit(1)


func _settle() -> void:
	for frame: int in 4:
		await get_tree().process_frame


func _test_room_and_loading_context(menu: Control, context: String) -> void:
	# Model server notifications without opening sockets or changing authority.
	var session: Node = get_node("/root/NetworkSession")
	var saved: Dictionary = {}
	for key: String in ["state", "room_code", "room_host", "room_players", "room_civilizations"]:
		saved[key] = session.get(key)
	var player_before: int = GameManager.selected_civilization
	session.set("state", "lobby")
	session.set("room_code", "CIV123")
	session.set("room_host", false)
	session.set("room_players", 2)
	var room_ids: Array[int] = [0, 1]
	session.set("room_civilizations", room_ids)
	menu.call("_on_room_changed")
	_expect((menu.get("_civilization_name") as Label).text == CivilizationData.get_civilization_name(1), context + " guest choice reads its actual room slot")
	_expect((menu.get("_room_civilizations") as Label).text == "Opponent: " + CivilizationData.get_civilization_name(0), context + " lobby identifies the other slot without a second selector")
	(menu.get("_civilization_button") as Button).pressed.emit()
	var stale_picker: Control = menu.get("_civilization_picker")
	_expect(int(stale_picker.get("selected")) == 1, context + " picker opens on authoritative guest kingdom")
	stale_picker.call("select_civilization", 0)
	session.set("room_code", "OTHER1")
	menu.call("_on_room_changed")
	(stale_picker.get("_confirm") as Button).pressed.emit()
	_expect(not stale_picker.visible and menu.get("_civilization_picker") == null and GameManager.selected_civilization == player_before, context + " room change discards stale modal choice")
	(menu.get("_civilization_button") as Button).pressed.emit()
	var loading_picker: Control = menu.get("_civilization_picker")
	loading_picker.call("select_civilization", 0)
	session.set("state", "loading")
	menu.call("_on_network_status_changed", "loading", "Starting match")
	(loading_picker.get("_confirm") as Button).pressed.emit()
	_expect(not loading_picker.visible and menu.get("_civilization_picker") == null and GameManager.selected_civilization == player_before, context + " loading discards stale modal choice")
	for key: String in saved:
		session.set(key, saved[key])
	menu.call("_on_network_status_changed", str(session.get("state")), "")


func _bounds(control: Control, safe: Rect2, label: String) -> void:
	_expect(control.is_visible_in_tree() and safe.grow(0.5).encloses(control.get_global_rect()), label + " bounds " + str(control.get_global_rect()))


func _visible_pickers(menu: Control) -> int:
	var count: int = 0
	for child: Node in menu.get_children():
		if child is Control and child.has_method("select_civilization") and (child as Control).is_visible_in_tree():
			count += 1
	return count


func _kingdom_choice(button: Button, name_label: Label, civilization: int, safe: Rect2, context: String) -> void:
	var expected_name: String = CivilizationData.get_civilization_name(civilization)
	_bounds(button, safe, context + " reachable choice")
	_bounds(name_label, button.get_global_rect(), context + " selected name remains within choice")
	_expect(button.size.x >= 48.0 and button.size.y >= 48.0 and not button.disabled, context + " usable touch target")
	_expect(name_label.text == expected_name, context + " visibly identifies the current draft")
	# A narrow display may ellipsize the label; assistive output keeps its full name.
	_expect(button.accessibility_name.contains(expected_name), context + " full selected name is accessible")


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
