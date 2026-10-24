extends SceneTree
## Presentation-only snapshot fixture; does not claim a live network connection.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session: Node = root.get_node("NetworkSession")
	var manager: Node = root.get_node("GameManager")
	root.get_node("AudioManager").set_all_enabled(false)
	session.set_process(false)
	session._client_packet({"op": "matched", "protocol": session.PROTOCOL, "slot": 0, "seed": 101, "match": 41, "civilizations": [0, 0]})
	for frame: int in range(600):
		await process_frame
		if is_instance_valid(session.adapter):
			break
	_check(is_instance_valid(session.adapter), "Client scene attached")
	if not is_instance_valid(session.adapter):
		quit(1)
		return
	var adapter: Node = session.adapter
	adapter.set_process(false)
	var actor: Dictionary = {"id": 1, "kind": "unit", "type": 1, "owner": 0, "x": 0.0, "y": 1152.0, "state": 0, "stance": 0, "hp": 100.0, "max_hp": 100.0}
	adapter.apply_snapshot({"actors": [actor]})
	var unit: Node = adapter.entities[1]
	unit.visible = true
	_check(unit.process_mode == Node.PROCESS_MODE_DISABLED, "Replica simulation stays disabled")
	_check(is_zero_approx(unit._health_feedback_remaining), "Initial snapshot does not fake a hit")
	manager.reduced_flashes = false
	actor.hp = 90.0
	adapter.apply_snapshot({"actors": [actor]})
	_check(is_equal_approx(unit._health_feedback_remaining, 2.0), "HP decrease shows recent-hit health feedback")
	_check(unit.modulate.is_equal_approx(Color(1.16, 1.12, 1.04)), "Hit uses restrained warm highlight")
	adapter._process(0.2)
	_check(unit.modulate.is_equal_approx(Color.WHITE), "Highlight expires through adapter visual update")
	_check(unit._health_feedback_remaining > 1.7 and unit._health_feedback_remaining < 1.9, "Health timer advances on inert replica")
	adapter._process(2.0)
	_check(is_zero_approx(unit._health_feedback_remaining), "Health feedback expires")
	_check(is_equal_approx(unit.hp, 90.0), "Visual updates never apply damage")
	manager.reduced_flashes = true
	actor.hp = 80.0
	adapter.apply_snapshot({"actors": [actor]})
	_check(unit.modulate.is_equal_approx(Color.WHITE), "Reduced flashes suppresses highlight")
	_check(is_equal_approx(unit._health_feedback_remaining, 2.0), "Reduced flashes retains readable health feedback")
	# Building replicas stay inert too: snapshots own their HP and construction,
	# while a bounded adapter pulse must expire without changing either state.
	# Load after autoload registration: this fixture also runs via --script.
	var building_script: GDScript = load("res://scripts/buildings/building_base.gd")
	manager.reduced_flashes = false
	var building_actor: Dictionary = {"id": 2, "kind": "building", "type": BuildingData.BuildingType.HOUSE, "owner": 0, "x": 256.0, "y": 1152.0, "state": building_script.State.CONSTRUCTING, "progress": 0.35, "hp": 500.0, "max_hp": 500.0}
	adapter.apply_snapshot({"actors": [actor, building_actor]})
	var building: Node = adapter.entities[2]
	building.visible = true
	_check(building.process_mode == Node.PROCESS_MODE_DISABLED, "Building simulation stays disabled")
	_check(building.modulate.is_equal_approx(Color.WHITE), "Initial building snapshot does not fake a hit")
	var construction_tint: Color = building._sprite.modulate
	building_actor.hp = 450.0
	adapter.apply_snapshot({"actors": [actor, building_actor]})
	_check(building.modulate.is_equal_approx(building_script.DAMAGE_FLASH_COLOR), "Building hit matches native material pulse")
	adapter._process(0.08)
	building_actor.hp = 400.0
	adapter.apply_snapshot({"actors": [actor, building_actor]})
	_check(building.modulate.is_equal_approx(building_script.DAMAGE_FLASH_COLOR), "Repeated hits do not accumulate a tint")
	adapter._process(0.2)
	_check(building.modulate.is_equal_approx(Color.WHITE), "Inert building pulse expires through adapter")
	_check(building._sprite.modulate.is_equal_approx(construction_tint), "Pulse does not restore or overwrite construction appearance")
	_check(building.state == building_script.State.CONSTRUCTING and is_equal_approx(building.build_progress, 0.35) and building.hp == 400, "Visual clock changes no building state, progress or HP")
	manager.reduced_flashes = true
	building_actor.hp = 350.0
	adapter.apply_snapshot({"actors": [actor, building_actor]})
	_check(building.modulate.is_equal_approx(Color.WHITE) and building.hp == 350, "Reduced flashes retains authoritative building HP without a pulse")
	manager.reduced_flashes = false
	building.visible = false
	building_actor.hp = 300.0
	adapter.apply_snapshot({"actors": [actor, building_actor]})
	_check(building.modulate.is_equal_approx(Color.WHITE), "Hidden building receives no visible hit feedback")
	for failure: String in failures:
		push_error("[FAIL] network_visual_feedback: " + failure)
	if failures.is_empty():
		print("[PASS] network_visual_feedback: inert unit/building HP feedback, visual expiry, construction preservation, repeated hits, hidden actors and reduced flashes")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
