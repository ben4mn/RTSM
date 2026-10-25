class_name BuildingBase
extends Area2D
## Base building for all structures in AOEM.
## Handles construction progress, health, selection, and sprite-based rendering.

signal construction_complete(building: BuildingBase)
signal building_destroyed(building: BuildingBase)
signal building_selected(building: BuildingBase)
signal building_deselected(building: BuildingBase)
signal health_changed(current: int, maximum: int)
signal damage_received(building: BuildingBase, hp_loss: int)
signal defensive_attack_fired(target: Node2D)

enum State { PLACING, CONSTRUCTING, ACTIVE, DESTROYED }

@export var building_type: int = BuildingData.BuildingType.HOUSE
@export var player_owner: int = 0

var state: int = State.PLACING
var hp: int = 0
var max_hp: int = 500
var build_progress: float = 0.0
var build_time: float = 15.0
var pop_provided: int = 0
var building_name: String = ""
var footprint: Vector2i = Vector2i(2, 2)
var drop_off_resources: Array = []
var trainable_units: Array = []
var building_color: Color = Color(0.6, 0.45, 0.3)
var provides_food: bool = false
var _assigned_farmer_ref: WeakRef = null

var rally_point: Vector2 = Vector2.ZERO
var rally_point_is_custom: bool = false
var rally_resource_type: String = ""
var rally_resource_instance_id: int = 0
var rally_resource_is_building: bool = false
var is_selected: bool = false
var _production_queue: Node = null
var _sprite: Sprite2D = null
var _ownership_marker: Node2D = null
var _ownership_marker_owner: int = -1
var _defensive_flash: Node2D = null
var _footprint_center: Vector2 = Vector2.ZERO
var _sprite_visual_rect: Rect2 = Rect2()
var _visual_top: float = -48.0
var _construction_dust_timer: float = 0.0
var _damage_smoke_timer: float = 0.0
var _construction_frame: ConstructionFrame = null
var _construction_material: ShaderMaterial = null
var _damage_flash_tween: Tween = null

const CONSTRUCTION_REVEAL_SHADER: Shader = preload("res://assets/buildings/construction_reveal.gdshader")
const DAMAGE_FLASH_COLOR := Color(1.0, 0.69, 0.50)
const DAMAGE_FLASH_SECONDS: float = 0.18


## A temporary timber surround, attached at the same ground sort point as the
## building sprite. Completed buildings have no extra material or frame node.
class ConstructionFrame extends Node2D:
	var half_width: float = 40.0
	var half_depth: float = 20.0
	var full_height: float = 64.0
	var stage: int = -1

	func get_frame_bounds() -> Rect2:
		return Rect2(-half_width - 4.0, -full_height - 4.0, half_width * 2.0 + 8.0, full_height + half_depth + 8.0)

	func _draw() -> void:
		var left := Vector2(-half_width, 0.0)
		var front := Vector2(0.0, half_depth)
		var right := Vector2(half_width, 0.0)
		var height: float = 12.0 if stage == 0 else full_height * 0.65 if stage == 1 else full_height
		var rise := Vector2(0.0, -height)
		var outline := Color("4b4b39")
		var wood := Color("b7a078")
		var lit_edge := Color("dcc8a0")
		for foot: Vector2 in [left, front, right]:
			draw_line(foot + Vector2(-4.0, 1.0), foot + Vector2(4.0, -1.0), outline, 4.0, true)
			draw_line(foot, foot + rise, outline, 5.0, true)
			draw_line(foot, foot + rise, wood, 2.6, true)
			draw_line(foot + Vector2(-0.8, -1.0), foot + rise, lit_edge, 0.8, true)
		for edge: Vector2 in [left, right]:
			draw_line(edge + rise, front + rise, outline, 5.0, true)
			draw_line(edge + rise, front + rise, wood, 2.6, true)
			if stage > 0:
				draw_line(edge + rise * 0.2, front + rise * 0.85, outline, 3.2, true)
				draw_line(edge + rise * 0.2, front + rise * 0.85, wood, 1.8, true)
		for foot: Vector2 in [left, front, right]:
			draw_line(foot + rise + Vector2(-2.5, 1.0), foot + rise + Vector2(2.5, -1.0), lit_edge, 1.2, true)

# Defensive building weapons. Names preserve the existing tower damage API.
var tower_attack_damage: int = 0
var tower_attack_range: float = 0.0  # Runtime world units; data is range tiles.
var tower_attack_interval: float = 1.5
var tower_attack_projectile_speed: float = 0.0
var tower_attack_buildings: bool = true
var _tower_attack_cooldown: float = 0.0
var _defensive_shot_flash_remaining: float = 0.0
const DEFENSIVE_TARGET_SCAN_INTERVAL: float = 0.2
# Authored 128px coordinates: Town Center lookout window and Watch Tower rampart.
# These attach presentation to the art; weapon range stays at the ground origin.
const DEFENSIVE_FIRE_POINTS: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: Vector2(101, 72),
	BuildingData.BuildingType.WATCH_TOWER: Vector2(64, 21),
}


class DefensiveArrow extends Node2D:
	var defender_ref: WeakRef
	var visibility_map_ref: WeakRef
	var final_damage: float = 0.0
	var start_position: Vector2
	var elapsed: float = 0.0
	var flight_seconds: float = 0.2
	var finished: bool = false
	var _heading: Vector2 = Vector2.RIGHT

	func _process(delta: float) -> void:
		advance_projectile(delta)

	func advance_projectile(delta: float) -> void:
		if finished:
			return
		var defender: UnitBase = defender_ref.get_ref() as UnitBase
		if not is_instance_valid(defender) or defender.current_state == UnitBase.State.DEAD:
			finished = true
			queue_free()
			return
		elapsed += delta
		var phase: float = minf(1.0, elapsed / flight_seconds)
		var previous: Vector2 = global_position
		global_position = start_position.lerp(defender.global_position + Vector2(0.0, -16.0), phase)
		global_position.y -= sin(phase * PI) * 12.0
		_heading = (global_position - previous).normalized()
		# Flight can finish after a target leaves vision; its rendering never
		# reveals that target or an unseen enemy Town Center to the human.
		var visibility_map: Node2D = visibility_map_ref.get_ref() as Node2D if visibility_map_ref != null else null
		if is_instance_valid(visibility_map):
			visible = bool(visibility_map.call("is_entity_visible_to_player", self, 0))
		else:
			visible = defender.visible
		queue_redraw()
		if phase >= 1.0:
			finished = true
			defender.take_damage(final_damage)
			if get_tree().current_scene != null and defender.visible:
				VFX.hit_burst(get_tree(), defender.global_position + Vector2(0.0, -14.0), Color(0.92, 0.78, 0.42))
			queue_free()

	func _draw() -> void:
		draw_line(-_heading * 10.0, _heading * 4.0, Color(1.0, 0.86, 0.48), 2.4, true)
		var normal := Vector2(-_heading.y, _heading.x)
		draw_colored_polygon(PackedVector2Array([
			_heading * 6.0, normal * 2.5, -normal * 2.5
		]), Color(1.0, 0.98, 0.80))

## Original Company SVGs for civic, military and farming buildings.
const BUILDING_SPRITES: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: "res://assets/buildings/company_town_center.svg",
	BuildingData.BuildingType.HOUSE: "res://assets/buildings/company_house.svg",
	BuildingData.BuildingType.BARRACKS: "res://assets/buildings/company_barracks.svg",
	BuildingData.BuildingType.ARCHERY_RANGE: "res://assets/buildings/company_archery_range.svg",
	BuildingData.BuildingType.STABLE: "res://assets/buildings/company_stable.svg",
	BuildingData.BuildingType.FARM: "res://assets/buildings/farm.svg",
	BuildingData.BuildingType.RESOURCE_CAMP: "res://assets/buildings/company_resource_camp.svg",
	BuildingData.BuildingType.SIEGE_WORKSHOP: "res://assets/buildings/company_siege_workshop.svg",
	BuildingData.BuildingType.BLACKSMITH: "res://assets/buildings/company_blacksmith.svg",
	BuildingData.BuildingType.WATCH_TOWER: "res://assets/buildings/watch_tower.svg",
}

## Company roofs/cloth carry ownership while bone, timber and stone remain neutral.
## Every family keeps neutral timber, crops and masonry for both owners.
const COMPANY_ENEMY_SPRITES: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: "res://assets/buildings/company_town_center_enemy.svg",
	BuildingData.BuildingType.HOUSE: "res://assets/buildings/company_house_enemy.svg",
	BuildingData.BuildingType.BARRACKS: "res://assets/buildings/company_barracks_enemy.svg",
	BuildingData.BuildingType.ARCHERY_RANGE: "res://assets/buildings/company_archery_range_enemy.svg",
	BuildingData.BuildingType.STABLE: "res://assets/buildings/company_stable_enemy.svg",
	BuildingData.BuildingType.RESOURCE_CAMP: "res://assets/buildings/company_resource_camp_enemy.svg",
	BuildingData.BuildingType.SIEGE_WORKSHOP: "res://assets/buildings/company_siege_workshop_enemy.svg",
	BuildingData.BuildingType.BLACKSMITH: "res://assets/buildings/company_blacksmith_enemy.svg",
	BuildingData.BuildingType.FARM: "res://assets/buildings/farm_enemy.svg",
	BuildingData.BuildingType.WATCH_TOWER: "res://assets/buildings/watch_tower_enemy.svg",
}


static func get_sprite_texture_path(type: int, owner: int = 0) -> String:
	var miniature_path: String = KingdomArt.building_path(CivilizationData.for_player(owner), type)
	if not miniature_path.is_empty():
		return miniature_path
	if owner != 0 and COMPANY_ENEMY_SPRITES.has(type):
		return COMPANY_ENEMY_SPRITES[type]
	return BUILDING_SPRITES.get(type, "")


const ART_AUTHORED_SIZE := Vector2(128, 128)


## Calibrated against visible artwork, not the padded 128px canvas.
## Broad, lower rooflines keep 28–30px people readable beside architecture.
## The reserved footprint includes open ground around the visible structure.
const BUILDING_SCALES: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: Vector2(1.70, 1.60),
	BuildingData.BuildingType.HOUSE: Vector2(1.00, 0.96),
	BuildingData.BuildingType.BARRACKS: Vector2(1.48, 1.40),
	BuildingData.BuildingType.ARCHERY_RANGE: Vector2(1.35, 1.28),
	BuildingData.BuildingType.STABLE: Vector2(1.35, 1.28),
	BuildingData.BuildingType.FARM: Vector2(1.0, 1.0),
	BuildingData.BuildingType.RESOURCE_CAMP: Vector2(0.90, 0.86),
	BuildingData.BuildingType.SIEGE_WORKSHOP: Vector2(1.32, 1.25),
	BuildingData.BuildingType.BLACKSMITH: Vector2(0.92, 0.88),
	BuildingData.BuildingType.WATCH_TOWER: Vector2(1.12, 1.12),
}

## Source-space center of each ground platform (including transparent padding).
const BUILDING_GROUND_ANCHORS: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: Vector2(64, 104),
	BuildingData.BuildingType.HOUSE: Vector2(65, 104),
	BuildingData.BuildingType.BARRACKS: Vector2(65, 70),
	BuildingData.BuildingType.ARCHERY_RANGE: Vector2(64, 100),
	BuildingData.BuildingType.STABLE: Vector2(64, 98),
	BuildingData.BuildingType.FARM: Vector2(64, 86),
	BuildingData.BuildingType.RESOURCE_CAMP: Vector2(64, 92),
	BuildingData.BuildingType.SIEGE_WORKSHOP: Vector2(64, 99),
	BuildingData.BuildingType.BLACKSMITH: Vector2(64, 100),
	BuildingData.BuildingType.WATCH_TOWER: Vector2(64, 116),
}

const DROP_OFF_BADGE_COLORS: Dictionary = {
	"food": Color("bd8067"),
	"wood": Color("88a58b"),
	"gold": Color("c4af77"),
}


func _ready() -> void:
	_load_stats()
	_setup_collision()
	_setup_sprite()
	rally_point = global_position + Vector2(footprint.x * MapData.TILE_WIDTH, 0)
	rally_point_is_custom = false
	add_to_group("buildings")
	add_to_group("player_%d_buildings" % player_owner)
	if drop_off_resources.size() > 0:
		add_to_group("dropoff_buildings")
	if provides_food:
		add_to_group("food_resources")
		# Farms share the same input-discovery group as natural resources.  Their
		# construction, ownership, and depletion rules are enforced by
		# is_harvestable_by(), rather than by adding/removing the group repeatedly.
		add_to_group("resources")
	if state == State.ACTIVE:
		hp = max_hp
		build_progress = 1.0


func _load_stats() -> void:
	var stats: Dictionary = BuildingData.get_building_stats(building_type, player_owner)
	if stats.is_empty():
		return
	max_hp = stats.get("hp", 500)
	build_time = stats.get("build_time", 15.0)
	pop_provided = stats.get("pop_provided", 0)
	building_name = stats.get("name", "Building")
	footprint = stats.get("footprint", Vector2i(2, 2))
	drop_off_resources = stats.get("drop_off", [])
	trainable_units = stats.get("can_train", [])
	building_color = stats.get("color", Color(0.6, 0.45, 0.3))
	provides_food = stats.get("provides_food", false)
	tower_attack_damage = stats.get("attack_damage", 0)
	tower_attack_range = MapData.range_tiles_to_world(float(stats.get("attack_range", 0)))
	tower_attack_interval = maxf(0.1, float(stats.get("attack_interval", 1.5)))
	tower_attack_projectile_speed = maxf(0.0, float(stats.get("attack_projectile_speed", 0.0)))
	tower_attack_buildings = bool(stats.get("attack_buildings", true))


func _setup_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var pixel_w: float = footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = footprint.y * MapData.TILE_HEIGHT
	rect.size = Vector2(pixel_w, pixel_h)
	shape.shape = rect
	add_child(shape)


func _setup_sprite() -> void:
	# Let the centered ground anchor participate in GameMap's shared depth sort.
	# Sorting the whole building at its first tile draws upper-side workers over roofs.
	y_sort_enabled = true
	_sprite = Sprite2D.new()
	_sprite.name = "BuildingSprite"
	var tex_path: String = get_sprite_texture_path(building_type, player_owner)
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_sprite.texture = load(tex_path)
	# The node stays at the first reserved tile. Only presentation moves to the
	# center of that tile rectangle; pathfinding and attack origins do not move.
	var map_node: Node = get_parent()
	while map_node != null and not map_node.has_method("tile_to_world"):
		map_node = map_node.get_parent()
	_footprint_center = get_footprint_center_offset(footprint, map_node)
	_sprite.position = _footprint_center
	add_child(_sprite)
	_refresh_sprite_geometry()
	_ownership_marker = Node2D.new()
	_ownership_marker.name = "OwnershipPennant"
	_ownership_marker.z_index = 1
	_ownership_marker.draw.connect(_draw_ownership_pennant)
	add_child(_ownership_marker)
	_update_sprite_appearance()
	if tower_attack_damage > 0:
		_defensive_flash = Node2D.new()
		_defensive_flash.name = "DefensiveShotFlash"
		_defensive_flash.z_index = 1
		_defensive_flash.draw.connect(_draw_defensive_shot_flash)
		add_child(_defensive_flash)


static func get_art_texture_scale(texture: Texture2D) -> Vector2:
	# SVG import resolution is independent of authored proportions and anchors.
	return texture.get_size() / ART_AUTHORED_SIZE if texture != null else Vector2.ONE


func _refresh_sprite_geometry() -> void:
	configure_art_sprite(_sprite, building_type, footprint)
	if _sprite.texture != null:
		var ink: Rect2 = KingdomArt.ink_rect(_sprite.texture)
		_sprite_visual_rect = _sprite.transform * Rect2(_sprite.get_rect().position + Vector2(ink.position), Vector2(ink.size))
		_visual_top = _sprite_visual_rect.position.y


static func configure_art_sprite(sprite: Sprite2D, type: int, size_in_tiles: Vector2i) -> void:
	if KingdomArt.is_kingdom_texture(sprite.texture):
		KingdomArt.configure_building(sprite, type, size_in_tiles)
		return
	var texture_scale: Vector2 = get_art_texture_scale(sprite.texture)
	sprite.scale = BUILDING_SCALES.get(type, Vector2(0.4, 0.4)) / texture_scale
	sprite.offset = get_sprite_offset(type, size_in_tiles) * texture_scale


static func get_sprite_offset(type: int, _size_in_tiles: Vector2i) -> Vector2:
	return Vector2(64, 64) - BUILDING_GROUND_ANCHORS.get(type, Vector2(64, 104))


static func get_footprint_center_offset(size_in_tiles: Vector2i, map_node: Node = null) -> Vector2:
	# Use the same projection as terrain. Standalone art fixtures have no map,
	# so a short-lived GameMap supplies its canonical fallback conversion.
	var projection: Node = map_node
	var owns_projection: bool = projection == null or not projection.has_method("tile_to_world")
	if owns_projection:
		projection = load("res://scripts/map/game_map.gd").new()
	var first: Vector2 = projection.call("tile_to_world", Vector2i.ZERO)
	var last: Vector2 = projection.call("tile_to_world", size_in_tiles - Vector2i.ONE)
	if owns_projection:
		projection.free()
	return (last - first) * 0.5


func get_visual_bounds(include_ground: bool = true) -> Rect2:
	var bounds: Rect2 = _sprite_visual_rect
	if is_instance_valid(_construction_frame):
		bounds = bounds.merge(_construction_frame.transform * _construction_frame.get_frame_bounds())
	if include_ground and is_selected:
		var ground_size := Vector2(footprint.x * MapData.TILE_WIDTH, footprint.y * MapData.TILE_HEIGHT)
		bounds = bounds.merge(Rect2(_footprint_center - ground_size * 0.5, ground_size).grow(2.0))
	if state == State.CONSTRUCTING or (state == State.ACTIVE and hp < max_hp):
		var bar_width: float = footprint.x * MapData.TILE_WIDTH * 0.6
		bounds = bounds.merge(Rect2(_footprint_center.x - bar_width * 0.5, _visual_top - 8.0, bar_width, 4.0))
	if not drop_off_resources.is_empty() and (building_type != BuildingData.BuildingType.TOWN_CENTER or is_selected):
		bounds = bounds.merge(Rect2(_footprint_center.x - footprint.x * MapData.TILE_WIDTH * 0.28 - 7.0, _visual_top - 28.0, (drop_off_resources.size() - 1) * 16.0 + 14.0, 14.0))
	return global_transform * bounds


func _update_sprite_appearance() -> void:
	if _sprite == null:
		return
	# Snapshot replicas set owner/type before entering the tree; the refresh also
	# handles a later owner assignment without retaining a cached home texture.
	var texture_path: String = get_sprite_texture_path(building_type, player_owner)
	if _sprite.texture != null and _sprite.texture.resource_path != texture_path and ResourceLoader.exists(texture_path):
		_sprite.texture = load(texture_path)
		_refresh_sprite_geometry()
	var legacy_enemy_tint: bool = player_owner != 0 and not COMPANY_ENEMY_SPRITES.has(building_type) and not KingdomArt.is_kingdom_texture(_sprite.texture)
	if _ownership_marker != null:
		_ownership_marker.visible = KingdomArt.is_kingdom_texture(_sprite.texture)
		if _ownership_marker_owner != player_owner:
			_ownership_marker_owner = player_owner
			_ownership_marker.queue_redraw()
	var base_color: Color = Color(1.0, 0.55, 0.55) if legacy_enemy_tint else Color.WHITE
	match state:
		State.CONSTRUCTING:
			# Earlier work stays subdued; it grows clearer toward completion.
			# A separate reveal material shows where the structure is built.
			var progress_alpha := lerpf(0.4, 1.0, build_progress)
			var progress_dark := lerpf(0.18, 0.0, build_progress)
			_sprite.modulate = Color(base_color.r - progress_dark, base_color.g - progress_dark, base_color.b - progress_dark, progress_alpha)
		State.DESTROYED:
			_sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)
		State.ACTIVE:
			_sprite.modulate = base_color
		_:
			_sprite.modulate = base_color
	_update_construction_presentation()
	if GameManager.reduced_flashes:
		_clear_damage_flash()


func _update_construction_presentation() -> void:
	if state != State.CONSTRUCTING:
		if is_instance_valid(_construction_frame):
			_construction_frame.hide()
			_construction_frame.queue_free()
			_construction_frame = null
		_sprite.material = null
		_construction_material = null
		return
	if _construction_material == null:
		_construction_material = ShaderMaterial.new()
		_construction_material.shader = CONSTRUCTION_REVEAL_SHADER
		if _sprite.texture != null:
			var uv_range: Vector2 = KingdomArt.vertical_uv_range(_sprite.texture)
			_construction_material.set_shader_parameter("ink_top", uv_range.x)
			_construction_material.set_shader_parameter("ink_bottom", uv_range.y)
		_sprite.material = _construction_material
	_construction_material.set_shader_parameter("construction_progress", clampf(build_progress, 0.0, 1.0))
	if not is_instance_valid(_construction_frame):
		_construction_frame = ConstructionFrame.new()
		_construction_frame.name = "ConstructionFrame"
		_construction_frame.position = _footprint_center
		_construction_frame.half_width = footprint.x * MapData.TILE_WIDTH * 0.34
		_construction_frame.half_depth = footprint.y * MapData.TILE_HEIGHT * 0.30
		_construction_frame.full_height = clampf(_sprite_visual_rect.size.y * 0.65, 18.0, 100.0)
		if building_type == BuildingData.BuildingType.FARM:
			_construction_frame.full_height = 14.0
		add_child(_construction_frame)
	var stage: int = 0 if build_progress < 0.25 else 1 if build_progress < 0.6 else 2
	if _construction_frame.stage != stage:
		_construction_frame.stage = stage
		_construction_frame.queue_redraw()


func _draw() -> void:
	var pixel_w: float = footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = footprint.y * MapData.TILE_HEIGHT
	if is_selected and state == State.ACTIVE and building_type == BuildingData.BuildingType.WATCH_TOWER and tower_attack_damage > 0:
		# Towers expose their defensive reach. Town Centers keep only the close
		# footprint selection cue so ordinary recruitment does not cover the map.
		var range_color := Color(0.70, 0.84, 1.0, 0.42) if player_owner == 0 else Color(1.0, 0.65, 0.50, 0.42)
		for segment: int in range(32):
			var angle: float = float(segment) * TAU / 32.0
			draw_arc(Vector2.ZERO, tower_attack_range, angle, angle + TAU / 48.0, 4, range_color, 1.6, true)
	# Selection outline (pulsing isometric diamond border)
	if is_selected:
		var pulse: float = 1.0 if GameManager.reduced_motion or GameManager.reduced_flashes else 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		var sel_alpha := lerpf(0.55, 0.95, pulse)
		var sel_width := lerpf(2.0, 3.6, pulse)
		var points := PackedVector2Array([
			_footprint_center + Vector2(0, -pixel_h * 0.5),
			_footprint_center + Vector2(pixel_w * 0.5, 0),
			_footprint_center + Vector2(0, pixel_h * 0.5),
			_footprint_center + Vector2(-pixel_w * 0.5, 0),
		])
		for i in points.size():
			var next_i := (i + 1) % points.size()
			draw_line(points[i], points[next_i], Color(1.0, 0.92, 0.55, sel_alpha), sel_width)

	# Construction progress bar
	if state == State.CONSTRUCTING:
		var bar_w := pixel_w * 0.6
		var bar_h := 4.0
		var bar_y := _visual_top - 8.0
		draw_rect(Rect2(_footprint_center.x - bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(_footprint_center.x - bar_w * 0.5, bar_y, bar_w * build_progress, bar_h), Color(0.2, 0.8, 0.2))

	# Health bar (only when active and damaged)
	if state == State.ACTIVE and hp < max_hp:
		var bar_w := pixel_w * 0.6
		var bar_h := 3.0
		var bar_y := _visual_top - 8.0
		var hp_ratio := float(hp) / float(max_hp)
		var hp_color := Color(0.2, 0.8, 0.2) if hp_ratio > 0.5 else Color(0.8, 0.8, 0.2) if hp_ratio > 0.25 else Color(0.8, 0.2, 0.2)
		draw_rect(Rect2(_footprint_center.x - bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(_footprint_center.x - bar_w * 0.5, bar_y, bar_w * hp_ratio, bar_h), hp_color)

	_draw_drop_off_badges(pixel_w, pixel_h)

	# Only the selected producer shows its rally flag; no battlefield-spanning line.
	if is_selected and state == State.ACTIVE and not trainable_units.is_empty():
		var rp_local: Vector2 = to_local(rally_point)
		var camera: Camera2D = get_viewport().get_camera_2d()
		var scale_factor: float = 1.0 / maxf(0.1, camera.zoom.x) if camera != null else 1.0
		var flag_color := Color(0.36, 0.72, 1.0, 0.8)
		draw_arc(rp_local, 5.0 * scale_factor, 0.0, TAU, 20, flag_color, scale_factor)
		draw_line(rp_local, rp_local + Vector2(0, -14) * scale_factor, flag_color, 1.5 * scale_factor)
		draw_colored_polygon(PackedVector2Array([rp_local + Vector2(0, -14) * scale_factor, rp_local + Vector2(9, -11) * scale_factor, rp_local + Vector2(0, -8) * scale_factor]), flag_color)


func _draw_ownership_pennant() -> void:
	# Draw above the sprite, so an isometric facade cannot hide ownership.
	# Civ architecture, skin, stone and crops keep their original materials.
	var pixel_w: float = footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = footprint.y * MapData.TILE_HEIGHT
	var pole := _footprint_center + Vector2(pixel_w * 0.29, pixel_h * 0.20)
	var flag_color := Color("88b7ad") if player_owner == 0 else Color("d69477")
	_ownership_marker.draw_line(pole, pole - Vector2(0, 19), Color("293235"), 2.0)
	var flag := PackedVector2Array([pole + Vector2(0, -19), pole + Vector2(13, -17), pole + Vector2(10, -10), pole + Vector2(0, -12)])
	_ownership_marker.draw_colored_polygon(flag, flag_color)
	if player_owner != 0:
		_ownership_marker.draw_polyline(PackedVector2Array([pole + Vector2(4, -16), pole + Vector2(7, -13), pole + Vector2(10, -15)]), Color("293235"), 1.4)


func _draw_drop_off_badges(pixel_w: float, _pixel_h: float) -> void:
	if drop_off_resources.is_empty():
		return
	if building_type == BuildingData.BuildingType.TOWN_CENTER and not is_selected:
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var fsize: int = maxi(10, ThemeDB.fallback_font_size - 3)
	var start_x: float = _footprint_center.x - pixel_w * 0.28
	var y: float = _visual_top - 21.0
	var spacing: float = 16.0
	for i in range(drop_off_resources.size()):
		var resource_type: String = String(drop_off_resources[i])
		var x: float = start_x + i * spacing
		draw_circle(Vector2(x, y), 6.0, Color(0.05, 0.05, 0.05, 0.78))
		draw_circle(Vector2(x, y), 4.9, DROP_OFF_BADGE_COLORS.get(resource_type, Color(0.62, 0.62, 0.62)))
		var text: String = "?"
		match resource_type:
			"food":
				text = "F"
			"wood":
				text = "W"
			"gold":
				text = "G"
		draw_string(
			font,
			Vector2(x - 4.5, y + 3.0),
			text,
			HORIZONTAL_ALIGNMENT_CENTER,
			9.0,
			fsize,
			Color(0.95, 0.95, 0.95, 0.98)
		)


func _process(delta: float) -> void:
	var had_shot_flash: bool = _defensive_shot_flash_remaining > 0.0
	_defensive_shot_flash_remaining = maxf(0.0, _defensive_shot_flash_remaining - delta)
	if state == State.CONSTRUCTING:
		_update_sprite_appearance()
		# Periodic construction dust particles
		_construction_dust_timer += delta
		if _construction_dust_timer >= 0.8:
			_construction_dust_timer = 0.0
			if get_tree() and get_tree().current_scene:
				VFX.construction_dust(get_tree(), global_position)
		queue_redraw()
	elif state == State.ACTIVE and hp < max_hp:
		# Damage smoke/fire effects
		var hp_ratio := float(hp) / float(max_hp) if max_hp > 0 else 1.0
		if hp_ratio < 0.5 and get_tree() and get_tree().current_scene:
			_damage_smoke_timer += delta
			var interval := 1.2 if hp_ratio > 0.25 else 0.6
			if _damage_smoke_timer >= interval:
				_damage_smoke_timer = 0.0
				VFX.building_smoke(get_tree(), global_position)
				if hp_ratio < 0.25:
					VFX.building_fire(get_tree(), global_position)
		queue_redraw()
	# Only completed, living buildings defend. The inherited PAUSABLE match
	# boundary freezes both cooldowns and arrows during pause/game-over.
	if state == State.ACTIVE and tower_attack_damage > 0:
		_tower_attack_cooldown -= delta
		if _tower_attack_cooldown <= 0.0:
			_tower_attack_cooldown = tower_attack_interval if _tower_try_attack() else DEFENSIVE_TARGET_SCAN_INTERVAL
	if is_selected or had_shot_flash:
		queue_redraw()
	if had_shot_flash and _defensive_flash != null:
		_defensive_flash.queue_redraw()


## Called by villagers to add construction progress.
func add_build_progress(amount: float) -> void:
	if state != State.CONSTRUCTING:
		return
	if amount > 0.0:
		AudioManager.play_world("construction_work", self)
	build_progress = clampf(build_progress + amount / build_time, 0.0, 1.0)
	hp = int(max_hp * build_progress)
	if build_progress >= 1.0:
		_complete_construction()


## Start construction of this building.
func start_construction() -> void:
	state = State.CONSTRUCTING
	build_progress = 0.0
	hp = 1
	_update_sprite_appearance()
	queue_redraw()


## Instantly finish construction (for starting town center, debug).
func complete_instantly() -> void:
	state = State.ACTIVE
	build_progress = 1.0
	hp = max_hp
	_update_sprite_appearance()
	construction_complete.emit(self)
	queue_redraw()


func _complete_construction() -> void:
	state = State.ACTIVE
	hp = max_hp
	build_progress = 1.0
	_update_sprite_appearance()
	if get_tree() and get_tree().current_scene:
		VFX.building_complete(get_tree(), global_position)
	construction_complete.emit(self)
	queue_redraw()


func take_damage(amount: int) -> void:
	## `amount` is final HP loss. Buildings have no armor in the current ruleset.
	if state == State.DESTROYED:
		return
	var previous_hp: int = hp
	hp = maxi(hp - maxi(amount, 0), 0)
	health_changed.emit(hp, max_hp)
	if hp < previous_hp:
		damage_received.emit(self, previous_hp - hp)
		_flash_damage()
	if hp <= 0:
		_destroy()
	queue_redraw()


func _flash_damage() -> void:
	_clear_damage_flash()
	if _sprite == null or GameManager.reduced_flashes:
		return
	# A restrained warm hit is visible on neutral art. self_modulate is separate
	# from ownership/construction/death alpha, so its tween cannot restore an old
	# building state or accumulate tint after repeated hits.
	_sprite.self_modulate = DAMAGE_FLASH_COLOR
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_sprite, "self_modulate", Color.WHITE, DAMAGE_FLASH_SECONDS)


func _clear_damage_flash() -> void:
	if _damage_flash_tween != null and _damage_flash_tween.is_valid():
		_damage_flash_tween.kill()
	_damage_flash_tween = null
	if _sprite != null:
		_sprite.self_modulate = Color.WHITE


func _destroy() -> void:
	state = State.DESTROYED
	_clear_damage_flash()
	_assigned_farmer_ref = null
	_update_sprite_appearance()
	building_destroyed.emit(self)
	# Destruction smoke puff
	if get_tree() and get_tree().current_scene:
		VFX.death_puff(get_tree(), global_position)
	queue_redraw()
	# Fade out and remove
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)


func select() -> void:
	is_selected = true
	building_selected.emit(self)
	AudioManager.play_ui("select_unit")
	queue_redraw()


func deselect() -> void:
	is_selected = false
	building_deselected.emit(self)
	queue_redraw()


func set_rally_point(pos: Vector2) -> void:
	rally_point = pos
	rally_point_is_custom = true
	rally_resource_type = ""
	rally_resource_instance_id = 0
	rally_resource_is_building = false
	queue_redraw()


## Main validates current visibility and ownership before recording this order.
## Keep observed identity and position only; future births must reveal the target.
func set_resource_rally(resource_node: Node2D) -> void:
	set_rally_point(resource_node.global_position)
	rally_resource_type = str(resource_node.call("get_resource_type"))
	rally_resource_instance_id = resource_node.get_instance_id()
	rally_resource_is_building = resource_node is BuildingBase


func has_custom_rally_point() -> bool:
	return rally_point_is_custom


func is_construction_complete() -> bool:
	return state == State.ACTIVE


func is_drop_off_point(resource: String) -> bool:
	return resource in drop_off_resources


func get_player_owner() -> int:
	return player_owner


func get_player_id() -> int:
	return player_owner


func deposit_resource(resource_type: String, amount: int) -> void:
	if state != State.ACTIVE or amount <= 0 or not is_drop_off_point(resource_type):
		return
	var rm: Node = get_node_or_null("/root/ResourceManager")
	if rm:
		rm.add_resource(player_owner, resource_type, amount)


func can_train() -> bool:
	return state == State.ACTIVE and trainable_units.size() > 0


# --- Farm support: permanent food, one assigned worker including delivery ---

func get_resource_type() -> String:
	if provides_food:
		return "food"
	return ""


func is_sprite_body_hit(world_position: Vector2) -> bool:
	if building_type != BuildingData.BuildingType.FARM or _sprite == null or _sprite.texture == null:
		return false
	return _sprite.is_pixel_opaque(_sprite.to_local(world_position))


func is_harvestable_by(gathering_player_id: int = -1) -> bool:
	if not provides_food or state != State.ACTIVE:
		return false
	return gathering_player_id < 0 or gathering_player_id == player_owner


func get_assigned_worker() -> UnitBase:
	var worker: UnitBase = _assigned_farmer_ref.get_ref() as UnitBase if _assigned_farmer_ref != null else null
	if not is_instance_valid(worker) or worker.is_queued_for_deletion() or worker.current_state == UnitBase.State.DEAD or state != State.ACTIVE:
		_assigned_farmer_ref = null
		return null
	return worker


func is_available_to_worker(worker: Node2D = null) -> bool:
	if not is_harvestable_by():
		return false
	var assigned: UnitBase = get_assigned_worker()
	return assigned == null or assigned == worker


func try_assign_worker(worker: UnitBase) -> bool:
	if not is_instance_valid(worker) or worker.is_queued_for_deletion() or worker.current_state == UnitBase.State.DEAD:
		return false
	if worker.unit_type != UnitData.UnitType.VILLAGER or not is_harvestable_by(worker.player_owner) or not is_available_to_worker(worker):
		return false
	_assigned_farmer_ref = weakref(worker)
	return true


func release_worker(worker: Node2D) -> void:
	if _assigned_farmer_ref != null and _assigned_farmer_ref.get_ref() == worker:
		_assigned_farmer_ref = null


func harvest(amount: int, worker: UnitBase = null) -> int:
	if not is_harvestable_by():
		return 0
	# Unassigned direct harvest remains useful for resource-contract probes;
	# every Villager supplies itself, and only the reserved farmer earns food.
	var assigned: UnitBase = get_assigned_worker()
	if (worker != null and assigned != worker) or (worker == null and assigned != null):
		return 0
	return maxi(0, amount)


func get_production_queue() -> Node:
	return _production_queue


func set_production_queue(queue: Node) -> void:
	_production_queue = queue


func _tower_try_attack() -> bool:
	if state != State.ACTIVE or hp <= 0 or tower_attack_damage <= 0:
		return false
	# Town Centers prioritize attacking/military raiders over a nearby Scout.
	# Towers preserve their ordinary nearest-target policy and building fire.
	var best_unit: UnitBase = null
	var best_unit_dist: float = INF
	var best_unit_priority: int = 3
	for node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is UnitBase):
			continue
		var u: UnitBase = node as UnitBase
		if u.player_owner == player_owner:
			continue
		if not _is_tower_target_visible(u):
			continue
		if u.current_state == UnitBase.State.DEAD:
			continue
		var dist: float = global_position.distance_to(u.global_position)
		var priority: int = _defensive_target_priority(u)
		if dist <= tower_attack_range and (priority < best_unit_priority or (priority == best_unit_priority and dist < best_unit_dist)):
			best_unit_dist = dist
			best_unit_priority = priority
			best_unit = u
	if best_unit != null:
		if tower_attack_projectile_speed > 0.0:
			_launch_defensive_arrow(best_unit)
		else:
			Combat.deal_tower_damage(self, best_unit)
			if get_tree().current_scene != null and best_unit.visible:
				VFX.hit_burst(get_tree(), best_unit.global_position, Color(0.8, 0.6, 0.2))
		defensive_attack_fired.emit(best_unit)
		return true
	if not tower_attack_buildings:
		return false

	# No enemy units in range — try enemy buildings
	var best_building: BuildingBase = null
	var best_bld_dist: float = INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is BuildingBase):
			continue
		var b: BuildingBase = node as BuildingBase
		if b.player_owner == player_owner:
			continue
		if not _is_tower_target_visible(b):
			continue
		if b.state == State.DESTROYED:
			continue
		var dist: float = global_position.distance_to(b.global_position)
		if dist <= tower_attack_range and dist < best_bld_dist:
			best_bld_dist = dist
			best_building = b
	if best_building != null:
		Combat.deal_tower_damage_to_building(self, best_building)
		if get_tree().current_scene != null and best_building.visible:
			VFX.hit_burst(get_tree(), best_building.global_position, Color(0.8, 0.6, 0.2))
		defensive_attack_fired.emit(best_building)
		return true
	return false


func _defensive_target_priority(unit: UnitBase) -> int:
	if building_type != BuildingData.BuildingType.TOWN_CENTER:
		return 0
	if (is_instance_valid(unit.attack_target) and unit.attack_target.player_owner == player_owner) or (is_instance_valid(unit.attack_building_target) and unit.attack_building_target.player_owner == player_owner):
		return 0
	if unit.unit_type in [UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY, UnitData.UnitType.SIEGE]:
		return 1
	return 2


func _get_defensive_fire_position() -> Vector2:
	if _sprite == null or _sprite.texture == null:
		return to_global(Vector2(0.0, -52.0))
	if KingdomArt.is_kingdom_texture(_sprite.texture):
		var ink: Rect2 = KingdomArt.ink_rect(_sprite.texture)
		return _sprite.to_global(_sprite.get_rect().position + ink.position + ink.size * Vector2(0.55, 0.42))
	var source_point: Vector2 = DEFENSIVE_FIRE_POINTS.get(building_type, Vector2(64, 52))
	return _sprite.to_global(_sprite.get_rect().position + source_point * get_art_texture_scale(_sprite.texture))


func _draw_defensive_shot_flash() -> void:
	if _defensive_shot_flash_remaining > 0.0 and not GameManager.reduced_flashes:
		_defensive_flash.draw_circle(_defensive_flash.to_local(_get_defensive_fire_position()), 4.0, Color(1.0, 0.88, 0.48, 0.7))


func _launch_defensive_arrow(target: UnitBase) -> void:
	var arrow := DefensiveArrow.new()
	arrow.defender_ref = weakref(target)
	var visibility_map: Node2D = _get_defensive_visibility_map()
	if visibility_map != null:
		arrow.visibility_map_ref = weakref(visibility_map)
	arrow.final_damage = Combat.calculate_tower_damage(self, target)
	arrow.start_position = _get_defensive_fire_position()
	arrow.flight_seconds = clampf(global_position.distance_to(target.global_position) / tower_attack_projectile_speed, 0.12, 0.42)
	arrow.z_index = 80
	get_parent().add_child(arrow)
	arrow.add_to_group("defensive_projectiles")
	arrow.global_position = arrow.start_position
	arrow.visible = visible
	_defensive_shot_flash_remaining = 0.18
	if _defensive_flash != null:
		_defensive_flash.queue_redraw()
	queue_redraw()


func _is_tower_target_visible(target: Node2D) -> bool:
	var visibility_map: Node2D = _get_defensive_visibility_map()
	if visibility_map != null:
		return bool(visibility_map.call("is_entity_visible_to_player", target, player_owner))
	return true


func _get_defensive_visibility_map() -> Node2D:
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor is Node2D and ancestor.has_method("is_entity_visible_to_player"):
			return ancestor as Node2D
		ancestor = ancestor.get_parent()
	return null
