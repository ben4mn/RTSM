extends Node
## Presentation contracts against real imported artwork and canonical tile geometry.
## Native composition and phone readability are covered by the separate gallery.

var _failures: Array[String] = []
var _metrics: Array[Dictionary] = []
var _map: Node2D
var _selection: SelectionManager
var _placement: BuildingPlacement

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# The map's fallback projection is canonical and needs no generation here.
	_map = load("res://scripts/map/game_map.gd").new()
	_selection = SelectionManager.new()
	add_child(_selection)
	_placement = BuildingPlacement.new()
	add_child(_placement)
	for type: int in BuildingBase.BUILDING_SPRITES:
		_check_building(type)
	_check_resources()
	_check_owner_palettes()
	_map.free()
	var output: String = "res://output/polish-2026-10-22/proportions"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var report := FileAccess.open(output.path_join("geometry-contracts.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": _failures.is_empty(), "failures": _failures, "metrics": _metrics, "building_sha256": FileAccess.get_sha256("res://scripts/buildings/building_base.gd"), "resource_sha256": FileAccess.get_sha256("res://scripts/map/resource_node.gd")}, "\t") + "\n")
	for failure: String in _failures:
		push_error("[FAIL] world_proportions: " + failure)
	if _failures.is_empty():
		print("[PASS] world_proportions: ten building ground widths/anchors, matching ghosts, opaque facade targeting, unchanged collision, complete framing, four natural resource proportions, Farm/Tower owner alpha")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check_building(type: int) -> void:
	var building := BuildingBase.new()
	building.building_type = type
	building.position = Vector2(300, 200)
	add_child(building)
	building.complete_instantly()
	building.set_process(false)
	var name_text: String = building.building_name
	var sprite: Sprite2D = building.get_node("BuildingSprite")
	_expect(building.y_sort_enabled, name_text + " artwork sorts from its actual ground center")
	var texture_scale: Vector2 = sprite.texture.get_size() / Vector2(128, 128)
	_expect(sprite.texture.get_size() == Vector2(256, 256), name_text + " uses the 2x SVG import")
	_expect((sprite.scale * texture_scale).is_equal_approx(BuildingBase.BUILDING_SCALES[type]), name_text + " preserves authored world scale")
	var ink: Rect2i = sprite.texture.get_image().get_used_rect()
	var coverage: float = float(ink.size.x) * sprite.scale.x / (building.footprint.x * MapData.TILE_WIDTH)
	_expect(coverage >= 0.75 and coverage <= 0.96, name_text + " visible width leaves a modest ground margin inside reserved tiles")
	_metrics.append({"name": name_text, "source_ink": [ink.position.x, ink.position.y, ink.size.x, ink.size.y], "world_ink": [ink.size.x * sprite.scale.x, ink.size.y * sprite.scale.y], "ground_coverage": coverage, "footprint": [building.footprint.x, building.footprint.y], "visual_center": [sprite.position.x, sprite.position.y]})
	if type == BuildingData.BuildingType.WATCH_TOWER:
		_expect(ink.size.y * sprite.scale.y >= 130.0 and ink.size.y * sprite.scale.y <= 150.0, "Watch Tower stands above the lower House roof")
		_expect(24.0 * texture_scale.y * sprite.scale.y >= 26.0 and 24.0 * texture_scale.y * sprite.scale.y <= 32.0, "Watch Tower door remains comparable to a person")
	var first: Vector2 = _map.call("tile_to_world", Vector2i.ZERO)
	var last: Vector2 = _map.call("tile_to_world", building.footprint - Vector2i.ONE)
	var center: Vector2 = (last - first) * 0.5
	var source_ground: Vector2 = BuildingBase.BUILDING_GROUND_ANCHORS[type] * texture_scale
	_expect(sprite.to_global(sprite.get_rect().position + source_ground).is_equal_approx(building.global_position + center), name_text + " artwork base centered over its reserved tiles")
	_expect(building.position == Vector2(300, 200), name_text + " logical attack/path origin unchanged")
	var collision: CollisionShape2D = building.get_child(0)
	_expect((collision.shape as RectangleShape2D).size == Vector2(building.footprint.x * MapData.TILE_WIDTH, building.footprint.y * MapData.TILE_HEIGHT), name_text + " collision dimensions unchanged")
	var art_world: Rect2 = sprite.global_transform * Rect2(sprite.get_rect().position + Vector2(ink.position), Vector2(ink.size))
	_expect(building.get_visual_bounds(false).grow(0.01).encloses(art_world), name_text + " framing encloses imported visible artwork")
	var facade: Rect2 = _selection.call("_building_touch_facade_rect", sprite)
	_expect(_selection.call("_is_touch_on_building_facade", building, sprite.to_global(facade.get_center())), name_text + " visible facade remains selectable after transform")
	_expect(not _selection.call("_is_touch_on_building_facade", building, sprite.to_global(sprite.get_rect().position + Vector2(1, 1) * texture_scale)), name_text + " transparent upper corner is not a facade target")
	building.is_selected = true
	building.hp -= 1
	var bounds: Rect2 = building.get_visual_bounds()
	_metrics[-1]["art_top"] = art_world.position.y
	_metrics[-1]["selected_bounds_top"] = bounds.position.y
	_metrics[-1]["health_clearance"] = art_world.position.y - bounds.position.y
	var ground_size := Vector2(building.footprint.x * MapData.TILE_WIDTH, building.footprint.y * MapData.TILE_HEIGHT)
	_expect(bounds.grow(0.01).encloses(Rect2(building.global_position + center - ground_size * 0.5, ground_size)), name_text + " framing encloses correctly centered selection footprint")
	# Composing world transforms can differ by a few float32 ULPs from adding
	# the local health offset before the building transform. Match other bounds
	# checks' subpixel tolerance while still catching a visibly attached bar.
	_expect(bounds.position.y <= art_world.position.y - 8.0 + 0.01, name_text + " damaged health bar sits above artwork and in framing")
	_placement.current_building_type = type
	_placement.current_footprint = building.footprint
	_placement.call("_setup_ghost_sprite")
	var ghost: Sprite2D = _placement.get("_ghost_sprite")
	_expect(ghost.transform.is_equal_approx(sprite.transform) and ghost.offset == sprite.offset, name_text + " paid-placement ghost matches final visual geometry")
	_check_resolution_and_owner_swaps(building)
	building.free()

func _check_resolution_and_owner_swaps(building: BuildingBase) -> void:
	var sprite: Sprite2D = building._sprite
	var name_text: String = building.building_name
	var authored_points: Array[Vector2] = [Vector2.ZERO, Vector2(128, 128), BuildingBase.BUILDING_GROUND_ANCHORS[building.building_type]]
	var expected_world: Array[Vector2] = []
	for point: Vector2 in authored_points:
		expected_world.append(sprite.to_global(sprite.get_rect().position + point * (sprite.texture.get_size() / Vector2(128, 128))))
	var expected_fire: Vector2 = building._get_defensive_fire_position()
	# Simulate a cached 1x raster before a newly imported 2x owner texture.
	# Both paths must preserve the complete authored canvas, not just its center.
	var lower_resolution: Image = sprite.texture.get_image().duplicate()
	lower_resolution.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	sprite.texture = ImageTexture.create_from_image(lower_resolution)
	building.call("_refresh_sprite_geometry")
	for pass_index: int in 3:
		if pass_index > 0:
			building.player_owner = 2 - pass_index
			building.call("_update_sprite_appearance")
			_expect(sprite.texture.get_size() == Vector2(256, 256), name_text + " owner refresh restores the 2x imported texture")
			var source: String = FileAccess.get_file_as_string(sprite.texture.resource_path)
			_expect(source.contains('width="128"') and source.contains('height="128"') and source.contains('viewBox="0 0 128 128"'), name_text + " owner SVG preserves authored coordinates")
		var texture_scale: Vector2 = sprite.texture.get_size() / Vector2(128, 128)
		for index: int in authored_points.size():
			var actual_world: Vector2 = sprite.to_global(sprite.get_rect().position + authored_points[index] * texture_scale)
			_expect(actual_world.distance_to(expected_world[index]) < 0.001, name_text + " raster/owner change preserves authored world point %d" % index)
		_expect(building._get_defensive_fire_position().distance_to(expected_fire) < 0.001, name_text + " raster/owner change preserves fire attachment")
		var used: Rect2i = sprite.texture.get_image().get_used_rect()
		var actual_bounds: Rect2 = sprite.transform * Rect2(sprite.get_rect().position + Vector2(used.position), Vector2(used.size))
		_expect(building._sprite_visual_rect.is_equal_approx(actual_bounds) and is_equal_approx(building._visual_top, actual_bounds.position.y), name_text + " raster/owner refresh updates cached art bounds")


func _check_resources() -> void:
	var ranges := {"food": Vector2(18, 25), "wood": Vector2(60, 72), "gold": Vector2(30, 40), "stone": Vector2(28, 36)}
	for kind: String in ranges:
		var resource := ResourceNode.new()
		resource.resource_type = kind
		add_child(resource)
		var sprite: Sprite2D = resource.get_node("Sprite")
		var ink: Rect2i = sprite.texture.get_image().get_used_rect()
		var height: float = ink.size.y * sprite.scale.y
		_metrics.append({"name": kind, "source_ink": [ink.position.x, ink.position.y, ink.size.x, ink.size.y], "world_ink": [ink.size.x * sprite.scale.x, height]})
		var allowed: Vector2 = ranges[kind]
		_expect(height >= allowed.x and height <= allowed.y, kind + " world height has intended relationship to a 30px person")
		var lower_edge: float = (sprite.get_rect().position.y + ink.end.y) * sprite.scale.y
		_expect(lower_edge >= 0.0 and lower_edge <= 6.0, kind + " visible base stays on its harvest tile")
		var circle: CircleShape2D = (resource.get_child(0) as CollisionShape2D).shape
		_expect(circle.radius == 16.0 and resource.remaining == 300, kind + " stock and ground interaction radius unchanged")
		if kind == "wood":
			var canopy: Vector2 = sprite.to_global(sprite.get_rect().position + Vector2(64, 45))
			_expect(resource.is_sprite_body_hit(canopy), "tree canopy target follows enlarged and grounded artwork")
			_expect(not resource.is_sprite_body_hit(sprite.to_global(sprite.get_rect().position + Vector2(1, 1))), "tree transparent padding remains untargetable")
		resource.free()

func _check_owner_palettes() -> void:
	for type: int in [BuildingData.BuildingType.FARM, BuildingData.BuildingType.WATCH_TOWER]:
		var home: Image = load(BuildingBase.get_sprite_texture_path(type, 0)).get_image()
		var enemy: Image = load(BuildingBase.get_sprite_texture_path(type, 1)).get_image()
		var equal_alpha := true
		var changed: int = 0
		for y: int in home.get_height():
			for x: int in home.get_width():
				equal_alpha = equal_alpha and is_equal_approx(home.get_pixel(x, y).a, enemy.get_pixel(x, y).a)
				changed += int(home.get_pixel(x, y) != enemy.get_pixel(x, y))
		var raster_area_scale: float = float(home.get_width() * home.get_height()) / (128.0 * 128.0)
		var changed_authored_area: float = float(changed) / raster_area_scale
		_expect(equal_alpha and changed_authored_area > 0.0 and changed_authored_area < 500.0, BuildingData.get_building_name(type) + " ownership changes cloth while preserving neutral materials and alpha")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
