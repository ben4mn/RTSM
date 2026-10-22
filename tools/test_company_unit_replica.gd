extends SceneTree
## Real snapshot adapter and both local-slot mappings. No live socket, simulated
## production or damage; replicas stay inert while animation/feedback is rendered.

var failures: Array[String] = []
const FILES: Array[String] = ["worker", "warrior", "archer"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("AudioManager").set_all_enabled(false)
	var session: Node = root.get_node("NetworkSession")
	var manager: Node = root.get_node("GameManager")
	session.set_process(false)
	session._client_packet({"op": "matched", "slot": 1, "seed": 101, "match": 41})
	for frame: int in 600:
		await process_frame
		if is_instance_valid(session.adapter):
			break
	_check(is_instance_valid(session.adapter), "Client match attaches through actual network entry")
	if not is_instance_valid(session.adapter):
		quit(1)
		return
	var adapter: Node = session.adapter
	adapter.set_process(false)
	for slot: int in [1, 0]:
		session.player_slot = slot
		var actors: Array[Dictionary] = []
		for role: int in 3:
			for owner: int in 2:
				actors.append({"id": actors.size() + 1, "kind": "unit", "type": role, "owner": owner,
					"x": 300.0 + actors.size() * 85.0, "y": 1152.0, "state": 0, "stance": 0,
					"hp": 100.0, "max_hp": 100.0})
		for rebuild: int in 2:
			adapter.apply_snapshot({"actors": actors})
			for actor: Dictionary in actors:
				var unit: Node = adapter.entities[int(actor.id)]
				var local_owner: int = 0 if int(actor.owner) == slot else 1
				var expected: String = "res://assets/units/%s%s.svg" % [FILES[int(actor.type)], "_enemy" if local_owner == 1 else ""]
				_check(unit.player_owner == local_owner, "Slot%d maps server owner before sprite creation" % slot)
				_check(unit._sprite.texture.resource_path == expected, "Rebuilt replica uses correct role and local cloth")
				_check(unit._sprite.modulate == Color.WHITE, "Neutral skin, hair and equipment remain untinted")
				_check(unit.process_mode == Node.PROCESS_MODE_DISABLED, "Presentation does not enable replica simulation")
				unit.visible = true
				unit.is_selected = local_owner == 0
				actor.x = float(actor.x) - 10.0
				actor.state = 2  # UnitBase.State.ATTACKING; defer class loading until autoloads exist.
				actor.animation = [0.35, 0.5, -1.0, 0.0, true]
				actor.hp = 75.0
			manager.reduced_flashes = false
			adapter.apply_snapshot({"actors": actors})
			adapter._process(0.1)
			for actor: Dictionary in actors:
				var unit: Node = adapter.entities[int(actor.id)]
				_check(unit._sprite.flip_h, "Snapshot plus interpolated movement preserves left-facing art")
				_check(unit._attack_animation_remaining > 0.0 and unit._attack_animation_remaining < 0.35, "Visual animation advances on inert replica")
				_check(unit._sprite.position.length() > 0.0, "Attack snapshot produces actual sprite recoil/lunge")
				_check(is_equal_approx(unit.hp, 75.0), "Animation does not simulate extra combat damage")
				_check(unit.process_mode == Node.PROCESS_MODE_DISABLED, "Animated replica remains inert")
				_check(unit._health_feedback_remaining > 1.8, "Damaged replica retains health feedback")
			adapter.apply_snapshot({"actors": []})
			await process_frame
			for actor: Dictionary in actors:
				actor.state = 0
				actor.hp = 100.0
				actor.erase("animation")
	for failure: String in failures:
		push_error("[FAIL] company_unit_replica: " + failure)
	if failures.is_empty():
		print("[PASS] company_unit_replica: three roles, both slots/owners, reconstruction, neutral materials, attack interpolation and recent-hit feedback; replicas remain inert")
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
