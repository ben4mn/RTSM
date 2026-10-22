extends Node
## Natural paid objective openings; all Main simulation and fog stay active.
## earliest: Scout purchase+ground move. delayed: same move at180s.
## reinforced: earliest plus paid Barracks at90s and two paid Warrior attack-moves.
var match_scene: Node
var site: Node
var scout: UnitBase
var report: Dictionary = {}
var output_path: String
var archetype: int = 0
var seed_value: int = 101
var scenario: String = "earliest"
var duration_seconds: float = 420.0
var barracks: BuildingBase
var placement_attempted: bool = false
var reinforcement_orders: Dictionary = {}
var reinforcement_queued: int = 0
var last_training_attempt: float = -1.0
var banks: Array[Dictionary] = []
var units_seen: Dictionary = {}
var buildings_seen: Dictionary = {}
var queues_seen: Dictionary = {}
var last_position_sample: float = -1.0
var last_snapshot: float = -15.0
var last_strategy: String = ""
var last_path: String = ""
var last_site_phase: String = ""
var ai_orders: Dictionary = {}
var winner: int = -1
var issued: bool = false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			archetype = int(arg.trim_prefix("--map="))
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--duration="):
			duration_seconds = float(arg.trim_prefix("--duration="))
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_difficulty = 0
	GameManager.selected_population_limit = 30
	GameManager.selected_map_seed = seed_value
	GameManager.selected_map_archetype = archetype
	report = {
		"map": archetype, "seed": seed_value, "scenario": scenario, "difficulty": 0, "population_limit": 30, "duration_limit": duration_seconds,
		"policy": "Scout bought at0 via Main; ordinary center Move on spawn, or at180s in delayed case. reinforced adds a normal paid Barracks at90s and two paid Warriors, each attack-moving to Sacred on birth. All normal economy, AI, fog, combat and navigation remain active. No resource grants, spawning, teleporting or simulation disabling.",
		"guided_opening": false, "failures": [], "events": [], "bank_ledger": [],
		"queue_ledger": [], "deposits": [], "created_entities": [], "scout_positions": [],
		"scout_routes": [], "snapshots": [], "damage": [],
		"first_ring_entry": -1.0, "first_ai_ring_entry": -1.0, "claim_at": -1.0,
		"first_contest_at": -1.0, "first_ai_objective_order_at": -1.0, "first_scout_damage_at": -1.0,
		"first_ai_field_attack_at": -1.0, "scout_produced_at": -1.0, "first_home_damage_at": -1.0, "first_ai_capture_at": -1.0, "ai_captures_before_neutral_initiative": [], "max_ai_objective_fighters": 0, "human_commands": [], "ai_order_changes": [],
		"first_ai_recon_assignment_at": -1.0, "first_ai_fighter_at": -1.0, "first_scout_visible_to_ai": -1.0, "first_site_visible_to_ai": -1.0,
		"user_data_dir": OS.get_user_data_dir(), "runtime_source_hashes": {},
		"simulation": {"time_scale": Engine.time_scale, "physics_ticks_per_second": Engine.physics_ticks_per_second, "fixed_fps": 60}
	}
	for source: String in ["scripts/main/main.gd", "scripts/ai/ai_controller.gd", "scripts/data/skirmish_data.gd", "scripts/data/unit_data.gd", "scripts/units/unit_base.gd", "scripts/map/map_generator.gd", "scripts/map/game_map.gd", "scripts/map/sacred_site.gd", "scripts/buildings/production_queue.gd", "scripts/managers/resource_manager.gd", "scripts/managers/fog_manager.gd"]:
		report["runtime_source_hashes"][source] = FileAccess.get_file_as_string("res://" + source).sha256_text()
	match_scene = load("res://scenes/main/main.tscn").instantiate()
	add_child(match_scene)
	for frame: int in range(900):
		if match_scene.get("_building_placement") != null:
			break
		await get_tree().process_frame
	if match_scene.get("_building_placement") == null:
		report["failures"].append("Main did not initialize")
		_finish()
		return
	site = match_scene.game_map.sacred_site
	report["ready_at"] = GameManager.game_time
	report["economic_bonus_active"] = match_scene.balance_ai_economic_bonus_active
	report["actual_ai_difficulty"] = match_scene.ai_controller.difficulty
	report["actual_map"] = match_scene.game_map.map_generator.archetype
	report["actual_guided_opening"] = match_scene._guided_opening_active
	report["site"] = {"world": _xy(site.global_position), "tile": _xy(match_scene.game_map.world_to_tile(site.global_position)), "capture_seconds": site.capture_time, "hold_seconds": site.victory_hold_time, "radius": site.get_capture_radius_world()}
	report["terrain"] = {"grid_sha256": JSON.stringify(match_scene.game_map.map_generator.grid).sha256_text(), "spawns": _points(match_scene.game_map.map_generator.spawn_positions), "tactical_routes": _safe(match_scene.game_map.map_generator.get_tactical_routes()), "sacred_visible_at_start": match_scene.game_map.is_tile_visible_to_player(match_scene.game_map.world_to_tile(site.global_position), 0)}
	banks = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
	report["initial_banks"] = banks.duplicate(true)
	ResourceManager.resources_changed.connect(_on_bank)
	GameManager.game_over.connect(func(owner: int): winner = owner; _event("game_over", {"winner": owner}))
	site.captured.connect(_on_captured)
	site.contested.connect(_on_contested)
	site.neutralized.connect(func(): _event("neutralized"))
	match_scene.ai_controller.ai_attack_launched.connect(func(_units: Array, _target: Vector2):
		if float(report["first_ai_field_attack_at"]) < 0.0: report["first_ai_field_attack_at"] = GameManager.game_time
		_event("ai_field_attack"))
	_register_entities()
	var town_center: BuildingBase = match_scene._player_town_center
	report["scout_cost"] = UnitData.get_unit_cost(UnitData.UnitType.SCOUT)
	report["scout_train_seconds"] = UnitData.UNITS[UnitData.UnitType.SCOUT]["build_time"]
	report["train_requested_at"] = GameManager.game_time
	report["human_commands"].append({"at": GameManager.game_time, "action": "train", "unit_type": UnitData.UnitType.SCOUT})
	match_scene._on_train_unit_requested(town_center, UnitData.UnitType.SCOUT)
	report["train_result"] = match_scene._last_train_request_result
	report["bank_immediately_after_train"] = ResourceManager.get_all_resources(0)
	if report["train_result"] != "queued":
		report["failures"].append("Normal Scout training request rejected: " + str(report["train_result"]))
		_finish()
		return
	while GameManager.current_state == GameManager.GameState.PLAYING and GameManager.game_time < duration_seconds:
		_register_entities()
		if is_instance_valid(scout) and not issued and (scenario != "delayed" or GameManager.game_time >= 180.0):
			issued = true
			report["move_order_at"] = GameManager.game_time
			report["spawn_position"] = _xy(scout.global_position)
			match_scene.game_map.selection_mgr.select_single(scout)
			match_scene._on_move_command(match_scene.game_map.world_to_tile(site.global_position))
			report["move_is_passive"] = scout._force_move_active and not scout.attack_move
			_event("ordinary_move", {"destination": _xy(scout.move_target)})
			report["human_commands"].append({"at": GameManager.game_time, "action": "move", "unit_type": scout.unit_type, "destination": _xy(scout.move_target)})
		_apply_reinforcements()
		_measure()
		await get_tree().process_frame
	_finish()

func _apply_reinforcements() -> void:
	if scenario != "reinforced":
		return
	if GameManager.game_time >= 90.0 and not placement_attempted:
		placement_attempted = true
		var origin: Vector2i = match_scene.game_map.world_to_tile(match_scene._player_town_center.global_position)
		var placed: bool = false
		for radius: int in range(4, 13):
			if placed: break
			for dx: int in range(-radius, radius + 1):
				if placed: break
				for dy: int in range(-radius, radius + 1):
					if maxi(absi(dx), absi(dy)) != radius: continue
					var tile: Vector2i = origin + Vector2i(dx, dy)
					var world: Vector2 = match_scene.game_map.tile_to_world(tile)
					if not match_scene._building_placement.revalidate_confirmation(BuildingData.BuildingType.BARRACKS, world, 0): continue
					match_scene._on_placement_confirmed(BuildingData.BuildingType.BARRACKS, world)
					for building: BuildingBase in match_scene._player_buildings[0]:
						if is_instance_valid(building) and building.building_type == BuildingData.BuildingType.BARRACKS:
							barracks = building
							placed = true
					if placed:
						report["human_commands"].append({"at": GameManager.game_time, "action": "place_barracks", "tile": _xy(tile), "cost": BuildingData.get_building_cost(BuildingData.BuildingType.BARRACKS)})
						break
		if not placed: report["failures"].append("No legal visible Barracks placement found")
	if is_instance_valid(barracks) and barracks.state == BuildingBase.State.ACTIVE and reinforcement_queued < 2 and GameManager.game_time - last_training_attempt >= 1.0:
		last_training_attempt = GameManager.game_time
		match_scene._on_train_unit_requested(barracks, UnitData.UnitType.INFANTRY)
		if match_scene._last_train_request_result == "queued":
			reinforcement_queued += 1
			report["human_commands"].append({"at": GameManager.game_time, "action": "train", "unit_type": UnitData.UnitType.INFANTRY})
	for unit: UnitBase in match_scene._player_units[0]:
		if not is_instance_valid(unit) or unit.unit_type != UnitData.UnitType.INFANTRY or reinforcement_orders.has(unit.get_instance_id()): continue
		reinforcement_orders[unit.get_instance_id()] = true
		match_scene.game_map.selection_mgr.select_single(unit)
		match_scene._on_touch_attack_move_command(match_scene.game_map.world_to_tile(site.global_position))
		report["human_commands"].append({"at": GameManager.game_time, "action": "attack_move", "unit_type": unit.unit_type, "destination": _xy(unit.move_target)})

func _register_entities() -> void:
	for owner: int in [0, 1]:
		for unit: UnitBase in match_scene._player_units[owner]:
			if not is_instance_valid(unit) or units_seen.has(unit.get_instance_id()):
				continue
			units_seen[unit.get_instance_id()] = true
			report["created_entities"].append({"at": GameManager.game_time, "kind": "unit", "id": unit.get_instance_id(), "owner": owner, "type": unit.unit_type, "position": _xy(unit.global_position)})
			if owner == 1 and unit.unit_type not in [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT] and float(report["first_ai_fighter_at"]) < 0.0:
				report["first_ai_fighter_at"] = GameManager.game_time
			unit.damage_received.connect(_on_damage)
			unit.unit_died.connect(func(dead: UnitBase): _event("unit_died", {"owner": dead.player_owner, "type": dead.unit_type, "id": dead.get_instance_id()}))
			if unit.has_signal("resource_deposited"):
				unit.resource_deposited.connect(_on_deposit.bind(owner, unit.get_instance_id()))
			if owner == 0 and unit.unit_type == UnitData.UnitType.SCOUT:
				scout = unit
				report["scout_produced_at"] = GameManager.game_time
				unit.navigation_failed.connect(func(_unit: UnitBase, target: Vector2): _event("scout_navigation_failed", {"target": _xy(target)}))
				unit.arrived_at_destination.connect(func(_unit: UnitBase): _event("scout_arrived", {"position": _xy(scout.global_position)}))
		for building: BuildingBase in match_scene._player_buildings[owner]:
			if not is_instance_valid(building):
				continue
			if not buildings_seen.has(building.get_instance_id()):
				buildings_seen[building.get_instance_id()] = true
				building.damage_received.connect(_on_building_damage)
				report["created_entities"].append({"at": GameManager.game_time, "kind": "building", "id": building.get_instance_id(), "owner": owner, "type": building.building_type, "position": _xy(building.global_position), "state": building.state})
			var queue: ProductionQueue = building.get_production_queue()
			if queue == null or queues_seen.has(queue.get_instance_id()):
				continue
			queues_seen[queue.get_instance_id()] = true
			queue.unit_queued.connect(_on_queue.bind("queued", owner, building.get_instance_id()))
			queue.unit_training_started.connect(_on_queue.bind("started", owner, building.get_instance_id()))
			queue.unit_trained.connect(_on_queue.bind("trained", owner, building.get_instance_id()))
			queue.unit_cancelled.connect(_on_queue.bind("cancelled", owner, building.get_instance_id()))

func _measure() -> void:
	var now: float = GameManager.game_time
	var status: Dictionary = site.get_status()
	if float(report["first_site_visible_to_ai"]) < 0.0 and match_scene.game_map.is_tile_visible_to_player(match_scene.game_map.world_to_tile(site.global_position), 1):
		report["first_site_visible_to_ai"] = now
	var phase: String = str(status["phase"]) + ":" + str(status["owner"])
	if phase != last_site_phase:
		last_site_phase = phase
		_event("site_phase", status)
	if is_instance_valid(scout) and scout.current_state != UnitBase.State.DEAD:
		var distance: float = scout.global_position.distance_to(site.global_position)
		if float(report["first_scout_visible_to_ai"]) < 0.0 and match_scene.game_map.is_tile_visible_to_player(match_scene.game_map.world_to_tile(scout.global_position), 1):
			report["first_scout_visible_to_ai"] = now
		if distance <= site.get_capture_radius_world() and float(report["first_ring_entry"]) < 0.0:
			report["first_ring_entry"] = now
			_event("scout_ring_entry", {"distance": distance, "position": _xy(scout.global_position)})
		if now - last_position_sample >= 0.5:
			last_position_sample = now
			report["scout_positions"].append({"at": now, "position": _xy(scout.global_position), "tile": _xy(match_scene.game_map.world_to_tile(scout.global_position)), "hp": scout.hp, "state": scout.current_state, "site_distance": distance})
		var encoded: String = JSON.stringify(_points(scout.path))
		if encoded != last_path:
			last_path = encoded
			var tiles: Array = []
			var length_world: float = 0.0
			var all_walkable: bool = true
			for index: int in scout.path.size():
				var tile: Vector2i = match_scene.game_map.world_to_tile(scout.path[index])
				tiles.append(_xy(tile))
				all_walkable = all_walkable and match_scene.game_map.is_tile_walkable(tile)
				if index > 0: length_world += scout.path[index - 1].distance_to(scout.path[index])
			report["scout_routes"].append({"at": now, "path_world": _points(scout.path), "tiles": tiles, "length_world": length_world, "waypoints_walkable": all_walkable})
	for enemy: UnitBase in match_scene._player_units[1]:
		if is_instance_valid(enemy) and enemy.current_state != UnitBase.State.DEAD and enemy.global_position.distance_to(site.global_position) <= site.get_capture_radius_world() and float(report["first_ai_ring_entry"]) < 0.0:
			report["first_ai_ring_entry"] = now
			_event("ai_ring_entry", {"type": enemy.unit_type, "position": _xy(enemy.global_position)})
	var objective_fighters: int = 0
	for assigned: UnitBase in match_scene.ai_controller._objective_units:
		if is_instance_valid(assigned) and assigned.unit_type not in [UnitData.UnitType.SCOUT, UnitData.UnitType.VILLAGER] and assigned.current_state != UnitBase.State.DEAD:
			objective_fighters += 1
	report["max_ai_objective_fighters"] = maxi(int(report["max_ai_objective_fighters"]), objective_fighters)
	for enemy: UnitBase in match_scene._player_units[1]:
		if not is_instance_valid(enemy) or enemy.unit_type == UnitData.UnitType.VILLAGER:
			continue
		var target: Node2D = enemy.attack_target if is_instance_valid(enemy.attack_target) else enemy.attack_building_target
		var detail: Dictionary = {"state": enemy.current_state, "stance": enemy.stance, "move": _xy(enemy.move_target), "attack_move": enemy.attack_move, "target": target.get_instance_id() if is_instance_valid(target) else -1, "assigned": enemy in match_scene.ai_controller._objective_units}
		var signature: String = JSON.stringify(detail)
		if str(ai_orders.get(enemy.get_instance_id(), "")) != signature:
			ai_orders[enemy.get_instance_id()] = signature
			report["ai_order_changes"].append({"at": now, "id": enemy.get_instance_id(), "type": enemy.unit_type, "position": _xy(enemy.global_position), "order": detail})
	var strategy: Dictionary = match_scene.ai_controller.get_strategy_snapshot()
	var decision: String = str(strategy["objective_mode"]) + ":" + str(strategy["objective_unit_count"])
	if decision != last_strategy:
		last_strategy = decision
		_event("ai_objective", strategy)
	if int(strategy["objective_unit_count"]) > 0 and str(strategy["objective_mode"]) in ["capture", "contest", "defend"] and float(report["first_ai_objective_order_at"]) < 0.0:
		report["first_ai_objective_order_at"] = now
	if str(strategy["objective_mode"]) == "scout" and int(strategy["objective_unit_count"]) > 0 and float(report["first_ai_recon_assignment_at"]) < 0.0:
		report["first_ai_recon_assignment_at"] = now
	if now - last_snapshot >= 15.0:
		last_snapshot = now
		report["snapshots"].append({"at": now, "banks": [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)], "site": status, "ai_strategy": strategy, "units": _unit_snapshot(), "site_visible_to_ai": match_scene.game_map.is_tile_visible_to_player(match_scene.game_map.world_to_tile(site.global_position), 1), "human_scout_visible_to_ai": is_instance_valid(scout) and match_scene.game_map.is_tile_visible_to_player(match_scene.game_map.world_to_tile(scout.global_position), 1)})

func _unit_snapshot() -> Array:
	var result: Array = []
	for owner: int in [0, 1]:
		for unit: UnitBase in match_scene._player_units[owner]:
			if is_instance_valid(unit):
				result.append({"id": unit.get_instance_id(), "owner": owner, "type": unit.unit_type, "position": _xy(unit.global_position), "hp": unit.hp, "state": unit.current_state, "stance": unit.stance, "move_target": _xy(unit.move_target)})
	return result

func _on_bank(owner: int, resource: String, amount: int) -> void:
	var previous: int = int(banks[owner].get(resource, 0))
	banks[owner][resource] = amount
	report["bank_ledger"].append({"at": GameManager.game_time, "owner": owner, "resource": resource, "delta": amount - previous, "amount": amount})

func _on_queue(type: int, operation: String, owner: int, producer: int) -> void:
	report["queue_ledger"].append({"at": GameManager.game_time, "owner": owner, "unit_type": type, "operation": operation, "producer": producer, "cost": UnitData.get_unit_cost(type), "bank": ResourceManager.get_all_resources(owner)})

func _on_deposit(resource: String, amount: int, owner: int, unit_id: int) -> void:
	report["deposits"].append({"at": GameManager.game_time, "owner": owner, "resource": resource, "amount": amount, "unit_id": unit_id})

func _on_damage(unit: UnitBase, loss: float) -> void:
	report["damage"].append({"at": GameManager.game_time, "kind": "unit", "owner": unit.player_owner, "type": unit.unit_type, "loss": loss, "position": _xy(unit.global_position)})
	if unit.player_owner == 0 and is_instance_valid(match_scene._player_town_center) and unit.global_position.distance_to(match_scene._player_town_center.global_position) < 512.0 and float(report["first_home_damage_at"]) < 0.0:
		report["first_home_damage_at"] = GameManager.game_time
	if unit == scout and float(report["first_scout_damage_at"]) < 0.0:
		report["first_scout_damage_at"] = GameManager.game_time

func _on_building_damage(building: BuildingBase, loss: float) -> void:
	report["damage"].append({"at": GameManager.game_time, "kind": "building", "owner": building.player_owner, "type": building.building_type, "loss": loss, "position": _xy(building.global_position)})
	if building.player_owner == 0 and float(report["first_home_damage_at"]) < 0.0:
		report["first_home_damage_at"] = GameManager.game_time

func _on_captured(owner: int) -> void:
	if owner == 1:
		if float(report["first_ai_capture_at"]) < 0.0: report["first_ai_capture_at"] = GameManager.game_time
		if GameManager.game_time < 390.0: report["ai_captures_before_neutral_initiative"].append(GameManager.game_time)
	if owner == 0 and float(report["claim_at"]) < 0.0: report["claim_at"] = GameManager.game_time
	_event("captured", {"owner": owner, "units": _unit_snapshot(), "ai_strategy": match_scene.ai_controller.get_strategy_snapshot()})

func _on_contested() -> void:
	if float(report["first_contest_at"]) < 0.0: report["first_contest_at"] = GameManager.game_time
	_event("contested")

func _event(kind: String, detail: Dictionary = {}) -> void:
	report["events"].append({"at": GameManager.game_time, "kind": kind, "detail": detail})

func _finish() -> void:
	report["ended_at"] = GameManager.game_time
	if scenario == "reinforced" and (reinforcement_queued != 2 or reinforcement_orders.size() != 2):
		report["failures"].append("Paid reinforcement plan did not complete two Warriors")
	report["reinforcement_queued"] = reinforcement_queued
	report["reinforcement_orders"] = reinforcement_orders.size()
	report["winner"] = winner
	report["end"] = "game_over" if winner >= 0 else "limit_or_fixture_failure"
	if is_instance_valid(match_scene):
		report["victory_reason"] = match_scene._victory_reason
		report["stats"] = match_scene._stats.duplicate(true)
		report["final_units"] = _unit_snapshot()
		report["final_banks"] = [ResourceManager.get_all_resources(0), ResourceManager.get_all_resources(1)]
		report["ai_process_active"] = match_scene.ai_controller.is_processing()
		report["final_ai_strategy"] = match_scene.ai_controller.get_strategy_snapshot()
	if is_instance_valid(site): report["final_site"] = site.get_status()
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[EASY_SACRED_RESPONSE] ", JSON.stringify({"map": archetype, "entry": report["first_ring_entry"], "claim": report["claim_at"], "end": report["ended_at"], "winner": winner, "ai_ring_entry": report["first_ai_ring_entry"], "contest": report["first_contest_at"], "failures": report["failures"]}))
	if is_instance_valid(match_scene): match_scene.free()
	get_tree().quit(0 if report["failures"].is_empty() else 2)

func _xy(value: Variant) -> Array:
	return [value.x, value.y]

func _points(values: Variant) -> Array:
	var result: Array = []
	for value: Variant in values: result.append(_xy(value))
	return result

func _safe(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return _xy(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[key] = _safe(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result: Array = []
		for child: Variant in value: result.append(_safe(child))
		return result
	return value
