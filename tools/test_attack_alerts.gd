extends SceneTree
## Exercise real damage/healing and mobile alert navigation in a running match.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("AudioManager").call("set_all_enabled", false)
	root.get_node("GameManager").set("guided_opening_enabled", false)
	var match_scene: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(match_scene)
	current_scene = match_scene
	for frame in range(900):
		if match_scene.get("_player_town_center") != null:
			break
		await process_frame
	var tc: Node2D = match_scene.get("_player_town_center") as Node2D
	_expect(tc != null, "match initializes Town Center")
	if tc == null:
		_finish(match_scene)
		return
	match_scene.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	var hud: Node = match_scene.get_node("HUD")
	var feedback: Control = match_scene.get("_battlefield_feedback") as Control
	var feed: VBoxContainer = feedback.get("_lane") as VBoxContainer
	_clear_fronts(feedback)

	# A genuine building hit previously had no notification connection at all.
	match_scene.set("_under_attack_cooldown", 0.0)
	tc.call("take_damage", 5)
	_expect((feedback.get("fronts") as Array).size() == 1, "building damage creates one alert")
	var panel: Button = feed.get_child(0) as Button
	_expect(panel.text.contains("Town Center") and panel.text.contains("view"), "alert identifies attacked building and touch action")
	_expect(panel.custom_minimum_size.y >= 48.0, "attack alert is at least a 48px touch target")
	_expect(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "alert consumes map input")
	var game_map: Node = match_scene.get_node("GameMap")
	var camera: Camera2D = game_map.get("camera") as Camera2D
	camera.position = tc.global_position + Vector2(128.0, 128.0)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(20.0, 60.0)
	panel.pressed.emit()
	_expect(camera.position.distance_to(tc.global_position) < 1.0, "touching alert focuses attack location")
	tc.call("take_damage", 5)
	_expect((feedback.get("fronts") as Array).size() == 1, "successive hits are throttled")

	var units_by_player: Array = match_scene.get("_player_units") as Array
	var villager: Node = (units_by_player[0] as Array)[0]
	_clear_fronts(feedback)
	match_scene.set("_under_attack_cooldown", 0.0)
	villager.call("take_damage", 2.0)
	_expect((feedback.get("fronts") as Array).size() == 1, "real unit damage creates an alert")
	_clear_fronts(feedback)
	match_scene.set("_under_attack_cooldown", 0.0)
	villager.call("heal", 2.0)
	_expect((feedback.get("fronts") as Array).is_empty(), "healing never creates under-attack alerts")
	# HUD pass: a boar's bite is wildlife, not a raid. It still hurts.
	var hp_before_bite: float = float(villager.get("hp"))
	villager.call("take_wildlife_damage", 2.0)
	_expect((feedback.get("fronts") as Array).is_empty() and float(villager.get("hp")) < hp_before_bite, "a boar bite wounds without raising a RAID alert")
	_expect(not bool(villager.get("wildlife_hit")), "the wildlife marker only lasts for the bite itself")
	villager.call("take_damage", 2.0)
	_expect((feedback.get("fronts") as Array).size() == 1, "a real attack after a bite still alerts")
	# HUD pass: the alert lane's response hook (the town bell shortcut uses it).
	# The plate stands beside the cards, as tall as they are, never below them.
	var answered: Array[int] = [0]
	var probe_answer := func() -> void: answered[0] += 1
	feedback.call("offer_response", "probe", "Ring bell", null, probe_answer, "Probe")
	var response: Button = feedback.get_node_or_null("Response_probe") as Button
	var alert_card: Button = feed.get_child(0) as Button
	_expect(response != null and response.visible and response.size.x >= 48.0 and response.size.y >= 48.0 and response.text == "Ring bell", "an offered response is a 48px target beside the alert card")
	_expect(response != null and response.position.x >= feed.position.x + feed.size.x and is_equal_approx(response.position.y, feed.position.y) and not response.get_global_rect().intersects(alert_card.get_global_rect()), "the response stands beside the card without covering it")
	_expect(bool(feedback.call("has_response", "probe")) and (feedback.call("get_visible_bounds") as Array).has(response.get_global_rect()), "an offered response is part of the lane's touch bounds")
	response.pressed.emit()
	_expect(answered[0] == 1 and not response.visible and not bool(feedback.call("has_response", "probe")), "one tap answers and retires the response")
	feedback.call("offer_response", "probe", "Ring bell", null, probe_answer)
	feedback.call("withdraw_response", "probe")
	_expect(not response.visible and answered[0] == 1, "a withdrawn response disappears without firing")
	feedback.call("offer_response", "probe", "Ring bell", null, probe_answer)
	_clear_fronts(feedback)
	feedback.call("_refresh")
	_expect(not response.visible, "a response never outlives the alert cards")
	feedback.call("withdraw_response", "probe")
	tc.call("take_damage", 0)
	tc.call("take_damage", -10)
	_expect((feedback.get("fronts") as Array).is_empty(), "zero or negative building damage creates no attack alert")
	var enemy: Node = (units_by_player[1] as Array)[0]
	enemy.call("take_damage", 2.0)
	_expect((feedback.get("fronts") as Array).is_empty(), "enemy unit damage does not alert the human")
	match_scene.call("_show_under_attack_alert", "Town Center", tc.global_position)
	match_scene.call("_show_under_attack_alert", "Villager", tc.global_position + Vector2(800, 0))
	_expect((feedback.get("fronts") as Array).size() == 2, "separate fronts survive global audio throttling")
	hud.call("show_notification", "Warrior trained")
	feedback.call("_process", 0.0)
	# HUD pass: toasts have their own lane beside the alert column, so a raid
	# no longer hides them (the bell's "villagers take shelter" must be seen).
	var toast_lane: Control = hud.get("_notification_container") as Control
	_expect((feedback.get("fronts") as Array).size() == 2 and toast_lane.visible, "ordinary production cannot replace either raid card, and its toast still shows")
	for toast: Node in toast_lane.get_children():
		if toast is Control and (toast as Control).visible and not toast.is_queued_for_deletion():
			for card: Rect2 in feedback.call("get_visible_bounds"):
				_expect(not card.intersects((toast as Control).get_global_rect()), "a toast never covers a raid card")
	await _test_phone_alert_layout(game_map)
	_finish(match_scene)


func _test_phone_alert_layout(game_map: Node) -> void:
	for phone_size: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale_factor: float in [1.0, 1.075, 1.15]:
			var logical_size := Vector2i(floori(phone_size.x / scale_factor), floori(phone_size.y / scale_factor))
			var viewport := SubViewport.new()
			viewport.size = logical_size
			root.add_child(viewport)
			var mobile_hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
			viewport.add_child(mobile_hud)
			await process_frame
			var safe := Rect2(Vector2(44.0 / scale_factor, 0.0), Vector2(logical_size) - Vector2(88.0 / scale_factor, 18.0 / scale_factor))
			mobile_hud.call("set_progression_hint", "Tap a villager, then a berry bush.", false)
			mobile_hud.call("update_sacred_site_timer", 1, 172.0, 600.0)
			mobile_hud.call("show_notification", "Town Center under attack! Tap to view.", Color.RED, 6.0, func() -> void: pass)
			await process_frame
			await process_frame
			mobile_hud.call("apply_mobile_layout", Vector2(logical_size), safe)
			await process_frame
			await process_frame
			var feedback: Control = load("res://scripts/ui/battlefield_feedback.gd").new()
			mobile_hud.get_node("Root").add_child(feedback)
			feedback.call("setup", mobile_hud, game_map, func(_position: Vector2) -> void: pass)
			feedback.call("report_attack", "Town Center", Vector2.ZERO)
			feedback.call("report_attack", "Villager", Vector2(800, 0))
			await process_frame
			await process_frame
			var alert_feed: VBoxContainer = feedback.get("_lane") as VBoxContainer
			var alert: Button = alert_feed.get_child(0) as Button
			var prefix := "%s scale %.2f" % [phone_size, scale_factor]
			_expect(alert.size.y >= 48.0, prefix + " settled touch target remains at least48px")
			_expect(safe.encloses(alert.get_global_rect()), prefix + " attack alert is inside safe area")
			_expect(safe.encloses((alert_feed.get_child(1) as Control).get_global_rect()), prefix + " second raid stays inside safe bounds")
			for sibling: String in ["_progression_hint_panel", "_sacred_site_panel", "_camera_controls"]:
				var control: Control = mobile_hud.get(sibling) as Control
				_expect(not control.visible or not control.get_global_rect().intersects(alert.get_global_rect()), prefix + " attack alert does not overlap " + sibling)
			viewport.free()


func _clear_fronts(feedback: Control) -> void:
	(feedback.get("fronts") as Array).clear()
	feedback.call("_refresh")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish(match_scene: Node) -> void:
	match_scene.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] attack_alerts: actual unit/building damage, healing, throttle and touch focus")
	quit(0 if _failures.is_empty() else 1)
