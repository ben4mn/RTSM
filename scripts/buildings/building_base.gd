class_name BuildingBase
extends Area2D
## Base building for all structures in AOEM.
## Handles construction progress, health, selection, and sprite-based rendering.

signal construction_complete(building: BuildingBase)
signal building_destroyed(building: BuildingBase)
signal building_selected(building: BuildingBase)
signal building_deselected(building: BuildingBase)
signal health_changed(current: int, maximum: int)

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
var is_selected: bool = false
var _production_queue: Node = null
var _sprite: Sprite2D = null
var _construction_dust_timer: float = 0.0
var _damage_smoke_timer: float = 0.0

# Tower auto-attack
var tower_attack_damage: int = 0
var tower_attack_range: float = 0.0
var _tower_attack_cooldown: float = 0.0
const TOWER_ATTACK_INTERVAL: float = 1.5

## Sprite texture paths per building type from Kenney Medieval RTS pack.
const BUILDING_SPRITES: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: "res://assets/buildings/town_center.png",
	BuildingData.BuildingType.HOUSE: "res://assets/buildings/house.png",
	BuildingData.BuildingType.BARRACKS: "res://assets/buildings/barracks.png",
	BuildingData.BuildingType.ARCHERY_RANGE: "res://assets/buildings/archery_range.png",
	BuildingData.BuildingType.STABLE: "res://assets/buildings/stable.png",
	BuildingData.BuildingType.FARM: "res://assets/buildings/market_stall.png",
	BuildingData.BuildingType.LUMBER_CAMP: "res://assets/buildings/lumber_camp.png",
	BuildingData.BuildingType.MINING_CAMP: "res://assets/buildings/market.png",
	BuildingData.BuildingType.SIEGE_WORKSHOP: "res://assets/buildings/monument.png",
	BuildingData.BuildingType.BLACKSMITH: "res://assets/buildings/blacksmith.png",
	BuildingData.BuildingType.WATCH_TOWER: "res://assets/buildings/tower.png",
}

## Scale per building type — larger footprint buildings get larger sprites.
const BUILDING_SCALES: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: Vector2(0.85, 0.85),
	BuildingData.BuildingType.HOUSE: Vector2(0.45, 0.45),
	BuildingData.BuildingType.BARRACKS: Vector2(0.60, 0.60),
	BuildingData.BuildingType.ARCHERY_RANGE: Vector2(0.55, 0.55),
	BuildingData.BuildingType.STABLE: Vector2(0.55, 0.55),
	BuildingData.BuildingType.FARM: Vector2(0.40, 0.40),
	BuildingData.BuildingType.LUMBER_CAMP: Vector2(0.45, 0.45),
	BuildingData.BuildingType.MINING_CAMP: Vector2(0.40, 0.40),
	BuildingData.BuildingType.SIEGE_WORKSHOP: Vector2(0.60, 0.60),
	BuildingData.BuildingType.BLACKSMITH: Vector2(0.50, 0.50),
	BuildingData.BuildingType.WATCH_TOWER: Vector2(0.50, 0.50),
}


func _ready() -> void:
	_load_stats()
	_setup_collision()
	_setup_sprite()
	rally_point = global_position + Vector2(footprint.x * MapData.TILE_WIDTH, 0)
	add_to_group("buildings")
	add_to_group("player_%d_buildings" % player_owner)
	if drop_off_resources.size() > 0:
		add_to_group("dropoff_buildings")
	if provides_food:
		add_to_group("food_resources")
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
	tower_attack_range = stats.get("attack_range", 0) * MapData.TILE_WIDTH


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
	var sprite_y_offset := -footprint.y * MapData.TILE_HEIGHT * 0.3
	_sprite.offset = Vector2(0, sprite_y_offset)
	add_child(_sprite)
	_update_sprite_appearance()


func _update_sprite_appearance() -> void:
	if _sprite == null:
		return
	match state:
		State.CONSTRUCTING:
			# Darken and make semi-transparent during construction, lerp to full
			var progress_alpha := lerpf(0.4, 1.0, build_progress)
			var progress_dark := lerpf(0.4, 0.0, 1.0 - build_progress)
			_sprite.modulate = Color(1.0 - progress_dark, 1.0 - progress_dark, 1.0 - progress_dark, progress_alpha)
		State.DESTROYED:
			_sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)
		State.ACTIVE:
			_sprite.modulate = Color.WHITE
		_:
			_sprite.modulate = Color.WHITE


func _draw() -> void:
	var pixel_w: float = footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = footprint.y * MapData.TILE_HEIGHT

	# Selection outline (pulsing isometric diamond border)
	if is_selected:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		var sel_alpha := lerpf(0.4, 0.9, pulse)
		var sel_width := lerpf(1.5, 3.0, pulse)
		var points := PackedVector2Array([
			Vector2(0, -pixel_h * 0.5),
			Vector2(pixel_w * 0.5, 0),
			Vector2(0, pixel_h * 0.5),
			Vector2(-pixel_w * 0.5, 0),
		])
		for i in points.size():
			var next_i := (i + 1) % points.size()
			draw_line(points[i], points[next_i], Color(1, 1, 1, sel_alpha), sel_width)

	# Shadow ellipse under building
	var shadow_w := pixel_w * 0.35
	var shadow_h := pixel_h * 0.25
	var shadow_pts := PackedVector2Array()
	for a in range(32):
		var angle := float(a) / 32.0 * TAU
		shadow_pts.append(Vector2(cos(angle) * shadow_w, sin(angle) * shadow_h + 2.0))
	draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.12))

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


func _process(delta: float) -> void:
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
	# Tower auto-attack
	if state == State.ACTIVE and tower_attack_damage > 0:
		_tower_attack_cooldown -= delta
		if _tower_attack_cooldown <= 0.0:
			_tower_attack_cooldown = TOWER_ATTACK_INTERVAL
			_tower_try_attack()
	elif is_selected:
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
	_sprite.modulate = Color(1, 0.3, 0.3)
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
	queue_redraw()


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


func harvest(amount: int) -> int:
	if not provides_food or state != State.ACTIVE:
		return 0
	if farm_remaining <= 0:
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


func _tower_try_attack() -> void:
	# Find nearest enemy unit in range (priority), fall back to enemy buildings
	var best_unit: UnitBase = null
	var best_unit_dist: float = INF
	for node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is UnitBase):
			continue
		var u: UnitBase = node as UnitBase
		if u.player_owner == player_owner or u.current_state == UnitBase.State.DEAD:
			continue
		var dist: float = global_position.distance_to(u.global_position)
		if dist <= tower_attack_range and dist < best_unit_dist:
			best_unit_dist = dist
			best_unit = u
	if best_unit != null:
		best_unit.take_damage(tower_attack_damage)
		if get_tree() and get_tree().current_scene:
			VFX.hit_burst(get_tree(), best_unit.global_position, Color(0.8, 0.6, 0.2))
		return

	# No enemy units in range — try enemy buildings
	var best_building: BuildingBase = null
	var best_bld_dist: float = INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is BuildingBase):
			continue
		var b: BuildingBase = node as BuildingBase
		if b.player_owner == player_owner or b.state == State.DESTROYED:
			continue
		var dist: float = global_position.distance_to(b.global_position)
		if dist <= tower_attack_range and dist < best_bld_dist:
			best_bld_dist = dist
			best_building = b
	if best_building != null:
		best_building.take_damage(tower_attack_damage)
		if get_tree() and get_tree().current_scene:
			VFX.hit_burst(get_tree(), best_building.global_position, Color(0.8, 0.6, 0.2))
