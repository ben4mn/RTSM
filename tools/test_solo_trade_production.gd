extends Node
## Exercise the solo scene registry and Main purchase/completion wiring, including
## saved posts from before they acquired a ProductionQueue scene child.
const STATE = preload("res://scripts/main/solo_match_state.gd")
const NETWORK = preload("res://scripts/network/network_match.gd")
var checks: int = 0
var failures: Array[String] = []
var main: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _wait_main() -> bool:
	main = null
	for frame: int in 900:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and scene.get("_building_placement") != null:
			main = scene
			main.process_mode = Node.PROCESS_MODE_DISABLED
			return true
	check(false, "Main initialized within bounded frames")
	return false

func _post() -> BuildingBase:
	for building: BuildingBase in main._player_buildings[0]:
		if building.building_type == BuildingData.BuildingType.TRADE_POST: return building
	return null

func _traders() -> Array[Trader]:
	var result: Array[Trader] = []
	for unit: UnitBase in main._player_units[0]:
		if unit is Trader: result.append(unit)
	return result

func _run() -> void:
	# Keep the fixture alive while the real scene lifecycle replaces Main.
	get_tree().current_scene = null
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	SoloSave.discard_save("solo_trade_fixture")
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.selected_population_limit = 100
	GameManager.guided_opening_enabled = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	if not await _wait_main():
		await _finish()
		return
	check(not NetworkSession.is_network_match(), "fixture uses the real solo runtime")
	for building_type: int in BuildingData.BUILDINGS:
		if not BuildingData.can_train_units(building_type): continue
		var scene: PackedScene = main._building_scenes.get(building_type)
		check(scene != null, "trainable building has a registered scene: %d" % building_type)
		if scene == null: continue
		var instance: BuildingBase = scene.instantiate()
		check(instance.get_node_or_null("ProductionQueue") is ProductionQueue, "trainable scene includes a real queue: %d" % building_type)
		instance.free()
	ResourceManager.initialize_player(0, {"food": 2000, "wood": 2000, "gold": 2000})
	check(GameManager.try_advance_age(0), "Feudal access is purchased normally")
	var center: Vector2i = main.game_map.map_generator.get_expansion_pocket_centers()[0]
	check(ResourceManager.try_spend(0, BuildingData.get_building_cost(BuildingData.BuildingType.TRADE_POST)), "post costs its normal 200 wood")
	var post: BuildingBase = main._spawn_building(BuildingData.BuildingType.TRADE_POST, 0, center)
	post.complete_instantly()
	var queue: ProductionQueue = post.get_production_queue() as ProductionQueue
	var bank: Dictionary = ResourceManager.get_all_resources(0)
	var population: int = int(GameManager.players[0].population)
	main._on_train_unit_requested(post, UnitData.UnitType.TRADER)
	check(main._last_train_request_result == "queued", "Main accepts a paid Trader command")
	check(queue != null, "Main-spawned Trade Post exposes its scene queue")
	if queue == null:
		await _finish()
		return
	var paid_bank: Dictionary = bank.duplicate()
	paid_bank.wood -= 60
	paid_bank.gold -= 40
	check(ResourceManager.get_all_resources(0) == paid_bank, "Trader charges exactly 60 wood and 40 gold once")
	check(queue.queue == [UnitData.UnitType.TRADER] and queue.is_training, "finite queue starts the actual Trader")
	check(int(GameManager.players[0].population) == population and GameManager.get_reserved_population(0) == 2, "queued Trader reserves two population without spawning")
	main._advance_production_queues(queue.current_train_time - 0.01)
	check(_traders().is_empty(), "Trader cannot spawn before production completes")
	main._advance_production_queues(0.02)
	check(_traders().size() == 1, "normal Main queue advancement spawns exactly one actual Trader")
	check(int(GameManager.players[0].population) == population + 2 and GameManager.get_reserved_population(0) == 0, "completion converts reservation into exactly two live population")
	check(ResourceManager.get_all_resources(0) == paid_bank and queue.queue.is_empty(), "completion neither charges again nor retains a repeat order")
	if not _traders().is_empty():
		check(_traders()[0].trade_route_active, "new Trader automatically starts the producer's reachable trade route")
	main._advance_production_queues(100.0)
	check(_traders().size() == 1 and ResourceManager.get_all_resources(0) == paid_bank, "idle production cannot duplicate a Trader or pay passive gold")
	main._on_train_unit_requested(post, UnitData.UnitType.TRADER)
	main._advance_production_queues(7.0)
	paid_bank.wood -= 60
	paid_bank.gold -= 40
	check(queue.queue.size() == 1 and is_equal_approx(queue.current_progress, 7.0), "second paid Trader is saved in progress")
	check(SoloSave.save_current("paid_trade_queue"), "real native checkpoint accepts paid Trade Post queue")
	check(SoloSave.resume_match(), "paid checkpoint resumes through real Main lifecycle")
	if not await _wait_main():
		await _finish()
		return
	post = _post()
	queue = post.get_production_queue() as ProductionQueue if post != null else null
	check(queue != null and queue.queue.size() == 1 and is_equal_approx(queue.current_progress, 7.0), "resumed Trade Post retains exact paid queue progress")
	check(_traders().size() == 1 and ResourceManager.get_all_resources(0) == paid_bank and GameManager.get_reserved_population(0) == 2, "resume does not respawn, repay or lose reserved population")
	if queue == null:
		await _finish()
		return
	main._advance_production_queues(queue.current_train_time - queue.current_progress + 0.01)
	main._advance_production_queues(100.0)
	check(_traders().size() == 2 and int(GameManager.players[0].population) == population + 4 and GameManager.get_reserved_population(0) == 0, "resumed paid Trader completes once with exact population")
	check(ResourceManager.get_all_resources(0) == paid_bank, "resumed production never repurchases the Trader")
	# beta.13 and earlier checkpoints contain a valid post record without a queue.
	var legacy: Dictionary = STATE.new().capture(main)
	for record: Dictionary in legacy.actors:
		if record.kind == "building" and int(record.type) == BuildingData.BuildingType.TRADE_POST: record.erase("queue")
	check(STATE.validate(legacy).is_empty(), "older queue-less Trade Post save remains schema-compatible")
	check(SoloSave._write_native(SoloSave._envelope(legacy, SoloSave._generation + 1), SoloSave._generation + 1), "legacy-shaped post checkpoint writes through native storage")
	SoloSave.reload_save()
	check(SoloSave.resume_match(), "older saved post resumes without a save-version change")
	if not await _wait_main():
		await _finish()
		return
	post = _post()
	queue = post.get_production_queue() as ProductionQueue if post != null else null
	check(queue != null and queue.queue.is_empty(), "old saved post acquires the fixed scene's empty production queue")
	check(_traders().size() == 2 and ResourceManager.get_all_resources(0) == paid_bank, "legacy restore preserves existing Traders and bank")
	main._on_train_unit_requested(post, UnitData.UnitType.TRADER)
	check(main._last_train_request_result == "queued" and GameManager.get_reserved_population(0) == 2, "previously saved post can buy a new Trader normally")
	if queue != null: queue.cancel_all()
	check(ResourceManager.get_all_resources(0) == paid_bank and GameManager.get_reserved_population(0) == 0, "cancelling restored post's finite purchase refunds exact cost and population")
	# The authoritative command adapter uses the same scene queue. This is an
	# in-process authority regression, not a claim of a socket-connected match.
	GameManager.current_state = GameManager.GameState.PLAYING
	NetworkSession.set_process(false)
	NetworkSession.set_physics_process(false)
	NetworkSession.online = true
	NetworkSession.server_mode = true
	var server: Node = NETWORK.new()
	main.add_child(server)
	server.main = main
	server.game_map = main.game_map
	server.set_process(false)
	server._register_server_entities()
	var command: Dictionary = {"command": "train", "target": NetworkSession.entity_id(post), "type": UnitData.UnitType.TRADER}
	var other_bank: Dictionary = ResourceManager.get_all_resources(1)
	check(not server.execute_command(1, command).is_empty() and queue.queue.is_empty(), "authority rejects another player's post training command")
	check(ResourceManager.get_all_resources(0) == paid_bank and ResourceManager.get_all_resources(1) == other_bank and GameManager.get_reserved_population(0) == 0, "rejected foreign training changes neither bank nor reservation")
	check(server.execute_command(0, command).is_empty(), "authority accepts owned post's actual paid training command")
	paid_bank.wood -= 60
	paid_bank.gold -= 40
	check(ResourceManager.get_all_resources(0) == paid_bank and queue.queue.size() == 1 and GameManager.get_reserved_population(0) == 2, "authority charges one normal Trader purchase with two reserved population")
	main._advance_production_queues(queue.current_train_time + 0.01)
	main._advance_production_queues(100.0)
	check(_traders().size() == 3 and int(GameManager.players[0].population) == population + 6 and GameManager.get_reserved_population(0) == 0, "authority queue completion spawns one Trader without repeat or lost population")
	check(ResourceManager.get_all_resources(0) == paid_bank and ResourceManager.get_all_resources(1) == other_bank, "authority completion has no second charge or foreign bank effects")
	NetworkSession.online = false
	NetworkSession.server_mode = false
	await _finish()

func _finish() -> void:
	print(JSON.stringify({"test": "solo_trade_production", "checks": checks, "failures": failures, "scope": "actual Main scenes, paid solo and authority commands, native save/resume; manually advanced queue time; no sockets"}))
	if is_instance_valid(main): main.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
