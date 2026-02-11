class_name Villager
extends UnitBase
## Villager unit: can gather resources and construct buildings.

signal resource_deposited(resource_type: String, amount: int)
signal gathering_started(resource_node: Node2D)
signal building_started(building: Node2D)
signal building_completed(building: Node2D)

enum GatherType { NONE, FOOD, WOOD, GOLD }

# Gathering stats
@export var gather_rate: float = 2.0  # resources per gather tick
@export var carry_capacity: int = 15
@export var gather_tick_time: float = 1.5  # seconds between gather ticks

# Gathering state
var gather_target: Node2D = null
var gather_type: int = GatherType.NONE
var carried_resource_type: String = ""
var carried_amount: int = 0
var gather_timer: float = 0.0
var dropoff_target: Node2D = null

# Building state
var build_target: Node2D = null
var build_timer: float = 0.0
var _gather_offset: Vector2 = Vector2.ZERO  # Small random offset to prevent villager stacking

# Saved gather state (restored after building completes)
var _saved_gather_target: Node2D = null
var _saved_gather_type: int = GatherType.NONE
var _saved_carried_resource_type: String = ""


func _ready() -> void:
	unit_type = UnitData.UnitType.VILLAGER
	super._ready()
	add_to_group("villagers")


## Villagers don't auto-attack; they stay focused on economic tasks.
func _try_auto_attack() -> void:
	pass


## Villagers flee toward nearest friendly building when attacked.
func take_damage(amount: float) -> void:
	super.take_damage(amount)
	if current_state == State.DEAD:
		return
	# Only flee if gathering or idle (not if player explicitly commanded an attack)
	if current_state == State.GATHERING or current_state == State.IDLE:
		_flee_to_safety()


func _process_gathering(delta: float) -> void:
	if gather_target == null or not is_instance_valid(gather_target):
		# Resource depleted or removed
		if carried_amount > 0:
			_find_and_go_to_dropoff()
		elif not _try_retarget_resource():
			set_state(State.IDLE)
		return

	var approach_pos: Vector2 = gather_target.global_position + _gather_offset
	var dist: float = global_position.distance_to(approach_pos)
	if dist > 28.0:
		# Walk to resource (with offset to spread villagers)
		var direction: Vector2 = (approach_pos - global_position).normalized()
		global_position += direction * speed * delta
		return

	# We are at the resource, gather
	gather_timer += delta
	if gather_timer >= gather_tick_time:
		gather_timer = 0.0
		var gathered: int = _harvest_from_target()
		carried_amount += gathered

		if carried_amount >= carry_capacity:
			_find_and_go_to_dropoff()


func _harvest_from_target() -> int:
	# Try calling harvest on the resource node if it has the method
	if gather_target.has_method("harvest"):
		var amount: int = gather_target.harvest(int(gather_rate))
		if amount > 0 and is_instance_valid(gather_target) and get_tree() and get_tree().current_scene:
			VFX.gather_particles(get_tree(), gather_target.global_position, carried_resource_type)
		if amount <= 0:
			# Resource exhausted
			gather_target = null
		return amount
	# Fallback: just produce resources
	return int(gather_rate)


func _find_and_go_to_dropoff() -> void:
	# Find nearest building that accepts this specific resource type, fall back to any dropoff
	var best_specific: Node2D = null
	var best_specific_dist: float = INF
	var best_any: Node2D = null
	var best_any_dist: float = INF
	for building in get_tree().get_nodes_in_group("dropoff_buildings"):
		if not is_instance_valid(building):
			continue
		if building.has_method("get_player_owner") and building.get_player_owner() != player_owner:
			continue
		var dist: float = global_position.distance_to(building.global_position)
		# Check if this building specifically accepts our resource type
		if building.has_method("is_drop_off_point") and building.is_drop_off_point(carried_resource_type):
			if dist < best_specific_dist:
				best_specific_dist = dist
				best_specific = building
		if dist < best_any_dist:
			best_any_dist = dist
			best_any = building
	# Prefer specific drop-off (lumber camp for wood, mining camp for gold)
	# But use any drop-off if it's much closer (within 30% distance)
	var best_building: Node2D = null
	if best_specific != null:
		if best_any != null and best_any_dist < best_specific_dist * 0.3:
			best_building = best_any
		else:
			best_building = best_specific
	else:
		best_building = best_any
	if best_building != null:
		dropoff_target = best_building
		move_target = best_building.global_position
		set_state(State.MOVING)
		# Disconnect any stale one-shot before reconnecting
		if arrived_at_destination.is_connected(_on_arrived_for_dropoff):
			arrived_at_destination.disconnect(_on_arrived_for_dropoff)
		arrived_at_destination.connect(_on_arrived_for_dropoff, CONNECT_ONE_SHOT)
	else:
		# No dropoff available, go idle
		set_state(State.IDLE)


func _on_arrived_for_dropoff(_unit: UnitBase) -> void:
	_deposit_resources()
	# Go back to the resource
	if gather_target != null and is_instance_valid(gather_target):
		command_gather(gather_target)
	elif not _try_retarget_resource():
		set_state(State.IDLE)


func _deposit_resources() -> void:
	if carried_amount <= 0:
		return
	var deposited_amount: int = carried_amount
	var deposited_type: String = carried_resource_type
	if dropoff_target != null and is_instance_valid(dropoff_target):
		if dropoff_target.has_method("deposit_resource"):
			dropoff_target.deposit_resource(carried_resource_type, carried_amount)
	resource_deposited.emit(carried_resource_type, carried_amount)
	carried_amount = 0
	# Floating resource text
	if get_tree():
		var float_color: Color
		match deposited_type:
			"food": float_color = Color(0.95, 0.4, 0.3)
			"wood": float_color = Color(0.45, 0.8, 0.3)
			"gold": float_color = Color(0.95, 0.85, 0.2)
			_: float_color = Color.WHITE
		VFX.resource_float(get_tree(), global_position, "+%d %s" % [deposited_amount, deposited_type.capitalize()], float_color)


func _process_building(delta: float) -> void:
	if build_target == null or not is_instance_valid(build_target):
		_resume_or_idle()
		return

	var dist: float = global_position.distance_to(build_target.global_position)
	if dist > 32.0:
		# Walk to building site
		var direction: Vector2 = (build_target.global_position - global_position).normalized()
		global_position += direction * speed * delta
		return

	# We are at the building, construct
	build_timer += delta
	if build_target.has_method("add_build_progress"):
		build_target.add_build_progress(delta)
		if not is_instance_valid(build_target):
			build_target = null
			_resume_or_idle()
			return
		if build_target.has_method("is_construction_complete") and build_target.is_construction_complete():
			building_completed.emit(build_target)
			build_target = null
			_resume_or_idle()


# --- Commands ---

func command_gather(resource_node: Node2D) -> void:
	if current_state == State.DEAD:
		return
	gather_target = resource_node
	gather_timer = 0.0
	# Small random offset so multiple villagers don't stack on the exact same pixel
	_gather_offset = Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 6.0))

	# Determine resource type from the target
	if resource_node.has_method("get_resource_type"):
		carried_resource_type = resource_node.get_resource_type()
	elif resource_node.is_in_group("food_resources"):
		carried_resource_type = "food"
	elif resource_node.is_in_group("wood_resources"):
		carried_resource_type = "wood"
	elif resource_node.is_in_group("gold_resources"):
		carried_resource_type = "gold"
	else:
		carried_resource_type = "food"  # default

	# Determine gather type enum
	match carried_resource_type:
		"food":
			gather_type = GatherType.FOOD
		"wood":
			gather_type = GatherType.WOOD
		"gold":
			gather_type = GatherType.GOLD
		_:
			gather_type = GatherType.NONE

	gathering_started.emit(resource_node)
	set_state(State.GATHERING)


func command_build(building_site: Node2D) -> void:
	if current_state == State.DEAD:
		return
	# Save current gather state so we can resume after building.
	if current_state == State.GATHERING:
		_saved_gather_target = gather_target
		_saved_gather_type = gather_type
		_saved_carried_resource_type = carried_resource_type
	else:
		_saved_gather_target = null
		_saved_gather_type = GatherType.NONE
		_saved_carried_resource_type = ""
	build_target = building_site
	build_timer = 0.0
	building_started.emit(building_site)
	set_state(State.BUILDING)


func _resume_or_idle() -> void:
	if _saved_gather_target != null and is_instance_valid(_saved_gather_target):
		command_gather(_saved_gather_target)
	elif not _try_retarget_resource():
		set_state(State.IDLE)
	_saved_gather_target = null
	_saved_gather_type = GatherType.NONE
	_saved_carried_resource_type = ""


func _flee_to_safety() -> void:
	## Run to the nearest friendly building (preferably Town Center).
	var best_building: Node2D = null
	var best_dist: float = INF
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or not (building is BuildingBase):
			continue
		if (building as BuildingBase).player_owner != player_owner:
			continue
		if (building as BuildingBase).state == BuildingBase.State.DESTROYED:
			continue
		var dist: float = global_position.distance_to(building.global_position)
		# Prefer Town Center (halve effective distance)
		if (building as BuildingBase).building_type == BuildingData.BuildingType.TOWN_CENTER:
			dist *= 0.5
		if dist < best_dist:
			best_dist = dist
			best_building = building
	if best_building != null:
		command_move(best_building.global_position)


func _try_retarget_resource() -> bool:
	if carried_resource_type == "":
		return false
	# Walk up the tree to find GameMap which has get_nearest_resource_node()
	var game_map: Node2D = null
	var parent: Node = get_parent()
	while parent != null:
		if parent.has_method("get_nearest_resource_node"):
			game_map = parent as Node2D
			break
		parent = parent.get_parent()
	if game_map == null:
		return false
	var new_target: Node2D = game_map.get_nearest_resource_node(carried_resource_type, global_position)
	if new_target != null and is_instance_valid(new_target):
		command_gather(new_target)
		return true
	return false


# --- Override draw for carried resource indicator ---

func _draw() -> void:
	super._draw()
	# Show resource indicator when gathering or carrying resources
	if current_state == State.GATHERING or carried_amount > 0:
		var res_color: Color
		match carried_resource_type:
			"food":
				res_color = Color(1.0, 0.3, 0.3)  # red
			"wood":
				res_color = Color(0.5, 0.3, 0.1)  # brown
			"gold":
				res_color = Color(1.0, 0.85, 0.0) # gold
			_:
				res_color = Color.WHITE
		var size: float = UNIT_SIZES.get(unit_type, 8.0)
		var dot_pos := Vector2(size + 4.0, 0)
		# Black outline
		draw_circle(dot_pos, 6.0, Color(0, 0, 0, 0.6))
		# Colored dot (larger)
		draw_circle(dot_pos, 5.0, res_color)
