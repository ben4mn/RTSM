extends SceneTree
## Uses the real network replica removal path, then delayed UI payload helpers.
## Pausing selection maintenance deliberately retains the input's stale reference.
var failures: Array[String] = []
var checks: int = 0
var lookup_completed: bool = false
var selection_completed: bool = false
var target_completed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var session: Node = root.get_node("NetworkSession")
	root.get_node("AudioManager").set_all_enabled(false)
	session.set_process(false)
	session._client_packet({"op": "matched", "slot": 1, "seed": 101, "match": 41})
	for frame: int in 600:
		await process_frame
		if is_instance_valid(session.adapter):
			break
	_check(is_instance_valid(session.adapter), "actual network match attaches")
	if not is_instance_valid(session.adapter):
		quit(1)
		return
	var adapter: Node = session.adapter
	adapter.set_process(false)
	var actor: Dictionary = {"id": 1, "kind": "unit", "type": 1, "owner": 1, "x": 0.0, "y": 1152.0, "state": 0, "stance": 0, "hp": 100.0, "max_hp": 100.0}
	adapter.apply_snapshot({"actors": [actor]})
	var unit: Variant = adapter.entities[1]
	var selected: Array = [unit]
	adapter.game_map.selection_mgr.set_process(false)
	adapter.game_map.selection_mgr.select_single(unit)
	_check(session.selection_ids(selected) == [1], "live owned replica supplies its server id")
	_check(session.target_payload(unit).get("target", 0) == 1, "live replica supplies target position and id")
	adapter.apply_snapshot({"actors": []})
	_check(adapter.entities.is_empty() and adapter._interpolation.is_empty() and adapter._hit_flashes.is_empty(), "snapshot removal clears replica registries")
	_check(adapter.main._player_units[0].is_empty(), "snapshot removal clears local owner roster")
	await process_frame
	_check(not is_instance_valid(unit), "replica is actually freed before delayed input")
	_probe_entity(session, unit)
	_probe_selection(session, selected)
	_probe_target(session, unit)
	_check(lookup_completed, "entity helper reaches its lifetime guard")
	_check(selection_completed, "selection helper reaches its lifetime guard")
	_check(target_completed, "target helper reaches its lifetime guard")
	adapter.game_map.selection_mgr.call("_prune_stale_selection")
	_check(adapter.game_map.selection_mgr.selected.is_empty(), "normal maintenance subsequently clears selection")
	adapter.apply_snapshot({"actors": [actor]})
	_check(is_instance_valid(adapter.entities[1]), "later visible replica reconstructs cleanly")
	_check(adapter.entities[1].process_mode == Node.PROCESS_MODE_DISABLED, "reconstructed replica stays inert")
	for failure: String in failures:
		push_error("[FAIL] network_reference_lifetime: " + failure)
	print("NETWORK_REFERENCE_LIFETIME checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func _probe_entity(session: Node, entry: Variant) -> void:
	_check(session.entity_id(entry) == 0, "freed entity has no command id")
	lookup_completed = true

func _probe_selection(session: Node, selected: Array) -> void:
	_check(session.selection_ids(selected).is_empty(), "freed selection sends no ids")
	selection_completed = true

func _probe_target(session: Node, entry: Variant) -> void:
	_check(session.target_payload(entry).is_empty(), "freed target sends no command position")
	target_completed = true

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
