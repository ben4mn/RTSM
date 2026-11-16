extends Node
## Exercise public objective feedback through the live Sacred Site state machine.

var _failures: Array[String] = []
var _match_scene: Node = null
var _saved_units: Array[Node] = []
@onready var root: Window = get_tree().root


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager: Node = root.get_node("GameManager")
	root.get_node("AudioManager").call("set_all_enabled", false)
	manager.set("selected_map_seed", 42)
	manager.set("selected_match_mode", SkirmishData.MatchMode.STANDARD)
	_match_scene = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_match_scene)
	get_tree().current_scene = _match_scene
	for _frame: int in 900:
		if int(manager.get("current_state")) == 2:
			break
		await get_tree().process_frame
	if int(manager.get("current_state")) != 2:
		_expect(false, "match did not reach PLAYING")
		_finish()
		return

	var map: Node2D = _match_scene.get("game_map") as Node2D
	var site: Node2D = map.get("sacred_site") as Node2D
	var hud: CanvasLayer = _match_scene.get("hud") as CanvasLayer
	var selection: SelectionManager = map.get("selection_mgr") as SelectionManager
	var label: Label = hud.get("_sacred_site_label") as Label
	var button: Button = hud.get("_sacred_site_button") as Button
	var panel: PanelContainer = hud.get("_sacred_site_panel") as PanelContainer
	site.process_mode = Node.PROCESS_MODE_DISABLED
	site.set("victory_wake_time", 0.0)  # The 8:00 opening has its own test (test_sacred_wake).
	_match_scene.set_process(false)
	(_match_scene.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	# Separate the fixture's participants from live starting villagers. Their
	# ownership/vision remains in the real match, but cannot alter site counts.
	for unit: Node in get_tree().get_nodes_in_group("units"):
		_saved_units.append(unit)
		unit.remove_from_group("units")
	var friendly: Node2D = _participant(site.global_position, 0)
	var enemy: Node2D = _participant(site.global_position + Vector2(500, 0), 1)
	await get_tree().process_frame
	_expect(panel.visible and button.size.y >= 48.0, "neutral locator is visible and at least 48px tall")
	_expect("Neutral" in label.text and "tap to view" in label.text, "neutral status explains discovery")
	_expect("Scouts" in button.tooltip_text and "villagers" in button.tooltip_text, "capture instructions cover all living unit types")

	# The visual boundary and detector share one radius, including its edge.
	var radius: float = float(site.call("get_capture_radius_world"))
	_expect(is_equal_approx(radius, float(site.get("capture_radius")) * MapData.TILE_WIDTH), "boundary uses the authoritative radius")
	friendly.position = site.global_position + Vector2(radius, 0)
	_expect((site.call("_count_nearby_players") as Array)[0] == 1, "unit on capture boundary counts")
	friendly.position.x += 0.01
	_expect((site.call("_count_nearby_players") as Array)[0] == 0, "unit outside capture boundary does not count")
	friendly.position = site.global_position
	_expect(map.get_node("FogLayer").z_index > site.z_index, "capture boundary remains beneath the existing fog overlay")

	site.call("_process", 0.0)
	_expect("You capturing" in label.text, "entry immediately exposes capturing state")
	selection.call("_add_to_selection", site)
	_expect(selection.selected == [site] and hud.get("_selection_kind") == "sacred", "visible site can be inspected")
	site.call("_process", 6.0)
	_expect("20%" in (hud.get("selection_details") as Label).text, "selected inspector refreshes capture progress without reselection")
	site.call("_process", 24.0)
	_expect("You win in 3:00" in label.text, "capture starts the actual three-minute hold")
	site.call("_process", 12.0)
	_expect("2:48" in label.text, "holding countdown follows authoritative time")
	var gold_before: int = ResourceManager.get_resource(0, "gold")
	friendly.position = site.global_position + Vector2(500, 0)
	site.call("_process", 5.0)
	_expect("Held · bring a fighter" in label.text and "2:48 paused" in label.text, "unguarded Standard clock visibly pauses without losing progress")
	_expect("Bring a fighter" in (hud.get("selection_details") as Label).text, "inspector explains paused garrison clock")
	_expect(int(site.get("owning_player")) == 0 and is_equal_approx(float(site.get("capture_progress")), 1.0) and ResourceManager.get_resource(0, "gold") == gold_before + 10, "leaving preserves ownership/capture and normal gold income")
	_expect("gold income continues" in button.tooltip_text, "inspection states the unchanged income rule")
	friendly.position = site.global_position
	site.call("_process", 0.0)
	_expect("You win in 2:48" in label.text, "returning fighter resumes feedback immediately")
	var hint := {"context": "sacred", "text": "Control unchanged"}
	_expect("Keep a fighter" in str(_match_scene.call("_timed_hint_text", hint)), "Standard guide describes guarded clock")
	# Copy-only fixture: inspect both latched rules without initializing a second match.
	var original_mode: int = GameManager.get_match_mode()
	GameManager.set("_match_mode", SkirmishData.MatchMode.QUICK_CONTROL)
	_expect(str(_match_scene.call("_timed_hint_text", hint)) == "Control unchanged", "Control guide copy remains unchanged")
	GameManager.set("_match_mode", original_mode)
	enemy.position = site.global_position + Vector2(10, 0)
	site.call("_process", 0.5)
	_expect("Contested" in label.text and "2:48 paused" in label.text, "contest explicitly pauses the preserved clock")
	_expect(selection.selected == [site] and "Contested" in (hud.get("selection_details") as Label).text, "selected inspector follows contest without being cleared")
	enemy.position = site.global_position + Vector2(500, 0)
	site.call("_process", 0.0)
	site.call("_process", 0.0)
	site.call("_process", 5.0)
	_expect("You win in 2:43" in label.text, "same-owner recovery resumes rather than restarting the hold")

	# Opponent takeover earns its own full hold instead of inheriting the clock.
	_match_scene.set("_sacred_site_victory_notified", true)
	enemy.position = site.global_position + Vector2(10, 0)
	site.call("_process", 0.0)
	friendly.position = site.global_position + Vector2(500, 0)
	site.call("_process", 30.0)
	site.call("_process", 30.0)
	site.call("_process", 2.0)
	_expect("Enemy win in 2:58" in label.text, "opponent ownership uses a new hold clock")
	_expect(not bool(_match_scene.get("_sacred_site_victory_notified")), "new owner receives its own final-minute warning")
	_expect("Enter to pause" in (hud.get("selection_details") as Label).text, "enemy site inspection explains how to interrupt victory")
	friendly.position = site.global_position
	enemy.position = site.global_position + Vector2(500, 0)
	site.call("_process", 0.5)
	_expect("Disrupted" in label.text and "2:58 paused" in label.text, "undefended enemy site also reports its paused clock")
	# A partially neutralized site resumes when attackers retreat; its capture
	# progress alone must not make the UI claim the clock is still paused.
	friendly.position = site.global_position + Vector2(500, 0)
	site.call("_process", 1.0)
	_expect("Enemy held · unguarded" in label.text and "2:58 paused" in label.text, "attacker retreat leaves an unguarded enemy clock paused")
	enemy.position = site.global_position
	site.call("_process", 1.0)
	_expect("Enemy win in 2:57" in label.text, "returning enemy guard resumes the preserved clock")
	enemy.position = site.global_position + Vector2(500, 0)
	friendly.position = site.global_position
	site.call("_process", 30.0)
	_expect("Neutral" in label.text and panel.visible, "neutralization preserves the locator")

	friendly.free()
	enemy.free()
	selection.call("_clear_selection")
	site.set("state", 2)
	site.set("owning_player", 1)
	site.set("capture_progress", 1.0)
	site.set("victory_timer", 2.0)
	_match_scene.call("_refresh_sacred_site_status")
	var fog: FogManager = map.get("fog_of_war") as FogManager
	var site_tile: Vector2i = map.call("world_to_tile", site.global_position)
	var fog_before: int = int(fog.fog_grid[site_tile.y][site_tile.x])
	_expect(fog_before == MapData.FogState.UNEXPLORED, "seeded objective starts behind fog")
	selection.call("_add_to_selection", site)
	_expect(selection.selected.is_empty(), "enemy-held site behind fog cannot be inspected")
	var worker: UnitBase = (_match_scene.get("_player_units") as Array)[0][0] as UnitBase
	selection.call("_add_to_selection", worker)
	var before_selection: Array[Node2D] = selection.selected.duplicate()
	button.emit_signal("pressed")
	_expect((map.get("camera") as Camera2D).position.distance_to(site.global_position) < 0.1, "locator focuses the objective")
	_expect(selection.selected == before_selection, "locator preserves units for a follow-up order")
	_expect(int(fog.fog_grid[site_tile.y][site_tile.x]) == fog_before, "locator does not reveal objective terrain")
	# Reveal only for command routing: tapping an enemy-owned site should move
	# troops, never issue an ineffective damage command against a neutral object.
	fog.fog_grid[site_tile.y][site_tile.x] = MapData.FogState.VISIBLE
	var moves: Array[Vector2i] = []
	var attacks: Array[Node2D] = []
	selection.move_command.connect(func(tile: Vector2i) -> void: moves.append(tile))
	selection.attack_command.connect(func(target: Node2D) -> void: attacks.append(target))
	selection.call("_handle_tap", selection.call("_world_to_screen", site.global_position), true)
	_expect(moves == [site_tile] and attacks.is_empty(), "touch on Sacred Site orders units into its ring")
	var actions: Array = selection.call("_build_touch_context_actions", site, null)
	_expect(actions.size() == 1 and int(actions[0]["id"]) == SelectionManager.TouchContextAction.MOVE, "Sacred context action offers movement instead of attack")
	selection.call("_clear_selection")
	selection.call("_handle_tap", selection.call("_world_to_screen", site.global_position), true)
	_expect(selection.selected == [site] and hud.get("_selection_kind") == "sacred", "touch without troops opens the visible site inspector")
	await _check_phone_status_layout()
	_finish()


func _participant(position: Vector2, player_id: int) -> Node2D:
	# A real armed unit supplies the Standard guard; no synthetic guard flag.
	var participant := preload("res://scenes/units/infantry.tscn").instantiate() as UnitBase
	participant.player_owner = player_id
	participant.position = position
	root.add_child(participant)
	participant.set_process(false)
	return participant


func _check_phone_status_layout() -> void:
	const UI_SCALE := 1.15
	var logical_size := Vector2(floorf(844.0 / UI_SCALE), floorf(390.0 / UI_SCALE))
	var safe_area := Rect2(Vector2(44.0 / UI_SCALE, 0), logical_size - Vector2(88.0 / UI_SCALE, 18.0 / UI_SCALE))
	var phone := SubViewport.new()
	phone.size = Vector2i(logical_size)
	root.add_child(phone)
	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	phone.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	for guided: bool in [false, true]:
		hud.call("set_progression_hint", "Guide · capture the site" if guided else "", false)
		for phase: String in ["neutral", "capturing", "holding", "unguarded", "contested", "neutralizing"]:
			hud.call("update_sacred_site_status", {"phase": phase, "owner": 1, "remaining": 532.1, "total": 600.0, "capture_progress": 0.42})
			hud.call("apply_mobile_layout", logical_size, safe_area)
			await get_tree().process_frame
			await get_tree().process_frame
			var button: Button = hud.get("_sacred_site_button") as Button
			var panel: PanelContainer = hud.get("_sacred_site_panel") as PanelContainer
			var label: Label = hud.get("_sacred_site_label") as Label
			_expect(button.size.y * UI_SCALE >= 48.0, "%s phone status retains a 48px touch target" % phase)
			_expect(safe_area.encloses(panel.get_global_rect()), "%s phone status stays inside notched safe bounds" % phase)
			var font: Font = label.get_theme_font("font")
			for line: String in label.text.split("\n"):
				_expect(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= button.size.x - 8.0, "%s phone status text fits its button" % phase)
			var notifications: Control = hud.get("_notification_container") as Control
			_expect(not panel.get_global_rect().intersects(notifications.get_global_rect(), true), "%s phone status avoids the notification lane" % phase)
	phone.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[FAIL] sacred_site_mobile: " + message)


func _finish() -> void:
	for unit: Node in _saved_units:
		if is_instance_valid(unit):
			unit.add_to_group("units")
	get_tree().paused = false
	if is_instance_valid(_match_scene):
		_match_scene.free()
	get_tree().current_scene = null
	if _failures.is_empty():
		print("[PASS] sacred_site_mobile: locator, capture radius, preserved clocks, inspector updates, fog rules, and touch orders")
	get_tree().quit(0 if _failures.is_empty() else 1)
