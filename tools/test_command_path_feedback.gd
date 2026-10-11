extends Node
## Real Main/SelectionManager/UnitBase route feedback with a deterministic
## navigation barrier. Fixture units and flat navigation are synthetic; no
## paid match or physical-phone claim. Movement and orders use runtime code.

const OUTPUT := "res://output/mobile-orders-2026-10-10"
const INFANTRY_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")
const START := Vector2i(21, 23)
const GOAL := Vector2i(27, 23)
const GAP := Vector2i(24, 28)

var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _main: Node
var _map: Node2D
var _selection: SelectionManager
var _overlay: Node2D
var _navigation: CountingPathfinding


class CountingPathfinding extends Pathfinding:
	var requests: int = 0

	func _init(generator: MapGenerator) -> void:
		super(generator)

	func get_tile_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
		requests += 1
		return super.get_tile_path(from, to)

	func get_tile_path_to_any(from: Vector2i, destinations: Array[Vector2i], max_path_checks: int = 32, start_recovery_radius: int = 4) -> Array[Vector2i]:
		requests += 1
		return super.get_tile_path_to_any(from, destinations, max_path_checks, start_recovery_radius)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 30
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_expect(_main.get("_building_placement") != null, "real Main did not initialize")
	if _main.get("_building_placement") == null:
		_finish()
		return
	_map = _main.get("game_map") as Node2D
	_selection = _map.get("selection_mgr") as SelectionManager
	_overlay = _map.get_node_or_null("CommandPaths") as Node2D
	_expect(_overlay != null, "production GameMap does not attach CommandPaths")
	if _overlay == null:
		_finish()
		return
	_main.set_process(false)
	_map.set_process(false)
	(_main.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var flat := MapGenerator.new(101)
	flat.call("_init_grid")
	_navigation = CountingPathfinding.new(flat)
	for y: int in MapData.MAP_HEIGHT:
		_navigation.set_solid(Vector2i(GAP.x, y), y != GAP.y)
	_map.set("pathfinding", _navigation)
	var worker: UnitBase = (_main.get("_player_units")[0] as Array)[0] as UnitBase
	worker.command_stop()
	worker.global_position = _map.tile_to_world(START)
	_selection.select_single(worker)
	_main.call("_arm_move_command")
	_main.call("_on_move_command", GOAL)
	var issued_path: PackedVector2Array = worker.path.duplicate()
	_expect(issued_path.has(_map.tile_to_world(GAP)), "Main-issued path did not use the only barrier gap")
	_expect(_polyline_length(issued_path) > worker.global_position.distance_to(worker.move_target) * 1.2, "navigation fixture does not require a meaningful detour")
	var routes: Array[Dictionary] = _routes()
	_expect(routes.size() == 1, "one moving worker must have one feedback route")
	if routes.size() == 1:
		var points: PackedVector2Array = routes[0]["points"]
		_expect(points.has(_map.tile_to_world(GAP)), "feedback replaced the obstacle detour with a straight line")
		_expect(points[0].is_equal_approx(worker.global_position), "feedback must start at the unit's current position")
		_expect(routes[0]["destination"] == worker.move_target and routes[0]["order_destination"] == worker.move_target, "regular movement endpoint metadata disagrees with the accepted order")
		_expect(routes[0]["mode"] == "move", "forced Move is displayed as attack-move")
	_record("issued_detour", routes, worker)
	var before_feedback: int = _navigation.requests
	for repeat: int in 20:
		_routes()
		worker.get_remaining_navigation_path()
	_expect(_navigation.requests == before_feedback, "reading route feedback invokes pathfinding")
	var initial_position: Vector2 = worker.global_position
	for step: int in 80:
		worker.call("_process_moving", 0.05)
	_expect(worker.global_position.distance_to(initial_position) > 30.0 and worker.path_index > 1, "runtime movement did not consume waypoints naturally")
	routes = _routes()
	if not routes.is_empty():
		var points: PackedVector2Array = routes[0]["points"]
		_expect(points[0].is_equal_approx(worker.global_position), "moving route remains anchored at the original command position")
		_expect(not points.has(initial_position), "feedback retains already consumed waypoints")
	_record("advanced_detour", routes, worker)
	_selection.deselect_all()
	_expect(_routes().is_empty(), "deselect leaves a command path visible")
	_selection.select_single(worker)
	_expect(not _routes().is_empty(), "reselecting a moving unit does not restore its live route")
	worker.command_stop()
	_expect(_routes().is_empty() and worker.get_remaining_navigation_path().is_empty(), "Stop leaves stale waypoints or a destination marker")
	worker.command_move_path(PackedVector2Array([worker.global_position, _map.tile_to_world(Vector2i(21, 29))]))
	for step: int in 1200:
		if worker.current_state != UnitBase.State.MOVING:
			break
		worker.call("_process_moving", 0.05)
	_expect(worker.current_state == UnitBase.State.IDLE, "bounded runtime movement did not arrive")
	_expect(_routes().is_empty(), "arrival leaves a command path visible")
	_record("arrival", _routes(), worker)
	_test_attack_intent()
	_test_grouping_and_visibility()
	_finish()


func _test_attack_intent() -> void:
	var troop := _fixture_unit(0, START)
	var enemy := _fixture_unit(1, Vector2i(21, 26))
	var fog: FogManager = _map.get("fog_of_war") as FogManager
	for y: int in MapData.MAP_HEIGHT:
		for x: int in MapData.MAP_WIDTH:
			fog.fog_grid[y][x] = MapData.FogState.VISIBLE
	_selection.select_single(troop)
	_main.call("_on_move_command", GOAL)
	var accepted_destination: Vector2 = troop.move_target
	_expect(troop.attack_move and _routes()[0]["mode"] == "attack", "military smart ground order must expose attack-move feedback")
	troop.command_attack(enemy, false)
	_expect(troop.current_state == UnitBase.State.ATTACKING and troop.attack_move, "auto-acquisition discarded attack-move intent")
	var engaged: Array[Dictionary] = _routes()
	_expect(engaged.size() == 1, "combat replanning hides the pending attack-move destination")
	if engaged.size() == 1:
		_expect((engaged[0]["points"] as PackedVector2Array).is_empty(), "combat with no accepted chase path invents a straight-line route")
		_expect(engaged[0]["order_destination"] == accepted_destination, "combat marker lost the original attack-move destination")
	_record("combat_replanning", engaged, troop)
	troop.call("_process_attacking", 0.05)
	engaged = _routes()
	if engaged.size() == 1:
		_expect(engaged[0]["order_destination"] == accepted_destination, "chase route replaced the original attack-move destination")
		var chase_points: PackedVector2Array = engaged[0]["points"]
		_expect(chase_points.size() >= 2, "runtime combat chase did not create an accepted navigation path")
		if chase_points.size() >= 2:
			_expect(engaged[0]["destination"] == chase_points[chase_points.size() - 1], "live combat endpoint disagrees with chase navigation")
	_record("combat_chase", engaged, troop)
	troop.command_attack(enemy, true)
	_expect(not troop.attack_move, "explicit Attack retains a stale attack-move destination")
	_expect(not bool(troop.call("_resume_post_combat_movement")), "explicit Attack resumes an obsolete attack-move order")
	_expect(_routes().is_empty(), "explicit Attack with no chase path exposes the previous command marker")
	var enemy_building: BuildingBase = load("res://scenes/buildings/watch_tower.tscn").instantiate() as BuildingBase
	enemy_building.player_owner = 1
	enemy_building.position = _map.tile_to_world(Vector2i(21, 27))
	_map.get_node("BuildingsContainer").add_child(enemy_building)
	enemy_building.state = BuildingBase.State.ACTIVE
	enemy_building.set_process(false)
	troop.command_attack_move_path(PackedVector2Array([troop.global_position, accepted_destination]))
	troop.command_attack_building(enemy_building, true)
	_expect(troop.attack_building_target == enemy_building and not troop.attack_move, "explicit building Attack fails to replace attack-move intent")
	_expect(not bool(troop.call("_resume_post_combat_movement")), "explicit building Attack resumes an obsolete attack-move order")
	troop.command_move_path(PackedVector2Array([troop.global_position, _map.tile_to_world(Vector2i(21, 29))]))
	troop.die()
	_expect(_routes().is_empty() and troop.get_remaining_navigation_path().is_empty(), "death leaves a pending route visible before queue_free")
	_selection.deselect_all()


func _test_grouping_and_visibility() -> void:
	var first := _fixture_unit(0, Vector2i(10, 10))
	var second := _fixture_unit(0, Vector2i(10, 11))
	var goal: Vector2 = _map.tile_to_world(Vector2i(15, 15))
	first.command_move_path(PackedVector2Array([first.global_position, goal]))
	second.command_move_path(PackedVector2Array([second.global_position, goal + Vector2(24, 0)]))
	_selection.select_many([first, second])
	_expect(_routes().size() == 1, "nearby same-mode formation goals are not grouped")
	second.command_attack_move_path(PackedVector2Array([second.global_position, goal + Vector2(24, 0)]))
	_expect(_routes().size() == 2, "nearby Move and Attack goals lose their different intent")
	var group: Array[Node2D] = []
	for index: int in 8:
		var unit := _fixture_unit(0, Vector2i(10, 10 + index))
		unit.command_move_path(PackedVector2Array([unit.global_position, goal + Vector2(index * 160, 0)]))
		group.append(unit)
	_selection.select_many(group)
	_expect(_routes().size() == 4, "independent route groups are not capped at four")
	_record("capped_groups", _routes(), first)
	var enemy := _fixture_unit(1, Vector2i(12, 12))
	enemy.command_move_path(PackedVector2Array([enemy.global_position, goal]))
	# Deliberately inject an enemy-only selection to test the overlay's own
	# ownership guard even if normal selection rejects a hidden hostile.
	_selection.selected.assign([enemy])
	_expect(_routes().is_empty(), "enemy selection exposes hostile navigation")
	_selection.select_single(first)
	first.hide()
	_expect(_routes().is_empty(), "hidden selected unit exposes navigation")
	first.show()
	_selection.deselect_all()
	_expect(_routes().is_empty(), "cleared selection retains grouped feedback")


func _fixture_unit(owner: int, tile: Vector2i) -> UnitBase:
	var unit := INFANTRY_SCENE.instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = _map.tile_to_world(tile)
	_map.get_node("UnitsContainer").add_child(unit)
	unit.set_process(false)
	unit.stance = UnitBase.Stance.STAND_GROUND
	return unit


func _routes() -> Array[Dictionary]:
	return _overlay.call("get_display_routes")


func _polyline_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for index: int in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


func _record(name: String, routes: Array[Dictionary], unit: UnitBase) -> void:
	var serialized: Array[Dictionary] = []
	for route: Dictionary in routes:
		var points: Array = []
		for point: Vector2 in route["points"]:
			points.append([point.x, point.y])
		serialized.append({"mode": route["mode"], "points": points, "destination": str(route["destination"]), "order_destination": str(route["order_destination"])})
	_records.append({"state": name, "unit_position": str(unit.global_position), "path_index": unit.path_index, "routes": serialized, "navigation_requests": _navigation.requests})


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var evidence := FileAccess.open(OUTPUT + "/command-path-regression.json", FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"evidence": "Real Main orders, real selection and natural UnitBase movement with a synthetic flat A* map/one-gap barrier and injected combat/group fixtures. No paid match or physical device claim.", "records": _records, "failures": _failures}, "  "))
	if is_instance_valid(_main):
		_main.free()
	for failure: String in _failures:
		push_error("[FAIL] command_path_feedback: " + failure)
	if _failures.is_empty():
		print("[PASS] command_path_feedback: real Main detour and live progress; no feedback A*; Stop/arrival/death/deselect; combat order retention and explicit Attack replacement; ownership and four-group cap")
	get_tree().quit(0 if _failures.is_empty() else 1)
