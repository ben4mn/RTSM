class_name Trader
extends UnitBase
## Paid, exposed gold: no income until a full TC -> Post -> TC trip completes.
const MIN_ROUTE_DISTANCE: float = 500.0
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
		_clear_route()
		if _retry_left <= 0.0:
			_retry_left = 2.0
			_find_route()
		return
	if not trade_route_active: return
	if _handling_left > 0.0:
		_handling_left = maxf(0.0, _handling_left - delta)
		if _handling_left == 0.0: _depart()
		return
	if current_state == State.IDLE and _endpoint_valid(_destination):
		var map: Node2D = _get_navigation_map()
		var distance: float = map.get_building_work_distance(global_position, _destination.global_position, _destination.footprint) if map else INF
		if distance > 46.0:
			# Blockade or unreachable route: no payout, retry at a bounded cadence.
			if _retry_left <= 0.0:
				_retry_left = 2.0
				_travel_to(_destination)
			return
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


func command_trade(post: BuildingBase) -> bool:
	if not _endpoint_valid(post) or post.building_type != BuildingData.BuildingType.TRADE_POST: return false
	var best_home: BuildingBase = null
	var longest_distance: float = MIN_ROUTE_DISTANCE
	var map: Node2D = _get_navigation_map()
	if map == null: return false
	for building: Node in get_tree().get_nodes_in_group("buildings"):
		if not _endpoint_valid(building) or building.building_type != BuildingData.BuildingType.TOWN_CENTER: continue
		var distance: float = post.global_position.distance_to(building.global_position)
		if distance >= longest_distance:
			var route: PackedVector2Array = map.get_building_dropoff_world_path(post.global_position, building.global_position, building.footprint, 36.0)
			if not route.is_empty():
				longest_distance = distance
				best_home = building
	if best_home == null: return false
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
	return clampi(floori(trade_post.global_position.distance_to(home_town_center.global_position) * 0.04), 20, 60)


func get_trade_status() -> String:
	if NetworkSession.is_client(): return str(get_meta("network_trade_status", "Waiting for route"))
	if _manual_pause: return "Trade paused · tap your Trade Post to resume"
	if not trade_route_active: return "Build a Trade Post farther from your Town Center"
	return "%d gold aboard · %d gold per round trip" % [carried_gold, get_trip_income()]


func _depart() -> void:
	_travel_to(trade_post if _destination == home_town_center else home_town_center)


func _travel_to(endpoint: BuildingBase) -> void:
	if not _endpoint_valid(endpoint): return
	_destination = endpoint
	var map: Node2D = _get_navigation_map()
	if map == null: return
	var route: PackedVector2Array = map.get_building_dropoff_world_path(global_position, endpoint.global_position, endpoint.footprint, 36.0)
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
