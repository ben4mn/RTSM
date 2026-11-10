extends "res://tools/garrison_fixture.gd"
## Town bell on a real seeded match: ring, shelter, extra arrows, enemy
## targeting and snapshots, all clear, capacity, and a destroyed Town Center.

var _bell_events: Array = []
var _arrows_launched: int = 0


func run_cases() -> void:
	case_name = "town_bell"
	GameManager.town_bell_changed.connect(func(player_id: int, town_center: Node2D, active: bool) -> void:
		_bell_events.append([player_id, town_center, active])
	)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is BuildingBase.DefensiveArrow:
			_arrows_launched += 1
	)
	await step(1.0)
	var workers: Array[Villager] = own_villagers()
	expect(workers.size() >= 3, "match starts with villagers")
	var gathering_before: int = 0
	for worker: Villager in workers:
		if worker.has_active_gather_order():
			gathering_before += 1
	expect(gathering_before >= 2, "starting villagers have gather jobs to return to")

	# Context action is offered through the Phase-0 seam.
	var action_ids: Array = tc.get_context_actions(0).map(func(action: Dictionary) -> String: return str(action.id))
	expect(Garrison.ACTION_BELL in action_ids and not Garrison.ACTION_RELEASE in action_ids, "TC offers the bell and no Ungarrison while empty")
	expect(tc.get_context_actions(1).is_empty(), "the rival is offered nothing on this TC")

	# Raiders stand inside the TC's arrow range; frozen so the case measures the
	# bell, not a fight.
	var raiders: Array[UnitBase] = []
	for index: int in 3:
		var raider: UnitBase = spawn(UnitData.UnitType.CAVALRY, 1, Vector2i(-2, -2), index)
		raider.process_mode = Node.PROCESS_MODE_DISABLED
		raider.max_hp = 100000.0
		raider.hp = 100000.0
		raiders.append(raider)
	await step(0.5)
	for raider: UnitBase in raiders:
		expect(tc.global_position.distance_to(raider.global_position) <= tc.tower_attack_range and map.is_entity_visible_to_player(raider, 0), "fixture raider stands inside the Town Center arrow range, in sight")
	# The match server knows every unit before it can shelter.
	var adapter: Node = load("res://scripts/network/network_match.gd").new()
	add_child(adapter)
	adapter.setup(main)
	adapter._register_server_entities()

	expect(tc.perform_context_action(0, Garrison.ACTION_BELL) == "", "bell action accepted")
	expect(tc.bell_active, "bell is ringing")
	expect(_bell_events.size() == 1 and _bell_events[0] == [0, tc, true], "town_bell_changed(owner, tc, true) emitted once")
	var all_in: bool = await step_until(func() -> bool: return Garrison.count(tc) == workers.size(), 40.0)
	expect(all_in, "every nearby villager reaches the Town Center and goes inside (%d/%d)" % [Garrison.count(tc), workers.size()])
	for worker: Villager in workers:
		expect(worker.current_state == UnitBase.State.GARRISONED and not worker.is_inside_tree(), "garrisoned villager is off the field")
		expect(not worker.is_in_group("units") or not get_tree().get_nodes_in_group("units").has(worker), "garrisoned villager left the units group")
		expect(not raiders[0]._is_valid_target(worker), "raider cannot target a garrisoned villager")
		var hp_before: float = worker.hp
		worker.take_damage(5.0)
		expect(is_equal_approx(worker.hp, hp_before), "garrisoned villager takes no damage")
	expect(not map.get_units_near(Garrison.footprint_center(tc), 2000.0).any(func(unit: UnitBase) -> bool: return unit.current_state == UnitBase.State.GARRISONED), "spatial index holds no garrisoned villager")
	expect(Garrison.bonus_arrows(tc) == workers.size(), "one bonus arrow per garrisoned villager")
	var garrison_cards: Array = tc.get_context_actions(0).filter(func(action: Dictionary) -> bool: return str(action.id).begins_with("garrison:"))
	action_ids = garrison_cards.map(func(action: Dictionary) -> String: return str(action.id))
	expect(action_ids == [Garrison.ACTION_BELL] and str(garrison_cards[0].label) == "All Clear", "while ringing the one card is the all-clear")

	# One volley = the TC's own arrow plus one per villager.
	tc._tower_attack_cooldown = 0.0
	_arrows_launched = 0
	await step(1.2)
	expect(_arrows_launched == 1 + workers.size(), "volley launches 1 + %d arrows (got %d)" % [workers.size(), _arrows_launched])

	# Online authority: owner keeps the hidden actors, the rival gets nothing.
	await _check_snapshots(adapter, workers)

	# While raiders stay, the bell stays.
	await step(13.0)
	expect(tc.bell_active and Garrison.count(tc) == workers.size(), "bell holds while an armed enemy is near")

	# All clear 12 s after the last raider is gone; villagers resume their jobs.
	for raider: UnitBase in raiders:
		kill(raider)
	await step(6.0)
	expect(tc.bell_active, "no all-clear before twelve quiet seconds")
	var cleared: bool = await step_until(func() -> bool: return not tc.bell_active, 9.0)
	expect(cleared and Garrison.count(tc) == 0, "bell stands down by itself after twelve quiet seconds")
	expect(_bell_events.size() == 2 and _bell_events[1] == [0, tc, false], "town_bell_changed(owner, tc, false) emitted")
	await step(1.0)
	var resumed: int = 0
	for worker: Villager in workers:
		expect(worker.is_inside_tree() and worker.current_state != UnitBase.State.GARRISONED and worker.visible, "released villager is back on the field")
		if worker.has_active_gather_order() or worker.current_state == UnitBase.State.GATHERING:
			resumed += 1
	expect(resumed >= gathering_before, "villagers resume their gather jobs (%d of %d)" % [resumed, gathering_before])

	# Manual toggle releases at once, including villagers still on the way.
	expect(Garrison.ring(tc), "ring again")
	await step(0.3)
	expect(Garrison.toggle(tc) and not tc.bell_active, "second tap releases")
	await step(0.5)
	for worker: Villager in workers:
		expect(worker.is_inside_tree() and worker._garrison_target == null and not worker.is_auto_recovering(), "toggle-off returns walking villagers to work")

	# Capacity: seventeen villagers, fifteen beds.
	for index: int in 17 - workers.size():
		spawn(UnitData.UnitType.VILLAGER, 0, Vector2i(5, 5), index)
	await step(0.5)
	Garrison.ring(tc)
	await step_until(func() -> bool: return Garrison.count(tc) >= 15, 40.0)
	await step(3.0)
	expect(Garrison.count(tc) == 15, "Town Center holds exactly fifteen (got %d)" % Garrison.count(tc))
	expect(Garrison.bonus_arrows(tc) == Garrison.MAX_BONUS_ARROWS, "bonus arrows cap at eight")
	var outside: int = 0
	for worker: Villager in own_villagers():
		if worker.is_inside_tree():
			outside += 1
	expect(outside == 2, "the two villagers without a bed stay outside (got %d)" % outside)

	# A destroyed Town Center ejects everyone alive.
	var inside: Array[UnitBase] = Garrison.garrisoned_units(tc)
	tc.take_damage(tc.max_hp + 1)
	for unit: UnitBase in inside:
		expect(is_instance_valid(unit) and unit.is_inside_tree() and unit.current_state != UnitBase.State.GARRISONED and unit.current_state != UnitBase.State.DEAD and unit.hp > 0.0, "unit ejected alive when the Town Center falls")
		expect(unit.global_position.distance_to(Garrison.footprint_center(tc)) < 400.0, "ejected unit stands beside the footprint")
	expect(tc.garrisoned_ids.is_empty() and not tc.bell_active, "fallen Town Center holds nobody")


func _check_snapshots(adapter: Node, workers: Array[Villager]) -> void:
	adapter._register_server_entities()
	var tc_id: int = NetworkSession.entity_id(tc)
	var worker_ids: Array[int] = []
	for worker: Villager in workers:
		worker_ids.append(NetworkSession.entity_id(worker))
	# Past the short grace in which a watching rival still holds the replica.
	await step(Garrison.ENEMY_REVEAL_GRACE + 0.2)
	var own: Dictionary = adapter._snapshot_for(0)
	var rival: Dictionary = adapter._snapshot_for(1)
	var own_states: Dictionary = {}
	for actor: Dictionary in own.actors:
		own_states[int(actor.id)] = int(actor.get("state", -1))
	var rival_ids: Dictionary = {}
	for actor: Dictionary in rival.actors:
		rival_ids[int(actor.id)] = true
	expect(rival_ids.has(tc_id), "rival can see the Town Center itself (raiders stand beside it)")
	for id: int in worker_ids:
		expect(id > 0 and own_states.get(id, -1) == UnitBase.State.GARRISONED, "owner snapshot keeps the garrisoned villager as GARRISONED")
		expect(not rival_ids.has(id), "rival snapshot never contains a garrisoned villager")
	var own_rows: Array = own.ext.get("garrison", [])
	expect(own_rows.size() == 1 and own_rows[0] == [tc_id, workers.size(), 1, 0], "owner gets [id, count, bell, repair] for the Town Center")
	expect((rival.ext.get("garrison", []) as Array).is_empty(), "rival gets no garrison row")
	expect(adapter.execute_command(1, {"command": "bell", "target": tc_id}) == "Select your Town Center" and tc.bell_active, "rival cannot ring or silence this bell")
	expect(adapter.execute_command(1, {"command": "ungarrison", "target": tc_id}) != "" and Garrison.count(tc) == workers.size(), "rival cannot empty this Town Center")
	expect(adapter.execute_command(0, {"command": "bell"}) == "Invalid order", "bell without a target is rejected")
	expect(adapter.execute_command(0, {"command": "garrison", "ids": worker_ids, "target": tc_id}) != "", "garrisoned units are not commandable ids")
	expect(Garrison.count(tc) == workers.size(), "rejected orders change nothing")
	main.ai_controller.process_mode = Node.PROCESS_MODE_DISABLED
	adapter.queue_free()
