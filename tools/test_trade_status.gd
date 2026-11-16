extends Node
## Real map paths and bank changes; no wall-clock match-duration claim.
class CountingPathfinding extends Pathfinding:
	var queries: int = 0
	func _init(generator: MapGenerator) -> void: super(generator)
	func get_tile_path_to_any(from: Vector2i, destinations: Array[Vector2i], max_path_checks: int = DEFAULT_MAX_PATH_CHECKS, start_recovery_radius: int = DEFAULT_START_RECOVERY_RADIUS) -> Array[Vector2i]:
		queries += 1
		return super.get_tile_path_to_any(from, destinations, max_path_checks, start_recovery_radius)

var failures: Array[String] = []
var checks: int = 0
func _ready() -> void: _run.call_deferred()
func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _run() -> void:
	AudioManager.set_all_enabled(false)
	SoloSave._pending = true
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.selected_population_limit = 100
	GameManager.guided_opening_enabled = false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var map: Node = main.game_map
	var paths := CountingPathfinding.new(map.map_generator)
	paths._astar = map.pathfinding._astar
	paths.walkability_revision = map.pathfinding.walkability_revision
	map.pathfinding = paths
	var home: BuildingBase = main._player_town_center
	var center: Vector2i = map.map_generator.get_expansion_pocket_centers()[0]
	var trader: Trader = main._spawn_unit(UnitData.UnitType.TRADER, 0, map.tile_to_world(center + Vector2i(-1, 1)))
	_expect(trader.get_trade_status() == "Finding route" and trader.needs_trade_attention(), "unobserved route says Finding route")
	trader._find_route()
	_expect(trader.get_trade_status() == "Needs an active Trade Post", "missing post is distinct from distance")
	var post: BuildingBase = main._spawn_building(BuildingData.BuildingType.TRADE_POST, 0, center)
	post.complete_instantly()
	home.state = BuildingBase.State.DESTROYED
	_expect(not trader.command_trade(post) and trader.get_trade_status() == "Needs an active Town Center", "missing active own home is distinct from distance")
	home.state = BuildingBase.State.ACTIVE
	var post_position: Vector2 = post.global_position
	post.global_position = home.global_position + Vector2(200, 0)
	_expect(not trader.command_trade(post) and trader.get_trade_status().contains("too close"), "actual short route reports distance")
	post.global_position = post_position
	var home_tile: Vector2i = map.world_to_tile(home.global_position)
	var blocked_tiles: Dictionary = {}
	for dy: int in range(-1, home.footprint.y + 1):
		for dx: int in range(-1, home.footprint.x + 1):
			var tile := home_tile + Vector2i(dx, dy)
			blocked_tiles[tile] = paths.is_walkable(tile)
			paths.set_solid(tile, true)
	_expect(not trader.command_trade(post), "real blocked home approaches reject route")
	_expect(trader.get_trade_status() == "Trade route blocked · retrying" and trader.needs_trade_attention(), "failed path reports blocked rather than distance or income")
	var queries_before: int = paths.queries
	for refresh: int in 100:
		trader.get_trade_status()
		trader.needs_trade_attention()
		trader.get_trip_income()
	_expect(paths.queries == queries_before, "repeated UI getters do zero path queries")
	var initial_gold: int = ResourceManager.get_resource(0, "gold")
	for tick: int in 60: trader._process(0.05)
	_expect(ResourceManager.get_resource(0, "gold") == initial_gold and trader.get_trade_status().contains("blocked"), "blocked automatic retries cannot pay")
	for tile: Vector2i in blocked_tiles: paths.set_solid(tile, not bool(blocked_tiles[tile]))
	for tick: int in 50: trader._process(0.05)
	_expect(trader.trade_route_active and not trader.needs_trade_attention(), "bounded retry discovers reopened road")
	_expect(trader.get_trade_status().begins_with("Travelling to "), "recovery status reports actual movement")
	# Block an already accepted route without issuing a new player order.
	for tile: Vector2i in blocked_tiles: paths.set_solid(tile, true)
	for tick: int in 1200:
		trader._process(0.05)
		if trader.get_trade_status().contains("blocked"): break
	_expect(trader.trade_route_active and trader.needs_trade_attention() and trader.get_trade_status().contains("blocked"), "accepted but interrupted route advertises blocked instead of normal income")
	_expect(not trader.get_trade_status().contains("per round trip"), "blocked status makes no normal earning claim")
	for tick: int in 60: trader._process(0.05)
	_expect(ResourceManager.get_resource(0, "gold") == initial_gold, "active blocked retries cannot pay")
	for tile: Vector2i in blocked_tiles: paths.set_solid(tile, not bool(blocked_tiles[tile]))
	var saw_loading: bool = false
	var saw_return: bool = false
	for tick: int in 3600:
		trader._process(0.05)
		if trader.get_trade_status().begins_with("Loading · "): saw_loading = true
		if trader.get_trade_status().begins_with("Returning · "): saw_return = true
		if trader.delivered_gold > 0: break
	_expect(saw_loading and saw_return, "real trip distinguishes loading and returning cargo")
	_expect(trader.delivered_gold == trader.get_trip_income() and trader.delivered_gold > 0, "recovered trip pays exactly one advertised delivery")
	_expect(ResourceManager.get_resource(0, "gold") == initial_gold + trader.delivered_gold, "diagnostic retries add no extra bank income")
	_expect(not trader.needs_trade_attention() and trader.get_trade_status().begins_with("Preparing next trip"), "successful home handling is healthy trade")
	trader.command_stop()
	var stopped_gold: int = ResourceManager.get_resource(0, "gold")
	_expect(trader.needs_trade_attention() and trader.get_trade_status().contains("paused"), "Stop status gives explicit resume guidance")
	for tick: int in 60: trader._process(0.05)
	_expect(ResourceManager.get_resource(0, "gold") == stopped_gold, "stopped trader cannot pay")
	_expect(trader.command_trade(post) and not trader.needs_trade_attention(), "Trade Post command resumes healthy route")
	post.state = BuildingBase.State.DESTROYED
	trader._retry_left = 0.0
	trader._process(0.05)
	_expect(not trader.trade_route_active and trader.get_trade_status() == "Needs an active Trade Post", "endpoint loss updates missing post diagnostic")
	post.state = BuildingBase.State.ACTIVE
	trader._retry_left = 0.0
	trader._process(0.05)
	_expect(trader.trade_route_active, "replacement active endpoint recovers automatically")
	home.state = BuildingBase.State.DESTROYED
	trader._retry_left = 0.0
	trader._process(0.05)
	_expect(trader.get_trade_status() == "Needs an active Town Center", "lost home reports home instead of farther post")
	home.state = BuildingBase.State.ACTIVE
	# Replicas use wire metadata rather than stale/unassigned local route fields.
	NetworkSession.online = true
	NetworkSession.server_mode = false
	trader.set_meta("network_trade_income", 32)
	trader.set_meta("network_trade_status", "Travelling to Trade Post · 32 gold per round trip")
	_expect(not trader.needs_trade_attention() and trader.get_trade_status().begins_with("Travelling"), "client uses authoritative activity")
	trader.set_meta("network_trade_status", "Trade route blocked · retrying")
	_expect(trader.needs_trade_attention() and trader.get_trade_status().contains("blocked"), "client blocked route needs attention despite positive potential income")
	trader.set_meta("network_trade_status", "Trade paused · tap your Trade Post to resume")
	_expect(trader.needs_trade_attention(), "client paused route needs attention")
	trader.set_meta("network_trade_status", "")
	_expect(trader.needs_trade_attention() and trader.get_trade_status() == "Finding route", "missing client diagnostic stays safely unknown")
	trader.set_meta("network_trade_status", "0 gold aboard · 32 gold per round trip")
	_expect(not trader.needs_trade_attention(), "existing protocol's healthy status remains compatible")
	NetworkSession.online = false
	for failure: String in failures: push_error("[FAIL] trade_status: " + failure)
	print(JSON.stringify({"test":"trade_status", "checks":checks, "failures":failures, "path_queries":paths.queries}))
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
