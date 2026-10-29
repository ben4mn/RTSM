extends Node
## Uses the existing simulation exclusively on the server. Clients keep inert
## visual replicas, with local player 0 remapped to their assigned server slot.

const PLANNER := preload("res://scripts/main/group_order_planner.gd")
const ATTACK_MARCH := preload("res://scripts/main/attack_march_cohesion.gd")
var main: Node = null
var game_map: Node2D = null
var entities: Dictionary = {}
var _next_entity_id: int = 1
var _interpolation: Dictionary = {}
var _hit_flashes: Dictionary = {}
var _camera_initialized: bool = false
var _snapshot_number: int = 0
var _resource_tiles: Array[Vector2i] = []
## Last publicly observed enemy footprints, separately for each recipient.
var _known_enemy_buildings: Dictionary = {0: {}, 1: {}}
var _forgotten_buildings: Dictionary = {0: [], 1: []}
var _known_resource_counts: Dictionary = {0: {}, 1: {}}

func setup(controller: Node) -> void:
	main = controller
	game_map = main.game_map
	for tile: Vector2i in game_map.resource_nodes:
		_resource_tiles.append(tile)
	process_mode = Node.PROCESS_MODE_ALWAYS
	main.ai_controller.process_mode = Node.PROCESS_MODE_DISABLED
	main._hints_shown = main.HINTS.size()
	if NetworkSession.is_client():
		game_map.sacred_site.set_process(false)
		main._guided_opening_active = false
		main._clear_guidance_state()
	else:
		GameManager.game_over.connect(_on_server_game_over)

func _on_server_game_over(winner: int) -> void:
	NetworkSession.call_deferred("end_match", winner, main._victory_reason)

func _process(delta: float) -> void:
	if not NetworkSession.is_client():
		return
	for id: int in _interpolation.keys():
		var unit: UnitBase = entities.get(id) as UnitBase
		if is_instance_valid(unit):
			unit.global_position = unit.global_position.lerp(_interpolation[id], minf(1.0, delta * 15.0))
			unit._update_sprite_motion(delta)
			unit.queue_redraw()
	for id: int in _hit_flashes.keys():
		_hit_flashes[id] = float(_hit_flashes[id]) - delta
		var node: Node2D = entities.get(id) as Node2D
		if float(_hit_flashes[id]) <= 0.0 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.modulate = Color.WHITE
			_hit_flashes.erase(id)

func _local_owner(server_owner: int) -> int:
	if server_owner < 0:
		return server_owner
	return 0 if server_owner == NetworkSession.player_slot else 1

func _register_server_entities() -> void:
	for group: String in ["units", "buildings"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if not (node is UnitBase or node is BuildingBase) or node.is_queued_for_deletion():
				continue
			if not node.has_meta("network_id"):
				node.set_meta("network_id", _next_entity_id)
				_next_entity_id += 1
			entities[NetworkSession.entity_id(node)] = node
	for id: int in entities.keys():
		if not is_instance_valid(entities[id]) or entities[id].is_queued_for_deletion():
			entities.erase(id)

func broadcast_snapshots() -> void:
	_register_server_entities()
	_snapshot_number += 1
	for slot: int in 2:
		NetworkSession.send_snapshot(slot, _snapshot_for(slot))

func _snapshot_for(slot: int) -> Dictionary:
	var actors: Array = []
	var observed_buildings: Dictionary = {}
	for node: Node2D in entities.values():
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.player_owner != slot and not game_map.is_entity_visible_to_player(node, slot):
			continue
		var actor: Dictionary = {"id": NetworkSession.entity_id(node), "owner": node.player_owner, "x": node.global_position.x, "y": node.global_position.y, "hp": node.hp, "max_hp": node.max_hp}
		if node is UnitBase:
			if node.current_state == UnitBase.State.DEAD:
				continue
			actor.merge({"kind": "unit", "type": node.unit_type, "state": node.current_state, "stance": node.stance, "animation": [node._attack_animation_remaining, node._attack_animation_duration, node._attack_animation_direction.x, node._attack_animation_direction.y, node._sprite.flip_h if node._sprite != null else false]})
			# Only an already-visible actor's observable tool/pose crosses here.
			# No work target, private order or cargo is included for opponents.
			var work_pose: Vector3 = node.get_work_presentation()
			actor["work_pose"] = [int(work_pose.x), work_pose.y, work_pose.z]
			if node.player_owner == slot:
				var points: Array = []
				var route: PackedVector2Array = node.get_remaining_navigation_path()
				for point: Vector2 in route.slice(0, mini(route.size(), 12)):
					points.append([point.x, point.y])
				actor["path"] = points
				actor["destination"] = [node.move_target.x, node.move_target.y]
				actor["attack_move"] = node.attack_move
				actor["marching"] = node.is_attack_marching()
				actor["queued_orders"] = _serialize_orders(node.queued_orders)
			if node is Trader and node.player_owner == slot:
				actor.merge({"trade_status": node.get_trade_status(), "trade_cargo": node.carried_gold, "trade_income": node.get_trip_income()})
			if node is Villager and node.player_owner == slot:
				actor.merge({"gather": node.gather_type, "cargo": node.carried_amount, "cargo_type": node.carried_resource_type, "cargo_manifest": node.get_carried_resources(), "work": node.get_economy_task(), "work_status": node.get_work_status(), "recovering": node.is_auto_recovering(), "building_order": node.has_active_build_order()})
		else:
			if node.state == BuildingBase.State.DESTROYED:
				continue
			actor.merge({"kind": "building", "type": node.building_type, "state": node.state, "progress": node.build_progress})
			if node.player_owner == slot:
				actor["rally"] = [node.rally_point.x, node.rally_point.y]
				actor["custom_rally"] = node.rally_point_is_custom
				actor["rally_orders"] = _serialize_orders(node.rally_orders)
				var queue: ProductionQueue = node.get_production_queue()
				if queue != null:
					actor["queue"] = {"items": queue.queue, "progress": queue.current_progress, "time": queue.current_train_time, "training": queue.is_training, "repeat": false, "repeat_type": queue.auto_queue_unit_type}
		actors.append(actor)
		if node is BuildingBase and node.player_owner != slot:
			var id: int = NetworkSession.entity_id(node)
			observed_buildings[id] = true
			_known_enemy_buildings[slot][id] = {"tile": game_map.world_to_tile(node.global_position), "footprint": node.footprint, "actor": {"id": id, "owner": node.player_owner, "type": node.building_type, "state": node.state, "progress": node.build_progress, "hp": node.hp, "x": node.global_position.x, "y": node.global_position.y}}
	# Omission alone means loss of sight, never destruction. Retire a previous
	# sighting only when its last-known ground is actually scouted and empty.
	var forgotten_buildings: Array = _forgotten_buildings[slot]
	for id: int in _known_enemy_buildings[slot].keys():
		if observed_buildings.has(id): continue
		var known: Dictionary = _known_enemy_buildings[slot][id]
		var visible: bool = false
		for dy: int in known.footprint.y:
			for dx: int in known.footprint.x:
				if game_map.is_tile_visible_to_player(known.tile + Vector2i(dx, dy), slot): visible = true
		if visible:
			forgotten_buildings.append(id)
			_known_enemy_buildings[slot].erase(id)
	var resources: Array = []
	var visible_resource_tiles: Dictionary = game_map.get_visible_tiles_for_player(_resource_tiles, slot)
	for tile: Vector2i in _resource_tiles:
		if visible_resource_tiles.has(tile):
			var resource: Node2D = game_map.get_resource_node_at(tile)
			var amount: int = resource.remaining if is_instance_valid(resource) else 0
			resources.append([tile.x, tile.y, amount])
			_known_resource_counts[slot][tile] = amount
	var memories: Dictionary = {"buildings": [], "resources": []}
	for known: Dictionary in _known_enemy_buildings[slot].values(): memories.buildings.append(known.actor)
	for tile: Vector2i in _known_resource_counts[slot]: memories.resources.append([tile.x, tile.y, _known_resource_counts[slot][tile]])
	var site: Node = game_map.sacred_site
	var player: Dictionary = GameManager.players[slot].duplicate()
	player.erase("units")
	player.erase("buildings")
	return {"memories": memories, "forgotten_buildings": forgotten_buildings.duplicate(), "worker_undo": main._worker_order_undo.status(slot), "worker_undo_result": main._worker_order_undo.result(slot), "tick": _snapshot_number, "time": GameManager.game_time, "civilizations": [GameManager.get_player_civilization(0), GameManager.get_player_civilization(1)], "actors": actors, "resources": resources, "bank": ResourceManager.get_all_resources(slot), "player": player, "upgrades": GameManager.player_upgrades[slot], "research": GameManager.researched_upgrades[slot], "stats": main._stats[slot], "battle": main._battle_receipts.get_summary(slot), "site": {"state": site.state, "owner": site.owning_player, "capture": site.capture_progress, "timer": site.victory_timer, "hold": site.victory_hold_time, "clock_ticking": site.clock_ticking, "garrison_paused": site.garrison_paused, "neutralizing": site._being_neutralized}}

func apply_snapshot(snapshot: Dictionary) -> void:
	GameManager.game_time = float(snapshot.get("time", 0.0))
	var civilizations: Variant = snapshot.get("civilizations")
	if NetworkSession._valid_civilizations(civilizations):
		# Apply both public identities before creating replicas. Guest local 0
		# maps to server slot 1; its units must never inherit the host's bonuses.
		for server_owner: int in 2:
			GameManager.players[_local_owner(server_owner)]["civilization"] = int(civilizations[server_owner])
	var player: Dictionary = snapshot.get("player", {})
	for key: String in ["age", "population", "population_reserved", "population_cap", "max_population", "is_defeated"]:
		if player.has(key):
			GameManager.players[0][key] = player[key]
	GameManager.player_upgrades[0] = snapshot.get("upgrades", {})
	GameManager.researched_upgrades[0] = snapshot.get("research", [])
	main._stats[0] = snapshot.get("stats", main._stats[0])
	# These are only this recipient's observed losses. No opponent receipt or
	# hidden attacker identity crosses the authority boundary.
	main._battle_receipts.apply_local_summary(snapshot.get("battle", {}))
	main._apply_network_worker_undo(snapshot.get("worker_undo", {}), snapshot.get("worker_undo_result", {}))
	var bank: Dictionary = snapshot.get("bank", {})
	for resource: String in ResourceManager.RESOURCE_NAMES:
		var amount: int = int(bank.get(resource, 0))
		ResourceManager._player_resources[0][resource] = amount
		ResourceManager.resources_changed.emit(0, resource, amount)
	var seen: Dictionary = {}
	for actor: Dictionary in snapshot.get("actors", []):
		var id: int = int(actor.id)
		seen[id] = true
		var node: Node2D = entities.get(id) as Node2D
		var was_present: bool = is_instance_valid(node)
		if not is_instance_valid(node):
			node = _create_replica(actor)
			if node == null:
				continue
			entities[id] = node
		var world := Vector2(float(actor.x), float(actor.y))
		if node is UnitBase:
			_interpolation[id] = world
			node.current_state = int(actor.state)
			node.stance = int(actor.stance)
			if node.player_owner == 0:
				var route := PackedVector2Array()
				for point: Array in actor.get("path", []):
					route.append(Vector2(float(point[0]), float(point[1])))
				node.path = route
				node.path_index = 0
				var destination: Array = actor.get("destination", [actor.x, actor.y])
				node.move_target = Vector2(float(destination[0]), float(destination[1]))
				node.attack_move = bool(actor.get("attack_move", false))
				node.queued_orders = _deserialize_orders(actor.get("queued_orders", []))
			# Default false on every packet: missing, non-boolean or enemy values
			# cannot retain an earlier own status or disclose another cohort.
			var marching: Variant = actor.get("marching", false)
			node.set_meta("network_attack_march", node.player_owner == 0 and _local_owner(int(actor.owner)) == 0 and typeof(marching) == TYPE_BOOL and marching == true)
			var animation: Array = actor.get("animation", [])
			node.apply_work_presentation(actor.get("work_pose", []))
			if animation.size() == 5:
				node._attack_animation_remaining = float(animation[0])
				node._attack_animation_duration = maxf(0.01, float(animation[1]))
				node._attack_animation_direction = Vector2(float(animation[2]), float(animation[3]))
				if node._sprite != null:
					node._sprite.flip_h = bool(animation[4])
			if node is Trader:
				node.set_meta("network_trade_status", str(actor.get("trade_status", "")))
				node.carried_gold = int(actor.get("trade_cargo", 0))
				node.set_meta("network_trade_income", int(actor.get("trade_income", 0)))
			if node is Villager:
				node.gather_type = int(actor.get("gather", 0))
				node.carried_amount = int(actor.get("cargo", 0))
				node.carried_resource_type = str(actor.get("cargo_type", ""))
				node.set_meta("network_cargo", actor.get("cargo_manifest", {}))
				node.set_meta("network_work", str(actor.get("work", "")))
				node.set_meta("network_work_status", str(actor.get("work_status", "")))
				node.set_meta("network_recovering", bool(actor.get("recovering", false)))
				node.set_meta("network_building", bool(actor.get("building_order", false)))
		else:
			node.state = int(actor.state)
			node.build_progress = float(actor.progress)
			node._update_sprite_appearance()
			var rally: Array = actor.get("rally", [])
			if rally.size() == 2:
				node.rally_point = Vector2(float(rally[0]), float(rally[1]))
				node.rally_point_is_custom = bool(actor.get("custom_rally", false))
			node.rally_orders = _deserialize_orders(actor.get("rally_orders", [])) if node.player_owner == 0 else []
			var queue: ProductionQueue = node.get_production_queue()
			if queue != null and actor.has("queue"):
				var data: Dictionary = actor.queue
				queue.queue.assign(data.items)
				queue.current_progress = float(data.progress)
				queue.current_train_time = float(data.time)
				queue.is_training = bool(data.training)
				queue.auto_queue_enabled = false
				queue.auto_queue_unit_type = int(data.repeat_type)
		if was_present and float(actor.hp) < float(node.hp) and node.is_visible_in_tree():
			if node is UnitBase:
				(node as UnitBase)._health_feedback_remaining = 2.0
			if not GameManager.reduced_flashes:
				# Inert replicas cannot advance a building-bound tween. Reuse
				# its presentation palette through the adapter's visual clock;
				# the sprite keeps its own construction/ownership modulation.
				node.modulate = BuildingBase.DAMAGE_FLASH_COLOR if node is BuildingBase else Color(1.16, 1.12, 1.04)
				_hit_flashes[id] = BuildingBase.DAMAGE_FLASH_SECONDS if node is BuildingBase else 0.15
			AudioManager.play_world("attack_hit", node)
		node.hp = actor.hp
		node.max_hp = actor.max_hp
		node.queue_redraw()
		if node is BuildingBase and node.player_owner != 0:
			game_map.remember_visible_building(node)
	for id: int in entities.keys():
		if not seen.has(id):
			_remove_replica(id)
	# Cumulative observations survive skipped/coalesced snapshots. They only
	# create inert memory art, never live actors or targetable resources.
	var memories: Dictionary = snapshot.get("memories", {})
	for data: Dictionary in memories.get("buildings", []):
		var local_data: Dictionary = data.duplicate()
		local_data.owner = _local_owner(int(data.owner))
		if local_data.owner != 0:
			game_map._ensure_fog_memory().remember_building(local_data)
			var remembered: Dictionary = game_map.fog_memory.buildings[int(local_data.id)]
			for dy: int in remembered.footprint.y:
				for dx: int in remembered.footprint.x:
					game_map.fog_of_war.remember_explored(remembered.tile + Vector2i(dx, dy))
	for data: Array in memories.get("resources", []):
		var tile := Vector2i(int(data[0]), int(data[1]))
		var resource: ResourceNode = game_map.get_resource_node_at(tile) as ResourceNode
		game_map.fog_of_war.remember_explored(tile)
		if int(data[2]) <= 0:
			# Zero here was observed by this player, possibly in a skipped
			# snapshot. It is not a hidden live depletion notification.
			var memory: Node2D = game_map._ensure_fog_memory()
			memory._erase(memory.resources, tile)
			if is_instance_valid(resource):
				game_map._on_resource_depleted(resource, tile)
				resource.queue_free()
		elif is_instance_valid(resource):
			game_map._ensure_fog_memory().remember_resource(tile, resource.resource_type, int(data[2]))
	game_map.forget_scouted_buildings(snapshot.get("forgotten_buildings", []))
	for item: Array in snapshot.get("resources", []):
		var resource: Node2D = game_map.get_resource_node_at(Vector2i(int(item[0]), int(item[1])))
		if resource is ResourceNode:
			resource.remaining = int(item[2])
			if resource.remaining > 0:
				game_map.remember_visible_resource(resource)
			if resource.remaining <= 0:
				game_map._on_resource_depleted(resource, Vector2i(int(item[0]), int(item[1])))
				resource.queue_free()
	var site_data: Dictionary = snapshot.get("site", {})
	var site: Node = game_map.sacred_site
	if not site_data.is_empty():
		site.state = int(site_data.state)
		site.owning_player = _local_owner(int(site_data.owner))
		site.capture_progress = float(site_data.capture)
		site.victory_timer = float(site_data.timer)
		site.victory_hold_time = float(site_data.hold)
		site._update_visuals()
	_apply_site_clock_snapshot(site, site_data)
	main._refresh_sacred_site_status()
	main._update_population_display()
	if not _camera_initialized and is_instance_valid(main._player_town_center):
		_camera_initialized = true
		game_map.camera.position = main._get_initial_camera_focus(main._player_town_center.global_position)
		game_map._clamp_camera()
		game_map.camera.reset_smoothing()


func _apply_site_clock_snapshot(site: Node, data: Dictionary) -> void:
	# These public objective flags come only from authority. Filtered actor
	# replicas cannot establish whether an unseen garrison exists. Missing or
	# malformed values clear earlier flags on every packet, including no site.
	site.clock_ticking = false
	site.garrison_paused = false
	site._being_neutralized = false
	if int(data.get("state", -1)) != site.SiteState.CAPTURED or int(data.get("owner", -1)) not in [0, 1]:
		return
	var neutralizing: Variant = data.get("neutralizing")
	site._being_neutralized = typeof(neutralizing) == TYPE_BOOL and neutralizing == true
	if site._being_neutralized:
		return
	var paused: Variant = data.get("garrison_paused")
	site.garrison_paused = site.match_mode == SkirmishData.MatchMode.STANDARD and typeof(paused) == TYPE_BOOL and paused == true
	var ticking: Variant = data.get("clock_ticking")
	# A contradictory explicit pause wins; never show a live clock from a
	# malformed combination. Control race ignores the Standard-only pause.
	site.clock_ticking = not site.garrison_paused and typeof(ticking) == TYPE_BOOL and ticking == true

func _create_replica(actor: Dictionary) -> Node2D:
	var owner: int = _local_owner(int(actor.owner))
	var type: int = int(actor.type)
	var unit_actor: bool = str(actor.kind) == "unit"
	var scenes: Dictionary = main._unit_scenes if unit_actor else main._building_scenes
	if not scenes.has(type):
		return null
	var node: Node2D = (scenes[type] as PackedScene).instantiate()
	node.player_owner = owner
	node.global_position = Vector2(float(actor.x), float(actor.y))
	node.set_meta("network_id", int(actor.id))
	# Disable before add_child: no replica can run even one simulation tick.
	if node is CollisionObject2D:
		node.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if unit_actor:
		node.unit_type = type
		node.set_team_color(main.TEAM_COLORS[owner])
		game_map.get_node("UnitsContainer").add_child(node)
		main._player_units[owner].append(node)
	else:
		node.building_type = type
		game_map.get_node("BuildingsContainer").add_child(node)
		main._player_buildings[owner].append(node)
		game_map.place_building_obstacle(game_map.world_to_tile(node.global_position), node.footprint)
		if node.provides_food:
			game_map.register_harvestable(node)
		if owner == 0 and type == BuildingData.BuildingType.TOWN_CENTER:
			main._player_town_center = node
	return node

func _remove_replica(id: int) -> void:
	var node: Node2D = entities[id] as Node2D
	entities.erase(id)
	_interpolation.erase(id)
	_hit_flashes.erase(id)
	if not is_instance_valid(node):
		return
	if node is UnitBase:
		node.set_meta("network_attack_march", false)
		main._player_units[node.player_owner].erase(node)
	else:
		main._player_buildings[node.player_owner].erase(node)
		game_map.remove_building_obstacle(game_map.world_to_tile(node.global_position), node.footprint)
		if node.provides_food:
			game_map.unregister_harvestable(node)
	node.queue_free()

func show_feedback(message: String) -> void:
	main.hud.show_notification(message, Color(1.0, 0.7, 0.35))

func finish_match(server_winner: int, reason: String) -> void:
	get_tree().paused = false
	if server_winner >= 0:
		main._conclude_match(_local_owner(server_winner), reason)
	else:
		# A transport failure/draw must not falsely award either player victory.
		main._victory_reason = reason
		for player: Dictionary in GameManager.players.values():
			player.is_defeated = true
		GameManager.set_state(GameManager.GameState.GAME_OVER)
		main._show_game_over()

func _owned(id: int, owner: int) -> Node2D:
	var node: Node2D = entities.get(id) as Node2D
	if not is_instance_valid(node) or node.is_queued_for_deletion() or node.player_owner != owner or node.hp <= 0:
		return null
	return node

func _serialize_orders(orders: Array[Dictionary]) -> Array:
	var serialized: Array = []
	for order: Dictionary in orders:
		var position: Vector2 = order.get("position", Vector2.ZERO)
		if order.get("kind", "") == "dropoff":
			var target: Object = instance_from_id(int(order.get("target_id", 0)))
			if not is_instance_valid(target) or not target is Node2D:
				continue
			position = target.global_position
		serialized.append({"kind": str(order.get("kind", "move")), "position": [position.x, position.y]})
	return serialized


func _deserialize_orders(serialized: Variant) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	if not serialized is Array:
		return orders
	for entry: Variant in serialized.slice(0, UnitBase.MAX_QUEUED_ORDERS):
		if not entry is Dictionary or not entry.get("position", null) is Array or entry.position.size() != 2:
			continue
		orders.append({"kind": str(entry.get("kind", "move")), "position": Vector2(float(entry.position[0]), float(entry.position[1]))})
	return orders


func _valid_packet(packet: Dictionary) -> bool:
	if packet.has("enabled") and typeof(packet.enabled) != TYPE_BOOL:
		return false
	for key: String in ["target", "type", "index", "sequence", "match", "undo_id"]:
		if packet.has(key) and typeof(packet[key]) not in [TYPE_INT, TYPE_FLOAT]:
			return false
	if packet.has("undo_id"):
		var undo_id: float = float(packet.undo_id)
		if not is_finite(undo_id) or undo_id <= 0.0 or undo_id != floor(undo_id) or undo_id > 9007199254740991.0: return false
	for key: String in ["command", "research", "source", "destination"]:
		if packet.has(key) and not packet[key] is String:
			return false
	if packet.has("ids"):
		if not packet.ids is Array or packet.ids.size() > 64:
			return false
		for id: Variant in packet.ids:
			if typeof(id) not in [TYPE_INT, TYPE_FLOAT]:
				return false
	if packet.has("position"):
		if not packet.position is Array or packet.position.size() != 2:
			return false
		for value: Variant in packet.position:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > 100000.0:
				return false
	return true

func execute_command(owner: int, packet: Dictionary) -> String:
	if not _valid_packet(packet) or owner not in [0, 1] or GameManager.current_state != GameManager.GameState.PLAYING:
		return "Invalid order"
	_register_server_entities()
	var operation: String = str(packet.get("command", ""))
	var units: Array[UnitBase] = []
	for id: Variant in packet.get("ids", []):
		var unit: Node2D = _owned(int(id), owner)
		if unit is UnitBase and unit not in units:
			units.append(unit)
	var target: Node2D = entities.get(int(packet.get("target", 0))) as Node2D
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		target = null
	var position_data: Array = packet.get("position", [0, 0])
	var position := Vector2(float(position_data[0]), float(position_data[1]))
	var tile: Vector2i = game_map.world_to_tile(position)
	if operation in ["move", "attack_move", "patrol", "rally", "place", "queue_move", "queue_rally"] and (tile.x < 0 or tile.y < 0 or tile.x >= MapData.MAP_WIDTH or tile.y >= MapData.MAP_HEIGHT):
		return "Outside map"
	var worker_before: Array[Dictionary] = []
	if operation in ["move", "gather", "build"]: worker_before = main._worker_order_undo.capture(owner, units)
	var affected_workers: Array = []
	match operation:
		"cancel_orders":
			if target is BuildingBase and target.player_owner == owner:
				target.cancel_rally_orders()
			for unit: UnitBase in units:
				unit.cancel_queued_orders()
			return ""
		"queue_move", "queue_dropoff", "queue_rally":
			if operation != "queue_dropoff" and (not packet.has("position") or (game_map.is_tile_visible_to_player(tile, owner) and not game_map.is_tile_walkable(tile))):
				return "Destination unavailable"
			if operation == "queue_rally":
				if not target is BuildingBase or target.player_owner != owner or not target.can_train():
					return "Select your production building"
				if not target.enqueue_rally_order({"kind": "move", "position": position}):
					return "Rally queue full"
				return ""
			if units.is_empty():
				return "Select your units"
			if operation == "queue_move" and units.size() > 1:
				return "" if main._queue_movement_orders(units, tile, owner) > 0 else "Order queue full or unavailable"
			if operation == "queue_dropoff" and (not target is BuildingBase or target.player_owner != owner or target.state != BuildingBase.State.ACTIVE or not target.is_in_group("dropoff_buildings")):
				return "Drop-off unavailable"
			var queued: bool = false
			for unit: UnitBase in units:
				if operation == "queue_dropoff" and not unit is Villager:
					continue
				var order: Dictionary = {"kind": "dropoff", "target_id": target.get_instance_id(), "position": target.global_position} if operation == "queue_dropoff" else {"kind": "move", "position": position}
				queued = unit.enqueue_order(order) or queued
			return "" if queued else "Order queue full or unavailable"
		"undo_workers":
			var undo_result: Dictionary = main._worker_order_undo.restore(owner, int(packet.get("undo_id", 0)), game_map)
			return str(undo_result.get("error", ""))
		"allocate":
			var result: Dictionary = main.get_node("StrategyController").try_allocate_worker(owner, str(packet.get("source", "")), str(packet.get("destination", "")))
			return str(result.get("error", ""))
		"trade":
			if not target is BuildingBase or target.player_owner != owner or target.building_type != BuildingData.BuildingType.TRADE_POST:
				return "Select your Trade Post"
			var accepted: bool = false
			for unit: UnitBase in units:
				if unit is Trader: accepted = unit.command_trade(target) or accepted
			if not accepted: return "Trade needs a clear route to a distant Town Center"
		"surrender":
			main._conclude_match(1 - owner, "Surrender")
		"move", "attack_move", "patrol":
			if units.is_empty():
				return "Select your units"
			var orders: Array[Dictionary] = PLANNER.plan(game_map, units, tile, main._player_units[owner], owner)
			for order: Dictionary in orders:
				var unit: UnitBase = order.unit
				affected_workers.append(unit)
				if operation == "attack_move":
					unit.command_attack_move_path(order.path) if order.path.size() > 1 else unit.command_attack_move(order.destination)
				elif operation == "patrol":
					unit.command_patrol(order.destination)
				else:
					unit.command_move_path(order.path) if order.path.size() > 1 else unit.command_move(order.destination)
			if operation == "attack_move":
				ATTACK_MARCH.attach_compact_orders(orders)
		"stop", "stance":
			affected_workers = units
			for unit: UnitBase in units:
				if operation == "stop":
					unit.command_stop()
				else:
					unit.stance = UnitBase.Stance.STAND_GROUND if unit.stance == UnitBase.Stance.AGGRESSIVE else UnitBase.Stance.AGGRESSIVE
		"attack":
			if target == null or target.player_owner == owner or not game_map.is_entity_visible_to_player(target, owner):
				return "Target no longer visible"
			affected_workers = units
			for unit: UnitBase in units:
				if target is UnitBase:
					unit.command_attack(target)
				elif target is BuildingBase:
					unit.command_attack_building(target)
		"gather":
			if target == null:
				target = game_map.get_resource_node_at(tile)
			if not game_map.is_resource_target_valid(target, "", owner) or not game_map.is_resource_target_visible_to_player(target, owner):
				return "Resource no longer available"
			var gathered_any: bool = false
			var occupied_farm_rejected: bool = false
			for unit: UnitBase in units:
				if unit is Villager:
					var gathered: bool = unit.command_gather(target)
					gathered_any = gathered or gathered_any
					if gathered: affected_workers.append(unit)
					if not gathered and target is BuildingBase and target.provides_food and not target.is_available_to_worker(unit):
						occupied_farm_rejected = true
			if occupied_farm_rejected and not gathered_any:
				return "Farm occupied. Choose an empty Farm or another food source."
		"build":
			if target == null or not target is BuildingBase or target.player_owner != owner:
				return "Select your foundation"
			for unit: UnitBase in units:
				if unit is Villager:
					unit.command_build(target)
					if unit.has_active_build_order() and unit.build_target == target: affected_workers.append(unit)
		"age":
			if not GameManager.try_advance_age(owner):
				return "Cannot advance age yet"
		"place":
			return _place_building(owner, int(packet.get("type", -1)), position, units)
		"train", "cancel", "repeat", "research", "rally", "delete":
			if target == null or not target is BuildingBase or _owned(int(packet.get("target", 0)), owner) == null:
				return "Select your building"
			var queue: ProductionQueue = target.get_production_queue()
			match operation:
				"train":
					var type: int = int(packet.get("type", -1))
					if not UnitData.UNITS.has(type) or GameManager.get_player_age(owner) < int(UnitData.UNITS[type].get("age_required", 1)) or queue == null or not queue.enqueue_unit(type):
						return "Cannot train · check resources and population"
				"cancel":
					if queue != null:
						var index: int = int(packet.get("index", -1))
						queue.cancel_all() if index == -1 else queue.cancel_unit(index)
				"repeat":
					return "Hold Train for a finite paid queue"
				"research":
					if not GameManager.try_research(owner, target, str(packet.get("research", ""))):
						return "Research unavailable"
				"rally":
					if target.state != BuildingBase.State.ACTIVE or target.trainable_units.is_empty():
						return "Rally unavailable"
					target.set_rally_point(position)
					var resource: Node2D = game_map.get_resource_node_at(tile)
					if resource != null and game_map.is_resource_target_visible_to_player(resource, owner):
						target.set_resource_rally(resource)
				"delete":
					if target.building_type == BuildingData.BuildingType.TOWN_CENTER:
						return "Cannot demolish Town Center"
					for resource: String in BuildingData.get_building_cost(target.building_type):
						ResourceManager.add_resource(owner, resource, int(BuildingData.get_building_cost(target.building_type)[resource] * 0.5))
					target.take_damage(target.max_hp + 1)
		_:
			return "Unknown order"
	main._worker_order_undo.remember(owner, worker_before, affected_workers)
	return ""

func _place_building(owner: int, type: int, position: Vector2, selected: Array[UnitBase]) -> String:
	var definition: Dictionary = BuildingData.get_building_stats(type)
	if definition.is_empty() or not main._building_scenes.has(type):
		return "Building unavailable"
	if GameManager.get_player_age(owner) < int(definition.get("age_required", 1)):
		return "Advance age first"
	if main._player_buildings[owner].size() >= 80:
		return "Building limit reached"
	if not main._building_placement.revalidate_confirmation(type, position, owner):
		return "Choose clear, visible ground"
	# Every selected villager that can reach the site builds it, as in solo.
	# With none selected or none able to reach, the first reachable worker goes.
	var footprint: Vector2i = definition.get("footprint", Vector2i.ONE)
	var builders: Array[Villager] = []
	for unit: Node in selected:
		if _can_build_at(unit, owner, position, footprint):
			builders.append(unit as Villager)
	if builders.is_empty():
		for unit: Node in main._player_units[owner]:
			if _can_build_at(unit, owner, position, footprint):
				builders.append(unit as Villager)
				break
	if builders.is_empty():
		return "No worker can reach this site"
	if not ResourceManager.try_spend(owner, BuildingData.get_building_cost(type)):
		return "Not enough resources"
	var building: BuildingBase = main._spawn_building(type, owner, game_map.world_to_tile(position))
	building.start_construction()
	for builder: Villager in builders:
		builder.command_build(building)
	main._worker_order_undo.supersede(owner, builders)
	return ""


func _can_build_at(unit: Node, owner: int, position: Vector2, footprint: Vector2i) -> bool:
	return is_instance_valid(unit) and unit is Villager and (unit as Villager).player_owner == owner \
		and (unit as Villager).hp > 0 and main._can_ai_builder_reach(unit, position, footprint)
