extends SceneTree
## Focused headless regression for the match-summary presentation contract.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/ui/game_over_screen.tscn")
	var screen: CanvasLayer = packed.instantiate()
	root.add_child(screen)
	await process_frame

	var stats: Dictionary = {
		"victory_reason": "Sacred Site held for 3:00",
		"game_time": "12:34",
		"player_age": 2,
		"ai_age": 3,
		"player_feudal_seconds": 245.0,
		"ai_feudal_seconds": 318.0,
		"score": 320,
		"ai_score": 280,
		"army_trained": 12,
		"ai_army_trained": 9,
		"units_killed": 8,
		"ai_units_killed": 5,
		"units_lost": 4,
		"ai_units_lost": 7,
		"buildings_lost": 1,
		"ai_buildings_lost": 3,
		"resources_gathered": 2400,
		"ai_resources_gathered": 2100,
		"sacred_control_seconds": 180,
		"ai_sacred_control_seconds": 42,
	}
	screen.show_victory(stats)
	screen.call("_fit_panel_to_size", Vector2(844, 390))
	await process_frame

	var failures: Array[String] = []
	var time_label: Label = screen.get_node("GameOverPanel/Margin/VBox/TimeLabel")
	if "Sacred Site held for 3:00" not in time_label.text:
		failures.append("summary omits victory reason")
	if "12:34" not in time_label.text:
		failures.append("summary omits match duration")
	if "Feudal 4:05 vs 5:18" not in time_label.text:
		failures.append("summary omits Feudal timing comparison")
	var diagnostics: Dictionary = screen.get("summary_diagnostics")
	for required_key in ["victory_reason", "army_trained", "buildings_lost", "resources_gathered", "player_feudal_seconds", "sacred_control_seconds"]:
		if not diagnostics.has(required_key):
			failures.append("diagnostics omit %s" % required_key)
	var stats_container: VBoxContainer = screen.get_node("GameOverPanel/Margin/VBox/StatsContainer")
	var row_names: Array[String] = []
	for row in stats_container.get_children():
		if row.get_child_count() >= 2:
			row_names.append(str(row.get_child(1).text))
	for required_row in ["Army Produced", "Units Lost", "Buildings Lost", "Resources Gathered", "Sacred Control"]:
		if required_row not in row_names:
			failures.append("summary omits row %s" % required_row)
	for button_name in ["PlayAgainButton", "MainMenuButton"]:
		var button: Button = screen.get_node("GameOverPanel/Margin/VBox/ButtonRow/%s" % button_name)
		if button.size.y < 48.0:
			failures.append("%s is below 48px touch target" % button_name)
	var panel: PanelContainer = screen.get_node("GameOverPanel")
	if panel.size.x > 828.0 or panel.size.y > 374.0:
		failures.append("game-over panel exceeds 844x390 safe bounds: %s" % panel.size)

	if failures.is_empty():
		print("[PASS] game_over_summary_contract: reason, duration, comparison rows, diagnostics, and touch targets")
		quit(0)
		return
	for failure in failures:
		push_error("[FAIL] game_over_summary_contract: %s" % failure)
	quit(1)
