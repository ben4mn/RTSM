extends Node
## A normal paid Warrior from a fixture Barracks must engage on its rally,
## resume the accepted destination afterward, and honor an explicit Move.

var _failures: Array[String] = []
var _match: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	_match = load("res://scenes/main/main.tscn").instantiate()
	add_child(_match)
	for frame: int in range(900):
		if GameManager.current_state == GameManager.GameState.PLAYING and _match.get("_building_placement") != null: break
		await get_tree().process_frame
	_match.set_process(false)
	_match.get("ai_controller").get("_decision_timer").stop()
	for owner_units: Array in _match.get("_player_units"):
		for existing: UnitBase in owner_units: existing.set_process(false)
	var map: Node2D = _match.get("game_map") as Node2D
	var origin: Vector2i = map.map_generator.spawn_positions[0]
	var barracks: BuildingBase = _match.call("_spawn_building", BuildingData.BuildingType.BARRACKS, 0, origin + Vector2i(0, 6)) as BuildingBase
	barracks.complete_instantly()
	barracks.set_process(false)
	var tc: BuildingBase = (_match.get("_player_buildings") as Array)[0][0] as BuildingBase
	barracks.set_rally_point(tc.global_position + Vector2(128.0, 0.0))
	var q: ProductionQueue = barracks.get_production_queue() as ProductionQueue
	var food_before: int = ResourceManager.get_resource(0, "food")
	var wood_before: int = ResourceManager.get_resource(0, "wood")
	var units: Array = (_match.get("_player_units") as Array)[0] as Array
	var units_before: int = units.size()
	_expect(q.enqueue_unit(UnitData.UnitType.INFANTRY), "ordinary starting resources pay for a Warrior")
	q.advance(q.current_train_time + 0.01)
	_expect(units.size() == units_before + 1, "Warrior completes exactly once")
	_expect(ResourceManager.get_resource(0, "food") == food_before - 50 and ResourceManager.get_resource(0, "wood") == wood_before - 20, "real Warrior transaction deducts 50 Food and 20 Wood")
	if units.size() == units_before + 1:
		var fighter: UnitBase = units.back() as UnitBase
		fighter.set_process(false)
		var destination: Vector2 = fighter.move_target
		var enemy: UnitBase = (_match.get("_player_units") as Array)[1][0] as UnitBase
		enemy.global_position = fighter.global_position + Vector2(12.0, 0.0)
		_match.call("_update_fog_of_war")
		_expect(fighter.current_state == UnitBase.State.MOVING and fighter.attack_move, "production gives its Warrior a smart rally")
		_expect(not bool(fighter.get("_force_move_active")), "production does not suppress self-defense")
		fighter.set("_auto_attack_timer", 0.0)
		fighter.call("_try_auto_attack")
		_expect(fighter.current_state == UnitBase.State.ATTACKING and fighter.attack_target == enemy, "visible enemy on the rally route is engaged")
		enemy.die()
		fighter._process(0.01)
		_expect(fighter.current_state == UnitBase.State.MOVING and fighter.move_target == destination, "rally resumes after its combat target dies")
		var second_enemy: UnitBase = (_match.get("_player_units") as Array)[1][0] as UnitBase
		second_enemy.global_position = fighter.global_position + Vector2(12.0, 0.0)
		_match.call("_update_fog_of_war")
		fighter.command_move(destination)
		fighter.set("_auto_attack_timer", 0.0)
		fighter.call("_try_auto_attack")
		_expect(fighter.current_state == UnitBase.State.MOVING and fighter.attack_target == null and bool(fighter.get("_force_move_active")), "explicit player Move still bypasses enemies")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)


func _finish() -> void:
	if is_instance_valid(_match): _match.free()
	if _failures.is_empty():
		print("[PASS] reinforcement_rally: paid Warrior engages, resumes rally, and honors explicit Move")
		get_tree().quit(0)
	else:
		for failure: String in _failures: push_error("[FAIL] reinforcement_rally: " + failure)
		get_tree().quit(1)
