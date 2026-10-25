extends "res://tools/test_worker_threat_batch.gd"
## Warm-cache mutation tests. Expected visibility uses direct fog cells and
## source-circle math, never the index, cached roster or canonical helper.
var _shared_checks: int = 0

func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_tree().current_scene = null
	for owner: int in [0, 1]:
		_case_name = "shared_owner_%d" % owner
		await _fixture()
		_worker.player_owner = owner
		_tc.free()
		_worker.vision_radius = 0.0
		_map.fog_of_war._init_fog_grid()
		_run_shared_cases(owner)
		_map.free()
		await get_tree().process_frame
	for failure: String in _failures: push_error("[FAIL] worker_shared_visibility: " + failure)
	print("WORKER_SHARED_VISIBILITY checks=%d failures=%s" % [_shared_checks, _failures])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _run_shared_cases(owner: int) -> void:
	var enemy: UnitBase = _unit("infantry", 1 - owner, Vector2i(18, 18))
	var passive: UnitBase = _unit("villager", 1 - owner, Vector2i(18, 19))
	var scout: UnitBase = _unit("scout", owner, Vector2i(18, 18))
	scout.vision_radius = MapData.range_tiles_to_world(2)
	_refresh_fog()
	_check_shared("initial and repeated")
	_check_shared("warm repeat")
	var spawned: UnitBase = _unit("infantry", 1 - owner, Vector2i(18, 18))
	_check_shared("new target after warm roster")
	spawned.free()
	_check_shared("new target removed")
	passive.current_state = UnitBase.State.ATTACKING
	_check_shared("passive to attacking without visibility revision")
	passive.damage = 0
	_check_shared("live damage becomes zero")
	passive.damage = 3
	_check_shared("live damage restored")
	passive.current_state = UnitBase.State.GATHERING
	_check_shared("attacking to passive")
	enemy.player_owner = owner
	_check_shared("target ownership ally")
	enemy.player_owner = 1 - owner
	_check_shared("target ownership enemy")
	enemy.current_state = UnitBase.State.DEAD
	_check_shared("target dead")
	enemy.current_state = UnitBase.State.IDLE
	_check_shared("target restored")
	enemy.global_position = _map.tile_to_world(Vector2i(25, 18))
	_check_shared("target leaves observed tile")
	enemy.global_position = _map.tile_to_world(Vector2i(18, 18))
	_check_shared("target returns")
	scout.global_position = _map.tile_to_world(Vector2i(30, 30))
	_refresh_fog()
	_check_shared("source teleport removes visibility")
	scout.vision_radius = MapData.range_tiles_to_world(30)
	_refresh_fog()
	_check_shared("source radius changes")
	scout.player_owner = 1 - owner
	_refresh_fog()
	_check_shared("source ownership changes")
	scout.player_owner = owner
	scout.current_state = UnitBase.State.DEAD
	_refresh_fog()
	_check_shared("source death")
	scout.current_state = UnitBase.State.IDLE
	scout.vision_radius = MapData.range_tiles_to_world(2)
	scout.global_position = enemy.global_position
	_refresh_fog()
	_check_shared("source revival")
	var wrapper := Node2D.new()
	_map.get_node("UnitsContainer").add_child(wrapper)
	scout.reparent(wrapper)
	_check_shared("source reparent retains global position")
	var outside := Node2D.new()
	add_child(outside)
	scout.reparent(outside)
	_refresh_fog()
	_check_shared("source leaves indexed map")
	scout.reparent(wrapper)
	outside.free()
	_refresh_fog()
	_check_shared("source reenters indexed map")
	wrapper.position += Vector2(500, 500)
	_refresh_fog()
	_check_shared("warm source ancestor translation")
	wrapper.position -= Vector2(500, 500)
	_refresh_fog()
	_check_shared("ancestor restored")
	_map.get_node("UnitsContainer").move_child(passive, 0)
	passive.current_state = UnitBase.State.ATTACKING
	_check_shared("exact scene group order after move_child")
	scout.free()
	_refresh_fog()
	_check_shared("source deletion")
	var building: BuildingBase = TC_SCENE.instantiate() as BuildingBase
	building.player_owner = owner
	building.global_position = enemy.global_position
	_map.get_node("BuildingsContainer").add_child(building)
	building.set_process(false)
	_refresh_fog()
	_check_shared("building construction vision")
	building.state = BuildingBase.State.DESTROYED
	_refresh_fog()
	_check_shared("building destroyed")
	building.state = BuildingBase.State.ACTIVE
	building.player_owner = 1 - owner
	_refresh_fog()
	_check_shared("building ownership")
	building.player_owner = owner
	building.global_position = _map.tile_to_world(Vector2i(30, 30))
	_refresh_fog()
	_check_shared("building movement")
	building.global_position = _map.tile_to_world(Vector2i(23, 18))
	_refresh_fog()
	_check_shared("large building vision radius")
	building.building_type = BuildingData.BuildingType.HOUSE
	_refresh_fog()
	_check_shared("building type changes vision radius")
	building.free()
	_refresh_fog()
	_check_shared("building deletion")
	var fog: FogManager = _map.fog_of_war
	fog.reveal_all()
	_check_shared("reveal_all")
	fog._init_fog_grid()
	_check_shared("fog reset")
	fog.set_debug_tile_state(_map.world_to_tile(enemy.global_position), MapData.FogState.VISIBLE)
	_check_shared("same-frame fog reveal")
	fog.set_debug_tile_state(_map.world_to_tile(enemy.global_position), MapData.FogState.EXPLORED)
	_check_shared("same-frame fog hide")
	fog.owning_player = 1 - owner
	_check_shared("fog owner changes visibility path")
	fog.owning_player = 0
	var foreign := Node2D.new()
	add_child(foreign)
	enemy.reparent(foreign)
	_check_shared("foreign target warm query")
	enemy.global_position = _worker.global_position
	_check_shared("foreign target movement uses uncached path")
	enemy.player_owner = owner
	_check_shared("foreign target ownership")
	enemy.reparent(_map.get_node("UnitsContainer"))
	foreign.free()
	_check_shared("target returns to indexed map")
	enemy.free()
	_check_shared("target deletion")

func _refresh_fog() -> void:
	var sources: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is UnitBase and _map.is_ancestor_of(node) and node.player_owner == 0 and node.current_state != UnitBase.State.DEAD:
			sources.append({"position": _map.world_to_tile(node.global_position), "vision_radius": maxi(0, int(round(MapData.world_to_range_tiles(node.vision_radius)))), "is_scout": false})
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is BuildingBase and _map.is_ancestor_of(node) and node.player_owner == 0 and node.state != BuildingBase.State.DESTROYED:
			sources.append({"position": _map.world_to_tile(node.global_position), "vision_radius": int(BuildingData.get_building_stats(node.building_type).get("vision_radius", 3)), "is_scout": false})
	_map.fog_of_war.set_vision_sources(sources)
	_map.fog_of_war._update_visibility()

func _check_shared(label: String) -> void:
	var expected: Array[UnitBase] = []
	var roster: Array[UnitBase] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not node is UnitBase: continue
		var unit := node as UnitBase
		if unit.player_owner == _worker.player_owner or unit.current_state == UnitBase.State.DEAD or not _independent_visible(unit): continue
		roster.append(unit)
		if unit.damage > 0 and (not unit is Villager or unit.current_state == UnitBase.State.ATTACKING): expected.append(unit)
	_shared_checks += 2
	_expect(_map.get_visible_enemy_units_for_player(_worker.player_owner) == roster, label + " ordered roster differs from direct visibility math")
	_expect(_worker._get_visible_economic_threats() == expected, label + " live threat filter differs from direct oracle")

func _independent_visible(unit: UnitBase) -> bool:
	var tile: Vector2i = _map.world_to_tile(unit.global_position)
	var owner: int = _worker.player_owner
	var fog: FogManager = _map.fog_of_war
	if fog.owning_player == owner:
		return tile.x >= 0 and tile.y >= 0 and tile.x < MapData.MAP_WIDTH and tile.y < MapData.MAP_HEIGHT and fog.fog_grid[tile.y][tile.x] == MapData.FogState.VISIBLE
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not node is UnitBase or not _map.is_ancestor_of(node) or node.player_owner != owner or node.current_state == UnitBase.State.DEAD: continue
		var delta: Vector2i = tile - _map.world_to_tile(node.global_position)
		var radius: int = maxi(0, int(round(MapData.world_to_range_tiles(node.vision_radius))))
		if delta.x * delta.x + delta.y * delta.y <= radius * radius: return true
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not node is BuildingBase or not _map.is_ancestor_of(node) or node.player_owner != owner or node.state == BuildingBase.State.DESTROYED: continue
		var delta: Vector2i = tile - _map.world_to_tile(node.global_position)
		var radius: int = maxi(0, int(BuildingData.get_building_stats(node.building_type).get("vision_radius", 3)))
		if delta.x * delta.x + delta.y * delta.y <= radius * radius: return true
	return false
