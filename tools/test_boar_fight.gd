extends "res://tools/wildlife_test_world.gd"
## The boar on the production nodes: it enrages on a gather order, bites
## through the wildlife damage path (no auto-flee), kills a lone villager who
## stands his ground, falls to four, is felled quickly when lured under a Town
## Center, retargets or walks home and resets, and is never an automatic
## gather target while alive.

var _felled: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	build_world()
	GameManager.boar_felled.connect(func(player_id: int, world_position: Vector2) -> void: _felled.append([player_id, world_position]))
	_wildlife_damage_path()
	_lone_villager_loses()
	_four_villagers_win()
	_three_villagers_pay()
	_lure_under_town_center()
	_retarget_and_reset()
	finish("boar_fight")


func _boar(id: int, tile: Vector2i) -> WildlifeNode:
	var node: WildlifeNode = animal(id, WildlifeData.BOAR, tile)
	expect(node.hp == WildlifeData.BOAR_MAX_HP and node.is_fighting() and node.remaining == int(WildlifeData.FOOD[WildlifeData.BOAR]), "a boar starts at full health with its full carcass")
	return node


func _wildlife_damage_path() -> void:
	var bush: ResourceNode = berries(Vector2i(30, 30), 500)
	var bitten: Villager = worker(Vector2i(30, 31))
	var struck: Villager = worker(Vector2i(31, 30))
	building(BuildingData.BuildingType.HOUSE, Vector2i(24, 30))
	expect(bitten.command_gather(bush) and struck.command_gather(bush), "both workers gather berries")
	step(1.0)
	var before: float = bitten.hp
	bitten.take_wildlife_damage(9.0)
	expect(is_equal_approx(before - bitten.hp, 9.0) and not bitten.is_auto_recovering() and bitten.current_state == UnitBase.State.GATHERING, "a boar bite hurts but never starts the economic auto-flee")
	struck.take_damage(9.0)
	expect(struck.is_auto_recovering(), "ordinary damage still makes a working villager flee")
	bitten.take_wildlife_damage(1000.0)
	expect(bitten.current_state == UnitBase.State.DEAD, "the wildlife damage path can kill")
	world.resource_nodes.erase(bush.tile_position)
	bush.free()
	clear_workers()


func _lone_villager_loses() -> void:
	var den := Vector2i(40, 40)
	var boar: WildlifeNode = _boar(1, den)
	var hunter: Villager = worker(den + Vector2i(4, 0))
	var bystander_food: Node2D = world.get_nearest_resource_node("food", hunter.global_position, 0, hunter)
	expect(bystander_food == null and world.get_nearest_reachable_resource_node("food", hunter.global_position, 0, {}, hunter) == null, "automatic food lookups never offer a live boar")
	expect(world.is_resource_target_valid(boar, "", 0), "a direct order on a live boar is still valid")
	expect(boar.mood == WildlifeNode.Mood.CALM, "an untouched boar is calm")
	expect(hunter.command_gather(boar), "a villager accepts the order to hunt a boar")
	step(0.6)
	expect(boar.mood == WildlifeNode.Mood.CALM, "the boar ignores a hunter who is still far away")
	var engaged_at: float = step(20.0, func() -> bool: return boar.mood == WildlifeNode.Mood.ENRAGED)
	expect(boar.mood == WildlifeNode.Mood.ENRAGED and boar.get_target() == hunter, "the boar turns on the villager ordered to gather it")
	var died_after: float = step(40.0, func() -> bool: return hunter.current_state == UnitBase.State.DEAD)
	metrics["lone_villager_dies_after_s"] = snappedf(died_after, 0.1)
	metrics["lone_villager_boar_hp_left"] = boar.hp
	expect(hunter.current_state == UnitBase.State.DEAD, "a lone villager who stays and fights dies")
	expect(boar.is_fighting() and boar.hp > WildlifeData.BOAR_MAX_HP * 0.4 and boar.hp < WildlifeData.BOAR_MAX_HP, "the boar survives him, wounded: %.0f HP" % boar.hp)
	expect(died_after > 6.0 and died_after < 16.0, "the lone fight lasts long enough to react to: %.1f s" % died_after)
	expect(_felled.is_empty() and engaged_at < 20.0, "nothing was felled")
	step(30.0, func() -> bool: return boar.mood == WildlifeNode.Mood.CALM)
	expect(boar.mood == WildlifeNode.Mood.CALM and boar.hp == boar.max_hp and boar.global_position.distance_to(world.tile_to_world(den)) < 4.0, "with nobody left it walks home and recovers fully")
	clear_workers()
	clear_animals()


func _four_villagers_win() -> void:
	var den := Vector2i(44, 44)
	var boar: WildlifeNode = _boar(2, den)
	building(BuildingData.BuildingType.RESOURCE_CAMP, den + Vector2i(-6, 0))
	var party: Array[Villager] = []
	for index: int in 4:
		party.append(worker(den + Vector2i(3, index - 1)))
	for hunter: Villager in party:
		expect(hunter.command_gather(boar), "each of four villagers accepts the hunt")
	var fight: float = step(40.0, func() -> bool: return not boar.is_fighting())
	metrics["four_villagers_fight_s"] = snappedf(fight, 0.1)
	var lowest: float = INF
	var alive: int = 0
	for hunter: Villager in party:
		if hunter.current_state != UnitBase.State.DEAD:
			alive += 1
			lowest = minf(lowest, hunter.hp)
	metrics["four_villagers_lowest_hp"] = lowest
	expect(boar.phase == WildlifeNode.Phase.CARCASS and alive == 4, "four villagers fell the boar without losing anyone: %d alive" % alive)
	expect(lowest < party[0].max_hp and lowest > 0.0, "the bitten villager is hurt: %.0f HP" % lowest)
	expect(_felled.size() == 1 and _felled[0][0] == 0 and (_felled[0][1] as Vector2).distance_to(boar.global_position) < 1.0, "boar_felled reports the killer's player and the place")
	expect(boar.remaining == int(WildlifeData.FOOD[WildlifeData.BOAR]) and boar.is_harvestable_by(1), "the carcass holds all its food and is open to anyone")
	expect(world.get_nearest_resource_node("food", party[0].global_position, 0, party[0]) == boar, "the carcass is now an ordinary food target")
	step(12.0)
	var carried: int = 0
	for hunter: Villager in party:
		carried += hunter.carried_amount
	expect(boar.remaining < int(WildlifeData.FOOD[WildlifeData.BOAR]) and carried + ResourceManager.get_resource(0, "food") > 0, "the party goes straight on to butcher it")
	clear_workers()
	clear_animals()
	_felled.clear()


func _three_villagers_pay() -> void:
	var den := Vector2i(52, 44)
	var boar: WildlifeNode = _boar(3, den)
	var party: Array[Villager] = []
	for index: int in 3:
		party.append(worker(den + Vector2i(3, index - 1)))
	for hunter: Villager in party:
		hunter.command_gather(boar)
	step(40.0, func() -> bool: return not boar.is_fighting())
	var alive: int = 0
	var lowest: float = INF
	for hunter: Villager in party:
		if hunter.current_state != UnitBase.State.DEAD:
			alive += 1
			lowest = minf(lowest, hunter.hp)
	metrics["three_villagers_alive"] = alive
	metrics["three_villagers_lowest_hp"] = lowest
	expect(boar.phase == WildlifeNode.Phase.CARCASS, "three villagers do bring it down")
	expect(alive < 3 or lowest <= party[0].max_hp * 0.4, "but three is one too few: a villager dies or barely survives (%d alive, lowest %.0f HP)" % [alive, lowest])
	clear_workers()
	clear_animals()
	_felled.clear()


func _lure_under_town_center() -> void:
	var home := Vector2i(20, 60)
	var town: BuildingBase = building(BuildingData.BuildingType.TOWN_CENTER, home, 0)
	var den: Vector2i = home + Vector2i(18, 0)
	var boar: WildlifeNode = _boar(4, den)
	var lurer: Villager = worker(den + Vector2i(-2, 0))
	expect(boar.distance_to_building(town) > town.tower_attack_range, "the den is outside Town Center fire")
	expect(lurer.command_gather(boar), "the lurer taps the boar")
	step(20.0, func() -> bool: return boar.mood == WildlifeNode.Mood.ENRAGED)
	expect(boar.mood == WildlifeNode.Mood.ENRAGED, "the boar is enraged")
	var full: float = lurer.max_hp
	var shelter: Vector2 = world.tile_to_world(home + Vector2i(5, 1))
	lurer.command_move(shelter)
	var chase: float = step(60.0, func() -> bool: return not boar.is_fighting() or lurer.current_state == UnitBase.State.DEAD)
	metrics["lure_seconds"] = snappedf(chase, 0.1)
	metrics["lure_hp_lost"] = full - lurer.hp
	expect(boar.phase == WildlifeNode.Phase.CARCASS, "the lured boar is felled under the Town Center")
	expect(lurer.current_state != UnitBase.State.DEAD and lurer.hp >= full * 0.2, "the lurer survives the run: %.0f of %.0f HP" % [lurer.hp, full])
	expect(full - lurer.hp >= WildlifeData.BOAR_BITE_DAMAGE, "the lure costs at least one bite: lost %.0f" % (full - lurer.hp))
	expect(boar.distance_to_building(town) <= town.tower_attack_range, "the carcass lies inside Town Center range (no haul)")
	expect(_felled.size() == 1 and _felled[0][0] == 0, "the Town Center's owner is credited")
	clear_workers()
	clear_animals()
	_felled.clear()


func _retarget_and_reset() -> void:
	var den := Vector2i(60, 60)
	var boar: WildlifeNode = _boar(5, den)
	var first: Villager = worker(den + Vector2i(1, 0))
	var second: Villager = worker(den + Vector2i(2, 2))
	expect(first.command_gather(boar), "the first villager engages")
	step(10.0, func() -> bool: return boar.mood == WildlifeNode.Mood.ENRAGED)
	expect(boar.get_target() == first, "the boar targets the villager who engaged it")
	first.take_wildlife_damage(1000.0)
	step(1.0)
	expect(boar.mood == WildlifeNode.Mood.ENRAGED and boar.get_target() == second, "when its target dies it turns on a villager within four tiles")
	var hurt: float = boar.hp
	second.position = world.tile_to_world(den + Vector2i(30, 0))
	step(0.1)
	expect(boar.mood == WildlifeNode.Mood.RETURNING and boar.get_target() == null, "a target that gets far away is given up")
	step(40.0, func() -> bool: return boar.mood == WildlifeNode.Mood.CALM)
	expect(boar.mood == WildlifeNode.Mood.CALM and boar.hp == boar.max_hp and hurt <= boar.max_hp, "back home it is calm and whole again")
	var hunt_result: String = director._command_hunt(0, {"wid": 5, "ids": []}, [second], null, Vector2.ZERO)
	expect(hunt_result == "" and second.gather_target == boar, "the `hunt` extension command orders a villager onto wildlife by id")
	expect(director._command_hunt(0, {"wid": 999, "ids": []}, [second], null, Vector2.ZERO) != "", "an unknown wildlife id is refused")
	expect(WildlifeDirector._valid_hunt({"wid": 5, "ids": [1]}) and not WildlifeDirector._valid_hunt({"ids": [1]}), "the hunt packet validator requires a wildlife id")
	clear_workers()
	clear_animals()
