extends Node
## Fixture Farms isolate remaining-stock feedback and Main's cleanup/loss ledger.
## Harvest is real; this does not simulate a paid match or prove economy balance.

var _failures: Array[String] = []
var _match: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	_match = load("res://scenes/main/main.tscn").instantiate()
	add_child(_match)
	for frame: int in range(900):
		if GameManager.current_state == GameManager.GameState.PLAYING and _match.get("_building_placement") != null: break
		await get_tree().process_frame
	_match.set_process(false)
	_match.get("ai_controller").get("_decision_timer").stop()
	var map: Node2D = _match.get("game_map") as Node2D
	var tile: Vector2i = map.map_generator.spawn_positions[0] + Vector2i(8, 0)
	var farm: BuildingBase = _match.call("_spawn_building", BuildingData.BuildingType.FARM, 0, tile) as BuildingBase
	farm.complete_instantly()
	var hud: Node = _match.get("hud")
	map.selection_mgr.select_single(farm)
	for frame: int in range(4): await get_tree().process_frame
	_expect((hud.get("selection_details") as Label).text == "Food: 300 remaining", "selected Farm exposes finite stock immediately")
	var details: Label = hud.get("selection_details") as Label
	var width: float = details.get_theme_font("font").get_string_size(details.text, HORIZONTAL_ALIGNMENT_LEFT, -1, details.get_theme_font_size("font_size")).x
	_expect(width <= details.size.x and details.get_line_count() == details.get_visible_line_count(), "finite Farm stock fits the phone information column")
	print("FARM_TEXT_METRIC ", JSON.stringify({"phone": "844x390", "text": details.text, "text_width": width, "available_width": details.size.x}))
	_expect(farm.harvest(200) == 200 and farm.farm_remaining == 100, "ordinary harvest reduces real finite stock")
	_match.call("_on_selection_changed", map.selection_mgr.selected)
	_expect((hud.get("selection_details") as Label).text == "Food: 100 remaining", "selected Farm refreshes remaining Food")
	var losses_before: int = (_match.get("_stats") as Array)[0]["buildings_lost"]
	var destroyed_signals: Array[int] = []
	farm.building_destroyed.connect(func(_building: BuildingBase) -> void: destroyed_signals.append(1))
	_expect(farm.harvest(150) == 100, "final harvest never exceeds remaining stock")
	_expect(farm.state == BuildingBase.State.DESTROYED and farm.depleted_naturally, "natural exhaustion records its cause before destruction")
	_expect(int((_match.get("_stats") as Array)[0]["buildings_lost"]) == losses_before, "exhaustion does not claim a building loss")
	_expect(_latest_notice(hud) == "Farm exhausted. Build another for more food.", "depletion explains the finite food supply without an attack warning")
	_expect(not farm in (_match.get("_player_buildings") as Array)[0], "depletion removes the old Farm from the ownership registry")
	_expect(not farm in map.get("_additional_resource_nodes"), "depletion removes its harvestable registry entry")
	_expect(farm.harvest(10) == 0 and destroyed_signals.size() == 1, "depleted harvest cannot duplicate Food or destruction")
	var damaged_farm: BuildingBase = _match.call("_spawn_building", BuildingData.BuildingType.FARM, 0, tile) as BuildingBase
	damaged_farm.complete_instantly()
	damaged_farm.take_damage(damaged_farm.hp)
	_expect(not damaged_farm.depleted_naturally and damaged_farm.farm_remaining == 300, "combat destruction retains its true cause")
	_expect(int((_match.get("_stats") as Array)[0]["buildings_lost"]) == losses_before + 1, "combat destruction still counts exactly one building loss")
	_expect(_latest_notice(hud) == "Building destroyed!", "combat destruction still warns the player")
	_finish()


func _latest_notice(hud: Node) -> String:
	var feed: Node = hud.get("_notification_container") as Node
	return (feed.get_child(feed.get_child_count() - 1).get_child(0) as Label).text


func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)


func _finish() -> void:
	if is_instance_valid(_match): _match.free()
	if _failures.is_empty():
		print("[PASS] farm_depletion_feedback: stock refresh, distinct cause/notice, cleanup, finite harvest and accurate loss ledger")
		get_tree().quit(0)
	else:
		for failure: String in _failures: push_error("[FAIL] farm_depletion_feedback: " + failure)
		get_tree().quit(1)
