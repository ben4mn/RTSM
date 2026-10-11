extends Node
## Native pixels of real Main/HUD plus controlled lesson/result fixtures.
## Injected troops/instructions/summary describe presentation only, not match play.

const OUTPUT: String = "res://output/evolution/learning-20261010-battle-lessons/rendered"
var records: Array[Dictionary] = []
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("render_match_learning requires native rendering; omit --headless")
		get_tree().quit(1)
		return
	AudioManager.set_all_enabled(false)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var previous_scale: float = GameManager.ui_scale
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for large_notched: bool in [false, true]:
			await _profile(phone, large_notched)
	GameManager.ui_scale = previous_scale
	var source: Dictionary = {}
	for path: String in ["res://scripts/main/main.gd", "res://scripts/main/match_learning.gd", "res://scripts/main/match_debrief.gd", "res://scripts/ui/hud.gd", "res://scripts/ui/game_over_screen.gd"]:
		source[path] = FileAccess.get_file_as_string(path).sha256_text()
	FileAccess.open(OUTPUT + "/manifest.json", FileAccess.WRITE).store_string(JSON.stringify({"scope": "Native rendered exact phone pixel captures; real seeded Main map/HUD; injected Warrior and selected long lesson text, synthetic debrief counts. UI scales1/1.15 and44px side/18px bottom synthetic safe insets. No match balance/input/physical-device claim", "source_sha256": source, "captures": records, "failures": failures}, "\t"))
	print("[PASS] render_match_learning: %d source-bound native captures" % records.size() if failures.is_empty() else "[FAIL] render_match_learning")
	get_tree().quit(0 if failures.is_empty() else 1)


func _profile(phone: Vector2i, large_notched: bool) -> void:
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	GameManager.ui_scale = 1.15 if large_notched else 1.0
	get_window().content_scale_factor = GameManager.ui_scale
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 42
	GameManager.selected_population_limit = 30
	await _frames(2)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for _frame in range(900):
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	await _frames(3)
	main.set_process(false)
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	var map: Node = main.get_node("GameMap")
	map.set_process(false)
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var hud: CanvasLayer = main.get_node("HUD")
	var worker: UnitBase = main.get("_player_units")[0][0]
	var warrior: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, worker.global_position)
	warrior.set_process(false)
	map.selection_mgr.select_single(warrior)
	main.call("_start_match_learning")
	main.call("_apply_primary_guidance", "Counters · Add Archers at an Archery Range. Archers beat Warriors; Warriors beat Horsemen.", "", UnitData.UnitType.ARCHER, BuildingData.BuildingType.ARCHERY_RANGE, false)
	for toast: Node in hud.get("_notification_container").get_children():
		hud.call("_retire_dynamic_control", toast)
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var inset: Vector2 = Vector2(44.0 * logical.x / phone.x, 18.0 * logical.y / phone.y) if large_notched else Vector2.ZERO
	var safe := Rect2(Vector2(inset.x, 0), logical - Vector2(inset.x * 2, inset.y))
	hud.apply_mobile_layout(logical, safe)
	await _frames(2)
	var profile: String = "%dx%d-%s" % [phone.x, phone.y, "large-notched" if large_notched else "normal"]
	await _capture(profile + "-lessons", phone, {"logical": str(logical), "safe": str(safe), "banner": str(hud.get("_progression_hint_panel").get_global_rect()), "label_lines": hud.get("_progression_hint_label").get_line_count()})
	hud.set_match_learning_active(false)
	hud.set_progression_hint("")
	var screen: CanvasLayer = load("res://scenes/ui/game_over_screen.tscn").instantiate()
	add_child(screen)
	await _frames(1)
	screen.show_defeat({"victory_reason": "Sacred Site held for 10:00", "game_time": "13:35", "player_age": 2, "ai_age": 3, "player_feudal_seconds": 245.0, "ai_feudal_seconds": 318.0, "score": 320, "ai_score": 480, "army_trained": 4, "ai_army_trained": 12, "units_lost": 5, "ai_units_lost": 2, "buildings_lost": 1, "ai_buildings_lost": 0, "resources_gathered": 1400, "ai_resources_gathered": 2700, "sacred_control_seconds": 0, "ai_sacred_control_seconds": 600, "learning": {"paid_army": 3, "army_losses": 2, "army_replacements": 1, "counter_demonstrated": false}})
	screen.call("_fit_panel_to_size", logical, safe)
	await _frames(30)
	await _capture(profile + "-debrief", phone, {"logical": str(logical), "safe": str(safe), "panel": str(screen.panel.get_global_rect()), "debrief_lines": screen.get("_debrief_label").get_line_count(), "debrief": screen.get("_debrief_label").text})
	get_tree().paused = false
	screen.free()
	main.free()
	await _frames(2)


func _capture(name: String, phone: Vector2i, details: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var bitmap: Image = get_viewport().get_texture().get_image()
	if bitmap.get_size() != phone:
		failures.append("%s native pixels %s != %s" % [name, bitmap.get_size(), phone])
	var path: String = OUTPUT + "/" + name + ".png"
	bitmap.save_png(path)
	details["name"] = name
	details["path"] = path
	details["pixels"] = str(bitmap.get_size())
	records.append(details)


func _frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame
