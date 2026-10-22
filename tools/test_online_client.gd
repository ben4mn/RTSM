extends SceneTree
## Independent client witness. Run two processes against AOEM_MATCH_URL.
var session: Node
var elapsed: float = 0.0
var saw_actors: bool = false
var order_sent: bool = false
var saw_move: bool = false
var initial_position := Vector2.ZERO
var unit_id: int = 0
var ordered_destination := Vector2.ZERO
var train_sent: bool = false
var own_count: int = 0
var initial_count: int = 0
var completed: bool = false
var house_sent: bool = false
var house_finished: bool = false
var gathered: bool = false
var builder_id: int = 0
var end_sent: bool = false
var map_verified: bool = false

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	root.get_node("GameManager").selected_map_seed = 454545
	root.get_node("GameManager").selected_map_archetype = MapData.MapArchetype.WOODLAND_FLANKS
	session = root.get_node("NetworkSession")
	session.snapshot_received.connect(_snapshot)
	session.match_ended.connect(_ended)
	session.status_changed.connect(_status)
	session.find_match()

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 90.0:
		push_error("ONLINE_CLIENT_TIMEOUT slot=%d moved=%s trained=%s" % [session.player_slot, saw_move, own_count > initial_count])
		quit(1)
	return false

func _status(state: String, message: String) -> void:
	print("CLIENT_STATUS %s %s" % [state, message])
	if state == "error":
		quit(1)

func _snapshot(data: Dictionary) -> void:
	if session.state != "playing":
		return
	if not map_verified:
		var game_map: Node = current_scene.get_node("GameMap")
		var expected := MapGenerator.new(session.match_seed, session.match_map_archetype)
		if game_map.map_archetype != session.match_map_archetype or game_map.map_generator.grid != expected.generate():
			push_error("ONLINE_CLIENT_MAP_MISMATCH")
			quit(1)
			return
		map_verified = true
		print("ONLINE_CLIENT_MAP_VERIFIED slot=%d seed=%d archetype=%d" % [session.player_slot, session.match_seed, session.match_map_archetype])
	var units: Array = []
	var town_center: int = 0
	for actor: Dictionary in data.get("actors", []):
		if int(actor.owner) != session.player_slot:
			continue
		if actor.kind == "unit":
			units.append(actor)
		elif int(actor.type) == 0:
			town_center = int(actor.id)
		elif int(actor.type) == 1 and int(actor.state) == 2:
			house_finished = true
	own_count = units.size()
	if not order_sent and units.size() > 0:
		initial_count = own_count
		builder_id = int(units[1].id) if units.size() > 1 else 0
		var unit: Dictionary = units[0]
		unit_id = int(unit.id)
		initial_position = Vector2(float(unit.x), float(unit.y))
		var map: Node = current_scene.get_node("GameMap")
		var start: Vector2i = map.world_to_tile(initial_position)
		var destination: Vector2 = initial_position
		for dx: int in range(-5, 6):
			var candidate: Vector2i = start + Vector2i(dx, 3)
			if map.is_tile_walkable(candidate):
				destination = map.tile_to_world(candidate)
				break
		ordered_destination = destination
		session.send_command("move", {"ids": [unit_id], "position": [destination.x, destination.y]})
		order_sent = true
		print("CLIENT_MOVE_SENT slot=%d id=%d" % [session.player_slot, unit_id])
	if not train_sent and town_center > 0:
		session.send_command("train", {"target": town_center, "type": 0})
		train_sent = true
	for unit: Dictionary in units:
		if int(unit.id) == unit_id and Vector2(float(unit.x), float(unit.y)).distance_to(ordered_destination) < 15.0:
			saw_move = true
	if not house_sent and saw_move and builder_id > 0:
		var map: Node = current_scene.get_node("GameMap")
		var center: Vector2i = map.map_generator.spawn_positions[session.player_slot]
		for radius: int in range(4, 9):
			for dx: int in range(-radius, radius + 1):
				for dy: int in [-radius, radius]:
					var position: Vector2 = map.tile_to_world(center + Vector2i(dx, dy))
					if not house_sent and current_scene._building_placement.revalidate_confirmation(1, position, 0):
						session.send_command("place", {"type": 1, "ids": [builder_id], "position": [position.x, position.y]})
						house_sent = true
	gathered = int(data.get("stats", {}).get("resources_gathered", 0)) > 0
	if saw_move and own_count > initial_count and house_finished and gathered and not completed:

		completed = true
		print("ONLINE_CLIENT_VERIFIED slot=%d actors=%d destination=true production=true construction=true deposits=true" % [session.player_slot, own_count])
	if completed and session.player_slot == 1 and float(data.time) > 60.0 and not end_sent:
		end_sent = true
		session.send_command("surrender")

func _ended(winner: int, reason: String) -> void:
	print("CLIENT_FINAL_CHECKS moved=%s house=%s deposits=%s trained=%s" % [saw_move, house_finished, gathered, own_count > initial_count])
	print("ONLINE_CLIENT_RESULT slot=%d winner=%d reason=%s verified=%s" % [session.player_slot, winner, reason, completed])
	var manager: Node = root.get_node("GameManager")
	session.leave_match()
	var preferences_preserved: bool = manager.selected_map_seed == 454545 and manager.selected_map_archetype == MapData.MapArchetype.WOODLAND_FLANKS
	print("ONLINE_SOLO_MAP_PREFERENCES_PRESERVED ", preferences_preserved)
	quit(0 if completed and map_verified and preferences_preserved and winner == 0 else 1)
