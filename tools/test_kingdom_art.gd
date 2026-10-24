extends Node
## Real-resource presentation regression. No combat or economy balance is changed.

var failures: Array[String] = []
var checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager: Node = get_tree().root.get_node("GameManager")
	get_tree().root.get_node("AudioManager").set_all_enabled(false)
	manager.players.clear()
	manager.current_state = 0
	for civilization: int in 3:
		manager.selected_civilization = civilization
		manager.selected_opponent_civilization = (civilization + 1) % 3
		for owner: int in 2:
			var expected_civilization: int = civilization if owner == 0 else (civilization + 1) % 3
			for kind: int in 6:
				_check_unit(kind, owner, expected_civilization)
			for kind: int in KingdomArt.BUILDING_NAMES:
				_check_building(kind, owner, expected_civilization)
	# Changing next-match preferences must not change latched active identities.
	manager.players = {0: {"civilization": 1}, 1: {"civilization": 2}}
	manager.current_state = 2
	manager.selected_civilization = 0
	manager.selected_opponent_civilization = 0
	_check(UnitData.get_unit_icon_path(2, 0) == KingdomArt.unit_path(1, 2), "Active Verdant archer keeps its latched Longbow artwork")
	_check(BuildingBase.get_sprite_texture_path(0, 1) == KingdomArt.building_path(2, 0), "Active Sunstride rival keeps its latched Town Center artwork")
	for failure: String in failures:
		push_error("[FAIL] kingdom_art: " + failure)
	if failures.is_empty():
		print("[PASS] kingdom_art: %d checks; all 48 sprites, actual units/buildings, civ ownership mapping, footprints, grounded scale, matching placement ghosts and atlas construction UVs" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_unit(kind: int, owner: int, civilization: int) -> void:
	var expected_path: String = KingdomArt.unit_path(civilization, kind)
	_check(not expected_path.is_empty(), "Unit atlas resource exists for %d/%d" % [civilization, kind])
	if expected_path.is_empty():
		return
	_check(UnitData.get_unit_icon_path(kind, owner) == expected_path, "Recruitment resolves actual player civilization")
	var unit: UnitBase = load("res://scenes/units/unit_base.tscn").instantiate()
	unit.unit_type = kind
	unit.player_owner = owner
	get_tree().root.add_child(unit)
	unit.set_process(false)
	var sprite: Sprite2D = unit.get_node("UnitSprite")
	_check(sprite.texture.resource_path == expected_path, "World and recruitment use the same unit art")
	var ink: Rect2 = KingdomArt.ink_rect(sprite.texture)
	_check(ink.has_area(), "Unit texture has visible alpha")
	var foot: Vector2 = sprite.get_rect().position + Vector2(ink.get_center().x, ink.end.y - ink.size.y * 0.025)
	_check((foot * sprite.scale).length() < 0.01, "Unit contact anchor stays on its logical origin")
	_check(ink.size.y * sprite.scale.y <= KingdomArt.UNIT_HEIGHTS[kind] + 0.01, "Unit fits its role's world height")
	_check(ink.size.y * sprite.scale.y >= 15.0, "Unit remains readable at world scale")
	_check(is_equal_approx(sprite.scale.x, sprite.scale.y), "Miniature proportions are not stretched")
	var shape: CircleShape2D = unit.get_node("CollisionShape2D").shape
	_check(is_equal_approx(shape.radius, UnitBase.UNIT_SIZES[kind]), "Artwork does not change unit collision")
	_check(is_equal_approx(unit.max_hp, float(UnitData.get_unit_stats(kind, owner).hp)), "Artwork preserves civilization unit stats")
	_check(sprite.modulate == Color.WHITE, "Neutral materials are not tinted by ownership")
	unit.free()


func _check_building(kind: int, owner: int, civilization: int) -> void:
	var expected_path: String = KingdomArt.building_path(civilization, kind)
	_check(not expected_path.is_empty(), "Building atlas resource exists for %d/%d" % [civilization, kind])
	if expected_path.is_empty():
		return
	_check(BuildingBase.get_sprite_texture_path(kind, owner) == expected_path, "Building resolves actual player civilization")
	var building := BuildingBase.new()
	building.building_type = kind
	building.player_owner = owner
	building.state = BuildingBase.State.ACTIVE
	get_tree().root.add_child(building)
	building.set_process(false)
	var sprite: Sprite2D = building.get_node("BuildingSprite")
	_check(sprite.texture.resource_path == expected_path, "World uses the resolved building texture")
	var ink: Rect2 = KingdomArt.ink_rect(sprite.texture)
	_check(ink.has_area(), "Building texture has visible alpha")
	_check(is_equal_approx(sprite.scale.x, sprite.scale.y), "Building proportions are not stretched")
	_check(ink.size.x * sprite.scale.x <= building.footprint.x * MapData.TILE_WIDTH * 0.87, "Building art stays inside reserved ground width")
	_check(ink.size.y * sprite.scale.y <= float(KingdomArt.BUILDING_HEIGHTS[kind]) + 0.01, "Building stays within its readable height")
	var shape: RectangleShape2D = building.get_child(0).shape
	_check(shape.size == Vector2(building.footprint.x * MapData.TILE_WIDTH, building.footprint.y * MapData.TILE_HEIGHT), "Artwork does not alter reserved building collision")
	_check(building.max_hp == int(BuildingData.get_building_stats(kind, owner).hp), "Artwork preserves civilization building stats")
	_check(sprite.modulate == Color.WHITE, "Stone and crops retain neutral materials")
	var ghost := Sprite2D.new()
	ghost.texture = load(expected_path)
	BuildingBase.configure_art_sprite(ghost, kind, building.footprint)
	_check(ghost.scale.is_equal_approx(sprite.scale) and ghost.offset.is_equal_approx(sprite.offset), "Placement preview and completed building agree in scale and anchor")
	ghost.free()
	building.state = BuildingBase.State.CONSTRUCTING
	building.build_progress = 0.4
	building._update_sprite_appearance()
	var material: ShaderMaterial = sprite.material
	var uv_range: Vector2 = KingdomArt.vertical_uv_range(sprite.texture)
	_check(uv_range.x >= 0.0 and uv_range.x < uv_range.y and uv_range.y <= 1.0, "Construction reveal remains inside its own atlas row")
	_check(is_equal_approx(float(material.get_shader_parameter("ink_top")), uv_range.x) and is_equal_approx(float(material.get_shader_parameter("ink_bottom")), uv_range.y), "Construction material uses atlas UV bounds")
	building.free()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
