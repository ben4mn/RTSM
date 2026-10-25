extends Node
## Bounded native rendering fixture on the real seeded map and gameplay HUD.
## Actors/poses are staged and simulation is frozen: this is visual evidence,
## not a paid-play, balance, input-journey or physical-device performance test.

const SIZES: Array[Vector2i] = [Vector2i(844, 390), Vector2i(932, 430)]
const SCENES: Array[String] = ["villager", "infantry", "archer", "cavalry", "scout", "siege"]
var _output: String = "res://output/illustrated-civilizations"
var _captures: Array[Dictionary] = []
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	if DisplayServer.get_name() == "headless":
		push_error("This fixture requires native rendering; headless images are not evidence.")
		get_tree().quit(1)
		return
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.ui_scale = 1.0
	GameManager.reduced_motion = false
	GameManager.reduced_flashes = true
	for size: Vector2i in SIZES:
		for civilization: int in 3:
			await _capture_civilization(size, civilization)
	var receipt := {
		"passed": _failures.is_empty(), "failures": _failures, "captures": _captures,
		"scope": "Real main scene, map, unit/building resources, HUD and construction preview; staged actors and poses with simulation frozen. No paid gameplay, balance, physical-phone or performance claim.",
		"capture_sha256": FileAccess.get_sha256("res://tools/capture_illustrated_civilizations.gd"),
		"atlas_manifest_sha256": FileAccess.get_sha256("res://assets/kingdoms/atlas_manifest.json"),
	}
	FileAccess.open(_output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify(receipt, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] illustrated_civilizations: " + failure)
	if _failures.is_empty():
		print("[PASS] illustrated_civilizations: %d exact-phone-size native captures on actual terrain" % _captures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _capture_civilization(size: Vector2i, civilization: int) -> void:
	get_window().size = size
	get_window().content_scale_size = size
	get_window().content_scale_factor = 1.0
	GameManager.set_state(GameManager.GameState.MENU)
	GameManager.selected_civilization = civilization
	GameManager.selected_opponent_civilization = (civilization + 1) % 3
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	if main.get("_building_placement") == null:
		_failures.append("Main did not initialize for civilization %d" % civilization)
		main.free()
		return
	main.process_mode = Node.PROCESS_MODE_DISABLED
	GameManager.set_process(false)
	var map: Node2D = main.get("game_map")
	map.fog_of_war.reveal_all()
	map.get_node("FogLayer").clear()
	map.update_resource_visibility_for_player(0)
	var town: BuildingBase = main.get("_player_town_center")
	var origin: Vector2 = town.global_position
	for existing: Node in map.get_node("UnitsContainer").get_children():
		if existing is CanvasItem:
			existing.hide()
	var farm := BuildingBase.new()
	farm.building_type = BuildingData.BuildingType.FARM
	farm.player_owner = 0
	farm.state = BuildingBase.State.ACTIVE
	farm.position = origin + Vector2(255, -30)
	map.get_node("BuildingsContainer").add_child(farm)
	farm.set_process(false)
	var units: Array[UnitBase] = []
	for kind: int in SCENES.size():
		var unit: UnitBase = load("res://scenes/units/%s.tscn" % SCENES[kind]).instantiate()
		unit.player_owner = 0
		unit.position = origin + Vector2(20 + kind * 64, 102)
		map.get_node("UnitsContainer").add_child(unit)
		unit.set_process(false)
		unit._last_visual_position = unit.global_position
		units.append(unit)
	var farmer: UnitBase = load("res://scenes/units/villager.tscn").instantiate()
	farmer.player_owner = 0
	farmer.position = farm.position + farm._footprint_center + Vector2(18, 6)
	map.get_node("UnitsContainer").add_child(farmer)
	farmer.set_process(false)
	farmer._last_visual_position = farmer.global_position
	map.note_camera_interaction()
	map.set("_user_zoom_override", true)
	map.set("_zoom_transition_active", false)
	map.camera.zoom = Vector2.ONE * 0.952
	map.camera.position = origin + Vector2(145, 0)
	map.camera.reset_smoothing()
	map.camera.force_update_scroll()
	map.selection_mgr.deselect_all()
	for phase: float in [0.18, 0.7]:
		units[0].current_state = UnitBase.State.GATHERING
		units[0].apply_work_presentation([UnitActionPresentation.Action.CHOP, phase, 0.8])
		farmer.current_state = UnitBase.State.GATHERING
		farmer.apply_work_presentation([UnitActionPresentation.Action.FARM, phase, 0.8])
		for kind: int in range(1, units.size()):
			var unit: UnitBase = units[kind]
			unit.current_state = UnitBase.State.ATTACKING
			var windup: float = float(UnitData.UNITS[kind].get("attack_windup", 0.12))
			unit._attack_animation_duration = windup + 0.16
			unit._attack_animation_remaining = unit._attack_animation_duration - windup * phase / 0.7
			unit._update_sprite_motion(0.0)
		await _capture(size, civilization, "field-lift" if phase < 0.5 else "field-contact", map)
	map.selection_mgr.select_single(town)
	await _capture(size, civilization, "recruitment", map)
	map.selection_mgr.deselect_all()
	main.call("_on_building_selected_for_placement", BuildingData.BuildingType.HOUSE)
	var placement: Node = main.get("_building_placement")
	placement.call("update_preview_at_world", origin + Vector2(365, 15))
	await _capture(size, civilization, "construction-preview", map)
	main.call("_on_cancel_placement")
	if size == SIZES[0]:
		main.get("hud").call("_on_build_menu_pressed")
		await _capture(size, civilization, "building-cards", map)
	main.free()
	GameManager.set_state(GameManager.GameState.MENU)
	await get_tree().process_frame


func _capture(size: Vector2i, civilization: int, view: String, map: Node2D) -> void:
	for frame: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var filename: String = "civilization-%d-%dx%d-%s.png" % [civilization, size.x, size.y, view]
	if screenshot.get_size() != size:
		_failures.append("Unexpected viewport dimensions for " + filename)
	if screenshot.save_png(_output.path_join(filename)) != OK:
		_failures.append("Could not save " + filename)
	_captures.append({"file": filename, "civilization": CivilizationData.get_civilization_name(civilization),
		"size": [screenshot.get_width(), screenshot.get_height()], "view": view, "zoom": map.camera.zoom.x,
		"sha256": FileAccess.get_sha256(_output.path_join(filename))})
