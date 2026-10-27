extends RefCounted
## A geometric planning hint, never a reachability or travel-time promise.
## Inputs contain only the owner's known Town Centers; no world/path queries.
const MIN_ROUTE_DISTANCE: float = 500.0
const GOLD_PER_WORLD_UNIT: float = 0.04
const MIN_TRIP_GOLD: int = 20
const MAX_TRIP_GOLD: int = 60

static func income_for_distance(distance: float) -> int:
	# The route owner validates minimum distance before calling this payout rule.
	if not is_finite(distance) or distance < 0.0: return 0
	return clampi(floori(distance * GOLD_PER_WORLD_UNIT), MIN_TRIP_GOLD, MAX_TRIP_GOLD)

static func candidate(position: Vector2, owner: int, town_centers: Array) -> Dictionary:
	var result: Dictionary = {
		"has_town_center": false, "usable_distance": false, "distance": 0.0,
		"needed_distance": MIN_ROUTE_DISTANCE, "payout": 0,
		"home_position": Vector2.ZERO, "route_confirmed": false,
		"reason": "no_town_center",
	}
	if not position.is_finite():
		result.reason = "invalid_position"
		return result
	for entry: Variant in town_centers:
		if not entry is Dictionary or entry.get("owner", -1) != owner or entry.get("active", false) != true: continue
		if not entry.get("position") is Vector2 or not (entry.position as Vector2).is_finite(): continue
		var distance: float = position.distance_to(entry.position)
		if not result.has_town_center or distance >= float(result.distance):
			result.has_town_center = true
			result.distance = distance
			result.home_position = entry.position
	if not result.has_town_center: return result
	result.needed_distance = maxf(0.0, MIN_ROUTE_DISTANCE - float(result.distance))
	result.usable_distance = float(result.distance) >= MIN_ROUTE_DISTANCE
	result.reason = "provisional" if result.usable_distance else "too_close"
	if result.usable_distance: result.payout = income_for_distance(float(result.distance))
	return result
