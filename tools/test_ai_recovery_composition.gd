extends Node
## Paid queue, actual work ownership, fair counter shares, and landed-hit contracts.

var failures: Array[String] = []
var fixtures: Array[Node] = []
var root: Window


class WorkMap extends Node2D:
	var enemy_visible: bool = true
	var resources: Array[ResourceNode] = []
	var ordinary_route_available: bool = true
	var building_route_queries: int = 0

	func is_entity_visible_to_player(entity: Node2D, viewer: int = 0) -> bool:
		return (entity is ResourceNode and entity in resources) or entity.get("player_owner") == viewer or enemy_visible

	func is_tile_visible_to_player(_tile: Vector2i, _viewer: int = 0) -> bool:
		return true

	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2(float(tile.x - tile.y) * 32.0, float(tile.x + tile.y) * 16.0)

	func world_to_tile(position: Vector2) -> Vector2i:
		return Vector2i(roundi((position.x / 32.0 + position.y / 16.0) * 0.5), roundi((position.y / 16.0 - position.x / 32.0) * 0.5))

	func get_navigation_world_path(from: Vector2, target: Vector2, _radius: float = 4.0, _goal_radius: int = 6) -> PackedVector2Array:
		return PackedVector2Array([from, target]) if ordinary_route_available else PackedVector2Array()

	func get_building_work_world_path(from: Vector2, target: Vector2, _footprint: Vector2i, _radius: float = 4.0) -> PackedVector2Array:
		building_route_queries += 1
		return PackedVector2Array([from, target + Vector2(64.0, 0.0)])

	func get_nearest_reachable_resource_node(kind: String, from: Vector2, owner: int = -1, excluded: Dictionary = {}) -> Node2D:
		var best: ResourceNode = null
		for resource: ResourceNode in resources:
			if excluded.has(resource.get_instance_id()) or resource.resource_type != kind or not resource.is_harvestable_by(owner):
				continue
			if best == null or from.distance_squared_to(resource.global_position) < from.distance_squared_to(best.global_position):
				best = resource
		return best


func _ready() -> void:
	root = get_tree().root
	call_deferred("_run")


func _run() -> void:
	root.get_node("AudioManager").call("set_all_enabled", false)
	_test_live_recovery_and_queue_availability()
	_test_idle_batch_and_work_ownership()
	_test_visible_raid_exclusions()
	_test_completed_farm_safe_work_edge()
	_test_paid_adaptive_composition()
	_test_home_defender_economy_and_unlock_bank()
	_test_safe_replacement_role_bank()
	_test_matchup_targeting_and_resolved_hits()
	_clear()
	if failures.is_empty():
		print("[PASS] ai_recovery_composition: real worker completions, safe labor, paid adaptive mix, matchup targeting and exact landed hits")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[FAIL] ai_recovery_composition: " + failure)
		get_tree().quit(1)


func _clear() -> void:
	for fixture: Node in fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	fixtures.clear()


func _setup() -> AIController:
	_clear()
	var gm: Node = root.get_node("GameManager")
	gm.selected_population_limit = 30
	gm.initialize_game(2)
	gm.players[1]["age"] = 2
	gm.players[1]["population_cap"] = 30
	root.get_node("ResourceManager").initialize_player(1, {"food": 1000, "wood": 1000, "gold": 100})
	var ai := AIController.new()
	root.add_child(ai)
	fixtures.append(ai)
	ai._decision_timer.stop()
	ai._game_time = 400.0
	ai._has_launched_field_attack = true
	var world := WorkMap.new()
	root.add_child(world)
	fixtures.append(world)
	ai.game_map = world
	return ai


func _unit(path: String, owner: int, parent: Node, position: Vector2 = Vector2.ZERO) -> UnitBase:
	var unit: UnitBase = (load(path) as PackedScene).instantiate()
	unit.player_owner = owner
	unit.position = position
	parent.add_child(unit)
	unit.set_process(false)
	fixtures.append(unit)
	return unit


func _building(path: String, ai: AIController, complete: bool = true) -> BuildingBase:
	var building: BuildingBase = (load(path) as PackedScene).instantiate()
	building.player_owner = 1
	root.add_child(building)
	fixtures.append(building)
	if complete:
		building.complete_instantly()
	building.set_process(false)
	ai.register_building(building)
	return building


func _resource(world: WorkMap, kind: String, position: Vector2) -> ResourceNode:
	var resource := ResourceNode.new()
	resource.resource_type = kind
	resource.position = position
	world.add_child(resource)
	world.resources.append(resource)
	fixtures.append(resource)
	return resource


func _test_live_recovery_and_queue_availability() -> void:
	var ai: AIController = _setup()
	for index: int in range(3):
		ai.register_unit(_unit("res://scenes/units/villager.tscn", 1, ai.game_map, Vector2(float(index) * 16.0, 0.0)))
	var tc: BuildingBase = _building("res://scenes/buildings/town_center.tscn", ai)
	var bank_before: Dictionary = root.get_node("ResourceManager").get_all_resources(1).duplicate()
	for _index: int in range(5):
		_expect(tc.get_production_queue().enqueue_unit(UnitData.UnitType.VILLAGER), "real paid worker queue accepts its five available entries")
	_expect(ai._count_queued_unit(UnitData.UnitType.VILLAGER) == 5, "pending paid workers are counted exactly")
	_expect(ai._needs_compact_worker_recovery(), "five pending workers cannot end three-survivor economy recovery")
	_expect(ai._find_trainable_building_of_type(BuildingData.BuildingType.TOWN_CENTER) == null, "full real queue cannot masquerade as available production")
	_expect(int(root.get_node("ResourceManager").get_resource(1, "food")) == int(bank_before["food"]) - 5 * int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER)["food"]), "worker queue deducts its five normal costs")
	var pending_stable: BuildingBase = _building("res://scenes/buildings/stable.tscn", ai, false)
	_expect(ai._find_trainable_building_of_type(BuildingData.BuildingType.STABLE) == null, "unfinished Stable is unavailable to policy banking")
	_expect(not ai._is_recovery_building(BuildingData.BuildingType.BLACKSMITH) and not ai._is_recovery_building(pending_stable.building_type), "optional support and role unlocks wait during severe worker recovery")
	var requests: Array[int] = []
	ai.ai_wants_to_train.connect(func(_building_node: Node, role: int) -> void: requests.append(role))
	root.get_node("ResourceManager").initialize_player(1, {"food": 25, "wood": 200, "gold": 0})
	ai._check_military_production()
	_expect(requests.is_empty(), "cheap army/Scout queues cannot consume scarce replacement-worker food")


func _test_idle_batch_and_work_ownership() -> void:
	var ai: AIController = _setup()
	var world: WorkMap = ai.game_map as WorkMap
	_resource(world, "food", Vector2(40.0, 0.0))
	_resource(world, "wood", Vector2(60.0, 0.0))
	root.get_node("ResourceManager").initialize_player(1, {"food": 25, "wood": 200, "gold": 100})
	for index: int in range(6):
		ai.register_unit(_unit("res://scenes/units/villager.tscn", 1, world, Vector2(float(index), 0.0)))
	var shelter: Villager = _unit("res://scenes/units/villager.tscn", 1, world) as Villager
	shelter._auto_recovering = true
	ai.register_unit(shelter)
	ai._assign_idle_villagers()
	var counts: Dictionary = ai._get_economy_work_counts()
	_expect(int(counts["food"]) == 5 and int(counts["wood"]) == 1, "six idle survivors receive replacement food plus one real wood job in the same decision")
	_expect(shelter.is_retreating() and shelter.gather_target == null, "generic idle recovery preserves automatic shelter ownership")
	var loaded: Villager = _unit("res://scenes/units/villager.tscn", 1, world) as Villager
	loaded.carried_resource_type = "wood"
	loaded.carried_amount = 7
	loaded.command_move(Vector2(200.0, 0.0))
	ai.register_unit(loaded)
	counts = ai._get_economy_work_counts()
	_expect(int(counts["wood"]) == 1, "manually moving wood cargo does not count as active wood labor")


func _test_visible_raid_exclusions() -> void:
	var ai: AIController = _setup()
	var world: WorkMap = ai.game_map as WorkMap
	var dangerous: ResourceNode = _resource(world, "food", Vector2(30.0, 0.0))
	var safe: ResourceNode = _resource(world, "food", Vector2(300.0, 0.0))
	var worker: UnitBase = _unit("res://scenes/units/villager.tscn", 1, world)
	_unit("res://scenes/units/infantry.tscn", 0, world, dangerous.position)
	_expect(ai._find_resource_for_villager("food", worker) == safe, "visible hostile at nearest food selects the farther currently visible reachable food")
	var tower: BuildingBase = (load("res://scenes/buildings/watch_tower.tscn") as PackedScene).instantiate()
	tower.player_owner = 0
	tower.position = dangerous.position.lerp(safe.position, 0.5)
	world.add_child(tower)
	tower.complete_instantly()
	tower.set_process(false)
	fixtures.append(tower)
	var safe_outside_fire: ResourceNode = _resource(world, "food", Vector2(600.0, 0.0))
	_expect(ai._find_resource_for_villager("food", worker) == safe_outside_fire, "visible enemy tower fire also excludes otherwise reachable gathering endpoints")
	world.enemy_visible = false
	_expect(ai._find_resource_for_villager("food", worker) == dangerous, "hidden hostile position cannot influence gather safety choices")


func _test_paid_adaptive_composition() -> void:
	var ai: AIController = _setup()
	ai._game_time = 0.0
	var world: WorkMap = ai.game_map as WorkMap
	for path: String in ["res://scenes/units/infantry.tscn", "res://scenes/units/archer.tscn", "res://scenes/units/cavalry.tscn"]:
		for _index: int in range(3):
			ai.register_unit(_unit(path, 1, world))
	for _index: int in range(10):
		_unit("res://scenes/units/archer.tscn", 0, world, Vector2(200.0, 0.0))
	var stable: BuildingBase = _building("res://scenes/buildings/stable.tscn", ai)
	var bank_before: Dictionary = root.get_node("ResourceManager").get_all_resources(1).duplicate()
	for _index: int in range(3):
		_expect(stable.get_production_queue().enqueue_unit(UnitData.UnitType.CAVALRY), "three cavalry reinforcements use a real paid queue")
	var plan: Array = ai._rank_compact_military_plan([UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY])
	_expect(plan[0] == UnitData.UnitType.CAVALRY, "visible ranged-heavy army favors cavalry even above the old additive two-unit counter cap")
	world.enemy_visible = false
	plan = ai._rank_compact_military_plan([UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY])
	_expect(plan[0] == UnitData.UnitType.INFANTRY, "hidden composition restores balance using living plus paid pending population")
	for kind: String in ["food", "wood", "gold"]:
		_expect(int(root.get_node("ResourceManager").get_resource(1, kind)) == int(bank_before[kind]) - 3 * int(UnitData.get_unit_cost(UnitData.UnitType.CAVALRY).get(kind, 0)), "adaptive queue pays exact cavalry " + kind + " costs")


func _test_completed_farm_safe_work_edge() -> void:
	var ai: AIController = _setup()
	var world: WorkMap = ai.game_map as WorkMap
	var gold: ResourceNode = _resource(world, "gold", Vector2(10.0, 0.0))
	var worker: Villager = _unit("res://scenes/units/villager.tscn", 1, world) as Villager
	ai.register_unit(worker)
	_expect(worker.command_gather(gold), "fixture worker has an actual safe Gold order")
	var farm: BuildingBase = _building("res://scenes/buildings/farm.tscn", ai)
	farm.position = Vector2(300.0, 0.0)
	_unit("res://scenes/units/infantry.tscn", 0, world, farm.position)
	ai._assign_safe_worker_to_completed_farm(farm)
	_expect(worker.gather_target == gold, "completed Farm under current visible raid cannot steal a safe loaded or working donor")
	world.enemy_visible = false
	world.ordinary_route_available = false
	_expect(ai._is_specific_resource_reachable(worker, farm, Villager.BUILD_APPROACH_DISTANCE), "legal canonical Farm work edge remains reachable when its blocked center has no ordinary route")
	ai._assign_safe_worker_to_completed_farm(farm)
	_expect(worker.gather_target == farm and world.building_route_queries >= 2, "safe completed Farm assignment uses its actual footprint work route")


func _test_matchup_targeting_and_resolved_hits() -> void:
	var ai: AIController = _setup()
	var own: Array[UnitBase] = []
	var enemy: Array[UnitBase] = []
	for path: String in ["res://scenes/units/infantry.tscn", "res://scenes/units/archer.tscn", "res://scenes/units/cavalry.tscn"]:
		own.append(_unit(path, 1, ai.game_map))
		enemy.append(_unit(path, 0, ai.game_map, Vector2(40.0, 0.0)))
	var allocations: Dictionary = {}
	_expect(ai._choose_counter_target(own[0], enemy, allocations) == enemy[2], "Warrior defender takes the visible cavalry matchup")
	_expect(ai._choose_counter_target(own[1], enemy, allocations) == enemy[0], "Archer defender takes the visible Warrior matchup")
	_expect(ai._choose_counter_target(own[2], enemy, allocations) == enemy[1], "Horseman defender takes the visible Archer matchup")
	var recorded: Array[float] = []
	own[2].attack_landed.connect(func(_attacker: UnitBase, _defender: UnitBase, loss: float, bonus: float) -> void: recorded.append(loss); recorded.append(bonus))
	enemy[1].hp = 20.0
	Combat.resolve_unit_hit(own[2], enemy[1], 15.0, 1.5)
	Combat.resolve_unit_hit(own[2], enemy[1], 15.0, 1.5)
	_expect(recorded == [15.0, 1.5, 5.0, 1.5], "resolved cavalry hits report actual HP loss and exact counter bonus with lethal overkill clamped")


func _test_home_defender_economy_and_unlock_bank() -> void:
	var ai: AIController = _setup()
	ai.difficulty = AIController.Difficulty.EASY
	ai._has_launched_field_attack = false
	ai._game_time = 0.0
	_expect(ai._get_target_villager_count() == 12, "Feudal home defense unlocks Easy's existing twelve-worker target without a field-attack flag")
	var barracks: BuildingBase = _building("res://scenes/buildings/barracks.tscn", ai)
	_building("res://scenes/buildings/archery_range.tscn", ai)
	ai.register_unit(_unit("res://scenes/units/infantry.tscn", 1, ai.game_map))
	for _index: int in range(2):
		_expect(barracks.get_production_queue().enqueue_unit(UnitData.UnitType.INFANTRY), "pending real Warriors complete the home defense packet")
	root.get_node("ResourceManager").initialize_player(1, {"food": 100, "wood": 149, "gold": 0})
	var requests: Array[int] = []
	ai.ai_wants_to_train.connect(func(_production: Node, role: int) -> void: requests.append(role))
	_expect(not ai._try_train_from_building(BuildingData.BuildingType.BARRACKS, UnitData.UnitType.INFANTRY), "living plus pending fighters preserve the one-wood-short Stable bank")
	_expect(requests.is_empty() and root.get_node("ResourceManager").get_resource(1, "wood") == 149, "role reserve spends nothing while the paid defense packet finishes")


func _test_safe_replacement_role_bank() -> void:
	var ai: AIController = _setup()
	ai._game_time = 0.0
	ai._ai_state = AIController.AIState.MID_GAME
	for path: String in ["res://scenes/buildings/barracks.tscn", "res://scenes/buildings/archery_range.tscn", "res://scenes/buildings/stable.tscn"]:
		_building(path, ai)
	var scout: UnitBase = _unit("res://scenes/units/scout.tscn", 1, ai.game_map)
	ai.register_unit(scout)
	ai._military_role_last_fielded = {UnitData.UnitType.INFANTRY: 100.0, UnitData.UnitType.ARCHER: 200.0}
	var plan: Array = ai._rank_compact_military_plan([UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY])
	_expect(plan[0] == UnitData.UnitType.CAVALRY, "an empty army rotates toward the own role absent longest without hidden enemy knowledge")
	var requests: Array[int] = []
	ai.ai_wants_to_train.connect(func(building: Node, role: int) -> void:
		if building.get_production_queue().enqueue_unit(role):
			requests.append(role)
	)
	root.get_node("ResourceManager").initialize_player(1, {"food": 80, "wood": 30, "gold": 100})
	ai._check_military_production()
	_expect(requests.is_empty() and root.get_node("ResourceManager").get_resource(1, "food") == 80, "safe replacement waits for the final ten food of its ranked Horseman instead of buying a cheaper Warrior")
	root.get_node("ResourceManager").add_resource(1, "food", 10)
	ai._check_military_production()
	_expect(requests == [UnitData.UnitType.CAVALRY], "earned final food buys the exact paid replacement role")
	_expect(root.get_node("ResourceManager").get_resource(1, "food") == 0 and root.get_node("ResourceManager").get_resource(1, "wood") == 0, "real queue deducts the Horseman's 90 food and 30 wood once")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
