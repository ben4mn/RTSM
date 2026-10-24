extends RefCounted
## One fresh AI wave waits for normal lazy navigation to accept actual paths.
## No new planner calls, retained actor references, or refresh regrouping.

const MARCH := preload("res://scripts/main/attack_march_cohesion.gd")
const ACCEPT_WINDOW_SECONDS := 1.0
var _members: Dictionary = {}
var _routes: Dictionary = {}
var _generations: Dictionary = {}
var _target := Vector2.ZERO
var _owner: int = -1
var _started: float = 0.0
var _closed: bool = false


static func watch_wave(units: Array, target: Vector2, owner: int) -> RefCounted:
	var participants: Array[UnitBase] = []
	var slowest: float = INF
	var fastest: float = 0.0
	for entry: Variant in units:
		if not is_instance_valid(entry) or not entry is UnitBase:
			continue
		var unit := entry as UnitBase
		if unit.unit_type in [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT] or unit.damage <= 0.0:
			continue
		if not MARCH._eligible(unit) or unit.player_owner != owner or unit.move_target.distance_to(target) > 1.0 or not unit.path.is_empty() or unit in participants:
			return null
		for other: UnitBase in participants:
			if other.global_position.distance_to(unit.global_position) > MARCH.START_DIAMETER:
				return null
		participants.append(unit)
		slowest = minf(slowest, unit.speed)
		fastest = maxf(fastest, unit.speed)
	if participants.size() < 2 or participants.size() > MARCH.MAX_MEMBERS or fastest - slowest < 0.1:
		return null
	var pending: RefCounted = load("res://scripts/main/pending_attack_march.gd").new()
	pending.call("_start", participants, target, owner)
	return pending


func _start(units: Array[UnitBase], target: Vector2, owner: int) -> void:
	_target = target
	_owner = owner
	_started = GameManager.game_time
	for unit: UnitBase in units:
		_members[unit.get_instance_id()] = weakref(unit)
		_generations[unit.get_instance_id()] = unit.get_command_generation()
		unit.set_pending_attack_march(self)


func accept_route(unit: UnitBase) -> void:
	if _closed:
		return
	var id: int = unit.get_instance_id()
	if not _members.has(id) or _routes.has(id) or GameManager.game_time - _started > ACCEPT_WINDOW_SECONDS:
		cancel()
		return
	if not _still_original(unit) or unit.path.size() < 2:
		cancel()
		return
	_routes[id] = unit.path.duplicate()
	var orders: Array[Dictionary] = []
	for member_id: int in _members:
		var member: UnitBase = (_members[member_id] as WeakRef).get_ref() as UnitBase
		if not is_instance_valid(member) or not _still_original(member):
			cancel()
			return
		if _routes.has(member_id):
			# The accepted path must still be the path this actor will follow.
			if member.path != _routes[member_id]:
				cancel()
				return
			orders.append({"unit": member, "path": _routes[member_id], "destination": member.move_target})
	if orders.size() != _members.size():
		return
	# Clear pending links before admission: attaching the active token invokes
	# normal command-lifecycle cleanup, which must not recursively cancel us.
	cancel()
	MARCH.attach_orders(orders)


func _still_original(unit: UnitBase) -> bool:
	return MARCH._eligible(unit) and unit.player_owner == _owner and unit.get_pending_attack_march() == self and unit.get_command_generation() == int(_generations.get(unit.get_instance_id(), -1)) and unit.move_target.distance_to(_target) <= 1.0


func expire_if_needed() -> void:
	if GameManager.game_time - _started > ACCEPT_WINDOW_SECONDS or GameManager.game_time < _started:
		cancel()


func cancel() -> void:
	if _closed:
		return
	_closed = true
	for reference: WeakRef in _members.values():
		var unit: UnitBase = reference.get_ref() as UnitBase
		if is_instance_valid(unit):
			unit.clear_pending_attack_march(self)
	_members.clear()
	_routes.clear()
	_generations.clear()
