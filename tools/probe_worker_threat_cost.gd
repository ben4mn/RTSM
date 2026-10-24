extends "res://tools/probe_authority_snapshot.gd"
## Paused production-map poses. Timings isolate worker observation cost; they
## are neither a paid match nor rendering/network FPS measurements.

class PassivePaidObserver extends "res://tools/probe_civilization_paid_match.gd":
	func _ready() -> void:
		pass


func _profile(label: String) -> void:
	var metadata: Dictionary = {"profile": label, "units": get_tree().get_nodes_in_group("units").size(), "buildings": get_tree().get_nodes_in_group("buildings").size(), "probe_source": get_script().get_source_code().sha256_text()}
	metadata["source"] = {}
	for path: String in ["scripts/units/villager.gd", "scripts/units/unit_base.gd", "scripts/map/game_map.gd", "tools/probe_authority_snapshot.gd", "tools/probe_ai_compact_paid_match.gd", "tools/probe_civilization_paid_match.gd"]:
		metadata.source[path] = (load("res://" + path) as Script).get_source_code().sha256_text()
	for owner: int in [0, 1]:
		var workers: Array[Villager] = []
		for unit: Node in get_tree().get_nodes_in_group("units"):
			if unit is Villager and unit.player_owner == owner:
				workers.append(unit as Villager)
		var details: Dictionary = metadata.duplicate()
		details["owner"] = owner
		details["workers"] = workers.size()
		for worker: Villager in workers:
			_expect(_observations(worker, false) == _observations(worker, true), "exact observed distances owner=%d worker=%s" % [owner, worker.get_instance_id()])
			if worker.has_method("_get_visible_economic_threats"):
				_expect(_observations(worker, false) == _production_observations(worker), "production observed distances owner=%d worker=%s" % [owner, worker.get_instance_id()])
		_measure(details, "original_worker_observations", func() -> void:
			for worker: Villager in workers: _observations(worker, false), 15)
		_measure(details, "fresh_batch_worker_observations", func() -> void:
			for worker: Villager in workers: _observations(worker, true), 15)
		if not workers.is_empty() and workers[0].has_method("_get_visible_economic_threats"):
			_measure(details, "production_worker_observations", func() -> void:
				for worker: Villager in workers: _production_observations(worker), 15)
	_measure(metadata, "main_fog", func() -> void: _main._update_fog_of_war(), 15)
	_measure(metadata, "main_entity_visibility", func() -> void: _main._update_fog_entity_visibility(), 15)
	_measure(metadata, "auto_target_all_units", func() -> void:
		for unit: Node in get_tree().get_nodes_in_group("units"):
			AUTO_TARGETING.find_target(unit, 120.0, 120.0, false), 15)
	_profile_observer(metadata)


func _profile_observer(metadata: Dictionary) -> void:
	var observer := PassivePaidObserver.new()
	add_child(observer)
	observer.match_scene = _main
	observer.human_bot = AIController.new()
	observer.human_bot.player_id = 0
	observer.add_child(observer.human_bot)
	observer.human_bot._decision_timer.stop()
	observer._observer_started_usec = Time.get_ticks_usec()
	observer.stats.merge({"first_contact": -1.0, "first_loss": [-1.0, -1.0], "army_types_seen": [{}, {}], "first_role_time": [{}, {}], "peak_army_by_type": [{}, {}], "snapshots": []})
	_main.ai_controller._my_units.clear()
	_main.ai_controller._my_buildings.clear()
	for unit: UnitBase in _main._player_units[1]:
		_main.ai_controller.register_unit(unit)
	for building: BuildingBase in _main._player_buildings[1]:
		_main.ai_controller.register_building(building)
	observer._register_human_entities()
	observer._register_combat_observers()
	observer._measure()
	_measure(metadata, "paid_observer_measure_without_snapshot", func() -> void: observer._measure(), 31)
	_measure(metadata, "paid_observer_registrations", func() -> void:
		observer._register_human_entities()
		observer._register_combat_observers(), 31)
	_measure(metadata, "paid_observer_measure_with_snapshot", func() -> void:
		observer.last_snapshot_time = -20.0
		observer._measure(), 5)
	observer.free()


func _observations(worker: Villager, batched: bool) -> Dictionary:
	var observed: Dictionary = {}
	var candidates: Array[UnitBase] = []
	var tiles: Array[Vector2i] = []
	for candidate: Node in get_tree().get_nodes_in_group("units"):
		if not candidate is UnitBase or candidate == worker:
			continue
		var enemy := candidate as UnitBase
		if enemy.player_owner == worker.player_owner:
			continue
		if not batched and not worker._can_track_entity(enemy):
			continue
		if enemy.current_state == UnitBase.State.DEAD or enemy.damage <= 0.0:
			continue
		if enemy is Villager and enemy.current_state != UnitBase.State.ATTACKING:
			continue
		if not batched:
			observed[enemy.get_instance_id()] = worker.global_position.distance_to(enemy.global_position)
		else:
			candidates.append(enemy)
			tiles.append(_map.world_to_tile(enemy.global_position))
	if batched and not candidates.is_empty():
		var visible: Dictionary = _map.get_visible_tiles_for_player(tiles, worker.player_owner)
		for index: int in candidates.size():
			var tile: Vector2i = tiles[index]
			var in_bounds: bool = tile.x >= 0 and tile.y >= 0 and tile.x < MapData.MAP_WIDTH and tile.y < MapData.MAP_HEIGHT
			var enemy: UnitBase = candidates[index]
			if visible.has(tile) if in_bounds else worker._can_track_entity(enemy):
				observed[enemy.get_instance_id()] = worker.global_position.distance_to(enemy.global_position)
	return observed


func _production_observations(worker: Villager) -> Dictionary:
	var observed: Dictionary = {}
	for enemy: UnitBase in worker.call("_get_visible_economic_threats"):
		observed[enemy.get_instance_id()] = worker.global_position.distance_to(enemy.global_position)
	return observed


func _verify_visibility(_label: String) -> void:
	pass


func _verify_lifecycle() -> void:
	pass


func _verify_target_oracle() -> void:
	pass
