extends Node2D
## Synthetic matched-view art/contract fixture. No paid-match or FPS claim.
const TYPES: Array[int] = [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE, BuildingData.BuildingType.RESOURCE_CAMP, BuildingData.BuildingType.BLACKSMITH, BuildingData.BuildingType.SIEGE_WORKSHOP, BuildingData.BuildingType.FARM, BuildingData.BuildingType.WATCH_TOWER]
var _failures: Array[String] = []
var _checks: int = 0
var _baseline: bool = false
var _output: String = "res://output/building-character-2026-10-24/candidate-captures"
var _metrics: Array[Dictionary] = []
var _geometry: Array[Dictionary] = []
var _color_parity: Array[Dictionary] = []
var _selection: SelectionManager

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--baseline":
			_baseline = true
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	GameManager.reduced_motion = true
	GameManager.reduced_flashes = false
	GameManager.guided_opening_enabled = false
	GameManager.ui_scale = 1.0
	_selection = SelectionManager.new()
	add_child(_selection)
	for kind: int in TYPES:
		await _contracts(kind)
	await _hit_contracts()
	if DisplayServer.get_name() != "headless":
		for page: int in 2:
			await _family_gallery(page)
		await _construction_gallery()
		await _damage_gallery()
		for kind: int in [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.FARM]:
			await _near_complete_color_parity(kind)
		await _village_gallery()
	var manifest: Dictionary = {"scripts/buildings/building_base.gd": FileAccess.get_sha256("res://scripts/buildings/building_base.gd"), "tools/test_building_character_presentation.gd": FileAccess.get_sha256("res://tools/test_building_character_presentation.gd")}
	for kind: int in TYPES:
		for owner: int in [0, 1]:
			var source: String = BuildingBase.get_sprite_texture_path(kind, owner)
			manifest[source.trim_prefix("res://")] = FileAccess.get_sha256(source)
	if FileAccess.file_exists("res://assets/buildings/construction_reveal.gdshader"):
		manifest["assets/buildings/construction_reveal.gdshader"] = FileAccess.get_sha256("res://assets/buildings/construction_reveal.gdshader")
	var report := FileAccess.open(_output.path_join("receipt.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"scope": "Synthetic frozen roster and matched views; contracts cover imports, owner alpha, canonical grounding/collision, facade picking, construction replicas, actual damage and reduced flashes. Render counters are not frame-time or device performance measurements.", "baseline": _baseline, "renderer": DisplayServer.get_name(), "checks": _checks, "failures": _failures, "geometry": _geometry, "near_complete_color_parity": _color_parity, "captures": _metrics, "source_sha256": manifest}, "  ") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] building_character: " + failure)
	print("[PASS] building_character: ", _checks, " checks; baseline=", _baseline, "; failures=", _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)

func _building(kind: int, parent: Node = null, owner: int = 0) -> BuildingBase:
	var building := BuildingBase.new()
	building.building_type = kind
	building.player_owner = owner
	var container: Node = parent if parent != null else self
	container.add_child(building)
	building.complete_instantly()
	building.set_process(false)
	return building

func _contracts(kind: int) -> void:
	var building: BuildingBase = _building(kind)
	building.position = Vector2(-1000, -1000)
	var sprite: Sprite2D = building.get_node("BuildingSprite")
	var collision: CollisionShape2D = building.get_child(0)
	var initial_children: int = building.get_child_count()
	var expected_footprint: Vector2i = BuildingData.get_building_stats(kind).footprint
	var texture_scale: Vector2 = sprite.texture.get_size() / BuildingBase.ART_AUTHORED_SIZE
	var ground: Vector2 = sprite.to_global(sprite.get_rect().position + BuildingBase.BUILDING_GROUND_ANCHORS[kind] * texture_scale)
	var footprint_center: Vector2 = BuildingBase.get_footprint_center_offset(expected_footprint)
	_expect(building.footprint == expected_footprint, building.building_name + " gameplay footprint")
	_expect((collision.shape as RectangleShape2D).size == Vector2(expected_footprint.x * MapData.TILE_WIDTH, expected_footprint.y * MapData.TILE_HEIGHT), building.building_name + " collision preserved")
	_expect(ground.is_equal_approx(building.global_position + footprint_center), building.building_name + " canonical source ground anchor")
	_expect((sprite.scale * texture_scale).is_equal_approx(BuildingBase.BUILDING_SCALES[kind]), building.building_name + " authored scale")
	_expect(sprite.texture.get_size() == Vector2(256, 256), building.building_name + " imported resolution")
	_expect(sprite.material == null and sprite.modulate == Color.WHITE, building.building_name + " active neutral materials and no shader")
	var shape_size: Vector2 = (collision.shape as RectangleShape2D).size
	var fire: Vector2 = building.call("_get_defensive_fire_position") - building.global_position
	_geometry.append({"kind": kind, "name": building.building_name, "footprint": [building.footprint.x, building.footprint.y], "collision": [shape_size.x, shape_size.y], "world_scale": [sprite.scale.x * texture_scale.x, sprite.scale.y * texture_scale.y], "ground": [ground.x - building.position.x, ground.y - building.position.y], "fire": [fire.x, fire.y], "idle_children": initial_children})
	var home: Image = sprite.texture.get_image()
	var enemy: Image = load(BuildingBase.get_sprite_texture_path(kind, 1)).get_image()
	var alpha_equal := true
	var changed_opaque: int = 0
	for y: int in home.get_height():
		for x: int in home.get_width():
			alpha_equal = alpha_equal and is_equal_approx(home.get_pixel(x, y).a, enemy.get_pixel(x, y).a)
			changed_opaque += int(home.get_pixel(x, y).a > 0.9 and home.get_pixel(x, y) != enemy.get_pixel(x, y))
	_expect(alpha_equal and changed_opaque > 0, building.building_name + " owner palettes change material only, identical alpha")
	var facade: Rect2 = _selection.call("_building_touch_facade_rect", sprite)
	_expect(_selection.call("_is_touch_on_building_facade", building, sprite.to_global(facade.get_center())), building.building_name + " opaque facade remains pickable")
	_expect(not _selection.call("_is_touch_on_building_facade", building, sprite.to_global(sprite.get_rect().position + Vector2.ONE)), building.building_name + " transparent padding rejects facade pick")
	var ink: Rect2i = home.get_used_rect()
	var art_world: Rect2 = sprite.global_transform * Rect2(sprite.get_rect().position + Vector2(ink.position), Vector2(ink.size))
	_expect(building.get_visual_bounds(false).grow(0.01).encloses(art_world), building.building_name + " framing covers current alpha artwork")
	# Actual construction entry and progress are used; replica-style refresh is
	# also exercised with simulation processing disabled, including completion.
	building.start_construction()
	for progress: float in [0.10, 0.42, 0.78]:
		building.build_progress = progress
		building.call("_update_sprite_appearance")
		if not _baseline:
			var material: ShaderMaterial = sprite.material
			var frame: Node2D = building.get_node_or_null("ConstructionFrame")
			_expect(material != null and is_equal_approx(float(material.get_shader_parameter("construction_progress")), progress), building.building_name + " inert replica reveal tracks replicated progress")
			_expect(frame != null and int(frame.get("stage")) == (0 if progress < 0.25 else 1 if progress < 0.6 else 2), building.building_name + " construction frame phase")
			if frame != null:
				_expect(building.get_visual_bounds().grow(0.01).encloses(frame.global_transform * frame.call("get_frame_bounds")), building.building_name + " construction staging fits camera bounds")
	building.player_owner = 1
	building.call("_update_sprite_appearance")
	_expect(sprite.texture.resource_path.ends_with("_enemy.svg"), building.building_name + " inert construction owner refresh")
	building.complete_instantly()
	await get_tree().process_frame
	_expect(sprite.material == null and sprite.modulate == Color.WHITE and building.get_child_count() == initial_children, building.building_name + " completion removes all temporary construction rendering")
	building.free()

func _hit_contracts() -> void:
	var building: BuildingBase = _building(BuildingData.BuildingType.HOUSE)
	building.position = Vector2(-1000, -1000)
	var sprite: Sprite2D = building.get_node("BuildingSprite")
	var original_hp: int = building.hp
	building.take_damage(17)
	_expect(building.hp == original_hp - 17, "actual damage still applies exact HP loss")
	if not _baseline:
		_expect(sprite.self_modulate != Color.WHITE and sprite.modulate == Color.WHITE, "ordinary neutral art visibly responds to an actual hit")
	building.take_damage(11)
	await get_tree().create_timer(0.25).timeout
	_expect(sprite.self_modulate == Color.WHITE and sprite.modulate == Color.WHITE, "repeated hits recover without accumulated tint")
	GameManager.reduced_flashes = true
	building.take_damage(5)
	_expect(sprite.self_modulate == Color.WHITE and sprite.modulate == Color.WHITE, "reduced flashes suppress hit modulation")
	GameManager.reduced_flashes = false
	building.take_damage(0)
	if not _baseline:
		_expect(sprite.self_modulate == Color.WHITE, "zero damage does not create a false hit")
	building.take_damage(building.hp)
	await get_tree().create_timer(0.22).timeout
	if not _baseline:
		_expect(building.state == BuildingBase.State.DESTROYED and sprite.modulate == Color(0.3, 0.3, 0.3, 0.5), "lethal hit tween cannot restore the destroyed appearance")
	building.free()

func _canvas(size: Vector2i, title: String, subtitle: String) -> Node2D:
	get_window().size = size
	get_window().content_scale_size = size
	get_window().content_scale_factor = 1.0
	var canvas := Node2D.new()
	add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("8d977d")
	background.size = Vector2(size)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	_label(canvas, title, Vector2(30, 18), 25)
	_label(canvas, subtitle, Vector2(30, 53), 15)
	return canvas

func _family_gallery(page: int) -> void:
	var canvas: Node2D = _canvas(Vector2i(1280, 740), "COMPANY ARCHITECTURE / " + ("CIVIC AND MILITARY" if page == 0 else "WORK AND DEFENSE"), "Synthetic gallery · actual world scale at 1.0 zoom · home above / opponent below")
	for column: int in 5:
		var kind: int = TYPES[page * 5 + column]
		for owner: int in [0, 1]:
			var building: BuildingBase = _building(kind, canvas, owner)
			building.position = Vector2(140 + 250 * column, 290 + 285 * owner) - building.get("_footprint_center")
			_label(canvas, BuildingData.get_building_name(kind), Vector2(45 + 250 * column, 338 + 285 * owner), 17)
	await _capture("families-%d.png" % page, {"zoom": 1.0, "buildings": 10})
	canvas.free()

func _construction_gallery() -> void:
	var canvas: Node2D = _canvas(Vector2i(1280, 870), "FROM FOUNDATION TO FINISHED STRUCTURE", "Synthetic state gallery · actual world scale at 1.0 zoom · construction changes presentation only")
	for row: int in 3:
		var kind: int = [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.FARM][row]
		for column: int in 4:
			var building: BuildingBase = _building(kind, canvas)
			building.position = Vector2(170 + 315 * column, 280 + row * 245) - building.get("_footprint_center")
			if column < 3:
				building.start_construction()
				building.build_progress = [0.10, 0.42, 0.78][column]
				building.call("_update_sprite_appearance")
				building.queue_redraw()
			_label(canvas, ["10% / foundation", "42% / structure", "78% / finishing", "Complete"][column], Vector2(60 + 315 * column, 312 + row * 245), 17)
	await _capture("construction-phases.png", {"zoom": 1.0, "buildings": 12, "constructing": 9})
	canvas.free()


func _damage_gallery() -> void:
	var canvas: Node2D = _canvas(Vector2i(1280, 740), "BUILDINGS UNDER ATTACK", "Synthetic state gallery · actual world scale · warm hit frozen for inspection, never used as gameplay evidence")
	for row: int in 2:
		for column: int in 4:
			var building: BuildingBase = _building(BuildingData.BuildingType.TOWN_CENTER, canvas, row)
			building.position = Vector2(170 + 315 * column, 290 + row * 290) - building.get("_footprint_center")
			if column == 1 or column == 3:
				GameManager.reduced_flashes = column == 3
				building.take_damage(10)
				if not _baseline and column == 1:
					(building.get("_damage_flash_tween") as Tween).pause()
			elif column == 2:
				building.hp = int(building.max_hp * 0.23)
				building.queue_redraw()
			_label(canvas, ["Healthy", "During hit", "Critical / 23% HP", "Reduced flashes / hit"][column], Vector2(50 + 315 * column, 340 + row * 290), 17)
	GameManager.reduced_flashes = false
	await _capture("damage-response.png", {"zoom": 1.0, "buildings": 8})
	canvas.free()


func _near_complete_color_parity(kind: int) -> void:
	# Compare the same opaque sprite pixels at 99.9% and active, with the
	# temporary frame hidden. This catches accidental texture multiplication in
	# the shader; alpha-edge pixels and the changing progress bar are excluded.
	get_window().size = Vector2i(280, 260)
	get_window().content_scale_size = Vector2i(280, 260)
	get_window().content_scale_factor = 1.0
	var canvas := Node2D.new()
	add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("8d977d")
	background.size = Vector2(280, 260)
	canvas.add_child(background)
	var building: BuildingBase = _building(kind, canvas)
	building.position = Vector2(140, 205) - building.get("_footprint_center")
	building.start_construction()
	building.build_progress = 0.999
	building.call("_update_sprite_appearance")
	building.queue_redraw()
	var frame: Node2D = building.get_node_or_null("ConstructionFrame")
	if frame != null:
		frame.hide()
	await _capture("parity-%d-construction.png" % kind, {"parity_stage": "99.9%", "kind": kind})
	var construction_image: Image = get_viewport().get_texture().get_image()
	building.complete_instantly()
	await _capture("parity-%d-active.png" % kind, {"parity_stage": "active", "kind": kind})
	var active_image: Image = get_viewport().get_texture().get_image()
	var sprite: Sprite2D = building.get_node("BuildingSprite")
	var source: Image = sprite.texture.get_image()
	var top: int = source.get_used_rect().position.y
	var maximum_difference: int = 0
	var compared: int = 0
	var visible_ink_samples: int = 0
	for y: int in range(top + 8, source.get_height(), 4):
		for x: int in range(2, source.get_width(), 4):
			if source.get_pixel(x, y).a < 0.99:
				continue
			var point: Vector2i = Vector2i(sprite.to_global(sprite.get_rect().position + Vector2(x, y)))
			if point.x < 0 or point.y < 0 or point.x >= 280 or point.y >= 260:
				continue
			var near: Color = construction_image.get_pixelv(point)
			var active: Color = active_image.get_pixelv(point)
			visible_ink_samples += int(active != background.color)
			maximum_difference = maxi(maximum_difference, maxi(absi(near.r8 - active.r8), maxi(absi(near.g8 - active.g8), absi(near.b8 - active.b8))))
			compared += 1
	_color_parity.append({"kind": kind, "opaque_samples": compared, "visible_ink_samples": visible_ink_samples, "maximum_rgb8_difference": maximum_difference})
	if not _baseline:
		_expect(compared > 100 and visible_ink_samples > compared * 0.9 and maximum_difference <= 2, building.building_name + " near-complete shader preserves active material colors")
	canvas.free()


func _village_gallery() -> void:
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.set_state(GameManager.GameState.MENU)
	get_window().size = Vector2i(1280, 800)
	get_window().content_scale_size = Vector2i(1280, 800)
	get_window().content_scale_factor = 1.0
	for frame: int in 4:
		await get_tree().process_frame
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var map: Node2D = main.get("game_map")
	var tc: BuildingBase = main.get("_player_town_center")
	var home: Vector2i = map.map_generator.spawn_positions[0]
	var offsets: Array[Vector2i] = [Vector2i(5, -1), Vector2i(-1, 6), Vector2i(6, 4), Vector2i(-4, 6), Vector2i(2, -5), Vector2i(9, 0), Vector2i(9, 5), Vector2i(4, 9), Vector2i(-2, -4)]
	var roster: Array[Dictionary] = []
	for index: int in range(1, TYPES.size()):
		var building: BuildingBase = _legal_building(main, TYPES[index], home + offsets[index - 1])
		_expect(building != null, "village legal visual foundation " + BuildingData.get_building_name(TYPES[index]))
		if building != null:
			building.complete_instantly()
			roster.append({"kind": building.building_type, "x": building.position.x, "y": building.position.y})
	main.call("_update_fog_of_war")
	main.call("_select_town_center")
	for viewport: Vector2i in [Vector2i(1280, 800), Vector2i(844, 390)]:
		get_window().size = viewport
		get_window().content_scale_size = viewport
		get_window().content_scale_factor = 1.0
		map.camera.zoom = Vector2.ONE * 0.952
		map.camera.position = tc.position + Vector2(110, 60)
		map.camera.reset_smoothing()
		map.camera.force_update_scroll()
		await _capture("village-%dx%d.png" % [viewport.x, viewport.y], {"zoom": 0.952, "roster": roster, "camera": [map.camera.position.x, map.camera.position.y]})
	main.free()
	GameManager.set_state(GameManager.GameState.MENU)

func _legal_building(main: Node, kind: int, anchor: Vector2i) -> BuildingBase:
	var map: Node2D = main.get("game_map")
	var footprint: Vector2i = BuildingData.get_building_stats(kind).footprint
	for radius: int in range(0, 12):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var tile := anchor + Vector2i(dx, dy)
				var legal := true
				for y: int in footprint.y:
					for x: int in footprint.x:
						legal = legal and map.is_tile_buildable(tile + Vector2i(x, y))
				if legal:
					return main.call("_spawn_building", kind, 0, tile)
	return null

func _label(parent: Node, text: String, position_value: Vector2, size_value: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = position_value
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", Color("f6edcf"))
	label.add_theme_color_override("font_shadow_color", Color("303c32"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)

func _capture(name_text: String, metadata: Dictionary) -> void:
	for frame: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_expect(image.save_png(_output.path_join(name_text)) == OK, name_text + " image saved")
	metadata["image"] = name_text
	metadata["viewport"] = [image.get_width(), image.get_height()]
	metadata["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	metadata["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	metadata["rendered_objects"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_metrics.append(metadata)

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
