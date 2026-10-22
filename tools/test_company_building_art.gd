extends Node
## Native art/contract receipt. The village screenshots are synthetic visual
## fixtures, not paid-play evidence; paid placement is covered by existing tests.

const OUTPUT := "res://output/company-buildings-expansion-2026-10-22"
const TYPES: Array[int] = [BuildingData.BuildingType.TOWN_CENTER, BuildingData.BuildingType.HOUSE, BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.RESOURCE_CAMP, BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE]
const SCALES: Array[float] = [1.08, 0.45, 0.60, 0.45, 0.55, 0.55]
const FOOTPRINTS: Array[Vector2i] = [Vector2i(4, 4), Vector2i(2, 2), Vector2i(3, 3), Vector2i(2, 2), Vector2i(3, 3), Vector2i(3, 3)]
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.audio_enabled = false
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for page: int in 2:
		await _contracts_and_contact_sheet(page)
	if DisplayServer.get_name() != "headless":
		await _village_captures()
	for failure: String in _failures:
		push_error("[FAIL] company_building_art: " + failure)
	if _failures.is_empty():
		print("[PASS] company_building_art: six original imported building families, 128px canvas, unchanged scales/offsets/footprints/collision, home/enemy/construction appearance; native contact sheet and phone village captures when rendered")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _contracts_and_contact_sheet(page: int) -> void:
	get_window().size = Vector2i(932, 600)
	get_window().content_scale_size = Vector2i(932, 600)
	get_window().content_scale_factor = 1.0
	var sheet := Control.new()
	add_child(sheet)
	var background := ColorRect.new()
	background.color = Color("293b3a")
	background.size = Vector2(932, 600)
	sheet.add_child(background)
	_label(sheet, "COMPANY ARCHITECTURE", Vector2(28, 14), 26)
	_label(sheet, "Original SVGs · same 128px canvas and runtime geometry", Vector2(28, 49), 16)
	for index: int in range(page * 3, mini(TYPES.size(), page * 3 + 3)):
		var column: int = index % 3
		var kind: int = TYPES[index]
		var name_text: String = BuildingData.get_building_name(kind)
		_label(sheet, name_text.to_upper(), Vector2(50 + 300 * column, 83), 21)
		for owner: int in [0, 1]:
			var building := BuildingBase.new()
			building.building_type = kind
			building.player_owner = owner
			add_child(building)
			building.complete_instantly()
			building.set_process(false)
			building.visible = false
			var sprite: Sprite2D = building.get_node("BuildingSprite")
			_expect(sprite.texture != null and sprite.texture.resource_path.ends_with(".svg"), name_text + " uses imported SVG")
			_expect(sprite.texture.get_size() == Vector2(128, 128), name_text + " preserves 128px texture canvas")
			_expect(sprite.scale == Vector2.ONE * SCALES[index], name_text + " preserves runtime scale")
			_expect(building.footprint == FOOTPRINTS[index], name_text + " preserves gameplay footprint")
			_expect(sprite.offset == Vector2(0, -FOOTPRINTS[index].y * MapData.TILE_HEIGHT * 0.3), name_text + " preserves vertical anchor")
			var collision: CollisionShape2D = null
			for child: Node in building.get_children():
				if child is CollisionShape2D:
					collision = child
			_expect(collision != null and (collision.shape as RectangleShape2D).size == Vector2(FOOTPRINTS[index].x * MapData.TILE_WIDTH, FOOTPRINTS[index].y * MapData.TILE_HEIGHT), name_text + " preserves collision")
			var expected_tint: Color = Color.WHITE
			_expect(sprite.modulate == expected_tint, name_text + " retains neutral building materials")
			_expect(sprite.texture.resource_path.ends_with("_enemy.svg") == (owner == 1), name_text + " uses matching ownership palette")
			var home_image: Image = load(BuildingBase.get_sprite_texture_path(kind, 0)).get_image()
			var enemy_image: Image = load(BuildingBase.get_sprite_texture_path(kind, 1)).get_image()
			var alpha_equal := true
			for y: int in 128:
				for x: int in 128:
					alpha_equal = alpha_equal and is_equal_approx(home_image.get_pixel(x, y).a, enemy_image.get_pixel(x, y).a)
			_expect(alpha_equal, name_text + " home/enemy palettes retain identical silhouette alpha")
			var picture := TextureRect.new()
			picture.texture = sprite.texture
			picture.position = Vector2(50 + 300 * column, 112 + 205 * owner)
			picture.size = Vector2(192, 192)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.modulate = sprite.modulate
			sheet.add_child(picture)
			_label(sheet, "HOME" if owner == 0 else "ENEMY · clay roof, neutral walls", Vector2(50 + 300 * column, 290 + 205 * owner), 14)
			building.player_owner = 1 - owner
			building.call("_update_sprite_appearance")
			_expect(sprite.texture.resource_path.ends_with("_enemy.svg") == (building.player_owner == 1), name_text + " refreshes cached texture after late owner assignment")
			building.state = BuildingBase.State.CONSTRUCTING
			building.build_progress = 0.5
			building.call("_update_sprite_appearance")
			_expect(sprite.modulate.a > 0.4 and sprite.modulate.a < 1.0, name_text + " retains construction fade")
			building.free()
	_label(sheet, "VISUAL FIXTURE · enlarged for material/ownership review; phone captures use real world scale", Vector2(28, 560), 14)
	await _frames(4)
	await _capture("building-materials-and-ownership-%d.png" % page)
	sheet.free()

func _village_captures() -> void:
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		get_window().size = phone
		get_window().content_scale_size = Vector2i(844, 390)
		get_window().content_scale_factor = 1.0
		GameManager.ui_scale = 1.0
		GameManager.set_state(GameManager.GameState.MENU)
		var main: Node = load("res://scenes/main/main.tscn").instantiate()
		add_child(main)
		for frame: int in 900:
			if main.get("_building_placement") != null:
				break
			await get_tree().process_frame
		var map: Node2D = main.get("game_map")
		var tc: BuildingBase = main.get("_player_town_center")
		var home: Vector2i = map.map_generator.spawn_positions[0]
		var camp: BuildingBase = _visual_building(main, BuildingData.BuildingType.RESOURCE_CAMP, home + Vector2i(4, -1))
		var archery: BuildingBase = _visual_building(main, BuildingData.BuildingType.ARCHERY_RANGE, home + Vector2i(7, -4))
		var stable: BuildingBase = _visual_building(main, BuildingData.BuildingType.STABLE, home + Vector2i(8, -8))
		_expect(camp != null and archery != null and stable != null, "village visual fixture found legal foundations")
		main.call("_update_fog_of_war")
		main.call("_select_town_center")
		main.process_mode = Node.PROCESS_MODE_DISABLED
		for zoom: float in [0.952, 1.6]:
			map.camera.zoom = Vector2.ONE * zoom
			map.camera.position = tc.global_position + (Vector2(220, -10) if zoom < 1.0 else Vector2(340, 40))
			map.camera.reset_smoothing()
			map.camera.force_update_scroll()
			await _frames(4)
			await _capture("village-%dx%d-zoom%s.png" % [phone.x, phone.y, str(zoom)])
		main.free()
		GameManager.set_state(GameManager.GameState.MENU)
		await _frames(2)

func _visual_building(main: Node, kind: int, anchor: Vector2i) -> BuildingBase:
	var map: Node2D = main.get("game_map")
	var footprint: Vector2i = BuildingData.get_building_stats(kind).get("footprint", Vector2i.ONE)
	for radius: int in range(0, 12):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var tile := anchor + Vector2i(dx, dy)
				var valid := true
				for y: int in footprint.y:
					for x: int in footprint.x:
						valid = valid and map.is_tile_buildable(tile + Vector2i(x, y))
				if valid:
					var building: BuildingBase = main.call("_spawn_building", kind, 0, tile)
					building.complete_instantly()
					return building
	return null

func _label(parent: Node, value: String, position: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = position
	label.add_theme_font_override("font", KingdomTheme.FONT_HEADING if font_size > 18 else KingdomTheme.FONT_BODY)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", KingdomTheme.PARCHMENT)
	parent.add_child(label)

func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame

func _capture(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(filename))

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
