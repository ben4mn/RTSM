extends Node
const PREVIEW = preload("res://scripts/units/trade_preview.gd")
var checks: int = 0
var failures: Array[String] = []
func _ready() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _run() -> void:
	var bank_before: Dictionary = ResourceManager._player_resources.duplicate(true)
	_check(Trader.MIN_ROUTE_DISTANCE == PREVIEW.MIN_ROUTE_DISTANCE, "actual trader and preview share minimum range")
	var result: Dictionary = PREVIEW.candidate(Vector2.ZERO, 0, [])
	_check(not result.has_town_center and not result.usable_distance and result.payout == 0 and result.reason == "no_town_center", "missing TC has no offered income")
	result = PREVIEW.candidate(Vector2.ZERO, 0, [{"owner": 0, "active": true, "position": Vector2(499, 0)}])
	_check(not result.usable_distance and result.payout == 0 and result.needed_distance == 1.0 and result.reason == "too_close", "499 is too close")
	result = PREVIEW.candidate(Vector2.ZERO, 0, [{"owner": 0, "active": true, "position": Vector2(300, 400)}])
	_check(result.usable_distance and result.distance == 500.0 and result.payout == 20 and result.needed_distance == 0.0, "exact500 qualifies geometrically")
	var centers: Array = [
		{"owner": 0, "active": true, "position": Vector2(600, 0)},
		{"owner": 0, "active": true, "position": Vector2(1000, 0)},
		{"owner": 1, "active": true, "position": Vector2(2000, 0)},
		{"owner": 0, "active": false, "position": Vector2(3000, 0)},
	]
	var original: Array = centers.duplicate(true)
	result = PREVIEW.candidate(Vector2.ZERO, 0, centers)
	_check(result.payout == 40 and result.distance == 1000.0 and result.home_position == Vector2(1000, 0), "farthest eligible own TC only")
	_check(centers == original, "planning does not mutate TC inputs")
	_check(not result.route_confirmed and result.reason == "provisional", "eligible distance never promises a clear road")
	centers[1]["blocked_route"] = true
	centers[1]["unexplored_route"] = true
	_check(PREVIEW.candidate(Vector2.ZERO, 0, centers) == result, "hidden blockages cannot change the geometric planning hint")
	result = PREVIEW.candidate(Vector2.ZERO, 0, [{"owner": 1, "active": true, "position": Vector2(2000, 0)}, {"owner": 0, "active": false, "position": Vector2(3000, 0)}])
	_check(not result.has_town_center and result.payout == 0, "enemy and unfinished TCs excluded")
	_check(PREVIEW.income_for_distance(1499.0) == 59 and PREVIEW.income_for_distance(1500.0) == 60 and PREVIEW.income_for_distance(3000.0) == 60, "floor and60gold cap unchanged")
	_check(PREVIEW.candidate(Vector2.ZERO, 1, centers).payout == 60, "ownership works for either player")
	_check(PREVIEW.candidate(Vector2.INF, 0, centers).reason == "invalid_position" and PREVIEW.income_for_distance(INF) == 0, "non-finite geometry rejected")
	_check(ResourceManager._player_resources == bank_before, "preview spends and earns nothing")
	print(JSON.stringify({"test": "trade_preview", "checks": checks, "failures": failures, "scope": "geometry only; no route or duration promises"}))
	get_tree().quit(0 if failures.is_empty() else 1)
