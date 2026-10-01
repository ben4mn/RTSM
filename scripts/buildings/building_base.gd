class_name BuildingBase
extends Area2D
## Base building for all structures in AOEM.
## Handles construction progress, health, selection, and sprite-based rendering.

signal construction_complete(building: BuildingBase)
signal building_destroyed(building: BuildingBase)
signal building_selected(building: BuildingBase)
signal building_deselected(building: BuildingBase)
signal health_changed(current: int, maximum: int)
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

var rally_point: Vector2 = Vector2.ZERO
var rally_point_is_custom: bool = false
var is_selected: bool = false
var _production_queue: Node = null
var _sprite: Sprite2D = null
var _construction_dust_timer: float = 0.0
var _damage_smoke_timer: float = 0.0

# Defensive building weapons. Names preserve the existing tower damage API.
var tower_attack_damage: int = 0
var tower_attack_range: float = 0.0  # Runtime world units; data is range tiles.
var tower_attack_interval: float = 1.5
var tower_attack_projectile_speed: float = 0.0
var tower_attack_buildings: bool = true
var _tower_attack_cooldown: float = 0.0
var _defensive_shot_flash_remaining: float = 0.0
const DEFENSIVE_TARGET_SCAN_INTERVAL: float = 0.2


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

## Sprite texture paths per building type from Kenney Medieval RTS pack.
const BUILDING_SPRITES: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: "res://assets/buildings/town_center_alt.png",
	BuildingData.BuildingType.HOUSE: "res://assets/buildings/house.png",
	BuildingData.BuildingType.BARRACKS: "res://assets/buildings/barracks.png",
	BuildingData.BuildingType.ARCHERY_RANGE: "res://assets/buildings/archery_range.png",
	BuildingData.BuildingType.STABLE: "res://assets/buildings/stable.png",
	BuildingData.BuildingType.FARM: "res://assets/buildings/farm.svg",
	BuildingData.BuildingType.MILL: "res://assets/buildings/market.png",
	BuildingData.BuildingType.LUMBER_CAMP: "res://assets/buildings/blacksmith.png",
	BuildingData.BuildingType.MINING_CAMP: "res://assets/buildings/market.png",
	BuildingData.BuildingType.SIEGE_WORKSHOP: "res://assets/buildings/archery_range.png",
	BuildingData.BuildingType.BLACKSMITH: "res://assets/buildings/blacksmith.png",
	BuildingData.BuildingType.WATCH_TOWER: "res://assets/buildings/watch_tower.svg",
}

## Scale per building type — larger footprint buildings get larger sprites.
const BUILDING_SCALES: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: Vector2(1.08, 1.08),
	BuildingData.BuildingType.HOUSE: Vector2(0.45, 0.45),
	BuildingData.BuildingType.BARRACKS: Vector2(0.60, 0.60),
	BuildingData.BuildingType.ARCHERY_RANGE: Vector2(0.55, 0.55),
	BuildingData.BuildingType.STABLE: Vector2(0.55, 0.55),
	BuildingData.BuildingType.FARM: Vector2(1.0, 1.0),
	BuildingData.BuildingType.MILL: Vector2(0.45, 0.45),
	BuildingData.BuildingType.LUMBER_CAMP: Vector2(0.45, 0.45),
	BuildingData.BuildingType.MINING_CAMP: Vector2(0.40, 0.40),
	BuildingData.BuildingType.SIEGE_WORKSHOP: Vector2(0.60, 0.60),
	BuildingData.BuildingType.BLACKSMITH: Vector2(0.50, 0.50),
	BuildingData.BuildingType.WATCH_TOWER: Vector2(0.65, 0.65),
}

const DROP_OFF_BADGE_COLORS: Dictionary = {
	"food": Color(0.92, 0.34, 0.30),
	"wood": Color(0.46, 0.76, 0.34),
	"gold": Color(0.96, 0.86, 0.22),
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
	var stats: Dictionary = BuildingData.get_building_stats(building_type)
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
	_sprite = Sprite2D.new()
	_sprite.name = "BuildingSprite"
	var tex_path: String = BUILDING_SPRITES.get(building_type, "")
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_sprite.texture = load(tex_path)
	_sprite.scale = BUILDING_SCALES.get(building_type, Vector2(0.4, 0.4))
	# Offset sprite upward so the base sits at the building position
	_sprite.offset = get_sprite_offset(building_type, footprint)
	add_child(_sprite)
	_update_sprite_appearance()


static func get_sprite_offset(type: int, size_in_tiles: Vector2i) -> Vector2:
	if type == BuildingData.BuildingType.FARM:
		return Vector2(0, -7)
	if type == BuildingData.BuildingType.WATCH_TOWER:
		return Vector2(0, -46)
	return Vector2(0, -size_in_tiles.y * MapData.TILE_HEIGHT * 0.3)


func _update_sprite_appearance() -> void:
	if _sprite == null:
		return
	var base_color: Color = Color(1.0, 0.55, 0.55) if player_owner != 0 else Color.WHITE
	match state:
		State.CONSTRUCTING:
			# Darken and make semi-transparent during construction, lerp to full
			var progress_alpha := lerpf(0.4, 1.0, build_progress)
			var progress_dark := lerpf(0.4, 0.0, 1.0 - build_progress)
			_sprite.modulate = Color(base_color.r - progress_dark, base_color.g - progress_dark, base_color.b - progress_dark, progress_alpha)
		State.DESTROYED:
			_sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)
		State.ACTIVE:
			_sprite.modulate = base_color
		_:
			_sprite.modulate = base_color


func _draw() -> void:
	var pixel_w: float = footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = footprint.y * MapData.TILE_HEIGHT
	if is_selected and state == State.ACTIVE and tower_attack_damage > 0:
		# This circle is the actual world-distance fire limit, independent of
		# the larger tile-based vision radius or decorative building facade.
		var range_color := Color(0.70, 0.84, 1.0, 0.42) if player_owner == 0 else Color(1.0, 0.65, 0.50, 0.42)
		for segment: int in range(32):
			var angle: float = float(segment) * TAU / 32.0
			draw_arc(Vector2.ZERO, tower_attack_range, angle, angle + TAU / 48.0, 4, range_color, 1.6, true)
	if _defensive_shot_flash_remaining > 0.0:
		draw_circle(Vector2(0.0, -52.0), 4.0, Color(1.0, 0.88, 0.48, 0.7))

	# Selection outline (pulsing isometric diamond border)
	if is_selected:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		var sel_alpha := lerpf(0.55, 0.95, pulse)
		var sel_width := lerpf(2.0, 3.6, pulse)
		var points := PackedVector2Array([
			Vector2(0, -pixel_h * 0.5),
			Vector2(pixel_w * 0.5, 0),
			Vector2(0, pixel_h * 0.5),
			Vector2(-pixel_w * 0.5, 0),
		])
		for i in points.size():
			var next_i := (i + 1) % points.size()
			draw_line(points[i], points[next_i], Color(1.0, 0.92, 0.55, sel_alpha), sel_width)

	# Shadow ellipse under building
	var shadow_w := pixel_w * 0.35
	var shadow_h := pixel_h * 0.25
	var shadow_pts := PackedVector2Array()
	for a in range(32):
		var angle := float(a) / 32.0 * TAU
		shadow_pts.append(Vector2(cos(angle) * shadow_w, sin(angle) * shadow_h + 2.0))
	draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.12))
	if building_type == BuildingData.BuildingType.TOWN_CENTER:
		var team: Color = Color("6bade0") if player_owner == 0 else Color("dc806d")
		draw_line(Vector2(48, -35), Vector2(48, -78), Color("384440"), 2.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(49, -77), Vector2(72, -71), Vector2(49, -63)]), team)

	# Construction progress bar
	if state == State.CONSTRUCTING:
		var bar_w := pixel_w * 0.6
		var bar_h := 4.0
		var bar_y := -pixel_h * 0.5 - 8.0
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * build_progress, bar_h), Color(0.2, 0.8, 0.2))

	# Health bar (only when active and damaged)
	if state == State.ACTIVE and hp < max_hp:
		var bar_w := pixel_w * 0.6
		var bar_h := 3.0
		var bar_y := -pixel_h * 0.5 - 6.0
		var hp_ratio := float(hp) / float(max_hp)
		var hp_color := Color(0.2, 0.8, 0.2) if hp_ratio > 0.5 else Color(0.8, 0.8, 0.2) if hp_ratio > 0.25 else Color(0.8, 0.2, 0.2)
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * hp_ratio, bar_h), hp_color)

	_draw_drop_off_badges(pixel_w, pixel_h)

	# Rally point indicator with line
	if is_selected and state == State.ACTIVE and trainable_units.size() > 0:
		var rp_local := rally_point - global_position
		# Dashed line from building to rally point
		var line_color := Color(0.2, 0.6, 1.0, 0.4)
		var dash_len := 6.0
		var gap_len := 4.0
		var total_dist := rp_local.length()
		if total_dist > 1.0:
			var dir := rp_local.normalized()
			var d := 0.0
			while d < total_dist:
				var start := dir * d
				var end_d := minf(d + dash_len, total_dist)
				var end := dir * end_d
				draw_line(start, end, line_color, 1.5)
				d = end_d + gap_len
		draw_circle(rp_local, 4.0, Color(0.2, 0.6, 1.0, 0.7))


func _draw_drop_off_badges(pixel_w: float, pixel_h: float) -> void:
	if drop_off_resources.is_empty():
		return
	if building_type == BuildingData.BuildingType.TOWN_CENTER and not is_selected:
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var fsize: int = maxi(10, ThemeDB.fallback_font_size - 3)
	var start_x: float = -pixel_w * 0.28
	var y: float = -pixel_h * 0.54
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


## Called by villagers to add construction progress.
func add_build_progress(amount: float) -> void:
	if state != State.CONSTRUCTING:
		return
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
	hp = maxi(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	_flash_damage()
	if hp <= 0:
		_destroy()
	queue_redraw()


func _flash_damage() -> void:
	if _sprite == null:
		return
	var original: Color = _sprite.modulate
	_sprite.modulate = Color(1.0, 1.0, 1.0)  # White flash — visible on both player and enemy buildings
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", original, 0.15)


func _destroy() -> void:
	state = State.DESTROYED
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
	queue_redraw()


func deselect() -> void:
	is_selected = false
	building_deselected.emit(self)
	queue_redraw()


func set_rally_point(pos: Vector2) -> void:
	rally_point = pos
	rally_point_is_custom = true
	queue_redraw()


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
	var rm: Node = get_node_or_null("/root/ResourceManager")
	if rm:
		rm.add_resource(player_owner, resource_type, amount)


func can_train() -> bool:
	return state == State.ACTIVE and trainable_units.size() > 0


# --- Farm support: farms act as renewable food sources ---
var farm_remaining: int = 300

func get_resource_type() -> String:
	if provides_food:
		return "food"
	return ""


func is_sprite_body_hit(world_position: Vector2) -> bool:
	if building_type != BuildingData.BuildingType.FARM or _sprite == null or _sprite.texture == null:
		return false
	return _sprite.is_pixel_opaque(_sprite.to_local(world_position))


func is_harvestable_by(gathering_player_id: int = -1) -> bool:
	if not provides_food or state != State.ACTIVE or farm_remaining <= 0:
		return false
	return gathering_player_id < 0 or gathering_player_id == player_owner


func harvest(amount: int) -> int:
	if not is_harvestable_by():
		return 0
	var actual := mini(amount, farm_remaining)
	farm_remaining -= actual
	if farm_remaining <= 0:
		# Farm exhausted - destroy it
		_destroy()
	return actual


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


func _launch_defensive_arrow(target: UnitBase) -> void:
	var arrow := DefensiveArrow.new()
	arrow.defender_ref = weakref(target)
	var visibility_map: Node2D = _get_defensive_visibility_map()
	if visibility_map != null:
		arrow.visibility_map_ref = weakref(visibility_map)
	arrow.final_damage = Combat.calculate_tower_damage(self, target)
	arrow.start_position = global_position + Vector2(0.0, -52.0)
	arrow.flight_seconds = clampf(global_position.distance_to(target.global_position) / tower_attack_projectile_speed, 0.12, 0.42)
	arrow.z_index = 80
	get_parent().add_child(arrow)
	arrow.add_to_group("defensive_projectiles")
	arrow.global_position = arrow.start_position
	arrow.visible = visible
	_defensive_shot_flash_remaining = 0.18
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
