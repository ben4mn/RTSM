extends RefCounted
## One short-lived, authority-owned worker intent record per player. Restoring
## orders never rewinds cargo, resources, construction, health, or position.

const LIFETIME_MS: int = 10000
const REVISION_META: StringName = &"player_worker_order_revision"
var _records: Dictionary = {}
var _next_id: int = 1
var _results: Dictionary = {}
const BUILD_CONTINUATION_KEYS: Array[String] = [
	"_saved_gather_type", "_saved_carried_resource_type", "_saved_gather_last_known_position",
	"_saved_has_gather_last_known_position", "_saved_gather_last_known_is_building", "_saved_gather_last_known_instance_id",
]

func capture(owner: int, units: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for node: Variant in units:
		if not _worker(node, owner): continue
		var worker := node as Villager
		var intent: Dictionary = {}
		if worker.has_active_build_order():
			intent = {"kind": "build", "target": weakref(worker.build_target), "continuation": {}}
			for key: String in BUILD_CONTINUATION_KEYS: intent.continuation[key] = worker.get(key)
			var saved_target: Node2D = worker.get("_saved_gather_target") as Node2D
			intent.continuation["target"] = weakref(saved_target) if is_instance_valid(saved_target) else null
		elif worker.has_active_gather_order() or (worker.is_auto_recovering() and worker.get("_recovery_work_state") == UnitBase.State.GATHERING):
			if is_instance_valid(worker.gather_target):
				intent = {"kind": "gather", "target": weakref(worker.gather_target)}
			elif bool(worker.get("_has_gather_last_known_position")):
				intent = {"kind": "observed_gather", "resource": worker.carried_resource_type,
					"position": worker.get("_gather_last_known_position"), "instance_id": worker.get("_gather_last_known_instance_id"),
					"building": worker.get("_gather_last_known_is_building")}
			else:
				intent = {"kind": "unavailable"}
		elif worker.is_returning_resources():
			intent = {"kind": "return"}
		elif worker.current_state == UnitBase.State.MOVING and not worker.attack_move and not bool(worker.get("_patrol_active")):
			intent = {"kind": "move", "destination": worker.move_target}
		elif worker.current_state == UnitBase.State.IDLE:
			intent = {"kind": "idle"}
		if not intent.is_empty():
			intent["worker"] = weakref(worker)
			entries.append(intent)
	return entries

func supersede(owner: int, units: Array) -> void:
	var changed: bool = false
	for node: Variant in units:
		if not _worker(node, owner): continue
		node.set_meta(REVISION_META, int(node.get_meta(REVISION_META, 0)) + 1)
		changed = true
	if changed: _records.erase(owner)

func remember(owner: int, before: Array[Dictionary], accepted: Array) -> void:
	# Only explicit player adapters call this. Automatic deposits, gathering,
	# construction progress and raid recovery do not replace a player's Undo.
	supersede(owner, accepted)
	var entries: Array[Dictionary] = []
	for entry: Dictionary in before:
		var worker: Node2D = entry.worker.get_ref() as Node2D
		if _worker(worker, owner) and worker in accepted:
			entry["revision"] = int(worker.get_meta(REVISION_META, 0))
			entries.append(entry)
	if entries.size() < 2: return
	_records[owner] = {"id": _next_id, "until": Time.get_ticks_msec() + LIFETIME_MS, "entries": entries}
	_next_id += 1

func status(owner: int) -> Dictionary:
	var record: Dictionary = _records.get(owner, {})
	if record.is_empty(): return {}
	var remaining: int = int(record.until) - Time.get_ticks_msec()
	if remaining <= 0:
		_records.erase(owner)
		return {}
	var living: int = 0
	for entry: Dictionary in record.entries:
		var worker: Node2D = entry.worker.get_ref() as Node2D
		if not _worker(worker, owner): continue
		if int(worker.get_meta(REVISION_META, 0)) != int(entry.revision):
			_records.erase(owner)
			return {}
		living += 1
	if living == 0:
		_records.erase(owner)
		return {}
	return {"id": int(record.id), "count": living, "remaining_ms": remaining}

func restore(owner: int, record_id: int, map: Node2D) -> Dictionary:
	var available: Dictionary = status(owner)
	if available.is_empty() or int(available.id) != record_id:
		return {"error": "Worker Undo expired or was replaced by a newer order", "restored": 0}
	var entries: Array = _records[owner].entries
	_records.erase(owner) # One-shot even when a former target is unavailable.
	var restored: int = 0
	var stopped: int = 0
	for entry: Dictionary in entries:
		var worker: Villager = entry.worker.get_ref() as Villager
		if not _worker(worker, owner): continue
		var accepted: bool = false
		match str(entry.kind):
			"gather":
				var target: Node2D = entry.target.get_ref() as Node2D
				# Visibility is checked before target state/stock. Hidden targets
				# are never queried or reactivated by an old history entry.
				if is_instance_valid(target) and map.is_resource_target_visible_to_player(target, owner) and map.is_resource_target_valid(target, "", owner):
					accepted = worker.command_gather(target)
			"observed_gather":
				# Reissue only the owner's saved observation. The ordinary API
				# approaches that position without querying a hidden live target.
				accepted = worker.command_gather_last_observed(entry.resource, entry.position, int(entry.instance_id), bool(entry.building))
			"return":
				accepted = worker.command_return_resources()
			"build":
				var target: BuildingBase = entry.target.get_ref() as BuildingBase
				if is_instance_valid(target) and not target.is_queued_for_deletion() and target.player_owner == owner and target.state == BuildingBase.State.CONSTRUCTING:
					worker.command_build(target)
					accepted = worker.has_active_build_order()
					if accepted:
						# command_build derives a continuation from the current job;
						# replace that with the original builder's saved intent only.
						for key: String in BUILD_CONTINUATION_KEYS: worker.set(key, entry.continuation[key])
						var saved: WeakRef = entry.continuation.target
						worker.set("_saved_gather_target", saved.get_ref() if saved != null else null)
						if int(entry.continuation._saved_gather_type) == Villager.GatherType.NONE:
							worker.set("_saved_carried_resource_type", worker.carried_resource_type if worker.carried_amount > 0 else "")
			"move":
				worker.command_move(entry.destination)
				accepted = true
			"idle":
				worker.command_stop()
				accepted = true
		if accepted:
			restored += 1
		else:
			worker.command_stop()
			stopped += 1
	_results[owner] = {"id": record_id, "restored": restored, "stopped": stopped}
	return {"error": "", "restored": restored, "stopped": stopped}

func result(owner: int) -> Dictionary:
	return _results.get(owner, {}).duplicate()

func _worker(node: Variant, owner: int) -> bool:
	return is_instance_valid(node) and node is Villager and node.player_owner == owner and not node.is_queued_for_deletion() and node.current_state != UnitBase.State.DEAD
