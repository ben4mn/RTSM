extends SceneTree
## Honest measured explanations plus 12 phone-safe result layouts.

const DEBRIEF := preload("res://scripts/main/match_debrief.gd")
var failures: Array[String] = []
var records: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session: Node = root.get_node("NetworkSession")
	var examples: Array[Dictionary] = [
		{"player_civilization": 1, "opponent_civilization": 2, "battle": {"losses_by_matchup": [[2, 3, 7]]}, "victory_reason": "Sacred Site held for 6:00", "ai_sacred_control_seconds": 360, "learning": {"objective_contests": 8}, "expect": "Outriders landed final blows on 7 of your Longbows"},
		{"player_civilization": 2, "opponent_civilization": 1, "battle": {"losses_by_matchup": [[3, 1, 9999]]}, "expect": "Warriors landed final blows on 9999 of your Outriders"},
		{"match_mode": SkirmishData.MatchMode.QUICK_CONTROL, "victory_reason": "Sacred control banked for 4:00", "is_victory": false, "ai_sacred_control_seconds": 240, "learning": {"objective_contests": 4}, "expect": "Both sides keep earned time"},
		{"victory_reason": "Sacred Site held for 10:00", "learning": {"paid_army": 0}, "expect": "No fighting troops"},
		{"learning": {"paid_army": 3, "worker_losses": 2, "worker_replacements": 1}, "expect": "Workers lost 2; paid replacements 1"},
		{"victory_reason": "Sacred Site held for 10:00", "ai_sacred_control_seconds": 600, "learning": {"paid_army": 3, "worker_losses": 8, "worker_replacements": 0}, "expect": "No Sacred capture or contest"},
		{"victory_reason": "Town Center destroyed", "learning": {"paid_army": 5, "worker_losses": 2}, "expect": "Your Town Center fell"},
		{"learning": {"paid_army": 3, "army_losses": 2, "army_replacements": 1}, "expect": "Fighting troops lost 2; paid replacements 1"},
		{"learning": {"paid_army": 3, "counter_demonstrated": false}, "expect": "No counter preparation"},
		{"learning": {"paid_army": 8, "army_losses": 3, "army_replacements": 3, "first_army_seconds": 144, "objective_contests": 2, "counter_demonstrated": true}, "expect": "First fighting troop 2:24; paid replacements 3; Sacred contests 2"},
	]
	_expect(DEBRIEF.describe({}).is_empty(), "Absent telemetry produces no invented facts")
	for example: Dictionary in examples:
		var text: String = DEBRIEF.describe(example)
		_expect(str(example["expect"]) in text, "Debrief uses observed fact: " + str(example["expect"]))
	var packed: PackedScene = load("res://scenes/ui/game_over_screen.tscn")
	for physical: Vector2 in [Vector2(844, 390), Vector2(932, 430)]:
		for scale_value: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				var logical := Vector2(floorf(physical.x / scale_value), floorf(physical.y / scale_value))
				var inset: float = 44.0 / scale_value if notched else 0.0
				var safe := Rect2(Vector2(inset, 0), logical - Vector2(inset * 2, 18.0 / scale_value if notched else 0.0))
				var viewport := SubViewport.new()
				viewport.size = Vector2i(logical)
				viewport.process_mode = Node.PROCESS_MODE_ALWAYS
				root.add_child(viewport)
				var screen: CanvasLayer = packed.instantiate()
				viewport.add_child(screen)
				await process_frame
				var max_lines: int = 0
				var panel: Control = screen.get_node("GameOverPanel")
				for example: Dictionary in examples:
					screen.show_defeat(example)
					screen.call("_fit_panel_to_size", logical, safe)
					await process_frame
					await process_frame
					var label: Label = screen.get("_debrief_label")
					max_lines = maxi(max_lines, label.get_line_count())
					_expect(label.get_line_count() <= 3, "%s %.3f notch%s debrief text fits three lines" % [physical, scale_value, notched])
					var rect: Rect2 = panel.get_global_rect()
					_expect(rect.position.x >= safe.position.x - 0.5 and rect.position.y >= safe.position.y - 0.5 and rect.end.x <= safe.end.x + 0.5 and rect.end.y <= safe.end.y + 0.5, "%s %.3f notch%s result fits safe bounds" % [physical, scale_value, notched])
					for name: String in ["PlayAgainButton", "MainMenuButton", "ReportButton"]:
						var button: Button = screen.get_node("GameOverPanel/Margin/VBox/ButtonRow/" + name)
						_expect(button.size.x >= 48.0 and button.size.y >= 48.0, "Result action preserves 48 logical px")
					paused = false
				# Exercise the actual online visibility branch on each phone profile.
				session.online = true
				screen.show_defeat(examples[0])
				screen.call("_fit_panel_to_size", logical, safe)
				await process_frame
				await process_frame
				var online_label: Label = screen.get("_debrief_label")
				_expect(online_label.visible and "Outriders landed final blows" in online_label.text, "Online phone result displays the recipient's authority lesson")
				_expect(online_label.get_line_count() <= 3, "Online authority lesson fits three phone lines")
				var online_rect: Rect2 = panel.get_global_rect()
				_expect(online_rect.position.x >= safe.position.x - 0.5 and online_rect.position.y >= safe.position.y - 0.5 and online_rect.end.x <= safe.end.x + 0.5 and online_rect.end.y <= safe.end.y + 0.5, "Online result with lesson fits safe bounds")
				_expect(not screen.score_bar.visible and not screen.panel.get_node("Margin/VBox/StatsHeader/Right").visible, "Online lesson never exposes opponent comparisons")
				for name: String in ["PlayAgainButton", "MainMenuButton", "ReportButton"]:
					var online_button: Button = screen.get_node("GameOverPanel/Margin/VBox/ButtonRow/" + name)
					_expect(online_button.size.x >= 48.0 and online_button.size.y >= 48.0, "Online result preserves 48 logical px actions")
				screen.show_defeat({"learning": {"paid_army": 0}})
				_expect(not online_label.visible, "No trusted online battle receipt means no invented local lesson")
				session.online = false
				paused = false
				records.append({"physical": str(physical), "scale": scale_value, "notched": notched, "panel": str(panel.get_global_rect()), "max_lines": max_lines})
				viewport.free()
				await process_frame
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var output := FileAccess.open(folder.path_join("debrief-phone.json"), FileAccess.WRITE)
		output.store_string(JSON.stringify({"scope": "Synthetic telemetry decision fixtures and headless Control/font measurements, no human/device claim", "profiles": records, "failures": failures}, "\t"))
	if failures.is_empty():
		print("[PASS] match_debrief: receipt-based suggestions, no invented empty telemetry, standard and banked explanations across 12 phone profiles")
		quit(0)
	else:
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[FAIL] match_debrief: " + message)
