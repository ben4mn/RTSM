extends RefCounted
## One accepted, compact armed attack march.
## Units own this token; it owns only weak references. No paths or stats change.

const MAX_MEMBERS := 64
const MAX_ROUTE_POINTS := 512
const START_DIAMETER := 128.0
const RELEASE_DIAMETER := 192.0
const MIN_ROUTE_LENGTH := 96.0
const MAX_ROUTE_LENGTH_DIFFERENCE := 128.0
const ROUTE_SAMPLES := 8
const STALL_RELEASE_SECONDS := 0.5

var _members: Dictionary = {}
var _released: bool = false
var _scan_frame: int = -1
var _cached_speed: float = 0.0
var member_scans: int = 0


static func attach_orders(orders: Array[Dictionary]) -> RefCounted:
	var units: Array[UnitBase] = []
	var samples: Array[PackedVector2Array] = []
	var shortest: float = INF
	var longest: float = 0.0
	var slowest: float = INF
	var fastest: float = 0.0
	var owner: int = -1
	for order: Dictionary in orders:
		var candidate: Variant = order.get("unit")
		if not is_instance_valid(candidate) or not candidate is UnitBase:
			continue
		var unit := candidate as UnitBase
		if unit.unit_type in [UnitData.UnitType.VILLAGER, UnitData.UnitType.SCOUT] or unit.damage <= 0.0:
			continue
		if not _eligible(unit) or unit in units:
			return null
		if owner < 0:
			owner = unit.player_owner
		if unit.player_owner != owner:
			return null
		# Empty blind/unreachable orders are still accepted by the game, but do
		# not establish a common route on which this optional cap can operate.
		var route: PackedVector2Array = order.get("path", PackedVector2Array())
		if route.size() < 2 or route.size() > MAX_ROUTE_POINTS or unit.path != route:
			return null
		if unit.move_target.distance_to(route[route.size() - 1]) > 1.0:
			return null
		var points := PackedVector2Array([unit.global_position])
		for point: Vector2 in route:
			if not point.is_finite():
				return null
			if points[points.size() - 1].distance_squared_to(point) > 1.0:
				points.append(point)
		var length: float = _route_length(points)
		if length < MIN_ROUTE_LENGTH:
			return null
		shortest = minf(shortest, length)
		longest = maxf(longest, length)
		slowest = minf(slowest, unit.speed)
		fastest = maxf(fastest, unit.speed)
		units.append(unit)
		samples.append(_sample_route(points, length))
	if units.size() < 2 or units.size() > MAX_MEMBERS or fastest - slowest < 0.1:
		return null
	if longest - shortest > MAX_ROUTE_LENGTH_DIFFERENCE:
		return null
	# Compare only geometry already accepted by the existing route planner.
	# The corridor gate rejects split obstacle routes, divergent endpoints and
	# distant reinforcements; it never asks for additional terrain or vision.
	for a: int in units.size():
		for b: int in range(a + 1, units.size()):
			for index: int in ROUTE_SAMPLES + 1:
				if samples[a][index].distance_to(samples[b][index]) > START_DIAMETER:
					return null
			var first_a: Vector2 = samples[a][1] - samples[a][0]
			var first_b: Vector2 = samples[b][1] - samples[b][0]
			if first_a.normalized().dot(first_b.normalized()) < 0.7:
				return null
	var march: RefCounted = load("res://scripts/main/attack_march_cohesion.gd").new()
	for unit: UnitBase in units:
		unit.detach_attack_march()
		march.call("_attach", unit)
	return march


static func _eligible(unit: UnitBase) -> bool:
	return is_instance_valid(unit) and unit.is_inside_tree() and not unit.is_queued_for_deletion() and unit.hp > 0.0 and unit.current_state == UnitBase.State.MOVING and unit.attack_move and not bool(unit.get("_patrol_active")) and unit.damage > 0.0 and unit.speed > 0.0 and is_finite(unit.speed)


static func _route_length(points: PackedVector2Array) -> float:
	var length: float = 0.0
	for index: int in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	return length


static func _sample_route(points: PackedVector2Array, length: float) -> PackedVector2Array:
	var result := PackedVector2Array([points[0]])
	var segment: int = 1
	var passed: float = 0.0
	for index: int in range(1, ROUTE_SAMPLES + 1):
		var distance: float = length * float(index) / ROUTE_SAMPLES
		while segment < points.size() - 1 and passed + points[segment - 1].distance_to(points[segment]) < distance:
			passed += points[segment - 1].distance_to(points[segment])
			segment += 1
		var segment_length: float = points[segment - 1].distance_to(points[segment])
		result.append(points[segment - 1].lerp(points[segment], clampf((distance - passed) / maxf(segment_length, 0.001), 0.0, 1.0)))
	return result


func _attach(unit: UnitBase) -> void:
	_members[unit.get_instance_id()] = weakref(unit)
	unit.set_attack_march(self)


func detach(unit: UnitBase) -> void:
	_members.erase(unit.get_instance_id())
	# A retasked slow member must not cap the survivors for the rest of this
	# frame. Other callers share the scan until the frame or membership changes.
	_scan_frame = -1
	if _members.size() < 2:
		release()


func release() -> void:
	_released = true
	_members.clear()
	_cached_speed = 0.0


func is_active_member(unit: UnitBase) -> bool:
	# Presentation reads only local membership. Never scan/prune, navigate or
	# inspect opponents from a UI refresh or a snapshot serialization call.
	if _released or not _eligible(unit) or unit.get_attack_march() != self:
		return false
	var member: WeakRef = _members.get(unit.get_instance_id()) as WeakRef
	return member != null and member.get_ref() == unit


func get_speed_cap(unit: UnitBase) -> float:
	if _released or not _members.has(unit.get_instance_id()):
		return 0.0
	var frame: int = Engine.get_process_frames()
	if _scan_frame != frame:
		_scan_frame = frame
		_scan_members()
	return _cached_speed if not _released and _members.has(unit.get_instance_id()) else 0.0


func _scan_members() -> void:
	member_scans += 1
	_cached_speed = INF
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for id: int in _members.keys():
		var unit: UnitBase = (_members[id] as WeakRef).get_ref() as UnitBase
		if not is_instance_valid(unit) or not _eligible(unit) or unit.get_attack_march() != self or float(unit.get("_stuck_timer")) >= STALL_RELEASE_SECONDS or int(unit.get("_navigation_failed_repaths")) > 0 or int(unit.get("_navigation_stall_repaths")) > 0:
			_members.erase(id)
			continue
		_cached_speed = minf(_cached_speed, unit.speed)
		minimum = minimum.min(unit.global_position)
		maximum = maximum.max(unit.global_position)
	if _members.size() < 2 or minimum.distance_to(maximum) > RELEASE_DIAMETER:
		release()
