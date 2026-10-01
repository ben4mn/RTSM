extends Node
## Regression for fog-legal automatic resource discovery and villager assignment.

const GAME_MAP_SCENE: PackedScene = preload("res://scenes/map/game_map.tscn")
const RESOURCE_SCENE: PackedScene = preload("res://scenes/map/resource_node.tscn")
const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const MAIN_SCRIPT: Script = preload("res://scripts/main/main.gd")
const AI_CONTROLLER_SCRIPT: Script = preload("res://scripts/ai/ai_controller.gd")

const PLAYER_HUMAN := 0
const TEST_RESOURCE_TYPE := "food"

var _failures: Array[String] = []


class VisibilityProbeResource extends Node2D:
	var resource_type_calls: int = 0
	var harvestable_calls: int = 0
	var harvest_calls: int = 0

	func get_resource_type() -> String:
		resource_type_calls += 1
		return TEST_RESOURCE_TYPE

	func is_harvestable_by(_player_id: int = -1) -> bool:
		harvestable_calls += 1
		return true

	func harvest(amount: int) -> int:
		harvest_calls += 1
		return amount


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var game_map: Node2D = GAME_MAP_SCENE.instantiate() as Node2D
	game_map.set("map_seed", 424242)
	add_child(game_map)
	await get_tree().process_frame
	game_map.set_process(false)
	var fog: FogManager = game_map.get_node("FogOfWar") as FogManager
	fog.set_process(false)

	var registry: Dictionary = game_map.get("resource_nodes") as Dictionary
	registry.clear()
	var additional: Array = game_map.get("_additional_resource_nodes") as Array
	additional.clear()

	var origin_tile: Vector2i = game_map.get("map_generator").spawn_positions[0]
	var hidden_tile: Vector2i = _find_reachable_tile(game_map, origin_tile, 1, [])
	var visible_tile: Vector2i = _find_reachable_tile(game_map, origin_tile, 4, [hidden_tile])
	var probe_tile: Vector2i = _find_reachable_tile(game_map, origin_tile, 1, [hidden_tile, visible_tile])
	_expect(hidden_tile != Vector2i(-1, -1), "found a near reachable hidden resource tile")
	_expect(visible_tile != Vector2i(-1, -1), "found a farther reachable visible resource tile")
	_expect(probe_tile != Vector2i(-1, -1), "found a near hidden visibility-probe tile")
	if (
		hidden_tile == Vector2i(-1, -1)
		or visible_tile == Vector2i(-1, -1)
		or probe_tile == Vector2i(-1, -1)
	):
		game_map.free()
		_finish()
		return

	var hidden_resource: ResourceNode = _spawn_resource(game_map, hidden_tile)
	var visible_resource: ResourceNode = _spawn_resource(game_map, visible_tile)
	registry[hidden_tile] = hidden_resource
	registry[visible_tile] = visible_resource
	var visibility_probe := VisibilityProbeResource.new()
	visibility_probe.global_position = game_map.call("tile_to_world", probe_tile) as Vector2
	game_map.get_node("ResourcesContainer").add_child(visibility_probe)
	registry[probe_tile] = visibility_probe
	_expect(not bool(game_map.call("is_tile_buildable", visible_tile)), "live natural resource tile rejects structure placement")
	var sacred_tile: Vector2i = game_map.call("world_to_tile", game_map.get("sacred_site").global_position) as Vector2i
	_expect(not bool(game_map.call("is_tile_buildable", sacred_tile)), "Sacred Site tile rejects structure placement")
	_set_fog_state(fog, hidden_tile, MapData.FogState.UNEXPLORED)
	_set_fog_state(fog, visible_tile, MapData.FogState.VISIBLE)
	_set_fog_state(fog, probe_tile, MapData.FogState.UNEXPLORED)
	game_map.call("update_resource_visibility_for_player", PLAYER_HUMAN)
	_expect(not hidden_resource.visible, "unexplored natural resource visual is hidden")
	_expect(visible_resource.visible, "currently visible natural resource visual is shown")

	var origin_world: Vector2 = game_map.call("tile_to_world", origin_tile) as Vector2
	_expect_same(
		game_map.call("get_nearest_resource_node", TEST_RESOURCE_TYPE, origin_world, PLAYER_HUMAN),
		visible_resource,
		"nearest lookup ignores a closer unexplored resource"
	)
	_expect_same(
		game_map.call("get_nearest_reachable_resource_node", TEST_RESOURCE_TYPE, origin_world, PLAYER_HUMAN, {}),
		visible_resource,
		"reachable retarget ignores a closer unexplored resource"
	)
	_expect_same_value(visibility_probe.resource_type_calls, 0, "hidden lookup never reads candidate resource type")
	_expect_same_value(visibility_probe.harvestable_calls, 0, "hidden lookup never reads candidate harvestability")
	_expect_same_value(visibility_probe.harvest_calls, 0, "hidden lookup never invokes candidate harvest")
	_set_fog_state(fog, probe_tile, MapData.FogState.VISIBLE)
	_expect_same(
		game_map.call("get_nearest_resource_node", TEST_RESOURCE_TYPE, origin_world, PLAYER_HUMAN),
		visibility_probe,
		"visibility-probe resource becomes queryable only after reveal"
	)
	_expect(visibility_probe.resource_type_calls > 0, "revealed lookup validates candidate resource type")
	_expect(visibility_probe.harvestable_calls > 0, "revealed lookup validates candidate harvestability")
	_expect_same_value(visibility_probe.harvest_calls, 0, "resource discovery never harvests a candidate")
	registry.erase(probe_tile)
	visibility_probe.queue_free()
	_set_fog_state(fog, probe_tile, MapData.FogState.UNEXPLORED)

	_set_fog_state(fog, hidden_tile, MapData.FogState.EXPLORED)
	game_map.call("update_resource_visibility_for_player", PLAYER_HUMAN)
	_expect(not hidden_resource.visible, "explored-only natural resource visual remains hidden")
	_expect_same(
		game_map.call("get_nearest_resource_node", TEST_RESOURCE_TYPE, origin_world, PLAYER_HUMAN),
		visible_resource,
		"automatic lookup does not use stale explored-only resource knowledge"
	)
	_expect_same(
		game_map.call("get_nearest_resource_node", TEST_RESOURCE_TYPE, origin_world, -1),
		hidden_resource,
		"explicit negative-player discovery remains available to debug callers"
	)

	var villager: Villager = VILLAGER_SCENE.instantiate() as Villager
	villager.player_owner = PLAYER_HUMAN
	villager.global_position = origin_world
	game_map.get_node("UnitsContainer").add_child(villager)
	villager.carried_resource_type = TEST_RESOURCE_TYPE
	_expect(bool(villager.call("_try_retarget_resource")), "depleted-target recovery found a visible replacement")
	_expect_same(villager.gather_target, visible_resource, "villager retarget never selects hidden map knowledge")
	await _test_hidden_gather_target_state(
		game_map,
		fog,
		villager,
		origin_tile,
		hidden_tile,
		hidden_resource,
		visible_resource,
		registry
	)
	await _test_depleted_terrain_memory(game_map, fog, origin_tile, hidden_tile, visible_tile, registry)

	villager.gather_target = null
	villager.set_state(UnitBase.State.IDLE)
	var main_controller: Node2D = MAIN_SCRIPT.new() as Node2D
	main_controller.set("game_map", game_map)
	main_controller.call("_auto_assign_starting_villagers", [villager])
	_expect_same(villager.gather_target, visible_resource, "starting-villager assignment uses visible resources only")

	villager.gather_target = null
	villager.set_state(UnitBase.State.IDLE)
	ResourceManager.reset()
	ResourceManager.initialize_player(PLAYER_HUMAN, {"food": 0, "wood": 100, "gold": 100})
	main_controller.call("_auto_assign_new_villager", villager)
	_expect_same(villager.gather_target, visible_resource, "new-villager assignment uses visible resources only")

	_set_fog_state(fog, hidden_tile, MapData.FogState.VISIBLE)
	_expect_same(
		game_map.call("get_nearest_resource_node", TEST_RESOURCE_TYPE, origin_world, PLAYER_HUMAN),
		hidden_resource,
		"a nearer resource becomes eligible immediately after entering current vision"
	)
	_test_ai_resource_camp_visibility(game_map, fog, origin_tile)

	main_controller.free()
	game_map.free()
	ResourceManager.reset()
	_finish()


func _test_hidden_gather_target_state(
	game_map: Node2D,
	fog: FogManager,
	villager: Villager,
	origin_tile: Vector2i,
	hidden_tile: Vector2i,
	hidden_resource: ResourceNode,
	visible_resource: ResourceNode,
	registry: Dictionary
) -> void:
	# Depletion while hidden must not become a live simulation input. The unit
	# keeps moving toward its last-known coordinate and validates only on reveal.
	_set_fog_state(fog, hidden_tile, MapData.FogState.VISIBLE)
	game_map.call("update_resource_visibility_for_player", PLAYER_HUMAN)
	_expect(bool(villager.call("command_gather", hidden_resource)), "visible resource accepts a gather order")
	villager.set("_gather_offset", Vector2.ZERO)
	var remembered_position: Vector2 = villager.get("_gather_last_known_position") as Vector2
	_set_fog_state(fog, hidden_tile, MapData.FogState.EXPLORED)
	game_map.call("update_resource_visibility_for_player", PLAYER_HUMAN)
	hidden_resource.remaining = 0
	villager.call("_process_gathering", 0.1)
	_expect_same(villager.gather_target, hidden_resource, "hidden depletion does not abandon the remembered target")
	_expect_same_value(
		villager.current_state,
		UnitBase.State.GATHERING,
		"hidden depletion does not trigger an observable retarget state change"
	)
	_expect_same_value(
		villager.get("_gather_last_known_position"),
		remembered_position,
		"hidden depletion preserves the last-known target coordinate"
	)
	_expect(not hidden_resource.visible, "hidden depletion cannot reveal a live resource visual update")
	_set_fog_state(fog, hidden_tile, MapData.FogState.VISIBLE)
	villager.call("_process_gathering", 0.1)
	_expect_same(villager.gather_target, visible_resource, "visible depletion triggers a legal visible retarget")
	hidden_resource.remaining = hidden_resource.total_amount
	_set_fog_state(fog, hidden_tile, MapData.FogState.EXPLORED)
	game_map.call("update_resource_visibility_for_player", PLAYER_HUMAN)

	# Freed targets follow the same rule: the invalid reference is not inspected
	# until the last-known tile re-enters current vision.
	var removal_tile: Vector2i = _find_reachable_tile(
		game_map,
		origin_tile,
		2,
		[hidden_tile, visible_resource.tile_position]
	)
	_expect(removal_tile != Vector2i(-1, -1), "found a reachable hidden-removal fixture tile")
	if removal_tile == Vector2i(-1, -1):
		return
	var removed_resource: ResourceNode = _spawn_resource(game_map, removal_tile)
	registry[removal_tile] = removed_resource
	_set_fog_state(fog, removal_tile, MapData.FogState.VISIBLE)
	_expect(bool(villager.call("command_gather", removed_resource)), "visible removal fixture accepts a gather order")
	villager.set("_gather_offset", Vector2.ZERO)
	var removed_position: Vector2 = removed_resource.global_position
	_set_fog_state(fog, removal_tile, MapData.FogState.EXPLORED)
	game_map.call("update_resource_visibility_for_player", PLAYER_HUMAN)
	_expect(not removed_resource.visible, "resource visual hides before off-screen removal")
	registry.erase(removal_tile)
	removed_resource.queue_free()
	await get_tree().process_frame
	villager.call("_process_gathering", 0.1)
	_expect_same_value(
		villager.current_state,
		UnitBase.State.GATHERING,
		"hidden removal does not trigger an observable retarget state change"
	)
	_expect_same_value(
		villager.get("_gather_last_known_position"),
		removed_position,
		"hidden removal preserves the last-known target coordinate"
	)
	_set_fog_state(fog, removal_tile, MapData.FogState.VISIBLE)
	villager.call("_process_gathering", 0.1)
	_expect_same_value(
		villager.current_state,
		UnitBase.State.IDLE,
		"revealing a removed explicit target ends that exact order safely"
	)
	_expect_same(villager.gather_target, null, "removed explicit target cannot redirect to a different visible identity")


func _test_depleted_terrain_memory(
	game_map: Node2D,
	fog: FogManager,
	origin_tile: Vector2i,
	hidden_tile: Vector2i,
	visible_tile: Vector2i,
	registry: Dictionary
) -> void:
	var depletion_tile: Vector2i = _find_reachable_tile(
		game_map,
		origin_tile,
		3,
		[hidden_tile, visible_tile]
	)
	_expect(depletion_tile != Vector2i(-1, -1), "found a reachable real-depletion fixture tile")
	if depletion_tile == Vector2i(-1, -1):
		return
	var generator: MapGenerator = game_map.get("map_generator") as MapGenerator
	var navigation: Pathfinding = game_map.get("pathfinding") as Pathfinding
	var terrain: TileMapLayer = game_map.get_node("TerrainLayer") as TileMapLayer
	generator.grid[depletion_tile.y][depletion_tile.x] = MapData.TileType.BERRY_BUSH
	navigation.update_tile(depletion_tile, MapData.TileType.BERRY_BUSH)
	terrain.set_cell(depletion_tile, 0, Vector2i(MapData.TileType.BERRY_BUSH, 0))
	var resource: ResourceNode = _spawn_resource(game_map, depletion_tile)
	registry[depletion_tile] = resource
	resource.depleted.connect(func(depleted_node: ResourceNode) -> void:
		game_map.call("_on_resource_depleted", depleted_node, depletion_tile)
	)
	_set_fog_state(fog, depletion_tile, MapData.FogState.EXPLORED)
	game_map.call("update_resource_visibility_for_player", PLAYER_HUMAN)
	_expect(not resource.visible, "real depletion fixture is hidden before harvest")
	var harvested: int = resource.harvest(resource.remaining)
	_expect(harvested == resource.total_amount, "real harvest drains the complete natural resource")
	_expect(not registry.has(depletion_tile), "depleted signal synchronously erases the resource registry entry")
	_expect_same_value(
		generator.grid[depletion_tile.y][depletion_tile.x],
		MapData.TileType.GRASS,
		"depletion immediately removes exhausted terrain from simulation planning"
	)
	_expect_same_value(
		terrain.get_cell_atlas_coords(depletion_tile),
		Vector2i(MapData.TileType.BERRY_BUSH, 0),
		"explored-only terrain retains the last visible resource appearance"
	)
	var hidden_minimap_grid: Array = game_map.call(
		"get_minimap_grid_for_player", PLAYER_HUMAN
	) as Array
	_expect_same_value(
		hidden_minimap_grid[depletion_tile.y][depletion_tile.x],
		MapData.TileType.BERRY_BUSH,
		"explored-only minimap retains the last visible resource terrain"
	)
	_set_fog_state(fog, depletion_tile, MapData.FogState.VISIBLE)
	game_map.call("update_resource_visibility_for_player", PLAYER_HUMAN)
	_expect_same_value(
		terrain.get_cell_atlas_coords(depletion_tile),
		Vector2i(MapData.TileType.GRASS, 0),
		"revealing the depleted tile updates its terrain to grass"
	)
	var revealed_minimap_grid: Array = game_map.call(
		"get_minimap_grid_for_player", PLAYER_HUMAN
	) as Array
	_expect_same_value(
		revealed_minimap_grid[depletion_tile.y][depletion_tile.x],
		MapData.TileType.GRASS,
		"revealing the depleted tile updates minimap terrain to grass"
	)
	await get_tree().create_timer(0.6).timeout
	_expect(not is_instance_valid(resource), "real depletion fade completes with queue_free")


func _test_ai_resource_camp_visibility(
	game_map: Node2D,
	fog: FogManager,
	base_tile: Vector2i
) -> void:
	var generator: MapGenerator = game_map.get("map_generator") as MapGenerator
	var navigation: Pathfinding = game_map.get("pathfinding") as Pathfinding
	var footprint := Vector2i(2, 2)
	var sites: Array[Dictionary] = _find_clear_resource_sites(generator, navigation, base_tile, footprint)
	_expect(sites.size() >= 2, "fixture found two clear resource-camp sites")
	if sites.size() < 2:
		return
	var hidden_site: Dictionary = sites[0]
	var visible_site: Dictionary = sites[1]
	var hidden_resource_tile: Vector2i = hidden_site["resource"]
	var visible_resource_tile: Vector2i = visible_site["resource"]
	var hidden_candidate: Vector2i = hidden_site["candidate"]
	var visible_candidate: Vector2i = visible_site["candidate"]

	for y in range(MapData.MAP_HEIGHT):
		for x in range(MapData.MAP_WIDTH):
			if generator.grid[y][x] == MapData.TileType.BERRY_BUSH:
				generator.grid[y][x] = MapData.TileType.GRASS
	generator.grid[hidden_resource_tile.y][hidden_resource_tile.x] = MapData.TileType.BERRY_BUSH
	generator.grid[visible_resource_tile.y][visible_resource_tile.x] = MapData.TileType.BERRY_BUSH
	_set_fog_state(fog, hidden_resource_tile, MapData.FogState.EXPLORED)
	_set_footprint_fog(fog, hidden_candidate, footprint, MapData.FogState.VISIBLE)
	_set_fog_state(fog, hidden_resource_tile, MapData.FogState.EXPLORED)
	_set_fog_state(fog, visible_resource_tile, MapData.FogState.VISIBLE)
	_set_footprint_fog(fog, visible_candidate, footprint, MapData.FogState.VISIBLE)

	var ai: AIController = AI_CONTROLLER_SCRIPT.new() as AIController
	ai.player_id = PLAYER_HUMAN
	ai.game_map = game_map
	ai.map_generator = generator
	ai.pathfinding = navigation
	ai.set("_base_tile", base_tile)
	_expect_same_value(
		ai.call("_find_build_near_resource", MapData.TileType.BERRY_BUSH, footprint),
		visible_candidate,
		"AI camp search skips the nearer explored-only resource"
	)

	_set_fog_state(fog, visible_resource_tile, MapData.FogState.EXPLORED)
	_expect_same_value(
		ai.call("_find_build_near_resource", MapData.TileType.BERRY_BUSH, footprint),
		Vector2i(-1, -1),
		"AI camp search finds no site when every resource is outside current vision"
	)
	_set_fog_state(fog, hidden_resource_tile, MapData.FogState.VISIBLE)
	_expect_same_value(
		ai.call("_find_build_near_resource", MapData.TileType.BERRY_BUSH, footprint),
		hidden_candidate,
		"AI camp search admits the nearer site once the resource is currently visible"
	)
	ai.free()


func _find_clear_resource_sites(
	generator: MapGenerator,
	navigation: Pathfinding,
	base_tile: Vector2i,
	footprint: Vector2i
) -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	for y in range(1, MapData.MAP_HEIGHT - footprint.y - 1):
		for x in range(1, MapData.MAP_WIDTH - footprint.x - 2):
			var resource_tile := Vector2i(x, y)
			var candidate := resource_tile + Vector2i(1, 0)
			var clear := true
			for dy in range(footprint.y):
				for dx in range(footprint.x):
					var tile := candidate + Vector2i(dx, dy)
					if (
						not MapData.is_grass(generator.grid[tile.y][tile.x] as MapData.TileType)
						or not navigation.is_walkable(tile)
					):
						clear = false
			if clear:
				sites.append({
					"resource": resource_tile,
					"candidate": candidate,
					"distance": base_tile.distance_squared_to(candidate),
				})
	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)
	if sites.size() < 2:
		return sites
	var near_site: Dictionary = sites[0]
	for candidate_site: Dictionary in sites:
		var near_resource: Vector2i = near_site["resource"]
		var candidate_resource: Vector2i = candidate_site["resource"]
		if (
			int(candidate_site["distance"]) > int(near_site["distance"])
			and (
				absi(candidate_resource.x - near_resource.x) >= 5
				or absi(candidate_resource.y - near_resource.y) >= 5
			)
		):
			return [near_site, candidate_site]
	return sites.slice(0, 2)


func _set_footprint_fog(
	fog: FogManager,
	origin: Vector2i,
	footprint: Vector2i,
	state: MapData.FogState
) -> void:
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			_set_fog_state(fog, origin + Vector2i(dx, dy), state)


func _find_reachable_tile(
	game_map: Node2D,
	origin_tile: Vector2i,
	minimum_tile_distance: int,
	excluded: Array[Vector2i]
) -> Vector2i:
	var origin_world: Vector2 = game_map.call("tile_to_world", origin_tile) as Vector2
	for radius in range(minimum_tile_distance, 13):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := origin_tile + Vector2i(dx, dy)
				if tile in excluded or not _tile_in_bounds(tile):
					continue
				if not bool(game_map.call("is_tile_walkable", tile)):
					continue
				var target_world: Vector2 = game_map.call("tile_to_world", tile) as Vector2
				var route: PackedVector2Array = game_map.call(
					"get_navigation_world_path", origin_world, target_world, 36.0
				) as PackedVector2Array
				if not route.is_empty() and route[route.size() - 1].distance_to(target_world) <= 44.0:
					return tile
	return Vector2i(-1, -1)


func _spawn_resource(game_map: Node2D, tile: Vector2i) -> ResourceNode:
	var resource: ResourceNode = RESOURCE_SCENE.instantiate() as ResourceNode
	resource.resource_type = TEST_RESOURCE_TYPE
	resource.total_amount = 200
	resource.tile_position = tile
	resource.global_position = game_map.call("tile_to_world", tile) as Vector2
	game_map.get_node("ResourcesContainer").add_child(resource)
	return resource


func _set_fog_state(fog: FogManager, tile: Vector2i, state: MapData.FogState) -> void:
	fog.fog_grid[tile.y][tile.x] = state


func _tile_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < MapData.MAP_WIDTH and tile.y >= 0 and tile.y < MapData.MAP_HEIGHT


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_same(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(message)


func _expect_same_value(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] resource_fog_targeting: automatic resource discovery obeys current player vision")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] resource_fog_targeting: %s" % failure)
	get_tree().quit(1)
