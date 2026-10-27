class_name Trader
extends UnitBase
## Paid, exposed gold: no income until a full TC -> Post -> TC trip completes.
const TRADE_PREVIEW = preload("res://scripts/units/trade_preview.gd")
const MIN_ROUTE_DISTANCE: float = TRADE_PREVIEW.MIN_ROUTE_DISTANCE
const HANDLING_SECONDS: float = 3.0
var trade_post: BuildingBase = null
var home_town_center: BuildingBase = null
var carried_gold: int = 0
var delivered_gold: int = 0
var trade_route_active: bool = false
var _destination: BuildingBase = null
var _visited_home: bool = false
var _manual_pause: bool = false
var _handling_left: float = 0.0
var _retry_left: float = 0.0
# Observation from the last route attempt, never a UI-triggered path search.
# Kept ephemeral: restored routes show Finding route until movement is confirmed.
enum RouteIssue { NONE, FINDING, MISSING_POST, MISSING_HOME, TOO_CLOSE, BLOCKED }
var _route_issue: RouteIssue = RouteIssue.FINDING


func _ready() -> void:
	super._ready()
	add_to_group("traders")
	stance = Stance.STAND_GROUND


func _process(delta: float) -> void:
	if NetworkSession.is_client(): return
	super._process(delta)
	if current_state == State.DEAD or get_tree().paused: return
	_retry_left = maxf(0.0, _retry_left - delta)
	if _manual_pause: return
	if not _endpoint_valid(trade_post) or not _endpoint_valid(home_town_center):
		if trade_route_active: _route_issue = RouteIssue.FINDING
		_clear_route()
		if _retry_left <= 0.0:
			_retry_left = 2.0
			_find_route()
		return
	if not trade_route_active: return
	if current_state == State.MOVING:
		if _navigation_failed_repaths > 0 or _navigation_stall_repaths > 0:
			_route_issue = RouteIssue.BLOCKED
		elif path_index < path.size():
			_route_issue = RouteIssue.NONE
	if _handling_left > 0.0:
		_handling_left = maxf(0.0, _handling_left - delta)
		if _handling_left == 0.0: _depart()
		return
	if current_state == State.IDLE and _endpoint_valid(_destination):
		var map: Node2D = _get_navigation_map()
		var distance: float = map.get_building_work_distance(global_position, _destination.global_position, _destination.footprint) if map else INF
		if distance > 46.0:
			_route_issue = RouteIssue.BLOCKED
			# Blockade or unreachable route: no payout, retry at a bounded cadence.
			if _retry_left <= 0.0:
				_retry_left = 2.0
				_travel_to(_destination)
			return
		_route_issue = RouteIssue.NONE
		if _destination == home_town_center:
			if carried_gold > 0:
				ResourceManager.add_resource(player_owner, "gold", carried_gold)
				delivered_gold += carried_gold
				carried_gold = 0
			_visited_home = true
		else:
			if _visited_home: carried_gold = get_trip_income()
		_handling_left = HANDLING_SECONDS


func _endpoint_valid(endpoint: Variant) -> bool:
	return is_instance_valid(endpoint) and endpoint is BuildingBase and endpoint.player_owner == player_owner and endpoint.state == BuildingBase.State.ACTIVE


func _find_route() -> void:
	var nearest_post: BuildingBase = null
	var nearest_distance: float = INF
	for building: Node in get_tree().get_nodes_in_group("buildings"):
		if not _endpoint_valid(building) or building.building_type != BuildingData.BuildingType.TRADE_POST: continue
		var distance: float = global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_post = building
	if nearest_post != null: command_trade(nearest_post)
	else: _route_issue = RouteIssue.MISSING_POST


func command_trade(post: BuildingBase) -> bool:
	if not _endpoint_valid(post) or post.building_type != BuildingData.BuildingType.TRADE_POST: return false
	var best_home: BuildingBase = null
	var longest_distance: float = MIN_ROUTE_DISTANCE
	var map: Node2D = _get_navigation_map()
	if map == null:
		if not trade_route_active: _route_issue = RouteIssue.FINDING
		return false
	var has_home: bool = false
	var has_distant_home: bool = false
	for building: Node in get_tree().get_nodes_in_group("buildings"):
		if not _endpoint_valid(building) or building.building_type != BuildingData.BuildingType.TOWN_CENTER: continue
		has_home = true
		var distance: float = post.global_position.distance_to(building.global_position)
		if distance >= longest_distance:
			has_distant_home = true
			var route: PackedVector2Array = map.get_building_dropoff_world_path(post.global_position, building.global_position, building.footprint, 36.0)
			if not route.is_empty():
				longest_distance = distance
				best_home = building
	if best_home == null:
		# A rejected new order leaves any existing route and its status intact.
		if not trade_route_active:
			_route_issue = RouteIssue.MISSING_HOME if not has_home else RouteIssue.TOO_CLOSE if not has_distant_home else RouteIssue.BLOCKED
		return false
	_clear_route()
	trade_post = post
	home_town_center = best_home
	_manual_pause = false
	trade_route_active = true
	_travel_to(home_town_center)
	return true


func get_trip_income() -> int:
	if NetworkSession.is_client(): return int(get_meta("network_trade_income", 0))
	if not _endpoint_valid(trade_post) or not _endpoint_valid(home_town_center): return 0
	return TRADE_PREVIEW.income_for_distance(trade_post.global_position.distance_to(home_town_center.global_position))


func get_trade_status() -> String:
	if NetworkSession.is_client():
		var status: String = str(get_meta("network_trade_status", ""))
		return status if not status.is_empty() else "Finding route"
	if _manual_pause: return "Trade paused · tap your Trade Post to resume"
	match _route_issue:
		RouteIssue.MISSING_POST: return "Needs an active Trade Post"
		RouteIssue.MISSING_HOME: return "Needs an active Town Center"
		RouteIssue.TOO_CLOSE: return "Trade Post too close · build farther from Town Center"
		RouteIssue.BLOCKED: return "Trade route blocked · retrying"
		RouteIssue.FINDING: return "Finding route"
	if not trade_route_active or not _endpoint_valid(trade_post) or not _endpoint_valid(home_town_center): return "Finding route"
	if _handling_left > 0.0:
		return "Loading · %d gold aboard" % carried_gold if _destination == trade_post else "Preparing next trip · %d gold per round trip" % get_trip_income()
	if carried_gold > 0: return "Returning · %d gold aboard" % carried_gold
	return "Travelling to Town Center" if _destination == home_town_center else "Travelling to Trade Post · %d gold per round trip" % get_trip_income()


func needs_trade_attention() -> bool:
	if NetworkSession.is_client():
		# Replicas have no local route assignment. Interpret the already-sent
		# authoritative status, including the previous protocol's income text.
		var status: String = str(get_meta("network_trade_status", ""))
		if int(get_meta("network_trade_income", 0)) <= 0: return true
		return not (status.begins_with("Travelling to ") or status.begins_with("Loading · ") or status.begins_with("Returning · ") or status.begins_with("Preparing next trip · ") or status.contains("gold aboard · "))
	return _manual_pause or not trade_route_active or _route_issue != RouteIssue.NONE or not _endpoint_valid(trade_post) or not _endpoint_valid(home_town_center)


func _depart() -> void:
	_travel_to(trade_post if _destination == home_town_center else home_town_center)


func _travel_to(endpoint: BuildingBase) -> void:
	if not _endpoint_valid(endpoint):
		_route_issue = RouteIssue.FINDING
		return
	_destination = endpoint
	var map: Node2D = _get_navigation_map()
	if map == null:
		_route_issue = RouteIssue.FINDING
		return
	var route: PackedVector2Array = map.get_building_dropoff_world_path(global_position, endpoint.global_position, endpoint.footprint, 36.0)
	_route_issue = RouteIssue.BLOCKED if route.is_empty() else RouteIssue.NONE
	if not route.is_empty(): super.command_move_path(route)


func _clear_route() -> void:
	trade_route_active = false
	carried_gold = 0
	_visited_home = false
	_handling_left = 0.0
	trade_post = null
	home_town_center = null
	_destination = null


func command_move(target_pos: Vector2) -> void:
	_clear_route()
	_manual_pause = true
	super.command_move(target_pos)


func command_stop() -> void:
	_clear_route()
	_manual_pause = true
	super.command_stop()


func command_move_path(world_path: PackedVector2Array) -> void:
	_clear_route()
	_manual_pause = true
	super.command_move_path(world_path)
