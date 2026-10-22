extends Node
## Rendered annotation regression. Controlled positions/vision isolate occlusion;
## the separate paid Scout match checks ordinary movement and combat.

var failures: Array[String] = []
var profiles: Array[Dictionary] = []
var output_dir: String


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	output_dir = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if output_dir.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Rendered annotation fixture requires AOEM_CAPTURE_UX_DIR and a native renderer")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for interface_scale: float in [1.0, 1.15]:
			await _profile(phone, interface_scale)
	FileAccess.open(output_dir.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "Four native phone profiles; controlled unit positions and live FogManager refresh, no paid-match or physical-phone claim. Pixel comparisons against the same scene with only the annotation hidden.", "profiles": profiles, "failures": failures}, "  "))
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("[PASS] sacred_annotation_visibility: unseen/explored badge, visible unit pixels, persistent ring, public status and input transparency")
	get_tree().quit(0 if failures.is_empty() else 1)


func _profile(phone: Vector2i, interface_scale: float) -> void:
	var name_tag: String = "%dx%d-scale%.2f" % [phone.x, phone.y, interface_scale]
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	GameManager.ui_scale = interface_scale
	get_window().content_scale_factor = interface_scale
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = 1
	GameManager.guided_opening_enabled = false
	var main: Node2D = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	main.set_process(false)
	main.get("ai_controller").set_process(false)
	main.get("ai_controller").get("_decision_timer").stop()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var map: Node2D = main.get("game_map")
	var site: Node2D = map.get("sacred_site")
	var feedback: Control = main.get("_battlefield_feedback")
	var worker: UnitBase = main.get("_player_units")[0][0]
	var home: Vector2 = worker.global_position
	site.set_process(false)
	map.call("note_camera_interaction")
	await _frames(4)
	var middle: Vector2 = get_viewport().get_visible_rect().size * 0.5
	map.call("_set_zoom_anchored", 0.65, middle, middle, true)
	var camera: Camera2D = map.get("camera")
	camera.position = site.global_position
	camera.reset_smoothing()
	camera.force_update_scroll()
	# Freeze only this visual observer while comparing annotated/reference frames;
	# its normal _process deliberately restores visibility during live play.
	feedback.set_process(false)
	for phase: String in ["unseen", "visible", "owned-explored", "visible-again"]:
		var visible_ground: bool = phase in ["visible", "visible-again"]
		worker.global_position = site.global_position if visible_ground else home
		if phase == "owned-explored":
			site.set("owning_player", 0)
			site.set("state", 2)
		main.call("_update_fog_of_war")
		main.call("_update_fog_entity_visibility")
		var tile: Vector2i = map.call("world_to_tile", site.global_position)
		_expect(bool(map.call("is_tile_visible_to_player", tile, 0)) == visible_ground, name_tag + " " + phase + " vision setup")
		if phase == "owned-explored":
			_expect(bool(map.get("fog_of_war").call("is_explored", tile)), name_tag + " explored memory missing")
		feedback.visible = true
		feedback.queue_redraw()
		await _frames(3)
		await RenderingServer.frame_post_draw
		var annotated: Image = get_viewport().get_texture().get_image()
		var center: Vector2 = site.get_global_transform_with_canvas().origin
		var ratio: float = float(annotated.get_width()) / get_viewport().get_visible_rect().size.x
		feedback.visible = false
		await _frames(2)
		await RenderingServer.frame_post_draw
		var reference: Image = get_viewport().get_texture().get_image()
		_expect(not feedback.is_visible_in_tree(), name_tag + " reference still contains annotation")
		var core: Rect2 = Rect2(center - Vector2(24, 24), Vector2(48, 48))
		var caption: Rect2 = Rect2(center + Vector2(-90, 27), Vector2(180, 30))
		var core_pixels: int = _changed_pixels(annotated, reference, core, ratio)
		var caption_pixels: int = _changed_pixels(annotated, reference, caption, ratio)
		var radius: float = float(site.call("get_capture_radius_world")) * camera.zoom.x
		var ring_pixels: int = _changed_pixels(annotated, reference, Rect2(center + Vector2(-radius - 3, -8), Vector2(6, 16)), ratio)
		_expect(core_pixels <= 4 if visible_ground else core_pixels > 100, name_tag + " " + phase + " opaque badge pixels=" + str(core_pixels))
		_expect(caption_pixels <= 4 if visible_ground else caption_pixels > 100, name_tag + " " + phase + " caption pixels=" + str(caption_pixels))
		_expect(ring_pixels > 10, name_tag + " " + phase + " public ring missing")
		_expect(feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE, name_tag + " annotation intercepts touch")
		var hud: CanvasLayer = main.get("hud")
		_expect((hud.get("_sacred_site_panel") as Control).is_visible_in_tree(), name_tag + " public status missing")
		annotated.save_png(output_dir.path_join(name_tag + "-" + phase + ".png"))
		profiles.append({"profile": name_tag, "phase": phase, "current_visibility": visible_ground, "center_pixels_changed": core_pixels, "caption_pixels_changed": caption_pixels, "ring_pixels_changed": ring_pixels, "zoom": camera.zoom.x})
		feedback.visible = true
	main.free()
	await _frames(3)


func _changed_pixels(a: Image, b: Image, rectangle: Rect2, ratio: float) -> int:
	var pixels := Rect2i(rectangle.position * ratio, rectangle.size * ratio)
	pixels = pixels.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var changed: int = 0
	for y: int in range(pixels.position.y, pixels.end.y):
		for x: int in range(pixels.position.x, pixels.end.x):
			if a.get_pixel(x, y).to_rgba32() != b.get_pixel(x, y).to_rgba32():
				changed += 1
	return changed


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
