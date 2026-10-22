extends AIController
## Test-only purchaser. All resources, labor, ages and queues remain ordinary.
## A fixed desired roster replaces counter selection; field orders are disabled.
var roster: Dictionary = {UnitData.UnitType.INFANTRY: 3, UnitData.UnitType.ARCHER: 3}


func _on_decision_tick() -> void:
	# Main registers owner 1 immediately; the test observer registers owner 0
	# between frames. Remove that observer-order asymmetry before purchasing.
	for unit: UnitBase in get_tree().get_nodes_in_group("units"):
		if unit.player_owner == player_id and unit.current_state != UnitBase.State.DEAD:
			register_unit(unit)
	super._on_decision_tick()


func _check_military_production() -> void:
	for role: int in roster:
		var count: int = _count_queued_unit(role)
		# A freshly completed human queue can precede the observer's next frame.
		# Count live scene units so that registration delay cannot overbuy a role.
		for unit: UnitBase in get_tree().get_nodes_in_group("units"):
			if unit.player_owner == player_id and unit.unit_type == role and unit.current_state != UnitBase.State.DEAD:
				count += 1
		var target: int = int(roster[role])
		if GameManager.get_player_age(player_id) < 2:
			target = mini(target, 2) if role == UnitData.UnitType.INFANTRY else 0
		if count < target and _try_train_from_building(_get_training_building_type_for_unit(role), role):
			return


func _get_min_military_for_age_up(_target_age: int) -> int:
	return 2


func _get_target_villager_count() -> int:
	return 10


func _get_compact_missing_role_building() -> int:
	return -1


func _needs_compact_siege_purchase() -> bool:
	return false


func _check_age_up() -> void:
	if GameManager.get_player_age(player_id) < 2:
		super._check_age_up()


func _update_age_up_reserve() -> void:
	if GameManager.get_player_age(player_id) < 2:
		super._update_age_up_reserve()
	else:
		_saving_for_age_up = false
		_timed_age_up_reserve_active = false


func _get_target_building_counts(age: int) -> Dictionary:
	var counts: Dictionary = super._get_target_building_counts(age)
	counts[BuildingData.BuildingType.ARCHERY_RANGE] = 1 if age >= 2 and roster.has(UnitData.UnitType.ARCHER) else 0
	counts[BuildingData.BuildingType.STABLE] = 1 if age >= 2 and roster.has(UnitData.UnitType.CAVALRY) else 0
	for kind: int in [BuildingData.BuildingType.BLACKSMITH, BuildingData.BuildingType.WATCH_TOWER, BuildingData.BuildingType.SIEGE_WORKSHOP]:
		counts[kind] = 0
	return counts


func _check_scouting() -> void:
	pass


func _micro_damaged_units() -> void:
	pass


func _check_attack_or_defend() -> void:
	pass


func _check_research() -> void:
	pass
