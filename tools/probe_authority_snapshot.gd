extends Node
## Isolated subsection timings. Directly reconstructed actor poses are synthetic;
## this does not replay the paid public match or measure network/rendering FPS.

const AUTO_TARGETING: Script = preload("res://scripts/units/auto_targeting.gd")
var _main: Node
var _map: Node2D
var _adapter: Node
var _records: Array[Dictionary] = []
var _output: String = ""
var _actors_path: String = "res://tools/fixtures/authority_late_river_2026_10_23.json"
var _verification_only: bool = false
var _failures: Array[String] = []
var _checks: int = 0
var _original_network_path: String = ""
var _packet_oracle: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): _output = argument.trim_prefix("--output=")
		if argument.begins_with("--actors="): _actors_path = argument.trim_prefix("--actors=")
		if argument.begins_with("--original-network="): _original_network_path = argument.trim_prefix("--original-network=")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_actors_path))
	AudioManager.set_all_enabled(false)
	NetworkSession.server_mode = true
	NetworkSession.online = true
	NetworkSession.state = "playing"
	NetworkSession.match_seed = int(fixture.seed)
	NetworkSession.match_map_archetype = int(fixture.map)
	NetworkSession.set_process(false)
	GameManager.guided_opening_enabled = false
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for _frame: int in range(600):
		if is_instance_valid(NetworkSession.adapter): break
		await get_tree().process_frame
	_map = _main.game_map
	_adapter = NetworkSession.adapter
	if not _original_network_path.is_empty():
		_packet_oracle = load(_original_network_path).new()
		_packet_oracle.main = _main
		_packet_oracle.game_map = _map
		_packet_oracle._resource_tiles = _adapter._resource_tiles
	get_tree().paused = true
	_adapter._register_server_entities()
	_profile("opening")
	_reconstruct(fixture.actors)
	_profile("recorded_late_poses")
	if _map.has_method("get_visible_tiles_for_player"):
		_verify_visibility("late_poses")
		_verify_lifecycle()
	_verify_target_oracle()
	var report: Dictionary = {
		"scope": fixture.scope, "fixture": fixture, "engine": Engine.get_version_info(),
		"display": DisplayServer.get_name(), "pid": OS.get_process_id(),
		"samples": _records, "source": {}, "clock_scale": Engine.time_scale,
		"checks": _checks, "failures": _failures, "full_packet_original_oracle": _packet_oracle != null,
	}
	for path: String in ["scripts/network/network_match.gd", "scripts/map/game_map.gd", "scripts/units/villager.gd", "scripts/units/auto_targeting.gd", "tools/probe_authority_snapshot.gd"]:
		report.source[path] = FileAccess.get_file_as_string("res://" + path).sha256_text()
	if not _output.is_empty(): FileAccess.open(_output, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("AUTHORITY_SUBSECTIONS ", JSON.stringify(_records))
	NetworkSession.adapter = null
	if _packet_oracle != null: _packet_oracle.free()
	NetworkSession.online = false
	GameManager.set_state(GameManager.GameState.MENU)
	_main.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	print("AUTHORITY_VERIFY checks=", _checks, " failures=", _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)

func _reconstruct(actors: Array) -> void:
	for group: String in ["units", "buildings"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if _map.is_ancestor_of(node) and (node is UnitBase or node is BuildingBase): node.free()
	for slot: int in 2:
		_main._player_units[slot].clear()
		_main._player_buildings[slot].clear()
	_adapter.entities.clear()
	_map.pathfinding = Pathfinding.new(_map.map_generator)
	for slot: int in 2:
		GameManager.players[slot].population = 0
		GameManager.players[slot].population_reserved = 0
		GameManager.players[slot].population_cap = 200
		GameManager.players[slot].max_population = 200
	for actor: Dictionary in actors:
		if actor.kind != "building": continue
		var position := Vector2(float(actor.x), float(actor.y))
		var building: BuildingBase = _main._spawn_building(int(actor.type), int(actor.owner), _map.world_to_tile(position))
		building.complete_instantly()
		building.set_meta("network_id", int(actor.id))
	for actor: Dictionary in actors:
		if actor.kind != "unit": continue
		var position := Vector2(float(actor.x), float(actor.y))
		var unit: UnitBase = _main._spawn_unit(int(actor.type), int(actor.owner), position)
		unit.set_meta("network_id", int(actor.id))
		unit.command_stop()
	_main._update_fog_of_war()
	_adapter._register_server_entities()

func _profile(label: String) -> void:
	if _verification_only: return
	var metadata: Dictionary = {"profile": label, "units": get_tree().get_nodes_in_group("units").size(), "buildings": get_tree().get_nodes_in_group("buildings").size(), "original_resource_tiles": _adapter._resource_tiles.size()}
	_measure(metadata, "snapshot_slot_0", func() -> void: _adapter._snapshot_for(0), 31)
	_measure(metadata, "snapshot_slot_1", func() -> void: _adapter._snapshot_for(1), 31)
	var snapshots: Array = [_adapter._snapshot_for(0), _adapter._snapshot_for(1)]
	_measure(metadata, "json_both", func() -> void:
		JSON.stringify(snapshots[0])
		JSON.stringify(snapshots[1]), 31)
	_measure(metadata, "main_fog", func() -> void: _main._update_fog_of_war(), 31)
	_measure(metadata, "main_entity_visibility", func() -> void: _main._update_fog_entity_visibility(), 31)
	_measure(metadata, "strategy_ui_refresh", func() -> void: _main.get_node("StrategyController")._refresh(), 15)
	_measure(metadata, "auto_target_all_units", func() -> void:
		for unit: Node in get_tree().get_nodes_in_group("units"):
			AUTO_TARGETING.find_target(unit, 120.0, 120.0, false), 15)
	_measure(metadata, "dropoff_all_workers", func() -> void:
		for unit: Node in get_tree().get_nodes_in_group("units"):
			if unit is Villager:
				for building: Node in get_tree().get_nodes_in_group("dropoff_buildings"):
					if building.player_owner == unit.player_owner: unit._get_dropoff_route(building), 5)

func _measure(metadata: Dictionary, label: String, action: Callable, count: int) -> void:
	action.call()
	var samples: Array[int] = []
	for _index: int in count:
		var started: int = Time.get_ticks_usec()
		action.call()
		samples.append(Time.get_ticks_usec() - started)
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var record: Dictionary = metadata.duplicate()
	record.merge({"section": label, "microseconds": samples, "median_us": sorted[sorted.size() / 2], "p95_us": sorted[int((sorted.size() - 1) * 0.95)], "max_us": sorted[-1]})
	_records.append(record)
	print("PROFILE ", label, " ", record.median_us, " us")

func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error(label)

func _verify_visibility(label: String) -> void:
	var tiles: Array[Vector2i] = []
	for y: int in range(-1, MapData.MAP_HEIGHT + 1):
		for x: int in range(-1, MapData.MAP_WIDTH + 1): tiles.append(Vector2i(x, y))
	for slot: int in [0, 1, 2]:
		var batch: Dictionary = _map.get_visible_tiles_for_player(tiles, slot)
		for tile: Vector2i in tiles:
			_expect(batch.has(tile) == _map.is_tile_visible_to_player(tile, slot), label + " visibility slot=%d tile=%s" % [slot, tile])
		if slot > 1: continue
		var expected: Array = []
		for tile: Vector2i in _adapter._resource_tiles:
			if _map.is_tile_visible_to_player(tile, slot):
				var resource: Node2D = _map.get_resource_node_at(tile)
				expected.append([tile.x, tile.y, resource.remaining if is_instance_valid(resource) else 0])
		var packet: Dictionary = _adapter._snapshot_for(slot)
		_expect(packet.resources == expected, label + " exact ordered resource packet slot=%d" % slot)
		if _packet_oracle != null:
			_packet_oracle.entities = _adapter.entities
			_packet_oracle._snapshot_number = _adapter._snapshot_number
			_expect(packet == _packet_oracle._snapshot_for(slot), label + " full original packet equality slot=%d" % slot)

func _verify_lifecycle() -> void:
	var worker: UnitBase = _main._player_units[1][0]
	var original: Vector2 = worker.global_position
	var original_radius: float = worker.vision_radius
	worker.global_position = _map.tile_to_world(Vector2i(0, 0))
	worker.vision_radius = 0.0
	_verify_visibility("moved_zero_radius")
	worker.current_state = UnitBase.State.DEAD
	_verify_visibility("dead_source")
	worker.current_state = UnitBase.State.IDLE
	worker.global_position = original
	worker.vision_radius = original_radius
	var added: UnitBase = _main._spawn_unit(UnitData.UnitType.SCOUT, 1, _map.tile_to_world(Vector2i(36, 36)))
	_verify_visibility("new_scout")
	added.queue_free()
	_verify_visibility("queued_source_matches_live_contract")
	_main._player_units[1].erase(added)
	added.free()
	var building: BuildingBase = _main._player_buildings[1][0]
	building.state = BuildingBase.State.DESTROYED
	_verify_visibility("destroyed_building")
	building.state = BuildingBase.State.ACTIVE
	_verify_visibility("deleted_scout_restored_building")

func _verify_target_oracle() -> void:
	# The oracle keeps the pre-change order of filters and stable group ties.
	for unit: Node in get_tree().get_nodes_in_group("units"):
		if not unit is UnitBase: continue
		for radius: float in [0.0, 120.0, 10000.0]:
			for buildings_first: bool in [false, true]:
				_expect(AUTO_TARGETING.find_target(unit, radius, radius, buildings_first) == _original_target(unit, radius, buildings_first), "original target choice %s radius=%s buildings_first=%s" % [unit.get_instance_id(), radius, buildings_first])
	var attacker: UnitBase = _main._spawn_unit(UnitData.UnitType.INFANTRY, 0, _map.tile_to_world(Vector2i(36, 36)))
	var first: UnitBase = _main._spawn_unit(UnitData.UnitType.INFANTRY, 1, attacker.global_position + Vector2(20.0, 0.0))
	var second: UnitBase = _main._spawn_unit(UnitData.UnitType.INFANTRY, 1, attacker.global_position + Vector2(-20.0, 0.0))
	_main._update_fog_of_war()
	_expect(AUTO_TARGETING.find_target(attacker, 20.0, 0.0, false) == first, "inclusive radius and first equal-priority unit win tie")
	attacker._temporarily_ignore_auto_target(first)
	_expect(AUTO_TARGETING.find_target(attacker, 20.0, 0.0, false) == second, "ignored tie winner allows second")
	second.current_state = UnitBase.State.DEAD
	_expect(AUTO_TARGETING.find_target(attacker, 20.0, 0.0, false) == null, "ignored and dead units excluded")
	second.current_state = UnitBase.State.IDLE
	second.global_position = _map.tile_to_world(Vector2i(70, 70))
	_expect(AUTO_TARGETING.find_target(attacker, 120.0, 0.0, false) == _original_target(attacker, 120.0, false), "hidden moved target matches original")
	_main._player_units[1].erase(first)
	first.free()
	_expect(AUTO_TARGETING.find_target(attacker, 120.0, 0.0, false) == _original_target(attacker, 120.0, false), "freed former target matches original")

func _original_target(attacker: UnitBase, radius: float, buildings_first: bool) -> Node2D:
	if buildings_first:
		var first: BuildingBase = _original_building(attacker, radius)
		if first != null: return first
	var nearest: UnitBase = null
	var nearest_distance: float = radius
	var best_priority: int = -1
	for candidate: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(candidate) or not candidate is UnitBase or candidate == attacker: continue
		var unit := candidate as UnitBase
		if unit.player_owner == attacker.player_owner: continue
		if not attacker._is_valid_target(unit) or attacker._is_auto_target_temporarily_ignored(unit): continue
		var distance: float = attacker.global_position.distance_to(unit.global_position)
		if distance > radius: continue
		var priority: int = AUTO_TARGETING._unit_priority(attacker, unit)
		if priority > best_priority or (priority == best_priority and distance < nearest_distance):
			best_priority = priority
			nearest_distance = distance
			nearest = unit
	if nearest != null: return nearest
	return null if buildings_first else _original_building(attacker, radius)

func _original_building(attacker: UnitBase, radius: float) -> BuildingBase:
	var nearest: BuildingBase = null
	var nearest_distance: float = radius
	for candidate: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(candidate) or not candidate is BuildingBase: continue
		var building := candidate as BuildingBase
		if building.player_owner == attacker.player_owner: continue
		if not attacker._is_valid_building_target(building) or attacker._is_auto_target_temporarily_ignored(building): continue
		var distance: float = attacker._get_building_attack_distance(building)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest
