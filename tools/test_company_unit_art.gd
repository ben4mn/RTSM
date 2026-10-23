extends Node
## Original miniature art at real phone scale. These are visual fixtures, not
## paid production or device-performance evidence. Never saves player settings.

const NAMES: Array[String] = ["Builder", "Warrior", "Archer", "Horseman", "Scout", "Siege"]
const FILES: Array[String] = ["worker", "warrior", "archer", "cavalry", "scout", "siege"]
const SCENES: Array[String] = ["villager", "infantry", "archer", "cavalry", "scout", "siege"]
const RADII: Array[float] = [12.0, 14.0, 13.0, 16.0, 12.0, 18.0]
var failures: Array[String] = []
var output: String = "res://output/company-units-20261022"
var baseline: String = "res://output/company-units-20261022/baseline"
var metrics: Dictionary = {"roles": [], "poses_checked": 0, "phone_captures": []}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--baseline="):
			baseline = argument.trim_prefix("--baseline=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	GameManager.ui_scale = 1.0
	GameManager.clearer_player_markers = false
	GameManager.guided_opening_enabled = false
	_contracts()
	if DisplayServer.get_name() != "headless":
		if FileAccess.file_exists(baseline.path_join("worker.svg")):
			await _contact_sheet()
		else:
			print("[INFO] Archived baseline art absent; current phone captures still run. Use --baseline=/path/to/previous/svgs for the comparison sheet.")
		await _phone_captures()
	metrics["renderer"] = DisplayServer.get_name()
	var source_hashes: Dictionary = {}
	for path: String in ["scripts/data/unit_data.gd", "scripts/units/unit_base.gd", "scripts/units/villager.gd", "scripts/managers/selection_manager.gd", "tools/test_company_unit_art.gd"]:
		source_hashes[path] = FileAccess.get_sha256("res://" + path)
	for asset: String in FILES:
		for suffix: String in ["", "_enemy"]:
			var path: String = "assets/units/%s%s.svg" % [asset, suffix]
			source_hashes[path] = FileAccess.get_sha256("res://" + path)
	metrics["source_sha256"] = source_hashes
	metrics["passed"] = failures.is_empty()
	metrics["failures"] = failures
	metrics["user_data_dir"] = OS.get_user_data_dir()
	var file := FileAccess.open(output.path_join("art-contracts.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics, "\t") + "\n")
	for failure: String in failures:
		push_error("[FAIL] company_unit_art: " + failure)
	if failures.is_empty():
		print("[PASS] company_unit_art: six roles, neutral materials, identical team alpha, grounded relative sizes/collision/foot anchor, pose bounds/selection/health; three foot-role native gallery when rendered")
	get_tree().quit(0 if failures.is_empty() else 1)

func _contracts() -> void:
	var selection: SelectionManager = load("res://scripts/managers/selection_manager.gd").new()
	add_child(selection)
	selection.set_process(false)
	var world_sizes: Array[Vector2] = []
	for role: int in FILES.size():
		var home: Image = load("res://assets/units/%s.svg" % FILES[role]).get_image()
		var enemy: Image = load("res://assets/units/%s_enemy.svg" % FILES[role]).get_image()
		var opaque: int = 0
		var material_same: int = 0
		var alpha_same := true
		for y: int in 128:
			for x: int in 128:
				var a: Color = home.get_pixel(x, y)
				var b: Color = enemy.get_pixel(x, y)
				alpha_same = alpha_same and is_equal_approx(a.a, b.a)
				if a.a > 0.95:
					opaque += 1
					if a.is_equal_approx(b):
						material_same += 1
		_expect(alpha_same, NAMES[role] + " cloth variants preserve exact silhouette alpha")
		_expect(material_same > opaque / 2 and material_same < opaque, NAMES[role] + " changes cloth while most opaque materials stay identical")
		metrics.roles.append({"role": NAMES[role], "opaque_pixels": opaque, "unchanged_material_pixels": material_same, "used_rect": str(home.get_used_rect()), "team_alpha_identical": alpha_same})
		for owner: int in 2:
			var unit := _unit(role, owner, self)
			var sprite: Sprite2D = unit.get_node("UnitSprite")
			_expect(sprite.texture.get_size() == Vector2(128, 128), NAMES[role] + " retains128px canvas")
			var ink_size: Vector2 = unit._sprite_opaque_rect.size * sprite.scale
			if owner == 0:
				world_sizes.append(ink_size)
				metrics.roles[role]["world_ink_size"] = [ink_size.x, ink_size.y]
			_expect(is_equal_approx(sprite.scale.x, sprite.scale.y) and sprite.scale.x > 0.0, NAMES[role] + " preserves artwork aspect ratio")
			_expect(sprite.to_global(Vector2(64, 104) - sprite.texture.get_size() * 0.5 + sprite.offset).is_equal_approx(unit.global_position), NAMES[role] + " authored feet meet the actual ground origin")
			var idle_art: Rect2 = sprite.transform * Rect2(unit._sprite_opaque_rect.position - sprite.texture.get_size() * 0.5 + sprite.offset, unit._sprite_opaque_rect.size)
			_expect(absf(idle_art.end.y) <= 1.0, NAMES[role] + " opaque feet meet ground without floating or sinking")
			_expect(unit._health_bar_y + 2.0 < idle_art.position.y, NAMES[role] + " idle health bar clears the head and weapons")
			if role < 3:
				_expect(ink_size.y >= 24.0 and ink_size.y <= 36.0, NAMES[role] + " foot miniature stays within the grounded human-height band")
				_expect(ink_size.x <= RADII[role] * 2.5, NAMES[role] + " equipment silhouette remains close to its unchanged navigation footprint")
			_expect(sprite.offset == Vector2(0, -40), NAMES[role] + " retains y104 foot anchor")
			_expect(is_equal_approx((unit.collision_shape.shape as CircleShape2D).radius, RADII[role]), NAMES[role] + " retains collision radius")
			_expect(sprite.modulate == Color.WHITE, NAMES[role] + " retains neutral material colors")
			_expect(sprite.texture.resource_path.ends_with("_enemy.svg") == (owner == 1), NAMES[role] + " uses correct owner cloth")
			unit.is_selected = true
			unit.hp = unit.max_hp * 0.25
			unit.stance = UnitBase.Stance.STAND_GROUND
			for pose: int in 5:
				unit.current_state = UnitBase.State.GATHERING if pose == 2 else UnitBase.State.ATTACKING if pose >= 3 else UnitBase.State.MOVING
				unit.position += Vector2(-4 if pose == 1 else 4, 0) if pose <= 1 else Vector2.ZERO
				unit._attack_animation_duration = 0.5
				unit._attack_animation_remaining = 0.35 if pose >= 3 else 0.0
				unit._attack_animation_direction = Vector2.LEFT if pose == 3 else Vector2.RIGHT
				unit._update_sprite_motion(1.0 / 60.0)
				var visible: Rect2 = unit.get_visual_bounds()
				var body: Rect2 = unit._sprite_opaque_rect
				body.position -= sprite.texture.get_size() * 0.5
				body.position += sprite.offset
				if sprite.flip_h:
					body.position.x = -body.end.x
				var transformed: Rect2 = sprite.global_transform * body
				_expect(visible.encloses(transformed), NAMES[role] + " animated artwork stays within visual framing bounds")
				var health := Rect2(unit.global_position + Vector2(-RADII[role] * 1.15, unit._health_bar_y), Vector2(RADII[role] * 2.3, 2))
				_expect(visible.encloses(health), NAMES[role] + " critical health remains within framing")
				var body_target: Vector2 = sprite.to_global(selection._unit_touch_body_rect(sprite).get_center())
				_expect(selection._is_touch_on_unit_body(unit, body_target), NAMES[role] + " keeps central body selectable in every pose")
				_expect(selection._get_node_at(body_target, false) == unit, NAMES[role] + " desktop resolver selects the animated body")
				_expect(selection._get_node_at(body_target, true) == unit, NAMES[role] + " touch resolver selects the animated body")
				_expect(selection._get_node_at(unit.global_position, true) == unit, NAMES[role] + " ground marker retains deliberate touch access")
				metrics.poses_checked += 1
			unit.free()
	var tallest_foot: float = maxf(world_sizes[0].y, maxf(world_sizes[1].y, world_sizes[2].y))
	for role: int in [3, 4]:
		_expect(world_sizes[role].y > tallest_foot * 1.25, NAMES[role] + " mounted rider sits clearly above foot troops")
		_expect(world_sizes[role].x > world_sizes[1].x * 1.25, NAMES[role] + " mount reads wider than a standing warrior")
	_expect(world_sizes[5].x > maxf(world_sizes[3].x, world_sizes[4].x), "siege carriage reads broader than either mount")
	selection.free()

func _unit(role: int, owner: int, parent: Node) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % SCENES[role]).instantiate()
	unit.player_owner = owner
	parent.add_child(unit)
	unit.set_process(false)
	return unit

func _contact_sheet() -> void:
	_size(Vector2i(932, 600))
	var sheet := Control.new()
	add_child(sheet)
	var bg := ColorRect.new()
	bg.color = Color("293235")
	bg.size = Vector2(932, 600)
	sheet.add_child(bg)
	_label(sheet, "COMPANY MINIATURES  /  ORIGINAL ROLE IDENTITIES", Vector2(24, 14), 24)
	_label(sheet, "Previous field art", Vector2(24, 53), 16)
	_label(sheet, "Refined cast  ·  shared canvas, foot anchor and team materials", Vector2(24, 310), 16)
	for role: int in 3:
		for row: int in 2:
			var texture: Texture2D = load("res://assets/units/%s.svg" % FILES[role])
			if row == 0:
				var old := Image.new()
				var error: Error = old.load_svg_from_string(FileAccess.get_file_as_string(baseline.path_join(FILES[role] + ".svg")))
				_expect(error == OK, "Archived baseline SVG renders")
				texture = ImageTexture.create_from_image(old)
			var picture := TextureRect.new()
			picture.texture = texture
			picture.position = Vector2(52 + role * 300, 74 + row * 260)
			picture.size = Vector2(208, 208)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sheet.add_child(picture)
		_label(sheet, NAMES[role], Vector2(119 + role * 300, 562), 20)
	await _capture("company-before-after.png")
	sheet.free()

func _phone_captures() -> void:
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
	camera.position = center
	var units: Array[UnitBase] = []
	for owner: int in 2:
		for role: int in 3:
			var unit := _unit(role, owner, map.get_node("UnitsContainer"))
			unit.position = center + Vector2(-170 + role * 170, -45 + owner * 115)
			units.append(unit)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_label(overlay, "FIELD MINIATURES  /  ACTUAL WORLD SCALE", Vector2(24, 14), 16, Color("293235"))
	_label(overlay, "Home above · opposing cloth below · selection, damage and markers remain optional", Vector2(24, 37), 13, Color("293235"))
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		_size(phone)
		for zoom: float in [0.952, 0.65, 1.6]:
			camera.zoom = Vector2.ONE * zoom
			camera.reset_smoothing()
			camera.force_update_scroll()
			await _capture("roles-%dx%d-zoom%s.png" % [phone.x, phone.y, str(zoom)])
			metrics.phone_captures.append({"viewport": str(phone), "zoom": zoom})
		camera.zoom = Vector2.ONE * 0.952
		GameManager.clearer_player_markers = true
		units[1].is_selected = true
		units[5].hp = units[5].max_hp * 0.25
		units[0].current_state = UnitBase.State.GATHERING
		units[0]._update_sprite_motion(0.12)
		for unit: UnitBase in units:
			unit.queue_redraw()
		await _capture("feedback-%dx%d.png" % [phone.x, phone.y])
		GameManager.clearer_player_markers = false
		units[1].is_selected = false
		units[5].hp = units[5].max_hp
		units[0].current_state = UnitBase.State.IDLE
		units[0]._update_sprite_motion(0.01)
		for unit: UnitBase in units:
			unit.queue_redraw()
	overlay.free()
	for unit: UnitBase in units:
		unit.free()
	for owner: int in 2:
		for index: int in 9:
			var unit := _unit(index % 3, owner, map.get_node("UnitsContainer"))
			unit.position = center + Vector2((-100 if owner == 0 else 80) + (index % 3) * 36, -65 + (index / 3) * 50)
			unit._sprite.flip_h = owner == 1
	_size(Vector2i(844, 390))
	camera.zoom = Vector2.ONE * 0.952
	await _capture("formation-18-units.png")
	map.free()

func _size(value: Vector2i) -> void:
	get_window().size = value
	get_window().content_scale_size = value
	get_window().content_scale_factor = 1.0

func _label(parent: Node, text: String, at: Vector2, font_size: int, color: Color = Color("E8E5DB")) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", load("res://assets/fonts/Barlow-Medium.ttf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _capture(name: String) -> void:
	for frame: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name))

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
