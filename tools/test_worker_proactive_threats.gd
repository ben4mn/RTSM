extends "res://tools/test_worker_raid_recovery.gd"
## Explicit physical-threat/fog fixtures with production economic orders,
## navigation, harvest and recovery. Paid Combat A/B is a separate scene.

func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_tree().current_scene = null
	for name: String in ["closing", "stationary", "away", "first_near", "attacking", "hidden", "hide_reveal", "scout", "move", "stop", "attack", "delivery", "return_only", "build"]:
		_case_name = name
		await _fixture()
		_proactive_case(name)
		_map.free()
		await get_tree().process_frame
	if _failures.is_empty():
		print("[PASS] worker_proactive_threats:14 cases, relative closing/attacking/near reach, stationary/away/hidden/scout exclusions, hidden-cache pruning, Move/Stop/Attack ownership, cargo/return-only delivery and true Build recovery")
	else:
		for failure: String in _failures:
			push_error("[FAIL] worker_proactive_threats: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _proactive_case(name: String) -> void:
	_expect(_worker.command_gather(_wood), "production gather order rejected")
	var enemy: UnitBase = _enemy(Vector2i(16, 18))
	enemy.global_position = _worker.global_position + Vector2(100, 0)
	enemy.set_state(UnitBase.State.MOVING)
	if name == "closing":
		_step(0.3)
		enemy.global_position = _worker.global_position + Vector2(75, 0)
		_step(0.3)
		_expect(_worker.is_auto_recovering() and _worker.hp == 25, "observed closing must protect before damage")
		return
	if name == "stationary" or name == "away":
		enemy.global_position = _worker.global_position + Vector2(70, 0)
		enemy.set_state(UnitBase.State.IDLE if name == "stationary" else UnitBase.State.MOVING)
		_step(0.3)
		if name == "away":
			enemy.global_position = _worker.global_position + Vector2(85, 0)
		_step(0.5)
		_expect(not _worker.is_auto_recovering(), "stationary distant or moving-away unit caused false evacuation")
		return
	if name == "first_near":
		enemy.global_position = _worker.global_position + Vector2(20, 0)
		enemy.set_state(UnitBase.State.IDLE)
		_step(0.25)
		_expect(_worker.is_auto_recovering() and _worker.hp == 25, "first-observed melee reach needs immediate protection")
		return
	if name == "hidden" or name == "hide_reveal":
		if name == "hide_reveal":
			_step(0.3)
			_expect(_worker.get("_observed_worker_threat_distances").has(enemy.get_instance_id()), "visible motion sample was not retained")
		enemy.global_position = _worker.global_position + Vector2(70, 0)
		enemy.set_state(UnitBase.State.ATTACKING if name == "hidden" else UnitBase.State.MOVING)
		var tile: Vector2i = _map.world_to_tile(enemy.global_position)
		var fog: FogManager = _map.get_node("FogOfWar") as FogManager
		fog.fog_grid[tile.y][tile.x] = MapData.FogState.EXPLORED
		_step(0.3)
		_expect(not _worker.is_auto_recovering() and not _worker.get("_observed_worker_threat_distances").has(enemy.get_instance_id()), "hidden live enemy affected protection or remained cached")
		if name == "hide_reveal":
			fog.fog_grid[tile.y][tile.x] = MapData.FogState.VISIBLE
			_step(0.3)
			_expect(not _worker.is_auto_recovering(), "reveal compared against stale unseen motion")
			enemy.global_position = _worker.global_position + Vector2(60, 0)
			_step(0.3)
			_expect(_worker.is_auto_recovering(), "newly observed closing after reveal was ignored")
		return
	if name == "scout":
		enemy.free()
		enemy = (load("res://scenes/units/scout.tscn") as PackedScene).instantiate() as UnitBase
		enemy.player_owner = 1
		_map.get_node("UnitsContainer").add_child(enemy)
		enemy.set_process(false)
		enemy.global_position = _worker.global_position + Vector2(10, 0)
		enemy.set_state(UnitBase.State.ATTACKING)
		_step(0.5)
		_expect(enemy.damage == 0 and not _worker.is_auto_recovering(), "unarmed Scout evacuated workers")
		return
	if name in ["move", "stop", "attack"]:
		if name == "move":
			_worker.command_move(_map.tile_to_world(Vector2i(18, 18)))
		elif name == "stop":
			_worker.command_stop()
		else:
			_worker.command_attack(enemy)
		enemy.global_position = _worker.global_position + Vector2(70, 0)
		enemy.set_state(UnitBase.State.ATTACKING)
		_step(0.5)
		_expect(not _worker.is_auto_recovering() and _worker.get("_observed_worker_threat_distances").is_empty(), "visible threat overrode explicit " + name)
		return
	var cargo_before: int = 0
	var house: BuildingBase = null
	if name in ["delivery", "return_only"]:
		_expect(_until(func() -> bool: return _worker.carried_amount > 0, 4.0), "worker never naturally harvested partial cargo")
		cargo_before = _worker.carried_amount
		if name == "return_only":
			_worker.command_stop()
		_expect(cargo_before > 0 and _worker.command_return_resources() and _worker.is_returning_resources(), "natural partial load must accept a real depot path")
		if name == "return_only":
			_expect(_worker.get_economy_task() == "", "return-only cargo delivery invented gather employment")
	elif name == "build":
		house = HOUSE_SCENE.instantiate() as BuildingBase
		house.player_owner = 0
		house.global_position = _map.tile_to_world(Vector2i(13, 19))
		_map.get_node("BuildingsContainer").add_child(house)
		house.start_construction()
		_worker.command_build(house)
		_expect(_worker.has_active_build_order(), "accepted construction API missing before threat")
	enemy.global_position = _worker.global_position + Vector2(70, 0)
	enemy.set_state(UnitBase.State.ATTACKING)
	_step(0.3)
	_expect(_worker.is_auto_recovering() and _worker.hp == 25, "attacking military did not protect economic " + name)
	if name == "build":
		_expect(_worker.has_active_build_order() and _worker.build_target == house, "proactive retreat lost construction ownership")
	if name in ["delivery", "return_only"]:
		_expect(_worker.carried_amount == cargo_before, "proactive retreat changed existing cargo")
	enemy.free()
	_expect(_until(func() -> bool: return not _worker.is_auto_recovering(), 30.0), "clear threat did not resume economic " + name)
	if name == "build":
		_expect(_worker.has_active_build_order(), "resumed true Build ownership missing")
	if name in ["delivery", "return_only"]:
		_expect(_until(func() -> bool: return int(_deposits["wood"]) >= cargo_before, 30.0), "resumed delivery did not return exact old cargo")
		if name == "return_only":
			_expect(int(_deposits["wood"]) == cargo_before and _worker.current_state == UnitBase.State.IDLE and _worker.get_economy_task() == "", "proactive return-only delivery must finish exact cargo and remain unassigned")
