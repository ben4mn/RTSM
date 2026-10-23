extends Node
## Scout art contracts and a native gallery using unchanged live unit scenes.
## This fixture is not an AI battle, touchscreen-device, or performance test.

const SCOUT_SCENE := preload("res://scenes/units/scout.tscn")
const PHONES: Array[Vector2i] = [Vector2i(844, 390), Vector2i(932, 430)]
const ZOOMS: Array[float] = [0.65, 0.952, 1.6]
const ROSTER: Array[String] = ["villager", "infantry", "scout", "cavalry", "archer", "siege"]

var _failures: Array[String] = []
var _output := "res://output/polish-2026-10-22/scout-art"
var _baseline := "res://output/polish-2026-10-22/scout-baseline"
var _metrics: Dictionary = {"pose_checks": 0, "profiles": [], "captures": [], "native_rendered": false}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--baseline="):
			_baseline = argument.trim_prefix("--baseline=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	GameManager.ui_scale = 1.0
	GameManager.clearer_player_markers = false
	GameManager.guided_opening_enabled = false
	_material_contracts()
	await _pose_contracts()
	if DisplayServer.get_name() != "headless":
		_metrics["native_rendered"] = true
		await _contact_sheet()
		await _field_gallery()
	_metrics["passed"] = _failures.is_empty()
	_metrics["failures"] = _failures
	_metrics["user_data_dir"] = OS.get_user_data_dir()
	var file := FileAccess.open(_output.path_join("scout-art-contracts.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_metrics, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] company_scout_art: " + failure)
	if _failures.is_empty():
		print("[PASS] company_scout_art: team alpha/materials; live scale/anchor/collision; 120 mirrored gait/selection/health/touch bounds checks across six phone/zoom profiles; native gallery when rendered")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _material_contracts() -> void:
	var home: Image = _source_image("res://assets/units/scout.svg")
	var enemy: Image = _source_image("res://assets/units/scout_enemy.svg")
	_expect(home.get_size() == Vector2i(128, 128) and enemy.get_size() == Vector2i(128, 128), "both owner sources retain the 128px canvas")
	if home.get_size() != enemy.get_size():
		return
	var alpha_same := true
	var opaque := 0
	var neutral := 0
	for y: int in home.get_height():
		for x: int in home.get_width():
			var a: Color = home.get_pixel(x, y)
			var b: Color = enemy.get_pixel(x, y)
			alpha_same = alpha_same and is_equal_approx(a.a, b.a)
			if a.a > 0.95:
				opaque += 1
				if a.is_equal_approx(b):
					neutral += 1
	_expect(alpha_same, "owner cloth swaps preserve exact silhouette alpha")
	_expect(neutral > opaque / 2 and neutral < opaque, "most opaque mount/skin/leather remains neutral while cloth changes")
	_expect(home.get_used_rect().end.y == 104, "hooves preserve the y104 art baseline")
	_metrics["materials"] = {"team_alpha_identical": alpha_same, "opaque_pixels": opaque, "neutral_pixels": neutral, "used_rect": str(home.get_used_rect())}
	for owner: int in 2:
		var path: String = "res://assets/units/scout%s.svg" % ("_enemy" if owner == 1 else "")
		var imported: Image = (load(path) as Texture2D).get_image()
		var source: Image = enemy if owner == 1 else home
		var matching: bool = imported.get_size() == source.get_size()
		if matching:
			for y: int in source.get_height():
				for x: int in source.get_width():
					var source_pixel: Color = source.get_pixel(x, y)
					var runtime_pixel: Color = imported.get_pixel(x, y)
					# Texture import fixes RGB in transparent borders. Alpha and
					# opaque material pixels must still match the current source.
					matching = matching and is_equal_approx(source_pixel.a, runtime_pixel.a)
					if source_pixel.a > 0.95:
						matching = matching and source_pixel.is_equal_approx(runtime_pixel)
		_expect(matching, "owner %d runtime import matches visible current SVG source" % owner)


func _pose_contracts() -> void:
	for phone: Vector2i in PHONES:
		var viewport := SubViewport.new()
		viewport.size = phone
		add_child(viewport)
		var camera := Camera2D.new()
		viewport.add_child(camera)
		camera.make_current()
		var selection := SelectionManager.new()
		viewport.add_child(selection)
		selection.set_process(false)
		var units: Array[UnitBase] = []
		for owner: int in 2:
			var unit: UnitBase = _unit("scout", owner, viewport)
			unit.position = Vector2(-70 if owner == 0 else 70, 15)
			unit._last_visual_position = unit.global_position
			units.append(unit)
			_expect(unit._sprite.texture.get_size() == Vector2(128, 128), "live Scout preserves the canvas")
			var ink_size: Vector2 = unit._sprite_opaque_rect.size * unit._sprite.scale
			_expect(ink_size.y > 36.0 and ink_size.y < 56.0 and ink_size.x > 36.0, "live Scout reads as a mounted figure at world scale")
			_expect(is_equal_approx(unit._sprite.scale.x, unit._sprite.scale.y), "live Scout preserves artwork proportions")
			_expect(unit._sprite.offset == Vector2(0, -40), "live Scout preserves foot anchor")
			_expect(is_equal_approx((unit.collision_shape.shape as CircleShape2D).radius, 12.0), "live Scout preserves collision radius")
			_expect(unit._sprite.modulate == Color.WHITE, "live Scout does not tint neutral materials")
			_expect(unit._sprite.texture.resource_path.ends_with("_enemy.svg") == (owner == 1), "live Scout selects its owner cloth")
		for zoom: float in ZOOMS:
			camera.zoom = Vector2.ONE * zoom
			camera.force_update_scroll()
			await get_tree().process_frame
			_metrics.profiles.append({"viewport": str(phone), "zoom": zoom})
			for unit: UnitBase in units:
				for direction: int in [-1, 1]:
					for pose: int in 5:
						unit.is_selected = pose >= 2
						unit.hp = unit.max_hp * (0.25 if pose >= 3 else 1.0)
						unit.stance = UnitBase.Stance.STAND_GROUND if pose == 4 else UnitBase.Stance.AGGRESSIVE
						unit.current_state = UnitBase.State.MOVING if pose > 0 else UnitBase.State.IDLE
						unit._animation_clock = float(pose) * 0.087
						unit._sprite.flip_h = direction < 0
						unit.position.x += direction * 3.0 if pose > 0 else 0.0
						unit._update_sprite_motion(1.0 / 60.0)
						_check_pose(unit, selection, viewport, direction, phone, zoom)
		viewport.free()


func _check_pose(unit: UnitBase, selection: SelectionManager, viewport: SubViewport, direction: int, phone: Vector2i, zoom: float) -> void:
	var context: String = "%s zoom%.3f owner%d facing%d" % [phone, zoom, unit.player_owner, direction]
	var sprite: Sprite2D = unit._sprite
	_expect(sprite.flip_h == (direction < 0), context + " respects mirrored mounted facing")
	var body: Rect2 = unit._sprite_opaque_rect
	body.position += sprite.offset - sprite.texture.get_size() * 0.5
	if sprite.flip_h:
		body.position.x = -body.end.x
	var artwork: Rect2 = sprite.global_transform * body
	var visible: Rect2 = unit.get_visual_bounds()
	_expect(visible.encloses(artwork), context + " moving artwork stays inside visual bounds")
	# The drawn ring is radius 13 × 5.76, with a 1.5px selected stroke.
	var selection_ring := Rect2(unit.global_position + Vector2(-13.75, -3.51), Vector2(27.5, 13.02))
	_expect(visible.encloses(selection_ring), context + " selection/ground ring stays inside framing")
	if unit.is_selected or unit.hp < unit.max_hp:
		var health := Rect2(unit.global_position + Vector2(-13.8, unit._health_bar_y), Vector2(27.6, 2))
		_expect(visible.encloses(health), context + " health overlay stays inside framing")
	if unit.stance == UnitBase.Stance.STAND_GROUND:
		_expect(visible.encloses(Rect2(unit.global_position + Vector2(12, -6.5), Vector2(8, 9))), context + " stance shield stays inside framing")
	var target: Vector2 = sprite.to_global(selection._unit_touch_body_rect(sprite).get_center())
	_expect(selection._is_touch_on_unit_body(unit, target), context + " rider/mount body remains touch-selectable")
	_expect(not selection._is_touch_on_unit_body(unit, target + Vector2(100, 0)), context + " nearby terrain remains outside body selection")
	var screen_bounds: Rect2 = viewport.get_canvas_transform() * visible
	_expect(Rect2(Vector2.ZERO, Vector2(phone)).encloses(screen_bounds), context + " phone framing includes the full pose and overlays")
	_metrics.pose_checks += 1


func _contact_sheet() -> void:
	_size(Vector2i(932, 568))
	var sheet := Control.new()
	add_child(sheet)
	var background := ColorRect.new()
	background.color = KingdomTheme.INK_LIGHT
	background.size = Vector2(932, 568)
	sheet.add_child(background)
	_label(sheet, "COMPANY SCOUT  /  OWNER CLOTH AND MIRRORED SILHOUETTE", Vector2(24, 12), 23)
	_label(sheet, "Previous field piece", Vector2(24, 48), 16)
	_label(sheet, "Refined outrider  ·  shared canvas and foot anchor", Vector2(24, 300), 16)
	for column: int in 4:
		var owner: int = column / 2
		var mirrored: bool = column % 2 == 1
		var filename: String = "scout%s.svg" % ("_enemy" if owner == 1 else "")
		_label(sheet, ("Home" if owner == 0 else "Opponent") + (" · left" if mirrored else " · right"), Vector2(50 + column * 224, 532), 17)
		for row: int in 2:
			var source: String = _baseline.path_join(filename) if row == 0 else "res://assets/units/" + filename
			_expect(FileAccess.file_exists(source), "before/after source exists: " + source)
			if not FileAccess.file_exists(source):
				continue
			var picture := TextureRect.new()
			picture.texture = ImageTexture.create_from_image(_source_image(source))
			picture.flip_h = mirrored
			picture.position = Vector2(28 + column * 224, 76 + row * 244)
			picture.size = Vector2(192, 192)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sheet.add_child(picture)
	await _capture("scout-before-after.png")
	sheet.free()


func _field_gallery() -> void:
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = 0
	var map: Node2D = load("res://scenes/map/game_map.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	map.process_mode = Node.PROCESS_MODE_DISABLED
	map.get_node("FogLayer").hide()
	for resource: Node in get_tree().get_nodes_in_group("resources"):
		(resource as CanvasItem).hide()
	map.sacred_site.hide()
	var center: Vector2 = map.tile_to_world(Vector2i(36, 36))
	var camera: Camera2D = map.get_node("Camera2D")
	camera.position = center + Vector2(0, 30)
	var units: Array[UnitBase] = []
	for owner: int in 2:
		for role: int in ROSTER.size():
			var unit: UnitBase = _unit(ROSTER[role], owner, map.get_node("UnitsContainer"))
			unit.position = center + Vector2(-175 + role * 70, owner * 95)
			unit._last_visual_position = unit.global_position
			unit._sprite.flip_h = owner == 1
			units.append(unit)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_label(overlay, "ACTUAL FIELD SCALE  /  SCOUT BESIDE THE MIXED ROSTER", Vector2(18, 10), 17, KingdomTheme.INK_LIGHT)
	var caption: Label = _label(overlay, "", Vector2(18, 32), 13, KingdomTheme.INK_LIGHT)
	for phone: Vector2i in PHONES:
		_size(phone)
		for zoom: float in ZOOMS:
			caption.text = "Home above · opponent below · Worker / Warrior / Scout / Cavalry / Archer / Siege · zoom %.3f" % zoom
			camera.zoom = Vector2.ONE * zoom
			camera.reset_smoothing()
			camera.force_update_scroll()
			await _capture("roster-%dx%d-zoom%s.png" % [phone.x, phone.y, str(zoom)])
		caption.text = "Selected Scout above · critical Scout below · optional owner markers · normal zoom"
		camera.zoom = Vector2.ONE * 0.952
		camera.force_update_scroll()
		GameManager.clearer_player_markers = true
		units[2].is_selected = true
		units[2].stance = UnitBase.Stance.STAND_GROUND
		units[8].hp = units[8].max_hp * 0.25
		for unit: UnitBase in units:
			unit.queue_redraw()
		await _capture("feedback-%dx%d.png" % [phone.x, phone.y])
		GameManager.clearer_player_markers = false
		units[2].is_selected = false
		units[2].stance = UnitBase.Stance.AGGRESSIVE
		units[8].hp = units[8].max_hp
		for unit: UnitBase in units:
			unit.queue_redraw()
	for unit: UnitBase in units:
		unit.free()
	for owner: int in 2:
		for index: int in 12:
			var unit: UnitBase = _unit(ROSTER[index % 6], owner, map.get_node("UnitsContainer"))
			unit.position = center + Vector2(-175 + (index % 6) * 70 + (18 if index >= 6 else 0), -25 + owner * 130 + (index / 6) * 50)
			unit._sprite.flip_h = owner == 1
	caption.text = "24 live units · two mixed formations · neutral materials with owner cloth · normal zoom"
	camera.position = center + Vector2(0, 60)
	camera.zoom = Vector2.ONE * 0.952
	camera.force_update_scroll()
	for phone: Vector2i in PHONES:
		_size(phone)
		await _capture("formation-24-units-%dx%d.png" % [phone.x, phone.y])
	overlay.free()
	map.free()


func _unit(scene_name: String, owner: int, parent: Node) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % scene_name).instantiate()
	unit.player_owner = owner
	parent.add_child(unit)
	unit.set_process(false)
	return unit


func _source_image(path: String) -> Image:
	var image := Image.new()
	var error: Error = image.load_svg_from_string(FileAccess.get_file_as_string(path))
	_expect(error == OK, "SVG source rasterizes: " + path)
	return image


func _size(value: Vector2i) -> void:
	get_window().size = value
	get_window().content_scale_size = value
	get_window().content_scale_factor = 1.0


func _label(parent: Node, text: String, at: Vector2, font_size: int, color: Color = KingdomTheme.PARCHMENT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", KingdomTheme.FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _capture(filename: String) -> void:
	for frame: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(_output.path_join(filename))
	_expect(error == OK, "native capture saved: " + filename)
	_metrics.captures.append(filename)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
