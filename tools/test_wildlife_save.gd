extends Node
## Wildlife through the real Main lifecycle and the solo checkpoint: the
## opening spawns the planned animals and puts every starting villager on a
## home sheep, and a save taken mid-herd and mid-boar-fight restores owners,
## stock, carcasses, walking sheep, the angry boar and the villagers' orders.
const STATE = preload("res://scripts/main/solo_match_state.gd")
const PER_PLAYER: int = WildlifeData.HOME_SHEEP + WildlifeData.STRAY_PAIRS * 2 + WildlifeData.DEER_COUNT + WildlifeData.BOAR_COUNT

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
			# One more frame lets the deferred opening assignment run.
			await get_tree().process_frame
			main.process_mode = Node.PROCESS_MODE_DISABLED
			return true
	check(false, "Main initialized within bounded frames")
	return false


func _finish() -> void:
	print(JSON.stringify({"test": "wildlife_save", "checks": checks, "failures": failures}))
	SoloSave.discard_save("wildlife_save_fixture")
	if is_instance_valid(main):
		main.queue_free()
		await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _by_group(director: WildlifeDirector, kind: String, owner: int, alive_only: bool = true) -> Array[WildlifeNode]:
	var result: Array[WildlifeNode] = []
	for node: WildlifeNode in director.get_nodes(kind):
		if node.owner_id == owner and (not alive_only or node.phase == WildlifeNode.Phase.ALIVE):
			result.append(node)
	return result


func _run() -> void:
	get_tree().current_scene = null
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	SoloSave.discard_save("wildlife_save_fixture")
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = MapData.MapArchetype.RIVER_CROSSINGS
	GameManager.guided_opening_enabled = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	if not await _wait_main():
		await _finish()
		return
	var map: Node2D = main.game_map
	var director: WildlifeDirector = WildlifeDirector.of(main)
	check(director != null and map.get_wildlife_director() == director, "Main installs the wildlife director on the map")
	if director == null:
		await _finish()
		return
	check(director.nodes.size() == PER_PLAYER * 2, "the planned animals are spawned: %d" % director.nodes.size())
	check(map.get_wildlife_for_player(0).size() == WildlifeData.HOME_SHEEP and map.get_wildlife_for_player(1).size() == WildlifeData.HOME_SHEEP, "each player starts with a home flock")
	check(map.get_wildlife_nodes(WildlifeData.DEER).size() == WildlifeData.DEER_COUNT * 2 and map.get_wildlife_nodes(WildlifeData.BOAR).size() == WildlifeData.BOAR_COUNT * 2, "deer and boar are present for both players")
	for owner: int in 2:
		var targets: Dictionary = {}
		var villagers: int = 0
		for unit: Node in main._player_units[owner]:
			if unit is Villager:
				villagers += 1
				var target: Node2D = (unit as Villager).gather_target
				check(target is WildlifeNode and (target as WildlifeNode).owner_id == owner and (unit as Villager).get_economy_task() == "food", "player %d's starting villager works a home sheep" % owner)
				targets[target] = true
		check(villagers == UnitData.get_starting_villager_count() and targets.size() == 1, "player %d's villagers all start on the same sheep" % owner)
	var town: BuildingBase = main._player_town_center
	var toggle: Array = town.get_context_actions(0).filter(func(action: Dictionary) -> bool: return action.id == WildlifeDirector.ACTION_WALK_HOME)
	check(toggle.size() == 1 and director.is_walk_home_enabled(0), "the Town Center offers the Sheep walk home assist, on by default")
	check(town.perform_context_action(0, WildlifeDirector.ACTION_WALK_HOME) == "" and not director.is_walk_home_enabled(0) and director.is_walk_home_enabled(1), "the context action toggles it for that player only")
	check(town.perform_context_action(0, WildlifeDirector.ACTION_WALK_HOME) == "" and director.is_walk_home_enabled(0), "and toggles it back")
	director.walk_home[1] = false

	# Mid-herd: one stray claimed and walking home, one hand-herded elsewhere.
	var strays: Array[WildlifeNode] = _by_group(director, WildlifeData.SHEEP, -1)
	check(strays.size() == WildlifeData.STRAY_PAIRS * 4, "all strays start unclaimed: %d" % strays.size())
	strays.sort_custom(func(a: WildlifeNode, b: WildlifeNode) -> bool: return a.global_position.distance_to(town.global_position) < b.global_position.distance_to(town.global_position))
	var walker: WildlifeNode = strays[0]
	var parked: WildlifeNode = strays[2]
	# L1: a claimed stray follows the Scout that found it.
	var herder: UnitBase = null
	for unit: Node in main._player_units[0]:
		if unit is UnitBase and (unit as UnitBase).unit_type == UnitData.UnitType.SCOUT:
			herder = unit
	check(herder != null, "player 0 has a Scout to herd with")
	if herder != null:
		herder.global_position = walker.global_position + Vector2(64.0, 0.0)
	director._claim(walker, 0, herder)
	director.think()
	check(walker.owner_id == 0 and walker.has_goal and walker.get_leader() == herder, "a claimed stray follows the Scout")
	for tick: int in 60:
		walker._process(1.0 / 30.0)
	director._claim(parked, 0)
	var meadow: Vector2 = map.tile_to_world(map.world_to_tile(parked.global_position) + Vector2i(0, -2))
	check(director.order_herd(0, [parked], meadow) or director.order_herd(0, [parked], parked.global_position), "the second stray is herded by hand")
	# An opened home carcass, partly spoiled.
	var carcass: WildlifeNode = _by_group(director, WildlifeData.SHEEP, 1)[0]
	carcass.harvest(13)
	carcass._decay = 0.5
	# Mid-fight: a villager engaged with a wounded, enraged boar.
	var boars: Array[WildlifeNode] = director.get_nodes(WildlifeData.BOAR)
	boars.sort_custom(func(a: WildlifeNode, b: WildlifeNode) -> bool: return a.global_position.distance_to(town.global_position) < b.global_position.distance_to(town.global_position))
	var boar: WildlifeNode = boars[0]
	var hunter: Villager = null
	for unit: Node in main._player_units[0]:
		if unit is Villager:
			hunter = unit
			break
	hunter.global_position = boar.global_position + Vector2(24.0, 0.0)
	main._update_fog_of_war()
	check(hunter.command_gather(boar), "a villager is ordered onto the boar")
	boar.enrage(hunter)
	boar._take_hit(37.0)
	boar._bite_cooldown = 0.9
	check(boar.mood == WildlifeNode.Mood.ENRAGED and boar.get_target() == hunter and is_equal_approx(boar.hp, WildlifeData.BOAR_MAX_HP - 37.0), "the boar is enraged and wounded")
	var expected: Dictionary = {}
	for node: WildlifeNode in director.nodes:
		expected[node.wildlife_id] = {"kind": node.kind, "position": node.global_position, "owner": node.owner_id, "phase": node.phase, "mood": node.mood, "remaining": node.remaining, "hp": node.hp, "has_goal": node.has_goal, "goal": node.move_goal, "manual": node.manual_stay}

	var data: Dictionary = STATE.new().capture(main)
	check(STATE.validate(data).is_empty(), "a capture with wildlife validates: " + STATE.validate(data))
	check(data.ext.get("wildlife", {}).get("rows", []).size() == PER_PLAYER * 2 and data.generator == MapData.GENERATOR_VERSION, "the wildlife section holds every animal")
	check(SoloSave.save_current("wildlife_save"), "the checkpoint is written")
	director.walk_home[1] = true
	walker.global_position += Vector2(500.0, 0.0)
	# The old scene and its animals are freed by the resume; keep plain ids.
	var boar_id: int = boar.wildlife_id
	var walker_id: int = walker.wildlife_id
	var carcass_id: int = carcass.wildlife_id
	var carcass_stock: int = carcass.total_amount - 13
	check(SoloSave.resume_match(), "the checkpoint resumes through the real Main lifecycle")
	if not await _wait_main():
		await _finish()
		return

	map = main.game_map
	director = WildlifeDirector.of(main)
	check(director != null and director.nodes.size() == expected.size(), "every animal is restored exactly once: %d" % (director.nodes.size() if director != null else -1))
	if director == null:
		await _finish()
		return
	var mismatches: Array[String] = []
	for id: Variant in expected:
		var node: WildlifeNode = director.by_id.get(id) as WildlifeNode
		var want: Dictionary = expected[id]
		if node == null:
			mismatches.append("missing %d" % int(id))
			continue
		if node.kind != want.kind or node.owner_id != want.owner or node.phase != want.phase or node.mood != want.mood or node.remaining != want.remaining or not is_equal_approx(node.hp, want.hp) or node.global_position.distance_to(want.position) > 0.01 or node.has_goal != want.has_goal or node.manual_stay != want.manual or (want.has_goal and node.move_goal.distance_to(want.goal) > 0.01):
			mismatches.append("%s %d" % [node.kind, int(id)])
	check(mismatches.is_empty(), "kind, place, owner, phase, mood, stock, health and walking orders round-trip: " + str(mismatches))
	check(not director.is_walk_home_enabled(1) and director.is_walk_home_enabled(0), "the per-player assist setting round-trips")
	var restored_boar: WildlifeNode = director.by_id.get(boar_id) as WildlifeNode
	var restored_hunter: Villager = null
	for unit: Node in main._player_units[0]:
		if unit is Villager and (unit as Villager).gather_target == restored_boar:
			restored_hunter = unit
	check(restored_boar != null and restored_hunter != null and restored_boar.get_target() == restored_hunter and is_equal_approx(restored_boar._bite_cooldown, 0.9), "the boar still has its villager, and the villager its boar")
	var restored_walker: WildlifeNode = director.by_id.get(walker_id) as WildlifeNode
	var restored_leader: UnitBase = restored_walker.get_leader() if restored_walker != null else null
	check(restored_leader != null and restored_leader.unit_type == UnitData.UnitType.SCOUT and restored_leader.player_owner == 0 and restored_walker.pasture_owner == -1, "the claimed stray still follows the Scout after the restore")
	var restored_carcass: WildlifeNode = director.by_id.get(carcass_id) as WildlifeNode
	check(restored_carcass != null and restored_carcass.phase == WildlifeNode.Phase.CARCASS and restored_carcass.remaining == carcass_stock and is_equal_approx(restored_carcass._decay, 0.5), "the opened carcass keeps its stock and spoilage")
	var sheep_workers: int = 0
	for unit: Node in main._player_units[1]:
		if unit is Villager and (unit as Villager).gather_target is WildlifeNode and ((unit as Villager).gather_target as WildlifeNode).owner_id == 1:
			sheep_workers += 1
	check(sheep_workers == UnitData.get_starting_villager_count(), "the rival's villagers keep their sheep after the restore: %d" % sheep_workers)
	check(map.is_resource_target_valid(restored_carcass, "food", 1) and not map.is_resource_target_valid(restored_carcass, "food", 0), "restored animals are registered harvestables with their ownership rule")
	# The restored fight simply continues.
	GameManager.set_paused(false)
	var hp_before: float = restored_hunter.hp if restored_hunter != null else 0.0
	if restored_boar != null and restored_hunter != null:
		for tick: int in 120:
			restored_boar._process(1.0 / 30.0)
		check(restored_hunter.hp < hp_before, "the restored boar bites its restored target")
		var before: Vector2 = restored_walker.global_position
		# The follower stands beside its Scout; ride on and it walks after it.
		if restored_leader != null:
			restored_leader.global_position += Vector2(160.0, 0.0)
		director.think()
		for tick: int in 30:
			restored_walker._process(1.0 / 30.0)
		check(restored_walker.global_position != before, "the restored sheep keeps walking")
	await _finish()
