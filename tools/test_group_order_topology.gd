extends Node
## Real Main order dispatch and A* with explicitly synthetic topology/units.
## Covers legal endpoint capacity, barrier detours, occupied slots, unreachable
## blind orders, command semantics and stale/foreign selection entries.

const OUTPUT := "res://output/evolution/group-movement-20261010"
const INFANTRY := preload("res://scenes/units/infantry.tscn")
const PLANNER := preload("res://scripts/main/group_order_planner.gd")
const FAR_CORNER := Vector2i(MapData.MAP_WIDTH - 1, MapData.MAP_HEIGHT - 1)
var _main: Node
var _map: Node2D
var _selection: SelectionManager
var _navigation: CountingNavigation
var _fixtures: Array[UnitBase] = []
var _failures: Array[String] = []
var _records: Array[Dictionary] = []

class CountingNavigation extends Pathfinding:
	var requests: int = 0
	var check_limits: Array[int] = []
	func _init(generator: MapGenerator) -> void:
		super(generator)
	func get_tile_path_to_any(from: Vector2i, destinations: Array[Vector2i], max_path_checks: int = 32, start_recovery_radius: int = 4) -> Array[Vector2i]:
		requests += 1
		check_limits.append(max_path_checks)
		return super.get_tile_path_to_any(from, destinations, max_path_checks, start_recovery_radius)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 202
	GameManager.selected_population_limit = 40
	GameManager.set_state(GameManager.GameState.MENU)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_map = _main.get("game_map")
	_selection = _map.get("selection_mgr")
	_main.set_process(false)
	_map.set_process(false)
	(_main.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	for count: int in [1, 8, 20, 40]:
		_flat()
		var units: Array[UnitBase] = _group(count, Vector2i(28, 28))
		_order(units, FAR_CORNER, "force", "corner-%d" % count)
		_check_legal_unique(units, FAR_CORNER)
		_clear()
	_flat()
	var settled: Array[UnitBase] = []
	for tile: Vector2i in [(FAR_CORNER + Vector2i(-1, 0)), (FAR_CORNER + Vector2i(0, -1)), FAR_CORNER, (FAR_CORNER + Vector2i(-1, -1))]:
		var unit: UnitBase = _spawn(tile)
		unit.command_move(unit.global_position)
		unit.call("_process_moving", 0.05)
		settled.append(unit)
	_order(settled, FAR_CORNER, "force", "settled-equal-distance-repeat")
	var settled_changes: int = 0
	for unit: UnitBase in settled:
		if unit.move_target != unit.global_position:
			settled_changes += 1
	_expect(settled_changes == 0, "equal-distance arrived members must retain their occupied legal slots on repeat")
	_records[_records.size() - 1]["repeated_goal_changes"] = settled_changes
	_clear()
	_flat()
	var outside: Array[UnitBase] = _group(8, Vector2i(25, 25))
	_order(outside, Vector2i(MapData.MAP_WIDTH + 32, -20), "force", "outside-map-center-projection")
	_check_legal_unique(outside, Vector2i(MapData.MAP_WIDTH - 1, 0))
	_clear()
	_flat()
	_navigation.set_area_solid(Vector2i(29, 29), Vector2i(4, 4))
	var blocked_units: Array[UnitBase] = _group(20, Vector2i(21, 21))
	_order(blocked_units, Vector2i(30, 30), "force", "solid-footprint")
	_check_legal_unique(blocked_units, Vector2i(30, 30))
	_clear()
	_flat()
	for y: int in MapData.MAP_HEIGHT:
		_navigation.set_solid(Vector2i(20, y), y != 26)
	var corridor: Array[UnitBase] = _group(8, Vector2i(12, 22))
	_order(corridor, Vector2i(25, 23), "attack", "one-gap-detour")
	_check_legal_unique(corridor, Vector2i(25, 23))
	for unit: UnitBase in corridor:
		_expect(unit.path.has(_map.tile_to_world(Vector2i(20, 26))), "every corridor route must use the actual barrier gap")
		_expect(unit.attack_move and not bool(unit.get("_force_move_active")), "A-Move must preserve engagement intent on its allocated slot")
	_clear()
	_flat()
	var occupied: UnitBase = _spawn(Vector2i(30, 30))
	(_main.get("_player_units")[0] as Array).append(occupied)
	var arriving: Array[UnitBase] = _group(8, Vector2i(22, 22))
	_order(arriving, Vector2i(30, 30), "smart", "friendly-occupied-center")
	_check_legal_unique(arriving, Vector2i(30, 30))
	for unit: UnitBase in arriving:
		_expect(unit.move_target.distance_to(occupied.global_position) >= PLANNER.FRIENDLY_CLEARANCE_WORLD, "group order must not stack onto an unselected friendly")
		_expect(not unit.attack_move and bool(unit.get("_force_move_active")), "ordinary military ground tap must preserve passive movement")
	(_main.get("_player_units")[0] as Array).erase(occupied)
	_clear()
	_flat()
	var live: UnitBase = _spawn(Vector2i(20, 20))
	var dead: UnitBase = _spawn(Vector2i(20, 21))
	dead.set_state(UnitBase.State.DEAD)
	var hostile: UnitBase = _spawn(Vector2i(20, 22), 1)
	var queued: UnitBase = _spawn(Vector2i(20, 23))
	queued.queue_free()
	_selection.selected.assign([live, dead, hostile, queued])
	_main.call("_arm_move_command")
	_main.call("_on_move_command", Vector2i(26, 26))
	_expect(live.current_state == UnitBase.State.MOVING and live.move_target == _map.tile_to_world(Vector2i(26, 26)), "only live owned unit must consume the nearest slot")
	_expect(dead.current_state == UnitBase.State.DEAD and hostile.current_state == UnitBase.State.IDLE, "foreign/dead selections must receive no group order")
	_expect(_navigation.requests == 1, "dead/foreign/queued entries must not reserve slots or run pathfinding")
	_clear()
	for count: int in [8, 40]:
		_flat()
		for y: int in MapData.MAP_HEIGHT:
			_navigation.set_solid(Vector2i(20, y))
		var sealed: Array[UnitBase] = _group(count, Vector2i(10, 20))
		_order(sealed, Vector2i(30, 20), "force", "sealed-blind-fallback-%d" % count)
		for unit: UnitBase in sealed:
			_expect(unit.current_state == UnitBase.State.MOVING and bool(unit.get("_force_move_active")), "unreachable blind Move remains an ordinary accepted Move")
			_expect(unit.path.is_empty() and unit.move_target == _map.tile_to_world(Vector2i(30, 20)), "sealed group retains requested target for canonical UnitBase fallback")
		_clear()
	_flat()
	var patrolling: Array[UnitBase] = _group(8, Vector2i(25, 25))
	_order(patrolling, FAR_CORNER, "patrol", "patrol-endpoints")
	_check_legal_unique(patrolling, FAR_CORNER, false)
	for unit: UnitBase in patrolling:
		_expect(bool(unit.get("_patrol_active")) and unit.attack_move and not bool(unit.get("_force_move_active")), "Patrol must retain its route and engagement semantics")
	_clear()
	_flat()
	var fighter: UnitBase = _spawn(Vector2i(20, 20))
	var nearby_enemy: UnitBase = _spawn(Vector2i(20, 21), 1)
	(_main.get("_player_units")[0] as Array).append(fighter)
	(_main.get("_player_units")[1] as Array).append(nearby_enemy)
	_main.call("_update_fog_of_war")
	_expect(_map.is_entity_visible_to_player(nearby_enemy, 0), "combat diagnostic enemy must actually be revealed by the owned fighter")
	var combat_units: Array[UnitBase] = [fighter]
	_order(combat_units, Vector2i(27, 20), "force", "visible-enemy-force-move")
	fighter.call("_process_moving", 0.05)
	_expect(fighter.current_state == UnitBase.State.MOVING and fighter.attack_target == null, "Main group Move must naturally pass a visible enemy without acquiring")
	_navigation.requests = 0
	_navigation.check_limits.clear()
	_order(combat_units, Vector2i(27, 20), "attack", "visible-enemy-attack-move")
	var accepted_goal: Vector2 = fighter.move_target
	fighter.call("_process_moving", 0.05)
	_expect(fighter.current_state == UnitBase.State.ATTACKING and fighter.attack_target == nearby_enemy, "Main A-Move must actually acquire a currently visible enemy")
	_expect(fighter.move_target == accepted_goal and fighter.attack_move, "A-Move engagement must retain the accepted formation endpoint")
	var before_hostile_change: Array[Dictionary] = PLANNER.plan(_map, combat_units, Vector2i(27, 20), [nearby_enemy])
	nearby_enemy.global_position = _map.tile_to_world(Vector2i(27, 20))
	var after_hostile_change: Array[Dictionary] = PLANNER.plan(_map, combat_units, Vector2i(27, 20), [nearby_enemy])
	_expect(before_hostile_change[0]["destination"] == after_hostile_change[0]["destination"], "hostile positions must never influence allocated group slots")
	(_main.get("_player_units")[0] as Array).erase(fighter)
	(_main.get("_player_units")[1] as Array).erase(nearby_enemy)
	_clear()
	var phase: String = "repeat-first-candidate" if "--repeat-baseline" in OS.get_cmdline_user_args() else "after"
	var file := FileAccess.open(OUTPUT + "/" + phase + "-topology-orders.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "Synthetic terrain/units; real Main/UnitBase/canonical A* order code. Elapsed timings are local CPU diagnostics, not device performance.", "records": _records, "failures": _failures}, "  "))
	_main.free()
	for failure: String in _failures:
		push_error("[FAIL] group_order_topology: " + failure)
	if _failures.is_empty():
		print("[PASS] group_order_topology: 1/8/20/40 unique legal group slots, solid-footprint/gap/occupied goals, stale ownership filtering, sealed blind fallback, smart/Move/A-Move/Patrol semantics")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _flat() -> void:
	var generator := MapGenerator.new(202)
	generator.call("_init_grid")
	_navigation = CountingNavigation.new(generator)
	_map.set("pathfinding", _navigation)

func _spawn(tile: Vector2i, owner: int = 0) -> UnitBase:
	var unit: UnitBase = INFANTRY.instantiate()
	unit.player_owner = owner
	unit.position = _map.tile_to_world(tile)
	unit.set_process(false)
	(_map.get_node("UnitsContainer") as Node2D).add_child(unit)
	_fixtures.append(unit)
	return unit

func _group(count: int, origin: Vector2i) -> Array[UnitBase]:
	var units: Array[UnitBase] = []
	for i: int in count:
		units.append(_spawn(origin + Vector2i(i % 4, i / 4)))
	return units

func _order(units: Array[UnitBase], target: Vector2i, mode: String, name: String) -> void:
	var selection: Array[Node2D] = []
	for unit: UnitBase in units:
		selection.append(unit)
	_selection.select_many(selection)
	if mode == "force":
		_main.call("_arm_move_command")
	elif mode == "attack":
		_main.call("_arm_attack_move_command")
	elif mode == "patrol":
		_main.call("_arm_patrol_command")
	var started: int = Time.get_ticks_usec()
	_main.call("_on_move_command", target)
	var elapsed: int = Time.get_ticks_usec() - started
	var destinations: Array[String] = []
	for unit: UnitBase in units:
		destinations.append(str(_map.world_to_tile(unit.move_target)))
	_expect(_navigation.requests == units.size(), "planning route work must make one bounded A* candidate request per live unit")
	for limit: int in _navigation.check_limits:
		_expect(limit <= PLANNER.MAX_PATH_CHECKS_PER_UNIT, "pathfinding candidate work exceeds the per-unit bound")
	_records.append({"case": name, "mode": mode, "units": units.size(), "target": str(target), "destinations": destinations, "route_requests": _navigation.requests, "path_checks_bound": PLANNER.MAX_PATH_CHECKS_PER_UNIT, "elapsed_us": elapsed})

func _check_legal_unique(units: Array[UnitBase], target: Vector2i, check_path: bool = true) -> void:
	var seen: Dictionary = {}
	for unit: UnitBase in units:
		var tile: Vector2i = _map.world_to_tile(unit.move_target)
		_expect(_map.is_tile_walkable(tile), "assigned endpoint must be walkable and in bounds")
		_expect(maxi(absi(tile.x - target.x), absi(tile.y - target.y)) <= PLANNER.MAX_SLOT_RADIUS_TILES, "formation endpoint must stay inside bounded requested area")
		_expect(not seen.has(tile), "group destination must not be reused")
		seen[tile] = true
		if check_path:
			_expect(not unit.path.is_empty() and unit.path[unit.path.size() - 1] == unit.move_target, "route must actually reach the distinct accepted endpoint")
			for waypoint: Vector2 in unit.path:
				_expect(_map.is_tile_walkable(_map.world_to_tile(waypoint)), "group path must not cross a solid tile")

func _clear() -> void:
	_selection.deselect_all()
	for unit: UnitBase in _fixtures:
		if is_instance_valid(unit):
			unit.free()
	_fixtures.clear()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
