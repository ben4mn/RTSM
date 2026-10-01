extends SceneTree
## Paid births must spread at a rally without hostile knowledge or worker order changes.

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.set("selected_map_seed", 404)
	gm.set("guided_opening_enabled", false)
	gm.set("selected_population_limit", 30)
	root.get_node("AudioManager").call("set_all_enabled", false)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for frame: int in range(900):
		await process_frame
		if int(gm.get("current_state")) == 2 and not (main.get("_player_buildings") as Array)[0].is_empty():
			break
	main.set_process(false)
	main.get_node("AIController").set_process(false)
	var map: Node2D = main.get_node("GameMap") as Node2D
	var buildings: Array = (main.get("_player_buildings") as Array)[0]
	var tc: Node2D = buildings[0] as Node2D
	var pq: Node = tc.get_production_queue() as Node
	pq.set_process(false)
	var units: Array = (main.get("_player_units") as Array)[0]
	for player_units: Array in main.get("_player_units"):
		for old_unit: Node2D in player_units:
			old_unit.set_process(false)
	var origin: Vector2i = map.world_to_tile(tc.global_position)
	var egress: Dictionary = main.call("_resolve_production_egress", tc)
	var rally_tile := Vector2i(-1, -1)
	for dy: int in range(-8, 9):
		for dx: int in range(-8, 9):
			var candidate := origin + Vector2i(dx, dy)
			var world: Vector2 = map.tile_to_world(candidate)
			if rally_tile.x >= 0 or not map.is_tile_walkable(candidate) or world.distance_to(tc.global_position) < 220.0:
				continue
			var route: PackedVector2Array = map.get_navigation_world_path(egress["world_position"], world, 8.0)
			if not route.is_empty() and route[-1].distance_to(world) < 8.0:
				rally_tile = candidate
	if rally_tile.x < 0:
		push_error("No legal rally fixture")
		quit(1)
		return
	var rally: Vector2 = map.tile_to_world(rally_tile)
	tc.set_rally_point(rally)
	var rm: Node = root.get_node("ResourceManager")
	var before: Dictionary = {"food":rm.call("get_resource",0,"food"),"wood":rm.call("get_resource",0,"wood"),"gold":rm.call("get_resource",0,"gold")}
	var cost: Dictionary = UnitData.get_unit_cost(4)
	var accepted: int = 0
	for i: int in range(5):
		if pq.enqueue_unit(4): accepted += 1
	_expect(accepted == 5, "five Scouts paid from normal initial resources")
	for i: int in range(5):
		pq.advance(float(pq.get("current_train_time")))
	var scouts: Array[Node2D] = []
	var destinations: Array[Vector2] = []
	for unit: Node2D in units:
		if int(unit.get("unit_type")) == 4:
			unit.set_process(false)
			scouts.append(unit)
			destinations.append(unit.get("move_target"))
			_expect(int(unit.get("current_state")) == 1, "new Scout receives a movement order")
			var goal_tile: Vector2i = map.world_to_tile(unit.get("move_target"))
			_expect(map.is_tile_walkable(goal_tile), "military rally endpoint is walkable")
			_expect(maxi(absi(goal_tile.x-rally_tile.x),absi(goal_tile.y-rally_tile.y)) <= 2, "endpoint stays within two tile rings")
	_expect(scouts.size() == 5, "each paid completion spawns once")
	_expect(_minimum_pair_distance(destinations) >= 30.0, "pending MOVING destinations reserve different rally slots")
	_expect((tc.get("rally_point") as Vector2).distance_to(rally) < 0.01, "public rally marker unchanged")
	_expect(int(rm.call("get_resource",0,"food")) == int(before["food"])-5*int(cost.get("food",0)), "exact paid food deductions")
	_expect(int(rm.call("get_resource",0,"gold")) == int(before["gold"])-5*int(cost.get("gold",0)), "exact paid gold deductions")
	_expect(int(gm.call("get_reserved_population",0)) == 0, "all birth reservations consumed once")
	if scouts.size() == 5:
		var probe: Node2D = scouts[0]
		var original: PackedVector2Array = map.get_navigation_world_path(probe.global_position,rally,4.0)
		var unchanged: PackedVector2Array = main.call("_get_unoccupied_production_rally_path",probe,original)
		var enemy_units: Array = (main.get("_player_units") as Array)[1]
		var enemy_saved: Array = []
		for enemy: Node2D in enemy_units:
			enemy_saved.append([enemy,enemy.global_position,enemy.get("current_state"),enemy.get("move_target")])
			enemy.global_position = unchanged[-1]
			enemy.set("current_state",1)
			enemy.set("move_target",rally)
		var hidden_enemy_route: PackedVector2Array = main.call("_get_unoccupied_production_rally_path",probe,original)
		_expect(hidden_enemy_route == unchanged, "hostile positions and movement destinations do not alter slot choice")
		for saved: Array in enemy_saved:
			saved[0].global_position = saved[1]
			saved[0].set("current_state",saved[2])
			saved[0].set("move_target",saved[3])
		var own_saved: Array = []
		for other: Node2D in scouts:
			if other == probe: continue
			own_saved.append([other,other.global_position,other.get("current_state")])
			other.global_position = rally
			other.set("current_state",5)
		_expect(bool(main.call("_is_production_rally_slot_free",probe,rally)), "dead owned entries do not occupy rally slots")
		for saved: Array in own_saved:
			saved[0].global_position = saved[1]
			saved[0].set("current_state",saved[2])
		var blockers: Array[Node2D] = []
		for dy: int in range(-2,3):
			for dx: int in range(-2,3):
				var tile := rally_tile + Vector2i(dx,dy)
				if not map.is_tile_walkable(tile): continue
				var blocker: Node2D = load("res://scenes/units/scout.tscn").instantiate()
				blocker.set("player_owner",0)
				root.add_child(blocker)
				blocker.set_process(false)
				blocker.global_position = map.tile_to_world(tile)
				units.append(blocker)
				blockers.append(blocker)
		var crowded_route: PackedVector2Array = main.call("_get_unoccupied_production_rally_path",probe,original)
		_expect(crowded_route == original, "fully occupied bounded area retains paid birth route")
		for blocker: Node2D in blockers:
			units.erase(blocker)
			blocker.free()
		var villager: Node2D = units[0]
		_expect(bool(main.call("_issue_production_rally",villager,rally)), "custom Villager rally remains routed")
		_expect((villager.get("move_target") as Vector2).distance_to(rally) < 0.01, "Villager retains exact requested rally endpoint")
	for step: int in range(1800):
		pq.advance(0.05)
		for unit: Node2D in units:
			unit.set_process(false)
			if unit.unit_type == 4:
				unit._process(0.05)
		if step % 100 == 0:
			await process_frame
	var positions: Array[Vector2] = []
	var states: Array[int] = []
	for unit: Node2D in units:
		if unit.unit_type == 4:
			positions.append(unit.global_position)
			states.append(unit.current_state)
	var min_pair: float = INF
	var max_pair: float = 0.0
	for a: int in range(positions.size()):
		for b: int in range(a+1, positions.size()):
			min_pair = minf(min_pair,positions[a].distance_to(positions[b]))
			max_pair = maxf(max_pair,positions[a].distance_to(positions[b]))
	var result: Dictionary = {"diagnostic":"normal-budget paid Scout production to one rally, idle overlap","accepted":accepted,"scouts":positions.size(),"states":states,"positions":positions,"rally":rally,"minimum_pair_world":min_pair,"maximum_pair_world":max_pair,"starting_bank":before,"ending_bank":{"food":rm.call("get_resource",0,"food"),"wood":rm.call("get_resource",0,"wood"),"gold":rm.call("get_resource",0,"gold")},"manual_browser_state_modified":false}
	var file := FileAccess.open("res://output/rts-iteration-2026-09-30/rally-spacing-regression.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	_expect(positions.size() == 5 and states == [0,0,0,0,0], "five paid Scouts naturally finish IDLE")
	_expect(min_pair >= 24.0, "idle arrivals remain visibly separated")
	if _failures.is_empty():
		print("[PASS] production_rally_spacing: paid births, distinct own MOVING destinations, separated idle arrivals, marker, ownership, dead entries, bounded crowding fallback, Villager semantics")
		quit(0)
	else:
		for failure: String in _failures: push_error("[FAIL] production_rally_spacing: " + failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)


func _minimum_pair_distance(positions: Array[Vector2]) -> float:
	var distance: float = INF
	for a: int in range(positions.size()):
		for b: int in range(a+1,positions.size()):
			distance = minf(distance,positions[a].distance_to(positions[b]))
	return distance
