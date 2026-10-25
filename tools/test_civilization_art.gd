extends Node
## Signature-unit art/import contracts and a synthetic phone-scale field gallery.
## Native images are presentation fixtures, not ordinary-cost match evidence.

const ROLES: Array[String] = ["longbow", "outrider"]
var _failures: Array[String] = []
var _output := "res://output/civilization-art-20261024"
var _receipt: Dictionary = {"assertions": 0, "materials": {}, "captures": []}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	GameManager.current_state = GameManager.GameState.PLAYING
	for role: String in ROLES:
		_materials(role)
	await _field_gallery()
	_receipt["passed"] = _failures.is_empty()
	_receipt["failures"] = _failures
	_receipt["native_rendered"] = DisplayServer.get_name() != "headless"
	_receipt["scope"] = "Synthetic artwork/import/owner-mapping fixture at actual unit scales; no paid gameplay, touchscreen-device, balance or performance claim."
	_receipt["source_sha256"] = {}
	for role: String in ROLES:
		for suffix: String in ["", "_enemy"]:
			var path := "res://assets/units/%s%s.svg" % [role, suffix]
			_receipt.source_sha256[path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(_output.path_join("receipt.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_receipt, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] civilization_art: " + failure)
	if _failures.is_empty():
		print("[PASS] civilization_art: owner palettes, imported pixels, ground anchor and actual signature scenes; %d assertions" % _receipt.assertions)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _materials(role: String) -> void:
	var home := _image("res://assets/units/%s.svg" % role)
	var enemy := _image("res://assets/units/%s_enemy.svg" % role)
	_expect(home.get_size() == Vector2i(128, 128) and enemy.get_size() == home.get_size(), role + " retains 128px canvas")
	if home.get_size() != enemy.get_size():
		return
	var same_alpha := true
	var opaque := 0
	var neutral := 0
	for y: int in home.get_height():
		for x: int in home.get_width():
			var a := home.get_pixel(x, y)
			var b := enemy.get_pixel(x, y)
			same_alpha = same_alpha and is_equal_approx(a.a, b.a)
			if a.a > 0.95:
				opaque += 1
				if a.is_equal_approx(b):
					neutral += 1
	_expect(same_alpha, role + " keeps the exact silhouette across owner colors")
	_expect(neutral > opaque / 2 and neutral < opaque, role + " preserves neutral mount/skin/leather and changes ownership cloth")
	_expect(home.get_used_rect().end.y == 104, role + " rests on the shared y104 ground anchor")
	_expect(home.get_used_rect().position.x > 0 and home.get_used_rect().end.x < 128 and home.get_used_rect().position.y > 0, role + " has no clipped edge")
	_receipt.materials[role] = {"opaque": opaque, "neutral": neutral, "same_alpha": same_alpha, "used_rect": str(home.get_used_rect())}
	for owner: int in 2:
		var path := "res://assets/units/%s%s.svg" % [role, "_enemy" if owner == 1 else ""]
		var imported: Image = (load(path) as Texture2D).get_image()
		var source: Image = home if owner == 0 else enemy
		var same := imported.get_size() == source.get_size()
		if same:
			for y: int in source.get_height():
				for x: int in source.get_width():
					var a := source.get_pixel(x, y)
					var b := imported.get_pixel(x, y)
					same = same and is_equal_approx(a.a, b.a) and (a.a <= 0.95 or a.is_equal_approx(b))
		_expect(same, role + " imported owner %d pixels match the current source" % owner)


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
	camera.position = center + Vector2(0, 45)
	var units: Array[UnitBase] = []
	for civilization: int in CivilizationData.ORDERED_IDS:
		for owner: int in 2:
			GameManager.players[owner]["civilization"] = civilization
			for kind: int in [UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY]:
				var unit: UnitBase = load("res://scenes/units/%s.tscn" % ("archer" if kind == UnitData.UnitType.ARCHER else "cavalry")).instantiate()
				unit.player_owner = owner
				map.get_node("UnitsContainer").add_child(unit)
				unit.set_process(false)
				unit.position = center + Vector2(-245 + civilization * 180 + (80 if kind == UnitData.UnitType.CAVALRY else 0), owner * 110)
				unit._last_visual_position = unit.global_position
				unit._sprite.flip_h = owner == 1
				var expected: String = UnitData.get_unit_icon_path(kind, owner)
				if owner == 1:
					expected = expected.replace(".svg", "_enemy.svg")
				_expect(unit._sprite.texture.resource_path == expected, "civilization %d owner %d kind %d selects its correct art" % [civilization, owner, kind])
				_expect(unit._sprite.scale == UnitData.WORLD_SPRITE_SCALES[kind] and unit._sprite.offset == Vector2(0, -40), "signature keeps shared world scale and ground offset")
				units.append(unit)
	if DisplayServer.get_name() != "headless":
		var overlay := CanvasLayer.new()
		add_child(overlay)
		_label(overlay, "THREE KINGDOMS  /  ARCHERS + CAVALRY AT FIELD SCALE", Vector2(18, 12), 17)
		_label(overlay, "French                                 English                                  Mongols", Vector2(135, 50), 16)
		_label(overlay, "Home above · opponent below · signature equipment retains the shared company materials", Vector2(18, 342), 13)
		for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
			get_window().size = phone
			get_window().content_scale_size = phone
			get_window().content_scale_factor = 1.0
			for zoom: float in [0.952, 1.6]:
				camera.zoom = Vector2.ONE * zoom
				camera.reset_smoothing()
				camera.force_update_scroll()
				await _capture("civilizations-%dx%d-zoom%s.png" % [phone.x, phone.y, str(zoom)])
		GameManager.clearer_player_markers = true
		for unit: UnitBase in units:
			unit.is_selected = unit.player_owner == 0
			unit.hp = unit.max_hp * 0.45 if unit.player_owner == 1 else unit.max_hp
			unit.queue_redraw()
		camera.zoom = Vector2.ONE * 0.952
		camera.force_update_scroll()
		await _capture("civilizations-selection-owner-markers.png")
		overlay.free()
	map.free()


func _image(path: String) -> Image:
	var image := Image.new()
	_expect(image.load_svg_from_string(FileAccess.get_file_as_string(path)) == OK, "SVG renders: " + path)
	return image


func _label(parent: Node, text: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", KingdomTheme.FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", KingdomTheme.INK_LIGHT)
	parent.add_child(label)


func _capture(filename: String) -> void:
	for frame: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(_output.path_join(filename)) == OK, "saved native image " + filename)
	_receipt.captures.append(filename)


func _expect(condition: bool, message: String) -> void:
	_receipt.assertions += 1
	if not condition:
		_failures.append(message)
