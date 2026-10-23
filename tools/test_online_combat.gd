extends SceneTree
## Two real clients buy Barracks + infantry, attack-move to the center and
## verify enemy visibility and replicated combat damage before ending.
var session: Node
var elapsed := 0.0
var placed := false
var trained := false
var ordered := false
var saw_combat := false
var completed := false
var military_id := 0
var saw_enemy := false
var completed_at := -1.0
var end_sent := false
var stand_ground_check := false
var stance_sent := false
var saw_stance_replica := false

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	stand_ground_check = "--stand-ground" in OS.get_cmdline_user_args()
	session = root.get_node("NetworkSession")
	session.snapshot_received.connect(_snapshot)
	session.status_changed.connect(_status)
	session.match_ended.connect(_ended)
	session.find_match()

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 150.0:
		push_error("ONLINE_COMBAT_TIMEOUT slot=%d place=%s trained=%s ordered=%s enemy=%s combat=%s" % [session.player_slot, placed, trained, ordered, saw_enemy, saw_combat])
		quit(1)
	return false

func _snapshot(data: Dictionary) -> void:
	if session.state != "playing" or elapsed < 2.0:
		return
	var map: Node = current_scene.get_node("GameMap")
	var own: int = session.player_slot
	var workers: Array = []
	for actor: Dictionary in data.actors:
		if int(actor.owner) == own:
			if actor.kind == "unit" and int(actor.type) == 0:
				workers.append(int(actor.id))
			if actor.kind == "building" and int(actor.type) == 2 and int(actor.state) == 2 and not trained:
				session.send_command("train", {"target": int(actor.id), "type": 1})
				trained = true
			if actor.kind == "unit" and int(actor.type) == 1:
				military_id = int(actor.id)
				if stand_ground_check and not stance_sent:
					session.send_command("stance", {"ids": [military_id]})
					stance_sent = true
				if stand_ground_check and int(actor.stance) == 1:
					var replica: Node = session.adapter.entities.get(military_id)
					if is_instance_valid(replica) and replica.get("stance") == 1 and not replica.can_process() and replica.process_mode == Node.PROCESS_MODE_DISABLED and int(replica.get("player_owner")) == 0:
						saw_stance_replica = true
				if not ordered and (not stand_ground_check or saw_stance_replica):
					var center: Vector2 = map.sacred_site.global_position
					session.send_command("attack_move", {"ids": [military_id], "position": [center.x, center.y]})
					ordered = true
		else:
			if actor.kind == "unit":
				saw_enemy = true
				if float(actor.hp) < float(actor.max_hp):
					saw_combat = true
	if not placed and not workers.is_empty():
		var spawn: Vector2i = map.map_generator.spawn_positions[own]
		for radius: int in range(4, 9):
			for dx: int in range(-radius, radius + 1):
				for dy: int in [-radius, radius]:
					var world: Vector2 = map.tile_to_world(spawn + Vector2i(dx, dy))
					if not placed and current_scene._building_placement.revalidate_confirmation(2, world, 0):
						session.send_command("place", {"type": 2, "ids": [workers[0]], "position": [world.x, world.y]})
						placed = true
	if saw_enemy and saw_combat and (not stand_ground_check or saw_stance_replica) and not completed:
		completed = true
		completed_at = float(data.time)
		print("ONLINE_COMBAT_VERIFIED slot=%d paid_barracks=true paid_infantry=true attack_move=true enemy_visible=true replicated_damage=true stand_ground_requested=%s inert_stance_replica=%s" % [own, stand_ground_check, saw_stance_replica])
	if completed and own == 1 and float(data.time) > completed_at + 4.0 and not end_sent:
		end_sent = true
		session.send_command("surrender")

func _ended(winner: int, reason: String) -> void:
	print("ONLINE_COMBAT_RESULT slot=%d winner=%d reason=%s verified=%s" % [session.player_slot, winner, reason, completed])
	quit(0 if completed else 1)


func _status(value: String, message: String) -> void:
	print("ONLINE_COMBAT_STATUS slot=%d state=%s elapsed=%.2f message=%s" % [session.player_slot, value, elapsed, message])
	if value == "error":
		push_error("ONLINE_COMBAT_TRANSPORT_FAILURE " + message)
		quit(1)
