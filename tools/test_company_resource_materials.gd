extends Node
## Authored resource art, visible-alpha picking, grounding, and fog/depletion contracts.
const OUTPUT := "res://output/company-resources-2026-10-22"
const KINDS: Array[String] = ["wood", "food", "gold", "stone"]
var _failures: Array[String] = []
var _metrics: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for kind: String in KINDS:
		await _contracts(kind, 0)
	for variant: int in range(1, ResourceNode.WOOD_SPRITES.size()):
		await _contracts("wood", variant)
	_expect(_metrics.size() == KINDS.size() + ResourceNode.WOOD_SPRITES.size() - 1, "All resource kinds and tree variants must complete")
	if DisplayServer.get_name() != "headless":
		await _material_sheet()
		await _phone_captures()
	var report := {"passed": _failures.is_empty(), "failures": _failures, "metrics": _metrics, "resource_node_sha256": FileAccess.get_sha256("res://scripts/map/resource_node.gd"), "user_data": OS.get_user_data_dir()}
	var file := FileAccess.open(OUTPUT.path_join("material-contracts.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] company_resource_materials: " + failure)
	if _failures.is_empty():
		print("[PASS] company_resource_materials: four resources and three tree silhouettes, stock/collision, actual opaque picking, calibrated anchors, baked shadows without extra nodes; GPU inherited fade and native phone captures when rendered")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _contracts(kind: String, variant: int) -> void:
	var resource := ResourceNode.new()
	resource.resource_type = kind
	resource.tile_position = Vector2i(variant, 0)
	resource.total_amount = 300
	add_child(resource)
	resource.visible = false
	var sprite: Sprite2D = resource.get_node("Sprite")
	_expect(sprite.texture.resource_path == resource.get_presentation_texture_path(), kind + " uses its deterministic authored texture")
	_expect(sprite.scale == ResourceNode.RESOURCE_SCALES[kind] and sprite.offset == ResourceNode.RESOURCE_OFFSETS[kind], kind + " uses calibrated scale and anchor")
	_expect(resource.remaining == 300, kind + " preserves initial stock")
	var collision := resource.get_child(0) as CollisionShape2D
	_expect(collision != null and is_equal_approx((collision.shape as CircleShape2D).radius, 16.0), kind + " preserves collision circle")
	var second := ResourceNode.new()
	second.resource_type = kind
	second.tile_position = resource.tile_position
	add_child(second)
	second.visible = false
	_expect((second.get_node("Sprite") as Sprite2D).texture == sprite.texture, kind + " shares its authored texture")
	_expect(resource.get_child_count() == 2, kind + " retains collision plus one sprite with baked contact shade")
	_expect(sprite.material == null, kind + " needs no per-resource material/shader")
	var art_bounds: Rect2 = Rect2(sprite.texture.get_image().get_used_rect())
	var base_y: float = (art_bounds.end.y - sprite.texture.get_height() * 0.5 + sprite.offset.y) * sprite.scale.y
	_expect(base_y >= 0.0 and base_y <= 6.0, kind + " visible base stays on its ground tile")
	_expect(art_bounds.size.x * sprite.scale.x < 55.0 and art_bounds.size.y * sprite.scale.y < 76.0, kind + " canopy/deposit keeps a compact readable world envelope")
	second.free()
	var original_sprite := Sprite2D.new()
	original_sprite.texture = sprite.texture
	original_sprite.offset = sprite.offset
	var mask_differences := 0
	for y: int in 128:
		for x: int in 128:
			var local: Vector2 = sprite.get_rect().position + Vector2(x, y) + Vector2.ONE * 0.5
			var expected: bool = kind == "wood" and original_sprite.is_pixel_opaque(local)
			mask_differences += int(resource.is_sprite_body_hit(sprite.to_global(local)) != expected)
	original_sprite.free()
	_expect(mask_differences == 0, kind + " picks exactly the visible authored canopy, not transparent padding")
	var metric := {"kind": kind, "variant": variant, "base_y": base_y, "mask_differences": mask_differences, "source_texture_sha256": FileAccess.get_sha256(sprite.texture.resource_path)}
	if DisplayServer.get_name() != "headless":
		var viewport := SubViewport.new()
		viewport.size = Vector2i(160, 160)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var tint := Node2D.new()
		viewport.add_child(tint)
		var painted := Sprite2D.new()
		painted.texture = sprite.texture
		painted.position = Vector2(80, 80)
		tint.add_child(painted)
		await _frames(3)
		await RenderingServer.frame_post_draw
		var original: Image = viewport.get_texture().get_image()
		painted.material = sprite.material
		await _frames(3)
		await RenderingServer.frame_post_draw
		var mapped: Image = viewport.get_texture().get_image()
		var alpha_differences := 0
		var color_differences := 0
		for y: int in 160:
			for x: int in 160:
				var before: Color = original.get_pixel(x, y)
				var after: Color = mapped.get_pixel(x, y)
				alpha_differences += int(not is_equal_approx(before.a, after.a))
				color_differences += int(before.a > 0.9 and before != after)
		_expect(alpha_differences == 0, kind + " GPU authored art preserves every alpha pixel")
		_expect(color_differences == 0, kind + " displays authored material colors directly")
		tint.modulate = Color(0.5, 0.5, 0.5, 0.5)
		await _frames(3)
		await RenderingServer.frame_post_draw
		var faded: Image = viewport.get_texture().get_image()
		var fade_failures := 0
		for y: int in 160:
			for x: int in 160:
				var before: Color = mapped.get_pixel(x, y)
				var after: Color = faded.get_pixel(x, y)
				fade_failures += int(absf(after.a - before.a * 0.5) > 1.1 / 255.0)
				if before.a > 0.9:
					fade_failures += int(after.r > before.r or after.g > before.g or after.b > before.b)
		_expect(fade_failures == 0, kind + " preserves inherited fog tint and half-alpha fade")
		metric.merge({"gpu_alpha_differences": alpha_differences, "changed_opaque_colors": color_differences, "fade_failures": fade_failures})
		viewport.free()
	var signal_count := [0]
	resource.depleted.connect(func(_node: ResourceNode) -> void: signal_count[0] += 1)
	_expect(resource.harvest(299) == 299 and resource.remaining == 1, kind + " preserves exact harvest arithmetic")
	_expect(resource.harvest(5) == 1 and resource.remaining == 0 and not resource.is_harvestable_by(0), kind + " caps final extraction at actual stock")
	_expect(resource.harvest(1) == 0 and signal_count[0] == 1, kind + " emits depletion once and refuses repeated harvest")
	await get_tree().create_timer(0.65).timeout
	_expect(not is_instance_valid(resource), kind + " finishes its depletion fade and removal")
	_metrics.append(metric)

func _material_sheet() -> void:
	get_window().size = Vector2i(932, 430)
	get_window().content_scale_size = Vector2i(932, 430)
	get_window().content_scale_factor = 1.0
	var sheet := Node2D.new()
	add_child(sheet)
	var background := ColorRect.new()
	background.color = Color("293b3a")
	background.size = Vector2(932, 430)
	sheet.add_child(background)
	_label(sheet, "COMPANY RESOURCES", Vector2(28, 18), 27)
	_label(sheet, "Original faceted crowns · clustered fruit · gold veins · cut stone", Vector2(28, 57), 17)
	for index: int in KINDS.size():
		var resource := ResourceNode.new()
		resource.resource_type = KINDS[index]
		resource.position = Vector2(130 + index * 225, 270)
		resource.scale = Vector2.ONE * 3.0
		sheet.add_child(resource)
		_label(sheet, KINDS[index].to_upper(), Vector2(87 + index * 225, 315), 21)
	_label(sheet, "ENLARGED MATERIAL FIXTURE · real phone scale is shown in the native map captures", Vector2(28, 388), 15)
	await _capture("material-sheet.png")
	sheet.free()

func _phone_captures() -> void:
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.guided_opening_enabled = false
	GameManager.ui_scale = 1.0
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		get_window().size = phone
		get_window().content_scale_size = Vector2i(844, 390)
		get_window().content_scale_factor = 1.0
		GameManager.set_state(GameManager.GameState.MENU)
		var main: Node = load("res://scenes/main/main.tscn").instantiate()
		add_child(main)
		for frame: int in 900:
			if main.get("_building_placement") != null:
				break
			await get_tree().process_frame
		var map: Node2D = main.get("game_map")
		var tc: BuildingBase = main.get("_player_town_center")
		await _frames(8)
		main.process_mode = Node.PROCESS_MODE_DISABLED
		map.set("_user_zoom_override", true)
		map.set("_zoom_transition_active", false)
		for zoom: float in [0.65, 0.952, 1.6]:
			map.camera.zoom = Vector2.ONE * zoom
			map.camera.position = tc.global_position + (Vector2(180, 20) if zoom < 1.0 else Vector2(400, 60))
			map.camera.reset_smoothing()
			map.camera.force_update_scroll()
			await _frames(4)
			_expect(is_equal_approx(map.camera.zoom.x, zoom), "phone capture retains requested zoom")
			print("RESOURCE_CAPTURE ", phone, " zoom=", map.camera.zoom.x)
			await _capture("resources-%dx%d-zoom%s.png" % [phone.x, phone.y, str(zoom)])
		main.free()
		GameManager.set_state(GameManager.GameState.MENU)
		await _frames(2)

func _label(parent: Node, value: String, at: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_override("font", KingdomTheme.FONT_HEADING if font_size > 20 else KingdomTheme.FONT_BODY)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
	parent.add_child(label)

func _capture(filename: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(filename))

func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
