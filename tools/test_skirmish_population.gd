extends Node
## Actual match budgets: both players, queue reservations, housing and age costs.

var _failures: Array[String] = []
@onready var root: Window = get_tree().root


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	root.size = Vector2i(844, 390)
	for limit: int in SkirmishData.POPULATION_OPTIONS:
		GameManager.selected_population_limit = limit
		GameManager.initialize_game(2)
		for player_id: int in [0, 1]:
			_expect(GameManager.get_player_population_limit(player_id) == limit, "%d: player %d has wrong limit" % [limit, player_id])
			GameManager.increase_population_cap(player_id, 1000)
			_expect(int(GameManager.players[player_id]["population_cap"]) == limit, "%d: housing exceeds limit" % limit)
			var reservation: int = GameManager.reserve_population(player_id, limit - 1)
			_expect(reservation > 0, "%d: valid reservation rejected" % limit)
			_expect(GameManager.reserve_population(player_id, 2) == -1, "%d: queued cavalry can overshoot limit" % limit)
			_expect(GameManager.consume_population_reservation(reservation), "%d: reservation cannot complete" % limit)
			_expect(GameManager.add_population(player_id, 1), "%d: final slot rejected" % limit)
			_expect(not GameManager.add_population(player_id, 1), "%d: live population can overshoot limit" % limit)
		_expect(GameManager.get_age_up_cost(0, 2) == GameManager.get_age_up_cost(1, 2), "%d: asymmetric age-up costs" % limit)
		var recorded_cost: Dictionary = GameManager.get_age_up_cost(0, 2)
		GameManager.selected_population_limit = 40 if limit != 40 else 20
		_expect(GameManager.get_match_population_limit() == limit, "%d: changing menu preference mutates running match" % limit)
		_expect(GameManager.get_age_up_cost(0, 2) == recorded_cost, "%d: changing menu preference mutates running economy" % limit)

		GameManager.selected_population_limit = limit
		var match_scene: Node = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(match_scene)
		for frame: int in range(900):
			if match_scene.get("_building_placement") != null:
				break
			await get_tree().process_frame
		_expect(match_scene.get("_building_placement") != null, "%d: match initialization timed out" % limit)
		_expect(int(GameManager.players[0]["population_cap"]) == 10, "%d: starting Town Center housing changed" % limit)
		_expect(GameManager.get_player_population_limit(1) == limit, "%d: AI match limit wrong" % limit)
		var cost: Dictionary = GameManager.get_age_up_cost(0, 2)
		var before: Dictionary = ResourceManager.get_all_resources(0)
		match_scene.call("_on_age_up_requested")
		_expect(GameManager.get_player_age(0) == 1, "%d: starting stock buys instant Feudal" % limit)
		for resource: String in cost:
			var missing: int = maxi(0, int(cost[resource]) - int(before.get(resource, 0)))
			ResourceManager.add_resource(0, resource, missing)
		before = ResourceManager.get_all_resources(0)
		match_scene.call("_on_age_up_requested")
		_expect(GameManager.get_player_age(0) == 2, "%d: affordable human age-up failed" % limit)
		for resource: String in cost:
			_expect(ResourceManager.get_resource(0, resource) == int(before[resource]) - int(cost[resource]), "%d: human spent wrong %s age cost" % [limit, resource])
		var hud: Node = match_scene.get_node("HUD")
		var game_map: Node = match_scene.get("game_map")
		for frame: int in range(4):
			await get_tree().process_frame
		var initial_zoom: float = float(game_map.call("get_zoom_state")["zoom"])
		var view: Button = hud.get("_camera_view_button") as Button
		if view.is_visible_in_tree() and not (hud.get("_camera_zoom_in_button") as Button).is_visible_in_tree():
			await _click(view.get_global_rect().get_center())
			for frame: int in range(4):
				await get_tree().process_frame
		var zoom_in: Button = hud.get("_camera_zoom_in_button") as Button
		await _click(zoom_in.get_global_rect().get_center())
		_expect(float(game_map.call("get_zoom_state")["zoom"]) > initial_zoom, "%d: real HUD + click did not zoom" % limit)
		var reset: Button = hud.get("_camera_zoom_reset_button") as Button
		await _click(reset.get_global_rect().get_center())
		_expect(is_equal_approx(float(game_map.call("get_zoom_state")["zoom"]), initial_zoom), "%d: real HUD reset did not restore camera" % limit)
		match_scene.free()
		GameManager.set_state(GameManager.GameState.MENU)
		await get_tree().process_frame
	if _failures.is_empty():
		print("[PASS] skirmish_population: 20/30/40 fair budgets, housing/queue limits, real age spending, GUI zoom/reset")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] skirmish_population: %s" % failure)
		get_tree().quit(1)


func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	await get_tree().process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		root.push_input(event, true)
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
