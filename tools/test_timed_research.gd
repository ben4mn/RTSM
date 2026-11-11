extends Node
## Round 2 workstream B on the real Main scene: timed research in one slot per
## building (start, queue blocking, cancel with full refund, completion through
## the modifier registry, refund when the building dies), the timed age-up with
## its building prerequisites, the authority commands and owner snapshot rows,
## and a native save/resume taken in the middle of a research.
const STATE = preload("res://scripts/main/solo_match_state.gd")
const NETWORK = preload("res://scripts/network/network_match.gd")
const RICH: Dictionary = {"food": 5000, "wood": 5000, "gold": 5000}

var checks: int = 0
var failures: Array[String] = []
var main: Node
var _events: Array[String] = []
var _site_index: int = 0


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


func _spawn(building_type: int, owner: int = 0) -> BuildingBase:
	## Completed building on open ground near the first expansion pocket.
	var center: Vector2i = main.game_map.map_generator.get_expansion_pocket_centers()[0]
	var tile: Vector2i = center + Vector2i((_site_index % 3) * 7 - 7, int(_site_index / 3.0) * 7 - 7)
	_site_index += 1
	var building: BuildingBase = main._spawn_building(building_type, owner, tile)
	building.complete_instantly()
	return building


func _find(building_type: int, owner: int = 0) -> BuildingBase:
	for building: BuildingBase in main._player_buildings[owner]:
		if is_instance_valid(building) and building.building_type == building_type and building.state == BuildingBase.State.ACTIVE: return building
	return null


func _tick(seconds: float) -> void:
	## The authority's research/production tick, in half-second steps.
	var remaining: float = seconds
	while remaining > 0.0:
		main._advance_production_queues(minf(0.5, remaining))
		remaining -= 0.5


func _bank() -> Dictionary:
	return ResourceManager.get_all_resources(0)


func _run() -> void:
	get_tree().current_scene = null
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	SoloSave.discard_save("timed_research_fixture")
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.guided_opening_enabled = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	if not await _wait_main():
		await _finish()
		return
	GameManager.increase_population_cap(0, 40)
	GameManager.increase_population_cap(1, 40)
	GameManager.research_started.connect(func(player_id: int, _building: Node2D, research_id: String, duration: float) -> void: _events.append("started:%d:%s:%d" % [player_id, research_id, int(duration)]))
	GameManager.research_cancelled.connect(func(player_id: int, _building: Node2D, research_id: String) -> void: _events.append("cancelled:%d:%s" % [player_id, research_id]))
	GameManager.research_completed.connect(func(player_id: int, research_id: String) -> void: _events.append("completed:%d:%s" % [player_id, research_id]))
	GameManager.age_advance_started.connect(func(player_id: int, target_age: int, duration: float) -> void: _events.append("age_started:%d:%d:%d" % [player_id, target_age, int(duration)]))
	GameManager.age_advance_cancelled.connect(func(player_id: int) -> void: _events.append("age_cancelled:%d" % player_id))
	GameManager.age_advanced.connect(func(player_id: int, new_age: int) -> void: _events.append("age:%d:%d" % [player_id, new_age]))
	_check_data()
	_check_research_slot()
	_check_age_up()
	_check_effects_and_destruction()
	_check_network()
	if await _check_save_round_trip():
		pass
	await _finish()


func _check_data() -> void:
	# Round 2 C: unique technologies carry a "civilization" key and are not generic.
	var ids: Array = TechData.RESEARCH_DEFS.filter(func(definition: Dictionary) -> bool: return not definition.has("civilization")).map(func(definition: Dictionary) -> String: return definition.id)
	check(ids.size() == 16 and ids.has("loom") and ids.has("hand_cart") and ids.has("stone_keep") and ids.has("knight"), "sixteen generic techs are defined: " + str(ids))
	for definition: Dictionary in TechData.RESEARCH_DEFS:
		check(float(definition.get("time", 0.0)) > 0.0 and not (definition.cost as Dictionary).is_empty() and ResourceLoader.exists(str(definition.get("icon", ""))), "%s has a time, a cost and an authored icon" % definition.id)
		check(definition.has("effects") != definition.has("tier"), "%s is either a modifier tech or a line upgrade" % definition.id)
		check(TechData.AI_PRIORITY.has(definition.id), "%s is in the AI priority list" % definition.id)
	check(TechData.get_research_definition("knight").cost == {"food": 400, "gold": 200} and TechData.get_research_definition("champion").cost == {"food": 300, "gold": 150}, "revision 2 line-upgrade prices")
	check(TechData.get_research_time("age_2") == 35.0 and TechData.get_research_time("age_3") == 50.0, "age-up takes 35 s then 50 s")


func _check_research_slot() -> void:
	ResourceManager.initialize_player(0, RICH)
	var town_center: BuildingBase = main._player_town_center
	var villager: UnitBase = main._player_units[0][0]
	var villager_hp: float = villager.max_hp
	var actions: Array = town_center.get_context_actions(0).map(func(action: Dictionary) -> String: return action.id).filter(func(id: String) -> bool: return id.begins_with("research:"))
	check(actions == ["research:age_2", "research:loom", "research:wheelbarrow"], "Town Center offers the age-up, Loom and Wheelbarrow (Hand Cart waits for it): " + str(actions))
	check(GameManager.get_research_failure_reason(0, town_center, "wheelbarrow") == "age_required" and GameManager.describe_research_failure(0, "wheelbarrow", "age_required") == "Need Feudal Age", "a later-age tech says which age it needs")
	check(GameManager.get_research_failure_reason(0, town_center, "hand_cart") == "age_required", "Hand Cart is gated twice (age first)")
	# Start: paid now, effect later.
	var queue: ProductionQueue = town_center.get_production_queue()
	check(queue != null and queue.enqueue_unit(UnitData.UnitType.VILLAGER) and queue.is_training, "a villager is training before research starts")
	_tick(2.0)
	var trained_before: float = queue.current_progress
	var bank_before: Dictionary = _bank()
	check(GameManager.try_start_research(0, town_center, "loom"), "Loom starts in the Town Center")
	check(_bank().gold == bank_before.gold - 50 and town_center.research_id == "loom" and town_center.research_duration == 15.0 and town_center.research_paid_cost == {"gold": 50}, "research is paid at start and held in the building slot")
	check(_events == ["started:0:loom:15"], "research_started carries the duration: " + str(_events))
	check(not GameManager.has_research(0, "loom") and GameManager.get_modifier(0, "villager_hp") == 0.0 and villager.max_hp == villager_hp, "nothing is applied before completion")
	var card: Dictionary = town_center.get_context_actions(0)[1]
	check(card.id == "research:loom" and card.progress == 0.0 and card.cancel == true and card.disabled_reason == "", "the running research is a cancellable meter card")
	# One slot per building; the same research cannot run twice.
	check(GameManager.get_research_failure_reason(0, town_center, "age_2") in ["needs_building", "building_busy"] and not GameManager.try_start_research(0, town_center, "wheelbarrow"), "a busy slot refuses a second research")
	check(GameManager.get_research_failure_reason(0, town_center, "loom") == "in_progress", "a running research cannot be started again")
	# Queue blocking.
	_tick(5.0)
	check(is_equal_approx(town_center.research_progress, 5.0) and is_equal_approx(queue.current_progress, trained_before), "research advances while the building's unit queue waits (%.2f, %.2f)" % [town_center.research_progress, queue.current_progress])
	check(is_equal_approx(town_center.get_context_actions(0)[1].progress, 5.0 / 15.0), "card progress follows the slot")
	# Cancel: full refund, queue resumes.
	check(GameManager.cancel_research(0, town_center) and _bank() == bank_before and town_center.research_id == "" and town_center.research_paid_cost.is_empty(), "cancel refunds 100% and frees the slot")
	check(_events == ["started:0:loom:15", "cancelled:0:loom"] and not GameManager.cancel_research(0, town_center), "research_cancelled fires once: " + str(_events))
	_tick(1.0)
	check(queue.current_progress > trained_before, "the unit queue resumes after the cancel")
	queue.cancel_all()
	# Through the context action (what the HUD card and the Research page emit): start, tap again to cancel.
	main._on_building_action_requested(town_center, "research:loom")
	check(town_center.research_id == "loom" and _bank().gold == bank_before.gold - 50, "the card starts the research")
	main._on_building_action_requested(town_center, "research:loom")
	check(town_center.research_id == "" and _bank().gold == bank_before.gold, "tapping the meter card cancels with a full refund")
	check(town_center.perform_context_action(0, "cancel_research") == "Nothing to cancel" and town_center.perform_context_action(1, "research:loom") == "Select your building", "idle cancel and foreign players are refused")
	# Complete.
	_events.clear()
	check(GameManager.try_start_research(0, town_center, "loom"), "Loom starts again")
	_tick(14.5)
	check(not GameManager.has_research(0, "loom"), "not complete a moment early")
	_tick(1.0)
	check(GameManager.has_research(0, "loom") and GameManager.get_modifier(0, "villager_hp") == 10.0 and town_center.research_id == "", "completion lands in the modifier registry and frees the slot")
	check(_events == ["started:0:loom:15", "completed:0:loom"], "research_completed follows the timer: " + str(_events))
	check(villager.max_hp == villager_hp + 10.0, "living villagers gain the Loom HP")
	var recruit: UnitBase = main._spawn_unit(UnitData.UnitType.VILLAGER, 0, villager.global_position + Vector2(24, 0))
	check(recruit != null and recruit.max_hp == villager_hp + 10.0 and recruit.hp == recruit.max_hp, "new villagers spawn with the Loom HP")
	check(_bank().gold == bank_before.gold - 50 and not GameManager.try_start_research(0, town_center, "loom") and GameManager.get_research_failure_reason(0, town_center, "loom") == "already_researched", "a finished research cannot be bought again")
	var done_ids: Array = town_center.get_context_actions(0).filter(func(action: Dictionary) -> bool: return bool(action.get("done", false))).map(func(action: Dictionary) -> String: return action.id)
	check(done_ids == ["research:loom"], "the finished card reports done: " + str(done_ids))
	check(not GameManager.try_start_research(1, town_center, "wheelbarrow") and not GameManager.try_start_research(0, main._player_buildings[1][0], "loom"), "research needs the owner's own building")
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	check(not GameManager.try_start_research(0, town_center, "age_2") and town_center.research_id == "", "an unaffordable research does not start")


func _check_age_up() -> void:
	_events.clear()
	ResourceManager.initialize_player(0, RICH)
	var town_center: BuildingBase = main._player_town_center
	var cost: Dictionary = GameManager.get_age_up_cost(0, 2)
	check(GameManager.get_age_up_failure_reason(0) == "needs_building" and GameManager.describe_age_up_failure(0) == "Need a Barracks or Resource Camp" and not GameManager.try_start_age_up(0), "Feudal needs a Barracks or Resource Camp: " + GameManager.describe_age_up_failure(0))
	var barracks: BuildingBase = main._spawn_building(BuildingData.BuildingType.BARRACKS, 0, main.game_map.map_generator.get_expansion_pocket_centers()[0] + Vector2i(0, 9))
	barracks.start_construction()
	check(GameManager.get_age_up_failure_reason(0) == "needs_building", "a foundation does not count")
	barracks.complete_instantly()
	check(GameManager.get_age_up_failure_reason(0) == "", "a completed Barracks unlocks the Feudal age-up")
	var bank_before: Dictionary = _bank()
	check(GameManager.try_start_age_up(0) and GameManager.get_player_age(0) == 1 and town_center.research_id == "age_2", "the age-up starts in the Town Center and takes time")
	check(_bank().food == bank_before.food - int(cost.food) and _bank().gold == bank_before.gold - int(cost.get("gold", 0)), "the age-up keeps today's cost, paid at start")
	check(_events == ["started:0:age_2:35", "age_started:0:2:35"], "age_advance_started carries target and duration: " + str(_events))
	var state: Dictionary = GameManager.get_age_up_state(0)
	check(state.get("building") == town_center and state.get("target_age") == 2 and state.get("duration") == 35.0, "age-up state is readable for the HUD")
	check(GameManager.get_age_up_failure_reason(0) == "in_progress" and not GameManager.try_start_age_up(0) and not GameManager.try_advance_age(0), "a running age-up cannot be bought twice")
	check(not GameManager.try_start_research(0, town_center, "wheelbarrow"), "the Town Center slot is busy during the age-up")
	_tick(10.0)
	check(GameManager.cancel_age_up(0) and _bank() == bank_before and GameManager.get_player_age(0) == 1 and GameManager.get_age_up_state(0).is_empty(), "cancelling the age-up refunds everything")
	check(_events.slice(2) == ["cancelled:0:age_2", "age_cancelled:0"], "age_advance_cancelled fires: " + str(_events))
	_events.clear()
	main._on_age_up_requested()
	check(town_center.research_id == "age_2", "the HUD age button starts the age-up")
	main.game_map.selection_mgr.deselect_all()
	main._on_age_up_requested()
	check(main.game_map.selection_mgr.selected == [town_center] and town_center.research_id == "age_2", "tapping it again jumps to the Town Center instead of buying twice")
	_tick(34.0)
	check(GameManager.get_player_age(0) == 1, "still Dark Age just before the timer ends")
	_tick(1.5)
	check(GameManager.get_player_age(0) == 2 and town_center.research_id == "" and _events.has("age:0:2"), "the age advances when the timer completes: " + str(_events))
	check(town_center.get_node_or_null("AgeBanner") != null, "the Town Center flies the age banner")
	# Castle: two of Archery Range, Stable, Blacksmith.
	check(GameManager.get_age_up_failure_reason(0) == "needs_building" and GameManager.describe_age_up_failure(0) == "Need 2 of: Archery Range, Stable, Blacksmith", "Castle names its prerequisite: " + GameManager.describe_age_up_failure(0))
	_spawn(BuildingData.BuildingType.BLACKSMITH)
	check(GameManager.get_age_up_failure_reason(0) == "needs_building", "one of the three is not enough")
	_spawn(BuildingData.BuildingType.ARCHERY_RANGE)
	check(GameManager.get_age_up_failure_reason(0) == "", "two of the three unlock the Castle age-up")
	check(GameManager.try_start_age_up(0), "Castle age-up starts")
	_tick(50.5)
	check(GameManager.get_player_age(0) == 3 and _events.has("age_started:0:3:50") and _events.has("age:0:3"), "Castle arrives after 50 s")
	check(GameManager.get_age_up_failure_reason(0) == "max_age" and not GameManager.try_start_age_up(0), "no age-up beyond the final age")


func _check_effects_and_destruction() -> void:
	_events.clear()
	ResourceManager.initialize_player(0, RICH)
	var town_center: BuildingBase = main._player_town_center
	var smith: BuildingBase = _find(BuildingData.BuildingType.BLACKSMITH)
	var villager: UnitBase = main._player_units[0][0]
	var smith_ids: Array = smith.get_context_actions(0).map(func(action: Dictionary) -> String: return action.id)
	check(smith_ids == ["research:forging", "research:scale_mail", "research:fletching", "research:stone_keep"], "Blacksmith shows first tiers; second tiers wait: " + str(smith_ids))
	check(GameManager.get_research_failure_reason(0, smith, "iron_casting") == "requires_research" and GameManager.describe_research_failure(0, "iron_casting", "requires_research") == "Need Forging", "Iron Casting needs Forging")
	# Destroyed mid-research: refund, no effect.
	var bank_before: Dictionary = _bank()
	check(GameManager.try_start_research(0, smith, "forging") and _bank() != bank_before, "Forging starts")
	_tick(12.0)
	smith.take_damage(smith.max_hp + 1)
	check(_bank() == bank_before and not GameManager.has_research(0, "forging") and GameManager.get_modifier(0, "attack") == 0.0, "a destroyed building refunds its research")
	check(_events == ["started:0:forging:30", "cancelled:0:forging"], "destruction cancels the research: " + str(_events))
	smith = _spawn(BuildingData.BuildingType.BLACKSMITH)
	check(GameManager.try_start_research(0, smith, "forging"), "the research is available again in a new Blacksmith")
	_tick(30.5)
	check(GameManager.has_research(0, "forging") and GameManager.get_attack_bonus(0) == 1, "Forging completes: +1 attack")
	smith_ids = smith.get_context_actions(0).map(func(action: Dictionary) -> String: return action.id)
	check(smith_ids[0] == "research:iron_casting", "Iron Casting takes Forging's place: " + str(smith_ids))
	# Parallel research in different buildings.
	var camp: BuildingBase = _spawn(BuildingData.BuildingType.RESOURCE_CAMP)
	check(GameManager.try_start_research(0, smith, "fletching") and GameManager.try_start_research(0, camp, "double_bit_axe") and GameManager.try_start_research(0, town_center, "wheelbarrow"), "three buildings research at once")
	check(not GameManager.try_start_research(0, camp, "gold_panning"), "but each only one at a time")
	var archer: UnitBase = main._spawn_unit(UnitData.UnitType.ARCHER, 0, villager.global_position + Vector2(48, 0))
	var archer_range: float = archer.attack_range
	var tower_range: float = town_center.tower_attack_range
	var carry: int = int(villager.get("carry_capacity"))
	var speed: float = villager.speed
	_tick(35.5)
	check(GameManager.has_research(0, "fletching") and GameManager.has_research(0, "double_bit_axe") and GameManager.has_research(0, "wheelbarrow"), "all three complete on their own timers")
	check(is_equal_approx(archer.attack_range, archer_range + MapData.range_tiles_to_world(1.0)) and is_equal_approx(town_center.tower_attack_range, tower_range + MapData.range_tiles_to_world(1.0)), "Fletching: +1 range for archers and the Town Center")
	check(is_equal_approx(ResearchEffects.gather_multiplier(0, "wood", null), 1.2) and is_equal_approx(ResearchEffects.gather_multiplier(0, "gold", null), 1.0) and is_equal_approx(ResearchEffects.gather_multiplier(1, "wood", null), 1.0), "Double-Bit Axe: +20% wood for its owner only")
	check(int(villager.get("carry_capacity")) == int(round(UnitData.VILLAGER_CARRY_CAPACITY * 1.34)) and int(villager.get("carry_capacity")) > carry and is_equal_approx(villager.speed, speed * 1.1), "Wheelbarrow: more carry and +10%% walking speed (%d, %.1f)" % [int(villager.get("carry_capacity")), villager.speed])
	check(town_center.get_context_actions(0).map(func(action: Dictionary) -> String: return action.id).filter(func(id: String) -> bool: return id.begins_with("research:")) == ["research:loom", "research:hand_cart"], "at the final age the Town Center row is Loom and Hand Cart")
	check(GameManager.try_start_research(0, camp, "horse_collar"), "Horse Collar starts")
	_tick(25.5)
	var farm: BuildingBase = _spawn(BuildingData.BuildingType.FARM)
	check(FarmPlots.capacity_for(0) == int(BuildingData.BUILDINGS[BuildingData.BuildingType.FARM].farm_food) + 75 and FarmPlots.capacity_for(1) == int(BuildingData.BUILDINGS[BuildingData.BuildingType.FARM].farm_food) and is_equal_approx(ResearchEffects.gather_multiplier(0, "food", farm), 1.0), "Horse Collar: +75 food in every Farm sown afterwards (Round 2 E)")
	# Stone Keep on standing and future towers.
	var tower: BuildingBase = _spawn(BuildingData.BuildingType.WATCH_TOWER)
	var tower_hp: int = tower.max_hp
	var tower_damage: int = tower.tower_attack_damage
	check(GameManager.try_start_research(0, smith, "stone_keep"), "Stone Keep starts")
	_tick(40.5)
	check(tower.max_hp == tower_hp + 300 and tower.hp == tower.max_hp and tower.tower_attack_damage == tower_damage + 3, "Stone Keep upgrades standing towers")
	var later: BuildingBase = _spawn(BuildingData.BuildingType.WATCH_TOWER)
	check(later.max_hp == tower_hp + 300 and later.tower_attack_damage == tower_damage + 3 and is_equal_approx(later.tower_attack_range, tower.tower_attack_range), "and towers built afterwards")
	check(GameManager.get_modifier(1, "tower_hp") == 0.0 and GameManager.researched_upgrades[1].is_empty(), "the opponent gains nothing")


func _check_network() -> void:
	# In-process authority regression (the adapter the match server runs).
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
	ResourceManager.initialize_player(1, RICH)
	var enemy_tc: BuildingBase = main._player_buildings[1][0]
	var enemy_tc_id: int = NetworkSession.entity_id(enemy_tc)
	check(server.execute_command(1, {"command": "age"}) == "Need a Barracks or Resource Camp" and GameManager.get_player_age(1) == 1, "the authority explains a blocked age-up")
	_spawn(BuildingData.BuildingType.RESOURCE_CAMP, 1)
	var bank_before: Dictionary = ResourceManager.get_all_resources(1)
	check(server.execute_command(1, {"command": "age"}) == "" and enemy_tc.research_id == "age_2" and GameManager.get_player_age(1) == 1, "the age command starts the timed age-up")
	_tick(4.0)
	var own: Dictionary = server._snapshot_for(1).ext.get("research", {})
	check(own.get("rows") == [[enemy_tc_id, "age_2", 4.0, 35.0]], "the owner's snapshot carries its research slot: " + str(own))
	check((server._snapshot_for(0).ext.get("research", {}) as Dictionary).get("rows") == [], "the opponent's snapshot does not")
	check(server.execute_command(0, {"command": "cancel_research", "target": enemy_tc_id}) == "Select your building" and enemy_tc.research_id == "age_2", "another player cannot cancel it")
	check(server.execute_command(1, {"command": "cancel_research", "target": enemy_tc_id}) == "" and ResourceManager.get_all_resources(1) == bank_before and enemy_tc.research_id == "", "cancel_research refunds on the authority")
	check(server.execute_command(1, {"command": "cancel_research", "target": enemy_tc_id}) == "Nothing to cancel", "nothing to cancel twice")
	check(server.execute_command(1, {"command": "research", "target": enemy_tc_id, "research": "loom"}) == "" and enemy_tc.research_id == "loom" and not GameManager.has_research(1, "loom"), "the research command starts a timed research")
	check(server.execute_command(1, {"command": "building_action", "target": enemy_tc_id, "action": "research:wheelbarrow"}) == "Need Feudal Age", "blocked research answers in card copy")
	check(server.execute_command(1, {"command": "building_action", "target": enemy_tc_id, "action": "research:loom"}) == "" and enemy_tc.research_id == "" and ResourceManager.get_all_resources(1) == bank_before, "building_action on the running card cancels it")
	check(server.execute_command(1, {"command": "building_action", "target": enemy_tc_id, "action": "research:loom"}) == "", "and starts it again")
	_tick(15.5)
	check(GameManager.has_research(1, "loom") and server._snapshot_for(1).modifiers.get("villager_hp") == 10.0, "completion reaches the owner's replicated modifiers")
	# Client side: rows land on the local player's building replicas.
	var town_center: BuildingBase = main._player_town_center
	ResearchEffects._apply_snapshot({"rows": [[NetworkSession.entity_id(town_center), "hand_cart", 9.0, 45.0]]}, main)
	check(town_center.research_id == "hand_cart" and is_equal_approx(town_center.get_research_ratio(), 0.2), "a client replica shows the replicated research meter")
	ResearchEffects._apply_snapshot({"rows": []}, main)
	check(town_center.research_id == "", "and clears it when the row is gone")
	NetworkSession.online = false
	NetworkSession.server_mode = false
	server.queue_free()


func _check_save_round_trip() -> bool:
	_events.clear()
	ResourceManager.initialize_player(0, RICH)
	var barracks: BuildingBase = _find(BuildingData.BuildingType.BARRACKS)
	var warrior: UnitBase = main._spawn_unit(UnitData.UnitType.INFANTRY, 0, main._player_units[0][0].global_position + Vector2(-48, 0))
	var warrior_hp: float = warrior.max_hp
	check(GameManager.try_start_research(0, barracks, "man_at_arms") and GameManager.try_start_research(0, main._player_town_center, "hand_cart"), "two researches are running before the save")
	_tick(10.0)
	var data: Dictionary = STATE.new().capture(main)
	check(STATE.validate(data).is_empty(), "a mid-research capture validates: " + STATE.validate(data))
	var saved_slots: Array = []
	for record: Dictionary in data.actors:
		if record.kind == "building" and str(record.fields.research_id) != "":
			saved_slots.append([record.fields.research_id, record.fields.research_progress, record.fields.research_duration, record.fields.research_paid_cost])
	saved_slots.sort()
	check(saved_slots == [["hand_cart", 10.0, 45.0, {"food": 300, "wood": 200}], ["man_at_arms", 10.0, 30.0, {"food": 100, "gold": 40}]], "building records carry the research slot: " + str(saved_slots))
	check(data.ext.has("research"), "the research extension section is captured")
	var bank_at_save: Dictionary = _bank()
	check(SoloSave.save_current("timed_research"), "native checkpoint accepts a match with research in progress")
	GameManager.cancel_research(0, barracks)
	check(SoloSave.resume_match(), "checkpoint resumes through the real Main lifecycle")
	if not await _wait_main(): return false
	GameManager.set_paused(false)
	barracks = _find(BuildingData.BuildingType.BARRACKS)
	var town_center: BuildingBase = main._player_town_center
	check(barracks != null and barracks.research_id == "man_at_arms" and is_equal_approx(barracks.research_progress, 10.0) and barracks.research_duration == 30.0, "the Barracks resumes its research where it was")
	check(town_center.research_id == "hand_cart" and is_equal_approx(town_center.research_progress, 10.0), "so does the Town Center")
	check(_bank() == bank_at_save and GameManager.get_player_age(0) == 3 and GameManager.has_research(0, "forging") and not GameManager.has_research(0, "man_at_arms"), "bank, age and finished research round-trip")
	check(town_center.get_node_or_null("AgeBanner") != null and (town_center.get_node("AgeBanner") as Sprite2D).visible, "the restored Town Center flies its age banner")
	var restored_warrior: UnitBase = null
	for unit: UnitBase in main._player_units[0]:
		if unit.unit_type == UnitData.UnitType.INFANTRY: restored_warrior = unit
	check(restored_warrior != null and restored_warrior.max_hp == warrior_hp, "the Warrior is restored at base tier")
	# A restored paid slot still refunds on cancel and completes on time.
	var bank_before: Dictionary = _bank()
	check(GameManager.cancel_research(0, town_center) and _bank().food == bank_before.food + 300 and _bank().wood == bank_before.wood + 200, "a restored research refunds its saved receipt")
	_tick(19.5)
	check(not GameManager.has_research(0, "man_at_arms"), "restored progress is not skipped")
	_tick(1.0)
	check(GameManager.has_research(0, "man_at_arms") and UnitData.get_unit_tier(UnitData.UnitType.INFANTRY, 0) == 2, "the restored research completes and raises the tier")
	check(restored_warrior != null and restored_warrior.max_hp == float(UnitData.get_unit_stats(UnitData.UnitType.INFANTRY, 0, 2).hp) and restored_warrior.get_node_or_null("TierBadge") != null, "living Warriors upgrade when it lands")
	# Tiers survive a second save.
	check(SoloSave.save_current("timed_research_tier"), "checkpoint with a researched tier")
	GameManager.player_modifiers = {0: {}, 1: {}}
	check(SoloSave.resume_match(), "second resume")
	if not await _wait_main(): return false
	GameManager.set_paused(false)
	var tiered: UnitBase = null
	for unit: UnitBase in main._player_units[0]:
		if unit.unit_type == UnitData.UnitType.INFANTRY: tiered = unit
	check(UnitData.get_unit_tier(UnitData.UnitType.INFANTRY, 0) == 2 and tiered != null and tiered.max_hp == float(UnitData.get_unit_stats(UnitData.UnitType.INFANTRY, 0, 2).hp), "the tier and upgraded stats round-trip")
	check(tiered != null and tiered.get_node_or_null("TierBadge") != null and (tiered.get_node("TierBadge") as Sprite2D).visible, "the restored unit wears its chevron")
	return true


func _finish() -> void:
	SoloSave.discard_save("timed_research_fixture")
	print(JSON.stringify({"test": "timed_research", "checks": checks, "failures": failures, "scope": "real Main scene; timed research slots, queue blocking, cancel/refund, destruction refund, timed age-up with prerequisites, authority commands and snapshot rows, native save/resume mid-research"}))
	if failures.is_empty():
		print("[PASS] timed_research: %d checks" % checks)
	else:
		for failure: String in failures: push_error("[FAIL] timed_research: " + failure)
	if is_instance_valid(main): main.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
