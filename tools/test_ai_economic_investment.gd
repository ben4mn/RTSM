extends Node
## Synthetic policy/transaction regression. Normal paid-match probes separately
## measure whether an investment actually improves a whole-match economy.

var failures: Array[String] = []
var fixture: Node2D
var ai: AIController
var map: InvestmentMap
var blacksmith: BuildingBase
var camp: BuildingBase
var source: ResourceNode
var workers: Array[Villager] = []


class InvestmentMap extends Node2D:
	var hide_terrain: bool = false
	var enemy_visible: bool = true
	var sacred_site: Node2D = null
	var blocked: Dictionary = {}
	var resources: Dictionary = {}
	var resource_queries: int = 0
	var hidden_tiles: Dictionary = {}
	var queried_tiles: Array[Vector2i] = []

	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2((tile.x - tile.y) * 32.0, (tile.x + tile.y) * 16.0)

	func world_to_tile(point: Vector2) -> Vector2i:
		return Vector2i(roundi((point.x / 32.0 + point.y / 16.0) * 0.5), roundi((point.y / 16.0 - point.x / 32.0) * 0.5))

	func is_tile_visible_to_player(tile: Vector2i, _owner: int = 0) -> bool:
		return not hide_terrain and not hidden_tiles.has(tile)

	func is_entity_visible_to_player(_entity: Node2D, _owner: int = 0) -> bool:
		return enemy_visible

	func is_tile_buildable(tile: Vector2i) -> bool:
		return not blocked.has(tile)

	func get_resource_node_at(tile: Vector2i) -> Node2D:
		resource_queries += 1
		queried_tiles.append(tile)
		return resources.get(tile)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	_setup()
	ai._is_under_pressure = true
	var bank: Dictionary = ResourceManager.get_all_resources(1).duplicate()
	ai._check_research()
	_expect(GameManager.has_research(1, "loom"), "visible home pressure chooses paid Loom for vulnerable workers")
	_expect(ResourceManager.get_resource(1, "gold") == int(bank.gold) - 50 and ResourceManager.get_resource(1, "food") == int(bank.food), "Loom uses the exact normal 50-gold transaction")
	_expect(GameManager.researched_upgrades[1].size() == 1, "one decision buys at most one technology")
	_setup()
	ai._check_research()
	_expect(GameManager.has_research(1, "wheelbarrow"), "safe mature workforce invests in Wheelbarrow")
	_expect(ResourceManager.get_resource(1, "food") == 825 and ResourceManager.get_resource(1, "wood") == 950, "economic research pays its normal food/wood cost")
	_expect(is_equal_approx(GameManager.get_gather_bonus(1), UnitData.WHEELBARROW_GATHER_BONUS), "shared transaction applies the real gather upgrade")
	_setup()
	ResourceManager.initialize_player(1, {"food": 224, "wood": 200, "gold": 200})
	ai._check_research()
	_expect(not GameManager.has_research(1, "wheelbarrow"), "investment preserves the next worker's food")
	_setup()
	blacksmith.state = BuildingBase.State.CONSTRUCTING
	ai._check_research()
	_expect(GameManager.researched_upgrades[1].is_empty(), "unfinished Blacksmith grants no technology")
	_setup()
	ai._saving_for_age_up = true
	ai._check_research()
	_expect(GameManager.researched_upgrades[1].is_empty(), "safe age saving remains ahead of optional research")
	_setup()
	if not ai.has_method("_get_expansion_camp_anchor"):
		_expect(false, "compact economy can identify a worked remote expansion")
	else:
		_test_expansion()
	if GameManager.has_method("get_player_civilization"):
		_setup()
		_test_civilization_mix()
	fixture.free()
	for failure: String in failures:
		push_error("[FAIL] ai_economic_investment: " + failure)
	if failures.is_empty():
		print("[PASS] ai_economic_investment: paid Loom/Wheelbarrow, reserves, active building, age saving, visible worked expansion, danger, resources, spacing, two-camp limit and fair civilization counters")
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_expansion() -> void:
	var expected: Vector2i = source.tile_position
	_expect(ai.call("_get_expansion_camp_anchor") == expected, "two workers hauling remote visible resources justify a second camp")
	var targets: Dictionary = ai._get_target_building_counts(2)
	_expect(int(targets[BuildingData.BuildingType.RESOURCE_CAMP]) == 2, "actual construction policy permits the justified second camp")
	var location: Vector2i = ai._find_build_location(BuildingData.BuildingType.RESOURCE_CAMP)
	_expect(location != Vector2i(-1, -1) and location.distance_to(expected) < 6.0, "placement searches the worked cluster instead of the original base")
	map.hide_terrain = true
	map.resource_queries = 0
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1), "orders left behind fog cannot reveal an expansion resource")
	_expect(map.resource_queries == 0, "hidden terrain is rejected before querying neighboring stock")
	map.hide_terrain = false
	source.remaining = 20
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1), "nearly depleted source cannot justify a fresh 80-wood camp")
	var neighbor := ResourceNode.new()
	neighbor.tile_position = source.tile_position + Vector2i(1, 0)
	neighbor.resource_type = "wood"
	neighbor.total_amount = 380
	neighbor.position = map.tile_to_world(neighbor.tile_position)
	fixture.add_child(neighbor)
	map.resources[neighbor.tile_position] = neighbor
	map.hidden_tiles[neighbor.tile_position] = true
	map.queried_tiles.clear()
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1) and neighbor.tile_position not in map.queried_tiles, "hidden neighboring stock is never read to justify a camp")
	map.hidden_tiles.clear()
	_expect(ai.call("_get_expansion_camp_anchor") == expected, "visible same-type cluster repays a camp even if the current tree is nearly spent")
	map.resources.erase(neighbor.tile_position)
	neighbor.free()
	source.remaining = 600
	workers[1].gather_target = null
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1), "single remote worker does not justify speculative infrastructure")
	workers[1].gather_target = source
	workers[1].current_state = UnitBase.State.IDLE
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1), "stale target on an idle worker does not count as productive demand")
	workers[1].current_state = UnitBase.State.GATHERING
	ai._is_under_pressure = true
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1), "home defense takes priority over expansion")
	ai._is_under_pressure = false
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 100, "gold": 1000})
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1), "camp investment preserves a real troop-production reserve")
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 1000, "gold": 1000})
	var enemy: UnitBase = _unit("infantry", 0)
	enemy.position = source.position + Vector2(10, 10)
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1), "visible armed threat makes the expansion unsafe")
	map.enemy_visible = false
	_expect(ai.call("_get_expansion_camp_anchor") == expected, "hidden enemy is not consulted by expansion policy")
	enemy.free()
	map.enemy_visible = true
	camp.position = source.position + Vector2(50, 0)
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1), "nearby owned drop-off removes the investment need")
	camp.position = map.tile_to_world(Vector2i(11, 6))
	var second: BuildingBase = _building("resource_camp", Vector2i(20, 15))
	ai._update_building_counts()
	_expect(ai.call("_get_expansion_camp_anchor") == Vector2i(-1, -1), "compact policy never adds a third camp")
	second.state = BuildingBase.State.DESTROYED
	ai._update_building_counts()
	var bank: Dictionary = ResourceManager.get_all_resources(1).duplicate()
	ai.call("_get_expansion_camp_anchor")
	_expect(ResourceManager.get_all_resources(1) == bank, "planning neither grants nor spends resources")


func _test_civilization_mix() -> void:
	GameManager.players[1]["civilization"] = 1
	var plan: Array = ai._rank_compact_military_plan([1, 2, 3])
	_expect(int(plan[0]) == UnitData.UnitType.ARCHER, "Verdant prioritizes its ranged identity in an otherwise even choice")
	GameManager.players[1]["civilization"] = 2
	plan = ai._rank_compact_military_plan([1, 2, 3])
	_expect(int(plan[0]) == UnitData.UnitType.CAVALRY, "Sunstride prioritizes its mounted identity in an otherwise even choice")
	GameManager.players[1]["civilization"] = 1
	var enemy: UnitBase = _unit("archer", 0)
	plan = ai._rank_compact_military_plan([1, 2, 3])
	_expect(int(plan[0]) == UnitData.UnitType.CAVALRY, "observed ranged counter overrides Verdant's mounted weakness")
	map.enemy_visible = false
	plan = ai._rank_compact_military_plan([1, 2, 3])
	_expect(int(plan[0]) == UnitData.UnitType.ARCHER, "hidden composition never overrides civilization strategy")
	enemy.free()


func _setup() -> void:
	if is_instance_valid(fixture):
		fixture.free()
	workers.clear()
	GameManager.selected_population_limit = 30
	GameManager.initialize_game(2)
	GameManager.players[1]["age"] = 2
	GameManager.players[1]["population_cap"] = 30
	ResourceManager.initialize_player(0, {"food": 1000, "wood": 1000, "gold": 1000})
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 1000, "gold": 1000})
	fixture = Node2D.new()
	fixture.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(fixture)
	map = InvestmentMap.new()
	fixture.add_child(map)
	ai = AIController.new()
	ai.player_id = 1
	ai.enemy_id = 0
	ai.difficulty = AIController.Difficulty.MEDIUM
	ai.game_map = map
	fixture.add_child(ai)
	ai._decision_timer.stop()
	ai._game_time = 420.0
	ai._base_tile = Vector2i(6, 6)
	ai._base_position = map.tile_to_world(ai._base_tile)
	_building("town_center", Vector2i(6, 6))
	camp = _building("resource_camp", Vector2i(11, 6))
	blacksmith = _building("blacksmith", Vector2i(6, 12))
	_building("archery_range", Vector2i(12, 12))
	_building("stable", Vector2i(17, 6))
	_building("barracks", Vector2i(6, 17))
	for index: int in 10:
		var worker := _unit("villager", 1) as Villager
		workers.append(worker)
		ai._my_units.append(worker)
	for index: int in 3:
		ai._my_units.append(_unit("infantry", 1))
	source = ResourceNode.new()
	source.tile_position = Vector2i(40, 20)
	source.resource_type = "wood"
	source.total_amount = 600
	source.position = map.tile_to_world(source.tile_position)
	fixture.add_child(source)
	map.resources[source.tile_position] = source
	map.blocked[source.tile_position] = true
	for index: int in 2:
		workers[index].gather_target = source
		workers[index].position = source.position + Vector2(index * 18, 0)
		workers[index].current_state = UnitBase.State.GATHERING
	ai._update_building_counts()


func _building(kind: String, tile: Vector2i) -> BuildingBase:
	var building := load("res://scenes/buildings/%s.tscn" % kind).instantiate() as BuildingBase
	building.player_owner = 1
	building.position = map.tile_to_world(tile)
	fixture.add_child(building)
	building.state = BuildingBase.State.ACTIVE
	building.hp = building.max_hp
	ai._my_buildings.append(building)
	return building


func _unit(kind: String, owner: int) -> UnitBase:
	var unit := load("res://scenes/units/%s.tscn" % kind).instantiate() as UnitBase
	unit.player_owner = owner
	fixture.add_child(unit)
	unit.position = ai._base_position
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
