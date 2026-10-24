extends SceneTree
## Presentation-only real snapshot adapter fixture; no live socket claim.
## Slot one remapping ensures server ownership does not choose the wrong art.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("AudioManager").set_all_enabled(false)
	var session: Node = root.get_node("NetworkSession")
	session.set_process(false)
	session._client_packet({"op": "matched", "slot": 1, "seed": 101, "match": 41})
	for frame: int in 600:
		await process_frame
		if is_instance_valid(session.adapter):
			break
	_check(is_instance_valid(session.adapter), "Client match attached")
	if not is_instance_valid(session.adapter):
		quit(1)
		return
	var building_script: GDScript = load("res://scripts/buildings/building_base.gd")
	var adapter: Node = session.adapter
	adapter.set_process(false)
	var actors: Array[Dictionary] = []
	for type: int in building_script.BUILDING_SPRITES:
		for server_owner: int in [0, 1]:
			actors.append({"id": actors.size() + 1, "kind": "building", "type": type, "owner": server_owner, "x": float(actors.size() * 150), "y": 1152.0, "state": 2, "progress": 1.0, "hp": 500.0, "max_hp": 500.0})
	for rebuild: int in 2:
		adapter.apply_snapshot({"actors": actors})
		for actor: Dictionary in actors:
			if not adapter.entities.has(int(actor.id)):
				_check(false, "Snapshot failed to create building")
				continue
			var building: Node = adapter.entities[int(actor.id)]
			var sprite: Sprite2D = building.get_node("BuildingSprite")
			var local_owner: int = 0 if int(actor.owner) == 1 else 1
			_check(building.player_owner == local_owner, "Slot one remaps owner before sprite setup")
			_check(building.building_type == int(actor.type), "Replica type set before sprite setup")
			_check(sprite.texture.resource_path == building_script.get_sprite_texture_path(int(actor.type), local_owner), "Replica texture matches type/local owner after rebuild %d" % rebuild)
			_check(building.process_mode == Node.PROCESS_MODE_DISABLED, "Art does not enable replica simulation")
			_check(sprite.modulate == Color.WHITE, "All ten Company families retain neutral materials, including Farm and Tower")
			_check(sprite.material == null and building.get_node_or_null("ConstructionFrame") == null, "Active inert replica has no temporary construction rendering")
			actor.state = 1
			actor.progress = 0.4
		adapter.apply_snapshot({"actors": actors})
		for actor: Dictionary in actors:
			if not adapter.entities.has(int(actor.id)):
				continue
			var sprite: Sprite2D = adapter.entities[int(actor.id)].get_node("BuildingSprite")
			_check(sprite.modulate.a < 1.0 and sprite.modulate.a > 0.4, "Snapshot construction appearance retains fade")
			var material: ShaderMaterial = sprite.material as ShaderMaterial
			_check(material != null and is_equal_approx(float(material.get_shader_parameter("construction_progress")), 0.4), "Disabled replica receives the latest construction reveal")
			_check(adapter.entities[int(actor.id)].get_node_or_null("ConstructionFrame") != null, "Disabled replica displays its construction frame")
			actor.state = 2
			actor.progress = 1.0
		adapter.apply_snapshot({"actors": actors})
		await process_frame
		for actor: Dictionary in actors:
			if adapter.entities.has(int(actor.id)):
				var building: Node = adapter.entities[int(actor.id)]
				_check(building.get_node("BuildingSprite").material == null and building.get_node_or_null("ConstructionFrame") == null, "Completion removes frame/material on disabled replicas")
		adapter.apply_snapshot({"actors": []})
		await process_frame
	for failure: String in failures:
		push_error("[FAIL] company_building_replica: " + failure)
	if failures.is_empty():
		print("[PASS] company_building_replica: actual snapshot adapter, slot-one local owner remap, ten Company families with neutral materials, reconstruction, construction reveal/frame and completion cleanup; replicas stay inert")
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
