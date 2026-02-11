class_name ProductionQueue
extends Node
## Handles unit training queue for buildings that can produce units.
## Attaches to a BuildingBase node. Deducts resources on queue, refunds on cancel.

signal unit_queued(unit_type: int)
signal unit_training_started(unit_type: int)
signal unit_training_progress(unit_type: int, progress: float)
signal unit_trained(unit_type: int, spawn_position: Vector2)
signal unit_cancelled(unit_type: int)
signal queue_changed()

const MAX_QUEUE_SIZE := 5

var queue: Array[int] = []  # Array of UnitData.UnitType values
var current_progress: float = 0.0
var current_train_time: float = 0.0
var is_training: bool = false
var _building: BuildingBase = null


func _ready() -> void:
	_building = get_parent() as BuildingBase
	if _building:
		_building.set_production_queue(self)


func _process(delta: float) -> void:
	if not is_training or queue.is_empty():
		return
	if _building and _building.state != BuildingBase.State.ACTIVE:
		return

	current_progress += delta
	var progress_ratio := current_progress / current_train_time if current_train_time > 0 else 1.0
	unit_training_progress.emit(queue[0], clampf(progress_ratio, 0.0, 1.0))

	if current_progress >= current_train_time:
		_complete_current_unit()


func enqueue_unit(unit_type: int) -> bool:
	if queue.size() >= MAX_QUEUE_SIZE:
		return false
	if _building and _building.state != BuildingBase.State.ACTIVE:
		return false
	if unit_type not in _building.trainable_units:
		return false

	# Check and deduct resources
	var cost := UnitData.get_unit_cost(unit_type)
	if not _can_afford(cost):
		return false
	_deduct_resources(cost)

	queue.append(unit_type)
	unit_queued.emit(unit_type)
	queue_changed.emit()

	if not is_training:
		_start_next_unit()
	return true


func cancel_unit(index: int) -> bool:
	if index < 0 or index >= queue.size():
		return false

	var unit_type: int = queue[index]
	var cost := UnitData.get_unit_cost(unit_type)

	# Refund resources
	_refund_resources(cost)

	queue.remove_at(index)
	unit_cancelled.emit(unit_type)
	queue_changed.emit()

	if index == 0:
		# Cancelled the currently training unit
		is_training = false
		current_progress = 0.0
		current_train_time = 0.0
		if not queue.is_empty():
			_start_next_unit()

	return true


func cancel_last() -> bool:
	if queue.is_empty():
		return false
	return cancel_unit(queue.size() - 1)


func get_queue_size() -> int:
	return queue.size()


func get_current_progress() -> float:
	if not is_training or current_train_time <= 0:
		return 0.0
	return clampf(current_progress / current_train_time, 0.0, 1.0)


func get_queue_info() -> Array[Dictionary]:
	var info: Array[Dictionary] = []
	for i in queue.size():
		info.append({
			"unit_type": queue[i],
			"name": UnitData.get_unit_name(queue[i]),
			"is_training": i == 0 and is_training,
			"progress": get_current_progress() if i == 0 else 0.0,
		})
	return info


func _start_next_unit() -> void:
	if queue.is_empty():
		is_training = false
		return
	var unit_type: int = queue[0]
	var stats := UnitData.get_unit_stats(unit_type)
	current_train_time = stats.get("build_time", 15.0)
	current_progress = 0.0
	is_training = true
	unit_training_started.emit(unit_type)


func _complete_current_unit() -> void:
	if queue.is_empty():
		return
	var unit_type: int = queue[0]
	var spawn_pos := _building.rally_point if _building else global_position
	queue.remove_at(0)
	is_training = false
	current_progress = 0.0
	current_train_time = 0.0

	unit_trained.emit(unit_type, spawn_pos)
	queue_changed.emit()

	if not queue.is_empty():
		_start_next_unit()


func _can_afford(cost: Dictionary) -> bool:
	var rm := _get_resource_manager()
	if rm == null:
		return true  # Allow for testing without ResourceManager
	var player_id: int = _building.player_owner if _building else 0
	return rm.can_afford(player_id, cost)


func _deduct_resources(cost: Dictionary) -> void:
	var rm := _get_resource_manager()
	if rm == null:
		return
	var player_id: int = _building.player_owner if _building else 0
	rm.try_spend(player_id, cost)


func _refund_resources(cost: Dictionary) -> void:
	var rm := _get_resource_manager()
	if rm == null:
		return
	var player_id: int = _building.player_owner if _building else 0
	rm.refund(player_id, cost)


func _get_resource_manager() -> Node:
	if has_node("/root/ResourceManager"):
		return get_node("/root/ResourceManager")
	return null
