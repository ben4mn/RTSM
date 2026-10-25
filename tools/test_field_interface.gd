extends Node
## Presentation regression: progress belongs only to active training; tap Guide
## must remain inspectable while the solo match is paused.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	for civilization: int in [0, 1, 2]:
		GameManager.selected_civilization = civilization
		GameManager.initialize_game(1)
		ResourceManager.initialize_player(0, {"food": 1000, "wood": 1000, "gold": 1000})
		var view := SubViewport.new()
		view.size = Vector2i(844, 390)
		add_child(view)
		var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
		view.add_child(hud)
		var tc := BuildingBase.new()
		tc.building_type = BuildingData.BuildingType.TOWN_CENTER
		tc.player_owner = 0
		tc.state = BuildingBase.State.ACTIVE
		view.add_child(tc)
		tc.add_child(ProductionQueue.new())
		var queue: Array = [{"unit_type": 0, "name": "Villager", "is_training": true, "progress": 0.35}, {"unit_type": 4, "name": "Scout", "is_training": false}]
		hud.call("show_building_selection", "Town Center", 5000, 5000, queue, [0, 4], tc)
		await _settle()
		var row: HBoxContainer = hud.get("_train_buttons_container")
		var active: ProgressBar = row.get_node("TrainButton_0/ProductionSeam")
		var waiting: ProgressBar = row.get_node("TrainButton_4/ProductionSeam")
		_expect(active.visible and is_equal_approx(active.value, 0.35), "active training has exact snapshot progress")
		_expect(not waiting.visible, "waiting unit has no invented progress")
		_expect(active.mouse_filter == Control.MOUSE_FILTER_IGNORE, "meter cannot steal recruitment touches")
		_expect((row.get_node("TrainButton_0") as Button).get_global_rect().encloses(active.get_global_rect()), "progress remains inside recruitment card")
		hud.call("show_building_selection", "Town Center", 5000, 5000, [], [0, 4], tc)
		_expect(not active.visible, "completion clears progress without replacing button")
		hud.call("set_pause_display", true)
		await _settle()
		var guide: Button = (hud.get("_pause_overlay") as Control).find_child("FieldGuideButton", true, false)
		_expect(guide != null and guide.size.x >= 48 and guide.size.y >= 48, "tap guide has a comfortable target")
		guide.pressed.emit()
		await _settle()
		_expect(hud.call("get_secondary_surface_name") == "help", "Guide opens from match menu without resuming")
		_expect(int(hud.get("_ui_modal_state")) == 2, "Guide preserves pause modal")
		var help: Control = hud.get("_hotkey_panel")
		_expect(help.visible and help.z_index > (hud.get("_pause_overlay") as Control).z_index, "Guide draws above pause overlay")
		hud.call("close_secondary_surface")
		_expect(int(hud.get("_ui_modal_state")) == 2, "closing Guide returns to paused menu")
		view.free()
		await _settle()
	for failure: String in _failures:
		push_error("[FAIL] field_interface: " + failure)
	if _failures.is_empty():
		print("[PASS] field_interface: all three civilizations; authoritative active/waiting/finished progress, touch transparency, paused tap Guide lifecycle")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _settle() -> void:
	for frame: int in 4:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
