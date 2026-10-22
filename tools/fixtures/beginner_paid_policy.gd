extends AIController
## A repeatable slower learner proxy, not a model of measured human skill.
## The unchanged Medium policy supplies decisions; this fixture deliberately
## spaces inputs and makes one recovery retreat after a natural combat loss.

const OPENING_DELAY: float = 18.0
const DECISION_SECONDS: float = 6.0
const TRAIN_SECONDS: float = 18.0
const BUILD_SECONDS: float = 20.0
const FIRST_BARRACKS: float = 90.0
const FIELD_ORDERS_AT: float = 240.0
const RECOVERY_SECONDS: float = 45.0

var last_train: Dictionary = {}
var last_build: float = -INF
var first_fighter_loss_at: float = -1.0
var recovery_until: float = -1.0
var paid_fighters_after_loss: int = 0
var first_paid_fighter_after_loss: float = -1.0


func _apply_difficulty_profile() -> void:
	difficulty = Difficulty.MEDIUM
	_decision_interval = DECISION_SECONDS
	if _decision_timer != null:
		_decision_timer.wait_time = DECISION_SECONDS


func _on_decision_tick() -> void:
	if _game_time >= OPENING_DELAY:
		super._on_decision_tick()


func accept_train_input(building: Node) -> bool:
	var identifier: int = building.get_instance_id()
	if _game_time - float(last_train.get(identifier, -INF)) < TRAIN_SECONDS:
		return false
	var queue: Node = building.get_production_queue()
	if queue != null and queue.get_queue_size() > 0:
		return false
	last_train[identifier] = _game_time
	return true


func accept_build_input(building_type: int) -> bool:
	if building_type == BuildingData.BuildingType.BARRACKS and _game_time < FIRST_BARRACKS:
		return false
	if _game_time - last_build < BUILD_SECONDS:
		return false
	last_build = _game_time
	return true


func accept_age_input() -> bool:
	return _game_time >= FIELD_ORDERS_AT


func _check_scouting() -> void:
	if _game_time >= FIELD_ORDERS_AT and _game_time >= recovery_until:
		super._check_scouting()


func _micro_damaged_units() -> void:
	pass


func _check_attack_or_defend() -> void:
	if _game_time >= FIELD_ORDERS_AT and _game_time >= recovery_until:
		super._check_attack_or_defend()
		return
	var threats: Array = _find_defense_threats()
	if not threats.is_empty():
		_rally_defense(threats)
		_last_strategy_decision = "learner_home_defense"
		return
	for unit: UnitBase in _get_military_units():
		if unit.current_state == UnitBase.State.IDLE and unit.global_position.distance_to(_base_position) > 96.0:
			unit.command_move(_base_position)
	_last_strategy_decision = "learner_recovery" if _game_time < recovery_until else "learner_opening"


func _on_unit_died(unit: UnitBase) -> void:
	var fighter_lost: bool = unit.unit_type not in [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT]
	super._on_unit_died(unit)
	if fighter_lost and first_fighter_loss_at < 0.0:
		first_fighter_loss_at = _game_time
		recovery_until = _game_time + RECOVERY_SECONDS
		_clear_attack_wave()
		_release_objective_units()
		for survivor: UnitBase in _get_military_units():
			survivor.command_move(_base_position)


func register_unit(unit: Node) -> void:
	var new_unit: bool = unit not in _my_units
	super.register_unit(unit)
	if new_unit and first_fighter_loss_at >= 0.0 and unit.unit_type not in [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT]:
		paid_fighters_after_loss += 1
		if first_paid_fighter_after_loss < 0.0:
			first_paid_fighter_after_loss = _game_time


func get_learner_receipt() -> Dictionary:
	return {"definition": "Slower automated Medium policy; not human play. Normal costs, queues, workers and damage. No injected losses or resources.", "opening_delay": OPENING_DELAY, "decision_seconds": DECISION_SECONDS, "train_input_spacing": TRAIN_SECONDS, "build_input_spacing": BUILD_SECONDS, "first_barracks_at": FIRST_BARRACKS, "field_orders_at": FIELD_ORDERS_AT, "recovery_seconds": RECOVERY_SECONDS, "wounded_unit_micro": false, "first_natural_fighter_loss": first_fighter_loss_at, "recovery_until": recovery_until, "first_paid_fighter_after_loss": first_paid_fighter_after_loss, "paid_fighters_after_loss": paid_fighters_after_loss}
