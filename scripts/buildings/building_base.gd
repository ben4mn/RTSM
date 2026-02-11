class_name BuildingBase
extends Area2D
## Base building for all structures in AOEM.
## Handles construction progress, health, selection, and placeholder rendering.

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


func _ready() -> void:
	_load_stats()
	_setup_collision()
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


func _setup_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var pixel_w: float = footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = footprint.y * MapData.TILE_HEIGHT
	rect.size = Vector2(pixel_w, pixel_h)
	shape.shape = rect
	add_child(shape)


func _draw() -> void:
	var pixel_w: float = footprint.x * MapData.TILE_WIDTH
	var pixel_h: float = footprint.y * MapData.TILE_HEIGHT
	# Draw isometric diamond shape
	var points := PackedVector2Array([
		Vector2(0, -pixel_h * 0.5),       # top
		Vector2(pixel_w * 0.5, 0),         # right
		Vector2(0, pixel_h * 0.5),         # bottom
		Vector2(-pixel_w * 0.5, 0),        # left
	])

	var color := building_color
	if state == State.CONSTRUCTING:
		color = color.darkened(0.3 * (1.0 - build_progress))
	elif state == State.DESTROYED:
		color = Color(0.2, 0.2, 0.2, 0.5)

	draw_colored_polygon(points, color)

	# Outline
	var outline_color := Color.WHITE if is_selected else Color(0.1, 0.1, 0.1, 0.6)
	var outline_width := 2.0 if is_selected else 1.0
	for i in points.size():
		var next_i := (i + 1) % points.size()
		draw_line(points[i], points[next_i], outline_color, outline_width)

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

	# Rally point indicator
	if is_selected and state == State.ACTIVE and trainable_units.size() > 0:
		var rp_local := rally_point - global_position
		draw_circle(rp_local, 4.0, Color(0.2, 0.6, 1.0, 0.7))


func _process(_delta: float) -> void:
	if state == State.CONSTRUCTING or (state == State.ACTIVE and hp < max_hp) or is_selected:
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
	queue_redraw()


## Instantly finish construction (for starting town center, debug).
func complete_instantly() -> void:
	state = State.ACTIVE
	build_progress = 1.0
	hp = max_hp
	construction_complete.emit(self)
	queue_redraw()


func _complete_construction() -> void:
	state = State.ACTIVE
	hp = max_hp
	build_progress = 1.0
	construction_complete.emit(self)
	queue_redraw()


func take_damage(amount: int) -> void:
	if state == State.DESTROYED:
		return
	hp = maxi(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	if hp <= 0:
		_destroy()
	queue_redraw()


func _destroy() -> void:
	state = State.DESTROYED
	building_destroyed.emit(self)
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


func get_production_queue() -> Node:
	return _production_queue


func set_production_queue(queue: Node) -> void:
	_production_queue = queue
