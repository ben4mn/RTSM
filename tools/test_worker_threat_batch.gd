extends "res://tools/test_worker_raid_recovery.gd"
## Canonical per-entity visibility is the independent oracle for fresh batching.
## Synthetic poses test owner-0 fog and owner-1 live allied vision separately.


func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_tree().current_scene = null
	for owner: int in [0, 1]:
		_case_name = "owner_%d" % owner
		await _fixture()
		_worker.player_owner = owner
		_tc.free()
		_worker.vision_radius = 0.0
		_run_visibility_cases(owner)
		_map.free()
		await get_tree().process_frame
	if _failures.is_empty():
		print("[PASS] worker_threat_batch: both visibility owners, exact original candidate order, allied live vision, source movement/death/deletion, fog edge, off-map fallback, dead/unarmed/passive-worker exclusions, far-motion retention and boundary closing")
	else:
		for failure: String in _failures:
			push_error("[FAIL] worker_threat_batch: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _run_visibility_cases(owner: int) -> void:
	var enemy: UnitBase = _enemy(Vector2i(18, 18))
	enemy.player_owner = 1 - owner
	enemy.current_state = UnitBase.State.ATTACKING
	_refresh_local_fog()
	_expect_oracle("hidden attacking enemy")
	_expect(_worker._get_visible_economic_threats().is_empty(), "hidden attacker became known")
	var scout: UnitBase = _unit("scout", owner, Vector2i(17, 18))
	scout.vision_radius = MapData.range_tiles_to_world(1.0)
	_refresh_local_fog()
	_expect_oracle("ally reveals exact radius edge")
	_expect(_worker._get_visible_economic_threats().has(enemy), "allied live source did not reveal radius edge")
	scout.global_position = _map.tile_to_world(Vector2i(16, 18))
	_refresh_local_fog()
	_expect_oracle("source moves beyond radius edge")
	_expect(not _worker._get_visible_economic_threats().has(enemy), "stale source position revealed hidden enemy")
	scout.global_position = enemy.global_position
	_refresh_local_fog()
	_expect_oracle("source moves back")
	scout.current_state = UnitBase.State.DEAD
	_refresh_local_fog()
	_expect_oracle("dead source")
	_expect(not _worker._get_visible_economic_threats().has(enemy), "dead allied source revealed enemy")
	scout.current_state = UnitBase.State.IDLE
	scout.free()
	_refresh_local_fog()
	_expect_oracle("deleted source")
	_expect(not _worker._get_visible_economic_threats().has(enemy), "deleted allied source revealed enemy")
	_worker.vision_radius = 1000.0
	var ally: UnitBase = _unit("infantry", owner, Vector2i(13, 18))
	ally.current_state = UnitBase.State.ATTACKING
	var unarmed: UnitBase = _unit("scout", 1 - owner, Vector2i(14, 18))
	unarmed.current_state = UnitBase.State.ATTACKING
	var dead: UnitBase = _unit("infantry", 1 - owner, Vector2i(15, 18))
	dead.current_state = UnitBase.State.DEAD
	var passive: UnitBase = _unit("villager", 1 - owner, Vector2i(16, 18))
	_refresh_local_fog()
	_expect_oracle("ally unarmed dead passive exclusions")
	_expect(_worker._get_visible_economic_threats() == [enemy], "filtered actor entered observations")
	passive.current_state = UnitBase.State.ATTACKING
	_refresh_local_fog()
	_expect_oracle("armed attacking villager")
	_expect(_worker._get_visible_economic_threats().has(passive), "attacking enemy villager omitted")
	passive.free()
	enemy.current_state = UnitBase.State.MOVING
	enemy.global_position = _worker.global_position + Vector2(100, 0)
	_refresh_local_fog()
	_worker._check_visible_economic_threats()
	_expect(not _worker.is_auto_recovering() and _worker._observed_worker_threat_distances.has(enemy.get_instance_id()), "far visible motion was lost or evacuated too soon")
	enemy.global_position = _worker.global_position + Vector2(75, 0)
	_refresh_local_fog()
	_worker._check_visible_economic_threats()
	_expect(_worker.is_auto_recovering(), "crossing warning boundary lost previous visible closing sample")
	_worker.command_stop()
	_worker.global_position = _map.tile_to_world(Vector2i(0, 0))
	_worker.vision_radius = MapData.range_tiles_to_world(2.0)
	enemy.global_position = _map.tile_to_world(Vector2i(-1, 0))
	_refresh_local_fog()
	_expect_oracle("off-map canonical fallback")


func _unit(scene: String, owner: int, tile: Vector2i) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/" + scene + ".tscn").instantiate() as UnitBase
	unit.player_owner = owner
	unit.global_position = _map.tile_to_world(tile)
	_map.get_node("UnitsContainer").add_child(unit)
	unit.set_process(false)
	return unit


func _refresh_local_fog() -> void:
	var fog: FogManager = _map.get_node("FogOfWar") as FogManager
	# The parent fixture deliberately starts fully visible. Reset it so every
	# visibility assertion here derives only from the current allied sources.
	fog._init_fog_grid()
	var sources: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is UnitBase and node.player_owner == 0 and node.current_state != UnitBase.State.DEAD:
			sources.append({"position": _map.world_to_tile(node.global_position), "vision_radius": maxi(0, int(round(MapData.world_to_range_tiles(node.vision_radius)))), "is_scout": node.unit_type == UnitData.UnitType.SCOUT})
	fog.set_vision_sources(sources)
	fog._update_visibility()


func _expect_oracle(label: String) -> void:
	var expected: Array[UnitBase] = []
	for candidate: Node in get_tree().get_nodes_in_group("units"):
		if not candidate is UnitBase or candidate == _worker:
			continue
		var enemy := candidate as UnitBase
		if enemy.player_owner == _worker.player_owner or not _worker._can_track_entity(enemy):
			continue
		if enemy.current_state == UnitBase.State.DEAD or enemy.damage <= 0.0:
			continue
		if enemy is Villager and enemy.current_state != UnitBase.State.ATTACKING:
			continue
		expected.append(enemy)
	_expect(_worker._get_visible_economic_threats() == expected, label + " differs from original ordered visibility queries")
