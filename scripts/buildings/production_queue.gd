class_name ProductionQueue
extends Node
## Handles unit training queue for buildings that can produce units.
## Attaches to a BuildingBase node. Deducts resources on queue, refunds on cancel.

signal unit_queued(unit_type: int)
signal unit_training_started(unit_type: int)
signal unit_training_progress(unit_type: int, progress: float)
signal unit_trained(unit_type: int)
signal unit_cancelled(unit_type: int)
signal queue_changed()

const MAX_QUEUE_SIZE := 5
const AUTO_QUEUE_RETRY_INTERVAL := 0.5

var queue: Array[int] = []  # Array of UnitData.UnitType values
var current_progress: float = 0.0
var current_train_time: float = 0.0
var is_training: bool = false
var _building: BuildingBase = null
var _population_reservation_ids: Array[int] = []
var _pending_completion_reservation_id: int = -1
var _pending_completion_unit_type: int = -1

# Auto-queue
var auto_queue_enabled: bool = false
var auto_queue_unit_type: int = -1
var _auto_queue_retry_elapsed: float = 0.0


func _ready() -> void:
	_building = get_parent() as BuildingBase
	if _building:
		_building.set_production_queue(self)
		if not _building.building_destroyed.is_connected(_on_building_destroyed):
			_building.building_destroyed.connect(_on_building_destroyed)


func _exit_tree() -> void:
	_release_all_population_reservations()


func advance(delta: float) -> void:
	if not is_instance_valid(_building):
		is_training = false
		return
	if _building.state != BuildingBase.State.ACTIVE:
		return
	if queue.is_empty():
		retry_auto_queue(delta)
		return
	if not is_training:
		return

	current_progress += delta
	var progress_ratio := current_progress / current_train_time if current_train_time > 0 else 1.0
	if not queue.is_empty():
		unit_training_progress.emit(queue[0], clampf(progress_ratio, 0.0, 1.0))

	if current_progress >= current_train_time:
		_complete_current_unit()


func retry_auto_queue(delta: float) -> bool:
	## An empty repeat queue can be waiting for a deposit or new housing. Retry
	## at most once per interval through the same paid reservation transaction.
	if not is_instance_valid(_building) or _building.state != BuildingBase.State.ACTIVE:
		_auto_queue_retry_elapsed = 0.0
		return false
	if not auto_queue_enabled or auto_queue_unit_type < 0 or not queue.is_empty():
		_auto_queue_retry_elapsed = 0.0
		return false
	_auto_queue_retry_elapsed += maxf(0.0, delta)
	if _auto_queue_retry_elapsed < AUTO_QUEUE_RETRY_INTERVAL:
		return false
	_auto_queue_retry_elapsed = 0.0
	return enqueue_unit(auto_queue_unit_type)


func enqueue_unit(unit_type: int) -> bool:
	if queue.size() >= MAX_QUEUE_SIZE:
		return false
	if not is_instance_valid(_building) or _building.state != BuildingBase.State.ACTIVE:
		return false
	if unit_type not in _building.trainable_units:
		return false

	# Resource spending and population reservation form one transaction. If
	# either side rejects the unit, roll the other side back before returning.
	var cost: Dictionary = UnitData.get_unit_cost(unit_type)
	if not _can_afford(cost):
		return false
	var pop_cost: int = int(UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1))
	var reservation_id: int = GameManager.reserve_population(_building.player_owner, pop_cost)
	if reservation_id < 0:
		return false
	if not _deduct_resources(cost):
		GameManager.release_population_reservation(reservation_id)
		return false

	queue.append(unit_type)
	_population_reservation_ids.append(reservation_id)
	auto_queue_unit_type = unit_type
	_auto_queue_retry_elapsed = 0.0
	unit_queued.emit(unit_type)
	queue_changed.emit()

	if not is_training:
		_start_next_unit()
	return true


func cancel_unit(index: int) -> bool:
	if index < 0 or index >= queue.size():
		return false

	var unit_type: int = queue[index]
	var cost: Dictionary = UnitData.get_unit_cost(unit_type)
	var reservation_id: int = _population_reservation_ids[index] if index < _population_reservation_ids.size() else -1

	# Refund resources
	_refund_resources(cost)
	if reservation_id >= 0:
		GameManager.release_population_reservation(reservation_id)

	queue.remove_at(index)
	if index < _population_reservation_ids.size():
		_population_reservation_ids.remove_at(index)
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
	var stats: Dictionary = UnitData.get_unit_stats(unit_type)
	current_train_time = stats.get("build_time", 15.0)
	current_progress = 0.0
	is_training = true
	unit_training_started.emit(unit_type)


func _complete_current_unit() -> void:
	if queue.is_empty():
		return
	var unit_type: int = queue[0]
	var reservation_id: int = _population_reservation_ids[0] if not _population_reservation_ids.is_empty() else -1
	queue.remove_at(0)
	if not _population_reservation_ids.is_empty():
		_population_reservation_ids.remove_at(0)
	is_training = false
	current_progress = 0.0
	current_train_time = 0.0
	_auto_queue_retry_elapsed = 0.0

	if reservation_id < 0:
		push_warning("Discarded trained unit %d because its population reservation was unavailable" % unit_type)
		_refund_resources(UnitData.get_unit_cost(unit_type))
	else:
		# Signals are synchronous. The spawn callback consumes this reservation
		# only after it has validated the scene, destination container, and a legal
		# egress beside this queue's building. Spatial spawn/rally policy belongs to
		# match orchestration, so the queue never exposes a rally point as a spawn.
		_pending_completion_reservation_id = reservation_id
		_pending_completion_unit_type = unit_type
		unit_trained.emit(unit_type)
		# An unclaimed synchronous completion is a failed spawn transaction. Return
		# both its population slot and unit cost instead of silently losing either.
		reject_completed_unit()
	queue_changed.emit()

	# Auto-queue: re-enqueue the same unit type
	if auto_queue_enabled and auto_queue_unit_type >= 0:
		enqueue_unit(auto_queue_unit_type)

	if not queue.is_empty() and not is_training:
		_start_next_unit()


func _can_afford(cost: Dictionary) -> bool:
	var rm: Node = _get_resource_manager()
	if rm == null:
		return true  # Allow for testing without ResourceManager
	var player_id: int = _building.player_owner if _building else 0
	return rm.can_afford(player_id, cost)


func _deduct_resources(cost: Dictionary) -> bool:
	var rm: Node = _get_resource_manager()
	if rm == null:
		return true
	var player_id: int = _building.player_owner if _building else 0
	return rm.try_spend(player_id, cost)


func _refund_resources(cost: Dictionary) -> void:
	var rm: Node = _get_resource_manager()
	if rm == null:
		return
	var player_id: int = _building.player_owner if _building else 0
	rm.refund(player_id, cost)


func _get_resource_manager() -> Node:
	if has_node("/root/ResourceManager"):
		return get_node("/root/ResourceManager")
	return null


func get_producing_building() -> BuildingBase:
	if not is_instance_valid(_building):
		return null
	return _building


func consume_completed_population_reservation() -> bool:
	## Called synchronously by the unit spawn listener after spawn validation.
	if _pending_completion_reservation_id < 0:
		return false
	var reservation_id := _pending_completion_reservation_id
	_pending_completion_reservation_id = -1
	_pending_completion_unit_type = -1
	return GameManager.consume_population_reservation(reservation_id)


func reject_completed_unit() -> bool:
	## Roll back a completion that could not produce a unit. This is intentionally
	## distinct from cancellation: training elapsed, but the spawn transaction did
	## not commit, so retaining the spent resources would deadlock progression.
	if _pending_completion_reservation_id < 0:
		return false
	var reservation_id: int = _pending_completion_reservation_id
	var failed_unit_type: int = _pending_completion_unit_type
	_pending_completion_reservation_id = -1
	_pending_completion_unit_type = -1
	var released: bool = GameManager.release_population_reservation(reservation_id)
	if failed_unit_type >= 0:
		_refund_resources(UnitData.get_unit_cost(failed_unit_type))
	return released


func _on_building_destroyed(_destroyed_building: BuildingBase) -> void:
	_release_all_population_reservations()
	queue.clear()
	is_training = false
	current_progress = 0.0
	current_train_time = 0.0
	auto_queue_enabled = false
	_auto_queue_retry_elapsed = 0.0
	queue_changed.emit()


func _release_all_population_reservations() -> void:
	for reservation_id in _population_reservation_ids:
		GameManager.release_population_reservation(reservation_id)
	_population_reservation_ids.clear()
	reject_completed_unit()
