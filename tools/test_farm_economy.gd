extends SceneTree
## Standalone headless regression for farms as finite, owner-scoped food resources.
##
## Run with:
##   Godot --headless --path . --script tools/test_farm_economy.gd
##
## Scenes and project scripts are loaded after SceneTree initialization so their
## autoload references resolve correctly in standalone --script mode.

const GAME_MAP_SCRIPT_PATH := "res://scripts/map/game_map.gd"
const FARM_SCENE_PATH := "res://scenes/buildings/farm.tscn"
const TOWN_CENTER_SCENE_PATH := "res://scenes/buildings/town_center.tscn"
const RESOURCE_SCENE_PATH := "res://scenes/map/resource_node.tscn"
const VILLAGER_SCENE_PATH := "res://scenes/units/villager.tscn"
const SELECTION_MANAGER_SCRIPT_PATH := "res://scripts/managers/selection_manager.gd"

const BUILDING_CONSTRUCTING: int = 1
const BUILDING_ACTIVE: int = 2
const BUILDING_DESTROYED: int = 3
const UNIT_MOVING: int = 1
const UNIT_GATHERING: int = 3

var _failures: Array[String] = []
var _fixtures: Array[Node] = []
var _resource_manager: Node
var _audio_manager: Node
var _game_map_script: Script
var _farm_scene: PackedScene
var _town_center_scene: PackedScene
var _resource_scene: PackedScene
var _villager_scene: PackedScene
var _selection_manager_script: Script
var _test_world: Node2D
var _lookup_fog: FogManager


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RUN] farm_economy: standalone assertions started")
	_resource_manager = root.get_node_or_null("ResourceManager")
	_audio_manager = root.get_node_or_null("AudioManager")
	if _resource_manager == null or _audio_manager == null:
		_failures.append("required ResourceManager/AudioManager autoloads are unavailable")
		_finish()
		return
	_audio_manager.call("set_all_enabled", false)
	_resource_manager.call("reset")
	_resource_manager.call("initialize_player", 0, {"food": 0, "wood": 0, "gold": 0})
	_test_world = Node2D.new()
	_test_world.name = "FarmEconomyTestWorld"
	root.add_child(_test_world)
	current_scene = _test_world
	if not _load_runtime_dependencies():
		_finish()
		return

	var game_map: Node2D = _game_map_script.new() as Node2D
	if game_map == null:
		_failures.append("GameMap script did not instantiate a Node2D")
		_finish()
		return
	_lookup_fog = FogManager.new()
	_test_world.add_child(_lookup_fog)
	_lookup_fog.set_process(false)
	game_map.set("fog_of_war", _lookup_fog)
	_test_discovery_and_owner_filtering(game_map)
	_test_human_input_targeting(game_map)
	_test_harvest_depletion()
	_test_villager_harvest_and_deposit_loop()
	game_map.free()
	_finish()


func _load_runtime_dependencies() -> bool:
	_game_map_script = load(GAME_MAP_SCRIPT_PATH) as Script
	_farm_scene = load(FARM_SCENE_PATH) as PackedScene
	_town_center_scene = load(TOWN_CENTER_SCENE_PATH) as PackedScene
	_resource_scene = load(RESOURCE_SCENE_PATH) as PackedScene
	_villager_scene = load(VILLAGER_SCENE_PATH) as PackedScene
	_selection_manager_script = load(SELECTION_MANAGER_SCRIPT_PATH) as Script
	var dependencies: Dictionary = {
		"GameMap script": _game_map_script,
		"Farm scene": _farm_scene,
		"Town Center scene": _town_center_scene,
		"Resource scene": _resource_scene,
		"Villager scene": _villager_scene,
		"SelectionManager script": _selection_manager_script,
	}
	for label: String in dependencies:
		if dependencies[label] == null:
			_failures.append("failed to load %s" % label)
	return _failures.is_empty()


func _test_discovery_and_owner_filtering(game_map: Node2D) -> void:
	var food_tile := Vector2i(5, 5)
	var wood_tile := Vector2i(1, 1)
	var natural_food: Node2D = _make_natural_resource(
		"food", 200, game_map.call("tile_to_world", food_tile) as Vector2
	)
	var natural_wood: Node2D = _make_natural_resource(
		"wood", 200, game_map.call("tile_to_world", wood_tile) as Vector2
	)
	_lookup_fog.fog_grid[food_tile.y][food_tile.x] = MapData.FogState.VISIBLE
	_lookup_fog.fog_grid[wood_tile.y][wood_tile.x] = MapData.FogState.VISIBLE
	var natural_nodes: Dictionary = game_map.get("resource_nodes") as Dictionary
	natural_nodes[Vector2i(1, 1)] = natural_food
	natural_nodes[Vector2i(2, 2)] = natural_wood

	var friendly: Node2D = _make_farm(0, Vector2(20.0, 0.0), BUILDING_ACTIVE)
	var enemy: Node2D = _make_farm(1, Vector2(10.0, 0.0), BUILDING_ACTIVE)
	var constructing: Node2D = _make_farm(0, Vector2(5.0, 0.0), BUILDING_CONSTRUCTING)
	var exhausted: Node2D = _make_farm(0, Vector2(3.0, 0.0), BUILDING_ACTIVE)
	exhausted.set("farm_remaining", 0)
	var destroyed: Node2D = _make_farm(0, Vector2(2.0, 0.0), BUILDING_DESTROYED)
	for farm: Node2D in [friendly, enemy, constructing, exhausted, destroyed]:
		game_map.call("register_harvestable", farm)

	_expect_same(
		game_map.call("get_nearest_resource_node", "food", Vector2.ZERO, 0),
		friendly,
		"player 0 lookup chooses its completed farm over closer invalid farms"
	)
	_expect_same(
		game_map.call("get_nearest_resource_node", "food", Vector2.ZERO, 1),
		enemy,
		"player 1 lookup chooses its own completed farm"
	)
	_expect_same(
		game_map.call("get_nearest_resource_node", "wood", Vector2.ZERO, 0),
		natural_wood,
		"owner filtering preserves natural non-food lookup"
	)
	_expect(bool(game_map.call("is_resource_target_valid", natural_food, "food", 0)), "neutral food remains valid for player 0")
	_expect(not bool(game_map.call("is_resource_target_valid", enemy, "food", 0)), "enemy farm is rejected")
	_expect(not bool(game_map.call("is_resource_target_valid", constructing, "food", 0)), "constructing farm is rejected")
	_expect(not bool(game_map.call("is_resource_target_valid", exhausted, "food", 0)), "exhausted farm is rejected")
	_expect(not bool(game_map.call("is_resource_target_valid", destroyed, "food", 0)), "destroyed farm is rejected")

	friendly.set("state", BUILDING_DESTROYED)
	_expect_same(
		game_map.call("get_nearest_resource_node", "food", Vector2.ZERO, 0),
		natural_food,
		"destroyed registered farm is skipped in favor of natural food"
	)
	game_map.call("unregister_harvestable", friendly)
	var registered: Array = game_map.get("_additional_resource_nodes") as Array
	_expect(not friendly in registered, "unregister removes destroyed farm from registry")


func _test_human_input_targeting(game_map: Node2D) -> void:
	var selection_manager: Node2D = _selection_manager_script.new() as Node2D
	selection_manager.set("game_map", game_map)
	root.add_child(selection_manager)
	_fixtures.append(selection_manager)
	var villager: Node2D = _villager_scene.instantiate() as Node2D
	villager.set("player_owner", 0)
	villager.global_position = Vector2(250.0, 0.0)
	root.add_child(villager)
	_fixtures.append(villager)
	selection_manager.call("_add_to_selection", villager)

	var friendly: Node2D = _make_farm(0, Vector2(300.0, 0.0), BUILDING_ACTIVE)
	var enemy: Node2D = _make_farm(1, Vector2(400.0, 0.0), BUILDING_ACTIVE)
	var constructing: Node2D = _make_farm(0, Vector2(500.0, 0.0), BUILDING_CONSTRUCTING)
	game_map.call("register_harvestable", friendly)
	game_map.call("register_harvestable", enemy)
	game_map.call("register_harvestable", constructing)

	var gather_targets: Array[Node2D] = []
	selection_manager.connect("gather_command", func(target: Node2D) -> void: gather_targets.append(target))
	selection_manager.call("_handle_right_click", friendly.global_position)
	_expect_eq(gather_targets.size(), 1, "friendly active farm emits a right-click gather command")
	selection_manager.set("_last_tap_time", -10.0)
	selection_manager.call("_handle_tap", friendly.global_position, true)
	if gather_targets.size() != 2:
		print("[DEBUG] farm touch diagnostics: %s" % str(selection_manager.get("touch_input_diagnostics")))
	_expect_eq(gather_targets.size(), 2, "friendly active farm also emits a touch gather command")
	if gather_targets.size() == 2:
		_expect_same(gather_targets[0], friendly, "right-click gather targets friendly farm")
		_expect_same(gather_targets[1], friendly, "touch gather targets friendly farm")

	var command_count: int = gather_targets.size()
	selection_manager.set("_last_tap_time", -10.0)
	selection_manager.call("_handle_tap", enemy.global_position, true)
	selection_manager.set("_last_tap_time", -10.0)
	selection_manager.call("_handle_tap", constructing.global_position, true)
	_expect_eq(gather_targets.size(), command_count, "enemy and constructing farms never emit gather commands")
	_expect_same(selection_manager.call("_get_resource_at", friendly.global_position, true), friendly, "friendly farm is touch-discoverable")
	_expect(selection_manager.call("_get_resource_at", enemy.global_position, true) == null, "enemy farm is absent from human resource hit testing")


func _test_harvest_depletion() -> void:
	var farm: Node2D = _make_farm(0, Vector2(600.0, 0.0), BUILDING_ACTIVE)
	farm.set("farm_remaining", 3)
	_expect_eq(farm.call("harvest", 2), 2, "farm returns the requested amount while stocked")
	_expect_eq(farm.get("farm_remaining"), 1, "farm stock decreases exactly")
	_expect_eq(farm.call("harvest", 5), 1, "final harvest is capped to remaining stock")
	_expect_eq(farm.get("farm_remaining"), 0, "farm reaches zero stock")
	_expect_eq(farm.get("state"), BUILDING_DESTROYED, "exhausted farm enters destroyed state immediately")
	_expect(not bool(farm.call("is_harvestable_by", 0)), "exhausted farm cannot be harvested again")
	_expect_eq(farm.call("harvest", 1), 0, "repeated harvest after exhaustion returns zero")


func _test_villager_harvest_and_deposit_loop() -> void:
	var farm: Node2D = _make_farm(0, Vector2(700.0, 0.0), BUILDING_ACTIVE)
	var town_center: Node2D = _town_center_scene.instantiate() as Node2D
	town_center.set("player_owner", 0)
	town_center.global_position = Vector2(716.0, 0.0)
	root.add_child(town_center)
	_fixtures.append(town_center)
	town_center.set("state", BUILDING_ACTIVE)
	town_center.set("hp", town_center.get("max_hp"))

	var villager: Node2D = _villager_scene.instantiate() as Node2D
	villager.set("player_owner", 0)
	villager.global_position = farm.global_position
	root.add_child(villager)
	_fixtures.append(villager)
	villager.set("gather_rate", 5.0)
	villager.set("gather_tick_time", 0.01)
	villager.set("carry_capacity", 5)

	var enemy_farm: Node2D = _make_farm(1, Vector2(704.0, 0.0), BUILDING_ACTIVE)
	villager.call("command_gather", enemy_farm)
	_expect(villager.get("gather_target") == null, "villager rejects a direct enemy-farm gather command")

	var deposits: Array[int] = []
	villager.connect("resource_deposited", func(resource_type: String, amount: int) -> void:
		if resource_type == "food":
			deposits.append(amount)
	)
	villager.call("command_gather", farm)
	villager.set("_gather_offset", Vector2.ZERO)
	villager.call("_process_gathering", 0.02)
	_expect_eq(villager.get("carried_amount"), 5, "villager carries harvested farm food to capacity")
	_expect_same(villager.get("dropoff_target"), town_center, "villager selects a friendly drop-off after harvesting")
	_expect_eq(villager.get("current_state"), UNIT_MOVING, "full villager starts its drop-off trip")

	villager.global_position = town_center.global_position
	villager.call("_on_arrived_for_dropoff", villager)
	_expect_eq(_resource_manager.call("get_resource", 0, "food"), 5, "farm food is deposited into the player economy")
	_expect_eq(villager.get("carried_amount"), 0, "deposit clears carried stock")
	_expect_eq(deposits, [5], "deposit signal reports the farm-food delivery once")
	_expect_same(villager.get("gather_target"), farm, "villager resumes the same live farm after deposit")
	_expect_eq(villager.get("current_state"), UNIT_GATHERING, "villager resumes gathering after deposit")


func _make_natural_resource(type: String, amount: int, position: Vector2) -> Node2D:
	var resource: Node2D = _resource_scene.instantiate() as Node2D
	resource.set("resource_type", type)
	resource.set("total_amount", amount)
	resource.global_position = position
	root.add_child(resource)
	_fixtures.append(resource)
	return resource


func _make_farm(owner: int, position: Vector2, farm_state: int) -> Node2D:
	var farm: Node2D = _farm_scene.instantiate() as Node2D
	farm.set("player_owner", owner)
	farm.global_position = position
	root.add_child(farm)
	_fixtures.append(farm)
	farm.set("state", farm_state)
	farm.set("hp", farm.get("max_hp") if farm_state == BUILDING_ACTIVE else 1)
	return farm


func _finish() -> void:
	for fixture: Node in _fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	current_scene = null
	if _test_world != null and is_instance_valid(_test_world):
		_test_world.free()
	if _resource_manager != null:
		_resource_manager.call("reset")
	if _failures.is_empty():
		print("[PASS] farm_economy: discovery, ownership, input, depletion, and deposit loop")
		quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] farm_economy: %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_same(actual: Object, expected: Object, message: String) -> void:
	if actual != expected:
		_failures.append(message)
