extends Node
## Mounted/carriage art contracts and native phone gallery with live scenes.
## This fixture is not an AI battle, touchscreen-device, or performance test.

const MATERIAL_ROLES: Array[String] = ["cavalry", "siege"]
const PHONES: Array[Vector2i] = [Vector2i(844, 390), Vector2i(932, 430)]
const ZOOMS: Array[float] = [0.65, 0.952, 1.6]
const ROSTER: Array[String] = ["villager", "infantry", "scout", "cavalry", "archer", "siege"]

var _failures: Array[String] = []
var _output := "res://output/iteration-2026-10-24/unit-art"
var _baseline := "res://output/iteration-2026-10-24/unit-art/baseline-assets"
var _metrics: Dictionary = {"pose_checks": 0, "profiles": [], "captures": [], "native_rendered": false, "render_counters": []}


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
	for role: String in MATERIAL_ROLES:
		_material_contracts(role)
	await _pose_contracts()
	_release_contracts()
	if DisplayServer.get_name() != "headless":
		_metrics["native_rendered"] = true
		await _contact_sheet()
		await _field_gallery()
	_metrics["passed"] = _failures.is_empty()
	_metrics["failures"] = _failures
	_metrics["user_data_dir"] = OS.get_user_data_dir()
	_metrics["scope"] = "Native synthetic art/pose fixture. Snapshot counters after four frames are diagnostics, not throughput or physical-phone performance. No paid production or balance claim."
	_metrics["source_sha256"] = {}
	for path: String in ["scripts/units/unit_base.gd", "scripts/units/villager.gd", "scripts/data/unit_data.gd", "tools/test_company_mounted_art.gd", "assets/units/cavalry.svg", "assets/units/cavalry_enemy.svg", "assets/units/siege.svg", "assets/units/siege_enemy.svg"]:
		_metrics.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	var file := FileAccess.open(_output.path_join("mounted-art-contracts.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_metrics, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] company_mounted_art: " + failure)
	if _failures.is_empty():
		print("[PASS] company_mounted_art: team alpha/materials; live scale/anchor/collision; 288 mirrored attack/selection/touch bounds checks across all six roles; native gallery when rendered")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _material_contracts(role: String) -> void:
	var home: Image = _source_image("res://assets/units/%s.svg" % role)
	var enemy: Image = _source_image("res://assets/units/%s_enemy.svg" % role)
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
	_metrics[role + "_materials"] = {"team_alpha_identical": alpha_same, "opaque_pixels": opaque, "neutral_pixels": neutral, "used_rect": str(home.get_used_rect())}
	for owner: int in 2:
		var path: String = "res://assets/units/%s%s.svg" % [role, "_enemy" if owner == 1 else ""]
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
	var selection := SelectionManager.new()
	add_child(selection)
	selection.set_process(false)
	for role: String in ROSTER:
		for owner: int in 2:
			var unit: UnitBase = _unit(role, owner, self)
			var sprite: Sprite2D = unit._sprite
			var radius: float = UnitBase.UNIT_SIZES[unit.unit_type]
			_expect(sprite.scale == UnitData.WORLD_SPRITE_SCALES[unit.unit_type], role + " unchanged scale")
			_expect(sprite.offset == Vector2(0, -40), role + " unchanged y104 anchor")
			_expect(is_equal_approx((unit.collision_shape.shape as CircleShape2D).radius, radius), role + " unchanged collision")
			_expect(sprite.modulate == Color.WHITE, role + " neutral materials untinted")
			_expect(sprite.texture.resource_path.ends_with("_enemy.svg") == (owner == 1), role + " owner variant")
			var health_before: float = unit.hp
			var position_before: Vector2 = unit.position
			var cooldown_before: float = unit.attack_cooldown
			for direction: int in [-1, 1]:
				for pose: int in 12:
					unit.is_selected = true
					unit.stance = UnitBase.Stance.STAND_GROUND
					unit.current_state = UnitBase.State.ATTACKING
					unit._attack_animation_duration = float(UnitData.UNITS[unit.unit_type].get("attack_windup", 0.12)) + 0.16
					unit._attack_animation_remaining = unit._attack_animation_duration * (1.0 - float(pose) / 12.0)
					unit._attack_animation_direction = Vector2(direction, -0.3).normalized()
					sprite.flip_h = direction < 0
					unit._update_sprite_motion(0.0)
					var body: Rect2 = unit._sprite_opaque_rect
					body.position += sprite.offset - sprite.texture.get_size() * 0.5
					if sprite.flip_h: body.position.x = -body.end.x
					_expect(unit.get_visual_bounds().encloses(sprite.global_transform * body), role + " complete attack pose framed")
					var target: Vector2 = sprite.to_global(selection._unit_touch_body_rect(sprite).get_center())
					_expect(selection._is_touch_on_unit_body(unit, target), role + " pose body touch selection")
					_expect(selection._get_node_at(target, false) == unit, role + " pose desktop selection")
					_expect(selection._get_node_at(target, true) == unit, role + " pose touch resolver")
					_expect(sprite.position.length() <= 5.01 and absf(sprite.rotation) <= 0.061, role + " existing attack excursion envelope")
					_metrics.pose_checks += 1
			_expect(unit.hp == health_before and unit.position == position_before and unit.attack_cooldown == cooldown_before, role + " presentation leaves simulation unchanged")
			if unit.has_method("_attack_pose_strength"):
				var windup: float = unit._attack_animation_duration - 0.16
				_expect(is_equal_approx(float(unit.call("_attack_pose_strength", windup, windup)), 1.0), role + " visual stroke peaks at release")
				_expect(absf(float(unit.call("_attack_pose_strength", windup + 0.16, windup))) < 0.0001, role + " visual recovery ends after160ms")
			unit.free()
	selection.free()


func _release_contracts() -> void:
	_metrics["releases"] = []
	var scene: Node = get_tree().current_scene
	get_tree().current_scene = null
	for role: String in ["infantry", "archer", "cavalry", "siege"]:
		for owner: int in 2:
			var arena := Node2D.new()
			add_child(arena)
			var attacker: UnitBase = _unit(role, owner, arena)
			var defender: UnitBase = _unit("infantry", 1 - owner, arena)
			defender.position = Vector2(20, 0)
			attacker.attack_target = defender
			attacker.current_state = UnitBase.State.ATTACKING
			attacker._perform_attack()
			var windup: float = float(UnitData.UNITS[attacker.unit_type].get("attack_windup", 0.12))
			var hp_before: float = defender.hp
			var cooldown: float = attacker.attack_cooldown
			_expect(is_equal_approx(attacker._attack_animation_duration, windup + 0.16), role + " uses unchanged windup plus visual recovery")
			attacker._update_sprite_motion(windup)
			_expect(attacker._attack_windup_remaining == windup and attacker.attack_cooldown == cooldown and defender.hp == hp_before, role + " visual clock cannot release damage")
			attacker._advance_attack_windup(windup - 0.0001)
			_expect(arena.get_child_count() == 2 and defender.hp == hp_before, role + " no hit or projectile before windup")
			attacker._advance_attack_windup(0.0002)
			_expect(arena.get_child_count() == 3 and defender.hp == hp_before, role + " releases one delayed attack at existing windup")
			var expected: float = Combat.calculate_unit_damage(attacker, defender)
			if arena.get_child_count() == 3:
				var released: Node = arena.get_child(2)
				if released is Combat.RangedProjectile:
					_expect(attacker.is_ranged, role + " retains projectile attack")
					(released as Combat.RangedProjectile).advance_projectile(1.0)
				elif released is Combat.CommittedMeleeHit:
					_expect(not attacker.is_ranged, role + " retains committed melee")
					(released as Combat.CommittedMeleeHit).advance_committed_hit()
			_expect(is_equal_approx(hp_before - defender.hp, expected), role + " existing damage resolves exactly once")
			_metrics.releases.append({"role": role, "owner": owner, "windup": windup, "animation_duration": attacker._attack_animation_duration, "cooldown": cooldown, "damage": hp_before - defender.hp})
			arena.free()
	get_tree().current_scene = scene


func _contact_sheet() -> void:
	_size(Vector2i(932, 530))
	var sheet := Control.new()
	add_child(sheet)
	var background := ColorRect.new()
	background.color = KingdomTheme.INK_LIGHT
	background.size = Vector2(932, 530)
	sheet.add_child(background)
	_label(sheet, "COMPANY HORSE GUARD AND FIELD BALLISTA", Vector2(24, 12), 23)
	_label(sheet, "Previous field pieces", Vector2(24, 48), 16)
	_label(sheet, "Refined company  ·  shared canvas and ground anchor", Vector2(24, 282), 16)
	for column: int in 4:
		var role: String = MATERIAL_ROLES[column / 2]
		var owner: int = column % 2
		var filename: String = "%s%s.svg" % [role, "_enemy" if owner == 1 else ""]
		for row: int in 2:
			var source: String = _baseline.path_join(filename) if row == 0 else "res://assets/units/" + filename
			_expect(FileAccess.file_exists(source), "before/after source exists: " + source)
			if not FileAccess.file_exists(source): continue
			var picture := TextureRect.new()
			picture.texture = ImageTexture.create_from_image(_source_image(source))
			picture.flip_h = owner == 1
			picture.position = Vector2(28 + column * 224, 72 + row * 234)
			picture.size = Vector2(192, 192)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sheet.add_child(picture)
	await _capture("mounted-before-after.png")
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
	_label(overlay, "ACTUAL FIELD SCALE  /  SIX COMPANY ROLES", Vector2(18, 10), 17, KingdomTheme.INK_LIGHT)
	var caption: Label = _label(overlay, "", Vector2(18, 32), 13, KingdomTheme.INK_LIGHT)
	for phone: Vector2i in PHONES:
		_size(phone)
		for zoom: float in ZOOMS:
			_metrics.profiles.append({"viewport": [phone.x, phone.y], "zoom": zoom})
			caption.text = "Home above · opponent below · Worker / Warrior / Scout / Cavalry / Archer / Siege · zoom %.3f" % zoom
			camera.zoom = Vector2.ONE * zoom
			camera.reset_smoothing()
			camera.force_update_scroll()
			await _capture("roster-%dx%d-zoom%s.png" % [phone.x, phone.y, str(zoom)])
		caption.text = "Selected Horseman above · critical Ballista below · optional owner markers · normal zoom"
		camera.zoom = Vector2.ONE * 0.952
		camera.force_update_scroll()
		GameManager.clearer_player_markers = true
		units[3].is_selected = true
		units[3].stance = UnitBase.Stance.STAND_GROUND
		units[11].hp = units[11].max_hp * 0.25
		for unit: UnitBase in units:
			unit.queue_redraw()
		await _capture("feedback-%dx%d.png" % [phone.x, phone.y])
		GameManager.clearer_player_markers = false
		units[3].is_selected = false
		units[3].stance = UnitBase.Stance.AGGRESSIVE
		units[11].hp = units[11].max_hp
		for unit: UnitBase in units:
			unit.queue_redraw()
	_size(Vector2i(844, 390))
	camera.zoom = Vector2.ONE * 0.952
	camera.force_update_scroll()
	for offset: float in [-0.04, 0.04, 0.12]:
		caption.text = "POSE SAMPLE · %.2fs relative to existing release · no simulated damage" % offset
		for unit: UnitBase in units:
			if unit.damage <= 0.0 or unit.unit_type == UnitData.UnitType.VILLAGER: continue
			unit.current_state = UnitBase.State.ATTACKING
			var windup: float = float(UnitData.UNITS[unit.unit_type].get("attack_windup", 0.12))
			unit._attack_animation_duration = windup + 0.16
			unit._attack_animation_remaining = 0.16 - offset
			unit._attack_animation_direction = Vector2.RIGHT if unit.player_owner == 0 else Vector2.LEFT
			unit._update_sprite_motion(0.0)
		await _capture("release-offset%s.png" % str(offset))
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
	_metrics.render_counters.append({"capture": filename,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"texture_memory_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"process_seconds": Performance.get_monitor(Performance.TIME_PROCESS)})


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
