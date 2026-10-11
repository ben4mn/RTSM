extends SceneTree
## Shared starting banks, actual source harvest cycles, fractional upgrades and
## deposit accounting. Seeded production liveness is measured by the match probe.

var _failures: Array[String] = []
var _world: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("AudioManager").call("set_all_enabled", false)
	var rm: Node = root.get_node("ResourceManager")
	rm.call("reset")
	for player_id: int in [0, 1]:
		rm.call("initialize_player", player_id)
		_expect(rm.call("get_all_resources", player_id) == {"food": 200, "wood": 150, "gold": 100}, "both players start with the shared 150-wood bank")
	_world = Node2D.new()
	root.add_child(_world)
	current_scene = _world
	var food_worker: Node = _make_worker(0)
	var wood_worker: Node = _make_worker(1)
	var food: Node2D = _make_resource("food", Vector2.ZERO)
	var wood: Node2D = _make_resource("wood", Vector2.ZERO)
	_expect(bool(food_worker.call("command_gather", food)), "food source accepts normal gathering")
	_expect(bool(wood_worker.call("command_gather", wood)), "wood source accepts normal gathering")
	for _tick: int in range(75):
		food_worker.call("_process_gathering", 0.1)
		wood_worker.call("_process_gathering", 0.1)
	_expect(int(food_worker.get("carried_amount")) == 6 and int(wood_worker.get("carried_amount")) == 5, "food earns six units in the time wood earns five")
	_expect(int(food.get("remaining")) == 194 and int(wood.get("remaining")) == 195, "each cargo unit is removed from its finite real source")
	food_worker.set("gather_rate", UnitData.VILLAGER_GATHER_AMOUNT + UnitData.WHEELBARROW_GATHER_BONUS)
	food_worker.set("carried_amount", 0)
	var before_upgrade_stock: int = int(food.get("remaining"))
	var upgrade_yield: int = 0
	for _tick: int in range(4):
		upgrade_yield += int(food_worker.call("_harvest_from_target"))
	_expect(upgrade_yield == 5, "Wheelbarrow's promised 25% bonus produces five actual units over four ticks")
	_expect(before_upgrade_stock - int(food.get("remaining")) == 5, "fractional upgrade harvest is paid by actual source depletion")
	food_worker.set("carried_amount", 9)
	var capped_yield: int = int(food_worker.call("_harvest_from_target"))
	food_worker.set("carried_amount", 9 + capped_yield)
	_expect(capped_yield == 1 and int(food_worker.call("_harvest_from_target")) == 0, "harvest fills the tenth carry slot without exceeding capacity")
	food_worker.set("carried_amount", 0)
	food_worker.set("gather_rate", 1.5)
	food_worker.set("_fractional_harvest", 0.5)
	_expect(bool(food_worker.call("command_gather", wood)), "an empty upgraded worker can change resources")
	_expect(is_zero_approx(float(food_worker.get("_fractional_harvest"))), "partial food work does not become wood after a resource switch")
	var tc: Node = (load("res://scenes/buildings/town_center.tscn") as PackedScene).instantiate()
	tc.set("player_owner", 0)
	_world.add_child(tc)
	tc.call("complete_instantly")
	tc.set_process(false)
	food_worker.set("carried_resource_type", "wood")
	food_worker.set("carried_amount", 7)
	_expect(bool(food_worker.call("command_return_resources")), "partial cargo receives a normal real drop-off order")
	food_worker.set("global_position", tc.get("global_position"))
	food_worker.call("_on_arrived_for_dropoff", food_worker)
	_expect(int(rm.call("get_resource", 0, "wood")) == 157 and int(food_worker.get("carried_amount")) == 0, "a real friendly Town Center deposits exact cargo into the lower starting bank")
	_world.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] economy_balance: equal lower wood, faster finite food, effective fractional upgrades, capped cargo and real deposits")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] economy_balance: %s" % failure)
		quit(1)


func _make_worker(player_id: int) -> Node:
	var worker: Node = (load("res://scenes/units/villager.tscn") as PackedScene).instantiate()
	worker.set("player_owner", player_id)
	_world.add_child(worker)
	worker.set_process(false)
	return worker


func _make_resource(resource_type: String, position: Vector2) -> Node2D:
	var resource: Node2D = (load("res://scenes/map/resource_node.tscn") as PackedScene).instantiate()
	resource.set("resource_type", resource_type)
	resource.set("total_amount", 200)
	resource.position = position
	_world.add_child(resource)
	return resource


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
