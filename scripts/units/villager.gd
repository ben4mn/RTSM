class_name Villager
extends UnitBase
## Villager unit: can gather resources and construct buildings.

signal resource_deposited(resource_type: String, amount: int)
signal gathering_started(resource_node: Node2D)
signal building_started(building: Node2D)
signal building_completed(building: Node2D)

enum GatherType { NONE, FOOD, WOOD, GOLD }

# Gathering stats
@export var gather_rate: float = 1.0  # resources per gather tick
@export var carry_capacity: int = 10
@export var gather_tick_time: float = 2.0  # seconds between gather ticks

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


func _ready() -> void:
	unit_type = UnitData.UnitType.VILLAGER
	super._ready()
	add_to_group("villagers")


func _process_gathering(delta: float) -> void:
	if gather_target == null or not is_instance_valid(gather_target):
		# Resource depleted or removed
		if carried_amount > 0:
			_find_and_go_to_dropoff()
		else:
			set_state(State.IDLE)
		return

	var dist: float = global_position.distance_to(gather_target.global_position)
	if dist > 20.0:
		# Walk to resource
		var direction: Vector2 = (gather_target.global_position - global_position).normalized()
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
		if amount <= 0:
			# Resource exhausted
			gather_target = null
		return amount
	# Fallback: just produce resources
	return int(gather_rate)


func _find_and_go_to_dropoff() -> void:
	# Find nearest building in player's group that accepts resource drops
	var best_building: Node2D = null
	var best_dist: float = INF
	for building in get_tree().get_nodes_in_group("dropoff_buildings"):
		if not is_instance_valid(building):
			continue
		if building.has_method("get_player_owner") and building.get_player_owner() != player_owner:
			continue
		var dist: float = global_position.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best_building = building
	if best_building != null:
		dropoff_target = best_building
		move_target = best_building.global_position
		set_state(State.MOVING)
		# When we arrive, we will deposit
		arrived_at_destination.connect(_on_arrived_for_dropoff, CONNECT_ONE_SHOT)
	else:
		# No dropoff available, go idle
		set_state(State.IDLE)


func _on_arrived_for_dropoff(_unit: UnitBase) -> void:
	_deposit_resources()
	# Go back to the resource
	if gather_target != null and is_instance_valid(gather_target):
		command_gather(gather_target)
	else:
		set_state(State.IDLE)


func _deposit_resources() -> void:
	if carried_amount <= 0:
		return
	if dropoff_target != null and is_instance_valid(dropoff_target):
		if dropoff_target.has_method("deposit_resource"):
			dropoff_target.deposit_resource(carried_resource_type, carried_amount)
	resource_deposited.emit(carried_resource_type, carried_amount)
	carried_amount = 0


func _process_building(delta: float) -> void:
	if build_target == null or not is_instance_valid(build_target):
		set_state(State.IDLE)
		return

	var dist: float = global_position.distance_to(build_target.global_position)
	if dist > 24.0:
		# Walk to building site
		var direction: Vector2 = (build_target.global_position - global_position).normalized()
		global_position += direction * speed * delta
		return

	# We are at the building, construct
	build_timer += delta
	if build_target.has_method("add_build_progress"):
		build_target.add_build_progress(delta)
		if build_target.has_method("is_construction_complete") and build_target.is_construction_complete():
			building_completed.emit(build_target)
			build_target = null
			set_state(State.IDLE)


# --- Commands ---

func command_gather(resource_node: Node2D) -> void:
	if current_state == State.DEAD:
		return
	gather_target = resource_node
	gather_timer = 0.0

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
	build_target = building_site
	build_timer = 0.0
	building_started.emit(building_site)
	set_state(State.BUILDING)


# --- Override draw for carried resource indicator ---

func _draw() -> void:
	super._draw()
	# Show a small colored dot for carried resources
	if carried_amount > 0:
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
		draw_circle(Vector2(size + 3.0, 0), 3.0, res_color)
