extends Node
## Paid repeat production must recover after resources or population room return.

const TOWN_CENTER_SCENE := preload("res://scenes/buildings/town_center.tscn")
const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const SCOUT := UnitData.UnitType.SCOUT
const VILLAGER := UnitData.UnitType.VILLAGER

@onready var root: Window = get_tree().root

var _failures: Array[String] = []
var _game_manager: Node
var _resource_manager: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_game_manager = root.get_node("GameManager")
	_resource_manager = root.get_node("ResourceManager")
	root.get_node("AudioManager").call("set_all_enabled", false)
	_test_resource_recovery_and_off()
	_test_clear_waiting_repeat()
	_test_clear_partial_queue_and_reenable()
	_test_housing_and_free_population()
	_test_inactive_and_destroyed_buildings()
	await _test_main_recovery_and_pause()
	if _failures.is_empty():
		print("[PASS] repeat_production: bounded paid recovery; Clear stops active/waiting Repeat and refunds; re-enable and individual cancellation remain deliberate; real Main/HUD immediately shows OFF; pause/inactive/destroyed states do not spend")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] repeat_production: %s" % failure)
		get_tree().quit(1)


func _test_resource_recovery_and_off() -> void:
	_reset({"food": 40, "wood": 0, "gold": 10})
	var building: BuildingBase = _fixture()
	var queue: ProductionQueue = building.get_production_queue() as ProductionQueue
	queue.unit_trained.connect(func(_unit_type: int) -> void:
		_expect(queue.consume_completed_population_reservation(), "resource recovery completion consumes its reservation")
	)
	_expect(queue.enqueue_unit(SCOUT), "first Scout uses the initial resources")
	queue.auto_queue_enabled = true
	queue.advance(queue.current_train_time)
	_expect(queue.queue.is_empty() and not queue.is_training, "repeat waits after the last resources are spent")
	_expect(_committed() == 1 and _reserved() == 0, "waiting for resources holds no phantom reservation")
	queue.advance(30.0)
	_expect(queue.queue.is_empty() and _food() == 0, "long blocked tick cannot create free production")
	_resource_manager.call("add_resource", 0, "food", 40)
	queue.advance(0.5)
	_expect(queue.queue.is_empty() and _food() == 40, "food-only deposit does not spend until gold is also affordable")
	_resource_manager.call("add_resource", 0, "gold", 10)
	queue.advance(0.49)
	_expect(queue.queue.is_empty() and _food() == 40, "retry is bounded by the half-second interval")
	queue.advance(0.02)
	_expect(queue.queue == [SCOUT] and queue.is_training, "repeat resumes after both resource deposits")
	_expect(_food() == 0 and _gold() == 0 and _reserved() == 1, "resumed Scout pays every resource and reserves exactly one slot")
	queue.advance(queue.current_train_time)
	_expect(queue.queue.is_empty(), "second completed Scout waits for resources again")
	queue.auto_queue_enabled = false
	_resource_manager.call("add_resource", 0, "food", 80)
	_resource_manager.call("add_resource", 0, "gold", 20)
	queue.advance(60.0)
	_expect(queue.queue.is_empty() and _reserved() == 0 and _food() == 80 and _gold() == 20, "Repeat OFF neither resumes nor spends after a deposit")
	building.free()


func _test_housing_and_free_population() -> void:
	_reset({"food": 1000, "wood": 0, "gold": 0})
	var building: BuildingBase = _fixture()
	var queue: ProductionQueue = building.get_production_queue() as ProductionQueue
	_set_cap(1)
	queue.unit_trained.connect(func(_unit_type: int) -> void:
		_expect(queue.consume_completed_population_reservation(), "housing completion consumes its reservation")
	)
	_expect(queue.enqueue_unit(VILLAGER), "housing fixture reserves its only slot")
	queue.auto_queue_enabled = true
	queue.advance(queue.current_train_time)
	var food_after_first: int = _food()
	for attempt in 3:
		queue.advance(0.5)
	_expect(queue.queue.is_empty() and _committed() == 1 and _food() == food_after_first, "full housing repeatedly blocks production without spending")
	_game_manager.call("increase_population_cap", 0, 1)
	queue.advance(0.49)
	_expect(queue.queue.is_empty(), "new housing respects the retry interval")
	queue.advance(0.02)
	_expect(queue.queue == [VILLAGER] and _committed() == 2 and _reserved() == 1, "new housing permits exactly one reserved repeat unit")
	_expect(_food() == food_after_first - 50, "housing recovery pays the normal Villager cost")
	queue.advance(queue.current_train_time)
	var food_at_cap: int = _food()
	queue.advance(30.0)
	_expect(queue.queue.is_empty() and _committed() == 2 and _food() == food_at_cap, "repeat never overshoots the newly filled cap")
	_game_manager.call("remove_population", 0, 1)
	queue.advance(0.5)
	_expect(queue.queue == [VILLAGER] and _committed() == 2 and _reserved() == 1, "freeing population also resumes repeat without exceeding cap")
	_expect(_food() == food_at_cap - 50, "free population recovery also pays normally")
	building.free()
	_expect(_reserved() == 0, "fixture destruction releases the resumed reservation")


func _test_clear_waiting_repeat() -> void:
	_reset({"food": 40, "wood": 0, "gold": 10})
	var building: BuildingBase = _fixture()
	var queue: ProductionQueue = building.get_production_queue() as ProductionQueue
	queue.unit_trained.connect(func(_unit_type: int) -> void:
		_expect(queue.consume_completed_population_reservation(), "waiting-clear fixture consumes completed reservation")
	)
	_expect(queue.enqueue_unit(SCOUT), "waiting-clear fixture pays for its Scout")
	queue.auto_queue_enabled = true
	queue.advance(queue.current_train_time)
	queue.advance(0.49)
	_expect(queue.queue.is_empty() and queue.auto_queue_enabled, "waiting-clear starts with pending repeat retry")
	queue.cancel_all()
	_expect(not queue.auto_queue_enabled and queue.auto_queue_unit_type == SCOUT, "empty Clear stops repeat while remembering its unit")
	_expect(queue.get("_auto_queue_retry_elapsed") == 0.0, "empty Clear resets the pending retry interval")
	_resource_manager.call("add_resource", 0, "food", 40)
	_resource_manager.call("add_resource", 0, "gold", 10)
	queue.advance(30.0)
	_expect(queue.queue.is_empty() and _reserved() == 0 and _committed() == 1 and _food() == 40 and _gold() == 10, "cleared waiting repeat never spends a later deposit")
	building.free()


func _test_clear_partial_queue_and_reenable() -> void:
	_reset({"food": 1000, "wood": 0, "gold": 100})
	var building: BuildingBase = _fixture()
	var queue: ProductionQueue = building.get_production_queue() as ProductionQueue
	for unit_type: int in [SCOUT, VILLAGER, SCOUT]:
		_expect(queue.enqueue_unit(unit_type), "partial-clear fixture queues unit %d" % unit_type)
	queue.auto_queue_enabled = true
	queue.current_progress = queue.current_train_time * 0.4
	var changed_count: Array[int] = [0]
	var cancelled_count: Array[int] = [0]
	var changed_callback: Callable = func() -> void:
		changed_count[0] += 1
		_expect(queue.queue.is_empty() and not queue.auto_queue_enabled and not queue.is_training, "Clear emits one final stopped queue state")
	var refund_callback: Callable = func(player_id: int, _resource_type: String, _amount: int) -> void:
		if player_id == 0:
			_expect(queue.queue.is_empty() and not queue.auto_queue_enabled and not queue.is_training, "refund observers already see cleared work and Repeat OFF")
	queue.queue_changed.connect(changed_callback)
	queue.unit_cancelled.connect(func(_unit_type: int) -> void: cancelled_count[0] += 1)
	_resource_manager.connect("resources_changed", refund_callback)
	queue.cancel_all()
	_resource_manager.disconnect("resources_changed", refund_callback)
	queue.queue_changed.disconnect(changed_callback)
	_expect(changed_count[0] == 1 and cancelled_count[0] == 3, "whole Clear emits one queue refresh and one cancellation per entry")
	_expect(_reserved() == 0 and _committed() == 0 and _food() == 1000 and _gold() == 100, "Clear fully refunds the active partial unit and waiting entries exactly once")
	_expect(queue.current_progress == 0.0 and queue.current_train_time == 0.0, "Clear resets active training progress")
	queue.cancel_all()
	queue.advance(30.0)
	_expect(queue.queue.is_empty() and _reserved() == 0 and _food() == 1000 and _gold() == 100, "repeated Clear and later ticks cannot refund twice or restart production")
	queue.auto_queue_enabled = true
	queue.advance(0.49)
	_expect(queue.queue.is_empty(), "deliberate re-enable starts a fresh bounded interval")
	queue.advance(0.02)
	_expect(queue.queue == [SCOUT] and _reserved() == 1 and _food() == 960 and _gold() == 90, "re-enabled repeat resumes the remembered paid reserved Scout")
	_expect(queue.cancel_unit(0) and queue.auto_queue_enabled, "individual cancellation deliberately preserves Repeat ON")
	queue.advance(0.5)
	_expect(queue.queue == [SCOUT] and _reserved() == 1 and _food() == 960 and _gold() == 90, "individual cancellation can retry its refunded unit normally")
	building.free()
	_expect(_reserved() == 0, "partial-clear fixture cleanup releases the re-enabled reservation")


func _test_inactive_and_destroyed_buildings() -> void:
	_reset({"food": 500, "wood": 0, "gold": 100})
	var building: BuildingBase = _fixture()
	var queue: ProductionQueue = building.get_production_queue() as ProductionQueue
	queue.auto_queue_enabled = true
	queue.auto_queue_unit_type = SCOUT
	building.state = BuildingBase.State.CONSTRUCTING
	queue.advance(10.0)
	_expect(queue.queue.is_empty() and _food() == 500 and _reserved() == 0, "inactive building does not retry or spend")
	building.state = BuildingBase.State.ACTIVE
	queue.advance(0.5)
	_expect(queue.queue == [SCOUT], "reactivated building can retry")
	building.take_damage(building.max_hp)
	queue.advance(10.0)
	_expect(building.state == BuildingBase.State.DESTROYED and queue.queue.is_empty() and not queue.auto_queue_enabled and _reserved() == 0, "destroyed building clears repeat and reservations")
	var food_after_destruction: int = _food()
	queue.auto_queue_enabled = true
	queue.advance(10.0)
	_expect(queue.queue.is_empty() and _food() == food_after_destruction, "destroyed state rejects even a stale enabled flag")
	queue.reparent(root)
	building.free()
	queue.advance(10.0)
	_expect(queue.queue.is_empty() and _food() == food_after_destruction, "freed producing building cannot retry or spend")
	queue.free()


func _test_main_recovery_and_pause() -> void:
	var match_scene: Node = MAIN_SCENE.instantiate()
	root.add_child(match_scene)
	get_tree().current_scene = match_scene
	var ready: bool = false
	for frame in 900:
		if match_scene.get("_building_placement") != null and int(_game_manager.get("current_state")) == 2:
			ready = true
			break
		await get_tree().process_frame
	_expect(ready, "real Main match reaches PLAYING")
	if not ready:
		match_scene.free()
		get_tree().current_scene = null
		return
	# Advance through Main explicitly so the test controls production time and
	# catches orchestration accidentally skipping empty enabled queues.
	match_scene.set_process(false)
	var buildings: Array = (match_scene.get("_player_buildings") as Array)[0]
	var building: BuildingBase = null
	for candidate: BuildingBase in buildings:
		if candidate.building_type == BuildingData.BuildingType.TOWN_CENTER:
			building = candidate
			break
	_expect(building != null, "real Main owns a Town Center")
	if building == null:
		match_scene.free()
		get_tree().current_scene = null
		return
	var queue: ProductionQueue = building.get_production_queue() as ProductionQueue
	_resource_manager.call("try_spend", 0, {"food": _food() - 40, "gold": _gold() - 10})
	_expect(queue.enqueue_unit(SCOUT), "real Main queues the resource-limited Scout")
	queue.auto_queue_enabled = true
	queue.call("_complete_current_unit")
	_expect(queue.queue.is_empty(), "real Main repeat blocks at empty resources")
	match_scene.call("_advance_production_queues", 0.5)
	_resource_manager.call("add_resource", 0, "food", 40)
	_resource_manager.call("add_resource", 0, "gold", 10)
	match_scene.call("_advance_production_queues", 0.49)
	_expect(queue.queue.is_empty(), "Main empty-queue retry remains bounded")
	match_scene.call("_advance_production_queues", 0.02)
	_expect(queue.queue == [SCOUT] and _food() == 0 and _gold() == 0 and _reserved() == 1, "real Main resumes a paid reserved Scout after deposits")
	queue.call("_complete_current_unit")
	_expect(queue.queue.is_empty(), "real Main has another resource wait for the pause check")
	_game_manager.call("set_state", 3)
	_resource_manager.call("add_resource", 0, "food", 40)
	_resource_manager.call("add_resource", 0, "gold", 10)
	match_scene.call("_process", 10.0)
	_expect(queue.queue.is_empty() and _food() == 40 and _gold() == 10, "Main does not retry or spend while paused")
	_game_manager.call("set_state", 2)
	match_scene.call("_process", 0.5)
	_expect(queue.queue == [SCOUT] and _food() == 0 and _reserved() == 1, "resuming Main permits the pending paid repeat")
	queue.auto_queue_enabled = false
	queue.cancel_unit(0)
	# Revoke the TC housing grant before setting this capacity-recovery fixture;
	# base-cap subtraction cannot remove an active provider's nominal grant.
	_game_manager.call("revoke_population_cap", building.get_instance_id())
	_set_cap(_committed())
	queue.auto_queue_enabled = true
	match_scene.call("_advance_production_queues", 0.5)
	_expect(queue.queue.is_empty() and _food() == 40, "Main blocks repeat at the current housing cap without spending")
	_game_manager.call("increase_population_cap", 0, 1)
	match_scene.call("_advance_production_queues", 0.5)
	_expect(queue.queue == [SCOUT] and _food() == 0 and _reserved() == 1, "Main resumes a paid repeat after housing recovery")
	_expect(_committed() == _cap(), "real Main recovery cannot overshoot the cap")
	var hud: CanvasLayer = match_scene.get_node("HUD") as CanvasLayer
	var game_map: Node = match_scene.get_node("GameMap")
	game_map.get("selection_mgr").call("select_single", building)
	var repeat_button: Button = hud.get("_auto_queue_button") as Button
	_expect(repeat_button != null and repeat_button.button_pressed and repeat_button.text.contains("ON") and repeat_button.accessibility_name.contains("Repeat training"), "selected producer immediately reflects Repeat ON")
	queue.current_progress = queue.current_train_time * 0.5
	hud.call("_on_clear_all_queue_pressed")
	_expect(not queue.auto_queue_enabled and queue.queue.is_empty() and not queue.is_training, "real HUD Clear atomically stops Repeat and all training")
	_expect(_reserved() == 0 and _food() == 40 and _gold() == 10, "real HUD Clear refunds the partial Scout and releases its population slot")
	_expect(repeat_button != null and not repeat_button.button_pressed and repeat_button.text.contains("OFF") and repeat_button.accessibility_name.contains("Repeat training"), "real HUD immediately shows Repeat OFF without another frame")
	_expect(int(hud.get("_population_current")) == _committed(), "real HUD immediately drops the cleared reservation")
	match_scene.call("_advance_production_queues", 30.0)
	_expect(queue.queue.is_empty() and _food() == 40 and _gold() == 10 and _reserved() == 0, "real Clear stays empty beyond the retry interval")
	hud.call("_on_auto_queue_toggled", true)
	match_scene.call("_advance_production_queues", 0.5)
	_expect(queue.queue == [SCOUT] and _food() == 0 and _reserved() == 1, "real HUD can deliberately re-enable paid repeat after Clear")
	queue.call("_complete_current_unit")
	match_scene.call("_advance_production_queues", 0.49)
	_expect(queue.queue.is_empty() and queue.auto_queue_enabled, "real producer can be waiting with Repeat ON")
	hud.call("_on_clear_all_queue_pressed")
	_expect(not queue.auto_queue_enabled and not repeat_button.button_pressed and repeat_button.text.contains("OFF") and repeat_button.accessibility_name.contains("Repeat training"), "real Clear also immediately stops empty waiting repeat")
	_resource_manager.call("add_resource", 0, "food", 40)
	_resource_manager.call("add_resource", 0, "gold", 10)
	_game_manager.call("increase_population_cap", 0, 1)
	match_scene.call("_advance_production_queues", 30.0)
	_expect(queue.queue.is_empty() and _food() == 40 and _gold() == 10 and _reserved() == 0, "cleared waiting Main does not spend after resources and housing recover")
	match_scene.free()
	get_tree().current_scene = null


func _reset(resources: Dictionary) -> void:
	_game_manager.call("initialize_game", 1)
	_resource_manager.call("reset")
	_resource_manager.call("initialize_player", 0, resources)


func _fixture() -> BuildingBase:
	var building: BuildingBase = TOWN_CENTER_SCENE.instantiate() as BuildingBase
	root.add_child(building)
	building.complete_instantly()
	return building


func _set_cap(target: int) -> void:
	var difference: int = target - _cap()
	if difference > 0:
		_game_manager.call("increase_population_cap", 0, difference)
	elif difference < 0:
		_game_manager.call("decrease_population_cap", 0, -difference)
	_expect(_cap() == target, "fixture can set housing cap %d" % target)


func _food() -> int:
	return int(_resource_manager.call("get_resource", 0, "food"))


func _gold() -> int:
	return int(_resource_manager.call("get_resource", 0, "gold"))


func _committed() -> int:
	return int(_game_manager.call("get_committed_population", 0))


func _reserved() -> int:
	return int(_game_manager.call("get_reserved_population", 0))


func _cap() -> int:
	return int((_game_manager.get("players") as Dictionary)[0]["population_cap"])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
