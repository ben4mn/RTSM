extends Node
var failures: Array[String] = []
var checks: int = 0
var phase: String = "writer"
var main: Node
func _ready() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _run() -> void:
	get_tree().current_scene = null
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
	get_tree().root.get_node("AudioManager").set_all_enabled(false)
	if phase == "writer": await _writer()
	elif phase == "reader": await _reader()
	elif phase == "corrupt": _corrupt()
	elif phase == "online": await _online()
	print(JSON.stringify({"test": "solo_save", "phase": phase, "checks": checks, "failures": failures}))
	if is_instance_valid(main):
		main.queue_free()
		await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
func _wait_main() -> void:
	for frame: int in 900:
		await get_tree().process_frame
		main = get_tree().current_scene
		if main != null and main.get("_building_placement") != null: break
	check(main != null and main.get("_building_placement") != null, "main initialized")
	main.process_mode = Node.PROCESS_MODE_DISABLED
func _writer() -> void:
	var save: Node = get_tree().root.get_node("SoloSave")
	var gm: Node = get_tree().root.get_node("GameManager")
	var bank: Node = get_tree().root.get_node("ResourceManager")
	save.discard_save("fixture")
	gm.selected_map_seed = 424242
	gm.selected_map_archetype = 4
	gm.selected_population_limit = 100
	gm.guided_opening_enabled = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await _wait_main()
	for owner: int in [0, 1]: bank._player_resources[owner] = {"food": 5000, "wood": 5000, "gold": 5000}
	check(gm.try_advance_age(0), "age purchased normally")
	var map: Node = main.game_map
	var tc: BuildingBase = main._player_town_center
	var units: Array = main._player_units[0]
	var worker: Villager = units[0]
	var builder: Villager = units[1]
	var farmer: Villager = units[2]
	var resource: ResourceNode = worker.gather_target
	check(resource != null, "starting worker has real gather assignment")
	resource.remaining -= 17
	worker._cargo = {"food": 4, "gold": 3}
	worker.carried_amount = 7
	worker.gather_timer = 0.41
	worker._fractional_harvest = 0.7
	var deleted: ResourceNode = map.resource_nodes.values().back()
	var deleted_tile: Vector2i = deleted.tile_position
	map._on_resource_depleted(deleted, deleted_tile)
	map._apply_depleted_terrain_visual(deleted_tile)
	deleted.free()
	var center: Vector2i = map.map_generator.get_expansion_pocket_centers()[0]
	check(bank.try_spend(0, BuildingData.get_building_cost(BuildingData.BuildingType.TRADE_POST)), "trade post paid")
	var post: BuildingBase = main._spawn_building(BuildingData.BuildingType.TRADE_POST, 0, center)
	post.complete_instantly()
	check(bank.try_spend(0, BuildingData.get_building_cost(BuildingData.BuildingType.FARM)), "farm paid")
	var farm: BuildingBase = main._spawn_building(BuildingData.BuildingType.FARM, 0, center + Vector2i(5, 3))
	farm.complete_instantly()
	farmer.command_gather(farm)
	check(bank.try_spend(0, BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE)), "house paid")
	var house: BuildingBase = main._spawn_building(BuildingData.BuildingType.HOUSE, 0, center + Vector2i(9, 3))
	house.start_construction()
	house.build_progress = 0.37
	house.hp = 41
	builder.command_build(house)
	check(bank.try_spend(0, UnitData.get_unit_cost(UnitData.UnitType.TRADER)), "trader paid")
	var trader: Trader = main._spawn_unit(UnitData.UnitType.TRADER, 0, map.tile_to_world(center + Vector2i(-1, 1)))
	check(trader.command_trade(post), "trade route accepted")
	trader._visited_home = true
	trader.carried_gold = trader.get_trip_income()
	trader._destination = tc
	trader._handling_left = 1.25
	var queue: ProductionQueue = tc.get_production_queue()
	check(queue.enqueue_unit(UnitData.UnitType.VILLAGER) and queue.enqueue_unit(UnitData.UnitType.VILLAGER), "two finite purchases")
	queue.current_progress = 7.25
	tc.set_resource_rally(resource)
	tc.enqueue_rally_order({"kind": "move", "position": worker.global_position + Vector2(80, 0)})
	var scout: UnitBase = units[3]
	scout.command_patrol(scout.global_position + Vector2(100, 100))
	scout.enqueue_order({"kind": "move", "position": scout.global_position + Vector2(150, 100)})
	worker.enqueue_order({"kind": "dropoff", "target_id": tc.get_instance_id()})
	main._control_groups[1] = [scout, worker]
	main.ai_controller._enemy_memory[worker.get_instance_id()] = {"position": worker.global_position, "seen_at": 117.0, "ref": weakref(worker)}
	main.ai_controller._game_time = 123.0
	main.ai_controller._last_harass_time = 112.0
	var site: Node = map.sacred_site
	site.state = 2
	site.owning_player = 0
	site.victory_timer = 45.75
	site.control_banks.assign([45.75, 12.25])
	site._gold_accumulator = 0.65
	site._gold_accumulator_owner = 0
	map.fog_of_war.fog_grid[10][10] = 1
	var memory: Node = map._ensure_fog_memory()
	memory.remember_resource(Vector2i(11, 11), "gold", 22)
	memory.remember_building({"id": 999999999, "owner": 1, "type": 1, "state": 2, "progress": 1.0, "hp": 123, "x": 128.0, "y": 320.0, "source_id": 999999999})
	map.camera.position = map.tile_to_world(Vector2i(27, 25))
	map.camera.zoom = Vector2(0.8, 0.8)
	check(bank.try_spend(0, UnitData.get_unit_cost(UnitData.UnitType.ARCHER)), "archer paid")
	var defender: UnitBase = main._player_units[1][0]
	var archer: UnitBase = main._spawn_unit(UnitData.UnitType.ARCHER, 0, defender.global_position + Vector2(-100, 0))
	Combat.launch_ranged_attack(archer, defender)
	var shot: Combat.RangedProjectile
	for child: Node in map.get_node("UnitsContainer").get_children():
		if child is Combat.RangedProjectile: shot = child
	shot.advance_projectile(0.05)
	gm.game_time = 122.0
	gm.set_paused(true)
	check(save.save_current("first_good"), "first good checkpoint")
	gm.game_time = 123.0
	check(save.save_current("latest_good"), "latest good checkpoint")
	check(save.has_save() and save.get_status().durable, "saved status means durable native checkpoint")
	var expected: Dictionary = {"bank": bank._player_resources.duplicate(true), "population": gm.players[0].population, "reserved": gm.players[0].population_reserved, "cap": gm.players[0].population_cap, "units": main._player_units[0].size(), "buildings": main._player_buildings[0].size(), "deposits": map.resource_nodes.size(), "deleted": deleted_tile, "resource_tile": resource.tile_position, "resource_remaining": resource.remaining, "trade_cargo": trader.carried_gold, "camera": map.camera.position, "defender_hp": defender.hp, "shot_damage": shot.final_damage}
	var file := FileAccess.open("user://expected.bin", FileAccess.WRITE)
	file.store_var(expected, false)
	file.close()
func _reader() -> void:
	var save: Node = get_tree().root.get_node("SoloSave")
	var gm: Node = get_tree().root.get_node("GameManager")
	var bank: Node = get_tree().root.get_node("ResourceManager")
	var expected: Dictionary = FileAccess.open("user://expected.bin", FileAccess.READ).get_var(false)
	gm.selected_map_seed = 666
	gm.selected_map_archetype = 1
	gm.selected_difficulty = 0
	gm.selected_civilization = 2
	check(save.has_save(), "fresh process finds saved match")
	check(save.resume_match(), "validated resume accepted")
	await _wait_main()
	check(gm.current_state == gm.GameState.PAUSED and get_tree().paused, "resume waits safely paused")
	check(gm.selected_map_seed == 666 and gm.selected_map_archetype == 1 and gm.selected_difficulty == 0 and gm.selected_civilization == 2, "next-match preferences preserved")
	check(main.game_map.map_seed == 424242 and main.game_map.map_archetype == 4, "saved battlefield restored")
	check(is_equal_approx(gm.game_time, 123.0), "clock restored")
	check(bank._player_resources == expected.bank, "no costs or payouts replayed")
	check(gm.players[0].population == expected.population and gm.players[0].population_reserved == expected.reserved and gm.players[0].population_cap == expected.cap, "population and paid reservation ledger exact")
	check(main._player_units[0].size() == expected.units and main._player_buildings[0].size() == expected.buildings, "no duplicate starter actors")
	var network: Node = get_tree().root.get_node("NetworkSession")
	var generation_before: int = save._generation
	network.online = true
	check(not save.save_current("forbidden_online") and not await save.save_and_wait("forbidden_online") and not save.resume_match(), "active online guard blocks save and resume")
	save.discard_save("forbidden_online")
	check(save.has_save() and save._generation == generation_before, "online match cannot delete solo checkpoint")
	network.online = false
	var map: Node = main.game_map
	check(map.resource_nodes.size() == expected.deposits and not map.resource_nodes.has(expected.deleted), "depleted deposit stays depleted")
	check(not map._pending_depleted_terrain_tiles.has(expected.deleted) and map.terrain_layer.get_cell_atlas_coords(expected.deleted) == map._tile_type_to_atlas(MapData.TileType.GRASS), "revealed depletion keeps grass artwork")
	check(map.resource_nodes[expected.resource_tile].remaining == expected.resource_remaining, "partly gathered deposit exact")
	var worker: Villager = main._player_units[0][0]
	var builder: Villager = main._player_units[0][1]
	var farmer: Villager = main._player_units[0][2]
	check(worker._cargo == {"food": 4, "gold": 3} and worker.carried_amount == 7 and is_equal_approx(worker.gather_timer, 0.41) and is_equal_approx(worker._fractional_harvest, 0.7), "mixed cargo and fractional harvest exact")
	check(worker.gather_target == map.resource_nodes[expected.resource_tile], "worker resource reference remapped")
	check(is_instance_valid(builder.build_target) and is_equal_approx(builder.build_target.build_progress, 0.37) and builder.build_target.hp == 41, "construction job and health restored")
	check(farmer.gather_target is BuildingBase and farmer.gather_target.get_assigned_worker() == farmer, "farm has exactly its assigned worker")
	var tc: BuildingBase = main._player_town_center
	check(is_instance_valid(tc) and tc.rally_resource_instance_id == worker.gather_target.get_instance_id() and tc.rally_orders.size() == 2, "rally identity and finite continuation restored")
	check(worker.queued_orders.size() == 1 and worker.queued_orders[0].target_id == tc.get_instance_id(), "queued dropoff references new process actor")
	var scout: UnitBase = main._player_units[0][3]
	check(scout._patrol_active and scout.queued_orders.size() == 1, "patrol and finite movement queue preserved")
	check(main._control_groups[1] == [scout, worker], "control group references remapped")
	check(main.ai_controller._enemy_memory.has(worker.get_instance_id()) and is_equal_approx(main.ai_controller._last_harass_time, 112.0), "AI knowledge and cadence restored")
	check(is_equal_approx(map.sacred_site.victory_timer, 45.75) and is_equal_approx(map.sacred_site._gold_accumulator, 0.65), "sacred hold and fractional gold exact")
	check(map.fog_of_war.fog_grid[10][10] == 1 and map.fog_memory.resources.has(Vector2i(11, 11)) and map.fog_memory.buildings.has(999999999), "exploration and immutable sightings preserved")
	check(map.camera.position.distance_to(expected.camera) < 1.0 and map.camera.zoom.is_equal_approx(Vector2(0.8, 0.8)), "camera restored")
	var shot: Combat.RangedProjectile
	var shot_count: int = 0
	for child: Node in map.get_node("UnitsContainer").get_children():
		if child is Combat.RangedProjectile:
			shot = child
			shot_count += 1
	var defender: UnitBase = main._player_units[1][0]
	check(shot_count == 1 and is_equal_approx(shot.elapsed, 0.05) and shot.defender_ref.get_ref() == defender and is_equal_approx(defender.hp, expected.defender_hp), "in-flight projectile retains progress and target")
	shot.advance_projectile(shot.flight_seconds)
	shot.advance_projectile(shot.flight_seconds)
	check(is_equal_approx(defender.hp, expected.defender_hp - expected.shot_damage), "resumed projectile lands exactly once")
	var queue: ProductionQueue = tc.get_production_queue()
	check(queue.queue.size() == 2 and is_equal_approx(queue.current_progress, 7.25), "paid finite queue progress exact")
	var initial_bank: Dictionary = bank._player_resources.duplicate(true)
	var initial_units: int = main._player_units[0].size()
	queue.advance(queue.current_train_time - queue.current_progress + 0.01)
	check(main._player_units[0].size() == initial_units + 1 and queue.queue.size() == 1, "one resumed production completion")
	check(bank._player_resources == initial_bank, "completion never repurchases queued unit")
	var trader: Trader
	for unit: UnitBase in main._player_units[0]:
		if unit is Trader: trader = unit
	check(trader != null and trader.carried_gold == expected.trade_cargo and trader.trade_post != null and trader.home_town_center == tc and is_equal_approx(trader._handling_left, 1.25), "trade cargo endpoints and handling preserved")
	var gold_before: int = bank.get_resource(0, "gold")
	gm.set_paused(false)
	var foundation: BuildingBase = builder.build_target
	var initial_cap: int = gm.players[0].population_cap
	var before_build: Dictionary = bank._player_resources.duplicate(true)
	for tick: int in 3600:
		builder._process(0.05)
		if foundation.state == BuildingBase.State.ACTIVE: break
	check(foundation.state == BuildingBase.State.ACTIVE and gm.players[0].population_cap == initial_cap + foundation.pop_provided, "resumed builder completes and grants housing exactly once")
	check(bank._player_resources == before_build and builder.has_active_gather_order(), "construction resumes prior economy without another purchase")
	for tick: int in 3600:
		trader._process(0.05)
		if trader.delivered_gold > 0: break
	check(trader.delivered_gold == expected.trade_cargo and bank.get_resource(0, "gold") == gold_before + expected.trade_cargo, "resumed trade cargo pays exactly once after travel")
	gm.set_paused(true)
func _corrupt() -> void:
	var save: Node = get_tree().root.get_node("SoloSave")
	var before: Dictionary = save.get_summary()
	var last_good: String = save._last_good_payload
	var target: String = save.SLOTS[1 - save._native_slot]
	var temporary: String = target + ".tmp"
	check(DirAccess.make_dir_absolute(temporary) == OK, "prepare bounded write failure")
	check(not save._write_native(save._envelope(save._saved_data, save._generation + 1), save._generation + 1), "native temporary write failure is reported")
	check(save._read_native(save.SLOTS[save._native_slot]) == last_good, "failed replacement preserves last good slot byte-for-byte")
	DirAccess.remove_absolute(temporary)
	var envelope: Dictionary = JSON.parse_string(last_good)
	envelope.version = 99
	check(save._unpack(JSON.stringify(envelope)).is_empty(), "future schema rejected")
	envelope.version = 1
	envelope.sha256 = "invalid checksum"
	check(save._unpack(JSON.stringify(envelope)).is_empty(), "checksum mismatch rejected")
	check(save._unpack(" ".repeat(save.MAX_BYTES + 1)).is_empty(), "oversized file rejected before parsing")
	var malformed: Dictionary = save._saved_data.duplicate(true)
	malformed.manager.players[0].population += 1
	check(save._unpack(save._envelope(malformed, save._generation + 1)).is_empty(), "invalid population ledger rejected")
	var latest: String = save.SLOTS[save._native_slot]
	var file := FileAccess.open(latest, FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	save.reload_save()
	check(save.has_save(), "corrupt newest slot falls back to prior valid checkpoint")
	check(save.get_summary().game_time <= before.game_time, "fallback is a prior checkpoint")
	for path: String in save.SLOTS:
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string("invalid")
		file.close()
	save.reload_save()
	check(not save.has_save() and not save.resume_match(), "all-corrupt save cannot start a broken world")
func _online() -> void:
	var save: Node = get_tree().root.get_node("SoloSave")
	var network: Node = get_tree().root.get_node("NetworkSession")
	network.online = true
	check(not save.save_current("online") and not await save.save_and_wait("online") and not save.resume_match(), "multiplayer never saves or resumes")
	network.online = false
