extends Node
## Production GameMap/navigation plus real Villager/Resource/Building scenes.
## The small arena, threats, and damage are explicit diagnostic fixtures. Worker
## movement, harvesting, cargo deposit and building progress use runtime methods.

const MAP_SCENE: PackedScene = preload("res://scenes/map/game_map.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/villager.tscn")
const TC_SCENE: PackedScene = preload("res://scenes/buildings/town_center.tscn")
const HOUSE_SCENE: PackedScene = preload("res://scenes/buildings/house.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")
var _failures: Array[String] = []
var _map: Node2D
var _worker: Villager
var _wood: ResourceNode
var _gold: ResourceNode
var _tc: BuildingBase
var _deposits: Dictionary = {}
var _case_name: String = ""

class ObservedResource extends ResourceNode:
	var hidden_for_test: bool = false
	var hidden_queries: int = 0
	func get_resource_type() -> String:
		if hidden_for_test:
			hidden_queries += 1
		return super.get_resource_type()
	func is_harvestable_by(player_id: int = -1) -> bool:
		if hidden_for_test:
			hidden_queries += 1
		return super.is_harvestable_by(player_id)
	func harvest(amount: int) -> int:
		if hidden_for_test:
			hidden_queries += 1
		return super.harvest(amount)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_tree().current_scene = null
	for name: String in ["gather", "delivery", "partial", "cross_type", "builder", "stop", "move", "retask", "manual_damage", "idle_loaded", "visible_threat", "hidden_threat", "hidden_resource", "destroyed_refuge", "safe_alternate", "safe_pending", "dead"]:
		_case_name = name
		await _fixture()
		_test_case(name)
		_map.free()
		await get_tree().process_frame
	if _failures.is_empty():
		print("[PASS] worker_raid_recovery: 17 production-navigation cases; gather/build/delivery/cross-type resume, cargo conservation, visibility, destroyed refuge and explicit commands")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] worker_raid_recovery: " + failure)
		get_tree().quit(1)

func _fixture() -> void:
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	_map = MAP_SCENE.instantiate() as Node2D
	_map.map_seed = 424242
	add_child(_map)
	await get_tree().process_frame
	_map.set_process(false)
	var fog: FogManager = _map.get_node("FogOfWar") as FogManager
	fog.set_process(false)
	for resource: Node in _map.get_node("ResourcesContainer").get_children():
		resource.free()
	_map.resource_nodes.clear()
	_map._additional_resource_nodes.clear()
	for y: int in range(MapData.MAP_HEIGHT):
		for x: int in range(MapData.MAP_WIDTH):
			_map.pathfinding.set_solid(Vector2i(x, y), false)
			fog.fog_grid[y][x] = MapData.FogState.VISIBLE
	_tc = TC_SCENE.instantiate() as BuildingBase
	_tc.player_owner = 0
	_tc.global_position = _map.tile_to_world(Vector2i(10, 10))
	_map.get_node("BuildingsContainer").add_child(_tc)
	_tc.complete_instantly()
	_tc.set_process(false)
	for dy: int in range(_tc.footprint.y):
		for dx: int in range(_tc.footprint.x):
			_map.pathfinding.set_solid(Vector2i(10, 10) + Vector2i(dx, dy), true)
	_wood = _resource("wood", Vector2i(12, 19))
	_gold = _resource("gold", Vector2i(18, 19))
	_worker = WORKER_SCENE.instantiate() as Villager
	_worker.player_owner = 0
	_worker.global_position = _map.tile_to_world(Vector2i(12, 18))
	_map.get_node("UnitsContainer").add_child(_worker)
	_worker.set_process(false)
	_deposits = {"food": 0, "wood": 0, "gold": 0}
	_worker.resource_deposited.connect(func(kind: String, amount: int) -> void:
		_deposits[kind] = int(_deposits[kind]) + amount
	)

func _resource(kind: String, tile: Vector2i) -> ResourceNode:
	var resource := ObservedResource.new()
	resource.resource_type = kind
	resource.total_amount = 1000
	resource.tile_position = tile
	resource.global_position = _map.tile_to_world(tile)
	_map.get_node("ResourcesContainer").add_child(resource)
	resource.set_process(false)
	_map.resource_nodes[tile] = resource
	return resource

func _enemy(tile: Vector2i) -> UnitBase:
	var enemy := ENEMY_SCENE.instantiate() as UnitBase
	enemy.player_owner = 1
	enemy.global_position = _map.tile_to_world(tile)
	_map.get_node("UnitsContainer").add_child(enemy)
	enemy.set_process(false)
	return enemy

func _step(seconds: float) -> void:
	for tick: int in range(ceili(seconds * 60.0)):
		_worker._process(1.0 / 60.0)

func _until(predicate: Callable, seconds: float) -> bool:
	for tick: int in range(ceili(seconds * 60.0)):
		if predicate.call():
			return true
		_worker._process(1.0 / 60.0)
	return bool(predicate.call())

func _test_case(name: String) -> void:
	if name == "dead":
		_worker.command_gather(_wood)
		_worker.take_damage(_worker.hp)
		_expect(_worker.get_economy_task() == "" and not _worker.has_active_gather_order() and _worker.get_work_status() == "Dead", "dead worker remained employed")
		return
	if name == "manual_damage":
		_worker.command_gather(_wood)
		_worker.command_move(_map.tile_to_world(Vector2i(18, 18)))
		var destination: Vector2 = _worker.move_target
		_worker.take_damage(1.0)
		_expect(not _worker.is_auto_recovering() and _worker.move_target == destination, "damage overrode explicit Move")
		_expect(_worker.get_economy_task() == "" and _worker.get_work_status() == "Moving", "manual Move was labeled employed")
		return
	if name == "idle_loaded":
		_worker.command_gather(_wood)
		_expect(_until(func() -> bool: return _worker.carried_amount >= 4, 20.0), "real partial harvest failed")
		var cargo: int = _worker.carried_amount
		_worker.command_stop()
		_worker.take_damage(1.0)
		_expect(_until(func() -> bool: return int(_deposits["wood"]) == cargo, 45.0), "idle cargo never returned")
		_step(8.0)
		_expect(_worker.current_state == UnitBase.State.IDLE and _worker.carried_amount == 0, "idle cargo recovery invented a gather order")
		return
	_expect(_worker.command_gather(_wood), "wood gather command rejected")
	if name in ["delivery", "partial", "cross_type", "builder", "safe_alternate", "safe_pending"]:
		var full: bool = name == "delivery"
		_expect(_until(func() -> bool: return _worker.is_returning_resources() if full else _worker.carried_amount >= 4, 30.0), "natural harvest/delivery setup failed")
	var cargo_before: int = _worker.carried_amount
	var stock_before: int = _wood.remaining
	var house: BuildingBase = null
	if name == "builder":
		house = HOUSE_SCENE.instantiate() as BuildingBase
		house.player_owner = 0
		house.global_position = _map.tile_to_world(Vector2i(15, 19))
		_map.get_node("BuildingsContainer").add_child(house)
		house.start_construction()
		house.set_process(false)
		_worker.command_build(house)
		_expect(_until(func() -> bool: return house.build_progress > 0.05, 15.0), "real building progress never started")
	if name in ["cross_type", "safe_pending"]:
		_expect(_worker.command_gather(_gold), "loaded cross-type command rejected")
		_expect(_worker.carried_resource_type == "wood", "cross-type setup relabeled cargo")
		_expect(_worker.get_economy_task() == "gold" and _worker.get_work_status() == "Returning wood", "pending accepted job/count and actual cargo action were conflated")
	_worker.take_damage(1.0)
	_expect(_worker.is_auto_recovering(), "economic damage did not start recovery")
	_expect(_worker.get_economy_task() == "" and _worker.get_work_status() == "Retreating", "retreating cargo was labeled employed")
	_expect(_worker.carried_amount == cargo_before and _worker.carried_resource_type == "wood", "damage lost/retyped cargo")
	if name in ["safe_alternate", "safe_pending"]:
		var requested: String = "gold" if name == "safe_pending" else "wood"
		var camp_tile: Vector2i = Vector2i(18, 19) if name == "safe_pending" else Vector2i(12, 19)
		var camper: UnitBase = _enemy(camp_tile)
		var alternate: ResourceNode = _resource(requested, Vector2i(7, 11))
		_expect(_until(func() -> bool: return _worker.gather_target == alternate and not _worker.is_auto_recovering() and _worker.current_state == UnitBase.State.GATHERING, 35.0), "persistent camper froze economy despite a reachable visible safe same-type job")
		_expect(_wood.remaining == stock_before, "safe fallback returned to the original raided resource")
		_expect(int(_deposits["wood"]) == cargo_before and ResourceManager.get_resource(0, "wood") == cargo_before, "safe fallback lost/duplicated original cargo")
		_expect(_worker.get_economy_task() == requested, "safe fallback changed accepted resource kind")
		_expect(_until(func() -> bool: return _worker.carried_amount > 0, 20.0), "safe alternate produced no real harvest")
		print("RECOVERY_SAFE_ALTERNATE ", JSON.stringify({"case":name,"cargo_before":cargo_before,"wood_deposited":_deposits["wood"],"task":_worker.get_economy_task(),"camper_alive":camper.hp > 0,"safe_target":_worker.gather_target == alternate}))
		return
	if name in ["stop", "move", "retask"]:
		if name == "stop":
			_worker.command_stop()
		elif name == "move":
			_worker.command_move(_map.tile_to_world(Vector2i(18, 18)))
		else:
			_worker.command_gather(_gold)
		_expect(not _worker.is_auto_recovering(), "new command failed to cancel recovery")
		_step(20.0)
		if name == "retask":
			_expect(_worker.gather_target == _gold and _worker.carried_resource_type == "gold", "new gather order lost to old recovery")
		else:
			_expect(_worker.current_state == UnitBase.State.IDLE and _worker.carried_amount == 0, "new Stop/Move resumed canceled work")
		return
	if name == "visible_threat" or name == "hidden_threat":
		var enemy: UnitBase = _enemy(Vector2i(12, 19))
		if name == "hidden_threat":
			(_map.get_node("FogOfWar") as FogManager).fog_grid[19][12] = MapData.FogState.EXPLORED
		_expect(_until(func() -> bool: return _worker.get_work_status() == "Sheltering", 20.0), "worker never reached refuge")
		_step(10.0)
		if name == "visible_threat":
			_expect(_worker.is_auto_recovering() and _wood.remaining == stock_before, "worker re-entered a visibly raided job")
		else:
			_expect(not _worker.is_auto_recovering(), "hidden enemy influenced clear-area recovery")
		enemy.free()
		(_map.get_node("FogOfWar") as FogManager).fog_grid[19][12] = MapData.FogState.VISIBLE
	if name == "hidden_resource":
		(_map.get_node("FogOfWar") as FogManager).fog_grid[19][12] = MapData.FogState.EXPLORED
		(_wood as ObservedResource).hidden_for_test = true
		_step(20.0)
		_expect((_wood as ObservedResource).hidden_queries == 0, "recovery queried hidden harvestability/type/stock")
		_expect(not _worker.is_auto_recovering() and _worker.current_state == UnitBase.State.GATHERING, "hidden remembered job could not resume its legal approach")
		(_wood as ObservedResource).hidden_for_test = false
		(_map.get_node("FogOfWar") as FogManager).fog_grid[19][12] = MapData.FogState.VISIBLE
	if name == "destroyed_refuge":
		_expect(_until(func() -> bool: return _worker.get_work_status() == "Sheltering", 20.0), "worker never reached refuge")
		_tc.free()
		_step(8.0)
		_expect(not _worker.is_auto_recovering(), "destroyed refuge left recovery stuck")
	if name == "builder":
		var progress: float = house.build_progress
		_step(2.0)
		_expect(is_equal_approx(house.build_progress, progress), "worker constructed remotely during retreat")
		_expect(_until(func() -> bool: return house.state == BuildingBase.State.ACTIVE, 50.0), "evacuated foundation did not finish after clear-area return")
		_expect(_worker.gather_target == _wood, "builder failed to restore exact previous resource job")
		_expect(_worker.carried_amount + int(_deposits["wood"]) == cargo_before, "builder recovery lost/duplicated cargo")
	elif name == "cross_type":
		_expect(_until(func() -> bool: return _worker.gather_target == _gold, 50.0), "pending gold order did not activate")
		_expect(int(_deposits["wood"]) == cargo_before and ResourceManager.get_resource(0, "wood") == cargo_before, "original wood cargo was not delivered exactly once")
		_expect(_worker.carried_resource_type == "gold", "gold gather did not follow wood delivery")
	else:
		_expect(_until(func() -> bool: return _worker.current_state == UnitBase.State.GATHERING and not _worker.is_auto_recovering(), 50.0), "old gather order never resumed")
		_expect(_worker.gather_target == _wood, "recovery replaced the exact accepted resource")
		if cargo_before > 0:
			_expect(int(_deposits["wood"]) == cargo_before, "interrupted cargo did not deposit exactly once before resume")
		_expect(_until(func() -> bool: return _worker.carried_amount > 0, 20.0), "resumed gather produced no real harvest")
	print("RECOVERY_CASE ", JSON.stringify({"case": name, "cargo_before": cargo_before, "wood_deposited": _deposits["wood"], "state": _worker.current_state, "status": _worker.get_work_status()}))

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(_case_name + ": " + message)
