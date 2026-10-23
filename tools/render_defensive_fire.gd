extends Node
## Native attachment diagnostic: real Main, TC, Warrior and DefensiveArrow.
## Free positioned target, revealed terrain and manually stepped ordinary weapon.
## Captures paused instants; no paid play, frame-time or physical-device claim.

var output: String = "res://output/polish-world-proportions-2026-10-22/defense-native"
var width: int = 844
var height: int = 390
var main: Node2D
var game_map: Node2D
var tc: BuildingBase
var target: UnitBase
var caption: Label
var shots: int = 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var source_hashes: Dictionary = {}
var original_preferences: Dictionary = {}
var _before_image: Image = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--width="): width = int(argument.trim_prefix("--width="))
		elif argument.begins_with("--height="): height = int(argument.trim_prefix("--height="))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for source: String in ["scripts/buildings/building_base.gd", "scripts/data/building_data.gd", "scripts/units/unit_base.gd", "scripts/units/combat.gd", "scripts/data/unit_data.gd", "scripts/main/main.gd", "scripts/map/game_map.gd", "scripts/map/map_generator.gd", "assets/buildings/company_town_center.svg", "assets/buildings/company_town_center.svg.import", "assets/units/warrior_enemy.svg", "tools/render_defensive_fire.gd", "tools/fixtures/polish_revealed_fog.gd"]:
		source_hashes[source] = FileAccess.get_sha256("res://" + source)
	for property: String in ["selected_map_seed", "selected_map_archetype", "selected_population_limit", "selected_difficulty", "guided_opening_enabled", "ui_scale", "reduced_flashes", "reduced_motion", "clearer_player_markers"]:
		original_preferences[property] = GameManager.get(property)
	AudioManager.set_all_enabled(false)
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_population_limit = 30
	GameManager.selected_difficulty = AIController.Difficulty.EASY
	GameManager.guided_opening_enabled = false
	GameManager.ui_scale = 1.0
	GameManager.reduced_flashes = false
	GameManager.reduced_motion = false
	GameManager.clearer_player_markers = false
	get_window().size = Vector2i(width, height)
	get_window().content_scale_size = Vector2i(width, height)
	get_window().content_scale_factor = 1.0
	main = load("res://scenes/main/main.tscn").instantiate() as Node2D
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	_check(main.get("_building_placement") != null, "actual Main initialized")
	if main.get("_building_placement") == null:
		_finish()
		return
	game_map = main.get("game_map") as Node2D
	# Disable inherited simulation; each weapon step below calls runtime methods
	# exactly once. Rendering still updates, so capture never stretches a shot.
	main.process_mode = Node.PROCESS_MODE_DISABLED
	GameManager.set_process(false)
	var fog: FogManager = game_map.get_node("FogOfWar") as FogManager
	fog.set_script(load("res://tools/fixtures/polish_revealed_fog.gd"))
	fog.fog_layer = game_map.get_node("FogLayer") as TileMapLayer
	fog.refresh_visibility_now()
	game_map.get_node("FogLayer").hide()
	(main.get("hud") as CanvasLayer).hide()
	(main.get("_battlefield_feedback") as CanvasItem).hide()
	(game_map.get("sacred_site") as CanvasItem).hide()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		(unit as CanvasItem).hide()
	tc = main.get("_player_town_center") as BuildingBase
	tc.is_selected = false
	target = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 1, tc.global_position + Vector2(-90, -18)) as UnitBase
	target.stance = UnitBase.Stance.STAND_GROUND
	target.is_selected = true
	target.show()
	target._sprite.show()
	_check(game_map.call("is_tile_walkable", game_map.call("world_to_tile", target.global_position)), "synthetic target stands on legal open terrain")
	_check(tc.visible and target.visible and not game_map.get_node("FogLayer").visible, "diagnostic actors and terrain are visible")
	tc.defensive_attack_fired.connect(func(_enemy: Node2D) -> void: shots += 1)
	var camera: Camera2D = game_map.get("camera") as Camera2D
	camera.position = tc.global_position + Vector2(-25, 0)
	camera.zoom = Vector2.ONE * 1.35
	camera.reset_smoothing()
	camera.force_update_scroll()
	var overlay := CanvasLayer.new()
	overlay.layer = 120
	add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(18, 12)
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	overlay.add_child(caption)
	tc.queue_redraw()
	target.queue_redraw()
	await _capture("01-before", null, "Before release · normal TC / Warrior stats")
	tc._process(0.001)
	var arrows: Array[Node] = get_tree().get_nodes_in_group("defensive_projectiles")
	_check(arrows.size() == 1 and shots == 1, "normal TC process releases exactly one actual arrow")
	if arrows.size() != 1:
		_finish()
		return
	var arrow: BuildingBase.DefensiveArrow = arrows[0] as BuildingBase.DefensiveArrow
	var expected_origin: Vector2 = tc._sprite.to_global(tc._sprite.get_rect().position + Vector2(101, 72) * (tc._sprite.texture.get_size() / Vector2(128, 128)))
	_check(arrow.start_position.distance_to(expected_origin) < 0.001, "release attaches to the actual source window")
	_check(is_equal_approx(arrow.final_damage, 4.0) and is_equal_approx(target.hp, 60.0), "release preserves base armor and causes no instant damage")
	await _capture("02-release", arrow, "Released · source window flash and actual arrow")
	var half_flight: float = arrow.flight_seconds * 0.5
	tc._process(half_flight)
	arrow.advance_projectile(half_flight)
	_check(is_equal_approx(arrow.elapsed / arrow.flight_seconds, 0.5), "capture is at the exact ordinary flight midpoint")
	_check(tc._defensive_shot_flash_remaining > 0.0 and arrow.visible, "mid-flight includes the still-active ordinary flash")
	_check(is_equal_approx(target.hp, 60.0), "mid-flight target has not been hit early")
	await _capture("03-mid-flight", arrow, "50% flight · actual arrow + remaining flash · HP60")
	tc._process(half_flight + 0.001)
	arrow.advance_projectile(half_flight + 0.001)
	_check(arrow.finished and is_equal_approx(target.hp, 56.0) and shots == 1, "ordinary impact applies4 damage once, before the next2-second release")
	await _capture("04-impact", null, "Impact · Warrior HP56 · same damage and timing")
	_finish()


func _capture(file_name: String, arrow: BuildingBase.DefensiveArrow, label: String) -> void:
	caption.text = "DEFENSIVE FIRE DIAGNOSTIC · paused sample\n" + label
	for frame: int in 4:
		await get_tree().process_frame
	var record: Dictionary = {"name": file_name, "native_rendered": DisplayServer.get_name() != "headless", "target_hp": target.hp, "shots": shots, "flash_remaining": tc._defensive_shot_flash_remaining, "fire_world": str(tc.call("_get_defensive_fire_position")), "fire_screen": str(get_viewport().get_canvas_transform() * (tc.call("_get_defensive_fire_position") as Vector2)), "target_world": str(target.global_position)}
	if arrow != null:
		record.merge({"arrow_world": str(arrow.global_position), "arrow_screen": str(arrow.get_global_transform_with_canvas().origin), "flight_seconds": arrow.flight_seconds, "elapsed": arrow.elapsed, "damage": arrow.final_damage})
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path: String = output.path_join(file_name + ".png")
		var captured: Image = get_viewport().get_texture().get_image()
		if file_name == "01-before":
			_before_image = captured
		elif file_name == "03-mid-flight" and _before_image != null:
			# The arrow is already away from the window at this paused instant.
			# Compare the actual window pixels, rather than trusting the timer.
			var screen: Vector2 = tc.get_global_transform_with_canvas() * tc.to_local(tc.call("_get_defensive_fire_position"))
			var patch := Rect2i(Vector2i(screen) - Vector2i(8, 8), Vector2i(17, 17)).intersection(Rect2i(0, 0, captured.get_width(), captured.get_height()))
			var changed: int = 0
			for y: int in range(patch.position.y, patch.end.y):
				for x: int in range(patch.position.x, patch.end.x):
					changed += int(captured.get_pixel(x, y) != _before_image.get_pixel(x, y))
			record["window_flash_changed_pixels"] = changed
			_check(changed >= 12, "window flash is visibly drawn above the opaque building artwork")
		var error: Error = captured.save_png(path)
		_check(error == OK, "native capture saves " + file_name)
		record["path"] = path
		record["pixel_size"] = [captured.get_width(), captured.get_height()]
	records.append(record)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)


func _finish() -> void:
	var unchanged: bool = true
	for source: String in source_hashes:
		unchanged = unchanged and FileAccess.get_sha256("res://" + source) == str(source_hashes[source])
	_check(unchanged, "source inputs stay unchanged through capture")
	FileAccess.open(output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Actual Main/GameMap/TC/Warrior/DefensiveArrow. Free positioned passive target, revealed fog, background frozen; ordinary weapon manually stepped and paused at exact instants. HUD hidden for art inspection. No paid-match, live cadence, performance, physical-device or socket claim.", "display": DisplayServer.get_name(), "engine": Engine.get_version_info(), "source_sha256": source_hashes, "source_unchanged": unchanged, "captures": records, "failures": failures}, "  "))
	for property: String in original_preferences:
		GameManager.set(property, original_preferences[property])
	for failure: String in failures:
		push_error("[FAIL] defensive_fire_capture: " + failure)
	if failures.is_empty():
		print("[PASS] defensive_fire_capture: actual release, half-flight with flash, impact; native captures when rendered")
	get_tree().quit(0 if failures.is_empty() else 1)
