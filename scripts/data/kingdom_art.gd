class_name KingdomArt
extends RefCounted
## Presentation-only catalog. Civilization selects the miniature's equipment and
## architecture; local ownership is shown separately by field markers.

const ROOT := "res://assets/kingdoms/"
const CIVILIZATIONS: Array[String] = ["crownlands", "verdant", "sunstride"]
const UNIT_NAMES: Array[String] = ["villager", "warrior", "archer", "cavalry", "scout", "siege"]
const BUILDING_NAMES: Dictionary = {0: "town_center", 1: "house", 2: "barracks", 3: "archery_range", 4: "stable", 5: "farm", 6: "resource_camp", 8: "siege_workshop", 9: "blacksmith", 10: "watch_tower"}
const UNIT_HEIGHTS: Array[float] = [31.0, 33.0, 32.0, 44.0, 40.0, 43.0]
const UNIT_WIDTHS: Array[float] = [28.0, 30.0, 29.0, 47.0, 44.0, 55.0]
const BUILDING_HEIGHTS: Dictionary = {0: 170.0, 1: 95.0, 2: 114.0, 3: 105.0, 4: 108.0, 5: 52.0, 6: 82.0, 8: 112.0, 9: 100.0, 10: 145.0}
static var _available: Dictionary = {}
static var _ink_cache: Dictionary = {}


static func _path(civilization: int, family: String, kind: String) -> String:
	var civilization_name: String = CIVILIZATIONS[clampi(civilization, 0, CIVILIZATIONS.size() - 1)]
	var path: String = ROOT + civilization_name + "/" + family + "_" + kind + ".tres"
	if not _available.has(path):
		_available[path] = ResourceLoader.exists(ROOT + civilization_name + "_" + ("units" if family == "unit" else "buildings") + ".png") and ResourceLoader.exists(path)
	return path if bool(_available[path]) else ""


static func unit_path(civilization: int, unit_type: int) -> String:
	return _path(civilization, "unit", UNIT_NAMES[unit_type]) if unit_type >= 0 and unit_type < UNIT_NAMES.size() else ""


static func building_path(civilization: int, building_type: int) -> String:
	return _path(civilization, "building", str(BUILDING_NAMES[building_type])) if BUILDING_NAMES.has(building_type) else ""


static func is_kingdom_texture(texture: Texture2D) -> bool:
	return texture != null and texture.resource_path.begins_with(ROOT)


static func ink_rect(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var key: String = texture.resource_path
	if key.is_empty():
		key = str(texture.get_instance_id())
	if not _ink_cache.has(key):
		var image: Image = texture.get_image()
		_ink_cache[key] = Rect2(image.get_used_rect()) if image != null else Rect2(Vector2.ZERO, texture.get_size())
	return _ink_cache[key]


static func configure_unit(sprite: Sprite2D, unit_type: int) -> void:
	var ink: Rect2 = ink_rect(sprite.texture)
	if not ink.has_area():
		return
	var kind: int = clampi(unit_type, 0, UNIT_NAMES.size() - 1)
	var factor: float = minf(UNIT_HEIGHTS[kind] / ink.size.y, UNIT_WIDTHS[kind] / ink.size.x)
	sprite.scale = Vector2.ONE * factor
	# Bottom-center is the foot/contact anchor. The small shadow stays grounded.
	var foot := Vector2(ink.get_center().x, ink.end.y - ink.size.y * 0.025)
	sprite.offset = sprite.texture.get_size() * 0.5 - foot


static func configure_building(sprite: Sprite2D, building_type: int, footprint: Vector2i) -> void:
	var ink: Rect2 = ink_rect(sprite.texture)
	if not ink.has_area():
		return
	var target_width: float = float(footprint.x) * MapData.TILE_WIDTH * 0.86
	var factor: float = minf(target_width / ink.size.x, float(BUILDING_HEIGHTS.get(building_type, 110.0)) / ink.size.y)
	sprite.scale = Vector2.ONE * factor
	# Isometric ground-center sits above the platform's front point. The
	# logical building origin, reserved cells and collision never move.
	var ground := Vector2(ink.get_center().x, ink.end.y - minf(ink.size.x * 0.20, ink.size.y * 0.45))
	sprite.offset = sprite.texture.get_size() * 0.5 - ground


static func vertical_uv_range(texture: Texture2D) -> Vector2:
	var ink: Rect2 = ink_rect(texture)
	if texture is AtlasTexture:
		var atlas_texture := texture as AtlasTexture
		return Vector2(atlas_texture.region.position.y + ink.position.y, atlas_texture.region.position.y + ink.end.y) / atlas_texture.atlas.get_height()
	return Vector2(ink.position.y, ink.end.y) / texture.get_height()
