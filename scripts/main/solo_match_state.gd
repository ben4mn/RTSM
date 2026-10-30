extends RefCounted
## Version-one solo match schema. Only listed gameplay state is persisted.
const UNIT_FIELDS: Array[String] = ["unit_type", "player_owner", "max_hp", "hp", "damage", "armor", "speed", "attack_range", "vision_radius", "attack_speed", "is_ranged", "current_state", "stance", "move_target", "attack_target", "attack_building_target", "attack_cooldown", "path", "path_index", "attack_move", "_attack_march", "_pending_attack_march", "_command_generation", "queued_orders", "_executing_queued_order", "_preserve_order_intent", "_suspended_building_target", "_suspended_building_forced", "_retaliation_ready_at", "kills", "_auto_attack_timer", "_stuck_timer", "_last_move_pos", "_forced_attack", "_force_move_active", "_auto_engagement_origin", "_auto_chase_elapsed", "_patrol_active", "_patrol_point_a", "_patrol_point_b", "_patrol_to_b", "_navigation_active", "_navigation_goal", "_navigation_target_snapshot", "_navigation_repath_cooldown", "_navigation_failed_repaths", "_navigation_stall_repaths", "_ignored_auto_targets_until", "_simulation_elapsed_seconds", "_attack_windup_remaining", "_attack_windup_target", "_attack_windup_building"]
const WORKER_FIELDS: Array[String] = ["gather_rate", "carry_capacity", "gather_tick_time", "gather_target", "_assigned_farm_ref", "_preserve_farm_assignment_on_command", "gather_type", "carried_resource_type", "carried_amount", "_cargo", "_dropoff_recheck_timer", "_dropoff_topology_revision", "_dropoff_buildings_signature", "gather_timer", "_fractional_harvest", "dropoff_target", "_manual_dropoff", "_manual_dropoff_resume_gather", "_dropoff_retry_timer", "_dropoff_route_active", "_gather_last_known_position", "_has_gather_last_known_position", "_gather_last_known_is_building", "_gather_last_known_instance_id", "_unreachable_resource_ids_until", "_unreachable_dropoff_ids_until", "build_target", "build_timer", "_gather_offset", "_saved_gather_target", "_saved_gather_type", "_saved_carried_resource_type", "_saved_gather_last_known_position", "_saved_has_gather_last_known_position", "_saved_gather_last_known_is_building", "_saved_gather_last_known_instance_id", "_pending_gather_resource_type", "_pending_gather_last_known_position", "_pending_gather_last_known_is_building", "_pending_gather_last_known_instance_id", "_preserve_pending_gather_on_command", "_building_work_target_id", "_building_work_destination", "_service_target_id", "_service_destination", "_service_kind", "_auto_recovering", "_recovery_waiting", "_recovery_work_state", "_recovery_refuge", "_recovery_check_timer", "_recovery_quiet_seconds", "_recovery_damage_remaining", "_recovery_danger_present", "_preserve_recovery_on_command", "_recovery_return_only", "_recovery_alternate_retry_remaining", "_avoid_recovery_dropoff_danger", "_economic_threat_check_timer"]
const TRADER_FIELDS: Array[String] = ["trade_post", "home_town_center", "carried_gold", "delivered_gold", "trade_route_active", "_destination", "_visited_home", "_manual_pause", "_handling_left", "_retry_left"]
const BUILDING_FIELDS: Array[String] = ["building_type", "player_owner", "state", "hp", "max_hp", "build_progress", "build_time", "pop_provided", "footprint", "drop_off_resources", "trainable_units", "provides_food", "rally_point", "rally_point_is_custom", "rally_orders", "rally_resource_type", "rally_resource_instance_id", "rally_resource_is_building", "tower_attack_damage", "tower_attack_range", "tower_attack_interval", "tower_attack_projectile_speed", "tower_attack_buildings", "_tower_attack_cooldown", "_assigned_farmer_ref"]
const AI_FIELDS: Array[String] = ["difficulty", "player_id", "enemy_id", "_decision_interval", "_ai_state", "_my_buildings", "_my_units", "_military_role_last_fielded", "_base_position", "_base_tile", "_staging_point", "_attack_in_progress", "_has_launched_field_attack", "_attack_wave_units", "_attack_wave_target_position", "_attack_wave_target_ref", "_attack_wave_best_distance", "_attack_wave_best_target_hp", "_attack_wave_last_progress_time", "_retreat_threshold", "_game_time", "_last_harass_time", "_last_field_attack_time", "_easy_regroup_until", "_scout_waypoints", "_next_scout_waypoint_index", "_objective_scout_sent", "_objective_mode", "_objective_units", "_sacred_armed_guard", "_objective_order_time", "_enemy_memory", "_rebuild_requests", "_last_defense_threat_position", "_last_defense_threat_time", "_last_strategy_decision", "_resource_memory", "_economy_exploration_waypoints", "_next_economy_exploration_waypoint", "_economy_exploration_revealed", "_economy_exploration_workers", "_economy_exploration_retry_after", "_economy_exploration_route_checks", "_economy_exploration_orders_issued", "_economy_memory_revisit_orders_issued", "_economy_wood_search_orders_issued", "_economy_wood_search_worker", "_economy_resource_assignments", "_economy_rebalance_orders_issued", "_next_economy_rebalance_time", "_pending_economy_rebalance_type", "_pending_economy_rebalance_from_type", "_pending_economy_rebalance_deadline", "_economy_rebalance_deferred_scheduled", "_last_economy_action", "_build_site_search_cursors", "_next_trade_decision", "_trade_site_cursor", "_town_center_count", "_house_count", "_barracks_count", "_archery_range_count", "_stable_count", "_resource_camp_count", "_farm_count", "_feudal_paid_farm_foundations", "_feudal_paid_farm_foundation_ids", "_siege_workshop_count", "_blacksmith_count", "_watch_tower_count", "_is_under_pressure", "_pressure_memory", "_saving_for_age_up", "_timed_age_up_reserve_active"]
const MAIN_FIELDS: Array[String] = ["_stats", "_age_reached_at", "_sacred_control_seconds", "_sacred_control_owner", "_sacred_last_remaining", "_ai_construction_jobs", "_ai_construction_recovery_elapsed", "_control_groups", "_player_town_center", "_hint_timer", "_hints_shown", "_guided_opening_active", "_guided_stage", "_milestone_first_house", "_milestone_first_military_building", "_milestone_first_age_up", "_opening_gather_complete", "_opening_house_complete", "_opening_scout_queued", "_opening_military_move_complete", "_guidance_dismissed_in_match", "_pause_open_count", "_sacred_site_victory_notified"]
const MANAGER_FIELDS: Array[String] = ["players", "game_time", "game_speed", "_match_mode", "_match_civilizations", "_match_population_limit", "_population_reservations", "_next_population_reservation_id", "_base_population_caps", "_population_cap_grants", "player_upgrades", "researched_upgrades"]
const QUEUE_FIELDS: Array[String] = ["queue", "current_progress", "current_train_time", "is_training", "_population_reservation_ids"]
const LEGACY_QUEUE_COSTS: Dictionary = {
	UnitData.UnitType.VILLAGER: {"food": 100, "wood": 0, "gold": 0},
	UnitData.UnitType.INFANTRY: {"food": 100, "wood": 40, "gold": 0},
	UnitData.UnitType.ARCHER: {"food": 50, "wood": 90, "gold": 0},
	UnitData.UnitType.CAVALRY: {"food": 180, "wood": 60, "gold": 0},
	UnitData.UnitType.SCOUT: {"food": 40, "wood": 0, "gold": 10},
	UnitData.UnitType.SIEGE: {"food": 0, "wood": 150, "gold": 100},
	UnitData.UnitType.TRADER: {"food": 0, "wood": 60, "gold": 40},
}
const SITE_FIELDS: Array[String] = ["state", "owning_player", "capture_progress", "capture_time", "gold_per_second", "capture_radius", "victory_hold_time", "victory_timer", "match_mode", "control_banks", "clock_ticking", "garrison_paused", "_armed_nearby_counts", "_gold_accumulator", "_gold_accumulator_owner", "_being_neutralized"]

const MARCH = preload("res://scripts/main/attack_march_cohesion.gd")
const PENDING_MARCH = preload("res://scripts/main/pending_attack_march.gd")
const MAX_ACTORS := 1024
const MAX_RESOURCES := MapData.MAP_WIDTH * MapData.MAP_HEIGHT
var _references: Dictionary = {}

func _script_fields(object: Object) -> Array[String]:
	var result: Array[String] = []
	for property: Dictionary in object.get_script().get_script_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and str(property.name) != "script":
			result.append(str(property.name))
	return result

func _encode(value: Variant) -> Variant:
	# A battle target may have been freed since the last unit update. Godot's
	# `is` operator itself errors on freed objects, before later guards can run.
	if typeof(value) == TYPE_OBJECT and not is_instance_valid(value):
		return {"$ref": 0}
	if value is WeakRef:
		var target: Object = value.get_ref()
		return {"$weak": target.get_instance_id() if is_instance_valid(target) and _references.has(target.get_instance_id()) else 0}
	if value is Object:
		return {"$ref": value.get_instance_id() if is_instance_valid(value) and _references.has(value.get_instance_id()) else 0}
	if value is Array:
		var result: Array = []
		for entry: Variant in value: result.append(_encode(entry))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[_encode(key)] = _encode(value[key])
		return result
	return value

func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.size() == 1 and value.has("$ref"): return _references.get(int(value["$ref"]))
		if value.size() == 1 and value.has("$weak"):
			return weakref(_references[int(value["$weak"])]) if _references.has(int(value["$weak"])) else WeakRef.new()
		var result: Dictionary = {}
		for key: Variant in value: result[_decode(key)] = _decode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value: result.append(_decode(entry))
		return result
	# Runtime IDs also appear in queue/rally/fog/AI ledgers, not just references.
	if value is int and _references.has(value): return _references[value].get_instance_id()
	return value

func _read(object: Object, fields: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for field: String in fields: result[field] = _encode(object.get(field))
	return result

func _write(object: Object, fields: Array[String], data: Dictionary) -> void:
	for field: String in fields:
		if not data.has(field): continue
		var value: Variant = _decode(data[field])
		var current: Variant = object.get(field)
		if current is Array and value is Array:
			current.assign(value)
		else:
			object.set(field, value)

func _capture_queue(queue: ProductionQueue) -> Dictionary:
	var data: Dictionary = _read(queue, QUEUE_FIELDS)
	# Resource quantities are values, never runtime actor IDs for _decode to remap.
	data.paid_costs = queue.paid_costs.duplicate(true)
	return data

func _restore_queue(queue: ProductionQueue, data: Dictionary) -> void:
	_write(queue, QUEUE_FIELDS, data)
	queue.paid_costs.clear()
	if data.has("paid_costs"):
		queue.paid_costs.assign(data.paid_costs.duplicate(true))
	else:
		# Pre-receipt checkpoints paid the beta16 schedule, regardless of today's
		# catalog. In particular, old Archers/Cavalry never paid refundable gold.
		for unit_type: int in queue.queue:
			queue.paid_costs.append(LEGACY_QUEUE_COSTS[unit_type].duplicate(true))

static func _valid_queue_receipts(data: Dictionary) -> bool:
	if not data.has("paid_costs"):
		return true
	if not data.paid_costs is Array or data.paid_costs.size() != data.queue.size():
		return false
	for receipt: Variant in data.paid_costs:
		if not receipt is Dictionary or receipt.size() != 3:
			return false
		for resource: String in ["food", "wood", "gold"]:
			if not receipt.get(resource) is int or receipt[resource] < 0:
				return false
	return true

func capture(main: Node) -> Dictionary:
	_references.clear()
	var map: Node = main.game_map
	_references[map.get_instance_id()] = map
	var actors: Array = []
	for owner: int in [0, 1]:
		for building: BuildingBase in main._player_buildings[owner]:
			if is_instance_valid(building) and not building.is_queued_for_deletion() and building.state != BuildingBase.State.DESTROYED:
				actors.append(building)
		for unit: UnitBase in main._player_units[owner]:
			if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit.current_state != UnitBase.State.DEAD: actors.append(unit)
	for actor: Node in actors: _references[actor.get_instance_id()] = actor
	for resource: Node in map.resource_nodes.values(): _references[resource.get_instance_id()] = resource
	var tokens: Dictionary = {}
	for actor: Node in actors:
		if not actor is UnitBase: continue
		for key: String in ["_attack_march", "_pending_attack_march"]:
			var token: Variant = actor.get(key)
			if token != null:
				_references[token.get_instance_id()] = token
				tokens[token.get_instance_id()] = {"kind": "march" if key == "_attack_march" else "pending", "object": token}
	var data: Dictionary = {
		"schema": 1, "generator": MapData.GENERATOR_VERSION, "map_id": map.get_instance_id(),
		"seed": map.map_seed, "style": map.map_archetype, "difficulty": main.ai_controller.difficulty,
		"manager": _read(GameManager, MANAGER_FIELDS), "resources": ResourceManager._player_resources.duplicate(true),
		"actors": [], "deposits": [], "tokens": [], "shots": [],
		"main": _read(main, MAIN_FIELDS), "ai": _read(main.ai_controller, AI_FIELDS),
		"decision_time_left": main.ai_controller._decision_timer.time_left,
		"sacred": _read(map.sacred_site, SITE_FIELDS),
		"shrines": map.shrines.map(func(shrine: Node) -> Dictionary: return _read(shrine, SITE_FIELDS)),
		"fog": map.fog_of_war.fog_grid.duplicate(true), "visible": map.fog_of_war._previously_visible.duplicate(),
		"pending_terrain": map._pending_depleted_terrain_tiles.duplicate(),
		"camera": {"position": map.camera.position, "zoom": map.camera.zoom},
		"speed": Engine.time_scale, "learning": _read(main._match_learning, _script_fields(main._match_learning)),
		"receipts": _read(main._battle_receipts, _script_fields(main._battle_receipts)),
		"memories": {"resources": [], "buildings": []},
	}
	for id: int in tokens:
		data.tokens.append({"id": id, "kind": tokens[id].kind, "fields": _read(tokens[id].object, _script_fields(tokens[id].object))})
	for resource: Node in map.resource_nodes.values():
		data.deposits.append({"id": resource.get_instance_id(), "tile": resource.tile_position, "kind": resource.resource_type, "remaining": resource.remaining, "total": resource.total_amount})
	for actor: Node in actors:
		var record: Dictionary = {"id": actor.get_instance_id(), "owner": actor.player_owner, "position": actor.global_position}
		if actor is BuildingBase:
			record.merge({"kind": "building", "type": actor.building_type, "fields": _read(actor, BUILDING_FIELDS)})
			var queue: Node = actor.get_production_queue()
			if queue != null: record.queue = _capture_queue(queue)
		else:
			record.merge({"kind": "unit", "type": actor.unit_type, "fields": _read(actor, UNIT_FIELDS)})
			if actor is Villager: record.worker = _read(actor, WORKER_FIELDS)
			if actor.unit_type == UnitData.UnitType.TRADER: record.trader = _read(actor, TRADER_FIELDS)
		data.actors.append(record)
	for container_name: String in ["UnitsContainer", "BuildingsContainer"]:
		for node: Node in map.get_node(container_name).get_children():
			var kind: String = "ranged" if node is Combat.RangedProjectile else "melee" if node is Combat.CommittedMeleeHit else "defensive" if node is BuildingBase.DefensiveArrow else ""
			if kind.is_empty() or bool(node.get("finished")) or node.is_queued_for_deletion(): continue
			data.shots.append({"kind": kind, "fields": _read(node, _script_fields(node)), "position": node.global_position if node is Node2D else Vector2.ZERO})
	if is_instance_valid(map.fog_memory):
		for record: Dictionary in map.fog_memory.resources.values():
			data.memories.resources.append({"tile": record.tile, "kind": record.resource_type, "remaining": record.remaining})
		for record: Dictionary in map.fog_memory.buildings.values():
			var clean: Dictionary = record.duplicate()
			for key: String in ["visual", "material", "signature", "tile", "footprint"]: clean.erase(key)
			data.memories.buildings.append(_encode(clean))
	_references.clear()
	return data

func restore_world(main: Node, data: Dictionary) -> bool:
	_references.clear()
	var map: Node = main.game_map
	_references[int(data.map_id)] = map
	var deposits: Dictionary = {}
	for record: Dictionary in data.deposits: deposits[record.tile] = record
	for tile: Vector2i in map.resource_nodes.keys():
		var resource: ResourceNode = map.resource_nodes[tile]
		if not deposits.has(tile):
			map._on_resource_depleted(resource, tile)
			resource.free()
		else:
			var record: Dictionary = deposits[tile]
			resource.remaining = int(record.remaining)
			resource.total_amount = int(record.total)
			_references[int(record.id)] = resource
	# Civilizations and completed upgrades must be in force before actor art/stats.
	_write(GameManager, MANAGER_FIELDS, data.manager)
	for record: Dictionary in data.actors:
		if record.kind != "building": continue
		var actor: Node = main._spawn_building(int(record.type), int(record.owner), map.world_to_tile(record.position))
		if actor == null: return false
		_references[int(record.id)] = actor
	for record: Dictionary in data.actors:
		if record.kind != "unit": continue
		var actor: Node = main._spawn_unit(int(record.type), int(record.owner), record.position, null, true)
		if actor == null: return false
		_references[int(record.id)] = actor
	for record: Dictionary in data.tokens:
		_references[int(record.id)] = MARCH.new() if record.kind == "march" else PENDING_MARCH.new()
	for record: Dictionary in data.tokens:
		var token: RefCounted = _references[int(record.id)]
		_write(token, _script_fields(token), record.fields)
		if record.kind == "march": token.set("_scan_frame", -1)
	for record: Dictionary in data.actors:
		var actor: Node = _references[int(record.id)]
		if record.kind == "building":
			_write(actor, BUILDING_FIELDS, record.fields)
			actor._update_sprite_appearance()
			actor.queue_redraw()
			if record.has("queue"): _restore_queue(actor.get_production_queue(), record.queue)
		else:
			_write(actor, UNIT_FIELDS, record.fields)
			if record.has("worker"):
				_write(actor, WORKER_FIELDS, record.worker)
				var service: Object = instance_from_id(actor._service_target_id) if actor._service_target_id > 0 else null
				if is_instance_valid(service): actor._reserve_service_position(service, actor._service_destination, actor._service_kind)
			if record.has("trader"): _write(actor, TRADER_FIELDS, record.trader)
	# Reapply ledgers only after every identity exists; spawning must not purchase,
	# grant cap, finish construction, or emit production a second time.
	_write(GameManager, MANAGER_FIELDS, data.manager)
	ResourceManager._player_resources = data.resources.duplicate(true)
	for record: Dictionary in data.shots:
		var shot: Node = Combat.RangedProjectile.new() if record.kind == "ranged" else Combat.CommittedMeleeHit.new() if record.kind == "melee" else BuildingBase.DefensiveArrow.new()
		_write(shot, _script_fields(shot), record.fields)
		map.get_node("UnitsContainer").add_child(shot)
		if shot is Node2D:
			shot.global_position = record.position
			shot.z_index = 80
		if record.kind == "defensive": shot.add_to_group("defensive_projectiles")
	return true

func restore_context(main: Node, data: Dictionary) -> void:
	var map: Node = main.game_map
	_write(main, MAIN_FIELDS, data.main)
	_write(main.ai_controller, AI_FIELDS, data.ai)
	main.ai_controller._economy_rebalance_deferred_scheduled = false
	main.ai_controller._decision_timer.start(maxf(0.05, float(data.decision_time_left)))
	_write(map.sacred_site, SITE_FIELDS, data.sacred)
	# Saves made before shrines existed simply leave them neutral.
	var saved_shrines: Array = data.get("shrines", [])
	for index: int in mini(saved_shrines.size(), map.shrines.size()):
		_write(map.shrines[index], SITE_FIELDS, saved_shrines[index])
	_write(main._match_learning, _script_fields(main._match_learning), data.learning)
	_write(main._battle_receipts, _script_fields(main._battle_receipts), data.receipts)
	map.fog_of_war.fog_grid = data.fog.duplicate(true)
	map.fog_of_war._previously_visible.assign(data.visible)
	map.fog_of_war._visibility_cache_valid = false
	map.fog_of_war._initial_apply_done = false
	# Initial regeneration still draws original deposits. Revealed depletions
	# were already grass when saved; only unseen depletions retain old terrain.
	for tile: Vector2i in map._pending_depleted_terrain_tiles.keys():
		if not data.pending_terrain.has(tile): map._apply_depleted_terrain_visual(tile)
	map._pending_depleted_terrain_tiles = data.pending_terrain.duplicate()
	var memory: Node = map._ensure_fog_memory()
	for record: Dictionary in data.memories.resources: memory.remember_resource(record.tile, record.kind, int(record.remaining))
	for record: Dictionary in data.memories.buildings: memory.remember_building(_decode(record))
	map.camera.position = data.camera.position
	map.camera.zoom = Vector2.ONE * clampf(float(data.camera.zoom.x), map._camera_zoom_min, map._camera_zoom_max)
	map._user_zoom_override = true
	map._clamp_camera()
	map.camera.reset_smoothing()
	map.camera.force_update_scroll()
	Engine.time_scale = clampf(float(data.speed), 0.5, 3.0)
	main._update_fog_of_war()
	main._update_fog_entity_visibility()
	main._refresh_sacred_site_status()
	main.hud.refresh_match_state()
	main._refresh_hud_resources(0)
	main._update_population_display()
	_references.clear()

static func _bounded(value: Variant, depth: int = 0) -> bool:
	if depth > 24 or value is Object: return false
	if value is Array or value is Dictionary:
		if value.size() > 20000: return false
		for key: Variant in value:
			if not _bounded(key, depth + 1): return false
			if value is Dictionary and not _bounded(value[key], depth + 1): return false
	return true

static func validate(data: Dictionary) -> String:
	if data.get("schema") != 1 or data.get("generator") != MapData.GENERATOR_VERSION: return "This save belongs to a different game version."
	for key: String in ["manager", "resources", "main", "ai", "sacred", "camera", "learning", "receipts", "memories", "pending_terrain"]:
		if not data.get(key) is Dictionary: return "Incomplete solo save."
	for key: String in ["actors", "deposits", "tokens", "shots", "fog", "visible"]:
		if not data.get(key) is Array: return "Incomplete solo save."
	if not _bounded(data): return "Solo save exceeds safe limits."
	for field: String in MANAGER_FIELDS:
		if not data.manager.has(field): return "Incomplete player state."
	for field: String in MAIN_FIELDS:
		if not data.main.has(field): return "Incomplete match state."
	for field: String in AI_FIELDS:
		if not data.ai.has(field): return "Incomplete opponent state."
	for field: String in SITE_FIELDS:
		if not data.sacred.has(field): return "Incomplete sacred state."
	if not data.memories.get("resources") is Array or not data.memories.get("buildings") is Array: return "Invalid sighting memory."
	if not data.get("difficulty") is int or data.difficulty not in [0, 1, 2] or not data.get("map_id") is int or not data.get("decision_time_left") is float or not data.get("speed") is float or not is_finite(data.speed): return "Invalid match settings."
	if not data.get("seed") is int or int(data.seed) <= 0 or not data.get("style") is int or int(data.style) < 0 or int(data.style) >= MapData.MAP_ARCHETYPES.size(): return "Invalid battlefield."
	if data.actors.is_empty() or data.actors.size() > MAX_ACTORS or data.deposits.size() > MAX_RESOURCES or data.tokens.size() > MAX_ACTORS or data.shots.size() > MAX_ACTORS: return "Invalid actor count."
	if not data.manager.get("players") is Dictionary or not data.manager.players.has(0) or not data.manager.players.has(1): return "Missing players."
	if not data.manager.get("game_time") is float or not is_finite(data.manager.game_time) or data.manager.game_time < 0.0: return "Invalid match clock."
	if not data.camera.get("position") is Vector2 or not data.camera.position.is_finite() or not data.camera.get("zoom") is Vector2 or not data.camera.zoom.is_finite() or data.camera.zoom.x <= 0.0 or data.camera.zoom.y <= 0.0: return "Invalid camera."
	var ids: Dictionary = {int(data.map_id): true}
	var tiles: Dictionary = {}
	var towns: Array[int] = [0, 0]
	var population: Array[int] = [0, 0]
	var reservations: Dictionary = {}
	for owner: int in [0, 1]:
		if not data.manager.players[owner] is Dictionary or not data.resources.get(owner) is Dictionary: return "Invalid player state."
		for resource: String in ["food", "wood", "gold"]:
			if not data.resources[owner].get(resource) is int or int(data.resources[owner][resource]) < 0: return "Invalid resource bank."
		if not data.manager.players[owner].get("civilization") is int or int(data.manager.players[owner].civilization) not in [0, 1, 2]: return "Invalid civilization."
	for record: Variant in data.actors:
		if not record is Dictionary or not record.get("fields") is Dictionary or not record.get("id") is int or ids.has(record.id): return "Invalid actor identity."
		ids[record.id] = true
		if record.get("owner") not in [0, 1] or not record.get("position") is Vector2 or not record.position.is_finite(): return "Invalid actor position."
		if record.position.length() > 20000.0: return "Actor outside battlefield."
		if record.get("kind") == "unit":
			for field: String in UNIT_FIELDS:
				if not record.fields.has(field): return "Incomplete unit state."
			if not UnitData.UNITS.has(record.get("type")) or not record.fields.has("hp") or float(record.fields.hp) <= 0.0: return "Invalid unit."
			population[int(record.owner)] += int(UnitData.UNITS[record.type].get("pop_cost", 1))
			if not is_finite(float(record.fields.hp)) or record.fields.player_owner != record.owner or record.fields.unit_type != record.type or not record.fields.path is PackedVector2Array or record.fields.path.size() > 4096 or not record.fields.queued_orders is Array or record.fields.queued_orders.size() > UnitBase.MAX_QUEUED_ORDERS: return "Invalid unit orders."
			if int(record.type) == UnitData.UnitType.VILLAGER:
				if not record.get("worker") is Dictionary: return "Missing worker job."
				for field: String in WORKER_FIELDS:
					if not record.worker.has(field): return "Incomplete worker job."
			if int(record.type) == UnitData.UnitType.TRADER and not record.get("trader") is Dictionary: return "Missing trade route."
		elif record.get("kind") == "building":
			for field: String in BUILDING_FIELDS:
				if not record.fields.has(field): return "Incomplete building state."
			if BuildingData.get_building_stats(int(record.get("type", -1))).is_empty() or record.fields.get("state") not in [BuildingBase.State.CONSTRUCTING, BuildingBase.State.ACTIVE]: return "Invalid building."
			if record.fields.player_owner != record.owner or record.fields.building_type != record.type or int(record.fields.hp) <= 0 or not is_finite(float(record.fields.build_progress)) or float(record.fields.build_progress) < 0 or float(record.fields.build_progress) > 1: return "Invalid construction state."
			if int(record.type) == BuildingData.BuildingType.TOWN_CENTER: towns[record.owner] += 1
			if record.has("queue"):
				if not record.queue is Dictionary or not record.queue.get("queue") is Array or not record.queue.get("_population_reservation_ids") is Array or record.queue.queue.size() > ProductionQueue.MAX_QUEUE_SIZE or record.queue.queue.size() != record.queue._population_reservation_ids.size(): return "Invalid production queue."
				if not _valid_queue_receipts(record.queue): return "Invalid production payment receipts."
		else: return "Unknown actor."
		if record.has("queue"):
			for index: int in record.queue.queue.size():
				var unit_type: int = int(record.queue.queue[index])
				var reservation: int = int(record.queue._population_reservation_ids[index])
				if not UnitData.UNITS.has(unit_type) or reservations.has(reservation): return "Invalid paid production."
				reservations[reservation] = {"player_id": int(record.owner), "amount": int(UnitData.UNITS[unit_type].get("pop_cost", 1))}
	if data.manager._population_reservations != reservations: return "Production reservations do not match paid queues."
	for owner: int in [0, 1]:
		if int(data.manager.players[owner].get("population", -1)) != population[owner]: return "Population does not match saved actors."
	if towns[0] == 0 or towns[1] == 0: return "This match has ended."
	for record: Variant in data.deposits:
		if not record is Dictionary or not record.get("tile") is Vector2i or not record.get("id") is int or ids.has(record.id) or tiles.has(record.tile): return "Invalid deposit identity."
		if record.tile.x < 0 or record.tile.y < 0 or record.tile.x >= MapData.MAP_WIDTH or record.tile.y >= MapData.MAP_HEIGHT or record.get("kind") not in ["food", "wood", "gold"] or int(record.get("remaining", 0)) <= 0 or int(record.remaining) > int(record.get("total", 0)): return "Invalid deposit."
		ids[record.id] = true
		tiles[record.tile] = true
	if data.fog.size() != MapData.MAP_HEIGHT: return "Invalid exploration memory."
	for row: Variant in data.fog:
		if not row is Array or row.size() != MapData.MAP_WIDTH: return "Invalid exploration memory."
		for cell: Variant in row:
			if cell not in [0, 1, 2]: return "Invalid exploration memory."
	return ""
