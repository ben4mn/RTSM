extends Node
## Shared fixture for the wildlife regressions: the production GameMap,
## Pathfinding, Villager, BuildingBase, WildlifeNode and WildlifeDirector on a
## fully revealed synthetic grass field, stepped by hand at 30 Hz so a case is
## deterministic and takes no wall time. Not a test case itself.

const STEP: float = 1.0 / 30.0


class OpenField extends "res://scripts/map/game_map.gd":
	func _ready() -> void:
		get_tree().tree_changed.connect(_on_unit_tree_changed)
		terrain_layer.tile_set = TilesetBuilder.build_terrain_tileset()
		set_process(false)
	func is_entity_visible_to_player(_entity: Node2D, _owner: int = 0) -> bool:
		return true
	func is_tile_visible_to_player(_tile: Vector2i, _owner: int = 0) -> bool:
		return true


var world: OpenField
var director: WildlifeDirector
var workers: Array[Villager] = []
var buildings: Array[BuildingBase] = []
var failures: Array[String] = []
var checks: int = 0
var metrics: Dictionary = {}
var _think_clock: float = 0.0


func build_world() -> void:
	AudioManager.set_all_enabled(false)
	ResourceManager.reset()
	for owner: int in 2:
		ResourceManager.initialize_player(owner, {"food": 0, "wood": 0, "gold": 0})
	var scene: Node2D = load("res://scenes/map/game_map.tscn").instantiate()
	scene.set_script(OpenField)
	world = scene as OpenField
	world.map_generator = MapGenerator.new(101)
	world.map_generator.call("_init_grid")
	world.map_generator.spawn_positions.assign([Vector2i(20, 60), Vector2i(60, 20)])
	world.pathfinding = Pathfinding.new(world.map_generator)
	add_child(world)
	director = WildlifeDirector.attach(world)
	director.set_process(false)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and message not in failures:
		failures.append(message)


func building(kind: int, tile: Vector2i, owner: int = 0) -> BuildingBase:
	var node := BuildingBase.new()
	node.building_type = kind
	node.player_owner = owner
	node.position = world.tile_to_world(tile)
	world.get_node("BuildingsContainer").add_child(node)
	node.complete_instantly()
	node.set_process(false)
	world.place_building_obstacle(tile, node.footprint)
	buildings.append(node)
	return node


func worker(tile: Vector2i, owner: int = 0) -> Villager:
	var unit: Villager = load("res://scenes/units/villager.tscn").instantiate()
	unit.player_owner = owner
	unit.position = world.tile_to_world(tile)
	world.get_node("UnitsContainer").add_child(unit)
	unit.set_process(false)
	workers.append(unit)
	return unit


func animal(id: int, kind: String, tile: Vector2i, owner: int = -1) -> WildlifeNode:
	var node: WildlifeNode = director.spawn(id, kind, world.tile_to_world(tile), owner)
	node.set_process(false)
	return node


func berries(tile: Vector2i, amount: int = 200) -> ResourceNode:
	var node := ResourceNode.new()
	node.resource_type = "food"
	node.total_amount = amount
	node.tile_position = tile
	node.position = world.tile_to_world(tile)
	world.get_node("ResourcesContainer").add_child(node)
	world.resource_nodes[tile] = node
	return node


## Advance the whole fixture. `until` may stop it early.
func step(seconds: float, until: Callable = Callable()) -> float:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += STEP
		for unit: Villager in workers:
			if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
				unit._process(STEP)
		for node: WildlifeNode in director.nodes.duplicate():
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node._process(STEP)
		_think_clock += STEP
		director._clock += STEP
		if _think_clock >= WildlifeDirector.THINK_SECONDS:
			_think_clock -= WildlifeDirector.THINK_SECONDS
			director.think(WildlifeDirector.THINK_SECONDS)
		if until.is_valid() and until.call():
			break
	return elapsed


func clear_workers() -> void:
	for unit: Villager in workers:
		if is_instance_valid(unit):
			unit.free()
	workers.clear()


func clear_animals() -> void:
	for node: WildlifeNode in director.nodes.duplicate():
		if is_instance_valid(node):
			director._remove(node)
			node.free()
	director.nodes.clear()
	director.by_id.clear()


func finish(test_name: String) -> void:
	print(JSON.stringify({"test": test_name, "checks": checks, "failures": failures, "metrics": metrics}))
	get_tree().quit(0 if failures.is_empty() else 1)
